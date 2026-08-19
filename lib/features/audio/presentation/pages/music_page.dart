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
                  const SizedBox(height: 14),
                  _MusicSwitchRow(
                    active: _active,
                    onToggle: _toggle,
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
                  _ModePill(selected: _mode, onPick: _onMode),
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

/// 律动模式：1×4 段按钮（prototype_redesign `.mode-pill` 的 Flutter 同构）。
/// 外层 pill 容器 + 4 px 内距，每个 cell 仅文字标签（不带 icon）；
/// 选中：accent 填充 + 白字 + 阴影，未选：透明 + muted 字。
/// `value` 保留 Rust 律动引擎所需的完整模式名（如「单色律动」），
/// `label` 是短显名（与 prototype 的「单色 / 七彩 / 强烈 / 柔和」一致）。
/// 功能不变：mode 状态机、SettingsStore 读写路径不变。
class _ModePill extends StatelessWidget {
  const _ModePill({required this.selected, required this.onPick});
  final String selected;
  final void Function(String) onPick;

  static const _modes = <(String, String)>[
    ('单色律动', '单色'),
    ('七彩律动', '七彩'),
    ('强烈', '强烈'),
    ('柔和', '柔和'),
  ];

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Row(
        children: [
          for (final (value, label) in _modes)
            Expanded(
              child: _ModePillCell(
                value: value,
                label: label,
                active: selected == value,
                onTap: () => onPick(value),
              ),
            ),
        ],
      ),
    );
  }
}

class _ModePillCell extends StatelessWidget {
  const _ModePillCell({
    required this.value,
    required this.label,
    required this.active,
    required this.onTap,
  });

  final String value;
  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      label: '律动模式：$value',
      selected: active,
      button: true,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.symmetric(vertical: 9),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: active ? scheme.primary : Colors.transparent,
            borderRadius: BorderRadius.circular(999),
            boxShadow: active
                ? [
                    BoxShadow(
                      color: scheme.primary.withValues(alpha: 0.32),
                      blurRadius: 14,
                      offset: const Offset(0, 6),
                    )
                  ]
                : null,
          ),
          child: AnimatedDefaultTextStyle(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.4,
              color: active ? Colors.white : scheme.onSurfaceVariant,
            ),
            child: Text(label),
          ),
        ),
      ),
    );
  }
}

/// 音乐响应开关行：prototype_redesign 中 `.switch-row` 的 Flutter 同构。
/// 左侧大标题 + 副标题（静态展示，仅作上下文），右侧 iOS 风格 51×31 开关。
/// 整体不接 InkWell，仅开关接 _toggle()，与 prototype "只点开关才翻转" 的行为等价。
class _MusicSwitchRow extends StatelessWidget {
  const _MusicSwitchRow({required this.active, required this.onToggle});
  final bool active;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '音乐响应',
                  style: TextStyle(
                    color: scheme.onSurface,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -0.05,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  '开启后跟随环境音量',
                  style: TextStyle(
                    color: scheme.onSurfaceVariant,
                    fontSize: 11,
                    letterSpacing: 0.4,
                  ),
                ),
              ],
            ),
          ),
          _IosSwitch(active: active, onTap: onToggle),
        ],
      ),
    );
  }
}

/// iOS 风格开关（51×31 px，与 prototype_redesign `.switch` 严格对齐）。
/// 轨道：未开 `rgba(126,141,166,.32)`，开启 `scheme.primary`；
/// 旋钮：27 px 白色圆，偏移 20 px，开启时回弹 easeOutBack。
class _IosSwitch extends StatelessWidget {
  const _IosSwitch({required this.active, required this.onTap});
  final bool active;
  final VoidCallback onTap;

  static const double _trackW = 51;
  static const double _trackH = 31;
  static const double _knob = 27;
  static const Color _trackInactive = Color(0x527E8DA6); // rgba(126,141,166,.32)

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      label: '音乐响应',
      toggled: active,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          width: _trackW,
          height: _trackH,
          decoration: BoxDecoration(
            color: active ? scheme.primary : _trackInactive,
            borderRadius: BorderRadius.circular(_trackH / 2),
          ),
          padding: const EdgeInsets.all(2),
          child: AnimatedAlign(
            duration: const Duration(milliseconds: 320),
            curve: Curves.easeOutBack,
            alignment: active ? Alignment.centerRight : Alignment.centerLeft,
            child: Container(
              width: _knob,
              height: _knob,
              decoration: BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x4D000000),
                    blurRadius: 6,
                    offset: Offset(0, 2),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
