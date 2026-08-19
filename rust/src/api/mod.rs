//! FRB 边界层：Flutter 通过这里调用 Rust，不直接接触内部模块。
//!
//! - [`protocol`] — 协议构造（已实现：lighting_command_body / build_packet /
//!   hex_to_bytes + LightingEffect）
//! - [`simple`] — frb 初始化钩子（init_app）
//! - [`audio`] — 音频分析（已实现：PcmAnalyzer → AudioFrame）
//! - [`lightstick`] — 音乐律动引擎（已实现：MusicRhythm → LightOutput）

pub mod audio;
pub mod lightstick;
pub mod protocol;
pub mod simple;
