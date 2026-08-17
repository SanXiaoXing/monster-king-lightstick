//! AES-128-ECB/Pkcs7 加解密。两套 key，编码不同：
//!
//! | 用途 | key | 编码 | 输出 |
//! |---|---|---|---|
//! | API 请求体 | `e19d688e06576f47331a701e62ee5a50` | Hex 16B | 密文 hex |
//! | 设备上报 | `xuecwdbn60bljumz` | UTF-8 16B | OpenSSL base64 |
//!
//! 对应 `appservice.app.js:841`（aes-util.js CryptoHelper）与 `:861`（util.js aesEncryptToHex）。

use aes::Aes128;
use base64::{engine::general_purpose::STANDARD as B64, Engine};
use cipher::{block_padding::Pkcs7, BlockDecryptMut, BlockEncryptMut, KeyInit};
use ecb::{Decryptor as EcbDec, Encryptor as EcbEnc};
use rand::RngCore;

/// API 请求体 AES key（Hex 解析为 16 字节）。
pub const API_AES_KEY_HEX: &[u8; 32] = b"e19d688e06576f47331a701e62ee5a50";

/// 设备上报 AES key（UTF-8 解析为 16 字节）。
pub const REPORT_AES_KEY: &[u8; 16] = b"xuecwdbn60bljumz";

#[derive(Debug, thiserror::Error)]
pub enum AesError {
    #[error("bad key length: {0}")]
    BadKey(usize),
    #[error("encrypt block error")]
    Encrypt,
    #[error("decrypt block error")]
    Decrypt,
}

/// 通用 AES-128-ECB/Pkcs7 加密，返回密文字节。
fn aes_ecb_encrypt(plaintext: &[u8], key: &[u8]) -> Result<Vec<u8>, AesError> {
    if key.len() != 16 {
        return Err(AesError::BadKey(key.len()));
    }
    let enc = EcbEnc::<Aes128>::new(key.into());
    // Pkcs7: 明文 16 倍数时补一个完整块，否则补到下一个 16 倍数 → ct_len = (pt/16+1)*16
    let pt_len = plaintext.len();
    let ct_len = (pt_len / 16 + 1) * 16;
    let mut buf = vec![0u8; ct_len];
    buf[..pt_len].copy_from_slice(plaintext);
    let ct = enc
        .encrypt_padded_mut::<Pkcs7>(&mut buf, pt_len)
        .map_err(|_| AesError::Encrypt)?;
    Ok(ct.to_vec())
}

/// 通用 AES-128-ECB/Pkcs7 解密。
fn aes_ecb_decrypt(ciphertext: &[u8], key: &[u8]) -> Result<Vec<u8>, AesError> {
    if key.len() != 16 {
        return Err(AesError::BadKey(key.len()));
    }
    let mut buf = ciphertext.to_vec();
    let dec = EcbDec::<Aes128>::new(key.into());
    let pt = dec
        .decrypt_padded_mut::<Pkcs7>(&mut buf)
        .map_err(|_| AesError::Decrypt)?;
    Ok(pt.to_vec())
}

/// API 请求体加密：明文 UTF-8 → AES-ECB(Hex key) → 密文 hex。
/// 对应 JS `aesEncryptToHex(plaintext)`。
pub fn api_aes_encrypt_hex(plaintext: &str) -> Result<String, AesError> {
    let key = crate::hexutil::hex_to_bytes(std::str::from_utf8(API_AES_KEY_HEX).unwrap());
    let pt = plaintext.as_bytes();
    let ct = aes_ecb_encrypt(pt, &key)?;
    Ok(crate::hexutil::bytes_to_hex(&ct))
}

/// API 请求体解密：密文 hex → 明文 UTF-8。
pub fn api_aes_decrypt_hex(ciphertext_hex: &str) -> Result<String, AesError> {
    let key = crate::hexutil::hex_to_bytes(std::str::from_utf8(API_AES_KEY_HEX).unwrap());
    let ct = crate::hexutil::hex_to_bytes(ciphertext_hex);
    let pt = aes_ecb_decrypt(&ct, &key)?;
    String::from_utf8(pt).map_err(|_| AesError::Decrypt)
}

/// 设备上报加密：明文 UTF-8 → AES-ECB(UTF-8 key) → OpenSSL base64。
///
/// crypto-js 的 `toString()` 在 ECB 模式下生成 `Salted__`(8B 固定) + 随机盐(8B)
/// + 密文，整体 base64。盐**不参与密钥派生**（key 已直接给出），仅格式占位。
pub fn report_aes_encrypt(plaintext: &str) -> String {
    let ct = aes_ecb_encrypt(plaintext.as_bytes(), REPORT_AES_KEY).unwrap();
    let mut out = Vec::with_capacity(16 + ct.len());
    out.extend_from_slice(b"Salted__");
    let mut salt = [0u8; 8];
    rand::thread_rng().fill_bytes(&mut salt);
    out.extend_from_slice(&salt);
    out.extend_from_slice(&ct);
    B64.encode(&out)
}

/// 设备上报解密：OpenSSL base64 → 跳过 `Salted__`+盐 → AES-ECB 解密 → UTF-8。
pub fn report_aes_decrypt(b64: &str) -> Result<String, AesError> {
    let raw = B64
        .decode(b64)
        .map_err(|_| AesError::Decrypt)?;
    // 必须以 "Salted__" 开头，其后 8 字节盐，再后才是密文
    if raw.len() < 16 || &raw[0..8] != b"Salted__" {
        return Err(AesError::Decrypt);
    }
    let ct = &raw[16..];
    let pt = aes_ecb_decrypt(ct, REPORT_AES_KEY)?;
    String::from_utf8(pt).map_err(|_| AesError::Decrypt)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn api_aes_roundtrip() {
        let pt = "{\"deviceId\":\"abc\",\"ts\":12345}";
        let ct = api_aes_encrypt_hex(pt).unwrap();
        let back = api_aes_decrypt_hex(&ct).unwrap();
        assert_eq!(back, pt);
    }

    #[test]
    fn report_aes_roundtrip() {
        let pt = "hello 光剑应援棒";
        let b64 = report_aes_encrypt(pt);
        let back = report_aes_decrypt(&b64).unwrap();
        assert_eq!(back, pt);
    }

    /// 密文 hex 长度 = 明文 UTF-8 字节向上取整到 16 的倍数。
    #[test]
    fn api_aes_ciphertext_length() {
        // "hello" = 5 字节 → Pkcs7 补到 16 字节 → 密文 32 hex 字符
        let ct = api_aes_encrypt_hex("hello").unwrap();
        assert_eq!(ct.len(), 32);
        // 16 字节明文 → 补一个完整 padding 块 → 32 字节密文 → 64 hex
        let ct2 = api_aes_encrypt_hex("0123456789abcdef").unwrap();
        assert_eq!(ct2.len(), 64);
    }

    /// OpenSSL base64 输出以 "U2FsdGVk"（= "Salted__"）开头。
    #[test]
    fn report_aes_openssl_prefix() {
        let b64 = report_aes_encrypt("test");
        assert!(b64.starts_with("U2FsdGVk"));
        assert_eq!(b64.len() % 4, 0);
    }
}
