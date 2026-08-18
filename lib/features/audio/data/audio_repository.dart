import 'dart:async';
import 'dart:io' show Platform;
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:record/record.dart';

import '../domain/audio_analysis.dart';
import 'native_audio_capture.dart';

/// 音频数据访问边界：麦克风采集 + 分析（纯 Dart 域模型）。
///
/// 采集路径按平台分流，对外 API 不变（UI 零改动）：
/// - **Android**：原生 ForegroundService + AudioRecord（[NativeAudioCapture]）。
///   锁屏/退后台后采集不中断，音乐律动持续驱动荧光棒；
/// - **其他平台**（iOS/桌面）：`record` 插件兜底，前台采集。
///
/// UI 只依赖本 Repository，不直接触碰插件/通道——与 DeviceRepository 同接缝；
/// Rust audio/ 就绪后换分析实现，UI 不动（分层铁律见 AGENT.md）。
class AudioRepository {
  final AudioRecorder _recorder = AudioRecorder();
  final NativeAudioCapture _native = NativeAudioCapture();
  final AudioAnalyzer _analyzer = AudioAnalyzer();

  StreamController<AudioFrame>? _controller;
  StreamSubscription<Uint8List>? _sub;

  /// 是否走 Android 原生前台服务采集路径。
  static bool get _useNative => !kIsWeb && Platform.isAndroid;

  bool get isListening => _sub != null;

  /// 请求麦克风权限（Android 运行时弹窗；拒绝返回 false）。
  Future<bool> requestPermission() => _useNative
      ? _native.requestPermission()
      : _recorder.hasPermission(request: true);

  /// 开始监听麦克风，返回分析帧流（PCM16 单声道 44.1kHz）。
  ///
  /// 权限被拒时抛出 [StateError]；调用方可先 [requestPermission] 预检。
  Future<Stream<AudioFrame>> start() async {
    if (_sub != null) return _controller!.stream;

    final granted = _useNative
        ? await _native.requestPermission()
        : await _recorder.hasPermission(request: true);
    if (!granted) {
      throw StateError('麦克风权限被拒绝，无法采集音乐');
    }

    final controller = StreamController<AudioFrame>();
    _controller = controller;

    try {
      final pcm = _useNative ? await _startNative() : await _startPlugin();
      _sub = pcm.listen(
        (bytes) {
          final frames = _analyzer.push(bytes);
          if (frames.isNotEmpty && !controller.isClosed) {
            for (final f in frames) {
              controller.add(f);
            }
          }
        },
        onError: (Object e) {
          _sub = null; // 流已死，允许下次 start() 重建会话
          if (!controller.isClosed) controller.addError(e);
        },
        onDone: () {
          _sub = null;
          if (!controller.isClosed) controller.close();
        },
      );
    } catch (e) {
      await controller.close();
      _controller = null;
      rethrow;
    }
    return controller.stream;
  }

  /// Android：启动前台服务采集，返回 PCM 流。
  ///
  /// 先 start 服务再 listen：服务启动前不存在监听者，启动即刻的少量
  /// 丢帧无影响（首个完整分析窗需攒满 1024 样本，约 23ms）。
  Future<Stream<Uint8List>> _startNative() async {
    await _native.start();
    return _native.pcmStream();
  }

  /// 其他平台：record 插件采集。
  Future<Stream<Uint8List>> _startPlugin() async {
    return _recorder.startStream(const RecordConfig(
      encoder: AudioEncoder.pcm16bits,
      sampleRate: 44100,
      numChannels: 1,
      // 音乐采集必须关闭通话向处理：AGC 会让音量忽大忽小（ pumping ），
      // 噪声抑制/回声消除会把音乐误判为噪声导致失真、闷响、断音
      autoGain: false,
      echoCancel: false,
      noiseSuppress: false,
    ));
  }

  /// 停止监听并释放采集器。
  Future<void> stop() async {
    await _sub?.cancel();
    _sub = null;
    await _controller?.close();
    _controller = null;
    if (_useNative) {
      await _native.stop();
    } else {
      try {
        await _recorder.stop();
      } catch (_) {
        // 未在采集时 stop 会抛错，忽略
      }
    }
  }

  void dispose() {
    _sub?.cancel();
    _controller?.close();
  }
}
