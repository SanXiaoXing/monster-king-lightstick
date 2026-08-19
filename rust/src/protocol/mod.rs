//! # protocol — 协议解析与封包
//!
//! 协议层门面。实现由独立 crate [`wan_protocol`] 提供（从微信小程序
//! 反编译代码精确移植，61 个单元测试字节级对齐验证通过），
//! 本模块将其透传为本 crate 内部的 `crate::protocol::` 命名空间。
//!
//! ## 调用链位置
//!
//! ```text
//! api/  →  lightstick/  →  protocol/  →  wan_protocol (实现)
//!                     └→  bluetooth/  →  BLE
//! ```
//!
//! 内部模块统一走 `crate::protocol::`，不直接 `use wan_protocol` —— 将来若把
//! wan_protocol 物理并入本 crate，调用方零改动。响应解码（notify 原始字节 →
//! 结构化响应）尚未逆向完成，拿到真机抓包后再补 decoder。

pub mod command;
pub mod packet;

/// 全量透传 wan_protocol 公共 API（crc32/aes/ed25519/broadcast/ota/
/// hexutil 及其顶层函数与常量）。
pub use wan_protocol::*;
