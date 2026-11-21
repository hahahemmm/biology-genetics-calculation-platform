// population_growth_engine_test.dart —— 种群增长引擎独立复算守卫
//
// 网型：所有期望值都是**手算 / 公式复算**后写死的常数（不调引擎自己
// 再算一遍来当期望），公式与口径见 lib/engine/population_growth_engine.dart
// 文件头。覆盖：默认例逐点、J 的 λ=0/1/增减、S 的 r=0、N₀=K、N₀>K、
// K/2 处速率 = r·K/4、K/2 是否经过（含 r=0 与代数不足）、端点、非法输入、
// 溢出。
import 'package:biology/engine/population_growth_engine.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('J 型：默认例（N₀=10、λ=1.5、12 代）独立复算', () {
    final r = jShapedGrowth(n0: 10, lambda: 1.5, generations: 12);

    test('曲线 = N₀·λᵗ 的逐点手算值', () {
      const expected = <double>[
        10,
        15,
        22.5,
        33.75,
        50.625,
        75.9375,
        113.90625,
        170.859375,
        256.2890625,
        384.43359375,
        576.650390625,
        864.9755859375,
        1297.46337890625,
      ];
      expect(r.population.length, 13);
      for (var t = 0; t < expected.length; t++) {
        expect(r.population[t], closeTo(expected[t], 1e-9), reason: 't=$t');
      }
      expect(r.finalPopulation, closeTo(1297.46337890625, 1e-9));
      expect(r.trend, JShapeTrend.grow);
    });

    test('相对增长率恒为 λ−1；绝对新增量 = N_t·(λ−1)', () {
      expect(r.relativeGrowthRate, closeTo(0.5, 1e-12));
      expect(r.increments.length, 12, reason: '长度 = 代数（t → t+1）');
      expect(r.increments.first, closeTo(5, 1e-12));
      expect(r.increments.last, closeTo(432.48779296875, 1e-9));
      for (var t = 0; t < r.generations; t++) {
        expect(r.increments[t], closeTo(r.population[t] * 0.5, 1e-12),
            reason: 't=$t 的增量为负时同样成立');
      }
    });
  });

  group('J 型：λ 的四个档位', () {
    test('λ=0 ⇒ 第 1 代起归零（extinct），第一代增量 −N₀', () {
      final r = jShapedGrowth(n0: 10, lambda: 0, generations: 4);
      expect(r.population, <double>[10, 0, 0, 0, 0]);
      expect(r.trend, JShapeTrend.extinct);
      // N_t·(λ−1)：第 0 代 10×(−1) = −10（从 10 掉到 0），之后恒为 0。
      expect(r.increments, <double>[-10, 0, 0, 0]);
      expect(r.relativeGrowthRate, -1);
    });

    test('λ=1 ⇒ 每代不变（stable），增量为 0', () {
      final r = jShapedGrowth(n0: 10, lambda: 1, generations: 6);
      expect(r.population.every((v) => v == 10), isTrue);
      expect(r.increments.every((v) => v == 0), isTrue);
      expect(r.trend, JShapeTrend.stable);
    });

    test('0<λ<1 ⇒ 逐代下降（decline），增量为负', () {
      final r = jShapedGrowth(n0: 10, lambda: 0.5, generations: 3);
      expect(r.population, <double>[10, 5, 2.5, 1.25]);
      expect(r.increments, <double>[-5, -2.5, -1.25]);
      expect(r.trend, JShapeTrend.decline);
      expect(r.relativeGrowthRate, closeTo(-0.5, 1e-12));
    });

    test('λ=2 ⇒ 每代翻倍', () {
      final r = jShapedGrowth(n0: 10, lambda: 2, generations: 3);
      expect(r.population, <double>[10, 20, 40, 80]);
      expect(r.trend, JShapeTrend.grow);
    });
  });

  group('S 型：连续 Logistic（默认例 K=1000、N₀=10、r=0.8、12 代）', () {
    final r = logisticGrowth(n0: 10, k: 1000, r: 0.8, generations: 12);

    test('逐点手算值 K/(1+(K/N₀−1)e^(−r·t))', () {
      const expected = <double>[
        10,
        21.9859623181923,
        47.64682961988097,
        100.18958498803272,
        198.59165968644112,
        355.4609871366469,
        551.0416191943004,
        732.016991720361,
        858.7419548541208,
        931.1749981642813,
        967.8567044042412,
        985.2968346449802,
        993.3395146071528,
      ];
      expect(r.population.length, 13);
      for (var t = 0; t < expected.length; t++) {
        expect(r.population[t], closeTo(expected[t], 1e-6), reason: 't=$t');
      }
    });

    test('K/2 处绝对增长速率 = r·K/4，且是最大点', () {
      expect(r.maxAbsoluteRate, closeTo(200, 1e-12));
      expect(r.absoluteRateAt(r.halfK), closeTo(200, 1e-12));
      expect(r.absoluteRateAt(r.halfK * 0.8), lessThan(200));
      expect(r.absoluteRateAt(r.halfK * 1.2), lessThan(200));
      expect(r.relativeRateAt(r.halfK), closeTo(0.4, 1e-12),
          reason: 'r·(1−1/2) = r/2');
      expect(r.absoluteRateAt(10), closeTo(7.92, 1e-12),
          reason: 'r·N₀·(1−N₀/K) = 0.8·10·0.99');
    });

    test('K/2 首次达到的采样代 = 6（N₅<500≤N₆），精确时刻 t*=ln(99)/0.8', () {
      expect(r.halfKStart, HalfKStart.below);
      expect(r.passesHalfK, isTrue);
      expect(r.halfKGeneration, 6);
      expect(r.population[5], lessThan(500));
      expect(r.population[6], greaterThanOrEqualTo(500));
      expect(r.halfKTime, closeTo(5.743899812668238, 1e-9));
    });
  });

  group('S 型：边界姿态', () {
    test('r=0 ⇒ 恒为 N₀（不突然跳 K、不抖动）', () {
      final r = logisticGrowth(n0: 37, k: 1000, r: 0, generations: 12);
      expect(r.population.every((v) => v == 37), isTrue);
      expect(r.isAtEquilibrium, isTrue);
      expect(r.halfKTime, isNull, reason: 'r=0 永远到不了 K/2');
      expect(r.halfKGeneration, isNull);
      expect(r.halfKStart, HalfKStart.below);
      expect(r.passesHalfK, isFalse,
          reason: '数量恒定 ⇒ 不经过 K/2（与 halfKTime 同一口径，⛔ 不许分叉）');
    });

    test('N₀ = K ⇒ 恒为 K', () {
      final r = logisticGrowth(n0: 1000, k: 1000, r: 0.9, generations: 8);
      expect(r.population.every((v) => (v - 1000).abs() < 1e-9), isTrue);
      expect(r.halfKStart, HalfKStart.above);
      expect(r.halfKTime, isNull);
    });

    test('N₀ > K ⇒ 单调下降、始终在 K 之上、从上方趋近 K', () {
      final r = logisticGrowth(n0: 2000, k: 1000, r: 0.8, generations: 12);
      expect(r.population.first, 2000);
      for (var t = 1; t < r.population.length; t++) {
        expect(r.population[t], lessThan(r.population[t - 1]), reason: 't=$t');
        expect(r.population[t], greaterThan(1000), reason: 't=$t 不得穿到 K 以下');
      }
      expect(r.population.last, closeTo(1000.0339, 1e-3));
      expect(r.halfKStart, HalfKStart.above);
      expect(r.halfKTime, isNull, reason: '起点在 K/2 之上，之后不再经过');
      expect(r.halfKGeneration, isNull);
    });

    test('N₀ = K/2 ⇒ 起点即最大增长点（t*=0）', () {
      final r = logisticGrowth(n0: 500, k: 1000, r: 0.8, generations: 3);
      expect(r.halfKStart, HalfKStart.at);
      expect(r.halfKGeneration, 0);
      expect(r.halfKTime, 0);
      expect(r.absoluteRateAt(r.n0), closeTo(r.maxAbsoluteRate, 1e-12));
    });

    test('K/2 < N₀ < K ⇒ 仍在增长趋势（不是回落），且不再经过 K/2', () {
      final r = logisticGrowth(n0: 800, k: 1000, r: 0.8, generations: 5);
      expect(r.halfKStart, HalfKStart.above);
      expect(r.passesHalfK, isFalse);
      expect(r.halfKGeneration, isNull);
      expect(r.population.last, greaterThan(r.population.first));
      expect(r.population.last, lessThan(1000));
    });
  });

  group('端点与非法输入', () {
    test('代数端点：1 与 40 合法', () {
      expect(jShapedGrowth(n0: 10, lambda: 1.1, generations: 1).population.length, 2);
      expect(
          jShapedGrowth(n0: 10, lambda: 1.1, generations: 40).population.length,
          41);
      expect(
          logisticGrowth(n0: 10, k: 1000, r: 0.8, generations: 40)
              .population
              .length,
          41);
    });

    test('代数 0 / 41 报错并点名范围', () {
      for (final g in [0, 41]) {
        expect(
          () => jShapedGrowth(n0: 10, lambda: 1.5, generations: g),
          throwsA(isA<ArgumentError>().having(
              (e) => e.message.toString(), 'message', contains('1–40'))),
          reason: 'g=$g',
        );
        expect(
          () => logisticGrowth(n0: 10, k: 1000, r: 0.8, generations: g),
          throwsA(isA<ArgumentError>()),
          reason: 'g=$g',
        );
      }
    });

    test('N₀ ≤ 0 / NaN / Infinity / 超上限 都报错', () {
      for (final n in [0.0, -1.0, double.nan, double.infinity, 1e12]) {
        expect(() => jShapedGrowth(n0: n, lambda: 1.5, generations: 3),
            throwsA(isA<ArgumentError>()),
            reason: 'n0=$n');
        expect(() => logisticGrowth(n0: n, k: 1000, r: 0.8, generations: 3),
            throwsA(isA<ArgumentError>()),
            reason: 'n0=$n');
      }
    });

    test('λ / r / K 越界都报错', () {
      for (final l in [-0.1, 10.5, double.nan]) {
        expect(() => jShapedGrowth(n0: 10, lambda: l, generations: 3),
            throwsA(isA<ArgumentError>()),
            reason: 'λ=$l');
      }
      for (final rr in [-0.1, 5.5, double.nan]) {
        expect(() => logisticGrowth(n0: 10, k: 1000, r: rr, generations: 3),
            throwsA(isA<ArgumentError>()),
            reason: 'r=$rr');
      }
      for (final kk in [0.0, -100.0, double.infinity]) {
        expect(() => logisticGrowth(n0: 10, k: kk, r: 0.8, generations: 3),
            throwsA(isA<ArgumentError>()),
            reason: 'K=$kk');
      }
    });

    test('溢出：N₀=1e9、λ=10、40 代 ⇒ 报错并点名 1e15（⛔ 不画假曲线）', () {
      expect(
        () => jShapedGrowth(n0: 1e9, lambda: 10, generations: 40),
        throwsA(isA<ArgumentError>().having(
            (e) => e.message.toString(), 'message', contains('1e15'))),
      );
    });
  });

  group('对照入口', () {
    test('comparePopulationGrowth：同一 N₀ / 代数，两条曲线都算出', () {
      final c = comparePopulationGrowth(
          n0: 10, lambda: 2, k: 500, r: 0.5, generations: 8);
      expect(c.generations, 8);
      expect(c.j.generations, 8);
      expect(c.s.population.length, 9);
      expect(c.j.population[8], closeTo(10 * 256, 1e-9));
      expect(c.s.k, 500);
      expect(c.s.n0, 10);
    });

    test('对照里任一曲线非法 ⇒ 整体抛错（不留半套结果）', () {
      expect(
        () => comparePopulationGrowth(
            n0: 10, lambda: 1.5, k: -1, r: 0.8, generations: 5),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  group('屏上数值格式（单一真相）', () {
    test('整数不带小数点、两位小数去尾 0、非有限给 —', () {
      expect(formatPopulationNumber(1000), '1000');
      expect(formatPopulationNumber(1297.46337890625), '1297.46');
      expect(formatPopulationNumber(22.5), '22.5');
      expect(formatPopulationNumber(100), '100');
      expect(formatPopulationNumber(0.00533), '0.01');
      expect(formatPopulationNumber(double.nan), '—');
      expect(formatPopulationNumber(double.infinity), '—');
    });
  });
}
