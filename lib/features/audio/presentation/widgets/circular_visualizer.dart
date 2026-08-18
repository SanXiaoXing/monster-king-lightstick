import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../domain/audio_analysis.dart';

/// Audio-reactive 圆形可视化：发光圆环 + 中心光球 + 强拍粒子爆发。
///
/// 颜色与亮度由页面每帧算好后经 [displayColor] / [displayBrightness] 推入，
/// 圆环如实镜像应援棒当前显示（随音=随音高流动的色相、单色=固定色、七彩=平滑周期色），
/// 不再自行按模式推导色相。
///
/// 动画仍由以下音频特征驱动：
/// - 低频 bass：圆环半径慢速大位移（低音越大、动作越大越慢）
/// - 高频 treble：圆环细密快速振荡（高频越强、振荡越细越快）
/// - 音量 volume：中心光球尺寸
/// - 强拍 isBeat：径向脉冲 + 粒子爆发
///
/// Ticker 以 60fps 平滑（指数 attack/decay），音频帧（~86fps）只更新目标值，
/// 视觉层与采集层解耦，动画始终顺滑。
class CircularVisualizer extends StatefulWidget {
  const CircularVisualizer({
    super.key,
    required this.frameNotifier,
    required this.active,
    required this.sensitivity,
    required this.displayColor,
    required this.displayBrightness,
  });

  final ValueListenable<AudioFrame?> frameNotifier;
  final bool active;
  final double sensitivity;

  /// 当前显示颜色（单色=所选色，七彩=步进色板中的当前色），由页面每帧推入。
  final ValueListenable<Color> displayColor;

  /// 当前显示亮度 0..1（单色随音量、七彩=亮灭包络×音量），由页面每帧推入。
  final ValueListenable<double> displayBrightness;

  @override
  State<CircularVisualizer> createState() => _CircularVisualizerState();
}

class _CircularVisualizerState extends State<CircularVisualizer>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  final _VisualState _state = _VisualState();
  final ValueNotifier<int> _repaint = ValueNotifier(0);
  Duration _last = Duration.zero;

  @override
  void initState() {
    super.initState();
    widget.frameNotifier.addListener(_onFrame);
    widget.displayColor.addListener(_onViz);
    widget.displayBrightness.addListener(_onViz);
    _state.setColor(widget.displayColor.value, widget.displayBrightness.value);
    _ticker = createTicker(_onTick)..start();
  }

  void _onFrame() {
    _state.update(widget.active ? widget.frameNotifier.value : null);
  }

  void _onViz() {
    _state.setColor(widget.displayColor.value, widget.displayBrightness.value);
    _repaint.value++;
  }

  void _onTick(Duration elapsed) {
    final dt = (elapsed - _last).inMicroseconds / 1e6;
    _last = elapsed;
    _state.tick(dt);
    // 完全静止（无信号、无粒子、能量落底）时跳过重绘，省电且不占 UI 线程
    if (_state.isIdle) return;
    _repaint.value++;
  }

  @override
  void dispose() {
    widget.frameNotifier.removeListener(_onFrame);
    widget.displayColor.removeListener(_onViz);
    widget.displayBrightness.removeListener(_onViz);
    _ticker.dispose();
    _repaint.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return LayoutBuilder(
      builder: (context, c) {
        final w = c.maxWidth;
        final h = w * 0.78; // 可视化区域高（与原频谱一致）
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
              painter: _CircularPainter(
                state: _state,
                repaint: _repaint,
                sensitivity: widget.sensitivity,
              ),
            ),
          ),
        );
      },
    );
  }
}

/// 可视化共享状态：目标值（音频帧）+ 平滑当前值 + 粒子 + 当前显示色/亮度。
class _VisualState {
  // 静音判定阈值：分析器已对底噪做绝对门限+软过渡（RMS < 0.008 输出
  // 全零帧），这里再用音量迟滞兜底——低于下限冻结 time（细振荡立刻停），
  // 高于上限恢复推进，中间迟滞避免临界抖动。
  // 阈值取低：小音量音乐不会被误判静音而停掉律动。
  static const _silenceLow = 0.03;
  static const _silenceHigh = 0.07;
  bool _hasSignal = false;
  // 目标值
  double _tVol = 0, _tBass = 0, _tTreble = 0;
  final List<double> _tBands = List.filled(28, 0);
  // 平滑当前值
  double vol = 0, bass = 0, treble = 0;
  final List<double> amps = List.filled(72, 0);
  double pulse = 0;
  double time = 0;
  final List<_Particle> _particles = [];

  /// 当前显示色与亮度（页面每帧推入，_CircularPainter 据此上色）。
  Color vizColor = Colors.blue;
  double vizBright = 0;

  List<_Particle> get particles => _particles;

  /// 完全静止：无信号、无粒子、能量与脉冲均已落底（可跳过重绘）。
  bool get isIdle {
    if (_hasSignal ||
        _particles.isNotEmpty ||
        pulse >= 0.01 ||
        vol >= 0.005 ||
        bass >= 0.005 ||
        treble >= 0.005) {
      return false;
    }
    for (final a in amps) {
      if (a >= 0.005) return false;
    }
    return true;
  }

  void setColor(Color c, double bright) {
    vizColor = c;
    vizBright = bright.clamp(0.0, 1.0);
  }

  void update(AudioFrame? f) {
    if (f == null) {
      _hasSignal = false;
      _tVol = _tBass = _tTreble = 0;
      for (var i = 0; i < _tBands.length; i++) {
        _tBands[i] = 0;
      }
      return;
    }
    // 音量门限（迟滞）：低于下限视为静音，高于上限恢复
    if (f.volume > _silenceHigh) {
      _hasSignal = true;
    } else if (f.volume < _silenceLow) {
      _hasSignal = false;
    }
    _tVol = f.volume;
    _tBass = f.bass;
    _tTreble = f.treble;
    for (var i = 0; i < _tBands.length && i < f.bands.length; i++) {
      _tBands[i] = f.bands[i];
    }
    if (f.isBeat) {
      pulse = 1;
      _spawnParticles(f.volume);
    }
  }

  void tick(double dt) {
    if (_hasSignal) {
      // 仅在有真实音频信号时推进时间：高频细振荡相位随音乐走
      time += dt;
    }
    // attack/decay：上升快、回落更快，声音一停柱子立刻落底。
    // attack 时间常数（20~35ms）控制在 1~2 个分析帧周期内，保证跟手性；
    // decay 略长保留余韵，避免闪烁。
    vol = _smooth(vol, _tVol, 0.025, 0.09, dt);
    bass = _smooth(bass, _tBass, 0.035, 0.14, dt);
    treble = _smooth(treble, _tTreble, 0.02, 0.07, dt);
    for (var i = 0; i < amps.length; i++) {
      final b = (i * 28 / amps.length).floor().clamp(0, 27);
      amps[i] = _smooth(amps[i], _tBands[b], 0.02, 0.07, dt);
    }
    pulse *= math.exp(-dt / 0.18);

    // 粒子：向外飞散 + 衰减
    for (final p in _particles) {
      p.life -= dt;
      p.radius += p.speed * dt;
      p.angle += p.spin * dt;
    }
    _particles.removeWhere((p) => p.life <= 0);
  }

  void _spawnParticles(double vol) {
    final count = 8 + (vol * 22).round();
    for (var i = 0; i < count; i++) {
      _particles.add(_Particle(
        angle: math.pi * 2 * math.Random().nextDouble(),
        radius: 0.95 + math.Random().nextDouble() * 0.25,
        speed: 40 + math.Random().nextDouble() * 140,
        spin: (math.Random().nextDouble() - 0.5) * 2.2,
        life: 0.5 + math.Random().nextDouble() * 0.7,
        size: 1.5 + math.Random().nextDouble() * 2.2,
      ));
    }
    if (_particles.length > 160) {
      _particles.removeRange(0, _particles.length - 160);
    }
  }

  /// 指数平滑：目标>当前走 attack 时间常数，回落走 decay。
  static double _smooth(double cur, double target, double attack, double decay, double dt) {
    final tau = target > cur ? attack : decay;
    return cur + (target - cur) * (1 - math.exp(-dt / math.max(1e-4, tau)));
  }
}

class _Particle {
  _Particle({
    required this.angle,
    required this.radius,
    required this.speed,
    required this.spin,
    required this.life,
    required this.size,
  });

  double angle;
  double radius;
  final double speed;
  final double spin;
  double life;
  final double size;
}

class _CircularPainter extends CustomPainter {
  _CircularPainter({
    required this.state,
    required this.repaint,
    required this.sensitivity,
  }) : super(repaint: repaint);

  final _VisualState state;
  final Listenable repaint;
  final double sensitivity;

  static const _points = 72;

  // 复用 Paint 对象（每帧 72 柱 ×3 笔 + 粒子，新建 Paint 会造成 GC 压力）
  final Paint _glowOuterPaint = Paint()..strokeCap = StrokeCap.round;
  final Paint _glowInnerPaint = Paint()..strokeCap = StrokeCap.round;
  final Paint _barPaint = Paint()..strokeCap = StrokeCap.round;
  final Paint _tipPaint = Paint();
  final Paint _particlePaint = Paint();

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final R = size.shortestSide * 0.27; // 基准环半径
    final gain = 0.6 + sensitivity * 0.8;
    final vol = state.vol, treble = state.treble;
    final color = state.vizColor;
    final bright = state.vizBright;

    // ---- 中心光球：半径随音量，强拍时径向膨胀；颜色=当前显示色 ----
    final orbR = R * (0.40 + vol * 0.52) * (1 + state.pulse * 0.25);
    final orbGlow = Paint()
      ..shader = RadialGradient(
        colors: [
          color.withValues(alpha: 0.5 * bright + 0.04),
          color.withValues(alpha: 0.0),
        ],
      ).createShader(Rect.fromCircle(center: center, radius: orbR * 2.2));
    canvas.drawCircle(center, orbR * 2.2, orbGlow);
    canvas.drawCircle(
      center,
      orbR,
      Paint()
        ..shader = RadialGradient(
          colors: [
            Colors.white.withValues(alpha: 0.85 + 0.1 * bright),
            color,
            color.withValues(alpha: 0.25),
          ],
          stops: const [0, 0.55, 1],
        ).createShader(Rect.fromCircle(center: center, radius: orbR)),
    );

    // ---- 柱状环：低频控整体半径（慢大），频带能量控柱长，高频细振荡 ----
    _drawBars(canvas, center, R, gain, vol, treble, color, bright);

    // ---- 强拍粒子：径向飞散的小光点（颜色=当前显示色）----
    for (final p in state.particles) {
      final alpha = (p.life / 1.2).clamp(0.0, 1.0);
      final pos = Offset(
        center.dx + math.cos(p.angle) * p.radius * R,
        center.dy + math.sin(p.angle) * p.radius * R,
      );
      final r = p.size * (0.6 + alpha * 0.6);
      _particlePaint
        ..color = color.withValues(alpha: alpha * 0.25 * (0.4 + 0.6 * bright))
        ..maskFilter = null;
      canvas.drawCircle(pos, r * 2.2, _particlePaint);
      _particlePaint.color = color.withValues(alpha: alpha * 0.85 * (0.4 + 0.6 * bright));
      canvas.drawCircle(pos, r, _particlePaint);
    }
  }

  /// 柱状环：72 根径向柱条，绕中心光球一圈。
  ///
  /// - 低频 bass：整体基准半径慢速胀缩（低音越大环越大）
  /// - 频带能量：单柱长度（每柱对应一个频带）
  /// - 高频 treble：柱顶细密快速振荡
  /// - 音量 vol：柱宽 / 辉光强度 / 柱顶亮斑
  /// - 强拍 pulse：整环径向脉冲
  /// - 颜色/亮度：来自页面推入的当前显示色与亮度（如实镜像应援棒）
  ///
  /// 辉光用两层递增宽度、递减透明度的描边模拟，替代逐柱 MaskFilter.blur
  /// （72 柱 ×2 次模糊是律动卡顿的主因之一，模糊滤镜每帧逐笔画光栅化）。
  void _drawBars(Canvas canvas, Offset center, double R, double gain, double vol, double treble,
      Color color, double bright) {
    final barCount = _points;
    final beatBoost = 1 + state.pulse * 0.2;
    final baseR = R * (1 + state.bass * 0.42 * gain) * beatBoost;
    // 柱宽：占单柱角距的 55%，留出间隙更优雅
    final barW = (2 * math.pi * baseR / barCount) * 0.55;

    for (var i = 0; i < barCount; i++) {
      final a = 2 * math.pi * i / barCount;
      final dir = Offset(math.cos(a), math.sin(a));
      // 柱长：静止保底 + 频带能量驱动 + 高频细振荡
      final amp = state.amps[i];
      final fine = treble * R * 0.06 * gain * math.sin(i * 2.7 + state.time * 22);
      final barLen = (R * 0.06 + amp * R * 0.3 * gain + fine).clamp(0.0, R * 0.62);
      final rIn = baseR * 0.88;
      final rOut = baseR + barLen;
      final pIn = center + dir * rIn;
      final pOut = center + dir * rOut;

      // 辉光外层（宽而淡，随亮度起伏）
      _glowOuterPaint
        ..strokeWidth = barW * 3.0
        ..color = color.withValues(alpha: 0.10 + 0.10 * bright);
      canvas.drawLine(pIn, pOut, _glowOuterPaint);
      // 辉光内层（略宽、稍亮）
      _glowInnerPaint
        ..strokeWidth = barW * 1.8
        ..color = color.withValues(alpha: 0.18 + 0.16 * bright);
      canvas.drawLine(pIn, pOut, _glowInnerPaint);
      // 主体柱（圆头，颜色即当前显示色）
      _barPaint
        ..strokeWidth = barW
        ..color = color;
      canvas.drawLine(pIn, pOut, _barPaint);
      // 柱顶亮斑（能量越强越亮；双层圆模拟柔光，整体随亮度起伏）
      final tipR = barW * (0.35 + 0.4 * amp);
      _tipPaint.color = Colors.white.withValues(alpha: (0.08 + 0.2 * amp) * (0.35 + 0.65 * bright));
      canvas.drawCircle(pOut, tipR * 1.9, _tipPaint);
      _tipPaint.color = Colors.white.withValues(alpha: (0.25 + 0.6 * amp) * (0.35 + 0.65 * bright));
      canvas.drawCircle(pOut, tipR, _tipPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _CircularPainter old) => old.sensitivity != sensitivity;
}
