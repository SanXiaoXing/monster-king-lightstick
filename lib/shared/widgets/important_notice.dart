import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// 重要声明卡片（关于页 / 温馨提示页共用，保证两处内容完全一致）。
///
/// 内容包含：免费声明、反诈警告、官方下载链接（可点击跳转）。
class ImportantNotice extends StatelessWidget {
  const ImportantNotice({super.key});

  /// 官方下载地址（Gitee Releases 发布页）。
  static const downloadUrl =
      'https://gitee.com/yan-kmd/monster-king-lightstick-re/releases/latest';

  Future<void> _openDownload(BuildContext context) async {
    final uri = Uri.parse(downloadUrl);
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('无法打开下载链接，请稍后重试')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: scheme.errorContainer,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: scheme.error.withValues(alpha: 0.35),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: scheme.error,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  Icons.warning_rounded,
                  color: scheme.onError,
                  size: 21,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '重要声明',
                  style: TextStyle(
                    color: scheme.onErrorContainer,
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 14),

          Text(
            '本软件为个人兴趣项目，仅用于技术交流与现场应援体验，'
                '完全出于热爱发电，永久免费提供，作者不进行任何形式的售卖。',
            style: TextStyle(
              color: scheme.onErrorContainer,
              fontSize: 13,
              height: 1.65,
              fontWeight: FontWeight.w500,
            ),
          ),

          const SizedBox(height: 12),

          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(13),
            decoration: BoxDecoration(
              color: scheme.error.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              '⚠️ 如果你是通过付费购买、代购或其他收费方式获得本软件，'
                  '请立即申请退款，并不要继续支付任何费用。',
              style: TextStyle(
                color: scheme.onErrorContainer,
                fontSize: 13,
                height: 1.6,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),

          const SizedBox(height: 14),

          Text(
            '请始终通过官方渠道获取软件：',
            style: TextStyle(
              color: scheme.onErrorContainer,
              fontSize: 12,
            ),
          ),

          const SizedBox(height: 8),

          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: () => _openDownload(context),
              icon: const Icon(Icons.download_rounded, size: 18),
              label: const Text('下载宝宝剑'),
            ),
          ),

          const SizedBox(height: 10),

          Text(
            downloadUrl,
            style: TextStyle(
              color: scheme.onErrorContainer.withValues(alpha: 0.75),
              fontSize: 11,
              decoration: TextDecoration.underline,
              decorationColor:
                  scheme.onErrorContainer.withValues(alpha: 0.45),
            ),
          ),
        ],
      ),
    );
  }
}
