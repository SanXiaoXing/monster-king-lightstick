//! 效果编排：音乐律动引擎（音频帧 → 荧光棒灯效）。
//!
//! 对齐 `docs/design/music.md` 音乐调光设置要求：
//! - **亮度 = 音量 × 灵敏度**（文档：`255 * r * f`，f 为灵敏度滑杆）；
//! - **颜色循环**：文档内置 15 色色板（`colorlist`）每 20 条指令（400ms）换色；
//!   原色板在反编译 JS 中无法复原，用 15 色彩虹近似；
//!   本引擎按 `color_interval_frames` 帧推进（60ms 下发节流 × 7 ≈ 420ms ≈ 文档 400ms）。
//!
//! 模式（UI 四个模式按钮）：
//! - 单色律动：固定 base 色，亮度随音量；
//! - 七彩律动：15 色板循环，亮度随音量；
//! - 强烈 / 柔和：七彩 + 亮度增益 1.35 / 0.65（对齐可视化 _gain）。

/// 律动模式。
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum RhythmMode {
    /// 单色律动：固定 base 色。
    Single,
    /// 七彩律动：15 色板循环。
    Rainbow,
    /// 强烈：七彩 + 亮度增益。
    Strong,
    /// 柔和：七彩 + 亮度压缩。
    Soft,
}

impl RhythmMode {
    /// 亮度增益（强烈放大、柔和压缩，与可视化 _gain 一致）。
    pub fn gain(self) -> f64 {
        match self {
            RhythmMode::Strong => 1.35,
            RhythmMode::Soft => 0.65,
            _ => 1.0,
        }
    }

    /// 是否循环换色（单色固定 base 色）。
    pub fn cycles_color(self) -> bool {
        !matches!(self, RhythmMode::Single)
    }
}

/// 一帧律动输出：RGB 颜色（3 字节）+ 亮度（0..1，随音量变化）。
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct LightOutput {
    pub rgb: [u8; 3],
    pub brightness: f64,
}

/// 15 色彩虹色板（文档 `colorlist` 无法复原，彩虹近似：
/// 红→橙→黄→绿→青→蓝→紫→品红，覆盖整个色相环）。
const PALETTE: [[u8; 3]; 15] = [
    [0xFF, 0x00, 0x00], // 红
    [0xFF, 0x55, 0x00], // 橙红
    [0xFF, 0xAA, 0x00], // 橙
    [0xFF, 0xE0, 0x00], // 金黄
    [0xC0, 0xFF, 0x00], // 黄绿
    [0x55, 0xFF, 0x00], // 草绿
    [0x00, 0xFF, 0x55], // 青绿
    [0x00, 0xFF, 0xAA], // 青
    [0x00, 0xFF, 0xFF], // 蓝青
    [0x00, 0xAA, 0xFF], // 天蓝
    [0x00, 0x55, 0xFF], // 蓝
    [0x40, 0x00, 0xFF], // 蓝紫
    [0xAA, 0x00, 0xFF], // 紫
    [0xFF, 0x00, 0xFF], // 品红
    [0xFF, 0x00, 0x80], // 玫红
];

/// 音乐律动引擎：音频帧 → 荧光棒灯效。
///
/// 状态：模式 / 灵敏度 / 单色 base 色 / 色板游标。`next` 每次下发调用一次。
pub struct MusicRhythm {
    mode: RhythmMode,
    sensitivity: f64,
    base_rgb: [u8; 3],
    palette_index: usize,
    frames_since_color: u32,
    /// 换色帧间隔（60ms 下发节流 × 7 ≈ 420ms ≈ 文档 400ms 换色）。
    color_interval_frames: u32,
}

impl MusicRhythm {
    /// 默认：单色律动、灵敏度 60%、base 色 = 主题强调色（iOS 蓝）。
    pub fn new() -> Self {
        Self {
            mode: RhythmMode::Single,
            sensitivity: 0.6,
            base_rgb: [0x0A, 0x84, 0xFF],
            palette_index: 0,
            frames_since_color: 0,
            color_interval_frames: 7,
        }
    }

    pub fn set_mode(&mut self, mode: RhythmMode) {
        self.mode = mode;
    }

    /// 灵敏度 0..1（文档：亮度 = 音量 × 灵敏度滑杆）。
    pub fn set_sensitivity(&mut self, v: f64) {
        self.sensitivity = v.clamp(0.0, 1.0);
    }

    /// 单色律动的固定颜色。
    pub fn set_base_color(&mut self, rgb: [u8; 3]) {
        self.base_rgb = rgb;
    }

    /// 由音量（0..1）推进一步，返回应下发的颜色与亮度。
    ///
    /// 只依赖音量：引擎按文档映射亮度 = 音量 × 灵敏度，颜色按帧循环，
    /// 频带/节拍等可视化数据不跨桥传入。
    pub fn next(&mut self, volume: f64) -> LightOutput {
        // 颜色：七彩/强烈/柔和按帧循环色板，单色固定 base 色。
        // 先取色再推进：每个颜色持续恰 color_interval_frames 帧（先推进会让
        // 首个颜色少一帧）。
        let rgb = if self.mode.cycles_color() {
            let color = PALETTE[self.palette_index];
            self.frames_since_color += 1;
            if self.frames_since_color >= self.color_interval_frames {
                self.frames_since_color = 0;
                self.palette_index = (self.palette_index + 1) % PALETTE.len();
            }
            color
        } else {
            self.base_rgb
        };

        // 亮度 = 音量 × 灵敏度 × 模式增益（静音帧音量=0 → 熄灭）
        let brightness = (volume * self.sensitivity * self.mode.gain()).clamp(0.0, 1.0);

        LightOutput { rgb, brightness }
    }
}

impl Default for MusicRhythm {
    fn default() -> Self {
        Self::new()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn brightness_is_volume_times_sensitivity() {
        let mut r = MusicRhythm::new();
        r.set_sensitivity(0.5);
        let out = r.next(0.8);
        assert!((out.brightness - 0.4).abs() < 1e-9);
    }

    #[test]
    fn silence_is_off() {
        let mut r = MusicRhythm::new();
        r.set_sensitivity(1.0);
        assert_eq!(r.next(0.0).brightness, 0.0);
    }

    #[test]
    fn zero_sensitivity_is_off() {
        let mut r = MusicRhythm::new();
        r.set_sensitivity(0.0);
        assert_eq!(r.next(1.0).brightness, 0.0);
    }

    #[test]
    fn brightness_clamped_to_one() {
        let mut r = MusicRhythm::new();
        r.set_sensitivity(1.0);
        r.set_mode(RhythmMode::Strong);
        assert_eq!(r.next(1.0).brightness, 1.0);
    }

    #[test]
    fn strong_soft_gain() {
        let mut r = MusicRhythm::new();
        r.set_sensitivity(1.0);
        r.set_mode(RhythmMode::Strong);
        assert!((r.next(0.5).brightness - 0.675).abs() < 1e-9);
        r.set_mode(RhythmMode::Soft);
        assert!((r.next(0.5).brightness - 0.325).abs() < 1e-9);
    }

    #[test]
    fn single_mode_keeps_base_color() {
        let mut r = MusicRhythm::new();
        r.set_mode(RhythmMode::Single);
        r.set_base_color([0x12, 0x34, 0x56]);
        for _ in 0..30 {
            let out = r.next(0.5);
            assert_eq!(out.rgb, [0x12, 0x34, 0x56]);
        }
    }

    #[test]
    fn rainbow_cycles_palette_every_interval() {
        let mut r = MusicRhythm::new();
        r.set_mode(RhythmMode::Rainbow);
        r.color_interval_frames = 2;
        // interval=2：每色持续 2 帧，15 色一周 = 30 帧
        let outs: Vec<_> = (0..32).map(|_| r.next(0.5).rgb).collect();
        // 前 2 帧同色（红），第 3 帧换色
        assert_eq!(outs[0], outs[1]);
        assert_ne!(outs[0], outs[2]);
        // 一周内遍历完整 15 色
        let mut seen = Vec::new();
        for o in &outs[..30] {
            if !seen.contains(o) {
                seen.push(*o);
            }
        }
        assert_eq!(seen.len(), 15, "应遍历完整 15 色色板");
        // 第 31 帧回到起点（红），进入下一圈
        assert_eq!(outs[30], outs[0]);
    }
}
