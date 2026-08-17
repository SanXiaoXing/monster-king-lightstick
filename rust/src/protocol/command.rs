//! 命令字表：9 种灯光效果 / 座位写 / 防伪指令 / 闪光特效。
//! 实现在 wan_protocol::commands。

pub use wan_protocol::commands::{
    antifake_instruction, lighting_command_body, seat_unbind_hex, seat_write_hex,
    LightingEffect, LIGHT_FLASH_HEX,
};
