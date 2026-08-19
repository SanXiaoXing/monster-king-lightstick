import 'package:flutter/material.dart';

/// 普通卡片统一圆角（对齐 docs/design/ui_layout_rules.md 第 3 节）。
const double kCardRadius = 16;

/// 普通卡片统一外观：圆角 [kCardRadius] + 1px 细边框。
///
/// 普通卡片一律用 [cardDecoration]，不要各自写 [BoxDecoration]。
/// 可点击卡片请在外层包 [Material] + [InkWell]（圆角同 [kCardRadius]），
/// 保证水波纹在圆角内。
BoxDecoration cardDecoration(ColorScheme scheme) => BoxDecoration(
      color: scheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(kCardRadius),
      border: Border.all(color: scheme.outlineVariant),
    );
