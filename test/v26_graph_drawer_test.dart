// v26_graph_drawer_test.dart —— v2.6 ☰ 图谱工具抽屉验收
//
// ☰ 死按钮修复：有 HomeShell 注入时打开本页工具抽屉
// （节点索引 / 搜索 / 易错点筛选 / 画布定位 + 详情），独立构造照旧不渲染。
// 抽屉状态全部内聚在抽屉自己的 State 里（DrawerController 关抽屉只
// deactivate 不 dispose，若读页面层可变状态重开会显示旧值——本实现
// 不读页面层状态，天然规避；测试含「关→改页面状态→重开」用例兜底）。

import 'package:biology/pages/knowledge_graph_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> pumpPage(WidgetTester t, {VoidCallback? onNavPressed}) async {
    // 大视口：抽屉 320 + 画布并排不挤。
    t.view.physicalSize = const Size(1400, 900);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    await t.pumpWidget(
        MaterialApp(home: KnowledgeGraphPage(onNavPressed: onNavPressed)));
    await t.pumpAndSettle();
  }

  Future<void> openDrawer(WidgetTester t) async {
    await t.tap(find.byIcon(Icons.menu));
    await t.pumpAndSettle();
  }

  testWidgets('独立构造（onNavPressed=null）不渲染 ☰ 也无抽屉', (t) async {
    await pumpPage(t);
    expect(find.byIcon(Icons.menu), findsNothing);
    expect(find.byType(Drawer), findsNothing);
  });

  testWidgets('☰ 打开抽屉 → 搜索过滤 → 点节点：关抽屉 + 画布定位 + 详情弹出',
      (t) async {
    await pumpPage(t, onNavPressed: () {});
    // 默认抽屉关闭（页面零变化）
    expect(find.text('图谱工具'), findsNothing);

    await openDrawer(t);
    expect(find.text('图谱工具'), findsOneWidget);

    // 抽屉内搜索（页面主搜索框并存，用抽屉 hint 定位）
    await t.enterText(
        find.widgetWithText(TextField, '搜索节点标题或标签'), '测交');
    await t.pumpAndSettle();
    expect(find.text('测交（testcross）'), findsOneWidget);
    expect(find.text('伴性遗传'), findsNothing, reason: '搜索应过滤掉不匹配节点');

    // 点节点 → 抽屉关闭 + 画布变换 + 详情 sheet 弹出
    final state = t.state(find.byType(KnowledgeGraphPage)) as dynamic;
    final before = state.debugViewTransform as Matrix4;
    await t.tap(find.text('测交（testcross）'));
    await t.pumpAndSettle();
    expect(find.text('图谱工具'), findsNothing, reason: '点节点后抽屉应关闭');
    final after = state.debugViewTransform as Matrix4;
    expect(after == before, isFalse, reason: '点节点后画布应平移居中到该节点');
    expect(find.textContaining('测交的目的是检验'), findsOneWidget,
        reason: '详情 sheet 应弹出并带易错点内容');
  });

  testWidgets('「只看易错点」开关生效，节点带易错点标记', (t) async {
    await pumpPage(t, onNavPressed: () {});
    await openDrawer(t);
    // 易错点标记图标（当前 19 个节点全部有易错点条目）
    expect(find.byIcon(Icons.warning_amber_rounded), findsWidgets);
    expect(find.byType(Switch), findsOneWidget);
    expect(t.widget<Switch>(find.byType(Switch)).value, isFalse);
    await t.tap(find.byType(Switch));
    await t.pumpAndSettle();
    expect(t.widget<Switch>(find.byType(Switch)).value, isTrue);
    // 开关 + 搜索组合：过滤仍按标题/tags 命中
    await t.enterText(
        find.widgetWithText(TextField, '搜索节点标题或标签'), '致死');
    await t.pumpAndSettle();
    expect(find.text('致死基因'), findsOneWidget);
    expect(find.text('测交（testcross）'), findsNothing);
  });

  testWidgets('关抽屉 → 改页面搜索 → 重开：抽屉自身状态不读页面层、不错位',
      (t) async {
    await pumpPage(t, onNavPressed: () {});
    await openDrawer(t);
    await t.enterText(
        find.widgetWithText(TextField, '搜索节点标题或标签'), '9331');
    await t.pumpAndSettle();
    expect(find.text('9331 及其变式'), findsOneWidget);

    // 关抽屉（点抽屉外空白）
    await t.tapAt(const Offset(1100, 450));
    await t.pumpAndSettle();
    expect(find.text('图谱工具'), findsNothing);

    // 改页面层状态：主搜索框输入（页面画布重排）
    await t.enterText(
        find.widgetWithText(TextField, '搜索知识点（如 分离、9331、伴性、测交）'),
        '伴性');
    await t.pumpAndSettle();

    // 重开抽屉：抽屉内部状态（搜索词 9331）自然保留，不受页面 _query 影响
    await openDrawer(t);
    expect(find.text('图谱工具'), findsOneWidget);
    expect(find.text('9331 及其变式'), findsOneWidget);
    expect(find.text('伴性遗传'), findsNothing,
        reason: '抽屉搜索词是抽屉自己的状态，不读页面层 _query');
  });

  testWidgets('抽屉底部「考点速查」入口：关抽屉并弹考点 sheet', (t) async {
    await pumpPage(t, onNavPressed: () {});
    await openDrawer(t);
    await t.tap(find.text('考点速查').last);
    await t.pumpAndSettle();
    expect(find.text('图谱工具'), findsNothing, reason: '入口点击后抽屉应关闭');
    // 考点 sheet 弹出（含其搜索框）
    expect(
        find.widgetWithText(TextField, '搜索考点（如 致死、连锁、9:7）'),
        findsOneWidget);
  });
}
