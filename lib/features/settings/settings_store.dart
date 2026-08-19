import '../../core/storage/local_storage.dart';

/// 设置页「默认值」的持久化（shared_preferences 落地）。
///
/// 三个默认设置：律动模式 / 灵敏度 / 亮度，分别作为音乐页与调色页的
/// 初始值（页面构造时读取一次，下次启动生效）。未设置或值非法时
/// 回退到页面内置默认值。写入口均为 no-op 安全：LocalStorage 未初始化
/// （如测试环境）时静默不落盘。
class SettingsStore {
  SettingsStore._();

  static const _modeKey = 'default_rhythm_mode';
  static const _sensitivityKey = 'default_sensitivity';
  static const _brightnessKey = 'default_brightness';

  static const defaultMode = '单色律动';
  static const defaultSensitivity = 0.6;
  static const defaultBrightness = 0.8;

  static const _knownModes = {'单色律动', '七彩律动', '强烈', '柔和'};

  /// 默认律动模式（四档全名，非法值回退单色律动）。
  static String readMode() {
    final v = LocalStorage.read(_modeKey);
    return v != null && _knownModes.contains(v) ? v : defaultMode;
  }

  static Future<void> writeMode(String v) => LocalStorage.write(_modeKey, v);

  /// 默认灵敏度 0..1。
  static double readSensitivity() =>
      double.tryParse(LocalStorage.read(_sensitivityKey) ?? '') ??
      defaultSensitivity;

  static Future<void> writeSensitivity(double v) =>
      LocalStorage.write(_sensitivityKey, '$v');

  /// 默认亮度 0..1。
  static double readBrightness() =>
      double.tryParse(LocalStorage.read(_brightnessKey) ?? '') ??
      defaultBrightness;

  static Future<void> writeBrightness(double v) =>
      LocalStorage.write(_brightnessKey, '$v');
}
