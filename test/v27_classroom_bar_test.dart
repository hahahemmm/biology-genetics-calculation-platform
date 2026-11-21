// v27_classroom_bar_test.dart —— v2.7 课堂快捷条
//
// 覆盖：仅课堂模式渲染；聚光灯/高对比/激光/退出四键语义；
// 快捷条按钮调真实 setter；统一注入临时 present_mode.json，
// 既不读真机课堂状态，也不把测试值写回真机。

import 'dart:io';

import 'package:biology/state/present_mode_controller.dart';
import 'package:biology/ui/classroom_quick_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final pm = PresentModeController.instance;
  late Directory tmp;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('v27_classroom_bar');
    PresentModeController.debugFilePath = '${tmp.path}/present_mode.json';
    PresentModeController.instance.debugReset();
  });

  tearDown(() {
    PresentModeController.debugFilePath = null;
    PresentModeController.instance.debugReset();
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  Future<void> pumpBar(WidgetTester t, {required bool spotlightAvailable}) async {
    await t.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Align(
          alignment: Alignment.bottomRight,
          child: ClassroomQuickBar(spotlightAvailable: spotlightAvailable),
        ),
      ),
    ));
    await t.pump();
  }

  testWidgets('课堂模式关 → 不渲染；开 → 四个键都在', (t) async {
    pm.debugSetEnabled(false);
    await pumpBar(t, spotlightAvailable: true);
    expect(find.byIcon(Icons.contrast_outlined), findsNothing);

    pm.debugSetEnabled(true);
    await t.pump();
    expect(find.byIcon(Icons.contrast_outlined), findsOneWidget); // 高对比
    expect(find.byIcon(Icons.gps_fixed_outlined), findsOneWidget); // 激光笔
    expect(find.byIcon(Icons.school_outlined), findsOneWidget); // 退出课堂
    expect(find.byIcon(Icons.highlight_outlined), findsOneWidget); // 聚光灯
  });

  testWidgets('聚光灯：系谱页可开关；其他页禁用', (t) async {
    pm.debugSetEnabled(true);
    await pumpBar(t, spotlightAvailable: true);
    await t.tap(find.byIcon(Icons.highlight_outlined));
    await t.pump();
    expect(pm.spotlightOn, isTrue);
    // 再点关闭（开启态图标变 Icons.highlight）
    await t.tap(find.byIcon(Icons.highlight));
    await t.pump();
    expect(pm.spotlightOn, isFalse);

    // 非系谱页：禁用（点了没反应）
    await pumpBar(t, spotlightAvailable: false);
    await t.pump();
    await t.tap(find.byIcon(Icons.highlight_outlined));
    await t.pump();
    expect(pm.spotlightOn, isFalse);
  });

  testWidgets('高对比与激光笔开关语义', (t) async {
    pm.debugSetEnabled(true);
    await pumpBar(t, spotlightAvailable: true);
    await t.tap(find.byIcon(Icons.contrast_outlined));
    await t.pump();
    expect(pm.highContrast, isTrue);
    await t.tap(find.byIcon(Icons.gps_fixed_outlined));
    await t.pump();
    expect(pm.laserEnabled, isTrue);
  });

  testWidgets('退出课堂模式：一键回学生模式，快捷条消失', (t) async {
    pm.debugSetEnabled(true);
    await pumpBar(t, spotlightAvailable: true);
    await t.tap(find.byIcon(Icons.school_outlined));
    await t.pump();
    expect(pm.enabled, isFalse);
    await t.pump();
    expect(find.byIcon(Icons.contrast_outlined), findsNothing);
  });
}
