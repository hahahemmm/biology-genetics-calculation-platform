// genetics_env.dart —— 规则注册式遗传环境（纯 Dart）
//
// 借鉴 GitHub 开源项目 GeneticsCalculator 的 GeneticsEnv 思路并用 Fraction 重写：
//   - 等位基因位点：注册显/隐关系（loci）
//   - 致死规则：任意「基因型 → 存活率(Fraction)」函数，可叠加（乘法合并）
//   - 表型规则：任意「基因型 → 表型名」函数（默认完全显性，可覆盖）
//   - cross 输出精确分数分布；toIntegerRatio 统一分母转整数比（9:3:3:1）
//
// 由此 9:7 / 9:3:4 / 15:1 / 1:4:6:4:1 等 9331 变式不再是查表，
// 而是「注册表型映射 → 真实推导」的结果；致死条件同样推导得出。
//
// 伴 X 遗传仍由 pedigree.dart 负责；本环境处理常染色体多位点。

import 'fraction.dart';
import 'utils.dart';
import 'variant_spec.dart';

/// 一个等位基因位点定义。
class AlleleLocus {
  final String dominant; // 显性字母（大写，如 'A'）
  final String recessive; // 隐性字母（小写，如 'a'）
  final String traitName; // 性状名（如 '粒形'），可选
  final String dominantPhenotype; // 显性表型名
  final String recessivePhenotype; // 隐性表型名

  const AlleleLocus(
    this.dominant,
    this.recessive, {
    this.traitName = '',
    this.dominantPhenotype = '',
    this.recessivePhenotype = '',
  });
}

/// 致死规则：输入归一化基因型字符串（如 'AaBb'），返回存活率（0 = 致死）。
typedef LethalRule = Fraction Function(String genotype);

/// 表型规则：输入归一化基因型字符串，返回表型名。
typedef PhenotypeRule = String Function(String genotype);

/// 遗传环境：注册位点与规则，执行杂交推导。
class GeneticsEnv {
  final List<AlleleLocus> loci = [];
  final List<LethalRule> lethalRules = [];
  PhenotypeRule? phenotypeRule;

  /// 注册一个位点（如 'A'/'a'）。
  void addLocus(AlleleLocus locus) {
    if (locus.dominant.length != 1 || locus.recessive.length != 1) {
      throw ArgumentError('等位基因必须是单字符');
    }
    loci.add(locus);
  }

  /// 便捷注册：连续位点（如 'Aa','Bb' → addLoci('AaBb')）。
  void addLoci(String letters) {
    for (int i = 0; i < letters.length; i += 2) {
      addLocus(AlleleLocus(
          letters[i].toUpperCase(), letters[i].toLowerCase()));
    }
  }

  /// 注册致死规则（可多条，存活率按乘法合并）。
  void addLethalRule(LethalRule rule) => lethalRules.add(rule);

  /// 设置表型映射（不设置则用默认完全显性）。
  void setPhenotypeRule(PhenotypeRule rule) => phenotypeRule = rule;

  /// 解析基因型字符串为每对位点的等位基因对。
  /// 如 'AaBb' → [['A','a'],['B','b']]。位点顺序以 loci 注册顺序为准，
  /// 若未注册位点则按字符串成对顺序推断。
  List<List<String>> parseGenotype(String genotype) {
    final s = genotype.trim();
    if (s.isEmpty || s.length % 2 != 0) {
      throw ArgumentError('基因型长度必须为偶数：$genotype');
    }
    final pairs = <List<String>>[];
    for (int i = 0; i < s.length; i += 2) {
      pairs.add([s[i], s[i + 1]]);
    }
    return pairs;
  }

  /// 归一化基因型：每位点显性字母在前。
  String normalize(String genotype) {
    final pairs = parseGenotype(genotype);
    final sb = StringBuffer();
    for (final pair in pairs) {
      sb.write(_normPair(pair[0], pair[1]));
    }
    return sb.toString();
  }

  String _normPair(String a, String b) {
    if (a == b) return '$a$b';
    final au = a.toUpperCase(), bu = b.toUpperCase();
    if (au != bu) return au.compareTo(bu) < 0 ? '$au$bu' : '$bu$au';
    return '$au${au.toLowerCase()}';
  }

  /// 生成某基因型的全部配子（精确概率）。
  Map<String, Fraction> gametesOf(String genotype) {
    final pairs = parseGenotype(genotype);
    var result = <String, Fraction>{'': Fraction.one};
    for (final pair in pairs) {
      // 每位点等位基因频率（AA → A:1；Aa → A:1/2 a:1/2）
      final freq = <String, Fraction>{};
      for (final al in pair) {
        freq[al] = (freq[al] ?? Fraction.zero) + Fraction.half;
      }
      final next = <String, Fraction>{};
      result.forEach((prefix, p) {
        freq.forEach((al, f) {
          final key = prefix + al;
          next[key] = (next[key] ?? Fraction.zero) + p * f;
        });
      });
      result = next;
    }
    return result;
  }

  /// 某基因型的存活率（全部致死规则乘法合并；无规则 = 1）。
  Fraction survivalOf(String genotype) {
    var s = Fraction.one;
    for (final rule in lethalRules) {
      s = s * rule(genotype);
      if (s.isZero) break;
    }
    return s;
  }

  /// 杂交：p1 × p2 → 子代基因型分布（Map<归一化基因型, 精确概率>）。
  /// 已应用致死规则：致死基因型剔除，存活部分归一化到和为 1。
  Map<String, Fraction> cross(String p1, String p2) {
    final raw = crossUnnormalized(p1, p2);
    if (lethalRules.isEmpty) return raw;
    return _normalizeDist(raw);
  }

  /// 杂交（不归一化版本）：应用致死存活率，但不做总和归一化。
  /// 返回分布的总和 = 该组合的子代存活率（无致死时为 1）。
  ///
  /// 「多组合加权后再统一选择」的场景（如自由交配逐代淘汰）必须用它：
  /// 若逐组合归一化再按交配概率加权，会错误放大高死亡率组合的贡献。
  Map<String, Fraction> crossUnnormalized(String p1, String p2) {
    final g1 = gametesOf(p1);
    final g2 = gametesOf(p2);
    final raw = <String, Fraction>{};
    g1.forEach((a, pa) {
      g2.forEach((b, pb) {
        final merged = _mergeGametes(a, b);
        raw[merged] = (raw[merged] ?? Fraction.zero) + pa * pb;
      });
    });
    if (lethalRules.isEmpty) return raw;
    final alive = <String, Fraction>{};
    raw.forEach((gen, p) {
      final sv = survivalOf(gen);
      if (!sv.isZero) alive[gen] = p * sv;
    });
    return alive;
  }

  String _mergeGametes(String ga, String gb) {
    final sb = StringBuffer();
    for (int i = 0; i < ga.length; i++) {
      sb.write(_normPair(ga[i], gb[i]));
    }
    return sb.toString();
  }

  Map<String, Fraction> _normalizeDist(Map<String, Fraction> dist) {
    var total = Fraction.zero;
    dist.forEach((_, p) => total = total + p);
    if (total.isZero) return dist;
    final out = <String, Fraction>{};
    dist.forEach((k, v) => out[k] = v / total);
    return out;
  }

  /// 表型判定：默认完全显性（每位点含显性字母→显性表型）。
  String phenotypeOf(String genotype) {
    final rule = phenotypeRule;
    if (rule != null) return rule(normalize(genotype));
    final pairs = parseGenotype(normalize(genotype));
    final parts = <String>[];
    for (int i = 0; i < pairs.length; i++) {
      final locus = i < loci.length ? loci[i] : null;
      final dom = locus?.dominant ?? pairs[i][0].toUpperCase();
      final isDom = pairs[i].contains(dom);
      if (locus != null &&
          (locus.dominantPhenotype.isNotEmpty ||
              locus.recessivePhenotype.isNotEmpty)) {
        parts.add(isDom ? locus.dominantPhenotype : locus.recessivePhenotype);
      } else {
        parts.add(isDom ? '${dom}显' : '${dom}隐');
      }
    }
    return parts.join(' ');
  }

  /// 表型分布：把基因型分布聚合为表型分布（精确分数）。
  Map<String, Fraction> phenotypeDist(Map<String, Fraction> genDist) {
    final out = <String, Fraction>{};
    genDist.forEach((gen, p) {
      final ph = phenotypeOf(gen);
      out[ph] = (out[ph] ?? Fraction.zero) + p;
    });
    return out;
  }

  /// 统一分母转整数比（借鉴 unifiedDenominator）：
  /// 把分布各项乘分母最小公倍数得整数，再除以最大公约数。
  /// 如 {双显:9/16, 显隐:3/16, 隐显:3/16, 双隐:1/16} → [9,3,3,1]。
  static List<int> toIntegerRatio(Iterable<Fraction> values) {
    final list = values.toList();
    if (list.isEmpty) return const [];
    int lcmVal = 1;
    for (final f in list) {
      lcmVal = lcm(lcmVal, f.denominator);
    }
    final ints =
        list.map((f) => f.numerator * (lcmVal ~/ f.denominator)).toList();
    int g = 0;
    for (final v in ints) {
      g = gcd(g, v.abs());
    }
    if (g > 1) {
      for (int i = 0; i < ints.length; i++) {
        ints[i] ~/= g;
      }
    }
    return ints;
  }

  // ---------- 预置规则工厂（教学常用） ----------

  /// 致死规则工厂：显性纯合致死（如 AA 致死，位点字母 dom）。
  static LethalRule lethalOnDominantHomozygous(String dom) {
    final pair = '$dom$dom';
    return (genotype) => genotype.contains(pair) ? Fraction.zero : Fraction.one;
  }

  /// 致死规则工厂：隐性纯合致死。
  static LethalRule lethalOnRecessiveHomozygous(String dom) {
    final pair = '${dom.toLowerCase()}${dom.toLowerCase()}';
    return (genotype) => genotype.contains(pair) ? Fraction.zero : Fraction.one;
  }

  /// 9331 变式表型映射工厂。
  ///
  /// [mode]：见 [VariantSpec.all]（v2.12 8 个 mode）。
  /// 输入基因型默认两对位点（如 'AaBb'）。v2.12 起 8 个 mode 全部用
  /// [VariantSpec] 集中常量，genetics_env 不再保留字面量。
  static PhenotypeRule phenotypeRuleForVariant(String mode,
      {String locus1 = 'A', String locus2 = 'B'}) {
    bool hasDom(String gen, String d) => gen.contains(d);
    return (genotype) {
      final d1 = hasDom(genotype, locus1);
      final d2 = hasDom(genotype, locus2);
      switch (mode) {
        case VariantSpec.complement97: // 9_7 互补：双显 vs 其他
          return d1 && d2 ? '双显' : '其他';
        case VariantSpec.epistasis934: // 9_3_4 隐性上位：双显 / 位点1显 / 其他
          if (d1 && d2) return '双显';
          if (d1 && !d2) return '${locus1}显';
          return '其他';
        case VariantSpec.dominant151: // 15_1 显性叠加：任一显性 vs 双隐
          return (d1 || d2) ? '显性' : '双隐';
        case VariantSpec.dominantEpistasis1231: // 12_3_1 显性上位：位点1显(含双显) / 位点2显 / 双隐
          if (d1) return '${locus1}显';
          if (d2) return '${locus2}显';
          return '双隐';
        case VariantSpec.inhibition13_3: // 13_3 抑制作用：位点2显或双隐 / 位点1显位点2隐
          if (d1 && !d2) return '${locus1}显';
          return '其他';
        case VariantSpec.additive961: // 9_6_1 积加：双显 / 单显 / 双隐
          if (d1 && d2) return '双显';
          if (d1 || d2) return '单显';
          return '双隐';
        case VariantSpec.quantitative14641: // 1_4_6_4_1 数量性状：按显性基因个数分档
          int count = 0;
          for (final ch in genotype.split('')) {
            if (ch == ch.toUpperCase() && ch != ch.toLowerCase()) count++;
          }
          return '显性基因×$count';
        case VariantSpec.standard9331:
        default:
          if (d1 && d2) return '双显';
          if (d1) return '${locus1}显${locus2}隐';
          if (d2) return '${locus1}隐${locus2}显';
          return '双隐';
      }
    };
  }
}
