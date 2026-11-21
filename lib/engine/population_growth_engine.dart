// population_growth_engine.dart —— 种群增长引擎（J 型 / S 型，纯 Dart）
//
// 科学口径（全仓唯一真相；屏上文案与测试都按这里复算）：
//
//  · J 型（离散代际；假设资源空间无限、λ 固定）：
//      N_t = N₀ · λᵗ
//      λ > 1 增长、λ = 1 稳定、0 < λ < 1 下降、λ = 0 后一直为 0（归零）。
//      相对增长率恒为 λ − 1（不随 N 变化）；
//      绝对新增量 N_{t+1} − N_t = N_t · (λ − 1)。
//
//  · S 型（连续 Logistic；只考虑环境容纳量 K）：
//      N_t = K / (1 + (K/N₀ − 1) · e^(−r·t))
//      r = 0 ⇒ 恒为 N₀（不会突然跳到 K）；N₀ > K ⇒ 从上方回落到 K。
//      绝对增长速率 dN/dt = r·N·(1 − N/K)；
//      相对增长率 = (1/N)·dN/dt = r·(1 − N/K)；
//      K/2 处绝对增长速率 = r·K/4 —— 只有曲线真的经过 K/2 时，
//      这一点才能叫「最大增长点」（N₀ ≥ K/2 时不许编造以后会经过）。
//
//  · 步数（代数）1..40；输入与输出都查 NaN / Infinity / 越界——
//    ⛔ 绝不把溢出值当曲线画出来（假曲线比没有曲线更糟）。

import 'dart:math' as math;

/// 代数下限（0 代 = 只有初始点，没有趋势可看）。
const int kPopGrowthMinGenerations = 1;

/// 代数上限（课堂演示够用；再长屏幕上也读不出逐代差异）。
const int kPopGrowthMaxGenerations = 40;

/// J 型每代增长倍数 λ 的教学上限。
const double kPopGrowthMaxLambda = 10;

/// S 型内禀增长率 r 的教学上限。
const double kPopGrowthMaxR = 5;

/// N₀ / K 的输入上限（超过它就不是一道课堂题了）。
const double kPopGrowthMaxInitialPopulation = 1e9;

/// 计算结果的上限：超过它说明指数增长已爆表，宁可报错也不画假曲线。
const double kPopGrowthMaxPopulationValue = 1e15;

/// J 型曲线随 λ 的走向。
enum JShapeTrend {
  grow('增长'),
  stable('稳定'),
  decline('下降'),
  extinct('归零');

  const JShapeTrend(this.label);

  /// 屏上可读的中文标签。
  final String label;
}

/// S 型起点 N₀ 相对 K/2 的位置。
enum HalfKStart {
  /// N₀ < K/2：曲线会（在某个 t > 0）经过 K/2。
  below,

  /// N₀ = K/2：起点就在 K/2。
  at,

  /// N₀ > K/2：起点已在 K/2 之上，之后不会再经过 K/2
  /// （N₀ > K 时从上方回落到 K；K/2 < N₀ < K 时继续增长趋近 K）。
  above,
}

/// J 型（离散代际）计算结果。
class JShapedResult {
  const JShapedResult({
    required this.n0,
    required this.lambda,
    required this.generations,
    required this.population,
  });

  final double n0;
  final double lambda;
  final int generations;

  /// 第 0..generations 代的数量（长度 = generations + 1，第 0 项为 N₀）。
  final List<double> population;

  /// 相对增长率（每代恒定）：λ − 1。
  double get relativeGrowthRate => lambda - 1;

  /// 由第 t 代到第 t+1 代的绝对新增量 N_t·(λ−1)（长度 = generations）。
  List<double> get increments => [
        for (var t = 0; t < generations; t++) population[t] * (lambda - 1),
      ];

  /// λ 决定的走向。
  JShapeTrend get trend => lambda > 1
      ? JShapeTrend.grow
      : lambda == 1
          ? JShapeTrend.stable
          : lambda > 0
              ? JShapeTrend.decline
              : JShapeTrend.extinct;

  /// 末代数量。
  double get finalPopulation => population.last;
}

/// S 型（连续 Logistic）计算结果。
class LogisticResult {
  const LogisticResult({
    required this.n0,
    required this.k,
    required this.r,
    required this.population,
  });

  final double n0;
  final double k;
  final double r;

  /// 第 0..generations 代的数量（长度 = generations + 1，第 0 项为 N₀）。
  final List<double> population;

  /// K/2（绝对增长速率最大的位置）。
  double get halfK => k / 2;

  /// 理论上限的最大绝对增长速率 r·K/4（个/代）。
  double get maxAbsoluteRate => r * k / 4;

  /// 起点 N₀ 相对 K/2 的位置（决定能否把 K/2 称作这条曲线的最大增长点）。
  HalfKStart get halfKStart => n0 < halfK
      ? HalfKStart.below
      : n0 == halfK
          ? HalfKStart.at
          : HalfKStart.above;

  /// 这条曲线是否会经过（或起点就在）K/2。
  ///
  /// ⚠️ 不能只看 [halfKStart]：r = 0 且 N₀ < K/2 时数量恒为 N₀，
  /// 永远到不了 K/2 ⇒ 必须与 [halfKTime] 同一口径（此处也返回 false）。
  bool get passesHalfK =>
      halfKStart == HalfKStart.at ||
      (halfKStart == HalfKStart.below && r > 0);

  /// 首次达到 K/2 的代数；不会经过则为 null（N₀ > K/2 时为 null）。
  int? get halfKGeneration {
    if (halfKStart == HalfKStart.above) return null;
    for (var t = 0; t < population.length; t++) {
      if (population[t] >= halfK) return t;
    }
    return null;
  }

  /// 连续模型解出「经过 K/2 的时刻」t*（可为小数）：
  ///   t* = ln((K−N₀)/N₀) / r
  ///
  /// - N₀ = K/2 ⇒ 0（起点就在 K/2）；
  /// - N₀ > K/2 ⇒ null（起点已在上面，之后不会再经过）；
  /// - r = 0 ⇒ null（数量不变，永远到不了 K/2）；
  /// - 否则为正值（即使超过当前代的采样范围也给得出精确时刻，供文案用）。
  double? get halfKTime {
    if (n0 == halfK) return 0;
    if (n0 > halfK) return null;
    if (r <= 0) return null;
    final numerator = k - n0; // N₀ < K/2 ⇒ 一定 > 0
    if (numerator <= 0) return null;
    return math.log(numerator / n0) / r;
  }

  /// 绝对增长速率 dN/dt = r·N·(1 − N/K)（个/代）。
  double absoluteRateAt(double n) => r * n * (1 - n / k);

  /// 相对增长率（每个个体每代）= r·(1 − N/K)。
  double relativeRateAt(double n) => r * (1 - n / k);

  /// 末代数量。
  double get finalPopulation => population.last;

  bool get isAtEquilibrium => r == 0;
}

/// 同一组输入下 J 型与 S 型的对照结果（两段曲线、同一时间轴）。
class PopulationGrowthComparison {
  const PopulationGrowthComparison({required this.j, required this.s});

  final JShapedResult j;
  final LogisticResult s;

  /// 代数（两条曲线共用）。
  int get generations => j.generations;
}

/// J 型增长：N_t = N₀·λᵗ（离散代际）。
///
/// [n0] 必须有限且 ∈ (0, 1e9]；[lambda] ∈ [0, 10]；
/// [generations] ∈ [1, 40]。越界 / NaN / 溢出抛 [ArgumentError]。
JShapedResult jShapedGrowth({
  required double n0,
  required double lambda,
  required int generations,
}) {
  _checkPopulation('初始数量 N0', n0);
  _checkGenerations(generations);
  if (!lambda.isFinite) {
    throw ArgumentError('λ 必须是有限数（当前 $lambda）');
  }
  if (lambda < 0 || lambda > kPopGrowthMaxLambda) {
    throw ArgumentError('λ 必须在 0–$kPopGrowthMaxLambda 之间'
        '（0 = 下一代全部死亡，当前 $lambda）');
  }

  final population = <double>[n0];
  for (var t = 1; t <= generations; t++) {
    population.add(population[t - 1] * lambda);
  }
  _checkValues('J 型数量', population);
  return JShapedResult(
    n0: n0,
    lambda: lambda,
    generations: generations,
    population: population,
  );
}

/// S 型增长：N_t = K / (1 + (K/N₀ − 1)·e^(−r·t))（连续 Logistic）。
///
/// [n0] 必须有限且 ∈ (0, 1e9]；[k] 必须有限且 ∈ (0, 1e9]；
/// [r] ∈ [0, 5]；[generations] ∈ [1, 40]。
/// r = 0 时恒为 N₀（不做离散递推，不出现 overshoot / 负值）。
LogisticResult logisticGrowth({
  required double n0,
  required double k,
  required double r,
  required int generations,
}) {
  _checkPopulation('初始数量 N0', n0);
  _checkPopulation('环境容纳量 K', k);
  _checkGenerations(generations);
  if (!r.isFinite) {
    throw ArgumentError('内禀增长率 r 必须是有限数（当前 $r）');
  }
  if (r < 0 || r > kPopGrowthMaxR) {
    throw ArgumentError('内禀增长率 r 必须在 0–$kPopGrowthMaxR 之间'
        '（当前 $r）');
  }

  final ratio = k / n0 - 1; // N₀ > K 时为负
  final population = <double>[
    for (var t = 0; t <= generations; t++)
      // r = 0 ⇒ e^0 = 1 ⇒ K/(1 + K/N₀ − 1) = N₀，恒不多不少。
      k / (1 + ratio * math.exp(-r * t)),
  ];
  _checkValues('S 型数量', population);
  return LogisticResult(
    n0: n0,
    k: k,
    r: r,
    population: population,
  );
}

/// J 型 + S 型对照（同一 N₀ / 代数，各自用自己的模型参数）。
PopulationGrowthComparison comparePopulationGrowth({
  required double n0,
  required double lambda,
  required double k,
  required double r,
  required int generations,
}) {
  final j = jShapedGrowth(n0: n0, lambda: lambda, generations: generations);
  final s =
      logisticGrowth(n0: n0, k: k, r: r, generations: generations);
  return PopulationGrowthComparison(j: j, s: s);
}

/// 屏上数值格式：整数不带小数点，其余最多两位小数（去掉尾随 0）。
///
/// 单一真相：屏上逐代表格、参考线标签与测试期望值都走这一个函数，
/// ⛔ 不许各处 `toStringAsFixed` 各写一套（同一个数两个写法必分叉）。
String formatPopulationNumber(double v) {
  if (!v.isFinite) return '—';
  final rounded = v.roundToDouble();
  if ((v - rounded).abs() < 1e-9) return rounded.toStringAsFixed(0);
  var s = v.toStringAsFixed(2);
  while (s.endsWith('0')) {
    s = s.substring(0, s.length - 1);
  }
  if (s.endsWith('.')) s = s.substring(0, s.length - 1);
  return s;
}

// ─── 校验 ──────────────────────────────────────────────────────

void _checkPopulation(String name, double v) {
  if (!v.isFinite) {
    throw ArgumentError('$name 必须是有限数（当前 $v）');
  }
  if (v <= 0) {
    throw ArgumentError('$name 必须大于 0（当前 $v）');
  }
  if (v > kPopGrowthMaxInitialPopulation) {
    throw ArgumentError(
        '$name 超出教学范围（须 ≤ 1e9，当前 $v）');
  }
}

void _checkGenerations(int generations) {
  if (generations < kPopGrowthMinGenerations ||
      generations > kPopGrowthMaxGenerations) {
    throw ArgumentError('代数必须在 $kPopGrowthMinGenerations–'
        '$kPopGrowthMaxGenerations 之间（当前 $generations）');
  }
}

void _checkValues(String name, List<double> values) {
  for (final v in values) {
    if (!v.isFinite) {
      throw ArgumentError('$name 计算溢出（出现非有限数），请减小输入');
    }
    if (v > kPopGrowthMaxPopulationValue) {
      throw ArgumentError('$name 超过 1e15，超出教学范围'
          '（指数增长会迅速爆表），请减小 N0、λ/r 或代数');
    }
    if (v < 0) {
      throw ArgumentError('$name 出现负值（当前 $v），请检查输入');
    }
  }
}
