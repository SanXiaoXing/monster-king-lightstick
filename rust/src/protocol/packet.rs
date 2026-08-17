//! BLE 命令包封包：`[帧序号 4B LE][命令体 N B][CRC32 4B LE]`。
//! 实现在 wan_protocol::packet（真机金标准验证过）。

pub use wan_protocol::packet::{build_packet, build_packet_bytes};
