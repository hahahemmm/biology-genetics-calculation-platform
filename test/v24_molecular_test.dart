// v24_molecular_test.dart —— N2 复制原料计算 + N5 中心法则互推（v2.4 题型能力建设）
import 'package:biology/engine/dna_strand_engine.dart';
import 'package:biology/pages/molecular_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('N5 中心法则互推引擎', () {
    test('模板链 TACGGATTA → 编码链/mRNA/密码子/反密码子', () {
      final r = centralDogmaFromTemplate('TACGGATTA');
      expect(r.coding, 'ATGCCTAAT');
      expect(r.mrna, 'AUGCCUAAU');
      expect(r.codons, ['AUG', 'CCU', 'AAU']);
      expect(r.anticodons, ['UAC', 'GGA', 'UUA'],
          reason: '反密码子与密码子 RNA 体系互补（A↔U、C↔G）');
    });

    test('经典起始密码子：模板 TAC → mRNA AUG → 反密码子 UAC', () {
      final r = centralDogmaFromTemplate('TAC');
      expect(r.mrna, 'AUG');
      expect(r.anticodons.single, 'UAC');
    });

    test('非法输入：非 ATCG / 长度非 3 倍数 / 超长', () {
      expect(() => centralDogmaFromTemplate('TAX'), throwsArgumentError);
      expect(() => centralDogmaFromTemplate('TACG'), throwsArgumentError);
      expect(
          () => centralDogmaFromTemplate('TAC' * 11), throwsArgumentError);
    });
  });

  group('N2 复制原料公式化入口（页面）', () {
    testWidgets('分子页复制原料卡：m=100 n=3 → 共需 700 / 第 3 次 400',
        (tester) async {
      await tester.pumpWidget(const MaterialApp(home: MolecularPage()));
      await tester.pump();
      await tester.scrollUntilVisible(
        find.text('DNA 复制原料计算'),
        160,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pump();
      await tester.tap(find.text('计算原料需求'));
      await tester.pump();
      expect(find.textContaining('共需 700 个'), findsOneWidget,
          reason: '(2³−1)×100=700');
      expect(find.textContaining('第 3 次需 400 个'), findsOneWidget,
          reason: '2²×100=400');
    });

    testWidgets('中心法则卡：示例 chip 一键推出各链', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: MolecularPage()));
      await tester.pump();
      await tester.scrollUntilVisible(
        find.text('中心法则互推（模板链→mRNA→反密码子）'),
        160,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pump();
      await tester.tap(find.text('示例 TACGGATTA'));
      await tester.pump();
      // v2.19.46：错因对照 caption 也含「UAC  GGA  UUA」（忘了互补的错误密码子），
      //    与正确的反密码子串撞车。精确锚「反密码子：」前缀（错因对照无此前缀）。
      expect(find.textContaining('密码子：AUG  CCU  AAU'), findsOneWidget);
      expect(find.textContaining('反密码子：UAC  GGA  UUA'), findsOneWidget);
    });
  });
}
