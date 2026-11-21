// step_chain_integration_test.dart —— v2.2 批次4a：StepChain 接入结果区集成测试
//
// 覆盖：分子页「两链 C/T 计数互推」计算后出现推导链节点（互补配对）；
// 分子页「DNA 标记计算」计算后出现推导链节点（半保留复制）；
// 倍性页「倍性判定」计算后出现推导链节点（判定规则）。
// 纪律：屏外元素先 drag ListView 滚入树再 ensureVisible（禁 scrollUntilVisible
// 默认 scrollable —— TextField 自带 Scrollable 会撞 single；禁 .first）。

import 'package:biology/pages/molecular_page.dart';
import 'package:biology/pages/ploidy_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 滚到目标进树并拉进视口（ListView 懒挂载：先 drag 再 ensureVisible）。
/// v2.19.21：工作台化后页面主体为 SingleChildScrollView——drag 循环
/// 仅在 ListView 存在时执行（切 tab 后目标必在树中，ensureVisible 即可）。
Future<void> _reveal(WidgetTester tester, Finder finder) async {
  final listView = find.byType(ListView);
  for (var i = 0;
      i < 20 && finder.evaluate().isEmpty && listView.evaluate().isNotEmpty;
      i++) {
    await tester.drag(listView, const Offset(0, -300));
    await tester.pumpAndSettle();
  }
  expect(finder, findsOneWidget, reason: '滚动后目标应存在且唯一');
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
}

/// v2.19.21 工作台化：顶部 TabBar 切 tab。
Future<void> _switchTab(WidgetTester tester, String label) async {
  await tester.tap(find.text(label));
  await tester.pumpAndSettle();
}

void main() {
  void wideViewport(WidgetTester tester) {
    tester.view.physicalSize = const Size(1000, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  testWidgets('分子页：两链 C/T 互推计算后出现 StepChain（互补配对）',
      (tester) async {
    wideViewport(tester);
    await tester.pumpWidget(const MaterialApp(home: MolecularPage()));
    await tester.pumpAndSettle();
    expect(find.text('互补配对'), findsNothing, reason: '计算前无推导链');

    await _reveal(tester, find.text('计算全分子碱基'));
    await tester.tap(find.text('计算全分子碱基'));
    await tester.pumpAndSettle();

    expect(find.text('题干数据'), findsWidgets, reason: '推导链输入节点出现');
    expect(find.text('互补配对'), findsOneWidget, reason: '推导链中间节点出现');
    expect(find.text('全分子结果'), findsOneWidget, reason: '推导链结果节点出现');
    expect(tester.takeException(), isNull);
  });

  testWidgets('分子页：DNA 标记计算后出现 StepChain（半保留复制）',
      (tester) async {
    wideViewport(tester);
    await tester.pumpWidget(const MaterialApp(home: MolecularPage()));
    await tester.pumpAndSettle();
    // v2.19.21 工作台化：DNA 标记计算在「复制与标记」tab
    await _switchTab(tester, '复制与标记');

    await _reveal(tester, find.text('计算标记分布'));
    await tester.tap(find.text('计算标记分布'));
    await tester.pumpAndSettle();

    expect(find.text('半保留复制'), findsWidgets, reason: '推导链中间节点出现');
    expect(find.text('标记分布'), findsOneWidget, reason: '推导链结果节点出现');
    expect(tester.takeException(), isNull);
  });

  testWidgets('倍性页：倍性判定后出现 StepChain（判定规则）', (tester) async {
    wideViewport(tester);
    await tester.pumpWidget(const MaterialApp(home: PloidyPage()));
    await tester.pumpAndSettle();
    // v2.19.21 工作台化：倍性判定在「倍性与育性」tab
    await _switchTab(tester, '倍性与育性');

    await _reveal(tester, find.text('判定倍性'));
    await tester.tap(find.text('判定倍性'));
    await tester.pumpAndSettle();

    expect(find.text('判定规则'), findsOneWidget, reason: '推导链中间节点出现');
    expect(find.text('判定结果'), findsOneWidget, reason: '推导链结果节点出现');
    expect(tester.takeException(), isNull);
  });
}
