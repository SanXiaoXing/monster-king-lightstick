import 'package:flutter/material.dart';

import '../../../../app/router/app_router.dart';
import '../../../device/presentation/device_view_model.dart';
import '../../../device/presentation/pages/device_page.dart';

/// 座位绑定页（主页「座位绑定」入口）。
///
/// 选择所在区域 + 选填座位号；绑定信息仅用于灯光联动，不上传服务器。
class SeatBindingPage extends StatefulWidget {
  const SeatBindingPage({super.key, required this.viewModel});

  final DeviceViewModel viewModel;

  @override
  State<SeatBindingPage> createState() => _SeatBindingPageState();
}

class _SeatBindingPageState extends State<SeatBindingPage> {
  static const _zones = <(String, String)>[
    ('内场前排', 'INNER A'),
    ('内场后排', 'INNER B'),
    ('看台 A 区', 'STAND A'),
    ('看台 B 区', 'STAND B'),
    ('VIP 区', 'VIP ZONE'),
    ('自由模式', 'FREE'),
  ];

  String _zone = _zones.first.$1;
  final _seatController = TextEditingController();

  @override
  void dispose() {
    _seatController.dispose();
    super.dispose();
  }

  void _bind() {
    if (!widget.viewModel.status.isConnected) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('请先完成蓝牙连接')));
      Navigator.of(context).push(
        AppRouter.page(DevicePage(viewModel: widget.viewModel)),
      );
      return;
    }
    final no = _seatController.text.trim();
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(no.isEmpty ? '✓ 已绑定区域：$_zone' : '✓ 座位已绑定：$_zone $no'),
      ));
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('座位绑定')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            '选择所在区域，绑定后应援棒将跟随该区域的灯光联动。',
            style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13, height: 1.6),
          ),
          const SizedBox(height: 16),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 2.1,
            children: [
              for (final (name, en) in _zones)
                _ZoneTile(
                  name: name,
                  en: en,
                  selected: _zone == name,
                  onTap: () => setState(() => _zone = name),
                ),
            ],
          ),
          const SizedBox(height: 20),
          TextField(
            controller: _seatController,
            decoration: const InputDecoration(
              hintText: '输入座位号，如 A区 12排 08号（选填）',
            ),
          ),
          const SizedBox(height: 16),
          FilledButton(onPressed: _bind, child: const Text('绑定座位')),
          const SizedBox(height: 12),
          Center(
            child: Text(
              '绑定信息仅用于应援棒灯光联动，不会上传服务器。',
              style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}

class _ZoneTile extends StatelessWidget {
  const _ZoneTile({
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
