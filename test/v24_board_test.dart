// v24_board_test.dart —— N6 遗传图解板书视图（v2.4）
import 'package:biology/pages/cross_calculator_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('9331 结果卡「板书」视图：P/配子/F1 棋盘/表型比',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(home: CrossCalculatorPage()));
    await tester.pump();
    // 未计算：无结果面板
    expect(find.text('板书'), findsNothing, reason: '未计算时不显示结果面板');

    await tester.tap(find.text('计算比例'));
    await tester.pump();
    // 结果面板在屏外时先滚到可见（大批量连跑时视口可能被前序测试污染，
    // 裸 tap 会因 obscured/off-screen 打不中——实测实锤）。
    await tester.scrollUntilVisible(
      find.text('板书'),
      100,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pump();
    await tester.tap(find.text('板书'));
    await tester.pump();
    expect(find.textContaining('P：AaBb  ×  AaBb'), findsOneWidget);
    expect(find.textContaining('AABB'), findsWidgets, reason: '棋盘整式有合子');
    expect(find.textContaining('表型比：9:3:3:1'), findsOneWidget);
  });
}
