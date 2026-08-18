import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../app/theme/app_theme.dart';
import '../../../../shared/theme/spacing.dart';
import '../../../../shared/widgets/app_top_bar.dart';
import '../../../../shared/widgets/connect_guard_view.dart';
import '../../../../shared/widgets/slider_row.dart';
import '../../../device/data/device_repository.dart';
import '../../../device/presentation/device_view_model.dart';
import '../../data/lighting_repository.dart';
import '../../domain/lighting_effect.dart';

/// 调色页（Dock「调色」Tab）。
///
/// 对齐原型调色屏：圆形 RGB 色环 + hex 输入 + 亮度滑杆 + 9 灯效 3×3。
/// 顶部统一用 [AppTopBar]。
class ColorPickerPage extends StatefulWidget {
  const ColorPickerPage({super.key, required this.viewModel, this.onGoConnect});

  final DeviceViewModel viewModel;

  /// 未连接时「去连接」按钮回调（Dock 宿主切换 Tab；独立页可不传）。
  final VoidCallback? onGoConnect;

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
  DateTime? _lastColorSent;
  bool _colorSending = false;
  static const _liveInterval = Duration(milliseconds: 70);

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

  /// 颜色/亮度变化实时下发：
  /// - 拖拽/滑动过程中按 [_liveInterval] 节流下发（约 14fps），灯棒跟随变化；
  /// - 若两次变化间隔不足，安排一次尾部发送，保证松手后停在最终色；
  /// - 上次写入未完成时跳过，避免 BLE 命令堆积。
  void _scheduleColorSend() {
    _colorDebounce?.cancel();
    final now = DateTime.now();
    final since = _lastColorSent == null
        ? _liveInterval
        : now.difference(_lastColorSent!);
    if (since >= _liveInterval) {
      _lastColorSent = now;
      _dispatchColor();
    } else {
      _colorDebounce = Timer(_liveInterval - since, () {
        if (!mounted) return;
        _colorDebounce = null;
        _lastColorSent = DateTime.now();
        _dispatchColor();
      });
    }
  }

  /// 实际下发（带在途保护），拖动期间的实时下发静默失败、不刷错误提示。
  Future<void> _dispatchColor() async {
    if (_colorSending) return;
    _colorSending = true;
    try {
      await _send(_fx, silentErrors: true);
    } finally {
      _colorSending = false;
    }
  }

  /// 下发当前颜色 + 指定效果到已连接设备。
  ///
  /// [announce] 为 true 时（用户点选效果）提示应用结果；
  /// [silentErrors] 为 true 时（拖动实时下发）静默吞掉失败，不弹错误。
  Future<void> _send(LightingFx fx,
      {bool announce = false, bool silentErrors = false}) async {
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
      if (!mounted || silentErrors) return;
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
            padding: EdgeInsets.symmetric(horizontal: Spacing.pageMargin),
            sliver: SliverToBoxAdapter(
              child: Column(
                children: [
                  _ColorWheel(
                    hue: _hue,
                    sat: _sat,
                    color: _color,
                    onChanged: (h, s) {
                      setState(() {
                        _hue = h;
                        _sat = s;
                        _val = 1; // 色环仅编码色相+饱和度，明度恒为满值
                      });
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
                      _lastColorSent = null; // 重置节流，下次拖拽立即下发
                      _send(fx, announce: true);
                    },
                  ),
                ],
              ),
            ),
          ),
          // extendBody 下内容延伸到玻璃导航栏下方，留白让末项可滚出遮挡区
          const SliverToBoxAdapter(child: SizedBox(height: Spacing.bottomSafe)),
        ],
      ),
    );

    // 未连接设备：正文锁定为连接引导，功能不可用
    return Scaffold(
      appBar: AppTopBar(title: '调色盘'),
      body: ListenableBuilder(
        listenable: widget.viewModel,
        builder: (context, _) => widget.viewModel.status.isConnected
            ? content
            : ConnectGuardView(onGoConnect: widget.onGoConnect),
      ),
    );
  }
}

class _Heading extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: EdgeInsets.fromLTRB(Spacing.pageMargin, 14, Spacing.pageMargin, 16),
      child: Text('圆形色环选色或直接输入十六进制，选灯效即时应用。',
          style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13, height: 1.55)),
    );
  }
}

/// 圆形 RGB 取色器：
/// 整盘 SweepGradient 色相谱（R→Y→G→C→B→M→R）叠白心径向饱和度：
/// - 角度 = 色相（0°=右=红，顺时针）
/// - 半径 = 饱和度（圆心白 / S=0，边缘纯色 / S=1）
/// 单手柄在 (hue angle, sat×radius) 处显示当前 RGB 混色结果。
class _ColorWheel extends StatelessWidget {
  const _ColorWheel({
    required this.hue,
    required this.sat,
    required this.color,
    required this.onChanged,
  });

  final double hue, sat;
  final Color color;
  final void Function(double hue, double sat) onChanged;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 340),
        child: AspectRatio(
          aspectRatio: 1,
          child: LayoutBuilder(
            builder: (context, c) {
              final size = c.maxWidth;
              final center = Offset(size / 2, size / 2);
              final radius = size / 2;
              final angle = hue * math.pi / 180;
              final pos =
                  center + Offset(math.cos(angle), math.sin(angle)) * (sat * radius);
              return Stack(
                alignment: Alignment.center,
                children: [
                  ClipOval(
                    child: CustomPaint(
                      size: Size.square(size),
                      painter: const _WheelPainter(),
                    ),
                  ),
                  // 拾取手柄（当前 RGB 混色结果）
                  Positioned(
                    left: pos.dx - 12,
                    top: pos.dy - 12,
                    child: IgnorePointer(
                      child: Container(
                        width: 24,
                        height: 24,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: color,
                          border: Border.all(color: Colors.white, width: 3),
                          boxShadow: [
                            BoxShadow(
                                color: Colors.black.withValues(alpha: 0.35),
                                blurRadius: 8),
                          ],
                        ),
                      ),
                    ),
                  ),
                  // 拾取手势
                  Positioned.fill(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onPanDown: (d) => _pick(d.localPosition, center, radius),
                      onPanUpdate: (d) => _pick(d.localPosition, center, radius),
                      child: const SizedBox.expand(),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  void _pick(Offset local, Offset center, double radius) {
    final dx = local.dx - center.dx;
    final dy = local.dy - center.dy;
    final dist = math.sqrt(dx * dx + dy * dy);
    final sat = (dist / radius).clamp(0.0, 1.0);
    var angle = math.atan2(dy, dx) * 180 / math.pi; // 0°=右（红），顺时针
    if (angle < 0) angle += 360;
    onChanged(angle, sat);
  }
}

class _WheelPainter extends CustomPainter {
  const _WheelPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final center = rect.center;
    final radius = size.shortestSide / 2;

    // 色相环：0°=红，顺时针黄(60°)/绿(120°)/青(180°)/蓝(240°)/品红(300°)，
    // 与 _pick 的角度换算一致，保证所见即所得。
    const stops = [0.0, 1 / 6, 2 / 6, 3 / 6, 4 / 6, 5 / 6, 1.0];
    const colors = [
      Color(0xFFFF0000), Color(0xFFFFFF00), Color(0xFF00FF00),
      Color(0xFF00FFFF), Color(0xFF0000FF), Color(0xFFFF00FF),
      Color(0xFFFF0000),
    ];
    final huePaint = Paint()
      ..shader = SweepGradient(colors: colors, stops: stops).createShader(rect);
    canvas.drawCircle(center, radius, huePaint);

    // 饱和度：圆心白 → 边缘透明（圆心即白 S=0）
    final satPaint = Paint()
      ..shader = RadialGradient(
        colors: [Colors.white, Colors.white.withValues(alpha: 0)],
      ).createShader(rect);
    canvas.drawCircle(center, radius, satPaint);
  }

  @override
  bool shouldRepaint(covariant _WheelPainter old) => false;
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
        // 圆形颜色预览（与圆形取色器统一）
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
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
      padding: EdgeInsets.only(top: Spacing.gap16, bottom: 0),
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
