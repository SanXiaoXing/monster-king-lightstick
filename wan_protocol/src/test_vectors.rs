//! 真机测试向量对齐。
//!
//! 所有向量来自小程序反编译代码中的固定常量与确定性算法路径，
//! 字节级对齐验证 wan_protocol 与真机行为一致。
//!
//! 金标准来源：
//! - `chunk_8.appservice.js:129` / `chunk_3.appservice.js:152`：LIGHT_FLASH_HEX
//! - `appservice.app.js:844`：防伪指令构造（F01DF5 + MAC LE + 随机挑战）
//! - `appservice.app.js:843`：buildBroadcastData（Android 27B）
//! - `appservice.app.js:861`：API AES key、CRC32 实现
//! - `chunk_2.appservice.js:123`：9 种灯光效果命令体

#![cfg(test)]

use crate::commands::{lighting_command_body, seat_unbind_hex, LightingEffect, LIGHT_FLASH_HEX};
use crate::packet::build_packet;

/// 金标准 1：LIGHT_FLASH_HEX 端到端构造验证。
///
/// 来源：`chunk_8.appservice.js:129` showshanguan() 硬编码
/// `"02000000100004ff020c06104c6a5e52"`（16 字节）。
///
/// 分解：
/// - 帧序号 LE: `02000000` → seq=2
/// - 命令体: `100004ff020c0610` = FlashMob(color="0004ff") → `10` + `0004ff` + `020c0610`
/// - CRC32 LE: `4c6a5e52` → CRC32(frame) 的小端 hex
///
/// 此测试通过即证明：frame_seq_hex_le + lighting_command_body(FlashMob) +
/// crc32_hex_le_hex + build_packet 四层链路与真机字节级对齐。
#[test]
fn golden_light_flash_hex_end_to_end() {
    // 用 build_packet(2, FlashMob("0004ff")) 重建，应等于 LIGHT_FLASH_HEX
    let body = lighting_command_body(LightingEffect::FlashMob, "0004ff", 0, || 0);
    assert_eq!(body, "100004ff020c0610");
    let packet = build_packet(2, &body);
    assert_eq!(packet, LIGHT_FLASH_HEX, "LIGHT_FLASH_HEX 端到端不匹配");
    assert_eq!(packet.len(), 32); // 16 字节
}

/// 金标准 2：LIGHT_FLASH_HEX 的 CRC32 反向验证。
///
/// 从硬编码包中提取 frame（前 18 hex = 9 字节），独立计算 CRC32，
/// 转小端后应等于包尾 `4c6a5e52`。
#[test]
fn golden_light_flash_crc_reverse_check() {
    let frame_hex = "02000000100004ff020c0610"; // seq + body (9 字节)
    let crc = crate::crc32::crc32_hex(frame_hex);
    let crc_le_hex = crate::crc32::crc32_hex_le_hex(frame_hex);
    assert_eq!(crc_le_hex, "4c6a5e52");
    // CRC32 值 → 小端字节 → 解析回 u32，应等于 0x525e6a4c
    let crc_bytes = crate::hexutil::hex_to_bytes(&crc_le_hex);
    let crc_as_le_u32 = u32::from_le_bytes(crc_bytes.try_into().unwrap());
    assert_eq!(crc, 0x525e6a4c);
    assert_eq!(crc_as_le_u32, crc);
}

/// 金标准 3：座位解绑包 = 10 字节全 0xFF。
///
/// 来源：`chunk_8.appservice.js:129` writeSeatInfo("FFFFFFFFFFFFFFFFFFFF")。
/// JS 用大写，Rust 返回小写；BLE `hexStringToArrayBuffer` 用 `parseInt(,16)`
/// 不区分大小写，字节级一致即可。
#[test]
fn golden_seat_unbind_all_ff() {
    let s = seat_unbind_hex();
    assert_eq!(s.to_uppercase(), "FFFFFFFFFFFFFFFFFFFF");
    let bytes = crate::hexutil::hex_to_bytes(s);
    assert_eq!(bytes.len(), 10);
    assert!(bytes.iter().all(|&b| b == 0xFF));
}

/// 金标准 4：灯光效果命令体（确定性路径，无随机量）。
///
/// 来源：`chunk_2.appservice.js:123` functionalInstructions 的 case 0/1/3/4/5。
/// 命令体 = `a + body` 中 a 之前的部分（不含帧序号）。
#[test]
fn golden_lighting_bodies_match_js() {
    // case 0: "00000000"
    assert_eq!(
        lighting_command_body(LightingEffect::BlackScreen, "", 0, || 0),
        "00000000"
    );
    // case 1: "00" + color
    assert_eq!(
        lighting_command_body(LightingEffect::ConstantlyOn, "ff8800", 0, || 0),
        "00ff8800"
    );
    // case 3: "10" + color + "020c0610"
    assert_eq!(
        lighting_command_body(LightingEffect::FlashMob, "ff0000", 0, || 0),
        "10ff0000020c0610"
    );
    // case 4: "20" + color + "58029001"
    assert_eq!(
        lighting_command_body(LightingEffect::Blink, "00ff00", 0, || 0),
        "2000ff0058029001"
    );
    // case 5: "20" + color + "c409f401"
    assert_eq!(
        lighting_command_body(LightingEffect::Breathe, "0000ff", 0, || 0),
        "200000ffc409f401"
    );
}

/// 金标准 5：FlashMob 命令体格式 = `10` + color(6) + `020c0610`。
///
/// LIGHT_FLASH_HEX 中的 color=`0004ff` 是真机抓包值，验证格式严格匹配。
#[test]
fn golden_flash_mob_format_from_real_capture() {
    // LIGHT_FLASH_HEX = seq(2) + "100004ff020c0610" + crc
    // body = "10" + "0004ff" + "020c0610" = 16 hex = 8 字节
    let body = lighting_command_body(LightingEffect::FlashMob, "0004ff", 0, || 0);
    assert_eq!(body, "100004ff020c0610");
    assert_eq!(body.len(), 16);
    // 头部 "10" + 尾部 "020c0610" 固定
    assert!(body.starts_with("10"));
    assert!(body.ends_with("020c0610"));
}

/// 金标准 6：完整包构造 = frame(8) + body(16) + crc(8) = 32 hex = 16 字节。
///
/// 验证 LIGHT_FLASH_HEX 的字节长度与结构。
#[test]
fn golden_packet_structure_16_bytes() {
    let packet = build_packet(2, "100004ff020c0610");
    assert_eq!(packet.len(), 32);
    // 帧序号占前 8 hex (4 字节)
    assert_eq!(&packet[0..8], "02000000");
    // CRC 占后 8 hex (4 字节)
    assert_eq!(&packet[24..32], "4c6a5e52");
    // 中间 16 hex (8 字节) 是命令体
    assert_eq!(&packet[8..24], "100004ff020c0610");
}

/// 金标准 7：防伪指令结构（固定随机挑战，可复现）。
///
/// 来源：`appservice.app.js:844` _verifyAntiFake 构造：
/// `frame(4B LE) + "f01df5" + MAC_LE(6B) + "0000ff000000" + random(16B) + CRC(4B LE)`
/// 总 39 字节。用固定随机挑战验证完整链路。
#[test]
fn golden_antifake_instruction_structure() {
    let mac = "aabbccddeeff";
    let mut random_16 = [0u8; 16];
    for (i, b) in random_16.iter_mut().enumerate() {
        *b = i as u8; // 0,1,2,...,15
    }
    let instr = crate::commands::antifake_instruction(1, mac, &random_16);

    assert_eq!(instr.len(), 39);
    // 帧序号 LE: seq=1 → 01 00 00 00
    assert_eq!(&instr[0..4], &[0x01, 0x00, 0x00, 0x00]);
    // 魔数 F0 1D F5
    assert_eq!(&instr[4..7], &[0xF0, 0x1D, 0xF5]);
    // MAC LE: aabbccddeeff → ffeeddccbbaa
    assert_eq!(&instr[7..13], &[0xff, 0xee, 0xdd, 0xcc, 0xbb, 0xaa]);
    // 固定段 00 00 FF 00 00 00
    assert_eq!(&instr[13..19], &[0x00, 0x00, 0xFF, 0x00, 0x00, 0x00]);
    // 随机挑战 0..15
    assert_eq!(&instr[19..35], &(0..16u8).collect::<Vec<_>>());
    // CRC32 LE 覆盖前 35 字节
    let crc = crate::crc32::crc32_ieee(&instr[0..35]);
    assert_eq!(&instr[35..39], &crc.to_le_bytes());
}

/// 金标准 8：Android 广播数据结构（27 字节，CRC32 LE 校验）。
///
/// 来源：`appservice.app.js:843` buildBroadcastData。
/// 布局：seq(4B LE) + F0 17 79 + MAC_LE(6B) + region(1B) + x0(2B LE) +
/// y0(2B LE) + FFFF(2B) + FFFF(2B) + show(1B) + CRC32(4B LE) = 27 字节。
#[test]
fn golden_android_broadcast_structure() {
    let data =
        crate::broadcast::build_android_broadcast(1, "aabbccddeeff", 0xA1, 0x0102, 0x0304, 0x05);
    assert_eq!(data.len(), 27);
    assert_eq!(&data[0..4], &[0x01, 0x00, 0x00, 0x00]); // seq LE
    assert_eq!(&data[4..7], &[0xF0, 0x17, 0x79]); // 头
    assert_eq!(&data[7..13], &[0xff, 0xee, 0xdd, 0xcc, 0xbb, 0xaa]); // MAC LE
    assert_eq!(data[13], 0xA1); // region
    assert_eq!(&data[14..16], &[0x02, 0x01]); // x0 LE
    assert_eq!(&data[16..18], &[0x04, 0x03]); // y0 LE
    assert_eq!(&data[18..22], &[0xFF, 0xFF, 0xFF, 0xFF]); // 0xFFFF × 2
    assert_eq!(data[22], 0x05); // show
    // CRC32 LE 覆盖前 23 字节
    let crc = crate::crc32::crc32_ieee(&data[0..23]);
    assert_eq!(&data[23..27], &crc.to_le_bytes());
}

/// 金标准 9：iOS 广播 26 字节 + serviceUuids 去重。
///
/// 来源：`chunk_69.appservice.js:46` doStartAdvertising 内联 iOS 算法。
/// 26B = F7 FF frmcnt + 19B payload + 4B CRC32 LE，[4..26] 做 xorshift32 混淆。
#[test]
fn golden_ios_broadcast_structure_and_uniqueness() {
    let (frmcnt, data) =
        crate::broadcast::build_ios_broadcast(0x42, "aabbccddeeff", 0xA1, 0x100, 0x200, 0x05);
    assert_eq!(data.len(), 26);
    assert_eq!(data[0], 0xF7); // 头部不被 XOR
    assert_eq!(data[1], 0xFF);
    assert_eq!(data[2], frmcnt); // frmcnt 不被 XOR
    assert_eq!(data[3], 0xF0); // payload[0] 不被 XOR（XOR 从 index 4 起）

    // 转成 13 个 serviceUuid，必须全不重复
    let uuids = crate::broadcast::ios_data_to_service_uuids(&data);
    assert_eq!(uuids.len(), 13);
    let unique: std::collections::HashSet<_> = uuids.iter().collect();
    assert_eq!(unique.len(), 13, "iOS serviceUuids 必须全不重复");
}

/// 金标准 10：iOS serviceUuid 格式 = `{hi:02X}{lo:02X}`。
///
/// 来源：`chunk_69.appservice.js:46`：
/// `s.push((h+d).toUpperCase())` 其中 d=lo.toString(16).padStart(2,"0"),
/// h=hi.toString(16).padStart(2,"0")。
#[test]
fn golden_ios_service_uuid_format() {
    // [0xF7, 0xFF] → hi=FF lo=F7 → "FFF7"
    let uuids = crate::broadcast::ios_data_to_service_uuids(&[0xF7, 0xFF]);
    assert_eq!(uuids, vec!["FFF7"]);
    // [0xAB, 0xCD, 0xEF] → "CDAB" + "FFEF"（末尾奇字节补 0xFF）
    let uuids2 = crate::broadcast::ios_data_to_service_uuids(&[0xAB, 0xCD, 0xEF]);
    assert_eq!(uuids2, vec!["CDAB", "FFEF"]);
}

/// 金标准 11：API AES key 确认（Hex 解析为 16 字节）。
///
/// 来源：`appservice.app.js:861`：
/// `n.enc.Hex.parse("e19d688e06576f47331a701e62ee5a50")`。
#[test]
fn golden_api_aes_key_hex_parsed() {
    let key_hex = std::str::from_utf8(crate::aes::API_AES_KEY_HEX).unwrap();
    assert_eq!(key_hex, "e19d688e06576f47331a701e62ee5a50");
    let key_bytes = crate::hexutil::hex_to_bytes(key_hex);
    assert_eq!(key_bytes.len(), 16); // AES-128
}

/// 金标准 12：设备上报 AES key 确认（UTF-8 解析为 16 字节）。
///
/// 来源：`appservice.app.js:841` aes-util.js CryptoHelper。
#[test]
fn golden_report_aes_key_utf8_16_bytes() {
    assert_eq!(crate::aes::REPORT_AES_KEY.len(), 16);
    assert_eq!(std::str::from_utf8(crate::aes::REPORT_AES_KEY).unwrap(), "xuecwdbn60bljumz");
}

/// 金标准 13：AES 加解密往返（验证 Pkcs7 padding 与 ECB 模式正确）。
#[test]
fn golden_aes_roundtrip_preserves_plaintext() {
    let pt = r#"{"deviceId":"abc","ts":12345}"#;
    let ct = crate::aes::api_aes_encrypt_hex(pt).unwrap();
    let back = crate::aes::api_aes_decrypt_hex(&ct).unwrap();
    assert_eq!(back, pt);
    // 密文长度 = 明文字节向上取整到 16 的倍数 × 2
    let expected_ct_len = ((pt.len() / 16 + 1) * 16) * 2;
    assert_eq!(ct.len(), expected_ct_len);
}

/// 金标准 14：设备上报 AES 输出 OpenSSL 格式（"U2FsdGVk" = "Salted__" base64）。
///
/// 来源：crypto-js `toString()` 在 ECB 模式下生成 `Salted__` + 8B 盐 + 密文。
#[test]
fn golden_report_aes_openssl_format() {
    let b64 = crate::aes::report_aes_encrypt("test");
    assert!(b64.starts_with("U2FsdGVk")); // "Salted__" 的 base64 前缀
    assert_eq!(b64.len() % 4, 0);
}

/// 金标准 15：Ed25519 验签（RFC 8032 标准，与 tweetnacl 互通）。
///
/// 来源：`appservice.app.js:858` tweetnacl `sign.detached.verify`。
/// JS tweetnacl 与 Rust ed25519-dalek 都实现 RFC 8032，对相同输入产生一致结果。
#[test]
fn golden_ed25519_verify_valid_signature() {
    use ed25519_dalek::{Signature, Signer, SigningKey};
    use rand::rngs::OsRng;

    let mut csprng = OsRng;
    let sk = SigningKey::generate(&mut csprng);
    let pk = sk.verifying_key();
    let msg = [1u8, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16];
    let sig: Signature = sk.sign(&msg);

    assert!(crate::ed25519_sig::verify_antifake(
        &msg,
        sig.to_bytes().as_ref(),
        pk.as_bytes()
    ));
}

/// 金标准 16：OTA 模式切换/重启命令（固定魔数）。
///
/// 来源：`appservice.app.js:855` ota-manager.js：
/// - 模式切换：`0x55555555` → 特征值 AC1F3D08
/// - 重启：`0xCCCCCCCC` → 特征值 AC1F3D13
#[test]
fn golden_ota_magic_commands() {
    assert_eq!(crate::ota::build_ota_mode_switch(), [0x55, 0x55, 0x55, 0x55]);
    assert_eq!(crate::ota::build_ota_reboot(), [0xCC, 0xCC, 0xCC, 0xCC]);
}

/// 金标准 17：OTA 固件分包 = offset(4B LE) + chunk。
///
/// 来源：`appservice.app.js:855` ota-manager.js，写入特征值 AC1F3D12。
#[test]
fn golden_ota_firmware_packet_layout() {
    let chunk = [0xAA, 0xBB, 0xCC, 0xDD];
    let pkt = crate::ota::build_ota_firmware_packet(0x01020304, &chunk);
    assert_eq!(pkt, vec![0x04, 0x03, 0x02, 0x01, 0xAA, 0xBB, 0xCC, 0xDD]);
}

/// 金标准 18：帧序号小端 hex（8 字符）。
///
/// 来源：`chunk_2.appservice.js:123`：
/// `dec2hex(FrameSequence, 8)` + `littleEndian(...)`。
#[test]
fn golden_frame_seq_little_endian() {
    assert_eq!(crate::frame_seq_hex_le(1), "01000000");
    assert_eq!(crate::frame_seq_hex_le(2), "02000000"); // LIGHT_FLASH_HEX 用的值
    assert_eq!(crate::frame_seq_hex_le(0xABCDEF01), "01efcdab");
    assert_eq!(crate::frame_seq_hex_le(0), "00000000");
}

/// 金标准 19：CRC32 经典校验值（IEEE 802.3 / zlib 标准）。
///
/// "123456789" → 0xCBF43926。这是 CRC32 的标准 check value，
/// JS `hex16StrCrc32Encryption` 与 Rust `crc32_ieee` 都必须匹配。
#[test]
fn golden_crc32_canonical_check() {
    assert_eq!(crate::crc32::crc32_ieee(b"123456789"), 0xCBF43926);
    assert_eq!(crate::crc32::crc32_ieee(&[0u8; 8]), 0x6522DF69);
}
