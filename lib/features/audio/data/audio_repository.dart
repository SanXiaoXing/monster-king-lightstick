import 'dart:async';
import 'dart:typed_data';

import 'package:record/record.dart';
import 'package:wanshou/src/rust/api/audio.dart' as frb_audio;
import 'package:wanshou/src/rust/api/lightstick.dart' as frb_light;
import 'package:wanshou/src/rust/lightstick/effect.dart' as frb_effect;

import 'android_listen_service.dart';
import '../domain/audio_analysis.dart';

/// 音频数据访问边界：麦克风采集（record 插件）+ 分析（Rust，经 frb）。
///
/// UI 只依赖本 Repository（领域类型），不直接触碰 frb 生成代码——与
/// DeviceRepository 同接缝（分层铁律见 AGENT.md）。
///
/// 音乐调光链路（对齐 docs/design/music.md）：
/// record 采集 PCM16 → Rust `PcmAnalyzer` 分析出音量/频带/节拍帧 →
/// Rust `MusicRhythm` 律动引擎（亮度 = 音量 × 灵敏度，色板循环）→
/// 灯效输出交 [RhythmOutput] 由调用方下发荧光棒。
class AudioRepository {
  final AudioRecorder _recorder = AudioRecorder();
  // 后台持续监听保活：Android microphone 前台服务 + 唤醒锁（见其类注释）
  final AndroidListenService _listenService = AndroidListenService();

  // Rust 引擎懒创建：start()/nextRhythm 首次调用时经 frb 构造
  // （RustLib 未初始化时静默失败，不阻塞 UI）。
  frb_audio.PcmAnalyzer? _analyzer;
  frb_light.MusicRhythm? _rhythm;

  StreamController<AudioFrame>? _controller;
  StreamSubscription<Uint8List>? _sub;

  bool get isListening => _sub != null;

  Future<frb_audio.PcmAnalyzer> _ensureAnalyzer() async =>
      _analyzer ??= await frb_audio.PcmAnalyzer.create();

  Future<frb_light.MusicRhythm> _ensureRhythm() async =>
      _rhythm ??= await frb_light.MusicRhythm.create();

  /// 请求麦克风权限（Android 运行时弹窗；拒绝返回 false）。
  Future<bool> requestPermission() => _recorder.hasPermission(request: true);

  /// 开始监听麦克风，返回分析帧流（PCM16 单声道 44.1kHz，Rust 分析）。
  ///
  /// 权限被拒时抛出 [StateError]；调用方可先 [requestPermission] 预检。
  Future<Stream<AudioFrame>> start() async {
    if (_sub != null) return _controller!.stream;

    if (!await _recorder.hasPermission(request: true)) {
      throw StateError('麦克风权限被拒绝，无法采集音乐');
    }

    final controller = StreamController<AudioFrame>();
    _controller = controller;

    try {
      final analyzer = await _ensureAnalyzer();
      // 后台持续监听：先拉起 microphone 前台服务（Android 11+ 后台麦克风
      // 限制 + 锁屏保活），再开始采集；采集失败时同步回收服务
      await _listenService.start();
      unawaited(_listenService.requestNotificationPermission());
      // 电池优化豁免：防激进后台清理杀掉监听进程（弹窗可能盖在界面上，
      // 异步不等待，用户可稍后处理）
      unawaited(_listenService.requestIgnoreBatteryOptimizations());
      final pcm = await _recorder.startStream(const RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: 44100,
        numChannels: 1,
        // 音乐采集必须关闭通话向处理：AGC 会让音量忽大忽小（pumping），
        // 噪声抑制/回声消除会把音乐误判为噪声导致失真、闷响、断音
        autoGain: false,
        echoCancel: false,
        noiseSuppress: false,
      ));
      _sub = pcm.listen(
        (bytes) async {
          try {
            final frames = await analyzer.push(chunk: bytes);
            if (frames.isNotEmpty && !controller.isClosed) {
              for (final f in frames) {
                controller.add(_toDomain(f));
              }
            }
          } catch (_) {
            // 单 chunk 分析失败不影响后续帧
          }
        },
        onError: (Object e) {
          if (!controller.isClosed) controller.addError(e);
        },
        onDone: () {
          _sub = null;
          if (!controller.isClosed) controller.close();
        },
      );
    } catch (e) {
      await _listenService.stop();
      await controller.close();
      _controller = null;
      rethrow;
    }
    return controller.stream;
  }

  /// 律动设置 → Rust 引擎（不可用时静默降级，不阻塞 UI）。
  Future<void> _swallow(Future<void> Function() fn) async {
    try {
      await fn();
    } catch (_) {
      // Rust 引擎不可用时静默降级
    }
  }

  /// 律动模式（UI 四档：单色律动/七彩律动/强烈/柔和）→ Rust 引擎。
  Future<void> setRhythmMode(String mode) =>
      _swallow(() async => (await _ensureRhythm()).setMode(mode: _modeToFrb(mode)));

  /// 灵敏度 0..1（亮度 = 音量 × 灵敏度）。
  Future<void> setRhythmSensitivity(double v) =>
      _swallow(() async => (await _ensureRhythm()).setSensitivity(v: v));

  /// 单色律动的固定颜色（RGB 三字节）。
  Future<void> setRhythmBaseColor(int r, int g, int b) =>
      _swallow(() async => (await _ensureRhythm()).setBaseColor(rgb: [r, g, b]));

  /// 音量帧 → 律动灯效（Rust 引擎只读音量，亮度 = 音量 × 灵敏度）。
  Future<RhythmOutput> nextRhythm(AudioFrame frame) async {
    final r = await _ensureRhythm();
    final out = await r.next(volume: frame.volume);
    return RhythmOutput(rgb: out.rgb, brightness: out.brightness);
  }

  /// frb 帧 → 领域帧。
  static AudioFrame _toDomain(frb_audio.AudioFrame f) => AudioFrame(
        volume: f.volume,
        bands: f.bands,
        bass: f.bass,
        treble: f.treble,
        isBeat: f.isBeat,
      );

  static frb_effect.RhythmMode _modeToFrb(String m) => switch (m) {
        '七彩律动' => frb_effect.RhythmMode.rainbow,
        '强烈' => frb_effect.RhythmMode.strong,
        '柔和' => frb_effect.RhythmMode.soft,
        _ => frb_effect.RhythmMode.single,
      };

  /// 停止监听并释放采集器。
  Future<void> stop() async {
    await _sub?.cancel();
    _sub = null;
    await _controller?.close();
    _controller = null;
    try {
      await _recorder.stop();
    } catch (_) {
      // 未在采集时 stop 会抛错，忽略
    }
    // 停止监听 → 回收前台服务与唤醒锁（锁屏/后台保活结束）
    await _listenService.stop();
  }

  void dispose() {
    _sub?.cancel();
    _controller?.close();
  }
}
