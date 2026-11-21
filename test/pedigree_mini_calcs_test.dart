// test/pedigree_mini_calcs_test.dart
//
// 杂交计算面板迷你计算器（MonoMiniCalc / LinkageMiniCalc）的输入校验与引擎联动。
// 正则与错误文案照抄 lib/pages/widgets/pedigree_mini_calcs.dart，不猜。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:biology/engine/linkage_engine.dart';
import 'package:biology/pages/widgets/pedigree_mini_calcs.dart';

void main() {
  Future<void> pumpMono(WidgetTester tester) => tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: MonoMiniCalc())),
      );

  Future<void> pumpLinkage(WidgetTester tester) => tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: LinkageMiniCalc())),
      );

  // 依次填入两个亲本字段并点「计算」。
  Future<void> calcMono(WidgetTester tester, String p1, String p2) async {
    await tester.enterText(find.byType(TextField).at(0), p1);
    await tester.enterText(find.byType(TextField).at(1), p2);
    await tester.tap(find.widgetWithText(FilledButton, '计算'));
    await tester.pump();
  }

  group('MonoMiniCalc', () {
    testWidgets('初始态：无错误也无结果', (tester) async {
      await pumpMono(tester);
      expect(find.textContaining('表型比'), findsNothing);
      expect(find.text('各 2 个字符（如 Aa / aa）'), findsNothing);
    });

    testWidgets('合法 Aa × Aa 用真实引擎算出 3:1', (tester) async {
      await pumpMono(tester);
      await calcMono(tester, 'Aa', 'Aa');
      expect(find.text('表型比 3:1'), findsOneWidget);
      expect(find.text('各 2 个字符（如 Aa / aa）'), findsNothing);
    });

    testWidgets('非法输入（空/混数字/空格/超长/符号）均被拒且文案具体', (tester) async {
      await pumpMono(tester);
      const bad = <List<String>>[
        ['', 'Aa'], // 空串
        ['A1', 'Aa'], // 字母混数字
        ['A a', 'Aa'], // 多余空格（中间）
        ['AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA', 'Aa'], // 超长串
        ['××', 'Aa'], // 只有符号
        ['Aa', 'B1'], // 第二栏同样校验
      ];
      for (final pair in bad) {
        await calcMono(tester, pair[0], pair[1]);
        expect(find.text('各 2 个字符（如 Aa / aa）'), findsOneWidget,
            reason: '输入 ${pair[0]} × ${pair[1]} 应被拒');
        expect(find.textContaining('表型比'), findsNothing,
            reason: '被拒时不得出结果');
      }
    });

    testWidgets('正则通过但引擎拒绝时透出引擎具体文案', (tester) async {
      await pumpMono(tester);
      // 'Ab' 与 'Aa' 都是 2 个字母，过正则；但倍性/位点不一致，crossAuto 拒绝。
      await calcMono(tester, 'Ab', 'Aa');
      expect(find.text('两个亲本的位点数与倍性须一致（如 AaBb × AaBb）'),
          findsOneWidget);
      expect(find.textContaining('表型比'), findsNothing);
    });

    testWidgets('改正后重算：错误消失并显示结果', (tester) async {
      await pumpMono(tester);
      await calcMono(tester, 'A1', 'Aa');
      expect(find.text('各 2 个字符（如 Aa / aa）'), findsOneWidget);
      await calcMono(tester, 'aa', 'Aa');
      expect(find.text('各 2 个字符（如 Aa / aa）'), findsNothing);
      expect(find.text('表型比 1:1'), findsOneWidget);
    });

    testWidgets('边界：多对基因 AaBb 被 2 字符正则挡下', (tester) async {
      await pumpMono(tester);
      await calcMono(tester, 'AaBb', 'AaBb');
      expect(find.text('各 2 个字符（如 Aa / aa）'), findsOneWidget);
      expect(find.textContaining('表型比'), findsNothing);
    });

    testWidgets('边界：含连字符的缺失型 A- 被拒', (tester) async {
      await pumpMono(tester);
      await calcMono(tester, 'A-', 'Aa');
      expect(find.text('各 2 个字符（如 Aa / aa）'), findsOneWidget);
      expect(find.textContaining('表型比'), findsNothing);
    });
  });

  group('LinkageMiniCalc', () {
    testWidgets('默认值点计算得 4:4:1:1，初始无结果', (tester) async {
      await pumpLinkage(tester);
      expect(find.textContaining('表型比'), findsNothing);
      await tester.tap(find.widgetWithText(FilledButton, '计算'));
      await tester.pump();
      expect(find.text('表型比 4:4:1:1'), findsOneWidget);
    });

    testWidgets('非法交换值与非法基因型文案具体', (tester) async {
      await pumpLinkage(tester);
      // 非法基因型：没有斜杠。
      await tester.enterText(find.byType(TextField).at(0), 'ABab');
      await tester.tap(find.widgetWithText(FilledButton, '计算'));
      await tester.pump();
      expect(find.text('连锁基因型应为 AB/ab 或 Ab/aB 形式：ABab'),
          findsOneWidget);
      expect(find.textContaining('表型比'), findsNothing);

      // 非法交换值：超过 1/2。
      await tester.enterText(find.byType(TextField).at(0), 'AB/ab');
      await tester.enterText(find.byType(TextField).at(2), '80%');
      await tester.tap(find.widgetWithText(FilledButton, '计算'));
      await tester.pump();
      expect(find.text('交换值须在 0 到 1/2 之间：80%'), findsOneWidget);
      expect(find.textContaining('表型比'), findsNothing);
    });

    testWidgets('边界：三位点（多对基因）成功出比；连字符单倍型被拒', (tester) async {
      await pumpLinkage(tester);
      await tester.enterText(find.byType(TextField).at(0), 'ABC/abc');
      await tester.enterText(find.byType(TextField).at(1), 'abc/abc');
      await tester.enterText(find.byType(TextField).at(2), '20%');
      await tester.tap(find.widgetWithText(FilledButton, '计算'));
      await tester.pump();
      final expected =
          LinkageEngine().cross('ABC/abc', 'abc/abc', '20%').phenotypeRatio;
      expect(find.text('表型比 ${expected.join(':')}'), findsOneWidget);

      // 含连字符的缺失型单倍型：长度就不配，引擎给具体文案。
      await tester.enterText(find.byType(TextField).at(0), 'A-B/ab');
      await tester.tap(find.widgetWithText(FilledButton, '计算'));
      await tester.pump();
      expect(
          find.text('两条染色体需含 2–3 个相同数量的位点：A-B/ab'),
          findsOneWidget);
      expect(find.textContaining('表型比'), findsNothing);
    });
  });
}
