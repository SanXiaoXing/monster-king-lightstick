//! # audio — 音频分析
//!
//! 音频采集与频谱分析，驱动音频律动效果。
//!
//! `ponytail:` 骨架模块，待实现。Kotlin 版用 Oboe/FFT（cpp/fft_engine.c），
//! Rust 侧接入时评估直接复用该 C 引擎或换 rustfft。

pub mod analyzer;
pub mod spectrum;
