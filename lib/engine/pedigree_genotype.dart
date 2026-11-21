// pedigree_genotype.dart —— 半开放基因型反推（v2.13+）
//
// 类型（PdMember/PdRelation/InheritancePattern）复用 pedigree_inference.dart。

import 'pedigree_inference.dart';

//
// 高考 staple 升级：推断器不止「判遗传方式」，还要「已知遗传方式，
// 求某成员基因型概率」。经典规则集（人教必修2 第5章）：
//   常隐：患者=aa；患者双亲均 Aa；正常同胞（双亲均携带）→
//         AA 1/3、Aa 2/3（条件概率，课本金标准）；与患者婚配的正常
//         配偶 → 必是 Aa（有患病子女时）否则未定。
//   常显：患者≈Aa（若其任一亲本正常）；正常=aa。
//   伴X隐：男患=XᵃY；女患=XᵃXᵃ；女患之父必 XᵃY；男患之女至少携带；
//         正常父 → 女儿非携带（Xᴬ 必来自父）。
//   伴X显：男患=XᴰY；女患父必患；正常子之母不可能是纯合患者…
//   伴Y：男患=致病半合子（无基因型写法，报告「Y 连锁致病」）。
//
// 输出三档：确定（deduced）/ 概率（probabilistic，附条件）/
// 未定（unknown——诚实输出，不编概率）。

/// 一名成员的反推结论。
class GenotypeCall {
  final String memberId;

  /// 基因型写法（如 'Aa'、'XAXa'、'aa'），或 Y 连锁的语义描述。
  final String genotype;

  /// 结论档位：确定 / 概率 / 未定。
  final GenotypeConfidence confidence;

  /// 人话依据（学生看到的推理链）。
  final String evidence;

  const GenotypeCall({
    required this.memberId,
    required this.genotype,
    required this.confidence,
    required this.evidence,
  });
}

enum GenotypeConfidence { deduced, probabilistic, unknown }

/// 半开放反推结果。
class GenotypeAnalysis {
  final InheritancePattern pattern;
  final List<GenotypeCall> calls;

  /// 汇总句（UI 头部）。
  final String summary;

  const GenotypeAnalysis({
    required this.pattern,
    required this.calls,
    required this.summary,
  });
}

/// 半开放反推引擎（静态方法，复用推断器的成员/关系模型）。
class PedigreeGenotypeAnalysis {
  /// 基于系谱事实 + 指定遗传方式，逐成员给出基因型结论。
  /// members/relations 校验规则与推断引擎一致（复用其校验思路）。
  static GenotypeAnalysis analyze(
    List<PdMember> members,
    List<PdRelation> relations,
    InheritancePattern pattern,
  ) {
    final byId = {for (final m in members) m.id: m};
    final parentsOf = <String, List<String>>{};
    final childrenOf = <String, List<String>>{};
    for (final r in relations) {
      parentsOf.putIfAbsent(r.childId, () => []).add(r.parentId);
      childrenOf.putIfAbsent(r.parentId, () => []).add(r.childId);
    }
    // 患病同胞表：childId → 是否共享至少一个亲本的患者存在。
    final hasAffectedSibling = <String, bool>{
      for (final m in members)
        m.id: members.any((o) =>
            o.id != m.id &&
            o.isAffected &&
            (parentsOf[m.id] ?? const [])
                .any((p) => (parentsOf[o.id] ?? const []).contains(p))),
    };
    // 患病子女表：parentId → 是否有患病子女。
    final hasAffectedChild = <String, bool>{
      for (final m in members)
        m.id: (childrenOf[m.id] ?? const [])
            .any((cid) => byId[cid]?.isAffected ?? false),
    };

    final calls = <GenotypeCall>[];
    for (final m in members) {
      calls.add(_analyzeOne(
          m, byId, parentsOf, hasAffectedSibling, hasAffectedChild, pattern));
    }

    final affected = members.where((m) => m.isAffected).length;
    return GenotypeAnalysis(
      pattern: pattern,
      calls: calls,
      summary:
          '${pattern.displayName} · ${members.length} 名成员（$affected 名患者）的基因型反推',
    );
  }

  static GenotypeCall _analyzeOne(
    PdMember m,
    Map<String, PdMember> byId,
    Map<String, List<String>> parentsOf,
    Map<String, bool> hasAffectedSibling,
    Map<String, bool> hasAffectedChild,
    InheritancePattern pattern,
  ) {
    final parents = (parentsOf[m.id] ?? const [])
        .map((id) => byId[id]!)
        .toList();
    final father = parents.where((p) => p.sex == PdSex.male).firstOrNull;
    final mother = parents.where((p) => p.sex == PdSex.female).firstOrNull;

    switch (pattern) {
      case InheritancePattern.autosomalRecessive:
        return _autoRecessive(m, father, mother, hasAffectedSibling[m.id] ?? false,
            hasAffectedChild[m.id] ?? false);
      case InheritancePattern.autosomalDominant:
        return _autoDominant(m, father, mother);
      case InheritancePattern.xLinkedRecessive:
        return _xRecessive(m, father, mother);
      case InheritancePattern.xLinkedDominant:
        return _xDominant(m, father, mother);
      case InheritancePattern.yLinked:
        return GenotypeCall(
          memberId: m.id,
          genotype: m.isAffected ? 'Y 连锁致病半合子' : '正常（无 Y 致病基因）',
          confidence: GenotypeConfidence.deduced,
          evidence: m.isAffected
              ? '伴 Y 遗传：男性患者的 Y 染色体带致病基因'
              : '伴 Y 遗传：男性正常 = 无该 Y 致病基因',
        );
    }
  }

  // ── 常染色体隐性 ──────────────────────────────────────────────
  // 课本记号：致病 a，正常 A。
  static GenotypeCall _autoRecessive(PdMember m, PdMember? father,
      PdMember? mother, bool hasAffectedSibling, bool hasAffectedChild) {
    if (m.isAffected) {
      return GenotypeCall(
        memberId: m.id,
        genotype: 'aa',
        confidence: GenotypeConfidence.deduced,
        evidence: '常隐患者 = 隐性纯合 aa',
      );
    }
    // 有患病子女的正常亲本 → 必为携带者 Aa（课本：无中生有的双亲）。
    if (hasAffectedChild) {
      return GenotypeCall(
        memberId: m.id,
        genotype: 'Aa（携带者）',
        confidence: GenotypeConfidence.deduced,
        evidence: '有患病子女（无中生有）→ 正常亲本必为携带者 Aa',
      );
    }
    // 正常成员：父母均携带（有患病同胞）→ AA 1/3 / Aa 2/3。
    // hasAffectedSibling 由 analyze 外层扫描传入（见方法签名）。
    if ((father?.isAffected ?? false) || (mother?.isAffected ?? false)) {
      // 亲本之一是患者 aa → 正常子女必得一个 a → 必为携带者 Aa。
      final which = (father?.isAffected ?? false)
          ? '父亲患病（aa）'
          : '母亲患病（aa）';
      return GenotypeCall(
        memberId: m.id,
        genotype: 'Aa（携带者）',
        confidence: GenotypeConfidence.deduced,
        evidence: '$which，正常 $which 子女必得一个 a → 必为携带者 Aa',
      );
    }
    if (hasAffectedSibling) {
      return GenotypeCall(
        memberId: m.id,
        genotype: 'AA 1/3 或 Aa 2/3',
        confidence: GenotypeConfidence.probabilistic,
        evidence: '有患病同胞 → 父母均 Aa；表现正常的子女中'
            ' AA:Aa = 1:2（课本条件概率）',
      );
    }
    return GenotypeCall(
      memberId: m.id,
      genotype: 'AA 或 Aa',
      confidence: GenotypeConfidence.unknown,
      evidence: '家族无患者信息，无法确定是否携带',
    );
  }

  // ── 常染色体显性 ──────────────────────────────────────────────
  static GenotypeCall _autoDominant(
      PdMember m, PdMember? father, PdMember? mother) {
    // 课本记号：致病 A（显性），正常 a。
    if (!m.isAffected) {
      return GenotypeCall(
        memberId: m.id,
        genotype: 'aa',
        confidence: GenotypeConfidence.deduced,
        evidence: '常显正常 = 隐性纯合 aa',
      );
    }
    // 患者：任一亲本正常（aa）→ 患者必为 Aa。
    final normalParent = [father, mother]
        .whereType<PdMember>()
        .where((p) => !p.isAffected)
        .firstOrNull;
    if (normalParent != null) {
      return GenotypeCall(
        memberId: m.id,
        genotype: 'Aa',
        confidence: GenotypeConfidence.deduced,
        evidence: '亲本 ${normalParent.id} 正常（aa）→ 患者必为杂合 Aa',
      );
    }
    return GenotypeCall(
      memberId: m.id,
      genotype: 'AA 或 Aa',
      confidence: GenotypeConfidence.unknown,
      evidence: '双亲均患病，无法区分纯合/杂合（需子女信息）',
    );
  }

  // ── 伴 X 隐性 ────────────────────────────────────────────────
  static GenotypeCall _xRecessive(
      PdMember m, PdMember? father, PdMember? mother) {
    if (m.sex == PdSex.male) {
      return GenotypeCall(
        memberId: m.id,
        genotype: m.isAffected ? 'XaY' : 'XAY',
        confidence: GenotypeConfidence.deduced,
        evidence: m.isAffected
            ? '伴 X 隐性男患者 = XaY（半合子即表现）'
            : '伴 X 隐性正常男 = XAY',
      );
    }
    // 女性。
    if (m.isAffected) {
      return GenotypeCall(
        memberId: m.id,
        genotype: 'XaXa',
        confidence: GenotypeConfidence.deduced,
        evidence: '女患者 = XaXa（父必 XaY、母至少给 Xa）',
      );
    }
    // 正常女性：父亲患病 → 必得 Xa → 必为携带者 XAXa。
    if (father?.isAffected ?? false) {
      return GenotypeCall(
        memberId: m.id,
        genotype: 'XAXa（携带者）',
        confidence: GenotypeConfidence.deduced,
        evidence: '父亲患病（XaY）→ 女儿必得 Xa → 携带者 XAXa',
      );
    }
    // 母亲患病 → 女儿必得母 Xa；父正常给 XA → XAXa 携带。
    if (mother?.isAffected ?? false) {
      return GenotypeCall(
        memberId: m.id,
        genotype: 'XAXa（携带者）',
        confidence: GenotypeConfidence.deduced,
        evidence: '母亲患病（XaXa）必给女儿 Xa，父正常给 XA → 携带者',
      );
    }
    // 有患病同胞（兄弟）→ 母携带概率条件化（简化给未定 + 说明）。
    return GenotypeCall(
      memberId: m.id,
      genotype: 'XAXA 或 XAXa',
      confidence: GenotypeConfidence.unknown,
      evidence: '父亲正常 → 女儿非携带概率大；是否携带取决于母亲'
          '（有患病儿子时母必为携带者）',
    );
  }

  // ── 伴 X 显性 ────────────────────────────────────────────────
  static GenotypeCall _xDominant(
      PdMember m, PdMember? father, PdMember? mother) {
    if (m.sex == PdSex.male) {
      return GenotypeCall(
        memberId: m.id,
        genotype: m.isAffected ? 'XDY' : 'XdY',
        confidence: GenotypeConfidence.deduced,
        evidence: m.isAffected
            ? '伴 X 显性男患者 = XDY'
            : '伴 X 显性正常男 = XdY（母不可能是纯合患者）',
      );
    }
    if (m.isAffected) {
      // 父亲正常 → 女患者必为 XDXd（XD 只能来自母）。
      if (father != null && !father.isAffected) {
        return GenotypeCall(
          memberId: m.id,
          genotype: 'XDXd',
          confidence: GenotypeConfidence.deduced,
          evidence: '父亲正常（XdY）→ 女患者的 XD 只能来自母亲 → XDXd',
        );
      }
      return GenotypeCall(
        memberId: m.id,
        genotype: 'XDXD 或 XDXd',
        confidence: GenotypeConfidence.unknown,
        evidence: '双亲信息不足，无法区分纯合/杂合',
      );
    }
    // 正常女 = XdXd。
    return GenotypeCall(
      memberId: m.id,
      genotype: 'XdXd',
      confidence: GenotypeConfidence.deduced,
      evidence: '伴 X 显性正常女 = XdXd',
    );
  }
}
