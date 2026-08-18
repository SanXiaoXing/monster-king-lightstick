//! Flutter Rust Bridge 适配层。
//!
//! 将 [`crate::protocol`]（wan_protocol 门面）的 API 包装为 frb 友好签名：
//! - `&str` → `String`
//! - `&[u8]` / `&[u8; N]` → `Vec<u8>`
//! - 元组返回 → struct
//! - 闭包参数（灯光随机效果）→ 内部用 `rand::random`
//!
//! AES 加解密失败返回 [`crate::error::WanError`]（frb 已注册，Dart 侧以异常上抛）。

use crate::error::WanError;

/// 9 种灯光效果。frb 生成对应 Dart 枚举。
#[derive(Clone, Copy, Debug)]
pub enum LightingEffect {
    BlackScreen,  // 黑屏
    ConstantlyOn, // 常亮
    Random,       // 随机色
    FlashMob,     // 快闪
    Blink,        // 眨眼
    Breathe,      // 呼吸
    Party,        // 聚会
    Rainbow,      // 彩虹
    StarrySky,    // 星空
}

/// iOS 广播结果（frmcnt + 26 字节数据）。
pub struct IosBroadcastResult {
    pub frmcnt: u8,
    pub data: Vec<u8>,
}

// ── hex / 字节转换 ──

pub fn hex_to_bytes(hex: String) -> Vec<u8> {
    crate::protocol::hex_to_bytes(&hex)
}

pub fn bytes_to_hex(bytes: Vec<u8>) -> String {
    crate::protocol::bytes_to_hex(&bytes)
}

pub fn dec2hex(n: u64, width: u32) -> String {
    crate::protocol::dec2hex(n, width as usize)
}

pub fn little_endian(hex: String) -> String {
    crate::protocol::little_endian(&hex)
}

// ── 帧序号 ──

pub fn frame_seq_hex_le(seq: u32) -> String {
    crate::protocol::frame_seq_hex_le(seq)
}

// ── CRC32 ──

pub fn crc32_hex(hex: String) -> u32 {
    crate::protocol::crc32_hex(&hex)
}

pub fn crc32_ieee(data: Vec<u8>) -> u32 {
    crate::protocol::crc32_ieee(&data)
}

// ── AES-128-ECB ──

/// AES-ECB 加密（API key），失败返回 [`WanError`]。
pub fn api_aes_encrypt_hex(plaintext: String) -> Result<String, WanError> {
    crate::protocol::api_aes_encrypt_hex(&plaintext)
        .map_err(|e| WanError::Protocol(format!("AES 失败: {e}")))
}

/// AES-ECB 解密（API key），失败返回 [`WanError`]。
pub fn api_aes_decrypt_hex(ciphertext_hex: String) -> Result<String, WanError> {
    crate::protocol::api_aes_decrypt_hex(&ciphertext_hex)
        .map_err(|e| WanError::Protocol(format!("AES 失败: {e}")))
}

pub fn report_aes_encrypt(plaintext: String) -> String {
    crate::protocol::report_aes_encrypt(&plaintext)
}

/// 设备上报解密，失败返回 [`WanError`]。
pub fn report_aes_decrypt(b64: String) -> Result<String, WanError> {
    crate::protocol::report_aes_decrypt(&b64)
        .map_err(|e| WanError::Protocol(format!("AES 失败: {e}")))
}

// ── BLE 命令包 ──

pub fn build_packet(seq: u32, command_body_hex: String) -> String {
    crate::protocol::build_packet(seq, &command_body_hex)
}

// ── 灯光效果 ──

pub fn lighting_command_body(effect: LightingEffect, color_hex: String, seed: u8) -> String {
    let e = match effect {
        LightingEffect::BlackScreen => crate::protocol::commands::LightingEffect::BlackScreen,
        LightingEffect::ConstantlyOn => crate::protocol::commands::LightingEffect::ConstantlyOn,
        LightingEffect::Random => crate::protocol::commands::LightingEffect::Random,
        LightingEffect::FlashMob => crate::protocol::commands::LightingEffect::FlashMob,
        LightingEffect::Blink => crate::protocol::commands::LightingEffect::Blink,
        LightingEffect::Breathe => crate::protocol::commands::LightingEffect::Breathe,
        LightingEffect::Party => crate::protocol::commands::LightingEffect::Party,
        LightingEffect::Rainbow => crate::protocol::commands::LightingEffect::Rainbow,
        LightingEffect::StarrySky => crate::protocol::commands::LightingEffect::StarrySky,
    };
    crate::protocol::lighting_command_body(e, &color_hex, seed, rand::random::<u8>)
}

/// LIGHT_FLASH_HEX 常量（座位绑定闪光特效，16 字节）。
pub fn light_flash_hex() -> String {
    crate::protocol::LIGHT_FLASH_HEX.to_string()
}

// ── 座位 ──

pub fn seat_write_hex(light_area: Option<u8>, x1: u16, y1: u16, show_num: Option<u8>) -> String {
    crate::protocol::seat_write_hex(light_area, x1, y1, show_num)
}

pub fn seat_unbind_hex() -> String {
    crate::protocol::seat_unbind_hex().to_string()
}

// ── 防伪 ──

pub fn antifake_instruction(seq: u32, mac_hex: String, random_16: Vec<u8>) -> Vec<u8> {
    let mut rnd = [0u8; 16];
    let n = random_16.len().min(16);
    rnd[..n].copy_from_slice(&random_16[..n]);
    crate::protocol::antifake_instruction(seq, &mac_hex, &rnd)
}

pub fn verify_antifake(message: Vec<u8>, signature: Vec<u8>, public_key: Vec<u8>) -> bool {
    crate::protocol::verify_antifake(&message, &signature, &public_key)
}

// ── 广播烧录 ──

pub fn build_android_broadcast(
    seq: u32,
    mac_hex: String,
    region: u8,
    x0: u16,
    y0: u16,
    show: u8,
) -> Vec<u8> {
    crate::protocol::build_android_broadcast(seq, &mac_hex, region, x0, y0, show).to_vec()
}

pub fn build_ios_broadcast(
    counter: u8,
    mac_hex: String,
    region: u8,
    x0: u16,
    y0: u16,
    show: u8,
) -> IosBroadcastResult {
    let (frmcnt, data) =
        crate::protocol::build_ios_broadcast(counter, &mac_hex, region, x0, y0, show);
    IosBroadcastResult { frmcnt, data: data.to_vec() }
}

pub fn ios_data_to_service_uuids(data: Vec<u8>) -> Vec<String> {
    crate::protocol::ios_data_to_service_uuids(&data)
}

// ── OTA ──

pub fn build_ota_mode_switch() -> Vec<u8> {
    crate::protocol::build_ota_mode_switch().to_vec()
}

pub fn build_ota_reboot() -> Vec<u8> {
    crate::protocol::build_ota_reboot().to_vec()
}

pub fn build_ota_firmware_packet(offset: u32, chunk: Vec<u8>) -> Vec<u8> {
    crate::protocol::build_ota_firmware_packet(offset, &chunk)
}
