import 'package:flutter/material.dart';

/// 调色盘当前选中的颜色（全 App 共享）。
///
/// 调色盘每次选色写入；音乐页「单色律动」以此为固定色——与 Rust
/// `MusicRhythm::set_base_color` 对齐。默认 iOS 蓝，与 Rust 引擎
/// base 色默认值一致，首次进入两页颜色天然相同。
final ValueNotifier<Color> selectedLightColor =
    ValueNotifier(const Color(0xFF0A84FF));
