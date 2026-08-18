import 'package:flutter/material.dart';

import '../../../../app/router/app_router.dart';
import '../../../../shared/widgets/slider_row.dart';
import '../../../device/presentation/device_view_model.dart';
import '../../../device/presentation/pages/device_page.dart';

/// 灯光效果选择结果（应用后 pop 回设置页）。
class FxResult {
  const FxResult(this.mode, this.speed);

  final String mode;
  final double speed;
}

/// 灯光效果页（设置 → 灯光效果模式）。
class FxPage extends StatefulWidget {
  const FxPage({
    super.key,
    required this.viewModel,
    this.initialMode = '常亮',
    this.initialSpeed = 0.5,
  });

  final DeviceViewModel viewModel;
  final String initialMode;
  final double initialSpeed;

  @override
  State<FxPage> createState() => _FxPageState();
}

class _FxPageState extends State<FxPage> {
  static const _modes = <(String, String)>[
    ('常亮', 'STEADY'),
    ('呼吸灯', 'BREATH'),
    ('闪烁', 'BLINK'),
    ('彩虹渐变', 'RAINBOW'),
    ('星光频闪', 'STROBE'),
    ('音乐律动', 'BEAT'),
  ];

  late String _mode = widget.initialMode;
  late double _speed = widget.initialSpeed;

  void _apply() {
    if (!widget.viewModel.status.isConnected) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('请先完成蓝牙连接')));
      Navigator.of(context).push(
        AppRouter.page(DevicePage(viewModel: widget.viewModel)),
      );
      return;
    }
    Navigator.of(context).pop(FxResult(_mode, _speed));
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('灯光效果')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            '选择灯光效果模式',
            style: TextStyle(color: scheme.onSurface, fontSize: 14),
          ),
          const SizedBox(height: 14),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 2.1,
            children: [
              for (final (name, en) in _modes)
                _FxTile(
                  name: name,
                  en: en,
                  selected: _mode == name,
                  onTap: () => setState(() => _mode = name),
                ),
            ],
          ),
          const SizedBox(height: 12),
          SliderRow(
            label: '效果速度',
            valueLabel: '${(_speed * 100).round()}%',
            value: _speed,
            onChanged: (v) => setState(() => _speed = v),
          ),
          const SizedBox(height: 20),
          FilledButton(onPressed: _apply, child: const Text('应用效果')),
          const SizedBox(height: 12),
          Center(
            child: Text(
              '灯光效果可实时同步至应援棒，支持与音乐调光叠加使用。',
              style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}

class _FxTile extends StatelessWidget {
  const _FxTile({
    required this.name,
    required this.en,
    required this.selected,
    required this.onTap,
  });

  final String name;
  final String en;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: selected ? scheme.primaryContainer : scheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected ? scheme.primary : scheme.outlineVariant,
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                name,
                style: TextStyle(
                  color: scheme.onSurface,
                  fontSize: 14,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                en,
                style: TextStyle(
                  color: scheme.onSurfaceVariant,
                  fontSize: 10,
                  letterSpacing: 1.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
