//! Flutter Rust Bridge 适配层（协议构造）。
//!
//! 将 [`crate::protocol`]（wan_protocol 门面）中当前 App 实际用到的 API
//! 包装为 frb 友好签名。其余协议能力（AES / Ed25519 / 座位 / 广播烧录 /
//! OTA 等）仍完整保留在 [`wan_protocol`] crate（61 测试验证资产），
//! 但不再暴露 FRB 导出，避免生成代码膨胀；需要时按需补回薄包装。

/// 9 种灯光效果。frb 生成对应 Dart 枚举。
#[derive(Clone, Copy, Debug)]
pub enum LightingEffect {
    BlackScreen,  // 黑屏
    ConstantlyOn, // 常亮
    Random,       // 随机色
    FlashMob,     // 快闪
    Blink,        // 眨眼
    Breathe,      // 呼吸
    Party,        // 聚会
    Rainbow,      // 彩虹
    StarrySky,    // 星空
}

/// hex 字符串 → 字节。
pub fn hex_to_bytes(hex: String) -> Vec<u8> {
    crate::protocol::hex_to_bytes(&hex)
}

/// BLE 命令包：`[帧序号 4B LE][命令体 N B][CRC32 4B LE]`。
pub fn build_packet(seq: u32, command_body_hex: String) -> String {
    crate::protocol::build_packet(seq, &command_body_hex)
}

/// 灯光效果命令体（随机源为 Party/Rainbow/Starry 等效果的 seed）。
pub fn lighting_command_body(effect: LightingEffect, color_hex: String, seed: u8) -> String {
    let e = match effect {
        LightingEffect::BlackScreen => crate::protocol::commands::LightingEffect::BlackScreen,
        LightingEffect::ConstantlyOn => crate::protocol::commands::LightingEffect::ConstantlyOn,
        LightingEffect::Random => crate::protocol::commands::LightingEffect::Random,
        LightingEffect::FlashMob => crate::protocol::commands::LightingEffect::FlashMob,
        LightingEffect::Blink => crate::protocol::commands::LightingEffect::Blink,
        LightingEffect::Breathe => crate::protocol::commands::LightingEffect::Breathe,
        LightingEffect::Party => crate::protocol::commands::LightingEffect::Party,
        LightingEffect::Rainbow => crate::protocol::commands::LightingEffect::Rainbow,
        LightingEffect::StarrySky => crate::protocol::commands::LightingEffect::StarrySky,
    };
    crate::protocol::lighting_command_body(e, &color_hex, seed, rand::random::<u8>)
}
