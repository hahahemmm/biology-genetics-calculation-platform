// cross_engine.dart —— 杂交引擎（纯 Dart）
//
//
// 本引擎实现遗传杂交的推导：
//   1) 单基因杂交（Aa×Aa、Aa×aa、AA×aa）→ 配子组合 + 基因型比例 + 表型比例
//   2) 双基因独立分配（AaBb×AaBb）→ 9:3:3:1 及其变式（9:7、9:3:4、15:1、1:4:6:4:1 等）
//   3) 修饰模型：不完全显性 / 共显性 / 致死基因（如 AA 致死）
//   4) 回交（backcross，F1 × 隐性亲本）、测交（testcross，× 隐性纯合）
//
// 全部为纯 Dart。数学核心是枚举亲本配子并交叉乘积、统计比例并约分。

import 'models.dart';

/// 修饰模型类型。
enum Modification {
  completeDominance, // 完全显性（默认）：显性/隐性二态
  incompleteDominance, // 不完全显性：Aa 表现出中间表型（如粉色花）
  codominance, // 共显性：Aa 同时表现出两种表型
  lethalDominant, // 致死基因（显性纯合 AA 致死）
  lethalRecessive, // 致死基因（隐性纯合 aa 致死）
}

/// 一次杂交的结果。
class CrossResult {
  final List<String> gametesP1; // 亲本1配子
  final List<String> gametesP2; // 亲本2配子
  final List<GenotypeRatio> genotypeRatios; // 基因型比例（归一化基因型 -> 份数）
  final List<PhenotypeRatio> phenotypeRatios; // 表型比例（表型 -> 份数）
  int get totalGenotype => genotypeRatios.fold(0, (s, r) => s + r.count);
  int get totalPhenotype => phenotypeRatios.fold(0, (s, r) => s + r.count);

  CrossResult({
    required this.gametesP1,
    required this.gametesP2,
    required this.genotypeRatios,
    required this.phenotypeRatios,
  });
}

/// 杂交引擎：对一个或多个基因位点做配子组合与比例推导。
class CrossEngine {
  /// 单基因杂交。输入两个基因型字符串（如 'Aa'、'aa'），返回配子 + 基因型/表型比例。
  ///
  /// [dominant]：显性等位基因字母（如 'A'，大写）。
  /// [recessive]：隐性等位基因字母（如 'a'，小写）。
  /// [modification]：修饰模型，默认完全显性。
  /// [dominantPhenotype] / [recessivePhenotype]：显性 / 隐性表型名，用于结果展示。
  CrossResult singleGeneCross(
    String p1Genotype,
    String p2Genotype, {
    required String dominant,
    required String recessive,
    Modification modification = Modification.completeDominance,
    String dominantPhenotype = '显性',
    String recessivePhenotype = '隐性',
  }) {
    // 解析配子：每个等位基因作为一个配子。
    final g1 = _parseGenes(p1Genotype);
    final g2 = _parseGenes(p2Genotype);
    final gametes1 = <String>[];
    for (final g in g1) {
      if (!gametes1.contains(g)) gametes1.add(g);
    }
    final gametes2 = <String>[];
    for (final g in g2) {
      if (!gametes2.contains(g)) gametes2.add(g);
    }

    // 交叉组合，统计基因型份数（用归一化去重）。
    final genoCnt = <String, int>{};
    final phenoCnt = <String, int>{};
    for (final a in gametes1) {
      for (final b in gametes2) {
        final gen = _normGen(a, b);
        genoCnt[gen] = (genoCnt[gen] ?? 0) + 1;
        final ph = _phenotypeFor(gen, dominant, recessive, modification,
            dominantPhenotype, recessivePhenotype);
        phenoCnt[ph] = (phenoCnt[ph] ?? 0) + 1;
      }
    }

    final gRatios = <GenotypeRatio>[
      ...genoCnt.entries.map((e) => GenotypeRatio(genotype: e.key, count: e.value)),
    ]..sort((x, y) => x.genotype.compareTo(y.genotype));
    final pRatios = <PhenotypeRatio>[
      ...phenoCnt.entries.map((e) => PhenotypeRatio(phenotype: e.key, count: e.value)),
    ]..sort((x, y) => x.phenotype.compareTo(y.phenotype));

    return CrossResult(
      gametesP1: gametes1,
      gametesP2: gametes2,
      genotypeRatios: gRatios,
      phenotypeRatios: pRatios,
    );
  }

  /// 双基因独立分配杂交（如 AaBb × AaBb）。
  ///
  /// [locus1Dominant]/[locus1Recessive]：位点1的显/隐性字母。
  /// [locus2Dominant]/[locus2Recessive]：位点2的显/隐性字母。
  /// 返回配子（如 AB、Ab、aB、ab）、F2 基因型比例与表型比例（9:3:3:1 及各变式）。
  CrossResult dihybridCross(
    String p1Genotype, // 如 'AaBb'
    String p2Genotype, // 如 'AaBb'
    {
    required String locus1Dominant,
    required String locus1Recessive,
    required String locus2Dominant,
    required String locus2Recessive,
    List<String>? phenoLabels, // 4 个表型名，依次对应 [AB, Ab, aB, ab] 显性组合
  }) {
    final l1d = locus1Dominant, l1r = locus1Recessive, l2d = locus2Dominant, l2r = locus2Recessive;
    final g1 = _parseGenes(p1Genotype);
    final g2 = _parseGenes(p2Genotype);

    // 生成每个亲本的配子（等位基因自由组合）。
    final gametes1 = _dihybridGametes(g1);
    final gametes2 = _dihybridGametes(g2);

    final labels = phenoLabels ??
        ['显性显性', '显性隐性', '隐性显性', '隐性隐性'];

    // 统计基因型：key 用「位点1基因型|位点2基因型」。
    final genoCnt = <String, int>{};
    final phenoCnt = <String, int>{};
    for (final a in gametes1) {
      for (final b in gametes2) {
        // a 形如 'AB'，b 形如 'AB'：a[0] & b[0] 是位点1，a[1] & b[1] 是位点2。
        final l1 = _normGen(a[0], b[0]);
        final l2 = _normGen(a[1], b[1]);
        final gkey = '$l1|$l2';
        genoCnt[gkey] = (genoCnt[gkey] ?? 0) + 1;

        // 表型索引：位点1显性?(1):(0) 二位点2显性?(1):(0) → 0..3
        int idx = _dominantOf(l1, l1d) ? 2 : 0;
        idx += _dominantOf(l2, l2d) ? 1 : 0;
        // 映射：idx=0→ab(00) 隐性*, 1→显性2, 2→显性1, 3→双显
        // 更直观：bit0 = 位点2显性?1:0，bit1 = 位点1显性?1:0
        // 标号按 11,10,01,00 → 对应 labels[0..3]=双显,显隐,隐显,双隐
        final phIdx = _phenoIndex(_dominantOf(l1, l1d), _dominantOf(l2, l2d));
        final ph = labels[phIdx];
        phenoCnt[ph] = (phenoCnt[ph] ?? 0) + 1;
      }
    }

    final gRatios = <GenotypeRatio>[
      ...genoCnt.entries
          .map((e) => GenotypeRatio(genotype: e.key.replaceAll('|', ''), count: e.value)),
    ]..sort((x, y) => x.genotype.compareTo(y.genotype));
    final pRatios = <PhenotypeRatio>[
      ...phenoCnt.entries.map((e) => PhenotypeRatio(phenotype: e.key, count: e.value)),
    ];

    return CrossResult(
      gametesP1: gametes1,
      gametesP2: gametes2,
      genotypeRatios: gRatios,
      phenotypeRatios: pRatios,
    );
  }

  /// 对 dihybrid 结果按指定簇聚合，得到 9331 变式。
  ///
  /// [clusters]：一个列表，每个元素是一个「表型名列表」，同簇合并且视为同一表型。
  /// 例如 9:7 → [{双显}, {其他三组都归一组}]。
  /// [labels]：为本簇分别命名。
  /// 返回新的表型比例（已合并 + 按份数排序）。
  List<PhenotypeRatio> aggregatePhenotypes(
    CrossResult result,
    List<List<String>> clusters,
    List<String> clusterNames,
  ) {
    final cnt = <String, int>{};
    for (final pr in result.phenotypeRatios) {
      int found = -1;
      for (int c = 0; c < clusters.length; c++) {
        if (clusters[c].contains(pr.phenotype)) {
          found = c;
          break;
        }
      }
      final name = found >= 0 ? clusterNames[found] : pr.phenotype;
      cnt[name] = (cnt[name] ?? 0) + pr.count;
    }
    final out = <PhenotypeRatio>[
      ...cnt.entries.map((e) => PhenotypeRatio(phenotype: e.key, count: e.value)),
    ]..sort((x, y) => y.count.compareTo(x.count));
    return out;
  }

  /// 测交（testcross）：F1 × 隐性纯合。返回配子 + 比例。
  CrossResult testcross(
    String f1Genotype, {
    required String dominant,
    required String recessive,
    String dominantPhenotype = '显性',
    String recessivePhenotype = '隐性',
  }) {
    return singleGeneCross(
      f1Genotype,
      '$recessive$recessive',
      dominant: dominant,
      recessive: recessive,
      dominantPhenotype: dominantPhenotype,
      recessivePhenotype: recessivePhenotype,
    );
  }

  /// 回交（backcross）：F1 × 亲本（此处简化为 F1 与任意亲本基因型杂交）。
  CrossResult backcross(
    String f1Genotype,
    String parentGenotype, {
    required String dominant,
    required String recessive,
    String dominantPhenotype = '显性',
    String recessivePhenotype = '隐性',
  }) {
    return singleGeneCross(
      f1Genotype,
      parentGenotype,
      dominant: dominant,
      recessive: recessive,
      dominantPhenotype: dominantPhenotype,
      recessivePhenotype: recessivePhenotype,
    );
  }

  // ---------- 内部工具 ----------

  /// 解析基因型字符串为等位基因列表（如 'AaBb' → ['A','a','B','b']）。
  List<String> _parseGenes(String s) {
    final res = <String>[];
    for (final ch in s.split('')) {
      res.add(ch);
    }
    return res;
  }

  /// 双显性配子：输入 ['A','a','B','b'] → ['AB','Ab','aB','ab']。
  List<String> _dihybridGametes(List<String> genes) {
    // 位点1 = 前两个，位点2 = 后两个
    final g1 = [genes[0], genes[1]];
    final g2 = [genes[2], genes[3]];
    final res = <String>[];
    for (final a in g1) {
      for (final b in g2) {
        res.add('$a$b');
      }
    }
    return res;
  }

  /// 归一化两个等位基因为基因型串（显性在前）。
  String _normGen(String a, String b) {
    // 两个小写相同 (a,a) -> 'aa'（隐性纯合）
    if (a == b) return a + b; // AA 或 aa
    final au = a.toUpperCase();
    final bu = b.toUpperCase();
    if (au != bu) {
      final aUp = a == au;
      final bUp = b == bu;
      if (aUp && !bUp) return au + bu.toLowerCase();
      if (bUp && !aUp) return bu + au.toLowerCase();
      return au.compareTo(bu) < 0 ? '$au$bu' : '$bu$au';
    } else {
      return au + au.toLowerCase(); // Aa / aA
    }
  }

  /// 判定某基因型是否含显性位点（用于注释语义：跟显性字母一致即显性）。
  bool _dominantOf(String gen, String dominantAllele) {
    return gen.contains(dominantAllele);
  }

  /// 双基因表型索引：传入两个位点的显性布尔，返回 0..3。
  /// bit1=位点1显性，bit0=位点2显性。返回：11→0, 10→1, 01→2, 00→3。
  int _phenoIndex(bool d1, bool d2) {
    final bits = (d1 ? 2 : 0) | (d2 ? 1 : 0);
    // 3=11(双显)→0; 2=10→1; 1=01→2; 0=00→3
    switch (bits) {
      case 3:
        return 0; // 双显
      case 2:
        return 1; // 位点1显
      case 1:
        return 2; // 位点2显
      default:
        return 3; // 双隐
    }
  }

  /// 计算单基因表型串（含修饰模型）。
  String _phenotypeFor(
    String gen,
    String dominant,
    String recessive,
    Modification mod,
    String domPh,
    String recPh,
  ) {
    switch (mod) {
      case Modification.incompleteDominance:
        // Aa → 中间表型「杂合」；AA → 显性；aa → 隐性
        if (gen.contains(dominant) && gen.contains(recessive)) {
          return '中间型(${gen[0]}${gen[1]})';
        }
        return gen.contains(recessive) && !gen.contains(dominant)
            ? recPh
            : domPh;
      case Modification.codominance:
        if (gen.contains(dominant) && gen.contains(recessive)) {
          return '共显($dominant$recessive)';
        }
        return gen.contains(recessive) && !gen.contains(dominant) ? recPh : domPh;
      case Modification.lethalDominant:
        // 显性纯合 AA 致死，不计入存活后代
        return gen == '$dominant$dominant' ? '致死' : (gen.contains(recessive) && !gen.contains(dominant) ? recPh : domPh);
      case Modification.lethalRecessive:
        return gen == '$recessive$recessive' ? '致死' : (gen.contains(dominant) ? domPh : recPh);
      case Modification.completeDominance:
      default:
        return gen.contains(recessive) && !gen.contains(dominant) ? recPh : domPh;
    }
  }
}
