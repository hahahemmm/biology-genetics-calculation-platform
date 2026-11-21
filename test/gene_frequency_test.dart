// gene_frequency_test.dart —— 基因频率与自然选择引擎单元测试
//
// 覆盖（课标 4.2.1~4.2.3）：
//   - 个体数 → 基因型频率/基因频率 + 哈迪-温伯格平衡判定
//   - 平衡预测（p²、2pq、q²）
//   - 逐代淘汰隐性纯合（q → q/(1+q) 经典数列）与无选择（频率不变）
//   - 异常输入校验

import 'package:biology/engine/gene_frequency.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('基因频率计算', () {
    test('AA=30, Aa=60, aa=10 → freqA=0.6, freqa=0.4，偏离平衡', () {
      final r = calcGeneFrequency(aa: 10, aA: 60, AA: 30);
      expect(r.freqA, closeTo(0.6, 1e-12));
      expect(r.freqa, closeTo(0.4, 1e-12));
      expect(r.freqAA, closeTo(0.3, 1e-12));
      expect(r.freqAa, closeTo(0.6, 1e-12));
      expect(r.freqaa, closeTo(0.1, 1e-12));
      // 实际 0.30/0.60/0.10 vs 平衡预测 p²/2pq/q²=0.36/0.48/0.16：
      // 偏差 0.06 > 0.001 容差 → 群体并未处于哈迪-温伯格平衡。
      // （注：验收样例预期 true 与给定判定公式矛盾，此处按公式判定为 false，
      //   详见引擎实现与提交说明。）
      expect(r.inEquilibrium, isFalse);
      expect(r.note, isNotNull);
    });

    test('AA=20, Aa=40, aa=40 → freqA=0.4, freqa=0.6，偏离平衡', () {
      final r = calcGeneFrequency(aa: 40, aA: 40, AA: 20);
      expect(r.freqA, closeTo(0.4, 1e-12));
      expect(r.freqa, closeTo(0.6, 1e-12));
      expect(r.freqAA, closeTo(0.2, 1e-12));
      expect(r.freqAa, closeTo(0.4, 1e-12));
      expect(r.freqaa, closeTo(0.4, 1e-12));
      // freqaa=0.40 偏离 q²=0.36（差 0.04 > 0.001）
      expect(r.inEquilibrium, isFalse);
      expect(r.note, isNotNull);
    });
  });

  group('哈迪-温伯格预测', () {
    test('p=0.7, q=0.3 → AA=0.49, Aa=0.42, aa=0.09，恒为平衡', () {
      final r = hardyWeinbergPredict(p: 0.7, q: 0.3);
      expect(r.freqAA, closeTo(0.49, 1e-12));
      expect(r.freqAa, closeTo(0.42, 1e-12));
      expect(r.freqaa, closeTo(0.09, 1e-12));
      expect(r.freqA, closeTo(0.7, 1e-12));
      expect(r.freqa, closeTo(0.3, 1e-12));
      expect(r.inEquilibrium, isTrue);
    });
  });

  group('逐代选择模拟', () {
    test('q0=0.5 淘汰隐性纯合 2 代 → q1≈1/3, q2=0.25', () {
      final r = simulateSelection(
          q0: 0.5, generations: 2, cullRecessive: true);
      expect(r.qPerGen.length, 3); // 含初始代
      expect(r.qPerGen[0], closeTo(0.5, 1e-12));
      expect(r.qPerGen[1], closeTo(1 / 3, 1e-9));
      expect(r.qPerGen[2], closeTo(0.25, 1e-9));
      // p = 1 − q
      expect(r.pPerGen[0], closeTo(0.5, 1e-12));
      expect(r.pPerGen[1], closeTo(2 / 3, 1e-9));
      expect(r.pPerGen[2], closeTo(0.75, 1e-12));
    });

    test('q0=0.5 无选择 5 代 → 每代 q 不变', () {
      final r = simulateSelection(
          q0: 0.5, generations: 5, cullRecessive: false);
      expect(r.qPerGen.length, 6);
      expect(r.qPerGen.every((q) => q == 0.5), isTrue);
      expect(r.pPerGen.every((p) => p == 0.5), isTrue);
    });
  });

  group('异常输入', () {
    test('个体总数为 0 抛 ArgumentError', () {
      expect(
        () => calcGeneFrequency(aa: 0, aA: 0, AA: 0),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('任一基因型个体数为负抛 ArgumentError', () {
      expect(
        () => calcGeneFrequency(aa: -1, aA: 10, AA: 10),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('simulateSelection 代数 ≤ 0 抛 ArgumentError', () {
      expect(
        () => simulateSelection(q0: 0.5, generations: 0, cullRecessive: true),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('simulateSelection q0 不在开区间 (0,1) 抛 ArgumentError', () {
      expect(
        () => simulateSelection(q0: 0, generations: 3, cullRecessive: true),
        throwsA(isA<ArgumentError>()),
      );
      expect(
        () => simulateSelection(q0: 1, generations: 3, cullRecessive: true),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('hardyWeinbergPredict p+q≠1 抛 ArgumentError', () {
      expect(
        () => hardyWeinbergPredict(p: 0.8, q: 0.1),
        throwsA(isA<ArgumentError>()),
      );
    });
  });
}