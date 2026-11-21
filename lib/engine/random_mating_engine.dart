// random_mating_engine.dart —— 自由交配（随机交配）引擎（纯 Dart，精确分数）
//
// 高考高频考点：群体自由交配 vs 自交 是两类完全不同的推导。
//   自交：每个个体只与自己交配，杂合子逐代减半。
//   自由交配：群体内任意个体随机结合——两种教学解法：
//     配子法：先求群体配子库（各等位基因频率），配子随机结合
//             →  Hardy-Weinberg 平衡（p²、2pq、q²），一步出结果。
//     枚举法：列出所有交配组合（含概率），逐对算子代再加权合并。
// 本引擎同时给出两种方法的结果（必然一致），并支持：
//   - 任意初始群体（Map<基因型, 频率>，自动归一化）
//   - 多对独立位点（复用 GeneticsEnv 的配子生成）
//   - 致死/选择（通过 GeneticsEnv 注册致死规则，逐代淘汰）
//   - 逐代自由交配（无选择时一代即达平衡，之后保持稳定）
//
// 输出全程 Fraction：如 1/3 AA + 2/3 Aa 群体自由交配 → AA 4/9、Aa 4/9、aa 1/9。

import 'fraction.dart';
import 'genetics_env.dart';

/// 一种交配组合（无序对）及其子代。
class MatingPair {
  final String parent1; // 归一化基因型
  final String parent2;
  final Fraction probability; // 该交配组合出现的概率（含 2× 异型组合）

  /// 该组合的子代基因型分布（已应用致死存活率，未归一化）。
  /// 各项之和 = 该组合的子代存活率（无致死时为 1）。
  /// 多组合加权合并后由引擎统一归一化——逐组合归一化会放大
  /// 高死亡率组合的贡献，是自由交配题的经典错误。
  final Map<String, Fraction> offspring;

  const MatingPair({
    required this.parent1,
    required this.parent2,
    required this.probability,
    required this.offspring,
  });

  String get label =>
      parent1 == parent2 ? '$parent1 自交' : '$parent1 × $parent2';

  /// 该组合的子代存活率（无致死时为 1）。
  Fraction get survivalRate {
    var s = Fraction.zero;
    offspring.forEach((_, p) => s = s + p);
    return s;
  }
}

/// 一代自由交配的完整结果。
class RandomMatingResult {
  /// 输入群体（归一化后，频率和为 1）。
  final Map<String, Fraction> population;

  /// 群体配子库：Map<配子, 频率>（配子法的中间结果）。
  final Map<String, Fraction> gametePool;

  /// 全部交配组合（枚举法明细，按概率降序）。
  final List<MatingPair> matings;

  /// 子代基因型分布（两种方法合并结果，必然一致）。
  final Map<String, Fraction> offspringGenotypes;

  /// 子代表型分布。
  final Map<String, Fraction> offspringPhenotypes;

  const RandomMatingResult({
    required this.population,
    required this.gametePool,
    required this.matings,
    required this.offspringGenotypes,
    required this.offspringPhenotypes,
  });

  /// 表型整数比（如 [3, 1]）。
  List<int> get phenotypeRatio =>
      GeneticsEnv.toIntegerRatio(offspringPhenotypes.values);

  /// 基因型整数比。
  List<int> get genotypeRatio =>
      GeneticsEnv.toIntegerRatio(offspringGenotypes.values);
}

/// 自由交配引擎。
class RandomMatingEngine {
  final GeneticsEnv env;

  /// [env] 可预注册位点、致死规则与表型规则；
  /// 默认空环境（完全显性、无致死）。
  RandomMatingEngine({GeneticsEnv? env}) : env = env ?? GeneticsEnv();

  /// 校验并归一化群体：键归一化、同基因型频率合并、总和归一到 1。
  Map<String, Fraction> normalizePopulation(Map<String, Fraction> population) {
    if (population.isEmpty) {
      throw ArgumentError('群体不能为空');
    }
    final merged = <String, Fraction>{};
    population.forEach((genotype, freq) {
      if (freq.compareTo(Fraction.zero) <= 0) {
        throw ArgumentError('频率必须为正数：$genotype → $freq');
      }
      final n = env.normalize(genotype);
      merged[n] = (merged[n] ?? Fraction.zero) + freq;
    });
    var total = Fraction.zero;
    merged.forEach((_, f) => total = total + f);
    final out = <String, Fraction>{};
    merged.forEach((k, v) => out[k] = v / total);
    return out;
  }

  /// 群体配子库：Σ(基因型频率 × 该基因型的配子分布)。
  Map<String, Fraction> gametePoolOf(Map<String, Fraction> population) {
    final pool = <String, Fraction>{};
    population.forEach((genotype, freq) {
      env.gametesOf(genotype).forEach((gamete, p) {
        pool[gamete] = (pool[gamete] ?? Fraction.zero) + freq * p;
      });
    });
    return pool;
  }

  /// 一代自由交配。
  RandomMatingResult randomMate(Map<String, Fraction> population) {
    final pop = normalizePopulation(population);
    final pool = gametePoolOf(pop);

    // —— 枚举法：无序配对，i≠j 概率 2·pi·pj，i==j 概率 pi² ——
    final genotypes = pop.keys.toList();
    final matings = <MatingPair>[];
    for (var i = 0; i < genotypes.length; i++) {
      for (var j = i; j < genotypes.length; j++) {
        final p = i == j
            ? pop[genotypes[i]]! * pop[genotypes[j]]!
            : Fraction.of(2) * pop[genotypes[i]]! * pop[genotypes[j]]!;
        matings.add(MatingPair(
          parent1: genotypes[i],
          parent2: genotypes[j],
          probability: p,
          offspring: env.crossUnnormalized(genotypes[i], genotypes[j]),
        ));
      }
    }
    matings.sort((a, b) => b.probability.compareTo(a.probability));

    // —— 合并子代并整体归一化（枚举法加权；与配子库法等价）——
    // 关键：先加权合并（致死组合的贡献按存活率自然缩水），再统一归一化。
    final merged = <String, Fraction>{};
    for (final m in matings) {
      m.offspring.forEach((gen, p) {
        merged[gen] = (merged[gen] ?? Fraction.zero) + m.probability * p;
      });
    }
    final offspring = _normalizeDist(merged);

    return RandomMatingResult(
      population: pop,
      gametePool: pool,
      matings: matings,
      offspringGenotypes: offspring,
      offspringPhenotypes: env.phenotypeDist(offspring),
    );
  }

  Map<String, Fraction> _normalizeDist(Map<String, Fraction> dist) {
    var total = Fraction.zero;
    dist.forEach((_, p) => total = total + p);
    if (total.isZero) return dist;
    final out = <String, Fraction>{};
    dist.forEach((k, v) => out[k] = v / total);
    return out;
  }

  /// 逐代自由交配：第 1 代子代 = randomMate(初始群体)，
  /// 之后每一代以上一代子代为新群体。
  ///
  /// 无选择时一代即达 Hardy-Weinberg 平衡并保持稳定；
  /// 有致死规则时体现逐代淘汰（如 aa 致死 → a 频率逐代下降）。
  /// 返回长度 [generations] 的列表，第 0 项是第一代子代。
  List<RandomMatingResult> generations(
      Map<String, Fraction> population, int generations) {
    if (generations < 1) {
      throw ArgumentError('代数至少为 1：$generations');
    }
    final out = <RandomMatingResult>[];
    var current = population;
    for (var g = 0; g < generations; g++) {
      final r = randomMate(current);
      out.add(r);
      current = r.offspringGenotypes;
    }
    return out;
  }
}
