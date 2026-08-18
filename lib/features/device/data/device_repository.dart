import 'dart:async';

import 'package:flutter_blue_plus/flutter_blue_plus.dart' as fbp;

import '../domain/device_state.dart';
import '../domain/lightstick.dart';

/// device feature 数据访问边界。
///
/// UI 只依赖 Repository（领域类型），不直接调插件/Rust API —— 未来把
/// flutter_blue_plus 换成 Rust BLE 或 Mock 时 UI 不动（分层铁律见 AGENT.md）。
///
/// `ponytail:` BLE 现以 flutter_blue_plus 原生实现落地于 Repository 层，
/// 对应 AGENT.md "换掉 Rust BLE 为 Native/Mock 时 UI 不动" 的既定接缝；
/// Rust 侧 rust/src/bluetooth 骨架保留，就绪后可无缝替换。
class DeviceRepository {
  /// 宝宝剑 BLE 主服务 UUID（见 docs/protocol/PROTOCOL.md，Kotlin 参考实现 FFE0）。
  static final _serviceUuid = fbp.Guid('ffe0');

  /// 灯光命令写特征（writeNoResponse，见 PROTOCOL.md / Kotlin 参考实现 FFE1）。
  static final _writeCharUuid = fbp.Guid('ffe1');

  /// 写特征缓存（address → FFE1 特征）。
  ///
  /// discoverServices 是一次完整 GATT 往返（数十~上百毫秒），律动期间每次
  /// 写入前都发现服务会让灯光响应严重滞后。连接后预热一次并缓存，写入
  /// 直接命中；写失败/断开时剔除，下次写入自动重新发现。
  final Map<String, fbp.BluetoothCharacteristic> _writeChars = {};

  /// 蓝牙适配器状态流（映射到领域枚举）。
  Stream<BluetoothAdapterState> get adapterState =>
      fbp.FlutterBluePlus.adapterState.map(_mapAdapterState);

  /// 蓝牙适配器当前状态。
  BluetoothAdapterState get adapterStateNow =>
      _mapAdapterState(fbp.FlutterBluePlus.adapterStateNow);

  /// 设备是否支持蓝牙。
  Future<bool> get isSupported => fbp.FlutterBluePlus.isSupported;

  /// 打开蓝牙（Android 弹系统确认；iOS 不支持，需引导用户手动开启）。
  ///
  /// 权限（BLUETOOTH_SCAN/CONNECT 等）由插件在 startScan/turnOn 时自动申请。
  Future<void> turnOn() => fbp.FlutterBluePlus.turnOn();

  /// 扫描结果流：每有新结果推一帧全量列表（去重后）。
  Stream<List<Lightstick>> get scanResults =>
      fbp.FlutterBluePlus.scanResults.map((results) => _dedupe(results));

  /// 开始扫描宝宝剑（按 FFE0 服务过滤），timeout 后自动停止。
  Future<void> startScan({Duration timeout = const Duration(seconds: 5)}) {
    return fbp.FlutterBluePlus.startScan(
      withServices: [_serviceUuid],
      timeout: timeout,
    );
  }

  /// 停止扫描。
  Future<void> stopScan() => fbp.FlutterBluePlus.stopScan();

  /// 是否正在扫描。
  bool get isScanning => fbp.FlutterBluePlus.isScanningNow;

  /// 连接指定设备。
  ///
  /// 返回后连接建立（连接过程状态经 [connectionStateOf] 推送），并预热
  /// 写特征缓存，首次写入无需再 discoverServices。
  Future<void> connect(Lightstick device) async {
    final d = fbp.BluetoothDevice.fromId(device.address);
    // 个人/教育用途按 nonprofit 许可；商业使用需 License.commercial
    await d.connect(
      license: fbp.License.nonprofit,
      timeout: const Duration(seconds: 15),
    );
    try {
      _writeChars[device.address] = await _discoverWriteChar(d);
    } catch (_) {
      // 预热失败不阻塞连接：首次写入时会重新发现并缓存
      _writeChars.remove(device.address);
    }
  }

  /// 断开指定设备。
  Future<void> disconnect(Lightstick device) async {
    _writeChars.remove(device.address);
    await fbp.BluetoothDevice.fromId(device.address).disconnect();
  }

  /// 平台层当前是否已连接（fbp Dart 侧缓存，connect 成功后置 true）。
  ///
  /// 供 ViewModel 在 connect 后确认"已连接"是真实会话，而非状态残留。
  bool isConnected(Lightstick device) =>
      fbp.BluetoothDevice.fromId(device.address).isConnected;

  /// 向设备写入原始命令字节（灯光/座位等，经 FFE1 writeNoResponse）。
  ///
  /// 命中缓存直接写入（单次 BLE 事务，毫秒级）；未命中（如系统侧已连接、
  /// 缓存被剔除）先 discoverServices 再缓存。写失败剔除缓存并上抛，
  /// 由上层转成用户可读错误。
  Future<void> writeCommand(Lightstick device, List<int> bytes) async {
    final d = fbp.BluetoothDevice.fromId(device.address);
    var characteristic = _writeChars[device.address];
    characteristic ??= _writeChars[device.address] =
        await _discoverWriteChar(d);
    try {
      await characteristic.write(bytes, withoutResponse: true);
    } catch (_) {
      // 特征可能在断连/重连后失效：剔除，下次写入重新发现
      _writeChars.remove(device.address);
      rethrow;
    }
  }

  /// 发现 FFE0/FFE1 写特征（一次 GATT 往返，结果应缓存复用）。
  Future<fbp.BluetoothCharacteristic> _discoverWriteChar(
    fbp.BluetoothDevice d,
  ) async {
    final services = await d.discoverServices();
    final service = services.firstWhere(
      (s) => s.uuid.str.toLowerCase() == _serviceUuid.str.toLowerCase(),
      orElse: () => throw StateError('设备未提供 FFE0 服务'),
    );
    return service.characteristics.firstWhere(
      (c) => c.uuid.str.toLowerCase() == _writeCharUuid.str.toLowerCase(),
      orElse: () => throw StateError('设备未提供 FFE1 写特征'),
    );
  }

  /// 指定设备的连接状态流。
  Stream<DeviceConnectionState> connectionStateOf(Lightstick device) =>
      fbp.BluetoothDevice.fromId(device.address)
          .connectionState
          .map(_mapConnectionState);

  /// 已连接设备列表（供 ViewModel 初始化时恢复状态）。
  Future<List<Lightstick>> connectedDevices() async {
    final devices = fbp.FlutterBluePlus.connectedDevices;
    return devices.map((d) => _fromDevice(d)).toList();
  }

  /// 扫描结果去重（同地址保留最新，覆盖 name/rssi）。
  List<Lightstick> _dedupe(List<fbp.ScanResult> results) {
    final map = <String, Lightstick>{};
    for (final r in results) {
      map[r.device.remoteId.str] = _fromScanResult(r);
    }
    return map.values.toList();
  }

  Lightstick _fromScanResult(fbp.ScanResult r) => Lightstick(
        address: r.device.remoteId.str,
        name: _deviceName(r.device),
        rssi: r.rssi,
      );

  Lightstick _fromDevice(fbp.BluetoothDevice d) => Lightstick(
        address: d.remoteId.str,
        name: _deviceName(d),
      );

  String? _deviceName(fbp.BluetoothDevice d) {
    final n = d.platformName.trim();
    return n.isEmpty ? null : n;
  }
}

BluetoothAdapterState _mapAdapterState(fbp.BluetoothAdapterState s) =>
    switch (s) {
      fbp.BluetoothAdapterState.unknown => BluetoothAdapterState.unknown,
      fbp.BluetoothAdapterState.unavailable => BluetoothAdapterState.unsupported,
      fbp.BluetoothAdapterState.unauthorized => BluetoothAdapterState.unauthorized,
      fbp.BluetoothAdapterState.turningOn => BluetoothAdapterState.turningOn,
      fbp.BluetoothAdapterState.on => BluetoothAdapterState.on,
      fbp.BluetoothAdapterState.turningOff => BluetoothAdapterState.turningOff,
      fbp.BluetoothAdapterState.off => BluetoothAdapterState.off,
    };

DeviceConnectionState _mapConnectionState(fbp.BluetoothConnectionState s) =>
    switch (s) {
      // 插件仅区分 未连接/已连接；中间态由 ViewModel 在发起操作时设置
      fbp.BluetoothConnectionState.disconnected => DeviceConnectionState.disconnected,
      fbp.BluetoothConnectionState.connected => DeviceConnectionState.connected,
    };
