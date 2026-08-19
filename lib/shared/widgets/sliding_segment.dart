import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';

/// 滑动分段选择器：外层 pill 容器 + 透明 cell + 一颗悬浮胶囊，
/// 以临界阻尼弹簧在档位间物理滑动。
///
/// 用于主题切换（跟随 / 浅色 / 深色）与律动模式（单色 / 七彩 / 强烈 / 柔和）
/// 等场景。选中态胶囊与 Dock 选中态使用同一份弹簧参数
/// （mass 1 / stiffness 246 / damping 31.4，response ≈ 0.40 s，无过冲），
/// 全 App 滑动胶囊零漂移。
///
/// [options] 为 (值, 显示名) 列表，[selected] 必须是其中一个值；
/// [onChanged] 回传被点的值。[semanticsPrefix] 可选，为无障碍标签
/// 提供前缀（如「主题」→「主题：跟随」）。
class SlidingSegment<T> extends StatefulWidget {
  const SlidingSegment({
    super.key,
    required this.options,
    required this.selected,
    required this.onChanged,
    this.semanticsPrefix,
  });

  final List<(T, String)> options;
  final T selected;
  final ValueChanged<T> onChanged;

  /// 无障碍前缀，如「主题」「律动模式」，组成「主题：跟随」。
  final String? semanticsPrefix;

  int indexOf(T value) {
    for (var i = 0; i < options.length; i++) {
      if (options[i].$1 == value) return i;
    }
    return 0;
  }

  @override
  State<SlidingSegment<T>> createState() => _SlidingSegmentState<T>();
}

class _SlidingSegmentState<T> extends State<SlidingSegment<T>> {
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final options = widget.options;
    final activeIdx = widget.indexOf(widget.selected);
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: scheme.outlineVariant),
      ),
      // LayoutBuilder 必须在 Stack 外层，否则 Positioned 失去 StackParentData。
      child: LayoutBuilder(
        builder: (context, constraints) {
          // 每格宽度 = 内容区宽 / 档位数，pill 两侧各留 4，贴近格位、视觉饱满。
          final count = options.length;
          final slot = constraints.maxWidth / count;
          final pillW = slot - 8;
          return Stack(
            children: [
              _SlidingPill(
                left: activeIdx * slot + 4,
                width: pillW,
              ),
              Row(
                children: [
                  for (var i = 0; i < count; i++)
                    Expanded(
                      child: _SegmentCell(
                        label: options[i].$2,
                        active: i == activeIdx,
                        onTap: () => widget.onChanged(options[i].$1),
                        semanticsLabel: widget.semanticsPrefix == null
                            ? null
                            : '${widget.semanticsPrefix}：${options[i].$2}',
                      ),
                    ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}

/// 选中态滑动胶囊：与 Dock 选中态使用同一份临界阻尼弹簧
/// （mass 1 / stiffness 246 / damping 31.4，response ≈ 0.40 s，无过冲）。
/// 必须作为 Stack 的直接子节点使用（依赖 StackParentData）。
/// left / width 由父级 LayoutBuilder 算好后传入，弹簧可中断重定向、无跳变。
class _SlidingPill extends StatefulWidget {
  const _SlidingPill({required this.left, required this.width});
  final double left;
  final double width;

  @override
  State<_SlidingPill> createState() => _SlidingPillState();
}

class _SlidingPillState extends State<_SlidingPill>
    with SingleTickerProviderStateMixin {
  // 临界阻尼弹簧：stiffness 246 → response ≈ 2π/√246 ≈ 0.40 s，无过冲。
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
  void didUpdateWidget(_SlidingPill old) {
    super.didUpdateWidget(old);
    if (old.left == widget.left && old.width == widget.width) return;
    if (_reduceMotion) {
      // 减少动态：不做位移动画，直接落到目标位置。
      _ctrl.stop();
      _left = widget.left;
      _width = widget.width;
      setState(() {});
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
      top: 0,
      bottom: 0,
      width: _width,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: scheme.primary,
          borderRadius: BorderRadius.circular(999),
          boxShadow: [
            BoxShadow(
              color: scheme.primary.withValues(alpha: 0.32),
              blurRadius: 14,
              offset: const Offset(0, 6),
            ),
          ],
        ),
      ),
    );
  }
}

/// 档位 cell：透明，仅负责点击 + 文字颜色翻转（选中→白）。
/// 背景与阴影完全交给 [_SlidingPill]。
class _SegmentCell extends StatelessWidget {
  const _SegmentCell({
    required this.label,
    required this.active,
    required this.onTap,
    this.semanticsLabel,
  });

  final String label;
  final bool active;
  final VoidCallback onTap;
  final String? semanticsLabel;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final cell = Container(
      padding: const EdgeInsets.symmetric(vertical: 9),
      alignment: Alignment.center,
      // 纯透明，背景由 [_SlidingPill] 呈现。
      child: AnimatedDefaultTextStyle(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.4,
          color: active ? Colors.white : scheme.onSurfaceVariant,
        ),
        child: Text(label),
      ),
    );
    if (semanticsLabel == null) {
      return GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: cell,
      );
    }
    return Semantics(
      label: semanticsLabel,
      selected: active,
      button: true,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: cell,
      ),
    );
  }
}
