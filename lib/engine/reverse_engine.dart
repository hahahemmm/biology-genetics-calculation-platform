// reverse_engine.dart —— 反推引擎（纯 Dart）
//
// 题型：给后代（F1/F2）表型比 → 枚举可能的亲本组合（校卷题 15 型，月考高频）。
// 边界（计划裁定）：1~2 对等位基因、独立分配、完全显隐 + 已知 9331 变式合并；
// 致死/连锁/三倍体反推不做（组合爆炸且超出教学常规）。
//
// 复用 KaojiCalcAuto.crossAuto 正推逐对验证：1 对基因 9 组有序亲本对、2 对基因 45 组无序亲本对，
// 逐一正推后代比与目标比对，命中者收为候选。

import 'models.dart';
import 'kaoji_calc.dart';
import 'utils.dart';

/// 一个命中：亲本组合 + 说明。
class ReverseMatch {
  final String p1;
  final String p2;

  /// 亲代表型（如 '显性 × 隐性'；两位点如 'AB × ab'）。
  final String p1Pheno;
  final String p2Pheno;

  /// 组合性质说明（'自交' / '测交' / 变式名等）。
  final String note;

  const ReverseMatch(this.p1, this.p2, this.p1Pheno, this.p2Pheno, this.note);
}

class ReverseEngine {
  final KaojiCalc _calc = KaojiCalc();

  static const _oneLocusGenotypes = ['AA', 'Aa', 'aa'];
  static const _twoLocusGenotypes = [
    'AABB', 'AABb', 'AAbb',
    'AaBB', 'AaBb', 'Aabb',
    'aaBB', 'aaBb', 'aabb',
  ];

  /// 变式合并模式：name → 四类份数 [AB, Ab, aB, ab] 的合并方式。
  /// 与 KaojiCalc.knownVariants + kaodian 经典变式（9:6:1 积加、12:3:1 显性上位）对齐。
  static const _merges = <String, List<List<int>>>{
    '标准': [[0], [1], [2], [3]],
    '9:7 互补': [[0], [1, 2, 3]],
    '9:3:4 隐性上位': [[0], [1], [2, 3]],
    '9:6:1 积加': [[0], [1, 2], [3]],
    '12:3:1 显性上位': [[0, 1], [2], [3]],
    '15:1 显性叠加': [[0, 1, 2], [3]],
  };

  /// 解析用户输入的比例文本为约分整数比。
  /// 接受 '3:1' '9:3:3:1' '1:1:1:1' '1:2:1' '15：1'（全角冒号）等。
  /// 非法输入抛 ArgumentError（与项目引擎风格一致）。
  static Ratio parseRatio(String raw) {
    final s = raw.trim().replaceAll('：', ':').replaceAll('∶', ':');
    final parts = s
        .split(':')
        .map((e) => int.tryParse(e.trim()))
        .toList();
    if (parts.any((p) => p == null) || parts.isEmpty || parts.length > 5) {
      throw ArgumentError('请输入整数比例（如 3:1 或 9:3:3:1），最多 5 项');
    }
    if (parts.any((p) => p! < 0) || parts.every((p) => p == 0)) {
      throw ArgumentError('比例各项须为非负整数且不全为 0');
    }
    return Ratio(parts.cast<int>()).reduced();
  }

  /// 主入口：反推候选亲本组合（按简洁度排序：自交/测交在前）。
  ///
  /// [loci]：1=一对基因；2=两对基因；null=两侧都试并合并去重
  ///（如 3:1 主要命中一对；9:7 只会命中两对合并变式）。
  List<ReverseMatch> inferParents(String ratioText, {int? loci}) {
    // v2.13 引擎优化：目标比改为携带约分后的份数（List<int>），
    // 下游逐对比较走 Ratio.equalsValues 值比较——不再渲染成字符串比对，
    // 渲染格式变化不再影响判定。
    final target = parseRatio(ratioText).parts;
    if (loci != null) return _inferWithLoci(target, loci);
    final seen = <String>{};
    final out = <ReverseMatch>[];
    for (final m in [
      ..._inferWithLoci(target, 1),
      ..._inferWithLoci(target, 2),
    ]) {
      final key = ([m.p1, m.p2]..sort()).join('×');
      if (seen.add(key)) out.add(m);
    }
    return out;
  }

  List<ReverseMatch> _inferWithLoci(List<int> target, int loci) {
    if (loci != 1 && loci != 2) {
      throw ArgumentError('暂支持 1~2 对等位基因的反推');
    }
    final pool = loci == 1 ? _oneLocusGenotypes : _twoLocusGenotypes;

    final seen = <String>{};
    final out = <ReverseMatch>[];
    for (final p1 in pool) {
      for (final p2 in pool) {
        final pairKey = ([p1, p2]..sort()).join('×');
        if (!seen.add(pairKey)) continue;
        final hit = _matchPair(p1, p2, target, loci);
        if (hit != null) out.add(hit);
      }
    }
    // 排序：自交 > 测交 > 其他；同类内按基因型字典序（确定性输出）。
    int rank(ReverseMatch m) {
      if (m.p1 == m.p2) return 0;
      if (m.note.contains('测交')) return 1;
      return 2;
    }

    out.sort((a, b) {
      final c = rank(a).compareTo(rank(b));
      return c != 0 ? c : (a.p1 + a.p2).compareTo(b.p1 + b.p2);
    });
    return out;
  }

  /// 单对亲本的命中测试：正推后与目标比对（含变式合并形态）。
  ReverseMatch? _matchPair(String p1, String p2, List<int> target, int loci) {
    final r = _calc.crossAuto(p1: p1, p2: p2);
    if (r.error != null || r.result == null) return null;
    final res = r.result!;

    // 1 对基因：直接比表型比（两类：显性/隐性）
    if (loci == 1) {
      if (res.phenotypeRatio.reduced().equalsValues(target)) {
        return ReverseMatch(
          p1, p2,
          _phenoOf1(p1), _phenoOf1(p2),
          _noteOf(p1, p2, null),
        );
      }
      return null;
    }

    // 2 对基因：先取四类份数 [AB, Ab, aB, ab]，再逐一比对变式合并形态。
    // phenotypeLabels 形如 'AB'/'Ab'/'aB'/'ab'（按位点显隐），
    // genotypeCounts 无法直接还原四类顺序——改用 gametes 组合重算四类计数，
    // 与 crossAuto 同源（位点含大写→显）。
    final counts = _fourClassCounts(res);
    if (counts == null) {
      // 非完全显隐标签（理论上不会发生：crossAuto 标签即 AB/Ab/aB/ab）
      if (res.phenotypeRatio.reduced().equalsValues(target)) {
        return ReverseMatch(
            p1, p2, res.phenotypeLabels.join('/'), res.phenotypeLabels.join('/'),
            _noteOf(p1, p2, res.variantName));
      }
      return null;
    }
    for (final e in _merges.entries) {
      final merged = e.value
          .map((g) => g.fold<int>(0, (sum, i) => sum + counts[i]))
          .toList();
      // 去掉 0 项（如 9:3:4 里某组为 0 时不成 3 类）
      final nz = merged.where((c) => c > 0).toList();
      if (Ratio(nz).reduced().equalsValues(target)) {
        return ReverseMatch(
          p1, p2,
          _phenoOf2(p1), _phenoOf2(p2),
          _noteOf(p1, p2, e.key == '标准' ? null : e.key),
        );
      }
    }
    return null;
  }

  /// 从 KaojiCalcResult 提取四类表型份数 [AB, Ab, aB, ab] 顺序。
  /// 标签不含双位点四种形态时返回 null（如 1 对基因场景——本函数不被调用）。
  List<int>? _fourClassCounts(KaojiCalcResult res) {
    const order = ['AB', 'Ab', 'aB', 'ab'];
    final labels = res.phenotypeLabels;
    final counts = List<int>.filled(4, 0);
    // phenotypeRatio 与 labels 对齐（顺序 = _entryCmp 排序后），逐项回填。
    final ratioParts = res.phenotypeRatio.parts;
    if (labels.length != ratioParts.length) return null;
    final byLabel = {for (var i = 0; i < labels.length; i++) labels[i]: ratioParts[i]};
    for (var i = 0; i < 4; i++) {
      final v = byLabel[order[i]];
      if (v == null) return null;
      counts[i] = v;
    }
    return counts;
  }

  String _phenoOf1(String g) => hasUpperAscii(g) ? '显性' : '隐性';

  String _phenoOf2(String g) {
    final a = g.substring(0, 2), b = g.substring(2, 4);
    final da = hasUpperAscii(a);
    final db = hasUpperAscii(b);
    if (da && db) return '双显';
    if (!da && !db) return '双隐';
    return da ? '显 A 隐 B' : '隐 A 显 B';
  }

  String _noteOf(String p1, String p2, String? variant) {
    // 测交 = 一方全部位点隐性纯合，另一方至少一个位点杂合。
    final fullRec = RegExp(r'^[a-z]+$');
    bool isHetero(String g) {
      for (var i = 0; i + 1 < g.length; i += 2) {
        final a = g[i], b = g[i + 1];
        if (a.toLowerCase() == b.toLowerCase() && a != b) return true;
      }
      return false;
    }

    final isTestcross =
        (fullRec.hasMatch(p2) && isHetero(p1)) ||
            (fullRec.hasMatch(p1) && isHetero(p2));
    final base = p1 == p2 ? '自交' : (isTestcross ? '测交' : '杂交');
    return variant == null ? base : '$base · $variant';
  }
}
