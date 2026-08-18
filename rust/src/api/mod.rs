//! FRB 边界层：Flutter 通过这里调用 Rust，不直接接触内部模块。
//!
//! - [`protocol`] — 协议构造（已实现，25 个包装函数）
//! - [`simple`] — frb 初始化钩子（init_app）
//! - [`bluetooth`] / [`lightstick`] / [`audio`] — 待实现的三个能力入口

pub mod audio;
pub mod bluetooth;
pub mod lightstick;
pub mod protocol;
pub mod simple;
