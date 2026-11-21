// v26_cross_drawer_test.dart —— v2.6 计算器页 ☰ 工具抽屉
//
// ☰ 原为死按钮（翻动的全局状态只影响系谱页）。现在开本页抽屉：
// 经典预设（一键载入对应 tab 开算）+ 计算历史（会话级，点按恢复）。

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

  Future<void> pumpPage(WidgetTester t) async {
    // v2.19.16：视口收窄到 <1200——宽屏（>=1200）时工具内容常驻
    // 左侧 CrossToolRail，☰ 抽屉不再出现（窄屏抽屉路径专用）。
    t.view.physicalSize = const Size(1000, 5000);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);
    // 模拟 HomeShell 注入 onNavPressed（独立构造不渲染 ☰，沿用该约定）
    await t.pumpWidget(MaterialApp(home: CrossCalculatorPage(onNavPressed: () {})));
    await t.pump();
  }

  testWidgets('☰ 打开工具抽屉：预设/历史区块可见', (t) async {
    await pumpPage(t);
    expect(find.byIcon(Icons.menu), findsOneWidget);
    await t.tap(find.byIcon(Icons.menu));
    await t.pumpAndSettle();
    expect(find.text('计算工具'), findsOneWidget);
    expect(find.text('经典预设（点按直接开算）'), findsOneWidget);
    expect(find.text('计算历史（本次会话）'), findsOneWidget);
    expect(find.textContaining('暂无记录'), findsOneWidget);
    // 双基因 + 三对基因预设都在
    expect(find.text('双基因 · 杂合自交 9:3:3:1'), findsOneWidget);
    expect(find.text('三对基因 · 三杂合自交 27:9:…:1'), findsOneWidget);
  });

  testWidgets('抽屉预设：点双基因测交 → 关抽屉直接出 1:1:1:1', (t) async {
    await pumpPage(t);
    await t.tap(find.byIcon(Icons.menu));
    await t.pumpAndSettle();
    await t.tap(find.text('双基因 · 测交 1:1:1:1'));
    await t.pump(); // postFrame 填参
    await t.pumpAndSettle();
    // 抽屉已关（预设按钮消失），结果已出
    expect(find.text('经典预设（点按直接开算）'), findsNothing);
    expect(find.textContaining('1:1:1:1', findRichText: true), findsWidgets);
  });

  testWidgets('抽屉预设：三对基因自动切 tab 出 27:9:…:1', (t) async {
    await pumpPage(t);
    await t.tap(find.byIcon(Icons.menu));
    await t.pumpAndSettle();
    await t.tap(find.text('三对基因 · 三杂合自交 27:9:…:1'));
    await t.pump();
    await t.pumpAndSettle();
    expect(find.textContaining('27:9:9:9:3:3:3:1', findRichText: true),
        findsWidgets);
  });

  testWidgets('计算历史：算过后进抽屉列表，点按恢复', (t) async {
    await pumpPage(t);
    // 先经抽屉算一遍测交
    await t.tap(find.byIcon(Icons.menu));
    await t.pumpAndSettle();
    await t.tap(find.text('双基因 · 测交 1:1:1:1'));
    await t.pump();
    await t.pumpAndSettle();
    // 重开抽屉：历史里应有 AaBb × aabb
    await t.tap(find.byIcon(Icons.menu));
    await t.pumpAndSettle();
    expect(find.text('AaBb × aabb'), findsOneWidget);
    expect(find.textContaining('表型比 1:1:1:1'), findsOneWidget);
    // 换成自交组合，点历史恢复测交
    await t.tap(find.text('双基因 · 杂合自交 9:3:3:1'));
    await t.pump();
    await t.pumpAndSettle();
    expect(find.textContaining('9:3:3:1', findRichText: true), findsWidgets);
    await t.tap(find.byIcon(Icons.menu));
    await t.pumpAndSettle();
    await t.tap(find.text('AaBb × aabb'));
    await t.pump();
    await t.pumpAndSettle();
    expect(find.textContaining('1:1:1:1', findRichText: true), findsWidgets);
  });

  // v2.19.16 工作台化：宽屏（>=1200）时工具内容常驻左侧 CrossToolRail，
  // ☰ 隐藏（抽屉不再配置）；预设/历史直接点侧栏。
  testWidgets('宽屏侧栏常驻：>=1200 时 rail 显示预设/历史，☰ 隐藏', (t) async {
    t.view.physicalSize = const Size(1600, 1000);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);
    await t.pumpWidget(MaterialApp(home: CrossCalculatorPage(onNavPressed: () {})));
    await t.pump();
    // ☰ 已隐藏（侧栏常驻，无抽屉入口）。
    expect(find.byIcon(Icons.menu), findsNothing);
    // 侧栏内容常驻可见。
    expect(find.text('计算工具'), findsOneWidget);
    expect(find.text('经典预设（点按直接开算）'), findsOneWidget);
    expect(find.text('计算历史（本次会话）'), findsOneWidget);
    // 点侧栏预设直接开算。
    await t.tap(find.text('双基因 · 测交 1:1:1:1'));
    await t.pump();
    await t.pumpAndSettle();
    expect(find.textContaining('1:1:1:1', findRichText: true), findsWidgets);
    // 历史进入侧栏列表。
    expect(find.text('AaBb × aabb'), findsOneWidget);
    expect(find.textContaining('表型比 1:1:1:1'), findsOneWidget);
  });
}
