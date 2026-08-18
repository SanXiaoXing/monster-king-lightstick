import 'dart:async';

import 'package:flutter/services.dart';

/// Android 原生麦克风采集（ForegroundService + AudioRecord）的 Dart 门面。
///
/// 与 `record` 插件的关键差异：采集跑在 microphone 类型的前台服务里，
/// 锁屏/退后台后进程与服务存活，PCM 流不中断——音乐律动可以持续驱动
/// 荧光棒，不需要用户一直亮屏停留在页面。
///
/// 通道协议（Kotlin 侧见 MainActivity / AudioCaptureService）：
/// - MethodChannel `monster_king/audio_capture`：
///   requestPermission / hasPermission / start / stop / isCapturing
/// - EventChannel `monster_king/audio_capture/pcm`：PCM16 小端单声道
///   44.1kHz 字节块（与 [AudioAnalyzer] 的输入约定一致）
class NativeAudioCapture {
  static const _method = MethodChannel('monster_king/audio_capture');
  static const _events = EventChannel('monster_king/audio_capture/pcm');

  /// 申请麦克风权限（Android 13+ 顺带申请通知权限，可拒绝，仅影响
  /// 常驻通知在通知栏的可见性）。返回麦克风权限是否已授予。
  Future<bool> requestPermission() async {
    final granted = await _method.invokeMethod<bool>('requestPermission');
    return granted ?? false;
  }

  Future<bool> hasPermission() async {
    final granted = await _method.invokeMethod<bool>('hasPermission');
    return granted ?? false;
  }

  /// 启动前台服务采集。权限未授予时抛 [PlatformException]（PERMISSION_DENIED）。
  Future<void> start() => _method.invokeMethod<void>('start');

  /// 停止前台服务采集（服务未运行时调用为空操作）。
  Future<void> stop() async {
    try {
      await _method.invokeMethod<void>('stop');
    } on MissingPluginException {
      // 非 Android 平台无实现，忽略
    }
  }

  /// 采集会话是否存活（服务视角，与 EventChannel 是否有监听者无关）。
  Future<bool> isCapturing() async {
    final v = await _method.invokeMethod<bool>('isCapturing');
    return v ?? false;
  }

  /// PCM16 字节流。start 之后 listen；取消 listen 不停止服务采集
  /// （服务丢帧继续跑），重新 listen 即恢复接收。
  Stream<Uint8List> pcmStream() => _events
      .receiveBroadcastStream()
      .map((event) => event as Uint8List);
}
