# LightStick — 万兽之王宝宝剑 控制

**一款通过蓝牙（BLE）控制"万兽之王"系列演出宝宝剑安卓 App。**
由于官方基于小程序开发，导致音乐同步可玩性大大降低，甚至不能很优雅的控制，于是逆向了官方的小程序，用来控制宝宝剑来完善自己需求。

>[!Warning]
> **为什么没有 iOS 版本：** 本框架是支持 iOS 的，由于本人工作原因不能使用苹果产品（虽然电脑是 Mac，但是也只是个人开发，不能在公司内使用），没有 iPhone 进行测试，以及上架APP Store 花销偏高，索性放弃，可自行 clone 源码进行编译安装。

## 软件是干什么的？

演唱会、演出、应援场合使用的"万兽之王"发光棒，由手机 App 通过低功耗蓝牙（BLE）直接控制：

- **随身控制台**：手机即遥控器，连接后即可调光换色、切换灯效、调节亮度，实时生效
- **音乐同步**：播放音乐时打开麦克风监听，应援棒颜色与亮度跟随节拍自动律动，无需手动编排
- **现场联动**：支持座位绑定（现场灯光系统按座位精准点亮）、防伪验证（Ed25519 签名校验真伪）、OTA 固件升级

## 解决了什么问题？

| 痛点 | 本项目的解法 |
|---|---|
| 官方控制端只有微信小程序：启动慢、依赖微信、后台易被回收，律动体验差 | 原生 Flutter App，独立运行、冷启动快、支持浅/深双主题 |
| 应援棒律动多为固定模式或手动开关，与音乐脱节 | 麦克风实时采集 + 纯 Dart FFT 频谱分析（50% 重叠滑窗，约 86fps），颜色/亮度/强拍脉冲实时跟随音乐 |
| 想用官方"现场联动/防伪/固件升级"但门槛高、不透明 | 协议层从官方小程序**反编译精确移植，字节级对齐**（61 个单元测试 + 真机抓包金标准），兼容官方服务端生态 |
| BLE 写入频繁导致灯效滞后、链路拥塞 | 写特征缓存（免重复 discoverServices）+ 60ms 节流 + 在途丢帧，响应跟手且无线稳定 |

## 核心功能

- **设备连接**：BLE 扫描（按 FFE0 服务过滤）、连接/断开、状态卡片
- **调色盘**：圆形 RGB 色环 + hex 输入 + 亮度滑杆 + 9 灯效 3×3，颜色/灯效实时下发（防抖）
- **音乐律动**：麦克风采集 → FFT 分析（28 对数频带 / 强拍检测）→ 圆形可视化 + 荧光棒联动（主导频带→色相、音量→亮度、强拍脉冲，60ms 节流）
- **座位绑定**：写座位 / 解绑
- **协议验证页**：Rust 协议 API 的 UI 入口（设置页）
- **设置**：双主题（浅色/深色/跟随系统）、灯效入口、协议验证、清除设备

## 仓库结构

仓库根目录即 Flutter 工程根（`pubspec.yaml` 与 `lib/` 在根，平铺），
周边目录共存于同一仓库。

| 目录 | 说明 | 状态 |
|---|---|---|
| `lib/` | Flutter 应用（feature 分层） | 已实现：Dock 主页 / 设备 / 调色 / 音乐律动 / 设置 |
| `rust/` | flutter_rust_bridge 桥接 crate（api / bluetooth / lightstick / audio / protocol） | `api/protocol` 已实现（24 个协议构造函数），其余骨架 |
| `wan_protocol/` | 协议实现 crate（封包 / CRC32 / AES / Ed25519 / 广播 / OTA） | **已验证（61 tests）** |
| `rust_builder/` | FRB 运行时壳 + cargokit 构建（生成代码禁改） | 生成物 |
| `docs/` | protocol / design（UI 原型、布局规则） | 持续更新 |
| `test/` | Flutter 测试（behavior / widget） | 随功能更新 |
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

> 现状：BLE 以 flutter_blue_plus 落地于 `device/data/device_repository.dart`、
> 音频分析以纯 Dart 落地于 `audio/domain/audio_analysis.dart`（见 AGENT.md 铁律 4）。
> Rust 侧骨架就绪后替换 Repository 实现即可，**UI 零改动**。

## 快速开始

```bash
# 协议层测试（61 个）
cargo test --manifest-path wan_protocol/Cargo.toml

# 桥接层编译检查
cargo check --manifest-path rust/Cargo.toml

# Flutter 静态分析与测试（仓库根执行）
flutter analyze
flutter test

# 运行（Windows 需开发者模式：start ms-settings:developers）
flutter run
```

## 协议速览

- 命令包：`[帧序号 4B LE][命令体 N B][CRC32 4B LE]`（IEEE 802.3）
- 控制通道：服务 `FFE0` / 写 `FFE1`（NoResponse）/ Notify `FFE2`
- 9 种灯效、座位绑定、Ed25519 防伪、双平台广播烧录、OTA 分包

完整规格：[docs/protocol/PROTOCOL.md](docs/protocol/PROTOCOL.md)

## TODO 待办

### Rust 领域层落地（替换 Dart/Native 实现，UI 零改动，见 AGENT.md 铁律 4）

- [ ] `rust/src/bluetooth/`：扫描 / 连接 / 读写，替换 flutter_blue_plus
- [ ] `rust/src/lightstick/`：device / controller / effect；连续动画（聚会 / 星空 / 跑马灯的 100ms 动画帧，参考 Kotlin 参考实现）
- [ ] `rust/src/audio/`：analyzer / spectrum，Dart 侧 `AudioAnalyzer` 迁入
- [ ] `rust/src/protocol/`：decoder / encoder 落地（响应解码：防伪回执 / OTA 状态等）

### 功能完善

- [ ] OTA 固件升级：分包发送 / 进度显示 / 重启
- [ ] 座位绑定页真机验证与完善
- [ ] 灯效页（`lighting_page.dart`）落地为可交互页面
- [ ] 音乐律动：单色 / 七彩 / 强烈 / 柔和 律动模式与荧光棒联动参数细化

### 基础设施

- [ ] `core/error/app_exception` 统一异常接入各 Repository
- [ ] `about_page` / `app_button` / 通用 `color_picker` 组件落地
- [ ] iOS：麦克风权限文案 + BLE 真机验证
