/// 荧光棒/宝宝剑领域模型。
///
/// 属性：地址、名称、RSSI、连接状态（对应 Rust 侧 lightstick/device.rs）。
/// 扫描时由 DeviceRepository 构造，UI 只读。
class Lightstick {
  const Lightstick({
    required this.address,
    this.name,
    this.rssi,
  });

  /// 设备地址（Android 为 MAC，iOS 为系统分配的 UUID）。
  final String address;

  /// 广播名称，可能为空。
  final String? name;

  /// 信号强度 dBm，可能为空。
  final int? rssi;
}
