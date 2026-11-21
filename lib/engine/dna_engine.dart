// dna_engine.dart —— 分子遗传计算引擎（纯 Dart，跨平台）
//
// 课标覆盖：必修2《遗传与进化》3.1.2（DNA双螺旋/碱基互补）、
// 3.1.3（半保留复制）、3.1.4（基因表达 6:3:1）、3.2.1（减数分裂
// 配子种类）。输入输出 double 百分比 / int 计数，无 IO。
// 契约见 docs/PLAN_2.0.md 第三节。

/// DNA 双链碱基组成结果（百分比，A=T、G=C、A+G=T+C=50%）。
class DnaBaseResult {
  final double a;
  final double t;
  final double g;
  final double c;
  const DnaBaseResult({required this.a, required this.t, required this.g, required this.c});

  @override
  String toString() => 'A=$a% T=$t% G=$g% C=$c%';
}

/// DNA 复制结果（半保留，n 次复制）。
class DnaReplicationResult {
  final int copies; // 复制次数 n
  final int dnaMolecules; // 2^n
  final int withParentStrand; // 含亲代链的 DNA 数 = 2
  final int newStrands; // 新合成链数 = 2^(n+1) - 2
  const DnaReplicationResult({
    required this.copies,
    required this.dnaMolecules,
    required this.withParentStrand,
    required this.newStrands,
  });
}

/// 基因表达结果（6:3:1 法则）。
class GeneExpressionResult {
  final int aminoAcids; // 氨基酸数
  final int mrnaBases; // mRNA 碱基数 = 氨基酸×3
  final int geneBases; // 基因（双链 DNA）碱基数 = 氨基酸×6
  const GeneExpressionResult({
    required this.aminoAcids,
    required this.mrnaBases,
    required this.geneBases,
  });
}

/// 双链 DNA 碱基组成计算。
/// 已知任一/两个碱基百分比（%），按 A=T、G=C、A+G=50% 补全其余。
/// 传入两个值时必须满足配对（A 与 T 相等、G 与 C 相等），否则抛错；
/// 传入三个值且第三个与推导矛盾时抛错。至少传入一个值。
DnaBaseResult dnaBaseComposition({double? a, double? t, double? g, double? c}) {
  final known = <String, double>{};
  if (a != null) known['A'] = a;
  if (t != null) known['T'] = t;
  if (g != null) known['G'] = g;
  if (c != null) known['C'] = c;
  if (known.isEmpty) {
    throw ArgumentError('至少输入一个碱基的百分比');
  }
  for (final v in known.values) {
    if (v < 0 || v > 100) throw ArgumentError('碱基百分比应在 0–100 之间');
  }
  // 配对校验：已知两个时若违反 A=T / G=C 则抛错
  void checkPair(String x, String y) {
    final xv = known[x];
    final yv = known[y];
    if (xv != null && yv != null && (xv - yv).abs() > 1e-9) {
      throw ArgumentError('$x 与 $y 必须相等（碱基互补配对：A=T、G=C）');
    }
  }

  checkPair('A', 'T');
  checkPair('G', 'C');

  // 已知值推导：A=T、G=C；A+G=50%
  double pairOf(String x, String y) {
    final xv = known[x];
    final yv = known[y];
    if (xv != null) return xv;
    if (yv != null) return yv;
    return -1; // 未知
  }

  final at = pairOf('A', 'T');
  final gc = pairOf('G', 'C');
  double av, tv, gv, cv;
  if (at >= 0) {
    av = at;
    tv = at;
    if (gc >= 0) {
      gv = gc;
      cv = gc;
      // 验证 A+G = 50
      if ((av + gv - 50).abs() > 1e-9) {
        throw ArgumentError('A+G 应等于 50%（非互补碱基之和为总数一半）');
      }
    } else {
      gv = 50 - av;
      cv = gv;
    }
  } else {
    // 未知 A/T，已知 G/C
    gv = gc;
    cv = gc;
    av = 50 - gv;
    tv = av;
  }
  if (av < 0 || gv < 0) throw ArgumentError('碱基百分比推导结果异常，请检查输入');
  return DnaBaseResult(a: av, t: tv, g: gv, c: cv);
}

/// DNA 半保留复制：n 次复制后的分子数、含亲代链数、新合成链数。
DnaReplicationResult dnaReplication({required int copies}) {
  if (copies < 1) throw ArgumentError('复制次数至少为 1');
  if (copies > 40) throw ArgumentError('复制次数过大（≤40）');
  final molecules = 1 << copies; // 2^n
  return DnaReplicationResult(
    copies: copies,
    dnaMolecules: molecules,
    withParentStrand: 2,
    newStrands: molecules * 2 - 2,
  );
}

/// 基因表达：氨基酸数 → 基因（双链）碱基数与 mRNA 碱基数（6:3:1）。
/// 也支持按 mRNA 碱基数反推（传 mrnaBases 则 aminoAcids 可省）。
GeneExpressionResult geneExpression({int? aminoAcids, int? mrnaBases, int? geneBases}) {
  final int aa;
  if (aminoAcids != null) {
    if (aminoAcids < 1) throw ArgumentError('氨基酸数至少为 1');
    aa = aminoAcids;
  } else if (mrnaBases != null) {
    if (mrnaBases < 3 || mrnaBases % 3 != 0) {
      throw ArgumentError('mRNA 碱基数应为 3 的倍数');
    }
    aa = mrnaBases ~/ 3;
  } else if (geneBases != null) {
    if (geneBases < 6 || geneBases % 6 != 0) {
      throw ArgumentError('基因碱基数应为 6 的倍数');
    }
    aa = geneBases ~/ 6;
  } else {
    throw ArgumentError('请传入氨基酸数 / mRNA 碱基数 / 基因碱基数之一');
  }
  return GeneExpressionResult(
    aminoAcids: aa,
    mrnaBases: aa * 3,
    geneBases: aa * 6,
  );
}

/// 减数分裂配子种类：n 对同源染色体 → 2^n 种（非同源染色体自由组合）。
int gameteKinds({required int chromosomePairs}) {
  if (chromosomePairs < 1) throw ArgumentError('染色体对数至少为 1');
  if (chromosomePairs > 30) throw ArgumentError('染色体对数过大（≤30）');
  return 1 << chromosomePairs;
}