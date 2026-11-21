// pedigree_graph.dart —— 系谱计算图引擎（状态 + 计算一体，UI 只跟它对话）
//
// 实现契约：docs/tasks/pedigree_api_contract.md（公开签名冻结，内部实现自由）。
// 数学复用：pedigree_engine.dart 的 PedigreeEngine.cross（double 归一化分布）。
//
// 语义要点（对应契约「语义约定」）：
//   1) P 代：father=male、mother=female + 一条 mating 边。
//   2) 扩展下一代：当前最大世代 male 池 × female 池按概率加权两两杂交，
//      group 节点同时进两个池；外来样本 probability=0，入池权重按 1.0 计。
//   3) 显式 mating 边的定向杂交结果按端点池内归一化权重并入，统一归一化。
//   4) 每个新节点记录 lineage 边（来源 = 上一代全部贡献者）。
//   5) 概率沿用 double 归一化分布。
//   6) recomputeFrom(n)：丢弃 n+1 代及以后，按当前第 n 代池重建到原 maxGeneration。
//   7) id 稳定：同位置节点复用 F<代>#<序号>；外来样本 EXT#<递增> 永不复用。

import 'pedigree_engine.dart';

/// 节点性别/种类：male（♂ 方形）、female（♀ 圆形）、
/// group（计算算出的分布桶，群体中性，渲染成圆角矩形）。
enum PedigreeNodeKind { male, female, group }

/// 系谱节点（不可变）。
class PedigreeNode {
  final String id; // 稳定唯一 id，如 'P-father' / 'F2#3' / 'EXT#1'
  final PedigreeNodeKind kind;
  final String genotype; // 如 'AaBb'
  final int generation; // 0=P 代，1=F1，…
  final double probability; // 世代内概率权重；外来样本为 0（不参与概率展示）
  final bool isExternal; // 用户右键添加的外来样本

  /// 家族编号（R14）：0=初始家族（标签 A）；addFamily 依次分配
  /// 1、2…（B、C…）；跨家族交配的子代进入「合并家族」
  /// （成分并集，标签如 A×B）。同家族成员组成独立交配池。
  final int familyId;

  /// XY 性别存证：开启「携带 XY」开关后，每个计算桶记录雄性占比
  ///（标准 XY 性别决定 = 0.5）；为 null 表示不区分性别（默认）。
  final double? maleFraction;

  /// v2.1i 致死标记：true=此节点命中致死条件、画 ✕ + lethal 色
  /// + 信息面板标「（纯合致死）」。存活子代仍按原概率展示
  ///（归一化到存活子代总和=1）。
  final bool isLethal;

  const PedigreeNode({
    required this.id,
    required this.kind,
    required this.genotype,
    required this.generation,
    required this.probability,
    required this.isExternal,
    this.maleFraction,
    this.familyId = 0,
    this.isLethal = false,
  });

  @override
  String toString() =>
      '$id($genotype, gen=$generation, p=${probability.toStringAsFixed(4)}, lethal=$isLethal)';
}

/// 边：mating=同世代雌雄交配横线；lineage=亲代→子代纵向连线。
enum PedigreeEdgeKind { mating, lineage }

class PedigreeEdge {
  final String fromId;
  final String toId;
  final PedigreeEdgeKind kind;

  /// R32：mating 边建边时两端点的性别（male/female；group 桶记 null）。
  /// 相连灯效据此精确到半边：即便重算把半边端点降级重映射回整桶，
  /// 仍能恢复「这条边当时连的是哪一半」——同性交配（male×male /
  /// female×female）不再被「强制异性半边」的兜底规则误判。
  /// 仅 mating 边有意义；lineage 边不填。
  final PedigreeNodeKind? fromSex;
  final PedigreeNodeKind? toSex;

  const PedigreeEdge(this.fromId, this.toId, this.kind,
      {this.fromSex, this.toSex});

  @override
  String toString() => '$fromId -${kind.name}-> $toId';
}

/// 计算图引擎：状态 + 计算一体，UI 只跟它对话。
/// R16：引擎状态快照（操作日志/多步回退）。由 takeSnapshot 创建，
/// 只读数据载体；restoreSnapshot 把引擎还原到该状态。
class PedigreeSnapshot {
  final List<PedigreeNode> nodes;
  final List<PedigreeEdge> edges;
  final int maxGeneration;
  final int extCounter;
  final int splitCounter;
  final bool allowSameSexMating;
  final bool allowMissingGeneMating;
  final bool trackSex;
  final SexLinkedConfig? sexLinked;
  final bool allowPolyploid;
  final String? lethalGenotype;
    final List<String> lethalGens;
  final List<Set<int>> familyConstituents;
  final Map<String, int> mergedIndex;
  final Map<int, int> frontier;

  const PedigreeSnapshot._({
    required this.nodes,
    required this.edges,
    required this.maxGeneration,
    required this.extCounter,
    required this.splitCounter,
    required this.allowSameSexMating,
    required this.allowMissingGeneMating,
    required this.trackSex,
    required this.sexLinked,
    required this.allowPolyploid,
    required this.lethalGenotype,
    required this.lethalGens,
    required this.familyConstituents,
    required this.mergedIndex,
    required this.frontier,
  });
}

/// v2.1 某对位点的等位/基因型频率（教学口径：按节点=个体计数统计，
/// 不按概率加权、不去重）。
class LocusFreq {
  final String locus; // 'A/a'、'B/b'、'C/c'…
  final double p; // 显性等位频率
  final double q; // 隐性等位频率 = 1-p
  final double fAA, fAa, faa; // 基因型频率（未出现的基因型为 0）

  const LocusFreq({
    required this.locus,
    required this.p,
    required this.q,
    required this.fAA,
    required this.fAa,
    required this.faa,
  });

  @override
  String toString() =>
      '$locus p=${p.toStringAsFixed(4)} q=${q.toStringAsFixed(4)} '
      'fAA=${fAA.toStringAsFixed(4)} fAa=${fAa.toStringAsFixed(4)} '
      'faa=${faa.toStringAsFixed(4)}';
}

class PedigreeGraphEngine {
  /// 内部安全阀：最多展开到第 20 代。
  static const int safetyMaxGeneration = 20;

  final PedigreeEngine _math = PedigreeEngine();

  final List<PedigreeNode> _nodes = [];
  final List<PedigreeEdge> _edges = [];

  int _maxGeneration = 0;

  /// 外来样本 id 计数器，单调递增、永不复用。
  int _extCounter = 0;

  /// 同性交配开关（普适性：雌雄同体/同配生殖物种）。
  /// false（默认）= 个体间必须一雄一雌；true = 雄×雄 / 雌×雌也允许。
  /// group 桶为群体中性，任何设置下都可与任何性别连线。
  bool allowSameSexMating = false;

  /// 基因缺失交配开关（R18）。false（默认）= 基因对数不一致的个体
  /// 禁止连线/添加/杂交（crossGametes 抛 ArgumentError）；true = 按
  /// 位点字母对齐合并，缺失方补 '-'（子代标注「基因缺失」，如
  /// 三倍体×二倍体场景 AABBCC × aa → AaB-C-）。
  bool allowMissingGeneMating = false;

  /// R19 删除黑名单：'familyId:generation:genotype'。**一次性**——
  /// 只在「删除操作 → 立即重算」那一次重建中拦截被删基因型，随后
  /// 由页面调用 clearRemovedGenotypes() 解除：删除即生效，且之后
  /// 点「计算」可重新推导出该代（用户 R20 反馈：删除后必须能重新
  /// 计算，不能永久挡住）。快照不承载黑名单（restore 时清空）。
  final Set<String> _removedGenotypes = {};

  static String _genKey(int familyId, int generation, String genotype) =>
      '$familyId:$generation:$genotype';

  /// 解除全部删除标记：删除流程在「立即重算」之后调用，让后续
  /// 主动计算恢复正常生成（被永久删除的只有外来样本本身）。
  void clearRemovedGenotypes() => _removedGenotypes.clear();

  /// XY 性别存证开关。true 时新生成的计算桶携带 maleFraction=0.5
  ///（标准 XX♀/XY♂ 性别决定，1:1）；false（默认）= 桶不区分性别。
  bool trackSex = false;

  /// 伴性遗传配置（可选）：null = 不启用。
  /// 启用后，基因型解析把 X/x/Y/y 作为伴性位点，结果按
  /// X=… / x=… / Y=… / y=… 标注表型并着色（大 X=蓝，小 x=黄…）。
  SexLinkedConfig? sexLinked;

  /// 多倍体开关（v2.1）：false=严格 2n（现状，零改变）；true=允许每位点
  /// 1~5 个等位（如 'Aaa' 3n、'Aaaa' 4n、'Aaaaa' 5n；单个等位=1n 单倍体）。
  /// 开启后：配子每对位点取 1 个等位（n 份等位 → n 种配子等位，概率=
  /// 份数/n）；子代倍性保持亲代倍性（每位点：父方取中等位 ⌈n/2⌉ 份 +
  /// 母方 ⌊n/2⌋ 份，教学简化）；n=2 时与严格模式逐位一致（回归保护）。
  bool allowPolyploid = false;

  /// 位点级致死基因型（v2.1c 升级为列表）：每个条目 = 某一位点的纯合
  /// 基因型（规范化形式，如 'AA'/'aa'/'AAA'），子代**任意位点**命中即
  /// 合子淘汰，其余概率重归一；某次交配全淘汰则不出子代（允许）。
  /// 大小写保留（'AA' 显性致死 ≠ 'Aa' ≠ 'aa' 隐性致死），字母数=倍性
  /// （'AAA' 三倍体纯合；倍性校验由页面与多倍体开关联动）。
  String? get lethalGenotype =>
      _lethalGens.isEmpty ? null : _lethalGens.first;

  /// 设定单一致死（旧页面语义）：清空列表后加入一个。
  set lethalGenotype(String? g) {
    _lethalGens
      ..clear()
      ..addAll(g == null ? const [] : [_canonLocus(g)]);
  }

  /// v2.1c 多条件致死列表（可含多个位点，如 'AA' 与 'bb' 并存）。
  final List<String> _lethalGens = [];

  List<String> get lethalGens => List.unmodifiable(_lethalGens);

  /// 追加一个致死条件；非法（空 / 超 5 字母 / 含非字母）返回 false。
  bool addLethal(String g) {
    final c = _canonLocus(g);
    if (c.isEmpty || c.length > 5 ||
        RegExp(r'^[A-Za-z]+$').hasMatch(c) == false) {
      return false;
    }
    if (!_lethalGens.contains(c)) _lethalGens.add(c);
    return true;
  }

  /// 移除一个致死条件；不存在忽略。
  void removeLethal(String g) => _lethalGens.remove(_canonLocus(g));

  /// 清空全部致死条件。
  void clearLethal() => _lethalGens.clear();

  /// 分裂计数器：桶拆 X/Y 子节点时生成稳定 id（SPLIT#<递增>）。
  int _splitCounter = 0;

  // ── 多家族（R14） ─────────────────────────────────────
  /// 家族注册表：家族编号 → 创始家族成分集合。创始家族 i 的成分
  /// 是 {i}；合并家族的成分是双方并集（如 {0,1} 标签 A×B）。
  final List<Set<int>> _familyConstituents = [
    {0}
  ];

  /// 合并家族索引：排序成分 key（如 '0+1'）→ 家族编号（幂等，
  /// 保证重算后同一对成分拿到同一编号）。
  final Map<String, int> _mergedIndex = {};

  /// 家族前沿：家族编号 → 已推进到的世代（该家族最新一代）。
  /// 节点被删空的家族移出本表（休眠），待跨家族边重燃。
  final Map<int, int> _frontier = {0: 0};

  /// 以双亲基因型初始化（父 ♂ × 母 ♀，组成 P 代及二者间 mating 边）。
  PedigreeGraphEngine({
    required String fatherGenotype,
    required String motherGenotype,
  }) {
    _nodes.add(PedigreeNode(
      id: 'P-father',
      kind: PedigreeNodeKind.male,
      genotype: fatherGenotype,
      generation: 0,
      probability: 1.0,
      isExternal: false,
    ));
    _nodes.add(PedigreeNode(
      id: 'P-mother',
      kind: PedigreeNodeKind.female,
      genotype: motherGenotype,
      generation: 0,
      probability: 1.0,
      isExternal: false,
    ));
    _edges.add(const PedigreeEdge('P-father', 'P-mother', PedigreeEdgeKind.mating));
  }

  // ── R16 快照（操作日志 / 多步回退） ─────────────────────
  /// 当前状态的不可变快照。节点/边对象字段全 final，列表浅拷贝即可；
  /// 家族成分 Set 需深拷贝（运行时会被并集修改）。
  PedigreeSnapshot takeSnapshot() => PedigreeSnapshot._(
        nodes: List.of(_nodes),
        edges: List.of(_edges),
        maxGeneration: _maxGeneration,
        extCounter: _extCounter,
        splitCounter: _splitCounter,
        allowSameSexMating: allowSameSexMating,
        allowMissingGeneMating: allowMissingGeneMating,
        trackSex: trackSex,
        sexLinked: sexLinked,
        allowPolyploid: allowPolyploid,
        lethalGenotype: lethalGenotype,
        lethalGens: List.of(_lethalGens),
        familyConstituents: [for (final s in _familyConstituents) Set.of(s)],
        mergedIndex: Map.of(_mergedIndex),
        frontier: Map.of(_frontier),
      );

  /// 恢复到快照状态（含开关 trackSex/allowSameSexMating/sexLinked，
  /// 调用方需同步回写 UI 开关）。回退语义由调用方控制：本方法只还原。
  void restoreSnapshot(PedigreeSnapshot s) {
    _nodes
      ..clear()
      ..addAll(s.nodes);
    _edges
      ..clear()
      ..addAll(s.edges);
    _maxGeneration = s.maxGeneration;
    _extCounter = s.extCounter;
    _splitCounter = s.splitCounter;
    allowSameSexMating = s.allowSameSexMating;
    allowMissingGeneMating = s.allowMissingGeneMating;
    trackSex = s.trackSex;
    sexLinked = s.sexLinked;
    allowPolyploid = s.allowPolyploid;
    lethalGenotype = s.lethalGenotype;
    _lethalGens
      ..clear()
      ..addAll(s.lethalGens.isNotEmpty
          ? s.lethalGens
          : (s.lethalGenotype == null ? const [] : [_canonLocus(s.lethalGenotype!)]));
    _familyConstituents
      ..clear()
      ..addAll([for (final c in s.familyConstituents) Set.of(c)]);
    _mergedIndex
      ..clear()
      ..addAll(s.mergedIndex);
    _frontier
      ..clear()
      ..addAll(s.frontier);
    // 黑名单不进快照：回退/恢复后一切删除标记清空（删除是一次的）
    _removedGenotypes.clear();
  }

  /// 当前已展开的最大世代（初始为 0，即只有 P 代）。
  int get maxGeneration => _maxGeneration;

  /// 全部节点（含外来样本），按 (generation, id) 稳定排序。
  List<PedigreeNode> get nodes {
    final out = List<PedigreeNode>.of(_nodes);
    out.sort((a, b) {
      final g = a.generation.compareTo(b.generation);
      return g != 0 ? g : a.id.compareTo(b.id);
    });
    return List.unmodifiable(out);
  }

  /// v2.19.6 性能：id → 节点 Map，用于页面侧按 id 快速定位（替代
  /// 旧的 O(N) `nodes.where(...)` 线性查找）。每次按 nodes 当前快照
  /// 重建——与 nodes getter 风格一致，调用方应避免在同一帧重复访问。
  Map<String, PedigreeNode> get nodesById => {
        for (final n in _nodes) n.id: n,
      };

  /// 全部边（mating + lineage）。
  List<PedigreeEdge> get edges => List.unmodifiable(_edges);

  // ── 多家族（R14）公开 API ─────────────────────────────

  /// 当前有节点的家族编号（升序）。布局分栏与下拉选择以此为准。
  List<int> get familyIds {
    final s = <int>{for (final n in _nodes) n.familyId};
    return s.toList()..sort();
  }

  /// 家族显示名：创始家族 A/B/C…；合并家族用 × 连接成分（A×B）。
  String familyLabel(int familyId) {
    if (familyId < 0 || familyId >= _familyConstituents.length) return '?';
    final c = _familyConstituents[familyId].toList()..sort();
    return c.map(_founderLetter).join('\u00d7');
  }

  static String _founderLetter(int founderIndex) => founderIndex < 26
      ? String.fromCharCode(65 + founderIndex)
      : 'F${founderIndex + 1}';

  /// 新增一个独立家族：双亲（父 ♂ × 母 ♀）落在 P 代（世代 0）并附
  /// 一条 mating 边；返回新家族编号。新家族独立繁衍（自己的交配池），
  /// 点「计算」/「计算下一代」后产生自己的 F1；与既有家族的成员
  /// 连线（跨家族交配）时，子代进入合并家族（如 A×B）。
  int addFamily({
    required String fatherGenotype,
    required String motherGenotype,
  }) {
    // v2.1：严格模式保持「成对字母」校验；多倍体模式放行 1~5n 形态
    //（位点内等位数一致），家族内一致性由 _checkPairCount 兜底。
    _validateGenotypeShape(fatherGenotype, allowPolyploid: allowPolyploid);
    _validateGenotypeShape(motherGenotype, allowPolyploid: allowPolyploid);
    final k = _familyConstituents.length;
    _familyConstituents.add({k});
    _frontier[k] = 0;
    _nodes.add(PedigreeNode(
      id: 'P$k-father',
      kind: PedigreeNodeKind.male,
      genotype: fatherGenotype,
      generation: 0,
      probability: 1.0,
      isExternal: false,
      familyId: k,
    ));
    _nodes.add(PedigreeNode(
      id: 'P$k-mother',
      kind: PedigreeNodeKind.female,
      genotype: motherGenotype,
      generation: 0,
      probability: 1.0,
      isExternal: false,
      familyId: k,
    ));
    _edges.add(
        PedigreeEdge('P$k-father', 'P$k-mother', PedigreeEdgeKind.mating));
    return k;
  }

  /// 某代节点列表；该代必须已展开，否则返回空列表。
  List<PedigreeNode> nodesOf(int generation) {
    if (generation < 0 || generation > _maxGeneration) return const [];
    return List.unmodifiable(_nodes.where((n) => n.generation == generation));
  }

  /// 懒扩展一代（R14 多家族）：每个活跃家族各自从自己的前沿推进
  /// 一代（多家族 = 多棵独立树齐头并进），返回本次创建的全部节点。
  /// 内部安全阀 20 代：所有家族都到顶才抛 StateError。
  List<PedigreeNode> expandNextGeneration() {
    // 快照本次要推进的家族：同一次调用内由跨家族边新建的合并家族
    // 不连锁推进（它的第一代就是本次产出的子代）。
    final advancing = <int>[
      for (final e in _frontier.entries)
        if (e.value < safetyMaxGeneration) e.key
    ]..sort();
    if (advancing.isEmpty) {
      throw StateError(
          '已达到安全阀上限第 $safetyMaxGeneration 代，禁止继续扩展');
    }
    final created = <PedigreeNode>[];
    for (final f in advancing) {
      created.addAll(_expandFamily(f));
    }
    _maxGeneration = _frontier.values.fold(0, (a, b) => a > b ? a : b);
    return List.unmodifiable(created);
  }

  /// 推进单个家族一代（frontier → frontier+1），返回新建节点。
  /// 本家族池随机交配 + 同家族定向边 → 本家族子代；
  /// 本家族作为驱动方的跨家族边 → 子代进入对应合并家族。
  List<PedigreeNode> _expandFamily(int familyId) {
    final from = _frontier[familyId] ?? 0;
    if (from >= safetyMaxGeneration) return const [];
    // 前沿世代已无成员（合并家族节点被删空）：休眠家族不空转推进。
    if (!_nodes.any((n) => n.familyId == familyId && n.generation == from)) {
      return const [];
    }
    final to = from + 1;
    final res = _computeFamilyNext(familyId, from);
    final created = <PedigreeNode>[];

    void createNodes(int fam, int gen, Map<String, double> dist,
        Map<String, double> lethal, Set<String> contributors) {
      // 确定性排序：概率降序，其次基因型字母序 —— 保证重算后 id 位置稳定。
      final labels = dist.keys.toList()
        ..sort((a, b) {
          final p = dist[b]!.compareTo(dist[a]!);
          return p != 0 ? p : a.compareTo(b);
        });
      // id 序号从该世代既有计算节点数继续：多家族/多批次共用一代时
      // 不重号；单家族时与旧版编号逐一致（F<代>#0 起）。
      var seq =
          _nodes.where((n) => !n.isExternal && n.generation == gen).length;
      for (final g in labels) {
        final node = PedigreeNode(
          id: 'F$gen#$seq',
          kind: PedigreeNodeKind.group,
          genotype: g,
          generation: gen,
          probability: dist[g]!,
          isExternal: false,
          // XY 存证：标准 XY 性别决定下子代雌雄比恒为 1:1
          maleFraction: trackSex ? 0.5 : null,
          familyId: fam,
        );
        seq++;
        _nodes.add(node);
        created.add(node);
        // lineage 边：每个新节点 ← 上一代全部贡献者。
        for (final src in contributors) {
          _edges.add(PedigreeEdge(src, node.id, PedigreeEdgeKind.lineage));
        }
      }
      // v2.1i 致死子代：独立 id 前缀 Lf<gen>#<seq>（与活节点编号隔离），
      // probability 保留原联合分布原始值（让用户能看到「本应 X% 但都死了」），
      // isLethal=true → 画布 ✕ + lethal 色 + 信息面板标「（纯合致死）」。
      if (lethal.isNotEmpty) {
        final lethalLabels = lethal.keys.toList()..sort();
        var lseq = _nodes
            .where((n) => n.isLethal && n.generation == gen)
            .length;
        for (final g in lethalLabels) {
          final node = PedigreeNode(
            id: 'Lf$gen#$lseq',
            kind: PedigreeNodeKind.group,
            genotype: g,
            generation: gen,
            probability: lethal[g]!,
            isExternal: false,
            maleFraction: trackSex ? 0.5 : null,
            familyId: fam,
            isLethal: true,
          );
          lseq++;
          _nodes.add(node);
          created.add(node);
          for (final src in contributors) {
            _edges.add(PedigreeEdge(src, node.id, PedigreeEdgeKind.lineage));
          }
        }
      }
    }

    createNodes(
        familyId, to, res.ownDist, res.ownLethal, res.contributors);
    res.merged.forEach((mf, m) {
      final prev = _frontier[mf] ?? 0;
      _frontier[mf] = m.targetGen > prev ? m.targetGen : prev;
      createNodes(mf, m.targetGen, m.dist, m.lethal, m.contributors);
    });
    _frontier[familyId] = to;
    return created;
  }

  /// 确保全局最大世代达到 n（各家族齐头逐代扩展）。
  void ensureGeneration(int n) {
    var guard = 0;
    while (_maxGeneration < n && guard++ < safetyMaxGeneration + 2) {
      final before = _maxGeneration;
      expandNextGeneration();
      if (_maxGeneration == before) break; // 到顶/休眠，无法继续
    }
  }

  /// 删除第 [generation] 代及以后的全部世代（收缩 maxGeneration）。
  /// 丢弃该代起的计算产出 group 桶与相关边；保留下游外来样本
  /// （用户数据）——外来样本若落在被删世代，其世代号会超出新
  /// maxGeneration，直到再次扩展到该代才重新参与计算。
  void collapseGeneration(int generation) {
    if (generation < 0) {
      throw ArgumentError('generation 不能为负：$generation');
    }
    if (generation == 0) generation = 1; // P 代是根，不可删；0 等价于回到 P×P
    if (generation > _maxGeneration) return; // 该代尚未展开，无操作
    final removedIds = _nodes
        .where((n) => n.generation >= generation && !n.isExternal)
        .map((n) => n.id)
        .toSet();
    _nodes.removeWhere((n) => removedIds.contains(n.id));
    _edges.removeWhere(
        (e) => removedIds.contains(e.fromId) || removedIds.contains(e.toId));
    _shrinkFrontiers();
    _maxGeneration = _frontier.values.fold(0, (a, b) => a > b ? a : b);
  }

  /// 节点删除后同步家族前沿：回退到该家族剩余「非外部节点」的最大
  /// 世代（外部样本不撑前沿——删除上一代后外来样本保留在原世代，
  /// 等该家族重新推进到那里时自动入池，与旧版 collapse 语义一致）；
  /// 非外部节点被删空的家族移出前沿表（休眠，待跨家族边重燃）。
  void _shrinkFrontiers() {
    final surviving = <int>{
      for (final n in _nodes)
        if (!n.isExternal) n.familyId
    };
    _frontier.removeWhere((f, _) => !surviving.contains(f));
    for (final f in surviving) {
      final maxGenOfF = _nodes
          .where((n) => n.familyId == f && !n.isExternal)
          .map((n) => n.generation)
          .fold(0, (a, b) => a > b ? a : b);
      final cur = _frontier[f] ?? maxGenOfF;
      _frontier[f] = cur < maxGenOfF ? cur : maxGenOfF;
    }
  }

  /// 确保所有 mating 边的子代世代已展开：边的子代落在
  /// max(亲本世代)+1（回交边因此覆盖到较年轻亲本的下一代）。
  /// 多家族下按「驱动家族」推进：跨家族边由较年轻亲本所在家族
  /// （同代时编号较小者）推进时触发；受 20 代安全阀约束（超出截断）。
  void ensureOffspringCoverage() {
    var guard = 0;
    while (guard++ < safetyMaxGeneration + 2) {
      var needExpand = false;
      for (final e in _edges) {
        if (e.kind != PedigreeEdgeKind.mating) continue;
        final a = _find(e.fromId);
        final b = _find(e.toId);
        if (a == null || b == null) continue;
        final younger =
            a.generation > b.generation ? a.generation : b.generation;
        if (younger >= safetyMaxGeneration) continue; // 超出截断
        if ((_frontier[_driverFamily(a, b)] ?? 0) <= younger) {
          needExpand = true;
          break;
        }
      }
      if (!needExpand) break;
      final sig = _frontierSignature();
      try {
        expandNextGeneration();
      } on StateError {
        break; // 全部家族到顶
      }
      if (_frontierSignature() == sig) break; // 无可推进家族，防死循环
    }
  }

  /// 前沿表快照签名（推进检测用）。
  String _frontierSignature() {
    final ks = _frontier.keys.toList()..sort();
    return ks.map((k) => '$k:${_frontier[k]}').join(',');
  }

  /// 只推进目标家族到目标世代（不动其他家族）；休眠/到顶则止步，
  /// 样本照常落位（下次该家族推进到该代时自动入池）。
  void _advanceFamilyTo(int familyId, int generation) {
    var guard = 0;
    while ((_frontier[familyId] ?? 0) < generation &&
        guard++ < safetyMaxGeneration) {
      final before = _frontier[familyId] ?? 0;
      _expandFamily(familyId);
      if ((_frontier[familyId] ?? 0) == before) break;
    }
    _maxGeneration = _frontier.values.fold(0, (a, b) => a > b ? a : b);
  }

  /// 基因型形态校验（v2.1 多倍体）。
  /// - 严格模式（allowPolyploid=false，现状零改变）：每位点恰 2 个字母
  ///   （成对字母，含 `-` 缺失），奇数长度抛 ArgumentError；
  /// - 多倍体模式：每位点 1~5 个字母且**各位点等位数一致**
  ///   （'AaaBbb' 每对 3 份、'Aaaa' 4 份、'A' 单倍体 1 份）；
  /// - 非法抛带中文说明的 ArgumentError。
  static void _validateGenotypeShape(
      String genotype, {required bool allowPolyploid}) {
    if (!allowPolyploid) {
      if (genotype.isEmpty || genotype.length % 2 != 0) {
        throw ArgumentError('基因型无效：需成对字母，如 AaBb');
      }
      return;
    }
    final loci = _splitLoci(genotype);
    if (loci.isEmpty) {
      throw ArgumentError('基因型无效：不能为空');
    }
    final n = loci.first.length;
    if (n < 1 || n > 5) {
      throw ArgumentError('每位点等位数需在 1~5 之间（多倍体 1~5n），'
          '收到 $n 份：$genotype');
    }
    for (final l in loci) {
      if (l.length != n) {
        throw ArgumentError('各位点等位数需一致（期望每对 $n 份，'
            '收到 ${l.length} 份）：$genotype');
      }
    }
  }

  /// 把基因型字符串拆成位点块（v2.1 多倍体解析）。
  /// 规则：连续同字母（忽略大小写）为一个位点（'Aaa'、'Aa'、'aa'）；
  /// '-' 缺失等位归属于当前位点块（'B-'）；块间以「字母不同」分界
  /// （'AaB-C-' → ['Aa', 'B-', 'C-']）。2n 串的拆分结果即成对位点，
  /// 与 legacy 按位点位置解析一致。
  static List<String> _splitLoci(String genotype) {
    final loci = <String>[];
    String? curLetter; // 当前位点字母（大写）；'-' 不改变归属
    for (final c in genotype.split('')) {
      if (c == '-') {
        if (loci.isEmpty) {
          loci.add(c);
        } else {
          loci.last += c;
        }
        continue;
      }
      final u = c.toUpperCase();
      if (loci.isEmpty || u != curLetter) {
        loci.add(c);
        curLetter = u;
      } else {
        loci.last += c;
      }
    }
    return loci;
  }

  /// 位点字母序规范化（v2.1 致死比较 / 多倍体子代 key）：大写（显性）
  /// 在前、小写在后、缺失 '-' 恒排最后（'aA' → 'Aa'；'AA'/'Aa'/'aa'
  /// 保持可区分——单纯小写排序会混淆纯合与杂合）。
  static String _canonLocus(String locus) {
    final upper = <String>[];
    final lower = <String>[];
    final dash = <String>[];
    for (final c in locus.split('')) {
      if (c == '-') {
        dash.add(c);
      } else if (c == c.toUpperCase()) {
        upper.add(c);
      } else {
        lower.add(c);
      }
    }
    return [...upper, ...lower, ...dash].join();
  }

  /// 基因对数须与目标家族双亲一致（不一致的配对在杂交合并时会抛错，
  /// 且对中学生物场景无意义——位点集应当相同）。
  /// 开启「允许基因缺失交配」后不再限制（缺失按 '-' 补齐）。
  /// v2.1：进入比对前先做形态校验（严格 2n / 多倍体 1~5n）。
  void _checkPairCount(String genotype, int familyId) {
    _validateGenotypeShape(genotype, allowPolyploid: allowPolyploid);
    if (allowMissingGeneMating) return;
    int? refLen;
    for (final n in _nodes) {
      if (n.familyId == familyId && n.generation == 0) {
        refLen = n.genotype.length;
        break;
      }
    }
    if (refLen != null && genotype.length != refLen) {
      throw ArgumentError('基因对数需与该家族双亲一致（${refLen ~/ 2} 对）；'
          '收到 ${genotype.length ~/ 2} 对，请补齐位点（如把 aa 写成 aabbcc 形式）');
    }
  }

  /// 外来接入：向 [generation] 代添加个体并返回其 id。
  /// 若该代尚未展开，先 ensureGeneration(generation)。
  /// 添加后 **不自动重算已有后代世代**；下次 expandNextGeneration /
  /// recomputeFrom 才携带新样本。
  String addExternal({
    required int generation,
    required PedigreeNodeKind kind, // 只允许 male / female
    required String genotype,
    int familyId = 0, // 加入哪个家族的交配池（R14）
  }) {
    if (kind == PedigreeNodeKind.group) {
      throw ArgumentError('外来样本只允许 male / female；'
          '混合群体请用 addExternalGroup');
    }
    if (familyId < 0 || familyId >= _familyConstituents.length) {
      throw ArgumentError('家族不存在：$familyId');
    }
    _checkPairCount(genotype, familyId);
    _advanceFamilyTo(familyId, generation);
    final id = 'EXT#${++_extCounter}';
    _nodes.add(PedigreeNode(
      id: id,
      kind: kind,
      genotype: genotype,
      generation: generation,
      probability: 0.0,
      isExternal: true,
      familyId: familyId,
    ));
    return id;
  }

  /// 外来混合样本（R17）：向 [generation] 代添加一个「雌雄混合」群体桶。
  /// 渲染同计算产出的组合桶（大矩形内含雄□雌○，trackSex 下半边可独立
  /// 点选/连线）；作为外部数据 probability=0、入池权重按 1.0 计，
  /// 同时进入雌雄两个交配池。校验规则同 addExternal。
  String addExternalGroup({
    required int generation,
    required String genotype,
    int familyId = 0,
    double maleFraction = 0.5,
  }) {
    if (genotype.isEmpty) {
      throw ArgumentError('基因型无效：请输入成对字母，如 AaBb');
    }
    // v2.1：严格模式保持现状；多倍体模式放行 1~5n 形态（一致等位数）。
    _validateGenotypeShape(genotype, allowPolyploid: allowPolyploid);
    if (familyId < 0 || familyId >= _familyConstituents.length) {
      throw ArgumentError('家族不存在：$familyId');
    }
    _checkPairCount(genotype, familyId);
    _advanceFamilyTo(familyId, generation);
    final id = 'EXT#${++_extCounter}';
    _nodes.add(PedigreeNode(
      id: id,
      kind: PedigreeNodeKind.group,
      genotype: genotype,
      generation: generation,
      probability: 0.0,
      isExternal: true,
      maleFraction: maleFraction,
      familyId: familyId,
    ));
    return id;
  }

  /// 在两个节点间建立 mating 边。支持跨世代（回交：子代 × 亲代）。
  /// 校验：一雄一雌、非同一节点、边不重复；非法返回 false（原因见
  /// [connectBlockReason]）。
  bool connect(String aId, String bId) {
    if (connectBlockReason(aId, bId) != null) return false;
    // R32：记录建边时两端性别（group 桶记 null=整桶，由灯效兜底规则
    // 处理）；SPLIT 半边/单性别节点精确到 male/female。
    PedigreeNodeKind? sexOf(String id) {
      final k = _find(id)?.kind;
      return (k == null || k == PedigreeNodeKind.group) ? null : k;
    }

    _edges.add(PedigreeEdge(aId, bId, PedigreeEdgeKind.mating,
        fromSex: sexOf(aId), toSex: sexOf(bId)));
    return true;
  }

  /// 返回连线被拒绝的具体原因；可以连线时返回 null。
  String? connectBlockReason(String aId, String bId) {
    if (aId == bId) return '不能与自身连线';
    final a = _find(aId);
    final b = _find(bId);
    if (a == null || b == null) return '节点不存在';
    if (!_sexCompatible(a.kind, b.kind)) {
      return '性别不相容（需一雄一雌；同配生殖物种请开启「同性交配」开关）';
    }
    // 基因对数不一致的配对默认无法杂交合并（crossGametes 会抛错），
    // 连线时直接拦；开启「允许基因缺失交配」后放行（按位点字母对齐，
    // 缺失补 '-'）。
    if (!allowMissingGeneMating && a.genotype.length != b.genotype.length) {
      return '基因对数不一致（${a.genotype} 是 ${a.genotype.length ~/ 2} 对，'
          '${b.genotype} 是 ${b.genotype.length ~/ 2} 对），无法杂交；'
          '请把样本补齐到相同位点数，或开启「允许基因缺失交配」';
    }
    final dup = _edges.any((e) =>
        e.kind == PedigreeEdgeKind.mating &&
        ((e.fromId == aId && e.toId == bId) ||
            (e.fromId == bId && e.toId == aId)));
    if (dup) return '两个节点间已有连线';
    return null;
  }

  /// 摘下某节点最近建立的一条 mating 边（Among Us 拽线取消语义）：
  /// 找到则移除并返回该边（其另一端成为「锚点」，调用方进入携线状态）；
  /// 该节点没有 mating 边时返回 null。
  PedigreeEdge? detachLatestMating(String nodeId) {
    for (var i = _edges.length - 1; i >= 0; i--) {
      final e = _edges[i];
      if (e.kind == PedigreeEdgeKind.mating &&
          (e.fromId == nodeId || e.toId == nodeId)) {
        _edges.removeAt(i);
        return e;
      }
    }
    return null;
  }

  /// 某节点当前挂着的 mating 边数量。
  int matingCountOf(String nodeId) => _edges
      .where((e) =>
          e.kind == PedigreeEdgeKind.mating &&
          (e.fromId == nodeId || e.toId == nodeId))
      .length;

  /// v2.18 选择性收线：某节点挂着的全部 mating 边（新→旧，
  /// 供「多连线时挑一条收回」的选择器）。只读快照。
  List<PedigreeEdge> matingEdgesOf(String nodeId) => [
        for (var i = _edges.length - 1; i >= 0; i--)
          if (_edges[i].kind == PedigreeEdgeKind.mating &&
              (_edges[i].fromId == nodeId || _edges[i].toId == nodeId))
            _edges[i],
      ];

  /// v2.18 选择性收线：摘下 from × to 之间的那条 mating 边
  ///（无向匹配；多条重边摘最新一条）；摘到返回 true。
  bool detachMating(String fromId, String toId) {
    for (var i = _edges.length - 1; i >= 0; i--) {
      final e = _edges[i];
      if (e.kind == PedigreeEdgeKind.mating &&
          ((e.fromId == fromId && e.toId == toId) ||
              (e.fromId == toId && e.toId == fromId))) {
        _edges.removeAt(i);
        return true;
      }
    }
    return false;
  }

  /// 两个节点是否跨世代配对（回交）。UI 据此画双细线并提示。
  bool isBackcross(String aId, String bId) {
    final a = _find(aId);
    final b = _find(bId);
    if (a == null || b == null) return false;
    return a.generation != b.generation;
  }

  /// 编辑外来样本的基因型 / 性别；仅 isExternal 节点可编辑。
  /// 编辑后下游世代数据不再可靠，调用方应 recomputeFrom(node.generation)。
  bool editExternal(String id,
      {String? genotype, PedigreeNodeKind? kind}) {
    final node = _find(id);
    if (node == null || !node.isExternal) return false;
    // 性别不可跨类变更：混合桶(group)不可改成单性别，单性别也不可改成
    // group（会架空已分裂的半边）；改性别请删除后重新添加。
    if (kind != null &&
        (kind == PedigreeNodeKind.group ||
            node.kind == PedigreeNodeKind.group)) {
      return false;
    }
    final newGenotype = genotype ?? node.genotype;
    if (newGenotype.isEmpty) return false;
    // v2.1：严格模式保持现状（奇数位拒绝）；多倍体模式放行 1~5n 形态。
    try {
      _validateGenotypeShape(newGenotype, allowPolyploid: allowPolyploid);
    } on ArgumentError {
      return false;
    }
    // 基因对数不可变（改变对数会破坏池内一致性）；
    // 开启「允许基因缺失交配」后放宽（缺失按 '-' 补齐）。
    if (!allowMissingGeneMating &&
        newGenotype.length != node.genotype.length) {
      return false;
    }
    final idx = _nodes.indexWhere((n) => n.id == id);
    _nodes[idx] = PedigreeNode(
      id: node.id,
      kind: kind ?? node.kind,
      genotype: newGenotype,
      generation: node.generation,
      probability: node.probability,
      isExternal: true,
      maleFraction: node.maleFraction,
      familyId: node.familyId, // 保留家族归属（此前丢失会被重置为 0）
    );
    // 性别变化可能使既有 mating 边非法（同性），清理之
    _edges.removeWhere((e) =>
        e.kind == PedigreeEdgeKind.mating &&
        (e.fromId == id || e.toId == id) &&
        !_edgeSexCompatible(e));
    return true;
  }

  bool _edgeSexCompatible(PedigreeEdge e) {
    final a = _find(e.fromId);
    final b = _find(e.toId);
    if (a == null || b == null) return false;
    return _sexCompatible(a.kind, b.kind);
  }

  /// 从第 [generation] 代起重算其下游所有已展开世代。
  /// 丢弃第 n+1 代及以后的**计算产出节点**（group 桶）与相关边，
  /// 但**保留下游外来样本**（用户数据）及其相互间的 mating 边，
  /// 按当前第 n 代池（含外来）逐代重建到原 maxGeneration；
  /// 重建经过每一代时，该代保留的外来样本自动进入交配池。
  ///
  /// 端点含 group 的 mating 边（回交常挂在此类节点上）：重建前记录其
  /// (世代, 基因型)，每重建完一代即按基因型重映射回新 group id；
  /// 基因型在新一代分布中消失则丢弃该边。重映射在重建循环内逐代进行，
  /// 保证边在计算其子代世代之前已恢复（回交结果因此真正生效）。
  void recomputeFrom(int generation) {
    if (generation < 0) {
      throw ArgumentError('generation 不能为负：$generation');
    }
    if (generation >= _maxGeneration) return; // 无下游可重算
    // 各家族重建目标前沿（保持重建前后各家族世代深度一致）
    final targetF = Map<int, int>.of(_frontier);
    final removedIds = _nodes
        .where((n) => n.generation > generation && !n.isExternal)
        .map((n) => n.id)
        .toSet();

    // 1) 记录端点将被销毁的 mating 边（group id 是位置 id，重建后失效，
    //    按 (世代, 家族, 基因型) 重映射）。
    final pending = <_DoomedMating>[];
    for (final e in _edges) {
      if (e.kind != PedigreeEdgeKind.mating) continue;
      final aDoomed = removedIds.contains(e.fromId);
      final bDoomed = removedIds.contains(e.toId);
      if (!aDoomed && !bDoomed) continue;
      final a = _find(e.fromId)!;
      final b = _find(e.toId)!;
      // R32：性别标注沿用原边；旧边无标注时按端点节点性别补齐
      //（SPLIT 半边 kind 即 male/female，重映射后灯效仍精确）。
      PedigreeNodeKind? effSex(PedigreeNodeKind? annotated,
              PedigreeNodeKind nodeKind) =>
          annotated ??
          (nodeKind == PedigreeNodeKind.group ? null : nodeKind);
      pending.add(_DoomedMating(
        fromId: aDoomed ? null : a.id,
        fromGen: a.generation,
        fromGenotype: a.genotype,
        fromFamily: a.familyId,
        toId: bDoomed ? null : b.id,
        toGen: b.generation,
        toGenotype: b.genotype,
        toFamily: b.familyId,
        fromSex: effSex(e.fromSex, a.kind),
        toSex: effSex(e.toSex, b.kind),
      ));
    }

    _nodes.removeWhere((n) => removedIds.contains(n.id));
    _edges.removeWhere(
        (e) => removedIds.contains(e.fromId) || removedIds.contains(e.toId));
    // 前沿回退到各家族剩余节点的最大世代；节点删空的家族休眠
    // （合并家族若整体被删空，待跨家族边在重建中重燃再现）。
    _shrinkFrontiers();
    _maxGeneration = _frontier.values.fold(0, (a, b) => a > b ? a : b);

    // 2) 锁步重建：每轮所有未达标的家族各推进一代，每步后尝试重映射。
    //    锁步保证跨家族边双端在同轮内齐备——边在其触发窗口（驱动家族
    //    推进到较年轻亲本世代）之前已完成重挂，子代真正落进合并家族。
    //    合并家族重燃后进入下一轮继续追到旧目标。
    var guard = 0;
    while (guard++ < safetyMaxGeneration + 2) {
      final fams = <int>[
        for (final f in _frontier.keys)
          if ((_frontier[f] ?? 0) < (targetF[f] ?? 0)) f
      ]..sort();
      if (fams.isEmpty) break;
      for (final f in fams) {
        final before = _frontier[f] ?? 0;
        _expandFamily(f);
        _remapDoomedMatings(pending);
        if ((_frontier[f] ?? 0) == before) {
          targetF[f] = before; // 休眠家族无法推进：放弃追旧目标
        }
      }
    }
    _maxGeneration = _frontier.values.fold(0, (a, b) => a > b ? a : b);
  }

  /// 每推进一家族一代调用一次：把两端点都可解析的待恢复 mating 边
  /// 重挂回新 group id；端点世代已重建但基因型消失的边在此丢弃。
  /// 端点 readiness 按「其家族前沿是否已过该世代」判定（多家族下
  /// 各家族世代深度独立）。
  void _remapDoomedMatings(List<_DoomedMating> pending) {
    pending.removeWhere((d) {
      final fromReady =
          d.fromId != null || d.fromGen <= (_frontier[d.fromFamily] ?? -1);
      final toReady =
          d.toId != null || d.toGen <= (_frontier[d.toFamily] ?? -1);
      if (!fromReady || !toReady) return false; // 等对应家族重建到该代
      final from = d.fromId ??
          _findByGenotype(d.fromGen, d.fromGenotype, d.fromFamily)?.id;
      final to = d.toId ??
          _findByGenotype(d.toGen, d.toGenotype, d.toFamily)?.id;
      if (from == null || to == null) return true; // 基因型消失，丢弃
      final dup = _edges.any((e) =>
          e.kind == PedigreeEdgeKind.mating &&
          ((e.fromId == from && e.toId == to) ||
              (e.fromId == to && e.toId == from)));
      if (!dup) {
        _edges.add(PedigreeEdge(from, to, PedigreeEdgeKind.mating,
            fromSex: d.fromSex, toSex: d.toSex)); // R32：性别标注随边恢复
      }
      return true;
    });
  }

  /// 在某世代某家族中按基因型找计算产出节点（同代同家族基因型唯一）。
  PedigreeNode? _findByGenotype(int generation, String genotype, int familyId) {
    for (final n in _nodes) {
      if (!n.isExternal &&
          n.generation == generation &&
          n.familyId == familyId &&
          n.genotype == genotype) {
        return n;
      }
    }
    return null;
  }

  /// 删除外来样本及其相关边（group 节点与初始 P 代不可删，返回 false）。
  /// 目标是外来混合桶时，其性别半边（SPLIT 子节点，同为外来）一并删除。
  bool removeExternal(String id) {
    final node = _find(id);
    if (node == null || !node.isExternal) return false;
    final doomed = <String>{id};
    for (final e in _edges) {
      if (e.kind == PedigreeEdgeKind.lineage &&
          e.fromId == id &&
          e.toId.startsWith('SPLIT#')) {
        doomed.add(e.toId);
      }
    }
    _nodes.removeWhere((n) => doomed.contains(n.id));
    _edges.removeWhere(
        (e) => doomed.contains(e.fromId) || doomed.contains(e.toId));
    return true;
  }

  /// R19 单元素删除：删除任意节点（外来样本 / 计算产出桶 / 性别半边）
  /// 及其全部关联边，返回是否成功。初始双亲（P-father/P-mother）不可删。
  /// - 外来样本：真实删除，解除对应黑名单（用户可再手动添加同基因型）；
  /// - 计算桶（group，含半边的母桶）：删除桶 + 其 SPLIT 半边 + 所有边，
  ///   并把 (家族, 世代, 基因型) 记入黑名单——调用方 recomputeFrom 后
  ///   该基因型不再生成（「删除即生效，不留空」）；
  /// - 性别半边（SPLIT#*）：若母桶只剩这一个半边则整桶删除（同计算桶），
  ///   否则只删该半边及其边（另一半边保留）。
  bool removeElement(String id) {
    final n = _find(id);
    if (n == null) return false;
    if (n.id == 'P-father' || n.id == 'P-mother') return false;
    if (n.isExternal) {
      final key = _genKey(n.familyId, n.generation, n.genotype);
      if (!removeExternal(id)) return false;
      _removedGenotypes.remove(key);
      return true;
    }
    if (n.id.startsWith('SPLIT#')) {
      // 找母桶；母桶另一半半边还在则只删半边
      PedigreeNode? parent;
      for (final e in _edges) {
        if (e.kind == PedigreeEdgeKind.lineage && e.toId == n.id) {
          parent = _find(e.fromId);
          break;
        }
      }
      if (parent != null) {
        final siblingAlive = _nodes.any((x) =>
            x.id != n.id &&
            x.id.startsWith('SPLIT#') &&
            _edges.any((e) =>
                e.kind == PedigreeEdgeKind.lineage &&
                e.fromId == parent!.id &&
                e.toId == x.id));
        if (!siblingAlive) return _removeGeneratedBucket(parent);
      }
      _nodes.removeWhere((x) => x.id == n.id);
      _edges.removeWhere((e) => e.fromId == n.id || e.toId == n.id);
      return true;
    }
    return _removeGeneratedBucket(n);
  }

  /// R19 删除一个计算产出桶（含其 SPLIT 半边与所有关联边）并记黑名单。
  bool _removeGeneratedBucket(PedigreeNode n) {
    if (n.isExternal) return removeExternal(n.id);
    final doomed = <String>{n.id};
    for (final e in _edges) {
      if (e.kind == PedigreeEdgeKind.lineage &&
          e.fromId == n.id &&
          e.toId.startsWith('SPLIT#')) {
        doomed.add(e.toId);
      }
    }
    _nodes.removeWhere((x) => doomed.contains(x.id));
    _edges.removeWhere(
        (e) => doomed.contains(e.fromId) || doomed.contains(e.toId));
    _removedGenotypes.add(_genKey(n.familyId, n.generation, n.genotype));
    return true;
  }

  /// R19 按家族删代：删除 [familyId] 家族第 [generation] 代及以后的
  /// 全部计算产出与相关边（**外来样本保留在原位**，与 collapseGeneration
  /// 一致——待该家族重新推进到该代时自动入池）；前沿随之回退，后续
  /// recomputeFrom 只重建到新前沿，被删世代不再生。P 代（gen<1）禁删；
  /// 该家族未展开到该代返回 false。
  bool removeFamilyGeneration(int familyId, int generation) {
    if (generation < 1) return false;
    if ((_frontier[familyId] ?? 0) < generation) return false;
    final removedIds = _nodes
        .where((n) =>
            n.familyId == familyId &&
            n.generation >= generation &&
            !n.isExternal)
        .map((n) => n.id)
        .toSet();
    if (removedIds.isEmpty) return false;
    _nodes.removeWhere((n) => removedIds.contains(n.id));
    _edges.removeWhere(
        (e) => removedIds.contains(e.fromId) || removedIds.contains(e.toId));
    // 黑名单同步：被删代的基因型不再需要黑名单（前沿已回退）；
    // 但保留下方世代曾删除的条目不冲突。
    _removedGenotypes.removeWhere(
        (k) => k.startsWith('$familyId:') && _genKeyGenOf(k) >= generation);
    _shrinkFrontiers();
    _maxGeneration = _frontier.values.fold(0, (a, b) => a > b ? a : b);
    return true;
  }

  static int _genKeyGenOf(String key) {
    final parts = key.split(':');
    if (parts.length < 2) return 0;
    return int.tryParse(parts[1]) ?? 0;
  }

  /// 把一个 group 桶分裂成 X/Y 两个子节点（伴性遗传的性别拆分）。
  /// 原桶保留（概率不变），新增 male(X) 与 female(Y) 子节点，
  /// 概率各为原桶一半（1:1）。
  /// isExternal **继承母桶**：计算桶的半边是计算产出（重算可回收），
  /// 外来混合桶的半边同为外来用户数据（重算不回收、连线不丢）。
  /// 仅 trackSex 开启时有意义；非 group 或已分裂过则返回 null。
  List<PedigreeNode>? splitBucketBySex(String groupId) {
    final g = _find(groupId);
    if (g == null || g.kind != PedigreeNodeKind.group) return null;
    // 幂等：已分裂过则直接返回既有子节点
    final existing = _nodes
        .where((n) =>
            n.id.startsWith('SPLIT#') &&
            _edges.any((e) =>
                e.kind == PedigreeEdgeKind.lineage &&
                e.fromId == groupId &&
                e.toId == n.id))
        .toList();
    if (existing.isNotEmpty) return existing;

    final x = PedigreeNode(
      id: 'SPLIT#${++_splitCounter}',
      kind: PedigreeNodeKind.male,
      genotype: g.genotype,
      generation: g.generation,
      probability: g.probability * 0.5,
      isExternal: g.isExternal,
      maleFraction: 1.0,
      familyId: g.familyId,
    );
    final y = PedigreeNode(
      id: 'SPLIT#${++_splitCounter}',
      kind: PedigreeNodeKind.female,
      genotype: g.genotype,
      generation: g.generation,
      probability: g.probability * 0.5,
      isExternal: g.isExternal,
      maleFraction: 0.0,
      familyId: g.familyId,
    );
    _nodes.add(x);
    _nodes.add(y);
    _edges.add(PedigreeEdge(groupId, x.id, PedigreeEdgeKind.lineage));
    _edges.add(PedigreeEdge(groupId, y.id, PedigreeEdgeKind.lineage));
    return [x, y];
  }

  /// 桶的性别半边子节点查询（只读，不触发分裂）：
  /// 已分裂过则返回对应 kind（male/female）的 SPLIT 子节点，否则返回 null。
  PedigreeNode? halfNode(String groupId, PedigreeNodeKind sex) {
    for (final e in _edges) {
      if (e.kind != PedigreeEdgeKind.lineage || e.fromId != groupId) {
        continue;
      }
      final c = _find(e.toId);
      if (c != null && c.id.startsWith('SPLIT#') && c.kind == sex) {
        return c;
      }
    }
    return null;
  }

  /// R15 懒分裂：确保 [id] 已按性别分裂，返回对应性别半边节点的 id。
  /// - [id] 为 group 桶：未分裂则现场分裂（splitBucketBySex），返回对应半边；
  /// - [id] 本身已是半边（SPLIT 子节点）：kind 匹配则幂等返回自身。
  /// 组合桶渲染下，UI 点选「桶的雄/雌半边」得到合成 id，连线前调本方法
  /// 落成真实节点，边挂在半边上、概率各半桶一半。
  String ensureHalf(String id, PedigreeNodeKind sex) {
    if (sex == PedigreeNodeKind.group) {
      throw ArgumentError('半边性别须为 male 或 female');
    }
    final n = _find(id);
    if (n == null) throw ArgumentError('节点不存在：$id');
    if (n.kind != PedigreeNodeKind.group) {
      if (n.id.startsWith('SPLIT#')) {
        if (n.kind != sex) {
          throw ArgumentError(
              '该半边是${n.kind == PedigreeNodeKind.male ? '雄' : '雌'}性，'
              '与所选性别不符');
        }
        return n.id; // 已是目标半边：幂等
      }
      throw ArgumentError('只能对群体桶取性别半边');
    }
    final existing = halfNode(id, sex);
    if (existing != null) return existing.id;
    final children = splitBucketBySex(id);
    if (children == null) throw StateError('该桶无法分裂');
    return children.firstWhere((c) => c.kind == sex).id;
  }

  // ---------------------------------------------------------------------------
  // 内部实现
  // ---------------------------------------------------------------------------

  PedigreeNode? _find(String id) {
    for (final n in _nodes) {
      if (n.id == id) return n;
    }
    return null;
  }

  /// v2.1 编辑节点基因型：仅允许**外来样本**与 **P 代初始双亲**；
  /// 计算产出的子代（世代 ≥1 且非外部）与 SPLIT 半边只读。
  /// 新基因型须与所在家族位点数一致（同 addExternal 校验）。
  /// 返回 null = 成功；非 null = 拒绝原因。id 不存在的节点也返回原因。
  String? editGenotype(String id, String newGenotype) {
    final n = _find(id);
    if (n == null) return '节点不存在';
    if (n.id.startsWith('SPLIT#')) return '半边节点不可直接编辑，请编辑其父桶';
    if (!n.isExternal && n.generation != 0) {
      return '计算产出的子代不可直接修改；如需改变遗传构成，请修改其亲本或外来样本';
    }
    final g = newGenotype.trim(); // 保留大小写（Aa 显隐信息关键）
    if (g.isEmpty) return '基因型不能为空';
    try {
      _checkPairCount(g, n.familyId);
    } on ArgumentError catch (e) {
      return e.message?.toString() ?? '基因型非法（须成对字母，如 AaBb）';
    }
    final updated = PedigreeNode(
      id: n.id,
      kind: n.kind,
      genotype: g,
      generation: n.generation,
      probability: n.probability,
      isExternal: n.isExternal,
      maleFraction: n.maleFraction,
      familyId: n.familyId,
    );
    for (var i = 0; i < _nodes.length; i++) {
      if (_nodes[i].id == id) {
        _nodes[i] = updated;
        return null;
      }
    }
    return '节点不存在';
  }

  /// 性别相容：male↔female；group 可与任何性别连（含 group↔group）。
  /// allowSameSexMating 开启时 male×male / female×female 也合法
  /// （雌雄同体 / 同配生殖物种的普适性场景）。
  bool _sexCompatible(PedigreeNodeKind a, PedigreeNodeKind b) {
    if (a == PedigreeNodeKind.group || b == PedigreeNodeKind.group) return true;
    if (allowSameSexMating) return true;
    return a != b;
  }

  /// v2.19.10：只数不删——关闭同性交配前的二次确认用（数出将移除
  /// 几条边给用户看）。语义与 removeSameSexEdges 的移除判定严格一致。
  int countSameSexEdges() {
    var count = 0;
    for (final e in _edges) {
      if (e.kind != PedigreeEdgeKind.mating) continue;
      final a = _find(e.fromId);
      final b = _find(e.toId);
      if (a == null || b == null) continue;
      if (a.kind == PedigreeNodeKind.group || b.kind == PedigreeNodeKind.group) {
        continue;
      }
      if (a.kind == b.kind) count++;
    }
    return count;
  }

  /// R29：移除当前语义下非法的同性 mating 边（male×male / female×female，
  /// group 端不受限），返回移除数量。用户关闭「同性交配」后调用——
  /// 否则历史同性边仍留在图里，相连灯效会"亮错半边"（用户困惑
  /// 根因：A 圆×B 圆 的旧边让它以为绑定反了）。
  int removeSameSexEdges() {
    var removed = 0;
    _edges.removeWhere((e) {
      if (e.kind != PedigreeEdgeKind.mating) return false;
      final a = _find(e.fromId);
      final b = _find(e.toId);
      if (a == null || b == null) return false;
      if (a.kind == PedigreeNodeKind.group || b.kind == PedigreeNodeKind.group) {
        return false;
      }
      if (a.kind == b.kind) {
        removed++;
        return true;
      }
      return false;
    });
    return removed;
  }

  /// 节点入池权重：probability > 0 用概率；外来样本（probability=0）按 1.0 计。
  static double _poolWeight(PedigreeNode n) =>
      n.probability > 0 ? n.probability : 1.0;

  /// 旧单条件规范化（兼容）；列表版请用 [_lethalGens]。
  String? get _lethalNormalized =>
      _lethalGens.isEmpty ? null : _lethalGens.first;

  /// 一次交配的杂交入口（v2.1）：严格模式走 legacy `_math.cross`（零改变，
  /// 仅把奇数长度输入从 RangeError 裸崩升级为 ArgumentError 中文说明）；
  /// allowPolyploid=true 走多倍体路径（2n 输入委托 legacy 保证逐位一致）。
  Map<String, double> _crossPair(String g1, String g2) {
    if (!allowPolyploid) {
      _validateGenotypeShape(g1, allowPolyploid: false);
      _validateGenotypeShape(g2, allowPolyploid: false);
      return _math.cross(g1, g2, allowMissing: allowMissingGeneMating);
    }
    _validateGenotypeShape(g1, allowPolyploid: true);
    _validateGenotypeShape(g2, allowPolyploid: true);
    return _crossPolyploid(g1, g2);
  }

  /// v2.1 多倍体杂交（allowPolyploid=true 时替代 legacy cross）。
  ///
  /// 教学简化模型：
  ///  - 每对位点 n 份等位（n = 1~5，串内各位点等位数一致）；
  ///  - 配子：每对位点从 n 份等位中取 1 个（n 份等位 → n 种配子等位，
  ///    概率 = 该等位份数 / n）；
  ///  - 子代倍性保持亲代倍性：每位点 = 父方取中等位 ⌈n/2⌉ 份 + 母方
  ///    ⌊n/2⌋ 份（n=2 时 1+1，与 legacy 逐位一致；n 为奇时父方多一份，
  ///    确定性、可复现的教学简化）；
  ///  - 双方倍性/位点数不一致 → 带中文说明的 ArgumentError；
  ///  - 多倍体（n≠2）+「允许基因缺失交配」暂不组合（2n 输入直接委托
  ///    legacy，保留既有 R18 语义）。
  Map<String, double> _crossPolyploid(String g1, String g2) {
    final l1 = _splitLoci(g1);
    final l2 = _splitLoci(g2);
    final n1 = l1.first.length;
    final n2 = l2.first.length;
    if (n1 != n2) {
      throw ArgumentError('双方倍性不一致（${n1}n × ${n2}n），'
          '多倍体杂交需同倍性（如 3n × 3n）');
    }
    if (l1.length != l2.length) {
      throw ArgumentError('基因对数不一致（${l1.length} 对 × ${l2.length} 对），'
          '无法杂交合并');
    }
    if (n1 == 2) {
      // 2n 全兼容：委托 legacy（结果逐位一致，且保留 allowMissing 语义）
      return _math.cross(g1, g2, allowMissing: allowMissingGeneMating);
    }
    if (allowMissingGeneMating) {
      throw ArgumentError('多倍体模式（${n1}n）暂不支持「允许基因缺失交配」；'
          '请关闭该开关（2n 可与此开关组合）');
    }
    final fGametes = _polyGametes(l1);
    final mGametes = _polyGametes(l2);
    final fatherCopies = (n1 + 1) ~/ 2; // ⌈n/2⌉
    final motherCopies = n1 - fatherCopies; // ⌊n/2⌋
    final dist = <String, double>{};
    for (final f in fGametes) {
      for (final m in mGametes) {
        final sb = StringBuffer();
        for (var i = 0; i < l1.length; i++) {
          sb.write(_canonLocus(
              f.alleles[i] * fatherCopies + m.alleles[i] * motherCopies));
        }
        final key = sb.toString();
        dist[key] = (dist[key] ?? 0) + f.probability * m.probability;
      }
    }
    return dist;
  }

  /// v2.1 多倍体配子枚举：每对位点从 n 份等位中取 1 个，
  /// 概率 = 该等位在该位点的份数 / n。返回 [(各位点取中等位, 概率)]。
  static List<({List<String> alleles, double probability})> _polyGametes(
      List<String> loci) {
    final out = <({List<String> alleles, double probability})>[];
    void rec(int idx, List<String> picked, double prob) {
      if (idx == loci.length) {
        out.add((alleles: List.of(picked), probability: prob));
        return;
      }
      final locus = loci[idx];
      final freq = <String, int>{};
      for (final al in locus.split('')) {
        freq[al] = (freq[al] ?? 0) + 1;
      }
      freq.forEach((al, times) {
        picked.add(al);
        rec(idx + 1, picked, prob * times / locus.length);
        picked.removeLast();
      });
    }

    rec(0, <String>[], 1.0);
    return out;
  }

  /// v2.1 全部节点（含外来样本，不去重、不按概率加权——教学口径按
  /// 节点=个体计数）的多位点等位/基因型频率统计。
  ///
  /// 对每对位点：
  ///  - p = 显性等位份数 / 总份数，q = 1 - p；
  ///  - 基因型按节点分类：全显性=AA、全隐性=aa、其余（含 n>2 混合位点
  ///    与 'aA' 正反序）= Aa；
  ///  - 缺失等位 '-' 不计入等位统计；某节点某位点全为 '-' 时该节点
  ///    跳过该位点（跳位）。
  /// 返回按位点字母序（A、B、C…）排列。
  List<LocusFreq> locusFrequencies() {
    final acc = <String, _LocusFreqAcc>{};
    for (final n in _nodes) {
      for (final locus in _splitLoci(n.genotype)) {
        if (locus.replaceAll('-', '').isEmpty) continue; // 全缺失位点跳位
        final letter =
            locus.replaceAll('-', '').split('').first.toUpperCase();
        final a = acc.putIfAbsent(letter, _LocusFreqAcc.new);
        a.nodes++;
        var hasUpper = false, hasLower = false;
        for (final c in locus.split('')) {
          if (c == '-') continue;
          if (c == c.toUpperCase()) {
            hasUpper = true;
            a.dom++;
          } else {
            hasLower = true;
            a.rec++;
          }
        }
        if (hasUpper && hasLower) {
          a.het++;
        } else if (hasUpper) {
          a.domHomo++;
        } else {
          a.recHomo++;
        }
      }
    }
    final letters = acc.keys.toList()..sort();
    return [
      for (final letter in letters) _LocusFreqAcc.toFreq(letter, acc[letter]!),
    ];
  }

  /// 计算某家族第 [from] 代 → 下一代：本家族子代分布 + 贡献者 +
  /// 本家族作为驱动方的跨家族边子代（进合并家族池）。
  ///
  /// 池杂交：本家族 male 池 × female 池，各池权重内部归一化后两两
  /// 相乘加权；同家族显式 mating 边按端点池内归一化权重定向并入；
  /// 跨家族边的子代进入「合并家族」独立池。各自统一归一化到和为 1。
  _FamilyNext _computeFamilyNext(int familyId, int from) {
    final members = _nodes
        .where((n) => n.generation == from && n.familyId == familyId)
        .toList();
    final malePool = members
        .where((n) =>
            n.kind == PedigreeNodeKind.male || n.kind == PedigreeNodeKind.group)
        .toList();
    final femalePool = members
        .where((n) =>
            n.kind == PedigreeNodeKind.female ||
            n.kind == PedigreeNodeKind.group)
        .toList();

    final maleSum = malePool.fold(0.0, (s, n) => s + _poolWeight(n));
    final femaleSum = femalePool.fold(0.0, (s, n) => s + _poolWeight(n));

    final acc = <String, double>{};
    final accLethal = <String, double>{};
    final contributors = <String>{};
    final merged = <int, _MergedAcc>{};

    /// v2.1i：把一次杂交的子代拆成「存活」+「致死」两份，各自**内部归一到 1**。
    /// 这样多次 accumulate（pool mating + 显式 mating 边各贡献 1.0 / 0.5 权重）
    /// 累加后，_computeFamilyNext 末尾可独立归一：活子代展示"占活子的比例"
    ///（Aa:aa = 2:1），致死子代展示"占致死的比例"（AA 100% 致死）。
    /// 两者 UI 上独立呈现——活子代按活子分布归一，致死子代按致死分布归一。
    ({Map<String, double> alive, Map<String, double> lethal}) splitLethal(
        Map<String, double> raw) {
      final lethals = List.of(_lethalGens);
      if (lethals.isEmpty || raw.isEmpty) {
        return (alive: Map.of(raw), lethal: const {});
      }
      final alive = <String, double>{};
      final lethal = <String, double>{};
      raw.forEach((gen, p) {
        final loci = _splitLoci(gen).map(_canonLocus).toList();
        if (lethals.any((l) => loci.contains(l))) {
          lethal[gen] = (lethal[gen] ?? 0) + p;
        } else {
          alive[gen] = (alive[gen] ?? 0) + p;
        }
      });
      final tAlive = alive.values.fold(0.0, (a, b) => a + b);
      if (tAlive > 0) alive.updateAll((_, v) => v / tAlive);
      final tLethal = lethal.values.fold(0.0, (a, b) => a + b);
      if (tLethal > 0) lethal.updateAll((_, v) => v / tLethal);
      return (alive: alive, lethal: lethal);
    }

    void accumulate(
        Map<String, double> into, Map<String, double> intoLethal, String g1,
        String g2, double w) {
      if (w <= 0) return;
      final dist = _crossPair(g1, g2);
      // 全部淘汰则本次婚配不出子代（允许空代，不抛异常）
      final split = splitLethal(dist);
      if (split.alive.isEmpty && split.lethal.isEmpty) return;
      split.alive.forEach((gen, p) {
        into[gen] = (into[gen] ?? 0) + w * p;
      });
      split.lethal.forEach((gen, p) {
        intoLethal[gen] = (intoLethal[gen] ?? 0) + w * p;
      });
    }

    // 1) 池随机交配：本家族 male 池 × female 池。
    if (maleSum > 0 && femaleSum > 0) {
      for (final m in malePool) {
        final wm = _poolWeight(m) / maleSum;
        for (final f in femalePool) {
          final wf = _poolWeight(f) / femaleSum;
          accumulate(acc, accLethal, m.genotype, f.genotype, wm * wf);
          contributors.add(m.id);
          contributors.add(f.id);
        }
      }
    }

    // 2) 显式 mating 边：同家族并入本家族分布；跨家族进合并家族池。
    //    边在 from=较年轻亲本所在世代、且当前推进的是驱动家族时触发
    //    （驱动家族规则保证跨家族边只触发一次），子代落入
    //    max(亲本世代)+1。
    for (final e in _edges) {
      if (e.kind != PedigreeEdgeKind.mating) continue;
      final a = _find(e.fromId);
      final b = _find(e.toId);
      if (a == null || b == null) continue;
      final younger = a.generation > b.generation ? a.generation : b.generation;
      if (younger != from) continue;
      final sameFamily = a.familyId == b.familyId;
      if (sameFamily && a.familyId != familyId) continue;
      if (!sameFamily && _driverFamily(a, b) != familyId) continue;
      if (sameFamily) {
        final wa =
            _normalizedWeight(a, malePool, maleSum, femalePool, femaleSum);
        final wb =
            _normalizedWeight(b, malePool, maleSum, femalePool, femaleSum);
        accumulate(acc, accLethal, a.genotype, b.genotype, wa * wb);
        contributors.add(a.id);
        contributors.add(b.id);
      } else {
        final mf = _mergedFamilyId(a.familyId, b.familyId);
        final entry = merged.putIfAbsent(mf, () => _MergedAcc(from + 1));
        final wa = _weightInOwnFamilyPool(a);
        final wb = _weightInOwnFamilyPool(b);
        accumulate(entry.dist, entry.lethal, a.genotype, b.genotype, wa * wb);
        entry.contributors.add(a.id);
        entry.contributors.add(b.id);
      }
    }

    // R19：被删除的基因型不再生成（单元素删除 + 立即重算语义）
    acc.removeWhere(
        (gt, _) => _removedGenotypes.contains(_genKey(familyId, from + 1, gt)));
    accLethal.removeWhere((gt, _) =>
        _removedGenotypes.contains(_genKey(familyId, from + 1, gt)));
    for (final entry in merged.entries) {
      entry.value.dist.removeWhere((gt, _) =>
          _removedGenotypes.contains(_genKey(entry.key, from + 1, gt)));
      entry.value.lethal.removeWhere((gt, _) =>
          _removedGenotypes.contains(_genKey(entry.key, from + 1, gt)));
    }

    // v2.1i：活子代与致死子代**独立归一**——活展示"占活子分布"，致死展示"占
    // 致死分布"；多次 accumulate 累加后在末尾各自归一到 1.0。
    final tAlive = acc.values.fold(0.0, (x, y) => x + y);
    if (tAlive > 0) acc.updateAll((k, v) => v / tAlive);
    final tLethal = accLethal.values.fold(0.0, (x, y) => x + y);
    if (tLethal > 0) accLethal.updateAll((k, v) => v / tLethal);
    for (final m in merged.values) {
      final t = m.dist.values.fold(0.0, (x, y) => x + y);
      if (t > 0) m.dist.updateAll((k, v) => v / t);
      final tl = m.lethal.values.fold(0.0, (x, y) => x + y);
      if (tl > 0) m.lethal.updateAll((k, v) => v / tl);
    }
    return _FamilyNext(acc, accLethal, contributors, merged);
  }

  /// 跨家族边的「驱动家族」：较年轻亲本所在家族；同代时取编号较小者。
  /// 边只在驱动家族推进到较年轻亲本世代时触发一次（避免两个家族
  /// 齐头推进时各触发一次导致子代权重翻倍）。
  int _driverFamily(PedigreeNode a, PedigreeNode b) {
    if (a.generation > b.generation) return a.familyId;
    if (b.generation > a.generation) return b.familyId;
    return a.familyId < b.familyId ? a.familyId : b.familyId;
  }

  /// 合并家族编号（幂等）：成分 = 双方家族成分并集；同一对成分
  /// 永远拿到同一编号（重算后合并家族 id 稳定）。
  int _mergedFamilyId(int fa, int fb) {
    final constituents = <int>{
      ..._familyConstituents[fa],
      ..._familyConstituents[fb]
    };
    final key = (constituents.toList()..sort()).join('+');
    final existing = _mergedIndex[key];
    if (existing != null) return existing;
    final id = _familyConstituents.length;
    _familyConstituents.add(constituents);
    _mergedIndex[key] = id;
    return id;
  }

  /// 跨家族边端点权重：在其「自己家族、自己世代」的性别池内归一化；
  /// 池缺失（理论兜底，池至少含端点自身）时按 1.0 计。
  double _weightInOwnFamilyPool(PedigreeNode n) {
    final members = _nodes.where(
        (x) => x.generation == n.generation && x.familyId == n.familyId);
    final maleSum = members
        .where((x) =>
            x.kind == PedigreeNodeKind.male || x.kind == PedigreeNodeKind.group)
        .fold(0.0, (s, x) => s + _poolWeight(x));
    final femaleSum = members
        .where((x) =>
            x.kind == PedigreeNodeKind.female ||
            x.kind == PedigreeNodeKind.group)
        .fold(0.0, (s, x) => s + _poolWeight(x));
    switch (n.kind) {
      case PedigreeNodeKind.male:
        return maleSum > 0 ? _poolWeight(n) / maleSum : 1.0;
      case PedigreeNodeKind.female:
        return femaleSum > 0 ? _poolWeight(n) / femaleSum : 1.0;
      case PedigreeNodeKind.group:
        return maleSum > 0 ? _poolWeight(n) / maleSum : 1.0;
    }
  }

  /// 显式边端点的池内归一化权重（male→maleSum，female→femaleSum，
  /// group 按 male 池）。若对应池为空则权重为 0（该边不贡献）。
  double _normalizedWeight(
    PedigreeNode n,
    List<PedigreeNode> malePool,
    double maleSum,
    List<PedigreeNode> femalePool,
    double femaleSum,
  ) {
    switch (n.kind) {
      case PedigreeNodeKind.male:
        return maleSum > 0 ? _poolWeight(n) / maleSum : 0;
      case PedigreeNodeKind.female:
        return femaleSum > 0 ? _poolWeight(n) / femaleSum : 0;
      case PedigreeNodeKind.group:
        return maleSum > 0 ? _poolWeight(n) / maleSum : 0;
    }
  }
}

/// _computeFamilyNext 的返回：本家族子代分布 + 贡献者 + 跨家族合并结果。
class _FamilyNext {
  final Map<String, double> ownDist;
  final Map<String, double> ownLethal;
  final Set<String> contributors;
  final Map<int, _MergedAcc> merged; // 合并家族编号 → 累积器

  const _FamilyNext(
      this.ownDist, this.ownLethal, this.contributors, this.merged);
}

/// 跨家族边子代累积器：定向杂交分布 + 贡献者 + 子代目标世代。
class _MergedAcc {
  final int targetGen;
  final Map<String, double> dist = {};
  final Map<String, double> lethal = {};
  final Set<String> contributors = {};

  _MergedAcc(this.targetGen);
}

/// recomputeFrom 重建前记录的「端点将被销毁」的 mating 边。
/// 端点为 null 表示原端点是 group 节点，按 (世代, 家族, 基因型)
/// 重映射（多家族下同代同基因型可能多家并存，家族参与定位）。
class _DoomedMating {
  final String? fromId;
  final int fromGen;
  final String fromGenotype;
  final int fromFamily;
  final String? toId;
  final int toGen;
  final String toGenotype;
  final int toFamily;

  /// R32：原边的端点性别标注（建边时记录）。重映射降级回整桶后
  /// 仍保留，灯效据此亮正确的半边（同性交配场景关键）。
  final PedigreeNodeKind? fromSex;
  final PedigreeNodeKind? toSex;

  const _DoomedMating({
    required this.fromId,
    required this.fromGen,
    required this.fromGenotype,
    required this.fromFamily,
    required this.toId,
    required this.toGen,
    required this.toGenotype,
    required this.toFamily,
    this.fromSex,
    this.toSex,
  });
}

/// 伴性遗传配置：把 X/x/Y/y 位点标注为表型标签并着色。
/// 例：X=「病」表示 X 连锁隐性致病；x=「正常」；Y/y 同理（Y 连锁）。
/// 颜色语义：大 X=蓝、小 x=黄、大 Y=蓝、小 y=黄（由 UI 渲染）。
class SexLinkedConfig {
  final String? xLabel; // 大 X 的表型标注
  final String? xLowerLabel; // 小 x 的表型标注
  final String? yLabel; // 大 Y 的表型标注
  final String? yLowerLabel; // 小 y 的表型标注

  const SexLinkedConfig({
    this.xLabel,
    this.xLowerLabel,
    this.yLabel,
    this.yLowerLabel,
  });

  bool get isEmpty =>
      xLabel == null && xLowerLabel == null && yLabel == null && yLowerLabel == null;

  /// 给一个基因型字符串生成分段标注（含概率由调用方附）。
  /// 返回 [(文本, 是否伴性位点, 是否大写)]，UI 据此着色。
  List<SexLinkedSegment> annotate(String genotype) {
    final out = <SexLinkedSegment>[];
    final chars = genotype.split('');
    for (var i = 0; i < chars.length; i += 2) {
      final a = chars[i];
      final b = i + 1 < chars.length ? chars[i + 1] : '';
      for (final al in [a, b]) {
        if (al.isEmpty) continue;
        final upper = al == al.toUpperCase();
        String? label;
        switch (al) {
          case 'X':
            label = xLabel;
            break;
          case 'x':
            label = xLowerLabel;
            break;
          case 'Y':
            label = yLabel;
            break;
          case 'y':
            label = yLowerLabel;
            break;
        }
        out.add(SexLinkedSegment(al, label != null, upper, label));
      }
    }
    return out;
  }
}

/// 伴性标注的一段等位基因：文本 + 是否伴性位点 + 是否大写 + 表型标签。
class SexLinkedSegment {
  final String allele;
  final bool isSexLinked;
  final bool isUpper;
  final String? label;

  const SexLinkedSegment(this.allele, this.isSexLinked, this.isUpper, this.label);
}

/// locusFrequencies 的位点累积器（v2.1，内部数据载体，教学口径按节点计数）。
class _LocusFreqAcc {
  int nodes = 0; // 计入该位点的节点数
  int dom = 0; // 显性等位份数（含 n>1 位点每份都计）
  int rec = 0; // 隐性等位份数
  int domHomo = 0; // 位点全显性的节点数（AA）
  int het = 0; // 位点显隐混合的节点数（Aa，含正反序与 n>2 混合）
  int recHomo = 0; // 位点全隐性的节点数（aa）

  static LocusFreq toFreq(String letter, _LocusFreqAcc a) {
    final total = a.dom + a.rec;
    final p = total > 0 ? a.dom / total : 0.0;
    return LocusFreq(
      locus: '$letter/${letter.toLowerCase()}',
      p: p,
      q: 1 - p,
      fAA: a.nodes > 0 ? a.domHomo / a.nodes : 0.0,
      fAa: a.nodes > 0 ? a.het / a.nodes : 0.0,
      faa: a.nodes > 0 ? a.recHomo / a.nodes : 0.0,
    );
  }
}