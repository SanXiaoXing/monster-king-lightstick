import 'dart:async';
import 'dart:typed_data';

import 'package:record/record.dart';

import '../domain/audio_analysis.dart';

/// 音频数据访问边界：麦克风采集（record 插件）+ 分析（纯 Dart 域模型）。
///
/// UI 只依赖本 Repository，不直接触碰插件——与 DeviceRepository 同接缝；
/// Rust audio/ 就绪后换实现，UI 不动（分层铁律见 AGENT.md）。
class AudioRepository {
  final AudioRecorder _recorder = AudioRecorder();
  final AudioAnalyzer _analyzer = AudioAnalyzer();

  StreamController<AudioFrame>? _controller;
  StreamSubscription<Uint8List>? _sub;

  bool get isListening => _sub != null;

  /// 请求麦克风权限（Android 运行时弹窗；拒绝返回 false）。
  Future<bool> requestPermission() => _recorder.hasPermission(request: true);

  /// 开始监听麦克风，返回分析帧流（PCM16 单声道 44.1kHz）。
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
      final pcm = await _recorder.startStream(const RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: 44100,
        numChannels: 1,
        // 音乐采集必须关闭通话向处理：AGC 会让音量忽大忽小（ pumping ），
        // 噪声抑制/回声消除会把音乐误判为噪声导致失真、闷响、断音
        autoGain: false,
        echoCancel: false,
        noiseSuppress: false,
      ));
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
  }

  void dispose() {
    _sub?.cancel();
    _controller?.close();
  }
}
