// evolution_page.dart —— 进化 · 基因频率（课标 4.1~4.2.5）
//
// 工具页：基因频率/基因型频率计算 + 哈迪-温伯格平衡检验与预测 +
// 自然选择（选择系数 s）逐代基因频率模拟 + 进化树先导图 + 进化理论
// 知识区。引擎：lib/engine/gene_frequency.dart。
//
// v2.19.21 工作台化（用户裁定：9331 布局语言推广到全计算器页）：
// 顶部 tab 导航（进化树 / 基因频率 / 遗传平衡 / 选择模拟 / 进化理论 /
// 种群增长），
// 宽屏 ≥1200 左侧常驻输入面板（ToolWorkbench 骨架，280px），
// 窄屏输入面板回渲染在结果区上方。

import 'package:flutter/material.dart';

import '../charts/evolution_chart.dart';
import '../charts/frequency_curve_chart.dart';
import '../data/big_question_cards.dart' show findCardIdForTopic;
import '../engine/gene_frequency.dart';
import '../theme.dart';
import '../ui/ai_chat_controller.dart';
import '../ui/assistant_panel.dart';
import '../ui/module_fill.dart';
import '../ui/tab_jump_shortcuts.dart';
import '../guide/guide_keys.dart';
import 'widgets/card_link_key_host.dart';
import 'widgets/cross_tool_rail.dart' show FlatSection;
import 'widgets/population_growth_lab.dart';
import 'widgets/save_mistake_key_host.dart';
import 'widgets/tool_workbench.dart';

class EvolutionPage extends StatefulWidget {
  const EvolutionPage(
      {super.key, this.navCollapsed = false, this.onNavPressed});

  /// 侧栏折叠联动（HomeShell 注入）；独立构造时不渲染 ☰。
  final bool navCollapsed;
  final VoidCallback? onNavPressed;

  @override
  State<EvolutionPage> createState() => _EvolutionPageState();
}

class _EvolutionPageState extends State<EvolutionPage>
    with TickerProviderStateMixin {
  // ── v2.19.32：出厂默认值（具名常量）────────────────────────────
  //
  // ⚠️ **常量是唯一真相**：controller 初始化与 `isPristine` 共用同一批常量
  // （本项目被「影子常量」坑过——重复定义 `_tabNames` 被 `dart analyze` 抓到，
  // 两个真相一定会分叉 ⇒ 一旦分叉，守卫会把出厂状态误判成 dirty）。
  static const _kDefaultAa = '10';
  static const _kDefaultAaHet = '60';
  static const _kDefaultAaDom = '30';
  static const _kDefaultP = '0.7';
  static const _kDefaultQ = '0.3';
  static const _kDefaultQ0 = '0.5';
  static const _kDefaultGens = '5';
  static const _kDefaultS = '1';

  final _aaCtrl = TextEditingController(text: _kDefaultAa);
  final _aACtrl = TextEditingController(text: _kDefaultAaHet);
  final _aACtrl2 = TextEditingController(text: _kDefaultAaDom);
  final _pCtrl = TextEditingController(text: _kDefaultP);
  final _qCtrl = TextEditingController(text: _kDefaultQ);
  final _q0Ctrl = TextEditingController(text: _kDefaultQ0);
  final _genCtrl = TextEditingController(text: _kDefaultGens);
  // v2.13：选择系数 s（aa 适合度 = 1−s），替代原二值「淘汰/无选择」开关——
  // s=1 完全淘汰（原默认）、s=0 无选择、中间值为教材「桦尺蛾」类部分选择。
  final _sCtrl = TextEditingController(text: _kDefaultS);

  GeneFrequencyResult? _freq;
  String? _freqError;
  // v2.19.53（找茬 D）：各节**算出那一刻的输入快照**。Ctrl+S 组装 payload
  // 时逐节比对现文——改动过未重算的节从题干/答案剔除（⛔ 不存「题干新
  // 输入 + 答案旧结果」的矛盾题，矛盾数据会喂给错题本 AI 错因归类）。
  String? _freqSnap;
  GeneFrequencyResult? _hw;
  String? _hwError;
  String? _hwSnap;
  SelectionSimResult? _sim;
  String? _simError;
  String? _simSnap;

  /// v2.19.21 工作台 tab（骨架外部持有 controller，避免 identical 短路）。
  late final TabController _tab;

  /// 第 6 页签「种群增长」的 State——输入与结果共用它一份真相。
  /// 父页经 GlobalKey 取两样东西：`isPristine`（深链覆盖守卫）与左栏
  /// 输入面板 `buildInputs`（见 widgets/population_growth_lab.dart 文件头）。
  final _growthKey = GlobalKey<PopulationGrowthLabState>();

  /// 该实验的状态版本号（⛔ 本页持有并 dispose，实验组件只自增）。
  /// 宽屏左栏副本先于 TabBarView 构建 ⇒ 首帧拿不到实验 State，靠它补一帧。
  final _growthRevision = ValueNotifier<int>(0);

  /// v2.19.32：这一页现在**还是出厂状态吗**（学生一个格子都没动过）？
  ///
  /// 供 `ModuleFillTarget.canOverwrite` 用：学生自己在进化页敲了题之后，
  /// 再从「考纲覆盖」/「大题套路卡」点深链，**不该把他那道题无声顶掉**。
  ///
  /// 判据 = **整页 6 个页签的全部输入框**都还等于出厂常量
  /// （多页签统一按整页判：任一页签被敲过就算 dirty）。
  /// 第 6 页签（种群增长）的五个输入在它自己的 State 里，未挂载时
  /// `?? true` = 视为出厂（与其它页签同一口径：没碰过就不算 dirty）。
  ///
  /// ⚠️ 判的是「有没有被学生动过」，不是「是不是空」。非空 ≠ dirty。
  /// ⚠️ 不看「有没有算过」（出厂状态也会自动算一次，那是它自己的默认题）。
  bool get isPristine =>
      _aaCtrl.text == _kDefaultAa &&
      _aACtrl.text == _kDefaultAaHet &&
      _aACtrl2.text == _kDefaultAaDom &&
      _pCtrl.text == _kDefaultP &&
      _qCtrl.text == _kDefaultQ &&
      _q0Ctrl.text == _kDefaultQ0 &&
      _genCtrl.text == _kDefaultGens &&
      _sCtrl.text == _kDefaultS &&
      (_growthKey.currentState?.isPristine ?? true);

  /// v2.19.32：`apply` 拒收本次参数时的**用户可见**反馈。
  ///
  /// 文案直接用总线给的 `reason`（`kModuleFillSkippedDirty`）；⛔ 不用
  /// 「你现在看到的是默认题」去解释「我们主动决定不写」，那是**假话**。
  /// ⚠️ 文案不含 markdown 星号（裸 `Text` 不解析），也不用方向词。
  void _onApplyFailed(String moduleId, String reason) {
    debugPrint('[evolution] 深链未写入：module=$moduleId reason=$reason');
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
      ..showSnackBar(SnackBar(
        content: Text(reason),
        duration: const Duration(seconds: 9),
      ));
  }

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 6, vsync: this);
    // v2.5 拍题识别填参路由：AI 识别出基因频率/哈迪温伯格题 → p/q 回填。
    ModuleFillBus.register(ModuleFillTarget(
      moduleId: 'evolution',
      pageIndex: 6, // 主导航「进化」页
      label: '进化页·基因频率',
      apply: (params) {
        // v2.19.23 找茬 P3#4：mounted 首行守卫（同分子页）。
        if (!mounted) return false;
        final p = double.tryParse(params['p']?.trim() ?? '');
        final q = double.tryParse(params['q']?.trim() ?? '');
        if (p == null && q == null) {
          // v2.19.25：套路卡深链——无 p/q 时仅切 tab（tab 参数 0..5，
          // 5 = 「种群增长」；tab 4 仍是「进化理论」）。
          final tab = int.tryParse(params['tab']?.trim() ?? '');
          if (tab != null && tab >= 0 && tab < 6) {
            _tab.animateTo(tab);
            return true;
          }
          return false;
        }
        if (p != null) _pCtrl.text = '$p';
        if (q != null) _qCtrl.text = '$q';
        _calcHw();
        // v2.19.21：结果在「遗传平衡」tab——切过去让用户直接看到。
        _tab.animateTo(2);
        return true;
      },
      // v2.19.32：进化页里已经有学生自己敲的题 ⇒ 深链**不覆盖**。
      canOverwrite: () => isPristine,
      onApplyFailed: _onApplyFailed,
    ));
  }

  @override
  void dispose() {
    ModuleFillBus.unregister('evolution');
    _tab.dispose();
    _growthRevision.dispose();
    for (final c in [_aaCtrl, _aACtrl, _aACtrl2, _pCtrl, _qCtrl, _q0Ctrl, _genCtrl, _sCtrl]) {
      c.dispose();
    }
    super.dispose();
  }

  // ─── 计算入口（引擎调用与 v2.19.20 前完全一致，零算法改动）───

  void _calcFreq() {
    try {
      final r = calcGeneFrequency(
        aa: int.tryParse(_aaCtrl.text.trim()) ?? 0,
        aA: int.tryParse(_aACtrl.text.trim()) ?? 0,
        AA: int.tryParse(_aACtrl2.text.trim()) ?? 0,
      );
      setState(() {
        _freq = r;
        _freqError = null;
        _freqSnap = '${_aaCtrl.text.trim()}|${_aACtrl.text.trim()}|'
            '${_aACtrl2.text.trim()}';
      });
    } on ArgumentError catch (e) {
      setState(() {
        _freq = null;
        _freqError = e.message?.toString() ?? '输入格式错误';
      });
    }
  }

  void _calcHw() {
    try {
      final r = hardyWeinbergPredict(
        p: double.tryParse(_pCtrl.text.trim()) ?? 0,
        q: double.tryParse(_qCtrl.text.trim()) ?? 0,
      );
      setState(() {
        _hw = r;
        _hwError = null;
        _hwSnap = '${_pCtrl.text.trim()}|${_qCtrl.text.trim()}';
      });
    } on ArgumentError catch (e) {
      setState(() {
        _hw = null;
        _hwError = e.message?.toString() ?? '输入格式错误';
      });
    }
  }

  void _calcSim() {
    // v2.13 评审修复：显式解析三参数——tryParse 失败置 _simError，
    // 不再静默降级（旧 ?? 0 会让非法 s 按 0 跑出「无选择→频率不变」，
    // 学生误读为哈迪-温伯格成立的假现象）。
    final q0 = double.tryParse(_q0Ctrl.text.trim());
    final gens = int.tryParse(_genCtrl.text.trim());
    final s = double.tryParse(_sCtrl.text.trim());
    if (q0 == null || gens == null || s == null) {
      setState(() {
        _sim = null;
        _simError = 'q₀、代数、s 都必须是数字（当前：q₀=${_q0Ctrl.text}、'
            '代数=${_genCtrl.text}、s=${_sCtrl.text}）';
      });
      return;
    }
    try {
      final r = simulateSelection(
        q0: q0,
        generations: gens,
        selectionAgainstAa: s,
      );
      setState(() {
        _sim = r;
        _simError = null;
        _simSnap = '${_q0Ctrl.text.trim()}|${_genCtrl.text.trim()}|'
            '${_sCtrl.text.trim()}';
      });
    } on ArgumentError catch (e) {
      setState(() {
        _sim = null;
        _simError = e.message?.toString() ?? '输入格式错误';
      });
    }
  }

  /// v2.13：教材/经典预设——一键填入 q0 / s / 代数（不自动开始模拟，
  /// 学生仍可先观察参数再点「开始模拟」，符合「输入→引擎→呈现」哲学）。
  void _applySimPreset(String q0, String s, String gens) {
    setState(() {
      _q0Ctrl.text = q0;
      _sCtrl.text = s;
      _genCtrl.text = gens;
    });
  }

  /// v2.13：按选择系数 s 分级给出「现象」解读。
  String _simInterpretation(double s) {
    if (s >= 1) {
      return '隐性纯合逐代被淘汰 → a 频率持续下降（选择使基因频率定向改变）';
    }
    if (s <= 0) {
      return '无选择 → 基因频率保持不变（哈迪-温伯格定律成立条件）';
    }
    return 'aa 适合度 1−s=${(1 - s).toStringAsFixed(2)} → 部分选择下 a 频率'
        '缓慢下降：选择压越弱，基因频率变化越慢（桦尺蛾这类经典场景）';
  }

  String _pct(double v) => '${(v * 100).toStringAsFixed(1)}%';

  void _calcAll() {
    _calcFreq();
    _calcHw();
    _calcSim();
    // 第 6 页签「种群增长」的输入在实验组件自己手里，一并重算
    // （未挂载时 currentState 为 null ⇒ 跳过；重算只按当前输入再算一遍，
    // ⛔ 不重置输入、不清空结果）。
    _growthKey.currentState?.recalc();
  }

  // ─── v2.19.51：Ctrl+S 存入错题本——题干/答案按下那一刻现组装 ───
  //
  // ⛔ 题干只写**已算出结果的那一节**的输入（屏上那一节的输入框），不把
  // 整页 8 个输入框全塞进去——那样题干会变成与当前这道题无关的噪音
  // （B 仓 v2.19.173 同款口径）。
  // ⛔ 屏上数字一律来自 controller 现文 / 引擎字段，一个都不许自编。

  // v2.19.53（找茬 D）：逐节「新鲜度」门——结果存在**且算出那一刻的
  // 输入快照与现文一致**才算数。学生改输入未重算时该节从题干/答案剔除，
  // ⛔ 不存「题干新输入 + 答案旧结果」的矛盾题（矛盾数据会喂给错题本
  // AI 错因归类）。全部节不新鲜 ⇒ 答案空串 ⇒ saveToMistakeBook 既有
  // 「先算出结果」守卫应答。
  bool get _freqFresh =>
      _freq != null &&
      _freqSnap ==
          '${_aaCtrl.text.trim()}|${_aACtrl.text.trim()}|'
              '${_aACtrl2.text.trim()}';
  bool get _hwFresh =>
      _hw != null &&
      _hwSnap == '${_pCtrl.text.trim()}|${_qCtrl.text.trim()}';
  bool get _simFresh =>
      _sim != null &&
      _simSnap ==
          '${_q0Ctrl.text.trim()}|${_genCtrl.text.trim()}|'
              '${_sCtrl.text.trim()}';

  /// 当前页签的考点标签（错题本筛选字段）。⛔ 每签一条课标，不共用一签。
  String get _mistakeSubjectArea {
    const areas = [
      '进化树（共同祖先·先导图）',
      '基因频率（按个体数计算）',
      '遗传平衡（哈迪-温伯格预测）',
      '选择模拟（自然选择逐代递推）',
      '进化理论（现代生物进化理论）',
      '种群增长（J 型与 S 型对照）',
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
  static const String _kCardLinkHint =
      '按 ${CardLinkKeyHost.keyLabel} 看这道题的套路卡';

  String get _mistakeStem {
    switch (_tab.index) {
      case 1:
        // 基因频率（按个体数）：输入 aa / Aa / AA 个体数。
        return _freqFresh
            ? '种群中 aa=${_aaCtrl.text.trim()}、Aa=${_aACtrl.text.trim()}、'
                'AA=${_aACtrl2.text.trim()} 个体数，求基因频率与基因型频率'
            : '';
      case 2:
        // 遗传平衡：输入 p / q → 预测下一代。
        return _hwFresh
            ? 'A 基因频率 p=${_pCtrl.text.trim()}、a 基因频率 q=${_qCtrl.text.trim()}，'
                '预测下一代基因型频率'
            : '';
      case 3:
        // 选择模拟：输入 q₀ / 代数 / 选择系数 s。
        return _simFresh
            ? '初始 a 频率 q₀=${_q0Ctrl.text.trim()}、'
                '选择系数 s=${_sCtrl.text.trim()}，'
                '模拟 ${_genCtrl.text.trim()} 代，求逐代基因频率变化'
            : '';
      default:
        return '';
    }
  }

  /// 答案全部取自引擎结果字段（GeneFrequencyResult / SelectionSimResult，
  /// 字段定义见 lib/engine/gene_frequency.dart），⛔ 一个数字都不自编。
  String get _mistakeAnswer {
    final parts = <String>[];
    switch (_tab.index) {
      case 1:
        final f = _freqFresh ? _freq : null;
        if (f != null) {
          parts.add('A=${_pct(f.freqA)}，a=${_pct(f.freqa)}；'
              'AA=${_pct(f.freqAA)}，Aa=${_pct(f.freqAa)}，aa=${_pct(f.freqaa)}；'
              '哈迪-温伯格${f.inEquilibrium ? '符合' : '偏离'}');
        }
      case 2:
        final h = _hwFresh ? _hw : null;
        if (h != null) {
          parts.add('AA=${_pct(h.freqAA)}，Aa=${_pct(h.freqAa)}，'
              'aa=${_pct(h.freqaa)}');
        }
      case 3:
        final s = _simFresh ? _sim : null;
        if (s != null) {
          parts.add('a 频率 F0=${_pct(s.qPerGen.first)} → '
              'F${s.qPerGen.length - 1}=${_pct(s.qPerGen.last)}'
              '（选择系数 s=${s.selectionS}）');
        }
      default:
        break;
    }
    return parts.join('；');
  }

  /// tab0（进化树）/ tab4（进化理论）是纯展示/知识区，没有计算器 ⇒
  /// 返回 null（闸④编造题干闸：给没有计算器的页签配题干是编造数据，
  /// 按了必须无声让路）；tab1~tab3「未算出结果」照常传空答案，由
  /// saveToMistakeBook 的「先算出结果，再存入错题本」守卫应答。
  ///
  /// tab5（种群增长）本轮**不接错题本**：它的题干/答案口径还没定稿，
  /// 与其编一段「模拟题」喂给错题本 AI，不如整签返回 null（无声让路）。
  ///
  /// srcModule 只给「遗传平衡」那一节：本页 ModuleFillBus 唯一的真 target
  /// 是 moduleId 'evolution'（回填 p/q + 切 tab2，见 initState）；tab1 基因
  /// 频率、tab3 选择模拟的输入没有可回填深链 ⇒ ⛔ 不传（传了错题本会出
  /// 现一枚点下去必然被拒的回程按钮）。
  SavePayload? _mistakePayload() {
    final i = _tab.index;
    if (i < 1 || i > 3) return null;
    final hwSaved = i == 2 && _hwFresh;
    return SavePayload(
      stem: _mistakeStem,
      correctAnswer: _mistakeAnswer,
      subjectArea: _mistakeSubjectArea,
      srcModule: hwSaved ? 'evolution' : null,
      srcParams: hwSaved
          ? {'p': _pCtrl.text.trim(), 'q': _qCtrl.text.trim()}
          : null,
    );
  }

  // ─── 工作台 tab 定义 ───

  List<WorkbenchTabSpec> _tabs() => [
        WorkbenchTabSpec(
          label: '进化树',
          icon: Icons.account_tree_outlined,
          sidePanel: _treeInputs,
          body: _treeBody,
        ),
        WorkbenchTabSpec(
          label: '基因频率',
          icon: Icons.percent_outlined,
          sidePanel: _freqInputs,
          body: _freqBody,
        ),
        WorkbenchTabSpec(
          label: '遗传平衡',
          icon: Icons.balance_outlined,
          sidePanel: _hwInputs,
          body: _hwBody,
        ),
        WorkbenchTabSpec(
          label: '选择模拟',
          icon: Icons.trending_down_outlined,
          sidePanel: _simInputs,
          body: _simBody,
        ),
        WorkbenchTabSpec(
          label: '进化理论',
          icon: Icons.menu_book_outlined,
          sidePanel: _theoryInputs,
          body: _theoryBody,
        ),
        // 第 6 页签「种群增长」：J 型 / S 型对照实验（独立 State，
        // 输入与结果共用一份真相，见 widgets/population_growth_lab.dart）。
        // 结果区直接挂组件（showInputs: false），输入由左栏副本承担；
        // ⛔ 不嵌套 TabBarView（body 在无界滚动区里，横向 viewport 会抛异常）。
        WorkbenchTabSpec(
          label: '种群增长',
          icon: Icons.show_chart_outlined,
          sidePanel: _growthInputs,
          body: (ctx) => PopulationGrowthLab(
            key: _growthKey,
            showInputs: false,
            revision: _growthRevision,
          ),
        ),
      ];

  @override
  Widget build(BuildContext context) {
    // v2.19.21 工作台化：顶部 tab + 宽屏左栏输入 / 右区结果。
    // v2.19.22：骨架 StatefulWidget（监听 TabController 刷新左栏），
    // 每次 build 新建实例；TabBar 由 buildWorkbenchTabBar 组装。
    final tabs = _tabs();
    return Scaffold(
      appBar: AppBar(
        leading: appNavButton(widget.onNavPressed),
        title: const Text('进化 · 基因频率'),
        // v2.19.23 找茬 P1#1：引导锚点挂在 TabBar 上（tab 无关、任何
        // tab 下都在树）。原挂法把 GuideKeys.evolutionFirst 放在 tab1
        // 首卡——默认 tab0 时 key 不在树，引导挖孔静默丢失。
        bottom: PreferredSize(
          key: GuideKeys.evolutionFirst,
          preferredSize: const Size.fromHeight(48),
          child: buildWorkbenchTabBar(_tab, tabs),
        ),
        actions: [
          TextButton.icon(
            onPressed: _calcAll,
            icon: const Icon(Icons.play_arrow, size: 18),
            label: const Text('全部计算'),
          ),
          // v2.1 问 AI：页面上下文随带（与系谱页同链路：queueSend + 侧栏）
          TextButton.icon(
            onPressed: () {
              AiChatController.instance.queueSend('【当前工具：进化 · 基因频率】基因/基因型频率计算 + 哈迪-温伯格平衡检验预测 + 自然选择淘汰模拟。当前输入：aa/Aa/AA 个体数 = ${_aaCtrl.text}/${_aACtrl.text}/${_aACtrl2.text}、p/q = ${_pCtrl.text}/${_qCtrl.text}、q0/代数 = ${_q0Ctrl.text}/${_genCtrl.text}。');
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
              railTitle: '进化 · 输入',
              railIcon: Icons.percent_outlined,
            ),
          ),
        ),
      ),
    );
  }

  // ─── Tab 0：进化树（纯展示，无计算）───

  Widget _treeInputs(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FlatSection(
            title: '生物进化树',
            subtitle: '课标 4.1 · 先导图',
            child: Text(
                '时间轴自上而下：共同祖先经世代分叉形成原核/真核、'
                '动物/植物等分支——节点越靠上代表越晚近的共同祖先。',
                style: AppText.caption.copyWith(color: AppColors.graphite)),
          ),
        ],
      );

  Widget _treeBody(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FlatSection(
            title: '生物进化树（先导图）',
            trailing: AppChip('课标 4.1'),
            child: EvolutionChart(
              nodes: [
                EvolutionNode(
                  id: 'root',
                  parent: null,
                  generation: 0,
                  trait: '共同祖先',
                ),
                EvolutionNode(
                  id: 'p1',
                  parent: 'root',
                  generation: 1,
                  trait: '原核生物',
                ),
                EvolutionNode(
                  id: 'e1',
                  parent: 'root',
                  generation: 1,
                  trait: '真核生物',
                ),
                EvolutionNode(
                  id: 'a1',
                  parent: 'e1',
                  generation: 2,
                  trait: '动物',
                ),
                EvolutionNode(
                  id: 'pl1',
                  parent: 'e1',
                  generation: 2,
                  trait: '植物',
                ),
                EvolutionNode(
                  id: 'v1',
                  parent: 'a1',
                  generation: 3,
                  trait: '脊椎动物',
                ),
              ],
            ),
          ),
        ],
      );

  // ─── Tab 1：基因频率（输入 + 结果）───

  Widget _freqInputs(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FlatSection(
            title: '基因频率计算（按个体数）',
            subtitle: '课标 4.2.1',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('已知种群中 aa / Aa / AA 个体数，求基因频率与基因型频率，'
                    '并检验是否符合哈迪-温伯格平衡。',
                    style: AppText.caption.copyWith(color: AppColors.graphite)),
                const SizedBox(height: 8),
                // v2.4 N4（题型矩阵 C3）：豆子模型/随机婚配预设——
                // 校卷题 4 型「容器内三种基因型个体若干 → 估算基因频率」，
                // 白板输入困难，一键载入免键盘。
                Wrap(spacing: 8, runSpacing: 4, children: [
                  for (final p in const [(30, 60, 10), (40, 40, 20), (25, 50, 25)])
                    ActionChip(
                      label: Text('预设 ${p.$1}/${p.$2}/${p.$3}'),
                      onPressed: () {
                        _aaCtrl.text = '${p.$1}';
                        _aACtrl.text = '${p.$2}';
                        _aACtrl2.text = '${p.$3}';
                        _calcFreq();
                      },
                    ),
                ]),
                const SizedBox(height: 8),
                _numField(_aaCtrl, '隐性纯合 aa 个体数', onDone: _calcFreq),
                _numField(_aACtrl, '杂合 Aa 个体数', onDone: _calcFreq),
                _numField(_aACtrl2, '显性纯合 AA 个体数', onDone: _calcFreq),
                _calcButton('计算基因频率', _calcFreq),
              ],
            ),
          ),
        ],
      );

  Widget _freqBody(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _resultSection(
            title: '基因频率计算 · 结果',
            badge: '课标 4.2.1',
            ready: _freq != null,
            error: _freqError,
            results: _freq == null
                ? null
                : [
                    _kv('基因频率', 'A = ${_pct(_freq!.freqA)}　a = ${_pct(_freq!.freqa)}'),
                    _kv('基因型频率',
                        'AA = ${_pct(_freq!.freqAA)}　Aa = ${_pct(_freq!.freqAa)}　aa = ${_pct(_freq!.freqaa)}'),
                    _kv(
                      '哈迪-温伯格平衡',
                      _freq!.inEquilibrium
                          ? '符合（实际≈p² / 2pq / q² 预测）'
                          : '偏离（实际基因型频率 ≠ p² / 2pq / q² 预测——'
                              '基因频率不变≠基因型频率不变，教学经典反例）',
                      highlight: !_freq!.inEquilibrium,
                    ),
                  ],
          ),
        ],
      );

  // ─── Tab 2：遗传平衡（输入 + 结果）───

  Widget _hwInputs(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FlatSection(
            title: '遗传平衡预测（p / q → 下一代）',
            subtitle: '课标 4.2.2',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('随机交配一代后达到哈迪-温伯格平衡：'
                    'AA:p²　Aa:2pq　aa:q²。',
                    style: AppText.caption.copyWith(color: AppColors.graphite)),
                const SizedBox(height: 8),
                _numField(_pCtrl, 'A 基因频率 p', onDone: _calcHw),
                _numField(_qCtrl, 'a 基因频率 q', onDone: _calcHw),
                _calcButton('预测下一代', _calcHw),
              ],
            ),
          ),
        ],
      );

  Widget _hwBody(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _resultSection(
            title: '遗传平衡预测 · 结果',
            badge: '课标 4.2.2',
            ready: _hw != null,
            error: _hwError,
            results: _hw == null
                ? null
                : [
                    _kv('预测基因型频率',
                        'AA = ${_pct(_hw!.freqAA)}　Aa = ${_pct(_hw!.freqAa)}　aa = ${_pct(_hw!.freqaa)}'),
                    _kv('说明', '随机交配一代后达到平衡：AA:p²　Aa:2pq　aa:q²'),
                  ],
          ),
        ],
      );

  // ─── Tab 3：自然选择模拟（输入 + 结果）───

  Widget _simInputs(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FlatSection(
            title: '自然选择模拟（逐代基因频率）',
            subtitle: '课标 4.2.2 / 4.2.3',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('初始 a 频率 q₀、代数、选择系数 s（aa 适合度 = 1−s），'
                    '逐代递推基因频率并画出折线。',
                    style: AppText.caption.copyWith(color: AppColors.graphite)),
                const SizedBox(height: 8),
                _numField(_q0Ctrl, '初始 a 基因频率 q₀', onDone: _calcSim),
                _numField(_genCtrl, '代数（1–40）', onDone: _calcSim),
                _numField(_sCtrl, '选择系数 s（0–1）', onDone: _calcSim),
                // v2.13 预设 chips：经典/教材场景一键填参（不自动开始，
                // 学生先读参数再点「开始模拟」——输入→引擎→呈现哲学）。
                Wrap(spacing: 8, runSpacing: 4, children: [
                  ActionChip(
                    label: const Text('完全淘汰（经典）'),
                    onPressed: () => _applySimPreset('0.5', '1', '5'),
                  ),
                  ActionChip(
                    label: const Text('无选择'),
                    onPressed: () => _applySimPreset('0.5', '0', '5'),
                  ),
                  // 教材必修2 p.121-122 桦尺蛾：黑色(S)+10%/年、浅色(s)−10%/年
                  // → 相对适合度 w(aa) = 0.9/1.1 → s = 2/11 ≈ 0.18；q0 = 浅色
                  // 频率 0.8。教材按表型增减简化计数（首年 S=23%），本引擎
                  // 为标准适合度递推（首年 S≈22.7%），差异在解读里说明。
                  ActionChip(
                    label: const Text('课本·桦尺蛾'),
                    onPressed: () => _applySimPreset('0.8', '0.18', '10'),
                  ),
                ]),
                const SizedBox(height: 4),
                _calcButton('开始模拟', _calcSim),
              ],
            ),
          ),
        ],
      );

  Widget _simBody(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _resultSection(
            title: '自然选择模拟 · 结果',
            badge: '课标 4.2.2 / 4.2.3',
            ready: _sim != null,
            error: _simError,
            results: _sim == null
                ? null
                : [
                    // v2.13：逐代频率折线图（替代纯文字扫读，课堂演示向）。
                    FrequencyCurveChart(
                      series: [
                        FreqSeries(
                            label: 'a 频率',
                            values: _sim!.qPerGen,
                            color: AppColors.sand),
                        FreqSeries(
                            label: 'A 频率',
                            values: _sim!.pPerGen,
                            color: AppColors.teal),
                      ],
                    ),
                    const SizedBox(height: 8),
                    _kv(
                      '逐代 a 基因频率',
                      _sim!.qPerGen
                          .asMap()
                          .entries
                          .take(16)
                          .map((e) => 'F${e.key} = ${(e.value * 100).toStringAsFixed(1)}%')
                          .join('　'),
                    ),
                    _kv('现象', _simInterpretation(_sim!.selectionS)),
                    if (_sim!.selectionS > 0 && _sim!.selectionS < 1)
                      _kv(
                        '课本对照',
                        '课本桦尺蛾例题按「表型个体数增减 10%」简化计数（首年'
                        '显性表型 S=23%）；本引擎为标准适合度递推 w(aa)=1−s'
                        '（首年显性频率≈${_pct(_sim!.pPerGen[1])}）——'
                        '两种算法都属合理简化，趋势一致：选择压使基因频率定向改变',
                      ),
                  ],
          ),
        ],
      );

  // ─── Tab 4：进化理论（纯知识区）───

  Widget _theoryInputs(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FlatSection(
            title: '知识速览',
            subtitle: '课标 4.1 ~ 4.2.5',
            child: Text('本区平铺三块考点：共同祖先的证据 / 现代生物进化理论 / '
                '物种形成——配合前四个 tab 的计算器使用。',
                style: AppText.caption.copyWith(color: AppColors.graphite)),
          ),
        ],
      );

  Widget _theoryBody(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FlatSection(
            title: '共同祖先的证据',
            trailing: AppChip('课标 4.1.1 / 4.1.2'),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _kv('化石证据', '化石是研究生物进化最直接、最重要的证据——越古老的地层，生物越简单、越低等'),
                _kv('比较解剖学', '同源器官（蝙蝠翼/鲸鳍/人上肢骨骼排列一致）来自共同祖先'),
                _kv('胚胎学证据', '脊椎动物早期胚胎都有鳃裂和尾，支持共同由来'),
                _kv('细胞与分子', '所有生物共用遗传密码、细胞色素 c 同源——DNA/新陈代谢共同特征'),
              ],
            ),
          ),
          FlatSection(
            title: '现代生物进化理论',
            trailing: AppChip('课标 4.2.4'),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _kv('核心', '自然选择学说为核心：过度繁殖→生存斗争→遗传变异→适者生存'),
                _kv('种群', '生物进化的基本单位是种群，进化的实质是种群基因频率的定向改变'),
                _kv('原材料', '突变（基因突变+染色体变异）和基因重组产生进化的原材料（不定向）'),
                _kv('方向', '自然选择决定进化方向（定向选择），使基因频率定向改变'),
              ],
            ),
          ),
          FlatSection(
            title: '物种形成',
            trailing: AppChip('课标 4.2.5'),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _kv('三步环节', '①突变和基因重组（原材料）→ ②自然选择（基因频率定向改变）→ ③隔离（必要条件）'),
                _kv('隔离类型', '地理隔离：阻断基因交流；生殖隔离：不能交配或后代不育——新物种形成标志'),
                _kv('常见方式', '地理隔离（长期）→ 生殖隔离 → 新物种；多倍体可直接一步形成新物种（如四倍体）'),
              ],
            ),
          ),
        ],
      );

  // ─── Tab 5：种群增长（独立实验组件；左栏 = 它的输入面板副本）───

  /// 左栏输入：实验 State 未挂载时（宽屏首帧）先渲染空占位，
  /// 由 [_growthRevision] 在挂载后补一帧；同一份 State ⇒ 输入与结果不打架。
  Widget _growthInputs(BuildContext context) => ValueListenableBuilder<int>(
        valueListenable: _growthRevision,
        builder: (_, _, _) =>
            _growthKey.currentState?.buildInputs(context) ??
            const SizedBox.shrink(),
      );

  // ─── 展示 helper ───

  /// 结果分区：FlatSection 平铺（替代 v2.19.20 前的 _sectionCard
  /// StepCard 输入+结果合体）。未计算 → 单行占位；错误 → lethal 文本。
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
          ? _errText(error)
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
            Icon(Icons.calculate_outlined,
                size: 18, color: AppColors.steel.withValues(alpha: 0.45)),
            const SizedBox(width: 8),
            Text('等待计算：结果将在这里展开',
                style: AppText.caption),
          ],
        ),
      );

  Widget _numField(TextEditingController ctrl, String label,
      {required VoidCallback onDone}) {
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

  Widget _calcButton(String label, VoidCallback onTap) {
    return Align(
      alignment: Alignment.centerLeft,
      child: FilledButton.icon(
        onPressed: onTap,
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

  Widget _kv(String label, String value, {bool highlight = false}) {
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
            child: Text(value,
                style: (highlight ? AppText.caption : AppText.body)
                    .copyWith(
                        color: highlight ? AppColors.lethal : AppColors.ink,
                        fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }
}
