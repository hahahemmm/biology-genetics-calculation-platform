// gene_frequency.dart —— 基因频率与自然选择引擎（纯 Dart，double）
//
// 覆盖课标：
//   4.2.1 种群内可遗传变异赋予个体生存与繁殖优势（基因频率计算·变异输入）
//   4.2.2 优势性状个体占比增加（选择压力模拟·淘汰隐性纯合）
//   4.2.3 自然选择促进适应（逐代定向选择模拟）
//
// 三个能力：
//   1. calcGeneFrequency  由三种基因型个体数 → 基因型频率 + 基因频率，
//                          并与哈迪-温伯格平衡（p²/2pq/q²）比对，判断是否处于遗传平衡。
//   2. hardyWeinbergPredict 由 p、q 预测下一代基因型频率（p²、2pq、q²）。
//   3. simulateSelection   哈迪-温伯格起步，逐代淘汰隐性纯合（aa 致死/不育），
//                          观察 a 基因频率逐代下降（经典数列 q → q/(1+q)）。

/// 三种基因型的个体数输入。
class GenotypeCounts {
  final int aa;
  final int aA;
  final int AA;

  const GenotypeCounts({
    required this.aa,
    required this.aA,
    required this.AA,
  });

  /// 个体总数。
  int get total => aa + aA + AA;
}

/// 基因频率/基因型频率计算结果。
class GeneFrequencyResult {
  /// 显性纯合基因型频率 AA。
  final double freqAA;

  /// 杂合基因型频率 Aa。
  final double freqAa;

  /// 隐性纯合基因型频率 aa。
  final double freqaa;

  /// 显性基因 A 的频率。
  final double freqA;

  /// 隐性基因 a 的频率。
  final double freqa;

  /// 是否符合哈迪-温伯格平衡（|freqAA−p²|<0.001 且 |freqAa−2pq|<0.001 且 |freqaa−q²|<0.001）。
  final bool inEquilibrium;

  /// 教学说明（可为 null）。
  final String? note;

  const GeneFrequencyResult({
    required this.freqAA,
    required this.freqAa,
    required this.freqaa,
    required this.freqA,
    required this.freqa,
    required this.inEquilibrium,
    this.note,
  });
}

/// 逐代选择模拟结果。
class SelectionSimResult {
  /// 每代 a 基因频率，第 0 项为初始 q0。
  final List<double> qPerGen;

  /// 每代 A 基因频率（= 1 − q），第 0 项为初始 p0。
  final List<double> pPerGen;

  /// 本次模拟使用的选择系数 s（aa 适合度 = 1 − s；1 = 完全淘汰，0 = 无选择）。
  final double selectionS;

  const SelectionSimResult({
    required this.qPerGen,
    required this.pPerGen,
    required this.selectionS,
  });
}

/// 由三种基因型个体数计算基因型频率与基因频率。
///
/// - fearqA = (2×AA + Aa) / (2×总数)，freqa = 1 − freqA。
/// - 与哈迪-温伯格平衡预测比对给出 [GeneFrequencyResult.inEquilibrium]。
/// - [aa]、[aA]、[AA] 任一为负，或总数 == 0，抛 [ArgumentError]。
GeneFrequencyResult calcGeneFrequency({
  required int aa,
  required int aA,
  required int AA,
}) {
  if (aa < 0 || aA < 0 || AA < 0) {
    throw ArgumentError('个体数不能为负：aa=$aa, aA=$aA, AA=$AA');
  }
  final total = aa + aA + AA;
  if (total == 0) {
    throw ArgumentError('个体总数不能为 0');
  }

  final freqAA = AA / total;
  final freqAa = aA / total;
  final freqaa = aa / total;
  final freqA = (2 * AA + aA) / (2 * total);
  final freqa = 1 - freqA;

  final p = freqA;
  final q = freqa;
  final inEquilibrium = (freqAA - p * p).abs() < 0.001 &&
      (freqAa - 2 * p * q).abs() < 0.001 &&
      (freqaa - q * q).abs() < 0.001;

  final note = inEquilibrium
      ? '符合哈迪-温伯格平衡：基因型频率与预测的 p²/2pq/q² 一致'
      : '不符合哈迪-温伯格平衡：基因型频率偏离 p²/2pq/q²，'
          '群体可能受到自然选择、突变、迁移等因素影响';

  return GeneFrequencyResult(
    freqAA: freqAA,
    freqAa: freqAa,
    freqaa: freqaa,
    freqA: freqA,
    freqa: freqa,
    inEquilibrium: inEquilibrium,
    note: note,
  );
}

/// 哈迪-温伯格平衡预测：由 p、q 预测下一代基因型频率。
///
/// 返回 freqAA=p²、freqAa=2pq、freqaa=q²，恒为平衡状态。
/// [p]、[q] 须 ∈ [0,1] 且 |p+q−1|<1e-9，否则抛 [ArgumentError]。
GeneFrequencyResult hardyWeinbergPredict({
  required double p,
  required double q,
}) {
  if (p.isNaN || q.isNaN || p < 0 || p > 1 || q < 0 || q > 1) {
    throw ArgumentError('p 与 q 必须在 [0,1] 区间内：p=$p, q=$q');
  }
  if ((p + q - 1).abs() >= 1e-9) {
    throw ArgumentError('p 与 q 之和必须为 1');
  }

  return GeneFrequencyResult(
    freqAA: p * p,
    freqAa: 2 * p * q,
    freqaa: q * q,
    freqA: p,
    freqa: q,
    inEquilibrium: true,
    note: '哈迪-温伯格平衡预测：AA=p²、Aa=2pq、aa=q²',
  );
}

/// 逐代选择模拟：哈迪-温伯格起步，模拟 [generations] 代。
///
/// 每代按随机交配得基因型频率（AA=p²、Aa=2pq、aa=q²），对隐性纯合 aa
/// 施加选择系数 s（aa 适合度 w = 1 − s），标准适合度选择递推：
///   平均适合度 w̄ = 1 − s·q²
///   新 q = (pq + q²(1−s)) / w̄      （a 等位基因来自 Aa 一半 + 全部 aa）
///
/// 参数二选一（都传且语义矛盾则抛 [ArgumentError]）：
/// - [selectionAgainstAa]：选择系数 s ∈ [0,1]。s=1 完全淘汰（aa 致死/
///   不育，退化为经典 q → q/(1+q) 数列）；s=0 无选择（q 不变）；中间值
///   即教材「桦尺蛾」类部分选择场景（w_aa = 1−s）。
/// - [cullRecessive]：旧布尔 API（v2.13 起弃用但保留兼容）——true 等价
///   s=1，false 等价 s=0。
///
/// 返回列表含初始代：第 0 项为 q0，共 generations+1 项。
/// [q0] 必须在开区间 (0,1) 内、[generations] 必须为正，否则抛 [ArgumentError]。
SelectionSimResult simulateSelection({
  required double q0,
  required int generations,
  bool? cullRecessive,
  double? selectionAgainstAa,
}) {
  final double s;
  if (selectionAgainstAa != null) {
    if (selectionAgainstAa.isNaN ||
        selectionAgainstAa < 0 ||
        selectionAgainstAa > 1) {
      throw ArgumentError('选择系数 s 必须在 [0,1] 内：s=$selectionAgainstAa');
    }
    if (cullRecessive != null &&
        ((cullRecessive && selectionAgainstAa != 1) ||
            (!cullRecessive && selectionAgainstAa != 0))) {
      throw ArgumentError(
          'cullRecessive 与 selectionAgainstAa 语义冲突：cull=$cullRecessive, s=$selectionAgainstAa');
    }
    s = selectionAgainstAa;
  } else if (cullRecessive != null) {
    s = cullRecessive ? 1 : 0;
  } else {
    throw ArgumentError('必须指定选择强度：selectionAgainstAa（推荐）或 cullRecessive（旧 API）');
  }

  if (q0.isNaN || q0 <= 0 || q0 >= 1) {
    throw ArgumentError('q0 必须在开区间 (0,1) 内：q0=$q0');
  }
  if (generations <= 0) {
    throw ArgumentError('世代数必须为正整数：generations=$generations');
  }

  final qPerGen = <double>[q0];
  var q = q0;
  for (var g = 0; g < generations; g++) {
    final p = 1 - q;
    final wBar = 1 - s * q * q;
    q = (p * q + q * q * (1 - s)) / wBar;
    qPerGen.add(q);
  }

  final pPerGen = qPerGen.map((q) => 1 - q).toList();
  return SelectionSimResult(
      qPerGen: qPerGen, pPerGen: pPerGen, selectionS: s);
}