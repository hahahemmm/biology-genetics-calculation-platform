// dna_strand_engine.dart —— DNA 单链比值与标记计算引擎（纯 Dart，跨平台）
//
// v2.2 批次3 新增。覆盖高考常考题型：
//   1. 单链碱基比值换算（双链 DNA 的碱基互补配对推论）：
//      · (A+T)/(G+C)：互补两链相等，且等于全分子比值
//      · (A+G)/(T+C)：互补链互为倒数，全分子 = 1
//   2. DNA 放射性标记（¹⁵N/³H/³²P 半保留复制）：
//      · 标记 DNA 移入无标记培养基复制 n 代后的分子/链比例、离心带型
//      · 细胞有丝分裂标记：第一次/第二次分裂后带标记染色体数
// 输入输出 double / int，无 IO。

/// 单链碱基比值换算结果。
class StrandRatioResult {
  final double chain1; // 已知链（链1）中的比值
  final double chain2; // 互补链（链2）中的比值
  final double whole; // 整个 DNA 分子中的比值
  final String rule; // 换算依据（思维链展示用）
  const StrandRatioResult({
    required this.chain1,
    required this.chain2,
    required this.whole,
    required this.rule,
  });
}

/// (A+T)/(G+C) 型比值：因 A1=T2、T1=A2、G1=C2、C1=G2，
/// 链1 的 (A+T) 等于链2 的 (A+T)，(G+C) 同理——
/// 互补链比值相等，全分子比值也相同。
StrandRatioResult atOverGc(double chain1Ratio) {
  if (chain1Ratio <= 0) throw ArgumentError('比值应为正数');
  return StrandRatioResult(
    chain1: chain1Ratio,
    chain2: chain1Ratio,
    whole: chain1Ratio,
    rule: 'A₁=T₂、T₁=A₂、G₁=C₂、C₁=G₂ → 两链 (A+T) 与 (G+C) 各自相等，'
        '故 (A+T)/(G+C) 在互补链与全分子中均相同。',
  );
}

/// (A+G)/(T+C) 型（嘌呤/嘧啶）比值：链1 的嘌呤 = 链2 的嘧啶，
/// 故互补链比值互为倒数；全分子嘌呤=嘧啶，比值恒为 1。
StrandRatioResult agOverTc(double chain1Ratio) {
  if (chain1Ratio <= 0) throw ArgumentError('比值应为正数');
  return StrandRatioResult(
    chain1: chain1Ratio,
    chain2: 1 / chain1Ratio,
    whole: 1.0,
    rule: '链1 的 (A+G) = 链2 的 (T+C)，链1 的 (T+C) = 链2 的 (A+G) → '
        '互补链比值互为倒数（1/x）；全分子 A+G=T+C，比值恒为 1。',
  );
}

/// 单链碱基数量互推结果：已知链1 各碱基数与 DNA 总碱基数（或按数量
/// 直接给两条链），求链2 各碱基数（A2=T1、T2=A1、G2=C1、C2=G1）。
class StrandComplement {
  final int a1, t1, g1, c1;
  final int a2, t2, g2, c2;
  final int total; // 全分子碱基总数
  const StrandComplement({
    required this.a1, required this.t1, required this.g1, required this.c1,
    required this.a2, required this.t2, required this.g2, required this.c2,
    required this.total,
  });
}

/// 已知一条链上各碱基的数量，求互补链与全分子的碱基组成。
/// （用户场景：「给你两段 DNA 链上 C 和 T 的数量，计算 A 和 G」——
/// 链1 给多少用多少，未知项传 null 则只推能推的部分会报错；此处要求
/// 链1 四种碱基齐全，保证全分子组成完整可算。）
StrandComplement strandComplement({
  required int a1,
  required int t1,
  required int g1,
  required int c1,
}) {
  for (final v in [a1, t1, g1, c1]) {
    if (v < 0) throw ArgumentError('碱基数量不能为负');
  }
  return StrandComplement(
    a1: a1, t1: t1, g1: g1, c1: c1,
    a2: t1, t2: a1, g2: c1, c2: g1,
    total: (a1 + t1 + g1 + c1) * 2,
  );
}

/// 中心法则互推结果：模板链 → mRNA → tRNA 反密码子。
class CentralDogmaResult {
  final String template; // 模板链（按输入书写方向，教学中读作 3'→5'）
  final String coding; // 编码链（互补回模板，T 保留）
  final String mrna; // mRNA（互补模板链，T→U）
  final List<String> codons; // mRNA 密码子（3 个/组）
  final List<String> anticodons; // tRNA 反密码子（与密码子互补，U 体系）
  const CentralDogmaResult({
    required this.template,
    required this.coding,
    required this.mrna,
    required this.codons,
    required this.anticodons,
  });
}

/// 中心法则互推：给 DNA 模板链序列 → 编码链 / mRNA / 密码子 / 反密码子。
///
/// 高中口径：模板链按书写方向读作 3'→5'，mRNA 逐位互补（A→U、T→A、
/// C↔G）；tRNA 反密码子与 mRNA 密码子逐位互补（U 体系）。
/// 题型实证：全国卷转录/翻译/密码子/反密码子 76 次命中（选择题高频）。
CentralDogmaResult centralDogmaFromTemplate(String rawTemplate) {
  final t = rawTemplate.trim().toUpperCase().replaceAll(RegExp(r'\s+'), '');
  if (!RegExp(r'^[ATCG]+$').hasMatch(t)) {
    throw ArgumentError('模板链只能含 A/T/C/G');
  }
  if (t.length % 3 != 0) {
    throw ArgumentError('模板链长度须为 3 的倍数（当前 ${t.length} 位）');
  }
  if (t.length > 30) {
    throw ArgumentError('序列过长（≤30 bp；白板输入以短序列为主）');
  }
  String compDna(String s) => s
      .split('')
      .map((c) => switch (c) {
            'A' => 'T',
            'T' => 'A',
            'C' => 'G',
            'G' => 'C',
            _ => c,
          })
      .join();
  String compRna(String s) => s
      .split('')
      .map((c) => switch (c) {
            'A' => 'U',
            'T' => 'A',
            'C' => 'G',
            'G' => 'C',
            _ => c,
          })
      .join();
  // RNA 字母体系互补（密码子 → 反密码子用：A↔U、C↔G）
  String compRnaRna(String s) => s
      .split('')
      .map((c) => switch (c) {
            'A' => 'U',
            'U' => 'A',
            'C' => 'G',
            'G' => 'C',
            _ => c,
          })
      .join();
  final mrna = compRna(t);
  final codons = [
    for (var i = 0; i < mrna.length; i += 3) mrna.substring(i, i + 3)
  ];
  return CentralDogmaResult(
    template: t,
    coding: compDna(t),
    mrna: mrna,
    codons: codons,
    anticodons: codons.map(compRnaRna).toList(),
  );
}

/// 双链 C/T 计数互推结果（用户高频场景：已知两段链上 C、T 数量，
/// 求全分子的 A、G 及比例）。
class StrandCTResult {
  final int c1, t1, c2, t2; // 已知：链1/链2 的 C、T 数量
  final int aTotal, tTotal, gTotal, cTotal; // 全分子各碱基数量
  final int total; // 全分子碱基总数
  const StrandCTResult({
    required this.c1, required this.t1, required this.c2, required this.t2,
    required this.aTotal, required this.tTotal,
    required this.gTotal, required this.cTotal,
    required this.total,
  });

  /// (A+G)/(T+C) 全分子比值（恒为 1，列出用于核对）。
  double get agOverTcWhole => 1.0;
}

/// v2.19.47 「空格留给你推」：由链1/链2 的 C、T 推**单链各自的 A 与 G**。
///
/// 双链 DNA 互补配对（A₁=T₂、T₁=A₂、G₁=C₂、C₁=G₂，见 :54）⇒ 已知链1/链2
/// 的 C、T，就能推出每条链的 A、G。引擎的 [StrandCTResult] 只给全分子
/// 总量（aTotal/tTotal/gTotal/cTotal），**没给**单链各自的 A 与 G ——
/// 这是互补配对的直接推论（非新数据，是把引擎已写的配对关系算出来）。
class StrandSingleResult {
  final int a1, g1; // 链1 的 A、G（由互补配对推得）
  final int a2, g2; // 链2 的 A、G
  const StrandSingleResult({
    required this.a1, required this.g1,
    required this.a2, required this.g2,
  });
}

/// 已知链1/链2 的 C、T，推单链各自的 A 与 G（互补配对）。
///
/// ⛔ 判据与 [strandCountsFromCT] 同源的负数守卫：输入是引擎给的合法计数，
///    但若传进来负数（数据被换掉），抛错比给错数好。
StrandSingleResult strandSingleFromCT({
  required int c1,
  required int t1,
  required int c2,
  required int t2,
}) {
  for (final v in [c1, t1, c2, t2]) {
    if (v < 0) throw ArgumentError('碱基数量不能为负');
  }
  // 互补配对：A₁=T₂、T₁=A₂、G₁=C₂、C₁=G₂（引擎注释 :54 同构）。
  return StrandSingleResult(
    a1: t2, g1: c2,
    a2: t1, g2: c1,
  );
}

/// 已知链1 与链2 上 C、T 的数量，推全分子 A、T、G、C：
/// A总数 = T总数 = T₁+T₂（因 A₁=T₂、A₂=T₁）；
/// G总数 = C总数 = C₁+C₂（因 G₁=C₂、G₂=C₁）。
StrandCTResult strandCountsFromCT({
  required int c1,
  required int t1,
  required int c2,
  required int t2,
}) {
  for (final v in [c1, t1, c2, t2]) {
    if (v < 0) throw ArgumentError('碱基数量不能为负');
  }
  final at = t1 + t2;
  final gc = c1 + c2;
  return StrandCTResult(
    c1: c1, t1: t1, c2: c2, t2: t2,
    aTotal: at, tTotal: at, gTotal: gc, cTotal: gc,
    total: (at + gc) * 2,
  );
}

/// ¹⁵N/³²P 标记 DNA 半保留复制结果（原料无标记）。
class DnaLabelResult {
  final int generations; // 复制代数 n
  final int totalMolecules; // DNA 分子总数 = 2^n
  final int labeledMolecules; // 含亲代标记链的分子数 = 2（即中带/杂合分子）
  final int unlabeledOnlyMolecules; // 全为无标记链的分子数 = 2^n - 2
  final int labeledStrands; // 含标记的链数 = 2
  final int totalStrands; // 链总数 = 2^(n+1)
  final String centrifugeBands; // 密度梯度离心带型描述
  const DnaLabelResult({
    required this.generations,
    required this.totalMolecules,
    required this.labeledMolecules,
    required this.unlabeledOnlyMolecules,
    required this.labeledStrands,
    required this.totalStrands,
    required this.centrifugeBands,
  });

  /// 含标记分子占比 = 2 / 2^n。
  double get labeledMoleculeRatio => labeledMolecules / totalMolecules;

  /// 含标记链占比 = 2 / 2^(n+1)。
  double get labeledStrandRatio => labeledStrands / totalStrands;
}

/// ¹⁵N 标记的双链 DNA 移入 ¹⁴N（无标记）培养基复制 n 代。
/// 半保留复制：亲代 2 条标记链永不消失，各自始终存在于 1 个分子中。
/// 带型：n=1 全为中带（¹⁵N/¹⁴N 杂合）；n≥2 中带 2 个 + 轻带 2^n-2 个；
/// 重带（¹⁵N/¹⁵N）从复制第一代起即消失。
DnaLabelResult dnaLabelReplication({required int generations}) {
  final n = generations;
  if (n < 1) throw ArgumentError('复制代数至少为 1');
  if (n > 40) throw ArgumentError('复制代数过大（≤40）');
  final total = 1 << n;
  final bands = n == 1
      ? '第 1 代：全部为中带（¹⁵N/¹⁴N 杂合分子），重带消失。'
      : '第 $n 代：中带 2 个（占 ${(2 / total * 100).toStringAsFixed(1)}%），'
          '轻带 ${total - 2} 个（占 ${((total - 2) / total * 100).toStringAsFixed(1)}%）；无重带。';
  return DnaLabelResult(
    generations: n,
    totalMolecules: total,
    labeledMolecules: 2,
    unlabeledOnlyMolecules: total - 2,
    labeledStrands: 2,
    totalStrands: 1 << (n + 1),
    centrifugeBands: bands,
  );
}

/// 细胞有丝分裂标记结果（³H 等标记全部染色体 DNA 双链后，
/// 移入无标记培养基连续分裂）。
class MitosisLabelResult {
  final int chromosomes2n; // 体细胞染色体数 2n
  final int divisions; // 分裂次数（1 或 2）
  final String labeledChromosomes; // 子细胞带标记染色体数（定值或范围）
  final int? labeledChromatidsAtMetaphase; // 该次分裂中期带标记的染色单体数
  final String mechanism; // 机理说明（思维链展示用）
  const MitosisLabelResult({
    required this.chromosomes2n,
    required this.divisions,
    required this.labeledChromosomes,
    required this.labeledChromatidsAtMetaphase,
    required this.mechanism,
  });
}

/// 有丝分裂染色体标记（半保留复制在细胞水平的推论）：
/// - 第 1 次分裂：每条染色体的 DNA 复制为「1 标记链 + 1 新链」的杂合
///   分子，两条姐妹染色单体都带标记 → 子细胞 2n 条染色体全部带标记。
/// - 第 2 次分裂：杂合 DNA 再复制，2 个子 DNA 中只 1 个含旧标记链 →
///   中期每条染色体仅 1 条单体带标记（共 2n 条标记单体）；后期单体随机
///   分向两极（后期细胞暂为 4n 条染色体，其中带标记的恰为 2n 条）→
///   子细胞带标记染色体数 0 ~ 2n（期望 n 条）。
MitosisLabelResult mitosisLabeling({
  required int chromosomes2n,
  required int divisions,
}) {
  if (chromosomes2n < 2 || chromosomes2n % 2 != 0) {
    throw ArgumentError('染色体数应为偶数（2n）');
  }
  if (divisions == 1) {
    return MitosisLabelResult(
      chromosomes2n: chromosomes2n,
      divisions: 1,
      labeledChromosomes: '$chromosomes2n 条（全部）',
      labeledChromatidsAtMetaphase: chromosomes2n * 2,
      mechanism: '亲代 DNA 双链均被标记，无标记原料中复制后每个 DNA 为'
          '「1 标记链+1 新链」杂合分子 → 第一次分裂中期 2n 条染色体的'
          ' 2×2n 条单体全部带标记，子细胞 $chromosomes2n 条染色体全带标记。',
    );
  }
  if (divisions == 2) {
    return MitosisLabelResult(
      chromosomes2n: chromosomes2n,
      divisions: 2,
      labeledChromosomes: '0 ~ $chromosomes2n 条（期望 ${chromosomes2n ~/ 2} 条）；'
          '第二次分裂后期细胞暂为 ${chromosomes2n * 2} 条染色体，其中带标记 $chromosomes2n 条',
      labeledChromatidsAtMetaphase: chromosomes2n,
      mechanism: '第二次复制时杂合 DNA 产生 1 个含标记链、1 个全无标记的'
          '子 DNA → 中期每条染色体只有 1 条单体带标记（共 $chromosomes2n 条'
          '标记单体）；后期姐妹染色单体随机移向两极，子细胞带标记染色体'
          '数为 0~$chromosomes2n，期望 ${chromosomes2n ~/ 2} 条。'
          '（对照：若为减数分裂，只复制一次，4 个子细胞全部含标记。）',
    );
  }
  throw ArgumentError('目前支持第 1 / 第 2 次有丝分裂');
}

/// DNA 复制原料需求：一个 DNA 分子（某碱基含量 m 个）在无标记原料中
/// 复制 n 代，共需游离的该碱基脱氧核苷酸 (2^n − 1) × m 个；
/// 其中第 n 次复制单独需要 2^(n−1) × m 个。
/// （新增 DNA 分子数 = 2^n − 1；第 n 次复制新增 2^(n−1) 个。）
class ReplicationMaterial {
  final int generations;
  final int perMolecule; // 每个 DNA 分子中该碱基（或碱基对）数量 m
  final int totalNeeded; // (2^n − 1) × m
  final int lastRoundNeeded; // 2^(n−1) × m
  const ReplicationMaterial({
    required this.generations,
    required this.perMolecule,
    required this.totalNeeded,
    required this.lastRoundNeeded,
  });
}

ReplicationMaterial replicationMaterial({
  required int generations,
  required int perMolecule,
}) {
  if (generations < 1) throw ArgumentError('复制代数至少为 1');
  if (generations > 30) throw ArgumentError('复制代数过大（≤30）');
  if (perMolecule < 1) throw ArgumentError('每个分子的碱基含量至少为 1');
  return ReplicationMaterial(
    generations: generations,
    perMolecule: perMolecule,
    totalNeeded: ((1 << generations) - 1) * perMolecule,
    lastRoundNeeded: (1 << (generations - 1)) * perMolecule,
  );
}
