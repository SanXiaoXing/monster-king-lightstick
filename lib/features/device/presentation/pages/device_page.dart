import 'dart:ui';

import 'package:flutter/material.dart';

import '../../../../app/theme/app_theme.dart';
import '../../../../shared/widgets/brand_logo.dart';
import '../../data/device_repository.dart';
import '../../domain/device_state.dart';
import '../../domain/lightstick.dart';
import '../device_view_model.dart';

/// 连接页（Dock「连接」Tab）。
///
/// 对齐原型连接屏：连接胶囊 + 「附近设备」标题 + 设备卡片（logo/名称/信号/
/// 断开按钮）+ 扫描指示。`embedded=true` 时无 AppBar，由 Dock 壳托管。
class DevicePage extends StatefulWidget {
  const DevicePage({super.key, this.viewModel, this.embedded = false});

  final DeviceViewModel? viewModel;

  /// true = 作为 Dock Tab 嵌入（无 AppBar，底部留 Dock 高度）；false = 独立推页。
  final bool embedded;

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
              SliverToBoxAdapter(child: _ConnectPill(vm: _vm)),
              const SliverToBoxAdapter(child: _PageHead()),
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 18),
                sliver: _DeviceList(vm: _vm),
              ),
              SliverToBoxAdapter(child: _ScanNote(vm: _vm)),
            ],
          ),
        );
      },
    );

    if (widget.embedded) {
      return SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.only(bottom: 110), // Dock 高度 + 间距
          child: body,
        ),
      );
    }
    return Scaffold(appBar: AppBar(title: const Text('连接设备')), body: body);
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

/// 连接胶囊：圆点 + 状态文案。
class _ConnectPill extends StatelessWidget {
  const _ConnectPill({required this.vm});
  final DeviceViewModel vm;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final st = vm.connection;
    final (color, text) = switch (st) {
      DeviceConnectionState.connected => (
        AppColors.ok,
        '已连接 ${vm.activeDevice?.name ?? vm.activeDevice?.address ?? ''}'.trim()
      ),
      DeviceConnectionState.connecting ||
      DeviceConnectionState.disconnecting => (AppColors.warn, '连接中…'),
      DeviceConnectionState.error => (scheme.error, '连接异常'),
      DeviceConnectionState.disconnected => (scheme.outline, '未连接'),
    };
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 12, 18, 0),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          decoration: BoxDecoration(
            color: scheme.surfaceContainer.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(100),
            border: Border.all(color: scheme.outlineVariant),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: color,
                  boxShadow: [
                    BoxShadow(color: color.withValues(alpha: 0.55), blurRadius: 8),
                  ],
                ),
              ),
              const SizedBox(width: 7),
              Text(
                text,
                style: TextStyle(
                    color: scheme.onSurfaceVariant,
                    fontSize: 12,
                    letterSpacing: 0.2),
              ),
            ],
          ),
        ),
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
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '附近设备',
            style: TextStyle(
              color: scheme.onSurface,
              fontSize: 26,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.4,
              height: 1.1,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '点选设备卡片即可配对连接，无需密码。',
            style: TextStyle(
                color: scheme.onSurfaceVariant, fontSize: 13, height: 1.55),
          ),
        ],
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
      return SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 24),
          child: Center(
            child: InkWell(
              onTap: vm.scanning ? null : () => vm.scan(),
              borderRadius: BorderRadius.circular(100),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
                child: Text(
                  vm.scanning ? '正在搜索…' : '点击扫描附近设备',
                  style: TextStyle(
                    color: vm.scanning
                        ? Theme.of(context).colorScheme.onSurfaceVariant
                        : Theme.of(context).colorScheme.primary,
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
      padding: const EdgeInsets.only(bottom: 10),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: Material(
            color: (active ? AppColors.accentSoft : scheme.surfaceContainerLow)
                .withValues(alpha: 0.6),
            child: InkWell(
              borderRadius: BorderRadius.circular(22),
              onTap: vm.scanning ? null : () => vm.connect(device),
              child: Container(
                padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(22),
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

class _ScanNote extends StatelessWidget {
  const _ScanNote({required this.vm});
  final DeviceViewModel vm;

  @override
  Widget build(BuildContext context) {
    if (!vm.scanning && vm.devices.isNotEmpty) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 14, 18, 0),
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
