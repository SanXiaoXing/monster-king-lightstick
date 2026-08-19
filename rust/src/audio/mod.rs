//! # audio — 音频分析
//!
//! 音频采集与频谱分析，驱动音频律动效果。
//! 已实现：[`analyzer`]（PCM16 → 音量/频带/节拍帧，对齐 docs/design/music.md）。
//! 频谱可视化（FFT 频带能量分布）暂未单独落地，需要时在此补充。

pub mod analyzer;
