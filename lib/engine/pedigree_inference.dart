// pedigree_inference.dart —— 经典表型系谱遗传方式推断引擎（v2.13+）
//
// 产品定位补全：系谱页（genetic_pedigree_page）是「基因型育种模拟器」
//（输入基因型 → 推演后代）；高中生物另一大系谱教学场景「给一张家族
//遗传病系谱图，判断遗传方式」此前没有工具承接——拍题/问 AI 只能问答，
//无法结构化计算。本引擎是纯规则打分制（高中课标规则集），输入成员
//表型/性别/亲子关系，输出候选遗传方式 + 命中依据。
//
// 与软件哲学一致：输入数据 → 引擎计算 → 步骤化呈现（UI 层消费
// InferenceResult.candidates 的 score/evidence 即可，无需懂规则）。
//
// 规则集（人教版必修2 第5章 + 课标 3.2.6 系谱分析）：
//   R1 无中生有：正常父母生出患病孩子 → 隐性（患病者才含致病基因），
//      且排除一切显性模式（显性患者亲本至少一方必病）。
//   R2 有中生无：患病父母生出正常孩子 → 显性，且排除一切隐性模式。
//   R3 X 连锁显性排除：女患者的父亲或儿子正常 → 排除 X 显
//      （X 显：女患者 XᴰXᵈ，父亲必给 Xᴰ → 父必病；儿子必得母一条 Xᴰ → 必病）。
//   R4 X 连锁隐性排除：男患者的母亲正常且女儿正常 → 排除 X 隐不成立…
//      精确表述：X 隐男患者（XᵃY）其女必得 Xᵃ → 女儿至少为携带者；
//      若女儿「患病」不可能除非母给 Xᵃ。判定用：男患者母亲正常 → 母为
//      携带者 XᴬXᵃ（不矛盾，不排他）；更硬的排除是「男患者父亲患病」
//      与 Y 无关 → 不构成排除。核心硬排除：女患者父亲正常 → 排除 X 隐
//      （女患者 XᵃXᵃ 必须父给 Xᵃ → 父必病）。
//   R5 Y 连锁：父病子必病、子病父必病；出现父病子正常或女患者 → 排除 Y。
//      命中「连续男传男 + 仅男患者」→ Y 支持。
//   R6 交叉遗传倾向（X 隐信号）：男患者明显多于女患者 → X 隐加分。
//   R7 代际连续性：代代相传（每代都有患者）→ 显性加分；隔代/跳跃 → 隐性加分。
//   R8 常染色体兜底：无硬排除时常显/常隐都列出，由 R1/R2/R6/R7 分胜负。
//
// 打分：硬矛盾 → 直接排除（excluded = true，不再参与排序）；软信号
// ±2 分。输出按 score 降序，附 evidence 人话条文（供 UI 逐条呈现）。

/// 性别。
enum PdSex { male, female }

/// 表型。
enum PdStatus { normal, affected }

/// 遗传方式候选。
enum InheritancePattern {
  autosomalDominant('常染色体显性'),
  autosomalRecessive('常染色体隐性'),
  xLinkedDominant('伴 X 显性'),
  xLinkedRecessive('伴 X 隐性'),
  yLinked('伴 Y 遗传');

  const InheritancePattern(this.displayName);

  /// 中文名（UI 直接呈现）。
  final String displayName;

  bool get isDominant =>
      this == InheritancePattern.autosomalDominant ||
          this == InheritancePattern.xLinkedDominant;
  bool get isXLinked =>
      this == InheritancePattern.xLinkedDominant ||
          this == InheritancePattern.xLinkedRecessive;
}

/// 系谱成员。
class PdMember {
  final String id;
  final PdSex sex;
  final PdStatus status;
  final int generation; // 世代序号（I=0, II=1…），仅用于展示/连续性分析

  const PdMember({
    required this.id,
    required this.sex,
    required this.status,
    this.generation = 0,
  });

  bool get isAffected => status == PdStatus.affected;
}

/// 亲子关系（父/母 → 子）。婚姻关系由「同代共同子女」隐含推出，
/// 引擎只依赖亲子边。
class PdRelation {
  final String parentId;
  final String childId;
  const PdRelation({required this.parentId, required this.childId});
}

/// 一个候选的推断结果。
class PatternCandidate {
  final InheritancePattern pattern;
  final int score;

  /// 人话依据条文（逐条呈现给学生：哪条规则、谁和谁的什么关系命中）。
  final List<String> evidence;

  /// 硬矛盾被排除（true = 不可能是这种遗传方式）。
  final bool excluded;

  const PatternCandidate({
    required this.pattern,
    required this.score,
    required this.evidence,
    this.excluded = false,
  });
}

/// 推断结果：候选列表（未排除的按 score 降序在前）+ 输入摘要。
class InferenceOutcome {
  final List<PatternCandidate> candidates;

  /// 输入事实的一句话摘要（UI 头部用）。
  final String summary;

  const InferenceOutcome({required this.candidates, required this.summary});

  /// 最可能的遗传方式（未排除中 score 最高）；全部排除返回 null。
  InheritancePattern? get best {
    for (final c in candidates) {
      if (!c.excluded) return c.pattern;
    }
    return null;
  }
}

/// 经典系谱遗传方式推断引擎。
class PedigreeInferenceEngine {
  /// 成员 id → 成员。
  final Map<String, PdMember> _byId = {};

  /// 亲子边：childId → parentIds。
  final Map<String, List<String>> _parentsOf = {};

  final List<PatternCandidate> _candidates = [];
  final List<String> _errors = [];

  /// 输入校验错误（成员缺失/自环等）；为空才可信任结果。
  List<String> get errors => List.unmodifiable(_errors);

  /// 执行推断。members 非空、relations 中 id 必须都在 members 里。
  InferenceOutcome infer(List<PdMember> members, List<PdRelation> relations) {
    _byId.clear();
    _parentsOf.clear();
    _candidates.clear();
    _errors.clear();

    for (final m in members) {
      if (_byId.containsKey(m.id)) {
        _errors.add('成员 id 重复：${m.id}');
      }
      _byId[m.id] = m;
    }
    for (final r in relations) {
      if (r.parentId == r.childId) {
        _errors.add('自环亲子边：${r.parentId}');
        continue;
      }
      if (!_byId.containsKey(r.parentId) || !_byId.containsKey(r.childId)) {
        _errors.add('亲子边引用了不存在的成员：${r.parentId} → ${r.childId}');
        continue;
      }
      _parentsOf.putIfAbsent(r.childId, () => []).add(r.parentId);
    }
    if (members.isEmpty) _errors.add('系谱为空：至少录入一名成员');
    if (members.where((m) => m.isAffected).isEmpty) {
      _errors.add('系谱中没有患者：无法推断遗传方式');
    }
    if (_errors.isNotEmpty) {
      return InferenceOutcome(candidates: const [], summary: '输入有误');
    }

    for (final p in InheritancePattern.values) {
      _candidates.add(PatternCandidate(
          pattern: p, score: 0, evidence: const []));
    }

    _ruleUnaffectedParentsAffectedChild();
    _ruleAffectedParentsNormalChild();
    _ruleXDadOrSonOfAffectedFemaleNormal();
    _ruleXRNormalFatherOfAffectedFemale();
    _ruleYLinked();
    _ruleSexDistribution();
    _ruleGenerationContinuity();

    _candidates.sort((a, b) {
      if (a.excluded != b.excluded) return a.excluded ? 1 : -1;
      return b.score - a.score;
    });

    final n = members.length, a = members.where((m) => m.isAffected).length;
    return InferenceOutcome(
      candidates: List.unmodifiable(_candidates),
      summary: '$n 名成员（$a 名患者）',
    );
  }

  PatternCandidate _cand(InheritancePattern p) =>
      _candidates.firstWhere((c) => c.pattern == p);

  void _hit(InheritancePattern p, int delta, String evidence) {
    final c = _cand(p);
    _candidates[_candidates.indexOf(c)] = PatternCandidate(
      pattern: p,
      score: c.score + delta,
      evidence: [...c.evidence, evidence],
      excluded: c.excluded,
    );
  }

  void _exclude(InheritancePattern p, String evidence) {
    final c = _cand(p);
    if (c.excluded) return;
    _candidates[_candidates.indexOf(c)] = PatternCandidate(
      pattern: p,
      score: c.score,
      evidence: [...c.evidence, '× 排除：$evidence'],
      excluded: true,
    );
  }

  /// R1 无中生有 → 隐性。
  void _ruleUnaffectedParentsAffectedChild() {
    for (final e in _parentsOf.entries) {
      final child = _byId[e.key]!;
      if (!child.isAffected) continue;
      for (final pid in e.value) {
        final parent = _byId[pid]!;
        if (parent.isAffected) return; // 有患病亲本，不叫无中生有
      }
      // 双亲均正常而子患病。
      final ids = e.value.map((id) => _byId[id]!.id).join('、');
      _hit(InheritancePattern.autosomalRecessive, 2,
          '无中生有：$ids 均正常却生出患病 ${child.id} → 致病基因为隐性');
      _hit(InheritancePattern.xLinkedRecessive, 2,
          '无中生有：患病 ${child.id} 的双亲表现正常 → 支持隐性');
      _exclude(InheritancePattern.autosomalDominant,
          '显性遗传中患者亲本至少一方必患病（${child.id} 无中生有）');
      _exclude(InheritancePattern.xLinkedDominant,
          '伴 X 显性中患者母亲必病或父病子病（${child.id} 无中生有）');
    }
  }

  /// R2 有中生无 → 显性。
  void _ruleAffectedParentsNormalChild() {
    for (final e in _parentsOf.entries) {
      final child = _byId[e.key]!;
      if (child.isAffected) continue;
      if (e.value.length < 2) continue;
      final p1 = _byId[e.value[0]]!, p2 = _byId[e.value[1]]!;
      if (p1.isAffected && p2.isAffected) {
        _hit(InheritancePattern.autosomalDominant, 2,
            '有中生无：${p1.id} 与 ${p2.id} 均患病却生出正常 ${child.id} → 致病基因为显性');
        _exclude(InheritancePattern.autosomalRecessive,
            '隐性遗传中患病双亲为 aa×aa，子女必患病（${child.id} 正常）');
        _exclude(InheritancePattern.xLinkedRecessive,
            '伴 X 隐性女患者 XᵃXᵃ × 男患者 XᵃY 子女必患病（${child.id} 正常）');
      }
    }
  }

  /// R3 女患者（X 显）父亲或儿子正常 → 排除 X 显。
  void _ruleXDadOrSonOfAffectedFemaleNormal() {
    for (final m in _byId.values) {
      if (m.sex != PdSex.female || !m.isAffected) continue;
      final parents = _parentsOf[m.id] ?? const [];
      for (final pid in parents) {
        final father = _byId[pid]!;
        if (father.sex == PdSex.male && !father.isAffected) {
          _exclude(InheritancePattern.xLinkedDominant,
              '女患者 ${m.id} 的父亲 ${father.id} 正常——伴 X 显性女患者的父亲必患病');
        }
      }
      for (final e in _parentsOf.entries) {
        if (!e.value.contains(m.id)) continue;
        final child = _byId[e.key]!;
        if (child.sex == PdSex.male && !child.isAffected) {
          _exclude(InheritancePattern.xLinkedDominant,
              '女患者 ${m.id} 的儿子 ${child.id} 正常——伴 X 显性女患者的儿子必患病');
        }
      }
    }
  }

  /// R4 女患者父亲正常 → 排除 X 隐（女患者 XᵃXᵃ 必从父得 Xᵃ，父必病）。
  void _ruleXRNormalFatherOfAffectedFemale() {
    for (final m in _byId.values) {
      if (m.sex != PdSex.female || !m.isAffected) continue;
      final parents = _parentsOf[m.id] ?? const [];
      for (final pid in parents) {
        final father = _byId[pid]!;
        if (father.sex == PdSex.male && !father.isAffected) {
          _exclude(InheritancePattern.xLinkedRecessive,
              '女患者 ${m.id} 的父亲 ${father.id} 正常——伴 X 隐性女患者的父亲必患病');
        }
      }
    }
  }

  /// R5 Y 连锁：仅男患者、父病子必病。女患者或父病子正常 → 排除。
  void _ruleYLinked() {
    for (final m in _byId.values) {
      if (m.sex == PdSex.female && m.isAffected) {
        _exclude(InheritancePattern.yLinked, '女患者 ${m.id}：伴 Y 遗传只有男性患病');
        return;
      }
    }
    for (final e in _parentsOf.entries) {
      final child = _byId[e.key]!;
      for (final pid in e.value) {
        final parent = _byId[pid]!;
        if (parent.sex != PdSex.male) continue;
        if (parent.isAffected && !child.isAffected) {
          _exclude(InheritancePattern.yLinked,
              '父病子不病：${parent.id} 患病而 ${child.id} 正常——伴 Y 父病子必病');
        }
        if (child.isAffected && !parent.isAffected) {
          _exclude(InheritancePattern.yLinked,
              '子病父不病：${child.id} 患病而父亲 ${parent.id} 正常——伴 Y 子病父必病');
        }
      }
    }
    // 支持信号：全部患者为男性且无排除。
    final c = _cand(InheritancePattern.yLinked);
    if (!c.excluded) {
      final allMale = _byId.values
          .where((m) => m.isAffected)
          .every((m) => m.sex == PdSex.male);
      if (allMale) {
        _hit(InheritancePattern.yLinked, 2, '全部患者均为男性 → 支持伴 Y 遗传');
      }
    }
  }

  /// R6 性别分布：男患者明显多于女患者 → X 隐加分。
  void _ruleSexDistribution() {
    final males =
        _byId.values.where((m) => m.isAffected && m.sex == PdSex.male).length;
    final females = _byId.values
        .where((m) => m.isAffected && m.sex == PdSex.female)
        .length;
    if (males >= 2 && males > females * 2) {
      _hit(InheritancePattern.xLinkedRecessive, 1,
          '男患者 $males 人远多于女患者 $females 人 → 倾向伴 X 隐性');
    }
    if (females >= 2 && females > males * 2) {
      _hit(InheritancePattern.xLinkedDominant, 1,
          '女患者 $females 人远多于男患者 $males 人 → 倾向伴 X 显性');
    }
  }

  /// R7 代际连续性：代代有患者 → 显性加分；隔代跳跃 → 隐性加分。
  void _ruleGenerationContinuity() {
    final genWithAffected = <int>{};
    for (final m in _byId.values) {
      if (m.isAffected) genWithAffected.add(m.generation);
    }
    final gens = _byId.values.map((m) => m.generation).toSet()..addAll(genWithAffected);
    final minG = gens.isEmpty ? 0 : gens.reduce((a, b) => a < b ? a : b);
    final maxG = gens.isEmpty ? 0 : gens.reduce((a, b) => a > b ? a : b);
    var continuous = true;
    for (var g = minG; g <= maxG; g++) {
      if (!genWithAffected.contains(g)) {
        continuous = false;
        break;
      }
    }
    if (continuous && genWithAffected.length >= 3) {
      _hit(InheritancePattern.autosomalDominant, 1,
          '连续 ${genWithAffected.length} 代均有患者 → 倾向显性（代代相传）');
      _hit(InheritancePattern.xLinkedDominant, 1,
          '连续 ${genWithAffected.length} 代均有患者 → 显性也可代代相传');
    }
    if (!continuous && genWithAffected.length >= 2) {
      _hit(InheritancePattern.autosomalRecessive, 1,
          '患者隔代出现 → 倾向隐性（隐性基因可携带不发病）');
      _hit(InheritancePattern.xLinkedRecessive, 1,
          '患者隔代出现 → 伴 X 隐性可经携带者跨代传递（交叉遗传）');
    }
  }
}
