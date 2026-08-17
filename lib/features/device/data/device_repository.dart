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
  /// 返回后连接建立（连接过程状态经 [connectionStateOf] 推送）。
  Future<void> connect(Lightstick device) async {
    final d = fbp.BluetoothDevice.fromId(device.address);
    // 个人/教育用途按 nonprofit 许可；商业使用需 License.commercial
    await d.connect(
      license: fbp.License.nonprofit,
      timeout: const Duration(seconds: 15),
    );
  }

  /// 断开指定设备。
  Future<void> disconnect(Lightstick device) async {
    await fbp.BluetoothDevice.fromId(device.address).disconnect();
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
