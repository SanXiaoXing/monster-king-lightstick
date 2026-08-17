import 'package:flutter/material.dart';

import '../core/config/app_config.dart';
import '../features/device/presentation/pages/device_page.dart';
import 'theme/app_theme.dart';

/// 应用根 Widget。
///
/// `ponytail:` 当前直接以设备连接页（初始界面）为首页；features 页面多于一个后
/// 改为 app/router/app_router.dart 路由表驱动。
class App extends StatelessWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: AppConfig.appTitle,
      theme: buildAppTheme(),
      home: const DevicePage(),
    );
  }
}
