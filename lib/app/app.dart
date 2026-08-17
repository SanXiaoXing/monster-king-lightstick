import 'package:flutter/material.dart';

import '../core/config/app_config.dart';
import '../features/home/presentation/protocol_demo_page.dart';
import 'theme/app_theme.dart';

/// 应用根 Widget。
///
/// `ponytail:` 当前直接以协议验证页为首页；features 页面多于一个后
/// 改为 app/router/app_router.dart 路由表驱动。
class App extends StatelessWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: AppConfig.appTitle,
      theme: buildAppTheme(),
      home: const ProtocolDemoPage(),
    );
  }
}
