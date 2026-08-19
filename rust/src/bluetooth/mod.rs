//! # bluetooth — 底层设备通信
//!
//! BLE 扫描 / 连接 / 特征值读写。当前 App 的 BLE 由 Flutter 侧
//! flutter_blue_plus 原生实现（features/device/data/device_repository.dart），
//! 本模块暂不落地；需要迁回 Rust 时按 glowstick-app-main 的真机时序实现
//! （FFE0 服务 / FFE1 写 / FFE2 notify / MTU 247 / 30ms 写节流）。
