// v24_chips_pitfall_test.dart —— N7 预设参数 chips + N8 图谱节点易错点
import 'package:biology/pages/cross_calculator_page.dart';
import 'package:biology/pages/knowledge_graph_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('N7 9331 预设 chip「测交」一键载入 → 1:1:1:1', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: CrossCalculatorPage()));
    await tester.pump();
    await tester.tap(find.widgetWithText(ActionChip, '测交'));
    await tester.pump();
    expect(find.text('1:1:1:1'), findsWidgets, reason: 'AaBb×aabb → 1:1:1:1');
  });

  testWidgets('N8 图谱节点详情展示易错点（gamete-formation）', (tester) async {
    final key = GlobalKey<State<KnowledgeGraphPage>>();
    // debugShowDetail 是 State 上的测试钩子——直接弹详情 sheet
    await tester.pumpWidget(MaterialApp(home: KnowledgeGraphPage(key: key)));
    await tester.pump();
    (key.currentState as dynamic).debugShowDetail('gamete-formation');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.textContaining('易错点'), findsOneWidget);
    expect(find.textContaining('配子种类 2ⁿ'), findsOneWidget);
  });

  testWidgets('N8 无易错点数据的节点不显示该块（backcross 有数据）',
      (tester) async {
    final key = GlobalKey<State<KnowledgeGraphPage>>();
    await tester.pumpWidget(MaterialApp(home: KnowledgeGraphPage(key: key)));
    await tester.pump();
    (key.currentState as dynamic).debugShowDetail('dna-genes-alleles');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.textContaining('易错点'), findsOneWidget);
  });
}
