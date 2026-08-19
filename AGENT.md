# AGENT.md — 开发约定与目录规范

> 本文件是所有贡献者（含 AI Agent）在本仓库工作的唯一分层/目录契约。
> 改代码前先读这里；结构变更必须同步更新本文件。

---

## 1. 项目总览

万兽之王光剑/演出宝宝剑 控制 App。协议层从微信小程序（mini_metalumic）
反编译代码精确移植，字节级对齐（61 个单元测试，金标准
`LIGHT_FLASH_HEX = 02000000100004ff020c06104c6a5e52`）。

```
WanShou/
├── lib/              	  # Flutter 应用（UI 层）
├── rust/                 # FRB 桥接 crate（Flutter ↔ Rust 边界 + 领域骨架）
├── wan_protocol/         # Rust 协议实现 crate（已验证，独立复用，勿轻动）
├── glowstick-app-main/   # Kotlin 参考实现（只读，勿改）
├── docs/                 # protocol / architecture / reverse-engineering
├── scripts/              # 构建/辅助脚本
└── AGENT.md / README.md
```

## 2. 核心原则

> **Flutter 负责"人怎么操作"，Rust 负责"设备怎么工作"。**
> 界面逻辑不拼字节，协议层不碰 UI。

写代码前先问：**这段代码是在描述界面、业务、还是设备？** 然后按下表归位。

## 3. 分层规则（代码放哪）

| 代码性质 | 归属 | 说明 |
|---|---|---|
| 界面 / 状态 / 导航 | `lib/features/*/presentation` | Page / Widget / ViewModel |
| 业务模型（Dart 侧） | `lib/features/*/domain` | 纯 Dart 模型，无 IO |
| 数据访问 | `lib/features/*/data` | Repository，UI 唯一数据入口 |
| 基础设施 | `lib/core/{config,error,storage,bridge}` | 全 feature 共享，禁止塞"不知道放哪"的代码 |
| 跨 feature UI 组件 | `lib/shared/{widgets,components}` | 按钮选色器等 |
| 设备通信（扫描/连接/读写） | `rust/src/bluetooth/` | scanner / connection / characteristic |
| 协议封包/解析 | `rust/src/protocol/` | 门面 → `wan_protocol` crate |
| 荧光棒领域逻辑 | `rust/src/lightstick/` | controller / device / effect |
| 音频分析 | `rust/src/audio/` | analyzer / spectrum |
| Flutter ↔ Rust 边界 | `rust/src/api/` | **唯一 FRB 入口，只做签名转换** |

### 调用链示例（连接荧光棒）

```
Flutter DevicePage
  ↓ (只认 DeviceViewModel)
DeviceViewModel → DeviceRepository        # features/device/
  ↓ (只认 Rust API，经 core/bridge 初始化)
rust/src/api/lightstick.rs                 # 薄签名转换
  ↓
rust/src/lightstick/controller.rs          # 领域编排
  ↓                ↓
rust/src/bluetooth/   rust/src/protocol/   # 通信 / 封包
                          ↓
                    wan_protocol crate     # 已验证实现
```

## 4. 边界铁律

1. **`rust/src/api/` 是 Flutter 唯一入口**：frb 只扫描 `crate::api`
   （`flutter_rust_bridge.yaml` 的 `rust_input`）。新能力 = 新 api 文件 +
   对应内部模块，不要把实现塞进 api。
2. **内部模块统一走 `crate::protocol::`**，不直接 `use wan_protocol`。
   protocol/ 是门面（packet/command/decoder/encoder），将来物理合并
   wan_protocol 时调用方零改动。
3. **生成代码禁止手改**：`lib/src/rust/`、`rust/src/frb_generated.rs`。
   改 `rust/src/api/` 后在仓库根重新生成：
   `flutter_rust_bridge_codegen generate --no-dart-fix --no-dart-format`
4. **UI 不 import 生成代码**：经 `core/bridge/rust_bridge.dart` 初始化，
   经各 feature Repository 调用。换掉 Rust BLE 为 Native/Mock 时 UI 不动。
   `ponytail:` 现状 BLE 以 flutter_blue_plus 落地于
   `features/device/data/device_repository.dart`（Native 实现，扫描按 FFE0
   服务过滤）；rust/src/bluetooth 骨架保留，就绪后 Repository 换实现，
   UI 零改动。
5. **wan_protocol 是已验证资产**：新协议能力先落 wan_protocol（必须带
   测试向量，`cargo test` 全绿），再在 `rust/src/protocol/` 补 re-export。
6. **glowstick-app-main 只读**：它是 Kotlin 参考实现（BLE 时序/动画帧
   的真机验证来源），逆向结论提炼进 `docs/`，不修改其代码。
7. **待实现模块是骨架不是垃圾桶**：`bluetooth/ lightstick/ audio/` 及
   对应 feature 下的空文件只带职责注释，不预写投机 API。

## 5. 目录详情

### lib（Flutter）

```
lib/
├── app/
│   ├── app.dart                      # 根 Widget [已实现]（首页 = HomePage，双主题 + 跟随系统）
│   ├── router/app_router.dart        # 集中路由 [已实现]（AppRouter.page 推页，不手写 MaterialPageRoute）
│   └── theme/app_theme.dart          # 全局主题 [已实现]（浅色/深色 ColorScheme + themeModeNotifier 跟随系统）
├── core/
│   ├── bridge/rust_bridge.dart       # Rust 运行时门面 [已实现]
│   ├── config/app_config.dart        # 应用常量 [已实现]
│   └── storage/local_storage.dart    # 持久化 [已实现]（shared_preferences；主题模式已接入）
├── features/
│   ├── home/presentation/pages/home_page.dart   # 主页 [已实现]（Liquid Glass 悬浮胶囊 Dock + 页面切换过渡）
│   ├── home/presentation/widgets/glass_tab_bar.dart # 玻璃 Dock 导航栏 [已实现]（毛玻璃壳 + 选中态弹簧胶囊）
│   ├── device/                       # data/domain/presentation [已实现：flutter_blue_plus 于 Repository 层]
│   ├── lighting/                     # domain [已实现：LightingFx 枚举]；presentation：调色盘 [已实现：圆形色环 + hex + 亮度 + 8 灯效单列]
│   ├── audio/                        # domain [已实现：AudioFrame/RhythmOutput 模型，分析已迁 Rust]；data [已实现：record 采集 + Rust 分析/律动]；presentation：音乐调光 [已实现]
│   ├── settings/                     # settings_page.dart [已实现]（仅 4 项：显示模式滑动胶囊/已连接设备/温馨提示/关于）
│   └── about/                        # tips_page 温馨提示 [已实现]
├── shared/
│   ├── theme/spacing.dart            # 统一间距系统（pageMargin/cardPadding/gap12/gap16/bottomSafe）[已实现]
│   ├── widgets/app_top_bar.dart      # 统一顶栏 AppTopBar [已实现]
│   ├── widgets/app_icon_button.dart  # 顶栏图标按钮 36×36 [已实现]
│   ├── widgets/card_decoration.dart  # 统一卡片圆角/描边 [已实现]
│   ├── widgets/connect_guard_view.dart # 未连接引导视图（调色/音乐页）[已实现]
│   ├── widgets/brand_logo.dart       # 像素风品牌 Logo（CustomPaint 复刻 SVG）[已实现]
│   ├── widgets/slider_row.dart       # 带标签滑杆行（亮度/灵敏度共用）[已实现]
│   └── widgets/sliding_segment.dart  # 滑动分段选择器（主题/律动模式共用，临界阻尼胶囊）[已实现]
├── src/rust/                         # frb 生成，禁改
└── main.dart                         # RustBridge.init + 存储/主题初始化 + runApp [已实现]
```

### rust/src（FRB 桥接 crate）

```
src/
├── api/
│   ├── protocol.rs                   # 协议构造（lighting_command_body / build_packet / hex_to_bytes + LightingEffect）[已实现]
│   ├── simple.rs                     # frb 初始化钩子（init_app）[已实现]
│   ├── lightstick.rs                # 音乐律动引擎（MusicRhythm→LightOutput）[已实现]
│   ├── audio.rs                     # 音频分析（PcmAnalyzer→AudioFrame）[已实现]
│   └── mod.rs
├── protocol/                         # 门面：mod + packet + command [透传]，全量 re-export wan_protocol
├── lightstick/                       # effect：音乐律动引擎（亮度=音量×灵敏度、15 色板循环，对齐 docs/design/music.md）[已实现]
├── audio/                            # analyzer：PCM16→音量/频带/节拍帧（Dart 版移植）[已实现]
├── error.rs                          # WanError 统一错误 [已实现]
├── frb_generated.rs                  # 生成，禁改
└── lib.rs
```

### wan_protocol（协议实现 crate，已验证）

`hexutil / crc32 / aes / ed25519_sig / packet / commands / broadcast / ota / test_vectors`
—— 见 `docs/protocol/PROTOCOL.md`（命令字表、加密规格、测试向量来源）。

## 6. 验证命令

```powershell
# 协议层 61 测试（动 wan_protocol 或 protocol 门面后必跑）
cargo test --manifest-path wan_protocol/Cargo.toml

# 桥接 crate 编译检查（动 rust/src 后必跑）
cargo check --manifest-path rust/Cargo.toml

# Flutter 静态分析（Windows 需先开开发者模式：start ms-settings:developers）
# 在仓库根执行
flutter analyze

# 重新生成 FRB 绑定（动 rust/src/api 后，在仓库根执行）
flutter_rust_bridge_codegen generate --no-dart-fix --no-dart-format
```

## 7. 约定

- 注释/文档用中文；`ponytail:` 前缀标记有已知上限的刻意简化及升级路径。
- 骨架文件落地实现时，删掉"待实现"字样并更新本文件第 5 节的状态标注。
- 遵循 ponytail：最小可用 diff；不过度抽象；能复用已验证代码不重写。
