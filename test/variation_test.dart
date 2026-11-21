// variation_test.dart —— 变异引擎测试（课标 3.3.1/3.3.2/3.3.3/3.3.5）
import 'package:flutter_test/flutter_test.dart';

import 'package:biology/engine/mutation_engine.dart';

void main() {
  group('mutateSequence', () {
    test('替换：长度不变、目标位点改变、密码子索引 0（原密码子 ATG）', () {
      final r = mutateSequence(sequence: 'ATGCCGTA', type: 'sub', position: 2);
      expect(r.original, 'ATGCCGTA');
      expect(r.mutated.length, 8, reason: '替换不改变长度');
      expect(r.mutated[2], isNot('G'), reason: '替换碱基必须与原位不同');
      expect(r.codonIndex, 0, reason: '位点 2 属于第 1 个密码子（0–2）');
      expect(r.originalCodon, 'ATG');
      expect(r.type, '替换');
    });

    test('缺失：删除首位，长度 -1', () {
      final r = mutateSequence(sequence: 'ATGCCGTA', type: 'del', position: 0);
      expect(r.mutated, 'TGCCGTA');
      expect(r.mutated.length, 7);
      expect(r.type, '缺失');
      expect(r.originalCodon, 'ATG', reason: '受影响密码子 = 原框内包含位置 0 的');
    });

    test('插入：新碱基插入到 position 前，长度 +1', () {
      final r = mutateSequence(
          sequence: 'ATGCCGTA', type: 'ins', position: 3, newBase: 'T');
      expect(r.mutated, 'ATGTCCGTA');
      expect(r.mutated.length, 9);
      expect(r.type, '插入');
    });

    test('插入缺省碱基为 A；ins 位置可等于长度（末尾追加）', () {
      final r1 =
          mutateSequence(sequence: 'ATG', type: 'ins', position: 3);
      expect(r1.mutated, 'ATGA');
      final r2 = mutateSequence(sequence: 'ATGCCGTA', type: 'ins', position: 2);
      expect(r2.mutated, 'ATAGCCGTA', reason: 'T 之前插入 A');
    });

    test('大小写不敏感，输出统一大写', () {
      final r = mutateSequence(sequence: 'atgccgta', type: 'sub', position: 0);
      expect(r.original, 'ATGCCGTA');
      expect(r.mutated, matches(RegExp(r'^[ATGC]+$')));
    });

    test('非法序列抛 ArgumentError（含非碱基字母）', () {
      expect(() => mutateSequence(sequence: 'ATGN', type: 'sub', position: 0),
          throwsArgumentError);
      expect(() => mutateSequence(sequence: 'ATGCCG1', type: 'sub', position: 0),
          throwsArgumentError);
      expect(() => mutateSequence(sequence: '', type: 'sub', position: 0),
          throwsArgumentError);
    });

    test('位置越界抛 ArgumentError', () {
      expect(() => mutateSequence(sequence: 'ATG', type: 'sub', position: 3),
          throwsArgumentError, reason: 'sub 最大值 len-1');
      expect(() => mutateSequence(sequence: 'ATG', type: 'del', position: 3),
          throwsArgumentError, reason: 'del 最大值 len-1');
      expect(() => mutateSequence(sequence: 'ATG', type: 'ins', position: 4),
          throwsArgumentError, reason: 'ins 最大值 len');
      expect(() => mutateSequence(sequence: 'ATG', type: 'sub', position: -1),
          throwsArgumentError);
    });

    test('敏感：sub 时 newBase 与原位相同 → 自动换成另一不同碱基', () {
      final r = mutateSequence(
          sequence: 'ATGCCGTA', type: 'sub', position: 2, newBase: 'G');
      expect(r.mutated[2], isNot('G'), reason: '即使指定原位碱基也必须发生改变');
    });

    test('seq 全为同一字母时 sub 也能换出另一碱基', () {
      final r = mutateSequence(sequence: 'GGGG', type: 'sub', position: 1);
      expect(r.mutated[1], isNot('G'));
      expect(r.mutated, matches(RegExp(r'^[ATGC]+$')));
    });
  });

  group('chromosomeSets', () {
    test('示例：Aa→2、AaaBbb→3、AAAaBBbb→4、ABCD→1、AAaa→4', () {
      expect(chromosomeSets(genotype: 'Aa'), 2);
      expect(chromosomeSets(genotype: 'AaaBbb'), 3);
      expect(chromosomeSets(genotype: 'AAAaBBbb'), 4);
      expect(chromosomeSets(genotype: 'ABCD'), 1);
      expect(chromosomeSets(genotype: 'AAaa'), 4);
    });

    test('大小写混合归并：aAa、Aaa 均 3', () {
      expect(chromosomeSets(genotype: 'aAa'), 3);
      expect(chromosomeSets(genotype: 'BbbAa'), 3);
      expect(chromosomeSets(genotype: 'Aaaa'), 4);
    });

    test('空 / 含非字母字符抛 ArgumentError', () {
      expect(() => chromosomeSets(genotype: ''), throwsArgumentError);
      expect(() => chromosomeSets(genotype: '   '), throwsArgumentError);
      expect(() => chromosomeSets(genotype: 'Aa1'), throwsArgumentError);
      expect(() => chromosomeSets(genotype: 'A-a'), throwsArgumentError);
    });
  });

  test('mutationFactors 非空且物理/化学/生物三大类齐全，各不少于 2 条', () {
    expect(mutationFactors, isNotEmpty);
    final cats = mutationFactors.map((f) => f.category).toSet();
    expect(cats, containsAll(['物理', '化学', '生物']));
    for (final c in ['物理', '化学', '生物']) {
      expect(mutationFactors.where((f) => f.category == c).length,
          greaterThanOrEqualTo(2),
          reason: '$c 类诱变因素应至少 2 条');
    }
    for (final f in mutationFactors) {
      expect(f.factor, isNotEmpty);
      expect(f.note, isNotEmpty);
    }
  });
}