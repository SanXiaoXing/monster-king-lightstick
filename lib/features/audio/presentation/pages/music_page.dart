import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../app/theme/app_theme.dart';
import '../../../../shared/widgets/slider_row.dart';
import '../../../device/data/device_repository.dart';
import '../../../device/presentation/device_view_model.dart';
import '../../../lighting/data/lighting_repository.dart';
import '../../../lighting/domain/lighting_effect.dart';
import '../../data/audio_repository.dart';
import '../../domain/audio_analysis.dart';
import '../widgets/circular_visualizer.dart';

/// 音乐页（Dock「音乐」Tab）。
///
/// 对齐原型音乐屏语义，可视化升级为 Audio-reactive 圆形可视化
/// （发光圆环 + 中心光球 + 强拍粒子爆发，见 circular_visualizer.dart）。
/// 频谱由麦克风采集（record 插件）→ 纯 Dart FFT 分析（AudioAnalyzer）驱动，
/// 与监听音乐实时同步；未采集时显示静默状态。
/// `embedded=true` 时无 AppBar，由 Dock 壳托管。
class MusicPage extends StatefulWidget {
  const MusicPage({super.key, required this.viewModel, this.embedded = false});

  final DeviceViewModel viewModel;
  final bool embedded;

  @override
  State<MusicPage> createState() => _MusicPageState();
}

class _MusicPageState extends State<MusicPage> {
  final AudioRepository _audio = AudioRepository();
  final LightingRepository _lighting = LightingRepository(DeviceRepository());
  final ValueNotifier<AudioFrame?> _frameNotifier = ValueNotifier(null);
  StreamSubscription<AudioFrame>? _sub;

  // 律动模式：单色 / 七彩 / 强烈 / 柔和
  String _mode = '单色律动';
  double _sensitivity = 0.6;
  bool _active = false;

  /// 荧光棒下发节流：分析帧 ~86fps（50% 重叠窗），BLE writeNoResponse
  /// 实测可稳定承载 ~16Hz；取 60ms 在跟手性与无线可靠性间折中。
  static const _stickInterval = Duration(milliseconds: 60);
  DateTime? _lastStickSend;

  /// 上一次下发尚未完成时丢帧不排队，避免慢 BLE 链路上命令积压、
  /// 灯光响应越来越滞后于音乐。
  bool _stickBusy = false;

  /// 主导频带平滑位置（0..1，指数平滑防跳变；对应能量峰值所在频带）。
  double _smoothPeak = 0;

  @override
  void dispose() {
    _sub?.cancel();
    _audio.dispose();
    _frameNotifier.dispose();
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

  /// 音频帧 → 荧光棒灯效（节流 60ms + 在途丢帧；未连接/写失败静默，不刷屏）。
  ///
  /// 映射：主导频带（能量峰值所在频带）→ 色相，低音偏暖、高音偏冷，
  /// 指数平滑防跳变；音量→亮度，强拍→亮度瞬间拉满（鼓点闪亮）。
  void _syncStick(AudioFrame f) {
    final device = widget.viewModel.activeDevice;
    if (device == null || !widget.viewModel.status.isConnected) return;
    if (_stickBusy) return; // 上一次写入未完成：丢帧防积压
    final now = DateTime.now();
    if (_lastStickSend != null &&
        now.difference(_lastStickSend!) < _stickInterval) {
      return;
    }
    _lastStickSend = now;

    // 主导频带：能量峰值所在频带索引 → 归一化位置（0..1，低音→高音）
    var peakIdx = 0;
    var peakVal = -1.0;
    for (var i = 0; i < f.bands.length; i++) {
      if (f.bands[i] > peakVal) {
        peakVal = f.bands[i];
        peakIdx = i;
      }
    }
    final peakNorm = f.bands.isEmpty ? 0.0 : peakIdx / (f.bands.length - 1);
    // 指数平滑（节流 60ms 一帧，取 0.5 系数约 3 帧 ≈ 180ms 收敛，
    // 防频带跳变闪烁的同时不明显拖慢色相跟随）
    _smoothPeak = _smoothPeak * 0.5 + peakNorm * 0.5;

    // 色相：低音(0)→红/橙，中音→绿，高音→蓝紫；映射到 0~300 避开红紫相接
    final hue = _smoothPeak * 300;
    final color = HSVColor.fromAHSV(
      1,
      hue,
      0.85,
      (0.45 + 0.55 * f.volume).clamp(0.0, 1.0),
    ).toColor();
    // 亮度死区：音量过低视为静音，荧光棒熄灭，避免底噪下微亮。
    // 死区取低（0.04）：小音量音乐播放时灯棒保持跟随，不提前熄灭
    final brightness = f.isBeat
        ? 1.0
        : f.volume < 0.04
            ? 0.0
            : ((f.volume - 0.04) / 0.96).clamp(0.0, 1.0);

    // 静默失败：避免每次节拍弹错；完成后解除在途标记
    _stickBusy = true;
    unawaited(
      _lighting
          .sendEffect(device, fx: LightingFx.constantlyOn, color: color, brightness: brightness)
          .catchError((_) {})
          .whenComplete(() => _stickBusy = false),
    );
  }

  /// 开始/暂停监听：开=申请权限并采集，关=停止采集恢复静默状态。
  Future<void> _toggle() async {
    if (_active) {
      await _sub?.cancel();
      _sub = null;
      await _audio.stop();
      _frameNotifier.value = null;
      _lastStickSend = null;
      if (!mounted) return;
      setState(() => _active = false);
      return;
    }
    try {
      final stream = await _audio.start();
      _sub = stream.listen(
        (f) {
          _frameNotifier.value = f;
          _syncStick(f);
        },
        onError: (Object e) {
          if (!mounted) return;
          ScaffoldMessenger.of(context)
            ..hideCurrentSnackBar()
            ..showSnackBar(SnackBar(content: Text('音频采集异常：$e')));
        },
      );
      if (!mounted) return;
      setState(() => _active = true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text('无法采集音乐：$e')));
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
                  CircularVisualizer(
                    frameNotifier: _frameNotifier,
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
                    onTap: _toggle,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );

    if (widget.embedded) {
      // 导航栏已是 Scaffold.bottomNavigationBar，框架自动在导航栏之上布局，
      // 不再需要为悬浮 Dock 手动留白。
      return SafeArea(bottom: false, child: content);
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
          Text('音频实时驱动发光圆环：低频推动环体、高频细密振荡、强拍脉冲爆发。',
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
