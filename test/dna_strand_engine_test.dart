// dna_strand_engine_test.dart —— v2.2 批次3：DNA 单链比值/标记引擎测试
//
// 经典结论来源（调研核对）：(A+G)/(T+C)=0.4 → 互补链 2.5、全分子 1；
// 玉米 2n=20 第二次有丝分裂后期 40 条中 20 条带标记；
// ¹⁵N 复制 n 代含母链分子恒为 2 个；原料需求 (2^n−1)×m。

import 'package:biology/engine/dna_strand_engine.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('单链碱基比值换算', () {
    test('(A+T)/(G+C)：互补链与全分子同值', () {
      final r = atOverGc(0.5);
      expect(r.chain2, 0.5);
      expect(r.whole, 0.5);
    });

    test('(A+G)/(T+C)=0.4 → 互补链 2.5，全分子 1（经典例题）', () {
      final r = agOverTc(0.4);
      expect(r.chain2, closeTo(2.5, 1e-9));
      expect(r.whole, 1.0);
      expect(r.rule, contains('倒数'));
    });

    test('非正比值报错', () => expect(() => atOverGc(0), throwsArgumentError));
  });

  group('链间碱基数量互推', () {
    test('链1 四碱基 → 链2 互补 + 全分子总数', () {
      final r = strandComplement(a1: 10, t1: 20, g1: 30, c1: 40);
      expect(r.a2, 20);
      expect(r.t2, 10);
      expect(r.g2, 40);
      expect(r.c2, 30);
      expect(r.total, 200);
    });

    test('用户点名场景：两链 C、T 数量 → 全分子 A、G', () {
      // 链1: C=10 T=20；链2: C=15 T=25
      // → A总数=T总数=45，G总数=C总数=25，总计 140
      final r = strandCountsFromCT(c1: 10, t1: 20, c2: 15, t2: 25);
      expect(r.aTotal, 45);
      expect(r.tTotal, 45);
      expect(r.gTotal, 25);
      expect(r.cTotal, 25);
      expect(r.total, 140);
      expect(r.agOverTcWhole, 1.0);
    });
  });

  group('¹⁵N 半保留复制标记', () {
    test('第 1 代：全中带', () {
      final r = dnaLabelReplication(generations: 1);
      expect(r.totalMolecules, 2);
      expect(r.labeledMolecules, 2);
      expect(r.unlabeledOnlyMolecules, 0);
      expect(r.centrifugeBands, contains('中带'));
    });

    test('第 3 代：8 分子中 2 含标记，链 2/16', () {
      final r = dnaLabelReplication(generations: 3);
      expect(r.totalMolecules, 8);
      expect(r.labeledMolecules, 2);
      expect(r.unlabeledOnlyMolecules, 6);
      expect(r.labeledStrands, 2);
      expect(r.totalStrands, 16);
      expect(r.labeledMoleculeRatio, 0.25);
      expect(r.labeledStrandRatio, 2 / 16);
    });
  });

  group('有丝分裂染色体标记（玉米 2n=20 经典题）', () {
    test('第 1 次分裂：子细胞 20 条全带标记', () {
      final r = mitosisLabeling(chromosomes2n: 20, divisions: 1);
      expect(r.labeledChromosomes, '20 条（全部）');
      expect(r.labeledChromatidsAtMetaphase, 40);
    });

    test('第 2 次分裂：子细胞 0~20 条；后期 40 条中 20 条带标记', () {
      final r = mitosisLabeling(chromosomes2n: 20, divisions: 2);
      expect(r.labeledChromatidsAtMetaphase, 20);
      expect(r.labeledChromosomes, contains('0 ~ 20'));
      expect(r.labeledChromosomes, contains('40 条染色体，其中带标记 20 条'));
    });

    test('奇数染色体数报错', () {
      expect(() => mitosisLabeling(chromosomes2n: 21, divisions: 1),
          throwsArgumentError);
    });
  });

  group('复制原料需求', () {
    test('复制 3 代共需 (8−1)×m，第 3 次单独需 4×m', () {
      final r = replicationMaterial(generations: 3, perMolecule: 100);
      expect(r.totalNeeded, 700);
      expect(r.lastRoundNeeded, 400);
    });
  });
}
