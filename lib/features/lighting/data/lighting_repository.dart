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
