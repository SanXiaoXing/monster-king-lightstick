import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../app/theme/app_theme.dart';
import '../../../../shared/theme/spacing.dart';
import '../../../../shared/widgets/app_top_bar.dart';
import '../../../../shared/widgets/connect_guard_view.dart';
import '../../../../shared/widgets/slider_row.dart';
import '../../../device/data/device_repository.dart';
import '../../../device/presentation/device_view_model.dart';
import '../../../lighting/data/lighting_repository.dart';
import '../../../lighting/domain/lighting_effect.dart';
import '../../../settings/settings_store.dart';
import '../../data/audio_repository.dart';
import '../../domain/audio_analysis.dart';
import '../widgets/circular_visualizer.dart';

/// 音乐页（Dock「音乐」Tab）。
///
/// 对齐原型音乐屏语义，可视化升级为 Audio-reactive 圆形可视化
/// （发光圆环 + 中心光球 + 强拍粒子爆发，见 circular_visualizer.dart）。
/// 分析链路（对齐 docs/design/music.md 音乐调光设置）：
/// record 采集 PCM → Rust `PcmAnalyzer` 分析帧 → Rust `MusicRhythm`
/// 律动引擎（亮度 = 音量 × 灵敏度、15 色板循环换色）→ 荧光棒下发。
/// 未采集时显示静默状态。顶部统一用 [AppTopBar]；未连接设备时正文锁定为连接引导。
class MusicPage extends StatefulWidget {
  const MusicPage({super.key, required this.viewModel, this.onGoConnect});

  final DeviceViewModel viewModel;

  /// 未连接时「去连接」按钮回调（Dock 宿主切换 Tab；独立页可不传）。
  final VoidCallback? onGoConnect;

  @override
  State<MusicPage> createState() => _MusicPageState();
}

class _MusicPageState extends State<MusicPage> {
  final AudioRepository _audio = AudioRepository();
  final LightingRepository _lighting = LightingRepository(DeviceRepository());
  final ValueNotifier<AudioFrame?> _frameNotifier = ValueNotifier(null);
  StreamSubscription<AudioFrame>? _sub;

  // 律动模式：单色 / 七彩 / 强烈 / 柔和（初始值来自设置页默认）
  String _mode = SettingsStore.defaultMode;
  double _sensitivity = SettingsStore.defaultSensitivity;
  bool _active = false;

  @override
  void initState() {
    super.initState();
    _mode = SettingsStore.readMode();
    _sensitivity = SettingsStore.readSensitivity();
  }

  /// 荧光棒下发节流：分析帧 ~86fps（50% 重叠窗），BLE writeNoResponse
  /// 实测可稳定承载 ~16Hz；取 60ms 在跟手性与无线可靠性间折中。
  static const _stickInterval = Duration(milliseconds: 60);
  DateTime? _lastStickSend;

  /// 上一次下发尚未完成时丢帧不排队，避免慢 BLE 链路上命令积压、
  /// 灯光响应越来越滞后于音乐。
  bool _stickBusy = false;

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
    unawaited(_audio.setRhythmMode(m));
    // 单色律动用当前主题强调色作为固定颜色
    if (m == '单色律动') {
      final accent = Theme.of(context).colorScheme.primary;
      unawaited(_audio.setRhythmBaseColor(
        (accent.r * 255).round(),
        (accent.g * 255).round(),
        (accent.b * 255).round(),
      ));
    }
    if (_ensureConnected()) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text('已切换律动：$m')));
    }
  }

  /// 音频帧 → 荧光棒灯效（节流 60ms + 在途丢帧；未连接/写失败静默，不刷屏）。
  ///
  /// 颜色与亮度由 Rust 律动引擎计算（亮度 = 音量 × 灵敏度，色板循环），
  /// 本页只负责节流与下发。
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

    // 静默失败：Rust 引擎/写失败不弹错；完成后解除在途标记
    _stickBusy = true;
    unawaited(
      _audio
          .nextRhythm(f)
          .then((out) => _lighting.sendEffect(
                device,
                fx: LightingFx.constantlyOn,
                color: Color.fromARGB(255, out.rgb[0], out.rgb[1], out.rgb[2]),
                brightness: out.brightness,
              ))
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
            padding: EdgeInsets.symmetric(horizontal: Spacing.pageMargin),
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
                    onChanged: (v) {
                      setState(() => _sensitivity = v);
                      unawaited(_audio.setRhythmSensitivity(v));
                    },
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
          // extendBody 下内容延伸到玻璃导航栏下方，留白让末项可滚出遮挡区
          const SliverToBoxAdapter(child: SizedBox(height: Spacing.bottomSafe)),
        ],
      ),
    );

    // 未连接设备：正文锁定为连接引导，功能不可用
    return Scaffold(
      appBar: AppTopBar(title: '音乐律动'),
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
  const _Heading({required this.active});
  final bool active;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: EdgeInsets.fromLTRB(Spacing.pageMargin, 14, Spacing.pageMargin, 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Text(
                '音频实时驱动发光圆环：低频推动环体、高频细密振荡、强拍脉冲爆发。',
                style: TextStyle(
                    color: scheme.onSurfaceVariant, fontSize: 13, height: 1.55)),
          ),
          const SizedBox(width: 12),
          _StatusDot(active: active),
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
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 11),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
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
