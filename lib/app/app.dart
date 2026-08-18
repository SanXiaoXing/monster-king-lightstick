import 'package:flutter/material.dart';

import '../core/config/app_config.dart';
import '../features/home/presentation/pages/home_page.dart';
import 'theme/app_theme.dart';

/// 应用根 Widget。
///
/// 浅色/深色双主题 + 跟随系统（[themeModeNotifier] 可被设置页切换）。
class App extends StatelessWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: themeModeNotifier,
      builder: (context, mode, _) {
        return MaterialApp(
          title: AppConfig.appTitle,
          theme: buildLightTheme(),
          darkTheme: buildDarkTheme(),
          themeMode: mode,
          home: const HomePage(),
        );
      },
    );
  }
}
