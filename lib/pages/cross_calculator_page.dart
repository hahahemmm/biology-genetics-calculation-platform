import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/big_question_cards.dart';
import '../engine/kaoji_calc.dart';
import '../engine/error_diagnosis.dart';
import '../engine/reverse_engine.dart';
import '../engine/variant_spec.dart';
import '../guide/guide_keys.dart';
import '../state/app_state.dart';
import '../state/history_store.dart';
import '../state/mistake_book.dart';
import '../state/mistake_book_exporter_stub.dart'
    if (dart.library.html) '../state/mistake_book_exporter_web.dart'
    as webimpl;
import '../theme.dart';
import '../ui/ai_fill_params.dart';
import '../ui/assistant_panel.dart';
import '../ui/cross_board.dart';
import '../ui/cross_pedigree_link.dart';
import '../ui/module_fill.dart';
import '../ui/png_export.dart';
import '../ui/step_card.dart';
import '../ui/tab_jump_shortcuts.dart';
import 'curriculum_page.dart';
import 'widgets/card_link_key_host.dart';
import 'widgets/method_compare_tab.dart';
import 'widgets/linkage_tab.dart';
import 'widgets/cross_tool_rail.dart';
import 'widgets/mono_cross_widget.dart';
import 'widgets/save_mistake_key_host.dart';
import 'widgets/save_to_mistake_book.dart';
import 'widgets/tool_workbench.dart' show kWorkbenchCompactWidth;
import 'widgets/random_mating_tab.dart';
import 'widgets/sex_linked_tab.dart';

/// v2.19.59：9331 七个计算面的**考点常量**——「K 看这道题的套路卡」的
/// 唯一判据源，同时也是「存入错题本」写进 `subjectArea` 的同一份。
///
/// ⛔ 每个考点字面量**只有这一处定义**（B 仓 v2.19.249 教训：同一字面量
/// 同时决定「键认不认领」与「屏上印不印」，两处各写一份迟早分叉——屏上
/// 印着提示而按键不认，或印着一枚按不动的键）。
/// · 双基因 / 三对基因 / 自由交配三个面共用「自由组合定律」（本文件定义）；
/// · 单基因面在 `mono_cross_widget.dart`（`kMonoCrossSubjectArea`）；
/// · 伴性面在 `sex_linked_tab.dart`（`kSexLinkedSubjectArea`）。
/// · 方法对比 / 连锁互换两个面**没有**「存入错题本」口径（读源码确认：
///   两页无 SavePayload / 无 subjectArea）⇒ 无考点 ⇒ 无卡，按 K 无声让路
///   （⛔ 不许替它们编一个考点）。
const String kFreeCombinationSubjectArea = '自由组合定律';

/// v2.19.59：结果区副标题尾注（屏上文案，⛔ 只有这一处定义）。
/// 尾注的渲染闸是「有结果 && 考点有配套卡」；K 宿主的判据只有「考点有
/// 配套卡」一道（套路卡是学习材料，没算出结果先去看卡是合法动线，B 仓
/// v2.19.245 原始语义）——提示印得出 ⇒ 键必跳；提示没印 ⇏ 键不应答。
const String kCardKeyHint = ' · 按 K 看这道题的套路卡';

/// v2.19.59：考点 → 配套卡 id。**本文件唯一一处** `findCardIdForTopic`
/// 调用——按键宿主（[CardLinkKeyHost] 的 cardId）与各结果区副标题尾注都
/// 从这里走，两处不可能分叉（A5 源码级守卫钉的就是这一条）。
/// 顶层函数（不是某个 State 的私有方法）：本页三个 State（容器 + 单/双基因
/// 两个页签 State）都要用它，挂在某一个 State 上另一个就够不着。
String? _cardIdForTopic(String? topic) =>
    topic == null ? null : findCardIdForTopic(topic);

/// v2.19.59：结果区副标题的套路卡尾注（null = 这一面没有配套卡 ⇒ 不加）。
String? _cardHintForTopic(String topic) =>
    _cardIdForTopic(topic) == null ? null : kCardKeyHint;

/// 有结果那一支副标题 + 尾注（无配套卡 ⇒ 原句逐字不变）。
String _withCardHint(String subtitle, String topic) {
  final hint = _cardHintForTopic(topic);
  return hint == null ? subtitle : '$subtitle$hint';
}

/// 遗传计算器容器页：七个 Tab。
///   Tab 1：双基因 9331 计算器（及变式速查）—— UI 重做样板页（步骤流程卡）
///   Tab 2：三对基因（8×8 棋盘，27:9:9:9:3:3:3:1）—— v2.5
///   Tab 3：单基因杂交 / 测交 / 回交 / 修饰模型
///   Tab 4：伴 X 遗传（交叉遗传 / 条件概率）
///   Tab 5：分解法 vs 配子法（方法论对比）
///   Tab 6：连锁互换
///   Tab 7：自由交配
class CrossCalculatorPage extends StatefulWidget {
  const CrossCalculatorPage({
    super.key,
    this.navCollapsed = false,
    this.onNavPressed,
  });

  /// v3.3 侧栏折叠联动（HomeShell 注入）；独立构造时不渲染 ☰。
  final bool navCollapsed;
  final VoidCallback? onNavPressed;

  @override
  State<CrossCalculatorPage> createState() => _CrossCalculatorPageState();
}

class _CrossCalculatorPageState extends State<CrossCalculatorPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tab = TabController(length: 7, vsync: this);

  // v2.5 拍题识别填参路由：AI 识别出杂交题 → 切到对应 tab 并回填亲本。
  final _diKey = GlobalKey<_Dihybrid9331TabState>();
  final _triKey = GlobalKey<_TrihybridTabState>();
  // v2.14 R5：单基因/伴性 tab 的 fill 直达 key（讲题回放补齐：
  // 两个 tab 也做成 ▷ 可复现）。
  final _monoKey = GlobalKey<MonoCrossWidgetState>();
  final _sexKey = GlobalKey<SexLinkedTabState>();
  // v2.15：方法对比 tab 的 fill 直达 key（讲题回放 ▷ 复现补齐）。
  final _mcKey = GlobalKey<MethodCompareTabState>();
  // v2.15：连锁互换 tab 的 fill 直达 key（p1/p2/r 三参回填）。
  final _linkKey = GlobalKey<LinkageTabState>();
  // v2.19.22：自由交配 tab 的 rail 输入面板 key（_currentSidePanel
  // case 6 取 State 注入左栏——v2.19.18 接入协议但容器页漏挂，
  // 切到该 tab 左栏输入面板消失）。
  final _rmKey = GlobalKey<RandomMatingTabState>();
  // 路由填参先于目标 tab 挂载到达时的待填槽（tab initState 消费）。
  ({String p1, String p2})? pendingDi;
  ({String p1, String p2})? pendingTri;
  ({String p1, String p2})? pendingMono;
  ({String p1, String p2})? pendingSex;
  ({String p1, String p2})? pendingMc;
  ({String p1, String p2, String r})? pendingLink;
  // v2.19.39：自由交配 tab 的待填槽（`rows` 行走串，整份 params 原样传）。
  Map<String, String>? pendingRm;

  // v2.6 ☰ 工具抽屉：本页 Scaffold key + 会话级计算历史（新→旧，≤20 条）。
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  final List<({int tab, String p1, String p2, String ratio})> _history = [];

  /// tab 计算成功后登记历史（同组合去重置顶）。
  void recordHistory(int tab, String p1, String p2, String ratio) {
    _history.removeWhere((h) => h.tab == tab && h.p1 == p1 && h.p2 == p2);
    _history.insert(0, (tab: tab, p1: p1, p2: p2, ratio: ratio));
    if (_history.length > 20) _history.removeLast();
    // v2.19.16 工作台化：宽屏侧栏常驻后历史列表始终在屏——登记即
    // setState 刷新（原抽屉版靠 openDrawer 前 setState 顺带刷新，
    // rail 常驻无此契机；mounted 守卫防 dispose 后回调）。
    if (mounted) setState(() {});
    // v2.13+ 老师走查 P0：内存历史同步落盘到 HistoryStore——
    // 此前只有系谱页写历史，dashboard 讲题回放卡对计算器是空头支票
    // （老师用最多的工具不产生回放记录）。fire-and-forget；
    // revision++ 触发回放卡自动刷新。
    // detail 存结构化 JSON（{'m': moduleId, 'p1':.., 'p2':..}）——
    // 回放卡点按可复现（ModuleFillBus 跳计算器 + 回填 + 即算）。
    HistoryStore.append(
      HistoryEntry(
        label: '$p1 × $p2 · ${_tabNames[tab]} · 表型 $ratio',
        epochMs: DateTime.now().millisecondsSinceEpoch,
        detail: jsonEncode({
          'm': tab == 0 ? 'cross_dihybrid' : 'cross_trihybrid',
          'p1': p1,
          'p2': p2,
        }),
      ),
    );
  }

  static const _tabNames = [
    '双基因 9331',
    '三对基因',
    '单基因杂交',
    '伴性遗传',
    '方法对比',
    '连锁互换',
    '自由交配',
  ];

  /// v2.19.35：**页签下标 → `ModuleFillBus` moduleId**，次序与上面那份
  /// `_tabNames` 一一对应，也与本 State 里那 7 次 `ModuleFillBus.register`
  /// 的次序同源（双基因/三对基因/单基因/伴性/方法对比/连锁/自由交配）。
  ///
  /// ⛔ 它**不是**一张新的课标对照表：只回答「这一栏是哪个 moduleId」，
  /// 课标 code 一律由 `curriculumReverseCodeOf` 从既有反向表反查
  /// （见 `curriculum_page.dart` 的 `CurriculumFocusShortcuts`）。
  /// ⇒ 方法对比（tab 4）与自由交配（tab 6）没被任何课标点名 ⇒ 反查 null ⇒
  /// `Alt+K` 在那两栏**不绑**（宁可不给，也不给错）。
  static const _tabModuleIds = [
    'cross_dihybrid',
    'cross_trihybrid',
    'cross_mono',
    'cross_sex_linked',
    'cross_method_compare',
    'cross_linkage',
    'cross_random_mating',
  ];

  /// v2.19.23 找茬 P1#4：按 index 差分即刻重建（与 ToolWorkbench 骨架
  /// 同款）。原 `!indexIsChanging` 守卫吞掉动画开始时 index 已变的那次
  /// 通知——300ms 动画期内左栏仍是旧 tab 面板且可点击/可输入。
  int _lastRailIndex = -1;

  void _onRailTabChanged() {
    if (!mounted) return;
    final i = _tab.index;
    if (i != _lastRailIndex) {
      AppState.instance.setModule(_tabNames[i]);
      setState(() => _lastRailIndex = i);
      // 目标 tab 懒构建：index 变化通知到达时 TabBarView 可能尚未挂载
      // 目标 State（GlobalKey.currentState 为 null → 槽位置空）。下一帧
      // 兜底一次；动画落定（indexIsChanging=false 的 notify）再兜底一
      // 次——只 postFrame 一次不够，因为动画首帧「当前页」仍是旧页。
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() {});
      });
    } else if (!_tab.indexIsChanging) {
      setState(() {});
    }
  }

  @override
  void initState() {
    super.initState();
    AppState.instance.setModule(_tabNames[0]);
    _lastRailIndex = _tab.index;
    _tab.addListener(_onRailTabChanged);
    // v2.19.17：首帧 TabBarView 尚未构建当前 tab State，rail 取不到
    // 注入面板——首帧后触发一次 rebuild，第二帧槽位就位。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() {});
    });
    // v2.19.32：7 个注册点全部接上 `canOverwrite` + `onApplyFailed`。
    //
    // 闸（canOverwrite）：这一栏里已经有学生自己敲的题 ⇒ 深链/拍题**不覆盖**。
    // 目标页回答「我那儿现在是不是空着」，判据 = 该页签 `isPristine`（与
    // 具名出厂常量逐一比对，⛔ 不用 initState 快照）。被拦下时总线**仍切页**
    // （导航意图要满足）只是跳过写入，并用 `kModuleFillSkippedDirty` 调
    // `onApplyFailed`。⛔ `State 尚未挂载 ⇒ ?? true`：TabBarView 懒构建，
    // 还没挂载的页签连题都还没见过，视为出厂。
    //
    // 提示（onApplyFailed）：只加闸不提示 = 学生看到「点了没反应」，比被顶掉
    // 更难排查。文案直接用总线给来的 `reason`（拒收=总线常量原句、apply
    // 校验没过=另一句），本方法不替总线猜原因。
    ModuleFillBus.register(
      ModuleFillTarget(
        moduleId: 'cross_dihybrid',
        pageIndex: 2, // 主导航「遗传计算器」页
        label: '遗传计算器·双基因',
        apply: (params) => _applyCrossFill(0, params),
        onApplyFailed: _onApplyFailed,
        canOverwrite: () => _diKey.currentState?.isPristine ?? true,
      ),
    );
    // 图谱/课标的纯导览深链：只切页签，不写输入、不触发计算，也不受
    // 各页签脏页闸影响。目标页已有学生的题时必须原样保留。
    ModuleFillBus.register(
      ModuleFillTarget(
        moduleId: 'cross_tab',
        pageIndex: 2,
        label: '遗传计算器·页签导览',
        apply: (params) {
          final tab = int.tryParse(params['tab']?.trim() ?? '');
          if (tab == null || tab < 0 || tab > 6 || !mounted) return false;
          _tab.animateTo(tab);
          return true;
        },
        onApplyFailed: _onApplyFailed,
      ),
    );
    ModuleFillBus.register(
      ModuleFillTarget(
        moduleId: 'cross_trihybrid',
        pageIndex: 2,
        label: '遗传计算器·三对基因',
        apply: (params) => _applyCrossFill(1, params),
        onApplyFailed: _onApplyFailed,
        canOverwrite: () => _triKey.currentState?.isPristine ?? true,
      ),
    );
    // v2.14 R5 讲题回放补齐：单基因/伴性注册 fill 目标（▷ 可复现）。
    // 注册跟页走（主导航页常驻 IndexedStack，生命周期 = App）。
    ModuleFillBus.register(
      ModuleFillTarget(
        moduleId: 'cross_mono',
        pageIndex: 2,
        label: '遗传计算器·单基因',
        apply: _applyMonoFill,
        onApplyFailed: _onApplyFailed,
        canOverwrite: () => _monoKey.currentState?.isPristine ?? true,
      ),
    );
    ModuleFillBus.register(
      ModuleFillTarget(
        moduleId: 'cross_sex_linked',
        pageIndex: 2,
        label: '遗传计算器·伴性遗传',
        apply: _applySexFill,
        onApplyFailed: _onApplyFailed,
        canOverwrite: () => _sexKey.currentState?.isPristine ?? true,
      ),
    );
    // v2.15：方法对比注册 fill 目标（▷ 可复现——分解法 vs 配子法
    // 并排出结果，老师重讲「为什么多对基因拆开算」一键到位）。
    ModuleFillBus.register(
      ModuleFillTarget(
        moduleId: 'cross_method_compare',
        pageIndex: 2,
        label: '遗传计算器·方法对比',
        apply: _applyMcFill,
        onApplyFailed: _onApplyFailed,
        canOverwrite: () => _mcKey.currentState?.isPristine ?? true,
      ),
    );
    // v2.15：连锁互换注册 fill 目标（▷ 可复现，p1/p2/r 三参回填）。
    ModuleFillBus.register(
      ModuleFillTarget(
        moduleId: 'cross_linkage',
        pageIndex: 2,
        label: '遗传计算器·连锁互换',
        apply: _applyLinkFill,
        onApplyFailed: _onApplyFailed,
        canOverwrite: () => _linkKey.currentState?.isPristine ?? true,
      ),
    );
    // v2.19.25：套路卡深链——自由交配 tab（当时仅切页）。
    // v2.19.39：补上回填通道（`_applyRandomMatingFill`，`rows` 行走串），
    // 于是这一栏终于**有**可被覆盖的东西 ⇒ 恒放行的占位闸换成真判据，
    // 与其余 6 个页签同款：已有学生自己敲的群体构成 ⇒ 不覆盖，只切页 + 提示。
    ModuleFillBus.register(
      ModuleFillTarget(
        moduleId: 'cross_random_mating',
        pageIndex: 2,
        label: '遗传计算器·自由交配',
        apply: _applyRandomMatingFill,
        onApplyFailed: _onApplyFailed,
        // 与上面 6 个逐字同款：`State 尚未挂载 ⇒ ?? true`（TabBarView 懒构建，
        // 还没挂载的页签连题都还没见过，视为出厂）；被拦下时总线**仍切页**
        // （导航意图要满足）只是跳过写入，并用 kModuleFillSkippedDirty 提示。
        canOverwrite: () => _rmKey.currentState?.isPristine ?? true,
      ),
    );
  }

  /// 参数没被写进本页签时的用户可见反馈（`onApplyFailed` 接线）。
  ///
  /// 两种 `reason` 都要能出口：闸主动拒收（`kModuleFillSkippedDirty`）
  /// 与 apply 校验没过（总线另一句原话）——后者同样会让学生对着**落地页
  /// 自己的默认题**照抄，全流程零提示。
  ///
  /// 文案直接用 `reason`（总线常量原句），本方法不替总线猜原因；裸 `Text`
  /// 不解析 markdown ⇒ 这两句里都没有星号，也没有方向词。
  void _onApplyFailed(String moduleId, String reason) {
    if (!mounted) return;
    // ⚠️ 先 hide 再 show：showSnackBar 默认**排队**，连发两次只有第一条能被
    // 看见（实测 3 发 1 见）。换掉而不是排队。
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(reason),
        duration: const Duration(seconds: 9),
      ));
  }

  /// 切 tab + 回填亲本并立即计算。bus 已保证本页至少构建过一帧；
  /// animateTo 当帧构建目标 tab，再等一帧其 State 即可达。
  bool _applyCrossFill(int tabIndex, Map<String, String> params) {
    final p1 = params['p1']?.trim() ?? '';
    final p2 = params['p2']?.trim() ?? '';
    final need = tabIndex == 1 ? 6 : 4;
    final ok =
        RegExp('^[A-Za-z]{$need}\$').hasMatch(p1) &&
        RegExp('^[A-Za-z]{$need}\$').hasMatch(p2);
    if (!ok) return false;
    _tab.animateTo(tabIndex);
    // 双通道兜底：①tab State 已挂载 → 下一帧直接填；②尚未挂载
    // （TabBarView 懒构建）→ 落入待填槽，由 tab initState 消费。
    if (tabIndex == 0) {
      pendingDi = (p1: p1, p2: p2);
    } else {
      pendingTri = (p1: p1, p2: p2);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _flushFill(tabIndex));
    return true;
  }

  void _flushFill(int tabIndex) {
    if (tabIndex == 0) {
      final pf = pendingDi;
      if (pf != null && _diKey.currentState != null) {
        pendingDi = null;
        _diKey.currentState!.fillFromAi(pf.p1, pf.p2);
      }
    } else if (tabIndex == 1) {
      final pf = pendingTri;
      if (pf != null && _triKey.currentState != null) {
        pendingTri = null;
        _triKey.currentState!.fillFromAi(pf.p1, pf.p2);
      }
    } else if (tabIndex == 2) {
      final pf = pendingMono;
      if (pf != null) {
        pendingMono = null;
        if (_monoKey.currentState != null) {
          _monoKey.currentState!.fillFromAi(pf.p1, pf.p2);
        } else {
          // TabBarView 懒构建：tab 尚未挂载——留给 widget initState 消费。
          MonoCrossWidget.pendingFill = pf;
        }
      }
    } else if (tabIndex == 3) {
      final pf = pendingSex;
      if (pf != null) {
        pendingSex = null;
        if (_sexKey.currentState != null) {
          _sexKey.currentState!.fillFromAi(pf.p1, pf.p2);
        } else {
          SexLinkedTab.pendingFill = pf;
        }
      }
    } else if (tabIndex == 4) {
      final pf = pendingMc;
      if (pf != null) {
        pendingMc = null;
        if (_mcKey.currentState != null) {
          _mcKey.currentState!.fillFromAi(pf.p1, pf.p2);
        } else {
          MethodCompareTab.pendingFill = pf;
        }
      }
    } else if (tabIndex == 5) {
      final pf = pendingLink;
      if (pf != null) {
        pendingLink = null;
        if (_linkKey.currentState != null) {
          _linkKey.currentState!.fillFromAi(pf.p1, pf.p2, pf.r);
        } else {
          LinkageTab.pendingFill = pf;
        }
      }
    } else if (tabIndex == 6) {
      // v2.19.39：自由交配补上回填通道，形态与其余 6 个页签逐字同款：
      // State 已挂载 → 直接回填；尚未挂载（TabBarView 懒构建，深链触发时
      // 当前多半停在别的页签）→ 落静态待填槽，由 tab 的 initState 消费。
      final pf = pendingRm;
      if (pf != null) {
        pendingRm = null;
        if (_rmKey.currentState != null) {
          _rmKey.currentState!.applyFillParams(pf);
        } else {
          RandomMatingTabState.pendingRm = pf;
        }
      }
    }
  }

  /// v2.15：连锁互换 tab 回填（p1/p2 如 AB/ab × ab/ab，r 如 20%）。
  bool _applyLinkFill(Map<String, String> params) {
    final p1 = params['p1']?.trim() ?? '';
    final p2 = params['p2']?.trim() ?? '';
    final r = params['r']?.trim() ?? '';
    // 宽松校验：连锁基因型含 '/'（AB/ab），交换值非空——引擎再严判。
    final ok = p1.contains('/') && p2.isNotEmpty && r.isNotEmpty;
    if (!ok) return false;
    _tab.animateTo(5);
    pendingLink = (p1: p1, p2: p2, r: r);
    WidgetsBinding.instance.addPostFrameCallback((_) => _flushFill(5));
    return true;
  }

  /// v2.15：方法对比 tab 回填（p1/p2 如 AaBb × AaBb，≥2 位点）。
  bool _applyMcFill(Map<String, String> params) {
    final p1 = params['p1']?.trim() ?? '';
    final p2 = params['p2']?.trim() ?? '';
    // 宽松校验：字母基因型 ≥2 字符（AaBb / Aa / AABB…），引擎再严判。
    final ok =
        RegExp('^[A-Za-z]{2,8}\$').hasMatch(p1) &&
        RegExp('^[A-Za-z]{2,8}\$').hasMatch(p2);
    if (!ok) return false;
    _tab.animateTo(4);
    pendingMc = (p1: p1, p2: p2);
    WidgetsBinding.instance.addPostFrameCallback((_) => _flushFill(4));
    return true;
  }

  /// v2.14 R5：单基因 tab 回填（p1/p2 各 2 字符，如 Aa × Aa）。
  bool _applyMonoFill(Map<String, String> params) {
    final p1 = params['p1']?.trim() ?? '';
    final p2 = params['p2']?.trim() ?? '';
    final ok =
        RegExp('^[A-Za-z]{2}\$').hasMatch(p1) &&
        RegExp('^[A-Za-z]{2}\$').hasMatch(p2);
    if (!ok) return false;
    _tab.animateTo(2);
    pendingMono = (p1: p1, p2: p2);
    WidgetsBinding.instance.addPostFrameCallback((_) => _flushFill(2));
    return true;
  }

  /// v2.14 R5：伴性 tab 回填（p1=母本 XAXa，p2=父本 XAY）。
  bool _applySexFill(Map<String, String> params) {
    final p1 = params['p1']?.trim() ?? '';
    final p2 = params['p2']?.trim() ?? '';
    // 宽松校验：X 开头、≥3 字符（XAXa / XAY / XaY…），引擎再严判。
    final ok =
        p1.length >= 3 &&
        p2.length >= 3 &&
        p1.toUpperCase().startsWith('X') &&
        p2.toUpperCase().startsWith('X');
    if (!ok) return false;
    _tab.animateTo(3);
    pendingSex = (p1: p1, p2: p2);
    WidgetsBinding.instance.addPostFrameCallback((_) => _flushFill(3));
    return true;
  }

  /// v2.19.39：自由交配 tab 回填（`rows`：`Aa=1;aa=1`，`;` 分段 `=` 分键）。
  ///
  /// 与其余 6 个页签同一套双通道兜底：先 animateTo 让 TabBarView 开始懒构建，
  /// 再落 pendingRm 并 postFrame flush；仍未挂载则交给
  /// `RandomMatingTabState.pendingRm` 由 tab 的 initState 消费。
  ///
  /// 宽松校验交给唯一的解析口径 `RandomMatingTabState.parseRowsParam`
  /// （⛔ 不在本文件另写一份正则：两处各判一次日后必然漂移——闸放行而回填
  /// 拒收，学生对着出厂题照抄）；频率只验非空，引擎再严判。
  bool _applyRandomMatingFill(Map<String, String> params) {
    final rows = params['rows']?.trim() ?? '';
    if (RandomMatingTabState.parseRowsParam(rows) == null) return false;
    _tab.animateTo(6);
    pendingRm = Map<String, String>.of(params);
    WidgetsBinding.instance.addPostFrameCallback((_) => _flushFill(6));
    return true;
  }

  /// v2.6 ☰ 工具抽屉：经典预设（一键载入对应 tab 开算）+ 计算历史。
  Widget _buildToolDrawer() {
    return Drawer(
      width: 320,
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 20),
          children: [
            Row(
              children: [
                Icon(Icons.handyman_outlined, size: 18, color: AppColors.teal),
                const SizedBox(width: 8),
                Text('计算工具', style: AppText.sectionTitle),
              ],
            ),
            const SizedBox(height: 14),
            Text('经典预设（点按直接开算）', style: AppText.label),
            const SizedBox(height: 8),
            for (final p in const [
              ('双基因 · 杂合自交 9:3:3:1', 0, 'AaBb', 'AaBb'),
              ('双基因 · 测交 1:1:1:1', 0, 'AaBb', 'aabb'),
              ('双基因 · 一对杂合 × 纯合', 0, 'AABb', 'AaBb'),
              ('三对基因 · 三杂合自交 27:9:…:1', 1, 'AaBbCc', 'AaBbCc'),
              ('三对基因 · 测交 1:1:…:1', 1, 'AaBbCc', 'aabbcc'),
              ('三对基因 · 两对杂合 AaBbCC', 1, 'AaBbCC', 'AaBbCc'),
            ])
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: OutlinedButton(
                  onPressed: () => _applyPreset(p.$2, p.$3, p.$4),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      p.$1,
                      style: AppText.body.copyWith(fontSize: 13),
                    ),
                  ),
                ),
              ),
            const SizedBox(height: 10),
            Divider(color: AppColors.border),
            const SizedBox(height: 6),
            Text('计算历史（本次会话）', style: AppText.label),
            const SizedBox(height: 6),
            if (_history.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.history_outlined,
                        size: 28, color: AppColors.steel),
                    const SizedBox(height: 8),
                    Text('暂无记录', style: AppText.sectionTitle),
                    const SizedBox(height: 4),
                    Text(
                      '在本页完成一次计算后会出现在这里。',
                      textAlign: TextAlign.center,
                      style: AppText.body.copyWith(color: AppColors.steel),
                    ),
                  ],
                ),
              ),
            for (final h in _history)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text(
                  '${h.p1} × ${h.p2}',
                  style: AppText.genotype.copyWith(fontSize: 13),
                ),
                subtitle: Text(
                  '${h.tab == 1 ? '三对基因' : '双基因'} · 表型比 ${h.ratio}',
                  style: AppText.caption.copyWith(color: AppColors.steel),
                ),
                trailing: Icon(
                  Icons.replay_outlined,
                  size: 16,
                  color: AppColors.teal,
                ),
                onTap: () => _applyPreset(h.tab, h.p1, h.p2),
              ),
          ],
        ),
      ),
    );
  }

  /// v2.19.17：取当前 tab 注入 rail 的输入面板（实现 CrossTabSidePanel
  /// 的 tab 才返回；未实现/未挂载 → null = 槽位置空，rail 只剩预设/历史）。
  Widget? _currentSidePanel() {
    Widget? tryCast(Object? s) {
      if (s is! CrossTabSidePanel) return null;
      return s.buildSidePanel(context);
    }

    // v2.19.23 找茬 P0#1：自由交配面板结构（增删行/预设替换）经
    // panelRevision 通知——宽屏 rail 副本是容器构建时的快照，tab 内部
    // setState 不会重建它（否则显示旧行、输入写进已 dispose 的
    // controller）。用 ValueListenableBuilder 让 rail 随结构变化重建。
    if (_tab.index == 6) {
      final rm = _rmKey.currentState;
      if (rm == null) return null;
      return ValueListenableBuilder<int>(
        valueListenable: rm.panelRevision,
        builder: (context, _, __) => rm.buildSidePanel(context),
      );
    }
    return switch (_tab.index) {
      0 => tryCast(_diKey.currentState),
      1 => tryCast(_triKey.currentState),
      2 => tryCast(_monoKey.currentState),
      3 => tryCast(_sexKey.currentState),
      4 => tryCast(_mcKey.currentState),
      5 => tryCast(_linkKey.currentState),
      _ => null,
    };
  }

  /// 抽屉项：关抽屉 → 切 tab + 回填即算（复用路由填参通道）。
  void _applyPreset(int tab, String p1, String p2) {
    _scaffoldKey.currentState?.closeDrawer();
    _applyCrossFill(tab, {'p1': p1, 'p2': p2});
  }

  @override
  void dispose() {
    ModuleFillBus.unregister('cross_tab');
    ModuleFillBus.unregister('cross_dihybrid');
    ModuleFillBus.unregister('cross_trihybrid');
    // R6 老师走查 #10：v2.14 新增的两个 target 对称注销（此前漏写会
    // 在复现清单混入幽灵 target）。
    ModuleFillBus.unregister('cross_mono');
    ModuleFillBus.unregister('cross_sex_linked');
    ModuleFillBus.unregister('cross_method_compare');
    ModuleFillBus.unregister('cross_linkage');
    // v2.19.33 对称注销补丁：cross_random_mating 注册点（initState）
    // 的对应注销此前漏写——页面销毁后幽灵 target 留在全局注册表
    // （cross 接线 worker 发现的既有 bug，顺带修）。
    ModuleFillBus.unregister('cross_random_mating');
    _tab.dispose();
    super.dispose();
  }

  /// v2.19.57 找茬 B1：页级单一 Ctrl+S 宿主的 payload 分派——按下那一刻
  /// 按 `_tab.index` 取**当前页签** State 的 savePayload()（⛔ 不在 build 期
  /// 预取：切页签不让本页 rebuild，预取会存到已切走的页签那道题）。
  /// 只有可存题的四个页签有宿主语义；方法对比/连锁互换/自由交配没有
  /// Ctrl+S 计算器页签 ⇒ 返回 null（宿主闸 ④ 无声让路，⛔ 不编造题干）。
  SavePayload? _currentTabPayload() {
    switch (_tab.index) {
      case 0:
        return _diKey.currentState?.savePayload();
      case 1:
        return _triKey.currentState?.savePayload();
      case 2:
        return _monoKey.currentState?.savePayload();
      case 3:
        return _sexKey.currentState?.savePayload();
      default:
        return null;
    }
  }

  /// v2.19.59：当前页签的**考点常量**（K 看套路卡的唯一判据源）。
  ///
  /// ⛔ 考点一律引用各面的**那一处常量定义**，本方法不另写一份字面量：
  /// 双基因/三对基因/自由交配共用 [kFreeCombinationSubjectArea]；
  /// 单基因用 `kMonoCrossSubjectArea`（mono 面 `savePayload` 的同一份）；
  /// 伴性用 `kSexLinkedSubjectArea`（伴性面 `savePayload` 的同一份）。
  /// ⛔ 方法对比（tab 4）/ 连锁互换（tab 5）**没有**「存入错题本」口径
  /// （读源码确认：两页既无 SavePayload 也无 subjectArea）⇒ 返回 null =
  /// 无考点 = 无卡（⛔ 不替这两页编一个考点）。
  String? _currentTabTopic() {
    switch (_tab.index) {
      case 0:
      case 1:
      case 6:
        return kFreeCombinationSubjectArea;
      case 2:
        return kMonoCrossSubjectArea;
      case 3:
        return kSexLinkedSubjectArea;
      default:
        return null;
    }
  }

  /// v2.19.59：按 K 那一刻现取的配套卡 id（`CardLinkKeyHost.cardId`）。
  /// 返回 null = 无声让路：这一面没有配套卡（方法对比/连锁互换无考点，
  /// 或考点命不中关键词）。判据走文件顶层的 `_cardIdForTopic`（**全文件
  /// 唯一一处** `findCardIdForTopic` 调用）。
  ///
  /// ⛔ 判据**只有**「当前考点有没有配套卡」一道——**不**加「有没有算出
  /// 结果」闸：套路卡是学习材料，没算出结果先去看卡是合法动线（B 仓
  /// v2.19.245 原始语义；与分子/进化/倍性同口径）。「有结果才印提示」是
  /// **屏上尾注**自己的闸（各结果区 `r == null` 那一支），键与提示解耦：
  /// 提示印得出 ⇒ 键必跳（cardId 非 null）；提示没印 ⇏ 键不应答——速览表
  /// 对 K 的承诺是「当前考点有配套卡才应答」，与这条判据逐字一致。
  String? _currentTabCardId() => _cardIdForTopic(_currentTabTopic());

  @override
  Widget build(BuildContext context) {
    // v2.19.16 工作台化：宽屏（>=1200）左侧常驻 CrossToolRail，☰ 抽屉
    // 隐藏（工具已在侧栏，再开抽屉 = 预设/历史双份）；窄屏维持抽屉。
    final wide = MediaQuery.of(context).size.width >= 1200;
    // v2.19.57 找茬 B1：整页只挂**一枚** SaveMistakeKeyHost——此前 7 个
    // keep-alive 页签各挂 1~2 枚，HardwareKeyboard 把同一枚事件派发给
    // 全部 handler（返回值只 OR 汇总，没有焦点链消费语义），按一次
    // Ctrl+S = 访问过的每个页签各存各的题 + 同 tab 两枚宿主互相顶掉
    // 回执。宿主包在 Scaffold 外缘（键盘 handler 全局生效，无需焦点祖先；
    // 焦点让路由宿主自己的 _editingText 闸判）。
    // v2.19.59：整页只挂**一枚** CardLinkKeyHost（「K 看这道题的套路卡」）
    // ——形态与上面那枚 Ctrl+S 宿主逐字同款（键盘 handler 全局生效，无需
    // 焦点祖先；焦点让路由宿主自己的 _editingText 闸判）。cardId 是
    // ValueGetter：按键那一刻按 _tab.index 现取当前页签的考点与卡 id
    // （⛔ 不在 build 期预取，切页签不让本页 rebuild）。
    return CardLinkKeyHost(
      cardId: _currentTabCardId,
      child: SaveMistakeKeyHost(
      payload: _currentTabPayload,
      child: Scaffold(
        key: _scaffoldKey,
      // v2.6：☰ 改开本页工具抽屉（原接 HomeShell 全局回调——翻动的
      // _navCollapsed 只影响系谱页，本页点了没反应的死按钮）。
      // v2.19.16：宽屏 drawer 置 null（侧栏常驻承接）。
      drawer: !wide && widget.onNavPressed != null ? _buildToolDrawer() : null,
      appBar: AppBar(
        leading: appNavButton(
          widget.onNavPressed != null && !wide
              // DrawerController 缓存抽屉子树（关抽屉只 deactivate 不 dispose），
              // 开前 setState 让抽屉按最新历史/预设重建。
              ? () {
                  setState(() {});
                  _scaffoldKey.currentState?.openDrawer();
                }
              : null,
        ),
        title: const Text('遗传计算器'),
        actions: [
          TextButton.icon(
            onPressed: () => showAiAssistant(context),
            icon: const Icon(Icons.psychology_outlined, size: 18),
            label: const Text('问 AI'),
          ),
          const SizedBox(width: 8),
        ],
        bottom: TabBar(
          controller: _tab,
          // v2.19.26（手机 P2-1 / 平板 F-14）：7 项固定均分在 390 宽
          // 下每项 55.7dp、文字可用宽 ≈24dp（≈1.7 汉字）淡出残字——
          // 改可滚动（同项目 buildWorkbenchTabBar ≥5 即滚动的口径；
          // 分子/进化/倍性/套路卡已全部 isScrollable，9331 漏网）。
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          // v2.19.60：挤压态（<720）去图标——与 buildWorkbenchTabBar 同一
          // 口径（kWorkbenchCompactWidth 单一真相）：窗口被压窄时 icon+文字
          // 页签条与底导视觉同构（双层导航观感），去图标后与底导明显分层，
          // 功能不变。本页不走共享 helper（页签带各自 icon），同款分支内联。
          tabs: [
            for (final t in const [
              (Icons.show_chart, '双基因 9331'),
              (Icons.grid_on, '三对基因'),
              (Icons.compare_arrows, '单基因杂交'),
              (Icons.transgender, '伴性遗传'),
              (Icons.compare_outlined, '方法对比'),
              (Icons.link, '连锁互换'),
              (Icons.groups_outlined, '自由交配'),
            ])
              Tab(
                icon: MediaQuery.of(context).size.width < kWorkbenchCompactWidth
                    ? null
                    : Icon(t.$1),
                text: t.$2,
              ),
          ],
        ),
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          // v2.19.16 工作台化：宽屏时左侧常驻工具侧栏
          // （经典预设+计算历史，与系谱页 PedigreeSidePanel 同款
          // 视觉语言），消除「系谱=Audition 工作台 / 9331=PPT 白板」
          // 的割裂；窄屏空间让给内容，☰ 抽屉承接（原路径不动）。
          // wide 判定与 build 顶层同一阈值（MediaQuery 1200）。
          final tabView = TabBarView(
            controller: _tab,
            // 严禁 const：tab 页内部文字用 AppColors 显式 style，const 实例会被
            // canonicalize 导致 Element 短路永不 rebuild，首帧（如系统深色）构建的
            // 深色 token 文字会永久冻结，浅色模式下变成白底白字。
            children: [
              _Dihybrid9331Tab(key: _diKey),
              _TrihybridTab(key: _triKey),
              // v2.14 R5：key 供讲题回放 fill 直达（▷ 可复现）。
              // v2.19.59：cardHint = 结果区副标题的套路卡尾注——由本页（而不是
              // 各 tab）统一算，判据与 K 宿主同源（单一 `_cardIdForTopic`）。
              MonoCrossWidget(
                key: _monoKey,
                cardHint: _cardHintForTopic(kMonoCrossSubjectArea),
              ),
              SexLinkedTab(
                key: _sexKey,
                cardHint: _cardHintForTopic(kSexLinkedSubjectArea),
              ),
              // v2.15：key 供讲题回放 fill 直达（▷ 可复现）。
              MethodCompareTab(key: _mcKey),
              LinkageTab(key: _linkKey),
              RandomMatingTab(
                key: _rmKey,
                cardHint: _cardHintForTopic(kFreeCombinationSubjectArea),
              ),
            ],
          );
          if (!wide) return _withTabJump(_withCurriculumKey(tabView));
          return _withTabJump(_withCurriculumKey(
            Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                CrossToolRail(
                  history: _history,
                  onPreset: _applyPreset,
                  onReplay: _applyPreset,
                  // v2.19.17 去主体化：当前 tab 的输入面板注入 rail 顶部
                  // （左功能右结果）。TabBarView 懒构建未挂载时无面板。
                  // v2.19.23 找茬 P3#6：按 tab 上 Key——同型根 widget 跨 tab
                  // 原位 patch 复用，TextField 换 controller 复用（焦点/光标
                  // 残留），rail 滚动位置也串 tab。
                  top: KeyedSubtree(
                    key: ValueKey('cross-rail-panel-${_tab.index}'),
                    child: _currentSidePanel() ?? const SizedBox.shrink(),
                  ),
                ),
                Expanded(child: tabView),
              ],
            ),
          ));
        },
      ),
      ),
      ),
    );
  }

  /// v2.19.35：页面主体外面套一层 `Alt+K` 宿主（**零像素**：不渲染任何东西）。
  ///
  /// ## 为什么包在 body 上（而不是 build 顶层或 App 级）
  /// 宿主要在**本页可见期间**才认领 `Alt+K`：它按 `ModalRoute.isCurrent` 让路，
  /// 所以被别的路由盖住时不会误触发；挂在 body 上还顺带保证「本页的输入框在
  /// 焦点链上」这一守卫读得到焦点（`_editingText` 判的就是那棵树）。
  /// ⛔ App 级集中注册表（备份仓 B 的 `active_shortcut_handlers`）是后续轮次，
  /// 本轮**不造**。
  Widget _withCurriculumKey(Widget child) => CurriculumFocusShortcuts(
        tab: _tab,
        moduleIdsByTab: _tabModuleIds,
        child: child,
      );

  /// v2.19.49：`Alt+1`–`Alt+7` 页签直跳宿主（**零像素**，只切页签不碰题面；
  /// 让路闸见 lib/ui/tab_jump_shortcuts.dart 文件头）。9331 有 7 个页签，
  /// 此前是本族唯一有这条键的页面（B 仓 v2.19.168 补其余五页——本仓同款）。
  Widget _withTabJump(Widget child) => TabJumpShortcuts(
        tab: _tab,
        child: child,
      );
}

/// 本页两类存题入口的**回程字符数**：真源是 `_applyCrossFill` 的
/// `need = tabIndex == 1 ? 6 : 4`（tab 0 = 双基因 4 字符、tab 1 = 三对基因
/// 6 字符）。
///
/// ⛔ 记成「moduleId → 字符数」一张表，而不是把 `srcModule` 与「字符数」
/// 拆成两个独立入参一路往下传：那两个入参迟早会被配错（双基因 id 配 6
/// 字符 = 记下一组回程判不过的亲本 = 错题本里一枚死按钮），而同表两项
/// 同源，配不错。
const _crossNeedByModule = <String, int>{
  'cross_dihybrid': 4,
  'cross_trihybrid': 6,
};

/// 存进错题本时**记下这道题的亲本**（`cross_dihybrid` / `cross_trihybrid`）。
///
/// ⛔ 口径：只有**回程一定写得进去**的亲本才记。回程走本页的
/// `_applyCrossFill`，它的判据是 `^[A-Za-z]{$need}$`（双基因 4 字母、
/// 三对基因 6 字母）——本函数的判据必须与它**逐字一致**，否则会记下一组
/// `fill` 会拒收的参数 ⇒ 错题本里出现一枚点下去必然弹「那一页现在过不去」
/// 的**死按钮**，比不记更糟。
/// ⛔ 因此这里比两页各自的 `_calculate` 更严：双基因那页只查「长度 == 4」
/// （`1aB1` 本页算得出、回程填不进 ⇒ 不记）。
Map<String, String>? _crossSrcParams(String module, String p1, String p2) {
  final need = _crossNeedByModule[module];
  // ⛔ 表里没有的 moduleId 不猜（宁可不给来源）——回程不认的 id 存进去
  // 只会得到一枚点下去没反应的按钮。
  if (need == null) return null;
  final a = p1.trim();
  final b = p2.trim();
  final re = RegExp('^[A-Za-z]{$need}\$');
  if (!re.hasMatch(a) || !re.hasMatch(b)) return null;
  return {'p1': a, 'p2': b};
}

/// Tab 1：双基因 9331 计算器 —— UI 重做样板。
///
/// v2.19.17 布局：左（rail：输入面板+预设+历史）右（平铺结果区）。
/// 原「步骤流程卡」去壳平铺，背景融入主体。
/// v2.19.18：平铺分区组件提升为公共 FlatSection（cross_tool_rail.dart），
/// 其余 tab 复用。
class _Dihybrid9331Tab extends StatefulWidget {
  const _Dihybrid9331Tab({super.key});

  @override
  State<_Dihybrid9331Tab> createState() => _Dihybrid9331TabState();
}

class _Dihybrid9331TabState extends State<_Dihybrid9331Tab>
    with AutomaticKeepAliveClientMixin
    implements CrossTabSidePanel {
  @override
  bool get wantKeepAlive => true;
  /// 出厂默认题（判 `isPristine` 的锚点）。⛔ controller 初始化复用它，
  /// 不另写一份字面量——两份常量迟早分叉，那时守卫就成了摆设。
  static const _kDefaultP1 = 'AaBb';
  static const _kDefaultP2 = 'AaBb';

  final _p1Ctrl = TextEditingController(text: _kDefaultP1);
  final _p2Ctrl = TextEditingController(text: _kDefaultP2);

  /// 这一栏现在**还是出厂状态吗**（没人动过）？
  ///
  /// 供 `ModuleFillTarget.canOverwrite` 用：学生自己在这一栏敲了题之后，再
  /// 从课标/拍题深链进来，**不该把他那道题无声顶掉**。
  ///
  /// 判据 = 两个亲本输入框都还等于出厂默认值。⛔ **不用 initState 快照**：
  /// 快照只认「本次挂载以来」，keep-alive 存活的 State 与重建过的 State
  /// 会各自拿一份，守卫就成了薛定谔的。⚠️ 只比 `fillFromAi` 会写的这两框——
  /// 本页签的反推（`_revCtrl`）与错因诊断（`_diag*Ctrl`）是**另外两套工具**，
  /// 深链不写它们，不该由它们拦下深链。
  bool get isPristine =>
      _p1Ctrl.text == _kDefaultP1 && _p2Ctrl.text == _kDefaultP2;

  KaojiCalcResult? _result;
  String? _error;
  // v2.19.56（找茬 D 收尾，照 v2.19.53 分子/变异试点）：算出那一刻的亲本
  // 输入快照。Ctrl+S 组装 payload 时比对现文——改动过未重算则从题干/答案
  // 剔除（⛔ 不存「题干新输入 + 答案旧结果」的矛盾题）。⛔ 本文件双/三对
  // 基因两个 _result：快照名加 tab 前缀防串。
  String? _diSnap;

  // N1 反推子模式状态（白板输入困难：预置常用比例 chips 免键盘）
  final _revCtrl = TextEditingController(text: '3:1');
  int _revLoci = 0; // 0 自动 / 1 一对 / 2 两对
  List<ReverseMatch>? _revMatches;
  String? _revError;
  final _reverse = ReverseEngine();

  final _kaoji = KaojiCalc();

  /// v2.19.23 找茬 P1#3：keep-alive 后 State 生命周期与页面解耦，
  /// controller 必须显式 dispose（原缺失，每次 tab 往返泄漏 3+2 个）。
  @override
  void dispose() {
    _p1Ctrl.dispose();
    _p2Ctrl.dispose();
    _revCtrl.dispose();
    super.dispose();
  }

  /// v2.5 拍题识别填参（ModuleFillBus 路由）：外部注入亲本并立即计算。
  void fillFromAi(String p1, String p2) {
    _p1Ctrl.text = p1;
    _p2Ctrl.text = p2;
    _calculate();
  }

  @override
  void initState() {
    super.initState();
    // v2.5 拍题识别路由：待填槽消费（路由到达时本 tab 尚未挂载的情形）
    final page = context.findAncestorStateOfType<_CrossCalculatorPageState>();
    final pf = page?.pendingDi;
    if (pf != null) {
      page!.pendingDi = null;
      _p1Ctrl.text = pf.p1;
      _p2Ctrl.text = pf.p2;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _calculate();
      });
    }
  }

  void _calculate() {
    final p1 = _p1Ctrl.text.trim();
    final p2 = _p2Ctrl.text.trim();
    if (p1.length != 4 || p2.length != 4) {
      setState(() {
        _error = '请输入 4 个字符的基因型（两对等位基因，如 AaBb 或 aabb）。';
        _result = null;
      });
      return;
    }
    setState(() {
      _error = null;
      _result = _kaoji.dihybrid9331(p1: p1, p2: p2);
      // v2.19.56：算出即存输入快照（stale 门的基准，照 v2.19.53 试点）。
      _diSnap = '$p1|$p2';
    });
    // 上报上下文：AI 助手可直接看到当前输入与结果
    final r = _result!;
    final state = AppState.instance;
    state.report('双亲基因型', '$p1 × $p2');
    state.report('P1 配子', r.gametesP1.join('、'));
    state.report('P2 配子', r.gametesP2.join('、'));
    state.report('F2 表型比例', r.phenotypeRatio.toString());
    state.report('F2 基因型比例', r.genotypeRatio.toString());
    state.report('变式类型', r.variantName);
    // v2.6：登记计算历史（☰ 工具抽屉展示/一键恢复）
    context.findAncestorStateOfType<_CrossCalculatorPageState>()?.recordHistory(
      0,
      p1,
      p2,
      r.phenotypeRatio.toString(),
    );
  }

  /// 输入区直达系谱：与结果区按钮共用同一链接服务。
  /// 先校验并计算当前输入，失败时保留本页错误提示，不跳转。
  void _openInPedigree() {
    _calculate();
    final r = _result;
    if (r == null) return;
    openCrossInPedigree(
      p1: _p1Ctrl.text.trim(),
      p2: _p2Ctrl.text.trim(),
      ratio: r.phenotypeRatio.toString(),
    );
  }

  // v2.19.56（照 v2.19.53 试点）：本节「新鲜度」门——结果存在且算出那
  // 一刻的输入快照与现文一致才算数。学生改亲本未重算时该节从题干/答案
  // 剔除（⛔ 不存「题干新输入 + 答案旧结果」的矛盾题，矛盾数据会喂给错
  // 题本 AI 错因归类）；全部节不新鲜 ⇒ 答案空串 ⇒ saveToMistakeBook 既
  // 有「先算出结果」守卫应答。srcModule/srcParams 同受门（stale ⇒ 整节
  // 剔除，错题本不出现「参数是新的、答案却是旧的」错回程）。
  bool get _diFresh =>
      _result != null &&
      _diSnap == '${_p1Ctrl.text.trim()}|${_p2Ctrl.text.trim()}';

  /// v2.19.17 去主体化：输入面板（无卡片壳）——宽屏时容器页把它注入
  /// CrossToolRail 顶部（左功能），窄屏时 tab 自己渲染在结果区上方。
  /// 引导高亮 key 挂在面板根（两棵树同一时刻只挂载一处，GlobalKey 唯一）。
  @override
  Widget buildSidePanel(BuildContext context) {
    // v2.19.57 找茬 B1：Ctrl+S 宿主收编为容器页**一枚**页级宿主（按键
    // 按 _tab.index 分派到当前页签的 savePayload()）——本 tab 不再自挂
    // 宿主。此前宽屏（面板注入 rail）+ 窄屏（面板嵌在 build 宿主内）都
    // 同时存活两枚宿主，同按一次 Ctrl+S 两枚各应答一次：第二枚的
    // 「已在错题本里」把第一枚的「已加入（含撤销）」顶掉。
    return Column(
      key: GuideKeys.crossSteps,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('设定亲本基因型', style: AppText.sectionTitle),
        const SizedBox(height: 4),
        Text(
          '两对等位基因共 4 个字符（如 AaBb / AABb / aabb）',
          style: AppText.caption.copyWith(color: AppColors.steel),
        ),
        const SizedBox(height: 12),
        _buildInputArea(),
      ],
    );
  }

  /// v2.19.57：页级宿主分派入口——按下 Ctrl+S 那一刻现读现拼（⛔ 不用
  /// build 期预取：「改了输入未重算」时预取到的旧结果非空会穿过 stale 门）。
  /// 与结果面板那枚按钮同口径（同源 _result/_diFresh）。
  SavePayload? savePayload() {
    final fresh = _diFresh;
    final r = fresh ? _result : null;
    return SavePayload(
      stem: fresh
          ? '${_p1Ctrl.text.trim()} × ${_p2Ctrl.text.trim()} 杂交，后代表型比和基因型比分别是？'
          : '',
      correctAnswer: r == null
          ? ''
          : '表型比 ${r.phenotypeRatio}'
              '${r.genotypeRatio != null ? '；基因型比 ${r.genotypeRatio}' : ''}',
      subjectArea: kFreeCombinationSubjectArea,
      srcModule: fresh ? 'cross_dihybrid' : null,
      srcParams: fresh
          ? _crossSrcParams('cross_dihybrid', _p1Ctrl.text, _p2Ctrl.text)
          : null,
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // AutomaticKeepAliveClientMixin 要求
    // v2.19.13（学生找茬 🔴2）：页面级 Ctrl+S 宿主——快捷键沿焦点链
    // 冒泡，必须是输入 TextField 的祖先（原按钮子树绑定在 TextField
    // 有焦点时永远不触发）。数据与结果面板内的按钮严格同链。
    final r = _result;
    // v2.19.36 正向「课标 X」可点徽章：挂**本结果区标题行 trailing**。
    // 数据真源 = 既有反向表（`curriculumReverseBadgeFor` 从本栏自己的
    // moduleId `cross_dihybrid` 唯一命中反查 3.2.3）⛔ 本页不建表。
    // ⛔ 空态（`r == null`）不挂：那一栏还没算出题，一枚可点徽章等于宣称
    // 一道**还不存在**的题考它。多义/未被点名时 helper 返 null ⇒ 回落
    // 原来那枚 AppChip（逐像素同旧）。
    final badge =
        r == null ? null : curriculumReverseBadgeFor(context, 'cross_dihybrid');
    final variant =
        r == null ? null : AppChip(r.variantName, icon: Icons.auto_awesome);
    // v2.19.17 去主体化：宽屏（>=1200）输入面板已被容器页注入左侧
    // rail，本区只渲染纯结果；窄屏自渲染输入面板（无 rail）。
    final wide = MediaQuery.of(context).size.width >= 1200;
    // v2.19.57 找茬 B1：宿主收编为容器页一枚（按键按 _tab.index 分派到
    // savePayload()），本 build 不再自挂宿主——见 buildSidePanel 头注。
    return SingleChildScrollView(
      // 底部避让 FAB 列；宽屏右侧再留出其横向命中区，避免滚动途中
      // 变式比例 chip 被「拍题 / 问 AI」覆盖（实窗口体验官发现）。
      padding: EdgeInsets.fromLTRB(24, 20, wide ? 112 : 24, 96),
        // v2.19.17 去主体化：顶对齐铺满，内容直接铺页面背景——
        // 分区用 _FlatSection 标题行区分，不再用悬浮卡片壳。
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1400),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // 窄屏：无 rail，输入面板自渲染在结果区上方（含引导 key）。
                if (!wide) buildSidePanel(context),
                if (!wide) const SizedBox(height: 28),
                FlatSection(
                  title: '计算结果',
                  subtitle: r == null
                      ? '设定亲本后点「计算比例」，这里展开配子、F2 比例与基因型明细'
                      : _withCardHint(
                          '配子 · F2 表型/基因型比例 · 基因型明细',
                          kFreeCombinationSubjectArea,
                        ),
                  // v2.19.36：徽章在前、变式 chip 在后，窄屏折行由 Wrap 兜。
                  trailing: badge == null
                      ? variant
                      : Wrap(
                          spacing: 10,
                          alignment: WrapAlignment.end,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [badge, variant!],
                        ),
                  child: _buildResultBody(),
                ),
                FlatSection(
                  title: '常见 9331 变式速查',
                  subtitle: '标准 9:3:3:1 按份数合并得到的经典变式',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildVariantList(),
                      // v2.19.17（真实用户调研转化·教研文档点名易错）：
                      // 「未出现 9:3:3:1 ≠ 不遵循自由组合」「性状与性别
                      // 有关 ≠ 伴性遗传」是学生高频错因（多篇教研/易错
                      // 盘点原话）；运行时框架定位下以提示卡呈现（非题库）。
                      const SizedBox(height: 10),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.sand.withValues(alpha: 0.10),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: AppColors.sand.withValues(alpha: 0.45),
                          ),
                        ),
                        child: Text(
                          '※ 易错提醒\n'
                          '· 子代未出现 9:3:3:1 ≠ 不遵循自由组合——可能是基因互作（变式比例仍是 9:3:3:1 的份数合并）\n'
                          '· 性状与性别有关 ≠ 伴性遗传——也可能是从性遗传/限性遗传，要看基因是否位于性染色体',
                          style: AppText.caption.copyWith(
                            color: AppColors.graphite,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                // N1（v2.4 题型能力建设）：反推子模式——后代比例 → 亲本组合
                // （校卷题 15 型，月考高频；题型矩阵 A8 缺口）。
                FlatSection(
                  title: '反推：由后代比例推亲本',
                  subtitle: '给 F1/F2 表型比（如 3:1、9:7、1:1:1:1），枚举亲本组合',
                  child: _buildReverseArea(),
                ),
                // v2.4 功能 3：错因诊断（面批面改场景）——学生答错比例题时
                // 反推最可能的错误类型。
                FlatSection(
                  title: '错因诊断（学生答错时）',
                  subtitle: '填亲本与正解，输入学生的错误比例，反推最可能的错因',
                  child: _buildDiagnosisArea(),
                ),
              ],
            ),
          ),
        ),
    );
  }

  Widget _buildInputArea() {
    // v2.19.22：亲本输入改竖排（P1 → × → P2 全宽各占一行）——
    // 宽屏 rail 内容宽仅 248px，横排两个 Expanded TextField 的
    // InputDecorator 固有最小宽度叠加溢出 6.9px；竖排与系谱页
    // 杂交面板同款窄宽形态。
    return SizedBox(
      width: double.infinity,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _p1Ctrl,
            style: AppText.genotype,
            decoration: const InputDecoration(labelText: '亲本 1'),
          ),
          const SizedBox(height: 2),
          Padding(
            padding: const EdgeInsets.only(left: 4),
            child: Icon(Icons.close, size: 16, color: AppColors.steel),
          ),
          const SizedBox(height: 2),
          TextField(
            controller: _p2Ctrl,
            style: AppText.genotype,
            decoration: const InputDecoration(labelText: '亲本 2'),
          ),
          const SizedBox(height: 8),
          // v2.4 N7：经典题型预设 chips（白板打字痛点，一键免键盘载入）
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (final p in const [
                ('杂合自交 9331', 'AaBb', 'AaBb'),
                ('测交', 'AaBb', 'aabb'),
                ('一对杂合 × 纯合', 'AABb', 'AaBb'),
              ])
                ActionChip(
                  label: Text(p.$1),
                  onPressed: () {
                    _p1Ctrl.text = p.$2;
                    _p2Ctrl.text = p.$3;
                    _calculate();
                  },
                ),
            ],
          ),
          const SizedBox(height: 16),
          // v2.19.17：改 Wrap——输入面板要兼容两种宿主（宽屏 rail 内容
          // 宽仅 248，三按钮一行溢出 157px；Wrap 窄处自动换行）。
          Wrap(
            spacing: 12,
            runSpacing: 8,
            children: [
              FilledButton.icon(
                onPressed: _calculate,
                icon: const Icon(Icons.calculate_outlined),
                label: const Text('计算比例'),
              ),
              Tooltip(
                message: '带当前亲本与参考比例到遗传图谱；可返回本页',
                child: OutlinedButton.icon(
                  onPressed: _openInPedigree,
                  icon: const Icon(Icons.account_tree_outlined),
                  label: const Text('系谱展开'),
                ),
              ),
              // v2.4 功能 1：AI 读题填参（白板免敲基因型）
              OutlinedButton.icon(
                onPressed: () => showAiFillParams(
                  context,
                  moduleHint:
                      '9331 双基因自由组合计算器，参数 p1/p2 为亲本基因型'
                      '（如 AaBb）；若题目只给一对基因，p1/p2 也用 4 字符（'
                      '如 AaBB）。只输出 {"p1":"...","p2":"..."}',
                  onApply: (params) {
                    final a = params['p1']?.trim();
                    final b = params['p2']?.trim();
                    if (a != null && a.isNotEmpty) _p1Ctrl.text = a;
                    if (b != null && b.isNotEmpty) _p2Ctrl.text = b;
                    _calculate();
                  },
                ),
                icon: const Icon(Icons.content_paste_search_outlined),
                label: const Text('读题填参'),
              ),
              OutlinedButton.icon(
                onPressed: () => showAiAssistant(context),
                icon: const Icon(Icons.psychology_outlined),
                label: const Text('AI 解析'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// v2.19.17 结果区内容体（无 StepCard 壳——壳由 _FlatSection 取代，
  /// 标题/trailing 在 build 的分区头里渲染）。
  Widget _buildResultBody() {
    final r = _result;
    if (r == null) {
      return _error != null
          ? _ErrorBanner(message: _error!)
          : Padding(
              padding: const EdgeInsets.symmetric(vertical: 18),
              child: Column(
                children: [
                  Icon(
                    Icons.grid_on_rounded,
                    size: 32,
                    color: AppColors.steel.withValues(alpha: 0.45),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    '等待计算：结果将在这里展开',
                    style: AppText.body.copyWith(color: AppColors.steel),
                  ),
                ],
              ),
            );
    }
    // N6（v2.4）：板书视图切换——结果面板支持「数值 / 板书」双视图，
    // 板书 = 标准遗传图解格式（投屏讲解用，烟台二中规范书写实证）。
    return _DihybridResultPanel(
      result: r,
      p1: _p1Ctrl.text.trim(),
      p2: _p2Ctrl.text.trim(),
      srcModule: 'cross_dihybrid',
    );
  }

  Widget _buildVariantList() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < KaojiCalc.knownVariants.length; i++) ...[
          if (i > 0)
            Divider(
              height: 14,
              color: AppColors.border.withValues(alpha: 0.35),
            ),
          _VariantRow(
            name: _variantName(KaojiCalc.knownVariants[i]),
            ratio: _kaoji
                .variantRatio(KaojiCalc.knownVariants[i])
                .reduced()
                .toString(),
          ),
        ],
      ],
    );
  }

  void _doReverse() {
    try {
      final ms = _reverse.inferParents(
        _revCtrl.text,
        loci: _revLoci == 0 ? null : _revLoci,
      );
      setState(() {
        _revMatches = ms;
        _revError = ms.isEmpty ? '未找到能产生该比例的亲本组合（确认比例写法）' : null;
      });
    } on ArgumentError catch (e) {
      setState(() {
        _revMatches = null;
        _revError = e.message?.toString() ?? '输入格式错误';
      });
    }
  }

  /// N1 反推区：比例输入 + 位点选择 + 候选亲本列表。
  Widget _buildReverseArea() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '输入后代（F1/F2）表型比，枚举能产生它的亲本组合。'
          '如 3:1（一对杂合自交）、1:1（测交）、9:7（互补变式）。',
          style: AppText.caption.copyWith(color: AppColors.graphite),
        ),
        const SizedBox(height: 8),
        // 白板打字痛点：常用比例一键填入
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            for (final r in const [
              '3:1',
              '1:1',
              '9:3:3:1',
              '1:1:1:1',
              '9:7',
              '15:1',
            ])
              ActionChip(
                label: Text(r),
                onPressed: () {
                  _revCtrl.text = r;
                  _doReverse();
                },
              ),
          ],
        ),
        const SizedBox(height: 8),
        // v2.19.26 手机 9:16 实修（157px 右溢出）：输入框(240) +
        // 三段 SegmentedButton(~290) 在 390 宽必炸——改 Wrap 自动换行。
        Wrap(
          spacing: 12,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 240),
              child: TextField(
                controller: _revCtrl,
                style: AppText.genotype,
                decoration: const InputDecoration(
                  isDense: true,
                  labelText: '后代表型比',
                  helperText: '如 3:1 / 9:3:3:1 / 9:7',
                ),
                onSubmitted: (_) => _doReverse(),
              ),
            ),
            // 位点数选择（自动=两侧都试）
            SegmentedButton<int>(
              segments: const [
                ButtonSegment(value: 0, label: Text('自动')),
                ButtonSegment(value: 1, label: Text('一对基因')),
                ButtonSegment(value: 2, label: Text('两对基因')),
              ],
              selected: {_revLoci},
              onSelectionChanged: (s) {
                setState(() => _revLoci = s.first);
                _doReverse();
              },
            ),
          ],
        ),
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton.icon(
            onPressed: _doReverse,
            icon: const Icon(Icons.manage_search_outlined),
            label: const Text('反推亲本'),
          ),
        ),
        if (_revError != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: _ErrorBanner(message: _revError!),
          ),
        if (_revMatches != null && _revMatches!.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text(
            '共 ${_revMatches!.length} 组候选亲本'
            '${_revMatches!.length > 1 ? '（多解：补充亲代表型或测交条件可唯一确定）' : ''}',
            style: AppText.label,
          ),
          const SizedBox(height: 6),
          for (final m in _revMatches!)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '${m.p1} × ${m.p2}（${m.p1Pheno} × ${m.p2Pheno}）',
                      style: AppText.genotype.copyWith(fontSize: 14),
                    ),
                  ),
                  AppChip(m.note),
                ],
              ),
            ),
        ],
      ],
    );
  }

  // 功能 3 错因诊断状态
  final _diagCorrectCtrl = TextEditingController(text: '9:3:3:1');
  final _diagStudentCtrl = TextEditingController(text: '');
  DiagnosisResult? _diagResult;
  String? _diagError;
  final _diag = ErrorDiagnosis();

  void _doDiagnosis() {
    final student = _diagStudentCtrl.text.trim();
    if (student.isEmpty) {
      setState(() {
        _diagResult = null;
        _diagError = '请输入学生答案的比例（如 3:1）';
      });
      return;
    }
    try {
      final r = _diag.diagnose(
        p1: _p1Ctrl.text.trim(),
        p2: _p2Ctrl.text.trim(),
        correctText: _diagCorrectCtrl.text.trim(),
        studentText: student,
      );
      setState(() {
        _diagResult = r;
        _diagError = null;
      });
    } on ArgumentError catch (e) {
      setState(() {
        _diagResult = null;
        _diagError = e.message?.toString() ?? '输入格式错误';
      });
    }
  }

  /// 功能 3 错因诊断区：正解/学生答案比例 + 错因列表。
  Widget _buildDiagnosisArea() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '亲本沿用第 1 步的设定（当前 ${_p1Ctrl.text} × ${_p2Ctrl.text}）。'
          '填题目的标准答案比与学生给出的比例，诊断最可能的错误类型。',
          style: AppText.caption.copyWith(color: AppColors.graphite),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            SizedBox(
              width: 180,
              child: TextField(
                controller: _diagCorrectCtrl,
                style: AppText.genotype,
                decoration: const InputDecoration(
                  isDense: true,
                  labelText: '标准答案比（如 9:3:3:1）',
                ),
              ),
            ),
            SizedBox(
              width: 180,
              child: TextField(
                controller: _diagStudentCtrl,
                style: AppText.genotype,
                decoration: const InputDecoration(
                  isDense: true,
                  labelText: '学生答案比（如 3:1）',
                ),
                onSubmitted: (_) => _doDiagnosis(),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton.icon(
            onPressed: _doDiagnosis,
            icon: const Icon(Icons.medical_services_outlined),
            label: const Text('诊断错因'),
          ),
        ),
        if (_diagError != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: _ErrorBanner(message: _diagError!),
          ),
        if (_diagResult != null) ...[
          const SizedBox(height: 12),
          if (!_diagResult!.correctMatchesEngine)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _ErrorBanner(
                message:
                    '引擎正推为 ${_diagResult!.computedRatio}，'
                    '与题面答案不一致——题目可能含致死/连锁等特殊条件',
              ),
            ),
          if (_diagResult!.studentCorrect)
            Text(
              _diagResult!.causes.isEmpty
                  ? '学生答案正确。'
                  : _diagResult!.causes.join('\n'),
            ),
          for (final c in _diagResult!.causes)
            if (!_diagResult!.studentCorrect)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.personal_injury_outlined,
                      size: 16,
                      color: AppColors.sand,
                    ),
                    const SizedBox(width: 8),
                    Expanded(child: Text(c, style: AppText.body)),
                  ],
                ),
              ),
        ],
      ],
    );
  }

  String _variantName(String mode) {
    // v2.11 M11b：变式名集中到 VariantSpec.displayNames，UI 显示委托
    return VariantSpec.displayName(mode);
  }
}

/// Tab 2（v2.5）：三对基因自由组合计算器（AaBbCc × AaBbCc → 27:9:9:9:3:3:3:1）。
///
/// 布局沿用 9331 样板的两步流程卡（①设定亲本 → ②计算结果），
/// 结果面板复用 n 基因通用的 _DihybridResultPanel（64 格棋盘横向滚动）。
class _TrihybridTab extends StatefulWidget {
  const _TrihybridTab({super.key});

  @override
  State<_TrihybridTab> createState() => _TrihybridTabState();
}

class _TrihybridTabState extends State<_TrihybridTab>
    with AutomaticKeepAliveClientMixin
    implements CrossTabSidePanel {
  @override
  bool get wantKeepAlive => true;
  /// 出厂默认题（判 `isPristine` 的锚点）。⛔ controller 初始化复用它，
  /// 不另写一份字面量。
  static const _kDefaultP1 = 'AaBbCc';
  static const _kDefaultP2 = 'AaBbCc';

  final _p1Ctrl = TextEditingController(text: _kDefaultP1);
  final _p2Ctrl = TextEditingController(text: _kDefaultP2);

  /// 与 tab 0 `_Dihybrid9331TabState` 同款判据（同一页、同一套规矩）。
  /// 判据 = 两个亲本输入框都还等于出厂默认值——三对基因没有别的回填输入框。
  bool get isPristine =>
      _p1Ctrl.text == _kDefaultP1 && _p2Ctrl.text == _kDefaultP2;

  KaojiCalcResult? _result;
  String? _error;
  // v2.19.56（照 v2.19.53 试点）：算出那一刻的亲本输入快照（stale 门
  // 基准）。⛔ 与双基因 tab 的 _diSnap 各自独立，防串。
  String? _triSnap;

  final _kaoji = KaojiCalc();

  /// v2.19.23 找茬 P1#3：controller 显式 dispose（原缺失）。
  @override
  void dispose() {
    _p1Ctrl.dispose();
    _p2Ctrl.dispose();
    super.dispose();
  }

  /// v2.5 拍题识别填参（ModuleFillBus 路由）：外部注入亲本并立即计算。
  void fillFromAi(String p1, String p2) {
    _p1Ctrl.text = p1;
    _p2Ctrl.text = p2;
    _calculate();
  }

  @override
  void initState() {
    super.initState();
    // v2.5 拍题识别路由：待填槽消费（路由到达时本 tab 尚未挂载的情形）
    final page = context.findAncestorStateOfType<_CrossCalculatorPageState>();
    final pf = page?.pendingTri;
    if (pf != null) {
      page!.pendingTri = null;
      _p1Ctrl.text = pf.p1;
      _p2Ctrl.text = pf.p2;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _calculate();
      });
    }
  }

  void _calculate() {
    final p1 = _p1Ctrl.text.trim();
    final p2 = _p2Ctrl.text.trim();
    if (p1.length != 6 || p2.length != 6) {
      setState(() {
        _error = '请输入 6 个字符的基因型（三对等位基因，如 AaBbCc 或 aabbcc）。';
        _result = null;
      });
      return;
    }
    final r = _kaoji.crossAuto(p1: p1, p2: p2);
    if (r.error != null) {
      setState(() {
        _error = r.error;
        _result = null;
      });
      return;
    }
    if (r.notice != null || r.result == null) {
      // 非阻断提示（如三倍体联会紊乱）：无比例可算，按提示展示。
      setState(() {
        _error = r.notice ?? '该组合无法给出标准遗传比例';
        _result = null;
      });
      return;
    }
    setState(() {
      _error = null;
      _result = r.result;
      // v2.19.56：算出即存输入快照（stale 门的基准，照双基因 tab）。
      _triSnap = '$p1|$p2';
    });
    // 上报上下文：AI 助手可直接看到当前输入与结果（同 9331 tab）。
    final res = r.result!;
    final state = AppState.instance;
    state.report('双亲基因型', '$p1 × $p2');
    state.report('P1 配子', res.gametesP1.join('、'));
    state.report('P2 配子', res.gametesP2.join('、'));
    state.report('F2 表型比例', res.phenotypeRatio.toString());
    state.report('F2 基因型比例', res.genotypeRatio.toString());
    state.report('变式类型', res.variantName);
    // v2.6：登记计算历史（☰ 工具抽屉展示/一键恢复）
    context.findAncestorStateOfType<_CrossCalculatorPageState>()?.recordHistory(
      1,
      p1,
      p2,
      res.phenotypeRatio.toString(),
    );
  }

  // v2.19.56（照 v2.19.53 试点）：本节「新鲜度」门——同 _diFresh 口径：
  // 结果存在且算出那一刻的输入快照与现文一致才算数；stale ⇒ 整节剔除
  // （题干/答案/srcModule/srcParams 一并走）⇒ 全节 stale 时答案空串 ⇒
  // saveToMistakeBook 既有「先算出结果」守卫应答。
  bool get _triFresh =>
      _result != null &&
      _triSnap == '${_p1Ctrl.text.trim()}|${_p2Ctrl.text.trim()}';

  /// v2.19.18 去主体化：输入面板（无壳）——宽屏注入 rail 顶部，窄屏
  /// 自渲染（同双基因 tab 模式）。
  @override
  Widget buildSidePanel(BuildContext context) {
    // v2.19.57 找茬 B1：宿主收编为容器页一枚页级宿主（按键按 _tab.index
    // 分派到 savePayload()）——本 tab 不再自挂宿主（跨页签连发根因之一：
    // 访问过的 keep-alive 页签宿主全部存活，同按一枚键各应答各的）。
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('设定亲本基因型', style: AppText.sectionTitle),
        const SizedBox(height: 4),
        Text(
          '三对等位基因共 6 个字符（如 AaBbCc / AaBbCC / aabbcc）',
          style: AppText.caption.copyWith(color: AppColors.steel),
        ),
        const SizedBox(height: 12),
        _buildInputArea(),
      ],
    );
  }

  /// v2.19.57：页级宿主分派入口（同双基因 tab 的 savePayload 口径）。
  SavePayload? savePayload() {
    final fresh = _triFresh;
    final r = fresh ? _result : null;
    return SavePayload(
      stem: fresh
          ? '${_p1Ctrl.text.trim()} × ${_p2Ctrl.text.trim()} 杂交，后代表型比和基因型比分别是？'
          : '',
      correctAnswer: r == null
          ? ''
          : '表型比 ${r.phenotypeRatio}'
              '${r.genotypeRatio != null ? '；基因型比 ${r.genotypeRatio}' : ''}',
      subjectArea: kFreeCombinationSubjectArea,
      // ⛔ 与双基因那页同模式：判据按**本页**的 6 字母档走（共用判据
      // 函数、档位由 moduleId 查表定），不写第二份正则。
      srcModule: fresh ? 'cross_trihybrid' : null,
      srcParams: fresh
          ? _crossSrcParams('cross_trihybrid', _p1Ctrl.text, _p2Ctrl.text)
          : null,
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // AutomaticKeepAliveClientMixin 要求
    final wide = MediaQuery.of(context).size.width >= 1200;
    final r = _result;
    // v2.19.36：同双基因页签（课标 3.2.3）——`cross_trihybrid` 同样唯一反查
    // 3.2.3（3.2.3 正文的「自由组合」那半边），同样只在有结果时挂。
    final badge = r == null
        ? null
        : curriculumReverseBadgeFor(context, 'cross_trihybrid');
    final variant =
        r == null ? null : AppChip(r.variantName, icon: Icons.auto_awesome);
    return SingleChildScrollView(
      // v3.6：底部留出全局「问 AI」FAB 的高度，最后一组结果不被遮。
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 96),
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1400),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (!wide) buildSidePanel(context),
              if (!wide) const SizedBox(height: 28),
              FlatSection(
                title: '计算结果',
                subtitle: r == null
                    ? '设定亲本后点「计算比例」，这里展开配子、64 合子棋盘与 F2 比例'
                    : _withCardHint(
                        '配子 · F2 表型/基因型比例 · 基因型明细',
                        kFreeCombinationSubjectArea,
                      ),
                trailing: badge == null
                    ? variant
                    : Wrap(
                        spacing: 10,
                        alignment: WrapAlignment.end,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [badge, variant!],
                      ),
                child: _buildResultBody(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInputArea() {
    // v2.19.22：亲本输入改竖排（P1 → × → P2 全宽各占一行）——
    // 宽屏 rail 内容宽仅 248px，横排两个 Expanded TextField 的
    // InputDecorator 固有最小宽度叠加溢出 6.9px；竖排与系谱页
    // 杂交面板同款窄宽形态。
    return SizedBox(
      width: double.infinity,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _p1Ctrl,
            style: AppText.genotype,
            decoration: const InputDecoration(labelText: '亲本 1'),
          ),
          const SizedBox(height: 2),
          Padding(
            padding: const EdgeInsets.only(left: 4),
            child: Icon(Icons.close, size: 16, color: AppColors.steel),
          ),
          const SizedBox(height: 2),
          TextField(
            controller: _p2Ctrl,
            style: AppText.genotype,
            decoration: const InputDecoration(labelText: '亲本 2'),
          ),
          const SizedBox(height: 8),
          // 预设 chips：白板免键盘一键载入（同 9331 tab 的 N7 思路）
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (final p in const [
                ('三杂合自交 27:9:…:1', 'AaBbCc', 'AaBbCc'),
                ('测交 1:1:…:1', 'AaBbCc', 'aabbcc'),
                ('两对杂合 AaBbCC', 'AaBbCC', 'AaBbCc'),
              ])
                ActionChip(
                  label: Text(p.$1),
                  onPressed: () {
                    _p1Ctrl.text = p.$2;
                    _p2Ctrl.text = p.$3;
                    _calculate();
                  },
                ),
            ],
          ),
          const SizedBox(height: 16),
          // v2.19.18：Wrap——同双基因，兼容 rail 窄内容宽。
          Wrap(
            spacing: 12,
            runSpacing: 8,
            children: [
              FilledButton.icon(
                onPressed: _calculate,
                icon: const Icon(Icons.calculate_outlined),
                label: const Text('计算比例'),
              ),
              // AI 读题填参（白板免敲基因型），同 9331 tab
              OutlinedButton.icon(
                onPressed: () => showAiFillParams(
                  context,
                  moduleHint:
                      '三对基因自由组合计算器，参数 p1/p2 为亲本基因型，'
                      '各 6 个字符（三对等位基因相邻书写，如 AaBbCc）；'
                      '只输出 {"p1":"...","p2":"..."}',
                  onApply: (params) {
                    final a = params['p1']?.trim();
                    final b = params['p2']?.trim();
                    if (a != null && a.isNotEmpty) _p1Ctrl.text = a;
                    if (b != null && b.isNotEmpty) _p2Ctrl.text = b;
                    _calculate();
                  },
                ),
                icon: const Icon(Icons.content_paste_search_outlined),
                label: const Text('读题填参'),
              ),
              const SizedBox(width: 12),
              OutlinedButton.icon(
                onPressed: () => showAiAssistant(context),
                icon: const Icon(Icons.psychology_outlined),
                label: const Text('AI 解析'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// v2.19.18 结果区内容体（无 StepCard 壳，同双基因 tab）。
  Widget _buildResultBody() {
    final r = _result;
    if (r == null) {
      return _error != null
          ? _ErrorBanner(message: _error!)
          : Padding(
              padding: const EdgeInsets.symmetric(vertical: 18),
              child: Column(
                children: [
                  Icon(
                    Icons.grid_on_rounded,
                    size: 32,
                    color: AppColors.steel.withValues(alpha: 0.45),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    '等待计算：结果将在这里展开',
                    style: AppText.body.copyWith(color: AppColors.steel),
                  ),
                ],
              ),
            );
    }
    // 面板 n 基因通用：8 种配子 × 8 = 64 格棋盘，横向滚动消化。
    return _DihybridResultPanel(
      result: r,
      p1: _p1Ctrl.text.trim(),
      p2: _p2Ctrl.text.trim(),
      srcModule: 'cross_trihybrid',
    );
  }
}

/// 9331 计算结果内容（StepCard 内部，无自身卡片外壳）。
/// v2.4 N6：双视图——「数值」（比例明细）/「板书」（标准遗传图解）。
/// v2.5：面板本身 n 基因通用（配子双重循环 + 逐位点合子合并），
/// 三对基因 tab 直接复用（8×8=64 格棋盘靠板书容器横向滚动消化）。
class _DihybridResultPanel extends StatefulWidget {
  final KaojiCalcResult result;
  final String p1;
  final String p2;

  /// v2.19.37：本栏的来源 moduleId。⛔ 面板 n 基因通用（双基因 9331 与
  /// 三对基因共用同一个面板）⇒ 它自己分不清是哪一页，**必须由调用方
  /// 透传**（`required`：漏传编译期就红，不靠自觉）。
  /// ⛔ 取值与 `ModuleFillBus` 注册的 id 逐字一致（`_tabModuleIds`）——
  /// 写错一个字，回程 `fill` 找不到目标，存下来的就是一枚跳不回本页的
  /// 按钮。
  final String srcModule;
  const _DihybridResultPanel({
    required this.result,
    required this.srcModule,
    this.p1 = 'AaBb',
    this.p2 = 'AaBb',
  });

  @override
  State<_DihybridResultPanel> createState() => _DihybridResultPanelState();
}

class _DihybridResultPanelState extends State<_DihybridResultPanel> {
  bool _board = false; // false=数值视图 true=板书视图
  final _boardKey = GlobalKey(); // 板书截图边界（存为图片用）
  final _valuesKey = GlobalKey(); // v2.13：数值视图截图边界
  bool _exporting = false;
  bool _exportingValues = false;

  /// v2.19.10：导出反馈统一——路径 10s（学生走查 #7：4s 一闪即逝）
  /// + 复制路径 / 打开下载目录（与系谱页板书 PNG 同链，学生验证 P1
  /// 跨页 UX 一致）。SnackBar 单 action 槽装不下两枚 → content Row
  /// 双 TextButton（save_to_mistake_book 同款成熟模式）。
  void _showExportSnack(({String? path, String? error}) r) {
    final path = r.path;
    final messenger = ScaffoldMessenger.of(context);
    if (path == null) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(r.error ?? '导出失败'),
          duration: const Duration(seconds: 4),
        ),
      );
      return;
    }
    messenger.showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 10),
        content: Row(
          children: [
            // v2.19.13（学生找茬 🟡4）：长路径截断单行——原 Text 软换行
            // 2-3 行把 SnackBar 撑高遮底栏。
            Expanded(
              child: Text(
                '已保存：$path',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            TextButton(
              onPressed: () => Clipboard.setData(ClipboardData(text: path)),
              child: const Text('复制路径'),
            ),
            TextButton(
              // 与系谱页一致地消费 openInExplorer 返回值，失败弹提示。
              onPressed: () async {
                final err = await MistakeBookExporter.openInExplorer(path);
                if (err != null && mounted) {
                  messenger.showSnackBar(SnackBar(content: Text(err)));
                }
              },
              child: const Text('打开目录'),
            ),
          ],
        ),
      ),
    );
  }

  /// 板书存为 PNG（v2.4 功能 2：插进老师自己的课件）。
  Future<void> _exportBoard() async {
    setState(() => _exporting = true);
    final r = await captureBoundaryPng(_boardKey, '板书9331');
    if (!mounted) return;
    setState(() => _exporting = false);
    _showExportSnack(r);
  }

  /// v2.13：数值视图（比例明细）存为 PNG——学生发群问老师的完整路径。
  Future<void> _exportValues() async {
    setState(() => _exportingValues = true);
    final r = await captureBoundaryPng(_valuesKey, '计算结果9331');
    if (!mounted) return;
    setState(() => _exportingValues = false);
    _showExportSnack(r);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Align(
          alignment: Alignment.centerRight,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              if (!_board)
                // v2.13：数值视图「存为图片」——与板书视图同权导出，
                // 学生「截图发群问老师」路径在数值视图也完整。
                TextButton.icon(
                  onPressed: _exportingValues ? null : _exportValues,
                  icon: const Icon(Icons.image_outlined, size: 18),
                  label: Text(_exportingValues ? '导出中…' : '存为图片'),
                ),
              if (_board)
                // v2.13 R6-P1：tooltip 提示板书图片「原样保存，不脱敏」——
                // 这是 P1 隐私根因中「照片/截图/板书 SVG 不脱敏」一项
                // 在板书导出的最小缓解。AES-GCM 对像素数据加密属重工程，
                // 推 R7 路线图；本轮先在工具按钮旁挂 tooltip 强提示。
                Tooltip(
                  message: '板书图片原样保存，不做脱敏；导出前请确认不含敏感信息',
                  child: TextButton.icon(
                    onPressed: _exporting ? null : _exportBoard,
                    icon: const Icon(Icons.image_outlined, size: 18),
                    label: Text(_exporting ? '导出中…' : '存为图片'),
                  ),
                ),
              if (_board)
                // v2.6 课堂讲解优化：板书全屏放映——隐藏一切 UI 杂质只留棋盘，
                // 后排可读；格子按屏宽放大、双指可缩放平移细看。
                TextButton.icon(
                  onPressed: () => showCrossBoardPresenter(
                    context,
                    result: widget.result,
                    p1: widget.p1,
                    p2: widget.p2,
                  ),
                  icon: const Icon(Icons.slideshow_outlined, size: 18),
                  label: const Text('放映'),
                ),
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(value: false, label: Text('数值')),
                  ButtonSegment(value: true, label: Text('板书')),
                ],
                selected: {_board},
                onSelectionChanged: (s) => setState(() => _board = s.first),
                style: SegmentedButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        if (_board) _buildBoard() else _buildValuesWrapped(),
      ],
    );
  }

  /// v2.13 学生走查：数值视图也挂 RepaintBoundary——「把这次计算截图
  /// 发群里问老师」此前只有板书视图能导出，数值（比例明细）发不了。
  /// 注意：只包 RepaintBoundary，不加背景装饰 Container——数值区内部
  /// 有 ExpansionTile（27 项明细折叠），ListTile 落在带背景色的
  /// DecoratedBox 里会触发「ink splashes may be invisible」渲染告警，
  /// v25 测试 takeException 会抓住它。
  Widget _buildValuesWrapped() {
    return RepaintBoundary(key: _valuesKey, child: _buildValues());
  }

  /// 板书视图：标准遗传图解（P → 配子 → F1 棋盘 → 表型比）。
  Widget _buildBoard() {
    return RepaintBoundary(
      key: _boardKey,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.canvas,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.border),
        ),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: CrossBoardView(
            result: widget.result,
            p1: widget.p1,
            p2: widget.p2,
          ),
        ),
      ),
    );
  }

  /// 数值视图：原比例明细呈现。
  Widget _buildValues() {
    final r = widget.result;
    final phenoParts = r.phenotypeRatio.parts;
    final total = phenoParts.fold<int>(0, (a, b) => a + b);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _kv('P1 配子', r.gametesP1.join('  ')),
        _kv('P2 配子', r.gametesP2.join('  ')),
        Divider(height: 24, color: AppColors.border.withValues(alpha: 0.6)),
        Text('F2 表型比例', style: AppText.label),
        const SizedBox(height: 2),
        Text(r.phenotypeRatio.toString(), style: AppText.monoFigure),
        if (r.phenotypeRatio.equalsValues(const [9, 3, 3, 1]))
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              VariantSpec.displayName(VariantSpec.standard9331),
              style: AppText.caption.copyWith(color: AppColors.teal),
            ),
          ),
        // v2.13 学生走查 P0：「存入错题本」挨着比例数字（学生视线落点），
        // 不再藏在顶部操作行——算完→收题一步直达。
        // v3.6 结果动作：「在系谱画布展开」把 p1/p2 + 表型比一起带走，
        // 走专用目标 'pedigree_from_cross'（系谱页已算过就追加新家族，
        // 不覆盖；空态则直接算）。老目标 'pedigree' 只填参、脏页即拒，
        // 契约不动——未注册专用目标时回退到它（老版本/独立预览）。
        // 顶部回程横幅（C 统一外壳）保证一键跳回。
        // v3.6：窄屏折行——按钮变长（「在系谱画布展开」）且右下有全局
        // 「问 AI」FAB，Row 会把按钮挤到溢出；Wrap 放不下就换行。
        Wrap(
          alignment: WrapAlignment.end,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 10,
          runSpacing: 8,
          children: [
            FilledButton.tonalIcon(
              onPressed: () => openCrossInPedigree(
                p1: widget.p1,
                p2: widget.p2,
                ratio: r.phenotypeRatio.toString(),
              ),
              icon: const Icon(Icons.account_tree_outlined, size: 18),
              label: const Text('在系谱画布展开'),
            ),
            SaveToMistakeBookButton(
              stem: '${widget.p1} × ${widget.p2} 杂交，后代表型比和基因型比分别是？',
              correctAnswer:
                  '表型比 ${r.phenotypeRatio}'
                  '${r.genotypeRatio != null ? '；基因型比 ${r.genotypeRatio}' : ''}',
              subjectArea: kFreeCombinationSubjectArea,
              // 本面板拿不到 controller，用它构造时透传进来的
              // srcModule + p1/p2（与题干同一个来源 ⇒ 记下的亲本与屏上
              // 题干逐字一致）。⛔ 判据同 `_crossSrcParams`：回程填不进去
              // 的亲本返回 null ⇒ 不记（宁缺勿滥）。
              srcModule: widget.srcModule,
              srcParams: _crossSrcParams(
                  widget.srcModule, widget.p1, widget.p2),
            ),
          ],
        ),
        const SizedBox(height: 12),
        for (var i = 0; i < r.phenotypeLabels.length; i++) ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: AppColors.canvas,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: AppColors.border.withValues(alpha: 0.5),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '表型 ${r.phenotypeLabels[i]}',
                    style: AppText.body,
                  ),
                ),
                Text(
                  '${phenoParts[i]}/$total',
                  style: AppText.caption.copyWith(color: AppColors.steel),
                ),
                const SizedBox(width: 10),
                RatioPill(text: '${phenoParts[i]}'),
              ],
            ),
          ),
          const SizedBox(height: 8),
        ],
        Divider(height: 24, color: AppColors.border.withValues(alpha: 0.6)),
        _kv('F2 基因型比例', r.genotypeRatio.toString()),
        const SizedBox(height: 10),
        Text('基因型明细', style: AppText.label),
        const SizedBox(height: 6),
        // v2.5：三对基因基因型最多 27 项，平铺过长——超过 12 项折叠为
        // ExpansionTile + Wrap chips 网格（≤12 项走原分支，渲染不变）。
        if (r.genotypeLabels.length <= 12)
          _genotypeChips(r)
        else
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            childrenPadding: const EdgeInsets.only(top: 6),
            title: Text(
              '共 ${r.genotypeLabels.length} 项，点开展开',
              style: AppText.caption.copyWith(color: AppColors.steel),
            ),
            children: [_genotypeChips(r)],
          ),
      ],
    );
  }

  /// 基因型明细 chips 网格（双/三基因共用，树结构与 v2.4 一致）。
  Widget _genotypeChips(KaojiCalcResult r) {
    return Wrap(
      spacing: 8,
      runSpacing: 6,
      children: r.genotypeLabels
          .map(
            (g) => Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.canvas,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: AppColors.border),
              ),
              child: Text(g, style: AppText.monoSmall),
            ),
          )
          .toList(),
    );
  }

  Widget _kv(String k, String v) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(width: 110, child: Text(k, style: AppText.caption)),
        Expanded(child: Text(v, style: AppText.monoSmall)),
      ],
    ),
  );
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.lethal.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppTheme.radiusInput),
        border: Border.all(color: AppColors.lethal.withValues(alpha: 0.35)),
      ),
      child: Row(
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
  }
}

class _VariantRow extends StatelessWidget {
  const _VariantRow({required this.name, required this.ratio});

  final String name;
  final String ratio;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: Text(name, style: AppText.body)),
        RatioPill(text: ratio),
      ],
    );
  }
}
