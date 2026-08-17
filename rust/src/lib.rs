//! # wan_protocol_frb
//!
//! Flutter Rust Bridge 桥接 crate。分层：
//!
//! ```text
//! Flutter (Dart)
//!    ↓ frb 生成绑定
//! api/                ← Flutter 唯一入口（薄签名转换）
//!    ↓
//! lightstick/         ← 领域逻辑（编排 bluetooth + protocol）
//!    ↓            ↓
//! bluetooth/     protocol/ → wan_protocol crate（协议实现，61 测试）
//! audio/              ← 音频分析（驱动律动效果）
//! ```
//!
//! 铁律：api/ 只做签名转换；逻辑落在对应领域模块；协议实现统一走
//! `crate::protocol::`（wan_protocol 透传），不直接 `use wan_protocol`。

pub mod api;
pub mod audio;
pub mod bluetooth;
pub mod error;
pub mod lightstick;
pub mod protocol;

// flutter_rust_bridge_codegen generate 会在首次运行时自动添加 `mod frb_generated;`
