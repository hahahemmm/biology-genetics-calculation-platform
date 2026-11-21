// phenotype_grouper.dart —— 表型归组引擎（纯 Dart，零 Flutter 依赖）
//
// 核心能力：
//   1) 位点解析：连续相同字母（忽略大小写）视为同一位点，位点内字符数不固定，
//      从而同时容忍二倍体（Aa）与多倍体（AAaa / Aaaa）；
//      不同位点字母不同（A、B、C…），故按字母归组即可，无需固定每 2 字符切。
//   2) 完全显性判定：位点内含任意大写等位基因即显性；全小写或 '-'（缺失）判隐性。
//   3) 伴性特殊处理：X/Y 不参与常染色体分组；Y 不携带等位基因、不影响判定，
//      X 染色体上的等位基因含大写即 X显，否则 X隐。
//   4) 归组聚合：同表型成员概率求和，按概率降序、概率相同按 label 字典序输出。

/// 一个待归组的基因型及其概率权重。
class GenotypeSample {
  final String genotype;   // 如 'AaBb'、'AABB'、'AaB-'(缺失)、'XBY'(伴性)、'AAaa'(多倍体)
  final double probability;
  const GenotypeSample(this.genotype, this.probability);
}

/// 一个表型组：同组基因型合并后的总概率 + 成员。
class PhenotypeGroup {
  final String label;          // 人话表型名，例如 'A显·B显'
  final double probability;    // 组内成员概率之和
  final List<String> genotypes;// 成员基因型（保持传入顺序）
  const PhenotypeGroup(
      {required this.label, required this.probability, required this.genotypes});
}

/// 按完全显性把基因型归组；结果按概率降序、概率相同按 label 字典序。
List<PhenotypeGroup> groupByPhenotype(List<GenotypeSample> samples) {
  final labels = <String>[]; // 表型出现顺序，供组内成员按传入顺序聚合
  final sums = <String, double>{};
  final members = <String, List<String>>{};
  for (final s in samples) {
    final label = _labelOf(s.genotype);
    if (!sums.containsKey(label)) {
      labels.add(label);
      sums[label] = 0;
      members[label] = <String>[];
    }
    sums[label] = sums[label]! + s.probability;
    members[label]!.add(s.genotype); // 保持传入顺序
  }
  final groups = [
    for (final l in labels)
      PhenotypeGroup(label: l, probability: sums[l]!, genotypes: members[l]!),
  ];
  groups.sort((a, b) {
    final byProb = b.probability.compareTo(a.probability); // 概率降序
    return byProb != 0 ? byProb : a.label.compareTo(b.label); // 同概率按 label 字典序
  });
  return groups;
}

/// 基因型字符串 → 表型标签（如 'A显·B隐'）。
String _labelOf(String genotype) {
  // 常染色体位点：字母 → 该位点全部字符（含 '-' 缺失）；Map 插入序即位点出现序。
  final loci = <String, List<String>>{};
  final sexAlleles = <String>[]; // X 染色体上携带的等位基因
  String? current; // 当前常染色体位点字母，'-' 并入前一位点
  final chars = genotype.split('');
  for (int i = 0; i < chars.length; i++) {
    final c = chars[i];
    if (c == 'X' || c == 'Y') {
      // 性染色体：X 紧跟的非 X/Y 字符是其等位基因；Y 不带等位基因、直接忽略
      current = null;
      if (c == 'X') {
        final next = i + 1 < chars.length ? chars[i + 1] : null;
        if (next != null && next != 'X' && next != 'Y') {
          sexAlleles.add(next);
          i++;
        } else {
          sexAlleles.add('-'); // X 无等位基因（缺失）
        }
      }
      continue;
    }
    if (c == '-') {
      // 缺失等位基因并入前一个位点（'B-' 是 B 位点缺一个等位基因）
      if (current != null) loci[current]!.add(c);
      continue;
    }
    final letter = c.toUpperCase();
    current = letter;
    loci.putIfAbsent(letter, () => <String>[]).add(c);
  }

  final parts = <String>[];
  loci.forEach((letter, alleles) {
    // 全缺失位点没有字母可标注，跳过（shortcut: 罕见输入不输出该位点，出现需求再补 '?显/隐'）
    if (alleles.every((c) => c == '-')) return;
    final dominant = alleles.any((c) => c != c.toLowerCase()); // 含大写即显性
    parts.add('$letter${dominant ? '显' : '隐'}');
  });
  if (sexAlleles.isNotEmpty) {
    final dominant = sexAlleles.any((c) => c != c.toLowerCase());
    parts.add('X${dominant ? '显' : '隐'}'); // 伴性标签统一放末尾
  }
  return parts.join('·');
}
