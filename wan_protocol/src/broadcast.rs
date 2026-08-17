//! 广播烧录协议。
//!
//! - Android：manufacturerData = `{ manufacturerId: 0xFFFD, data: 27B }`
//! - iOS：19B payload → frmcnt 循环 → CRC32 → xorshift32 混淆 → 13 个 serviceUuids
//!
//! 对应：
//! - `appservice.app.js:843`（ble-burn.js `buildBroadcastData`）
//! - `chunk_69.appservice.js:46`（operations 页 `doStartAdvertising` 内联 iOS 算法）

use crate::crc32::crc32_ieee;
use crate::hexutil::hex_to_bytes;

/// xorshift32 种子常数。`Math.imul(frmcnt, 0x9E3779B1) + 2779096485`。
const XOR_K1: u32 = 2654435761; // 0x9E3779B1
const XOR_K2: u32 = 2779096485;

/// Android 广播数据：23B payload + 4B CRC32 LE = 27B。
///
/// 对应 JS `buildBroadcastData(seq, mac, x0, y0, show, region, o=0xFFFF, u=0xFFFF)`。
/// `o` / `u` 固定 0xFFFF（JS 默认值，operations 页调用未传）。
///
/// 布局：
/// - `[0..4]` seq LE
/// - `[4]` 0xF0  `[5]` 0x17 (23)  `[6]` 0x79
/// - `[7..13]` MAC LE (6B)
/// - `[13]` region
/// - `[14..16]` x0 LE  `[16..18]` y0 LE
/// - `[18..20]` 0xFFFF LE  `[20..22]` 0xFFFF LE  `[22]` show
/// - `[23..27]` CRC32(前 23 字节) LE
pub fn build_android_broadcast(
    seq: u32,
    mac_hex: &str,
    region: u8,
    x0: u16,
    y0: u16,
    show: u8,
) -> [u8; 27] {
    let mac = mac_le_bytes(mac_hex);
    let mut out = [0u8; 27];
    out[0..4].copy_from_slice(&seq.to_le_bytes());
    out[4] = 0xF0;
    out[5] = 0x17;
    out[6] = 0x79;
    out[7..13].copy_from_slice(&mac);
    out[13] = region;
    out[14..16].copy_from_slice(&x0.to_le_bytes());
    out[16..18].copy_from_slice(&y0.to_le_bytes());
    out[18..20].copy_from_slice(&0xFFFFu16.to_le_bytes());
    out[20..22].copy_from_slice(&0xFFFFu16.to_le_bytes());
    out[22] = show;
    let crc = crc32_ieee(&out[0..23]);
    out[23..27].copy_from_slice(&crc.to_le_bytes());
    out
}

/// iOS 广播：返回 `(frmcnt, 26B 数据)`。
///
/// 对应 operations 页 `doStartAdvertising` 内联函数 `o(t,e,r,n,a,o,i,s)`。
/// 26B = `[0xF7, 0xFF, frmcnt] + 19B payload + 4B CRC32 LE`，再对 `[4..26]` 做
/// xorshift32 混淆（跳过前 4 字节 `F7 FF frmcnt F0`）。
///
/// frmcnt 从 `counter` 起递增，直到 13 个 2 字节 UUID 全不重复。
/// `ponytail:` 最多 256 轮后仍重复则返回最后一次（XOR 混淆下实际不会发生）。
pub fn build_ios_broadcast(
    counter: u8,
    mac_hex: &str,
    region: u8,
    x0: u16,
    y0: u16,
    show: u8,
) -> (u8, [u8; 26]) {
    let mac = mac_le_bytes(mac_hex);
    let mut payload = [0u8; 19];
    payload[0] = 0xF0;
    payload[1] = 0x11;
    payload[2] = 0x79;
    payload[3..9].copy_from_slice(&mac);
    payload[9] = region;
    payload[10..12].copy_from_slice(&x0.to_le_bytes());
    payload[12..14].copy_from_slice(&y0.to_le_bytes());
    payload[14..16].copy_from_slice(&0xFFFFu16.to_le_bytes());
    payload[16..18].copy_from_slice(&0xFFFFu16.to_le_bytes());
    payload[18] = show;

    let mut h = counter;
    for _ in 0..=255u16 {
        let v = build_ios_frame(h, &payload);
        if uuids_unique(&v) {
            return (h, v);
        }
        h = h.wrapping_add(1);
    }
    // ponytail: 理论兜底，XOR 混淆下 256 轮内必能找到解
    (h, build_ios_frame(h, &payload))
}

/// 构造单帧：头 3B + payload 19B + CRC32 LE 4B = 26B，再对 `[4..26]` 做 xorshift32 混淆。
fn build_ios_frame(frmcnt: u8, payload: &[u8; 19]) -> [u8; 26] {
    let mut v = [0u8; 26];
    v[0] = 0xF7;
    v[1] = 0xFF;
    v[2] = frmcnt;
    v[3..22].copy_from_slice(payload);
    // CRC32 覆盖 v[2..22] = frmcnt + payload (20 字节)
    let crc = crc32_ieee(&v[2..22]);
    v[22..26].copy_from_slice(&crc.to_le_bytes());

    // xorshift32 混淆 v[4..26]（跳过 F7 FF frmcnt F0）
    let mut s = (frmcnt as u32).wrapping_mul(XOR_K1).wrapping_add(XOR_K2);
    for x in 4..26 {
        s = xorshift32_step(s);
        v[x] ^= (s >> 24) as u8;
    }
    v
}

/// 把 iOS 26 字节数据转成 13 个 4 字符 hex UUID（大写）。
///
/// 对应 JS serviceUuids 构造：每 2 字节 `[lo, hi]` → `"{hi:02X}{lo:02X}"`，
/// 末尾奇字节补 0xFF。
pub fn ios_data_to_service_uuids(data: &[u8]) -> Vec<String> {
    let mut out = Vec::with_capacity((data.len() + 1) / 2);
    let mut c = 0;
    while c < data.len() {
        let lo = data[c];
        let hi = if c + 1 < data.len() { data[c + 1] } else { 0xFF };
        out.push(format!("{:02X}{:02X}", hi, lo));
        c += 2;
    }
    out
}

/// xorshift32 单步：`S ^= S<<13; S ^= S>>17; S ^= S<<5`。
fn xorshift32_step(mut s: u32) -> u32 {
    s ^= s << 13;
    s ^= s >> 17;
    s ^= s << 5;
    s
}

/// MAC hex → 6 字节小端（反转）。
/// Android `U.unshift(byte)` 与 iOS `for(d=5..0)` 都得到 `[byte5..byte0]`。
fn mac_le_bytes(mac_hex: &str) -> [u8; 6] {
    let clean: String = mac_hex.chars().filter(|c| *c != ':' && *c != '-').collect();
    let bytes = hex_to_bytes(&clean);
    let mut out = [0u8; 6];
    let n = bytes.len().min(6);
    for i in 0..n {
        out[i] = bytes[n - 1 - i];
    }
    out
}

/// 26 字节按 2 字节分组是否全不重复。
/// `ponytail:` 13 个元素，O(n²) 比 HashSet 更快更简单。
fn uuids_unique(v: &[u8; 26]) -> bool {
    let n = v.len() / 2;
    for i in 0..n {
        for j in (i + 1)..n {
            if v[2 * i] == v[2 * j] && v[2 * i + 1] == v[2 * j + 1] {
                return false;
            }
        }
    }
    true
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn android_broadcast_layout() {
        let data = build_android_broadcast(1, "aabbccddeeff", 0xA1, 0x0102, 0x0304, 0x05);
        assert_eq!(data.len(), 27);
        assert_eq!(&data[0..4], &[0x01, 0x00, 0x00, 0x00]); // seq LE
        assert_eq!(&data[4..7], &[0xF0, 0x17, 0x79]); // 头
        assert_eq!(&data[7..13], &[0xff, 0xee, 0xdd, 0xcc, 0xbb, 0xaa]); // MAC LE
        assert_eq!(data[13], 0xA1); // region
        assert_eq!(&data[14..16], &[0x02, 0x01]); // x0 LE
        assert_eq!(&data[16..18], &[0x04, 0x03]); // y0 LE
        assert_eq!(&data[18..22], &[0xFF, 0xFF, 0xFF, 0xFF]); // 0xFFFF × 2
        assert_eq!(data[22], 0x05); // show
    }

    #[test]
    fn android_broadcast_crc_le_matches() {
        let data = build_android_broadcast(0, "000000000000", 0, 0, 0, 0);
        let crc = crc32_ieee(&data[0..23]);
        assert_eq!(&data[23..27], &crc.to_le_bytes());
    }

    #[test]
    fn ios_frame_header_not_xored() {
        let (_, v) = build_ios_broadcast(0x42, "aabbccddeeff", 0xA1, 0x0102, 0x0304, 0x05);
        assert_eq!(v.len(), 26);
        assert_eq!(v[0], 0xF7); // 不被 XOR
        assert_eq!(v[1], 0xFF); // 不被 XOR
        // v[3] = payload[0] = 0xF0（XOR 从 x=4 起，v[3] 不变）
        assert_eq!(v[3], 0xF0);
    }

    #[test]
    fn ios_service_uuids_format() {
        let data = [
            0xF7, 0xFF, 0x42, 0xF0, 0x11, 0x79, 0xAA, 0xBB, 0xCC, 0xDD, 0xEE, 0xFF, 0x00, 0x11,
            0x22, 0x33, 0x44, 0x55, 0x66, 0x77, 0x88, 0x99, 0xAA, 0xBB, 0xCC, 0xDD,
        ];
        let uuids = ios_data_to_service_uuids(&data);
        assert_eq!(uuids.len(), 13);
        assert_eq!(uuids[0], "FFF7"); // [0xF7, 0xFF] → hi=FF lo=F7
        assert_eq!(uuids[1], "F042"); // [0x42, 0xF0]
        assert_eq!(uuids[12], "DDCC"); // [0xCC, 0xDD]
    }

    #[test]
    fn ios_service_uuids_odd_byte_pads_ff() {
        let uuids = ios_data_to_service_uuids(&[0xAB, 0xCD, 0xEF]);
        assert_eq!(uuids, vec!["CDAB", "FFEF"]);
    }

    #[test]
    fn mac_le_bytes_reverses_byte_order() {
        assert_eq!(mac_le_bytes("aabbccddeeff"), [0xff, 0xee, 0xdd, 0xcc, 0xbb, 0xaa]);
        assert_eq!(mac_le_bytes("AA:BB:CC:DD:EE:FF"), [0xff, 0xee, 0xdd, 0xcc, 0xbb, 0xaa]);
        assert_eq!(mac_le_bytes("010203040506"), [0x06, 0x05, 0x04, 0x03, 0x02, 0x01]);
    }

    #[test]
    fn xorshift_step_changes_state() {
        let s0 = (0x42u32).wrapping_mul(XOR_K1).wrapping_add(XOR_K2);
        let s1 = xorshift32_step(s0);
        assert_ne!(s0, s1);
        assert_eq!(xorshift32_step(s0), s1); // 可重现
    }

    #[test]
    fn uuids_unique_detects_duplicates() {
        let mut v = [0u8; 26];
        for i in 0..13u8 {
            v[2 * i as usize] = i;
            v[2 * i as usize + 1] = i + 1;
        }
        assert!(uuids_unique(&v));
        v[0] = v[2];
        v[1] = v[3];
        assert!(!uuids_unique(&v));
    }

    #[test]
    fn ios_broadcast_returns_unique_uuids() {
        let (frmcnt, v) = build_ios_broadcast(0, "aabbccddeeff", 0xA1, 0x100, 0x200, 0x05);
        assert_eq!(v[2], frmcnt);
        assert!(uuids_unique(&v));
        let uuids = ios_data_to_service_uuids(&v);
        assert_eq!(uuids.len(), 13);
        // UUID 集合去重后仍为 13 个
        let unique: std::collections::HashSet<_> = uuids.iter().collect();
        assert_eq!(unique.len(), 13);
    }
}
