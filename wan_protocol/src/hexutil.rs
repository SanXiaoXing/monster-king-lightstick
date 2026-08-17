//! hex / 小端 / 字节序转换工具。
//!
//! 对应 `appservice.app.js:861`（utils/util.js）里的：
//! `dec2hex` / `littleEndian` / `hexStringToArrayBuffer` /
//! `arrayBufferToHexString` / `hexStringToByte`。

/// 数字 → 指定宽度的 hex 字符串（左侧补 0，小写）。
/// 对应 JS `dec2hex(n, width)` / `int2hex16`（后者额外 toUpperCase，按场景在调用方处理）。
pub fn dec2hex(n: u64, width: usize) -> String {
    let mut s = format!("{:x}", n);
    while s.len() < width {
        s.insert(0, '0');
    }
    s
}

/// hex 字符串按 2 字节（4 hex 字符）为一组**整体反转字节序**。
///
/// 对应 JS `littleEndian`。JS 实现从 `e = r.length` 起循环，第一次取 `charAt(length)`
/// 为空串——对**偶数长度** hex 串，结果与下方干净实现完全一致（已验证）。
/// 所有调用方传的都是偶数长度（4/8/12/…），故行为对齐。
///
/// 例：`"12345678"` → `"78563412"`，`"cbf43926"` → `"2639f4cb"`。
pub fn little_endian(hex: &str) -> String {
    if hex.is_empty() {
        return String::new();
    }
    let mut out = String::with_capacity(hex.len());
    let mut i = hex.len();
    while i > 0 {
        let start = i.saturating_sub(2);
        out.push_str(&hex[start..i]);
        i = start;
    }
    out
}

/// hex 字符串 → 字节。对应 JS `hexStringToByte` / `hexStringToArrayBuffer`。
/// 忽略大小写；空串返回空 Vec。
pub fn hex_to_bytes(hex: &str) -> Vec<u8> {
    if hex.is_empty() {
        return Vec::new();
    }
    let s: String = hex.chars().filter(|c| !c.is_whitespace()).collect();
    (0..s.len())
        .step_by(2)
        .map(|i| u8::from_str_radix(&s[i..i + 2], 16).unwrap_or(0))
        .collect()
}

/// 字节 → hex 字符串（小写，无分隔）。对应 JS `arrayBufferToHexString`。
pub fn bytes_to_hex(bytes: &[u8]) -> String {
    let mut s = String::with_capacity(bytes.len() * 2);
    for b in bytes {
        s.push_str(&format!("{:02x}", b));
    }
    s
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn dec2hex_pads_to_width() {
        assert_eq!(dec2hex(1, 8), "00000001");
        assert_eq!(dec2hex(0xabc, 8), "00000abc");
        assert_eq!(dec2hex(255, 2), "ff");
        // 超过宽度不截断（与 JS 一致）
        assert_eq!(dec2hex(0x12345, 2), "12345");
    }

    #[test]
    fn little_endian_reverses_byte_pairs() {
        assert_eq!(little_endian("12345678"), "78563412");
        assert_eq!(little_endian("cbf43926"), "2639f4cb");
        assert_eq!(little_endian("00000001"), "01000000");
        assert_eq!(little_endian("a1b2c3d4"), "d4c3b2a1");
        // 偶数长度边界
        assert_eq!(little_endian("ab"), "ab");
        assert_eq!(little_endian(""), "");
    }

    #[test]
    fn hex_bytes_roundtrip() {
        assert_eq!(hex_to_bytes("deadbeef"), vec![0xde, 0xad, 0xbe, 0xef]);
        assert_eq!(bytes_to_hex(&[0xde, 0xad, 0xbe, 0xef]), "deadbeef");
        assert!(hex_to_bytes("").is_empty());
        // 大小写不敏感
        assert_eq!(hex_to_bytes("DEADBEEF"), vec![0xde, 0xad, 0xbe, 0xef]);
    }
}
