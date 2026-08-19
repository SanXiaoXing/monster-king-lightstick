//! 音频分析器：PCM16 小端字节流 → 音量级 + 频带能量 + 低频/高频 + 节拍。
//!
//! 从 Dart 侧 `lib/features/audio/domain/audio_analysis.dart` 精确移植
//! （原实现是 Rust audio/ 骨架就绪前的 Dart 落地，现按分层铁律回归 Rust）。
//!
//! 输入 PCM16 小端字节流，环形缓冲 + 50% 重叠滑窗 + 汉宁窗 + radix-2 FFT，
//! 输出音量级与对数频带能量，驱动律动 UI 与荧光棒灯效。
//!
//! 实时性设计（同 Dart 原版）：
//! - hop = window_size/2（50% 重叠）：1024@44.1kHz 时帧周期 ≈ 11.6ms（~86fps）；
//! - 汉宁窗 / FFT 位反转表 / 频带 bin 边界全部构造时预计算，帧内零三角函数；
//! - 环形缓冲避免逐样本搬移；FFT/频带工作缓冲复用，帧内零分配；
//! - 衰减类常数按帧周期折算，帧率变化后墙钟行为不变。

use std::f64::consts::PI;

/// 一帧音频分析结果：音量级 + 频带能量 + 低频/高频 + 节拍，驱动律动 UI。
#[derive(Clone, Debug, PartialEq)]
pub struct AudioFrame {
    /// 音量级 0..1（RMS + 动态峰值归一化）。
    pub volume: f64,
    /// 频带能量 0..1（对数频带，长度 = [`PcmAnalyzer::band_count`]）。
    pub bands: Vec<f64>,
    /// 低频能量 0..1（约 40~230Hz，驱动圆环半径的慢速大位移）。
    pub bass: f64,
    /// 高频能量 0..1（约 4kHz+，驱动细密快速振荡）。
    pub treble: f64,
    /// 强拍标记：低频能量突增时置 true（触发径向脉冲与粒子爆发）。
    pub is_beat: bool,
}

/// PCM16 分析器：环形缓冲 + 50% 重叠滑窗 + 汉宁窗 + radix-2 FFT。
///
/// `push` 逐 chunk 喂入字节流，返回本次新产生的全部帧（可能多帧，可能为空）。
/// 采集 chunk 长度不固定：50% 重叠下一块大 chunk 可能覆盖多个帧移，
/// 逐帧全部返回，保证分析帧率稳定在 ~86fps，不被 chunk 大小稀释。
pub struct PcmAnalyzer {
    /// 频带数（与频谱柱数一致）。
    pub band_count: usize,
    /// FFT 窗口采样数（1024 @44.1kHz ≈ 23ms 窗长）。
    pub window_size: usize,
    /// 采样率（record 采集配置需一致）。
    pub sample_rate: usize,
    /// 帧移（50% 重叠 → 帧周期 ≈ 11.6ms，响应延迟减半）。
    pub hop_size: usize,
    /// 频带能量时域平滑系数（0..1，越大越跟手；帧率 ~86fps 下 0.5 ≈ 12ms 时间常数）。
    pub smoothing: f64,

    // ── 采样缓冲：环形，避免每帧搬移 ──
    ring: Vec<f64>,
    write: usize,       // 下一个写入位置（缓冲满时即最老样本位置）
    filled: usize,      // 已填充样本数（≤ window_size）
    since_frame: usize, // 距上一帧的样本数（满 hop_size 出一帧）

    // 跨 chunk 的奇数字节携带（PCM16 单样本 2 字节，chunk 长度可能为奇数）
    pending_byte: Option<u8>,

    // ── 预计算表 ──
    hann: Vec<f64>,
    bit_rev: Vec<usize>,
    band_lo: Vec<usize>,
    band_hi: Vec<usize>,

    // ── FFT 工作缓冲（复用，帧内零分配）──
    re: Vec<f64>,
    im: Vec<f64>,
    mag: Vec<f64>,

    // ── 频带工作缓冲（复用；输出帧另分配新 Vec 以免被下一帧覆写）──
    raw_bands: Vec<f64>,
    prev_bands: Option<Vec<f64>>,

    // 节拍检测状态：低频能量基线（指数平滑）+ 冷却帧计数
    bass_baseline: f64,
    beat_cooldown: usize,
    beat_cooldown_frames: usize,

    // 动态峰值（参考实现 strength/maxStrength：当前值 / 历史峰值，
    // 任意音量下都有完整动态范围，避免固定归一化导致的"要么 0 要么顶满"）
    peak_bands: Vec<f64>,
    peak_volume: f64,
    peak_decay_per_frame: f64,
    peak_decay_fast_per_frame: f64,
    baseline_decay_per_frame: f64,
}

/// 绝对噪声门限（≈ -42dBFS）：RMS 低于此值判静音，输出全零帧。
///
/// 动态峰值归一化会把环境底噪也放大成"有声音"，需要绝对电平兜底；
/// 但门限过高会把小音量播放的音乐一并误杀，故取较低值，
/// 并在 [`NOISE_GATE`, `NOISE_GATE×3`] 区间做软过渡渐隐。
const NOISE_GATE: f64 = 0.008;

/// 峰值衰减标定值（按 23ms 帧周期，实际每帧系数按帧周期折算）：
/// - 慢速 0.992（约 1.9 秒减半）：电平接近峰值时用，音乐内部起伏不被吃掉；
/// - 快速 0.98（约 0.8 秒减半）：电平远低于峰值（<30%）时用，
///   响→静切换后安静段落 1~2 秒内重新获得大部分动态范围。
const PEAK_DECAY_REF: f64 = 0.992;
const PEAK_DECAY_FAST_REF: f64 = 0.98;

impl PcmAnalyzer {
    /// 构造分析器（window_size 须为 2 的幂）。
    pub fn new(band_count: usize, window_size: usize, sample_rate: usize) -> Self {
        assert!(window_size.is_power_of_two(), "window_size 必须为 2 的幂");
        let hop_size = window_size / 2;
        let half = window_size / 2;

        // 预计算对数频带的 FFT bin 边界（40Hz ~ Nyquist）
        let f_min = 40.0f64;
        let f_max = sample_rate as f64 / 2.0;
        let ratio = f_max / f_min;
        let mut band_lo = Vec::with_capacity(band_count);
        let mut band_hi = Vec::with_capacity(band_count);
        for b in 0..band_count {
            let f_lo = f_min * ratio.powf(b as f64 / band_count as f64);
            let f_hi = f_min * ratio.powf((b + 1) as f64 / band_count as f64);
            let lo = ((f_lo / sample_rate as f64) * window_size as f64).floor() as usize;
            let hi = ((f_hi / sample_rate as f64) * window_size as f64).ceil() as usize;
            band_lo.push(lo.clamp(1, half - 1));
            band_hi.push(hi.clamp(1, half - 1));
        }

        // 衰减常数折算：原值按 23ms 帧周期标定，帧周期变为 hop 后取幂保持墙钟一致
        let frame_ratio = hop_size as f64 / window_size as f64; // 0.5
        let peak_decay_per_frame = PEAK_DECAY_REF.powf(frame_ratio);
        let peak_decay_fast_per_frame = PEAK_DECAY_FAST_REF.powf(frame_ratio);
        let baseline_decay_per_frame = 0.9f64.powf(frame_ratio);
        // 强拍冷却约 180ms（快速鼓点也能跟上），按帧周期折算为帧数
        let beat_cooldown_frames =
            ((0.18 * sample_rate as f64 / hop_size as f64).round() as usize).max(1);

        Self {
            band_count,
            window_size,
            sample_rate,
            hop_size,
            smoothing: 0.5,
            ring: vec![0.0; window_size],
            write: 0,
            filled: 0,
            since_frame: 0,
            pending_byte: None,
            hann: build_hann(window_size),
            bit_rev: build_bit_rev(window_size),
            band_lo,
            band_hi,
            re: vec![0.0; window_size],
            im: vec![0.0; window_size],
            mag: vec![0.0; half],
            raw_bands: vec![0.0; band_count],
            prev_bands: None,
            bass_baseline: 0.0,
            beat_cooldown: 0,
            beat_cooldown_frames,
            peak_bands: vec![0.0; band_count],
            peak_volume: 0.0,
            peak_decay_per_frame,
            peak_decay_fast_per_frame,
            baseline_decay_per_frame,
        }
    }

    /// 喂入 PCM16 小端字节流；返回本次新产生的全部帧。
    pub fn push(&mut self, pcm: &[u8]) -> Vec<AudioFrame> {
        let mut frames = Vec::new();
        let mut offset = 0;

        // 奇数字节携带：上一 chunk 遗留的首字节 + 本 chunk 首字节拼成一个样本
        if let Some(p) = self.pending_byte.take() {
            if !pcm.is_empty() {
                let v = (((p as i32) | ((pcm[0] as i32) << 8)) as i16) as f64;
                offset = 1;
                self.push_sample(v, &mut frames);
            }
        }
        // 主体：按 i16 小端成对读取
        while offset + 1 < pcm.len() {
            let v = i16::from_le_bytes([pcm[offset], pcm[offset + 1]]) as f64;
            offset += 2;
            self.push_sample(v, &mut frames);
        }
        if offset < pcm.len() {
            self.pending_byte = Some(pcm[offset]);
        }
        frames
    }

    fn push_sample(&mut self, v: f64, frames: &mut Vec<AudioFrame>) {
        self.ring[self.write] = v;
        self.write = (self.write + 1) % self.window_size;
        if self.filled < self.window_size {
            self.filled += 1;
        }
        self.since_frame += 1;
        if self.since_frame >= self.hop_size && self.filled >= self.window_size {
            self.since_frame = 0;
            frames.push(self.analyze());
        }
    }

    /// 对当前窗口（最老→最新）做一帧完整分析。
    fn analyze(&mut self) -> AudioFrame {
        // 线性化环形缓冲 + 汉宁窗 + RMS，一趟完成（缓冲满时 write 即最老样本）
        let mut sum_sq = 0.0;
        for i in 0..self.window_size {
            let s = self.ring[(self.write + i) % self.window_size];
            sum_sq += s * s;
            self.re[i] = s * self.hann[i];
            self.im[i] = 0.0;
        }
        let rms = (sum_sq / self.window_size as f64).sqrt() / 32768.0;

        // 绝对噪声门限：环境底噪直接判静音，输出全零帧并衰减峰值
        if rms < NOISE_GATE {
            self.peak_volume *= self.peak_decay_per_frame;
            for p in self.peak_bands.iter_mut() {
                *p *= self.peak_decay_per_frame;
            }
            self.bass_baseline *= self.baseline_decay_per_frame;
            self.prev_bands = None;
            return AudioFrame {
                volume: 0.0,
                bands: vec![0.0; self.band_count],
                bass: 0.0,
                treble: 0.0,
                is_beat: false,
            };
        }

        // 门限软过渡：[NOISE_GATE, NOISE_GATE×3] 内输出按 0→1 渐显，
        // 小音量音乐不被一刀切，临界电平也不会全有/全无闪烁
        let gate_fade = ((rms - NOISE_GATE) / (NOISE_GATE * 2.0)).clamp(0.0, 1.0);

        fft(&mut self.re, &mut self.im, &self.bit_rev);

        // 幅度谱（取前 N/2 个 bin）
        let half = self.window_size / 2;
        for i in 0..half {
            self.mag[i] = (self.re[i] * self.re[i] + self.im[i] * self.im[i]).sqrt();
        }

        // 对数频带聚合（边界已预计算）——保留原始平均幅度，不做固定缩放
        for b in 0..self.band_count {
            let lo = self.band_lo[b];
            let hi = self.band_hi[b];
            let mut sum = 0.0;
            for k in lo..hi {
                sum += self.mag[k];
            }
            self.raw_bands[b] = sum / (hi - lo).max(1) as f64;
        }

        // 动态峰值归一化（参考实现 strength/maxStrength：当前值 / 历史峰值）。
        // 峰值上升即时跟随、下降指数衰减，任意音量下都有完整动态范围。
        let mut bands = vec![0.0; self.band_count];
        for b in 0..self.band_count {
            let raw = self.raw_bands[b];
            let p = self.peak_bands[b];
            // 电平远低于峰值时快速释放，安静段落尽快恢复动态范围
            let decay = if raw < p * 0.3 {
                self.peak_decay_fast_per_frame
            } else {
                self.peak_decay_per_frame
            };
            let peak = if raw > p { raw } else { p * decay };
            self.peak_bands[b] = peak;
            bands[b] = (raw / peak.max(1e-9)).clamp(0.0, 1.0);
        }

        // 音量同样按动态峰值归一化（同样的双速释放）
        self.peak_volume = if rms > self.peak_volume {
            rms
        } else {
            self.peak_volume
                * if rms < self.peak_volume * 0.3 {
                    self.peak_decay_fast_per_frame
                } else {
                    self.peak_decay_per_frame
                }
        };
        let mut volume = (rms / self.peak_volume.max(1e-9)).clamp(0.0, 1.0);

        // 门限软过渡作用于归一化结果：近门限的低电平信号（含底噪）不会被
        // 峰值归一化放大成"满格信号"
        if gate_fade < 1.0 {
            volume *= gate_fade;
            for b in bands.iter_mut() {
                *b *= gate_fade;
            }
        }

        // 与上一帧平滑，避免柱子跳动
        if let Some(prev) = &self.prev_bands {
            for b in 0..self.band_count {
                bands[b] = prev[b] * (1.0 - self.smoothing) + bands[b] * self.smoothing;
            }
        }
        self.prev_bands = Some(bands.clone());

        // 低频能量：前 8 个频带（约 40~243Hz）；高频能量：后 8 个频带（约 4kHz~22kHz）
        let bass = mean(&bands, 0, 8);
        let treble = mean(&bands, self.band_count.saturating_sub(8), self.band_count);

        // 强拍检测：用原始（未归一化）低频突增，避免归一化后基线失真
        let raw_bass = mean(&self.raw_bands, 0, 8);
        self.bass_baseline = if self.bass_baseline == 0.0 {
            raw_bass
        } else {
            self.bass_baseline * self.baseline_decay_per_frame
                + raw_bass * (1.0 - self.baseline_decay_per_frame)
        };
        let is_beat = self.beat_cooldown <= 0 && raw_bass > self.bass_baseline * 1.4 + 0.02;
        if is_beat {
            // 触发后重置基线，避免连续触发；冷却约 180ms
            self.bass_baseline = raw_bass;
            self.beat_cooldown = self.beat_cooldown_frames;
        } else if self.beat_cooldown > 0 {
            self.beat_cooldown -= 1;
        }

        AudioFrame {
            volume,
            bands,
            bass,
            treble,
            is_beat,
        }
    }
}

/// 频带均值（[from, to)）。
fn mean(v: &[f64], from: usize, to: usize) -> f64 {
    let mut s = 0.0;
    for x in v.iter().take(to).skip(from) {
        s += x;
    }
    s / (to - from).max(1) as f64
}

fn build_hann(n: usize) -> Vec<f64> {
    (0..n)
        .map(|i| 0.5 - 0.5 * (2.0 * PI * i as f64 / (n - 1) as f64).cos())
        .collect()
}

fn build_bit_rev(n: usize) -> Vec<usize> {
    let mut table = vec![0usize; n];
    let mut j = 0usize;
    for i in 1..n {
        let mut bit = n >> 1;
        while j & bit != 0 {
            j ^= bit;
            bit >>= 1;
        }
        j ^= bit;
        table[i] = j;
    }
    table
}

/// 迭代 radix-2 FFT（原地，n 须为 2 的幂；位反转查表，免每帧重排计算）。
fn fft(re: &mut [f64], im: &mut [f64], bit_rev: &[usize]) {
    let n = re.len();
    for i in 1..n {
        let j = bit_rev[i];
        if i < j {
            re.swap(i, j);
            im.swap(i, j);
        }
    }
    let mut len = 2;
    while len <= n {
        let ang = -2.0 * PI / len as f64;
        let w_re = ang.cos();
        let w_im = ang.sin();
        let half_len = len >> 1;
        let mut i = 0;
        while i < n {
            let mut cur_re = 1.0;
            let mut cur_im = 0.0;
            for k in 0..half_len {
                let u_re = re[i + k];
                let u_im = im[i + k];
                let v_re = re[i + k + half_len] * cur_re - im[i + k + half_len] * cur_im;
                let v_im = re[i + k + half_len] * cur_im + im[i + k + half_len] * cur_re;
                re[i + k] = u_re + v_re;
                im[i + k] = u_im + v_im;
                re[i + k + half_len] = u_re - v_re;
                im[i + k + half_len] = u_im - v_im;
                let n_re = cur_re * w_re - cur_im * w_im;
                cur_im = cur_re * w_im + cur_im * w_re;
                cur_re = n_re;
            }
            i += len;
        }
        len <<= 1;
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn sine_bytes(freq: f64, amplitude: f64, samples: usize, sample_rate: usize) -> Vec<u8> {
        let mut pcm = Vec::with_capacity(samples * 2);
        for i in 0..samples {
            let s = (amplitude * 32767.0 * (2.0 * PI * freq * i as f64 / sample_rate as f64).sin())
                as i16;
            pcm.extend_from_slice(&s.to_le_bytes());
        }
        pcm
    }

    #[test]
    fn silence_yields_zero_frames() {
        let mut a = PcmAnalyzer::new(28, 1024, 44100);
        let frames = a.push(&vec![0u8; 1024 * 4]);
        assert!(!frames.is_empty());
        for f in frames {
            assert_eq!(f.volume, 0.0);
            assert!(f.bands.iter().all(|&b| b == 0.0));
            assert_eq!(f.bass, 0.0);
            assert_eq!(f.treble, 0.0);
            assert!(!f.is_beat);
        }
    }

    #[test]
    fn odd_byte_chunks_preserve_stream() {
        let pcm = sine_bytes(440.0, 0.5, 2048, 44100);
        let mut a = PcmAnalyzer::new(28, 1024, 44100);
        // 首 chunk 只给 1 字节（奇数），跨 chunk 携带
        let frames_split = {
            let mut f1 = a.push(&pcm[..1]);
            f1.extend(a.push(&pcm[1..]));
            f1
        };
        let mut b = PcmAnalyzer::new(28, 1024, 44100);
        let frames_full = b.push(&pcm);
        assert_eq!(frames_split.len(), frames_full.len());
    }

    #[test]
    fn sine_wave_produces_volume_and_band_energy() {
        let mut a = PcmAnalyzer::new(28, 1024, 44100);
        let pcm = sine_bytes(440.0, 0.5, 4096, 44100);
        let frames = a.push(&pcm);
        assert!(frames.len() >= 4);
        assert!(frames.iter().any(|f| f.volume > 0.1));
        // 440Hz 在对数频带中段（约 band 10），该频带应显著高于 0
        assert!(frames.iter().any(|f| f.bands.iter().any(|&b| b > 0.3)));
    }

    #[test]
    fn bass_burst_triggers_beat() {
        let mut a = PcmAnalyzer::new(28, 1024, 44100);
        // 先低音量 100Hz 建立低基线（100Hz 落在低频区前 8 个频带内）
        let quiet = sine_bytes(100.0, 0.05, 2048, 44100);
        a.push(&quiet);
        // 再大音量 100Hz → 低频突增 → 触发一次强拍（随后基线重置 + 冷却抑制）
        let loud = sine_bytes(100.0, 0.9, 2048, 44100);
        let frames = a.push(&loud);
        let beats = frames.iter().filter(|f| f.is_beat).count();
        assert!(beats >= 1, "低频突增应触发强拍，实际 {beats}");
        assert!(beats <= 3, "强拍应被冷却/基线重置抑制，实际 {beats}");
    }
}
