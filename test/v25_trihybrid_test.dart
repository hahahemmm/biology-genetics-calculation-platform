// v25_trihybrid_test.dart —— 三对基因 tab（v2.5）
//
// 引擎层：crossAuto 三对基因（AaBbCc×AaBbCc → 8 配子 / 64 合子 /
// 27:9:9:9:3:3:3:1 / variantName；AaBbCc×aabbcc → 1:1:…:1）。
// Widget 层：切到「三对基因」tab → 预设 chip 一键计算 → 断言比例出现；
// 课堂模式 ×1.3 下 64 格板书靠横向滚动消化，不得 overflow。
import 'package:biology/engine/kaoji_calc.dart';
import 'package:biology/pages/cross_calculator_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('crossAuto 三对基因（引擎层）', () {
    final calc = KaojiCalc();

    int sumParts(List<int> parts) => parts.fold(0, (a, b) => a + b);

    test('AaBbCc×AaBbCc → 配子各 8，表型比 27:9:9:9:3:3:3:1，基因型总和 64', () {
      final r = calc.crossAuto(p1: 'AaBbCc', p2: 'AaBbCc');
      expect(r.error, isNull);
      expect(r.notice, isNull);
      expect(r.ploidy, 2);
      expect(r.loci, 3);
      final res = r.result!;
      expect(res.gametesP1.length, 8, reason: '三杂合亲本配子 2^3=8 种');
      expect(res.gametesP2.length, 8);
      expect(res.phenotypeRatio.toString(), '27:9:9:9:3:3:3:1');
      expect(res.phenotypeLabels.length, 8);
      expect(sumParts(res.phenotypeRatio.parts), 64);
      expect(res.genotypeLabels.length, 27, reason: 'F2 基因型 3^3=27 种');
      expect(sumParts(res.genotypeRatio.parts), 64, reason: '基因型份数总和=64 合子');
      expect(res.variantName, '标准 27:9:9:9:3:3:3:1');
    });

    test('AaBbCc×aabbcc 测交 → 1:1:1:1:1:1:1:1，基因型 8 种各 1 份', () {
      final r = calc.crossAuto(p1: 'AaBbCc', p2: 'aabbcc');
      expect(r.error, isNull);
      final res = r.result!;
      expect(res.gametesP1.length, 8);
      expect(res.gametesP2, ['abc'], reason: '纯隐亲本只产 abc 配子');
      expect(res.phenotypeRatio.toString(), '1:1:1:1:1:1:1:1');
      expect(res.phenotypeLabels.length, 8);
      expect(res.genotypeLabels.length, 8);
      expect(sumParts(res.genotypeRatio.parts), 8);
    });
  });

  group('三对基因 tab（widget 层）', () {
    Future<void> gotoTrihybrid(WidgetTester tester) async {
      await tester.tap(find.text('三对基因'));
      await tester.pumpAndSettle();
    }

    testWidgets('预设 chip 一键计算 → 27:9:9:9:3:3:3:1', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: CrossCalculatorPage()));
      await tester.pump();
      await gotoTrihybrid(tester);

      // TabBarView 只挂载当前 tab（非 IndexedStack），切页后元素均在台上。
      expect(find.text('三杂合自交 27:9:…:1'), findsOneWidget);
      await tester.tap(find.text('三杂合自交 27:9:…:1'));
      await tester.pump();

      expect(find.text('27:9:9:9:3:3:3:1'), findsOneWidget,
          reason: '数值视图展示 F2 表型比例');
      expect(find.text('标准 27:9:9:9:3:3:3:1'), findsOneWidget,
          reason: '结果卡 variantName 角标');
      // 27 项基因型明细超过 12 项阈值 → 折叠为 ExpansionTile。
      expect(find.text('共 27 项，点开展开'), findsOneWidget);
      expect(tester.takeException(), isNull, reason: '无溢出等渲染异常');
    });

    testWidgets('课堂模式 ×1.3 下 64 格板书横向滚动消化、零溢出', (tester) async {
      await tester.pumpWidget(MediaQuery(
        data: const MediaQueryData(textScaler: TextScaler.linear(1.3)),
        child: const MaterialApp(home: CrossCalculatorPage()),
      ));
      await tester.pump();
      await gotoTrihybrid(tester);

      await tester.tap(find.text('三杂合自交 27:9:…:1'));
      await tester.pump();

      // 结果面板在屏外时先滚到可见（v24_board_test 实锤坑）。
      await tester.scrollUntilVisible(
        find.text('板书'),
        100,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pump();
      await tester.tap(find.text('板书'));
      await tester.pump();

      expect(find.textContaining('P：AaBbCc  ×  AaBbCc'), findsOneWidget);
      expect(find.textContaining('表型比：27:9:9:9:3:3:3:1'), findsOneWidget);
      expect(tester.takeException(), isNull,
          reason: '×1.3 下 8×8 棋盘靠横向滚动消化，不得报 overflow');
    });
  });
}
