import 'package:flutter/material.dart';

import '../../app/theme/app_theme.dart';

/// 品牌 Logo：像素风（对齐 assets/icon/logo_black.svg 的 25 个 rect）。
///
/// 用 CustomPaint 复刻，不引入 flutter_svg 依赖（ponytail: 无新依赖）。
/// 颜色随主题：深色用浅色填充，浅色用深色填充。
class BrandLogo extends StatelessWidget {
  const BrandLogo({
    super.key,
    this.size = const Size(24, 44),
    this.color,
  });

  /// 逻辑尺寸（高度锚定，宽度按 viewBox 比例）。
  final Size size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final c = color ??
        (AppColors.isDark(scheme) ? AppColors.darkText : AppColors.lightText);
    return CustomPaint(
      size: size,
      painter: _PixelLogoPainter(c),
    );
  }
}

class _PixelLogoPainter extends CustomPainter {
  _PixelLogoPainter(this.color);

  final Color color;

  /// 与 logo_black.svg 完全一致的 25 个 rect（viewBox 360×672，24px 网格）。
  static const _rects = <Rect>[
    Rect.fromLTWH(144, 48, 24, 216),
    Rect.fromLTWH(168, 72, 24, 72),
    Rect.fromLTWH(120, 120, 24, 120),
    Rect.fromLTWH(168, 192, 24, 120),
    Rect.fromLTWH(192, 264, 24, 96),
    Rect.fromLTWH(120, 288, 24, 72),
    Rect.fromLTWH(216, 288, 24, 168),
    Rect.fromLTWH(96, 336, 24, 120),
    Rect.fromLTWH(240, 336, 24, 96),
    Rect.fromLTWH(72, 360, 24, 48),
    Rect.fromLTWH(120, 408, 24, 72),
    Rect.fromLTWH(192, 408, 24, 72),
    Rect.fromLTWH(48, 432, 24, 120),
    Rect.fromLTWH(144, 432, 48, 48),
    Rect.fromLTWH(288, 432, 24, 120),
    Rect.fromLTWH(72, 480, 24, 96),
    Rect.fromLTWH(264, 480, 24, 96),
    Rect.fromLTWH(96, 504, 48, 72),
    Rect.fromLTWH(216, 504, 48, 96),
    Rect.fromLTWH(24, 528, 24, 24),
    Rect.fromLTWH(312, 528, 24, 24),
    Rect.fromLTWH(144, 552, 24, 72),
    Rect.fromLTWH(192, 552, 24, 72),
    Rect.fromLTWH(120, 576, 24, 24),
    Rect.fromLTWH(168, 576, 24, 72),
  ];

  static const _viewW = 360.0;
  static const _viewH = 672.0;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    // viewBox 360×672 缩放到实际 size
    final sx = size.width / _viewW;
    final sy = size.height / _viewH;
    for (final r in _rects) {
      canvas.drawRect(
        Rect.fromLTWH(r.left * sx, r.top * sy, r.width * sx, r.height * sy),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_PixelLogoPainter old) => old.color != color;
}
