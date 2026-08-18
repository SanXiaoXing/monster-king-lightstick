import 'dart:ui';

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

    return Scaffold(appBar: AppTopBar(title: '附近设备'), body: body);
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
        '点选设备卡片即可配对连接，无需密码。',
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
                                _shortAddr(device.address),
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

  String _shortAddr(String a) =>
      a.length > 12 ? '${a.substring(0, 6)}…${a.substring(a.length - 4)}' : a;
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
            SizedBox(
              width: 12,
              height: 12,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation(scheme.primary),
              ),
            ),
            const SizedBox(width: 8),
          ],
          Text(
            vm.scanning ? '正在扫描附近的应援棒设备' : '点击设备卡片即可配对',
            style: TextStyle(
              color: scheme.onSurfaceVariant,
              fontSize: 12,
              letterSpacing: 0.1,
            ),
          ),
        ],
      ),
    );
  }
}
