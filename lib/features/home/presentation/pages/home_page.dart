import 'package:flutter/material.dart';

import '../../../audio/presentation/pages/music_page.dart';
import '../../../device/data/device_repository.dart';
import '../../../device/presentation/device_view_model.dart';
import '../../../device/presentation/pages/device_page.dart';
import '../../../lighting/presentation/pages/color_picker_page.dart';
import '../../../settings/settings_page.dart';
import '../widgets/glass_tab_bar.dart';

/// 主页：Liquid Glass 悬浮胶囊底部导航（见 glass_tab_bar.dart）。
///
/// `extendBody: true` 让 body 延伸到导航栏下方，BackdropFilter 才能模糊到
/// 滚动内容，实现真正的毛玻璃悬浮观感（玻璃壳 + 选中态弹簧胶囊滑动）。
/// 页面切换用淡入淡出 + 朝切换方向微移（对齐原型过渡）。
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
      // extendBody 让 body 内容延伸到 bottomNavigationBar 下方，
      // 使 GlassTabBar 的 BackdropFilter 能模糊后方滚动内容。
      extendBody: true,
      body: Stack(
        fit: StackFit.expand,
        children: [
          _buildPage(0, DevicePage(viewModel: _vm)),
          _buildPage(
              1, ColorPickerPage(viewModel: _vm, onGoConnect: () => _go(0))),
          _buildPage(2, MusicPage(viewModel: _vm, onGoConnect: () => _go(0))),
          _buildPage(3, SettingsPage(viewModel: _vm, onGoConnect: () => _go(0))),
        ],
      ),
      bottomNavigationBar: GlassTabBar(index: _index, onChanged: _go),
    );
  }

  /// 带切换动画的页面：当前页淡入原位，其余页淡出并朝切换方向微移。
  /// 所有页常驻树中（不销毁），各 Tab 页状态保留。
  Widget _buildPage(int i, Widget page) {
    final selected = i == _index;
    final reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final offset = selected
        ? Offset.zero
        : Offset(_index < i ? 0.06 : -0.06, 0);
    return IgnorePointer(
      ignoring: !selected,
      child: AnimatedOpacity(
        opacity: selected ? 1 : 0,
        // 减少动态：仅保留瞬时切换，不做位移动画。
        duration: reduceMotion ? Duration.zero : const Duration(milliseconds: 320),
        curve: Curves.easeOutCubic,
        child: AnimatedSlide(
          offset: reduceMotion ? Offset.zero : offset,
          duration: reduceMotion ? Duration.zero : const Duration(milliseconds: 320),
          curve: Curves.easeOutCubic,
          child: page,
        ),
      ),
    );
  }
}
