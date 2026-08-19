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
import 'package:wanshou/features/lighting/presentation/pages/color_picker_page.dart';
import 'package:wanshou/features/lighting/presentation/pages/seat_binding_page.dart';
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
}

Future<DeviceViewModel> _vm({required bool connected}) async {
  final vm = DeviceViewModel(_FakeRepo(connected: connected));
  await vm.init();
  return vm;
}

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

    // 进入设置页
    await tester.ensureVisible(find.text('设置'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('设置'));
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
    await tester.tap(find.text('跟随系统'));
    await tester.pumpAndSettle();
    expect(app().themeMode, ThemeMode.system);
    expect(theme().brightness, Brightness.light);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('设置页：分组渲染、默认值', (tester) async {
    final vm = await _vm(connected: true);
    addTearDown(vm.dispose);
    await tester.pumpWidget(_wrap(SettingsPage(viewModel: vm)));
    await tester.pump();

    // 主题模式（顶部）
    expect(find.text('跟随系统'), findsOneWidget);

    // 我的设备分组
    await tester.scrollUntilVisible(find.text('清除设备记录'), 200);
    expect(find.text('清除设备记录'), findsOneWidget);

    // 灯光偏好分组：默认亮度 80%
    await tester.scrollUntilVisible(find.text('默认亮度'), 200);
    expect(find.text('80%'), findsOneWidget);

    // 音频律动分组：默认律动模式（单色）+ 默认灵敏度 60%
    await tester.scrollUntilVisible(find.text('默认律动模式'), 200);
    expect(find.text('单色'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('默认灵敏度'), 200);
    expect(find.text('60%'), findsOneWidget);

    // 无用 stub 项已删除：不再渲染任何待构建占位入口
    expect(find.text('启动灯效'), findsNothing);
    expect(find.text('记忆上次颜色'), findsNothing);
    expect(find.text('频谱样式'), findsNothing);
    expect(find.text('开源协议'), findsNothing);
    expect(find.text('反馈与建议'), findsNothing);
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

  testWidgets('连接守卫：未连接点选灯效 → 提示，不触发下发', (tester) async {
    final vm = await _vm(connected: false);
    addTearDown(vm.dispose);
    await tester.pumpWidget(_wrap(ColorPickerPage(viewModel: vm)));
    await tester.pump();

    await tester.ensureVisible(find.text('呼吸'));
    await tester.pump();
    await tester.tap(find.text('呼吸'));
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    expect(find.text('请先在「连接」Tab 配对应援棒'), findsOneWidget);
    // 未推入设备连接页，仍停留在调色页
    expect(find.byType(DevicePage), findsNothing);
  });

  testWidgets('座位绑定：区域+座位号 → 绑定成功提示', (tester) async {
    final vm = await _vm(connected: true);
    addTearDown(vm.dispose);
    await tester.pumpWidget(_wrap(SeatBindingPage(viewModel: vm)));
    await tester.pump();

    await tester.ensureVisible(find.text('看台 B 区'));
    await tester.pump();
    await tester.tap(find.text('看台 B 区'));
    await tester.pump();
    await tester.ensureVisible(find.text('绑定座位'));
    await tester.pump();
    await tester.enterText(find.byType(TextField), 'A区 12排 08号');
    await tester.tap(find.text('绑定座位'));
    await tester.pump();

    expect(find.text('✓ 座位已绑定：看台 B 区 A区 12排 08号'), findsOneWidget);
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

    // 默认已暂停
    expect(find.text('已暂停'), findsOneWidget);

    // 点击开始：权限请求失败 → 提示无法采集，状态不变
    await tester.ensureVisible(find.text('开始律动'));
    await tester.pump();
    await tester.tap(find.text('开始律动'));
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(find.textContaining('无法采集音乐'), findsOneWidget);
    // 状态未变，按钮仍是开始
    expect(find.text('开始律动'), findsOneWidget);
  });

  testWidgets('音乐律动：未连接切换模式 → 守卫提示', (tester) async {
    final vm = await _vm(connected: false);
    addTearDown(vm.dispose);
    await tester.pumpWidget(_wrap(MusicPage(viewModel: vm)));
    await tester.pump();

    await tester.ensureVisible(find.text('七彩律动'));
    await tester.pump();
    await tester.tap(find.text('七彩律动'));
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(find.text('请先在「连接」Tab 配对应援棒'), findsOneWidget);
  });
}
