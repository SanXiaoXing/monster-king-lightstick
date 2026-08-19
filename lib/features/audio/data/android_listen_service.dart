import 'package:flutter/services.dart';

/// Android 后台监听前台服务门面（MethodChannel 直连原生）。
///
/// 音乐监听期间启动 microphone 类型前台服务（AudioListeningService）：
/// 锁屏 / 切后台 / 被系统回收时，进程保持前台优先级、麦克风访问不被
/// 回收（Android 11+ 后台麦克风限制），并由原生侧持有 PARTIAL_WAKE_LOCK
/// 保证息屏后 CPU 持续供数。
/// 非 Android / 原生未注册时全部静默降级，不影响既有采集链路。
class AndroidListenService {
  static const MethodChannel _channel = MethodChannel(
    'cn.sanxiaoxing.monster_king/listen_service',
  );

  /// 启动前台服务（调用方需已持有 RECORD_AUDIO 权限）。
  Future<void> start() => _invoke('startService');

  /// 停止前台服务并释放唤醒锁。
  Future<void> stop() => _invoke('stopService');

  /// 申请通知权限（Android 13+ 弹窗；拒绝时监听不受影响，仅通知栏不显示）。
  Future<void> requestNotificationPermission() =>
      _invoke('requestNotificationPermission');

  /// 申请电池优化豁免（弹系统"允许后台运行"对话框；拒绝不影响前台监听，
  /// 但激进的后台清理可能在切后台几秒内杀掉监听进程）。
  Future<void> requestIgnoreBatteryOptimizations() =>
      _invoke('requestIgnoreBatteryOptimizations');

  Future<void> _invoke(String method) async {
    try {
      await _channel.invokeMethod<void>(method);
    } on MissingPluginException {
      // 原生侧未注册（非 Android 构建）：静默降级
    }
  }
}
