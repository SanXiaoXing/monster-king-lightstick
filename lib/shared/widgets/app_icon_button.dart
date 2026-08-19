import 'package:flutter/material.dart';

/// 顶栏操作按钮（对齐 docs/design/ui_layout_rules.md 第 2 节 AppIconButton 规格）。
///
/// 36 × 36，圆角 10，底色 [ColorScheme.surfaceContainerHigh]，
/// 1px 描边 [ColorScheme.outlineVariant]，图标 [ColorScheme.onSurface]。
class AppIconButton extends StatelessWidget {
  const AppIconButton({
    super.key,
    required this.icon,
    required this.onPressed,
    this.tooltip,
  });

  final IconData icon;
  final VoidCallback onPressed;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final child = SizedBox(
      width: 36,
      height: 36,
      child: Icon(icon, size: 20, color: scheme.onSurface),
    );
    return Material(
      color: scheme.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onPressed,
        child: tooltip != null
            ? Tooltip(message: tooltip!, child: child)
            : child,
      ),
    );
  }
}
