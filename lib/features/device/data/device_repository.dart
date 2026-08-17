/// device feature 数据访问边界。
///
/// UI 只依赖 Repository，不直接调 Rust API —— 未来把 Rust BLE 换成
/// Android Native BLE 或 Mock 时 UI 不动（分层铁律见 AGENT.md）。
class DeviceRepository {
  // 待 rust/src/api/bluetooth.rs 就绪后接入：
  // Future<List<Lightstick>> scan();
  // Future<void> connect(String address);
  // Future<void> disconnect();
}
