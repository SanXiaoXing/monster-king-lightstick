import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../shared/widgets/app_top_bar.dart';
import '../../shared/widgets/brand_logo.dart';
import '../../shared/widgets/important_notice.dart';

/// 关于页：介绍宝宝剑的制作初衷、项目边界、声明及开源信息。
class AboutPage extends StatelessWidget {
  const AboutPage({super.key});

  static const appName = '宝宝剑';
  static const appVersion = 'v1.0.0';

  /// 项目 GitHub 仓库地址。
  static const githubUrl = 'https://github.com/SanXiaoXing/monster-king-lightstick';

  Future<void> _openGitHub(BuildContext context) async {
    final uri = Uri.parse(githubUrl);
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('无法打开 GitHub，请稍后重试')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppTopBar(title: '关于'),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 28, 20, 40),
        children: [
          // ═══════════════════════════════════════════════
          // 品牌
          // ═══════════════════════════════════════════════
          _buildBrand(context),

          const SizedBox(height: 36),

          // ═══════════════════════════════════════════════
          // 为什么制作
          // ═══════════════════════════════════════════════
          _SectionLabel(
            icon: Icons.favorite_rounded,
            title: '为什么制作这个软件',
          ),

          const SizedBox(height: 12),

          _StoryCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '只是想让宝宝剑，',
                  style: TextStyle(
                    color: scheme.onSurface,
                    fontSize: 21,
                    fontWeight: FontWeight.w800,
                    height: 1.35,
                  ),
                ),
                Text(
                  '一直陪着音乐一起亮。',
                  style: TextStyle(
                    color: scheme.primary,
                    fontSize: 21,
                    fontWeight: FontWeight.w800,
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 18),
                Text(
                  '官方小程序存在运行限制，',
                  style: TextStyle(
                    color: scheme.onSurface,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    height: 1.7,
                  ),
                ),
                Text(
                  '无法长时间持续使用手机麦克风控制宝宝剑。',
                  style: TextStyle(
                    color: scheme.onSurface,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    height: 1.7,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  '所以，我对官方小程序进行了逆向分析，'
                      '并基于 112 版本实现了这个独立应用。',
                  style: TextStyle(
                    color: scheme.onSurfaceVariant,
                    fontSize: 13,
                    height: 1.7,
                  ),
                ),
                const SizedBox(height: 16),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: scheme.primaryContainer.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.music_note_rounded,
                        color: scheme.primary,
                        size: 18,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '让音乐律动真正成为宝宝剑的一部分。',
                          style: TextStyle(
                            color: scheme.onPrimaryContainer,
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 32),

          // ═══════════════════════════════════════════════
          // 功能边界
          // ═══════════════════════════════════════════════
          _SectionLabel(
            icon: Icons.question_mark_rounded,
            title: '后续会增加官方其他功能吗',
          ),

          const SizedBox(height: 12),

          _QuestionCard(
            question: '会同步官方 OTA 升级吗？',
            answer: '不会。',
            description: '本项目不会实现官方 OTA 升级功能。',
          ),

          const SizedBox(height: 10),

          _QuestionCard(
            question: '会加入演唱会座位功能吗？',
            answer: '不会。',
            description: '本项目不会实现演唱会座位等官方服务功能。',
          ),

          const SizedBox(height: 14),

          Text(
            '不是技术达不到。',
            style: TextStyle(
              color: scheme.onSurface,
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),

          const SizedBox(height: 5),

          Text(
            '而是因为相关功能可能涉及版权及授权问题。'
                '因此，本项目会主动避开这些功能，'
                '只专注于荧光棒控制与音乐律动。',
            style: TextStyle(
              color: scheme.onSurfaceVariant,
              fontSize: 13,
              height: 1.7,
            ),
          ),

          const SizedBox(height: 32),

          // ═══════════════════════════════════════════════
          // 重要声明（与温馨提示页共用同一组件，内容保持一致）
          // ═══════════════════════════════════════════════
          const ImportantNotice(),

          const SizedBox(height: 32),

          // ═══════════════════════════════════════════════
          // 开源与版权
          // ═══════════════════════════════════════════════
          _SectionLabel(
            icon: Icons.code_rounded,
            title: '开源与版权',
          ),

          const SizedBox(height: 12),

          _buildOpenSourceCard(context),

          const SizedBox(height: 32),

          // ═══════════════════════════════════════════════
          // Footer
          // ═══════════════════════════════════════════════
          Center(
            child: Text(
              '© 2026 SanXiaoXing',
              style: TextStyle(
                color: scheme.onSurfaceVariant,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),

          const SizedBox(height: 5),

          Center(
            child: Text(
              '本作品以 CC BY-NC-SA 4.0 许可协议发布',
              style: TextStyle(
                color: scheme.onSurfaceVariant,
                fontSize: 11,
              ),
            ),
          ),

          const SizedBox(height: 5),

          Center(
            child: Text(
              '宝宝剑™ 为官方品牌商标 · 非官方个人项目',
              style: TextStyle(
                color: scheme.onSurfaceVariant,
                fontSize: 11,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────
  // 品牌
  // ─────────────────────────────────────────────────────

  Widget _buildBrand(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Column(
      children: [
        BrandLogo(
          size: const Size(52, 96),
        ),
        const SizedBox(height: 18),
        Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              appName,
              style: TextStyle(
                color: scheme.onSurface,
                fontSize: 30,
                fontWeight: FontWeight.w900,
                letterSpacing: 1,
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 5, left: 2),
              child: Text(
                '™',
                style: TextStyle(
                  color: scheme.onSurfaceVariant,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 7),
        Container(
          padding: const EdgeInsets.symmetric(
            horizontal: 10,
            vertical: 4,
          ),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            appVersion,
            style: TextStyle(
              color: scheme.onSurface,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }

  // ─────────────────────────────────────────────────────
  // 开源与版权
  // ─────────────────────────────────────────────────────

  Widget _buildOpenSourceCard(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Column(
      children: [
        // GitHub
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: scheme.outlineVariant.withValues(alpha: 0.5),
            ),
          ),
          child: Column(
            children: [
              Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: scheme.onSurface,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Icon(
                      Icons.code_rounded,
                      color: Colors.white,
                      size: 27,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'GitHub 开源项目',
                          style: TextStyle(
                            color: scheme.onSurface,
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '源码公开 · 欢迎学习与交流',
                          style: TextStyle(
                            color: scheme.onSurfaceVariant,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 16),

              Text(
                '项目源码公开于 GitHub。'
                    '你可以自由查看源码、学习实现方式，'
                    '也欢迎通过 Issue 或 Pull Request 参与交流。',
                style: TextStyle(
                  color: scheme.onSurface,
                  fontSize: 13,
                  height: 1.7,
                ),
              ),

              const SizedBox(height: 14),

              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () => _openGitHub(context),
                  icon: const Icon(
                    Icons.open_in_new_rounded,
                    size: 17,
                  ),
                  label: const Text('查看 GitHub 源码'),
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 12),

        // 许可协议（CC BY-NC-SA 4.0）
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(18),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '开源许可 · CC BY-NC-SA 4.0',
                style: TextStyle(
                  color: scheme.onSurface,
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                ),
              ),

              const SizedBox(height: 10),

              Text(
                '本作品以「知识共享 署名-非商业性使用-相同方式共享 4.0 国际」'
                    '许可协议（CC BY-NC-SA 4.0）发布，保留版权与署名。',
                style: TextStyle(
                  color: scheme.onSurface,
                  fontSize: 13,
                  height: 1.7,
                ),
              ),

              const SizedBox(height: 12),

              Text(
                '许可协议核心条款：',
                style: TextStyle(
                  color: scheme.onSurface,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),

              const SizedBox(height: 10),

              _LicenseItem(
                icon: Icons.check_circle_outline_rounded,
                text: '署名：使用或转载时须标注原作者',
                color: scheme.primary,
              ),

              _LicenseItem(
                icon: Icons.check_circle_outline_rounded,
                text: '非商业性使用：不得用于商业目的',
                color: scheme.primary,
              ),

              _LicenseItem(
                icon: Icons.check_circle_outline_rounded,
                text: '相同方式共享：衍生作品须以相同许可发布',
                color: scheme.primary,
              ),

              const SizedBox(height: 4),

              _LicenseItem(
                icon: Icons.block_rounded,
                text: '不得将本项目或其衍生版本用于商业售卖、收费分发',
                color: scheme.error,
              ),

              const SizedBox(height: 14),

              Text(
                '许可协议全文：',
                style: TextStyle(
                  color: scheme.onSurfaceVariant,
                  fontSize: 12,
                ),
              ),

              const SizedBox(height: 4),

              Text(
                'creativecommons.org/licenses/by-nc-sa/4.0',
                style: TextStyle(
                  color: scheme.primary,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════
// License Item
// ═══════════════════════════════════════════════════════

class _LicenseItem extends StatelessWidget {
  const _LicenseItem({
    required this.icon,
    required this.text,
    required this.color,
  });

  final IconData icon;
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: Row(
        children: [
          Icon(
            icon,
            size: 17,
            color: color,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: color,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════
// Section Label
// ═══════════════════════════════════════════════════════

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({
    required this.icon,
    required this.title,
  });

  final IconData icon;
  final String title;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Row(
      children: [
        Icon(
          icon,
          size: 19,
          color: scheme.primary,
        ),
        const SizedBox(width: 8),
        Text(
          title,
          style: TextStyle(
            color: scheme.onSurface,
            fontSize: 17,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════
// Story Card
// ═══════════════════════════════════════════════════════

class _StoryCard extends StatelessWidget {
  const _StoryCard({
    required this.child,
  });

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: scheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      child: child,
    );
  }
}

// ═══════════════════════════════════════════════════════
// Question Card
// ═══════════════════════════════════════════════════════

class _QuestionCard extends StatelessWidget {
  const _QuestionCard({
    required this.question,
    required this.answer,
    required this.description,
  });

  final String question;
  final String answer;
  final String description;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(15),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            question,
            style: TextStyle(
              color: scheme.onSurface,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                answer,
                style: TextStyle(
                  color: scheme.error,
                  fontSize: 17,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  description,
                  style: TextStyle(
                    color: scheme.onSurfaceVariant,
                    fontSize: 12,
                    height: 1.5,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}