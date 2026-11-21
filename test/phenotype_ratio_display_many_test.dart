// phenotype_ratio_display_many_test.dart —— 组数很多时的本代配比显示
//
// 覆盖：AaBbCcDd 自交 F2 的 16 个表型组、概率总和不为 1（不归一化）、
// 8 组等概率。纯函数层测试，不构造系谱引擎。

import 'package:flutter_test/flutter_test.dart';

import 'package:biology/engine/phenotype_grouper.dart';
import 'package:biology/pages/widgets/pedigree_detail_strip.dart';

/// AaBbCcDd 自交 F2：16 个表型组各取一个代表基因型，
/// 概率用经典比例 3^显性位点数 / 256（1/256 的整数倍）。
List<GenotypeSample> f2SixteenGroups() => const [
      GenotypeSample('AaBbCcDd', 81 / 256),
      GenotypeSample('AaBbCcdd', 27 / 256),
      GenotypeSample('AaBbccDd', 27 / 256),
      GenotypeSample('AabbCcDd', 27 / 256),
      GenotypeSample('aaBbCcDd', 27 / 256),
      GenotypeSample('AaBbccdd', 9 / 256),
      GenotypeSample('AabbCcdd', 9 / 256),
      GenotypeSample('AabbccDd', 9 / 256),
      GenotypeSample('aaBbCcdd', 9 / 256),
      GenotypeSample('aaBbccDd', 9 / 256),
      GenotypeSample('aabbCcDd', 9 / 256),
      GenotypeSample('Aabbccdd', 3 / 256),
      GenotypeSample('aaBbccdd', 3 / 256),
      GenotypeSample('aabbCcdd', 3 / 256),
      GenotypeSample('aabbccDd', 3 / 256),
      GenotypeSample('aabbccdd', 1 / 256),
    ];

void main() {
  group('组数很多', () {
    test('AaBbCcDd 自交 F2 16 组 → 只显示前 3 组 + 等 13 类', () {
      final groups = groupByPhenotype(f2SixteenGroups());
      expect(groups.length, 16);

      // 3^j/256 的分母正好是 256，凑比上限恰好覆盖 → 经典 81:27:…:1
      final text = phenotypeRatioText(groups);
      expect(
          text,
          'A显·B显·C显·D显 81 : A显·B显·C显·D隐 27 : '
          'A显·B显·C隐·D显 27 : 等 13 类');
      expect(text.contains('等 13 类'), isTrue);

      // 只出现前 3 组：第 4 组起的 label 不得泄漏
      for (var i = 3; i < groups.length; i++) {
        expect(text.contains(groups[i].label), isFalse);
      }

      expect(text, isNot(contains('NaN')));
      expect(text, isNot(contains('Infinity')));
      expect('('.allMatches(text).length, ')'.allMatches(text).length);

      // 配比值全是整数，总和 = 256（分母）
      final values = phenotypeRatioValues(groups);
      for (final v in values) {
        expect(RegExp(r'^\d+$').hasMatch(v), isTrue, reason: 'v=$v');
      }
      expect(values.fold<int>(0, (a, v) => a + int.parse(v)), 256);
    });

    test('概率总和不为 1（只传部分组）→ 不归一化，按原始概率凑比/乘 100', () {
      // 和 = 0.6 ≠ 1，但凑比只看各自概率×k 为整数：k=10 → 1:2:3
      final groups = groupByPhenotype(const [
        GenotypeSample('AAbb', 0.1),
        GenotypeSample('aaBB', 0.2),
        GenotypeSample('aabb', 0.3),
      ]);
      expect(groups.length, 3);
      expect(phenotypeRatioText(groups), 'A隐·B隐 3 : A隐·B显 2 : A显·B隐 1');

      // 百分比回退同样不归一化：0.123+0.234+0.343 = 0.7，输出 70.0% 而非 100%
      final part = groupByPhenotype(const [
        GenotypeSample('AAbb', 0.123),
        GenotypeSample('aaBB', 0.234),
        GenotypeSample('aabb', 0.343),
      ]);
      expect(phenotypeRatioText(part),
          'A隐·B隐 34.3% : A隐·B显 23.4% : A显·B隐 12.3%');
    });

    test('8 组各 1/8 → 全 1，前 3 组 + 等 5 类', () {
      final groups = [
        for (var i = 0; i < 8; i++)
          PhenotypeGroup(
              label: 'G${i + 1}', probability: 0.125, genotypes: ['g$i']),
      ];
      expect(phenotypeRatioValues(groups),
          ['1', '1', '1', '1', '1', '1', '1', '1']);
      expect(phenotypeRatioText(groups), 'G1 1 : G2 1 : G3 1 : 等 5 类');
    });
  });
}
