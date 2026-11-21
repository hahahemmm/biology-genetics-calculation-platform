// molecular_page.dart —— 分子遗传计算（课标 3.1.2/3.1.3/3.1.4/3.2.1）
//
// DNA 碱基互补 / 单链与两链碱基关系 / 半保留复制与标记 / 基因表达
// 6:3:1 / 中心法则互推 / 减数分裂配子种类。引擎：dna_engine.dart +
// dna_strand_engine.dart。
//
// v2.19.21 工作台化（用户裁定：9331 布局语言推广到全计算器页）：
// 顶部 tab 导航（碱基组成 / 复制与标记 / 基因表达 / 配子种类），
// 宽屏 ≥1200 左侧常驻输入面板（ToolWorkbench 骨架，280px，与
// CrossToolRail 同款视觉），窄屏输入面板回渲染在结果区上方。
// 原「输入卡→箭头→结果卡」纵向全览改为「左输入右结果」分栏。

import 'package:flutter/material.dart';

import '../data/big_question_cards.dart' show findCardIdForTopic;
import '../engine/dna_engine.dart';
import '../engine/dna_strand_engine.dart';
import '../theme.dart';
import '../ui/ai_chat_controller.dart';
import '../guide/guide_keys.dart';
import '../ui/assistant_panel.dart';
import '../ui/module_fill.dart';
import '../ui/step_card.dart' show RatioPill;
import '../ui/step_chain.dart';
import '../ui/tab_jump_shortcuts.dart';
import '../state/present_mode_controller.dart';
import 'widgets/card_link_key_host.dart';
import 'widgets/centrifuge_band_diagram.dart';
import 'widgets/cross_tool_rail.dart' show FlatSection;
import 'widgets/dogma_strand_diagram.dart';
import 'widgets/knowledge_lab.dart';
import 'widgets/pcr_lab.dart';
import 'widgets/restriction_lab.dart';
import 'widgets/save_mistake_key_host.dart';
import 'widgets/semiconservative_grid.dart';
import 'widgets/strand_ct_matrix.dart';
import 'widgets/tool_workbench.dart';

class MolecularPage extends StatefulWidget {
  const MolecularPage({super.key, this.onNavPressed});

  final VoidCallback? onNavPressed;

  @override
  State<MolecularPage> createState() => _MolecularPageState();
}

class _MolecularPageState extends State<MolecularPage>
    with TickerProviderStateMixin {
  // ── v2.19.32：出厂默认值（具名常量）────────────────────────────
  //
  // ⚠️ **常量是唯一真相**：下面的 controller 初始化与 `isPristine` **共用**
  // 同一批常量。本项目被「影子常量」坑过（重复定义 `_tabNames` 被
  // `dart analyze` 抓到），两个真相一定会分叉 ⇒ 一旦分叉，守卫会把
  // 「出厂状态」误判成 dirty（或反之），学生就会莫名其妙地被拒。
  static const _kDefaultBase = '30'; // 某碱基百分比
  static const _kDefaultRep = '3';
  static const _kDefaultAa = '50';
  static const _kDefaultPair = '2';
  // 碱基组成 tab 输入
  static const _kDefaultRatio = '0.4'; // 链1 比值
  static const _kDefaultC1 = '10';
  static const _kDefaultT1 = '20';
  static const _kDefaultC2 = '15';
  static const _kDefaultT2 = '25';
  // 复制与标记 tab 输入
  static const _kDefaultLabelGen = '3'; // 复制代数
  static const _kDefaultMat = '100'; // 每分子某碱基含量
  static const _kDefaultMit2n = '20'; // 2n
  static const _kDefaultMat2 = '100'; // 每分子该碱基个数 m
  static const _kDefaultMatGen = '3'; // 复制代数 n
  // 基因表达 tab 输入
  static const _kDefaultDogma = 'TACGGATTA'; // 模板链

  final _baseCtrl = TextEditingController(text: _kDefaultBase);
  final _repCtrl = TextEditingController(text: _kDefaultRep);
  final _aaCtrl = TextEditingController(text: _kDefaultAa);
  final _pairCtrl = TextEditingController(text: _kDefaultPair);
  // 碱基组成 tab 输入
  final _ratioCtrl = TextEditingController(text: _kDefaultRatio);
  final _c1Ctrl = TextEditingController(text: _kDefaultC1);
  final _t1Ctrl = TextEditingController(text: _kDefaultT1);
  final _c2Ctrl = TextEditingController(text: _kDefaultC2);
  final _t2Ctrl = TextEditingController(text: _kDefaultT2);
  // 复制与标记 tab 输入
  final _labelGenCtrl = TextEditingController(text: _kDefaultLabelGen);
  final _matCtrl = TextEditingController(text: _kDefaultMat);
  final _mit2nCtrl = TextEditingController(text: _kDefaultMit2n);
  final _matCtrl2 = TextEditingController(text: _kDefaultMat2);
  final _matGenCtrl = TextEditingController(text: _kDefaultMatGen);
  // 基因表达 tab 输入
  final _dogmaCtrl = TextEditingController(text: _kDefaultDogma); // 模板链

  DnaBaseResult? _baseResult;
  String? _baseError;
  // v2.19.53（找茬 D）：各节**算出那一刻的输入快照**。Ctrl+S 组装 payload
  // 时逐节比对现文——改动过未重算的节从题干/答案剔除（⛔ 不存「题干新
  // 输入 + 答案旧结果」的矛盾题，矛盾数据会喂给错题本 AI 错因归类）。
  String? _baseSnap;
  DnaReplicationResult? _repResult;
  String? _repError;
  String? _repSnap;
  GeneExpressionResult? _exprResult;
  String? _exprError;
  String? _exprSnap;
  String? _pairResult;
  String? _pairError;
  String? _pairSnap;
  StrandRatioResult? _ratioResult;
  String? _ratioError;
  String? _ratioTitle;
  String? _ratioSnap;
  StrandCTResult? _ctResult;
  String? _ctError;
  String? _ctSnap;
  DnaLabelResult? _labelResult;
  String? _labelError;
  String? _labelSnap;
  ReplicationMaterial? _matResult;

  /// v2.19.50：原料那节**自己的**错误位。
  ///
  /// ⛔ 此前它没有错误位，`replicationMaterial` 抛错时只能借用 `_labelError`
  /// ——而 `_calcLabel` 又把两个调用塞进**同一个 try**，于是一节的限制会
  /// 「连坐」擦掉另一节的合法结果（详见 [_calcLabel]）。
  String? _matError;

  /// v2.19.53：_matResult 与 _labelResult 同生（共用 n），它的输入是
  /// n+m 两个框；快照独立成节。
  String? _matSnap;
  MitosisLabelResult? _mitResult;
  String? _mitError;
  String? _mitSnap;
  ReplicationMaterial? _mat2Result;
  String? _mat2Error;
  String? _mat2Snap;
  CentralDogmaResult? _dogmaResult;
  String? _dogmaError;
  String? _dogmaSnap;

  /// v2.19.21 工作台 tab（骨架外部持有 controller，避免 identical 短路）。
  late final TabController _tab;

  /// v2.21：第 5 页签「基因工程」的 State——输入与结果共用它一份真相。
  /// 父页经 GlobalKey 取两样东西：`isPristine`（深链覆盖守卫）与左栏
  /// 输入面板 `buildInputs`（见 widgets/restriction_lab.dart 文件头）。
  final _restrictionKey = GlobalKey<RestrictionLabState>();

  /// v2.21：该实验的状态版本号（⛔ 本页持有并 dispose，实验组件只自增）。
  /// 宽屏左栏副本先于 TabBarView 构建 ⇒ 首帧拿不到实验 State，靠它补一帧。
  final _restrictionRevision = ValueNotifier<int>(0);

  /// 第 5 页签里的第二个实验：PCR 与电泳（同一套公开契约）。
  /// 输入与结果共用它一份真相；父页同样经 GlobalKey 取 `isPristine` 与
  /// 左栏 `buildInputs`（见 widgets/pcr_lab.dart 文件头）。
  final _pcrKey = GlobalKey<PcrLabState>();

  /// PCR 实验的状态版本号（同上：本页持有并 dispose，组件只自增）。
  final _pcrRevision = ValueNotifier<int>(0);

  /// 第三个实验：遗传与基因工程知识库（同一套公开契约）。
  final _knowledgeKey = GlobalKey<KnowledgeLabState>();
  final _knowledgeRevision = ValueNotifier<int>(0);

  /// 第 5 页签当前实验：0 = 限制酶切、1 = PCR 与电泳、2 = 知识库。
  /// 三份 State 各自保活，切换只换显示，不重置任何输入或结果。
  int _engineeringLab = 0;

  /// v2.19.32：这一页现在**还是出厂状态吗**（学生一个格子都没动过）？
  ///
  /// 供 `ModuleFillTarget.canOverwrite` 用：学生自己在分子页敲了题之后，
  /// 再从「考纲覆盖」/「大题套路卡」点深链，**不该把他那道题无声顶掉**。
  ///
  /// 判据 = **整页 4 个页签的全部 15 个输入框**都还等于出厂常量
  /// （多页签统一按整页判：任一页签被敲过就算 dirty——本页的深链 apply
  /// 只会写模板链，但学生在这页建立的任何一格都是他自己的题）。
  ///
  /// ⚠️ `TACGGATTA` 这类**有意义的示例题算 pristine**——判的是「有没有被
  /// 学生动过」，不是「是不是空」。非空 ≠ dirty。
  /// ⚠️ 不看「有没有算过」：出厂状态也会自动算一次，那是**它自己的**默认题，
  /// 不是「使用者留下的东西」。
  ///
  /// 基因工程三个实验的输入在各自 State 里，未挂载时视为出厂；任一实验
  /// 被学生动过都使整页 dirty，避免深链覆盖学生正在做的内容。
  bool get isPristine =>
      _baseCtrl.text == _kDefaultBase &&
      _repCtrl.text == _kDefaultRep &&
      _aaCtrl.text == _kDefaultAa &&
      _pairCtrl.text == _kDefaultPair &&
      _ratioCtrl.text == _kDefaultRatio &&
      _c1Ctrl.text == _kDefaultC1 &&
      _t1Ctrl.text == _kDefaultT1 &&
      _c2Ctrl.text == _kDefaultC2 &&
      _t2Ctrl.text == _kDefaultT2 &&
      _labelGenCtrl.text == _kDefaultLabelGen &&
      _matCtrl.text == _kDefaultMat &&
      _mit2nCtrl.text == _kDefaultMit2n &&
      _matCtrl2.text == _kDefaultMat2 &&
      _matGenCtrl.text == _kDefaultMatGen &&
      _dogmaCtrl.text == _kDefaultDogma &&
      (_restrictionKey.currentState?.isPristine ?? true) &&
      (_pcrKey.currentState?.isPristine ?? true) &&
      (_knowledgeKey.currentState?.isPristine ?? true);

  /// v2.19.32：`apply` 拒收本次参数时的**用户可见**反馈。
  ///
  /// ⛔ 只加守卫不提示 = 学生看到「点了没反应」，那比被顶掉更难排查。
  /// 文案直接用总线给的 `reason`（`kModuleFillSkippedDirty` = 目标页已被
  /// 使用者改过，本次参数**故意**没写进去）——⛔ 不用「你现在看到的是默认题」
  /// 去解释「我们主动决定不写」，那是**假话**。
  /// ⚠️ 文案里**不许出现 markdown 星号**（裸 `Text` 不解析，星号会原样上屏）。
  void _onApplyFailed(String moduleId, String reason) {
    debugPrint('[molecular] 深链未写入：module=$moduleId reason=$reason');
    if (!mounted) return;
    // 页面上下文拿不到 ScaffoldMessenger 时（极端挂载时序）退回 appCanvasKey。
    final ctx = ScaffoldMessenger.maybeOf(context) != null
        ? context
        : appCanvasKey.currentContext;
    final messenger = ctx == null ? null : ScaffoldMessenger.maybeOf(ctx);
    if (messenger == null) return;
    // 先换掉再 show：不 hide 的话连发只有第一条能看见。
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(reason), duration: const Duration(seconds: 9)),
      );
  }

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 5, vsync: this);
    // 图谱纯导览：只切页签，不填参、不触发计算，也不经过整页脏页闸。
    // 与 cross_tab 同范式；学生已有任何分子/限制酶输入都原样保留。
    ModuleFillBus.register(
      ModuleFillTarget(
        moduleId: 'molecular_tab',
        pageIndex: 5,
        label: '分子页·页签导览',
        apply: (params) {
          if (!mounted) return false;
          final tab = int.tryParse(params['tab']?.trim() ?? '');
          if (tab == null || tab < 0 || tab > 4) return false;
          _tab.animateTo(tab);
          return true;
        },
        onApplyFailed: _onApplyFailed,
      ),
    );
    // v2.5 拍题识别填参路由：AI 识别出 DNA/中心法则题 → 模板链回填。
    ModuleFillBus.register(
      ModuleFillTarget(
        moduleId: 'molecular',
        pageIndex: 5, // 主导航「分子」页
        label: '分子页·中心法则',
        apply: (params) {
          // v2.19.23 找茬 P3#4：mounted 首行守卫——原守卫在 _calcDogma
          // （内部 setState）之后，unmount 场景先抛、守卫形同虚设。
          if (!mounted) return false;
          final t = params['template']?.trim().toUpperCase() ?? '';
          if (t.isEmpty || !RegExp(r'^[ATCG]+$').hasMatch(t)) {
            // v2.19.25：套路卡深链——无模板时仅切 tab（tab 参数 0..4；
            // v2.21 起第 5 页签「基因工程」也可直达）。
            final tab = int.tryParse(params['tab']?.trim() ?? '');
            if (tab != null && tab >= 0 && tab < 5) {
              _tab.animateTo(tab);
              return true;
            }
            return false;
          }
          _dogmaCtrl.text = t;
          _calcDogma();
          // v2.19.21：结果在「基因表达」tab——切过去让用户直接看到。
          _tab.animateTo(2);
          return true;
        },
        // v2.19.32：分子页里已经有学生自己敲的题 ⇒ 深链**不覆盖**。
        //
        // ⚠️ 本页 State 由主导航 IndexedStack 常驻，`canOverwrite` 直接读本
        // State（不走 GlobalKey）——注册就在本 State 的 initState 里，
        // 拿得到的一定是**当前这个**实例。
        canOverwrite: () => isPristine,
        onApplyFailed: _onApplyFailed,
      ),
    );
  }

  @override
  void dispose() {
    ModuleFillBus.unregister('molecular_tab');
    ModuleFillBus.unregister('molecular');
    _tab.dispose();
    _restrictionRevision.dispose();
    _pcrRevision.dispose();
    _knowledgeRevision.dispose();
    for (final c in [
      _baseCtrl,
      _repCtrl,
      _aaCtrl,
      _pairCtrl,
      _ratioCtrl,
      _c1Ctrl,
      _t1Ctrl,
      _c2Ctrl,
      _t2Ctrl,
      _labelGenCtrl,
      _matCtrl,
      _mit2nCtrl,
      _matCtrl2,
      _matGenCtrl,
      _dogmaCtrl,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  // ─── 计算入口（引擎调用与 v2.19.20 前完全一致，零算法改动）───

  void _calcBase() {
    try {
      final v = double.tryParse(_baseCtrl.text.trim());
      if (v == null) throw ArgumentError('请输入数字（0–100）');
      final r = dnaBaseComposition(a: v);
      setState(() {
        _baseResult = r;
        _baseError = null;
        _baseSnap = _baseCtrl.text.trim();
      });
    } on ArgumentError catch (e) {
      setState(() {
        _baseResult = null;
        _baseError = e.message?.toString() ?? '输入格式错误';
      });
    }
  }

  void _calcRep() {
    try {
      final r = dnaReplication(copies: int.tryParse(_repCtrl.text.trim()) ?? 0);
      setState(() {
        _repResult = r;
        _repError = null;
        _repSnap = _repCtrl.text.trim();
      });
    } on ArgumentError catch (e) {
      setState(() {
        _repResult = null;
        _repError = e.message?.toString() ?? '输入格式错误';
      });
    }
  }

  void _calcExpr() {
    try {
      final r = geneExpression(
        aminoAcids: int.tryParse(_aaCtrl.text.trim()) ?? 0,
      );
      setState(() {
        _exprResult = r;
        _exprError = null;
        _exprSnap = _aaCtrl.text.trim();
      });
    } on ArgumentError catch (e) {
      setState(() {
        _exprResult = null;
        _exprError = e.message?.toString() ?? '输入格式错误';
      });
    }
  }

  void _calcPair() {
    try {
      final kinds = gameteKinds(
        chromosomePairs: int.tryParse(_pairCtrl.text.trim()) ?? 0,
      );
      setState(() {
        _pairResult = '2ⁿ = $kinds 种';
        _pairError = null;
        _pairSnap = _pairCtrl.text.trim();
      });
    } on ArgumentError catch (e) {
      setState(() {
        _pairResult = null;
        _pairError = e.message?.toString() ?? '输入格式错误';
      });
    }
  }

  double _parseRatio() {
    final v = double.tryParse(_ratioCtrl.text.trim());
    if (v == null || v <= 0) throw ArgumentError('请输入正数比值（如 0.4）');
    return v;
  }

  void _calcRatioAtGc() {
    try {
      final r = atOverGc(_parseRatio());
      setState(() {
        _ratioTitle = '(A+T)/(G+C)';
        _ratioResult = r;
        _ratioError = null;
        _ratioSnap = _ratioCtrl.text.trim();
      });
    } on ArgumentError catch (e) {
      setState(() {
        _ratioResult = null;
        _ratioError = e.message?.toString() ?? '输入格式错误';
      });
    }
  }

  void _calcRatioAgTc() {
    try {
      final r = agOverTc(_parseRatio());
      setState(() {
        _ratioTitle = '(A+G)/(T+C)';
        _ratioResult = r;
        _ratioError = null;
        _ratioSnap = _ratioCtrl.text.trim();
      });
    } on ArgumentError catch (e) {
      setState(() {
        _ratioResult = null;
        _ratioError = e.message?.toString() ?? '输入格式错误';
      });
    }
  }

  int _parseCount(TextEditingController c, String name) {
    final v = int.tryParse(c.text.trim());
    if (v == null || v < 0) throw ArgumentError('$name 应为非负整数');
    return v;
  }

  void _calcCT() {
    try {
      final r = strandCountsFromCT(
        c1: _parseCount(_c1Ctrl, '链1 C'),
        t1: _parseCount(_t1Ctrl, '链1 T'),
        c2: _parseCount(_c2Ctrl, '链2 C'),
        t2: _parseCount(_t2Ctrl, '链2 T'),
      );
      setState(() {
        _ctResult = r;
        _ctError = null;
        _ctSnap =
            '${_c1Ctrl.text.trim()}|${_t1Ctrl.text.trim()}|'
            '${_c2Ctrl.text.trim()}|${_t2Ctrl.text.trim()}';
      });
    } on ArgumentError catch (e) {
      setState(() {
        _ctResult = null;
        _ctError = e.message?.toString() ?? '输入格式错误';
      });
    }
  }

  /// v2.19.50：⛔ **两个调用必须各自 try**（此前共用一个 catch，会连坐）。
  ///
  /// 病灶：两个引擎对同一个 `n` 的**上限不同**——`dnaLabelReplication` 允许
  /// n ≤ 40（`dna_strand_engine.dart`），`replicationMaterial` 只允许 n ≤ 30
  /// （抛「复制代数过大（≤30）」）。学生填 **n ∈ [31, 40]** 且填了 m 时：
  /// ① 标记分布**算得出、且完全合法**；② 原料抛错；
  /// 旧代码把两者放进同一个 try ⇒ 原料的错把**标记分布的合法答案一起清空**，
  /// 屏上还显示一句「复制代数过大（≤30）」——**那句限制对标记分布那节
  /// 根本不适用**。学生看到的是「我填的 n 被拒了」，而它没被拒。
  void _calcLabel() {
    final n = int.tryParse(_labelGenCtrl.text.trim()) ?? 0;
    final m = int.tryParse(_matCtrl.text.trim());
    // 先算标记分布。n 本身不合法 ⇒ 原料必然也不合法，没有第二段可算，直接收。
    try {
      final r = dnaLabelReplication(generations: n);
      setState(() {
        _labelResult = r;
        _labelError = null;
        _labelSnap = _labelGenCtrl.text.trim();
      });
    } on ArgumentError catch (e) {
      setState(() {
        _labelResult = null;
        _labelError = e.message?.toString() ?? '输入格式错误';
        _matResult = null;
        _matError = null;
      });
      return;
    }
    // 原料是**另一节**的事：它失败只清它自己，不许动上面那个合法结果。
    if (m == null || m <= 0) {
      setState(() {
        _matResult = null;
        _matError = null;
      });
      return;
    }
    try {
      final mat = replicationMaterial(generations: n, perMolecule: m);
      setState(() {
        _matResult = mat;
        _matError = null;
        _matSnap = '${_labelGenCtrl.text.trim()}|${_matCtrl.text.trim()}';
      });
    } on ArgumentError catch (e) {
      setState(() {
        _matResult = null;
        _matError = e.message?.toString() ?? '输入格式错误';
      });
    }
  }

  // ─── v2.19.51：Ctrl+S 存入错题本——题干/答案按下那一刻现组装 ───
  //
  // ⛔ 一个页签里多个计算器时，题干只写**已算出结果的那几节**的输入
  // （屏上那一节的输入框），不把整页 15 个输入框全塞进去——那样题干
  // 会变成与当前这道题无关的噪音（B 仓 v2.19.173 同款口径）。
  // ⛔ 屏上数字一律来自 controller 现文 / 引擎字段，一个都不许自编。

  // v2.19.53（找茬 D）：逐节「新鲜度」门——结果存在**且算出那一刻的
  // 输入快照与现文一致**才算数。学生改输入未重算时该节从题干/答案剔除，
  // ⛔ 不存「题干新输入 + 答案旧结果」的矛盾题（矛盾数据会喂给错题本
  // AI 错因归类）。全部节不新鲜 ⇒ 答案空串 ⇒ saveToMistakeBook 既有
  // 「先算出结果」守卫应答。
  bool get _baseFresh =>
      _baseResult != null && _baseSnap == _baseCtrl.text.trim();
  bool get _ratioFresh =>
      _ratioResult != null && _ratioSnap == _ratioCtrl.text.trim();
  bool get _ctFresh =>
      _ctResult != null &&
      _ctSnap ==
          '${_c1Ctrl.text.trim()}|${_t1Ctrl.text.trim()}|'
              '${_c2Ctrl.text.trim()}|${_t2Ctrl.text.trim()}';
  bool get _repFresh => _repResult != null && _repSnap == _repCtrl.text.trim();
  bool get _labelFresh =>
      _labelResult != null && _labelSnap == _labelGenCtrl.text.trim();
  bool get _matFresh =>
      _matResult != null &&
      _matSnap == '${_labelGenCtrl.text.trim()}|${_matCtrl.text.trim()}';
  bool get _mitFresh =>
      _mitResult != null && _mitSnap == _mit2nCtrl.text.trim();
  bool get _mat2Fresh =>
      _mat2Result != null &&
      _mat2Snap == '${_matCtrl2.text.trim()}|${_matGenCtrl.text.trim()}';
  bool get _exprFresh =>
      _exprResult != null && _exprSnap == _aaCtrl.text.trim();
  bool get _dogmaFresh =>
      _dogmaResult != null && _dogmaSnap == _dogmaCtrl.text.trim();
  bool get _pairFresh =>
      _pairResult != null && _pairSnap == _pairCtrl.text.trim();

  /// 当前页签的考点标签（错题本筛选字段）。⛔ 四签四条课标，不共用一签。
  String get _mistakeSubjectArea {
    const areas = [
      '碱基组成（DNA 碱基互补）',
      '复制与标记（半保留复制与密度梯度）',
      '基因表达（6:3:1 与中心法则）',
      '配子种类（减数分裂）',
    ];
    final i = _tab.index;
    return i >= 0 && i < areas.length ? areas[i] : areas.first;
  }

  /// v2.19.59：**当前考点有没有配套套路卡**——全页唯一判据。
  ///
  /// 屏上提示句与 [CardLinkKeyHost] 的 `cardId` 回调都调这一个 getter
  /// （同一个 `findCardIdForTopic(_mistakeSubjectArea)` 调用链）⇒ 两处
  /// 不可能分叉：显示提示时按 K 必跳、不显示时按 K 必无声让路。
  /// ⛔ 不许按 `_tab.index` 另行推导考点——考点就是 save 用的那一份。
  String? get _linkedCardId => findCardIdForTopic(_mistakeSubjectArea);

  /// v2.19.59：结果区副标题位的屏上提示句（键位文案从宿主取，唯一真相；
  /// ⛔ 无 markdown 星号、无方向词）。
  static const String _kCardLinkHint = '按 ${CardLinkKeyHost.keyLabel} 看这道题的套路卡';

  String get _mistakeStem {
    switch (_tab.index) {
      case 0:
        return <String>[
          if (_baseFresh) '双链 DNA 中 A 占 ${_baseCtrl.text.trim()}%，求其余碱基各占多少',
          if (_ratioFresh)
            '全分子 ${_ratioTitle ?? '碱基比'} = ${_ratioCtrl.text.trim()}，'
                '求链 2 与全分子的对应比值',
          if (_ctFresh)
            '链1 C=${_c1Ctrl.text.trim()}、T=${_t1Ctrl.text.trim()}，'
                '链2 C=${_c2Ctrl.text.trim()}、T=${_t2Ctrl.text.trim()}，'
                '求全分子各碱基数量',
        ].join('；');
      case 1:
        return <String>[
          if (_repFresh)
            '1 个 DNA 分子复制 ${_repCtrl.text.trim()} 次，'
                '求分子数、含亲代链的分子数与新合成链数',
          if (_labelFresh)
            '标记 DNA 移入无标记培养基复制 ${_labelGenCtrl.text.trim()} 代，'
                '求标记分子分布与离心带型',
          // v2.19.52（找茬 C1）：_calcLabel 一单算两节——_matResult 与
          // _labelResult 同生，题干必须也写它的输入（m），否则答案里
          // 多出一条题干推不出的数。
          if (_matFresh)
            '同栏原料：每分子该碱基 m=${_matCtrl.text.trim()} 个，'
                '复制 ${_labelGenCtrl.text.trim()} 代，求游离核苷酸需求',
          if (_mitFresh)
            '染色体全部双链标记后移入无标记培养基（2n=${_mit2nCtrl.text.trim()}），'
                '第 ${_mitResult!.divisions} 次分裂后子细胞带标记染色体数',
          if (_mat2Fresh)
            '每分子某碱基 m=${_matCtrl2.text.trim()} 个，'
                '复制 ${_matGenCtrl.text.trim()} 代，求游离核苷酸原料需求',
        ].join('；');
      case 2:
        return <String>[
          if (_exprFresh) '氨基酸数 ${_aaCtrl.text.trim()}，求基因碱基数与 mRNA 碱基数',
          if (_dogmaFresh)
            '模板链 ${_dogmaCtrl.text.trim()}（3′→5′），'
                '求编码链、mRNA、密码子与反密码子',
        ].join('；');
      case 3:
        return 'n=${_pairCtrl.text.trim()} 对同源染色体的生物，'
            '求减数分裂可产生的配子种类数';
      default:
        return '';
    }
  }

  /// 答案全部取自引擎结果字段。⚠️ tab3 的 [_pairResult] 在 [_calcPair]
  /// 里就被拼成了 `'2ⁿ = $kinds 种'`（gameteKinds 只返回 int，没有结果
  /// 对象可读）⇒ 直接沿用该串，⛔ 不许对它取引擎字段。
  String get _mistakeAnswer {
    final parts = <String>[];
    switch (_tab.index) {
      case 0:
        final b = _baseFresh ? _baseResult : null;
        if (b != null) {
          parts.add(
            'A=${b.a.toStringAsFixed(1)}%，T=${b.t.toStringAsFixed(1)}%，'
            'G=${b.g.toStringAsFixed(1)}%，C=${b.c.toStringAsFixed(1)}%',
          );
        }
        final r = _ratioFresh ? _ratioResult : null;
        if (r != null) {
          parts.add(
            '${_ratioTitle ?? '碱基比'}：链2 ${r.chain2.toStringAsFixed(3)}，'
            '全分子 ${r.whole.toStringAsFixed(3)}',
          );
        }
        final ct = _ctFresh ? _ctResult : null;
        if (ct != null) {
          parts.add(
            '全分子 A=${ct.aTotal}、T=${ct.tTotal}、G=${ct.gTotal}、'
            'C=${ct.cTotal}，碱基总数 ${ct.total}',
          );
        }
      case 1:
        final rep = _repFresh ? _repResult : null;
        if (rep != null) {
          parts.add(
            '2ⁿ=${rep.dnaMolecules} 个分子，含亲代链 ${rep.withParentStrand} 个，'
            '新合成链 ${rep.newStrands} 条',
          );
        }
        final lab = _labelFresh ? _labelResult : null;
        if (lab != null) {
          parts.add(
            '总分子 ${lab.totalMolecules}，含标记 ${lab.labeledMolecules} 个'
            '（${(lab.labeledMoleculeRatio * 100).toStringAsFixed(1)}%），'
            '标记链 ${lab.labeledStrands}/${lab.totalStrands} 条；${lab.centrifugeBands}',
          );
        }
        final mit = _mitFresh ? _mitResult : null;
        if (mit != null) {
          parts.add(
            '2n=${mit.chromosomes2n} 分裂 ${mit.divisions} 次后'
            '带标记染色体 ${mit.labeledChromosomes} 条',
          );
        }
        final mat2 = _mat2Fresh ? _mat2Result : null;
        if (mat2 != null) {
          parts.add(
            '原料共需 ${mat2.totalNeeded} 个，第 ${mat2.generations} 次'
            '需 ${mat2.lastRoundNeeded} 个',
          );
        }
        final mat = _matFresh ? _matResult : null;
        if (mat != null) {
          parts.add(
            '（同栏原料）共需 ${mat.totalNeeded} 个，'
            '第 ${mat.generations} 次需 ${mat.lastRoundNeeded} 个',
          );
        }
      case 2:
        final ex = _exprFresh ? _exprResult : null;
        if (ex != null) {
          parts.add('基因 ${ex.geneBases} 个碱基，mRNA ${ex.mrnaBases} 个碱基');
        }
        final d = _dogmaFresh ? _dogmaResult : null;
        if (d != null) {
          parts.add(
            '编码链 ${d.coding}，mRNA ${d.mrna}，'
            '密码子 ${d.codons.join('-')}，反密码子 ${d.anticodons.join('-')}',
          );
        }
      case 3:
        final p = _pairFresh ? _pairResult : null;
        if (p != null) parts.add(p);
      default:
        break;
    }
    return parts.join('；');
  }

  /// 本页 4 个页签全部有计算器 ⇒ 永不返回 null；「未算出结果」照常传
  /// 空答案，由 saveToMistakeBook 的「先算出结果，再存入错题本」守卫应答。
  ///
  /// srcModule 只给「中心法则」那一节：本页 ModuleFillBus 唯一的真 target
  /// 是 moduleId 'molecular'（回填 template + 切 tab2），别的节没有可回填
  /// 深链 ⇒ ⛔ 不传（传了错题本会出现点下去必然被拒的回程按钮）。
  SavePayload? _mistakePayload() {
    final i = _tab.index;
    // v2.21：第 5 页签（基因工程·限制酶切）本轮**不接** Ctrl+S——它没有
    // 「题干/答案」这套口径（题面是序列与酶，不是可复用的一道题），返回
    // null ⇒ 宿主闸 ④ 无声让路，⛔ 不替它编一个题干。
    if (i < 0 || i > 3) return null;
    final dogmaSaved = i == 2 && _dogmaFresh;
    return SavePayload(
      stem: _mistakeStem,
      correctAnswer: _mistakeAnswer,
      subjectArea: _mistakeSubjectArea,
      srcModule: dogmaSaved ? 'molecular' : null,
      srcParams: dogmaSaved ? {'template': _dogmaCtrl.text.trim()} : null,
    );
  }

  void _calcMitosis(int divisions) {
    try {
      final r = mitosisLabeling(
        chromosomes2n: int.tryParse(_mit2nCtrl.text.trim()) ?? 0,
        divisions: divisions,
      );
      setState(() {
        _mitResult = r;
        _mitError = null;
        _mitSnap = _mit2nCtrl.text.trim();
      });
    } on ArgumentError catch (e) {
      setState(() {
        _mitResult = null;
        _mitError = e.message?.toString() ?? '输入格式错误';
      });
    }
  }

  void _calcMat() {
    try {
      final m = int.tryParse(_matCtrl2.text.trim());
      final n = int.tryParse(_matGenCtrl.text.trim()) ?? 0;
      if (m == null) throw ArgumentError('m 应为正整数');
      final r = replicationMaterial(generations: n, perMolecule: m);
      setState(() {
        _mat2Result = r;
        _mat2Error = null;
        _mat2Snap = '${_matCtrl2.text.trim()}|${_matGenCtrl.text.trim()}';
      });
    } on ArgumentError catch (e) {
      setState(() {
        _mat2Result = null;
        _mat2Error = e.message?.toString() ?? '输入格式错误';
      });
    }
  }

  void _calcDogma() {
    try {
      final r = centralDogmaFromTemplate(_dogmaCtrl.text);
      setState(() {
        _dogmaResult = r;
        _dogmaError = null;
        _dogmaSnap = _dogmaCtrl.text.trim();
      });
    } on ArgumentError catch (e) {
      setState(() {
        _dogmaResult = null;
        _dogmaError = e.message?.toString() ?? '输入格式错误';
      });
    }
  }

  // ─── 工作台 tab 定义 ───

  List<WorkbenchTabSpec> _tabs() => [
    WorkbenchTabSpec(
      label: '碱基组成',
      icon: Icons.science_outlined,
      sidePanel: _baseInputs,
      body: _baseBody,
    ),
    WorkbenchTabSpec(
      label: '复制与标记',
      icon: Icons.content_copy_outlined,
      sidePanel: _replicationInputs,
      body: _replicationBody,
    ),
    WorkbenchTabSpec(
      label: '基因表达',
      icon: Icons.translate_outlined,
      sidePanel: _expressionInputs,
      body: _expressionBody,
    ),
    WorkbenchTabSpec(
      label: '配子种类',
      icon: Icons.call_split_outlined,
      sidePanel: _gameteInputs,
      body: _gameteBody,
    ),
    // 第 5 页签「基因工程」= 三个并列实验：限制酶切、PCR 与电泳、知识库。
    // 三者各自持有一份 State（输入 + 结果），不共享 controller；结果区
    // 用 IndexedStack 保活，切换只是换显示，不重建、不丢状态。
    // ⚠️ 不用嵌套 TabBarView：外层结果区高度无界，横向 viewport 会抛异常。
    WorkbenchTabSpec(
      label: '基因工程',
      icon: Icons.content_cut_outlined,
      sidePanel: _engineeringInputs,
      body: (ctx) => IndexedStack(
        index: _engineeringLab,
        children: [
          RestrictionLab(
            key: _restrictionKey,
            showInputs: false,
            revision: _restrictionRevision,
          ),
          PcrLab(key: _pcrKey, showInputs: false, revision: _pcrRevision),
          KnowledgeLab(
            key: _knowledgeKey,
            showInputs: false,
            revision: _knowledgeRevision,
          ),
        ],
      ),
    ),
  ];

  /// 第 5 页签的左栏：实验选择器 + 当前实验的输入面板。
  Widget _engineeringInputs(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Semantics(
        label: '基因工程实验选择，三个实验各自保留输入与结果',
        child: Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: _labTile(
                      value: 0,
                      label: '限制酶切',
                      icon: Icons.content_cut_outlined,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _labTile(
                      value: 1,
                      label: 'PCR 与电泳',
                      icon: Icons.science_outlined,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              _labTile(value: 2, label: '知识库', icon: Icons.menu_book_outlined),
            ],
          ),
        ),
      ),
      if (_engineeringLab == 0)
        ValueListenableBuilder<int>(
          valueListenable: _restrictionRevision,
          builder: (_, _, _) =>
              _restrictionKey.currentState?.buildInputs(context) ??
              const SizedBox.shrink(),
        )
      else if (_engineeringLab == 1)
        ValueListenableBuilder<int>(
          valueListenable: _pcrRevision,
          builder: (_, _, _) =>
              _pcrKey.currentState?.buildInputs(context) ??
              const SizedBox.shrink(),
        )
      else
        ValueListenableBuilder<int>(
          valueListenable: _knowledgeRevision,
          builder: (_, _, _) =>
              _knowledgeKey.currentState?.buildInputs(context) ??
              const SizedBox.shrink(),
        ),
    ],
  );

  /// 实验选择块：整块可点（白板远距离也好按），选中的用同色系深一档，
  /// 不整页换色。最小高度 44（触控目标），文字按宽档自动换行不裁切。
  Widget _labTile({
    required int value,
    required String label,
    required IconData icon,
  }) {
    final selected = _engineeringLab == value;
    return Material(
      color: selected ? AppColors.tealWash : AppColors.surface,
      borderRadius: BorderRadius.circular(AppTheme.radiusInput),
      child: InkWell(
        onTap: () => setState(() => _engineeringLab = value),
        borderRadius: BorderRadius.circular(AppTheme.radiusInput),
        child: Container(
          constraints: const BoxConstraints(minHeight: 44),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppTheme.radiusInput),
            border: Border.all(
              color: selected ? AppColors.teal : AppColors.border,
              width: selected ? 1.6 : 1,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 16,
                color: selected ? AppColors.tealDark : AppColors.graphite,
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  label,
                  textAlign: TextAlign.center,
                  style: AppText.label.copyWith(
                    color: selected ? AppColors.tealDark : AppColors.ink,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // v2.19.21 工作台化：顶部 tab + 宽屏左栏输入 / 右区结果。
    // v2.19.22：骨架每次 build 新建（identical 短路纪律）；
    // TabBar 进 AppBar.bottom（骨架 StatefulWidget 后改由
    // buildWorkbenchTabBar 顶层函数组装）。
    final tabs = _tabs();
    return Scaffold(
      appBar: AppBar(
        leading: appNavButton(widget.onNavPressed),
        title: const Text('分子遗传'),
        // v2.19.23 找茬 P1#1：引导锚点挂 TabBar（tab 无关，永在树）——
        // 原挂 tab0 首卡，拍题填入后 animateTo(2) 永久离树，引导丢高亮。
        bottom: PreferredSize(
          key: GuideKeys.molecularFirst,
          preferredSize: const Size.fromHeight(48),
          child: buildWorkbenchTabBar(_tab, tabs),
        ),
        actions: [
          TextButton.icon(
            onPressed: () {
              _calcBase();
              _calcRep();
              _calcExpr();
              _calcPair();
              // 三个实验一并刷新；知识库仅在已有检索词时重查，默认不联网。
              _restrictionKey.currentState?.recalc();
              _pcrKey.currentState?.recalc();
              _knowledgeKey.currentState?.recalc();
            },
            icon: const Icon(Icons.play_arrow, size: 18),
            label: const Text('全部计算'),
          ),
          // v2.1 问 AI：页面上下文随带（与系谱页同链路：queueSend + 侧栏）
          TextButton.icon(
            onPressed: () {
              AiChatController.instance.queueSend(
                '【当前工具：分子遗传计算】DNA 碱基互补 / 半保留复制 / 基因表达 6:3:1 / 减数分裂配子种类。当前输入：碱基 A=${_baseCtrl.text}%、复制 n=${_repCtrl.text}、氨基酸数=${_aaCtrl.text}、染色体对数=${_pairCtrl.text}。',
              );
              showAiAssistant(context);
            },
            icon: Icon(
              Icons.psychology_outlined,
              size: 18,
              color: AppColors.teal,
            ),
            label: Text(
              '问 AI',
              style: TextStyle(
                color: AppColors.teal,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
      // v2.19.49：Alt+数字 页签直跳宿主（零像素，只切页签不碰题面；
      // 让路闸见 lib/ui/tab_jump_shortcuts.dart 文件头）。
      // v2.19.51：Ctrl+S 存当前题进错题本（页面级唯一宿主；payload 是
      // 按下那一刻现取的 ValueGetter ⇒ ToolWorkbench 切页签不让本 State
      // rebuild 也没有过期窗，B 仓 v2.19.173 抓的 stale-capture 病由构造
      // 不存在；闸见 save_mistake_key_host.dart 文件头）。
      body: SaveMistakeKeyHost(
        payload: _mistakePayload,
        child: CardLinkKeyHost(
          // v2.19.59：K 看这道题的套路卡（页面级唯一宿主；只切页签不让本
          // State rebuild ⇒ cardId 必须是按下那一刻现取的 ValueGetter，
          // 闸见 card_link_key_host.dart 文件头）。
          cardId: () => _linkedCardId,
          child: TabJumpShortcuts(
            tab: _tab,
            child: ToolWorkbench(
              controller: _tab,
              tabs: tabs,
              railTitle: '分子遗传 · 输入',
              railIcon: Icons.science_outlined,
            ),
          ),
        ),
      ),
    );
  }

  // ─── Tab 1：碱基组成（输入 + 结果）───

  Widget _baseInputs(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      FlatSection(
        title: 'DNA 碱基互补计算',
        subtitle: '课标 3.1.2',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '双链 DNA：A=T、G=C、A+G=T+C=50%。输入任一碱基百分比，'
              '自动补全其余。',
              style: AppText.caption.copyWith(color: AppColors.graphite),
            ),
            const SizedBox(height: 8),
            _narrowField(_baseCtrl, '输入 A 的百分比（如 30）', _calcBase),
            _calcBtn('计算碱基组成', _calcBase),
          ],
        ),
      ),
      FlatSection(
        title: '单链碱基比值换算',
        subtitle: '常考',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '已知链1 的比值，求互补链与全分子：'
              '(A+T)/(G+C) 三处相同；(A+G)/(T+C) 互补链取倒数、全分子=1。',
              style: AppText.caption.copyWith(color: AppColors.graphite),
            ),
            const SizedBox(height: 8),
            _narrowField(_ratioCtrl, '链1 中的比值（如 0.4）', _calcRatioAgTc),
            Wrap(
              spacing: 8,
              children: [
                _calcBtn('按 (A+T)/(G+C) 算', _calcRatioAtGc),
                _calcBtn('按 (A+G)/(T+C) 算', _calcRatioAgTc),
              ],
            ),
          ],
        ),
      ),
      FlatSection(
        title: '两链 C / T 计数互推',
        subtitle: '常考',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '已知链1、链2 上 C 和 T 的数量，求全分子 A、G（及总数）：'
              'A总数=T₁+T₂；G总数=C₁+C₂。',
              style: AppText.caption.copyWith(color: AppColors.graphite),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(child: _field(_c1Ctrl, '链1 C', _calcCT)),
                const SizedBox(width: 8),
                Expanded(child: _field(_t1Ctrl, '链1 T', _calcCT)),
              ],
            ),
            Row(
              children: [
                Expanded(child: _field(_c2Ctrl, '链2 C', _calcCT)),
                const SizedBox(width: 8),
                Expanded(child: _field(_t2Ctrl, '链2 T', _calcCT)),
              ],
            ),
            _calcBtn('计算全分子碱基', _calcCT),
          ],
        ),
      ),
    ],
  );

  Widget _baseBody(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _resultSection(
        title: 'DNA 碱基互补计算 · 结果',
        badge: '课标 3.1.2',
        ready: _baseResult != null,
        error: _baseError,
        results: _baseResult == null
            ? null
            : [
                Text(
                  'A=${_baseResult!.a.toStringAsFixed(1)}%　'
                  'T=${_baseResult!.t.toStringAsFixed(1)}%　'
                  'G=${_baseResult!.g.toStringAsFixed(1)}%　'
                  'C=${_baseResult!.c.toStringAsFixed(1)}%',
                  style: AppText.monoFigure,
                ),
              ],
      ),
      _resultSection(
        title: '单链碱基比值换算 · 结果',
        badge: '常考',
        ready: _ratioResult != null,
        error: _ratioError,
        results: _ratioResult == null
            ? null
            : [
                _pillRow(
                  '${_ratioTitle!} 互补链',
                  _ratioResult!.chain2.toStringAsFixed(3),
                ),
                _pillRow(
                  '${_ratioTitle!} 全分子',
                  _ratioResult!.whole.toStringAsFixed(3),
                ),
                Text(
                  _ratioResult!.rule,
                  style: AppText.caption.copyWith(color: AppColors.graphite),
                ),
              ],
      ),
      _resultSection(
        title: '两链 C / T 计数互推 · 结果',
        badge: '常考',
        ready: _ctResult != null,
        error: _ctError,
        results: _ctResult == null
            ? null
            : [
                StepChain(
                  steps: [
                    ChainStep.input(
                      '题干数据',
                      formula:
                          '链1 C=${_c1Ctrl.text} T=${_t1Ctrl.text}；'
                          '链2 C=${_c2Ctrl.text} T=${_t2Ctrl.text}',
                    ),
                    const ChainStep.compute(
                      '互补配对',
                      formula: 'A=T₁+T₂，G=C₁+C₂',
                      detail: '链1 的 A 配对链2 的 T，链1 的 G 配对链2 的 C',
                    ),
                    ChainStep.result(
                      '全分子结果',
                      formula:
                          'A=${_ctResult!.aTotal}　T=${_ctResult!.tTotal}　'
                          'G=${_ctResult!.gTotal}　C=${_ctResult!.cTotal}',
                      detail: '碱基总数 ${_ctResult!.total} 个',
                    ),
                  ],
                ),
                // v2.19.41：两链 C/T 计数格阵（纯 CustomPainter 代码绘制，
                // ⛔ 禁位图）。引擎只给链1/链2 的 C、T 与全分子四种计数 ——
                // 链1/链2 各自的 A 与 G 它**没有字段** ⇒ 格阵 12 格里那
                // 4 格留空，⛔ 绝不代填 0（空格画只有框、没有字 + 图例）。
                // ⛔ 画不出来时把原因印在这里（数据闸 + 宽度闸），⛔ 零静默、
                // ⛔ 不留空框 / 标题 / 占位。
                const SizedBox(height: 10),
                LayoutBuilder(
                  builder: (context, c) {
                    // ⛔ 可画性闸门与组件本体必须用同一个课堂倍率：闸门按
                    // 1.0 判而组件按课堂档建 ⇒ 闸门放行、组件自己收缩 ⇒ 连
                    // 「为什么不画」那一句都不出现。标准档恒 1.0。
                    final ctScale = PresentModeController.instance.enabled
                        ? PresentModeController.textScale
                        : 1.0;
                    final reason = StrandCtMatrix.skipReason(
                      _ctResult,
                      c.maxWidth,
                      textScale: ctScale,
                    );
                    if (reason != null) {
                      return Text(
                        reason,
                        style: AppText.caption.copyWith(
                          color: AppColors.graphite,
                        ),
                      );
                    }
                    // 本图是 TextPainter 自绘，不吃 MaterialApp.builder 注入的
                    // MediaQuery.textScaler（那条只作用于 Text widget）⇒ 课堂
                    // 档格内数字必须显式下传倍率；标准档传 1.0。
                    return StrandCtMatrix(
                      result: _ctResult!,
                      textScale: ctScale,
                    );
                  },
                ),
              ],
      ),
    ],
  );

  // ─── Tab 2：复制与标记（输入 + 结果）───

  Widget _replicationInputs(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      FlatSection(
        title: 'DNA 半保留复制',
        subtitle: '课标 3.1.3',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '1 个 DNA 复制 n 次：分子数 2ⁿ，含亲代链的始终为 2；'
              '新合成链 = 2ⁿ⁺¹ − 2。',
              style: AppText.caption.copyWith(color: AppColors.graphite),
            ),
            const SizedBox(height: 8),
            _narrowField(_repCtrl, '复制次数 n', _calcRep),
            _calcBtn('计算复制结果', _calcRep),
          ],
        ),
      ),
      FlatSection(
        title: 'DNA 标记计算（¹⁵N/³H/³²P）',
        subtitle: '常考',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '标记 DNA 移入无标记培养基复制 n 代：含亲代标记链的分子'
              '恒为 2 个；原料需求 =(2ⁿ−1)×每分子含量。',
              style: AppText.caption.copyWith(color: AppColors.graphite),
            ),
            const SizedBox(height: 8),
            // v2.19.23 找茬 P2#3：两字段改竖排全宽——宽屏 rail 内容
            // 宽 248px，横排两个 Expanded 的 18 字标签被裁断。
            // v2.19.50：与下方「原料需求」那节的『复制代数 n』区分——
            // 同页两个同标签输入框学生分不清哪个 n 属于哪节（B 仓
            // v2.19.166 同款修法）。
            _field(_labelGenCtrl, '复制代数 n（标记分布用）', _calcLabel),
            _field(_matCtrl, '每分子某碱基含量 m（可留空跳过原料）', _calcLabel),
            _calcBtn('计算标记分布', _calcLabel),
          ],
        ),
      ),
      FlatSection(
        title: '有丝分裂染色体标记',
        subtitle: '常考',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '全部染色体 DNA 双链被标记后移入无标记培养基：第 1 次分裂'
              '子细胞全部带标记；第 2 次分裂后带标记 0~2n 条（随机）。'
              '对照：减数分裂只复制一次，4 个子细胞全含标记。',
              style: AppText.caption.copyWith(color: AppColors.graphite),
            ),
            const SizedBox(height: 8),
            _narrowField(
              _mit2nCtrl,
              '体细胞染色体数 2n（如玉米 20）',
              () => _calcMitosis(1),
            ),
            Wrap(
              spacing: 8,
              children: [
                _calcBtn('第 1 次分裂', () => _calcMitosis(1)),
                _calcBtn('第 2 次分裂', () => _calcMitosis(2)),
              ],
            ),
          ],
        ),
      ),
      FlatSection(
        title: 'DNA 复制原料计算',
        subtitle: '常考',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '1 个 DNA 复制 n 次，需游离的某种核苷酸 =(2ⁿ−1)×m'
              '（m=每分子该碱基个数）；第 n 次复制单需 2ⁿ⁻¹×m。',
              style: AppText.caption.copyWith(color: AppColors.graphite),
            ),
            const SizedBox(height: 8),
            // v2.19.23 找茬 P2#3：竖排全宽（同复制标记区）。
            _field(_matCtrl2, '每分子该碱基个数 m', _calcMat),
            _field(_matGenCtrl, '复制代数 n', _calcMat),
            _calcBtn('计算原料需求', _calcMat),
          ],
        ),
      ),
    ],
  );

  Widget _replicationBody(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _resultSection(
        title: 'DNA 半保留复制 · 结果',
        badge: '课标 3.1.3',
        ready: _repResult != null,
        error: _repError,
        results: _repResult == null
            ? null
            : [
                Text(
                  '2^${_repResult!.copies} = ${_repResult!.dnaMolecules} 个',
                  style: AppText.monoFigure,
                ),
                const SizedBox(height: 8),
                _kv('含亲代链的 DNA', '${_repResult!.withParentStrand} 个（半保留复制特征）'),
                _kv('新合成链数', '${_repResult!.newStrands} 条'),
                // v2.19.167：把 2ⁿ 个分子画成格阵，含亲代链的那几个点亮。
                // ⛔ 引擎只给**个数**、不给位置 ⇒ 图上取靠前的高亮格，
                //   并在图里明写这一点（见 semiconservative_grid.dart）。
                const SizedBox(height: 10),
                LayoutBuilder(
                  builder: (context, c) {
                    final reason = SemiconservativeGrid.skipReason(
                      _repResult,
                      c.maxWidth,
                    );
                    if (reason != null) {
                      return Text(
                        reason,
                        style: AppText.caption.copyWith(
                          color: AppColors.graphite,
                        ),
                      );
                    }
                    // v2.19.172（R54）：自绘图不吃 MediaQuery.textScaler ⇒
                    // 课堂档显式接全局倍率（标准档 1.0 = 基线零变化）。
                    return SemiconservativeGrid(
                      result: _repResult!,
                      textScale: PresentModeController.instance.enabled
                          ? PresentModeController.textScale
                          : 1.0,
                    );
                  },
                ),
              ],
      ),
      _resultSection(
        title: 'DNA 标记计算 · 结果',
        badge: '常考',
        ready: _labelResult != null,
        error: _labelError,
        results: _labelResult == null
            ? null
            : [
                StepChain(
                  steps: [
                    ChainStep.input(
                      '题干数据',
                      formula: '标记 DNA 移入无标记培养基，复制 n=${_labelGenCtrl.text} 代',
                    ),
                    ChainStep.compute(
                      '半保留复制',
                      detail: '亲代 2 条标记链各自守恒',
                      formula: 'DNA 分子 2^n=${_labelResult!.totalMolecules} 个',
                    ),
                    ChainStep.result(
                      '标记分布',
                      formula:
                          '含标记分子 ${_labelResult!.labeledMolecules} 个'
                          '（占 ${(_labelResult!.labeledMoleculeRatio * 100).toStringAsFixed(1)}%）；'
                          '标记链 ${_labelResult!.labeledStrands}/${_labelResult!.totalStrands} 条',
                      detail:
                          '全无标记分子 ${_labelResult!.unlabeledOnlyMolecules} 个；'
                          '${_labelResult!.centrifugeBands}',
                    ),
                  ],
                ),
                // v2.19.50：原料自己的错误**印在原料这件事的旁边**，
                // ⛔ 不再借用标记分布那节的错误位（那会把一节的限制
                // 说成另一节的）。
                if (_matError != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    _matError!,
                    style: AppText.caption.copyWith(color: AppColors.lethal),
                  ),
                ],
                if (_matResult != null) ...[
                  const SizedBox(height: 8),
                  _kv('原料总需求', '${_matResult!.totalNeeded} 个'),
                  _kv('第 n 次需求', '${_matResult!.lastRoundNeeded} 个'),
                ],
                // 离心管带型条图：一格 = 一个 DNA 分子，管内依次是
                // 重带、中带、轻带（纯 CustomPainter 代码绘制，⛔ 禁位图）。
                // ⛔ 重带**没有**独立的引擎字段，本图只放行
                //   「总分子 − 含亲代标记链 − 全无标记 = 0」的数据。
                // ⛔ 画不出来时把原因印在这里（数据闸 + 宽度闸 +
                //   容量闸），⛔ 零静默、不留空框 / 标题 / 占位。
                const SizedBox(height: 10),
                LayoutBuilder(
                  builder: (context, c) {
                    final reason = CentrifugeBandDiagram.skipReason(
                      _labelResult,
                      c.maxWidth,
                    );
                    if (reason != null) {
                      return Text(
                        reason,
                        style: AppText.caption.copyWith(
                          color: AppColors.graphite,
                        ),
                      );
                    }
                    // 本图是 TextPainter 自绘，不吃 MaterialApp.builder 注入
                    // 的 MediaQuery.textScaler（那条只作用于 Text widget）⇒
                    // 课堂档把全局倍率显式下传（标准档 1.0 = 逐像素零变化）。
                    return CentrifugeBandDiagram(
                      result: _labelResult!,
                      textScale: PresentModeController.instance.enabled
                          ? PresentModeController.textScale
                          : 1.0,
                    );
                  },
                ),
              ],
      ),
      _resultSection(
        title: '有丝分裂染色体标记 · 结果',
        badge: '常考',
        ready: _mitResult != null,
        error: _mitError,
        results: _mitResult == null
            ? null
            : [
                _kv('带标记染色体', _mitResult!.labeledChromosomes),
                if (_mitResult!.labeledChromatidsAtMetaphase != null)
                  _kv(
                    '中期标记单体',
                    '${_mitResult!.labeledChromatidsAtMetaphase} 条',
                  ),
                Text(
                  _mitResult!.mechanism,
                  style: AppText.caption.copyWith(color: AppColors.graphite),
                ),
              ],
      ),
      _resultSection(
        title: 'DNA 复制原料计算 · 结果',
        badge: '常考',
        ready: _mat2Result != null,
        error: _mat2Error,
        results: _mat2Result == null
            ? null
            : [
                StepChain(
                  steps: [
                    ChainStep.input(
                      '题干数据',
                      formula:
                          '每分子含该碱基 m=${_mat2Result!.perMolecule}，复制 n=${_mat2Result!.generations} 代',
                    ),
                    const ChainStep.compute(
                      '公式',
                      formula: '总量 =(2ⁿ−1)×m；第 n 次 = 2ⁿ⁻¹×m',
                      detail: '新增分子链才是原料消耗——亲代 2 条链守恒不耗原料',
                    ),
                    ChainStep.result(
                      '原料需求',
                      formula:
                          '共需 ${_mat2Result!.totalNeeded} 个；第 ${_mat2Result!.generations} 次需 ${_mat2Result!.lastRoundNeeded} 个',
                      detail: '若改问碱基对或全分子原料，先按比例换算 m',
                    ),
                  ],
                ),
              ],
      ),
    ],
  );

  // ─── Tab 3：基因表达（输入 + 结果）───

  Widget _expressionInputs(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      FlatSection(
        title: '基因表达 6:3:1',
        subtitle: '课标 3.1.4',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '基因（双链 DNA）碱基数 : mRNA 碱基数 : 氨基酸数 = 6 : 3 : 1。',
              style: AppText.caption.copyWith(color: AppColors.graphite),
            ),
            const SizedBox(height: 8),
            _narrowField(_aaCtrl, '氨基酸数（如 50）', _calcExpr),
            _calcBtn('计算各阶段碱基数', _calcExpr),
          ],
        ),
      ),
      FlatSection(
        title: '中心法则互推（模板链→mRNA→反密码子）',
        subtitle: '常考',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '给 DNA 模板链（按书写方向读作 3′→5′），推出编码链、mRNA、'
              '密码子与 tRNA 反密码子。长度须为 3 的倍数、≤30 bp。',
              style: AppText.caption.copyWith(color: AppColors.graphite),
            ),
            const SizedBox(height: 8),
            // 白板打字痛点：示例序列一键填入
            Wrap(
              spacing: 8,
              children: [
                ActionChip(
                  label: const Text('示例 TACGGATTA'),
                  onPressed: () {
                    _dogmaCtrl.text = 'TACGGATTA';
                    _calcDogma();
                  },
                ),
                ActionChip(
                  label: const Text('示例 TACCAT'),
                  onPressed: () {
                    _dogmaCtrl.text = 'TACCAT';
                    _calcDogma();
                  },
                ),
              ],
            ),
            const SizedBox(height: 6),
            _narrowField(_dogmaCtrl, '模板链序列（如 TACGGATTA）', _calcDogma),
            _calcBtn('推出各链', _calcDogma),
          ],
        ),
      ),
    ],
  );

  Widget _expressionBody(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _resultSection(
        title: '基因表达 6:3:1 · 结果',
        badge: '课标 3.1.4',
        ready: _exprResult != null,
        error: _exprError,
        results: _exprResult == null
            ? null
            : [
                Align(
                  alignment: Alignment.centerLeft,
                  child: RatioPill(text: '基因 : mRNA : 氨基酸 = 6 : 3 : 1'),
                ),
                const SizedBox(height: 8),
                _kv('mRNA 碱基数', '${_exprResult!.mrnaBases}'),
                _kv('基因碱基数（双链）', '${_exprResult!.geneBases}'),
              ],
      ),
      _resultSection(
        title: '中心法则互推 · 结果',
        badge: '常考',
        ready: _dogmaResult != null,
        error: _dogmaError,
        results: _dogmaResult == null
            ? null
            : [
                StepChain(
                  steps: [
                    ChainStep.input(
                      '模板链（3′→5′）',
                      formula: _dogmaResult!.template,
                    ),
                    ChainStep.compute(
                      '转录（互补，T→U）',
                      formula: 'mRNA：${_dogmaResult!.mrna}',
                      detail: '编码链：${_dogmaResult!.coding}',
                    ),
                    ChainStep.result(
                      '翻译配对',
                      formula: '密码子：${_dogmaResult!.codons.join('  ')}',
                      detail: '反密码子：${_dogmaResult!.anticodons.join('  ')}',
                    ),
                  ],
                ),
                // v2.19.46 「错因对照」创新：学生**忘了互补**、把模板链直接
                // 当 mRNA 读（T→U 就切）是转录题最高频失分点。模板链须先
                // **互补**（A→U、T→A、C↔G）才得 mRNA；直接 T→U 读是错的。
                // 这一行把「忘了互补」的错误密码子点名摆出来，与上面正确
                // 的密码子对照。⛔ 数据全来自引擎 `_dogmaResult.template`，
                // 一行算术都不另起（replaceAll + 3 位切片）。
                const SizedBox(height: 8),
                Builder(
                  builder: (_) {
                    final wrongMrna = _dogmaResult!.template.replaceAll(
                      'T',
                      'U',
                    );
                    final wrongCodons = <String>[
                      for (var i = 0; i + 3 <= wrongMrna.length; i += 3)
                        wrongMrna.substring(i, i + 3),
                    ];
                    return Text(
                      // ⛔ 文案里**不重贴正确密码子串**（如 'AUG  CCU  AAU'）：
                      //    下游测试按文字 finder 取「密码子：…」行，重贴会让
                      //    find.textContaining 一次命中两行（撞 v24_molecular）。
                      //    只摆**错误**密码子 + 点名「与上面正确的不同」即可。
                      '若忘了互补、把模板链直接当 mRNA 读，密码子会变成 '
                      '${wrongCodons.join('  ')}——与上面正确的密码子不同。'
                      '模板链先互补（A→U、T→A、C↔G）才得 mRNA。',
                      style: AppText.caption.copyWith(
                        color: AppColors.graphite,
                      ),
                    );
                  },
                ),
                // 「密码子：AUG  CCU  AAU」那两行里，密码子的边界只由两个
                // 空格承担 ⇒ 学生看不出「哪三个字母是一个密码子」。这张图把
                // 每个密码子画成一个正好圈住 3 个相邻 mRNA 碱基的框，框数由
                // `codons.length` 算出。⛔ 组件自己判「画不画得出」
                // （`DogmaStrandDiagram.canDraw`），画不出就整体收缩成
                // SizedBox.shrink，不留空框 / 标题 / 占位。
                const SizedBox(height: 12),
                // 自绘图（CustomPainter / TextPainter）不吃 MediaQuery
                // .textScaler ⇒ 课堂档把全局倍率**同时**接进 painter 与版面
                // 解算（标准档 1.0 = 逐像素零变化）。
                DogmaStrandDiagram(
                  result: _dogmaResult!,
                  textScale: PresentModeController.instance.enabled
                      ? PresentModeController.textScale
                      : 1.0,
                ),
              ],
      ),
    ],
  );

  // ─── Tab 4：配子种类（输入 + 结果）───

  Widget _gameteInputs(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      FlatSection(
        title: '减数分裂配子种类',
        subtitle: '课标 3.2.1',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'n 对同源染色体的生物，减数分裂可产生 2ⁿ 种配子'
              '（1 个精原细胞只产 2 种）。',
              style: AppText.caption.copyWith(color: AppColors.graphite),
            ),
            const SizedBox(height: 8),
            _narrowField(_pairCtrl, '染色体对数 n', _calcPair),
            _calcBtn('计算配子种类', _calcPair),
          ],
        ),
      ),
    ],
  );

  Widget _gameteBody(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _resultSection(
        title: '减数分裂配子种类 · 结果',
        badge: '课标 3.2.1',
        ready: _pairResult != null,
        error: _pairError,
        results: _pairResult == null
            ? null
            : [Text(_pairResult!, style: AppText.monoFigure)],
      ),
    ],
  );

  // ─── 展示 helper ───

  /// 结果分区：FlatSection 平铺（替代 v2.19.20 前的 _resultCard
  /// StepCard）。未计算 → 单行占位；错误 → lethal 横幅；就绪 → results。
  Widget _resultSection({
    required String title,
    String? badge,
    required bool ready,
    String? error,
    List<Widget>? results,
  }) {
    return FlatSection(
      title: title,
      // v2.19.59：算出结果 且 当前考点有配套卡 ⇒ 副标题位出 K 提示句；
      // 无结果 / 无卡（_linkedCardId 为 null）⇒ 整句不渲染。判据与宿主
      // cardId() 共用 _linkedCardId（同一个 findCardIdForTopic 调用链）。
      subtitle: ready && _linkedCardId != null ? _kCardLinkHint : null,
      trailing: badge == null ? null : AppChip(badge),
      child: error != null
          ? _errBanner(message: error)
          : (ready
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: results!,
                  )
                : _waitingPlaceholder()),
    );
  }

  Widget _waitingPlaceholder() => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(
          Icons.calculate_outlined,
          size: 18,
          color: AppColors.steel.withValues(alpha: 0.45),
        ),
        const SizedBox(width: 8),
        Text('等待计算：结果将在这里展开', style: AppText.caption),
      ],
    ),
  );

  /// 错误横幅：lethal 色圆角容器 + 图标。
  Widget _errBanner({required String message}) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: AppColors.lethal.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(AppTheme.radiusInput),
      border: Border.all(color: AppColors.lethal.withValues(alpha: 0.35)),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.error_outline_rounded, size: 18, color: AppColors.lethal),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            message,
            style: AppText.caption.copyWith(color: AppColors.lethal),
          ),
        ),
      ],
    ),
  );

  /// 比例/比值行：名称 + RatioPill 胶囊数值。
  Widget _pillRow(String label, String value) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Row(
      children: [
        Expanded(child: Text(label, style: AppText.caption)),
        RatioPill(text: value),
      ],
    ),
  );

  Widget _kv(String k, String v) => Padding(
    padding: const EdgeInsets.only(bottom: 4),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 168,
          child: Text(
            k,
            style: AppText.caption.copyWith(color: AppColors.graphite),
          ),
        ),
        Expanded(
          child: Text(
            v,
            style: AppText.body.copyWith(fontWeight: FontWeight.w600),
          ),
        ),
      ],
    ),
  );

  Widget _field(TextEditingController ctrl, String label, VoidCallback onDone) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: TextField(
        controller: ctrl,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: InputDecoration(
          isDense: true,
          labelText: label,
          counterText: '',
        ),
        onSubmitted: (_) => onDone(),
      ),
    );
  }

  /// 独立输入框限宽 240——这些字段只需输入一两位数字，通栏拉伸造成
  /// 右侧巨大空洞、视觉重心偏左。多字段并排场景仍用 Row+Expanded。
  Widget _narrowField(
    TextEditingController ctrl,
    String label,
    VoidCallback onDone,
  ) => ConstrainedBox(
    constraints: const BoxConstraints(maxWidth: 240),
    child: _field(ctrl, label, onDone),
  );

  Widget _calcBtn(String label, VoidCallback onTap) {
    return Align(
      alignment: Alignment.centerLeft,
      child: FilledButton.tonalIcon(
        onPressed: onTap,
        icon: const Icon(Icons.play_arrow_rounded, size: 18),
        label: Text(label),
        style: FilledButton.styleFrom(
          minimumSize: const Size(0, 36),
          padding: const EdgeInsets.symmetric(horizontal: 14),
        ),
      ),
    );
  }
}
