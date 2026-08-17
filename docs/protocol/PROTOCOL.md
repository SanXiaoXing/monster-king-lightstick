# 说明文档

> 由微信小程序反编译代码提取并移植到 Flutter + Rust 架构的控制 App。
> 协议层与原小程序字节级对齐，已通过 61 个单元测试验证。

---

## 一、软件功能概览

### 1.1 核心功能

| 功能模块 | 说明 | 对应小程序页面 |
|---|---|---|
| 蓝牙连接 | 扫描/连接/订阅/读写腕带设备 | 蓝牙管理页 |
| 灯光控制 | 9 种灯光效果（黑屏/常亮/快闪/眨眼/呼吸/聚会/彩虹/星空/随机色） | lighting 页 |
| 座位绑定 | 写入座位区域、坐标、显示编号；解绑座位 | seatbind 页 |
| 防伪验证 | Ed25519 验签确认设备真伪 | 防伪校验页 |
| 广播烧录 | Android manufacturerData / iOS serviceUuids 双平台广播 | operations 页 |
| OTA 升级 | 固件分包下发、模式切换、重启 | ota-manager 页 |

### 1.2 目标平台

- **Android**：通过 manufacturerSpecificData 广播
- **iOS**：通过 serviceUuids 广播（xorshift32 混淆）

---

## 二、技术架构

### 2.1 整体结构

```
WanShou/
├── wan_protocol/              # Rust 协议层（与小程序字节级对齐）
│   └── src/
│       ├── hexutil.rs         # hex/LE/字节转换
│       ├── crc32.rs           # CRC32 (IEEE 802.3)
│       ├── aes.rs             # AES-128-ECB ×2
│       ├── ed25519_sig.rs     # Ed25519 验签
│       ├── packet.rs          # 命令包构造
│       ├── commands.rs        # 9 灯光/座位/防伪指令
│       ├── broadcast.rs       # 广播烧录协议
│       ├── ota.rs             # OTA 固件升级
│       └── test_vectors.rs    # 19 个金标准测试向量
├── rust/                      # Flutter Rust Bridge 桥接层
│   └── src/api/protocol.rs    # 25 个 frb 包装函数
└── wanshou/                   # Flutter 工程
    └── lib/
        ├── main.dart          # 协议验证演示页
        └── src/rust/api/protocol.dart  # 自动生成的 Dart 绑定
```

### 2.2 技术栈

| 层 | 技术 | 版本 |
|---|---|---|
| UI | Flutter | 3.41.2 |
| 协议层 | Rust | 1.96.0 |
| 桥接 | flutter_rust_bridge | 2.12.0 |
| 加密 | aes / cipher / ed25519-dalek | - |
| CRC | crc32fast | 1.4 |

### 2.3 数据流

```
Flutter UI (Dart)
   ↓ async 调用
flutter_rust_bridge (自动生成绑定)
   ↓
wan_protocol_frb (Rust 包装层)
   ↓ re-export
wan_protocol (Rust 协议层)
   ↓ 输出 hex/bytes
蓝牙 BLE 写入
```

---

## 三、蓝牙通信协议

### 3.1 通信流程

```
1. 扫描设备（按 serviceUuid 过滤）
2. 建立连接
3. 发现服务 / 特征值
4. 订阅 notify 特征值
5. 构造命令包 → 写入 write 特征值
6. 接收 notify 数据 → 解析响应
```

### 3.2 命令包格式

所有 BLE 命令包遵循统一格式：

```
┌──────────────┬──────────────┬──────────────┐
│  帧序号 (4B)  │   命令体 (N) │  CRC32 (4B)  │
│   小端 LE     │   可变长度   │   小端 LE    │
└──────────────┴──────────────┴──────────────┘
```

| 字段 | 长度 | 说明 |
|---|---|---|
| 帧序号 | 4 字节 | 全局递增计数器，小端 hex（如 seq=2 → 02000000） |
| 命令体 | N 字节 | 由具体命令决定（灯光/座位/防伪/OTA） |
| CRC32 | 4 字节 | 对"帧序号 + 命令体"做 CRC32（IEEE 802.3），小端包装 |

**示例**：座位绑定闪光特效包 LIGHT_FLASH_HEX

```
02000000100004ff020c06104c6a5e52
├────────┬────────────────┬────────┤
│帧序号2 │  命令体(8B)     │ CRC32  │
│02000000│ 100004ff020c0610│ 4c6a5e52│
└────────┴────────────────┴────────┘
```

### 3.3 帧序号小端转换

对应小程序 dec2hex(FrameSequence, 8) + littleEndian(...)：

```
seq=1     → "01000000"
seq=2     → "02000000"
seq=0xABCDEF01 → "01efcdab"
```

---

## 四、加密算法

### 4.1 AES-128-ECB（两套密钥）

#### 4.1.1 API 加密（Hex 密钥）

| 项 | 值 |
|---|---|
| 算法 | AES-128-ECB / Pkcs7 |
| 密钥 | e19d688e06576f47331a701e62ee5a50（32 字符 hex） |
| 密钥解析 | enc.Hex.parse(...) → 16 字节 |
| 输入 | UTF-8 字符串（如 JSON） |
| 输出 | hex 字符串 |

**来源**：appservice.app.js:861（小程序 API 请求加密）

#### 4.1.2 设备上报加密（UTF-8 密钥）

| 项 | 值 |
|---|---|
| 算法 | AES-128-ECB / Pkcs7 |
| 密钥 | xuecwdbn60bljumz（16 字符 UTF-8） |
| 密钥解析 | 直接 UTF-8 字节 |
| 输入 | UTF-8 字符串 |
| 输出 | OpenSSL 格式 base64（Salted__ + 8B 盐 + 密文） |

**来源**：appservice.app.js:841（aes-util.js CryptoHelper）

### 4.2 Ed25519 验签

| 项 | 值 |
|---|---|
| 算法 | Ed25519（RFC 8032） |
| 用途 | 设备防伪验证 |
| JS 实现 | tweetnacl sign.detached.verify |
| Rust 实现 | ed25519-dalek |
| 互通性 | 标准 RFC 8032，JS/Rust 互通 |

---

## 五、CRC32 校验

### 5.1 算法规格

| 项 | 值 |
|---|---|
| 标准 | IEEE 802.3（与 zlib/PNG 一致） |
| 多项式 | 0xEDB88320（反射形式） |
| 初始值 | 0xFFFFFFFF |
| 输出反转 | 是 |
| 最终异或 | 0xFFFFFFFF |
| 经典校验值 | "123456789" → 0xCBF43926 |

### 5.2 小端包装

命令包中的 CRC32 以小端 hex 形式附加在包尾：

```
CRC32 值: 0x525E6A4C
小端字节: 4C 6A 5E 52
hex 字符串: "4c6a5e52"
```

**来源**：appservice.app.js:861（util.js hex16StrCrc32Encryption）

---

## 六、命令字表

### 6.1 灯光效果（9 种）

对应小程序 chunk_2.appservice.js:123 functionalInstructions：

| 效果 | 枚举 | 命令体格式 | 说明 |
|---|---|---|---|
| 黑屏 | BlackScreen | 00000000 | 全黑 |
| 常亮 | ConstantlyOn | 00 + color(6) | 固定颜色 |
| 随机色 | Random | 00 + color(6) | 随机颜色 |
| 快闪 | FlashMob | 10 + color(6) + 020c0610 | 快速闪烁 |
| 眨眼 | Blink | 20 + color(6) + 58029001 | 慢速闪烁 |
| 呼吸 | Breathe | 20 + color(6) + c409f401 | 呼吸渐变 |
| 聚会 | Party | 30 + color(6) + random(8) | 多彩随机 |
| 彩虹 | Rainbow | 30 + color(6) + random(8) | 彩虹流转 |
| 星空 | StarrySky | 30 + color(6) + random(8) | 星光效果 |

其中 color 为 RGB hex（如 ff8800），random(8) 为 8 hex 随机字节。

### 6.2 座位写入

对应 chunk_8.appservice.js:129 writeSeatInfo：

```
命令体格式（10 字节）：
┌─────────┬─────────┬─────────┬─────────────┬───────┐
│ area(1) │  x(2LE) │  y(2LE) │ reserved(4) │ show  │
└─────────┴─────────┴─────────┴─────────────┴───────┘
```

- area：区域编号（None → 0xFF）
- x, y：座位坐标（u16 小端）
- reserved：固定 FFFFFFFF
- show：显示编号（None → 0xFF）

**解绑**：全 0xFF → FFFFFFFFFFFFFFFFFFFF

### 6.3 防伪指令

对应 appservice.app.js:844 _verifyAntiFake：

```
命令包格式（39 字节）：
┌──────────┬─────────┬──────────┬──────────────┬──────────┬──────────┐
│ 帧序号(4)│ F01DF5  │ MAC_LE(6)│ 0000FF000000│ 随机(16) │ CRC32(4) │
└──────────┴─────────┴──────────┴──────────────┴──────────┴──────────┘
```

- 魔数：F0 1D F5
- MAC：小端字节序（如 aabbccddeeff → ffeeddccbbaa）
- 固定段：00 00 FF 00 00 00
- 随机挑战：16 字节（由服务端下发或本地生成）
- CRC32：覆盖前 35 字节

### 6.4 闪光特效（座位绑定）

对应 chunk_8.appservice.js:129 showshanguan：

```
LIGHT_FLASH_HEX = "02000000100004ff020c06104c6a5e52"
```

这是开发者真机抓包后写死的常量，用于座位绑定时的闪光确认。

---

## 七、广播烧录协议

### 7.1 Android 广播（manufacturerData）

对应 appservice.app.js:843 buildBroadcastData：

```
27 字节 manufacturerSpecificData：
manufacturerId = 0xFFFD

┌──────────┬───────┬──────────┬────────┬────────┬────────┬────────┬────────┬───────┬──────────┐
│ seq(4LE) │ F01779│ MAC_LE(6)│region  │  x0(2LE)│  y0(2LE)│ FFFF(2) │ FFFF(2) │ show  │ CRC32(4LE)│
└──────────┴───────┴──────────┴────────┴────────┴────────┴────────┴────────┴───────┴──────────┘
   [0..4]    [4..7]   [7..13]    [13]    [14..16] [16..18]  [18..20]  [20..22]  [22]    [23..27]
```

- CRC32 覆盖前 23 字节

### 7.2 iOS 广播（serviceUuids + XOR 混淆）

对应 chunk_69.appservice.js:46 doStartAdvertising 内联算法：

iOS 不支持 manufacturerData，需将 26 字节数据转换为 13 个 serviceUuid。

#### 7.2.1 数据构造（26 字节）

```
┌────────────────────┬───────────────────┬──────────┐
│ 头部(3) + F0        │  payload(19)      │ CRC32(4LE)│
└────────────────────┴───────────────────┴──────────┘
   [0]F7 [1]FF [2]frmcnt [3]F0 + payload[1..19]   [22..26]
```

- CRC32 覆盖 v[2..22]（frmcnt + payload，共 20 字节）

#### 7.2.2 xorshift32 混淆

对 v[4..26]（跳过 F7 FF frmcnt F0）逐字节异或：

```
seed = imul(frmcnt, 0x9E3779B1) + 2779096485
   = (frmcnt * 2654435761 + 2779096485) mod 2^32

for x in 4..26:
    seed ^= seed << 13
    seed ^= seed >> 17
    seed ^= seed << 5
    v[x] ^= (seed >> 24) & 0xFF
```

#### 7.2.3 serviceUuid 转换

26 字节按 2 字节分组，每组 [lo, hi] → "{hi:02X}{lo:02X}"：

```
[F7, FF] → "FFF7"
[42, F0] → "F042"
...
末尾奇字节补 0xFF
```

#### 7.2.4 frmcnt 循环去重

从 counter 起，frmcnt 递增直到 13 个 serviceUuid 全不重复（xorshift32 混淆下实际几轮内必能找到）。

### 7.3 MAC 字节序

Android U.unshift(byte) 与 iOS for(d=5..0) 都得到 [byte5, byte4, byte3, byte2, byte1, byte0]（小端反转）：

```
"aabbccddeeff" → [ff, ee, dd, cc, bb, aa]
```

---

## 八、OTA 固件升级

对应 appservice.app.js:855 ota-manager.js：

### 8.1 命令字

| 命令 | 字节 | 说明 |
|---|---|---|
| 模式切换 | 55 55 55 55 | 进入 OTA 模式 |
| 固件分包 | offset(4LE) + chunk | 写入固件分块 |
| 重启 | CC CC CC CC | 升级完成重启 |

### 8.2 分包格式

```
┌─────────────┬─────────────────┐
│ offset(4LE) │   chunk(N)      │
└─────────────┴─────────────────┘
```

- offset：当前分块在固件中的偏移（u32 小端）
- chunk：固件数据（可变长度）

---

## 九、测试向量验证

### 9.1 金标准向量来源

| # | 向量 | 来源 | 验证范围 |
|---|---|---|---|
| 1 | LIGHT_FLASH_HEX 端到端 | chunk_8.appservice.js:129 硬编码 | frame_seq + FlashMob body + CRC32 LE + build_packet 四层链路 |
| 2 | LIGHT_FLASH_HEX CRC 反向 | 同上 | CRC32 计算与小端包装 |
| 3 | 座位解绑 10×0xFF | chunk_8.appservice.js:129 | seat_unbind |
| 4 | 5 种灯光命令体 | chunk_2.appservice.js:123 | BlackScreen/On/FlashMob/Blink/Breathe |
| 5 | FlashMob 真机格式 | LIGHT_FLASH_HEX 内 color="0004ff" | 命令体格式 |
| 6 | 包结构 16 字节 | LIGHT_FLASH_HEX | 帧序号+命令体+CRC 长度 |
| 7 | 防伪指令 39 字节 | appservice.app.js:844 | F01DF5 + MAC LE + 随机挑战 + CRC |
| 8 | Android 广播 27 字节 | appservice.app.js:843 | seq+头+MAC+坐标+CRC |
| 9 | iOS 广播 26 字节+去重 | chunk_69.appservice.js:46 | xorshift32 混淆 + 13 serviceUuids |
| 10 | iOS serviceUuid 格式 | 同上 | {hi:02X}{lo:02X} |
| 11-12 | AES 两套 key | appservice.app.js:861/841 | Hex key 16B / UTF-8 key 16B |
| 13-14 | AES 往返+OpenSSL 格式 | crypto-js 行为 | Pkcs7 + Salted__ 前缀 |
| 15 | Ed25519 验签 | appservice.app.js:858 tweetnacl | RFC 8032 互通 |
| 16-17 | OTA 魔数+分包 | appservice.app.js:855 | 55555555/CCCCCCCC/offset LE |
| 18 | 帧序号小端 | chunk_2.appservice.js:123 | dec2hex+littleEndian |
| 19 | CRC32 经典值 | IEEE 802.3 标准 | "123456789"→0xCBF43926 |

### 9.2 测试结果

```
cargo test --manifest-path WanShou/wan_protocol/Cargo.toml
test result: ok. 61 passed; 0 failed; 0 ignored
```

**关键金标准**：LIGHT_FLASH_HEX = "02000000100004ff020c06104c6a5e52" 是开发者真机抓包后写死的常量。build_packet(2, lighting_command_body(FlashMob, "0004ff", ...)) 重建结果与之字节级一致，证明整条构造链路与真机对齐。

---

## 十、Dart 侧可用 API

通过 flutter_rust_bridge 自动生成，共 25 个函数 + 2 个类型：

### 10.1 类型

```dart
// 9 种灯光效果枚举
enum LightingEffect {
  blackScreen, constantlyOn, random, flashMob,
  blink, breathe, party, rainbow, starrySky
}

// iOS 广播结果
class IosBroadcastResult {
  final int frmcnt;      // 帧计数器
  final Uint8List data;  // 26 字节数据
}
```

### 10.2 核心函数

```dart
// 包构造
Future<String> buildPacket({required int seq, required String commandBodyHex});
Future<String> lightingCommandBody({required LightingEffect effect, required String colorHex, required int seed});
Future<String> lightFlashHex();

// 座位
Future<String> seatWriteHex({int? lightArea, required int x1, required int y1, int? showNum});
Future<String> seatUnbindHex();

// 防伪
Future<Uint8List> antifakeInstruction({required int seq, required String macHex, required Uint8List random16});
Future<bool> verifyAntifake({required Uint8List message, required Uint8List signature, required Uint8List publicKey});

// 广播
Future<Uint8List> buildAndroidBroadcast({required int seq, required String macHex, required int region, required int x0, required int y0, required int show});
Future<IosBroadcastResult> buildIosBroadcast({required int counter, required String macHex, required int region, required int x0, required int y0, required int show});
Future<List<String>> iosDataToServiceUuids({required Uint8List data});

// OTA
Future<Uint8List> buildOtaModeSwitch();
Future<Uint8List> buildOtaReboot();
Future<Uint8List> buildOtaFirmwarePacket({required int offset, required Uint8List chunk});

// 加密
Future<String> apiAesEncryptHex({required String plaintext});
Future<String> apiAesDecryptHex({required String ciphertextHex});
Future<String> reportAesEncrypt({required String plaintext});
Future<String> reportAesDecrypt({required String b64});

// CRC32 / hex 工具
Future<int> crc32Hex({required String hex});
Future<int> crc32Ieee({required Uint8List data});
Future<Uint8List> hexToBytes({required String hex});
Future<String> bytesToHex({required Uint8List bytes});
Future<String> dec2Hex({required int n, required int width});
Future<String> littleEndian({required String hex});
Future<String> frameSeqHexLe({required int seq});
```

---

## 十一、开发与构建

### 11.1 环境要求

| 工具 | 版本 |
|---|---|
| Flutter | 3.41.2 |
| Rust | 1.96.0 |
| flutter_rust_bridge_codegen | 2.12.0 |

### 11.2 构建命令

```bash
# 协议层测试
cargo test --manifest-path WanShou/wan_protocol/Cargo.toml

# Rust 桥接层检查
cargo check --manifest-path WanShou/rust/Cargo.toml

# 重新生成 Dart 绑定（修改 api/protocol.rs 后）
cd WanShou/wanshou
flutter_rust_bridge_codegen generate --no-dart-fix --no-dart-format

# Flutter 分析
flutter analyze lib/main.dart

# 运行
flutter run
```

### 11.3 Windows 构建注意

flutter build / flutter run 在 Windows 上需要开发者模式（支持符号链接）：

```
start ms-settings:developers
```

---

## 十二、移植注意事项

### 12.1 字节序一致性

所有多字节字段统一使用小端序（与小程序 JS 一致）：
- 帧序号：u32 → 4 字节小端
- CRC32：u32 → 4 字节小端 hex
- 坐标 x/y：u16 → 2 字节小端
- OTA offset：u32 → 4 字节小端

### 12.2 AES 密钥编码差异

两套 AES 密钥的编码方式不同，不可混用：

| 密钥 | 编码 | 长度 | 用途 |
|---|---|---|---|
| e19d688e06576f47331a701e62ee5a50 | Hex 解析 | 16 字节 | API 请求加密 |
| xuecwdbn60bljumz | UTF-8 直接 | 16 字节 | 设备上报加密 |

### 12.3 大小写处理

- Rust seat_unbind_hex() 返回小写 ffffffffffffffffffff
- JS writeSeatInfo("FFFFFFFFFFFFFFFFFFFF") 用大写
- BLE hexStringToArrayBuffer 用 parseInt(,16) 不区分大小写，字节级一致

### 12.4 frb 2.x 不扫描 pub use

flutter_rust_bridge 2.x 不为 pub use re-export 生成绑定，需在 api/protocol.rs 中写显式包装函数：

```rust
// 不会生成 Dart 绑定
pub use wan_protocol::build_packet;

// 会生成 Dart 绑定
pub fn build_packet(seq: u32, command_body_hex: String) -> String {
    wan_protocol::build_packet(seq, &command_body_hex)
}
```

### 12.5 iOS 广播 frmcnt 循环

iOS 广播需保证 13 个 serviceUuid 全不重复。frmcnt 从 counter 起递增，xorshift32 混淆下实际几轮内必能找到解。最多 256 轮兜底。

---

## 十三、源码引用

| 模块 | 文件 | 小程序对应位置 |
|---|---|---|
| hex/LE 转换 | wan_protocol/src/hexutil.rs | util.js dec2hex/littleEndian |
| CRC32 | wan_protocol/src/crc32.rs | util.js hex16StrCrc32Encryption |
| AES | wan_protocol/src/aes.rs | aes-util.js (CryptoHelper) |
| Ed25519 | wan_protocol/src/ed25519_sig.rs | tweetnacl sign.detached.verify |
| 命令包 | wan_protocol/src/packet.rs | ble-manager.js |
| 灯光/座位/防伪 | wan_protocol/src/commands.rs | lighting/seatbind/glowdetail 页 |
| 广播烧录 | wan_protocol/src/broadcast.rs | ble-burn.js + operations 页 |
| OTA | wan_protocol/src/ota.rs | ota-manager.js |
| 测试向量 | wan_protocol/src/test_vectors.rs | 反编译代码固定常量 |
| frb 桥接 | rust/src/api/protocol.rs | - |
| Flutter UI | wanshou/lib/main.dart | - |

---

## 附录：工程目录结构

```
WanShou/
├── docs/
│   └── PROTOCOL.md              # 本文档
├── wan_protocol/                # Rust 协议层
│   ├── Cargo.toml
│   └── src/
│       ├── lib.rs
│       ├── hexutil.rs
│       ├── crc32.rs
│       ├── aes.rs
│       ├── ed25519_sig.rs
│       ├── packet.rs
│       ├── commands.rs
│       ├── broadcast.rs
│       ├── ota.rs
│       └── test_vectors.rs
├── rust/                        # frb 桥接层
│   ├── Cargo.toml
│   └── src/
│       ├── lib.rs
│       ├── api/
│       │   ├── mod.rs
│       │   ├── simple.rs
│       │   └── protocol.rs      # 25 个包装函数
│       └── frb_generated.rs
└── wanshou/                     # Flutter 工程
    ├── pubspec.yaml
    ├── flutter_rust_bridge.yaml
    ├── rust_builder/            # cargokit 构建插件
    └── lib/
        ├── main.dart
        └── src/rust/
            ├── frb_generated.dart
            └── api/
                ├── simple.dart
                └── protocol.dart # 自动生成的 Dart 绑定
```

---

*文档版本：1.0  |  最后更新：2026-08-14  |  协议层测试：61 passed*
