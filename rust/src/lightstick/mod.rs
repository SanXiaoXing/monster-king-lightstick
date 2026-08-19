//! # lightstick — 荧光棒领域逻辑
//!
//! 已实现：音乐律动引擎（[`effect`]，对齐 docs/design/music.md）。
//! 设备状态机 / 连接编排暂未落地（当前由 Flutter 侧 DeviceViewModel 编排）；
//! 需要时在此实现，编排 [`crate::bluetooth`] 与 [`crate::protocol`]。

pub mod effect;
