// ploidy_engine_test.dart —— v2.2 批次3：染色体倍性计算引擎测试
//
// 经典结论来源：学科网/21世纪教育（AAaa→1:4:1、配子发育=单倍体等），
// 见 docs/PLAN_2.2.md 调研核对。

import 'package:biology/engine/ploidy_engine.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('setsByMorphology（形态法）', () {
    test('果蝇 8 条 4 种形态 → 2 组，每组 4 条', () {
      final r = setsByMorphology(totalChromosomes: 8, distinctForms: 4);
      expect(r.sets, 2);
      expect(r.perSet, 4);
    });

    test('玉米 20 条 10 种形态 → 2 组', () {
      final r = setsByMorphology(totalChromosomes: 20, distinctForms: 10);
      expect(r.sets, 2);
    });

    test('不整除报错', () {
      expect(() => setsByMorphology(totalChromosomes: 7, distinctForms: 2),
          throwsArgumentError);
    });
  });

  group('setsByGenotype（基因型法）', () {
    test('Aa → 2 组', () => expect(setsByGenotype('Aa').sets, 2));
    test('AaaBBb → 3 组', () => expect(setsByGenotype('AaaBBb').sets, 3));
    test('AAaaBBbb → 4 组', () => expect(setsByGenotype('AAaaBBbb').sets, 4));
    test('AAbb → 2 组（多字母取最大次数）', () {
      final r = setsByGenotype('AAbb');
      expect(r.sets, 2);
      expect(r.letterCounts, {'A': 2, 'B': 2});
    });
    test('无字母报错', () => expect(() => setsByGenotype('123'), throwsArgumentError));
  });

  group('judgePloidy（倍性判定：先看发育来源）', () {
    test('受精卵 + 2 组 → 二倍体可育', () {
      final r = judgePloidy(sets: 2, origin: PloidyOrigin.zygote);
      expect(r.name, '二倍体');
      expect(r.fertile, isTrue);
    });

    test('受精卵 + 3 组 → 三倍体不育（无子西瓜）', () {
      final r = judgePloidy(sets: 3, origin: PloidyOrigin.zygote);
      expect(r.name, '三倍体');
      expect(r.fertile, isFalse);
      expect(r.reason, contains('联会'));
    });

    test('配子发育 + 2 组 → 单倍体（关键易错点：与组数无关）', () {
      final r = judgePloidy(sets: 2, origin: PloidyOrigin.gamete);
      expect(r.name, '单倍体');
      expect(r.fertile, isFalse);
      expect(r.reason, contains('无论含'));
    });

    test('受精卵 + 4 组 → 四倍体可育', () {
      final r = judgePloidy(sets: 4, origin: PloidyOrigin.zygote);
      expect(r.name, '四倍体');
      expect(r.fertile, isTrue);
    });
  });

  group('haploidBreeding（单倍体育种）', () {
    test('AaBb → 4 种花粉 → 4 种纯合加倍', () {
      final r = haploidBreeding('AaBb');
      expect(r.gametes, ['AB', 'Ab', 'aB', 'ab']);
      expect(r.doubled, ['AABB', 'AAbb', 'aaBB', 'aabb']);
      expect(r.pureRatio, 1.0);
    });

    test('Aa → A/a → AA/aa', () {
      final r = haploidBreeding('Aa');
      expect(r.gametes, ['A', 'a']);
      expect(r.doubled, ['AA', 'aa']);
    });

    test('超过 3 对基因报错', () {
      expect(() => haploidBreeding('AaBbCcDd'), throwsArgumentError);
    });
  });

  group('tetraploidGametes（同源四倍体配子比例）', () {
    test('AAaa → AA:Aa:aa = 1:4:1', () {
      final r = tetraploidGametes('AAaa');
      expect(r.counts, {'AA': 1, 'Aa': 4, 'aa': 1});
      expect(r.ratioText, 'AA : Aa : aa = 1 : 4 : 1');
    });

    test('AAAa → AA:Aa = 3:3（即 1:1）', () {
      final r = tetraploidGametes('AAAa');
      expect(r.counts, {'AA': 3, 'Aa': 3});
    });

    test('Aaaa → Aa:aa = 3:3（即 1:1）', () {
      final r = tetraploidGametes('Aaaa');
      expect(r.counts, {'Aa': 3, 'aa': 3});
    });

    test('非 4 字母报错', () {
      expect(() => tetraploidGametes('Aa'), throwsArgumentError);
    });
  });


group('triploidSeedless 三倍体无子西瓜', () {
  test('四倍体母本×二倍体父本：胚3组/胚乳5组/果皮4组', () {
    final r = triploidSeedless(motherPloidy: 4, fatherPloidy: 2, x: 11);
    expect(r.embryoSets, 3);
    expect(r.endospermSets, 5);
    expect(r.fruitSets, 4);
    expect(r.embryoChromosomes, 33);
    expect(r.sterility, contains('联会紊乱'));
    expect(r.pollenRole, contains('生长素'));
  });

  test('二倍体母本×四倍体父本：胚3组/胚乳4组/果皮2组', () {
    final r = triploidSeedless(motherPloidy: 2, fatherPloidy: 4, x: 11);
    expect(r.embryoSets, 3);
    expect(r.endospermSets, 4);
    expect(r.fruitSets, 2);
  });

  test('非法亲本组合报错', () {
    expect(() => triploidSeedless(motherPloidy: 2, fatherPloidy: 2),
        throwsArgumentError);
    expect(() => triploidSeedless(motherPloidy: 4, fatherPloidy: 4),
        throwsArgumentError);
    expect(() => triploidSeedless(x: 0), throwsArgumentError);
  });
});
}
