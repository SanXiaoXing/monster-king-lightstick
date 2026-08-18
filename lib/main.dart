import 'package:flutter/material.dart';

import 'app/app.dart';
import 'app/theme/app_theme.dart';
import 'core/bridge/rust_bridge.dart';
import 'core/storage/local_storage.dart';

Future<void> main() async {
  // 必须先初始化 binding：RustLib.init / SharedPreferences 均可能触碰平台通道，
  // 否则 ServicesBinding 未就绪时直接抛 "Binding has not yet been initialized"，
  // runApp 永远不执行 → 黑屏。
  WidgetsFlutterBinding.ensureInitialized();
  await RustBridge.init();
  await LocalStorage.ensureInit();
  await initThemeMode();
  runApp(const App());
}
