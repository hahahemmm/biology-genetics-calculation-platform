// curriculum_2020.dart —— 必修2《遗传与进化》课标内容要求结构化数据
//
// 依据：《普通高中生物学课程标准（2017年版2020年修订）》【内容要求】，
// 本文录入 3.1.1~4.2.5 共 22 条次位概念，顺序与 PLAN_2.0.md 表格一致。
// 原文经联网核对教育部 2020 修订版全文（PLAN_2.0 表中以「……」省略的
// 条目按其完整表述补全）。
// 纯数据层：不依赖任何页面 / 引擎 / Flutter。
//
// ⚠ 字符存储位置备忘（2026-08-28 验收反馈后建，2026-08-28 补 v2.1k 根因） ─
// 3.1.1 描述"概述多数生物的基因是DNA分子的功能片段，有些病毒的基因
// 在RNA分子上"——见下方 L58（code: '3.1.1' 的 text 字段，原备忘误写 L44）。
// 已知坑（按时间顺序）：
//   ① v2.1i 之前：实心底工具 chip 13 字换行挤压 ListTile.title，
//      导致该行 description 只渲染顶部 6 像素，AI/用户都看到"白字白底
//      不可见"（实际是被裁切）。
//   ② v2.1j 修复：工具 chip 强制 softWrap=false+maxLines:1+ellipsis，
//      description 显式 color=AppColors.ink + maxLines:2。
//   ③ v2.1k 真正根因：AppColors._dark 是全局静态字段，ListenableBuilder
//      只订阅 ThemeController.mode 变化，**不响应系统亮度变化**。当
//      Windows 系统从白天切到晚上，MediaQuery.platformBrightness 变
//      但 ThemeController 不 notify → ListenableBuilder 不 rebuild
//      → AppColors.sync 不被调 → _dark 残留浅色 → AppColors.ink
//      拿到 _inkD 暖米白 = 与 _surfaceL 暖近白几乎同色 = 白字白底。
//   ④ v2.1k 修复（双保险）：
//      主：lib/main.dart _BiologyAppState mixin WidgetsBindingObserver，
//        didChangePlatformBrightness 调 ThemeController.notifyListeners()
//        → ListenableBuilder rebuild → AppColors.sync 重新求值。
//      副：lib/pages/curriculum_page.dart _itemTile description 改用
//        Theme.of(context).colorScheme.onSurface —— 不依赖 _dark 全局
//        状态，只要 MaterialApp rebuild，scheme 重新计算。
// 3.1 关键概念标题"遗传信息主要编码在 DNA 分子上"——见
// lib/pages/curriculum_page.dart _keyConceptName('3.1')（switch L136）。
// 课标树渲染入口：lib/pages/curriculum_page.dart CurriculumPage.build。
// 测试覆盖：test/_v21j_curri_test.dart 断言 description 用
//        cs.onSurface + w500 + maxLines:2（不依赖 _dark 全局）。
// ───────────────────────────────────────────────────────────

/// v2.19.35：**一枚 chip 自己的**深链覆盖。
///
/// ⛔ **成对律与条目级同款**（守卫 `test/curriculum_coverage_gap_test.dart`）：
/// `params` 声明成**非空类型** ⇒ 「挂了 moduleId 却没参数」这种形态在**类型
/// 上就造不出来**。理由一字不改地抄条目级：**空参数深链比不深链更糟**
/// ——本仓每个已注册 target 的 `apply` 对空/缺参一律 `return false`
/// ⇒ 触发 `onApplyFailed` ⇒ 学生看到「目标页未消费本次参数」。
typedef CurriculumChipLink = ({String moduleId, Map<String, String> params});

/// 课标内容要求单条（次位概念）。
class CurriculumItem {
  const CurriculumItem({
    required this.code,
    required this.text,
    required this.bigIdea,
    required this.keyConcept,
    required this.heat,
    this.tool,
    this.linkModuleId,
    this.linkParams,
    this.chipLinks,
  });

  /// 次位概念编号，如 '3.2.3'。
  final String code;

  /// 内容要求的课标表述。
  final String text;

  /// 所属大概念：'概念3'（遗传信息控制生物性状，并代代相传）
  ///           / '概念4'（生物的多样性和适应性是进化的结果）。
  final String bigIdea;

  /// 所属重要概念编号，如 '3.2'（即 code 的前两段）。
  final String keyConcept;

  /// 高考核心常考热度 ★ 数（1..3，未标注为 0），取自 PLAN_2.0 标注。
  final int heat;

  /// 关联工具名（无工具为 null）。
  final String? tool;

  /// v2.19.35：点「工具：xxx →」chip 时的**深链目标**（`ModuleFillBus` 的
  /// moduleId），无深链为 null。消费侧 = `curriculum_page.dart` 的
  /// `resolveCurriculumLink` + `_openTool`。
  ///
  /// 为什么需要它：`_openTool` 的字符串匹配只能把学生送到**页**（导航索引
  /// 或 push 一份新实例），送不到**页内的页签**，更送不到**输入框里的示范题**。
  /// 9331 计算器有 7 个页签、变异页有 4 个：学生从「工具：连锁互换 + 9331 →」
  /// 点进去，落在的是**默认的第 0 个页签（双基因 9:3:3:1）**——和 chip 上写的
  /// 字**完全不是一回事**，屏上那道题也是另一道。
  ///
  /// ⛔ **成对律（守卫钉住）**：挂了 `linkModuleId` 就**必须**同时给非空
  /// `linkParams`。各 target 的 `apply` 对缺参一律 `return false`
  /// ⇒ 学生看到的是「参数没带过去——你现在看到的是默认题」的错误提示。
  /// **空参数深链比不深链更糟。**
  final String? linkModuleId;

  /// 深链要带的参数（示范题）。见 [linkModuleId] 的成对律说明。
  final Map<String, String>? linkParams;

  /// v2.19.35：**逐枚 chip** 的深链覆盖（**条目级**之上的第二层）。
  ///
  /// ## 病灶
  /// `_openTool` 读的是**条目级**的 [linkModuleId]，而 chip 文本是**分段级**
  /// 的（`tool` 里的 `/` 拆出多枚，见 `curriculum_page.dart` 的
  /// `resolveCurriculumLink`）。⇒ 挂上去的条目级深链会被该条目的
  /// **所有** chip 一起劫持。
  ///
  /// ## 形状约定（守卫钉住）
  ///  · `chipLinks![i]` ↔ [tool] 按 `/` 拆出的**第 i 段**（trim 后、剔空段）；
  ///  · 元素为 `null` = 那一枚**故意不带**深链（走 [linkModuleId] / 导航）；
  ///  · 缺项 / 越界 ⇒ 那一枚回落条目级（[linkModuleId] + [linkParams]）；
  ///  · `params` 为空或含空串 ⇒ **一律不采纳**（成对律在解析层再兜一道，
  ///    见 `resolveCurriculumLink`），不产生「无参数深链」这种形态。
  ///
  /// ## 本仓的可达性口径（与备份仓 B 不同，守卫按本仓写）
  /// v2.19.36 起 `_itemTile` 按 `/`（含全角 `／`）拆段**逐枚**渲染 chip
  /// （规则见 `curriculum_page.dart` 的 `curriculumToolSegments`），本条目
  /// 的 `遗传图谱/9331` 因此渲染成两枚 ⇒ `chipIndex` **0 与 1 都可达**。
  /// 第 0 段写 `null` = 那一枚**故意不带**深链（走 navIndex 1 原通路，
  /// ⛔ 不许挂），第 1 段（`cross_dihybrid` + 示范题）**已生效**。
  /// 22 条里其余 21 条无分隔符 ⇒ 仍渲染一枚整串 chip，文本逐字未变。
  ///
  /// ## 兼容性
  /// 旧数据（`chipLinks == null`）**一行不改**也能跑：全部回落条目级。
  /// 本字段只增不改，22 条里目前只有 3.2.3 写它。
  final List<CurriculumChipLink?>? chipLinks;
}

/// 必修2《遗传与进化》22 条内容要求（顺序与 PLAN_2.0 表格一致）。
const List<CurriculumItem> curriculum2020 = [
  CurriculumItem(
    code: '3.1.1',
    text: '概述多数生物的基因是DNA分子的功能片段，有些病毒的基因在RNA分子上',
    bigIdea: '概念3',
    keyConcept: '3.1',
    heat: 0,
    tool: '中心法则页·基因概念卡',
    // v2.19.35：以前点这枚 chip **什么都不发生**——`_openTool` 的分支
    // 一个都不含「中心法则页」，落进 `else`（navIndex/pushFactory 双 null）。
    // ⇒ 它是全仓唯一一条「死键」课标，本轮补上。
    //
    // 落点依据（本仓逐字读过）：分子页 tab 2「基因表达」里印着 FlatSection
    // 「中心法则互推（模板链→mRNA→反密码子）」（`molecular_page.dart:819`），
    // 那正是「基因是 DNA 的功能片段 / 有些在 RNA 上」这条正文要落到的
    // 互推工具。`molecular` 的 `apply`（`molecular_page.dart:173-186`）认
    // `{tab: 0..3}` ⇒ 只补数据，⛔ 不造机制。
    linkModuleId: 'molecular',
    linkParams: {'tab': '2'},
  ),
  CurriculumItem(
    code: '3.1.2',
    text: '概述DNA分子是由四种脱氧核苷酸构成，通常由两条碱基互补配对的反向平行长链形成双螺旋结构，碱基的排列顺序编码了遗传信息',
    bigIdea: '概念3',
    keyConcept: '3.1',
    heat: 1,
    tool: 'DNA计算器',
    // v2.19.35：正文讲「四种脱氧核苷酸 / 碱基的排列顺序」⇒ 分子页
    // tab 0「碱基组成」（`molecular_page.dart:422-427` 的 TabSpec 原文）。
    // 以前只切到分子页，落在**同一个** tab 0 ⇒ 本条是**零增益**的补齐，
    // 但它把「深链可达」这件事钉进数据（将来 chip 逐枚化后不必再动）。
    linkModuleId: 'molecular',
    linkParams: {'tab': '0'},
  ),
  CurriculumItem(
    code: '3.1.3',
    text: '概述DNA分子通过半保留方式进行复制',
    bigIdea: '概念3',
    keyConcept: '3.1',
    heat: 1,
    tool: 'DNA复制计算器',
    // v2.19.35：正文讲「半保留复制」⇒ 分子页 tab 1「复制与标记」
    // （`molecular_page.dart:428-433`）。以前落在 tab 0「碱基组成」——
    // 与 chip 上的字毫无关系。
    // ⚠️ 这个页签号**有牙齿**：分子页出厂停在 tab 0，所以「确实收到
    // {tab:'1'}」与「什么都没收到」在断言上可区分。
    linkModuleId: 'molecular',
    linkParams: {'tab': '1'},
  ),
  CurriculumItem(
    code: '3.1.4',
    text: '概述DNA分子上的遗传信息通过RNA指导蛋白质的合成，细胞分化的本质是基因选择性表达的结果，生物的性状主要通过蛋白质表现',
    bigIdea: '概念3',
    keyConcept: '3.1',
    heat: 1,
    tool: '转录翻译计算器',
    // v2.19.35：正文讲「RNA 指导蛋白质的合成 / 性状通过蛋白质表现」⇒
    // 分子页 tab 2「基因表达」（`molecular_page.dart:434-439`）。
    // 与 3.1.1 同一页签、同一 moduleId，是**两条独立依据**的结论。
    linkModuleId: 'molecular',
    linkParams: {'tab': '2'},
  ),
  CurriculumItem(
    code: '3.1.5',
    text: '概述某些基因中碱基序列不变但表型改变的表观遗传现象',
    bigIdea: '概念3',
    keyConcept: '3.1',
    heat: 0,
    tool: '课标体系页·概念卡',
    // ⛔ 本轮**明确不接**，且理由不是「忘了」：
    // 全仓没有任何表观遗传的**计算**模块——`grep 表观 lib/` 只命中两处
    // 纯文字（课标表述自身 + 知识库词条），
    // 分子页只算碱基/复制/表达/配子四种，变异页只算基因突变与染色体变异
    // ⇒ `linkModuleId` 只能指向一个**不存在**的目标。
    // 宁可不给——挂一个假目标是「点下去必然失败的重算按钮」。
  ),
  CurriculumItem(
    code: '3.2.1',
    text: '阐明减数分裂产生染色体数量减半的精细胞或卵细胞',
    bigIdea: '概念3',
    keyConcept: '3.2',
    heat: 1,
    tool: '减数分裂配子种类计算',
    // v2.19.35：以前落分子页的**第 0 个页签（碱基组成）**——屏上算的是
    // 碱基比例，和「配子种类」四个字毫无关系。`molecular` 早已注册并
    // 支持 `{tab: 0..3}` ⇒ 只补数据，⛔ 不造机制。
    // 落点：分子页 tab 3「配子种类」（`molecular_page.dart:440-445`）。
    linkModuleId: 'molecular',
    linkParams: {'tab': '3'},
  ),
  CurriculumItem(
    code: '3.2.2',
    text: '说明进行有性生殖的生物体，其遗传信息通过配子传递给子代',
    bigIdea: '概念3',
    keyConcept: '3.2',
    heat: 0,
    tool: '遗传图谱',
    // v2.19.35（覆盖缺口第 1 条）：`pedigree` 早已注册
    // （`genetic_pedigree_page.dart:315-325`，主导航 1 号页）。
    //
    // 零增益的旧理由是「系谱页没有页签」——那条只算了页签、没算**示范题**：
    // `pedigree` 的 apply（`_applyAiParams`，`genetic_pedigree_page.dart:334-342`）
    // 收到双亲后会**顺手 `_derive()`**，而只走导航索引落在的是**空画布**
    // （`_engine == null` ⇒ 那张空态图，`isPristine` 的另一半判据）。
    // 本条正文要的正是「**配子**传递给子代」，而 `_derive()` 之后画布上
    // 出现的就是亲本配子与子代 ⇒ 深链相对导航有增益。
    //
    // 参数 `Aa × Aa`：**出厂串**是 `AABBCC` / `aabbcc`
    // （`genetic_pedigree_page.dart:144-145` 的 `_kDefaultP1/_kDefaultP2`），
    // 逐字不同 ⇒ 断言「示范题已写入」有牙齿，不是恒真。
    // 选它的理由是本条正文的最小忠实样例：一个位点，双亲各给 A / a 两种配子，
    // 子代立刻出现 AA : Aa : aa ——「遗传信息经配子传递」一句话就能看完。
    // ⚠️ 多义的后果写在明处：3.2.3 的 `tool` 也写着「遗传图谱」⇒ 同一枚
    // moduleId 对两条课标 ⇒ `curriculumReverseCodeOf('pedigree')` 必须返
    // null ⇒ 系谱页那一侧**不挂**「课标 X」徽章、`Alt+K` 也**不认领**
    // （反向表 `curriculumReverseAnchors` 已按此裁定，本轮不动它）。
    linkModuleId: 'pedigree',
    linkParams: {'father': 'Aa', 'mother': 'Aa'},
  ),
  CurriculumItem(
    code: '3.2.3',
    text: '阐明有性生殖中基因的分离和自由组合使得子代的基因型和表型有多种可能，并可由此预测子代的遗传性状',
    bigIdea: '概念3',
    keyConcept: '3.2',
    heat: 2,
    tool: '遗传图谱/9331',
    // ⛔ 故意**不挂**条目级 `linkModuleId`：它会被这一条目的**所有** chip
    // 劫持（`_openTool` 读的是条目级），第一枚「遗传图谱」会被拽到 9331
    // 的某个页签上——那正是逐枚深链要修的病灶。
    // 逐枚覆盖按下标与 `/` 分段一一对齐，index 0 = `遗传图谱`（置 null =
    // 这一枚**故意不带**，走 navIndex 1 原通路，⛔ 不许挂）。
    //
    // index 1 = `9331`：本仓 9331 页第 0 个页签就是「双基因 9:3:3:1」
    // （`cross_calculator_page.dart` 的 Tab 原文「双基因 9331」），
    // 是「自由组合」的最简形式。参数取该页签的**出厂默认题**
    // （`cross_dihybrid` 的 `apply` 认 `{p1, p2}`）。
    // v2.19.36：`_itemTile` 逐枚渲染后这一枚**已生效**（守卫
    // `curriculum_forward_badge_test.dart` B1 双断言钉住「第 0 枚走导航
    // / 第 1 枚走深链」）。
    chipLinks: [
      null, // ① 遗传图谱：走 navIndex 1 原通路（⛔ 不许挂深链）
      (moduleId: 'cross_dihybrid', params: {'p1': 'AaBb', 'p2': 'AaBb'}),
    ],
  ),
  CurriculumItem(
    code: '3.2.4',
    text: '概述性染色体上的基因传递和性别相关联',
    bigIdea: '概念3',
    keyConcept: '3.2',
    heat: 2,
    tool: '伴性遗传',
    // v2.19.35：以前点这个 chip 落在**双基因**页签（9:3:3:1），
    // 和「伴性遗传」四个字毫无关系。
    // ⚠️ 示范题**必须与该页签的出厂值不同**：`sex_linked_tab.dart:59-60`
    // 的 `_kDefaultFemale/_kDefaultMale` 是 `XAXa` / `XAY`，若示范题与它
    // 逐字相同 ⇒「示范题已写入」那条断言**恒真**，守卫成了摆设。
    // 取 `XAXa × XaY`：父本为隐性个体，正是 3.2.4 最常考的伴 X 隐性模型，
    // 且与出厂值可区分 ⇒ 守卫这才有牙齿。apply 认 `{p1, p2}`
    // （`cross_calculator_page.dart:402-416`）。
    linkModuleId: 'cross_sex_linked',
    linkParams: {'p1': 'XAXa', 'p2': 'XaY'},
  ),
  CurriculumItem(
    code: '3.3.1',
    text: '概述碱基的替换、插入或缺失会引发基因中碱基序列的改变',
    bigIdea: '概念3',
    keyConcept: '3.3',
    heat: 2,
    tool: '变异页·基因突变模拟',
    // v2.19.35（覆盖缺口第 2 条）：本轮**新增** target `gene_mutation`
    // （`variation_page.dart` 的 initState 注册 / dispose 注销，与
    // `cross_*` 那些页内 target 同款）。变异页 tab 0「基因突变」一直装着
    // 真正的计算器（`_calcMut` → `mutateSequence`，算出突变后序列 +
    // 受影响密码子 + 同义/错义判定），只是**没注册**进 `ModuleFillBus`
    // ⇒ 工具在、引擎在、屏上有内容，课标页却跳不过去。
    //
    // 示范题三键都与该页签**出厂值**不同（出厂 = `ATGCCGTA` / 位置 `2` /
    // 类型「替换」，见 `variation_page.dart` 的 `_kDefaultMut*`）⇒ 守卫断言
    // 有牙齿（老教训：示范题与默认值逐字相同 ⇒ 那条断言恒真）：
    //  · 本条正文是「碱基的**替换、插入或缺失**」⇒ 取「插入」这一类
    //    （本页三个 ChoiceChip 的原文之一，`_typeToEngine` 的键）。
    //  · 落点 `ATGGCCAAT` 第 3 位插入 A ⇒ `ATGAGCCAAT`，受影响密码子
    //    `GGC → AGC`（第 2 个）⇒ 非同义 = 序列真的被改写了。
    linkModuleId: 'gene_mutation',
    linkParams: {'sequence': 'ATGGCCAAT', 'type': '插入', 'position': '3'},
  ),
  CurriculumItem(
    code: '3.3.2',
    text: '阐明基因中碱基序列的改变有可能导致它所编码的蛋白质及相应的细胞功能发生变化，甚至带来致命的后果',
    bigIdea: '概念3',
    keyConcept: '3.3',
    heat: 0,
    tool: '变异页·缺失位点',
    // 与 3.3.1 共用同一枚 moduleId（**允许**：3.1.1~3.1.4 + 3.2.1 都共用
    // `molecular`），但示范题不同 ⇒ 点进去落在**另一个**突变类型上。
    //
    // ⛔ 多义的后果写在明处：正因为两条 code 指向同一枚 moduleId，
    // `curriculumReverseCodeOf('gene_mutation')` 必须返 `null`（唯一命中才
    // 返回）⇒ 变异页那一侧**不挂**「课标 X」徽章、`Alt+K` 也**不认领**。
    // 挑一条挂上就是凭空编造对应关系，且学生在屏上看不出差别。
    //
    // 本条正文是「序列改变 → 蛋白质与功能变化（甚至致命）」，而本页 chip 文案
    // 逐字就是「变异页·**缺失位点**」⇒ 取「缺失」这一类：缺 1 个碱基必然移码，
    // `ATGAGCTAA` 第 4 位缺失 ⇒ `ATGACTAA`，受影响密码子 `AGC → ACT`（第 2 个）
    // ⇒ 结果判定落在「可能改变氨基酸」，正是本条正文要说的那一步。
    linkModuleId: 'gene_mutation',
    linkParams: {'sequence': 'ATGAGCTAA', 'type': '缺失', 'position': '4'},
  ),
  CurriculumItem(
    code: '3.3.3',
    text: '描述细胞在某些化学物质、射线以及病毒的作用下，基因突变概率可能提高，而某些基因突变能导致细胞分裂失控，甚至发生癌变',
    bigIdea: '概念3',
    keyConcept: '3.3',
    heat: 0,
    tool: '变异页·诱变因素卡',
    // ⛔ 仍然不给：`mutationFactors` 是 `engine/mutation_engine.dart:43` 的
    // 一张 **const 文字表**（category/factor/note），变异页「诱变与育种」
    // 页签只把它按类别**渲染成文字**（`variation_page.dart:533` 的循环），
    // **没有任何引擎函数吃它、也不产出任何数字**。
    // ⇒ 屏上没有「只在某条件下为真」的突变概率可算，挂深链只能编一个数字出来。
  ),
  CurriculumItem(
    code: '3.3.4',
    text: '阐明进行有性生殖的生物在减数分裂过程中，染色体所发生的自由组合和交叉互换，会导致控制不同性状的基因重组，从而使子代出现变异',
    bigIdea: '概念3',
    keyConcept: '3.3',
    heat: 2,
    tool: '连锁互换 + 9331',
    // v2.19.35：以前点这个 chip 落在 9331 的**双基因**页签。
    // `cross_linkage` 早已注册（`cross_calculator_page.dart:225-234`），
    // 其 apply 认 `{p1, p2, r}`（`:359-370`，宽松校验：`p1` 含 `/`、
    // `p2` 非空、`r` 非空）⇒ 只补数据。
    // ⚠️ 交换率取 **10%**：出厂值是 `linkage_tab.dart:38-40` 的
    // `_kDefaultR = '20%'`，逐字不同 ⇒ 「填没填」在断言上可区分；
    // 10% 与 20% 都是 3.3.4「交叉互换导致基因重组」的经典取值。
    // 亲本保持出厂同款（`AB/ab × ab/ab`）：改动最小、引擎零风险。
    linkModuleId: 'cross_linkage',
    linkParams: {'p1': 'AB/ab', 'p2': 'ab/ab', 'r': '10%'},
  ),
  CurriculumItem(
    code: '3.3.5',
    text: '举例说明染色体结构和数量的变异都可能导致生物性状的改变甚至死亡',
    bigIdea: '概念3',
    keyConcept: '3.3',
    heat: 1,
    tool: '变异页·染色体组数判断',
    // ⛔ 本轮**不接**：本仓这一枚 chip 逐字写的是「**组数判断**」
    // （= 数量那一半），而本仓**唯一**能带参落地的变异页 target 是
    // `cross_chromosomal_struct`（`{variant: 缺失|重复|倒位|易位}`，
    // `variation_page.dart:171-195`），它答的是**结构**那一半。
    // 把「组数判断」这枚 chip 拽到结构变异页签 = 屏上的东西与 chip 上的字
    // 不是一件事，而学生**看不出来**（banner 一样、页一样）⇒
    // 按「宁可不给，也不给错」的口径不给。
    // 顺带记一条本轮核实的**外部依赖**：`cross_chromosomal_struct` 是
    // **push 型** target（App 级常驻注册，`main.dart:336-342`），走它必定
    // 用注册点写死的 `sourceLabel: '拍题识别'` push 新实例 ⇒ 回程横幅会说
    // 「来自拍题识别」，对课标 chip 是**假话**。改注册点在 `main.dart`
    // （不在本簇文件所有权内）⇒ 留待后续轮次。
  ),
  CurriculumItem(
    code: '3.3.6',
    text: '举例说明人类遗传病是可以检测和预防的',
    bigIdea: '概念3',
    keyConcept: '3.3',
    heat: 1,
    tool: '遗传病速查 + 图谱概率',
    // v2.19.35 主线程裁定**解堵接上**：worker 上报的唯一障碍（push 型
    // 目标回程横幅写死「来自拍题识别」= 假话）已由总线 sourceLabel
    // 透传解决（consumePushSourceLabel 取后即焚，拍题 fill 不传标签
    // ⇒ 回落默认「拍题识别」）。示范题选「父亲患病 XaY × 携带者母亲
    // XAXa」（≠ 出厂 XAY/XAXa，守卫 CG6/CG7g 据此有牙齿）。
    linkModuleId: 'disease_risk',
    linkParams: {'father': 'XaY', 'mother': 'XAXa', 'mode': 'rec'},
  ),
  CurriculumItem(
    code: '4.1.1',
    text: '尝试通过化石记录、比较解剖学和胚胎学等事实，说明当今生物具有共同的祖先',
    bigIdea: '概念4',
    keyConcept: '4.1',
    heat: 0,
    tool: '进化页·证据速览',
    // v2.19.35：进化页有 5 个页签（`evolution_page.dart:267-298`：
    // 0 进化树 / 1 基因频率 / 2 遗传平衡 / 3 选择模拟 / 4 进化理论），
    // 以前只跳到**第 0 个页签（进化树）**。`evolution` 早已注册并支持
    // `{tab: 0..4}`（`evolution_page.dart:126-146`）⇒ 只补数据。
    // ⛔ 该分支**只切 tab、不自动计算**（无 p/q 时），如实记录。
    //
    // 落点证据是**本仓屏上的原文**，不是按名字猜的：tab 4「进化理论」里
    // 印着 FlatSection「共同祖先的证据」，其 trailing 就是一枚
    // `AppChip('课标 4.1.1 / 4.1.2')`（`evolution_page.dart:637-639`），
    // 正文逐条列着化石证据 / 比较解剖学（同源器官）/ 胚胎学证据 ——
    // 与 4.1.1 的正文一一对上。
    linkModuleId: 'evolution',
    linkParams: {'tab': '4'},
  ),
  CurriculumItem(
    code: '4.1.2',
    text: '尝试通过细胞生物学和分子生物学等知识，说明当今生物在新陈代谢、DNA的结构与功能等方面具有许多共同特征',
    bigIdea: '概念4',
    keyConcept: '4.1',
    heat: 0,
    tool: '进化页·共同特征卡',
    // v2.19.35 主线程裁定**翻案接上**：worker 发现的证据强度高于 B 当初——
    // 同一页签（进化理论 tab 4）有一行 `_kv('细胞与分子', '所有生物共用
    // 遗传密码、细胞色素 c 同源——DNA/新陈代谢共同特征')`
    // （`evolution_page.dart:646`），且那枚 `AppChip('课标 4.1.1 / 4.1.2')`
    // 把两条**并列印在同一节** ⇒ tab 4 即「共同特征」的落点，不是部分匹配。
    // 该 tab 同时承载证据/特征/理论/物种形成四节（4.1.1/4.1.2/4.2.4/4.2.5
    // 同落 tab 4，逐条理由见各自注释与守卫网 CG7f）。
    linkModuleId: 'evolution',
    linkParams: {'tab': '4'},
  ),
  CurriculumItem(
    code: '4.2.1',
    text: '举例说明种群内的某些可遗传变异将赋予个体在特定环境中的生存和繁殖优势',
    bigIdea: '概念4',
    keyConcept: '4.2',
    heat: 1,
    tool: '基因频率计算器',
    // v2.19.35：以前只跳到进化页第 0 个页签（**进化树**）——chip 上写着
    // 「基因频率计算器」，屏上却是进化树。现在直达**基因频率**页签（tab 1，
    // `evolution_page.dart:274-279`）。
    linkModuleId: 'evolution',
    linkParams: {'tab': '1'},
  ),
  CurriculumItem(
    code: '4.2.2',
    text: '阐明具有优势性状的个体在种群中所占比例将会增加',
    bigIdea: '概念4',
    keyConcept: '4.2',
    heat: 1,
    tool: '基因频率计算器',
    linkModuleId: 'evolution',
    linkParams: {'tab': '1'},
  ),
  CurriculumItem(
    code: '4.2.3',
    text: '说明自然选择促进生物更好地适应特定的生存环境',
    bigIdea: '概念4',
    keyConcept: '4.2',
    heat: 1,
    tool: '基因频率计算器',
    linkModuleId: 'evolution',
    linkParams: {'tab': '1'},
  ),
  CurriculumItem(
    code: '4.2.4',
    text: '概述现代生物进化理论以自然选择学说为核心，为地球上的生命进化史提供了科学的解释',
    bigIdea: '概念4',
    keyConcept: '4.2',
    heat: 1,
    tool: '进化页·理论脉络',
    // 落点 tab 4「进化理论」（`evolution_page.dart:292-297`）——与 4.1.1
    // 同一页签但**不同依据**：那一节印着「共同祖先的证据 / 现代生物
    // 进化理论 / 物种形成」三块（`:625-629` 的知识速览原文）。
    linkModuleId: 'evolution',
    linkParams: {'tab': '4'},
  ),
  CurriculumItem(
    code: '4.2.5',
    text: '阐述变异、选择和隔离可导致新物种形成',
    bigIdea: '概念4',
    keyConcept: '4.2',
    heat: 1,
    tool: '进化页·物种形成三步',
    // 落点仍是 tab 4：那一节有 FlatSection「物种形成」，trailing 就是
    // `AppChip('课标 4.2.5')`（`evolution_page.dart:663-666`），正文写着
    // 「三步环节：①突变和基因重组 → ②自然选择 → ③隔离」。
    linkModuleId: 'evolution',
    linkParams: {'tab': '4'},
  ),
];

/// 兼容 PLAN_2.0 接口契约：内嵌数据，无 IO。
List<CurriculumItem> loadCurriculum2020() => curriculum2020;
