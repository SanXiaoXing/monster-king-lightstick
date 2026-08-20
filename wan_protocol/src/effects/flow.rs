//! 自定义流光效果引擎（本项目自定义，非官方协议）。
//!
//! # 定位
//!
//! 官方小程序（`chunk_2.appservice.js`）只证明了：
//! - `Party / Rainbow` 的命令体 = `40 + seed(1B) + ff + 7 × reunionGroup(3B)`；
//! - `reunionGroup` 的 3 字节结构 = `[dim][0x81][(o<<4)|n]`，其中
//!   `o = floor(16*rand)`（0..15）、`n = i = floor(16*rand)`（0..15）、
//!   `dim = 16*(15-i)+15`。
//!
//! 官方**并没有**证明存在"流光"效果，也没有证明第三字节是色相索引。
//! 本模块是在上述已验证帧结构基础上，由本项目自行设计的实验性效果：
//!
//! ```text
//! 自定义 Flow
//!   ├── 复用官方 0x40 帧结构（40 + seed + ff + 7×3B）
//!   ├── 复用官方 0x81 group 模式字段
//!   ├── 自行设计 seed → 灯珠位置（seed % 7 环形带头）
//!   ├── 自行设计亮度衰减曲线（255 → 175 → 95 → 15）
//!   └── 自行设计颜色映射（色相 → 第三字节高 4 位，低 4 位预留）
//! ```
//!
//! 字段语义尚未经真机验证，上线前建议抓包比对一帧输出并校准。

use crate::hexutil::{dec2hex, hex_to_bytes};

/// 自定义流光帧命令体：`40 + seed + ff + 7 × 3B`（24 字节）。
///
/// `seed` 每帧 +1（由上层循环驱动），光带沿 7 组环形移动。
/// `color_hex`：6 位 RGB hex（如 `"ff8800"`），用于推导光带颜色索引。
pub fn flow_command_body(seed: u8, color_hex: &str) -> String {
    let color_nibble = color_nibble_of(color_hex);
    let mut s = format!("40{}ff", dec2hex(seed as u64, 2));
    for group in 0..7 {
        s.push_str(&flow_group(seed, group, color_nibble));
    }
    s
}

/// 自定义流光组：3 字节 = 亮度衰减 + 0x81 + 颜色配置。
///
/// - 第 1 字节：本项目自定义的移动光带亮度（带头 255，环形距离 1/2/≥3 分别
///   衰减为 175/95/15，尾随拖尾形成"流光"感）；
/// - 第 2 字节：`0x81`，来自官方 `reunionGroup` 的模式字段
///   （`parseInt("1000"+"0001",2)`）；
/// - 第 3 字节：高 4 位 = 用户色相索引（0..15），低 4 位 = 0（未定义，
///   对齐官方 `(o<<4)|n` 的高/低 nibble 结构推测）。
///
/// 注意：官方协议只证明了 reunionGroup 的 3 字节结构，并未证明上述参数
/// 可直接解释为"亮度 + 色彩索引"。本实现属于实验性自定义流光。
fn flow_group(seed: u8, group: usize, color_nibble: u8) -> String {
    let head = (seed as usize) % 7;
    // 带头到本组的环形最短距离 0..=3（7 组取 min(d, 7-d)）
    let dist = (group + 7 - head) % 7;
    let dist = dist.min(7 - dist);
    let dim = match dist {
        0 => 255,
        1 => 175,
        2 => 95,
        _ => 15,
    };
    // 高 4 位 = 色相索引（o），低 4 位 = 0（n 未定义，预留）
    let color_byte = (color_nibble & 0x0F) << 4;
    format!("{}81{:02x}", dec2hex(dim as u64, 2), color_byte)
}

/// 用户颜色（6 位 RGB hex）→ 色相 16 级量化索引（0..15）。
///
/// 对应官方 `reunionGroup` 第三字节的高 4 位 `o`；低 4 位 `n` 未定义。
/// 色相映射：红=0、黄≈2、绿≈5、青=8、蓝≈10、品红≈13。
/// 具体色表由设备端解释，真机比对后可再校准。
fn color_nibble_of(color_hex: &str) -> u8 {
    let bytes = hex_to_bytes(color_hex);
    if bytes.len() != 3 {
        return 0;
    }
    let [r, g, b] = [
        bytes[0] as f32 / 255.0,
        bytes[1] as f32 / 255.0,
        bytes[2] as f32 / 255.0,
    ];
    let max = r.max(g).max(b);
    let min = r.min(g).min(b);
    let delta = max - min;
    // 标准 RGB→HSV 色相（0..360）
    let hue = if delta < 1e-6 {
        0.0
    } else if (max - r).abs() < 1e-6 {
        60.0 * (((g - b) / delta) % 6.0)
    } else if (max - g).abs() < 1e-6 {
        60.0 * ((b - r) / delta + 2.0)
    } else {
        60.0 * ((r - g) / delta + 4.0)
    };
    let hue = if hue < 0.0 { hue + 360.0 } else { hue };
    // 色相 → 16 级：0°=0 … 360°→15（360 处归一化回 0，等价截断）
    ((hue / 360.0 * 16.0) as u32).min(15) as u8
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::packet::build_packet;

    /// 帧结构：`40 + seed + ff`（3 字节头）+ 7 组 × 3 字节 = 24 字节 = 48 hex。
    #[test]
    fn flow_frame_has_header_and_7_groups() {
        let body = flow_command_body(0x42, "ff0000");
        assert_eq!(body.len(), 48);
        assert!(body.starts_with("4042ff"));
    }

    /// 完整 BLE 包 = 帧序号(4B) + 命令体(24B) + CRC32(4B) = 32 字节 = 64 hex。
    #[test]
    fn flow_full_packet_is_32_bytes() {
        let body = flow_command_body(0x42, "ff0000");
        let packet = build_packet(1, &body);
        assert_eq!(packet.len(), 64); // 32 字节
        assert!(packet.starts_with("01000000")); // 帧序号 LE
        assert!(packet[8..56].starts_with("4042ff")); // 命令体头
    }

    /// 带头位置随 seed 移动：seed=0 带头在组0（最亮 255），
    /// seed=1 带头移动到组1（组0 亮度降为尾随 175，组1 变 255）。
    #[test]
    fn flow_head_moves_with_seed() {
        let s0 = flow_command_body(0, "ff0000");
        // 组0 = "ff" (255) + "81" + 颜色(红→色相 nibble 0 → 高4位 0x00) → ff8100
        assert!(s0.starts_with("4000ffff8100"), "seed=0 带头应在组0: {s0}");

        let s1 = flow_command_body(1, "ff0000");
        // 组0 尾随 = af(175)81 00，组1 带头 = ff 81 00
        assert!(s1.starts_with("4001ffaf8100ff8100"), "seed=1 带头应在组1: {s1}");
    }

    /// 亮度为移动光带：带头 255 → 175 → 95 → 15（环形最短距离 0..3）。
    #[test]
    fn flow_brightness_falls_off_around_head() {
        // seed=0，带头组0；距离：g0=0 g1=1 g2=2 g3=3 g4=3 g5=2 g6=1
        let s = flow_command_body(0, "ff0000");
        let groups: Vec<&str> = (0..7).map(|i| &s[6 + i * 6..12 + i * 6]).collect();
        assert_eq!(groups[0], "ff8100"); // 255
        assert_eq!(groups[1], "af8100"); // 175
        assert_eq!(groups[2], "5f8100"); // 95
        assert_eq!(groups[3], "0f8100"); // 15
        assert_eq!(groups[4], "0f8100"); // 15
        assert_eq!(groups[5], "5f8100"); // 95
        assert_eq!(groups[6], "af8100"); // 175
    }

    /// 用户色相 → 16 级 nibble：红=0、黄≈2、绿≈5、青=8、蓝≈10、品红≈13。
    #[test]
    fn flow_color_nibble_from_user_hue() {
        assert_eq!(color_nibble_of("ff0000"), 0x0); // 红 hue=0
        assert_eq!(color_nibble_of("ffff00"), 0x2); // 黄 hue=60 → 60/360*16=2.67→2
        assert_eq!(color_nibble_of("00ff00"), 0x5); // 绿 hue=120 → 5.33→5
        assert_eq!(color_nibble_of("00ffff"), 0x8); // 青 hue=180 → 8
        assert_eq!(color_nibble_of("0000ff"), 0xA); // 蓝 hue=240 → 10.67→10
        assert_eq!(color_nibble_of("ff00ff"), 0xD); // 品红 hue=300 → 13.33→13
        assert_eq!(color_nibble_of("ff0000ff"), 0x0); // 非法长度（4 字节）→ 0
        assert_eq!(color_nibble_of(""), 0x0);
    }
}
