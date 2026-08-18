import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'audio_analysis.dart';

/// 音乐律动引擎（领域层，无 Flutter 显示依赖）。
///
/// 把「音频帧 → 应援棒应显示色 + 亮度」的映射从 UI 页面抽离，作为**单一数据源**：
/// 同一份输出同时喂给 BLE 下发与可视化渲染，避免逻辑在页面里散落、两边不一致。
///
/// 三种律动：
/// - **随音律动（原版）**：主导频带（能量峰值所在频带）→ 色相，低音偏暖、高音偏冷，
///   指数平滑防跳变；颜色随音高在红橙黄绿青蓝紫间平滑流动。颜色始终鲜艳，
///   亮度随音量/强拍脉冲。这是最初被认可的"活"的律动感。
/// - **单色律动**：颜色 = 所选色（固定，色相/饱和度不变），亮度随声音实时呼吸
///   （强拍快闪 + 柔和回落 + 最低微光地板，避免闪烁熄灭），颜色本身不变。
/// - **七彩律动**：相位按音量推进 + 强拍跳步，在 7 色锚点间**平滑过渡**周期换色；
///   亮度按"每个色步登场点亮、随后柔和回落"的呼吸包络 + 音量整体缩放 + 强拍闪满，
///   形成规律显示 + 一定亮灭，但永不彻底熄灭，比旧版硬跳变/硬灭更优雅。
///
/// **[sensitivity]（滑块）= 节奏灵敏度（增益，0..1，默认 0.6）**：律动整体响应增益，
/// 越大灯光随声音起伏越剧烈、越跟手；越小越柔和含蓄。直接乘到归一化音量上驱动
/// 亮度/换色幅度，任意音量下都有完整律动动态范围，律动始终"活"。
///
/// 将来 Rust 音频管线（rust/src/lightstick/effect.rs）就绪后，本类可被
/// Repository 实现替换，UI 与可视化无需改动（对齐 AudioAnalyzer 注释的
/// 「Rust audio/ 就绪后可替换 Repository 实现，UI 不动」）。
class LightRhythm {
  LightRhythm({required this.pickedColor, this.sensitivity = defaultSensitivity});

  /// 律动模式：随音 / 单色 / 七彩（默认随音，即最初被认可的观感）。
  String mode = '随音律动';

  /// 单色律动所选颜色（RGB 线性缩放，色相/饱和度不变）。
  Color pickedColor;

  /// 节奏灵敏度默认增益：滑块量程 0..1，默认 0.6（与初版可视化灵敏度一致）。
  static const double defaultSensitivity = 0.6;

  /// 节奏灵敏度（增益，0..1）：律动整体响应强度。越大随声音起伏越剧烈。
  double sensitivity;

  /// 七彩律动调色板（红橙黄绿青蓝紫，等距 7 色，跳变清晰、对比强）。
  static const List<Color> sevenPalette = <Color>[
    Color(0xFFFF3B30), // 红
    Color(0xFFFF9500), // 橙
    Color(0xFFFFCC00), // 黄
    Color(0xFF34C759), // 绿
    Color(0xFF32ADE6), // 青
    Color(0xFF007AFF), // 蓝
    Color(0xFFAF52DE), // 紫
  ];

  /// 随音律动：主导频带平滑位置（0..1，指数平滑防跳变）。
  double _smoothPeak = 0;

  /// 七彩律动相位累加器：按响应推进 + 强拍跳步，取整为色板索引。
  double _sevenPhase = 0;

  /// 输出亮度平滑（快起慢落包络），让三种模式都"脉动"而非闪烁。
  double _smoothBright = 0;

  DateTime? _lastFrameTime;

  /// 处理一帧音频，返回应援棒应显示的 (颜色, 亮度)。
  ///
  /// [dt] 由帧时间戳推算，使相位推进与帧率解耦。
  (Color, double) process(AudioFrame f) {
    final now = DateTime.now();
    final prev = _lastFrameTime; // 局部副本，避免可空字段无法类型提升
    final dt = prev == null ? 0.016 : now.difference(prev).inMicroseconds / 1e6;
    _lastFrameTime = now;

    final (color, target) = switch (mode) {
      '单色律动' => _single(f),
      '七彩律动' => _seven(f, dt),
      _ => _rainbow(f),
    };

    // 亮度统一走快起慢落包络（attack ≈50ms 跟手、release ≈180ms 留余韵），
    // 三种模式都因此平滑脉动，不再逐帧闪烁。
    final tau = target > _smoothBright ? 0.05 : 0.18;
    _smoothBright += (target - _smoothBright) * (1 - math.exp(-dt / tau));
    return (color, _smoothBright.clamp(0.0, 1.0));
  }

  /// 律动幅度（0..1）：归一化音量乘以节奏灵敏度增益，任意音量下都有完整动态范围。
  /// 低于噪声门限的帧音量已为 0。幅度由真实音量起伏驱动，律动才"活"。
  double _resp(double volume) => (volume * sensitivity).clamp(0.0, 1.0);

  /// 随音律动：主导频带 → 色相，颜色随音高平滑流动；亮度随音量/强拍脉冲。
  (Color, double) _rainbow(AudioFrame f) {
    var peakIdx = 0;
    var peakVal = -1.0;
    for (var i = 0; i < f.bands.length; i++) {
      if (f.bands[i] > peakVal) {
        peakVal = f.bands[i];
        peakIdx = i;
      }
    }
    final peakNorm = f.bands.isEmpty ? 0.0 : peakIdx / (f.bands.length - 1);
    // 指数平滑（约 3 帧收敛），防频带跳变导致色相乱跳
    _smoothPeak = _smoothPeak * 0.5 + peakNorm * 0.5;
    // 色相：低音(0)→暖、高音→冷，映射到 0~300 避开红紫相接
    final hue = _smoothPeak * 300;
    final color = HSVColor.fromAHSV(1, hue, 0.9, 1).toColor();
    // 亮度：动态幅度(×灵敏度) + 强拍拉满（忠实还原最初被认可的观感）
    final resp = _resp(f.volume);
    final target = f.isBeat ? 1.0 : resp;
    return (color, target);
  }

  /// 单色律动：颜色固定，亮度随声音呼吸（强拍快闪 + 微光地板防熄灭）。
  (Color, double) _single(AudioFrame f) {
    final resp = _resp(f.volume);
    final target = f.isBeat
        ? 1.0
        : 0.12 + 0.88 * math.sqrt(resp); // sqrt 感知曲线 + 微光地板 0.12
    return (pickedColor, target);
  }

  /// 七彩律动：相位按响应推进换色（平滑过渡）+ 呼吸包络（亮灭、不灭）。
  (Color, double) _seven(AudioFrame f, double dt) {
    final resp = _resp(f.volume);
    _sevenPhase += resp * 2.8 * dt * 3 + (f.isBeat ? 0.45 : 0);
    final n = sevenPalette.length;
    final idxF = _sevenPhase % n;
    final idx = idxF.floor();
    final frac = idxF - idx; // 当前色步内进度 0..1
    // 在相邻两个锚点间平滑过渡（smoothstep），既周期换色又优雅不跳变
    final t = frac * frac * (3 - 2 * frac);
    final color = Color.lerp(
      sevenPalette[idx],
      sevenPalette[(idx + 1) % n],
      t,
    )!;

    // 呼吸包络：每个色步登场点亮(1) → 柔和回落到地板(floor)，叠加响应整体缩放；
    // 强拍闪满。规律显示 + 一定亮灭，但永不彻底熄灭。
    const floor = 0.32;
    final breath = floor + (1 - floor) * math.pow(1 - frac, 1.4); // 1 → floor
    final volScale = 0.3 + 0.7 * resp;
    final target = breath * volScale;
    return (color, target);
  }

  /// 重置跨帧状态（切换模式 / 暂停时调用），避免颜色突跳或相位残留。
  void reset() {
    _smoothPeak = 0;
    _sevenPhase = 0;
    _smoothBright = 0;
    _lastFrameTime = null;
  }
}
