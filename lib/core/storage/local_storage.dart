import 'package:shared_preferences/shared_preferences.dart';

/// 本地存储门面（shared_preferences 落地）。
///
/// 职责：已配对设备、灯效偏好等持久化。统一 key-value 字符串存取，
/// 具体模型的序列化由调用方负责（示例见 app_theme.dart 的主题持久化）。
/// 使用前先 [ensureInit]（main.dart 启动时调用一次，幂等）。
class LocalStorage {
  LocalStorage._();

  static SharedPreferences? _prefs;

  /// 初始化（幂等）：main.dart 启动时调用。
  static Future<void> ensureInit() async {
    _prefs ??= await SharedPreferences.getInstance();
  }

  /// 读取字符串；未初始化或键不存在返回 null。
  static String? read(String key) => _prefs?.getString(key);

  /// 写入字符串。
  static Future<void> write(String key, String value) async {
    await _prefs?.setString(key, value);
  }

  /// 删除键。
  static Future<void> remove(String key) async {
    await _prefs?.remove(key);
  }
}
