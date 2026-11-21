// molecular_label_material_split_test.dart —— v2.19.50 半保留复制两节「连坐」修复守卫网
//
// 病灶（与 B 仓 v2.19.166 同源，本仓 molecular_page._calcLabel 同款）：
// `dnaLabelReplication` 允许 n ≤ 40，`replicationMaterial` 只允许 n ≤ 30。
// 学生填 n ∈ [31,40] 且填了 m 时：标记分布**算得出且合法**；原料抛错。
// 旧代码两个调用共用一个 try ⇒ 原料的错把标记分布的合法答案一起清空，
// 屏上还显示一句「复制代数过大（≤30）」——那句限制对标记分布根本不适用。
//
// 判据不写死 35 当魔法数：用例里先各断一次引擎约束（缝隙驱动），
// 哪天引擎改了上限，这条测试先红在前提、而不是继续绿。
import 'package:biology/engine/dna_strand_engine.dart';
import 'package:biology/pages/molecular_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('N6 半保留复制：两节上限不同，一节失败不得连坐另一节', () {
    // 缝隙：标记分布允许 n ∈ [1,40]；原料只允许 n ∈ [1,30] ⇒ 冲突窗 [31,40]。
    const nInGap = 35;

    Future<void> gotoLabelTab(WidgetTester tester) async {
      await tester.tap(find.descendant(
          of: find.byType(TabBar), matching: find.text('复制与标记')));
      await tester.pumpAndSettle();
      expect(
          find.descendant(
              of: find.byType(TabBar), matching: find.text('复制与标记')),
          findsOneWidget,
          reason: '前提：TabBar 上有「复制与标记」');
    }

    Future<void> fillLabelInputs(WidgetTester tester,
        {required String n, String? m}) async {
      final fN = find.widgetWithText(TextField, '复制代数 n（标记分布用）');
      expect(fN, findsOneWidget, reason: '前提：页面上恰好一个「复制代数 n（标记分布用）」输入框');
      await tester.ensureVisible(fN);
      await tester.pump();
      await tester.enterText(fN, n);
      if (m != null) {
        final fM =
            find.widgetWithText(TextField, '每分子某碱基含量 m（可留空跳过原料）');
        expect(fM, findsOneWidget, reason: '前提：页面上恰好一个「每分子 m」输入框');
        await tester.ensureVisible(fM);
        await tester.pump();
        await tester.enterText(fM, m);
      }
      await tester.pump();
    }

    testWidgets(
        'n=35 合法于标记分布、越界于原料 ⇒ 标记分布照常出结果，原料自己报自己的错，'
        '⛔ 标记分布的结果不许被连坐清空', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: MolecularPage()));
      await tester.pump();
      // 前提硬断言：n 落在两节上限的缝隙里（引擎约束各断一次）。
      expect(() => dnaLabelReplication(generations: nInGap), returnsNormally,
          reason: '前提：$nInGap 对标记分布必须是合法的');
      expect(() => replicationMaterial(generations: nInGap, perMolecule: 100),
          throwsArgumentError,
          reason: '前提：$nInGap 对原料必须是越界的');

      await gotoLabelTab(tester);
      await fillLabelInputs(tester, n: '$nInGap', m: '100');
      final cta = find.text('计算标记分布');
      expect(cta, findsOneWidget, reason: '前提：整页恰好一个「计算标记分布」按钮');
      // ⚠️ 打空前先滚进可点区域：tap 打空默认只 warning 不 fail，
      // 那正是这病当初「看起来没问题」的形态。
      await tester.ensureVisible(cta);
      await tester.pump();
      await tester.tap(cta);
      await tester.pumpAndSettle();

      // ① 标记分布的合法结果必须在屏上：2^35 = 34359738368。
      expect(find.textContaining('34359738368'), findsWidgets,
          reason: '⛔ 标记分布对 n=35 完全合法，屏上必须有它的结果'
              '（旧代码会被原料的越界连坐清空）');
      // ② 原料自己的越界说明必须出现。
      expect(find.textContaining('复制代数过大（≤30）'), findsOneWidget,
          reason: '原料那节必须报自己的限制，且印在原料旁边');
      // ③ ⛔ 标记分布那节的错误位不许出现——它没越界。
      expect(find.textContaining('复制代数过大（≤40）'), findsNothing,
          reason: '⛔ 标记分布没越界，它的错误位必须是空的');
    });

    testWidgets('m 被清空 ⇒ 原料按「可留空跳过原料」静默不画，标记分布照常出结果',
        (tester) async {
      await tester.pumpWidget(const MaterialApp(home: MolecularPage()));
      await tester.pump();
      // ⚠️ 前提：`_matCtrl` 出厂值是 '100' ⇒ 「留空」必须主动清空，
      // 且 enterText 之后回读 controller 确认，不能只看「没报错」。
      await gotoLabelTab(tester);
      await fillLabelInputs(tester, n: '$nInGap', m: '');
      final fM = find.widgetWithText(TextField, '每分子某碱基含量 m（可留空跳过原料）');
      expect(tester.widget<TextField>(fM).controller?.text, isEmpty,
          reason: '前提：m 输入框此刻确实是空的（出厂值是 100）');
      final cta = find.text('计算标记分布');
      expect(cta, findsOneWidget);
      await tester.ensureVisible(cta);
      await tester.pump();
      await tester.tap(cta);
      await tester.pumpAndSettle();
      expect(find.textContaining('34359738368'), findsWidgets,
          reason: 'm 清空是合法用法（输入框就写着「可留空跳过原料」）');
      expect(find.textContaining('复制代数过大'), findsNothing,
          reason: '⛔ m 为空时原料压根没参与计算，不该产生任何越界说明');
    });
  });
}
