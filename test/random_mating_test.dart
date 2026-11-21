// random_mating_test.dart —— 自由交配引擎单元测试
//
// 覆盖：
//   - 经典案例：Aa 群体 → 1:2:1；1/3AA+2/3Aa → 4:4:1
//   - 配子库法与枚举法一致性
//   - Hardy-Weinberg 平衡：一代后逐代稳定
//   - 致死选择：aa 致死逐代淘汰，a 频率下降
//   - 输入校验与归一化

import 'package:biology/engine/fraction.dart';
import 'package:biology/engine/genetics_env.dart';
import 'package:biology/engine/random_mating_engine.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('自由交配 · 经典案例', () {
    test('F1 杂合群体（全 Aa）自由交配 → 1:2:1，表型 3:1', () {
      final e = RandomMatingEngine();
      final r = e.randomMate({'Aa': Fraction.one});
      expect(r.offspringGenotypes['AA'], Fraction(1, 4));
      expect(r.offspringGenotypes['Aa'], Fraction(1, 2));
      expect(r.offspringGenotypes['aa'], Fraction(1, 4));
      expect(r.genotypeRatio, [1, 2, 1]);
      expect(r.phenotypeRatio, [3, 1]);
      // 只有一种交配组合：Aa 自交，概率 1
      expect(r.matings.length, 1);
      expect(r.matings.single.probability, Fraction.one);
    });

    test('1/3 AA + 2/3 Aa 群体 → AA 4/9、Aa 4/9、aa 1/9', () {
      final e = RandomMatingEngine();
      final r = e.randomMate({'AA': Fraction(1, 3), 'Aa': Fraction(2, 3)});
      // 配子库：A = 1/3 + 2/3·1/2 = 2/3；a = 1/3
      expect(r.gametePool['A'], Fraction(2, 3));
      expect(r.gametePool['a'], Fraction(1, 3));
      expect(r.offspringGenotypes['AA'], Fraction(4, 9));
      expect(r.offspringGenotypes['Aa'], Fraction(4, 9));
      expect(r.offspringGenotypes['aa'], Fraction(1, 9));
    });

    test('三种基因型混合群体概率和恒为 1', () {
      final e = RandomMatingEngine();
      final r = e.randomMate({
        'AA': Fraction(1, 4),
        'Aa': Fraction(1, 2),
        'aa': Fraction(1, 4),
      });
      var sum = Fraction.zero;
      r.offspringGenotypes.forEach((_, p) => sum = sum + p);
      expect(sum, Fraction.one);
      // 交配组合概率和也为 1
      var mp = Fraction.zero;
      for (final m in r.matings) {
        mp = mp + m.probability;
      }
      expect(mp, Fraction.one);
      // 该群体本就在平衡态，子代仍是 1:2:1
      expect(r.genotypeRatio, [1, 2, 1]);
    });
  });

  group('自由交配 · 枚举法与配子法一致', () {
    test('枚举法合并结果 == 配子库直接结合', () {
      final e = RandomMatingEngine();
      final pop = {'AA': Fraction(1, 3), 'Aa': Fraction(2, 3)};
      final r = e.randomMate(pop);
      // 配子库直接结合
      final pool = r.gametePool;
      final byPool = <String, Fraction>{};
      pool.forEach((g1, p1) {
        pool.forEach((g2, p2) {
          final env = GeneticsEnv();
          final merged = env.normalize('$g1$g2');
          byPool[merged] = (byPool[merged] ?? Fraction.zero) + p1 * p2;
        });
      });
      expect(r.offspringGenotypes, byPool);
    });

    test('异型组合概率带 2 倍系数', () {
      final e = RandomMatingEngine();
      final r = e.randomMate({'AA': Fraction(1, 3), 'Aa': Fraction(2, 3)});
      final hetero = r.matings.firstWhere((m) => m.parent1 != m.parent2);
      expect(hetero.probability, Fraction(4, 9)); // 2 × 1/3 × 2/3
      final selfAA = r.matings
          .firstWhere((m) => m.parent1 == 'AA' && m.parent2 == 'AA');
      expect(selfAA.probability, Fraction(1, 9));
    });
  });

  group('自由交配 · 逐代平衡', () {
    test('无选择时一代达平衡，之后各代稳定不变', () {
      final e = RandomMatingEngine();
      final gens = e.generations({'AA': Fraction(1, 3), 'Aa': Fraction(2, 3)}, 3);
      expect(gens.length, 3);
      // 第一代子代 4:4:1，之后每代与第一代完全相同（H-W 平衡）
      for (var g = 1; g < gens.length; g++) {
        expect(gens[g].offspringGenotypes, gens[0].offspringGenotypes);
      }
    });

    test('区别于自交：自由交配群体杂合子不会逐代减半', () {
      final e = RandomMatingEngine();
      final gens = e.generations({'Aa': Fraction.one}, 3);
      // 每代 Aa 都是 1/2（平衡），不会像连续自交那样 1/2 → 1/4 → 1/8
      for (final g in gens) {
        expect(g.offspringGenotypes['Aa'], Fraction(1, 2));
      }
    });
  });

  group('自由交配 · 致死选择', () {
    test('aa 致死：子代存活者中 AA:Aa = 1:2', () {
      final env = GeneticsEnv()
        ..addLethalRule(GeneticsEnv.lethalOnRecessiveHomozygous('A'));
      final e = RandomMatingEngine(env: env);
      final r = e.randomMate({'Aa': Fraction.one});
      expect(r.offspringGenotypes.containsKey('aa'), isFalse);
      expect(r.offspringGenotypes['AA'], Fraction(1, 3));
      expect(r.offspringGenotypes['Aa'], Fraction(2, 3));
    });

    test('aa 致死 + 混合群体：统一淘汰，不逐组合归一化', () {
      // 1/3 AA + 2/3 Aa 群体，配子库 A 2/3、a 1/3
      // 理论子代 4/9 AA、4/9 Aa、1/9 aa → 淘汰 aa → AA 1/2、Aa 1/2。
      // 若逐组合归一化会错算成 13/27 : 14/27。
      final env = GeneticsEnv()
        ..addLethalRule(GeneticsEnv.lethalOnRecessiveHomozygous('A'));
      final e = RandomMatingEngine(env: env);
      final r = e.randomMate({'AA': Fraction(1, 3), 'Aa': Fraction(2, 3)});
      expect(r.offspringGenotypes['AA'], Fraction(1, 2));
      expect(r.offspringGenotypes['Aa'], Fraction(1, 2));
      expect(r.offspringGenotypes.containsKey('aa'), isFalse);
    });

    test('aa 致死逐代淘汰：a 频率逐代下降', () {
      final env = GeneticsEnv()
        ..addLethalRule(GeneticsEnv.lethalOnRecessiveHomozygous('A'));
      final e = RandomMatingEngine(env: env);
      final gens = e.generations({'Aa': Fraction.one}, 3);
      Fraction aFreq(RandomMatingResult r) =>
          r.gametePool['a'] ?? Fraction.zero;
      // 各代配子库 a 频率：初始 1/2 → 1/3（群体 1/3AA+2/3Aa）→ 1/4（群体 1/2AA+1/2Aa）
      expect(aFreq(gens[0]), Fraction(1, 2));
      expect(aFreq(gens[1]), Fraction(1, 3));
      expect(aFreq(gens[2]), Fraction(1, 4));
      // 单调下降：致死选择下 a 被逐代淘汰
      expect(aFreq(gens[1]).compareTo(aFreq(gens[0])) < 0, isTrue);
      expect(aFreq(gens[2]).compareTo(aFreq(gens[1])) < 0, isTrue);
    });
  });

  group('自由交配 · 多位点', () {
    test('AaBb 群体自由交配 → 9:3:3:1', () {
      final e = RandomMatingEngine();
      final r = e.randomMate({'AaBb': Fraction.one});
      expect(r.phenotypeRatio, [9, 3, 3, 1]);
      var sum = Fraction.zero;
      r.offspringGenotypes.forEach((_, p) => sum = sum + p);
      expect(sum, Fraction.one);
    });
  });

  group('自由交配 · 输入校验', () {
    test('空群体抛错', () {
      final e = RandomMatingEngine();
      expect(() => e.randomMate({}), throwsArgumentError);
    });

    test('零/负频率抛错', () {
      final e = RandomMatingEngine();
      expect(() => e.randomMate({'Aa': Fraction.zero}), throwsArgumentError);
      expect(() => e.randomMate({'Aa': Fraction(-1, 2)}), throwsArgumentError);
    });

    test('频率自动归一化：2:1 与 2/3:1/3 等价', () {
      final e = RandomMatingEngine();
      final r = e.randomMate({'AA': Fraction.of(2), 'Aa': Fraction.one});
      expect(r.population['AA'], Fraction(2, 3));
      expect(r.population['Aa'], Fraction(1, 3));
    });

    test('写法容错：aA 与 Aa 合并为同一基因型', () {
      final e = RandomMatingEngine();
      final r = e.randomMate({'aA': Fraction(1, 2), 'Aa': Fraction(1, 2)});
      expect(r.population.length, 1);
      expect(r.population['Aa'], Fraction.one);
    });

    test('代数至少为 1', () {
      final e = RandomMatingEngine();
      expect(() => e.generations({'Aa': Fraction.one}, 0), throwsArgumentError);
    });
  });
}
