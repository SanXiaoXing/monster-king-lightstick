import 'dart:async';

import 'package:flutter/foundation.dart';

import '../data/device_repository.dart';
import '../domain/device_state.dart';
import '../domain/lightstick.dart';

/// 设备视图模型：持有蓝牙状态/扫描结果/连接状态，调 DeviceRepository，
/// notifyListeners 驱动页面重建。页面不放业务逻辑（分层铁律见 AGENT.md）。
class DeviceViewModel extends ChangeNotifier {
  DeviceViewModel(this._repository);

  final DeviceRepository _repository;

  BluetoothAdapterState _adapter = BluetoothAdapterState.unknown;
  DeviceConnectionState _connection = DeviceConnectionState.disconnected;
  List<Lightstick> _devices = const [];
  Lightstick? _activeDevice;
  bool _scanning = false;
  String? _error;
  StreamSubscription<List<Lightstick>>? _scanSub;

  BluetoothAdapterState get adapter => _adapter;
  DeviceConnectionState get connection => _connection;
  List<Lightstick> get devices => _devices;
  Lightstick? get activeDevice => _activeDevice;
  bool get scanning => _scanning;
  String? get error => _error;

  /// 组合状态（供 UI 一次性展示）。
  BluetoothStatus get status => BluetoothStatus(
        adapter: _adapter,
        connection: _connection,
        deviceName: _activeDevice?.name ?? _activeDevice?.address,
      );

  /// 初始化：订阅适配器状态流，恢复已连接设备。
  Future<void> init() async {
    _repository.adapterState.listen((s) {
      _adapter = s;
      notifyListeners();
    }, onError: (Object e) {
      _error = '蓝牙状态读取失败: $e';
      notifyListeners();
    });

    try {
      final connected = await _repository.connectedDevices();
      if (connected.isNotEmpty) {
        _activeDevice = connected.first;
        _connection = DeviceConnectionState.connected;
        _subscribeConnection(connected.first);
      }
    } catch (_) {
      // 无已连接设备属正常情况，忽略
    }
    notifyListeners();
  }

  /// 开始扫描（自动停止旧扫描）。扫描前确保蓝牙已开、权限已申请。
  Future<void> scan() async {
    _error = null;
    await _ensureBluetoothReady();
    if (_adapter != BluetoothAdapterState.on) return;

    if (_repository.isScanning) await _repository.stopScan();
    _scanSub?.cancel();
    _scanSub = _repository.scanResults.listen((list) {
      _devices = list;
      notifyListeners();
    }, onError: (Object e) {
      _error = '扫描失败: $e';
      notifyListeners();
    });

    setScanning(true);
    try {
      await _repository.startScan(timeout: const Duration(seconds: 5));
    } finally {
      setScanning(false);
    }
  }

  /// 停止扫描。
  Future<void> stopScan() async {
    _scanSub?.cancel();
    _scanSub = null;
    await _repository.stopScan();
    setScanning(false);
  }

  /// 连接指定设备。
  Future<void> connect(Lightstick device) async {
    _error = null;
    await _ensureBluetoothReady();
    if (_adapter != BluetoothAdapterState.on) return;

    _activeDevice = device;
    _connection = DeviceConnectionState.connecting;
    notifyListeners();
    _subscribeConnection(device);

    try {
      await _repository.connect(device);
      // 连接状态由流推送，此处无需额外赋值
    } catch (e) {
      _connection = DeviceConnectionState.error;
      _error = '连接失败: $e';
      notifyListeners();
    }
  }

  /// 断开当前设备。
  Future<void> disconnect() async {
    final device = _activeDevice;
    if (device == null) return;
    _connection = DeviceConnectionState.disconnecting;
    notifyListeners();
    try {
      await _repository.disconnect(device);
    } catch (e) {
      _error = '断开失败: $e';
      notifyListeners();
    }
  }

  /// 确保蓝牙已开启：关闭则尝试打开（权限由插件在扫描/连接时自动申请）。
  Future<void> _ensureBluetoothReady() async {
    if (_adapter == BluetoothAdapterState.off) {
      try {
        await _repository.turnOn();
      } catch (e) {
        _error = '打开蓝牙失败: $e';
        notifyListeners();
      }
    }
    // adapterState 流会推送最新状态
    await Future<void>.delayed(const Duration(milliseconds: 300));
  }

  void _subscribeConnection(Lightstick device) {
    _repository.connectionStateOf(device).listen((s) {
      _connection = s;
      if (s == DeviceConnectionState.disconnected ||
          s == DeviceConnectionState.error) {
        _activeDevice = null;
      }
      notifyListeners();
    }, onError: (Object e) {
      _error = '连接状态读取失败: $e';
      notifyListeners();
    });
  }

  void setScanning(bool value) {
    _scanning = value;
    notifyListeners();
  }

  @override
  void dispose() {
    _scanSub?.cancel();
    super.dispose();
  }
}
