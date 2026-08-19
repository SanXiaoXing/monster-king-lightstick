import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';

import '../../../../app/theme/app_theme.dart';

/// 底部导航菜单项数据。
class MenuItemSpec {
  final IconData icon;
  final IconData activeIcon;
  final String label;

  const MenuItemSpec({
    required this.icon,
    required this.activeIcon,
    required this.label,
  });
}

/// 底部悬浮菜单栏：Liquid Glass 壳 + 选中态浮动胶囊平滑滑动。
///
/// - 圆角 28px 胶囊容器，半透明表面色 + 1px 描边 + 柔和投影。
/// - BackdropFilter 模糊下方内容（需宿主 Scaffold 开 `extendBody: true`），
///   营造真正悬浮在内容之上的玻璃质感。
/// - 选中态浮动胶囊用主题色填充，跨选中项宽度居中，由临界阻尼弹簧驱动
///   在各项之间平滑滑动。
/// - 选中项图标实心 / 文字反色为白；未选中保持 muted 灰。
class GlassTabBar extends StatelessWidget {
  final int index;
  final ValueChanged<int> onChanged;

  const GlassTabBar({super.key, required this.index, required this.onChanged});

  static const _items = <MenuItemSpec>[
    MenuItemSpec(
      icon: Icons.bluetooth_outlined,
      activeIcon: Icons.bluetooth_rounded,
      label: '连接',
    ),
    MenuItemSpec(
      icon: Icons.palette_outlined,
      activeIcon: Icons.palette_rounded,
      label: '调色',
    ),
    MenuItemSpec(
      icon: Icons.music_note_outlined,
      activeIcon: Icons.music_note_rounded,
      label: '音乐',
    ),
    MenuItemSpec(
      icon: Icons.settings_outlined,
      activeIcon: Icons.settings_rounded,
      label: '设置',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = AppColors.isDark(scheme);
    return SafeArea(
      top: false,
      child: SizedBox(
        // 固定高度 = 胶囊 + 底部留白：Center 在有限高度内不会垂直撑满（贴底），
        // 同时宽度保持有界，内部 Row + Expanded 布局正常。
        height: 64 + 16,
        child: Center(
          child: Padding(
            // 左右留白加大，整体宽度比屏幕收窄 80，胶囊更紧凑。
            padding: const EdgeInsets.fromLTRB(28, 0, 28, 14),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(32),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 28, sigmaY: 28),
                child: Container(
                  height: 64,
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  decoration: BoxDecoration(
                    // 液态玻璃：单一半透明纯色，按明暗自适应表面色 + 不透明度。
                    // - 亮色模式：#F8FAFC + 0.92 alpha，跟页面底色形成清晰高度差；
                    // - 暗色模式：darkBg2（#111318）+ 0.78 alpha。
                    // 两个模式都配 1px 描边 + 投影，让"悬浮"边界更明确。
                    color: isDark
                        ? AppColors.darkBg2.withValues(alpha: 0.78)
                        : const Color(0xFFF8FAFC).withValues(alpha: 0.92),
                    borderRadius: BorderRadius.circular(32),
                    // 1px 描边：亮色用深灰低透明（避免白边看不见），
                    // 暗色用白色低透明（玻璃边缘高光）。
                    border: Border.all(
                      color: isDark
                          ? Colors.white.withValues(alpha: 0.10)
                          : const Color(0xFFCBD5E1).withValues(alpha: 0.6),
                      width: 1.0,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black
                            .withValues(alpha: isDark ? 0.55 : 0.22),
                        blurRadius: 28,
                        offset: const Offset(0, 12),
                      ),
                    ],
                  ),
                  // 用 LayoutBuilder 取得容器宽度，让 Stack 内的
                  // AnimatedPositioned 能直接拿到每格 / 胶囊宽度。
                  // LayoutBuilder 必须在 Stack 外层，否则 Positioned
                  // 会失去 StackParentData 报错。
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      // 每格宽度 = 容器宽 / itemCount（已扣 horizontal padding 8）。
                      final slot = constraints.maxWidth / _items.length;
                      // 胶囊比单格窄 8，左右各留 4，贴近格位、视觉更饱满。
                      final pillWidth = slot - 8;
                      return Stack(
                        children: [
                          // 选中态浮动胶囊：在内容之上覆盖，跟随选中项平滑滑动。
                          _SelectedPill(
                            // LayoutBuilder 坐标系已从容器内边距之后开始，
                            // 不能再加 padding 4，否则胶囊会整体右偏、盖不准。
                            left: index * slot + 4,
                            width: pillWidth,
                          ),
                          // 各菜单项（图标 + 文字上下排列）。
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                            children: [
                              for (var i = 0; i < _items.length; i++)
                                _GlassTab(
                                  spec: _items[i],
                                  selected: i == index,
                                  onTap: () => onChanged(i),
                                ),
                            ],
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 选中态浮动胶囊：主题色填充 + 软阴影。
/// 必须作为 Stack 的直接子节点使用（依赖 StackParentData），
/// left/width 由父级 LayoutBuilder 算好后传入。
///
/// 位置/宽度用临界阻尼弹簧驱动（Apple 移动/重定位默认：damping 1.0、
/// response ≈ 0.4s）：每次切换从当前屏幕值（而非目标值）出发，
/// 途中可被下一次切换随时打断并重定向，不会跳变。
class _SelectedPill extends StatefulWidget {
  final double left;
  final double width;

  const _SelectedPill({required this.left, required this.width});

  @override
  State<_SelectedPill> createState() => _SelectedPillState();
}

class _SelectedPillState extends State<_SelectedPill>
    with SingleTickerProviderStateMixin {
  // 临界阻尼弹簧：stiffness 246 → response ≈ 2π/√246 ≈ 0.40s，无过冲。
  // 临界阻尼 damping = 2√(stiffness·mass) ≈ 31.4。
  static const _spring = SpringDescription(
    mass: 1,
    stiffness: 246,
    damping: 31.4,
  );

  late final AnimationController _ctrl;
  double _left = 0;
  double _width = 0;
  // 本次弹簧的起点（屏幕当前值）与目标值。
  double _fromLeft = 0, _toLeft = 0;
  double _fromWidth = 0, _toWidth = 0;
  bool _reduceMotion = false;

  @override
  void initState() {
    super.initState();
    _left = widget.left;
    _width = widget.width;
    _ctrl = AnimationController.unbounded(vsync: this)
      ..addListener(_onSpringTick);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // 减少动态需在依赖就绪后读取（initState 内不允许查 MediaQuery）。
    _reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
  }

  @override
  void didUpdateWidget(_SelectedPill old) {
    super.didUpdateWidget(old);
    if (old.left == widget.left && old.width == widget.width) return;
    if (_reduceMotion) {
      // 减少动态：不做位移动画，直接落到目标位置。
      _ctrl.stop();
      _left = widget.left;
      _width = widget.width;
      return;
    }
    // 从当前屏幕值（presentation value）出发向新目标弹簧运动。
    // animateWith 会先停掉旧模拟再启动新模拟，快速连续切换也能
    // 安全打断重定向，不会触发「Ticker 已激活」断言。
    _fromLeft = _left;
    _fromWidth = _width;
    _toLeft = widget.left;
    _toWidth = widget.width;
    _ctrl.animateWith(SpringSimulation(_spring, 0, 1, 0));
  }

  void _onSpringTick() {
    setState(() {
      if (!_ctrl.isAnimating) {
        // 弹簧收敛后精确落到目标，避免浮点残留。
        _left = _toLeft;
        _width = _toWidth;
        return;
      }
      final t = _ctrl.value; // 0→1 弹簧进度（临界阻尼单调无过冲）。
      _left = _fromLeft + (_toLeft - _fromLeft) * t;
      _width = _fromWidth + (_toWidth - _fromWidth) * t;
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Positioned(
      left: _left,
      top: 6,
      bottom: 6,
      width: _width,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: scheme.primary,
          borderRadius: BorderRadius.circular(26),
          boxShadow: [
            BoxShadow(
              color: scheme.primary.withValues(alpha: 0.32),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
        ),
      ),
    );
  }
}

/// 单个菜单项：图标 + 文字上下排列。选中态切换实心图标 + 文字反色为白。
class _GlassTab extends StatelessWidget {
  final MenuItemSpec spec;
  final bool selected;
  final VoidCallback onTap;

  const _GlassTab({
    required this.spec,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // 选中态文字 / 图标反色为白，未选中保持 muted 灰。
    final fgColor = selected ? Colors.white : scheme.onSurfaceVariant;
    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: SizedBox(
          height: double.infinity,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              // 图标：选中用实心，未选中用描边；颜色由 fgColor 驱动。
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                transitionBuilder: (child, anim) => FadeTransition(
                  opacity: anim,
                  child: ScaleTransition(scale: anim, child: child),
                ),
                child: Icon(
                  selected ? spec.activeIcon : spec.icon,
                  key: ValueKey(selected),
                  size: 22,
                  color: fgColor,
                ),
              ),
              const SizedBox(height: 2),
              AnimatedDefaultTextStyle(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOutCubic,
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w600,
                  color: fgColor,
                  letterSpacing: 0.1,
                ),
                child: Text(spec.label),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
