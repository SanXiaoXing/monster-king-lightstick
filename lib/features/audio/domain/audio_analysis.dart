import 'dart:math' as math;
import 'dart:typed_data';

/// 一帧音频分析结果：音量级 + 频带能量 + 低频/高频 + 节拍，驱动律动 UI。
class AudioFrame {
  const AudioFrame({
    required this.volume,
    required this.bands,
    required this.bass,
    required this.treble,
    required this.isBeat,
  });

  /// 音量级 0..1（RMS 归一化）。
  final double volume;

  /// 频带能量 0..1（对数频带，长度 = [AudioAnalyzer.bandCount]）。
  final List<double> bands;

  /// 低频能量 0..1（约 40~230Hz，驱动圆环半径的慢速大位移）。
  final double bass;

  /// 高频能量 0..1（约 4kHz+，驱动细密快速振荡）。
  final double treble;

  /// 强拍标记：低频能量突增时置 true（触发径向脉冲与粒子爆发）。
  final bool isBeat;
}

/// 纯 Dart 音频分析器（无 IO，领域层）。
///
/// 输入 PCM16 小端字节流，环形缓冲 + 50% 重叠滑窗 + 汉宁窗 + radix-2 FFT，
/// 输出音量级与对数频带能量。对应 rust/src/audio 骨架的 Dart 侧落地；
/// Rust audio/ 就绪后可替换 Repository 实现，UI 不动。
///
/// 实时性设计：
/// - hop = windowSize/2（50% 重叠）：1024@44.1kHz 时帧周期 ≈ 11.6ms（~86fps），
///   相比无重叠的 23ms（~43fps）响应延迟减半；
/// - 汉宁窗 / FFT 位反转表 / 频带 bin 边界全部构造时预计算，帧内零三角函数；
/// - 环形缓冲避免 sublist/removeRange 的 O(n) 拷贝与逐字节 List 追加；
/// - 衰减类常数（峰值/基线）按帧周期折算，帧率翻倍后墙钟行为不变。
class AudioAnalyzer {
  AudioAnalyzer({
    this.bandCount = 28,
    this.windowSize = 1024,
    this.sampleRate = 44100,
  })  : hopSize = windowSize ~/ 2,
        _ring = Float64List(windowSize),
        _re = Float64List(windowSize),
        _im = Float64List(windowSize),
        _mag = Float64List(windowSize ~/ 2),
        _hann = _buildHann(windowSize),
        _bitRev = _buildBitRev(windowSize),
        _peakBands = List.filled(bandCount, 0),
        _bandLo = Int32List(bandCount),
        _bandHi = Int32List(bandCount) {
    // 预计算对数频带的 FFT bin 边界（40Hz ~ Nyquist）
    final half = windowSize ~/ 2;
    const fMin = 40.0;
    final fMax = sampleRate / 2;
    final ratio = fMax / fMin;
    for (var b = 0; b < bandCount; b++) {
      final fLo = fMin * math.pow(ratio, b / bandCount).toDouble();
      final fHi = fMin * math.pow(ratio, (b + 1) / bandCount).toDouble();
      _bandLo[b] = (fLo / sampleRate * windowSize).floor().clamp(1, half - 1);
      _bandHi[b] = (fHi / sampleRate * windowSize).ceil().clamp(1, half - 1);
    }
    // 衰减常数折算：原值按 23ms 帧周期标定，帧周期变为 hop 后取幂保持墙钟一致
    final frameRatio = hopSize / windowSize; // 0.5
    _peakDecayPerFrame = math.pow(_peakDecayRef, frameRatio).toDouble();
    _peakDecayFastPerFrame = math.pow(_peakDecayFastRef, frameRatio).toDouble();
    _baselineDecayPerFrame = math.pow(0.9, frameRatio).toDouble();
    // 强拍冷却约 180ms（快速鼓点也能跟上），按帧周期折算为帧数
    _beatCooldownFrames =
        (0.18 * sampleRate / hopSize).round().clamp(1, 1 << 30);
  }

  /// 频带数（与频谱柱数一致）。
  final int bandCount;

  /// FFT 窗口采样数（1024 @44.1kHz ≈ 23ms 窗长）。
  final int windowSize;

  /// 采样率（record 采集配置需一致）。
  final int sampleRate;

  /// 帧移（50% 重叠 → 帧周期 ≈ 11.6ms，响应延迟减半）。
  final int hopSize;

  /// 频带能量时域平滑系数（0..1，越大越跟手；帧率 ~86fps 下 0.5 ≈ 12ms 时间常数）。
  double smoothing = 0.5;

  // ── 采样缓冲：环形，避免每帧 sublist/removeRange 的 O(n) 拷贝 ──
  final Float64List _ring;
  int _write = 0; // 下一个写入位置（缓冲满时即最老样本位置）
  int _filled = 0; // 已填充样本数（≤ windowSize）
  int _sinceFrame = 0; // 距上一帧的样本数（满 hopSize 出一帧）

  // 跨 chunk 的奇数字节携带（PCM16 单样本 2 字节，chunk 长度可能为奇数）
  int? _pendingByte;

  // ── 预计算表 ──
  final Float64List _hann;
  final Int32List _bitRev;
  final Int32List _bandLo;
  final Int32List _bandHi;

  // ── FFT 工作缓冲（复用，帧内零分配）──
  final Float64List _re;
  final Float64List _im;
  final Float64List _mag;

  // ── 频带工作缓冲（复用；输出帧另分配新列表以免被下一帧覆写）──
  late final List<double> _rawBands = List<double>.filled(bandCount, 0);
  List<double>? _prevBands;

  // 节拍检测状态：低频能量基线（指数平滑）+ 冷却帧计数
  double _bassBaseline = 0;
  int _beatCooldown = 0;
  late final int _beatCooldownFrames;

  // 动态峰值（参考实现 strength/maxStrength：当前值 / 历史峰值，
  // 任意音量下都有完整动态范围，避免固定归一化导致的"要么 0 要么顶满"）
  final List<double> _peakBands;
  double _peakVolume = 0;

  /// 峰值衰减标定值（按 23ms 帧周期，实际每帧系数按帧周期折算）：
  /// - 慢速 0.992（约 1.9 秒减半）：电平接近峰值时用，音乐内部起伏
  ///   不被峰值吃掉、停止后柱体缓慢回落；
  /// - 快速 0.98（约 0.8 秒减半）：电平远低于峰值（<30%）时用——
  ///   响→静切换后安静段落在 1~2 秒内重新获得大部分动态范围，
  ///   不会一直被旧峰值压在低位不动。
  static const _peakDecayRef = 0.992;
  static const _peakDecayFastRef = 0.98;
  late final double _peakDecayPerFrame;
  late final double _peakDecayFastPerFrame;
  late final double _baselineDecayPerFrame;

  /// 绝对噪声门限（≈ -42dBFS）：RMS 低于此值判静音，输出全零帧。
  ///
  /// 动态峰值归一化会把环境底噪也放大成"有声音"，需要绝对电平兜底；
  /// 但门限过高会把小音量播放的音乐一并误杀（音乐还在放、画面却定格），
  /// 故取较低值，并在 [_noiseGate, _noiseGate×3] 区间做软过渡渐隐，
  /// 避免临界音量下全有/全无抖动。
  static const _noiseGate = 0.008;

  /// 喂入 PCM16 小端字节流；返回本次新产生的全部帧（可能多帧，可能为空）。
  ///
  /// 采集 chunk 长度不固定：50% 重叠下一块大 chunk 可能覆盖多个帧移，
  /// 逐帧全部返回，保证分析帧率稳定在 ~86fps，不被 chunk 大小稀释。
  List<AudioFrame> push(Uint8List pcm16) {
    final frames = <AudioFrame>[];
    final data = ByteData.sublistView(pcm16);
    var offset = 0;

    // 奇数字节携带：上一 chunk 遗留的首字节 + 本 chunk 首字节拼成一个样本
    if (_pendingByte != null && pcm16.isNotEmpty) {
      final v = (_pendingByte! | (pcm16[0] << 8)).toSigned(16).toDouble();
      _pendingByte = null;
      offset = 1;
      _pushSample(v, frames);
    }
    // 主体：ByteData 直接读 int16 LE（比逐字节移位拼接快，且少一次 bool 运算）
    for (; offset + 1 < pcm16.length; offset += 2) {
      _pushSample(data.getInt16(offset, Endian.little).toDouble(), frames);
    }
    if (offset < pcm16.length) {
      _pendingByte = pcm16[offset];
    }
    return frames;
  }

  void _pushSample(double v, List<AudioFrame> frames) {
    _ring[_write] = v;
    _write = (_write + 1) % windowSize;
    if (_filled < windowSize) _filled++;
    if (++_sinceFrame >= hopSize && _filled >= windowSize) {
      _sinceFrame = 0;
      frames.add(_analyze());
    }
  }

  /// 对当前窗口（最老→最新）做一帧完整分析。
  AudioFrame _analyze() {
    // 线性化环形缓冲 + 汉宁窗 + RMS，一趟完成（缓冲满时 _write 即最老样本）
    var sumSq = 0.0;
    for (var i = 0; i < windowSize; i++) {
      final s = _ring[(_write + i) % windowSize];
      sumSq += s * s;
      _re[i] = s * _hann[i];
      _im[i] = 0.0;
    }
    final rms = math.sqrt(sumSq / windowSize) / 32768.0;

    // 绝对噪声门限：环境底噪直接判静音，输出全零帧并衰减峰值，
    // 防止动态归一化把底噪放大成"有声音"
    if (rms < _noiseGate) {
      _peakVolume *= _peakDecayPerFrame;
      for (var b = 0; b < bandCount; b++) {
        _peakBands[b] *= _peakDecayPerFrame;
      }
      _bassBaseline *= _baselineDecayPerFrame;
      _prevBands = null;
      return AudioFrame(
        volume: 0,
        bands: List<double>.filled(bandCount, 0),
        bass: 0,
        treble: 0,
        isBeat: false,
      );
    }

    // 门限软过渡：[_noiseGate, _noiseGate×3] 内输出按 0→1 渐显，
    // 小音量音乐不被一刀切，临界电平也不会全有/全无闪烁
    final gateFade = ((rms - _noiseGate) / (_noiseGate * 2)).clamp(0.0, 1.0);

    _fft(_re, _im, windowSize);

    // 幅度谱（取前 N/2 个 bin）
    final half = windowSize ~/ 2;
    for (var i = 0; i < half; i++) {
      _mag[i] = math.sqrt(_re[i] * _re[i] + _im[i] * _im[i]);
    }

    // 对数频带聚合（边界已预计算）—— 保留原始平均幅度，不做固定缩放
    for (var b = 0; b < bandCount; b++) {
      final lo = _bandLo[b];
      final hi = _bandHi[b];
      var sum = 0.0;
      for (var k = lo; k < hi; k++) {
        sum += _mag[k];
      }
      _rawBands[b] = sum / math.max(1, hi - lo);
    }

    // 动态峰值归一化（参考实现 strength/maxStrength：当前值 / 历史峰值）。
    // 峰值上升即时跟随、下降指数衰减，任意音量下都有完整动态范围，
    // 避免固定归一化导致的"安静时几乎不动、响亮时顶满"。
    final bands = List<double>.filled(bandCount, 0);
    for (var b = 0; b < bandCount; b++) {
      final raw = _rawBands[b];
      final p = _peakBands[b];
      // 电平远低于峰值时快速释放，安静段落尽快恢复动态范围
      final decay =
          raw < p * 0.3 ? _peakDecayFastPerFrame : _peakDecayPerFrame;
      final peak = raw > p ? raw : p * decay;
      _peakBands[b] = peak;
      bands[b] = (raw / math.max(peak, 1e-9)).clamp(0.0, 1.0);
    }

    // 音量同样按动态峰值归一化（同样的双速释放）
    _peakVolume = rms > _peakVolume
        ? rms
        : _peakVolume *
            (rms < _peakVolume * 0.3
                ? _peakDecayFastPerFrame
                : _peakDecayPerFrame);
    var volume = (rms / math.max(_peakVolume, 1e-9)).clamp(0.0, 1.0);

    // 门限软过渡作用于归一化结果：近门限的低电平信号（含底噪）不会被
    // 峰值归一化放大成"满格信号"，音量越接近门限输出越收敛
    if (gateFade < 1.0) {
      volume *= gateFade;
      for (var b = 0; b < bandCount; b++) {
        bands[b] *= gateFade;
      }
    }

    // 与上一帧平滑，避免柱子跳动
    final prev = _prevBands;
    if (prev != null) {
      for (var b = 0; b < bandCount; b++) {
        bands[b] = prev[b] * (1 - smoothing) + bands[b] * smoothing;
      }
    }
    _prevBands = bands;

    // 低频能量：前 8 个频带（约 40~243Hz，对数频带边界）
    final bass = _mean(bands, 0, 8);
    // 高频能量：后 8 个频带（约 4kHz~22kHz）
    final treble = _mean(bands, bandCount - 8, bandCount);

    // 强拍检测：用原始（未归一化）低频突增，避免归一化后基线失真
    final rawBass = _mean(_rawBands, 0, 8);
    _bassBaseline = _bassBaseline == 0
        ? rawBass
        : _bassBaseline * _baselineDecayPerFrame +
            rawBass * (1 - _baselineDecayPerFrame);
    final isBeat =
        _beatCooldown <= 0 && rawBass > _bassBaseline * 1.4 + 0.02;
    if (isBeat) {
      // 触发后重置基线，避免连续触发；冷却约 180ms
      _bassBaseline = rawBass;
      _beatCooldown = _beatCooldownFrames;
    } else if (_beatCooldown > 0) {
      _beatCooldown--;
    }

    return AudioFrame(
      volume: volume,
      bands: bands,
      bass: bass,
      treble: treble,
      isBeat: isBeat,
    );
  }

  /// 频带均值（[from, to)）。
  double _mean(List<double> v, int from, int to) {
    var s = 0.0;
    for (var i = from; i < to; i++) {
      s += v[i];
    }
    return s / math.max(1, to - from);
  }

  static Float64List _buildHann(int n) {
    final w = Float64List(n);
    for (var i = 0; i < n; i++) {
      w[i] = 0.5 - 0.5 * math.cos(2 * math.pi * i / (n - 1));
    }
    return w;
  }

  static Int32List _buildBitRev(int n) {
    final table = Int32List(n);
    for (var i = 1, j = 0; i < n; i++) {
      var bit = n >> 1;
      for (; j & bit != 0; bit >>= 1) {
        j ^= bit;
      }
      j ^= bit;
      table[i] = j;
    }
    return table;
  }

  /// 迭代 radix-2 FFT（原地，n 须为 2 的幂；位反转查表，免每帧重排计算）。
  void _fft(Float64List re, Float64List im, int n) {
    for (var i = 1; i < n; i++) {
      final j = _bitRev[i];
      if (i < j) {
        final tr = re[i]; re[i] = re[j]; re[j] = tr;
        final ti = im[i]; im[i] = im[j]; im[j] = ti;
      }
    }
    for (var len = 2; len <= n; len <<= 1) {
      final ang = -2 * math.pi / len;
      final wRe = math.cos(ang);
      final wIm = math.sin(ang);
      final halfLen = len >> 1;
      for (var i = 0; i < n; i += len) {
        var curRe = 1.0, curIm = 0.0;
        for (var k = 0; k < halfLen; k++) {
          final uRe = re[i + k], uIm = im[i + k];
          final vRe = re[i + k + halfLen] * curRe - im[i + k + halfLen] * curIm;
          final vIm = re[i + k + halfLen] * curIm + im[i + k + halfLen] * curRe;
          re[i + k] = uRe + vRe; im[i + k] = uIm + vIm;
          re[i + k + halfLen] = uRe - vRe; im[i + k + halfLen] = uIm - vIm;
          final nRe = curRe * wRe - curIm * wIm;
          curIm = curRe * wIm + curIm * wRe;
          curRe = nRe;
        }
      }
    }
  }
}
