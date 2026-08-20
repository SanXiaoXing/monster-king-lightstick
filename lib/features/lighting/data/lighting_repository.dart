import 'dart:async';

import 'package:flutter/material.dart';
import 'package:wanshou/src/rust/api/protocol.dart' as frb;

import '../../device/data/device_repository.dart';
import '../../device/domain/lightstick.dart';
import '../domain/lighting_effect.dart';

/// 灯光数据访问边界：构造协议命令（经 Rust api）并写入 BLE。
///
/// UI 只依赖本 Repository（领域类型），不直接触碰 frb 生成代码——
/// 与 DeviceRepository 同接缝，未来 Rust BLE 就绪后换实现，UI 不动。
class LightingRepository {
  LightingRepository(this._deviceRepository);

  final DeviceRepository _deviceRepository;

  /// 帧序号（协议要求全局递增，小端 LE 入包）。
  int _seq = 0;

  int _nextSeq() => ++_seq;

  /// 下发灯效：effect + 颜色（RGB，无 alpha）+ 亮度缩放。
  ///
  /// 亮度 0..1 直接线性缩放到 RGB，使设备端明暗与滑杆一致。
  Future<void> sendEffect(
    Lightstick device, {
    required LightingFx fx,
    required Color color,
    double brightness = 1,
  }) async {
    final rgb = _scaledRgb(color, brightness);
    final body = await frb.lightingCommandBody(
      effect: _toFrb(fx),
      colorHex: rgb,
      seed: _nextSeq() & 0xFF,
    );
    final packet = await frb.buildPacket(seq: _seq, commandBodyHex: body);
    final bytes = await frb.hexToBytes(hex: packet);
    await _deviceRepository.writeCommand(device, bytes);
  }

  // ---- 流光（Flow）连续帧循环 ----
  //
  // 按 docs/design/style.md 第七节的官方节奏：
  //   流光帧 → 100ms → 黑屏清除帧 → 100ms → 下一帧（seed 递增 → 光带移动）
  // 两次 BLE 写入间隔 100ms，满足官方 sendBlueData 的 lastWriteTime 限制。

  Timer? _flowTimer;
  bool _flowRunning = false;
  int _flowSeed = 0;
  Lightstick? _flowDevice;
  String _flowColorHex = '0A84FF';

  /// 启动流光：按官方 cycleReunion 节奏循环发送，直到 [stopFlow]。
  void startFlow(
    Lightstick device, {
    required Color color,
    double brightness = 1,
  }) {
    _flowDevice = device;
    _flowColorHex = _scaledRgb(color, brightness);
    _flowRunning = true;
    _flowSeed = 0;
    _flowTimer?.cancel();
    _flowTick();
  }

  /// 更新流光基准色（不打断循环，拖动色环/亮度时调用）。
  void updateFlow({required Color color, double brightness = 1}) {
    _flowColorHex = _scaledRgb(color, brightness);
  }

  /// 停止流光循环。
  void stopFlow() {
    _flowRunning = false;
    _flowTimer?.cancel();
    _flowTimer = null;
  }

  void _flowTick() {
    if (!_flowRunning || _flowDevice == null) return;
    _sendFlowFrame();
    _flowTimer = Timer(const Duration(milliseconds: 100), () {
      _sendFlowClear();
      _flowTimer = Timer(const Duration(milliseconds: 100), _flowTick);
    });
  }

  /// 发送一帧流光（seed 递增 → Rust 侧光带沿 7 组移动）。
  Future<void> _sendFlowFrame() async {
    final device = _flowDevice;
    if (device == null) return;
    try {
      final body = await frb.lightingCommandBody(
        effect: frb.LightingEffect.flow,
        colorHex: _flowColorHex,
        seed: _flowSeed & 0xFF,
      );
      _flowSeed++;
      final packet = await frb.buildPacket(seq: _nextSeq(), commandBodyHex: body);
      final bytes = await frb.hexToBytes(hex: packet);
      await _deviceRepository.writeCommand(device, bytes);
    } catch (_) {
      // 写失败（如断开）静默停止循环，避免无意义重试
      stopFlow();
    }
  }

  /// 发送黑屏清除帧（官方 cycleReunion 的 a+"00000000"）。
  Future<void> _sendFlowClear() async {
    final device = _flowDevice;
    if (device == null) return;
    try {
      final packet = await frb.buildPacket(seq: _nextSeq(), commandBodyHex: '00000000');
      final bytes = await frb.hexToBytes(hex: packet);
      await _deviceRepository.writeCommand(device, bytes);
    } catch (_) {
      stopFlow();
    }
  }

  /// 域枚举 → frb 枚举（同名一一对应）。
  frb.LightingEffect _toFrb(LightingFx fx) => switch (fx) {
        LightingFx.blackScreen => frb.LightingEffect.blackScreen,
        LightingFx.constantlyOn => frb.LightingEffect.constantlyOn,
        LightingFx.random => frb.LightingEffect.random,
        LightingFx.flashMob => frb.LightingEffect.flashMob,
        LightingFx.blink => frb.LightingEffect.blink,
        LightingFx.breathe => frb.LightingEffect.breathe,
        LightingFx.party => frb.LightingEffect.party,
        LightingFx.rainbow => frb.LightingEffect.rainbow,
        LightingFx.starrySky => frb.LightingEffect.starrySky,
        LightingFx.flow => frb.LightingEffect.flow,
      };

  /// Color → 6 hex RGB（协议格式），亮度线性缩放。
  static String _scaledRgb(Color c, double brightness) {
    final b = brightness.clamp(0.0, 1.0);
    final r = (c.r * 255 * b).round().clamp(0, 255);
    final g = (c.g * 255 * b).round().clamp(0, 255);
    final bl = (c.b * 255 * b).round().clamp(0, 255);
    final hex =
        '${r.toRadixString(16).padLeft(2, '0')}'
        '${g.toRadixString(16).padLeft(2, '0')}'
        '${bl.toRadixString(16).padLeft(2, '0')}';
    return hex.toUpperCase();
  }
}
