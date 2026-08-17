import 'package:flutter/material.dart';

/// 全局主题。
///
/// `ponytail:` 目前只有种子色；深色模式/自定义字体按需扩展，
/// 不提前建空抽象。
ThemeData buildAppTheme() {
  return ThemeData(colorSchemeSeed: const Color(0xFF6750A4));
}
