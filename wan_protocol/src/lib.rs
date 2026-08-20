//! # wan_protocol
//!
//! 光剑应援棒 / 演出宝宝剑（mini_metalumic）蓝牙协议与加密层。
//!
//! 从微信小程序反编译代码精确移植，字节级对齐。
//! 参考来源：`appservice.app.js` 第 840~863 行（util.js / aes-util.js /
//! ble-manager.js / ble-burn.js / ota-manager.js / app.js）。
//!
//! ## 模块
//! - [`hexutil`] — hex / 小端 / 字节序转换
//! - [`crc32`] — CRC32 (IEEE 802.3) + 小端包装
//! - [`aes`] — AES-128-ECB/Pkcs7 × 2（API 请求 / 设备上报）
//! - [`ed25519_sig`] — Ed25519 防伪验签
//! - [`packet`] — BLE 命令包构造 `[帧序号 4B LE][命令体][CRC32 4B LE]`
//! - [`commands`] — 命令字表（9 种灯光效果 / 座位写 / 防伪指令 / OTA）
//! - [`effects`] — 自定义灯光效果引擎（非官方协议，实验性）
//! - [`broadcast`] — 广播烧录协议（Android manufacturerData / iOS serviceUuids XOR）
//! - [`ota`] — OTA 分包包构造

pub mod aes;
pub mod broadcast;
pub mod commands;
pub mod crc32;
pub mod ed25519_sig;
pub mod effects;
pub mod hexutil;
pub mod ota;
pub mod packet;

#[cfg(test)]
mod test_vectors;

pub use aes::{api_aes_decrypt_hex, api_aes_encrypt_hex, report_aes_decrypt, report_aes_encrypt};
pub use broadcast::{build_android_broadcast, build_ios_broadcast, ios_data_to_service_uuids};
pub use commands::{
    antifake_instruction, lighting_command_body, seat_unbind_hex, seat_write_hex,
    LIGHT_FLASH_HEX,
};
pub use crc32::{crc32_hex, crc32_hex_le_hex, crc32_ieee};
pub use ed25519_sig::verify_antifake;
pub use hexutil::{bytes_to_hex, dec2hex, hex_to_bytes, little_endian};
pub use ota::{build_ota_firmware_packet, build_ota_mode_switch, build_ota_reboot};
pub use packet::build_packet;

/// 帧序号小端 hex（8 字符）。等价于 JS `dec2hex(seq,8)` + `littleEndian`。
pub fn frame_seq_hex_le(seq: u32) -> String {
    little_endian(&dec2hex(seq as u64, 8))
}
