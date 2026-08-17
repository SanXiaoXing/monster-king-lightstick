//! # 统一错误类型
//!
//! 跨模块（bluetooth/protocol/lightstick/audio）共享的错误枚举。
//! 当前 frb API 仍以"吞错"返回默认值（见 `api/protocol.rs` 注释），
//! 上线需要向 Flutter 上报错误时，把签名改为 `Result<T, WanError>` 即可。
//!
//! `ponytail:` 未在 api/ 启用；启用前需在 frb 端注册 Error 类型。
//! 暂不引入 thiserror 依赖，用标准库手写 Display/Error，等用到再换。

use std::fmt;

/// 腕带协议层统一错误。
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
