import 'package:flutter/material.dart';

import '../../../audio/presentation/pages/music_page.dart';
import '../../../device/data/device_repository.dart';
import '../../../device/presentation/device_view_model.dart';
import '../../../device/presentation/pages/device_page.dart';
import '../../../lighting/presentation/pages/color_picker_page.dart';
import '../../../settings/settings_page.dart';

/// 主页：胶囊式底部导航栏。
///
/// 视觉风格参考截图：圆角胶囊（≈角 28）悬浮在底部安全区之上，整体居中
/// 且宽度受限（≈340），左右留出屏幕边距；选中态有圆形高亮背景包图标，
/// 图标填充 + 文字使用主题色，未选中为中性灰。背景半透明 + 轻微边框
/// 与深色页面一致。导航栏为布局一部分，不再遮挡内容，且系统手势条
/// 通过 [SafeArea] 留出空间。
///
/// [IndexedStack] 保持各页状态，切换不重建（音乐 / 调色等状态得以保留）。
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
    final tabs = _tabs(context);
    return Scaffold(
      backgroundColor: scheme.surface,
      body: IndexedStack(
        index: _index,
        children: [
          DevicePage(viewModel: _vm, embedded: true),
          ColorPickerPage(viewModel: _vm, embedded: true),
          MusicPage(viewModel: _vm, embedded: true),
          SettingsPage(viewModel: _vm, embedded: true),
        ],
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: _PillTabBar(
            index: _index,
            onChanged: _go,
            tabs: tabs,
          ),
        ),
      ),
    );
  }

  static List<_TabSpec> _tabs(BuildContext context) => const [
        _TabSpec(
          icon: Icons.bluetooth_rounded,
          outlined: Icons.bluetooth_outlined,
          label: '连接',
        ),
        _TabSpec(
          icon: Icons.palette_rounded,
          outlined: Icons.palette_outlined,
          label: '调色',
        ),
        _TabSpec(
          icon: Icons.music_note_rounded,
          outlined: Icons.music_note_outlined,
          label: '音乐',
        ),
        _TabSpec(
          icon: Icons.settings_rounded,
          outlined: Icons.settings_outlined,
          label: '设置',
        ),
      ];
}

class _TabSpec {
  const _TabSpec({
    required this.icon,
    required this.outlined,
    required this.label,
  });
  final IconData icon;
  final IconData outlined;
  final String label;
}

/// 圆角胶囊式底部导航（自绘 NavigationDestination）。
///
/// - 容器：圆角 28，半透明深色 + 细边框（适配深色页面）。
/// - 项：图标 + 文字垂直；选中态有圆形高亮背景 + 主题色填充 + 主题色文字。
/// - 等宽分布，宽度受最大 360 限制（窄屏自适应至屏幕边缘）。
class _PillTabBar extends StatelessWidget {
  const _PillTabBar({
    required this.index,
    required this.onChanged,
    required this.tabs,
  });

  final int index;
  final ValueChanged<int> onChanged;
  final List<_TabSpec> tabs;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: Material(
          color: scheme.surfaceContainerHighest.withValues(alpha: 0.85),
          shape: StadiumBorder(
            side: BorderSide(
              color: scheme.outlineVariant.withValues(alpha: 0.35),
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: SizedBox(
            height: 64,
            child: Row(
              children: [
                for (var i = 0; i < tabs.length; i++)
                  Expanded(
                    child: _PillTabItem(
                      spec: tabs[i],
                      selected: index == i,
                      onTap: () => onChanged(i),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 胶囊 TabBar 中的单个图标 + 文字项。
class _PillTabItem extends StatelessWidget {
  const _PillTabItem({
    required this.spec,
    required this.selected,
    required this.onTap,
  });

  final _TabSpec spec;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final fg = selected ? scheme.primary : scheme.onSurfaceVariant;
    return InkWell(
      onTap: onTap,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // 选中态圆形高亮（围绕图标）
          if (selected)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: scheme.primary.withValues(alpha: 0.18),
                ),
              ),
            ),
          // 图标 + 标签垂直居中
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const SizedBox(height: 4),
              Icon(
                selected ? spec.icon : spec.outlined,
                size: 22,
                color: fg,
              ),
              const SizedBox(height: 2),
              Text(
                spec.label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                  color: fg,
                  height: 1.0,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
