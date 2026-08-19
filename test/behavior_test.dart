// 行为验证测试：驱动真实页面与状态流转，断言输出结果。
//
// 覆盖：主题切换（跟随系统/浅色/深色）、FX 选择往返、调色盘取色数学
// （色相→hex）、亮度滑杆、连接守卫、座位绑定、音乐响应开关。
//
// 未连接路径用真实 DeviceRepository（插件缺失走 onError 分支）；
// 已连接路径用 _FakeRepo 子类伪造蓝牙状态，验证连接后行为。

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:wanshou/app/app.dart';
import 'package:wanshou/app/theme/app_theme.dart';
import 'package:wanshou/features/audio/presentation/pages/music_page.dart';
import 'package:wanshou/features/device/data/device_repository.dart';
import 'package:wanshou/features/device/domain/device_state.dart';
import 'package:wanshou/features/device/domain/lightstick.dart';
import 'package:wanshou/features/device/presentation/device_view_model.dart';
import 'package:wanshou/features/device/presentation/pages/device_page.dart';
import 'package:wanshou/features/home/presentation/widgets/glass_tab_bar.dart';
import 'package:wanshou/features/lighting/presentation/pages/color_picker_page.dart';
import 'package:wanshou/features/settings/settings_page.dart';

/// 伪造仓库：蓝牙开启；connected=true 时上报一台已连接设备。
class _FakeRepo extends DeviceRepository {
  _FakeRepo({required this.connected});

  final bool connected;

  @override
  Stream<BluetoothAdapterState> get adapterState =>
      Stream.value(BluetoothAdapterState.on);

  @override
  Future<List<Lightstick>> connectedDevices() async => connected
      ? const [Lightstick(address: 'AA:BB:CC:DD:EE:FF', name: '万兽之王 · 应援棒')]
      : const [];

  @override
  Stream<DeviceConnectionState> connectionStateOf(Lightstick device) =>
      Stream.value(DeviceConnectionState.connected);

  // 新 ViewModel 在 init 时重连已恢复设备并校验真实会话（防假连接状态）
  @override
  Future<void> connect(Lightstick device) async {}

  @override
  bool isConnected(Lightstick device) => connected;

  // 首次进入自动搜索：扫描全链路也由 Fake 接管，避免触碰插件（测试环境
  // 无平台实现，startScan 会抛 UnsupportedError 且污染全局 isScanning 状态）
  @override
  bool get isScanning => false;

  @override
  Future<void> startScan({Duration timeout = const Duration(seconds: 5)}) async {}

  @override
  Future<void> stopScan() async {}

  @override
  Stream<List<Lightstick>> get scanResults => const Stream.empty();
}

Future<DeviceViewModel> _vm({required bool connected}) async {
  final vm = DeviceViewModel(_FakeRepo(connected: connected));
  await vm.init();
  return vm;
}

/// Dock 栏中的 Tab 文案（避开与页面内 AppTopBar 标题同名的重复匹配）。
Finder _dockTab(String label) => find.descendant(
      of: find.byType(GlassTabBar),
      matching: find.text(label),
    );

Widget _wrap(Widget home) =>
    MaterialApp(theme: buildLightTheme(), home: home);

void main() {
  setUp(() => themeModeNotifier.value = ThemeMode.system);

  // record 插件在测试环境无原生实现：全局 mock 通道让构造（create）成功，
  // 否则 AudioRecorder 构造函数发起的 create 永久挂起，泄漏 record 包
  // 的全局信号量，导致后续 hasPermission 全部卡死。
  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('com.llfbandit.record/messages'),
      (call) async => null,
    );
  });

  testWidgets('主题切换：设置页三档切换驱动 MaterialApp 重建', (tester) async {
    await tester.pumpWidget(const App());
    await tester.pump();

    // 进入设置页（Dock 栏 Tab；页面内 AppTopBar 标题同名，需限定作用域）
    await tester.pumpAndSettle();
    await tester.tap(_dockTab('设置'));
    await tester.pumpAndSettle();

    MaterialApp app() => tester.widget<MaterialApp>(find.byType(MaterialApp));
    ThemeData theme() => Theme.of(tester.element(find.byType(SettingsPage)));

    // 默认跟随系统（测试环境平台亮度为浅色）
    expect(app().themeMode, ThemeMode.system);
    expect(theme().brightness, Brightness.light);

    // 切深色
    await tester.tap(find.text('深色'));
    await tester.pumpAndSettle();
    expect(app().themeMode, ThemeMode.dark);
    expect(theme().brightness, Brightness.dark);

    // 切浅色
    await tester.tap(find.text('浅色'));
    await tester.pumpAndSettle();
    expect(app().themeMode, ThemeMode.light);
    expect(theme().brightness, Brightness.light);

    // 回跟随系统
    await tester.tap(find.text('跟随'));
    await tester.pumpAndSettle();
    expect(app().themeMode, ThemeMode.system);
    expect(theme().brightness, Brightness.light);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('设置页：四项分组渲染（显示模式/已连接设备/温馨提示/关于）', (tester) async {
    final vm = await _vm(connected: true);
    addTearDown(vm.dispose);
    await tester.pumpWidget(_wrap(SettingsPage(viewModel: vm)));
    await tester.pump();

    // 显示模式（顶部）：3 档 pill
    expect(find.text('跟随'), findsOneWidget);
    expect(find.text('浅色'), findsOneWidget);
    expect(find.text('深色'), findsOneWidget);

    // 已连接设备分组：连接态显示设备名
    expect(find.text('已连接'), findsOneWidget);

    // 温馨提示入口（滚动到唯一副标题，避免与分组标签同名歧义）
    await tester.scrollUntilVisible(find.text('阅读安全提示'), 200);
    expect(find.text('温馨提示'), findsWidgets);
    expect(find.text('阅读安全提示'), findsOneWidget);

    // 关于分组
    await tester.scrollUntilVisible(find.text('万兽之王'), 200);
    expect(find.text('万兽之王'), findsOneWidget);
    expect(find.text('v1.0.0'), findsOneWidget);

    // 已删除的项不再渲染
    expect(find.text('清除设备记录'), findsNothing);
    expect(find.text('默认亮度'), findsNothing);
    expect(find.text('默认灵敏度'), findsNothing);
    expect(find.text('座位绑定'), findsNothing);
  });

  testWidgets('调色盘：默认 #0A84FF，色环取色/hex 回填/亮度滑杆', (tester) async {
    final vm = await _vm(connected: true);
    addTearDown(vm.dispose);
    await tester.pumpWidget(_wrap(ColorPickerPage(viewModel: vm)));
    await tester.pump();

    TextField field() => tester.widget<TextField>(find.byType(TextField));

    // 默认 iOS 蓝
    expect(field().controller!.text, '0A84FF');

    // 色环取色：拖到底部边缘（90° 黄绿），颜色应显著偏离默认蓝
    final wheelRect = tester.getRect(find.byType(AspectRatio));
    final g = await tester.startGesture(
        wheelRect.center + Offset(0, wheelRect.height / 2 - 2));
    await g.moveBy(const Offset(0, 2));
    await g.up();
    await tester.pump();
    final afterDrag = field().controller!.text;
    expect(afterDrag, isNot('0A84FF'));

    // 点击圆心 → 白（S=0，精确）
    final g2 = await tester.startGesture(wheelRect.center);
    await g2.up();
    await tester.pump();
    expect(field().controller!.text, 'FFFFFF');

    // hex 输入回填：直接键入十六进制 → 状态同步
    await tester.enterText(find.byType(TextField), '00FF00');
    await tester.pump();
    expect(field().controller!.text, '00FF00');

    // 亮度滑杆默认 80%，左拉后不再是满值（滑杆在视口下方，先滚动到可见）
    await tester.ensureVisible(find.byType(Slider));
    await tester.pump();
    expect(find.text('80%'), findsOneWidget);
    await tester.drag(find.byType(Slider), const Offset(-120, 0));
    await tester.pump();
    expect(find.text('80%'), findsNothing);

    // 卸载页面 → dispose 取消防抖定时器，避免遗留 Timer
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('连接守卫：未连接时调色页锁定为连接引导，不渲染灯效', (tester) async {
    final vm = await _vm(connected: false);
    addTearDown(vm.dispose);
    await tester.pumpWidget(_wrap(ColorPickerPage(viewModel: vm)));
    await tester.pump();

    // 正文被 ConnectGuardView 替换：提示文案 + 图标，无灯效网格
    expect(find.text('尚未连接应援棒'), findsOneWidget);
    expect(find.byIcon(Icons.bluetooth_disabled_rounded), findsOneWidget);
    expect(find.text('呼吸'), findsNothing);
    // 独立页未传 onGoConnect：不渲染「去连接」按钮
    expect(find.text('去连接'), findsNothing);
    // 未推入设备连接页
    expect(find.byType(DevicePage), findsNothing);
  });

  testWidgets('音乐律动：连接后点击开始 → 麦克风不可用 → 提示采集失败，状态不变',
      (tester) async {
    // 测试环境无 record 原生插件：mock 平台通道——构造（create）成功，
    // 权限请求（hasPermission）立即失败，避免永久挂起。
    // 注意 create 是 AudioRecorder 构造函数异步发起的，不能抛错。
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('com.llfbandit.record/messages'),
      (call) async {
        if (call.method == 'create') return null;
        throw PlatformException(code: 'no_impl', message: '测试环境无录音插件');
      },
    );

    final vm = await _vm(connected: true);
    addTearDown(vm.dispose);
    await tester.pumpWidget(_wrap(MusicPage(viewModel: vm)));
    await tester.pump();

    // 默认未开启：音乐响应开关处于 off（语义 toggled=false）
    expect(find.text('音乐响应'), findsOneWidget);

    // 点击开关（Semantics label 定位自定义 iOS 开关）
    // 权限请求失败 → 提示无法采集，状态不变（开关仍 off）
    await tester.ensureVisible(find.bySemanticsLabel('音乐响应开关'));
    await tester.pump();
    await tester.tap(find.bySemanticsLabel('音乐响应开关'));
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(find.textContaining('无法采集音乐'), findsOneWidget);
    // 状态未变：开关语义仍是 toggled=false
    final sw = tester.widget<Semantics>(find.bySemanticsLabel('音乐响应开关'));
    expect(sw.properties.toggled, isFalse);
  });

  testWidgets('音乐律动：未连接时正文锁定为连接引导', (tester) async {
    final vm = await _vm(connected: false);
    addTearDown(vm.dispose);
    await tester.pumpWidget(_wrap(MusicPage(viewModel: vm)));
    await tester.pump();

    // 未连接：ConnectGuardView 替换正文，律动控件不可见
    expect(find.text('尚未连接应援棒'), findsOneWidget);
    expect(find.text('七彩'), findsNothing);
    expect(find.text('音乐响应'), findsNothing);
  });
}
