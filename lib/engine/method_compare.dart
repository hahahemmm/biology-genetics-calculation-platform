// method_compare.dart —— 分解法 vs 配子法 对比引擎（纯 Dart）
//
// 教学背景（高考遗传计算两大方法）：
//   配子法：列出双亲全部配子，两两组合（Punnett 方阵），
//     n 对杂合基因 → 2^n × 2^n = 4^n 个格子，指数爆炸。
//   分解法：每对基因单独算（分离定律），再把各位点结果相乘，
//     n 对基因 → n 个 3:1 / 1:2:1，组合数线性增长。
// 本模块对同一组亲本同时跑两种方法，验证结果一致，
// 并量化「格子数 vs 分解步数」的效率差，让学生直观看到为什么要分解。

import 'fraction.dart';
import 'genetics_env.dart';

/// 单个位点的分解结果。
class LocusBreakdown {
  final String label; // 位点对，如 'Aa'
  final String crossLabel; // 如 'Aa × Aa'
  final Map<String, Fraction> phenotypeDist; // {'显性': 3/4, '隐性': 1/4}

  const LocusBreakdown({
    required this.label,
    required this.crossLabel,
    required this.phenotypeDist,
  });

  /// 整数比，如 [3, 1]。
  List<int> get integerRatio =>
      GeneticsEnv.toIntegerRatio(phenotypeDist.values);
}

/// 两种方法的完整对比结果。
class MethodComparison {
  final String p1;
  final String p2;
  final int lociCount;

  // —— 配子法 ——
  final List<String> gametesP1; // 亲本1 配子标签
  final List<String> gametesP2;
  final List<List<String>> punnett; // punnett[i][j] = g1[i] × g2[j] 子代基因型
  final int cellCount; // 方阵格子数 = len(g1) × len(g2)

  // —— 分解法 ——
  final List<LocusBreakdown> loci; // 每个位点单独的结果

  // —— 共同结论（两法一致）——
  final Map<String, Fraction> phenotypeDist; // 表型 → 精确比例
  final List<int> integerRatio; // 表型整数比

  const MethodComparison({
    required this.p1,
    required this.p2,
    required this.lociCount,
    required this.gametesP1,
    required this.gametesP2,
    required this.punnett,
    required this.cellCount,
    required this.loci,
    required this.phenotypeDist,
    required this.integerRatio,
  });

  /// 效率对比文案用：分解法只需处理 lociCount 个单位点。
  int get decomposeSteps => lociCount;
}

/// 计算同一组亲本的配子法 / 分解法对比。
/// 支持 1–3 对独立遗传位点（3 对时方阵 64 格，UI 仅统计不展开）。
MethodComparison compareMethods(String p1, String p2) {
  final probe = GeneticsEnv();
  final pairs1 = probe.parseGenotype(p1);
  final pairs2 = probe.parseGenotype(p2);
  if (pairs1.length != pairs2.length) {
    throw ArgumentError('双亲位点数必须一致：$p1 vs $p2');
  }
  if (pairs1.isEmpty || pairs1.length > 3) {
    throw ArgumentError('支持 1–3 对位点，当前 ${pairs1.length} 对');
  }
  // 校验位点字母一致
  for (var i = 0; i < pairs1.length; i++) {
    if (pairs1[i][0].toUpperCase() != pairs2[i][0].toUpperCase()) {
      throw ArgumentError('第 ${i + 1} 对位点字母不一致：'
          '${pairs1[i].join()} vs ${pairs2[i].join()}');
    }
  }

  final env = GeneticsEnv()
    ..addLoci(pairs1.map((p) => p[0].toUpperCase() + p[0].toLowerCase()).join());

  final n1 = env.normalize(p1);
  final n2 = env.normalize(p2);

  // —— 配子法 ——
  final g1map = env.gametesOf(n1);
  final g2map = env.gametesOf(n2);
  final g1 = g1map.keys.toList();
  final g2 = g2map.keys.toList();
  final punnett = <List<String>>[
    for (final a in g1)
      [
        for (final b in g2)
          env.normalize(_interleave(a, b)),
      ],
  ];

  // —— 分解法：每对位点单独杂交 ——
  final breakdowns = <LocusBreakdown>[];
  for (var i = 0; i < pairs1.length; i++) {
    final locus1 = pairs1[i].join();
    final locus2 = pairs2[i].join();
    final single = GeneticsEnv()..addLoci(locus1);
    final dist = single.cross(locus1, locus2);
    final pheno = single.phenotypeDist(dist);
    breakdowns.add(LocusBreakdown(
      label: locus1,
      crossLabel: '${single.normalize(locus1)} × ${single.normalize(locus2)}',
      phenotypeDist: pheno,
    ));
  }

  // —— 共同结论 ——
  final fullDist = env.cross(n1, n2);
  final phenoDist = env.phenotypeDist(fullDist);
  final ratio = GeneticsEnv.toIntegerRatio(phenoDist.values);

  return MethodComparison(
    p1: n1,
    p2: n2,
    lociCount: pairs1.length,
    gametesP1: g1,
    gametesP2: g2,
    punnett: punnett,
    cellCount: g1.length * g2.length,
    loci: breakdowns,
    phenotypeDist: phenoDist,
    integerRatio: ratio,
  );
}

/// 把两个配子按位点交错合并：'AB' + 'aB' → 'AaBB'（未归一化）。
String _interleave(String a, String b) {
  final sb = StringBuffer();
  for (var i = 0; i < a.length; i++) {
    sb.write(a[i]);
    sb.write(b[i]);
  }
  return sb.toString();
}
