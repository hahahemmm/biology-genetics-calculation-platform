// phenotype_ratio_engine_test.dart —— 表型配比 × 系谱引擎联调测试
//
// 不复用手写样本：由 PedigreeGraphEngine 真实展开世代拿 (基因型, 概率)，
// 再喂 groupByPhenotype + phenotypeRatioValues，验证经典分离比。
// 覆盖：单基因 3:1、双基因 9:3:3:1、三基因 27:9:9:9:3:3:3:1。

import 'package:biology/engine/pedigree_graph.dart';
import 'package:biology/engine/phenotype_grouper.dart';
import 'package:biology/pages/widgets/pedigree_detail_strip.dart';
import 'package:flutter_test/flutter_test.dart';

/// 引擎某一代 → GenotypeSample 列表（只用真实计算产出，跳过外来样本）。
List<GenotypeSample> _samplesOf(PedigreeGraphEngine engine, int generation) => [
      for (final n in engine.nodesOf(generation))
        if (!n.isExternal) GenotypeSample(n.genotype, n.probability),
    ];

void main() {
  group('三基因 AaBbCc 自交，引擎展开到 F2', () {
    test('F2 27 个桶 → 8 组表型，配比 27:9:9:9:3:3:3:1', () {
      final engine = PedigreeGraphEngine(
          fatherGenotype: 'AaBbCc', motherGenotype: 'AaBbCc');
      engine.recomputeFrom(0);
      engine.ensureGeneration(2);

      final f2 = _samplesOf(engine, 2);
      expect(f2, hasLength(27), reason: 'F2 应有 27 个基因型桶');

      final groups = groupByPhenotype(f2);
      expect(groups, hasLength(8), reason: '三对完全显性 → 2³ = 8 组');
      expect(groups.map((g) => g.label).toList(), [
        'A显·B显·C显',
        'A显·B显·C隐',
        'A显·B隐·C显',
        'A隐·B显·C显',
        'A显·B隐·C隐',
        'A隐·B显·C隐',
        'A隐·B隐·C显',
        'A隐·B隐·C隐',
      ]);

      final total = groups.fold<double>(0, (s, g) => s + g.probability);
      expect(total, closeTo(1.0, 1e-9), reason: '各组概率合计应为 1');

      expect(phenotypeRatioValues(groups).join(':'), '27:9:9:9:3:3:3:1');
      // 8 组时文本只展示前 3 组 + 省略提示
      expect(phenotypeRatioText(groups), 'A显·B显·C显 27 : A显·B显·C隐 9 : A显·B隐·C显 9 : 等 5 类');
    });
  });

  group('双基因 AaBb 自交', () {
    test('F1 9 个桶 → 4 组表型，配比 9:3:3:1', () {
      final engine = PedigreeGraphEngine(
          fatherGenotype: 'AaBb', motherGenotype: 'AaBb');
      engine.recomputeFrom(0);
      engine.ensureGeneration(1);

      final f1 = _samplesOf(engine, 1);
      expect(f1, hasLength(9), reason: 'F1 应有 3² = 9 个基因型桶');

      final groups = groupByPhenotype(f1);
      expect(groups, hasLength(4));
      expect(phenotypeRatioValues(groups).join(':'), '9:3:3:1');

      final total = groups.fold<double>(0, (s, g) => s + g.probability);
      expect(total, closeTo(1.0, 1e-9));
    });
  });

  group('单基因 Aa 自交', () {
    test('F1 3 个桶 → 2 组表型，配比 3:1', () {
      final engine = PedigreeGraphEngine(
          fatherGenotype: 'Aa', motherGenotype: 'Aa');
      engine.recomputeFrom(0);
      engine.ensureGeneration(1);

      final f1 = _samplesOf(engine, 1);
      expect(f1, hasLength(3), reason: 'F1 应有 AA / Aa / aa 三个桶');

      final groups = groupByPhenotype(f1);
      expect(groups, hasLength(2));
      expect(groups[0].label, 'A显');
      expect(groups[1].label, 'A隐');
      expect(phenotypeRatioValues(groups).join(':'), '3:1');

      final total = groups.fold<double>(0, (s, g) => s + g.probability);
      expect(total, closeTo(1.0, 1e-9));
    });
  });
}
