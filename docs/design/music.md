This is a WeChat mini-program (演唱会荧光棒控制 app). Let me dig into the actual mic pickup / music rhythm implementation.

Found the core logic in `chunk_11.appservice.js`. Let me also check the pages directory to see if there's a readable source version, and look at the page structure.

The compiled source of `pages/music` lives in `chunk_11.appservice.js`. Let me look at the webview side (UI animation) and check the `util.js` helpers used for BLE packet encoding.

Let me check the waveform component that renders the visual bars.

这是一个微信小程序项目（演唱会荧光棒“光海智控”），源码被打包成了 `chunk_*.js`。我找到了核心实现：**“音乐调光”（MIC Music Rhythm）功能在 `pages/music/index.js`，编译产物在 `chunk_11.appservice.js` 第 108 行**。下面讲一下整个链路。

## 整体流程：mic 拾音 → 音量换算 → 蓝牙下发颜色

### 1. 录音拾音（start / onFrameRecorded）

页面用 `wx.getRecorderManager()` 开启录音来拾取环境音乐，参数是：

```js
b = { duration: 6e5, sampleRate: 44100, numberOfChannels: 1,
      encodeBitRate: 192e3, format: "PCM", frameSize: .1 }
```

`frameSize: 0.1` 表示每 **100ms** 回调一帧 PCM 数据。核心算法在 `onFrameRecorded` 里，本质就是**算这一帧的平均音量**：

```js
for (var t = e.frameBuffer, n = new Int16Array(t), a = n.length, s = 0, c = 0; c < a; c++)
    s += Math.abs(n[c]);              // 所有采样点绝对值求和
var i = 500 * s / (16383 * a);        // 归一化平均振幅，放大到 0~500
i >= 200 && (i = 200);                // 上限 200
i < 10 && (i = 0);                    // 低于 10 视为静音（噪声门限）
var l = Math.floor(i/200*120),
    d = .3 * (r = l/120) + .8,        // scale（波形动画缩放 0.8~1.1）
    f = .3 + d,                       // opacity
    g = i/200;                        // waveScale（0~1，喂给波形组件）
o.setData({ scale: d, opacity: f, waveScale: g });
u || (u = !0, o.startsend())          // 第一帧开始循环发指令
```

即：把 PCM 帧转成 `Int16Array`，求绝对值的均值，归一化到 0~200，得到音量值 `r`（0~1.67），同时算出驱动 UI 的 `scale/opacity/waveScale`。

### 2. 持续发送灯光指令（startsend / sendcommand）

拿到音量后，用 `setInterval(..., 20)` **每 20ms** 通过 BLE 向荧光棒写一次颜色：

```js
sendcommand: function () {
    var e = 255 * r * f;              // 亮度 = 音量 r × 灵敏度滑块 f（sliderchange 更新）
    e > 255 && (e = 255);
    null != p && h % 20 != 0 || (p = this.currentcolor());  // 每 20 次（400ms）换一个颜色
    h += 1;
    var t = e / 255;                  // 亮度比例
    // 当前颜色 RGB 各通道 × 亮度比例 → 音量越大颜色越亮
    o = dec2hex(p.r*t) + dec2hex(p.g*t) + dec2hex(p.b*t);
    // 组包：帧序号(4字节小端) + 0x00 + RGB + CRC32(小端)
    n = littleEndian(dec2hex(FrameSequence, 8)); FrameSequence++;
    a = n + "00" + o;
    s = littleEndian(dec2hex(hex16StrCrc32Encryption(a), 8));
    wx.writeBLECharacteristicValue({ ..., value: hexStringToArrayBuffer(a + s),
                                     writeType: "writeNoResponse", ... });
}
```

要点：
- **亮度随音量变化**：`255 * r * f`，音量越大亮度越高；`f` 来自页面滑杆（`sliderchange`，默认 1）。
- **颜色循环**：内置 15 色色板（`colorlist`），每发 20 条指令（400ms）切一次颜色，实现“随音乐变色”。
- **数据包格式**：`帧序号(4字节小端) + 0x00 + RGB(3字节) + CRC32(4字节小端)`，`FrameSequence` 每帧递增。
- 用 `writeNoResponse` 方式写入，不等待设备应答。

### 3. 录音循环续录（secondStart）

微信录音有最大时长（这里设了 10 分钟），所以监听 `onStop` 后调用 `secondStart()` **自动重新开始录音**，实现无限续录；`onPause` 或手动 `stop()` 时清掉定时器、关闭拾音。页面 `onHide`/`onUnload`/BLE 断开时也会自动 `stop()`。

### 4. 可视化波形（components/waveform）

同 chunk 里的 `waveform` 组件是纯视觉：在 2D canvas 上画 **45 根渐变柱状条**（`#89C8F8→#A089F5→#D37FEA`），接收页面的 `power`（即 `waveScale` 0~1）属性，柱高 = `baseHeight + power*maxHeight`，再加随机抖动和“中间高两边低”的衰减，形成随音量跳动的声浪效果。页面本身还有 `scale/opacity` 驱动的呼吸动画。

## 小结

| 环节 | 实现 |
|---|---|
| 拾音 | `wx.getRecorderManager()` 录 PCM，`frameSize:0.1` |
| 音量 | 每帧 `Int16Array` 绝对值均值，归一化 0~200 |
| 控制 | 每 20ms 一条 BLE 指令，亮度=音量×灵敏度，400ms 换色 |
| 指令格式 | `帧序号(4B小端)+00+RGB+CRC32(小端)`，writeNoResponse |
| 视觉 | canvas 45 根渐变波形条，power 驱动 |

顺带说明：项目里还有两个相关但不同的功能——`pages/lighting`（调色盘，黑场/常亮/快闪/眨眼/呼吸等是**静态模式**，不带 mic）；`pages/livemusic`（现场音乐，走**服务器同步场控**，不是 mic 拾音）。你说的“音乐控制灯光闪烁”对应的就是 `pages/music` 这条 mic 拾音链路。

需要的话，我可以帮你把这段混淆代码还原成可读的源码，或者分析某个细节（比如音量映射公式、BLE 组包校验）。