/// 音频领域模型（纯 Dart，无 IO）。
///
/// 分析逻辑已迁至 Rust（`rust/src/audio/analyzer.rs` + `rust/src/lightstick/effect.rs`，
/// 对齐 docs/design/music.md 音乐调光设置），本文件只保留跨层传递的数据模型。
library;

/// 一帧音频分析结果：音量级 + 频带能量 + 低频/高频 + 节拍，驱动律动 UI。
class AudioFrame {
  const AudioFrame({
    required this.volume,
    required this.bands,
    required this.bass,
    required this.treble,
    required this.isBeat,
  });

  /// 音量级 0..1（RMS + 动态峰值归一化）。
  final double volume;

  /// 频带能量 0..1（对数频带，长度 28）。
  final List<double> bands;

  /// 低频能量 0..1（约 40~230Hz，驱动圆环半径的慢速大位移）。
  final double bass;

  /// 高频能量 0..1（约 4kHz+，驱动细密快速振荡）。
  final double treble;

  /// 强拍标记：低频能量突增时置 true（触发径向脉冲与粒子爆发）。
  final bool isBeat;
}

/// 一帧律动输出：RGB 颜色 + 亮度（0..1）。
///
/// 由 Rust 律动引擎计算（`rust/src/lightstick/effect.rs`）：
/// - 亮度 = 音量 × 灵敏度（+ 强烈/柔和模式增益）；
/// - 七彩/强烈/柔和按 15 色板循环换色（≈400ms），单色固定 base 色。
class RhythmOutput {
  const RhythmOutput({required this.rgb, required this.brightness});

  /// RGB 三字节（0..255）。
  final List<int> rgb;

  /// 亮度 0..1（随音量变化）。
  final double brightness;
}
