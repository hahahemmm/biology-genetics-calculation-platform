// phenotype_input_robustness_test.dart —— 输入不规范健壮性测试
//
// 断言以 lib/engine/phenotype_grouper.dart 当前实际语义为准：
//   - 大小写不敏感归组；位点按字母出现顺序生成 label（乱序输入会得不同 label）。
//   - '-' 并入前一位点；孤立 '-' 被忽略；全缺失位点不输出。
//   - 空格/数字/符号等非字母字符被当作"位点字母"处理，不抛异常（已知怪癖，锁定现状）。

import 'package:biology/engine/phenotype_grouper.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('大小写混写', () {
    test('AaBb / aAbB / AABB 归入同一表型组 A显·B显', () {
      final groups = groupByPhenotype(const [
        GenotypeSample('AaBb', 0.4),
        GenotypeSample('aAbB', 0.3),
        GenotypeSample('AABB', 0.3),
      ]);
      expect(groups, hasLength(1), reason: '三种写法应归同一表型组');
      expect(groups.single.label, 'A显·B显', reason: '大小写不敏感，均判全显');
      expect(groups.single.probability, closeTo(1.0, 1e-12), reason: '组内概率求和');
      expect(groups.single.genotypes, ['AaBb', 'aAbB', 'AABB'], reason: '成员保持传入顺序');
    });
  });

  group('缺失标记', () {
    test('aabb 全小写判双隐', () {
      final groups = groupByPhenotype(const [GenotypeSample('aabb', 1.0)]);
      expect(groups.single.label, 'A隐·B隐', reason: '全小写即隐性');
    });

    test('ab-- 的缺失并入前一位点，仍判 A隐·B隐', () {
      final groups = groupByPhenotype(const [GenotypeSample('ab--', 1.0)]);
      expect(groups.single.label, 'A隐·B隐', reason: '\'--\' 并入 B 位点，全隐不变');
    });

    test('A-B- 判 A显·B显（有大写即显）', () {
      final groups = groupByPhenotype(const [GenotypeSample('A-B-', 1.0)]);
      expect(groups.single.label, 'A显·B显', reason: '缺失并入前位点，大写判显');
    });

    test('孤立 \'--\' 不抛异常，得空标签（现状锁定）', () {
      final groups = groupByPhenotype(const [GenotypeSample('--', 1.0)]);
      expect(groups, hasLength(1), reason: '不崩溃，正常返回');
      expect(groups.single.label, '', reason: '孤立缺失无位点可标注，当前产出空标签');
    });
  });

  group('位点顺序打乱', () {
    test('BbAa 与 AaBb 当前判为不同表型组（现状锁定）', () {
      final groups = groupByPhenotype(const [
        GenotypeSample('AaBb', 0.5),
        GenotypeSample('BbAa', 0.5),
      ]);
      expect(groups, hasLength(2), reason: 'label 按位点出现顺序生成，乱序即不同组');
      expect(groups.map((g) => g.label).toSet(), {'A显·B显', 'B显·A显'},
          reason: '两种顺序各自成组，语义等价但未合并');
    });
  });

  group('空白与空串', () {
    test('空串不抛异常，得空标签（现状锁定）', () {
      final groups = groupByPhenotype(const [GenotypeSample('', 1.0)]);
      expect(groups.single.label, '', reason: '无字符即无位点，当前产出空标签');
    });

    test('纯空格被当作位点，得 \' 隐\' 标签（现状锁定）', () {
      final groups = groupByPhenotype(const [GenotypeSample('  ', 1.0)]);
      expect(groups.single.label, ' 隐', reason: '空格被判为一个隐性位点字母');
    });

    test('\' AaBb \' 空格混入产生伪位点（现状锁定）', () {
      final groups = groupByPhenotype(const [GenotypeSample(' AaBb ', 1.0)]);
      expect(groups.single.label, ' 隐·A显·B显', reason: '首尾空格被当作隐性位点，不裁剪');
    });
  });

  group('非法字符不崩溃', () {
    for (final bad in ['Aa1b', 'Aa*b', 'Aa中b', '😀Aa']) {
      test('输入 \'$bad\' 不抛异常且返回列表', () {
        final groups = groupByPhenotype([GenotypeSample(bad, 1.0)]);
        expect(groups, hasLength(1), reason: '单样本总返回单组，只验不崩溃');
      });
    }
  });

  group('单样本与全同样本', () {
    test('单样本 → 组数 1', () {
      final groups = groupByPhenotype(const [GenotypeSample('AaBb', 1.0)]);
      expect(groups, hasLength(1), reason: '单样本必为一组');
    });

    test('全同样本 → 组数 1，概率求和', () {
      final groups = groupByPhenotype(const [
        GenotypeSample('AaBb', 0.25),
        GenotypeSample('AaBb', 0.25),
        GenotypeSample('AaBb', 0.5),
      ]);
      expect(groups, hasLength(1), reason: '同一基因型合并为一组');
      expect(groups.single.probability, closeTo(1.0, 1e-12), reason: '组内概率求和');
    });
  });
}
