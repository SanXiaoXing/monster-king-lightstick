import 'package:flutter/material.dart';

import '../../core/storage/local_storage.dart';

/// 万兽之王品牌色板（取自 docs/design/ios27_floating_nav_prototype.html）。
///
/// 单强调色 iOS 系统蓝，深/浅双主题跟随系统；纯高斯模糊美学。
class AppColors {
  AppColors._();

  /// 单强调色：iOS 系统蓝，全页锁定。
  static const accent = Color(0xFF0A84FF);
  static const accentSoft = Color(0x291A84FF); // accent @ 16%

  // 系统语义色
  static const ok = Color(0xFF34C759);
  static const warn = Color(0xFFFF9F0A);
  static const err = Color(0xFFFF453A);

  // 深色模式（对齐原型 :root[data-theme="dark"]）
  static const darkBg = Color(0xFF08080B);
  static const darkBg2 = Color(0xFF111318);
  static const darkText = Color(0xFFF5F5F7);
  static const darkMuted = Color(0xFF8E8E93);
  static const darkLine = Color(0x1AF5F5F7); // 10% 白

  // 浅色模式（对齐原型 :root[data-theme="light"]）
  static const lightBg = Color(0xFFEEF2F8);
  static const lightBg2 = Color(0xFFE2E8F1);
  static const lightText = Color(0xFF0A0F1A);
  static const lightMuted = Color(0xFF54627A);
  static const lightLine = Color(0x1A0A0F1A); // 10% 文字色

  /// 当前是否为深色模式。
  static bool isDark(ColorScheme scheme) => scheme.brightness == Brightness.dark;
}

/// 主题模式（跟随系统 / 浅色 / 深色）。
///
/// 持久化于 [LocalStorage]：启动时 [initThemeMode] 读取上次选择，
/// 之后每次切换自动落盘。
final ValueNotifier<ThemeMode> themeModeNotifier =
    ValueNotifier<ThemeMode>(ThemeMode.system);

const _themeModeKey = 'theme_mode';

/// 启动时读取持久化的主题模式并挂载自动落盘监听。
///
/// 需在 [LocalStorage.ensureInit] 之后调用（main.dart 一次）。
Future<void> initThemeMode() async {
  final saved = LocalStorage.read(_themeModeKey);
  if (saved != null) {
    themeModeNotifier.value = ThemeMode.values.firstWhere(
      (m) => m.name == saved,
      orElse: () => ThemeMode.system,
    );
  }
  themeModeNotifier.addListener(_persistThemeMode);
}

void _persistThemeMode() {
  LocalStorage.write(_themeModeKey, themeModeNotifier.value.name);
}

ThemeData buildLightTheme() => _buildTheme(Brightness.light);
ThemeData buildDarkTheme() => _buildTheme(Brightness.dark);

ThemeData _buildTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final scheme = ColorScheme(
    brightness: brightness,
    primary: AppColors.accent,
    onPrimary: Colors.white,
    primaryContainer: dark ? const Color(0xFF0B223A) : const Color(0xFFD3ECFF),
    onPrimaryContainer: dark ? const Color(0xFFCFE8FF) : const Color(0xFF0A3B5C),
    secondary: AppColors.accent,
    onSecondary: Colors.white,
    secondaryContainer: dark ? const Color(0xFF0B223A) : const Color(0xFFD3ECFF),
    onSecondaryContainer: dark ? const Color(0xFFCFE8FF) : const Color(0xFF0A3B5C),
    tertiary: AppColors.ok,
    onTertiary: Colors.white,
    error: dark ? AppColors.err : const Color(0xFFBA1A1A),
    onError: Colors.white,
    surface: dark ? AppColors.darkBg : AppColors.lightBg,
    onSurface: dark ? AppColors.darkText : AppColors.lightText,
    surfaceContainerLowest: dark ? const Color(0xFF050509) : Colors.white,
    surfaceContainerLow: dark ? const Color(0xFF0E0F14) : const Color(0xFFE8EEF7),
    surfaceContainer: dark ? const Color(0xFF15171D) : const Color(0xFFDDE5F1),
    surfaceContainerHigh: dark ? const Color(0xFF1C1E25) : const Color(0xFFCFD9EA),
    surfaceContainerHighest: dark ? const Color(0xFF24262E) : const Color(0xFFC1CCDF),
    onSurfaceVariant: dark ? AppColors.darkMuted : AppColors.lightMuted,
    outline: dark ? const Color(0xFF2A2D36) : const Color(0xFFB9C7D8),
    outlineVariant: dark ? const Color(0xFF1A1C22) : const Color(0xFFDCE6F2),
    shadow: Colors.black,
    scrim: Colors.black,
    inverseSurface: dark ? AppColors.darkText : AppColors.lightText,
    onInverseSurface: dark ? AppColors.darkBg : AppColors.lightBg,
    inversePrimary: AppColors.accent,
    surfaceTint: Colors.transparent,
  );

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: scheme.surface,
    // 原型各屏无 AppBar，主屏由悬浮 Dock 导航
    appBarTheme: AppBarTheme(
      backgroundColor: scheme.surface,
      foregroundColor: scheme.onSurface,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
        color: scheme.onSurface,
        fontSize: 26,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.4,
      ),
    ),
    cardTheme: CardThemeData(
      color: scheme.surfaceContainerLow,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: scheme.outlineVariant),
      ),
    ),
    dividerTheme: DividerThemeData(color: scheme.outlineVariant, space: 1),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: scheme.surfaceContainer,
      hintStyle: TextStyle(color: scheme.onSurfaceVariant.withValues(alpha: 0.7)),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: scheme.primary, width: 1.5),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    ),
    sliderTheme: SliderThemeData(
      activeTrackColor: scheme.primary,
      inactiveTrackColor: scheme.surfaceContainerHighest,
      thumbColor: scheme.primary,
      overlayColor: scheme.primary.withValues(alpha: 0.12),
      trackHeight: 4,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(52),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(100)),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: Colors.transparent,
    ),
    // 统一对话框外观（对齐 ui_layout_rules.md 第 10 节）：
    // 底色 surfaceContainerLow、圆角 20；危险操作用 error 色由调用方指定。
    dialogTheme: DialogThemeData(
      backgroundColor: scheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      titleTextStyle: TextStyle(
        color: scheme.onSurface,
        fontSize: 17,
        fontWeight: FontWeight.w700,
      ),
      contentTextStyle: TextStyle(
        color: scheme.onSurfaceVariant,
        fontSize: 14,
        height: 1.5,
      ),
    ),
    // 次/取消按钮用中性 fgMuted（对齐 ui_layout_rules.md 第 10 节）。
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: scheme.onSurfaceVariant,
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
      ),
    ),
  );
}
