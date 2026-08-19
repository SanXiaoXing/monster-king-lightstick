import 'package:flutter/material.dart';

import '../../shared/theme/spacing.dart';
import '../../shared/widgets/app_top_bar.dart';
import '../../shared/widgets/important_notice.dart';

/// 温馨提示页。
///
/// 页面分为：使用方法、使用前准备、重要声明三个模块。
class TipsPage extends StatelessWidget {
  const TipsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppTopBar(title: '温馨提示'),
      body: ListView(
        padding: EdgeInsets.all(Spacing.pageMargin),
        children: [
          _buildHeader(context),
          const SizedBox(height: 20),

          // 使用方法
          _buildSectionTitle(
            context,
            icon: Icons.lightbulb_outline_rounded,
            title: '使用方法',
          ),
          const SizedBox(height: 10),
          _buildInfoCard(
            context,
            icon: Icons.power_settings_new_rounded,
            title: '开机',
            description: '长按电源键开机，等待荧光棒指示灯亮起。',
          ),
          _buildInfoCard(
            context,
            icon: Icons.bluetooth_rounded,
            title: '连接蓝牙',
            description: '开机后双击电源键进入蓝牙连接模式，然后在 App 中完成连接。',
          ),

          const SizedBox(height: 20),

          // 使用前准备
          _buildSectionTitle(
            context,
            icon: Icons.settings_outlined,
            title: '使用前准备',
          ),
          const SizedBox(height: 10),
          _buildInfoCard(
            context,
            icon: Icons.mic_none_rounded,
            title: '授权麦克风',
            description: '音乐律动功能需要获取手机麦克风权限，用于实时分析周围的音乐节奏。',
          ),
          _buildInfoCard(
            context,
            icon: Icons.notifications_none_rounded,
            title: '允许通知',
            description: '请允许 App 发送通知，以保证蓝牙及音乐监听等后台功能能够正常运行。',
          ),
          _buildInfoCard(
            context,
            icon: Icons.android_rounded,
            title: '系统要求',
            description: '本软件需要 Android 11 及以上版本的设备。',
          ),

          const SizedBox(height: 20),

          // 重要声明（与关于页共用同一组件，内容保持一致）
          const ImportantNotice(),

          const SizedBox(height: 24),

          Center(
            child: Text(
              '感谢你的理解与支持 ❤️',
              style: TextStyle(
                color: scheme.onSurfaceVariant,
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.info_outline_rounded,
            color: scheme.primary,
            size: 24,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              '首次使用前，请先阅读以下说明，以确保荧光棒与音乐律动功能能够正常工作。',
              style: TextStyle(
                color: scheme.onSurfaceVariant,
                fontSize: 13,
                height: 1.6,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(
      BuildContext context, {
        required IconData icon,
        required String title,
      }) {
    final scheme = Theme.of(context).colorScheme;

    return Row(
      children: [
        Icon(
          icon,
          size: 20,
          color: scheme.primary,
        ),
        const SizedBox(width: 8),
        Text(
          title,
          style: TextStyle(
            color: scheme.onSurface,
            fontSize: 16,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }

  Widget _buildInfoCard(
      BuildContext context, {
        required IconData icon,
        required String title,
        required String description,
      }) {
    final scheme = Theme.of(context).colorScheme;

    return Card(
      margin: const EdgeInsets.only(bottom: Spacing.gap12),
      child: Padding(
        padding: EdgeInsets.all(Spacing.cardPadding),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 38,
              height: 38,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: scheme.primaryContainer,
                borderRadius: BorderRadius.circular(11),
              ),
              child: Icon(
                icon,
                size: 20,
                color: scheme.onPrimaryContainer,
              ),
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
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    description,
                    style: TextStyle(
                      color: scheme.onSurfaceVariant,
                      fontSize: 12,
                      height: 1.5,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

}