import 'package:flutter/material.dart';

import '../../app/theme/app_theme.dart';
import '../../shared/widgets/brand_logo.dart';
import '../device/presentation/device_view_model.dart';

/// 设置页（Dock「设置」Tab）。
///
/// 对齐原型设置屏：4 分组卡片（我的设备 / 灯光偏好 / 音频律动 / 关于），
/// 顶部主题模式 SegmentedButton。`embedded=true` 时无 AppBar，由 Dock 壳托管。
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key, required this.viewModel, this.embedded = false});

  final DeviceViewModel viewModel;
  final bool embedded;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  double _defaultBrightness = 0.8;
  final String _defaultMode = '单色律动';
  double _defaultSensitivity = 0.6;

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
            padding: const EdgeInsets.symmetric(horizontal: 18),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                // 主题模式（顶部独立段）
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
                const SizedBox(height: 22),

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
                const SizedBox(height: 22),

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
                        onChanged: (v) =>
                            setState(() => _defaultBrightness = v),
                      ),
                    ),
                  ),
                  const _Divider(),
                  _Tile(
                    icon: Icons.lightbulb_rounded,
                    title: '启动灯效',
                    subtitle: '常亮',
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () => _toast('启动灯效选择待 Rust 协议层落地'),
                  ),
                  const _Divider(),
                  _Tile(
                    icon: Icons.palette_rounded,
                    title: '记忆上次颜色',
                    subtitle: '0A84FF',
                    trailing: Switch(
                      value: true,
                      onChanged: (v) =>
                          _toast(v ? '已开启颜色记忆' : '颜色记忆已关闭'),
                    ),
                  ),
                ]),
                const SizedBox(height: 22),

                // 音频律动
                _SectionLabel('音频律动'),
                _GroupCard(children: [
                  _Tile(
                    icon: Icons.tune_rounded,
                    title: '默认灵敏度',
                    subtitle: '${(_defaultSensitivity * 100).round()}%',
                    trailing: SizedBox(
                      width: 110,
                      child: Slider(
                        value: _defaultSensitivity,
                        onChanged: (v) =>
                            setState(() => _defaultSensitivity = v),
                      ),
                    ),
                  ),
                  const _Divider(),
                  _Tile(
                    icon: Icons.tonality_rounded,
                    title: '默认律动模式',
                    subtitle: _defaultMode,
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () => _toast('律动模式选择待音频层落地'),
                  ),
                  const _Divider(),
                  _Tile(
                    icon: Icons.equalizer_rounded,
                    title: '频谱样式',
                    subtitle: '镜像柱状+波形线',
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () => _toast('频谱样式暂固定'),
                  ),
                ]),
                const SizedBox(height: 22),

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
                  const _Divider(),
                  _Tile(
                    icon: Icons.code_rounded,
                    title: '开源协议',
                    subtitle: 'MIT',
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () => _toast('协议页面待构建'),
                  ),
                  const _Divider(),
                  _Tile(
                    icon: Icons.feedback_rounded,
                    title: '反馈与建议',
                    subtitle: '帮助改进',
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () => _toast('反馈通道待接入'),
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
        ],
      ),
    );

    if (widget.embedded) {
      return SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.only(bottom: 110),
          child: content,
        ),
      );
    }
    return Scaffold(appBar: AppBar(title: const Text('设置')), body: content);
  }
}

class _Heading extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('设置',
              style: TextStyle(
                  color: scheme.onSurface,
                  fontSize: 26,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.4,
                  height: 1.1)),
          const SizedBox(height: 6),
          Text('管理设备、主题、灯光与音频偏好。',
              style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13, height: 1.55)),
        ],
      ),
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
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: scheme.outlineVariant),
      ),
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
