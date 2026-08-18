import 'package:flutter/material.dart';

import 'app/app.dart';
import 'app/theme/app_theme.dart';
import 'core/bridge/rust_bridge.dart';
import 'core/storage/local_storage.dart';

Future<void> main() async {
  await RustBridge.init();
  await LocalStorage.ensureInit();
  await initThemeMode();
  runApp(const App());
}
