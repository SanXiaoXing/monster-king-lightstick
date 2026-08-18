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
import '../../../lighting/data/lighting_repository.dart';
import '../../../lighting/domain/lighting_effect.dart';
import '../../data/audio_repository.dart';
import '../../domain/audio_analysis.dart';
import '../../domain/light_rhythm.dart';
import '../widgets/circular_visualizer.dart';

/// 音乐页（Dock「音乐」Tab）。
///
/// 三种音频律动：
/// - **随音律动**：颜色随音高在红橙黄绿青蓝紫间平滑流动（主导频带→色相），
///   亮度随音量/强拍脉冲 —— 最初被认可的"活"的律动感。
/// - **单色律动**：先选一个固定颜色，亮度随声音实时呼吸（强拍快闪 + 微光地板），
///   颜色本身不变。
/// - **七彩律动**：按声音在 7 色间平滑周期换色，叠加呼吸亮灭包络，规律显示。
/// 频谱由麦克风采集（record 插件）→ 纯 Dart FFT 分析（AudioAnalyzer）驱动，
/// 与监听音乐实时同步；未采集时显示静默状态。顶部统一用 [AppTopBar]。
class MusicPage extends StatefulWidget {
  const MusicPage({super.key, required this.viewModel, this.onGoConnect});

  final DeviceViewModel viewModel;

  /// 未连接时「去连接」按钮回调（Dock 宿主切换 Tab；独立页可不传）。
  final VoidCallback? onGoConnect;

  @override
  State<MusicPage> createState() => _MusicPageState();
}

/// 单色律动可选色板（含白，边框保证深浅主题可见）。
const _singleSwatches = <Color>[
  Color(0xFFFF3B30), // 红
  Color(0xFFFF9500), // 橙
  Color(0xFFFFCC00), // 黄
  Color(0xFF34C759), // 绿
  Color(0xFF32ADE6), // 青
  Color(0xFF007AFF), // 蓝
  Color(0xFFAF52DE), // 紫
  Color(0xFFFF2D55), // 粉
  Color(0xFFFFFFFF), // 白
];

class _MusicPageState extends State<MusicPage> {
  final AudioRepository _audio = AudioRepository();
  final LightingRepository _lighting = LightingRepository(DeviceRepository());
  final ValueNotifier<AudioFrame?> _frameNotifier = ValueNotifier(null);
  StreamSubscription<AudioFrame>? _sub;

  // 律动模式：随音 / 单色 / 七彩（默认随音，即最初被认可的观感）
  String _mode = '随音律动';
  double _sensitivity = LightRhythm.defaultSensitivity; // 节奏灵敏度（增益 0..1，默认 0.6）
  bool _active = false;

  /// 单色律动所选颜色（默认蓝，与色板一致以便高亮）。
  Color _pickedColor = const Color(0xFF007AFF);

  /// 律动引擎（领域层）：持有模式/选色/灵敏度与七彩相位状态，
  /// 每帧 process(AudioFrame) → (颜色, 亮度)，单一数据源喂 BLE 与可视化。
  late final LightRhythm _rhythm =
      LightRhythm(pickedColor: _pickedColor, sensitivity: LightRhythm.defaultSensitivity);

  /// 当前显示色 / 亮度（每帧推给可视化，如实镜像应援棒）。
  final ValueNotifier<Color> _vizColor = ValueNotifier(const Color(0xFF32ADE6));
  final ValueNotifier<double> _vizBright = ValueNotifier(0);

  /// 荧光棒下发节流：分析帧 ~86fps（50% 重叠窗），BLE writeNoResponse
  /// 实测可稳定承载 ~16Hz；取 60ms 在跟手性与无线可靠性间折中。
  static const _stickInterval = Duration(milliseconds: 60);
  DateTime? _lastStickSend;

  /// 上一次下发尚未完成时丢帧不排队，避免慢 BLE 链路上命令积压、
  /// 灯光响应越来越滞后于音乐。
  bool _stickBusy = false;

  /// 自动重连：采集流异常/中断后按指数退避持续重试，
  /// 保证切 Tab、App 退后台被系统打断后仍能恢复持续监听。
  Timer? _restartTimer;
  int _restartBackoffSec = 1;

  @override
  void dispose() {
    _restartTimer?.cancel();
    _sub?.cancel();
    _audio.dispose();
    _frameNotifier.dispose();
    _vizColor.dispose();
    _vizBright.dispose();
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
    _rhythm.mode = m;
    _rhythm.reset(); // 切换重置跨帧状态，避免跨模式颜色突跳
    _vizColor.value = m == '单色律动'
        ? _pickedColor
        : LightRhythm.sevenPalette[0]; // 随音/七彩首帧即覆盖
    if (_ensureConnected()) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text('已切换律动：$m')));
    }
  }

  void _onPickColor(Color c) {
    setState(() => _pickedColor = c);
    _rhythm.pickedColor = c;
    _vizColor.value = c;
    if (_ensureConnected()) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
            SnackBar(content: Text('单色律动已选色 #${c.toARGB32().toRadixString(16).substring(2).toUpperCase()}')));
    }
  }

  /// 音频帧 → 当前显示色 + 亮度（由 [LightRhythm] 计算，单一数据源）；
  /// 推给可视化后节流下发荧光棒。
  void _syncStick(AudioFrame f) {
    final (color, brightness) = _rhythm.process(f);
    _vizColor.value = color;
    _vizBright.value = brightness;

    // ── 下发荧光棒（节流 60ms + 在途丢帧；未连接/写失败静默，不刷屏）──
    final device = widget.viewModel.activeDevice;
    if (device == null || !widget.viewModel.status.isConnected) return;
    if (_stickBusy) return; // 上一次写入未完成：丢帧防积压
    final now = DateTime.now();
    if (_lastStickSend != null &&
        now.difference(_lastStickSend!) < _stickInterval) {
      return;
    }
    _lastStickSend = now;

    _stickBusy = true;
    unawaited(
      _lighting
          .sendEffect(device, fx: LightingFx.constantlyOn, color: color, brightness: brightness)
          .catchError((_) {})
          .whenComplete(() => _stickBusy = false),
    );
  }

  /// 开始/暂停监听：开=申请权限并采集，关=停止采集与自动重连。
  Future<void> _toggle() async {
    if (_active) {
      _restartTimer?.cancel();
      _restartBackoffSec = 1;
      await _sub?.cancel();
      _sub = null;
      await _audio.stop();
      _frameNotifier.value = null;
      _lastStickSend = null;
      _rhythm.reset();
      _vizColor.value = const Color(0xFF32ADE6);
      _vizBright.value = 0;
      if (!mounted) return;
      setState(() => _active = false);
      return;
    }
    // 先标记“想要监听”，让自动重连机制接管后续会话维护
    setState(() => _active = true);
    await _startListening();
  }

  /// 建立监听会话；流中断/异常时由 [_scheduleRestart] 自动重建。
  Future<void> _startListening({bool isRestart = false}) async {
    _restartTimer?.cancel();
    await _sub?.cancel();
    _sub = null;
    // 重试前先停掉可能残留的旧采集会话（record 不允许重复 start）
    await _audio.stop();
    try {
      final stream = await _audio.start();
      if (!mounted || !_active) {
        // 等待期间用户已暂停：丢弃本次会话
        await _audio.stop();
        return;
      }
      _sub = stream.listen(
        (f) {
          _restartBackoffSec = 1; // 收到帧即稳定，重置退避
          _frameNotifier.value = f;
          _syncStick(f);
        },
        // 中断静默自动重连，不弹错误刷屏（后台场景会频繁触发）
        onError: (Object e) => _scheduleRestart(),
        onDone: _scheduleRestart,
      );
    } catch (e) {
      if (!mounted) return;
      if (!isRestart) {
        // 仅首次（用户主动开启）失败时提示，重试静默
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text('无法采集音乐：$e')));
      }
      _scheduleRestart();
    }
  }

  /// 指数退避重连（1s → 2s → 4s → 封顶 5s）：App 退后台 / 系统打断时
  /// 采集流会 error/onDone，恢复前台后下一次重试即成功，监听不中断。
  void _scheduleRestart() {
    if (!mounted || !_active) return;
    _restartTimer?.cancel();
    final delay = Duration(seconds: _restartBackoffSec);
    _restartBackoffSec = math.min(_restartBackoffSec * 2, 5);
    _restartTimer = Timer(delay, () {
      if (!mounted || !_active) return;
      _startListening(isRestart: true);
    });
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
          const SliverToBoxAdapter(child: _Heading()),
          SliverPadding(
            padding: EdgeInsets.symmetric(horizontal: Spacing.pageMargin),
            sliver: SliverToBoxAdapter(
              child: Column(
                children: [
                  CircularVisualizer(
                    frameNotifier: _frameNotifier,
                    active: _active,
                    // 单滑块同时驱动可视化增益与律动引擎响应强度
                    sensitivity: _sensitivity,
                    displayColor: _vizColor,
                    displayBrightness: _vizBright,
                  ),
                  const SizedBox(height: 18),
                  SliderRow(
                    label: '节奏灵敏度',
                    valueLabel: '${(_sensitivity * 100).round()}%',
                    value: _sensitivity,
                    onChanged: (v) {
                      setState(() => _sensitivity = v);
                      _rhythm.sensitivity = v;
                    },
                  ),
                  const SizedBox(height: 18),
                  _ModeRow(selected: _mode, onPick: _onMode),
                  // 单色律动：显示取色色板
                  if (_mode == '单色律动') ...[
                    const SizedBox(height: 16),
                    _ColorSwatchRow(
                      selected: _pickedColor,
                      onPick: _onPickColor,
                    ),
                  ],
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
  const _Heading();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: EdgeInsets.fromLTRB(Spacing.pageMargin, 14, Spacing.pageMargin, 16),
      child: Text(
          '随音律动：颜色随音高流动。单色：选色后亮度随声音呼吸。七彩：按声音周期换色并带亮灭。',
          style: TextStyle(
              color: scheme.onSurfaceVariant, fontSize: 13, height: 1.55)),
    );
  }
}

class _ModeRow extends StatelessWidget {
  const _ModeRow({required this.selected, required this.onPick});
  final String selected;
  final void Function(String) onPick;

  static const _modes = <(String, IconData)>[
    ('随音律动', Icons.blur_on_rounded),
    ('单色律动', Icons.tonality_rounded),
    ('七彩律动', Icons.auto_awesome_rounded),
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

/// 单色律动取色色板：圆点选色，选中态描边高亮，白点靠边框保证可见。
class _ColorSwatchRow extends StatelessWidget {
  const _ColorSwatchRow({required this.selected, required this.onPick});
  final Color selected;
  final ValueChanged<Color> onPick;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      alignment: WrapAlignment.start,
      children: [
        for (final c in _singleSwatches)
          _Swatch(
            color: c,
            active: c.toARGB32() == selected.toARGB32(),
            outline: scheme.outlineVariant,
            primary: scheme.primary,
            onTap: () => onPick(c),
          ),
      ],
    );
  }
}

class _Swatch extends StatelessWidget {
  const _Swatch({
    required this.color,
    required this.active,
    required this.outline,
    required this.primary,
    required this.onTap,
  });

  final Color color;
  final bool active;
  final Color outline;
  final Color primary;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: Border.all(
              color: active ? primary : outline,
              width: active ? 3 : 1,
            ),
          ),
          child: active
              ? Icon(
                  Icons.check_rounded,
                  size: 18,
                  // 深色块上白勾、浅色块上深勾，保证对比
                  color: color.computeLuminance() > 0.6 ? Colors.black87 : Colors.white,
                )
              : null,
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
