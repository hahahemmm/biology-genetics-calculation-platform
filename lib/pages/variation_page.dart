// variation_page.dart —— 变异模块（课标 3.3.1~3.3.5）
//
// 基因突变模拟（3.3.1/3.3.2：替换/插入/缺失 → 序列 + 密码子影响）、
// 染色体组数判断（3.3.5）、染色体结构变异速览（3.3.5）、诱变因素
// （3.3.3）、育种方法对照（3.3.4）。窄屏友好：滚动表单 + 常驻结果。
// 引擎：lib/engine/mutation_engine.dart。全键盘可达（onSubmitted 联动）。

import 'package:flutter/material.dart';

import '../engine/mutation_engine.dart';
import '../state/present_mode_controller.dart';
import '../theme.dart';
import '../ui/ai_chat_controller.dart';
import '../ui/assistant_panel.dart';
import '../ui/module_fill.dart';
import '../ui/tab_jump_shortcuts.dart';
import 'widgets/mutation_diff_diagram.dart';
import 'widgets/calculation_empty_state.dart';
import 'widgets/save_mistake_key_host.dart';
import 'widgets/tool_workbench.dart';

/// 染色体结构变异速览条目（纯展示，课标 3.3.5）。
class _StructuralVariant {
  final String name;
  final String def;
  final String example;
  const _StructuralVariant(
      {required this.name, required this.def, required this.example});
}

const _structuralVariants = [
  _StructuralVariant(
      name: '缺失',
      def: '染色体某片段丢失，其上基因随之缺失',
      example: '猫叫综合征（5 号染色体短臂缺失）'),
  _StructuralVariant(
      name: '重复',
      def: '染色体某片段增加，基因数目增多',
      example: '果蝇棒眼（X 染色体 16A 区段重复）'),
  _StructuralVariant(
      name: '倒位',
      def: '染色体某片段颠倒 180° 后重新接合',
      example: '果蝇 X 染色体倒位（位置效应）'),
  _StructuralVariant(
      name: '易位',
      def: '非同源染色体间片段互换位置',
      example: '慢性粒细胞白血病（9/22 号染色体易位，费城染色体）'),
];

/// 育种方法对照条目（纯展示，课标 3.3.4）。
class _BreedingMethod {
  final String name;
  final String principle;
  final String prosCons;
  const _BreedingMethod(
      {required this.name, required this.principle, required this.prosCons});
}

const _breedingMethods = [
  _BreedingMethod(
      name: '杂交育种',
      principle: '基因重组：杂交使不同亲本的优良性状组合到子代',
      prosCons: '操作简单、目的性强；但周期长，后代需多代自交筛选'),
  _BreedingMethod(
      name: '诱变育种',
      principle: '基因突变：用射线/化学诱变剂提高突变率',
      prosCons: '能提高变异频率、加速育种进程；但突变不定向，需大量筛选'),
  _BreedingMethod(
      name: '单倍体育种',
      principle: '染色体（数目）变异：花药离体培养后秋水仙素加倍',
      prosCons: '后代全是纯合子、明显缩短育种年限；但技术复杂，需与杂交结合'),
  _BreedingMethod(
      name: '多倍体育种',
      principle: '染色体（数目）变异：秋水仙素抑制纺锤体形成、染色体不减半',
      prosCons: '器官大、营养丰富、抗逆性强；但结实率低、发育迟缓'),
];

class VariationPage extends StatefulWidget {
  const VariationPage(
      {super.key,
      this.navCollapsed = false,
      this.onNavPressed,
      this.sourceLabel});

  /// v2.20.0：HomeShell 的导航面板折叠态（与系谱/9331/图谱页同源）。
  ///
  /// 本页没有「随 ☰ 折叠的本地面板」——布局是 ToolWorkbench（宽屏左
  /// 输入栏 / 窄屏输入回渲染顶部），输入栏不在折叠范围内（用户裁定：
  /// 折叠只收控制类面板，输入栏必须常驻可用）。故本参数当前**不改变
  /// 像素**，只为与同族工作台页（evolution/home/settings 等）保持同一
  /// 构造签名，并由 HomeShell 统一注入——避免「有的页收得到全局状态、
  /// 有的页收不到」再次出现。默认 false ⇒ 独立构造（测试/嵌入）行为不变。
  final bool navCollapsed;

  final VoidCallback? onNavPressed;

  /// v2.19.30（M3.1 老师 P2-3）：push 来源页名（如「课标」）——非主导航
  /// 页被 push 后无返回线索，顶部给回程细条；null 不渲染。
  final String? sourceLabel;

  @override
  State<VariationPage> createState() => _VariationPageState();
}

class _VariationPageState extends State<VariationPage>
    with TickerProviderStateMixin {
  /// v2.19.28 工作台化：4 个 tab 的 TabController（本 State 持有，
  /// 骨架每 build 新建实例——identical 短路纪律）。
  late final TabController _tab;

  /// v2.19.35：「基因突变」页签的**出厂默认题**（判 `canOverwrite` 的锚点）。
  /// ⛔ 提为**具名常量**并让 controller 初始化复用它：两份字面量迟早分叉，
  /// 那一轮 `isPristine` 就会把「刚出厂的页」误判成 dirty ⇒ 深链被无理由
  /// 拒掉，而屏上看不出原因（本项目被影子常量坑过，系谱页/分子页同款）。
  static const _kDefaultMutSequence = 'ATGCCGTA';
  static const _kDefaultMutPosition = '2';
  static const _kDefaultMutType = '替换';

  final _seqCtrl = TextEditingController(text: _kDefaultMutSequence);
  final _posCtrl = TextEditingController(text: _kDefaultMutPosition);
  final _genoCtrl = TextEditingController(text: 'AaaBbb');
  String _mutType = _kDefaultMutType; // 替换 / 插入 / 缺失

  /// v2.19.35：本实例注册的那一枚 `gene_mutation` target（dispose 时按身份
  /// 比对，只摘自己那一份——见 dispose 注释里的双实例覆盖事故）。
  ModuleFillTarget? _geneMutation;

  /// v2.12 拍题识别填参：被高亮的结构变异条目名（缺失/重复/倒位/易位）。
  /// null = 不高亮（默认）。
  String? _highlightVariant;

  /// v2.12：每个结构变异条目挂的 GlobalKey，用于 Scrollable.ensureVisible
  /// 滚动到目标条目（拍题识别后自动定位）。
  final Map<String, GlobalKey> _variantKeys = {
    for (final v in _structuralVariants) v.name: GlobalKey(),
  };

  // v2.19.53（找茬 D）：各节**算出那一刻的输入快照**。Ctrl+S 组装 payload
  // 时逐节比对现文——改动过未重算的节从题干/答案剔除（⛔ 不存「题干新
  // 输入 + 答案旧结果」的矛盾题，矛盾数据会喂给错题本 AI 错因归类）。
  // tab0 的输入除两个框还有突变类型开关 _mutType（直接喂引擎、题干里也
  // 渲染它）⇒ 一并入快照（照倍性页「框+开关」先例）：只拨开关不重算同样
  // 算 stale。
  MutatedSequence? _mutResult;
  String? _mutError;
  String? _mutSnap;
  int? _setsResult;
  String? _setsError;
  String? _setsSnap;

  static const _typeToEngine = {'替换': 'sub', '插入': 'ins', '缺失': 'del'};

  /// 「基因突变」这一栏现在**还是出厂状态吗**（没人动过）？
  ///
  /// 供 `ModuleFillTarget.canOverwrite` 用：学生自己在这一栏敲了题之后，
  /// 课标 chip 的深链**不覆盖**（深链的语义是「带我去看看那一栏」，覆盖掉
  /// 他正在做的题是不该的）。⛔ 不用 initState 快照——「进页面之前是什么样」
  /// 判不出来，判据只能是**当前值 vs 出厂常量**。
  /// ⛔ 判据只覆盖「基因突变」这一栏的三个输入：另外三栏（组数/结构/育种）
  /// 与本 target 无关，学生在那边敲的东西不该拦下这边的课标深链。
  bool get isPristine =>
      _seqCtrl.text == _kDefaultMutSequence &&
      _posCtrl.text == _kDefaultMutPosition &&
      _mutType == _kDefaultMutType;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 4, vsync: this);
    // v2.12 拍题识别填参路由：AI 识别出染色体结构变异题 → 高亮对应条目。
    // v2.19.32 P1 修复：target 已上移至应用级 registerAppLevelModuleTargets()
    // （main.dart）常驻注册，不再随页面实例注册/注销——旧实现里拍题 push 出的
    // 第二个实例 dispose 时会注销全局 target，导致再次拍题深链返回 false。
    // 页面实例只负责消费 push 前入队的 params / actions（push 后页面才构建）。
    //
    // v2.12 修复 (VerB2 P0)：拍题识别走 fillScan（AI 返回 actions 不带 params）
    // 时，actions 入队 `_pendingActions` 而非 `_pendingFills`，老代码只消费
    // `_pendingFills` → actions 永远不被消费，是死数据。修复：params 缺失时
    // 退一步消费 `_pendingActions`，把 `highlight_variant` action 转译成 params
    // 再走原有 apply 路径。
    final pending = ModuleFillBus.consumePending('cross_chromosomal_struct');
    Map<String, String>? appliedParams;
    if (pending != null && pending.isNotEmpty) {
      appliedParams = pending;
    } else {
      // 拍题识别走 fillScan（AI 返回 actions 不带 params）时，
      // `_pendingFills` 留下空 map `{}`——`pending != null` 走不进 else；
      // 需 `isNotEmpty` 才认作有效 params，否则继续消费 actions。
      final pendingActions =
          ModuleFillBus.consumePendingActions('cross_chromosomal_struct');
      if (pendingActions.isNotEmpty) {
        final first = pendingActions.first;
        if (first['type'] == 'highlight_variant') {
          final variant = first['variant']?.trim();
          if (variant != null && variant.isNotEmpty) {
            appliedParams = {'variant': variant};
          }
        }
      }
    }
    if (appliedParams != null) {
      // initState 阶段 widget 还未挂载，延迟到首帧后再高亮/滚动。
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _applyChromosomalStruct(appliedParams!);
      });
    }
    // v2.19.35（课标 → 工具**正向**深链）：本页 tab 0「基因突变」一直装着
    // 真正的计算器（`_calcMut` → `mutateSequence` = 突变后序列 + 受影响密码子
    // + 同义/错义判定），只是**没注册**进 `ModuleFillBus` ⇒ 课标 3.3.1 /
    // 3.3.2 的 chip 跳不过去。本轮补上这一枚 target。
    //
    // 生命周期：与 `cross_*` / `ploidy` / `evolution` 那批**页内** target 同款
    // ——initState 注册、dispose 注销。⛔ 不学 `cross_chromosomal_struct` 那样
    // 上移 App 级常驻：那是拍题 FAB 挂在 HomeShell 上的需求，而本 target 唯一
    // 的调用方是**课标页**（主导航的一页），深链走 `navigator(9)` 切到的正是
    // 主导航里这份**同一个**实例 ⇒ 跟实例走已经够，且不污染全局注册表。
    // v2.19.60：变异页导航位次由 11 前移到 9（设置/关于挪去末位）。
    _geneMutation = ModuleFillTarget(
      moduleId: 'gene_mutation',
      pageIndex: 9, // 主导航「变异」页
      label: '变异页·基因突变',
      apply: _applyGeneMutation,
      canOverwrite: () => isPristine,
      onApplyFailed: _onApplyFailed,
    );
    ModuleFillBus.register(_geneMutation!);
    // ⛔ 本页**不挂** `Alt+K`（课标聚焦快捷键）：本页唯一可反查的两枚
    // moduleId 都是**多义**——`gene_mutation` 被 3.3.1 + 3.3.2 同时点名，
    // `cross_chromosomal_struct` 被 3.3.1/3.3.2/3.3.3/3.3.5 点名 ⇒
    // `curriculumReverseCodeOf` 一律返 null（挑一条挂上就是编造对应关系，
    // 且学生在屏上看不出差别）。宿主 `CurriculumFocusShortcuts` 见到 null
    // 压根不绑这一键，所以「不绑」是机制保证，不靠各页自觉。
  }

  @override
  void dispose() {
    _tab.dispose();
    // v2.19.32 P1：target 为应用级常驻注册（见 initState 注释），
    // 页面 dispose 不得注销——否则拍题 push 实例 pop 后全局深链失效。
    // ⛔ 但 `gene_mutation` 是**页内** target（initState 注册），必须在这里
    // 注销——否则页面销毁后全局注册表里留一枚幽灵 target，`fill` 照样返 true
    // 却打在已不存在的 State 上（与 `cross_*` 那批同款纪律）。
    //
    // ⚠️ 但**只注销自己那一份**：同一个 moduleId 可能同时挂着两个实例的注册
    // （主导航那份 + 课标 chip push 出来的那份，后者的 initState 会覆盖前者）。
    // 若这份先被 pop，它一注销就把**主导航实例**的 target 一起带走 ⇒ 之后
    // 3.3.1/3.3.6 的深链静默失效（`fill` 返 false，屏上零提示）。
    // ⇒ 比对身份，只摘自己那份（`identical` 是这里唯一正确的判据）。
    if (identical(ModuleFillBus.targetOf('gene_mutation'), _geneMutation)) {
      ModuleFillBus.unregister('gene_mutation');
    }
    for (final c in [_seqCtrl, _posCtrl, _genoCtrl]) {
      c.dispose();
    }
    super.dispose();
  }

  /// v2.19.35：`apply` 拒收本次参数时的**用户可见**反馈。
  ///
  /// ⛔ 只加闸不提示 = 学生看到「点了没反应」，那比被顶掉更难排查。文案直接用
  /// 总线给的 `reason`（拒收 = `kModuleFillSkippedDirty` 原句、校验没过 =
  /// 另一句），本方法不替总线猜原因。⚠️ 文案里**不许出现 markdown 星号**
  /// （裸 `Text` 不解析，星号会原样上屏）。
  void _onApplyFailed(String moduleId, String reason) {
    debugPrint('[gene_mutation] 深链未写入：module=$moduleId reason=$reason');
    if (!mounted) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;
    // 先换掉再 show：不 hide 的话连发只有第一条能看见。
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(reason),
        duration: const Duration(seconds: 9),
      ));
  }

  /// v2.12 拍题识别：设高亮条目 + 滚动到位。
  /// params 支持两种字段：`variant`（缺失/重复/倒位/易位）为主，
  /// 也兼容 `name` 字段（与 variant 同义）。
  bool _applyChromosomalStruct(Map<String, String> params) {
    final variant = (params['variant'] ?? params['name'])?.trim();
    if (variant == null || variant.isEmpty) return false;
    // 校验：必须是 4 种结构变异之一
    if (!_variantKeys.containsKey(variant)) return false;
    setState(() {
      _highlightVariant = variant;
    });
    // v2.19.28 工作台化：条目在「结构变异」tab（index 2）——先切 tab，
    // 等骨架 rebuild 后再滚动到对应条目（首屏外才有效）。
    _tab.animateTo(2);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final key = _variantKeys[variant];
      final ctx = key?.currentContext;
      if (ctx != null) {
        Scrollable.ensureVisible(
          ctx,
          duration: const Duration(milliseconds: 280),
          alignment: 0.15,
          curve: Curves.easeOutCubic,
        );
      }
    });
    return true;
  }

  /// v2.19.35：课标深链填参——`{sequence, type, position}`。
  ///
  /// ## 参数键以**本仓页内校验器**为准（⛔ 不按别的仓的字段名想当然）
  ///  · `sequence`：只允许 A/T/G/C（大小写不敏感）——由引擎判；
  ///  · `type`：**页面 ChoiceChip 的原文**三选一（替换 / 插入 / 缺失），
  ///    经 [_typeToEngine] 映射成引擎的 sub/ins/del。⛔ 不接受 `'sub'` 这类
  ///    引擎内部值：页面上没有那个选项，填进去等于「参数收到了但类型没变」，
  ///    而学生在屏上**看不出**哪里不对；
  ///  · `position`：0 起点整数（替换/缺失 ∈ [0, len-1]，插入 ∈ [0, len]，
  ///    等于 len 表示末尾追加）——越界由引擎判。
  ///
  /// ## 校验 = [_calcMut] 的**同款**引擎调用，但**先探后写**
  /// 先拿引擎探一次（非法序列 / 位置越界在这里就 `return false`），过了才写
  /// 输入框 ⇒ 拒收时屏上不会留下填了一半的值（那比一句报错更难排查）。
  bool _applyGeneMutation(Map<String, String> params) {
    if (!mounted) return false;
    final sequence = params['sequence']?.trim() ?? '';
    final type = params['type']?.trim() ?? '';
    final positionText = params['position']?.trim() ?? '';
    final position = int.tryParse(positionText);
    final engineType = _typeToEngine[type];
    if (position == null || engineType == null) return false;
    try {
      // 探针：与 _calcMut 同一个引擎入口、同样的异常语义（ArgumentError）。
      mutateSequence(sequence: sequence, type: engineType, position: position);
    } on ArgumentError {
      return false;
    }
    _seqCtrl.text = sequence;
    _posCtrl.text = positionText;
    setState(() => _mutType = type);
    // 「基因突变」是出厂第 0 栏，仍显式写一次：将来若在前面插栏，本行不会
    // 跟着错（与 `_applyChromosomalStruct` 里 `animateTo(2)` 同一纪律）。
    _tab.animateTo(0);
    _calcMut();
    return _mutError == null;
  }

  void _calcMut() {
    try {
      final pos = int.tryParse(_posCtrl.text.trim());
      if (pos == null) throw ArgumentError('请输入位置（数字）');
      final r = mutateSequence(
        sequence: _seqCtrl.text,
        type: _typeToEngine[_mutType]!,
        position: pos,
      );
      setState(() {
        _mutResult = r;
        _mutError = null;
        // v2.19.53：序列|位置|突变类型开关 '|' 拼快照（基因突变节）。
        _mutSnap =
            '${_seqCtrl.text.trim()}|${_posCtrl.text.trim()}|$_mutType';
      });
    } on ArgumentError catch (e) {
      setState(() {
        _mutResult = null;
        _mutError = e.message?.toString() ?? '输入格式错误';
      });
    }
  }

  void _calcSets() {
    try {
      final n = chromosomeSets(genotype: _genoCtrl.text);
      setState(() {
        _setsResult = n;
        _setsError = null;
        _setsSnap = _genoCtrl.text.trim();
      });
    } on ArgumentError catch (e) {
      setState(() {
        _setsResult = null;
        _setsError = e.message?.toString() ?? '输入格式错误';
      });
    }
  }

  /// 示例基因型点选即算：同时回填输入框，保证所见即所得。
  void _calcSetsFor(String genotype) {
    _genoCtrl.text = genotype;
    _calcSets();
  }

  String _ploidyName(int n) {
    switch (n) {
      case 1:
        return '单倍体';
      case 2:
        return '二倍体';
      case 3:
        return '三倍体';
      case 4:
        return '四倍体';
      default:
        return '多倍体';
    }
  }

  // ─── v2.19.51：Ctrl+S 存入错题本——题干/答案按下那一刻现组装 ───
  //
  // ⛔ 题干只写**已算出结果的那一节**的输入（屏上那一节的输入框），不把
  // 整页 4 个页签的输入全塞进去——那样题干会变成与当前这道题无关的噪音
  // （B 仓 v2.19.173 同款口径）。
  // ⛔ 屏上数字一律来自 controller 现文 / 引擎字段，一个都不许自编。

  // v2.19.53（找茬 D）：逐节「新鲜度」门——结果存在**且算出那一刻的
  // 输入快照与现文一致**才算数。学生改输入未重算时该节从题干/答案剔除，
  // ⛔ 不存「题干新输入 + 答案旧结果」的矛盾题（矛盾数据会喂给错题本
  // AI 错因归类）。全部节不新鲜 ⇒ 答案空串 ⇒ saveToMistakeBook 既有
  // 「先算出结果」守卫应答。
  bool get _mutFresh =>
      _mutResult != null &&
      _mutSnap ==
          '${_seqCtrl.text.trim()}|${_posCtrl.text.trim()}|$_mutType';
  bool get _setsFresh =>
      _setsResult != null && _setsSnap == _genoCtrl.text.trim();

  /// 当前页签的考点标签（错题本筛选字段）。⛔ 四签四条课标，不共用一签。
  String get _mistakeSubjectArea {
    const areas = [
      '基因突变模拟（碱基替换/插入/缺失）',
      '染色体组数判断（基因型法）',
      '染色体结构变异（缺失/重复/倒位/易位）',
      '诱变因素与育种方法',
    ];
    final i = _tab.index;
    return i >= 0 && i < areas.length ? areas[i] : areas.first;
  }

  String get _mistakeStem {
    switch (_tab.index) {
      case 0:
        // 基因突变模拟：输入序列 / 突变类型 / 位置（0 起点）。
        return _mutFresh
            ? 'DNA 序列 ${_seqCtrl.text.trim()}、突变类型 $_mutType、'
                '位置 ${_posCtrl.text.trim()}（0 起点），模拟基因突变'
            : '';
      case 1:
        // 染色体组数判断：输入基因型。
        return _setsFresh
            ? '基因型 ${_genoCtrl.text.trim()}，求染色体组数'
            : '';
      default:
        return '';
    }
  }

  /// 答案全部取自引擎结果字段（MutatedSequence / chromosomeSets 返回值，
  /// 定义见 lib/engine/mutation_engine.dart），⛔ 一个数字都不自编。
  String get _mistakeAnswer {
    switch (_tab.index) {
      case 0:
        final r = _mutFresh ? _mutResult : null;
        if (r == null) return '';
        return '突变类型 ${r.type}（位置 ${r.position}），原序列 ${r.original} → '
            '突变后序列 ${r.mutated}；受影响密码子 ${r.originalCodon} → '
            '${r.mutatedCodon}（第 ${r.codonIndex + 1} 个密码子），'
            '${r.silent ? '同义突变（氨基酸不变）' : '可能改变氨基酸（错义/无义突变）'}';
      case 1:
        final n = _setsFresh ? _setsResult : null;
        if (n == null) return '';
        return '$n 个染色体组（${_ploidyName(n)}）';
      default:
        return '';
    }
  }

  /// tab2（结构变异）/ tab3（诱变与育种）是纯展示/知识区，没有计算器 ⇒
  /// 返回 null（闸④编造题干闸：给没有计算器的页签配题干是编造数据，
  /// 按了必须无声让路）；tab0/tab1「未算出结果」照常传空答案，由
  /// saveToMistakeBook 的「先算出结果，再存入错题本」守卫应答。
  ///
  /// srcModule 只给「基因突变」那一节：本页 ModuleFillBus 唯一的真 target
  /// 是 moduleId 'gene_mutation'（initState 注册，apply=_applyGeneMutation：
  /// 引擎探针校验后真实回填 _seqCtrl/_posCtrl/_mutType 并 _calcMut 重算，
  /// 参数键 sequence/type/position）；tab1 染色体组数的 _genoCtrl 没有任何
  /// target 能回填（'cross_chromosomal_struct' 只高亮结构变异条目，那一签
  /// 又没有计算器）⇒ ⛔ 不传（传了错题本会出现一枚点下去必然被拒/落错签
  /// 的回程按钮）。
  /// v2.19.53：srcModule/srcParams 受「基因突变」节的新鲜度门——stale
  /// （改输入/拨开关未重算）时不传回程，错题本不会出现「参数是新的、
  /// 答案却是旧的」的错回程（照分子页 dogmaSaved 先例）。
  SavePayload? _mistakePayload() {
    final i = _tab.index;
    if (i < 0 || i > 1) return null;
    final mutSaved = i == 0 && _mutFresh;
    return SavePayload(
      stem: _mistakeStem,
      correctAnswer: _mistakeAnswer,
      subjectArea: _mistakeSubjectArea,
      srcModule: mutSaved ? 'gene_mutation' : null,
      srcParams: mutSaved
          ? {
              'sequence': _seqCtrl.text.trim(),
              'type': _mutType,
              'position': _posCtrl.text.trim(),
            }
          : null,
    );
  }

  List<WorkbenchTabSpec> _tabs() => [
        WorkbenchTabSpec(
          label: '基因突变',
          icon: Icons.change_circle_outlined,
          sidePanel: _mutationInputs,
          body: _mutationBody,
        ),
        WorkbenchTabSpec(
          label: '染色体组数',
          icon: Icons.format_list_numbered,
          sidePanel: _setsInputs,
          body: _setsBody,
        ),
        WorkbenchTabSpec(
          label: '结构变异',
          icon: Icons.broken_image_outlined,
          sidePanel: _structuralSide,
          body: _structuralBody,
        ),
        WorkbenchTabSpec(
          label: '诱变与育种',
          icon: Icons.eco_outlined,
          sidePanel: _breedingSide,
          body: _breedingBody,
        ),
      ];

  @override
  Widget build(BuildContext context) {
    // v2.19.28 UI 统一：废弃 5 个 _sectionCard 纵向堆叠，接入
    // ToolWorkbench（与分子/进化/倍性同款骨架）——顶部 tab 分工具，
    // 宽屏 ≥1200 左栏输入 / 右区结果，窄屏面板回渲染结果上方。
    final tabs = _tabs();
    return Scaffold(
      appBar: AppBar(
        leading: appNavButton(widget.onNavPressed),
        title: const Text('变异'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: buildWorkbenchTabBar(_tab, tabs),
        ),
        actions: [
          // v2.1 问 AI：页面上下文随带（与系谱页同链路：queueSend + 侧栏）
          TextButton.icon(
            onPressed: () {
              AiChatController.instance.queueSend('【当前工具：变异】基因突变模拟（替换/插入/缺失）、染色体组数判断。当前输入：序列 ${_seqCtrl.text} / 类型 $_mutType / 位置 ${_posCtrl.text}。');
              showAiAssistant(context);
            },
            icon: Icon(Icons.psychology_outlined,
                size: 18, color: AppColors.teal),
            label: Text('问 AI',
                style: TextStyle(
                    color: AppColors.teal, fontWeight: FontWeight.w600)),
          ),
          const SizedBox(width: 8),
        ],
      ),
      // v2.19.49：Alt+数字 页签直跳宿主（零像素，只切页签不碰题面；
      // 让路闸见 lib/ui/tab_jump_shortcuts.dart 文件头）。包在整个 body 上
      // （含 push 来源回程细条），宿主与路由同生命周期。
      // v2.19.51：Ctrl+S 存当前题进错题本（页面级唯一宿主；payload 是
      // 按下那一刻现取的 ValueGetter ⇒ ToolWorkbench 切页签不让本 State
      // rebuild 也没有过期窗，B 仓 v2.19.173 抓的 stale-capture 病由构造
      // 不存在；闸见 save_mistake_key_host.dart 文件头）。
      body: SaveMistakeKeyHost(
        payload: _mistakePayload,
        child: TabJumpShortcuts(
          tab: _tab,
          child: Column(
            children: [
              // v2.19.30（M3.1 老师 P2-3）：push 来源回程细条（与 HomeShell
              // 「来自…·点击返回…」同款语言）。
              if (widget.sourceLabel != null)
                GestureDetector(
                  onTap: () => Navigator.of(context).maybePop(),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 6),
                    decoration: BoxDecoration(
                      border: Border(
                          bottom: BorderSide(color: AppColors.border)),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.arrow_back,
                            size: 15, color: AppColors.teal),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '来自${widget.sourceLabel} · 点击返回',
                            style: AppText.caption
                                .copyWith(color: AppColors.ink),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              Expanded(
                child: ToolWorkbench(
                  controller: _tab,
                  tabs: tabs,
                  railTitle: '变异 · 输入',
                  railIcon: Icons.change_circle_outlined,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ─── Tab 1：基因突变模拟 ───

  Widget _mutationInputs(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('碱基的替换、插入或缺失会引发基因中碱基序列的改变'
            '（密码子框从序列起点起，每 3 个碱基一个密码子）。',
            style: AppText.caption),
        const SizedBox(height: 8),
        _dnaField(_seqCtrl, 'DNA 序列（仅 A/T/G/C）', _calcMut),
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Wrap(
            spacing: 8,
            children: [
              for (final t in _typeToEngine.keys)
                ChoiceChip(
                  label: Text(t),
                  selected: _mutType == t,
                  onSelected: (_) => setState(() => _mutType = t),
                ),
            ],
          ),
        ),
        _numField(_posCtrl, '突变位置（0 起点，数字）', _calcMut),
        _calcButton('模拟突变', _calcMut),
      ],
    );
  }

  Widget _mutationBody(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // v2.19.29（M3.1 老师 P1-2）：课标编号锚点（改造随 StepCard
        // 丢失，与分子页 FlatSection 徽标同款）。
        const Row(
          children: [AppChip('课标 3.3.1')],
        ),
        const SizedBox(height: 8),
        if (_mutError != null) _errText(_mutError!),
        if (_mutResult != null)
          _mutResultCard(_mutResult!)
        else if (_mutError == null)
          const CalculationEmptyState(
            icon: Icons.change_circle_outlined,
            title: '等待模拟：结果将在这里展开',
            description: '左侧已给出 DNA 序列与突变位置。选择替换、插入或缺失后点「模拟突变」，这里显示突变前后序列与密码子差异。',
          ),
      ],
    );
  }

  // ─── Tab 2：染色体组数判断 ───

  Widget _setsInputs(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('同一基因座（同字母、不分大小写）上的等位基因总数 = 染色体组数：'
            '含 1 套为二倍体（Aa）、2 套为四倍体（AAaa）等。',
            style: AppText.caption),
        const SizedBox(height: 8),
        TextField(
          key: const Key('genotypeField'),
          controller: _genoCtrl,
          style: AppText.genotype,
          decoration: const InputDecoration(
            isDense: true,
            labelText: '基因型（字母表等位基因，不分大小写）',
            counterText: '',
          ),
          onSubmitted: (_) => _calcSets(),
        ),
        const SizedBox(height: 8),
        _calcButton('判断染色体组数', _calcSets),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final g in ['Aa', 'AaaBbb', 'AAAaBBbb', 'ABCD'])
              ActionChip(
                label: Text('$g → ${chromosomeSets(genotype: g)}',
                    style: AppText.genotype.copyWith(fontSize: 12)),
                onPressed: () => _calcSetsFor(g),
              ),
          ],
        ),
      ],
    );
  }

  Widget _setsBody(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Row(
          children: [AppChip('课标 3.3.5')],
        ),
        const SizedBox(height: 8),
        if (_setsError != null) _errText(_setsError!),
        if (_setsResult != null)
          _kv('染色体组数',
              '$_setsResult 个染色体组（${_ploidyName(_setsResult!)}）',
              mono: true)
        else if (_setsError == null)
          const CalculationEmptyState(
            icon: Icons.bubble_chart_outlined,
            title: '等待判断：结果将在这里展开',
            description: '输入基因型，或点左侧示例。这里按同字母（不分大小写）的数量给出染色体组数与倍性名称。',
          ),
      ],
    );
  }

  // ─── Tab 3：染色体结构变异速览（纯展示 + 拍题高亮） ───

  Widget _structuralSide(BuildContext context) {
    return Text('染色体某区段发生缺失 / 重复 / 倒位 / 易位，多数对生物不利，'
        '甚至致死。', style: AppText.caption);
  }

  Widget _structuralBody(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final v in _structuralVariants)
          Container(
            key: _variantKeys[v.name],
            margin: const EdgeInsets.only(bottom: 8),
            padding: _highlightVariant == v.name
                ? const EdgeInsets.symmetric(horizontal: 8, vertical: 6)
                : EdgeInsets.zero,
            decoration: _highlightVariant == v.name
                ? BoxDecoration(
                    color: AppColors.tealWash,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.teal, width: 1.5),
                  )
                : null,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 52,
                  child: Text(v.name,
                      style: AppText.label.copyWith(
                          color: AppColors.teal,
                          fontWeight: _highlightVariant == v.name
                              ? FontWeight.w800
                              : FontWeight.w600)),
                ),
                Expanded(
                  child: Text('${v.def}　——　${v.example}',
                      style: AppText.body.copyWith(
                          fontWeight: _highlightVariant == v.name
                              ? FontWeight.w600
                              : FontWeight.w400)),
                ),
              ],
            ),
          ),
      ],
    );
  }

  // ─── Tab 4：诱变因素 + 育种方法对照（纯展示） ───

  Widget _breedingSide(BuildContext context) {
    return Text('某些化学物质、射线以及病毒可提高基因突变概率；'
        '可遗传变异（基因重组 / 基因突变 / 染色体变异）是育种的原材料。',
        style: AppText.caption);
  }

  Widget _breedingBody(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('诱变因素', style: AppText.sectionTitle),
        const SizedBox(height: 6),
        Text('某些基因突变可导致细胞分裂失控，甚至发生癌变（课标 3.3.3）。',
            style: AppText.caption),
        const SizedBox(height: 8),
        for (final cat in ['物理', '化学', '生物']) ...[
          Padding(
            padding: const EdgeInsets.only(top: 4, bottom: 6),
            child: Text(cat,
                style: AppText.label.copyWith(color: AppColors.teal)),
          ),
          for (final f in mutationFactors.where((f) => f.category == cat))
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 88,
                    child: Text(f.factor,
                        style: AppText.body
                            .copyWith(fontWeight: FontWeight.w600)),
                  ),
                  Expanded(child: Text(f.note, style: AppText.caption)),
                ],
              ),
            ),
        ],
        const SizedBox(height: 18),
        Text('育种方法对照', style: AppText.sectionTitle),
        const SizedBox(height: 6),
        const Divider(height: 16),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(width: 88, child: Text('方法', style: AppText.caption)),
            Expanded(flex: 3, child: Text('原理', style: AppText.caption)),
            Expanded(flex: 4, child: Text('优缺点', style: AppText.caption)),
          ],
        ),
        const SizedBox(height: 4),
        for (final b in _breedingMethods)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 88,
                  child: Text(b.name,
                      style: AppText.label.copyWith(color: AppColors.teal)),
                ),
                Expanded(
                  flex: 3,
                  child: Text(b.principle, style: AppText.body),
                ),
                Expanded(flex: 4, child: Text(b.prosCons, style: AppText.caption)),
              ],
            ),
          ),
      ],
    );
  }

  // ── 基因突变结果卡（border-top 文档流分隔，非卡片）─────────────
  Widget _mutResultCard(MutatedSequence r) {
    final highlightStart = (r.codonIndex * 3).clamp(0, r.mutated.length);
    final highlightLen = (r.codonIndex * 3 + 3)
        .clamp(0, r.mutated.length)
        .toInt() - highlightStart;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 6),
      padding: const EdgeInsets.only(top: 10),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _kv('突变类型', '${r.type}（位置 ${r.position}）'),
          _kv('原序列', r.original, mono: true),
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                    width: 108, child: Text('突变后序列', style: AppText.caption)),
                Expanded(
                  child: Text.rich(
                    TextSpan(
                      style: AppText.genotype,
                      children: [
                        if (highlightStart > 0)
                          TextSpan(
                              text:
                                  r.mutated.substring(0, highlightStart)),
                        TextSpan(
                          text: r.mutated.substring(
                              highlightStart, highlightStart + highlightLen),
                          style: TextStyle(
                            color: AppColors.tealDark,
                            backgroundColor: AppColors.tealWash,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        if (highlightStart + highlightLen < r.mutated.length)
                          TextSpan(
                              text: r.mutated.substring(highlightStart +
                                  highlightLen)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          _kv('受影响密码子',
              '${r.originalCodon} → ${r.mutatedCodon}（第 ${r.codonIndex + 1} 个密码子）',
              mono: true),
          // v2.19.163：密码子框对照图（代码绘制）。挂点是**平级兄弟**——
          // 排在「受影响密码子」那一行之后，⛔ 不塞进任何一行里。
          // ⛔ 组件内部自带可画性闸门：不可画时收缩成 SizedBox.shrink，
          //    屏上不留空框 / 标题 / 占位（`_mutResult == null` 时本组件根本
          //    不会被构建，见本方法调用处）。
          MutationDiffDiagram(
              // 课堂档显式接全局倍率（标准档 1.0 = 基线零变化）。
              result: r,
              textScale: PresentModeController.instance.enabled
                  ? PresentModeController.textScale
                  : 1.0),
          _kv('结果判定',
              r.silent
                  ? '同义突变（氨基酸不变）'
                  : '可能改变氨基酸（错义/无义突变）',
              highlight: !r.silent),
          Text('碱基序列改变 → 所编码蛋白质及细胞功能可能改变，甚至致命'
              '（课标 3.3.2）。', style: AppText.caption),
        ],
      ),
    );
  }

  // ── 通用构件（沿用 molecular/evolution 页写法）─────────────────
  Widget _dnaField(
      TextEditingController ctrl, String label, VoidCallback onDone) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: TextField(
        controller: ctrl,
        style: AppText.genotype,
        decoration: InputDecoration(
            isDense: true, labelText: label, counterText: ''),
        onSubmitted: (_) => onDone(),
      ),
    );
  }

  Widget _numField(
      TextEditingController ctrl, String label, VoidCallback onDone) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: TextField(
        controller: ctrl,
        keyboardType: const TextInputType.numberWithOptions(decimal: false),
        decoration: InputDecoration(
            isDense: true, labelText: label, counterText: ''),
        onSubmitted: (_) => onDone(),
      ),
    );
  }

  Widget _calcButton(String label, VoidCallback onTap) {
    return Align(
      alignment: Alignment.centerLeft,
      child: FilledButton.icon(
        // v2.19.29（M3.1 学生 N-P1-5）：先收键盘再算（窄态结果在
        // 输入面板下方，不收键盘结果看不到）。
        onPressed: () {
          FocusManager.instance.primaryFocus?.unfocus();
          onTap();
        },
        icon: const Icon(Icons.calculate_outlined, size: 18),
        label: Text(label),
        style: FilledButton.styleFrom(
          minimumSize: const Size(0, 38),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        ),
      ),
    );
  }

  Widget _errText(String msg) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(msg,
            style: AppText.caption.copyWith(color: AppColors.lethal)),
      );

  Widget _kv(String label, String value,
      {bool mono = false, bool highlight = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 108,
            child: Text(label, style: AppText.caption),
          ),
          Expanded(
            child: Text(
              value,
              style: (mono
                      ? AppText.genotype
                      : highlight
                          ? AppText.caption
                          : AppText.body)
                  .copyWith(
                color: highlight ? AppColors.lethal : AppColors.ink,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}