import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../../../../app/theme/app_theme.dart';
import '../../../../shared/theme/spacing.dart';
import '../../../../shared/widgets/app_top_bar.dart';
import '../../../../shared/widgets/brand_logo.dart';
import '../../data/device_repository.dart';
import '../../domain/device_state.dart';
import '../../domain/lightstick.dart';
import '../device_view_model.dart';

/// 连接页（Dock「连接」Tab）。
///
/// 对齐原型连接屏：连接胶囊 + 「附近设备」标题 + 设备卡片（logo/名称/信号/
/// 断开按钮）+ 扫描指示。顶部统一用 [AppTopBar]（由本页自带 Scaffold 托管）。
class DevicePage extends StatefulWidget {
  const DevicePage({super.key, this.viewModel});

  final DeviceViewModel? viewModel;

  @override
  State<DevicePage> createState() => _DevicePageState();
}

class _DevicePageState extends State<DevicePage> {
  late final DeviceViewModel _vm;
  late final bool _ownsVm;

  @override
  void initState() {
    super.initState();
    _ownsVm = widget.viewModel == null;
    _vm = widget.viewModel ?? DeviceViewModel(DeviceRepository());
    if (_ownsVm) _vm.init();
  }

  @override
  void dispose() {
    if (_ownsVm) _vm.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final body = ListenableBuilder(
      listenable: _vm,
      builder: (context, _) {
        return Container(
          decoration: _pageDecoration(context),
          child: CustomScrollView(
            slivers: [
              const SliverToBoxAdapter(child: _PageHead()),
              SliverPadding(
                padding: EdgeInsets.symmetric(horizontal: Spacing.pageMargin),
                sliver: _DeviceList(vm: _vm),
              ),
              SliverToBoxAdapter(child: _ScanNote(vm: _vm)),
              // extendBody 下内容延伸到玻璃导航栏下方，留白让末项可滚出遮挡区
              const SliverToBoxAdapter(child: SizedBox(height: Spacing.bottomSafe)),
            ],
          ),
        );
      },
    );

    return Scaffold(
      appBar: AppTopBar(
        title: '附近设备',
        actions: [
          // 把 ListenableBuilder 放在 actions 里，以拿到 _vm 的 scanning
          // 状态并跳到按钮上。Scaffold 的 appBar 是 PreferredSizeWidget，
          // 但 actions 仅是普通 Widget 列表，所以这里可以直接塞进去。
          ListenableBuilder(
            listenable: _vm,
            builder: (context, _) => _ScanActionButton(
              scanning: _vm.scanning,
              onTap: _vm.scan,
              tooltip: '扫描附近的应援棒',
            ),
          ),
          const SizedBox(width: 12),
        ],
      ),
      body: body,
    );
  }

  BoxDecoration _pageDecoration(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dark = AppColors.isDark(scheme);
    return BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [scheme.surface, dark ? AppColors.darkBg2 : AppColors.lightBg2],
      ),
    );
  }
}

class _PageHead extends StatelessWidget {
  const _PageHead();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: EdgeInsets.fromLTRB(Spacing.pageMargin, 14, Spacing.pageMargin, 16),
      child: Text(
        '点选设备卡片即可配对连接',
        style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13, height: 1.55),
      ),
    );
  }
}

class _DeviceList extends StatelessWidget {
  const _DeviceList({required this.vm});
  final DeviceViewModel vm;

  @override
  Widget build(BuildContext context) {
    final devices = vm.devices;
    if (devices.isEmpty) {
      // 首次进入自动搜索：扫描中显示脉冲骨架屏，结束后显示点击扫描入口
      return SliverToBoxAdapter(
        child: vm.scanning
            ? const _DeviceSkeleton()
            : Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Center(
                  child: InkWell(
                    onTap: () => vm.scan(),
                    borderRadius: BorderRadius.circular(100),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 18, vertical: 8),
                      child: Text(
                        '点击扫描附近设备',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.primary,
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
      );
    }
    return SliverList(
      delegate: SliverChildBuilderDelegate(
        (context, i) => _DeviceCard(device: devices[i], vm: vm),
        childCount: devices.length,
      ),
    );
  }
}

class _DeviceCard extends StatelessWidget {
  const _DeviceCard({required this.device, required this.vm});

  final Lightstick device;
  final DeviceViewModel vm;

  bool get _isActive =>
      vm.activeDevice?.address == device.address &&
      vm.connection == DeviceConnectionState.connected;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final active = _isActive;
    return Padding(
      padding: const EdgeInsets.only(bottom: Spacing.gap12),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: Material(
            color: (active ? AppColors.accentSoft : scheme.surfaceContainerLow)
                .withValues(alpha: 0.6),
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: vm.scanning ? null : () => vm.connect(device),
              child: Container(
                padding: const EdgeInsets.all(Spacing.cardPadding),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: active ? scheme.primary : scheme.outlineVariant,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        SizedBox(
                          width: 18,
                          height: 34,
                          child: BrandLogo(
                            size: const Size(18, 34),
                            color: scheme.primary,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                device.name ?? '未命名设备',
                                style: TextStyle(
                                  color: scheme.onSurface,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: 0.1,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 2),
                              Text(
                                device.address,
                                style: TextStyle(
                                  color: scheme.onSurfaceVariant,
                                  fontSize: 11,
                                  letterSpacing: 0.1,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (active)
                          _DiscBtn(onTap: vm.disconnect)
                        else
                          Text(
                            '未配对',
                            style: TextStyle(
                              color: scheme.onSurfaceVariant,
                              fontSize: 11,
                              letterSpacing: 0.1,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Divider(height: 1, color: scheme.outlineVariant),
                    const SizedBox(height: 8),
                    _SignalMeta(rssi: device.rssi),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

}

/// 断开按钮：仅已连接设备显示。
class _DiscBtn extends StatelessWidget {
  const _DiscBtn({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(100),
      child: Container(
        width: 28,
        height: 28,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: AppColors.accentSoft,
          shape: BoxShape.circle,
        ),
        child: Icon(Icons.link_off_rounded, size: 15, color: scheme.primary),
      ),
    );
  }
}

class _SignalMeta extends StatelessWidget {
  const _SignalMeta({required this.rssi});
  final int? rssi;

  int _level(int? r) {
    if (r == null) return 0;
    if (r >= -50) return 4;
    if (r >= -60) return 3;
    if (r >= -70) return 2;
    return 1;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Text(
          '信号',
          style: TextStyle(
            color: scheme.onSurfaceVariant,
            fontSize: 10,
            letterSpacing: 1,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(width: 8),
        _SignalBars(level: _level(rssi)),
        const SizedBox(width: 6),
        Text(
          rssi != null ? '$rssi dBm' : '—',
          style: TextStyle(
            color: scheme.onSurface,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _SignalBars extends StatelessWidget {
  const _SignalBars({required this.level});
  final int level; // 0-4

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    const heights = [4.0, 7.0, 10.0, 12.0];
    return SizedBox(
      height: 12,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (var i = 0; i < 4; i++)
            Padding(
              padding: const EdgeInsets.only(right: 2),
              child: Container(
                width: 3,
                height: heights[i],
                decoration: BoxDecoration(
                  color: i < level ? scheme.primary : scheme.outline,
                  borderRadius: BorderRadius.circular(1),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// 扫描中的骨架屏：3 张脉冲呼吸的占位卡片，替代"点击扫描"空态。
class _DeviceSkeleton extends StatefulWidget {
  const _DeviceSkeleton();

  @override
  State<_DeviceSkeleton> createState() => _DeviceSkeletonState();
}

class _DeviceSkeletonState extends State<_DeviceSkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 800),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: Tween<double>(begin: 0.5, end: 0.95).animate(
        CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
      ),
      child: Column(
        children: [
          for (var i = 0; i < 3; i++) _SkeletonCard(),
        ],
      ),
    );
  }
}

/// 骨架占位卡片：灰条模拟品牌 logo / 名称 / 地址 / 右侧状态。
class _SkeletonCard extends StatelessWidget {
  const _SkeletonCard();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final bar = scheme.surfaceContainerHighest;
    Widget block(double w, double h) => Container(
          width: w,
          height: h,
          decoration: BoxDecoration(
            color: bar,
            borderRadius: BorderRadius.circular(4),
          ),
        );
    return Padding(
      padding: const EdgeInsets.only(bottom: Spacing.gap12),
      child: Container(
        height: 100,
        padding: const EdgeInsets.all(Spacing.cardPadding),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: scheme.outlineVariant),
        ),
        child: Row(
          children: [
            block(18, 34), // 品牌 logo 占位
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  block(140, 12), // 设备名
                  const SizedBox(height: 8),
                  block(90, 10), // 地址
                ],
              ),
            ),
            block(40, 12), // 右侧状态/按钮占位
          ],
        ),
      ),
    );
  }
}

class _ScanNote extends StatelessWidget {
  const _ScanNote({required this.vm});
  final DeviceViewModel vm;

  @override
  Widget build(BuildContext context) {
    if (!vm.scanning && vm.devices.isNotEmpty) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: EdgeInsets.fromLTRB(Spacing.pageMargin, 14, Spacing.pageMargin, 0),
      child: Row(
        children: [
          if (vm.scanning) ...[
            const _ScanPulseRing(size: 20),
            const SizedBox(width: 12),
          ],
          Flexible(
            child: vm.scanning
                ? const _BreathingScanLabel(text: '正在扫描附近的应援棒设备')
                : Text(
                    '点击设备卡片即可配对',
                    style: TextStyle(
                      color: scheme.onSurfaceVariant,
                      fontSize: 12,
                      letterSpacing: 0.1,
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

/// 扫描中的脉冲环形指示器。
///
/// 动画：
/// - 3 个同步护航、从圆心向外扩的圆，间隔 1/3 周期间隔启动；
/// - easeOutCubic 让初始撞中后往外推时越走越缓；
/// - 中间还有一个轻微「哑呼」键（0.30 半径 × 1.20 硕峰）的实心点。
///
/// 使用 [RepaintBoundary] 隔离重绘到仅 20×20 范围，
/// 不带动 device 卡 / list 同时刷新。
class _ScanPulseRing extends StatefulWidget {
  const _ScanPulseRing({required this.size});

  final double size;

  @override
  State<_ScanPulseRing> createState() => _ScanPulseRingState();
}

class _ScanPulseRingState extends State<_ScanPulseRing>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return RepaintBoundary(
      child: SizedBox(
        width: widget.size,
        height: widget.size,
        child: AnimatedBuilder(
          animation: _ctrl,
          builder: (context, _) => CustomPaint(
            painter: _PulseRingsPainter(
              t: _ctrl.value,
              color: scheme.primary,
            ),
          ),
        ),
      ),
    );
  }
}

class _PulseRingsPainter extends CustomPainter {
  _PulseRingsPainter({required this.t, required this.color});

  final double t; // 0..1 循环
  final Color color;

  static const _ringCount = 3;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final maxR = size.width / 2 - 1.0; // 留 约 1 px 描边边距
    final dotR = maxR * 0.30;

    // 3 个圈护航。圈 i 起始于 t = i / ringCount，
    // 每圈走完 / ringCount 后被下一圈接替覆盖。
    for (var i = 0; i < _ringCount; i++) {
      final startT = i / _ringCount;
      var p = (t - startT) * _ringCount;
      if (p < 0) p += 1; // 周期性包裹（不会跳出，因为 _ctrl.repeat()）
      if (p > 1) continue;
      final r = dotR + (maxR - dotR) * Curves.easeOutCubic.transform(p);
      final alpha = (1 - p) * 0.55;
      final stroke = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = color.withValues(alpha: alpha);
      canvas.drawCircle(center, r, stroke);
    }

    // 中心点轻微 «哑呼»：硕峰跳 1.0 → 1.2 → 1.0，0.9 s 周期与环创建错开。
    final dotWave = 1 + 0.20 * (1 - math.pow(2 * t - 1, 2));
    final dotPaint = Paint()
      ..style = PaintingStyle.fill
      ..color = color;
    canvas.drawCircle(center, dotR * dotWave, dotPaint);
  }

  @override
  bool shouldRepaint(_PulseRingsPainter old) => old.t != t;
}

/// 扫描中状态文案。文字颜色随正弦波在 muted 与 primary 之间软呼吸，
/// 1.4 s 为一周期，不仅是 alpha 而是色相变化，避免 Opacity 边缘抗锯齿问题。
class _BreathingScanLabel extends StatefulWidget {
  const _BreathingScanLabel({required this.text});

  final String text;

  @override
  State<_BreathingScanLabel> createState() => _BreathingScanLabelState();
}

class _BreathingScanLabelState extends State<_BreathingScanLabel>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _ctrl,
        builder: (context, _) {
          // (1 - sin)/2 产生一个 0..1 的柔和呼吸波形。
          final wave = (1 - math.sin(_ctrl.value * 2 * math.pi)) / 2;
          // lerp 量在 0..0.7，从 muted 偏到偏亮（不全量 fully primary，过多干扰阅读）。
          final color = Color.lerp(scheme.onSurfaceVariant, scheme.primary, wave * 0.7);
          return Text(
            widget.text,
            style: TextStyle(
              color: color,
              fontSize: 12,
              letterSpacing: 0.1,
            ),
          );
        },
      ),
    );
  }
}

/// 连接页右上角扫描按钮。
///
/// 视觉/线程：
/// - 38×38 圆角胶囊，外圈描边，底色 surfaceContainerHigh。
/// - 扫描中（[scanning] 为 true）：加载图标 [Icons.refresh_rounded] 以 1.1 s
///   / 转一圈的速度持续旋转，刷描边 + 主体色为 primary，表格化的「扫描中」视觉。
///
/// 点击反渣：
/// - 按下：scale 1.0 → 0.92 走 160 ms easeOutCubic（按下时立即出现，体感实）。
/// - 松开 / 取消：scale 由 0.92 走 300 ms easeOutBack 弹回 1.0，
///   带轻微锅过冲（与 dock / dock 胶囊同步同個 spring 语调）。
/// - 点击间的视觉反馈只是微量反渣（不需要震动反渣的体感干涉，
///   haptics 留给系统默认的 InkWell）。
/// - 点击开销：onTap = 触发 [DeviceViewModel.scan]，scan 内部已有
///   「扫描中不再叠启动」的防抖。
class _ScanActionButton extends StatefulWidget {
  const _ScanActionButton({
    required this.scanning,
    required this.onTap,
    this.tooltip,
  });

  final bool scanning;
  final VoidCallback onTap;
  final String? tooltip;

  @override
  State<_ScanActionButton> createState() => _ScanActionButtonState();
}

class _ScanActionButtonState extends State<_ScanActionButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _spin;
  late final AnimationController _bounce;

  @override
  void initState() {
    super.initState();
    _spin = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    );
    _bounce = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
      value: 1.0,
    );
    if (widget.scanning) _spin.repeat();
  }

  @override
  void didUpdateWidget(_ScanActionButton old) {
    super.didUpdateWidget(old);
    if (widget.scanning != old.scanning) {
      if (widget.scanning) {
        // 从当前角度续传，避免从 0 重新跳。
        _spin.repeat();
      } else {
        _spin.stop();
        _spin.value = 0;
      }
    }
  }

  @override
  void dispose() {
    _spin.dispose();
    _bounce.dispose();
    super.dispose();
  }

  void _press() {
    _bounce.animateTo(0.92, duration: const Duration(milliseconds: 160), curve: Curves.easeOutCubic);
  }

  // tapUp / tapCancel 走同一路径：先把 scale 弹回 1.0，
  // 只有真切完成回调时才同时调 widget.onTap。
  void _release(bool fireTap) {
    _bounce.animateTo(
      1.0,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutBack,
    );
    if (fireTap) widget.onTap();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final scanning = widget.scanning;
    final core = AnimatedBuilder(
      animation: Listenable.merge([_spin, _bounce]),
      builder: (context, _) {
        final scale = _bounce.value;
        final angle = _spin.value * 2 * 3.14159;
        // border / icon 颜色也要反应「扫描中」状态。
        return Transform.scale(
          scale: scale,
          child: Container(
            width: 38,
            height: 38,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: scanning
                  ? scheme.primaryContainer.withValues(alpha: 0.45)
                  : scheme.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(13),
              border: Border.all(
                color: scanning ? scheme.primary : scheme.outlineVariant,
                width: 1,
              ),
            ),
            child: Transform.rotate(
              angle: angle,
              child: Icon(
                Icons.refresh_rounded,
                size: 19,
                color: scanning ? scheme.primary : scheme.onSurface,
              ),
            ),
          ),
        );
      },
    );
    final wrapped = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => _press(),
      onTapUp: (_) => _release(true),
      onTapCancel: () => _release(false),
      child: core,
    );
    if (widget.tooltip == null) return wrapped;
    return Tooltip(message: widget.tooltip!, child: wrapped);
  }
}
