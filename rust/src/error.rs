//! # 统一错误类型
//!
//! 跨模块（bluetooth/protocol/lightstick/audio）共享的错误枚举。
//! AES 加解密等 API 已改为 `Result<T, WanError>` 上报（见 `api/protocol.rs`），
//! frb 已生成对应的 Dart 异常类型；其余骨架模块就绪后沿用同一签名。
//! 暂不引入 thiserror 依赖，用标准库手写 Display/Error，等用到再换。

use std::fmt;

/// 宝宝剑协议层统一错误。
#[derive(Debug)]
pub enum WanError {
    /// 协议封包/解包错误
    Protocol(String),
    /// BLE 扫描/连接/读写错误
    Bluetooth(String),
    /// 音频采集/分析错误
    Audio(String),
    /// 参数非法
    Invalid(String),
}

impl fmt::Display for WanError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            WanError::Protocol(m) => write!(f, "协议错误: {m}"),
            WanError::Bluetooth(m) => write!(f, "蓝牙错误: {m}"),
            WanError::Audio(m) => write!(f, "音频错误: {m}"),
            WanError::Invalid(m) => write!(f, "参数错误: {m}"),
        }
    }
}

impl std::error::Error for WanError {}
