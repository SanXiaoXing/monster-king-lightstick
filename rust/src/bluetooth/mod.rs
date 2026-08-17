//! # bluetooth — 底层设备通信
//!
//! BLE 扫描 / 连接 / 特征值读写。上承 [`crate::lightstick`]（领域逻辑），
//! 下接系统蓝牙栈。
//!
//! `ponytail:` 骨架模块，全部待实现。接入时参考
//! glowstick-app-main（Kotlin 原生 BleManager/BleScanner 的已验证时序：
//! FFE0 服务 / FFE1 写 / FFE2 notify / MTU 247 / 30ms 写节流 / 3s 自动重连）。

pub mod characteristic;
pub mod connection;
pub mod scanner;
