//! OTA 固件升级命令构造。
//!
//! 对应 `appservice.app.js:855`（ota-manager.js）与 `chunk_65.appservice.js:89`（devicesota 页）。

/// OTA 模式切换命令：4 字节 `0x55555555`，写入特征值 `AC1F3D08`。
pub fn build_ota_mode_switch() -> [u8; 4] {
    [0x55, 0x55, 0x55, 0x55]
}

/// OTA 重启命令：4 字节 `0xCCCCCCCC`，写入特征值 `AC1F3D13`。
pub fn build_ota_reboot() -> [u8; 4] {
    [0xCC, 0xCC, 0xCC, 0xCC]
}

/// OTA 固件分包：`偏移量(4B LE) + 固件块`，写入特征值 `AC1F3D12`。
///
/// blockSize：iOS 固定 256；Android 系统主版本 ≥14 用 128，否则 256。
/// writeType 优先 `write`，errCode 10008/10007 降级 `writeNoResponse`（由 BLE 层处理）。
pub fn build_ota_firmware_packet(offset: u32, chunk: &[u8]) -> Vec<u8> {
    let mut out = Vec::with_capacity(4 + chunk.len());
    out.extend_from_slice(&offset.to_le_bytes());
    out.extend_from_slice(chunk);
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn mode_switch_is_55555555() {
        assert_eq!(build_ota_mode_switch(), [0x55, 0x55, 0x55, 0x55]);
    }

    #[test]
    fn reboot_is_cccccccc() {
        assert_eq!(build_ota_reboot(), [0xCC, 0xCC, 0xCC, 0xCC]);
    }

    #[test]
    fn firmware_packet_offset_le_plus_chunk() {
        let chunk = [0xAA, 0xBB, 0xCC];
        let pkt = build_ota_firmware_packet(0x01020304, &chunk);
        assert_eq!(pkt, vec![0x04, 0x03, 0x02, 0x01, 0xAA, 0xBB, 0xCC]);
    }

    #[test]
    fn firmware_packet_offset_zero() {
        let pkt = build_ota_firmware_packet(0, &[0xFF; 8]);
        assert_eq!(pkt[0..4], [0, 0, 0, 0]);
        assert_eq!(pkt.len(), 12);
    }
}
