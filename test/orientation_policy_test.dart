// orientation_policy_test.dart —— v2.19.26 方向策略 control test
//
// 官方 control 写法（flutter/test/services/system_chrome_test.dart）：
// mock SystemChannels.platform 捕获 SystemChrome.setPreferredOrientations
// 下发值——手机档（物理短边 <600dp）必须仅竖屏；平板档（≥600dp）必须
// 放开横屏。物理 display 尺寸改 tester.view.physicalSize 后
// didChangeMetrics 重评估（类档差分保证只有跨档才二次下发）。

import 'package:biology/main.dart';
import 'package:biology/state/first_run_store.dart';
import 'package:biology/state/theme_controller.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('方向策略：手机锁竖屏、平板放开横竖', (tester) async {
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      calls.add(call);
      return null;
    });
    addTearDown(() => TestDefaultBinaryMessengerBinding
        .instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null));

    tester.view.physicalSize = const Size(390, 844); // 手机 9:16 竖
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.runAsync(() => ThemeController.instance.debugEnsureLoaded());
    await FirstRunStore.instance.setRole(UserRole.student);
    addTearDown(FirstRunStore.instance.debugReset);

    await tester.pumpWidget(const BiologyApp());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    List<String> lastOrientations() {
      final c = calls
          .where((c) => c.method == 'SystemChrome.setPreferredOrientations')
          .toList();
      expect(c, isNotEmpty, reason: '应至少下发一次方向策略');
      return (c.last.arguments as List).cast<String>();
    }

    var orient = lastOrientations();
    expect(orient, contains('DeviceOrientation.portraitUp'));
    expect(orient, isNot(contains('DeviceOrientation.landscapeLeft')),
        reason: '手机档不得包含横屏（锁竖屏 = 设计基准）；calls=$calls');

    // 切平板 3:4 横屏（1280×800）→ 类档跨档 → 二次下发。
    tester.view.physicalSize = const Size(1280, 800);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    orient = lastOrientations();
    expect(orient, contains('DeviceOrientation.landscapeLeft'),
        reason: '平板档放开横屏');
    expect(orient, contains('DeviceOrientation.portraitUp'),
        reason: '平板档竖屏也可用（3:4 竖拿适配）');
  });
}
