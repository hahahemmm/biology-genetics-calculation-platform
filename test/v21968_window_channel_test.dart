// v21968_window_channel_test.dart —— v2.19.68 F11 无边框全屏（Windows 通道）
//
// 覆盖（P2-7 修复回归网）：
//   1. WindowChannel.toggleFullscreen 经 MethodChannel "biology/window"
//      以 method 名 "toggleFullscreen" 调用，bool 回执透传；
//   2. debugToggle 注入路径（测试钩子本身可用）；
//   3. 真实 BiologyApp 里按 F11 → 通道真的被调用一次（HomeShell
//      Shortcuts → _FullscreenIntent → WindowChannel 接线证明）。
//
// C++ 侧（windows/runner/flutter_window.cpp ToggleFullscreen）属原生
// 代码，flutter test 无法执行——由 flutter build windows --release 编译
// 把关，真机行为以通道协议为契约（本文件的 mock 即该契约）。
// mock handler 按**通道名**注册（TestDefaultBinaryMessenger 以 name 为键），
// 测试里自建同名 MethodChannel 即可命中生产实例的调用。

import 'dart:io';

import 'package:biology/main.dart';
import 'package:biology/services/window_channel.dart';
import 'package:biology/state/first_run_store.dart';
import 'package:biology/state/present_mode_controller.dart';
import 'package:biology/state/theme_controller.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// 与生产侧同名的通道实例（mock 按 name 命中）。
const MethodChannel _kWindowChannel = MethodChannel('biology/window');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    WindowChannel.debugToggle = null;
    PresentModeController.instance.debugSetEnabled(false);
  });

  testWidgets('通道契约：invokeMethod("toggleFullscreen") + bool 回执透传',
      (tester) async {
    if (!WindowChannel.supported) return; // 非 Windows：契约由 C++ 侧守
    String? capturedMethod;
    var reply = true;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      _kWindowChannel,
      (call) async {
        capturedMethod = call.method;
        return reply;
      },
    );
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(_kWindowChannel, null));

    final first = await WindowChannel.toggleFullscreen();
    expect(capturedMethod, 'toggleFullscreen');
    expect(first, isTrue, reason: '进入全屏 → 通道回执 true');

    reply = false;
    final second = await WindowChannel.toggleFullscreen();
    expect(second, isFalse, reason: '再次切换 → 还原，回执 false');
  });

  testWidgets('debugToggle 注入路径可用（HomeShell 接线的测试替身）',
      (tester) async {
    var calls = 0;
    WindowChannel.debugToggle = () async {
      calls++;
      return true;
    };
    final handled = await WindowChannel.toggleFullscreen();
    expect(handled, isTrue);
    expect(calls, 1);
  });

  testWidgets('真实 BiologyApp：按 F11 触发一次 toggleFullscreen 通道调用',
      (tester) async {
    if (!WindowChannel.supported) return; // 非 Windows：快捷键为 no-op
    final tmp = Directory.systemTemp.createTempSync('v21968_f11_shell');
    final filePath = '${tmp.path}/first_run.json';
    FirstRunStore.debugFilePath = filePath;
    FirstRunStore.debugWebStorage = null;
    FirstRunStore.debugForceIsWebStorage = false;
    FirstRunStore.instance.debugReset();
    File(filePath).writeAsStringSync('{"role":"student"}');
    addTearDown(() {
      FirstRunStore.debugFilePath = null;
      FirstRunStore.debugWebStorage = null;
      FirstRunStore.debugForceIsWebStorage = null;
      FirstRunStore.instance.debugReset();
      if (tmp.existsSync()) tmp.deleteSync(recursive: true);
    });

    var channelCalls = 0;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      _kWindowChannel,
      (call) async {
        if (call.method == 'toggleFullscreen') channelCalls++;
        return true;
      },
    );
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(_kWindowChannel, null));

    await tester.runAsync(() async {
      await ThemeController.instance.debugEnsureLoaded();
      await PresentModeController.instance.debugEnsureLoaded();
    });
    PresentModeController.instance.debugSetEnabled(false);
    await tester.pumpWidget(const BiologyApp());
    await tester.pumpAndSettle();

    await tester.sendKeyEvent(LogicalKeyboardKey.f11);
    await tester.pump();
    expect(channelCalls, 1,
        reason: 'HomeShell Shortcuts 表的 F11 → _FullscreenIntent → '
            'WindowChannel.toggleFullscreen() 接线必须真实可达');
  });
}
