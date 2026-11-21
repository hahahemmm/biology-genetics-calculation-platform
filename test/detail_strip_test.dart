// detail_strip_test.dart —— v2.2 遗传图谱元素详情面板重构验收
//
// 用户痛点：①概率/性别/世代/家族等信息项挤在基因型下方单列，面板
// 右侧大片空白，需滚动才能看全；②「收回连线」只有长按节点一个入口，
// 隐蔽难用。
// 修复：宽屏左右两列（信息项网格填入基因型右侧空白）；标题行新增
// 「取消连线」按钮（常开可点，无连线时 toast 引导）。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:biology/engine/pedigree_graph.dart';
import 'package:biology/pages/genetic_pedigree_page.dart';
import 'package:biology/pages/widgets/pedigree_canvas.dart';

void main() {
  Future<void> pumpWide(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1000, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const MaterialApp(home: GeneticPedigreePage()));
    await tester.pumpAndSettle();
  }

  PedigreeCanvas canvas(WidgetTester tester) =>
      tester.widget<PedigreeCanvas>(find.byType(PedigreeCanvas));

  Future<void> derive(WidgetTester tester) async {
    await tester.tap(find.text('计算').first);
    await tester.pumpAndSettle();
    expect(find.byType(PedigreeCanvas), findsOneWidget);
  }

  testWidgets('详情面板：取消连线按钮常驻标题行；信息项无需滚动全可见',
      (tester) async {
    await pumpWide(tester);
    await derive(tester);

    // 选中 F1 节点（组合桶，点父桶 id）
    final c = canvas(tester);
    final f1 = c.nodes.firstWhere((n) => n.generation == 1);
    c.onNodeTap!(f1);
    await tester.pumpAndSettle();

    // ① 标题行三个操作按钮齐全（导入 9331 / 取消连线 / 删除）
    expect(find.text('导入 9331'), findsOneWidget);
    expect(find.text('取消连线'), findsOneWidget, reason: '取消连线按钮应在详情面板标题行');
    expect(find.text('删除'), findsOneWidget);

    // ② 信息项一屏全显：概率/性别/世代/连线/来源都在且无滚动需求
    for (final label in ['概率', '性别', '世代', '连线', '来源']) {
      expect(find.textContaining(label), findsWidgets,
          reason: '$label 应在信息面板可见');
    }

    // ③ 宽屏两列布局：信息项在基因型块右侧（利用原空白区）。
    // 限定 Text widget：杂交面板 cross panel 的亲本 1 EditableText 也含
    // "AaBbCc"（_autoFillFromTap 在 browse 模式选节点时自动填入），
    // 不限定会导致 getRect ambiguous 错误。用 widgetPredicate 只匹配
    // Text 类型，不匹配 EditableText。
    final genoFinder = find.byWidgetPredicate(
        (w) => w is Text && w.data == f1.genotype, description: 'geneText');
    final probFinder = find.byWidgetPredicate(
        (w) => w is Text && (w.data ?? '').startsWith('概率'),
        description: 'probText');
    final genoRect = tester.getRect(genoFinder);
    final probRect = tester.getRect(probFinder.first);
    expect(probRect.left, greaterThan(genoRect.right - 1),
        reason: '宽屏下信息项应排在基因型块右侧空白区，而非挤在下方');

    // ④ 无连线时点「取消连线」→ toast 引导（不崩不静默）
    await tester.tap(find.text('取消连线'));
    await tester.pumpAndSettle();
    expect(find.text('该节点没有可收回的连线。'), findsOneWidget);
  });

  testWidgets('取消连线按钮收回连线：连线数 1→0', (tester) async {
    await pumpWide(tester);
    await derive(tester);

    // 连线模式：选 F1 节点 + P 代父本连线（回交）
    await tester.tap(find.widgetWithText(FilterChip, '连线'));
    await tester.pumpAndSettle();
    var c = canvas(tester);
    final f1 = c.nodes.firstWhere((n) => n.generation == 1);
    final pMale = c.nodes.firstWhere((n) =>
        n.generation == 0 && n.kind == PedigreeNodeKind.male);
    c.onNodeTap!(f1);
    await tester.pump();
    c.onNodeTap!(pMale);
    await tester.pumpAndSettle();

    // 选中 F1 查看详情：连线数 ≥1（label/value 是两个独立 Text，
    // 分开断言「连线」+「N 条」）
    c = canvas(tester);
    final f1b = c.nodes.firstWhere((n) => n.id == f1.id);
    c.onNodeTap!(f1b);
    await tester.pumpAndSettle();
    expect(find.text('连线 '), findsOneWidget, reason: '详情面板应有连线项');
    expect(find.text('0 条'), findsNothing,
        reason: '连线后详情面板应显示非零连线数');

    // 点「取消连线」→ 收回
    await tester.tap(find.text('取消连线'));
    await tester.pumpAndSettle();
    expect(find.text('已收回一条连线，点「计算」重算下游。'), findsOneWidget);
    expect(find.text('0 条'), findsOneWidget, reason: '取消连线后连线数应归零');
  });
}
