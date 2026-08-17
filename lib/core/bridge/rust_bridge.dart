import 'package:wanshou/src/rust/frb_generated.dart';

/// Rust 运行时访问门面。
///
/// UI/Repository 不直接依赖 frb 生成代码细节，统一从这里进入。
/// 未来若把 Rust BLE 换成 Android Native BLE 或 Mock，UI 不动。
class RustBridge {
  /// 初始化 flutter_rust_bridge 运行时。必须在 runApp 前调用。
  static Future<void> init() async {
    await RustLib.init();
  }
}
