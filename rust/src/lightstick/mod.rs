//! # lightstick — 荧光棒领域逻辑
//!
//! 设备状态机、效果编排、控制流程。编排 [`crate::bluetooth`] 与
//! [`crate::protocol`]，不直接拼字节。
//!
//! `ponytail:` 骨架模块，待实现。连续动画（聚会/星空/跑马灯的 100ms
//! 帧循环）在此层做，参考 Kotlin 版 continuousAnimJob 时序。

pub mod controller;
pub mod device;
pub mod effect;
