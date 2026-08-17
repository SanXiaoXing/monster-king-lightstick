//! 编码扩展点。
//!
//! 现有编码（封包/命令体/广播/OTA）全部由 wan_protocol 提供并通过
//! packet.rs / command.rs 透传；此文件预留给 wan_protocol 之外的
//! 新编码格式（如新固件协议变体），避免污染已验证 crate。
