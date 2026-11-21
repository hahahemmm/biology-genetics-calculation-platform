// linkage_engine.dart —— 连锁与互换引擎（纯 Dart，精确分数）
//
// 高考高频考点：两对基因位于同一对同源染色体上（连锁），
// 减数分裂时非姐妹染色单体可发生交叉互换。
//
// 记法（教学通用）：
//   连锁相：'AB/ab'（相引相，显性在同一条染色体）或 'Ab/aB'（相斥相）
//   交换值 r：重组型配子所占比例，0 ≤ r ≤ 1/2
//     r = 0   完全连锁：只产亲本型配子
//     r = 1/2 自由组合等价：四种配子 1:1:1:1
//
// 配子规则（以 AB/ab 为例）：
//   亲本型 AB、ab 各 (1-r)/2；重组型 Ab、aB 各 r/2
//
// 输出全程 Fraction：如 r = 1/5 时测交后代 4:4:1:1。

import 'fraction.dart';
import 'utils.dart';

/// 连锁亲本：两条染色体单倍型（如 ['AB','ab']）。
class LinkedParent {
  final String hap1; // 第一条染色体携带的等位基因组合
  final String hap2;

  const LinkedParent(this.hap1, this.hap2);

  String get label => '$hap1/$hap2';

  /// 位点字母（大写形式），如 ['A','B']。
  List<String> get loci {
    final out = <String>[];
    for (var i = 0; i < hap1.length; i++) {
      out.add(hap1[i].toUpperCase());
    }
    return out;
  }
}

/// 连锁杂交结果。
class LinkageResult {
  final LinkedParent parent1;
  final LinkedParent parent2;
  final Fraction recombination; // 交换值 r

  /// 亲本1 配子（含重组）；Map<配子, 概率>。
  final Map<String, Fraction> gametesP1;
  final Map<String, Fraction> gametesP2;

  /// 子代基因型分布：Map<'AB/ab' 形式, 概率>。
  final Map<String, Fraction> offspring;

  /// 子代表型分布（默认完全显性）：Map<'A显B隐' 形式, 概率>。
  final Map<String, Fraction> phenotypes;

  /// 重组型配子占比（实测交换值，应等于输入 r）。
  final Fraction observedRecombination;

  const LinkageResult({
    required this.parent1,
    required this.parent2,
    required this.recombination,
    required this.gametesP1,
    required this.gametesP2,
    required this.offspring,
    required this.phenotypes,
    required this.observedRecombination,
  });

  /// 表型整数比。
  List<int> get phenotypeRatio {
    final values = phenotypes.values.toList();
    if (values.isEmpty) return const [];
    int lcmVal = 1;
    for (final f in values) {
      lcmVal = lcm(lcmVal, f.denominator);
    }
    final ints =
        values.map((f) => f.numerator * (lcmVal ~/ f.denominator)).toList();
    var g = 0;
    for (final v in ints) {
      g = gcd(g, v.abs());
    }
    if (g > 1) {
      for (var i = 0; i < ints.length; i++) {
        ints[i] ~/= g;
      }
    }
    return ints;
  }

}

/// 连锁互换引擎。
class LinkageEngine {
  /// 解析连锁基因型 'AB/ab'。
  /// 要求：两条单倍型等长（2–3 个位点）、每位点字母大小写配对
  /// （如 A/a、B/b），且两位点覆盖同一对字母集合。
  LinkedParent parseParent(String raw) {
    final s = raw.trim().replaceAll(' ', '');
    final parts = s.split('/');
    if (parts.length != 2 || parts[0].isEmpty) {
      throw ArgumentError('连锁基因型应为 AB/ab 或 Ab/aB 形式：$raw');
    }
    final h1 = parts[0], h2 = parts[1];
    if (h1.length != h2.length || h1.length < 2 || h1.length > 3) {
      throw ArgumentError('两条染色体需含 2–3 个相同数量的位点：$raw');
    }
    for (var i = 0; i < h1.length; i++) {
      final a = h1[i], b = h2[i];
      if (a.toUpperCase() != b.toUpperCase() || a.toUpperCase() == a.toLowerCase()) {
        throw ArgumentError('第 ${i + 1} 位点等位基因不配对（如 A/a）：$raw');
      }
    }
    return LinkedParent(h1, h2);
  }

  /// 解析交换值：'0.2' / '20%' / '1/5' → Fraction(1,5)。范围 0–1/2。
  Fraction parseRecombination(String raw) {
    final s = raw.trim();
    Fraction r;
    if (s.endsWith('%')) {
      final v = double.tryParse(s.substring(0, s.length - 1));
      if (v == null) throw ArgumentError('交换值格式错误：$raw');
      r = Fraction.approx(v / 100);
    } else if (s.contains('/')) {
      final parts = s.split('/');
      final n = int.tryParse(parts[0]), d = int.tryParse(parts[1]);
      if (n == null || d == null) {
        throw ArgumentError('交换值格式错误：$raw');
      }
      r = Fraction(n, d);
    } else {
      final v = double.tryParse(s);
      if (v == null) throw ArgumentError('交换值格式错误：$raw');
      r = Fraction.approx(v);
    }
    if (r.compareTo(Fraction.zero) < 0 || r.compareTo(Fraction.half) > 0) {
      throw ArgumentError('交换值须在 0 到 1/2 之间：$raw');
    }
    return r;
  }

  /// 某连锁亲本在交换值 r 下的配子分布。
  /// 亲本型各 (1-r)/2，重组型各 r/2；位点超过 2 时按相邻两两互换的
  /// 简化模型处理（教学口径：只算一次互换）。
  Map<String, Fraction> gametesOf(LinkedParent parent, Fraction r) {
    final h1 = parent.hap1, h2 = parent.hap2;
    final out = <String, Fraction>{};
    if (h1.length == 2) {
      // 两位点：亲本型 + 单交换重组型
      final parental = (Fraction.one - r) / Fraction.of(2);
      final recombinant = r / Fraction.of(2);
      out[h1] = (out[h1] ?? Fraction.zero) + parental;
      out[h2] = (out[h2] ?? Fraction.zero) + parental;
      out['${h1[0]}${h2[1]}'] =
          (out['${h1[0]}${h2[1]}'] ?? Fraction.zero) + recombinant;
      out['${h2[0]}${h1[1]}'] =
          (out['${h2[0]}${h1[1]}'] ?? Fraction.zero) + recombinant;
    } else {
      // 三位点：亲本型为主，重组型按两端位点互换简化
      final parental = (Fraction.one - r) / Fraction.of(2);
      out[h1] = (out[h1] ?? Fraction.zero) + parental;
      out[h2] = (out[h2] ?? Fraction.zero) + parental;
      final n = h1.length;
      final per = r / Fraction.of(2 * (n - 1));
      for (var i = 0; i < n - 1; i++) {
        // 在 i 与 i+1 之间发生一次交换
        final rec1 = h1.substring(0, i + 1) + h2.substring(i + 1);
        final rec2 = h2.substring(0, i + 1) + h1.substring(i + 1);
        out[rec1] = (out[rec1] ?? Fraction.zero) + per;
        out[rec2] = (out[rec2] ?? Fraction.zero) + per;
      }
    }
    out.removeWhere((_, v) => v.isZero);
    return out;
  }

  /// 连锁杂交：parent1 × parent2（相同交换值 r）。
  LinkageResult cross(String p1, String p2, String recombination) {
    final parent1 = parseParent(p1);
    final parent2 = parseParent(p2);
    final r = parseRecombination(recombination);
    // 两位点字母集合须一致
    if (parent1.loci.join() != parent2.loci.join()) {
      throw ArgumentError('双亲位点字母必须一致：$p1 vs $p2');
    }

    final g1 = gametesOf(parent1, r);
    final g2 = gametesOf(parent2, r);

    // 子代基因型分布
    final offspring = <String, Fraction>{};
    g1.forEach((a, pa) {
      g2.forEach((b, pb) {
        final gen = _normalizeDiploid(a, b);
        offspring[gen] = (offspring[gen] ?? Fraction.zero) + pa * pb;
      });
    });

    // 表型分布（完全显性）
    final pheno = <String, Fraction>{};
    offspring.forEach((gen, p) {
      final name = _phenotypeName(gen);
      pheno[name] = (pheno[name] ?? Fraction.zero) + p;
    });

    // 实测交换值：重组型配子占比（亲本1）
    var obs = Fraction.zero;
    g1.forEach((g, p) {
      if (g != parent1.hap1 && g != parent1.hap2) obs = obs + p;
    });

    return LinkageResult(
      parent1: parent1,
      parent2: parent2,
      recombination: r,
      gametesP1: g1,
      gametesP2: g2,
      offspring: offspring,
      phenotypes: pheno,
      observedRecombination: obs,
    );
  }

  /// 两配子合并为二倍体并归一化：每位点显性字母在前。
  /// 'AB' + 'ab' → 'AB/ab'。
  String _normalizeDiploid(String ga, String gb) {
    final h1 = StringBuffer(), h2 = StringBuffer();
    for (var i = 0; i < ga.length; i++) {
      final a = ga[i], b = gb[i];
      if (a == a.toUpperCase()) {
        h1.write(a);
        h2.write(b);
      } else {
        h1.write(b);
        h2.write(a);
      }
    }
    return '${h1.toString()}/${h2.toString()}';
  }

  /// 表型名：每位点「X显」或「X隐」。
  /// 单倍型记法中位点 i 的等位基因是 h1[i] 与 h2[i]（_normalizeDiploid
  /// 已把显性等位基因放入 h1），故 h1[i] 为大写即该位点呈显性。
  String _phenotypeName(String diploid) {
    final parts = diploid.split('/');
    final h1 = parts[0];
    final out = <String>[];
    for (var i = 0; i < h1.length; i++) {
      final up = h1[i].toUpperCase();
      out.add(h1[i] == up ? '$up显' : '$up隐');
    }
    return out.join(' ');
  }
}
