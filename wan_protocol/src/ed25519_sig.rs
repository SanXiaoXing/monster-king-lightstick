//! Ed25519 防伪验签。
//!
//! 对应 `appservice.app.js:858`（tweetnacl.js）的 `sign.detached.verify(message, signature, publicKey)`。
//! JS tweetnacl 与 Rust `ed25519-dalek` 都实现 RFC 8032 标准 Ed25519，
//! 对相同 (message, signature, publicKey) 产生一致结果。

use ed25519_dalek::{Signature, Verifier, VerifyingKey};

/// 防伪验签。参数顺序与 JS tweetnacl 一致：`(message, signature, publicKey)`。
///
/// - `message`: 随机挑战（JS 端 16 字节）
/// - `signature`: 设备返回的 64 字节签名
/// - `public_key`: 按设备型号下发的 32 字节 Ed25519 公钥
///
/// 返回 `true` 即验签通过。任何长度/格式错误均返回 `false`（与 JS 的 try/catch
/// 防御性放行不同：这里只回答"签名是否有效"，放行策略由上层 `ble-manager` 决定）。
pub fn verify_antifake(message: &[u8], signature: &[u8], public_key: &[u8]) -> bool {
    let Ok(vk) = VerifyingKey::from_bytes(try_into32(public_key)) else {
        return false;
    };
    let Ok(sig) = Signature::from_slice(signature) else {
        return false;
    };
    vk.verify(message, &sig).is_ok()
}

fn try_into32(s: &[u8]) -> &[u8; 32] {
    if s.len() == 32 {
        // 安全：长度匹配
        let ptr = s.as_ptr() as *const [u8; 32];
        unsafe { &*ptr }
    } else {
        // 返回一个占位引用；调用方先用 from_bytes 判定
        static EMPTY: [u8; 32] = [0; 32];
        &EMPTY
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use ed25519_dalek::{Signature, Signer, SigningKey};
    use rand::rngs::OsRng;

    #[test]
    fn verify_valid_signature() {
        let mut csprng = OsRng;
        let sk = SigningKey::generate(&mut csprng);
        let pk = sk.verifying_key();
        let msg = [1u8, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16];
        let sig: Signature = sk.sign(&msg);

        assert!(verify_antifake(&msg, sig.to_bytes().as_ref(), pk.as_bytes()));
    }

    #[test]
    fn reject_tampered_message() {
        let mut csprng = OsRng;
        let sk = SigningKey::generate(&mut csprng);
        let pk = sk.verifying_key();
        let msg = [1u8; 16];
        let sig: Signature = sk.sign(&msg);

        let tampered = [2u8; 16];
        assert!(!verify_antifake(&tampered, sig.to_bytes().as_ref(), pk.as_bytes()));
    }

    #[test]
    fn reject_bad_lengths() {
        let msg = [0u8; 16];
        // 错误公钥长度
        assert!(!verify_antifake(&msg, &[0u8; 64], &[0u8; 31]));
        // 错误签名长度
        assert!(!verify_antifake(&msg, &[0u8; 63], &[0u8; 32]));
    }
}
