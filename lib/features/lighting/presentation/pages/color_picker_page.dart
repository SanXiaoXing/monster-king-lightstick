import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../app/theme/app_theme.dart';
import '../../../../shared/widgets/slider_row.dart';
import '../../../device/data/device_repository.dart';
import '../../../device/presentation/device_view_model.dart';
import '../../data/lighting_repository.dart';
import '../../domain/lighting_effect.dart';

/// 调色页（Dock「调色」Tab）。
///
/// 对齐原型调色屏：方形 SV 板 + 色相条 + hex 输入 + 亮度滑杆 + 9 灯效 3×3。
/// `embedded=true` 时无 AppBar，由 Dock 壳托管。
class ColorPickerPage extends StatefulWidget {
  const ColorPickerPage({super.key, required this.viewModel, this.embedded = false});

  final DeviceViewModel viewModel;
  final bool embedded;

  @override
  State<ColorPickerPage> createState() => _ColorPickerPageState();
}

class _ColorPickerPageState extends State<ColorPickerPage> {
  late final LightingRepository _repo = LightingRepository(DeviceRepository());

  // HSV 状态：默认 #0A84FF（iOS 蓝）
  double _hue = 210, _sat = 1, _val = 1;
  double _brightness = 0.8;
  LightingFx _fx = LightingFx.constantlyOn;
  final _hexCtrl = TextEditingController(text: '0A84FF');
  Timer? _colorDebounce;

  @override
  void dispose() {
    _colorDebounce?.cancel();
    _hexCtrl.dispose();
    super.dispose();
  }

  Color get _color => HSVColor.fromAHSV(1, _hue, _sat, _val).toColor();
  String get _hex =>
      '#${_color.toARGB32().toRadixString(16).substring(2).toUpperCase()}';

  void _syncHex() {
    final hex = _color.toARGB32().toRadixString(16).substring(2).toUpperCase();
    if (_hexCtrl.text != hex) _hexCtrl.value = TextEditingValue(text: hex);
  }

  void _onHexInput(String v) {
    final clean = v.replaceAll(RegExp(r'[^0-9a-fA-F]'), '').toUpperCase();
    if (clean.length == 6) {
      final n = int.parse(clean, radix: 16);
      final hsv = HSVColor.fromColor(Color(0xFF000000 | n));
      setState(() {
        _hue = hsv.hue;
        _sat = hsv.saturation;
        _val = hsv.value;
      });
      _scheduleColorSend();
    }
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

  /// 颜色/亮度变化防抖 250ms 后实时下发（拖拽过程不逐帧写 BLE）。
  void _scheduleColorSend() {
    _colorDebounce?.cancel();
    _colorDebounce = Timer(const Duration(milliseconds: 250), () {
      if (!mounted) return;
      _send(_fx);
    });
  }

  /// 下发当前颜色 + 指定效果到已连接设备。
  ///
  /// [announce] 为 true 时（用户点选效果）提示应用结果，静默失败仍提示。
  Future<void> _send(LightingFx fx, {bool announce = false}) async {
    final device = widget.viewModel.activeDevice;
    if (device == null || !_ensureConnected()) return;
    try {
      await _repo.sendEffect(
        device,
        fx: fx,
        color: _color,
        brightness: _brightness,
      );
      if (announce && mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text('已应用：${fx.label} $_hex')));
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text('下发失败：$e')));
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
          SliverToBoxAdapter(child: _Heading()),
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 18),
            sliver: SliverToBoxAdapter(
              child: Column(
                children: [
                  _SvPanel(
                    hue: _hue,
                    sat: _sat,
                    val: _val,
                    onChanged: (s, v) {
                      setState(() {
                        _sat = s;
                        _val = v;
                      });
                      _syncHex();
                      _scheduleColorSend();
                    },
                  ),
                  const SizedBox(height: 14),
                  _HueStrip(
                    hue: _hue,
                    onChanged: (h) {
                      setState(() => _hue = h);
                      _syncHex();
                      _scheduleColorSend();
                    },
                  ),
                  const SizedBox(height: 14),
                  _HexRow(
                    controller: _hexCtrl,
                    color: _color,
                    onSubmitted: _onHexInput,
                  ),
                  const SizedBox(height: 16),
                  SliderRow(
                    label: '亮度',
                    valueLabel: '${(_brightness * 100).round()}%',
                    value: _brightness,
                    onChanged: (v) {
                      setState(() => _brightness = v);
                      _scheduleColorSend();
                    },
                  ),
                  const SizedBox(height: 6),
                  _SectionLabel('灯光效果（9 种）'),
                  const SizedBox(height: 8),
                  _EffectGrid(
                    selected: _fx,
                    onPick: (fx) {
                      setState(() => _fx = fx);
                      _send(fx, announce: true);
                    },
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
    return Scaffold(appBar: AppBar(title: const Text('调色盘')), body: content);
  }
}

class _Heading extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('调色盘',
              style: TextStyle(
                  color: scheme.onSurface,
                  fontSize: 26,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.4,
                  height: 1.1)),
          const SizedBox(height: 6),
          Text('方形面板选色或直接输入十六进制，选灯效即时应用。',
              style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13, height: 1.55)),
        ],
      ),
    );
  }
}

/// 方形 SV 板：X=饱和度，Y=明度（上明下暗）。
class _SvPanel extends StatelessWidget {
  const _SvPanel({required this.hue, required this.sat, required this.val, required this.onChanged});

  final double hue, sat, val;
  final void Function(double sat, double val) onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final hueColor = HSVColor.fromAHSV(1, hue, 1, 1).toColor();
    return LayoutBuilder(
      builder: (context, c) {
        final w = c.maxWidth;
        final h = w / 1.4; // aspect 1.4:1
        return SizedBox(
          width: w,
          height: h,
          child: Stack(
            children: [
              // 底层：白 → 色相（水平）
              Positioned.fill(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.centerLeft,
                        end: Alignment.centerRight,
                        colors: [Colors.white, hueColor],
                      ),
                      border: Border.all(color: scheme.outlineVariant),
                    ),
                  ),
                ),
              ),
              // 上层：透明 → 黑（垂直，下黑）
              Positioned.fill(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Colors.transparent, Colors.black],
                      ),
                    ),
                  ),
                ),
              ),
              // 游标
              Positioned(
                left: sat * w - 11,
                top: (1 - val) * h - 11,
                child: Container(
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: HSVColor.fromAHSV(1, hue, sat, val).toColor(),
                    border: Border.all(color: Colors.white, width: 3),
                    boxShadow: [
                      BoxShadow(color: Colors.black.withValues(alpha: 0.35), blurRadius: 8),
                    ],
                  ),
                ),
              ),
              // 拾取手势
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onPanDown: (d) => _pick(d.localPosition, w, h),
                  onPanUpdate: (d) => _pick(d.localPosition, w, h),
                  child: const SizedBox.expand(),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _pick(Offset local, double w, double h) {
    final s = (local.dx / w).clamp(0.0, 1.0);
    final v = (1 - local.dy / h).clamp(0.0, 1.0);
    onChanged(s, v);
  }
}

/// 色相条：水平彩虹，X=色相 0-360。
class _HueStrip extends StatelessWidget {
  const _HueStrip({required this.hue, required this.onChanged});
  final double hue;
  final void Function(double hue) onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return LayoutBuilder(
      builder: (context, c) {
        final w = c.maxWidth;
        const h = 28.0;
        return SizedBox(
          width: w,
          height: h,
          child: Stack(
            children: [
              Positioned.fill(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(100),
                  child: CustomPaint(
                    size: Size(w, h),
                    painter: _RainbowPainter(),
                  ),
                ),
              ),
              Positioned(
                left: (hue / 360) * w - 5,
                top: -3,
                bottom: -3,
                child: Container(
                  width: 10,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(100),
                    border: Border.all(color: Colors.white, width: 2),
                    boxShadow: [
                      BoxShadow(color: Colors.black.withValues(alpha: 0.35), blurRadius: 6),
                    ],
                  ),
                ),
              ),
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onPanDown: (d) => _pick(d.localPosition.dx, w),
                  onPanUpdate: (d) => _pick(d.localPosition.dx, w),
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(100),
                      border: Border.all(color: scheme.outlineVariant),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _pick(double dx, double w) =>
      onChanged((dx / w).clamp(0.0, 1.0) * 360);
}

class _RainbowPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    const stops = [0.0, 0.17, 0.33, 0.5, 0.67, 0.83, 1.0];
    final colors = [
      const Color(0xFFFF0000), const Color(0xFFFFFF00),
      const Color(0xFF00FF00), const Color(0xFF00FFFF),
      const Color(0xFF0000FF), const Color(0xFFFF00FF),
      const Color(0xFFFF0000),
    ];
    final paint = Paint()
      ..shader = LinearGradient(colors: colors, stops: stops).createShader(rect);
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, Radius.circular(size.height / 2)),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}

class _HexRow extends StatelessWidget {
  const _HexRow({required this.controller, required this.color, required this.onSubmitted});

  final TextEditingController controller;
  final Color color;
  final ValueChanged<String> onSubmitted;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: scheme.outlineVariant),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: TextField(
            controller: controller,
            textInputAction: TextInputAction.done,
            onSubmitted: onSubmitted,
            onChanged: onSubmitted,
            style: TextStyle(
              color: scheme.onSurface,
              fontSize: 14,
              fontWeight: FontWeight.w500,
              letterSpacing: 2,
            ),
            textCapitalization: TextCapitalization.characters,
            decoration: InputDecoration(
              prefixText: '#',
              prefixStyle: TextStyle(color: scheme.onSurfaceVariant),
              hintText: '0A84FF',
            ),
          ),
        ),
      ],
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 22, bottom: 0),
      child: Text(text,
          style: TextStyle(
              color: scheme.onSurfaceVariant,
              fontSize: 11,
              letterSpacing: 1,
              fontWeight: FontWeight.w600)),
    );
  }
}

class _EffectGrid extends StatelessWidget {
  const _EffectGrid({required this.selected, required this.onPick});
  final LightingFx selected;
  final void Function(LightingFx fx) onPick;

  static const _effects = <(LightingFx, IconData)>[
    (LightingFx.constantlyOn, Icons.lightbulb_rounded),
    (LightingFx.breathe, Icons.waves_rounded),
    (LightingFx.flashMob, Icons.bolt_rounded),
    (LightingFx.blink, Icons.visibility_rounded),
    (LightingFx.party, Icons.celebration_rounded),
    (LightingFx.rainbow, Icons.gradient_rounded),
    (LightingFx.starrySky, Icons.star_rounded),
    (LightingFx.random, Icons.shuffle_rounded),
    (LightingFx.blackScreen, Icons.nightlight_rounded),
  ];

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return GridView.count(
      crossAxisCount: 3,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 8,
      crossAxisSpacing: 8,
      childAspectRatio: 0.92,
      children: [
        for (final (fx, icon) in _effects)
          _EffectBtn(
            icon: icon,
            label: fx.label,
            active: selected == fx,
            onTap: () => onPick(fx),
            accent: scheme.primary,
            surface: scheme.surfaceContainerLow,
            outline: scheme.outlineVariant,
            onSurface: scheme.onSurface,
            onSurfaceVariant: scheme.onSurfaceVariant,
          ),
      ],
    );
  }
}

class _EffectBtn extends StatelessWidget {
  const _EffectBtn({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
    required this.accent,
    required this.surface,
    required this.outline,
    required this.onSurface,
    required this.onSurfaceVariant,
  });

  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;
  final Color accent, surface, outline, onSurface, onSurfaceVariant;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: active ? AppColors.accentSoft : surface,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: active ? accent : outline),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              TweenAnimationBuilder<double>(
                tween: Tween(begin: 1.0, end: active ? 1.15 : 1.0),
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeOutBack,
                builder: (context, s, child) =>
                    Transform.scale(scale: s, child: child),
                child: Icon(icon, size: 22, color: accent),
              ),
              const SizedBox(height: 7),
              Text(label,
                  style: TextStyle(
                      color: onSurface,
                      fontSize: 11,
                      letterSpacing: 0.1)),
            ],
          ),
        ),
      ),
    );
  }
}
