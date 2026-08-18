import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../app/theme/app_theme.dart';
import '../../../../shared/widgets/slider_row.dart';
import '../../../device/presentation/device_view_model.dart';

/// 音乐页（Dock「音乐」Tab）。
///
/// 对齐原型音乐屏：镜像柱状频谱 + 波形线叠加 + 律动模式按钮 + 灵敏度滑杆。
/// 真实音频分析由 Rust audio/ 落地后接入，当前以双正弦波+噪声模拟动态。
/// `embedded=true` 时无 AppBar，由 Dock 壳托管。
class MusicPage extends StatefulWidget {
  const MusicPage({super.key, required this.viewModel, this.embedded = false});

  final DeviceViewModel viewModel;
  final bool embedded;

  @override
  State<MusicPage> createState() => _MusicPageState();
}

class _MusicPageState extends State<MusicPage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _anim;
  // 律动模式：单色 / 七彩 / 强烈 / 柔和
  String _mode = '单色律动';
  double _sensitivity = 0.6;
  bool _active = true;

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat();
  }

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  bool _ensureConnected() {
    if (!widget.viewModel.status.isConnected) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('请先在「连接」Tab 配对应援棒')));
      return false;
    }
    return true;
  }

  void _onMode(String m) {
    setState(() => _mode = m);
    if (_ensureConnected()) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text('已切换律动：$m')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final content = Container(
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
      child: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(child: _Heading(active: _active)),
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 18),
            sliver: SliverToBoxAdapter(
              child: Column(
                children: [
                  _Spectrum(
                    anim: _anim,
                    active: _active,
                    sensitivity: _sensitivity,
                    mode: _mode,
                  ),
                  const SizedBox(height: 18),
                  SliderRow(
                    label: '节奏灵敏度',
                    valueLabel: '${(_sensitivity * 100).round()}%',
                    value: _sensitivity,
                    onChanged: (v) => setState(() => _sensitivity = v),
                  ),
                  const SizedBox(height: 18),
                  _ModeRow(selected: _mode, onPick: _onMode),
                  const SizedBox(height: 16),
                  _ToggleBtn(
                    active: _active,
                    onTap: () => setState(() => _active = !_active),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );

    if (widget.embedded) {
      return SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.only(bottom: 110),
          child: content,
        ),
      );
    }
    return Scaffold(appBar: AppBar(title: const Text('音乐律动')), body: content);
  }
}

class _Heading extends StatelessWidget {
  const _Heading({required this.active});
  final bool active;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('音乐律动',
                  style: TextStyle(
                      color: scheme.onSurface,
                      fontSize: 26,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.4,
                      height: 1.1)),
              _StatusDot(active: active),
            ],
          ),
          const SizedBox(height: 6),
          Text('频谱实时跟随环境音乐，驱动应援棒亮度与色彩。',
              style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13, height: 1.55)),
        ],
      ),
    );
  }
}

class _StatusDot extends StatelessWidget {
  const _StatusDot({required this.active});
  final bool active;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = active ? AppColors.ok : scheme.onSurfaceVariant;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(100),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(active ? '响应中' : '已暂停',
              style: TextStyle(
                  color: color, fontSize: 11, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

/// 镜像柱状频谱 + 波形线。
class _Spectrum extends StatelessWidget {
  const _Spectrum({
    required this.anim,
    required this.active,
    required this.sensitivity,
    required this.mode,
  });

  final Animation<double> anim;
  final bool active;
  final double sensitivity;
  final String mode;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return LayoutBuilder(
      builder: (context, c) {
        final w = c.maxWidth;
        final h = w * 0.78; // 频谱区域高
        return AnimatedBuilder(
          animation: anim,
          builder: (context, _) {
            return Container(
              width: w,
              height: h,
              decoration: BoxDecoration(
                color: scheme.surfaceContainerLow,
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: scheme.outlineVariant),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(22),
                child: CustomPaint(
                  size: Size(w, h),
                  painter: _SpectrumPainter(
                    t: active ? anim.value : 0.0,
                    sensitivity: sensitivity,
                    isDark: AppColors.isDark(scheme),
                    accent: scheme.primary,
                    mode: mode,
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _SpectrumPainter extends CustomPainter {
  _SpectrumPainter({
    required this.t,
    required this.sensitivity,
    required this.isDark,
    required this.accent,
    required this.mode,
  });

  final double t;
  final double sensitivity;
  final bool isDark;
  final Color accent;
  final String mode;

  // ponytail: 纯模拟数据，真实音频由 Rust audio/ 落地后替换 _barHeight
  static const _barCount = 28;

  @override
  void paint(Canvas canvas, Size size) {
    final cy = size.height / 2;
    final barW = size.width / _barCount;
    final gap = barW * 0.32;
    final w = barW - gap;

    // 镜像柱：上下对称
    for (var i = 0; i < _barCount; i++) {
      final v = _barHeight(i, t);
      final barH = v * (size.height * 0.46) * (0.4 + sensitivity);
      final x = i * barW + gap / 2;

      // 颜色：单色=accent；七彩=HSL 随 i 昶移
      final color = mode == '七彩律动'
          ? HSLColor.fromAHSL(1, (i / _barCount) * 360, 0.7, 0.6).toColor()
          : accent;

      // 上柱
      final topRect = RRect.fromRectAndRadius(
        Rect.fromLTWH(x, cy - barH, w, barH),
        const Radius.circular(3),
      );
      canvas.drawRRect(
        topRect,
        Paint()
          ..color = color
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [color, color.withValues(alpha: 0.4)],
          ).createShader(topRect.outerRect),
      );
      // 下柱（镜像，透明度低）
      final botRect = RRect.fromRectAndRadius(
        Rect.fromLTWH(x, cy, w, barH * 0.7),
        const Radius.circular(3),
      );
      canvas.drawRRect(
        botRect,
        Paint()
          ..color = color.withValues(alpha: 0.45)
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [color.withValues(alpha: 0.45), color.withValues(alpha: 0.1)],
          ).createShader(botRect.outerRect),
      );
    }

    // 中线
    final linePaint = Paint()
      ..color = (isDark ? Colors.white : Colors.black).withValues(alpha: 0.06)
      ..strokeWidth = 1;
    canvas.drawLine(
      Offset(0, cy),
      Offset(size.width, cy),
      linePaint,
    );

    // 波形线：叠加在频谱上方
    final wavePath = Path();
    final wavePaint = Paint()
      ..color = accent.withValues(alpha: 0.85)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round;

    for (var i = 0; i <= _barCount * 2; i++) {
      final x = (i / (_barCount * 2)) * size.width;
      final baseWave = math.sin((i * 0.4) + t * 2 * math.pi) * 0.18;
      final noise = _noise(i, t) * 0.06;
      final y = cy + (baseWave + noise) * size.height * (0.5 + sensitivity);
      if (i == 0) {
        wavePath.moveTo(x, y);
      } else {
        wavePath.lineTo(x, y);
      }
    }
    canvas.drawPath(wavePath, wavePaint);
  }

  /// 模拟频谱柱高（0-1）：双正弦 + 噪声，中央频段更活跃。
  double _barHeight(int i, double t) {
    final norm = i / _barCount;
    // 中央峰值（音乐低/中频更活跃）
    final env = math.sin(norm * math.pi);
    final w1 = math.sin((i * 0.55) + t * 2 * math.pi);
    final w2 = math.sin((i * 0.31) - t * 2 * math.pi * 0.7) * 0.7;
    final n = _noise(i, t);
    final v = (env * (0.5 + 0.5 * (w1 + w2 + n).abs())).clamp(0.04, 1.0);
    return v;
  }

  double _noise(int i, double t) {
    // ponytail: 伪随机基于 i+t，确定性，够用；真实音频落地后替换
    final s = (i * 13.7 + t * 47.3) % 1;
    return (s - 0.5) * 2;
  }

  @override
  bool shouldRepaint(covariant _SpectrumPainter old) =>
      old.t != t ||
      old.sensitivity != sensitivity ||
      old.mode != mode ||
      old.isDark != isDark;
}

class _ModeRow extends StatelessWidget {
  const _ModeRow({required this.selected, required this.onPick});
  final String selected;
  final void Function(String) onPick;

  static const _modes = <(String, IconData)>[
    ('单色律动', Icons.tonality_rounded),
    ('七彩律动', Icons.auto_awesome_rounded),
    ('强烈', Icons.flash_on_rounded),
    ('柔和', Icons.spa_rounded),
  ];

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (final (name, icon) in _modes)
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(
                right: name == _modes.last.$1 ? 0 : 8,
              ),
              child: _ModeBtn(
                icon: icon,
                label: name,
                active: selected == name,
                onTap: () => onPick(name),
              ),
            ),
          ),
      ],
    );
  }
}

class _ModeBtn extends StatelessWidget {
  const _ModeBtn({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: active ? AppColors.accentSoft : scheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 11),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: active ? scheme.primary : scheme.outlineVariant),
          ),
          child: Column(
            children: [
              Icon(icon, size: 18, color: scheme.primary),
              const SizedBox(height: 4),
              Text(label,
                  style: TextStyle(
                    color: scheme.onSurface,
                    fontSize: 11,
                    fontWeight: active ? FontWeight.w600 : FontWeight.w400,
                  )),
            ],
          ),
        ),
      ),
    );
  }
}

class _ToggleBtn extends StatelessWidget {
  const _ToggleBtn({required this.active, required this.onTap});
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: double.infinity,
      child: FilledButton.icon(
        onPressed: onTap,
        style: FilledButton.styleFrom(
          backgroundColor: active ? scheme.primary : scheme.surfaceContainerHigh,
          foregroundColor: active ? Colors.white : scheme.onSurface,
          minimumSize: const Size.fromHeight(50),
        ),
        icon: Icon(active ? Icons.pause_rounded : Icons.play_arrow_rounded, size: 20),
        label: Text(active ? '暂停律动' : '开始律动',
            style: const TextStyle(fontWeight: FontWeight.w600, letterSpacing: 0.3)),
      ),
    );
  }
}
