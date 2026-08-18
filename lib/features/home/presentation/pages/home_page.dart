import 'package:flutter/material.dart';

import '../../../audio/presentation/pages/music_page.dart';
import '../../../device/data/device_repository.dart';
import '../../../device/presentation/device_view_model.dart';
import '../../../device/presentation/pages/device_page.dart';
import '../../../lighting/presentation/pages/color_picker_page.dart';
import '../../../settings/settings_page.dart';

/// 主页：胶囊式底部导航栏（基于 Material 3 [NavigationBar]）。
///
/// 视觉参考截图：悬浮圆角胶囊、左右留边距、选中态有圆形高亮包图标，
/// 图标填充 + 文字使用主题色，未选中为中性灰描线图标 + 灰文字。
///
/// 布局采用 `body` 内 `Column([Expanded(IndexedStack), 导航栏])` 而非
/// [Scaffold.bottomNavigationBar] 槽——旧版 Scaffold 对自定义包裹的
/// 底部栏高度预留异常，会把 [IndexedStack] 压成 0 高（整页只剩导航栏）。
/// 这样 [IndexedStack] 始终撑满剩余区域，切换 Tab 不重建（状态保留）。
class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  late final DeviceViewModel _vm;
  int _index = 0;

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
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: IndexedStack(
                index: _index,
                children: [
                  DevicePage(viewModel: _vm, embedded: true),
                  ColorPickerPage(viewModel: _vm, embedded: true),
                  MusicPage(viewModel: _vm, embedded: true),
                  SettingsPage(viewModel: _vm, embedded: true),
                ],
              ),
            ),
            // 胶囊导航栏：左右留边距、宽屏居中（≤360）、悬浮观感。
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 360),
                  child: NavigationBar(
                    height: 64,
                    elevation: 0,
                    selectedIndex: _index,
                    onDestinationSelected: _go,
                    backgroundColor:
                        scheme.surfaceContainerHighest.withValues(alpha: 0.92),
                    indicatorColor: scheme.primary.withValues(alpha: 0.18),
                    labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
                    destinations: const [
                      NavigationDestination(
                        icon: Icon(Icons.bluetooth_outlined),
                        selectedIcon: Icon(Icons.bluetooth_rounded),
                        label: '连接',
                      ),
                      NavigationDestination(
                        icon: Icon(Icons.palette_outlined),
                        selectedIcon: Icon(Icons.palette_rounded),
                        label: '调色',
                      ),
                      NavigationDestination(
                        icon: Icon(Icons.music_note_outlined),
                        selectedIcon: Icon(Icons.music_note_rounded),
                        label: '音乐',
                      ),
                      NavigationDestination(
                        icon: Icon(Icons.settings_outlined),
                        selectedIcon: Icon(Icons.settings_rounded),
                        label: '设置',
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
