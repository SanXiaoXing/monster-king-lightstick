import 'package:flutter/material.dart';

/// 带标签与数值的滑杆行（亮度/灵敏度/速度等共用）。
class SliderRow extends StatelessWidget {
  const SliderRow({
    super.key,
    required this.label,
    required this.valueLabel,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final String valueLabel;
  final double value;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: TextStyle(color: scheme.onSurface, fontSize: 14)),
            Text(
              valueLabel,
              style: TextStyle(
                color: scheme.primary,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        Slider(value: value, onChanged: onChanged),
      ],
    );
  }
}
