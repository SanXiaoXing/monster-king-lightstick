//! FRB 入口：荧光棒领域（音乐律动引擎）。
//!
//! 暴露音乐律动引擎给 Flutter：音量 + 律动设置 → 下一帧灯效（RGB + 亮度）。
//! 实现逻辑在 lightstick/effect.rs（对齐 docs/design/music.md 音乐调光设置），
//! api 层只做签名转换。

use crate::lightstick::effect::{LightOutput as InnerOutput, MusicRhythm as InnerRhythm};

/// 一帧律动输出：RGB 颜色（3 字节）+ 亮度（0..1，随音量变化）。
#[derive(Clone, Debug)]
pub struct LightOutput {
    pub rgb: Vec<u8>,
    pub brightness: f64,
}

/// 音乐律动引擎（Rust 侧持有模式/色板游标状态，opaque 不跨桥序列化）。
#[flutter_rust_bridge::frb(opaque)]
pub struct MusicRhythm {
    inner: InnerRhythm,
}

impl MusicRhythm {
    pub fn create() -> MusicRhythm {
        MusicRhythm {
            inner: InnerRhythm::new(),
        }
    }

    pub fn set_mode(&mut self, mode: crate::lightstick::effect::RhythmMode) {
        self.inner.set_mode(mode);
    }

    /// 灵敏度 0..1（亮度 = 音量 × 灵敏度）。
    pub fn set_sensitivity(&mut self, v: f64) {
        self.inner.set_sensitivity(v);
    }

    /// 单色律动的固定颜色（RGB 3 字节）。
    pub fn set_base_color(&mut self, rgb: Vec<u8>) {
        let mut c = [0u8; 3];
        let n = rgb.len().min(3);
        c[..n].copy_from_slice(&rgb[..n]);
        self.inner.set_base_color(c);
    }

    /// 由音量（0..1）推进一步，返回应下发的颜色与亮度。
    pub fn next(&mut self, volume: f64) -> LightOutput {
        let out: InnerOutput = self.inner.next(volume);
        LightOutput {
            rgb: out.rgb.to_vec(),
            brightness: out.brightness,
        }
    }
}
