// models.dart —— 生物遗传领域模型
//
//
// 本文件定义遗传学的基础领域模型：
//   Gene（等位基因，如 A/a）、Trait（性状：显性/隐性）、Genotype（基因型，如 Aa）、
//   Phenotype（表型）、Individual（个体）、PhenotypeRatio / GenotypeRatio（表型比 / 基因型比）。
//
// 这些模型是引擎层的「名词」，引擎通过对它们的组合来推导杂交、比例、系谱等结果。
// 全部为纯 Dart，不依赖 Flutter 与任何平台 API。

import 'utils.dart';

/// 显性 / 隐性 标记。
///
/// 生物学语义：
///  - 显性（dominant）：只要含有一个显性等位基因（如 Aa 或 AA）即表现显性性状。
///  - 隐性（recessive）：必须两个都是隐性等位基因（aa）才表现隐性性状。
enum Dominance { dominant, recessive }

/// 单个性状（如「豌豆粒形」这一性状）。
///
/// [dominantAllele]：显性等位基因字母（如 'R'）。
/// [recessiveAllele]：隐性等位基因字母（如 'r'）。
/// [phenotypeNames]：表型名称映射，键为显性表型/隐性表型，便于显示。
class Trait {
  final String name; // 性状名，如「粒形」「花色」
  final String dominantAllele; // 显性等位基因字母
  final String recessiveAllele; // 隐性等位基因字母
  final String dominantPhenotype; // 显性表型名，如「圆粒」
  final String recessivePhenotype; // 隐性表型名，如「皱粒」

  const Trait({
    required this.name,
    required this.dominantAllele,
    required this.recessiveAllele,
    required this.dominantPhenotype,
    required this.recessivePhenotype,
  });

  /// 该性状是否含有某个等位基因字母。
  bool containsAllele(String allele) =>
      allele == dominantAllele || allele == recessiveAllele;
}

/// 单个等位基因（如 A 或 a）。
///
/// [symbol]：字母，如 'A'。
/// [dominance]：显性或隐性。
class Gene {
  final String symbol;
  final Dominance dominance;

  const Gene(this.symbol, this.dominance);

  bool get isDominant => dominance == Dominance.dominant;

  @override
  String toString() => symbol;
}

/// 单个基因位点的一对等位基因（如 Aa、AA、aa）。
///
/// 生物学语义：
///  - 纯合（homozygous）：两个等位基因相同（AA 或 aa）。
///  - 杂合（heterozygous）：两个等位基因不同（Aa）。
///
/// [sortAlleles]：把两个等位基因排序（显性在前），保证 Aa 与 aA 归一为 Aa，
///              便于比例统计与去重。
class Genotype {
  final String allele1; // 如 'A'
  final String allele2; // 如 'a'

  Genotype(this.allele1, this.allele2) {
    // 注意：等位基因可以相同（纯合体 AA / aa 是合法基因型），因此不禁用相等。
    if (allele1.length != 1 || allele2.length != 1) {
      throw ArgumentError('等位基因必须是单字符：$allele1 / $allele2');
    }
  }

  /// 归一化后的基因型字符串（显性字母在前），如 Aa / AA / ab。
  String get normalized {
    // 关键：两个小写相同等位基因 (a,a) -> 'aa'，绝不能改写成 Aa
    if (allele1 == allele2) return allele1 + allele2; // 'AA' 或 'aa'
    final au = allele1.toUpperCase();
    final bu = allele2.toUpperCase();
    if (au != bu) {
      final aUp = allele1 == au;
      final bUp = allele2 == bu;
      if (aUp && !bUp) return au + bu.toLowerCase();
      if (bUp && !aUp) return bu + au.toLowerCase();
      return au.compareTo(bu) < 0 ? '$au$bu' : '$bu$au';
    } else {
      return au + au.toLowerCase(); // Aa / aA
    }
  }

  bool get isHomozygous => allele1 == allele2;
  bool get isHeterozygous => allele1 != allele2;

  @override
  String toString() => normalized;

  @override
  bool operator ==(Object other) =>
      other is Genotype && other.normalized == normalized;

  @override
  int get hashCode => normalized.hashCode;
}

/// 个体（一个生物体）。
///
/// [genotypes]：各基因位点的基因型，键为位点名（如 'R'，即该位点的显性字母作 key）。
/// [traits]：各性状定义，用于把基因型解释为表型。
/// [sex]：性别（'M'/'F'），用于伴性遗传计算；未知可为 null。
class Individual {
  final Map<String, Genotype> genotypes; // 位点名(key 用显性字母) -> 基因型
  final Map<String, Trait> traits; // 位点名 -> 该位点性状定义
  final String? sex; // 'M' / 'F'，伴性遗传用

  Individual({
    required this.genotypes,
    required this.traits,
    this.sex,
  });

  /// 取某位点的基因型。
  Genotype genotypeOf(String locus) => genotypes[locus]!;

  /// 计算该个体的表型（显性/隐性表型 key）。
  ///
  /// 对于单一显隐性关系：AA/Aa → 显性表型；aa → 隐性表型。
  /// 返回「表型名」字符串，供上层显示与统计。
  Map<String, String> phenotypes() {
    final result = <String, String>{};
    traits.forEach((locus, trait) {
      final g = genotypes[locus]!;
      String phenotype;
      if (g.allele1 == trait.recessiveAllele &&
          g.allele2 == trait.recessiveAllele) {
        phenotype = trait.recessivePhenotype;
      } else {
        phenotype = trait.dominantPhenotype;
      }
      result[locus] = phenotype;
    });
    return result;
  }
}

/// 表型比例：一种表型出现次数 / 总次数。
class PhenotypeRatio {
  final String phenotype; // 表型描述，如「黄圆」「绿皱」或「显性:隐性」组合
  final int count; // 该表型出现的份数（计数单位）

  const PhenotypeRatio({required this.phenotype, required this.count});

  @override
  String toString() => '$phenotype=$count';
}

/// 基因型比例：一种基因型出现次数 / 总次数。
class GenotypeRatio {
  final String genotype; // 基因型描述，如 Aa
  final int count;

  const GenotypeRatio({required this.genotype, required this.count});

  @override
  String toString() => '$genotype=$count';
}

/// 整数比（约分后的比例），用于 9331 及变式输出，例如 9:3:3:1。
class Ratio {
  final List<int> parts;

  const Ratio(this.parts);

  /// 各部分约分（除以最大公约数）。
  Ratio reduced() {
    if (parts.isEmpty) return this;
    int g = parts.first;
    for (final p in parts) {
      g = gcd(g, p);
    }
    if (g <= 1) return this;
    return Ratio(parts.map((p) => p ~/ g).toList());
  }

  /// 按值比较份数（长度敏感、顺序敏感）。
  ///
  /// 替代易碎的 `ratio.toString() == '9:3:3:1'` 字符串比对：
  /// 不依赖渲染格式（分隔符、空格），重构 toString 也不会静默改变判定结果。
  bool equalsValues(List<int> other) {
    if (other.length != parts.length) return false;
    for (var i = 0; i < parts.length; i++) {
      if (parts[i] != other[i]) return false;
    }
    return true;
  }

  @override
  String toString() => parts.join(':');
}
