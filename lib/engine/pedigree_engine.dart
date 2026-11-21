// pedigree_engine.dart —— 遗传系谱/计算引擎（纯 Dart）
//
//
// 核心能力：
//   1) 解析多对等位基因的亲本基因型（如 AABBCC / AaBbCc / aabbcc），自动识别每对位点
//   2) 配子生成：每对位点独立分离，组合生成全部配子及其概率
//   3) 表型推导：默认完全显性（含显性基因即显性表型），支持显/隐标记
//   4) 概率传递：用「基因型分布 Map<基因型,概率>」表示个体，逐代传递，避免多对基因穷举爆炸
//   5) Punnett 方阵：输出双亲配子 × 配子的子一代基因型矩阵 + 表型比例
//
// 说明：多对基因时若穷举全部配子组合会指数爆炸（n 对杂合 = 4^n 个配子格），
//       因此提供「概率传递」模式：把配子概率卷积，逐代计算，O(位点数) 而非 O(4^n)。

/// 一个等位基因位点（一对等位基因）。
class Locus {
  final String dominant; // 显性等位基因字母（大写）
  final String recessive; // 隐性等位基因字母（小写）

  const Locus({required this.dominant, required this.recessive});

  bool get isValid => dominant != recessive && dominant.isNotEmpty;
}

/// 配子（携带每个位点的一个等位基因），如 AAb - > A、B、c。
class Gamete {
  final List<String> alleles; // 每个位点取的等位基因
  final double probability; // 该配子的概率

  const Gamete(this.alleles, this.probability);

  String get label => alleles.join();

  @override
  String toString() => '$label(${_pct(probability)})';

  static String _pct(double p) => '${(p * 100).toStringAsFixed(1)}%';
}

/// 一个基因型（每位点的纯合/杂合状态）。
class GenotypeProfile {
  final List<String> alleles; // 原名，如 A,a,B,B,C,c
  final double probability; // 该基因型出现的概率

  const GenotypeProfile(this.alleles, this.probability);

  String get label => alleles.join();

  /// 统一排序显示：同一位点按显性在前（Aa，AA，aa）。
  /// 缺失等位基因 '-' 恒排最后（B- 而不是 -B，R18 基因缺失）。
  String get sortedLabel {
    final sb = StringBuffer();
    for (int i = 0; i < alleles.length; i += 2) {
      final a = alleles[i];
      final b = alleles[i + 1];
      if (a == b) {
        sb.write(a);
        sb.write(b);
      } else if (a == '-') {
        sb.write('$b$a');
      } else if (b == '-') {
        sb.write('$a$b');
      } else {
        final upA = a.toUpperCase(), upB = b.toUpperCase();
        if (upA == upB) {
          sb.write(upA);
          sb.write(upA.toLowerCase());
        } else if (a == upA) {
          sb.write('$a$b');
        } else {
          sb.write('$b$a');
        }
      }
    }
    return sb.toString();
  }
}

/// 一代表型（含该表型出现的概率）。
class PhenotypeEntry {
  final String name; // 表型名，如「显显隐」或「A显、B隐」组合
  final double probability;

  const PhenotypeEntry(this.name, this.probability);

  @override
  String toString() => '$name ${(probability * 100).toStringAsFixed(2)}%';
}

/// 解析基因型字符串为位点列表。
///
/// 约定：字符串按成对字母解析，如 'AaBbCc' → 位点 [A/a, B/b, C/c]。
/// 大小写代表等位基因：大写=显性，小写=隐性。每对字母作为一个位点。
List<Locus> parseGenotypeToLoci(String genotype) {
  final s = genotype.trim();
  if (s.isEmpty || s.length % 2 != 0) {
    throw ArgumentError('基因型长度必须为偶数（每对位点两个字母）：$genotype');
  }
  final loci = <Locus>[];
  for (int i = 0; i < s.length; i += 2) {
    final a = s[i];
    final b = s[i + 1];
    final d = a.toUpperCase();
    final r = d == a ? b.toLowerCase() : b;
    // 显性字母 = 该位点大写形式
    final dom = d;
    final rec = dom.toLowerCase();
    if (a == dom && b == dom) {
      // AA
      loci.add(Locus(dominant: dom, recessive: rec));
    } else {
      loci.add(Locus(dominant: dom, recessive: rec));
    }
  }
  return loci;
}

/// 遗传计算引擎：多对基因、多代传递。
class PedigreeEngine {
  /// 由亲本基因型字符串生成全部配子（带概率）。
  /// [genotype] 如 'AaBbCc'。
  List<Gamete> gametesOf(String genotype) {
    final chars = genotype.trim().split('');
    final loci = <List<String>>[];
    for (int i = 0; i < chars.length; i += 2) {
      loci.add([chars[i], chars[i + 1]]);
    }
    return _enumerateGametes(loci);
  }

  List<Gamete> _enumerateGametes(List<List<String>> loci) {
    final result = <Gamete>[];
    final counts = <String, int>{};
    for (final locus in loci) {
      for (final al in locus) {
        counts[al] = (counts[al] ?? 0) + 1;
      }
    }
    // 每个位点取一个等位基因，概率 = 该等位基因在该位点的比例
    void rec(int idx, List<String> picked, double prob) {
      if (idx == loci.length) {
        result.add(Gamete(List.of(picked), prob));
        return;
      }
      final locus = loci[idx];
      // 统计本位置点各等位基因出现次数
      final freq = <String, int>{};
      for (final al in locus) {
        freq[al] = (freq[al] ?? 0) + 1;
      }
      freq.forEach((allele, times) {
        picked.add(allele);
        rec(idx + 1, picked, prob * (times / locus.length));
        picked.removeLast();
      });
    }

    rec(0, <String>[], 1.0);
    return result;
  }

  /// 计算两个配子合并成子代基因型的概率分布。
  /// [g1]、[g2] 为配子。
  ///
  /// [allowMissing]（R18 基因缺失交配）：开启后用「位点字母对齐」合并——
  /// 对数不一致的配子（如 3 对 × 1 对）按等位基因大写字母对齐位点，
  /// 缺失方补 '-'（如 AABBCC × aa → 子代 AaB-C-，B/C 位点单亲遗传，
  /// 标注「基因缺失」）；字母一致的常规配对结果与逐位合并完全等价。
  /// 关闭时对数不一致抛带中文说明的 ArgumentError。
  Map<String, double> crossGametes(
      List<Gamete> g1Set, List<Gamete> g2Set,
      {bool allowMissing = false}) {
    final dist = <String, double>{};
    for (final a in g1Set) {
      for (final b in g2Set) {
        if (a.alleles.length != b.alleles.length && !allowMissing) {
          // 基因对数不一致是未定义输入（如 AABBCC × aa）：抛带中文说明的
          // ArgumentError，而不是让 b.alleles[i] 越界裸崩成 RangeError。
          throw ArgumentError(
              '基因对数不一致（${a.alleles.length} 对 × ${b.alleles.length} 对），'
              '无法杂交合并；请保证双亲位点数相同，'
              '或开启「允许基因缺失交配」');
        }
        final key = allowMissing
            ? _mergeByLocusLetter(a, b)
            : _mergePositional(a, b);
        dist[key] = (dist[key] ?? 0) + a.probability * b.probability;
      }
    }
    return dist;
  }

  /// 逐位合并（位点一一对应的传统路径）。
  String _mergePositional(Gamete a, Gamete b) {
    if (a.alleles.length != b.alleles.length) {
      throw ArgumentError(
          '基因对数不一致（${a.alleles.length} 对 × ${b.alleles.length} 对），'
          '无法杂交合并；请保证双亲位点数相同，'
          '或开启「允许基因缺失交配」');
    }
    final merged = <String>[];
    for (int i = 0; i < a.alleles.length; i++) {
      merged.add(a.alleles[i]);
      merged.add(b.alleles[i]);
    }
    return GenotypeProfile(merged, 1).sortedLabel;
  }

  /// 按位点字母对齐合并（R18）：任一方缺失的位点补 '-'。
  /// 位点集合 = 双方等位基因大写字母全集（字母序稳定），
  /// 子代位点排列也按字母序归一（同分布下同 key 稳定聚合）。
  String _mergeByLocusLetter(Gamete a, Gamete b) {
    final letters = <String>{
      for (final al in a.alleles) al.toUpperCase(),
      for (final al in b.alleles) al.toUpperCase(),
    }.toList()
      ..sort();
    String? pick(Gamete g, String letter) {
      for (final al in g.alleles) {
        if (al.toUpperCase() == letter) return al;
      }
      return null;
    }

    final merged = <String>[];
    for (final letter in letters) {
      merged.add(pick(a, letter) ?? '-');
      merged.add(pick(b, letter) ?? '-');
    }
    return GenotypeProfile(merged, 1).sortedLabel;
  }

  /// 对亲本1 × 亲本2 做一次杂交，返回子代基因型分布 Map<基因型, 概率>。
  Map<String, double> cross(String p1, String p2,
      {bool allowMissing = false}) {
    final g1 = gametesOf(p1);
    final g2 = gametesOf(p2);
    return crossGametes(g1, g2, allowMissing: allowMissing);
  }

  /// 分布 × 基因型：把基因型分布中的每个基因型与 [partner] 杂交，按概率加权合并。
  /// 用于回交（F1 整群 × 亲本）、以及任何「上一代分布 × 固定个体」的场景。
  /// 返回子代基因型分布（会自动归一化到和为 1）。
  Map<String, double> crossDist(
      Map<String, double> dist, String partner) {
    final result = <String, double>{};
    dist.forEach((gen, prob) {
      final childDist = cross(gen, partner);
      childDist.forEach((c, cp) {
        result[c] = (result[c] ?? 0) + prob * cp;
      });
    });
    final total = result.values.fold(0.0, (a, b) => a + b);
    if (total > 0) {
      result.updateAll((k, v) => v / total);
    }
    return result;
  }

  /// 一次杂交 + 生成 Punnett 方阵信息（配子 × 配子 → 子代矩阵）。
  CrossResultPunnett punnett(String p1, String p2) {
    final g1 = gametesOf(p1);
    final g2 = gametesOf(p2);
    final matrix = <List<String>>[];
    for (final a in g1) {
      final row = <String>[];
      for (final b in g2) {
        final merged = <String>[];
        for (int i = 0; i < a.alleles.length; i++) {
          merged.add(a.alleles[i]);
          merged.add(b.alleles[i]);
        }
        row.add(GenotypeProfile(merged, 1).sortedLabel);
      }
      matrix.add(row);
    }
    return CrossResultPunnett(
      gametesP1: g1,
      gametesP2: g2,
      matrix: matrix,
      lociCount: g1.isEmpty ? 0 : g1.first.alleles.length,
    );
  }

  /// 由子代基因型分布按每对位点显性表型，得到表型分布。
  /// [phenotypeBuilder] 自定义表型名，默认用「显性字母+…/隐性字母」。
  Map<String, double> phenotypesOf(Map<String, double> genDist,
      {String Function(String genotype)? phenotypeBuilder}) {
    final pheno = <String, double>{};
    genDist.forEach((gen, p) {
      final name = phenotypeBuilder?.call(gen) ?? defaultPhenotypeName(gen);
      pheno[name] = (pheno[name] ?? 0) + p;
    });
    return pheno;
  }

  /// 默认表型名：每个位点「显性字母」或「隐性字母」连接，如 AAB b → 'A显B隐'。
  String defaultPhenotypeName(String genotype) {
    final chars = genotype.split('');
    final parts = <String>[];
    for (int i = 0; i < chars.length; i += 2) {
      final a = chars[i];
      final b = chars[i + 1];
      final upA = a.toUpperCase();
      final upB = b.toUpperCase();
      final hasDom = a == upA || b == upB;
      parts.add(hasDom ? '${upA}显' : '${upA}隐');
    }
    return parts.join('');
  }

  /// 从基因型分布中取每个位点的显性/隐性等位基因，供上层组合成表现型比例。

  /// 多代计算：从初始个体出发，逐代两两杂交扩散。
  /// 返回每代的个体基因型分布列表。
  ///
  /// [initialIndividual]：个体集合（基因型字符串）。
  /// [generations]：要传播的代数（1=只算子一代，2=子二代...）。
  /// 每代：取上一代所有个体两两杂交（含自交），合并所有可能的子代.
  List<Map<String, double>> propagateMultigeneration(
      List<String> initialIndividual, int generations) {
    var current = <String, double>{};
    for (final id in initialIndividual) {
      current[id] = (current[id] ?? 0) + 1;
    }
    final result = <Map<String, double>>[current];
    for (int g = 0; g < generations; g++) {
      final next = <String, double>{};
      current.forEach((genotype, p) {
        // 杂交：与集合内其他个体 + 自交
        // 简化物理处理：本代每个个体概率为 p，与集合内所有个体杂交并加权
        current.forEach((other, op) {
          final childDist = cross(genotype, other);
          childDist.forEach((c, cp) {
            next[c] = (next[c] ?? 0) + p * op * cp;
          });
        });
      });
      // 归一化（两两杂交会把种群规模平方，需除总数使 sum=1）
      final total = next.values.fold(0.0, (x, y) => x + y);
      if (total > 0) {
        next.updateAll((k, v) => v / total);
      }
      current = next;
      result.add(current);
    }
    return result;
  }
}

/// Punnett 方阵结果。
class CrossResultPunnett {
  final List<Gamete> gametesP1;
  final List<Gamete> gametesP2;
  final List<List<String>> matrix; // matrix[i][j] = 配子P1[i]×配子P2[j] 子代基因型
  final int lociCount;

  const CrossResultPunnett({
    required this.gametesP1,
    required this.gametesP2,
    required this.matrix,
    required this.lociCount,
  });
}

/// 表型概率简化输出：给定多位点基因型字符串，返回每个位点的表型描述。
List<String> phenotypePerLocus(String genotype) {
  final chars = genotype.split('');
  final out = <String>[];
  for (int i = 0; i < chars.length; i += 2) {
    final a = chars[i], b = chars[i + 1];
    final up = a.toUpperCase();
    final dom = a == up || b == up;
    out.add(dom ? '${up}显性' : '${up}隐性');
  }
  return out;
}
