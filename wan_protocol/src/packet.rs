//! BLE 命令包构造。
//!
//! 统一格式：`[帧序号 4B LE][命令体 N B][CRC32 4B LE]`。
//! 对应 JS 各页面 `_doSendBlueData` / `deviceTestColor` 的拼接逻辑
//! （`chunk_2.appservice.js:123` / `chunk_7.appservice.js:186`）。

use crate::crc32::crc32_hex_le_hex;
use crate::hexutil::hex_to_bytes;
use crate::frame_seq_hex_le;

/// 由帧序号 + 命令体 hex 构造完整包，返回 hex 字符串。
///
/// 1. `frame = frame_seq_hex_le(seq) + command_body_hex`
/// 2. `crc_le = crc32_hex_le_hex(frame)`  // CRC32 覆盖 frame_seq+命令体，再转小端
/// 3. `packet = frame + crc_le`
pub fn build_packet(seq: u32, command_body_hex: &str) -> String {
    let frame = format!("{}{}", frame_seq_hex_le(seq), command_body_hex);
    let crc_le = crc32_hex_le_hex(&frame);
    format!("{}{}", frame, crc_le)
}

/// 同 [`build_packet`]，但返回字节（可直接写 BLE）。
pub fn build_packet_bytes(seq: u32, command_body_hex: &str) -> Vec<u8> {
    hex_to_bytes(&build_packet(seq, command_body_hex))
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::crc32::crc32_hex;
    use crate::hexutil::{bytes_to_hex, dec2hex, little_endian};

    /// 黑屏命令：帧序号 1 + 命令体 "00000000"。
    /// 手算：frame = "01000000" + "00000000" = "0100000000000000"
    /// crc32(8 字节 [01,00,00,00,00,00,00,00]) → 小端 hex。
    #[test]
    fn build_packet_black_screen() {
        let seq = 1u32;
        let body = "00000000";
        let packet = build_packet(seq, body);

        // 重组预期：frame(8B) + crc(4B LE) = 24 hex 字符
        assert_eq!(packet.len(), 24);
        assert!(packet.starts_with("0100000000000000"));

        // 校验 CRC 部分 = little_endian(dec2hex(crc32(frame), 8))
        let frame = "0100000000000000";
        let crc = crc32_hex(frame);
        let expected_crc = little_endian(&dec2hex(crc as u64, 8));
        assert!(packet.ends_with(&expected_crc));
    }

    /// 帧序号递增不溢出（JS 用 Number，这里用 u32 更安全）。
    #[test]
    fn build_packet_high_seq() {
        let p = build_packet(0xABCDEF01, "00ff00ff");
        // 帧序号小端："abcdef01" → "01efcdab"
        assert!(p.starts_with("01efcdab00ff00ff"));
    }

    /// bytes 版与 hex 版一致。
    #[test]
    fn packet_bytes_matches_hex() {
        let hex = build_packet(7, "00ff00ff");
        let bytes = build_packet_bytes(7, "00ff00ff");
        assert_eq!(bytes_to_hex(&bytes), hex);
    }
}
