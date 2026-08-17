//! BLE 扫描（待实现）。
//!
//! 职责：按 serviceUuid（FFE0 / AC1F3D*）过滤广播、解析设备型号与版本、
//! 去重、RSSI 上报。参考 glowstick-app-main/ble/BleScanner.kt 的过滤规则
//! （bytes[4..8] 型号、bytes[8..14] 版本、0000/FFFF 无效型号剔除）。
