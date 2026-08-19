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
  bool _autoScanned = false; // 本次会话只自动搜索一次
  StreamSubscription<List<Lightstick>>? _scanSub;
  StreamSubscription<BluetoothAdapterState>? _adapterSub;
  StreamSubscription<DeviceConnectionState>? _connSub;

  DeviceConnectionState get connection => _connection;
  List<Lightstick> get devices => _devices;
  Lightstick? get activeDevice => _activeDevice;
  bool get scanning => _scanning;
  String? get error => _error;

  /// 是否已连接设备（UI 统一用这个，不再暴露组合状态对象）。
  bool get isConnected => _connection == DeviceConnectionState.connected;

  /// 初始化：订阅适配器状态流，恢复已连接设备，首次进入自动搜索。
  Future<void> init() async {
    _adapterSub = _repository.adapterState.listen((s) {
      _adapter = s;
      notifyListeners();
      // 蓝牙开启后触发首次自动搜索（只一次）
      if (s == BluetoothAdapterState.on && !_autoScanned) {
        _autoScanned = true;
        scan();
      }
    }, onError: (Object e) {
      _error = '蓝牙状态读取失败: $e';
      notifyListeners();
    });

    try {
      final connected = await _repository.connectedDevices();
      if (connected.isNotEmpty) {
        _activeDevice = connected.first;
        _connection = DeviceConnectionState.connecting;
        notifyListeners();
        _subscribeConnection(connected.first);
        // 恢复已连接设备：重新走一遍连接并预热写特征，确认是可用会话，
        // 避免系统侧残留的"已连接"缓存显示已连接但写入实际不可用
        await _repository.connect(connected.first);
        if (_repository.isConnected(connected.first)) {
          _connection = DeviceConnectionState.connected;
        } else {
          _activeDevice = null;
          _connection = DeviceConnectionState.disconnected;
        }
        notifyListeners();
      }
    } catch (_) {
      // 无已连接设备/恢复失败属正常情况，忽略
    }

    // 适配器已开启则立即自动搜索；未开启等上面的流推送后触发
    if (_adapter == BluetoothAdapterState.on && !_autoScanned) {
      _autoScanned = true;
      scan();
    }
  }

  /// 开始扫描（自动停止旧扫描）。
  Future<void> scan() async {
    if (_scanning) return;
    _error = null;
    setScanning(true);
    final ready = await _ensureAdapterOn();
    if (!ready) {
      setScanning(false);
      return;
    }

    if (_repository.isScanning) await _repository.stopScan();
    _scanSub?.cancel();
    _scanSub = _repository.scanResults.listen((list) {
      _devices = list;
      notifyListeners();
    }, onError: (Object e) {
      _error = '扫描失败: $e';
      notifyListeners();
    });

    try {
      await _repository.startScan(timeout: const Duration(seconds: 5));
    } catch (e) {
      _error = '扫描失败: $e';
      notifyListeners();
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
    final ready = await _ensureAdapterOn();
    if (!ready) return;

    // 已连接同一台设备：防重复连接
    if (_activeDevice?.address == device.address &&
        _connection == DeviceConnectionState.connected) {
      return;
    }

    _activeDevice = device;
    _connection = DeviceConnectionState.connecting;
    notifyListeners();
    _subscribeConnection(device);

    try {
      await _repository.connect(device);
      // 平台缓存确认真实连接；若状态流未及时推送，手动补 connected，
      // 避免 UI 显示已连接但实际未连上
      if (!_repository.isConnected(device)) {
        throw StateError('设备连接未建立（无响应）');
      }
      if (_connection == DeviceConnectionState.connecting) {
        _connection = DeviceConnectionState.connected;
        notifyListeners();
      }
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

  /// 确保蓝牙适配器开启，并等待状态流确认 `on`（最长 8s）。
  ///
  /// 之前是「turnOn + 固定 300ms + 读旧字段」：`turnOn` 后 `_adapter` 由流
  /// 异步推送，旧字段滞后会导致首次点击被静默 return、需要再点一次。
  Future<bool> _ensureAdapterOn() async {
    if (_adapter == BluetoothAdapterState.on) return true;
    if (_adapter == BluetoothAdapterState.off ||
        _adapter == BluetoothAdapterState.turningOn) {
      try {
        await _repository.turnOn();
      } catch (e) {
        _error = '打开蓝牙失败: $e';
        notifyListeners();
        return false;
      }
    }
    final deadline = DateTime.now().add(const Duration(seconds: 8));
    while (_adapter != BluetoothAdapterState.on &&
        DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    if (_adapter != BluetoothAdapterState.on) {
      _error = '蓝牙未就绪（${_adapter.name}），请检查系统蓝牙';
      notifyListeners();
      return false;
    }
    return true;
  }

  void _subscribeConnection(Lightstick device) {
    _connSub?.cancel();
    // fbp 的 connectionState 流在每次订阅时先同步回放一次当前缓存值
    // （newStreamWithInitialValue，见 flutter_blue_plus utils.dart）：
    // 连接前回放 disconnected，会把我们刚设置的 _activeDevice 误清空 →
    // “第一次点击已连上但界面仍显示未连接，需要再点一次”。
    // 首个事件必为回放值，跳过；初始状态由 connect()/init() 显式管理，
    // 此后只处理真实状态变化（连接成功/断连/异常）。
    var skippedReplay = false;
    _connSub = _repository.connectionStateOf(device).listen((s) {
      if (!skippedReplay) {
        skippedReplay = true;
        return;
      }
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
    _adapterSub?.cancel();
    _connSub?.cancel();
    super.dispose();
  }
}
