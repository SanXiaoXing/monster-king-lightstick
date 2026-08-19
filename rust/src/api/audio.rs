//! FRB 入口：音频能力（音乐律动）。
//!
//! 暴露音频分析器给 Flutter：PCM chunk → [`AudioFrame`] 帧流（律动可视化用）。
//! 律动引擎（音频帧 → 灯效）在 api/lightstick.rs（属荧光棒领域）。

use crate::audio::analyzer::PcmAnalyzer as InnerAnalyzer;

/// 一帧音频分析结果：音量级 + 频带能量 + 低频/高频 + 节拍。
#[derive(Clone, Debug)]
pub struct AudioFrame {
    /// 音量级 0..1（RMS + 动态峰值归一化）。
    pub volume: f64,
    /// 频带能量 0..1（对数频带，长度 28）。
    pub bands: Vec<f64>,
    /// 低频能量 0..1（约 40~230Hz）。
    pub bass: f64,
    /// 高频能量 0..1（约 4kHz+）。
    pub treble: f64,
    /// 强拍标记。
    pub is_beat: bool,
}

/// PCM16 分析器（Rust 侧持有环形缓冲/FFT 状态，opaque 不跨桥序列化）。
#[flutter_rust_bridge::frb(opaque)]
pub struct PcmAnalyzer {
    inner: InnerAnalyzer,
}

impl PcmAnalyzer {
    /// 默认参数：28 频带、1024 窗、44.1kHz（与 record 采集配置一致）。
    pub fn create() -> PcmAnalyzer {
        PcmAnalyzer {
            inner: InnerAnalyzer::new(28, 1024, 44100),
        }
    }

    /// 喂入 PCM16 小端字节流，返回本次新产生的全部分析帧。
    pub fn push(&mut self, chunk: Vec<u8>) -> Vec<AudioFrame> {
        self.inner
            .push(&chunk)
            .into_iter()
            .map(|f| AudioFrame {
                volume: f.volume,
                bands: f.bands,
                bass: f.bass,
                treble: f.treble,
                is_beat: f.is_beat,
            })
            .collect()
    }
}
