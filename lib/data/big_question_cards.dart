// big_question_cards.dart —— 大题套路卡内容库
//
// 素材源：依据学科通行表述与常见教辅口径整理。
// 口径说明：
// - 概念定义采用学科通行的标准表述；步骤/口诀含教辅通行口径（遗传平衡卡对
//   教师补充公式已逐条标注，其余卡同理视为「通行定义 + 教辅套路」）。
// - 引注只写章节名，不写页码。
// 一张卡 = 识别信号 + 套路步骤 + 易错提醒 + 一句话背诵 + 关联工具深链
// （linkModuleId 走 ModuleFillBus 直达目标页 tab 并带经典例题开算）。
//
// 修订清单：
// - P0 修复：15N 标记例题原写「占 1/8」——那是常见选择题的**干扰项**，
//   正确口径：含 15N 的 DNA 分子 = 2/8 = 1/4（1/8 是含 15N **单链**占比）。
// - 12:3:1（显性上位）补进 9331 变式步骤，术语对齐引擎 variant_spec
//   （互补作用 / 隐性上位 / 显性叠加 / 显性上位 / 积加作用）。
// - 遗传平衡 5 条件措辞按学科通行表述整理；系谱口诀补「女患者之子必病」。
// - 口诀病句修订 6 条（三/四/五/八/十一/十二号卡）。
// - 新增 2 卡：配子法与自由交配速算、由后代比例反推亲本（共 14 张）。

/// 一张大题套路卡。
class BigQuestionCard {
  const BigQuestionCard({
    required this.id,
    required this.title,
    required this.tag,
    required this.signals,
    required this.steps,
    required this.pitfalls,
    required this.takeaway,
    this.linkLabel,
    this.linkNavIndex,
    this.linkModuleId,
    this.linkParams,
  });

  /// 稳定 id（测试唯一性用）。
  final String id;

  /// 卡名（也是 TOC 与正文的标题）。
  final String title;

  /// 难度/考频标签：常考 / 易错 / 高频。
  final String tag;

  /// 识别信号：题干出现什么就该想这张卡。
  final List<String> signals;

  /// 套路步骤（有序，≥2 步）。
  final List<String> steps;

  /// 易错提醒。
  final List<String> pitfalls;

  /// 一句话背诵结论（口诀）。
  final String takeaway;

  /// 关联工具按钮文案（null = 无跳转）。
  final String? linkLabel;

  /// 关联工具的主导航索引（深链失败/未注册时的回退跳转）。
  final int? linkNavIndex;

  /// v2.19.25：ModuleFillBus 模块 id——直达目标页对应 tab 并带参开算。
  final String? linkModuleId;

  /// 随深链传递的参数（经典例题预填）。
  final Map<String, String>? linkParams;
}

/// 一章 = 顶部一个工作台 tab。
class BigQuestionChapter {
  const BigQuestionChapter({
    required this.title,
    required this.iconName,
    required this.cards,
  });

  final String title;

  /// Material 图标名（页面侧映射 IconData，数据层不引 UI）。
  final String iconName;
  final List<BigQuestionCard> cards;
}

/// 全套套路卡（6 章 14 张）。
const bigQuestionChapters = <BigQuestionChapter>[
  BigQuestionChapter(
    title: '分离定律',
    iconName: 'filter_1',
    cards: [
      BigQuestionCard(
        id: 'xyx-panduan',
        title: '显隐性判断三步',
        tag: '常考',
        signals: [
          '题目问「判断显隐性」或「哪个是显性性状」',
          '纯合亲本杂交，F1 只表现一种性状',
          '亲本正常（无某性状），后代突然出现新性状',
        ],
        steps: [
          '能杂交就杂交：纯合亲本杂交，F1 显现出来的性状 = 显性性状，未显现的 = 隐性性状。',
          '能自交就自交：后代出现性状分离（同时出现显性和隐性），分离出来的新性状 = 隐性。',
          '无中生有为隐性：双亲都没有某性状而后代出现 → 隐性；有中生无为显性：双亲都有而后代出现正常 → 显性。',
        ],
        pitfalls: [
          '判断前先确认亲本是否纯合——杂合亲本杂交的结果不能直接下显隐结论。',
          '「性状分离」指杂种后代同时出现显性性状和隐性性状的现象，不是一个比例数字。',
        ],
        takeaway: '无中生有为隐性，有中生无为显性。',
        linkLabel: '去 9331 练比例',
        linkNavIndex: 2,
        linkModuleId: 'cross_mono',
        linkParams: {'p1': 'Aa', 'p2': 'Aa'},
      ),
      BigQuestionCard(
        id: 'fan-tui-qinben',
        title: '由后代比例反推亲本',
        tag: '高频',
        signals: [
          '给出子代表型比例，问「亲本基因型是什么」',
          '后代出现 3:1、1:1、9:3:3:1、1:1:1:1 等典型比',
        ],
        steps: [
          '分离比 3:1 → 亲本均为杂合子（Aa × Aa）；1:1 → 一方杂合一方隐性纯合（测交 Aa × aa）。',
          '9:3:3:1（或总和为 16 的变式）→ 两对基因双杂合自交 AaBb × AaBb；1:1:1:1 → AaBb × aabb（双测交）。',
          '后代全是显性 → 至少一方显性纯合（AA × __）；后代出现隐性个体 → 双亲必都含隐性基因。',
          '两对以上性状「先分对、后合并」——每对单独反推，最后组合，这是反推题唯一安全的顺序。',
        ],
        pitfalls: [
          '1:2:1（不完全显性）别错认成 3:1——先数表型到底有几种。',
          '变式比（9:7 等）先还原成 9331 棋盘，反推逻辑不变。',
        ],
        takeaway: '见 3:1 想 Aa×Aa，见 1:1 想测交，见 9:3:3:1 想双杂合。',
        linkLabel: '去 9331 实战反推',
        linkNavIndex: 2,
        linkModuleId: 'cross_dihybrid',
        linkParams: {'p1': 'AaBb', 'p2': 'aabb'},
      ),
    ],
  ),
  BigQuestionChapter(
    title: '自由组合',
    iconName: 'filter_2',
    cards: [
      BigQuestionCard(
        id: 'b9331-bianshi',
        title: '9331 变式拆分',
        tag: '高频',
        signals: [
          'F2 表型比不是 9:3:3:1，而是 9:7、15:1、9:6:1、12:3:1、9:3:4',
          '题目出现「基因互作」「两种基因控制同一性状」',
        ],
        steps: [
          '先看分母：所有变式加起来仍是 16 份 → 两对基因仍按自由组合处理，棋盘照画。',
          '对照 9331 逐格找「哪几格被合并成同一表型」。',
          '背五个典型：9:7 = 9:(3+3+1) 互补作用（只有双显 A_B_ 一类，其余 3+3+1 全合并）；15:1 = (9+3+3):1 显性叠加/重叠作用（有显性基因即表现）；9:6:1 = 9:(3+3):1 积加作用（单显合并）；12:3:1 = (9+3):3:1 显性上位（含 A 即归为一类）；9:3:4 = 9:3:(3+1) 隐性上位。',
          '落笔：变的是表型归类，基因型仍是 9 种——按基因型答题的部分不受影响。',
        ],
        pitfalls: [
          '变式只改表型比例，不改配子种类（1:1:1:1）和基因型比例。',
          '先验证总和 = 16 再套变式；总和不是 16 的多半有致死或连锁，别硬套。',
        ],
        takeaway: '变式 = 9331 的格子重新合并，先画棋盘再归类。',
        linkLabel: '去 9331 变式速查',
        linkNavIndex: 2,
        linkModuleId: 'cross_dihybrid',
        linkParams: {'p1': 'AaBb', 'p2': 'AaBb'},
      ),
      BigQuestionCard(
        id: 'peizi-ziyoujiaopei',
        title: '配子法与自由交配速算',
        tag: '高频',
        signals: [
          '题干出现「随机交配」「自由交配」「种群内个体相互交配」',
          '问的是子代基因型/表型频率，而不是某一次具体杂交',
        ],
        steps: [
          '先算配子频率：按每种基因型产生的配子比例拆开，再用群体里各基因型的频率加权平均（如群体全是 AaBb → AB:Ab:aB:ab = 1:1:1:1）。',
          '雌雄配子随机结合：子代某基因型频率 = 对应雌配子频率 × 雄配子频率（AA = p(A)²，Aa = 2·p(A)·p(a)）。',
          '与「逐代自交」严格区分：自由交配用配子频率展开；连续自交才让杂合子比例逐代减半（(1/2)ⁿ）。',
          '平衡时可直接套 p²/2pq/q²（见「遗传平衡判断」卡）；有选择/迁入等扰动时先修正配子频率再走配子法。',
        ],
        pitfalls: [
          '自由交配 ≠ 自交——先看清题干是「随机交配一代」还是「连续自交 n 代」。',
          '配子比两多两少说明连锁，先按互换率修正配子频率，再进配子法。',
        ],
        takeaway: '自由交配 = 配子频率先算好，雌雄随机结合各相乘。',
        linkLabel: '去 9331 自由交配 tab',
        linkNavIndex: 2,
        linkModuleId: 'cross_random_mating',
      ),
      BigQuestionCard(
        id: 'lian-suo-panduan',
        title: '连锁还是自由组合',
        tag: '易错',
        signals: [
          '两对基因测交/自交比例严重偏离 1:1:1:1 或 9:3:3:1',
          '后代只有亲本型，或出现「两多两少」四种',
        ],
        steps: [
          '自交看 F2：接近 9:3:3:1 → 自由组合；明显向亲本组合集中 → 连锁。',
          '测交看后代：四种且均等（1:1:1:1）→ 自由组合；只有两种亲本型 → 完全连锁；两多两少 → 不完全连锁（发生了互换）。',
          '不完全连锁：交换率 = 重组型个体数 ÷ 总数，两种亲本型配子各占 (1−交换率)/2。',
        ],
        pitfalls: [
          '「两多两少」里少的一对是重组型（互换产生），亲本型永远是多的。',
          '连锁判断的对象是两对（或以上）基因——一对基因谈不上连锁互换。',
        ],
        takeaway: '测交四种均等 = 自由组合；两多两少 = 互换重组。',
        linkLabel: '去 9331 连锁互换',
        linkNavIndex: 2,
        linkModuleId: 'cross_linkage',
        linkParams: {'p1': 'AB/ab', 'p2': 'ab/ab', 'r': '20%'},
      ),
    ],
  ),
  BigQuestionChapter(
    title: '伴性遗传',
    iconName: 'filter_3',
    cards: [
      BigQuestionCard(
        id: 'xipu-koujue',
        title: '系谱图判断口诀',
        tag: '高频',
        signals: [
          '给出家系图，问「遗传方式 / 最可能属于哪种遗传病」',
          '题干出现「代代相传」或「隔代遗传」',
        ],
        steps: [
          '先定显隐：无中生有为隐性（父母无病，孩子有病）；有中生无为显性（父母有病，孩子正常）。',
          '再定常/伴：隐性看女患者——女病父正（父亲正常）→ 常染色体隐性；显性看男患者——男病母正 → 常染色体显性。',
          '伴性排除口诀：伴 X 隐「女患者的父亲和儿子必病」（母病子必病）；伴 X 显「父病女必病、子病母必病」——找到反例就排除伴性。',
          '答题格式：遗传方式 + 关键个体基因型（不能定死的写「AA 或 Aa」）。',
        ],
        pitfalls: [
          '母系遗传（细胞质遗传）特征是患者子女全部患病且与父亲无关，先与常/伴染色体遗传区分。',
          '系谱图里个别个体两种基因型都可能时，不要硬定。',
        ],
        takeaway: '先显隐、后常伴；女患查父与子，男患查母与女。',
        linkLabel: '去系谱画布',
        linkNavIndex: 1,
      ),
      BigQuestionCard(
        id: 'banxing-buzhou',
        title: '伴性遗传大题步骤',
        tag: '常考',
        signals: [
          '题干出现红绿色盲、血友病、抗维生素 D 佝偻病',
          '概率要按性别分开问（儿子/女儿各多大概率）',
        ],
        steps: [
          '先写基因型全集：以色盲为例 XBXB 正常、XBXb 携带者、XbXb 患病、XBY 正常、XbY 患病。',
          '亲本定基因型 → 拆配子：男性的 X 染色体只给女儿、Y 染色体只给儿子。',
          '逐性别列棋盘：女儿一栏、儿子一栏分开算概率，别混在一张表里。',
          '答「患病男孩」时 = 生男孩概率 1/2 × 男孩中患病概率——两步都要写出来。',
        ],
        pitfalls: [
          '「患病男孩」≠「男孩患病」：前者必须先乘 1/2，后者不用。',
          '交叉遗传的实质：男患者的 X 来自母亲、只能传给女儿（患者中男性远多于女性是伴 X 隐的判据之一）。',
        ],
        takeaway: '男性 X 只给女儿、Y 只给儿子；问「患病男孩」先乘 1/2。',
        linkLabel: '去 9331 伴性实战',
        linkNavIndex: 2,
        linkModuleId: 'cross_sex_linked',
        linkParams: {'p1': 'XBXb', 'p2': 'XbY'},
      ),
    ],
  ),
  BigQuestionChapter(
    title: 'DNA 与表达',
    iconName: 'filter_4',
    cards: [
      BigQuestionCard(
        id: 'jianji-hubu',
        title: '碱基互补配对计算',
        tag: '常考',
        signals: [
          '给出一条链的碱基（个数或比例），求互补链或整个 DNA 分子',
          '出现「嘌呤 / 嘧啶占总碱基的比例」',
        ],
        steps: [
          '背死关系：A = T，G = C；整个双链分子中 A + G = T + C = 50%（嘌呤 = 嘧啶）。',
          '一条链的 (A+G)/(T+C) 与互补链互为倒数。',
          '(A+T)/(G+C) 在两条单链彼此相等，也等于整个分子的比值。',
          '知 A 占 b → C + G = 1 − 2b → G = C = (1−2b)/2；换成个数再乘总碱基数。',
        ],
        pitfalls: [
          '「DNA 区段」默认双链；单链题会明说「一条链」，别混。',
          '比例和个数别半途混用：先统一到比例、最后再乘总数。',
        ],
        takeaway: 'A=T、G=C 锁死；单链比值「倒互补、和相同」。',
        linkLabel: '去分子页练手',
        linkNavIndex: 5,
        linkModuleId: 'molecular',
        linkParams: {'tab': '0'},
      ),
      BigQuestionCard(
        id: 'biaoji-shidai',
        title: '同位素标记世代计算',
        tag: '易错',
        signals: [
          '15N（或 32P）标记后换 14N（31P）培养基培养',
          '问第 n 代「含标记的 DNA 占多少」「中带 : 轻带」',
        ],
        steps: [
          '半保留：复制 n 次共 2ⁿ 个 DNA 分子、2ⁿ⁺¹ 条单链。',
          '最初的模板链永远只有 2 条 → 含旧链（带标记）的 DNA 分子 = 2 个，占 2/2ⁿ = 1/2ⁿ⁻¹。',
          '密度带：含旧链 = 中带，全新 = 轻带 → 中带 : 轻带 = 2 : (2ⁿ − 2)。',
          '经典例题（选择题）：15N 双链标记换 14N 分裂 3 次 → 含 15N 的大肠杆菌占 1/4（正确答案 C）；选项 D「含 15N 的 DNA 分子占 1/8」是陷阱——含 15N 的 DNA 分子也是 2/8 = 1/4，1/8 是「含 15N 的单链占全部单链」（2/16）的口径。',
        ],
        pitfalls: [
          '「含标记的 DNA 分子」按分子数算（2/2ⁿ）、「含标记的链」按 2 条算（2/2ⁿ⁺¹）——这类题的 1/8 陷阱正是把两者混了。',
          '密度带只分中带/轻带（无重带）是因为半保留必留旧链，重带只有在没换代时才有。',
        ],
        takeaway: '分子 2ⁿ、旧链恒 2；带比 = 2 : (2ⁿ−2)。',
        linkLabel: '去分子页复制与标记',
        linkNavIndex: 5,
        linkModuleId: 'molecular',
        linkParams: {'tab': '1'},
      ),
      BigQuestionCard(
        id: 'fanyi-huansuan',
        title: '转录翻译换算',
        tag: '高频',
        signals: [
          '给出氨基酸个数，求 mRNA / DNA 碱基数（或反过来）',
          '给出 mRNA 碱基比例，求模板链 / 非模板链比例',
        ],
        steps: [
          '定比率：DNA（双链）: mRNA : 氨基酸 = 6 : 3 : 1——一个密码子 3 个碱基决定 1 个氨基酸。',
          '典型例题：500 个氨基酸 → mRNA 至少 1500 个碱基、DNA 至少 3000 个碱基。',
          '「至少」要带上：终止密码子不决定氨基酸，实际长度会更长（课本口径如此）。',
          '反推链比例：mRNA 的 U 对应模板链的 A；mRNA 的序列对应 DNA 另一链（T 换 U 即得）。',
        ],
        pitfalls: [
          'mRNA 与模板链互补、与非模板链一致（U ↔ T 替换），方向相反别搞混。',
          '64 个密码子中 61 个编码 21 种氨基酸（另 3 个终止密码子不编码）——别拿氨基酸数当密码子数。',
        ],
        takeaway: '6 : 3 : 1 一路比到底；「至少」两个字要带上。',
        linkLabel: '去分子页基因表达',
        linkNavIndex: 5,
        linkModuleId: 'molecular',
        linkParams: {'tab': '2'},
      ),
    ],
  ),
  BigQuestionChapter(
    title: '变异与育种',
    iconName: 'filter_5',
    cards: [
      BigQuestionCard(
        id: 'bianyi-sanfen',
        title: '可遗传变异三分法',
        tag: '常考',
        signals: [
          '给出实例判断变异类型（如镰状细胞贫血、无子西瓜、猫叫综合征）',
          '问「可遗传变异有哪几种，根本区别是什么」',
        ],
        steps: [
          '分子水平：DNA 碱基发生替换、增添或缺失 → 基因突变（可能产生新等位基因，是变异的根本来源）。',
          '个体水平有性生殖：控制不同性状的基因重新组合 → 基因重组（不产生新基因，只产生新基因型）。',
          '细胞水平：染色体数目（个别增减 / 成倍增减）或结构（缺失、重复、倒位、易位）改变 → 染色体变异。',
          '一眼分辨：显微镜下能看到的 = 染色体变异；看不到的再看是「基因内部变了」（突变）还是「基因组合变了」（重组）。',
        ],
        pitfalls: [
          '「基因重组不产生新基因」是选择题高频陷阱，后半句「只产生新基因型」要写全。',
          '单倍体 ≠ 只有一个染色体组：由配子直接发育而来的一律叫单倍体（如雄蜂 16 条；六倍体小麦的单倍体含 3 个组，有同源染色体但仍因组数不成对而不育）。',
        ],
        takeaway: '镜下可见 = 染色体变异；不可见 → 基因内部 = 突变，组合 = 重组。',
        linkLabel: '去倍性页',
        linkNavIndex: 7,
        linkModuleId: 'ploidy',
        linkParams: {'tab': '1'},
      ),
      BigQuestionCard(
        id: 'danbei-liucheng',
        title: '单倍体育种流程',
        tag: '高频',
        signals: [
          '育种大题要求「快速获得纯合新品种」',
          '比较杂交育种、单倍体育种、诱变育种、多倍体育种',
        ],
        steps: [
          '流程背全：杂合亲本 → 花药离体培养 → 单倍体幼苗 → 秋水仙素处理 → 纯合子 → 选择所需类型。',
          '为什么快：单倍体经秋水仙素加倍后 100% 纯合、直接稳定遗传——省掉杂交育种「选出后连续自交纯化」的多年功夫。',
          '对比记忆：杂交育种育纯合新品种需连续多年自交；诱变育种原理是基因突变、方向不定需大量筛选；多倍体育种果实大、营养物质高（三倍体无子西瓜走多倍体路线）。',
          '单倍体植株特点：染色体组不成对（无成对同源染色体）、联会紊乱，高度不育——所以必须再经秋水仙素加倍。',
        ],
        pitfalls: [
          '花药离体培养得到的是单倍体植株，不能直接作种子推广。',
          '答优点用通行表述：「明显缩短育种年限」。',
        ],
        takeaway: '花药离培 + 秋水仙素 = 纯合一步到位。',
        linkLabel: '去倍性页育种应用',
        linkNavIndex: 7,
        linkModuleId: 'ploidy',
        linkParams: {'tab': '2'},
      ),
    ],
  ),
  BigQuestionChapter(
    title: '进化',
    iconName: 'filter_6',
    cards: [
      BigQuestionCard(
        id: 'pinlv-susuan',
        title: '基因频率速算',
        tag: '常考',
        signals: [
          '给出 AA / Aa / aa 的个体数（或比例）',
          '问「A 基因占全部等位基因数的比率」',
        ],
        steps: [
          '数基因：总等位基因数 = 个体数 × 2；A 的个数 = 2×(AA 数) + Aa 数——杂合子一人算半个 A；a 的个数 = 2×(aa 数) + Aa 数。',
          '除：A 频率 = A 个数 ÷ 总等位基因数；a 频率同理。',
          '典型例题：100 个个体 AA=30、Aa=60、aa=10 → A = (2×30 + 60)/200 = 60%，a = 40%。',
          '校验：p + q 必须正好 = 100%（或 1），不等于就回去重数。',
        ],
        pitfalls: [
          '分母是等位基因总数（2N），不是个体数 N——最常见的错。',
          'X 染色体上的基因（如色盲基因频率）：男性只有一份 X，分母要按性别分开算。',
        ],
        takeaway: '纯合算 2、杂合算 1，加总再除以 2N。',
        linkLabel: '去进化页基因频率',
        linkNavIndex: 6,
        linkModuleId: 'evolution',
        linkParams: {'tab': '1'},
      ),
      BigQuestionCard(
        id: 'pingheng-panduan',
        title: '遗传平衡判断',
        tag: '易错',
        signals: [
          '问「该种群是否处于遗传平衡 / 基因频率是否改变」',
          '给基因频率，求下一代（或上一代）基因型频率',
        ],
        steps: [
          '先背课本常见的 5 个条件：①种群很大；②所有雌雄个体间都能自由交配并产生后代；③没有迁入和迁出；④不同表型的个体生存和繁殖的机会是均等的；⑤基因不产生突变。',
          '满足 5 条件 → 基因频率世代不变；基因型频率可按教师补充公式直接算：AA = p²、Aa = 2pq、aa = q²（p、q 为 A、a 的基因频率；课本正文以 5 条件 + 分离定律计算呈现，未给公式名）。',
          '判断题套路：任一条件被破坏（如「每年从外地引入个体」= 有迁入、「浅色个体易被捕食」= 有选择）→ 基因频率会改变。',
          '验算技巧：平衡时 √AA频率 = p、√aa频率 = q，且 Aa 应等于 2×√(AA×aa)——三个数对不上就不是平衡种群。',
        ],
        pitfalls: [
          'p² 开平方根才是基因频率——别把基因型频率当基因频率带进公式。',
          '平衡是种群统计规律：个体层面、某一代可以偏离，不代表种群不平衡。',
        ],
        takeaway: '5 条件定平衡；平衡时 AA=p²、Aa=2pq、aa=q²。',
        linkLabel: '去进化页遗传平衡',
        linkNavIndex: 6,
        linkModuleId: 'evolution',
        linkParams: {'p': '0.6', 'q': '0.4'},
      ),
    ],
  ),
];

/// v2.19.25：错题本「看套路卡」回链——考点自由文本 → 卡 id 关键词映射。
/// v2.19.26 三找茬代理交叉 P1 修订（学生 P1-1 / 老师 P1-3 / 老用户 ③）：
/// - 补 App 自产考点常量（各计算器「存入错题本」写入的 subjectArea
///   只有 分离定律/自由组合定律/伴性遗传/人类遗传病 四种，旧表漏 3/4，
///   主路径错题连不上卡）。
/// - 全角冒号/括号归一（「9：3：3：1」→ 半角才可命中）。
/// - 泛词降序/收紧：「标记基因」不再误命中同位素卡（裸「标记」删除，
///   改「同位素/15n/半保留」）；「碱基对替换」类先命中变异卡
///   （「基因突变」提前且变异卡条目先于碱基卡）。
/// 顺序即优先级（先 specific 后 general）。
const Map<String, List<String>> kCardTopicKeywords = {
  'xipu-koujue': ['系谱', '人类遗传病', '遗传图谱'],
  'banxing-buzhou': ['伴性', '色盲', '血友', '佝偻'],
  'lian-suo-panduan': ['连锁', '互换', '交换率'],
  'bianyi-sanfen': ['基因突变', '碱基对替换', '染色体变异', '可遗传变异'],
  'peizi-ziyoujiaopei': ['自由交配', '随机交配', '配子法', '配子种类'],
  'fan-tui-qinben': ['反推', '分离定律', '亲本基因型'],
  'b9331-bianshi': ['自由组合', '9331', '9:3', '基因互作', '变式', '双基因', '三对'],
  'pinlv-susuan': ['基因频率'],
  'pingheng-panduan': ['遗传平衡', '哈迪', '哈代'],
  'fanyi-huansuan': ['转录', '翻译', '密码子', '中心法则'],
  'danbei-liucheng': ['单倍体', '育种', '花药离体'],
  'jianji-hubu': ['碱基互补', '嘌呤', '嘧啶'],
  'biaoji-shidai': ['同位素', '15n', '半保留', '密度带'],
  'xyx-panduan': ['显隐'],
};

/// 按考点文本找最相关的一张卡（找不到返回 null）。
/// 归一：全角冒号/括号→半角 + 小写（覆盖「9：3：3：1」等手输风格）。
String? findCardIdForTopic(String topic) {
  final t = topic
      .replaceAll('：', ':')
      .replaceAll('（', '(')
      .replaceAll('）', ')')
      .toLowerCase();
  for (final entry in kCardTopicKeywords.entries) {
    for (final kw in entry.value) {
      if (t.contains(kw.toLowerCase())) return entry.key;
    }
  }
  return null;
}

/// 按卡 id 定位（章索引, 卡索引），供错题本回链与初始深链使用。
(int, int)? findCardIndexById(String id) {
  for (var c = 0; c < bigQuestionChapters.length; c++) {
    final cards = bigQuestionChapters[c].cards;
    for (var i = 0; i < cards.length; i++) {
      if (cards[i].id == id) return (c, i);
    }
  }
  return null;
}
