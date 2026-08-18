import 'package:flutter/material.dart';

/// 温馨提示页（主页「温馨提示」入口）。
///
/// 使用安全提示静态列表，内容与原型一致。
class TipsPage extends StatelessWidget {
  const TipsPage({super.key});

  static const _tips = <(String, String, String)>[
    ('⚠', '请勿直视强光', '避免长时间直视应援棒灯光，防止眼睛不适。'),
    ('👶', '儿童请在家长陪同下使用', '本产品含有小零件，谨防误食或吞入。'),
    ('🔋', '电量提醒', '电量低于 20% 时请及时充电，避免影响现场体验。'),
    ('💧', '防摔防水', '请勿摔落、浸水或置于高温、潮湿环境。'),
    ('⚡', '演出结束后请关机', '长按 2 秒关机；长时间不用请关闭电源。'),
    ('🔧', '请勿自行改装', '保修期内出现故障请联系官方客服，请勿拆解设备。'),
  ];

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('温馨提示')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          for (final (emoji, title, desc) in _tips)
            Card(
              margin: const EdgeInsets.only(bottom: 10),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: scheme.primaryContainer,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(emoji, style: const TextStyle(fontSize: 20)),
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
                          const SizedBox(height: 4),
                          Text(
                            desc,
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
            ),
        ],
      ),
    );
  }
}
