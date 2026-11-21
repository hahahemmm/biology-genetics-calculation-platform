// reverse_engine_test.dart —— 反推引擎：后代比例 → 候选亲本组合
import 'package:biology/engine/reverse_engine.dart';
import 'package:biology/pages/cross_calculator_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final eng = ReverseEngine();

  group('parseRatio', () {
    test('常规与全角冒号', () {
      expect(ReverseEngine.parseRatio('3:1').toString(), '3:1');
      expect(ReverseEngine.parseRatio('9：3：3：1').toString(), '9:3:3:1');
      expect(ReverseEngine.parseRatio(' 12 : 3 : 1 ').toString(), '12:3:1');
    });

    test('非法输入抛 ArgumentError', () {
      expect(() => ReverseEngine.parseRatio('abc'), throwsArgumentError);
      expect(() => ReverseEngine.parseRatio(''), throwsArgumentError);
    });
  });

  group('一对基因反推', () {
    test('3:1 → Aa 自交', () {
      final ms = eng.inferParents('3:1', loci: 1);
      expect(ms.length, 1);
      expect(ms.first.p1, 'Aa');
      expect(ms.first.p2, 'Aa');
      expect(ms.first.note, '自交');
    });

    test('1:1 → Aa×aa 测交', () {
      final ms = eng.inferParents('1:1', loci: 1);
      expect(ms.length, 1);
      final pair = [ms.first.p1, ms.first.p2]..sort();
      expect(pair.join('×'), 'Aa×aa');
      expect(ms.first.note, contains('测交'));
    });

    test('1（全显性）→ 多解候选（教学价值：列全）', () {
      final ms = eng.inferParents('1', loci: 1);
      // AA×AA / AA×Aa / AA×aa 等全部后代显性
      expect(ms.length, greaterThanOrEqualTo(3));
      expect(ms.any((m) => m.p1 == 'AA' && m.p2 == 'AA'), isTrue);
    });
  });

  group('两对基因反推', () {
    test('9:3:3:1 → AaBb 自交', () {
      final ms = eng.inferParents('9:3:3:1', loci: 2);
      expect(ms.length, 1);
      expect(ms.first.p1, 'AaBb');
      expect(ms.first.p2, 'AaBb');
      expect(ms.first.note, '自交');
    });

    test('1:1:1:1 → AaBb×aabb 测交 + Aabb×aaBb 双单杂合（两解均合法）', () {
      final ms = eng.inferParents('1:1:1:1', loci: 2);
      expect(ms.length, 2);
      String key(ReverseMatch m) => ([m.p1, m.p2]..sort()).join('×');
      // 测交解排最前（排序约定）
      expect(key(ms.first), 'AaBb×aabb');
      expect(ms.first.note, contains('测交'));
      expect(ms.any((m) => key(m) == 'Aabb×aaBb'), isTrue,
          reason: '两对基因各杂一对的组合同样产 1:1:1:1，是多解教学点');
    });

    test('9:7 → AaBb 自交（互补变式）', () {
      final ms = eng.inferParents('9:7', loci: 2);
      expect(ms.length, 1);
      expect(ms.first.p1, 'AaBb');
      expect(ms.first.note, contains('9:7'));
    });

    test('15:1 → AaBb 自交（显性叠加）', () {
      final ms = eng.inferParents('15:1', loci: 2);
      expect(ms.length, 1);
      expect(ms.first.note, contains('15:1'));
    });

    test('9:3:4 → AaBb 自交（隐性上位）', () {
      final ms = eng.inferParents('9:3:4', loci: 2);
      expect(ms.length, 1);
      expect(ms.first.note, contains('9:3:4'));
    });

    test('3:1 自动模式 → 一对 Aa 自交为主解', () {
      final ms = eng.inferParents('3:1');
      expect(ms.any((m) => m.p1 == 'Aa' && m.p2 == 'Aa'), isTrue);
    });

    test('1:1:1:1 自动模式 → AaBb×aabb', () {
      final ms = eng.inferParents('1:1:1:1');
      expect(ms.any((m) {
        final pair = [m.p1, m.p2]..sort();
        return pair.join('×') == 'AaBb×aabb';
      }), isTrue);
    });
  });

  group('9331 反推 UI', () {
    testWidgets('点 9:7 预设 chip → 列出 AaBb×AaBb', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: CrossCalculatorPage()));
      await tester.pump();
      await tester.scrollUntilVisible(
        find.text('反推：由后代比例推亲本'),
        120,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pump();
      // 变式速查列表里也有「9:7」文本（RatioPill），必须精确到 ActionChip
      await tester.tap(find.widgetWithText(ActionChip, '9:7'));
      await tester.pump();
      expect(find.textContaining('AaBb × AaBb'), findsWidgets,
          reason: '9:7 互补变式反推出 AaBb 自交（诊断卡说明文字也含该串）');
      expect(find.textContaining('共 1 组候选亲本'), findsOneWidget);
    });
  });
}
