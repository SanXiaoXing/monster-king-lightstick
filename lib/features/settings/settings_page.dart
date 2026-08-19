import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/theme/app_theme.dart';
import '../../shared/theme/spacing.dart';
import '../../shared/widgets/app_top_bar.dart';
import '../../shared/widgets/brand_logo.dart';
import '../../shared/widgets/card_decoration.dart';
import '../device/presentation/device_view_model.dart';
import 'settings_store.dart';

/// 设置页（Dock「设置」Tab）。
///
/// 对齐原型设置屏，只保留真正生效的项：主题模式 / 我的设备 /
/// 灯光偏好（默认亮度）/ 音频律动（默认模式 + 灵敏度）/ 关于。
/// 三个默认值经 [SettingsStore] 持久化，作为音乐页与调色页的初始值。
/// 顶部统一用 [AppTopBar]。
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key, required this.viewModel});

  final DeviceViewModel viewModel;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late double _defaultBrightness;
  late String _defaultMode;
  late double _defaultSensitivity;

  /// 律动模式分段：短标签 ↔ 完整模式名（与音乐页四档一致）。
  static const _modes = <(String, String)>[
    ('单色', '单色律动'),
    ('七彩', '七彩律动'),
    ('强烈', '强烈'),
    ('柔和', '柔和'),
  ];

  @override
  void initState() {
    super.initState();
    _defaultBrightness = SettingsStore.readBrightness();
    _defaultMode = SettingsStore.readMode();
    _defaultSensitivity = SettingsStore.readSensitivity();
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _forgetDevice() async {
    if (widget.viewModel.status.isConnected) {
      await widget.viewModel.disconnect();
    }
    if (!mounted) return;
    _toast('已清除设备记录');
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final vm = widget.viewModel;
    final content = Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            scheme.surface,
            AppColors.isDark(scheme) ? AppColors.darkBg2 : AppColors.lightBg2,
          ],
        ),
      ),
      child: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(child: _Heading()),
          SliverPadding(
            padding: EdgeInsets.symmetric(horizontal: Spacing.pageMargin),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                // 主题模式
                _SectionLabel('主题模式'),
                _GroupCard(children: [
                  ValueListenableBuilder<ThemeMode>(
                    valueListenable: themeModeNotifier,
                    builder: (context, mode, _) {
                      return Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 8),
                        child: SegmentedButton<ThemeMode>(
                          segments: const [
                            ButtonSegment(
                                value: ThemeMode.system,
                                icon: Icon(Icons.brightness_auto, size: 18),
                                label: Text('跟随系统')),
                            ButtonSegment(
                                value: ThemeMode.light,
                                icon: Icon(Icons.light_mode, size: 18),
                                label: Text('浅色')),
                            ButtonSegment(
                                value: ThemeMode.dark,
                                icon: Icon(Icons.dark_mode, size: 18),
                                label: Text('深色')),
                          ],
                          selected: {mode},
                          onSelectionChanged: (s) =>
                              themeModeNotifier.value = s.first,
                        ),
                      );
                    },
                  ),
                ]),
                const SizedBox(height: Spacing.gap16),

                // 我的设备
                _SectionLabel('我的设备'),
                _GroupCard(children: [
                  ListenableBuilder(
                    listenable: vm,
                    builder: (context, _) {
                      final connected = vm.status.isConnected;
                      final name = vm.activeDevice?.name ??
                          vm.activeDevice?.address ??
                          '未连接';
                      return _Tile(
                        icon: connected
                            ? Icons.bluetooth_connected_rounded
                            : Icons.bluetooth_disabled_rounded,
                        iconColor:
                            connected ? AppColors.ok : scheme.onSurfaceVariant,
                        title: connected ? '已连接' : '设备未连接',
                        subtitle: name,
                      );
                    },
                  ),
                  const _Divider(),
                  _Tile(
                    icon: Icons.delete_outline_rounded,
                    iconColor: scheme.error,
                    title: '清除设备记录',
                    subtitle: '断开并遗忘已保存的应援棒',
                    onTap: _forgetDevice,
                  ),
                ]),
                const SizedBox(height: Spacing.gap16),

                // 灯光偏好
                _SectionLabel('灯光偏好'),
                _GroupCard(children: [
                  _Tile(
                    icon: Icons.brightness_6_rounded,
                    title: '默认亮度',
                    subtitle: '${(_defaultBrightness * 100).round()}%',
                    trailing: SizedBox(
                      width: 110,
                      child: Slider(
                        value: _defaultBrightness,
                        onChanged: (v) {
                          setState(() => _defaultBrightness = v);
                          unawaited(SettingsStore.writeBrightness(v));
                        },
                      ),
                    ),
                  ),
                ]),
                const SizedBox(height: Spacing.gap16),

                // 音频律动
                _SectionLabel('音频律动'),
                _GroupCard(children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('默认律动模式',
                            style: TextStyle(
                              color: scheme.onSurface,
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                            )),
                        const SizedBox(height: 10),
                        SizedBox(
                          width: double.infinity,
                          child: SegmentedButton<String>(
                            segments: [
                              for (final (label, mode) in _modes)
                                ButtonSegment(
                                    value: mode, label: Text(label)),
                            ],
                            selected: {_defaultMode},
                            onSelectionChanged: (s) {
                              setState(() => _defaultMode = s.first);
                              unawaited(SettingsStore.writeMode(s.first));
                            },
                            showSelectedIcon: false,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const _Divider(),
                  _Tile(
                    icon: Icons.tune_rounded,
                    title: '默认灵敏度',
                    subtitle: '${(_defaultSensitivity * 100).round()}%',
                    trailing: SizedBox(
                      width: 110,
                      child: Slider(
                        value: _defaultSensitivity,
                        onChanged: (v) {
                          setState(() => _defaultSensitivity = v);
                          unawaited(SettingsStore.writeSensitivity(v));
                        },
                      ),
                    ),
                  ),
                ]),
                const SizedBox(height: Spacing.gap16),

                // 关于
                _SectionLabel('关于'),
                _GroupCard(children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 16, 14, 16),
                    child: Row(
                      children: [
                        const BrandLogo(size: Size(20, 36)),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('万兽之王',
                                  style: TextStyle(
                                    color: scheme.onSurface,
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600,
                                  )),
                              const SizedBox(height: 2),
                              Text('应援棒控制 App',
                                  style: TextStyle(
                                    color: scheme.onSurfaceVariant,
                                    fontSize: 12,
                                  )),
                            ],
                          ),
                        ),
                        Text('v1.0.0',
                            style: TextStyle(
                              color: scheme.onSurfaceVariant,
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                            )),
                      ],
                    ),
                  ),
                ]),
                const SizedBox(height: 16),
                Center(
                  child: Text(
                    'Copyright © 2026 SanXiaoXing.\nAll rights reserved.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: scheme.onSurfaceVariant.withValues(alpha: 0.7),
                      fontSize: 11,
                      height: 1.6,
                    ),
                  ),
                ),
              ]),
            ),
          ),
          // extendBody 下内容延伸到玻璃导航栏下方，留白让末项可滚出遮挡区
          const SliverToBoxAdapter(child: SizedBox(height: Spacing.bottomSafe)),
        ],
      ),
    );

    return Scaffold(appBar: AppTopBar(title: '设置'), body: content);
  }
}

class _Heading extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: EdgeInsets.fromLTRB(Spacing.pageMargin, 14, Spacing.pageMargin, 16),
      child: Text('管理设备、主题、灯光与音频偏好。',
          style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13, height: 1.55)),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Text(text,
          style: TextStyle(
              color: scheme.onSurfaceVariant,
              fontSize: 11,
              letterSpacing: 1,
              fontWeight: FontWeight.w600)),
    );
  }
}

/// iOS 风格分组卡片：圆角容器 + 多个 Tile + 内分隔线。
class _GroupCard extends StatelessWidget {
  const _GroupCard({required this.children});
  final List<Widget> children;
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      decoration: cardDecoration(scheme),
      child: Column(children: children),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.trailing,
    this.onTap,
    this.iconColor,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final c = iconColor ?? scheme.primary;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                color: c.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, size: 16, color: c),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: TextStyle(
                        color: scheme.onSurface,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      )),
                  const SizedBox(height: 2),
                  Text(subtitle,
                      style: TextStyle(
                        color: scheme.onSurfaceVariant,
                        fontSize: 12,
                      )),
                ],
              ),
            ),
            if (trailing != null) ...[
              const SizedBox(width: 8),
              trailing!,
            ],
          ],
        ),
      ),
    );
  }
}

class _Divider extends StatelessWidget {
  const _Divider();
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(left: 56),
      child: Divider(height: 1, color: scheme.outlineVariant),
    );
  }
}
