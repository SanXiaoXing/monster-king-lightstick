import 'package:flutter/material.dart';

import '../../app/router/app_router.dart';
import '../../app/theme/app_theme.dart';
import '../../shared/theme/spacing.dart';
import '../../shared/widgets/app_top_bar.dart';
import '../../shared/widgets/brand_logo.dart';
import '../../shared/widgets/card_decoration.dart';
import '../../shared/widgets/sliding_segment.dart';
import '../about/tips_page.dart';
import '../device/presentation/device_view_model.dart';

/// 设置页（Dock「设置」Tab）。
///
/// 仅保留 4 项（与最新需求一致）：
/// 1. 显示模式（主题选择器，3 选 1 + 滑动胶囊物理反馈）
/// 2. 已连接设备（当前连接状态，单行展示，不提供「清除」子入口）
/// 3. 温馨提示（点击跳 [TipsPage]）
/// 4. 关于（品牌 + 版本信息，纯展示）
///
/// 主题选择器与音乐律动选择器共用共享组件 [SlidingSegment]
/// （同一份临界阻尼弹簧：mass 1 / stiffness 246 / damping 31.4，
/// 与 Dock 选中态同源，全 App 零漂移）。
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key, required this.viewModel, this.onGoConnect});

  final DeviceViewModel viewModel;

  /// 未连接时「去连接」回调（Dock 宿主切换 Tab；独立页可不传）。
  final VoidCallback? onGoConnect;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  void _openTips() {
    Navigator.of(context).push(AppRouter.page(const TipsPage()));
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
          const SliverToBoxAdapter(child: _Heading()),
          SliverPadding(
            padding: EdgeInsets.symmetric(horizontal: Spacing.pageMargin),
            sliver: SliverList(
              delegate: SliverChildListDelegate.fixed([
                // 1. 显示模式：3 文本滑动胶囊（跟随 / 浅色 / 深色）
                const _SectionLabel('显示模式'),
                _GroupCard(
                  padding: const EdgeInsets.fromLTRB(14, 14, 14, 16),
                  children: [
                    ValueListenableBuilder<ThemeMode>(
                      valueListenable: themeModeNotifier,
                      builder: (context, mode, _) {
                        return SlidingSegment<ThemeMode>(
                          semanticsPrefix: '主题',
                          options: const [
                            (ThemeMode.system, '跟随'),
                            (ThemeMode.light, '浅色'),
                            (ThemeMode.dark, '深色'),
                          ],
                          selected: mode,
                          onChanged: (m) => themeModeNotifier.value = m,
                        );
                      },
                    ),
                  ],
                ),
                const SizedBox(height: Spacing.gap16),

                // 2. 已连接设备：单行状态展示
                const _SectionLabel('已连接设备'),
                _GroupCard(children: [
                  ListenableBuilder(
                    listenable: vm,
                    builder: (context, _) {
                      final connected = vm.isConnected;
                      final name = vm.activeDevice?.name ??
                          vm.activeDevice?.address ??
                          '未连接';
                      return _NavTile(
                        icon: connected
                            ? Icons.bluetooth_connected_rounded
                            : Icons.bluetooth_disabled_rounded,
                        iconColor:
                            connected ? AppColors.ok : scheme.onSurfaceVariant,
                        title: connected ? '已连接' : '设备未连接',
                        subtitle: name,
                        chevron: !connected,
                        onTap: connected ? null : widget.onGoConnect,
                      );
                    },
                  ),
                ]),
                const SizedBox(height: Spacing.gap16),

                // 3. 温馨提示：点击进入安全提示页
                const _SectionLabel('温馨提示'),
                _GroupCard(children: [
                  _NavTile(
                    icon: Icons.warning_amber_rounded,
                    iconColor: scheme.primary,
                    title: '温馨提示',
                    subtitle: '阅读安全提示',
                    chevron: true,
                    onTap: _openTips,
                  ),
                ]),
                const SizedBox(height: Spacing.gap16),

                // 4. 关于：品牌 + 版本信息（纯展示）
                const _SectionLabel('关于'),
                _GroupCard(
                  padding: const EdgeInsets.fromLTRB(14, 16, 14, 16),
                  children: [
                    Row(
                      children: [
                        const BrandLogo(size: Size(20, 36)),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '万兽之王',
                                style: TextStyle(
                                  color: scheme.onSurface,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '应援棒控制 App',
                                style: TextStyle(
                                  color: scheme.onSurfaceVariant,
                                  fontSize: 12,
                                  letterSpacing: 0.2,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Text(
                          'v1.0.0',
                          style: TextStyle(
                            color: scheme.onSurfaceVariant,
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                Center(
                  child: Text(
                    '万兽之王应援棒控制 · 字节级协议对齐',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: scheme.onSurfaceVariant.withValues(alpha: 0.65),
                      fontSize: 11,
                      letterSpacing: 0.4,
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
  const _Heading();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: EdgeInsets.fromLTRB(Spacing.pageMargin, 14, Spacing.pageMargin, 16),
      child: Text(
        '管理显示模式、设备状态与提示。',
        style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13, height: 1.55),
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
      child: Text(
        text,
        style: TextStyle(
          color: scheme.onSurfaceVariant,
          fontSize: 11,
          letterSpacing: 1,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// 分组卡片：圆角容器，可指定内边距（默认无 padding，由子节点自带）。
class _GroupCard extends StatelessWidget {
  const _GroupCard({required this.children, this.padding});

  final List<Widget> children;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final base = cardDecoration(scheme);
    if (padding == null) return Container(decoration: base, child: Column(children: children));
    return Container(
      decoration: base,
      padding: padding,
      child: Column(children: children),
    );
  }
}

/// 通用导航/状态行：左 icon + 标题 + 副标题，可选右侧 chevron。
class _NavTile extends StatelessWidget {
  const _NavTile({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    this.chevron = false,
    this.onTap,
  });

  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final bool chevron;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final body = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 16, color: iconColor),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: scheme.onSurface,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(
                    color: scheme.onSurfaceVariant,
                    fontSize: 12,
                    letterSpacing: 0.1,
                  ),
                ),
              ],
            ),
          ),
          if (chevron)
            Icon(
              Icons.chevron_right_rounded,
              size: 18,
              color: scheme.onSurfaceVariant,
            ),
        ],
      ),
    );

    if (onTap == null) return body;
    return Material(
      color: Colors.transparent,
      child: InkWell(onTap: onTap, child: body),
    );
  }
}
