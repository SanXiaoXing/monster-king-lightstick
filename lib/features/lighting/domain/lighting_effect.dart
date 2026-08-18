// 灯光效果领域模型（9 种，对齐 PROTOCOL.md 命令字表 6.1）。
//
// 纯 Dart 领域枚举，不依赖 frb 生成代码；Repository 负责映射到
// Rust 侧 LightingEffect 并构造命令。
enum LightingFx {
  blackScreen('黑屏'),
  constantlyOn('常亮'),
  random('随机色'),
  flashMob('快闪'),
  blink('眨眼'),
  breathe('呼吸'),
  party('聚会'),
  rainbow('彩虹'),
  starrySky('星空');

  const LightingFx(this.label);

  /// 中文显示名（UI 直接使用）。
  final String label;

  /// 按显示名反查（用于效果网格选中态同步）。
  static LightingFx? byLabel(String label) {
    for (final fx in values) {
      if (fx.label == label) return fx;
    }
    return null;
  }
}
