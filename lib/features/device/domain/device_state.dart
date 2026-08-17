/// 蓝牙适配器状态。
///
/// 对应 flutter_blue_plus 的 `BluetoothAdapterState`，映射到领域层，
/// UI/Repository 不直接依赖插件类型（分层铁律见 AGENT.md）。
enum BluetoothAdapterState {
  /// 未知（iOS 首次访问的初始态）。
  unknown,

  /// 当前设备不支持蓝牙。
  unsupported,

  /// 缺少权限（Android 上会卡在此状态，需要用户授权）。
  unauthorized,

  /// 蓝牙已关闭。
  off,

  /// 正在打开。
  turningOn,

  /// 已开启，可扫描/连接。
  on,

  /// 正在关闭。
  turningOff,
}

/// 设备连接状态。
///
/// 对应 Kotlin/Rust 侧 `ConnectionState`：
/// disconnected / connecting / connected / disconnecting / error。
enum DeviceConnectionState {
  /// 未连接。
  disconnected,

  /// 连接中。
  connecting,

  /// 已连接。
  connected,

  /// 断开中。
  disconnecting,

  /// 连接出错。
  error,
}

/// 蓝牙适配器 + 连接状态的组合视图，供 UI 一次性展示。
class BluetoothStatus {
  const BluetoothStatus({
    required this.adapter,
    required this.connection,
    this.deviceName,
  });

  final BluetoothAdapterState adapter;
  final DeviceConnectionState connection;

  /// 已连接设备名（未连接时为 null）。
  final String? deviceName;

  bool get isConnected => connection == DeviceConnectionState.connected;
}
