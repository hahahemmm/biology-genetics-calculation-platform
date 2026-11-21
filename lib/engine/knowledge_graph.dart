// knowledge_graph.dart —— 知识图谱结构（纯 Dart）
//
//
// 定义 KnowledgeNode（知识点）与 KnowledgeEdge（先修/关联关系），
// 并预置一份基础知识点图谱（不小于 15 个节点，含描述与里程碑题目编号）。
//
// 图谱用于：课程导航、按知识点的练习推荐、先修链路提示等。

/// 知识点（Knowledge Point）。
class KnowledgeNode {
  final String id; // 稳定 ID，如 'law-of-segregation'
  final String title; // 标题，如「分离定律」
  final String description; // 描述
  final List<String> milestoneExercises; // 里程碑题目编号
  final List<String> tags; // 标签，如 ['孟德尔', '豌豆']

  const KnowledgeNode({
    required this.id,
    required this.title,
    required this.description,
    this.milestoneExercises = const [],
    this.tags = const [],
  });
}

/// 知识点间的边关系。
class KnowledgeEdge {
  final String from; // 前序知识点 id
  final String to; // 后序知识点 id
  final String kind; // 'prerequisite'(先修) / 'related'(关联)

  const KnowledgeEdge({
    required this.from,
    required this.to,
    this.kind = 'related',
  });
}

/// 知识图谱容器：存放节点集合与边集合，并提供查询方法。
class KnowledgeGraph {
  final List<KnowledgeNode> nodes;
  final List<KnowledgeEdge> edges;

  const KnowledgeGraph({required this.nodes, required this.edges});

  /// 按 id 取节点。
  KnowledgeNode? nodeById(String id) {
    for (final n in nodes) {
      if (n.id == id) return n;
    }
    return null;
  }

  /// 取某节点的所有后继（to == id）。
  List<KnowledgeNode> successorsOf(String id) {
    final out = <KnowledgeNode>[];
    for (final e in edges) {
      if (e.from == id) {
        final n = nodeById(e.to);
        if (n != null) out.add(n);
      }
    }
    return out;
  }

  /// 取某节点的所有先修（from 指向它且 kind == prerequisite）。
  List<KnowledgeNode> prerequisitesOf(String id) {
    final out = <KnowledgeNode>[];
    for (final e in edges) {
      if (e.to == id && e.kind == 'prerequisite') {
        final n = nodeById(e.from);
        if (n != null) out.add(n);
      }
    }
    return out;
  }

  int get nodeCount => nodes.length;
  int get edgeCount => edges.length;
}

/// 预置的基础遗传知识图谱（>= 15 个节点）。
const KnowledgeGraph defaultKnowledgeGraph = KnowledgeGraph(
  nodes: [
    KnowledgeNode(
      id: 'dna-genes-alleles',
      title: 'DNA、基因与等位基因',
      description: '基因是 DNA 片段，位于染色体上；一对同源染色体相同位置控制同一性状的基因为等位基因（如 A/a）。',
      milestoneExercises: ['E01'],
      tags: ['遗传物质'],
    ),
    KnowledgeNode(
      id: 'genotype-phenotype',
      title: '基因型与表型',
      description: '基因型是基因组成（如 AA、Aa、aa），表型是可观察性状（如显性/隐性）。相同基因型不一定相同表型，表型还受环境影响。',
      milestoneExercises: ['E02'],
      tags: ['基础概念'],
    ),
    KnowledgeNode(
      id: 'dominant-recessive',
      title: '显性与隐性',
      description: '显性基因（如 A）在杂合时即表现；隐性基因（如 a）需纯合（aa）才表现。',
      milestoneExercises: ['E03'],
      tags: ['基础概念'],
    ),
    KnowledgeNode(
      id: 'law-of-segregation',
      title: '分离定律（孟德尔第一定律）',
      description: '成对等位基因在形成配子时彼此分离，分别进入不同配子。如 Aa 产生 A、a 两种配子。',
      milestoneExercises: ['E04'],
      tags: ['孟德尔', '豌豆'],
    ),
    KnowledgeNode(
      id: 'law-of-independent-assortment',
      title: '自由组合定律（孟德尔第二定律）',
      description: '位于非同源染色体上的非等位基因在形成配子时自由组合。',
      milestoneExercises: ['E05', 'E10'],
      tags: ['孟德尔', '豌豆'],
    ),
    KnowledgeNode(
      id: 'punnett-square',
      title: '棋盘法（Punnett 方阵）',
      description: '将双亲配子分别列行与列，交叉成子代基因型，用于推算比例。',
      milestoneExercises: ['E04', 'E05'],
      tags: ['解题方法'],
    ),
    KnowledgeNode(
      id: 'gamete-formation',
      title: '配子形成与类型',
      description: '1 对基因产 2 种配子；2 对基因（独立分配）产 4 种配子（AB、Ab、aB、ab）。',
      milestoneExercises: ['E05'],
      tags: ['配子'],
    ),
    KnowledgeNode(
      id: 'testcross',
      title: '测交（testcross）',
      description: '与隐性纯合子杂交，据后代比例反推未知个体基因型。若 F1 为 Aa，测交后代为 1:1。',
      milestoneExercises: ['E06'],
      tags: ['杂交方式'],
    ),
    KnowledgeNode(
      id: 'backcross',
      title: '回交（backcross）',
      description: 'F1 与亲本之一（常为隐性亲本）杂交，用于检测 F1 基因型与亲本关系。',
      milestoneExercises: ['E12'],
      tags: ['杂交方式'],
    ),
    KnowledgeNode(
      id: '9331',
      title: '9331 及其变式',
      description: '双杂合自交（AaBb×AaBb）F2 表型为 9:3:3:1；不同显性/互作机制衍生 9:7、9:3:4、15:1、1:4:6:4:1 等变式。',
      milestoneExercises: ['E07', 'E13'],
      tags: ['9331', '比值'],
    ),
    KnowledgeNode(
      id: '9331-variant-97',
      title: '9331 变式：9:7',
      description: '双显性共同作用才表现某性状（互补），其余合并为 7，即 9:7（如紫花×白花的互补遗传）。',
      milestoneExercises: ['E08'],
      tags: ['9331', '互补'],
    ),
    KnowledgeNode(
      id: '9331-variant-934',
      title: '9331 变式：9:3:4',
      description: '一个基因抑制另一基因的表达（隐性上位），9:3:4。',
      milestoneExercises: ['E14'],
      tags: ['9331', '上位'],
    ),
    KnowledgeNode(
      id: '9331-variant-151',
      title: '9331 变式：15:1',
      description: '只要含任一显性基因即表现同一表型（叠加），15:1。',
      milestoneExercises: ['E15'],
      tags: ['9331', '叠加'],
    ),
    KnowledgeNode(
      id: '9331-variant-14641',
      title: '9331 变式：1:4:6:4:1（数量性状）',
      description: '按显性基因数目分档（0/1/2/3/4 个），组合数 1:4:6:4:1，如肤色、株高多基因控制。',
      milestoneExercises: ['E16'],
      tags: ['9331', '数量性状'],
    ),
    KnowledgeNode(
      id: 'lethal-gene',
      title: '致死基因',
      description: '某些基因型致死（如 AA 致死、aa 致死），导致存活后代比例改变（如 2:1）。',
      milestoneExercises: ['E17'],
      tags: ['致死'],
    ),
    KnowledgeNode(
      id: 'incomplete-dominance',
      title: '不完全显性',
      description: '杂合子表现中间表型（如红花×白花 → 粉花），Aa 自交表型比 1:2:1。',
      milestoneExercises: ['E18'],
      tags: ['修饰'],
    ),
    KnowledgeNode(
      id: 'codominance',
      title: '共显性',
      description: '杂合子同时表现双亲表型（如 AB 血型），Aa 自交表型比 1:2:1。',
      milestoneExercises: ['E19'],
      tags: ['修饰'],
    ),
    KnowledgeNode(
      id: 'sex-linked',
      title: '伴性遗传',
      description: '基因位于性染色体（X/Y）上，遗传与性别相关，如红绿色盲（伴 X 隐性）、抗维生素 D 佝偻病（伴 X 显性）。',
      milestoneExercises: ['E20'],
      tags: ['X 染色体', '伴性'],
    ),
    KnowledgeNode(
      id: 'pedigree-analysis',
      title: '系谱分析',
      description: '根据家族图谱推断遗传方式与后代患病概率（常显/常隐/伴X显/伴X隐）。',
      milestoneExercises: ['E21', 'E22'],
      tags: ['系谱'],
    ),
  ],
  edges: [
    // 先修链：概念 → 定律 → 方法 → 变式/修饰 → 系谱
    KnowledgeEdge(from: 'dna-genes-alleles', to: 'genotype-phenotype', kind: 'prerequisite'),
    KnowledgeEdge(from: 'genotype-phenotype', to: 'dominant-recessive', kind: 'prerequisite'),
    KnowledgeEdge(from: 'dominant-recessive', to: 'law-of-segregation', kind: 'prerequisite'),
    KnowledgeEdge(from: 'punnett-square', to: 'law-of-segregation', kind: 'related'),
    KnowledgeEdge(from: 'law-of-segregation', to: 'gamete-formation', kind: 'prerequisite'),
    KnowledgeEdge(from: 'gamete-formation', to: 'law-of-independent-assortment', kind: 'prerequisite'),
    KnowledgeEdge(from: 'law-of-independent-assortment', to: '9331', kind: 'prerequisite'),
    KnowledgeEdge(from: 'gamete-formation', to: 'testcross', kind: 'related'),
    KnowledgeEdge(from: '9331', to: '9331-variant-97', kind: 'related'),
    KnowledgeEdge(from: '9331', to: '9331-variant-934', kind: 'related'),
    KnowledgeEdge(from: '9331', to: '9331-variant-151', kind: 'related'),
    KnowledgeEdge(from: '9331', to: '9331-variant-14641', kind: 'related'),
    KnowledgeEdge(from: 'dominant-recessive', to: 'incomplete-dominance', kind: 'related'),
    KnowledgeEdge(from: 'dominant-recessive', to: 'codominance', kind: 'related'),
    KnowledgeEdge(from: '9331', to: 'lethal-gene', kind: 'related'),
    KnowledgeEdge(from: 'law-of-segregation', to: 'sex-linked', kind: 'prerequisite'),
    KnowledgeEdge(from: 'sex-linked', to: 'pedigree-analysis', kind: 'prerequisite'),
    KnowledgeEdge(from: 'law-of-independent-assortment', to: 'pedigree-analysis', kind: 'related'),
    KnowledgeEdge(from: 'backcross', to: 'testcross', kind: 'related'),
  ],
);

/// 节点易错点速查（v2.4 N8）：图谱节点详情展示。
/// 内容来自教研实证（平度九中遗传教研/烟台二中实施方案）的学生高频错误。
const Map<String, String> nodePitfalls = {
  'dna-genes-alleles': '基因 ≠ DNA 全链——基因是有遗传效应的片段；等位基因位于同源染色体同一位置',
  'genotype-phenotype': '表型 = 基因型 + 环境共同作用；相同基因型在不同环境可表现不同表型',
  'dominant-recessive': '显性 ≠ 常见、隐性 ≠ 有害；显隐是表型掩盖关系，不是优劣',
  'law-of-segregation': '3:1 是大样本统计比例，后代数少时可明显偏离；'
      '「每对相对性状都遵循分离定律」是自由组合的前提',
  'law-of-independent-assortment': '9:3:3:1 的前提：完全显隐 + 两对基因独立分配；'
      '变式（9:7 等）不是「做错了」，先看基因互作',
  'punnett-square': '概率乘加混淆：同一事件分步用乘法，互斥事件求并用加法；'
      '棋盘写完后勿把「份数」当「概率」直接相加',
  'gamete-formation': '配子种类 2ⁿ 的前提：n 对杂合基因且独立分配；'
      '纯合位点不贡献种类（AaBB 只产 2 种配子，不是 4 种）',
  'testcross': '测交的目的是检验 F1 产生的配子类型与比例，不是「验证隐性」',
  'backcross': '回交 ≠ 测交：回交是回任一亲本，测交特指与隐性纯合亲本杂交',
  '9331': '勿直接背 9:3:3:1——先数配子种类（4 种）再画棋盘；变式题先对照份数合并',
  '9331-variant-97': '互补作用：9 份之外全合并为同一表型（9:7），别漏算 3+3+1',
  '9331-variant-934': '隐性上位：一对隐性纯合掩盖另一对（9:3:4），注意掩盖方向',
  '9331-variant-151': '显性叠加：只要有一个显性基因即同一表型（15:1）',
  '9331-variant-14641': '数量性状按显性基因个数分档：C(4,k)=1:4:6:4:1',
  'lethal-gene': '致死题先从总份数里扣掉致死份数再约分；勿用 16 份直接约',
  'incomplete-dominance': '不完全显性 F2 是 1:2:1（中间型独立成类），不是 3:1',
  'codominance': '共显性（如 AB 型血）两种性状同时表现，≠ 不完全显性的中间型',
  'sex-linked': '伴 X 隐性「交叉遗传」≠ 伴 Y；患病概率与生男生女概率分开算',
  'pedigree-analysis': '系谱先判显隐（「无中生有」为隐性），再判基因位置（常/X）；'
      '勿见「男性多」就断伴性',
};

/// v2.19.63：节点「挂题关键词」小表（错题本 `subjectArea` 自由文本 → 图谱节点）。
///
/// 口径（写死在这里，以免将来被改松）：
///   - 逐节点给 **1-2 个显式关键词**，错题的 `subjectArea` 只要**包含**其中
///     一个子串，就算该节点挂 1 题。
///   - ⛔ **不做分词、不做模糊匹配**——`subjectArea` 是用户手打的自由文本，
///     唯一可靠的做法是人工给词；节点数有限（19 个），给词成本远低于任何
///     启发式切词，且结果可解释、可复现。
///   - 关键词取自节点标题 / 常见考点写法（如「分离定律」「测交」「9331」）。
///   - **已知取舍**：基础节点 `9331` 的关键词 `9331` 会被「9331 变式：9:7」
///     这类写法同时命中——这是**有意**的（基础规律① + 变式②本就都涉及），
///     本表只服务分层着色（≥3 红 / 1-2 琥珀），轻微重叠不影响分层结论。
///     同一节点内多关键词同时命中只记 1 次（[graphWeaknessCounts] 里 break）。
const Map<String, List<String>> graphNodeKeywords = {
  'dna-genes-alleles': ['DNA', '等位基因'],
  'genotype-phenotype': ['基因型', '表型'],
  'dominant-recessive': ['显隐性', '显性与隐性'],
  'law-of-segregation': ['分离定律'],
  'law-of-independent-assortment': ['自由组合'],
  'punnett-square': ['棋盘'],
  'gamete-formation': ['配子'],
  'testcross': ['测交'],
  'backcross': ['回交'],
  '9331': ['9331'],
  '9331-variant-97': ['9:7'],
  '9331-variant-934': ['9:3:4'],
  '9331-variant-151': ['15:1'],
  '9331-variant-14641': ['1:4:6:4:1'],
  'lethal-gene': ['致死'],
  'incomplete-dominance': ['不完全显性'],
  'codominance': ['共显性'],
  'sex-linked': ['伴性'],
  'pedigree-analysis': ['系谱'],
};

/// v2.19.63：按 `subjectArea` 文本计算**每个节点的挂题数**（错题本 → 图谱着色）。
///
/// 纯函数：输入一串 `subjectArea` 文本即可，不读任何全局状态 ⇒ 单元测试友好。
/// 生产环境传 `MistakeBook.instance.entries.map((e) => e.subjectArea)`。
///
/// 口径：
///   ① 输出**每个节点都出现**（零值也保留），便于着色层无分支读取；
///   ② 一条错题对同一节点最多记 1 次（多关键词同时命中不重复计）；
///   ③ 空字符串直接跳过。
Map<String, int> graphWeaknessCounts(
  Iterable<String> subjectAreas, {
  Map<String, List<String>> keywords = graphNodeKeywords,
}) {
  final counts = <String, int>{for (final id in keywords.keys) id: 0};
  for (final raw in subjectAreas) {
    if (raw.isEmpty) continue;
    for (final entry in keywords.entries) {
      for (final kw in entry.value) {
        if (kw.isNotEmpty && raw.contains(kw)) {
          counts[entry.key] = (counts[entry.key] ?? 0) + 1;
          break; // 同一节点的一条错题只记 1 次
        }
      }
    }
  }
  return counts;
}
