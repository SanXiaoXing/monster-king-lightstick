import 'package:flutter/material.dart';

import '../../app/theme/app_theme.dart';
import '../theme/spacing.dart';

/// 未连接设备时的锁定占位：提示先去「连接」Tab 配对应援棒，可一键跳转。
///
/// 调色 / 音乐页在设备未连接时用它替换正文内容（功能不可用），
/// 连接成功后自动恢复原内容。
class ConnectGuardView extends StatelessWidget {
  const ConnectGuardView({super.key, this.onGoConnect});

  /// 跳转「连接」Tab 的回调（由 Dock 宿主提供；独立使用时传 null 隐藏按钮）。
  final VoidCallback? onGoConnect;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
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
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(Spacing.pageMargin),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: scheme.primary.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.bluetooth_disabled_rounded,
                  size: 30,
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                '尚未连接应援棒',
                style: TextStyle(
                  color: scheme.onSurface,
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                '请先在「连接」Tab 配对应援棒，再来使用本页功能',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: scheme.onSurfaceVariant,
                  fontSize: 13,
                  height: 1.5,
                ),
              ),
              if (onGoConnect != null) ...[
                const SizedBox(height: 20),
                FilledButton.icon(
                  onPressed: onGoConnect,
                  icon: const Icon(Icons.bluetooth_searching_rounded, size: 18),
                  label: const Text('去连接'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
