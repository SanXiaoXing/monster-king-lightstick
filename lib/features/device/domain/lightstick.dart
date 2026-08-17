/// 荧光棒/腕带领域模型（待实现）。
///
/// 属性规划：地址、名称、型号、固件版本、MAC、连接状态、能力集
/// （对应 Rust 侧 lightstick/device.rs）。
class Lightstick {
  const Lightstick({required this.address, this.name});

  final String address;
  final String? name;
}
