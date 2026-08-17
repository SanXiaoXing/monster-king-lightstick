# WanShou — 万兽之王光剑/演出腕带控制 App

从微信小程序反编译代码精确移植的腕带蓝牙协议栈 + Flutter 控制端。
协议层与原小程序**字节级对齐**，61 个单元测试验证通过。

## 仓库结构

仓库根目录即 Flutter 工程根（`pubspec.yaml` 与 `lib/` 在根，平铺），
周边目录共存于同一仓库。

| 目录 | 说明 | 状态 |
|---|---|---|
| `lib/` | Flutter 应用（UI / feature 分层） | 骨架 + 协议验证页 |
| `rust/` | flutter_rust_bridge 桥接 crate（api / bluetooth / lightstick / audio / protocol 门面） | api 已实现，其余骨架 |
| `wan_protocol/` | 协议实现 crate（封包 / CRC32 / AES / Ed25519 / 广播 / OTA） | **已验证（61 tests）** |
| `glowstick-app-main/` | Kotlin 参考实现（只读，BLE 真机时序来源） | 冻结 |
| `docs/` | protocol / architecture / reverse-engineering | 持续更新 |
| `scripts/` | 构建/辅助脚本 | 空 |

> 分层规则、边界铁律、代码归属决策表见 **[AGENT.md](AGENT.md)**。

## 分层架构

```
Flutter (lib/)                 "人怎么操作"
   features/*/{presentation,domain,data}
   core / shared
        ↓ flutter_rust_bridge
Rust api/ (rust/src/api)        Flutter ↔ Rust 唯一边界
        ↓
Rust 领域层                     "设备怎么工作"
   lightstick/  ← bluetooth/（BLE 通信）
                ← protocol/ → wan_protocol（协议实现）
   audio/                       （律动分析）
```

## 快速开始

```powershell
# 协议层测试（61 个）
cargo test --manifest-path wan_protocol/Cargo.toml

# 桥接层编译检查
cargo check --manifest-path rust/Cargo.toml

# 运行 Flutter 端（Windows 需开发者模式：start ms-settings:developers）
# 在仓库根执行
flutter run
```

## 协议速览

- 命令包：`[帧序号 4B LE][命令体 N B][CRC32 4B LE]`（IEEE 802.3）
- 控制通道：服务 `FFE0` / 写 `FFE1`（NoResponse）/ Notify `FFE2`
- 9 种灯效、座位绑定、Ed25519 防伪、双平台广播烧录、OTA 分包
- 金标准：`LIGHT_FLASH_HEX = 02000000100004ff020c06104c6a5e52`（真机抓包）

完整规格：[docs/protocol/PROTOCOL.md](docs/protocol/PROTOCOL.md)
