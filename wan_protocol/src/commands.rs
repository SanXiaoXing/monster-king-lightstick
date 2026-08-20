//! 命令字表：9 种官方灯光效果 + 座位写 / 防伪指令 / 闪光特效。
//!
//! 对应：
//! - `chunk_2.appservice.js:123`（lighting 页 `functionalInstructions`）
//! - `chunk_3.appservice.js:152` / `chunk_8.appservice.js:129`（seatbind / glowdetail 的 `writeSeatInfo`）
//! - `appservice.app.js:845`（ble-manager `_verifyAntiFake` 指令构造）
//!
//! 自定义效果（如 `Flow`）不在本模块实现，见 [`crate::effects`]。

use crate::hexutil::{bytes_to_hex, dec2hex, hex_to_bytes, little_endian};
use crate::frame_seq_hex_le;

/// 9 种官方灯光效果 + 1 种自定义流光效果。
///
/// 官方效果对应 lighting 页 case 0~8（已在真机抓包验证）。
/// `Flow = 9` 仅为本项目本地效果枚举，不对应官方小程序的功能枚举；
/// 其命令体复用官方 0x40 帧结构，但字段语义为自定义（见 [`crate::effects::flow`]）。
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum LightingEffect {
    BlackScreen = 0,    // 黑屏
    ConstantlyOn = 1,   // 常亮
    Random = 2,         // 随机色
    FlashMob = 3,        // 快闪
    Blink = 4,          // 眨眼
    Breathe = 5,        // 呼吸
    Party = 6,          // 聚会（循环）
    Rainbow = 7,        // 彩虹（循环）
    StarrySky = 8,      // 星空
    /// 自定义流光（非官方枚举，仅本项目）。
    Flow = 9,
}

/// 座位绑定成功后的固定"闪光"特效包（已含帧序号与 CRC）。
/// 对应 seatbind/glowdetail 的 `showshanguan()`：`02000000100004ff020c06104c6a5e52`（16 字节）。
pub const LIGHT_FLASH_HEX: &str = "02000000100004ff020c06104c6a5e52";

/// 构造灯光效果命令体（帧序号之后、CRC 之前的部分）。
///
/// - `color_hex`：6 位 hex 颜色（如 `"ff8800"`），BlackScreen/Party/Rainbow/Starry 可传空。
/// - `seed`：循环效果的随机种子（Party/Rainbow/Starry 用，0..=255）。
/// - `rand_fill`：循环效果每组的随机字节来源（闭包返回 0..=255）。
///
/// 返回的 hex 即 `functionalInstructions` 里的 `o`（不含帧序号、不含 CRC）。
/// 调用方再用 [`crate::packet::build_packet`] 拼成完整包。
///
/// `ponytail:` Party/Rainbow/Starry 的组生成逻辑按 JS `reunionGroup`/`randompatternGroup`
/// 复刻；这些模式含随机量无法做固定向量测试，仅做结构校验。上线前建议用真机比对一帧输出。
pub fn lighting_command_body<F: FnMut() -> u8>(
    effect: LightingEffect,
    color_hex: &str,
    seed: u8,
    mut rand_fill: F,
) -> String {
    match effect {
        LightingEffect::BlackScreen => "00000000".to_string(),
        LightingEffect::ConstantlyOn | LightingEffect::Random => {
            format!("00{}", color_hex)
        }
        LightingEffect::FlashMob => format!("10{}020c0610", color_hex),
        LightingEffect::Blink => format!("20{}58029001", color_hex),
        LightingEffect::Breathe => format!("20{}c409f401", color_hex),
        LightingEffect::Party | LightingEffect::Rainbow => {
            // 头：40 + seed(1B) + ff；再追加 7 个 reunionGroup（每组 3 字节）
            let mut s = format!("40{}ff", dec2hex(seed as u64, 2));
            for _ in 0..7 {
                s.push_str(&reunion_group(&mut rand_fill));
            }
            s
        }
        LightingEffect::StarrySky => {
            let mut s = format!("40{}ff", dec2hex(seed as u64, 2));
            for _ in 0..7 {
                s.push_str(&randompattern_group(&mut rand_fill));
            }
            s
        }
        LightingEffect::Flow => {
            // 自定义流光：复用官方 0x40 帧结构，字段语义为自定义设计，
            // 实现与文档见 crate::effects::flow（实验性，待真机验证）。
            crate::effects::flow::flow_command_body(seed, color_hex)
        }
    }
}

/// reunionGroup：3 字节 = dim(1B) + 0x81(1B) + (o<<4 | n)(1B)。
/// `o` = floor(16*rand)（0..15）；`i` = floor(16*rand)（0..15）；`n` = i；
/// `dim` = 16*(15-i)+15；`mode` = parseInt("1000"+"0001",2) = 0x81。
fn reunion_group<F: FnMut() -> u8>(rand_fill: &mut F) -> String {
    let o = rand_fill() & 0x0F;
    let i = rand_fill() & 0x0F;
    let n = i;
    let dim = 16 * (15 - i as u16) + 15; // 15..255
    let third = (o << 4) | n;
    format!("{}81{:02x}", dec2hex(dim as u64, 2), third)
}

/// randompatternGroup：3 字节 = dim(1B) + mode(1B) + (0<<4 | configindex)(1B)。
/// `t` = floor(3*rand)+1（1..3）；mode = parseInt(e + "0001", 2)，e 由 t 决定。
fn randompattern_group<F: FnMut() -> u8>(rand_fill: &mut F) -> String {
    // t∈1..3，e(t=1)="0100", t=2="1000", t=3="1100"
    // 用 (rand*3)/256 近似 JS 的 floor(3*random)，避免取模偏差（0..255 % 3 分布不均）
    let t = ((rand_fill() as u16 * 3) / 256) as u8 + 1; // 1..3
    let e_bits: u8 = match t {
        1 => 0b0100_0001, // "0100"+"0001" = 0x41
        2 => 0b1000_0001, // 0x81
        3 => 0b1100_0001, // 0xC1
        _ => 0x41,
    };
    let i = rand_fill() & 0x0F;
    let dim = 16 * (15 - i as u16) + 15;
    let third = i; // "0" + n → 0x0n
    format!("{}{:02x}0{:x}", dec2hex(dim as u64, 2), e_bits, third)
}

/// 座位写入包（10 字节）。
///
/// 布局：`lightAreaName(1B) | x1(2B LE) | y1(2B LE) | FFFFFFFF(4B) | showNum(1B)`。
/// `None` 字段写 `0xFF`（与 JS 一致）。
pub fn seat_write_hex(light_area: Option<u8>, x1: u16, y1: u16, show_num: Option<u8>) -> String {
    let area = light_area.map(|v| dec2hex(v as u64, 2)).unwrap_or_else(|| "ff".to_string());
    let x = little_endian(&dec2hex(x1 as u64, 4));
    let y = little_endian(&dec2hex(y1 as u64, 4));
    let show = show_num.map(|v| dec2hex(v as u64, 2)).unwrap_or_else(|| "ff".to_string());
    format!("{}{}{}ffffffff{}", area, x, y, show)
}

/// 座位解绑包：10 字节全 0xFF。
pub fn seat_unbind_hex() -> &'static str {
    "ffffffffffffffffffff"
}

/// 防伪指令（39 字节）。
///
/// 布局：`帧序号(4B LE) | F0 1D F5 | MAC(6B LE) | 00 00 FF 00 00 00 | 随机挑战(16B) | CRC32(4B LE)`。
/// CRC32 覆盖前 35 字节（帧序号 ~ 随机挑战）。
///
/// 对应 `ble-manager._verifyAntiFake` 构造的 `fullInstr`。
pub fn antifake_instruction(seq: u32, mac_hex: &str, random_16: &[u8; 16]) -> Vec<u8> {
    let frame = frame_seq_hex_le(seq);
    // MAC：去冒号/横线、转小写、再 littleEndian
    let mac_clean: String = mac_hex
        .chars()
        .filter(|c| *c != ':' && *c != '-')
        .collect::<String>()
        .to_lowercase();
    let mac_le = little_endian(&mac_clean);
    let body_hex = format!(
        "{}f01df5{}0000ff000000{}",
        frame,
        mac_le,
        bytes_to_hex(random_16)
    );
    let crc_le = crate::crc32::crc32_hex_le_hex(&body_hex);
    hex_to_bytes(&format!("{}{}", body_hex, crc_le))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn black_screen_body() {
        assert_eq!(lighting_command_body(LightingEffect::BlackScreen, "", 0, || 0), "00000000");
    }

    #[test]
    fn constant_on_body() {
        assert_eq!(
            lighting_command_body(LightingEffect::ConstantlyOn, "ff8800", 0, || 0),
            "00ff8800"
        );
    }

    #[test]
    fn flash_mob_body() {
        assert_eq!(
            lighting_command_body(LightingEffect::FlashMob, "ff0000", 0, || 0),
            "10ff0000020c0610"
        );
    }

    #[test]
    fn blink_body() {
        assert_eq!(
            lighting_command_body(LightingEffect::Blink, "00ff00", 0, || 0),
            "2000ff0058029001"
        );
    }

    #[test]
    fn breathe_body() {
        assert_eq!(
            lighting_command_body(LightingEffect::Breathe, "0000ff", 0, || 0),
            "200000ffc409f401"
        );
    }

    #[test]
    fn seat_write_layout() {
        // area=0xA1, x=0x0102, y=0x0304, show=0x05
        // area="a1" | x="0102"→LE"0201" | y="0304"→LE"0403" | ffffffff | show="05"
        let s = seat_write_hex(Some(0xA1), 0x0102, 0x0304, Some(0x05));
        assert_eq!(s, "a102010403ffffffff05");
        assert_eq!(s.len(), 20); // 10 字节
    }

    #[test]
    fn seat_write_none_fields_become_ff() {
        // area=ff | x=0000 | y=0000 | ffffffff | show=ff → 20 hex 字符
        let s = seat_write_hex(None, 0, 0, None);
        assert_eq!(s, "ff00000000ffffffffff");
        assert_eq!(s.len(), 20);
    }

    #[test]
    fn seat_unbind_is_all_ff() {
        assert_eq!(seat_unbind_hex(), "ffffffffffffffffffff");
        assert_eq!(seat_unbind_hex().len(), 20);
    }

    #[test]
    fn light_flash_hex_is_16_bytes() {
        assert_eq!(LIGHT_FLASH_HEX, "02000000100004ff020c06104c6a5e52");
        assert_eq!(LIGHT_FLASH_HEX.len(), 32);
    }

    #[test]
    fn antifake_instruction_length_and_layout() {
        let mac = "aabbccddeeff";
        let mut rnd = [0u8; 16];
        for (i, b) in rnd.iter_mut().enumerate() {
            *b = i as u8;
        }
        let instr = antifake_instruction(1, mac, &rnd);
        // 4 + 3 + 6 + 6 + 16 + 4 = 39 字节
        assert_eq!(instr.len(), 39);
        // 帧序号 LE：seq=1 → 01 00 00 00
        assert_eq!(&instr[0..4], &[0x01, 0x00, 0x00, 0x00]);
        // 魔数 F0 1D F5
        assert_eq!(&instr[4..7], &[0xF0, 0x1D, 0xF5]);
        // MAC LE：aabbccddeeff → 反转字节对 → ffeeddccbbaa
        assert_eq!(&instr[7..13], &[0xff, 0xee, 0xdd, 0xcc, 0xbb, 0xaa]);
        // 固定 00 00 FF 00 00 00
        assert_eq!(&instr[13..19], &[0x00, 0x00, 0xFF, 0x00, 0x00, 0x00]);
        // 随机挑战 0..15
        assert_eq!(&instr[19..35], &(0..16).collect::<Vec<u8>>());
    }

    #[test]
    fn party_body_has_header_and_7_groups() {
        let body = lighting_command_body(LightingEffect::Party, "", 0x42, || 0);
        // 40 + 42 + ff (6 hex = 3 字节头) + 7 组 × 6 hex = 6 + 42 = 48 hex = 24 字节
        assert_eq!(body.len(), 48);
        assert!(body.starts_with("4042ff"));
    }

    #[test]
    fn flow_body_has_header_and_7_groups() {
        let body = lighting_command_body(LightingEffect::Flow, "ff0000", 0x42, || 0);
        // 40 + 42 + ff (6 hex) + 7 组 × 6 hex = 48 hex = 24 字节
        assert_eq!(body.len(), 48);
        assert!(body.starts_with("4042ff"));
    }
}
