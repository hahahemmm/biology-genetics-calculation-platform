// kaoji_calc.dart —— 9331 计算器（纯 Dart）
//
//
// 输入亲本基因型 → 输出配子类型、F2 基因型比例、F2 表型比例（9331 及全套变式），
// 数值化输出（整数比，自动约分）。
//
// 本文件是对 cross_engine.dart 的高层封装：面向「9331 及其变式」这一类题目，
// 提供更直接的 API（如 dihybrid9331、变式识别），并给出整数比输出。

import 'dart:collection';

import 'models.dart';
import 'cross_engine.dart';
import 'variant_spec.dart';
import 'utils.dart';

/// 9331 及变式的计算结果。
class KaojiCalcResult {
  final List<String> gametesP1;
  final List<String> gametesP2;
  final Ratio genotypeRatio; // F2 基因型整数比（如 1:2:1:2:4:2:1:2:1）
  final Ratio phenotypeRatio; // F2 表型整数比（如 9:3:3:1 / 9:7 / 15:1 ...）
  final String variantName; // 变式名称，如「标准 9331」「9:7」「1:4:6:4:1」等
  final List<String> genotypeLabels; // 各基因型的标签（与 genotypeRatio 对齐）
  final List<String> phenotypeLabels; // 各表型的标签（与 phenotypeRatio 对齐）

  KaojiCalcResult({
    required this.gametesP1,
    required this.gametesP2,
    required this.genotypeRatio,
    required this.phenotypeRatio,
    required this.variantName,
    required this.genotypeLabels,
    required this.phenotypeLabels,
  });
}

/// 9331 计算器。
class KaojiCalc {
  final CrossEngine _engine = CrossEngine();

  /// 标准双基因杂交（默认 9:3:3:1）。
  KaojiCalcResult dihybrid9331({
    String p1 = 'AaBb',
    String p2 = 'AaBb',
    String l1d = 'A',
    String l1r = 'a',
    String l2d = 'B',
    String l2r = 'b',
    List<String> phenoLabels = const ['AB', 'Ab', 'aB', 'ab'],
  }) {
    final r = _engine.dihybridCross(
      p1,
      p2,
      locus1Dominant: l1d,
      locus1Recessive: l1r,
      locus2Dominant: l2d,
      locus2Recessive: l2r,
      phenoLabels: phenoLabels,
    );

    final genoRatio = Ratio(
      r.genotypeRatios.map((e) => e.count).toList(),
    ).reduced();
    final phenoRatio = Ratio(r.phenotypeRatios.map((e) => e.count).toList()).reduced();

    return KaojiCalcResult(
      gametesP1: r.gametesP1,
      gametesP2: r.gametesP2,
      genotypeRatio: genoRatio,
      phenotypeRatio: phenoRatio,
      variantName: phenoRatio.equalsValues(const [9, 3, 3, 1])
          ? VariantSpec.shortName(VariantSpec.standard9331)
          : '自定义',
      genotypeLabels: r.genotypeRatios.map((e) => e.genotype).toList(),
      phenotypeLabels: r.phenotypeRatios.map((e) => e.phenotype).toList(),
    );
  }

  /// 生成经典变式比例，基于标准 9:3:3:1 的份数合并。
  ///
  /// [mode] 取值见 [VariantSpec.all]：
  ///   '9331'   → 9:3:3:1          （双显/单显1/单显2/双隐 分开）
  ///   '9_7'    → 9:7               （9 双显 / 其余合并）
  ///   '9_3_4'  → 9:3:4             （9 双显 / 3 单显1 / 其余合并）
  ///   '15_1'   → 15:1              （只要有一个显性表现双显类 / 双隐）
  ///   '1_4_6_4_1' → 1:4:6:4:1     （按显性基因数量 0/1/2/3/4 分档，需数量型）
  ///
  /// 返回该变式对应的整数表型比。
  Ratio variantRatio(String mode) =>
      Ratio(VariantSpec.ratioFor(mode));

  /// 封装：给定变式模式，返回该变式的命名 + 比值字符串（约分后）。
  String variantString(String mode) {
    final r = variantRatio(mode).reduced();
    return '$mode → ${r.toString()}';
  }

  /// 常见变式的清单（供 UI 展示）。v2.11 M11b 改为委托 VariantSpec.all，
  /// 保持 KaojiCalc.knownVariants 公开 API 不变。
  static const List<String> knownVariants = VariantSpec.all;
}

/// 自动倍性/位点数识别的通用杂交结果。
class AutoCrossResult {
  final KaojiCalcResult? result; // 计算成功时非空
  final String? error; // 阻断性输入错误（中文），此时 result 为 null
  final String? notice; // 非阻断提示（三倍体场景用），此时 result 为 null
  final int ploidy; // 1=一倍体 2=二倍体 3=三倍体 0=无法解析
  final int loci; // 位点（基因对）数，无法解析为 0

  const AutoCrossResult({
    this.result,
    this.error,
    this.notice,
    this.ploidy = 0,
    this.loci = 0,
  });
}

/// crossAuto 的内部解析结果：位点分组或错误。
class _ParsedGenotype {
  final List<List<String>> groups; // 每个元素是一个位点的等位基因列表
  final String? error;
  final int ploidy;
  final int loci;

  const _ParsedGenotype({
    this.groups = const [],
    this.error,
    this.ploidy = 0,
    this.loci = 0,
  });
}

/// n 对基因 + 倍性自适应的通用杂交计算。
extension KaojiCalcAuto on KaojiCalc {
  /// 自动识别位点数与倍性并计算杂交结果。
  ///
  /// 基因型书写规则：同一对基因的等位基因相邻书写（如 AaBbCc）。
  /// 一倍体（如 AB × ab）按单倍体杂交处理；三倍体返回 notice 不计算比例。
  AutoCrossResult crossAuto({required String p1, required String p2}) {
    final g1 = _parseGenotype(p1);
    if (g1.error != null) {
      return AutoCrossResult(error: g1.error, ploidy: g1.ploidy, loci: g1.loci);
    }
    final g2 = _parseGenotype(p2);
    if (g2.error != null) {
      return AutoCrossResult(error: g2.error, ploidy: g2.ploidy, loci: g2.loci);
    }
    if (g1.loci != g2.loci || g1.ploidy != g2.ploidy) {
      return AutoCrossResult(
        error: '两个亲本的位点数与倍性须一致（如 AaBb × AaBb）',
        ploidy: g1.ploidy,
        loci: g1.loci,
      );
    }
    final loci = g1.loci;
    final ploidy = g1.ploidy;
    if (loci > 6) {
      return AutoCrossResult(
        error: '暂支持 1~6 对基因（当前输入 $loci 对）',
        ploidy: ploidy,
        loci: loci,
      );
    }
    if (ploidy > 3) {
      return AutoCrossResult(
        error: '暂不支持四倍体及以上',
        ploidy: ploidy,
        loci: loci,
      );
    }
    if (ploidy == 3) {
      return AutoCrossResult(
        notice: '三倍体减数分裂时染色体联会紊乱，通常高度不育，无法给出标准遗传比例',
        ploidy: ploidy,
        loci: loci,
      );
    }

    final gametes1 = _gametesOf(g1.groups);
    final gametes2 = _gametesOf(g2.groups);

    // 合子组合：每位点两个等位归一化（显性大写在前）后拼接。
    final genoCounts = <String, int>{};
    for (final a in gametes1) {
      for (final b in gametes2) {
        final buf = StringBuffer();
        for (var i = 0; i < loci; i++) {
          buf.write(_normalizePair(a[i], b[i]));
        }
        final g = buf.toString();
        genoCounts[g] = (genoCounts[g] ?? 0) + 1;
      }
    }

    // 表型：每位点含大写显性等位→显（大写字母），否则隐（小写字母）。
    final phenoCounts = <String, int>{};
    for (final e in genoCounts.entries) {
      final buf = StringBuffer();
      for (var i = 0; i < loci; i++) {
        final pair = e.key.substring(i * 2, i * 2 + 2);
        final dominant = hasUpperAscii(pair);
        buf.write(dominant ? pair[0].toUpperCase() : pair[0].toLowerCase());
      }
      final p = buf.toString();
      phenoCounts[p] = (phenoCounts[p] ?? 0) + e.value;
    }

    final genoSorted = genoCounts.entries.toList()..sort(_entryCmp);
    final phenoSorted = phenoCounts.entries.toList()..sort(_entryCmp);

    final genoRatio = Ratio(genoSorted.map((e) => e.value).toList()).reduced();
    final phenoRatio = Ratio(phenoSorted.map((e) => e.value).toList()).reduced();

    final String variantName;
    if (ploidy == 1) {
      variantName = '单倍体杂交';
    } else if (loci == 2 && phenoRatio.equalsValues(const [9, 3, 3, 1])) {
      variantName = VariantSpec.shortName(VariantSpec.standard9331);
    } else if (loci == 3 && phenoRatio.equalsValues(const [27, 9, 9, 9, 3, 3, 3, 1])) {
      // v2.5：三对基因标准自由组合（AaBbCc 自交），追加分支不动既有判定。
      variantName = '标准 27:9:9:9:3:3:3:1';
    } else {
      variantName = '$loci 对基因（自定义）';
    }

    return AutoCrossResult(
      result: KaojiCalcResult(
        gametesP1: gametes1,
        gametesP2: gametes2,
        genotypeRatio: genoRatio,
        phenotypeRatio: phenoRatio,
        variantName: variantName,
        genotypeLabels: genoSorted.map((e) => e.key).toList(),
        phenotypeLabels: phenoSorted.map((e) => e.key).toList(),
      ),
      ploidy: ploidy,
      loci: loci,
    );
  }

  /// 按「相邻同字母（忽略大小写）」分组解析基因型。
  static _ParsedGenotype _parseGenotype(String raw) {
    final s = raw.trim();
    if (s.isEmpty) {
      return const _ParsedGenotype(error: '基因型不能为空');
    }
    if (!RegExp(r'^[A-Za-z]+$').hasMatch(s)) {
      return const _ParsedGenotype(error: '仅支持字母 A-Z');
    }
    final groups = <List<String>>[];
    for (var i = 0; i < s.length; i++) {
      final c = s[i];
      if (groups.isNotEmpty &&
          groups.last.first.toLowerCase() == c.toLowerCase()) {
        groups.last.add(c);
      } else {
        groups.add([c]);
      }
    }
    // 同字母非相邻重复（如 ABab）。
    final seen = <String>{};
    for (final g in groups) {
      final letter = g.first.toLowerCase();
      if (!seen.add(letter)) {
        return const _ParsedGenotype(
          error: '同一对基因的等位基因必须相邻书写（如 AaBb）',
        );
      }
    }
    // 同一亲本内各位点组大小须一致。
    final size = groups.first.length;
    if (groups.any((g) => g.length != size)) {
      return _ParsedGenotype(
        error: '两个亲本的位点数与倍性须一致（如 AaBb × AaBb）',
        loci: groups.length,
      );
    }
    return _ParsedGenotype(groups: groups, ploidy: size, loci: groups.length);
  }

  /// 生成配子：一倍体=自身各等位拼接；二倍体=各位点等位笛卡尔积（去重保序）。
  static List<String> _gametesOf(List<List<String>> groups) {
    var gametes = <String>[''];
    for (final locus in groups) {
      final next = <String>[];
      for (final prefix in gametes) {
        for (final allele in locus) {
          next.add(prefix + allele);
        }
      }
      gametes = next;
    }
    return LinkedHashSet<String>.from(gametes).toList();
  }

  /// 同位点两等位归一：显性大写在前。三种情形全对：
  /// AA→'AA'、Aa/aA→'Aa'、aa→'aa'。
  ///（v2.4 修复：旧版 AA 误归一为 'Aa'，纯合显性合子被并进杂合计数。）
  static String _normalizePair(String c1, String c2) {
    final upper = c1.toUpperCase();
    final lower = c1.toLowerCase();
    final dom1 = c1 == upper;
    final dom2 = c2 == upper;
    if (dom1 && dom2) return upper + upper;
    if (!dom1 && !dom2) return lower + lower;
    return upper + lower;
  }

  /// 份数降序，同份数按标签字典序。
  static int _entryCmp(MapEntry<String, int> a, MapEntry<String, int> b) {
    final c = b.value.compareTo(a.value);
    return c != 0 ? c : a.key.compareTo(b.key);
  }
}
