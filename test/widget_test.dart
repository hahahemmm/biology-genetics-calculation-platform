// 遗传引擎单元测试：验证杂交、9331、测交、系谱、判题等核心逻辑。
import 'package:flutter_test/flutter_test.dart';

import 'package:biology/engine/cross_engine.dart';
import 'package:biology/engine/kaoji_calc.dart';
import 'package:biology/engine/pedigree.dart';
import 'package:biology/engine/pedigree_engine.dart';
import 'package:biology/engine/knowledge_graph.dart';
import 'package:biology/engine/models.dart';

void main() {
  group('杂交引擎', () {
    test('单基因 Aa×Aa → 表型 3:1', () {
      final r = CrossEngine().singleGeneCross(
          'Aa', 'Aa', dominant: 'A', recessive: 'a');
      expect(r.phenotypeRatios.map((e) => e.count).join(':'), '3:1');
    });

    test('双基因 AaBb×AaBb → 表型 9:3:3:1', () {
      final r = CrossEngine().dihybridCross(
        'AaBb', 'AaBb',
        locus1Dominant: 'A',
        locus1Recessive: 'a',
        locus2Dominant: 'B',
        locus2Recessive: 'b',
      );
      final ratio = Ratio(r.phenotypeRatios.map((e) => e.count).toList())
          .reduced()
          .toString();
      expect(ratio, '9:3:3:1');
    });

    test('测交 AaBb×aabb → 1:1:1:1', () {
      final r = CrossEngine().dihybridCross(
        'AaBb', 'aabb',
        locus1Dominant: 'A',
        locus1Recessive: 'a',
        locus2Dominant: 'B',
        locus2Recessive: 'b',
      );
      final ratio = Ratio(r.phenotypeRatios.map((e) => e.count).toList())
          .reduced()
          .toString();
      expect(ratio, '1:1:1:1');
    });
  });

  group('9331 计算器', () {
    test('常见变式比例', () {
      final k = KaojiCalc();
      expect(k.variantRatio('9331').toString(), '9:3:3:1');
      expect(k.variantRatio('9_7').toString(), '9:7');
      expect(k.variantRatio('9_3_4').toString(), '9:3:4');
      expect(k.variantRatio('15_1').toString(), '15:1');
      expect(k.variantRatio('1_4_6_4_1').toString(), '1:4:6:4:1');
    });
  });

  group('系谱', () {
    test('AR Aa×Aa → 1/4', () {
      expect(
        (Pedigree().autosomalRecessiveRisk('Aa', 'Aa') - 0.25).abs() < 1e-9,
        isTrue,
      );
    });
    test('XR 母亲 XaXa × 父亲 XAY → 儿子全患病', () {
      expect(
        (Pedigree().xLinkedRecessiveRisk('XaXa', 'XAY') - 1.0).abs() < 1e-9,
        isTrue,
      );
    });
  });

  group('知识图谱', () {
    test('节点数 >= 15 且含 9331', () {
      expect(defaultKnowledgeGraph.nodeCount, greaterThanOrEqualTo(15));
      expect(defaultKnowledgeGraph.nodeById('9331'), isNotNull);
    });
  });

  group('遗传计算引擎', () {
    test('Aa 配子 2 种', () {
      expect(PedigreeEngine().gametesOf('Aa').length, 2);
    });
    test('AABB × aabb → 后代为 AaBb', () {
      expect(
        PedigreeEngine().cross('AABB', 'aabb').containsKey('AaBb'),
        isTrue,
      );
    });
    test('AaBb × AaBb 表型 4 种且双显约 9/16', () {
      final e = PedigreeEngine();
      final ph = e.phenotypesOf(e.cross('AaBb', 'AaBb'));
      expect(ph.length, 4);
      double maxP = 0;
      ph.forEach((k, v) {
        if (v > maxP) maxP = v;
      });
      expect((maxP - 0.5625).abs(), lessThan(0.005));
    });
    test('F1 自交传播到 F2 表型 4 种', () {
      final e = PedigreeEngine();
      final f1 = e.cross('AaBb', 'AaBb');
      final f2 = <String, double>{};
      f1.forEach((gen, prob) {
        e.cross(gen, gen).forEach((c2, p2) {
          f2[c2] = (f2[c2] ?? 0) + prob * p2;
        });
      });
      final tot = f2.values.fold(0.0, (a, b) => a + b);
      f2.updateAll((k, v) => v / tot);
      expect(e.phenotypesOf(f2).length, 4);
    });
  });
}
