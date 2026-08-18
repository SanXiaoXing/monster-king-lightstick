import 'dart:ui';

import 'package:flutter/material.dart';

import '../../../../app/theme/app_theme.dart';
import '../../../audio/presentation/pages/music_page.dart';
import '../../../device/data/device_repository.dart';
import '../../../device/presentation/device_view_model.dart';
import '../../../device/presentation/pages/device_page.dart';
import '../../../lighting/presentation/pages/color_picker_page.dart';
import '../../../settings/settings_page.dart';

/// 主页：悬浮 Dock 导航壳。
///
/// 对齐 docs/design/ios27_floating_nav_prototype.html：底部悬浮 Dock 4 Tab
/// （连接/调色/音乐/设置），IndexedStack 保持各页状态，Dock 用 BackdropFilter
/// 高斯模糊。各子屏为无 AppBar 的可嵌入 Widget。
class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  late final DeviceViewModel _vm;
  int _index = 0;

  static const _tabs = <({IconData icon, String label})>[
    (icon: Icons.bluetooth_rounded, label: '连接'),
    (icon: Icons.palette_rounded, label: '调色'),
    (icon: Icons.music_note_rounded, label: '音乐'),
    (icon: Icons.settings_rounded, label: '设置'),
  ];

  @override
  void initState() {
    super.initState();
    _vm = DeviceViewModel(DeviceRepository())..init();
  }

  @override
  void dispose() {
    _vm.dispose();
    super.dispose();
  }

  void _go(int i) => setState(() => _index = i);

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: scheme.surface,
      body: Stack(
        children: [
          // IndexedStack：各页保持状态，切换不重建
          IndexedStack(
            index: _index,
            children: [
              DevicePage(viewModel: _vm, embedded: true),
              ColorPickerPage(viewModel: _vm, embedded: true),
              MusicPage(viewModel: _vm, embedded: true),
              SettingsPage(viewModel: _vm, embedded: true),
            ],
          ),
          // 悬浮 Dock
          Positioned(
            left: 12,
            right: 12,
            bottom: 10,
            child: _FloatingDock(
              tabs: _tabs,
              index: _index,
              onTap: _go,
            ),
          ),
        ],
      ),
    );
  }
}

/// 悬浮 Dock：BackdropFilter 高斯模糊 + 38px 圆角 + overflow 裁剪角部 tab。
class _FloatingDock extends StatelessWidget {
  const _FloatingDock({
    required this.tabs,
    required this.index,
    required this.onTap,
  });

  final List<({IconData icon, String label})> tabs;
  final int index;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ClipRRect(
      borderRadius: BorderRadius.circular(38),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 44, sigmaY: 44),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: BoxDecoration(
            // 纯高斯模糊半透明底，无玻璃质感装饰
            color: scheme.brightness == Brightness.dark
                ? const Color(0x14FFFFFF) // 8% 白
                : const Color(0x8CFFFFFF), // 55% 白
            border: Border.all(
              color: scheme.brightness == Brightness.dark
                  ? const Color(0x1FFFFFFF)
                  : const Color(0xB3FFFFFF),
            ),
            borderRadius: BorderRadius.circular(38),
            boxShadow: [
              BoxShadow(
                color: scheme.brightness == Brightness.dark
                    ? Colors.black.withValues(alpha: 0.55)
                    : const Color(0xFF1D3C5E).withValues(alpha: 0.2),
                blurRadius: 50,
                offset: const Offset(0, 24),
              ),
            ],
          ),
          child: Row(
            children: [
              for (var i = 0; i < tabs.length; i++)
                Expanded(
                  child: _DockTab(
                    icon: tabs[i].icon,
                    label: tabs[i].label,
                    active: i == index,
                    onTap: () => onTap(i),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DockTab extends StatelessWidget {
  const _DockTab({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = active ? scheme.primary : scheme.onSurfaceVariant;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 9),
        decoration: BoxDecoration(
          color: active ? AppColors.accentSoft : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TweenAnimationBuilder<double>(
              tween: Tween(begin: 1.0, end: active ? 1.12 : 1.0),
              duration: const Duration(milliseconds: 320),
              curve: Curves.easeOutBack,
              builder: (context, s, child) =>
                  Transform.scale(scale: s, child: child),
              child: Icon(icon, size: 21, color: color),
            ),
            const SizedBox(height: 3),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 10,
                fontWeight: FontWeight.w500,
                letterSpacing: 0.1,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
