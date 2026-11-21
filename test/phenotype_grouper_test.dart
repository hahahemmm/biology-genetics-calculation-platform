// phenotype_grouper_test.dart —— 表型归组引擎测试
//
// 覆盖：经典分离比（1:2:1 / 9:3:3:1 / 27:9:9:9:3:3:3:1）、缺失基因、
//       伴性遗传、多倍体、空输入、概率 0 与排序规则。

import 'package:biology/engine/phenotype_grouper.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('单基因 Aa × Aa（1:2:1）', () {
    test('→ 两组 0.75 / 0.25，成员保持传入顺序', () {
      final groups = groupByPhenotype(const [
        GenotypeSample('AA', 0.25),
        GenotypeSample('Aa', 0.5),
        GenotypeSample('aa', 0.25),
      ]);
      expect(groups, hasLength(2));
      expect(groups[0].label, 'A显');
      expect(groups[0].probability, closeTo(0.75, 1e-12));
      expect(groups[0].genotypes, ['AA', 'Aa']); // 传入顺序
      expect(groups[1].label, 'A隐');
      expect(groups[1].probability, closeTo(0.25, 1e-12));
      expect(groups[1].genotypes, ['aa']);
    });
  });

  group('双基因 AaBb 自交（9:3:3:1）', () {
    test('9 种基因型 → 4 组，分母 16', () {
      final groups = groupByPhenotype(const [
        GenotypeSample('AABB', 1 / 16),
        GenotypeSample('AABb', 2 / 16),
        GenotypeSample('AAbb', 1 / 16),
        GenotypeSample('AaBB', 2 / 16),
        GenotypeSample('AaBb', 4 / 16),
        GenotypeSample('Aabb', 2 / 16),
        GenotypeSample('aaBB', 1 / 16),
        GenotypeSample('aaBb', 2 / 16),
        GenotypeSample('aabb', 1 / 16),
      ]);
      expect(groups, hasLength(4));
      expect(
          groups.map((g) => g.label).toList(),
          ['A显·B显', 'A显·B隐', 'A隐·B显', 'A隐·B隐']);
      expect(groups[0].probability, closeTo(9 / 16, 1e-12)); // 0.5625
      expect(groups[1].probability, closeTo(3 / 16, 1e-12)); // 0.1875
      expect(groups[2].probability, closeTo(3 / 16, 1e-12)); // 0.1875
      expect(groups[3].probability, closeTo(1 / 16, 1e-12)); // 0.0625
      expect(groups[0].genotypes, ['AABB', 'AABb', 'AaBB', 'AaBb']);
      expect(groups[1].genotypes, ['AAbb', 'Aabb']);
      expect(groups[2].genotypes, ['aaBB', 'aaBb']);
      expect(groups[3].genotypes, ['aabb']);
    });
  });

  group('三基因 AaBbCc 自交（27:9:9:9:3:3:3:1）', () {
    test('27 种基因型 → 8 组，分母 64', () {
      // AaBbCc 自交：位点 A/B/C 的基因型分别是 AA|Aa|aa、BB|Bb|bb、CC|Cc|cc
      const locusA = ['AA', 'Aa', 'aa'];
      const locusB = ['BB', 'Bb', 'bb'];
      const locusC = ['CC', 'Cc', 'cc'];
      const probs = [0.25, 0.5, 0.25];
      final samples = <GenotypeSample>[];
      for (int i = 0; i < 3; i++) {
        for (int j = 0; j < 3; j++) {
          for (int k = 0; k < 3; k++) {
            samples.add(GenotypeSample('${locusA[i]}${locusB[j]}${locusC[k]}',
                probs[i] * probs[j] * probs[k]));
          }
        }
      }
      final groups = groupByPhenotype(samples);
      expect(groups, hasLength(8));
      expect(
          groups.map((g) => g.label).toList(),
          [
            'A显·B显·C显', // 27/64
            'A显·B显·C隐', //  9/64（同概率按 label 字典序）
            'A显·B隐·C显',
            'A隐·B显·C显',
            'A显·B隐·C隐', //  3/64
            'A隐·B显·C隐',
            'A隐·B隐·C显',
            'A隐·B隐·C隐', //  1/64
          ]);
      final expected = [
        27 / 64, 9 / 64, 9 / 64, 9 / 64, 3 / 64, 3 / 64, 3 / 64, 1 / 64
      ];
      for (int i = 0; i < 8; i++) {
        expect(groups[i].probability, closeTo(expected[i], 1e-12),
            reason: '第 $i 组 ${groups[i].label}');
      }
      expect(groups.map((g) => g.genotypes.length).toList(),
          [8, 4, 4, 4, 2, 2, 2, 1]); // 合计 27 个成员
    });
  });

  group('缺失基因 -', () {
    test('A- 显性、a- 隐性（有大写即显）', () {
      final groups = groupByPhenotype(const [
        GenotypeSample('A-', 0.5),
        GenotypeSample('a-', 0.5),
      ]);
      expect(groups.map((g) => g.label).toList(), ['A显', 'A隐']);
    });

    test('混合双位点 AaB- → A显·B显；b- → B隐', () {
      final groups = groupByPhenotype(const [
        GenotypeSample('AaB-', 1.0),
      ]);
      expect(groups.single.label, 'A显·B显');

      final g2 = groupByPhenotype(const [GenotypeSample('b-', 1.0)]);
      expect(g2.single.label, 'B隐');
    });
  });

  group('伴性遗传', () {
    test('XBY 显性 / XbY 隐性（Y 不参与判定）', () {
      final groups = groupByPhenotype(const [
        GenotypeSample('XBY', 0.5),
        GenotypeSample('XbY', 0.5),
      ]);
      expect(groups.map((g) => g.label).toList(), ['X显', 'X隐']);
    });

    test('XBXb 显性（杂合）/ XbXb 隐性', () {
      final groups = groupByPhenotype(const [
        GenotypeSample('XBXb', 0.5),
        GenotypeSample('XbXb', 0.5),
      ]);
      expect(groups.map((g) => g.label).toList(), ['X显', 'X隐']);
    });
  });

  group('多倍体', () {
    test('AAaa 与 Aaaa 都判显性，aaaa 隐性', () {
      final groups = groupByPhenotype(const [
        GenotypeSample('AAaa', 1 / 3),
        GenotypeSample('Aaaa', 1 / 3),
        GenotypeSample('aaaa', 1 / 3),
      ]);
      expect(groups[0].label, 'A显');
      expect(groups[0].probability, closeTo(2 / 3, 1e-12));
      expect(groups[0].genotypes, ['AAaa', 'Aaaa']);
      expect(groups[1].label, 'A隐');
      expect(groups[1].probability, closeTo(1 / 3, 1e-12));
    });
  });

  group('边界与排序', () {
    test('空列表返回空', () {
      expect(groupByPhenotype(const []), isEmpty);
    });

    test('概率为 0 的样本也参与归组', () {
      final groups = groupByPhenotype(const [
        GenotypeSample('aa', 0.0),
        GenotypeSample('AA', 1.0),
      ]);
      expect(groups, hasLength(2));
      expect(groups[1].label, 'A隐');
      expect(groups[1].probability, 0.0);
      expect(groups[1].genotypes, ['aa']);
    });

    test('概率降序，同概率按 label 字典序', () {
      final groups = groupByPhenotype(const [
        GenotypeSample('aabb', 0.5), // A隐·B隐
        GenotypeSample('AAbb', 0.5), // A显·B隐
        GenotypeSample('AABB', 0.25), // A显·B显
      ]);
      expect(groups.map((g) => g.label).toList(),
          ['A显·B隐', 'A隐·B隐', 'A显·B显']);
      expect(groups.map((g) => g.probability).toList(), [0.5, 0.5, 0.25]);
    });
  });
}
