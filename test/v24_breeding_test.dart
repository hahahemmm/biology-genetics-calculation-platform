// v24_breeding_test.dart —— N3 杂交育种流程 + N4 豆子模型预设（v2.4）
import 'package:biology/engine/ploidy_engine.dart';
import 'package:biology/pages/evolution_page.dart';
import 'package:biology/pages/ploidy_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('N3 hybridBreeding 引擎', () {
    test('AaBb → AABB：分离世代 9/16 目标表型、1/16 纯合，需连续自交纯化',
        () {
      final r = hybridBreeding('AaBb', 'AABB');
      expect(r.segregatingTotal, 16);
      expect(r.targetPhenotypeCount, 9);
      expect(r.targetPureCount, 1);
      expect(r.pureAtSelection, isFalse);
      expect(r.selfingGenerations, greaterThanOrEqualTo(5),
          reason: '两位点纯化到 99% 需多代');
      expect(r.pureRateAfterN, greaterThanOrEqualTo(0.99));
      expect(r.estimatedYears, 1 + r.selfingGenerations);
    });

    test('AaBb → aabb：目标全隐性，选出即纯合（0 代再自交）', () {
      final r = hybridBreeding('AaBb', 'aabb');
      expect(r.pureAtSelection, isTrue);
      expect(r.selfingGenerations, 0);
      expect(r.estimatedYears, 1);
      expect(r.targetPhenotypeCount, 1);
      expect(r.targetPureCount, 1);
    });

    test('Aa → Aa 目标非纯合抛错；位点字母不一致抛错；亲本不含目标等位抛错',
        () {
      expect(() => hybridBreeding('AaBb', 'AaBB'), throwsArgumentError);
      expect(() => hybridBreeding('AaBb', 'CCBB'), throwsArgumentError);
      expect(() => hybridBreeding('AA', 'aa'), throwsArgumentError);
    });

    test('单基因 Aa → AA：分离世代 3/4 表型、1/4 纯合', () {
      final r = hybridBreeding('Aa', 'AA');
      expect(r.segregatingTotal, 4);
      expect(r.targetPhenotypeCount, 3);
      expect(r.targetPureCount, 1);
      expect(r.pureAtSelection, isFalse);
    });
  });

  group('N3/N4 页面', () {
    testWidgets('倍性页杂交育种卡：AaBb→AABB 推算出流程链', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: PloidyPage()));
      await tester.pump();
      // v2.19.21 工作台化：杂交育种流程在「育种应用」tab
      await tester.tap(find.text('育种应用'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('杂交育种流程'),
        160,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pump();
      await tester.tap(find.text('推算育种流程'));
      await tester.pump();
      expect(find.textContaining('基因型 9 种'), findsOneWidget);
      expect(find.textContaining('连续自交'), findsWidgets);
    });

    testWidgets('进化页豆子模型预设：点 30/60/10 一键载入并计算',
        (tester) async {
      await tester.pumpWidget(const MaterialApp(home: EvolutionPage()));
      await tester.pump();
      // v2.19.21 工作台化：基因频率计算在「基因频率」tab
      await tester.tap(find.text('基因频率'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('预设 30/60/10'));
      await tester.pump();
      // 预设 30/60/10 → aa=30/Aa=60/AA=10 → A=(2×10+60)/200=40%
      expect(find.textContaining('A = 40.0%'), findsWidgets,
          reason: '一键载入后自动计算出基因频率结果');
    });
  });
}
