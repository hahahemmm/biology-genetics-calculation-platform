// v26_board_presenter_test.dart —— v2.6 板书全屏放映（课堂讲解优化）
//
// 场景：老师大屏讲课——板书视图点「放映」→ 全屏遗传图解（杂质隐藏、格子按屏宽放大），关闭后回到页面。

import 'package:biology/pages/cross_calculator_page.dart';
import 'package:biology/pages/settings_page.dart';
import 'package:biology/services/ai_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    AiSettingsStore.debugConfig = AiConfig.presetMinimax;
  });
  tearDown(() {
    AiSettingsStore.debugConfig = null;
  });

  testWidgets('板书放映：打开全屏棋盘 → 退出', (t) async {
    t.view.physicalSize = const Size(1920, 1080);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);
    await t.pumpWidget(const MaterialApp(home: CrossCalculatorPage()));
    await t.pump();

    // 预设 chip 一键计算（杂合自交 9331，chip 触发自动计算
    await t.tap(find.text('杂合自交 9331'));
    await t.pumpAndSettle();
    // 切到板书视图
    await t.tap(find.text('板书'));
    await t.pumpAndSettle();
    // 放映按钮出现
    expect(find.text('放映'), findsOneWidget);
    await t.tap(find.text('放映'));
    await t.pumpAndSettle();
    // 全屏放映打开：棋盘 + 退出按钮
    expect(find.textContaining('表型比'), findsWidgets);
    expect(find.byTooltip('退出放映'), findsOneWidget);
    // 退出
    await t.tap(find.byTooltip('退出放映'));
    await t.pumpAndSettle();
    expect(find.byTooltip('退出放映'), findsNothing);
    // 页面恢复原状
    expect(find.text('遗传计算器'), findsOneWidget);
  });
}
