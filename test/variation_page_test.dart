// variation_page_test.dart —— 变异页 widget 冒烟（课标 3.3.1/3.3.4/3.3.5）
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:biology/pages/variation_page.dart';

/// ListView 惰性构建：先滚到树中，再 ensureVisible 拉进视口（缓存区
/// 内的元素树中存在但不可点）。返回后目标保证 hit-testable。
Future<void> _reveal(WidgetTester tester, Finder finder) async {
  // v2.19.28 工作台化：骨架滚动载体是 Scrollable（宽态左栏 + 右区/
  // 窄态整页均为 SingleChildScrollView），不再特判 ListView。
  for (var i = 0; i < 14 && finder.evaluate().isEmpty; i++) {
    final scrollable = find.byType(Scrollable);
    if (scrollable.evaluate().isEmpty) break;
    await tester.drag(scrollable.first, const Offset(0, -160));
    await tester.pumpAndSettle();
  }
  if (finder.evaluate().isNotEmpty) {
    await tester.ensureVisible(finder.first);
    await tester.pumpAndSettle();
  }
  expect(finder, findsWidgets, reason: '滚动后目标应可见');
}

void main() {
  testWidgets('基因突变模拟：默认 ATGCCGTA + 模拟突变 → 原序列/突变后序列',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(home: VariationPage()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('模拟突变'));
    await tester.pumpAndSettle();
    expect(find.text('原序列'), findsOneWidget, reason: '结果卡出现原序列');
    expect(find.text('突变后序列'), findsOneWidget, reason: '结果卡出现突变后序列');
    expect(find.textContaining('可能改变氨基酸'), findsOneWidget,
        reason: '替换非 G 后原密码子 ATG 改变');
  });

  testWidgets('染色体组数判断：输入 AAAaBBbb → 4 个染色体组', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: VariationPage()));
    await tester.pumpAndSettle();
    // v2.19.28 工作台化：组数判断在「染色体组数」tab（index 1）。
    await tester.tap(find.text('染色体组数'));
    await tester.pumpAndSettle();
    final field = find.byKey(const Key('genotypeField'));
    await _reveal(tester, field);
    await tester.enterText(field, 'AAAaBBbb');
    await tester.tap(find.text('判断染色体组数'));
    await tester.pumpAndSettle();
    await _reveal(tester, find.textContaining('4 个染色体组'));
    expect(find.textContaining('4 个染色体组'), findsOneWidget);
  });

  testWidgets('育种方法对照：滚动后杂交/单倍体育种可见', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: VariationPage()));
    await tester.pumpAndSettle();
    // v2.19.28 工作台化：育种对照在「诱变与育种」tab（index 3）。
    await tester.tap(find.text('诱变与育种'));
    await tester.pumpAndSettle();
    await _reveal(tester, find.text('杂交育种'));
    expect(find.text('杂交育种'), findsWidgets);
    await _reveal(tester, find.text('单倍体育种'));
    expect(find.text('单倍体育种'), findsWidgets);
    await _reveal(tester, find.text('多倍体育种'));
    expect(find.text('多倍体育种'), findsWidgets);
  });
}