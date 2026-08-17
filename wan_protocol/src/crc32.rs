//! CRC32 (IEEE 802.3) 与小端包装。
//!
//! 对应 `appservice.app.js:861`（utils/util.js）的 `hex16StrCrc32Encryption`：
//! 多项式 `0xEDB88320`，init `0xFFFFFFFF`，finalXOR `0xFFFFFFFF`，表驱动。
//! 等价于 zlib/zip 使用的标准 CRC32。底层用 `crc32fast`（同款实现）。

use crate::hexutil::{hex_to_bytes, little_endian, dec2hex};

/// 对字节切片做标准 CRC32，返回无符号 u32。
/// 对应 JS `hex16StrCrc32Encryption` 内部对字节的处理（不含 hex 解析）。
pub fn crc32_ieee(data: &[u8]) -> u32 {
    let mut h = crc32fast::Hasher::new();
    h.update(data);
    h.finalize()
}

/// 对 hex 字符串做 CRC32（先 hex→bytes 再 crc32），返回无符号 u32。
/// 对应 JS `hex16StrCrc32Encryption(hexStr)` 的返回值（十进制整数）。
pub fn crc32_hex(hex: &str) -> u32 {
    let bytes = hex_to_bytes(hex);
    crc32_ieee(&bytes)
}

/// CRC32 → 8 位 hex → 小端，返回 8 字符 hex 串（用于追加到包尾）。
/// 对应 JS 调用链：`dec2hex(hex16StrCrc32Encryption(body), 8)` + `littleEndian(...)`。
pub fn crc32_hex_le_hex(body_hex: &str) -> String {
    let crc = crc32_hex(body_hex);
    let crc_hex = dec2hex(crc as u64, 8);
    little_endian(&crc_hex)
}

#[cfg(test)]
mod tests {
    use super::*;

    /// CRC32 经典校验值：9 字节 ASCII "123456789" → 0xCBF43926。
    /// 这是 IEEE 802.3 / zlib 的标准 check value，JS hex16StrCrc32Encryption 同款。
    #[test]
    fn crc32_canonical_check_value() {
        let bytes = b"123456789";
        assert_eq!(crc32_ieee(bytes), 0xCBF43926);
    }

    #[test]
    fn crc32_empty_is_zero() {
        assert_eq!(crc32_ieee(&[]), 0);
    }

    /// hex 形式的 "123456789"（0x31..0x39）应等于经典校验值。
    #[test]
    fn crc32_hex_matches_ascii() {
        assert_eq!(crc32_hex("313233343536373839"), 0xCBF43926);
    }

    /// 8 个 0x00 字节的 CRC32（zlib 已知值 0x6522DF69）。
    #[test]
    fn crc32_eight_zeros() {
        assert_eq!(crc32_ieee(&[0u8; 8]), 0x6522DF69);
    }

    /// CRC32 小端包装：`crc32_hex_le_hex` 应 = `little_endian(dec2hex(crc,8))`。
    #[test]
    fn crc32_le_wrapper() {
        let body = "313233343536373839";
        let crc = crc32_hex(body);
        let expected = little_endian(&dec2hex(crc as u64, 8));
        assert_eq!(crc32_hex_le_hex(body), expected);
        // 经典值 0xCBF43926 → "cbf43926" → 小端 "2639f4cb"
        assert_eq!(crc32_hex_le_hex("313233343536373839"), "2639f4cb");
    }
}
