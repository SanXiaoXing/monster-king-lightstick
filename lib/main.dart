import 'package:flutter/material.dart';

import 'app/app.dart';
import 'core/bridge/rust_bridge.dart';

Future<void> main() async {
  await RustBridge.init();
  runApp(const App());
}
