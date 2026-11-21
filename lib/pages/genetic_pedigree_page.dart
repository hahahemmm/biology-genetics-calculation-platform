// genetic_pedigree_page.dart —— 遗传图谱计算页（UI 层重写）
//
// 页面只与 PedigreeGraphEngine 对话（契约见 docs/tasks/pedigree_api_contract.md）：
//  - 「计算」= recomputeFrom(0)，外来样本与连线参与重算（R5）；
//  - 「再计算一代」= expandNextGeneration，无穷懒世代，20 代安全阀（R6）；
//  - 右键空白添加样本（R3）、点选-点选连线（R12）、点击选中（R1）；
//  - 全屏按钮（R8）、滚轮/Ctrl+滚轮/空白拖手势（R9）都在 PedigreeCanvas 内。
//
// 金色测试依赖：按钮文案「计算」、默认双亲输入 AABBCC / aabbcc —— 不可改。

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;

import '../engine/kaoji_calc.dart';
import '../engine/linkage_engine.dart';
import '../engine/pedigree_graph.dart';
import '../state/app_state.dart';
import '../state/history_store.dart';
import '../state/present_mode_controller.dart';
import '../state/mistake_book.dart';
import '../storage/platform_storage_io.dart'
    if (dart.library.html) '../storage/platform_storage_web.dart';
// v2.12+ R2 P0-A1：Web 端板书下载条件导入
import '../ui/board_save_stub.dart'
    if (dart.library.html) '../ui/board_save_web.dart';
import '../theme.dart';
import '../ui/ai_chat_controller.dart';
import '../ui/assistant_panel.dart';
import '../ui/cross_pedigree_link.dart';
import '../ui/module_fill.dart';
import '../ui/module_surface.dart';
import '../ui/png_export.dart';
import '../ui/share_file.dart';
import '../ui/svg_export.dart';
import 'widgets/pedigree_canvas.dart';
import 'widgets/pedigree_canvas_area.dart';
import 'widgets/pedigree_bottom_bar.dart';
import 'widgets/pedigree_command_bar.dart';
import 'widgets/pedigree_cross_panel.dart';
import 'widgets/pedigree_detail_strip.dart';
import 'widgets/pedigree_dialogs.dart';
import 'widgets/pedigree_edge_focus.dart';
import 'widgets/pedigree_linkage_panel.dart';
import 'widgets/pedigree_side_panel.dart';

/// R15 画布交互模式：浏览（点=看信息，拖=平移，手机端友好）/
/// 连线（点选-点选配对）/ 选择元素（多选后折叠未选中的桶）。
enum _CanvasMode { browse, wire, select }

/// R16 操作日志条目：操作描述 + 操作完成后的引擎快照（回退目标）+
/// R21 家族手动偏移快照（移动家族位置也入日志，回退时恢复位置）。
/// v2.19.6：+选择/聚焦视图态（picked/focusSet/mode）——「选择元素/
/// 显示全部」入日志后，回退恢复的不只是引擎快照，还有当时的选择集。
class _LogEntry {
  final String label;
  final PedigreeSnapshot snapshot;
  final Map<int, Offset> familyOffsets;

  /// 视图态（可空 = 旧日志条目，回退时按"清空瞬态"处理）。
  final Set<String>? picked;
  final Set<String>? focusSet;
  final _CanvasMode? mode;
  const _LogEntry(this.label, this.snapshot,
      [this.familyOffsets = const {},
      this.picked,
      this.focusSet,
      this.mode]);
}

class GeneticPedigreePage extends StatefulWidget {
  /// v3.3：HomeShell 侧栏折叠联动（折叠时隐藏本页左控制面板）与
  /// ☰ 入口（命令栏最左）；独立构造（测试）时均为默认值 → 不渲染 ☰。
  const GeneticPedigreePage(
      {super.key, this.navCollapsed = false, this.onNavPressed});

  final bool navCollapsed;
  final VoidCallback? onNavPressed;

  // ── 跨端持久化测试 hook（v2.12 R1 C P0 #7）────────────────
  //
  // 9331 杂交面板展开状态走 platform_storage 中性 API：桌面 / 安卓
  // File，Web localStorage。下面三个 static hook 让 flutter_test 在
  // 没有 window 对象时也能验证 web round-trip 链路。放在公开
  // `GeneticPedigreePage` 类上（不是私有 `_GeneticPedigreePageState`），
  // test 跨 import 边界可访问。

  /// 测试注入：非空时 load / save 走该文件而非用户目录。
  @visibleForTesting
  static String? debugFilePath;

  /// 测试注入：mock Web 端 localStorage。flutter_test 无 window 对象
  /// （`package:web` 的 `localStorage` 不可用），此 hook 让
  /// `test/genetic_pedigree_page_test.dart` 能验证 web 端 round-trip
  /// 链路（toggle 写 localStorage → load 读回 → _crossOpen 一致）。
  @visibleForTesting
  static Map<String, String>? debugWebStorage;

  /// 测试注入：mock `isWebStorage` 标志。非空时强制走 web / desktop 路径。
  /// 配合 `debugWebStorage` 模拟"用户在浏览器中"的完整链路。
  @visibleForTesting
  static bool? debugForceIsWebStorage;

  /// 测试专用：清静态 hook（debugFilePath / debugWebStorage / debugForceIsWebStorage
  /// / debugBoardHistoryDirForTest / debugEncodeDelayMs）。**不**触碰磁盘 / localStorage。
  @visibleForTesting
  static void debugResetHooks() {
    debugFilePath = null;
    debugWebStorage = null;
    debugForceIsWebStorage = null;
    debugBoardHistoryDirForTest = null;
    debugEncodeDelayMs = 0;
  }

  /// v2.13 R3 P1-D1 测试注入：mock「PNG 解码/裁剪/编码」耗时（毫秒）。
  /// >0 时 `_cropEncodePng` 开头 `sleep` 该时长——native 端 sleep 发生在
  /// isolate 里，UI 线程不受影响；测试借此断言编码不在 UI 线程
  /// （冻结回归检测）。默认 0 = 不生效。
  @visibleForTesting
  static int debugEncodeDelayMs = 0;

  /// v2.12+ R2 P0-A1：测试注入——非空时 `_saveAsBoard` 写盘走该目录而非
  /// `userAppDir()/board_history/`。test 用临时目录隔离写盘（避免污染
  /// 真实 `~/.biology_app/board_history/`）。该 hook 是临时实现——
  /// v2.13 计划把 _saveAsBoard 路径注入提到 MistakeBookExporter
  /// 同款「debugSaveDir」风格（统一 save 路径 mock 入口）。
  @visibleForTesting
  static String? debugBoardHistoryDirForTest;

  @override
  State<GeneticPedigreePage> createState() => _GeneticPedigreePageState();
}

class _GeneticPedigreePageState extends State<GeneticPedigreePage> {
  // 默认双亲输入不可改（金色测试依赖）
  //
  // v2.19.32：出厂值提为**具名常量**，与下面的 `isPristine` 共用同一份真相
  // （本项目被「影子常量」坑过——重复定义被 `dart analyze` 抓到，两边一定分叉）。
  static const _kDefaultP1 = 'AABBCC';
  static const _kDefaultP2 = 'aabbcc';

  final _p1Ctrl = TextEditingController(text: _kDefaultP1);
  final _p2Ctrl = TextEditingController(text: _kDefaultP2);

  PedigreeGraphEngine? _engine;
  String? _fatherUsed;
  String? _motherUsed;
  String? _selectedId;
  String? _error;

  /// 折叠：key=家族:世代（如 '0:2'）。不在集合中的 (家族,世代) 只显示
  /// 概率最高的桶（同概率取基因型字母序首个，保证确定性）；外来样本
  /// 始终显示。R26：每家族每代独立折叠（每个 F1/F2 都有 +N 芯片）。
  final Set<String> _expandedKeys = {};

  /// R12 点选-点选连线：待命的第一个节点 id（画布画紫罗兰光晕）。
  /// R15 起可携带组合桶半边合成 id（'桶id::male/::female'）。
  String? _armedId;

  /// R15 画布交互模式（默认浏览：点节点只看信息，不再常驻连线）。
  _CanvasMode _mode = _CanvasMode.browse;

  /// 选择模式勾选集（可含组合桶半边合成 id）。
  final Set<String> _picked = {};

  /// 聚焦集合：「确定」后未选中的桶折叠隐藏（纯视图态，不删除节点）；
  /// null = 不聚焦。再点按钮（显示全部）恢复。
  Set<String>? _focusSet;

  /// R16 操作日志：第 0 条 = 初始计算后的状态（回退封顶处，不存在
  /// 「-1 步」）；之后每条 = 一次结构操作完成后的快照。
  final List<_LogEntry> _opLog = [];

  /// 连线成功瞬间闪光的双节点（画布画琥珀橙光晕），约 2 秒后清除。
  /// 用户裁定（2026-10-27）：闪光要能被看见（1 秒太短），但必须
  /// **自己熄灭**——一轮配对结束后不留下任何常驻光，才不干扰下一轮。
  Set<String> _flashIds = {};
  Timer? _flashTimer;
  static const Duration _kFlashDuration = Duration(seconds: 2);

  /// v3.5 多模态截图：画布 RepaintBoundary 与画布 State 的双 key
  ///（仅页面内嵌画布挂载；全屏 Dialog 不挂，避免 GlobalKey 冲突）。
  final _canvasBoundaryKey = GlobalKey();
  final _canvasStateKey = GlobalKey<PedigreeCanvasState>();
  // v2.18 P0：全屏 Dialog 专用 key——内嵌画布与全屏画布同时挂在树
  // 上（Dialog 叠加不卸载内嵌实例），共用同一 GlobalKey 会触发
  // duplicate-GlobalKey 使 Dialog 构建失败：整窗变灰、ESC 失效，
  // 只能重启（用户实测）。两套 key 各管各的渲染句柄。
  final _fsBoundaryKey = GlobalKey();
  final _fsCanvasStateKey = GlobalKey<PedigreeCanvasState>();
  /// 全屏 Dialog 的局部重建句柄：页面每次 setState 同步刷新全屏，
  /// 但两侧 PedigreeCanvasState 仍各自管理缩放和平移。
  StateSetter? _fullscreenSetState;

  /// 线路可见性：主干线（lineage 灰总线）/ 回交线（跨代 mating 彩色）。
  bool _showLineage = true;
  bool _showBackcross = true;

  /// 逐条隐藏的回交边（key 见 backcrossEdgeKey；调色板菜单里逐条开关）。
  final Set<String> _hiddenBackcross = {};

  /// 「全部连线」视图开关（默认关 = 智能密线）。
  ///
  /// 智能密线只在**画布输入**层抽稀自动推导的 lineage 边（见
  /// widgets/pedigree_edge_focus.dart）：引擎 edges 一条不删，学生手连的
  /// 回交/连线全留；打开本开关则原样铺满所有自动边。与「显示全部」
  /// （聚焦恢复动作）是两件不同的事，互不代偿。
  bool _showAllEdges = false;

  // ── 9331 → 系谱 桥接的参考表型比例 ────────────────────────
  /// 来自计算器的**参考**表型比例（如 9:3:3:1）。⛔ 不是引擎结论：
  /// 系谱引擎按孟德尔分离逐代模拟，不建模基因互作，9:7 / 15:1 之类
  /// 变式绝不会被它「自动推出」——所以这里按参考值显式标注来源。
  String? _crossRefRatio;
  String? _crossRefSource;
  String? _crossRefGenotypes;

  /// 「参考表型比例」在 AppState 上下文里的键。
  ///
  /// ⚠️ 上报**只**经 `_report` 同步（见该方法注释）：桥接带入时直接写
  /// AppState 会与「双亲基因型」脱钩——追加家族后主输入还是旧亲本，AI 会把
  /// 参考比例误挂到旧双亲上（交付前复核 MEDIUM）。收敛进 `_report`
  /// 还有第二个好处：手动重算清空字段后，同一条路径会顺手把旧键摘掉。
  static const String _kRefRatioKey = '参考表型比例';

  /// 引擎语义开关（页面持有；引擎因双亲变更重建后要重新应用）。
  bool _allowSameSex = false;
  bool _allowMissingGene = false; // R18：允许基因缺失交配（默认关）

  /// R18 画布锁：锁定后禁缩放/平移，可按住家族横幅整体拖动该家族。
  bool _canvasLocked = false;

  /// R23/R25 相连元素（与选中/待命节点有边相连）→ 画布柔光，
  /// 粒度到性别半边：baseId → 相连那侧 kind 集合。
  Map<String, Set<PedigreeNodeKind>> _connectedIds = const {};

  /// R18 家族手动位移（世界坐标偏移）：只影响对应家族及其附属节点，
  /// 连线随节点矩形自动跟随；其他家族不动。视图态，不进快照。
  final Map<int, Offset> _familyOffsets = {};
  /// R16 起默认开启（常驻）：桶渲染为组合体（内含 雄□/雌○），
  /// 用户手动点「XY 性别」chip 才能关闭。
  bool _trackSex = true;
  SexLinkedConfig? _sexLinked; // 伴性遗传配置（null=不启用）

  /// v3.6 连锁互换（两点连锁模型；独立于谱系树，只影响本区块展示）。
  bool _linkageOn = false;
  final _linkageEngine = LinkageEngine();
  final _linkageP1Ctrl = TextEditingController(text: 'AB/ab');
  final _linkageP2Ctrl = TextEditingController(text: 'ab/ab');
  final _linkageRCtrl = TextEditingController(text: '20%');
  LinkageResult? _linkageResult;
  String? _linkageError;

  /// v2.1 多倍体开关：开启后放行 1~5n（每对位点 1~5 份等位，如 'Aaa'）。
  bool _allowPolyploid = false;
  /// v2.1 位点致死筛选（第一对位点）：null='AA'/'Aa'/'aa'。
  String? _lethalGenotype;

  // ── v3.8 9331 杂交计算面板（右侧折叠）─────────────────────
  // 常驻关闭的持久开关：默认关，状态写 ~/.biology_app/cross_panel.json；
  // 懒计算——只有点「开始计算」才调引擎，改输入/点元素都不触发计算。
  bool _crossOpen = false;
  final _crossP1Ctrl = TextEditingController();
  final _crossP2Ctrl = TextEditingController();
  final _crossKaoji = KaojiCalc();
  AutoCrossResult? _crossResult;

  /// 「开始计算」时输入的快照：之后改输入会在结果区提示「结果已过期」。
  String _crossSnapshot = '';
  int _crossNextSlot = 1; // 轮流填充：1=下一个填亲本1，2=亲本2

  @override
  void setState(VoidCallback fn) {
    super.setState(fn);
    // showDialog 是独立路由，默认不会跟随本页重建。全屏打开期间，
    // 任意页面状态变化都同时刷新其 StatefulBuilder；关闭后句柄清空。
    _fullscreenSetState?.call(() {});
  }

  @override
  void dispose() {
    ModuleFillBus.unregister('pedigree');
    ModuleFillBus.unregister('pedigree_from_cross');
    _flashTimer?.cancel();
    _p1Ctrl.dispose();
    _p2Ctrl.dispose();
    _linkageP1Ctrl.dispose();
    _linkageP2Ctrl.dispose();
    _linkageRCtrl.dispose();
    _crossP1Ctrl.dispose();
    _crossP2Ctrl.dispose();
    super.dispose();
  }

  bool get _computed => _engine != null;

  /// v2.19.32：这一页现在**还是出厂状态吗**（学生一处都没动过）？
  ///
  /// 供 `ModuleFillTarget.canOverwrite` 用：学生在系谱页建了自己的家族之后，
  /// 再从「考纲覆盖」点深链，**不该把他那张系谱图无声顶掉**。
  ///
  /// 判据 = 两个亲本输入框都还等于出厂常量 **且 引擎还是 null**。
  ///
  /// ⚠️ 为什么**必须**纳入 `_engine == null`：`_applyAiParams` 走 `_derive()`，
  /// 而 `_derive` 在双亲变了时会**重建引擎**——重建会**丢失学生加进来的外来
  /// 样本与连线**。学生只点了一次「计算」（双亲仍是出厂值、输入框一个字没动），
  /// 系谱图就已经是他的了 ⇒ 只比输入框**判不出来**，必须看引擎活没活。
  /// ⇒ 所以「引擎已活」= 出厂状态的反面。
  bool get isPristine =>
      _engine == null &&
      _p1Ctrl.text == _kDefaultP1 &&
      _p2Ctrl.text == _kDefaultP2;

  /// v2.19.32：`apply` 拒收本次参数时的**用户可见**反馈。
  ///
  /// 文案直接用总线给的 `reason`（`kModuleFillSkippedDirty`）；⛔ 不用
  /// 「你现在看到的是默认题」去解释「我们主动决定不写」，那是**假话**。
  /// ⚠️ 文案不含 markdown 星号，也不用「上面/下面」方向词。
  void _onApplyFailed(String moduleId, String reason) {
    debugPrint('[pedigree] 深链未写入：module=$moduleId reason=$reason');
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
    _history = [];
    _loadHistory();
    _loadCrossPanel();
    _loadEdgeStyle();
    _loadSameSexPref();
    // 输入变化只刷新「结果过期」提示，绝不触发计算（懒计算纪律）
    _crossP1Ctrl.addListener(_onCrossInputChanged);
    _crossP2Ctrl.addListener(_onCrossInputChanged);
    // v2.9 拍题识别动作路由：AI 识别出系谱/家族题 → 标准动作序列（创建家族/添加样本/计算下一代）。
    ModuleFillBus.register(ModuleFillTarget(
      moduleId: 'pedigree',
      pageIndex: 1, // 主导航「遗传图谱」页
      label: '遗传图谱',
      apply: _applyAiParams, // 兜底：params {father,mother} 作初始双亲直接计算
      applyActions: _applyAiActions,
      // v2.19.32：系谱页里已经有学生自己建的家族 ⇒ 深链**不覆盖**。
      // ⚠️ 拦的不只是输入框：`_derive` 会重建引擎、丢掉外来样本与连线。
      canOverwrite: () => isPristine,
      onApplyFailed: _onApplyFailed,
    ));
    // 9331 计算器 → 系谱的专用目标：把 p1/p2 + 参考表型比带进来。
    // 与上面的 'pedigree'（拍题/深链，污染即拒）分开：
    //   · 出厂空态 → 填入并计算；
    //   · 学生已有系谱 → **追加新家族**（原图一条边都不动），不覆盖、
    //     也不静默拒绝。
    ModuleFillBus.register(ModuleFillTarget(
      moduleId: 'pedigree_from_cross',
      pageIndex: 1,
      label: '遗传图谱',
      apply: _applyCrossRef,
    ));
  }

  void _onCrossInputChanged() {
    if (mounted && _crossResult != null) setState(() {});
  }

  // ── v2.9 拍题识别：AI 标准动作序列执行端点 ─────────────
  /// 兜底填参：params {father,mother} 作初始双亲直接计算（无动作时的回退）。
  bool _applyAiParams(Map<String, String> params) {
    final father = params['father']?.trim() ?? params['p1']?.trim() ?? '';
    final mother = params['mother']?.trim() ?? params['p2']?.trim() ?? '';
    if (father.isEmpty || mother.isEmpty) return false;
    _p1Ctrl.text = father;
    _p2Ctrl.text = mother;
    _derive();
    return _engine != null;
  }

  // ── 9331 → 系谱：携带 p1/p2 + 参考表型比例 ────────────────
  /// `pedigree_from_cross` 目标的填参入口（9331 结果区「在系谱画布展开」）。
  ///
  /// 与 `pedigree`（拍题/深链，脏页即拒）的差别只有一处：**不拒收**。
  /// 出厂空态 → 填入并计算；学生已有系谱 → 作为新家族追加
  /// （addFamily 只加 P 代双亲 + 一条 mating 边，不重算、不删既有节点 /
  /// 连线 / 外来样本），原图一条边都不动。
  ///
  /// [params]：`p1`/`p2`（兼容 `father`/`mother`）+ `ratio` + `sourceLabel`。
  /// ratio 只作**参考表型比例**显示与上报 —— 系谱引擎按孟德尔分离逐代
  /// 模拟，不建模基因互作，9:7 / 15:1 等变式不会被它自动推出。
  bool _applyCrossRef(Map<String, String> params) {
    final p1 = (params['p1'] ?? params['father'] ?? '').trim();
    final p2 = (params['p2'] ?? params['mother'] ?? '').trim();
    if (p1.isEmpty || p2.isEmpty) return false;
    final ratio = params['ratio']?.trim() ?? '';
    final rawSource = params['sourceLabel']?.trim() ?? '';
    final source = rawSource.isEmpty ? '9331 杂交计算' : rawSource;
    var appendedFamily = false;
    if (_engine == null) {
      // 空态（或只改了输入框还没点「计算」）：填入并计算。
      _p1Ctrl.text = p1;
      _p2Ctrl.text = p2;
      _derive();
      if (_engine == null) return false;
    } else {
      final engine = _engine!;
      try {
        final k = engine.addFamily(fatherGenotype: p1, motherGenotype: p2);
        // 只追加 P 代双亲 + 一条 mating 边；该家族的 F1 由「计算下一代」
        // 产出（与「添加家族」同一语义），不推进既有家族。
        setState(_clearFocus);
        _pushLog('$source 追加家族 ${engine.familyLabel(k)}：$p1 × $p2');
        _appendHistory();
        appendedFamily = true;
      } catch (e) {
        _toast('无法追加家族：$e');
        return false;
      }
    }
    setState(() {
      _crossRefRatio = ratio.isEmpty ? null : ratio;
      _crossRefSource = source;
      _crossRefGenotypes = '$p1 × $p2';
      // 右侧杂交面板同步呈现同一道原题，不再出现左边已填、右边空白
      // 的“题目丢失”错觉；结果仍由本面板自己的公开引擎计算。
      _crossP1Ctrl.text = p1;
      _crossP2Ctrl.text = p2;
      _startCross();
    });
    // 上报统一走 `_report`：它会把「参考表型比例」与本字段的
    // p1 × p2 / 来源 / 「参考值；非引擎推算」一起写进 AppState，
    // 并同时保留旧主输入的「双亲基因型」（追加家族时主输入仍是旧亲本）。
    _report(_p1Ctrl.text, _p2Ctrl.text);
    final refNote = ratio.isEmpty ? '' : '；参考表型比 $ratio（非引擎推算）';
    _toast(appendedFamily
        ? '已把 $p1 × $p2 作为新家族追加（保留原系谱）$refNote'
        : '已按 $p1 × $p2 计算$refNote');
    return true;
  }

  /// 执行 AI 标准动作序列（按序）。
  /// create_family → engine.addFamily；add_external → engine.addExternal；
  /// next_generation → _expandNext。全部失败返回 false（面板提示）。
  bool _applyAiActions(List<Map<String, String>> actions) {
    if (actions.isEmpty) return false;
    var ok = 0;
    final errors = <String>[];
    setState(() {
      for (final a in actions) {
        try {
          switch (a['type']) {
            case 'create_family':
              final father = a['father']?.trim() ?? '';
              final mother = a['mother']?.trim() ?? '';
              if (father.isEmpty || mother.isEmpty) {
                errors.add('创建家族需要 father/mother 基因型');
                continue;
              }
              _createFamilyFromAi(father, mother);
              ok++;
            case 'add_external':
              if (_addExternalFromAi(a)) {
                ok++;
              } else {
                errors.add('添加样本失败（基因型/世代不合法或引擎未计算）');
              }
            case 'next_generation':
              if (_engine == null) {
                errors.add('计算下一代前请先创建家族');
                continue;
              }
              _expandNext();
              ok++;
          }
        } catch (e) {
          errors.add('$e');
        }
      }
    });
    if (ok > 0) {
      _toast(errors.isEmpty
          ? 'AI 已执行 $ok 个动作（可继续点「计算下一代」推演）'
          : 'AI 已执行 $ok 个动作，部分失败：${errors.first}');
    } else {
      _toast(errors.isEmpty ? 'AI 动作无法识别' : 'AI 动作执行失败：${errors.first}');
    }
    return ok > 0;
  }

  /// create_family：引擎未计算时作初始双亲（走 _derive 全量校验/报告）；
  /// 已有计算结果时 addFamily 追加独立家族。
  void _createFamilyFromAi(String father, String mother) {
    final engine = _engine;
    if (engine == null) {
      _p1Ctrl.text = father;
      _p2Ctrl.text = mother;
      _derive();
      return;
    }
    final k = engine.addFamily(fatherGenotype: father, motherGenotype: mother);
    _pushLog('AI 添加家族 ${engine.familyLabel(k)}：$father × $mother');
    _appendHistory();
  }

  /// add_external：向指定世代添加外来样本（默认第 1 代、male）。
  bool _addExternalFromAi(Map<String, String> a) {
    final engine = _engine;
    if (engine == null) return false;
    final genotype = a['genotype']?.trim() ?? '';
    if (genotype.isEmpty) return false;
    final kindStr = a['kind']?.trim() ?? 'male';
    final kind = kindStr == 'female'
        ? PedigreeNodeKind.female
        : kindStr == 'group'
            ? PedigreeNodeKind.group
            : PedigreeNodeKind.male;
    final gen = int.tryParse(a['generation']?.trim() ?? '1') ?? 1;
    final family = int.tryParse(a['family']?.trim() ?? '0') ?? 0;
    try {
      if (kind == PedigreeNodeKind.group) {
        engine.addExternalGroup(
            generation: gen, genotype: genotype, familyId: family);
      } else {
        engine.addExternal(
            generation: gen, kind: kind, genotype: genotype, familyId: family);
      }
      _pushLog('AI 添加样本：$genotype（第 $gen 代）');
      _appendHistory();
      return true;
    } catch (_) {
      return false;
    }
  }

  // ── 测试钩子（私有成员跨库 dynamic 调用不到，公开委托）──
  @visibleForTesting
  void debugImportToCross(String genotype) => _importToCross(genotype);
  @visibleForTesting
  String get debugCrossP1 => _crossP1Ctrl.text;
  @visibleForTesting
  String get debugCrossP2 => _crossP2Ctrl.text;
  @visibleForTesting
  int get debugCrossNextSlot => _crossNextSlot;
  /// v2.12.0+2 hotfix：测试可调 _exportCanvasSvg 验证
  /// pedigreeToSvg 调用链。
  @visibleForTesting
  Future<void> debugExportCanvasSvg() => _exportCanvasSvg();

  // ── R5 计算：重算（外来样本/连线参与） ─────────────────
  void _derive({bool announce = true}) {
    final p1 = _p1Ctrl.text.trim();
    final p2 = _p2Ctrl.text.trim();
    // 严格 2n 模式保持「成对字母」校验（金色测试依赖）；多倍体模式下
    // 每位点 1~5 份等位、串长可为奇数（形态合法性交给引擎校验）。
    final shapeOk = _allowPolyploid
        ? (p1.isNotEmpty && p2.isNotEmpty)
        : (p1.isNotEmpty &&
            p2.isNotEmpty &&
            p1.length % 2 == 0 &&
            p2.length % 2 == 0);
    if (!shapeOk) {
      setState(() {
        _error = '请输入有效的基因型（成对字母，如 AaBb / aabb）。';
      });
      return;
    }
    // 双亲基因对数默认须一致（不等长亲本在杂交合并时无定义）；
    // 开启「允许基因缺失交配」后放行（缺失按 '-' 补齐）。
    if (!_allowMissingGene && p1.length != p2.length) {
      setState(() {
        _error = '双亲基因对数需一致（如 AaBb × aabb 都是 2 对）；'
            '或开启「允许基因缺失交配」。';
      });
      return;
    }
    var fresh = false;
    try {
      // 双亲变了才重建引擎（重建会丢失外来样本与连线）
      if (_engine == null || _fatherUsed != p1 || _motherUsed != p2) {
        _engine = PedigreeGraphEngine(fatherGenotype: p1, motherGenotype: p2);
        _fatherUsed = p1;
        _motherUsed = p2;
        _selectedId = null;
        _armedId = null;
        _flashIds = {};
        _flashTimer?.cancel();
        _flashTimer = null;
        _opLog.clear(); // 全新引擎 → 日志从头开始
        _familyOffsets.clear(); // 布局重建，旧家族位移失效
        fresh = true;
      }
      // 开关是页面级状态，重建引擎后必须重新应用
      _engine!
        ..allowSameSexMating = _allowSameSex
        ..allowMissingGeneMating = _allowMissingGene
        ..trackSex = _trackSex
        ..sexLinked = _sexLinked
        // v2.1 多倍体 / 位点致死筛选（引擎已由 Worker A 扩展）
        ..allowPolyploid = _allowPolyploid
        ..lethalGenotype = _lethalGenotype;
      _engine!.recomputeFrom(0);
      // 覆盖所有 mating 边的子代世代：回交/连线的子代必须真正出现，
      // 否则「连线 + 计算」看不到任何结果（首次计算也因此至少有 F1）。
      // R20：删除整代把前沿截到 0 后，点「计算」应重新推导出 F1
      //（否则用户删了 F1 就再也算不回来，见 R20 反馈）。
      _engine!.ensureOffspringCoverage();
      if (_engine!.maxGeneration == 0) {
        _engine!.expandNextGeneration();
      }
      _clearFocus();
      // 手动重算 = 当前图谱已按输入框重新推导，9331 桥接带来的参考比例
      // 不再对应这张图（LOW：重算后横幅仍挂着旧比例，且 AppState 里也还
      // 留着——学生随后改主输入点「计算」，AI 看到的却是上一题的参考值）。
      // 只在本方法**算成功**之后清；上面的形状 / 基因对数校验与 catch 分支
      // 都是失败路径，不动仍有效的旧参考。
      _crossRefRatio = null;
      _crossRefSource = null;
      _crossRefGenotypes = null;
      _pushLog(fresh ? '初始计算：$p1 × $p2' : '重新计算');
      setState(() => _error = null);
      _report(p1, p2);
      _appendHistory(); // v2.1 自动记录本次计算
      // P0-7：算成功要有文字确认——只有画面变化 + 顶栏 chip 太安静，
      // 老师不知道自己有没有算成功。预置路径传 announce:false，只留一条。
      if (announce) _toast(deriveSuccessMessage(_engine!));
    } on StateError catch (e) {
      setState(() => _error = '计算受限：${e.message}');
    } on ArgumentError catch (e) {
      setState(() => _error = '计算受限：${e.message}');
    } catch (e) {
      setState(() => _error = '计算出错：$e');
    }
  }

  // ── R6 再计算一代（懒扩展，不写死代数） ───────────────
  void _expandNext() {
    final engine = _engine;
    if (engine == null) return;
    try {
      engine.expandNextGeneration();
      _pushLog('计算下一代 → F${engine.maxGeneration}');
      setState(_clearFocus);
      _appendHistory(); // v2.1 自动记录新世代
    } on StateError {
      _toast('已达安全上限（20 代），无法继续计算。');
    }
  }

  // ── R15 三态交互：浏览 / 连线 / 选择元素 ─────────────────────
  /// 统一入口：普通节点 tapId=节点 id；组合桶半边 tapId=合成 id
  /// （见 halfTapId：'桶id::male/::female'）。
  void _handleTap(String tapId) {
    final engine = _engine;
    switch (_mode) {
      case _CanvasMode.browse:
        // 浏览：只选中看信息，不连线（手机端可放心拖动画布）
        setState(() {
          _selectedId = tapId;
          _connectedIds = _connectedOf(tapId);
        });
        // v3.8：杂交面板打开时，点选元素基因型轮流填入亲本框（只填不算）
        if (_crossOpen) _autoFillFromTap(tapId);
        return;
      case _CanvasMode.select:
        // 选择：toggle 勾选集（雄/雌半边单独选）
        setState(() {
          if (!_picked.remove(tapId)) _picked.add(tapId);
        });
        return;
      case _CanvasMode.wire:
        // 连线：点选-点选状态机。**画布视觉只由 armed / flash 承担**
        //（2026-10-27 用户裁定，恢复旧手感）：点 A → A 紫色待命；
        // 再点合法 B → A/B 橙色双闪约 2 秒后一起熄灭，可立刻开始下一轮。
        //
        // ⛔ 不再写 _connectedIds：相连柔光会和紫/橙叠加，且成功闪光后
        // 常驻——用户截图里满屏同色高亮，分不清 A→B。
        // ✅ _selectedId 仍随点选更新，但那只是给详情面板的**数据**
        //（基因型/连线数要能看）；画布在 wire 里不接收它
        //（见 _buildCanvasArea 的 wireMode 隔离）。
        if (engine == null) return;
        setState(() => _selectedId = tapId);
        final armed = _armedId;
        if (armed == null) {
          // 新一轮开始：上一轮橙光若还在 2 秒窗口内，立即收掉——
          // 两轮配对的高亮不允许同时挂在画布上互相干扰。
          setState(() {
            _flashTimer?.cancel();
            _flashTimer = null;
            _flashIds = {};
            _armedId = tapId;
          });
          return;
        }
        if (armed == tapId) {
          setState(() => _armedId = null); // 再点自己 = 取消待命
          return;
        }
        // v2.19.15（DeepSeek 找茬 🔴2 双保险）：待命起点已被折叠/聚焦
        // 藏起来时（漏网路径，如别处改可见集），拒绝连接并清待命——
        // 否则 _connect 成功但画布过滤不可见边 = 静默连到看不见的点。
        {
          final (aBase, _) = parseTapId(armed);
          final armedVisible =
              _visibleNodes(engine.nodes).any((n) => n.id == aBase);
          if (!armedVisible) {
            setState(() => _armedId = null);
            _toast('待命起点已不在画布上（可能被折叠），请重新选择');
            return;
          }
        }
        // v2.19.5 性别互斥：未开同性交配、两端性别明确且相同 → 直接
        // 拒并 toast，保持待命（不走进 _connect 的通用失败路径，提示
        // 更明确、不闪红光扰动）。
        if (!_allowSameSex) {
          final aSex = _sexOfTapId(armed);
          final bSex = _sexOfTapId(tapId);
          if (aSex != null && aSex == bSex) {
            // v2.19.6 polish（学生走查 #3）：统一骨架
            // 「同性交配 · {状态} · {后果}」。
            _toast('同性交配 · 关 · ${aSex == PedigreeNodeKind.male ? '雄' : '雌'}性只能连异性 · 打开开关后允许同性');
            return;
          }
        }
        // 组合桶半边 → 懒分裂落成真实 SPLIT 半桶再连线
        final a = _resolveWireId(armed);
        final b = _resolveWireId(tapId);
        if (a == null || b == null) {
          setState(() => _armedId = null);
          return;
        }
        if (_connect(a, b)) {
          _pushLog('连线：$armed × $tapId');
          _flashTimer?.cancel();
          setState(() {
            _flashIds = {armed, tapId};
            _armedId = null;
          });
          _flashTimer = Timer(_kFlashDuration, () {
            if (mounted) setState(() => _flashIds = {});
            _flashTimer?.cancel();
            _flashTimer = null;
          });
        }
        // 失败：保持 armed 待命，用户可另点目标（toast 已在 _connect 内发）
    }
  }

  void _onNodeTap(PedigreeNode node) => _handleTap(node.id);

  /// v2.19.5 性别互斥：tapId 的明确性别——半边合成 id 用后缀性别；
  /// 普通节点非组合桶用 kind；组合桶（可分裂任一半）返回 null。
  PedigreeNodeKind? _sexOfTapId(String tapId) {
    final engine = _engine;
    if (engine == null) return null;
    final (base, half) = parseTapId(tapId);
    if (half != null) return half;
    final n = engine.nodesById[base];
    return n?.kind == PedigreeNodeKind.group ? null : n?.kind;
  }

  /// v2.19.6 性能：dimIds 缓存键——armed/节点集合不变时直接返旧集。
  /// 避免每次 build 跑一遍 engine.nodes。
  /// v2.19.6 fix：原 _dimCacheById = engine.nodesById 后用 identical 比对
  /// ——但 nodesById getter 每次访问都返回新 Map literal，永远命中失败。
  /// 改用「引擎实例 + 节点数 + 最大世代」三键做软版本戳；极少数等量
  /// 替换（remove+add 同 length）会让 cache 多持一帧，下次 build 自然恢复。
  PedigreeGraphEngine? _dimCacheEngine;
  int _dimCacheNodesLen = -1;
  int _dimCacheMaxGen = -1;
  String? _dimCacheArmed;
  Set<String> _dimCacheResult = const {};
  Set<String> _wireDimIds() {
    final armed = _armedId;
    final engine = _engine;
    if (armed == null || engine == null || _allowSameSex) {
      return const {};
    }
    final curLen = engine.nodes.length;
    final curMax = engine.maxGeneration;
    if (identical(_dimCacheEngine, engine) &&
        _dimCacheNodesLen == curLen &&
        _dimCacheMaxGen == curMax &&
        _dimCacheArmed == armed) {
      return _dimCacheResult;
    }
    final (base, half) = parseTapId(armed);
    final sex = half ?? _sexOfTapId(armed);
    final out = <String>{};
    if (sex != null) {
      final byId = engine.nodesById;
      for (final n in byId.values) {
        if (n.kind == sex && n.id != base) out.add(n.id);
      }
    }
    _dimCacheEngine = engine;
    _dimCacheNodesLen = curLen;
    _dimCacheMaxGen = curMax;
    _dimCacheArmed = armed;
    _dimCacheResult = out;
    return out;
  }

  /// 组合桶半边点选（R15）：合成 id 进统一入口。
  void _onNodeHalfTap(PedigreeNode group, PedigreeNodeKind sex) =>
      _handleTap(halfTapId(group.id, sex));

  /// 连线端点解析：合成 id（桶::性别）→ ensureHalf 懒分裂成真实
  /// SPLIT 半边节点 id；普通 id 原样返回。失败 toast 并返回 null。
  String? _resolveWireId(String tapId) {
    final engine = _engine!;
    final (base, half) = parseTapId(tapId);
    if (half == null) return base;
    try {
      return engine.ensureHalf(base, half);
    } catch (e) {
      _toast('无法连线：$e');
      return null;
    }
  }

  /// 「连线」开关：开启进入连线模式（chip 发光）；关闭回浏览并清待命。
  ///
  /// 进出 wire 都清掉**不属于本模式**的临时态：待命/闪光 timer，以及
  /// 浏览态的普通选中光与相连柔光（否则一进连线就有一层琥珀/青瓷光
  /// 盖在紫橙反馈上，用户分不清哪个是待命、哪个是上一轮的残留）。
  /// 选择草稿 `_picked` 不动——它是学生在选择模式里的作业，不是临时态。
  void _toggleWireMode() {
    setState(() {
      _flashTimer?.cancel();
      _flashTimer = null;
      _flashIds = {};
      _armedId = null;
      _selectedId = null;
      _connectedIds = const {};
      _mode =
          _mode == _CanvasMode.wire ? _CanvasMode.browse : _CanvasMode.wire;
    });
  }

  /// v2.19.6 「选择元素」菜单项（持续选择，不打断）：进入选择模式后
  /// 可一直加选/取消选；选择中再点本项 = 保持（无操作）——此前三态
  /// toggle（选→确定→显示全部）会在选择后再点就把选择收掉，中途加
  /// 选必须先显示全部再从头来（用户反馈不便）。
  void _onEnterSelect() {
    if (_mode == _CanvasMode.select) return; // 已在选择中：保持
    setState(() {
      // 聚焦中再进选择 = 在现有聚焦集上继续编辑
      if (_focusSet != null) {
        _picked
          ..clear()
          ..addAll(_focusSet!);
        _focusSet = null;
      }
      _mode = _CanvasMode.select;
      // 进入选择模式 = 离开连线反馈：待命/闪光与普通选中光都不该
      // 跨模式残留（绿勾是选择模式唯一的勾选反馈）。
      _armedId = null;
      _selectedId = null;
      _connectedIds = const {};
      _flashTimer?.cancel();
      _flashTimer = null;
      _flashIds = {};
    });
    _pushLog('选择元素');
  }

  /// 「只看所选（N）」：把选择模式下的勾选**应用为聚焦**（只显示所选）。
  ///
  /// v3.6 语义拆分：应用聚焦与恢复全都是两个动作、两颗按钮 ——
  /// 「选择」不再兼任「应用」，选择空集时也不会出现一颗看着像
  /// 「显示全部」却把东西藏起来的按钮（用户反馈的语义反转）。
  void _onApplyFocus() {
    if (_mode != _CanvasMode.select || _picked.isEmpty) return;
    final n = _picked.length;
    setState(() {
      _focusSet = Set.of(_picked);
      _picked.clear();
      _mode = _CanvasMode.browse;
      // 聚焦应用时清选中/相连——否则详情条仍在展示被聚焦藏起来的
      // 元素，还能把它删掉（"删了屏幕上不存在的东西"）。armed 同理。
      _selectedId = null;
      _connectedIds = {};
      _armedId = null;
    });
    _pushLog('聚焦：所选 $n 个');
    _toast('已聚焦所选 $n 个元素；点「显示全部」恢复全部。');
  }

  /// 「显示全部」：**只清聚焦集合**，恢复全部元素可见。
  ///
  /// ⛔ 不展开各代（`_expandedKeys` 不动）——恢复可见 ≠ 替学生逐代
  /// 展开；折叠芯片仍是学生自己点了才开。
  void _onShowAll() {
    if (_focusSet == null) return;
    setState(() {
      _focusSet = null;
      _picked.clear();
    });
    _pushLog('显示全部');
    _toast('已恢复显示全部元素（各代折叠状态保持不变）。');
  }

  /// 「全部连线」视图开关：智能密线 ↔ 全部自动连线原样铺开。
  /// 纯视图态（引擎 edges 不删），因此不入操作日志。
  void _toggleAllEdges() {
    setState(() => _showAllEdges = !_showAllEdges);
    _toast(_showAllEdges
        ? '已显示全部自动连线（密线会铺满画布）。'
        : '已回到智能密线：只保留主干与选中元素相关的连线。');
  }

  /// 结构变更后解除聚焦（聚焦是临时视图态；新结构应全量可见）。
  /// 连线闪光同样是临时态：结构一变，旧的双闪节点可能已被删/被换，
  /// 留着只会闪在不存在的位置 → 一并掐掉 timer。
  void _clearFocus() {
    _focusSet = null;
    _picked.clear();
    _connectedIds = const {};
    _flashTimer?.cancel();
    _flashTimer = null;
    _flashIds = {};
    if (_mode == _CanvasMode.select) _mode = _CanvasMode.browse;
  }

  /// R23/R25：与某 tapId（可带半边后缀）相连的**可见节点**集合，
  /// 粒度到性别：baseId → Set<相连的那一侧 kind>（mating/lineage 边
  /// 另一端；SPLIT 半边归一为父桶 id + 记录其 male/female）。组合桶
  /// 渲染时只给对应半边柔光（用户反馈：点小圆圈，只有连着的正方形
  /// 该亮，不能整桶亮）。普通节点亮整节点。
  Map<String, Set<PedigreeNodeKind>> _connectedOf(String tapId) {
    final engine = _engine;
    if (engine == null) return const {};
    final (baseId, half) = parseTapId(tapId);
    String rootOf(String id) {
      if (!id.startsWith('SPLIT#')) return id;
      for (final e in engine.edges) {
        if (e.kind == PedigreeEdgeKind.lineage && e.toId == id) {
          return e.fromId;
        }
      }
      return id;
    }

    PedigreeNodeKind? kindOf(String id) {
      return engine.nodesById[id]?.kind;
    }

    final out = <String, Set<PedigreeNodeKind>>{};
    for (final e in engine.edges) {
      final a = rootOf(e.fromId);
      final b = rootOf(e.toId);
      String? otherId;
      if (a == baseId) {
        otherId = e.toId;
      } else if (b == baseId) {
        otherId = e.fromId;
      }
      if (otherId == null || otherId == baseId) continue;
      final root = rootOf(otherId);
      // R30：跳过自指——SPLIT 半边经 lineage 回指父桶（baseId 自己），
      // 若写入会把"选中桶自己"标成相连 → 组合桶整桶泛蓝（用户反馈
      // "只点一个圆/方块，整个大矩形都亮"的根因）。
      if (root == baseId) continue;
      var k = kindOf(otherId) ?? PedigreeNodeKind.group;
      if (e.kind == PedigreeEdgeKind.mating) {
        // v2.2 参与端判定（修 R33 过度兜底）：mating 边两端参与性别 =
        // 边标注 fromSex/toSex 优先，端点是 SPLIT 半边时取其 kind。
        // —— 我点的半边若不是该边参与端（如边是 A□×B○ 而我点 A○），
        // 该边与我无关，跳过不亮（用户反馈：点 A○ 却让 B□ 亮的根因
        // 是 R33「一律亮异性半边」没校验我是否为参与端）。
        final selEndId = a == baseId ? e.fromId : e.toId;
        final selSex = (a == baseId ? e.fromSex : e.toSex) ??
            (selEndId.startsWith('SPLIT#') ? kindOf(selEndId) : null);
        final otherSex = (a == baseId ? e.toSex : e.fromSex) ??
            (otherId.startsWith('SPLIT#') ? kindOf(otherId) : null);
        if (half != null) {
          if (selSex != null && selSex != half) {
            continue; // 我不是这条边的参与端 → 不产生高亮
          }
          if (otherSex != null) {
            k = otherSex; // 亮对方标注侧（同性边亮同性，R32）
          } else {
            // 对方无标注（整桶端点）：池杂交语义异性兜底（R31）
            k = half == PedigreeNodeKind.male
                ? PedigreeNodeKind.female
                : PedigreeNodeKind.male;
          }
        } else if (otherSex != null) {
          k = otherSex; // 点整桶：亮对方标注侧（R32）
        }
      }
      // lineage 边：亮另一端（SPLIT 半边→该半边；整桶→整桶），
      // 不做性别兜底——亲子遗传无性别配对语义（修 R31 把子代桶
      // 也兜底成异性半边的越界行为）。
      out.putIfAbsent(root, () => {}).add(k);
    }
    return out;
  }

  /// 相连元素的展示标签列表（基因型（世代）♂/♀），供信息面板并列。
  /// 端点半边同样归一化到父桶（手动连线挂半边也能列出），性别标记
  /// 精确到雄/雌。
  List<String> _connectedLabels(String tapId) {
    final engine = _engine;
    if (engine == null) return const [];
    final (baseId, selHalf) = parseTapId(tapId);
    final byId = engine.nodesById;
    String rootOf(String id) {
      if (!id.startsWith('SPLIT#')) return id;
      for (final e in engine.edges) {
        if (e.kind == PedigreeEdgeKind.lineage && e.toId == id) {
          return e.fromId;
        }
      }
      return id;
    }

    String sexMark(String id) =>
        byId[id]?.kind == PedigreeNodeKind.male
            ? '♂'
            : byId[id]?.kind == PedigreeNodeKind.female
                ? '♀'
                : '';

    final seen = <String>{};
    final out = <String>[];
    for (final e in engine.edges) {
      final a = rootOf(e.fromId);
      final b = rootOf(e.toId);
      String? otherId;
      if (a == baseId) {
        otherId = e.toId;
      } else if (b == baseId) {
        otherId = e.fromId;
      }
      if (otherId == null || otherId == baseId) continue;
      final root = rootOf(otherId);
      if (root == baseId) continue; // R30 自指跳过
      final n = byId[root];
      if (n == null || !seen.add(root)) continue;
      final g = n.generation == 0 ? 'P' : 'F${n.generation}';
      var mark = sexMark(otherId);
      // R32：整桶端点用 mating 边记录的性别补 ♂/♀ 标记（与灯效同源）。
      if (mark.isEmpty && e.kind == PedigreeEdgeKind.mating) {
        final rec = otherId == e.fromId ? e.fromSex : e.toSex;
        if (rec == PedigreeNodeKind.male) mark = '♂';
        if (rec == PedigreeNodeKind.female) mark = '♀';
      }
      // R33：与灯效同源——同性交配关闭且选中明确半边时，组合桶另一端
      // 一律标异性符号（覆盖存量同性边/非参与端的旧标注）。
      if (e.kind == PedigreeEdgeKind.mating &&
          selHalf != null &&
          !_allowSameSex &&
          byId[root]?.kind == PedigreeNodeKind.group) {
        mark = selHalf == PedigreeNodeKind.male ? '♀' : '♂';
      }
      out.add('${n.genotype}（$g）$mark');
    }
    return out;
  }

  /// 点空白：解除待命（不清选中，信息面板保留）。
  void _onBlankTap() {
    if (_armedId != null) setState(() => _armedId = null);
  }

  /// 长按节点 = 收回连线（移动端收线入口）。
  /// v2.18 选择性收线：单连线直接收回（保持爽快）；多条连线弹出
  /// 底缘选择器（白板可达——底部弹出在几米白板上抬手即触），
  /// 挑「与某一个伙伴」的那条收回，或一键全部收回。
  /// R15：组合桶的连线挂在 SPLIT 半边上，聚合桶 id + 两半边去重。
  Future<void> _onWireDetach(PedigreeNode node) async {
    final engine = _engine;
    if (engine == null) return;
    final ids = <String>[node.id];
    if (node.kind == PedigreeNodeKind.group) {
      for (final sex
          in const [PedigreeNodeKind.male, PedigreeNodeKind.female]) {
        final h = engine.halfNode(node.id, sex);
        if (h != null) ids.add(h.id);
      }
    }
    final edges = <PedigreeEdge>{};
    for (final id in ids) {
      edges.addAll(engine.matingEdgesOf(id));
    }
    final list = edges.toList();
    if (list.isEmpty) {
      _toast('该节点没有可收回的连线。');
      return;
    }
    if (list.length == 1) {
      _detachEdge(list.first);
      return;
    }
    // 多条：挑一条收回。伙伴标签 = 基因型 + 世代 + 性别/回交标注。
    final byId = engine.nodesById;
    String partnerLabel(PedigreeEdge e) {
      final otherId = ids.contains(e.fromId) ? e.toId : e.fromId;
      final o = byId[otherId];
      if (o == null) return otherId;
      final kindLabel = o.kind == PedigreeNodeKind.male
          ? '雄'
          : o.kind == PedigreeNodeKind.female
              ? '雌'
              : '桶';
      final backcross = engine.isBackcross(e.fromId, e.toId) ? ' · 回交' : '';
      return '${o.genotype}（F${o.generation}·$kindLabel）$backcross';
    }

    final picked = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
              child: Text('该节点连着 ${list.length} 条线——收回哪一条？',
                  style: AppText.label),
            ),
            for (final e in list)
              ListTile(
                leading: Icon(Icons.cable_outlined,
                    size: 18, color: AppColors.teal),
                title: Text('与 ${partnerLabel(e)} 的连线',
                    style: AppText.body),
                onTap: () => Navigator.of(ctx).pop('${e.fromId}|${e.toId}'),
              ),
            const Divider(height: 1),
            ListTile(
              leading:
                  Icon(Icons.delete_sweep_outlined, size: 18, color: AppColors.lethal),
              title: Text('全部收回（${list.length} 条）',
                  style: AppText.body.copyWith(color: AppColors.lethal)),
              onTap: () => Navigator.of(ctx).pop('all'),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (!mounted || picked == null) return;
    if (picked == 'all') {
      // 全部收回：反复摘最新边直到没有（detachLatestMating 语义复用）。
      var removed = 0;
      for (final id in ids) {
        while (engine.detachLatestMating(id) != null) {
          removed++;
        }
      }
      if (removed > 0) {
        _pushLog('收回连线：全部 $removed 条');
        // 线已全部摘掉：立即收掉“刚连上”的橙光（计时器也要掐，防稍后
        // 在已不存在的边上闪一下）。
        _flashTimer?.cancel();
        _flashTimer = null;
        setState(() => _flashIds = {});
        _toast('已收回全部连线，点「计算」重算下游。');
      }
      return;
    }
    final parts = picked.split('|');
    final target = list.firstWhere(
        (e) =>
            (e.fromId == parts[0] && e.toId == parts[1]) ||
            (e.fromId == parts[1] && e.toId == parts[0]),
        orElse: () => list.first);
    _detachEdge(target);
  }

  /// 摘下指定边 + 日志 + 提示（选择性/单条收线共用收尾）。
  void _detachEdge(PedigreeEdge e) {
    final engine = _engine;
    if (engine == null) return;
    engine.detachMating(e.fromId, e.toId);
    _pushLog('收回连线：${e.fromId} -×- ${e.toId}');
    // 线已经不存在 → 橙光必须当场熄灭（含未到期的 2 秒计时器），
    // 否则画布仍在宣称“这两个节点刚连上”。
    _flashTimer?.cancel();
    _flashTimer = null;
    setState(() => _flashIds = {});
    _toast('已收回一条连线，点「计算」重算下游。');
  }

  /// 连线（含回交：跨代一雄一雌也允许）。成功返回 true。
  bool _connect(String fromId, String toId) {
    final engine = _engine;
    if (engine == null) return false;
    final reason = engine.connectBlockReason(fromId, toId);
    if (reason != null) {
      _toast('无法连线：$reason。');
      return false;
    }
    final backcross = engine.isBackcross(fromId, toId);
    engine.connect(fromId, toId);
    setState(() {});
    _toast(backcross ? '已建立回交连线，点「计算」重算。' : '已连线，点「计算」重算。');
    return true;
  }

  // ── 折叠：每代默认只渲染最高概率桶 ──────────────────

  /// 画布可见节点：折叠世代 = 每家族各保最高概率桶（同概率取基因型
  /// 字母序首个，确定性选择）+ 该代全部外来样本；P 代与展开世代全量。
  /// R14：折叠粒度从「世代」改为「世代×家族」，多家族各自保一个代表桶。
  /// R15 聚焦修正：选择折叠**只作用于有选中元素的世代**——该代只显示
  /// 选中的桶（半边勾选=保留父桶整只）+ 外来样本；没有选中元素的世代
  /// （P、上下各代）按原折叠规则照常呈现。
  List<PedigreeNode> _visibleNodes(List<PedigreeNode> all) {
    // R15：trackSex 下 SPLIT 半桶由父组合桶内 glyph 代表，
    // 不参与折叠统计与代表桶选举（trackSex 关闭时保持旧行为）
    final pool = _trackSex
        ? all.where((n) => !n.id.startsWith('SPLIT#')).toList()
        : all;
    final focusGens = _focusGens(pool);
    final byGenFam = <String, List<PedigreeNode>>{};
    for (final n in pool) {
      byGenFam.putIfAbsent('${n.generation}|${n.familyId}', () => []).add(n);
    }
    final out = <PedigreeNode>[];
    byGenFam.forEach((_, list) {
      final g = list.first.generation;
      final fid = list.first.familyId;
      // 聚焦代：只显示选中的（外来样本始终可见）
      if (focusGens.contains(g)) {
        out.addAll(list.where((n) => _focusKept(n.id) || n.isExternal));
        return;
      }
      if (g == 0 || _expandedKeys.contains('$fid:$g')) {
        out.addAll(list);
        return;
      }
      // v2.1i 致死子代始终可见（不被折叠）：让用户能直接看到 ✕ 标记 + lethal 色；
      // 非致死桶仍按概率降序折叠为 1 个 + 概率最低的被隐藏。
      final lethal = list.where((n) => n.isLethal).toList();
      final nonLethal = list.where((n) => !n.isLethal && !n.isExternal).toList()
        ..sort((a, b) {
          final p = b.probability.compareTo(a.probability);
          return p != 0 ? p : a.genotype.compareTo(b.genotype);
        });
      out.addAll(lethal);
      if (nonLethal.isNotEmpty) out.add(nonLethal.first);
      out.addAll(list.where((n) => n.isExternal));
    });
    return out;
  }

  /// 聚焦集判中：桶 id 或其任一半边合成 id 被勾选即视为选中。
  bool _focusKept(String id) {
    final focus = _focusSet;
    if (focus == null) return false;
    return focus.contains(id) ||
        focus.contains('$id::male') ||
        focus.contains('$id::female');
  }

  /// 聚焦集涉及的世代集合（空集 = 未聚焦）。这些世代走「只显示选中」，
  /// 其余世代按原折叠规则照常。
  Set<int> _focusGens(List<PedigreeNode> pool) {
    if (_focusSet == null) return const {};
    return {
      for (final n in pool)
        if (_focusKept(n.id)) n.generation
    };
  }

  /// 每个可折叠 (家族,世代) 被隐藏的桶数（key='家族:世代'，P 代不折叠）。
  /// R26：每家族每代独立统计、独立芯片——隐藏数 = 该家族该代桶数 - 1。
  /// R15：[skipGens] 中的世代不出折叠芯片（聚焦代由用户选择集接管）。
  Map<String, int> _hiddenCounts(List<PedigreeNode> all,
      {Set<int> skipGens = const {}}) {
    final countKey = <String, int>{};
    for (final n in all) {
      if (n.generation == 0 || n.isExternal) continue;
      if (skipGens.contains(n.generation)) continue; // 聚焦代不出芯片
      // R15：SPLIT 半桶不计入折叠统计（组合桶内展示，不占桶位）
      if (_trackSex && n.id.startsWith('SPLIT#')) continue;
      final k = '${n.familyId}:${n.generation}';
      countKey[k] = (countKey[k] ?? 0) + 1;
    }
    final out = <String, int>{};
    countKey.forEach((k, count) {
      if (count > 1) out[k] = count - 1;
    });
    return out;
  }

  /// 处于「展开」状态的世代节点（详情条「完整配比」用）。
  /// 多世代同时展开时全部返回，由详情条逐代成块——不做「只取选中代」
  /// 的单值化，否则同开两代就只剩一代的配比。
  List<PedigreeNode> _expandedGenNodes(PedigreeGraphEngine engine) {
    if (_expandedKeys.isEmpty) return const [];
    return [
      for (final n in engine.nodes)
        if (n.generation > 0 &&
            !n.isExternal &&
            !(_trackSex && n.id.startsWith('SPLIT#')) &&
            _expandedKeys.contains('${n.familyId}:${n.generation}'))
          n,
    ];
  }

  /// 画布应当收到的边（可见端点过滤 + 智能密线派生）。
  ///
  /// 只过滤画布输入：引擎 edges 一条不删（学生手连的回交/连线全留，
  /// 见 pedigree_edge_focus.dart）。[visible] 为折叠/聚焦后的可见节点。
  List<PedigreeEdge> _canvasEdges(
      List<PedigreeNode> visible, PedigreeGraphEngine engine) {
    final visibleIds = visible.map((n) => n.id).toSet();
    // R15：trackSex 下半边（SPLIT）端点的边，父桶可见即保留
    // （画布把线画进组合桶对应半边 glyph）
    bool endpointVisible(String id) {
      if (visibleIds.contains(id)) return true;
      if (_trackSex && id.startsWith('SPLIT#')) {
        for (final e in engine.edges) {
          if (e.kind == PedigreeEdgeKind.lineage && e.toId == id) {
            return visibleIds.contains(e.fromId);
          }
        }
      }
      return false;
    }

    final endpoints = engine.edges
        .where((e) => endpointVisible(e.fromId) && endpointVisible(e.toId))
        .toList();
    return deriveCanvasEdges(
      edges: endpoints,
      nodesById: engine.nodesById,
      showAllAuto: _showAllEdges,
      // wire 模式只认待命起点（紫光）——浏览态的旧选中不能顺带
      // 决定哪些自动边算「相关」，否则换模式会换来一张不同的密线图。
      selectedTapId: _mode == _CanvasMode.wire
          ? _armedId
          : (_selectedId ?? _armedId),
      focusTapIds: _focusSet ?? const {},
      // 已展开的世代不抽稀：摊开后每个桶都要看得见亲代连线。
      expandedGroupKeys: _expandedKeys,
    );
  }

  /// 当前视图的节点/边快照：画布与 SVG/PNG 导出共用同一份派生结果
  /// （导出所见 = 屏上所见；不伪造也不改写引擎结果）。
  ({List<PedigreeNode> nodes, List<PedigreeEdge> edges}) _viewportGraph() {
    final engine = _engine!;
    final visible = _visibleNodes(engine.nodes);
    return (nodes: visible, edges: _canvasEdges(visible, engine));
  }

  void _toggleGenKey(String key) {
    setState(() {
      if (!_expandedKeys.remove(key)) _expandedKeys.add(key);
      // 折叠后若选中节点被隐藏，清掉选中态
      if (!_expandedKeys.contains(key) && _selectedId != null) {
        final (baseId, _) = parseTapId(_selectedId!);
        final stillVisible =
            _visibleNodes(_engine!.nodes).any((n) => n.id == baseId);
        if (!stillVisible) _selectedId = null;
      }
      // v2.19.15（DeepSeek 找茬 🔴2）：折叠把待命起点藏起来时同步清
      // armed——原实现只清 selectedId，armed 残留导致下一次点选直接
      // _connect 成功但画布过滤不可见边 → 静默连到看不见的点，子代
      // 按看不见的连线重算。
      if (!_expandedKeys.contains(key) && _armedId != null) {
        final (aBase, _) = parseTapId(_armedId!);
        final armedVisible =
            _visibleNodes(_engine!.nodes).any((n) => n.id == aBase);
        if (!armedVisible) _armedId = null;
      }
    });
  }

  // ── R13 回交线逐条显隐 ──────────────────────────────
  List<PedigreeEdge> _backcrossEdges(PedigreeGraphEngine engine) {
    final byId = engine.nodesById;
    return engine.edges.where((e) {
      if (e.kind != PedigreeEdgeKind.mating) return false;
      final a = byId[e.fromId], b = byId[e.toId];
      return a != null && b != null && a.generation != b.generation;
    }).toList();
  }

  // ── 引擎语义开关 ────────────────────────────────────
  // v2.19.6 polish（学生走查 #3）：统一 3 处同性交配 toast 骨架——
  // 「同性交配 · {开/关} · {后果}」。后果 = "允许 ♂♂/♀♀ 连线" / "禁止同
  // 性连线 + 移除 {N} 条既有边"（后果导向，避免"已移除/已恢复"分裂）。
  // 无副作用（无既有边被移除）的开关切换静默——避免扰民。
  static const _sameSexToastOn =
      '同性交配 · 开 · 允许 ♂♂ / ♀♀ 连线';
  String _sameSexToastOff(int removed) =>
      '同性交配 · 关 · 禁止同性连线，已移除 $removed 条既有边';
  String _sameSexToastOffNoRemoved() =>
      '同性交配 · 关 · 禁止同性连线（无既有边需清理）';

  /// v2.19.9：同性交配开关持久化（用户实际遇到「开了开关退出去再进
  /// 就丢」——走查报告 🟢#7）。范式照抄 _edgeStyle（独立文件
  /// same_sex.json + Platform.environment 守卫 + debugWebStorage 注入
  /// 放行 round-trip 测试）。
  static const String _sameSexKey = 'pedigree_same_sex';
  static String _sameSexFile() {
    if (GeneticPedigreePage.debugFilePath != null) {
      return GeneticPedigreePage.debugFilePath!;
    }
    final appDir = userAppDir();
    if (appDir == null) return 'same_sex.json';
    return '$appDir/same_sex.json';
  }

  void _loadSameSexPref() {
    if (_edgeTestGuard) return;
    () async {
      try {
        String? raw;
        if (_isWebStorage) {
          raw = _storageGet(_sameSexKey);
        } else {
          final f = File(_sameSexFile());
          if (!f.existsSync()) return;
          raw = f.readAsStringSync();
        }
        if (raw == null || raw.isEmpty) return;
        final v = jsonDecode(raw);
        if (v is Map && v['on'] == true && mounted) {
          setState(() {
            _allowSameSex = true;
            _engine?.allowSameSexMating = true;
          });
        }
      } catch (_) {/* 尽力而为 */}
    }();
  }

  void _saveSameSexPref(bool v) {
    if (_edgeTestGuard) return;
    () async {
      try {
        final s = jsonEncode({'on': v});
        if (_isWebStorage) {
          await _storageSet(_sameSexKey, s);
          return;
        }
        final f = File(_sameSexFile());
        f.parent.createSync(recursive: true);
        f.writeAsStringSync(s);
      } catch (_) {/* 持久化尽力而为 */}
    }();
  }

  void _toggleSameSex(bool v) {
    // v2.19.13（学生找茬 🟡8）：预 commit 反模式修正——原实现在
    // showDialog **之前**就 setState/engine/pref 三件套，取消时靠
    // restore() 逐步回滚（任何一条漏掉都半新半旧）。改为：有边待
    // 清时先弹确认，**确认后才一次性执行全部变更**；无边/开启时
    // 即时执行。
    if (v) {
      setState(() => _allowSameSex = true);
      _engine?.allowSameSexMating = true;
      _saveSameSexPref(true);
      _toast(_sameSexToastOn);
      return;
    }
    final count = _engine?.countSameSexEdges() ?? 0;
    if (count == 0) {
      setState(() => _allowSameSex = false);
      _engine?.allowSameSexMating = false;
      _saveSameSexPref(false);
      _toast(_sameSexToastOffNoRemoved());
      return;
    }
    _confirmRemoveSameSexEdges(count);
  }

  /// 关闭同性交配的二次确认（将移除 N 条既有同性边，不可逆）。
  /// v2.19.12（学生验证 P0）：barrierDismissible 必须 false——默认 true
  /// 时点外面/Esc 会旁路恢复逻辑，留下「开关已关但旧边没删」的不一致
  /// 状态（恰是 R29 要修的灯效错半边）。
  /// v2.19.13（学生找茬 🔴3）：PopScope canPop=false 封 Android 系统
  /// 返回键/手势返回的旁路（此前只堵了点外面/Esc）。预 commit 已
  /// 移除（🟡8），取消 = 纯 pop 无需恢复；返回键只能走两个显式出口。
  void _confirmRemoveSameSexEdges(int count) {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => PopScope(
        canPop: false,
        child: CallbackShortcuts(
          bindings: {
            const SingleActivator(LogicalKeyboardKey.escape): () =>
                Navigator.of(ctx).pop(),
          },
          child: AlertDialog(
            icon: const Icon(Icons.warning_amber_rounded),
            title: const Text('关闭同性交配？'),
            content:
                Text('画布上已有 $count 条同性连线，关闭后将被移除且不可恢复。'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('取消'),
              ),
              FilledButton(
                style: FilledButton.styleFrom(
                    backgroundColor: AppColors.select,
                    foregroundColor: AppColors.onTeal),
                onPressed: () {
                  Navigator.of(ctx).pop();
                  // 确认后才一次性执行全部变更（不再预 commit）。
                  setState(() => _allowSameSex = false);
                  _engine?.allowSameSexMating = false;
                  _saveSameSexPref(false);
                  final removed = _engine?.removeSameSexEdges() ?? 0;
                  _toast(removed > 0
                      ? _sameSexToastOff(removed)
                      : _sameSexToastOffNoRemoved());
                },
                child: Text('移除 $count 条边'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// R18：基因缺失交配——开启后不同对数（如 3 对 × 1 对）可连线
  /// 杂交，子代缺失位点补 '-' 并标注「基因缺失」（三倍体×二倍体等）。
  void _toggleMissingGene(bool v) {
    setState(() => _allowMissingGene = v);
    _engine?.allowMissingGeneMating = v;
    _toast(v
        ? '已允许基因缺失交配：不同对数可连线，子代缺失位点以「-」标注。'
        : '已关闭基因缺失交配：恢复相同对数才能连线。');
  }

  /// v3.6 连锁互换开关：首次开启即出默认结果。
  void _toggleLinkage(bool v) {
    setState(() {
      _linkageOn = v;
      // 首次开启即出默认结果（AB/ab × ab/ab r=20% → 4:4:1:1）
      if (v && _linkageResult == null) _computeLinkage();
    });
  }

  void _computeLinkage() {
    try {
      final r = _linkageEngine
          .cross(_linkageP1Ctrl.text, _linkageP2Ctrl.text, _linkageRCtrl.text);
      setState(() {
        _linkageResult = r;
        _linkageError = null;
      });
    } on ArgumentError catch (e) {
      setState(() {
        _linkageResult = null;
        _linkageError = e.message?.toString() ?? '输入格式错误';
      });
    }
  }

  /// v3.6 连锁互换结果区块：两位点 + 交换值 + 案例速选 + 完整比例信息。
  /// 2.3 重构：已抽取为独立组件 PedigreeLinkagePanel
  /// （widgets/pedigree_linkage_panel.dart），此处只做状态/回调接线。
  Widget _buildLinkageSection() {
    return PedigreeLinkagePanel(
      p1Ctrl: _linkageP1Ctrl,
      p2Ctrl: _linkageP2Ctrl,
      rCtrl: _linkageRCtrl,
      result: _linkageResult,
      error: _linkageError,
      onCompute: _computeLinkage,
    );
  }

  /// R18：画布锁——锁定后缩放/平移禁用，解锁家族横幅整体拖动。
  void _toggleCanvasLock() {
    setState(() => _canvasLocked = !_canvasLocked);
    _toast(_canvasLocked
        ? '画布已锁定：按住家族横幅（家族 A/B…）可整体拖动该家族，再次点锁解锁。'
        : '画布已解锁：恢复拖动/滚轮平移与 Ctrl+滚轮缩放。');
  }

  /// R18：家族拖动回调——只累加被拖家族的偏移，其他家族不动。
  /// R21：按下开始即记起点（拖动结束回调里写日志）。
  Map<int, Offset>? _dragFamilyStart;

  void _onFamilyDragDelta(int familyId, Offset worldDelta) {
    _dragFamilyStart ??= Map.of(_familyOffsets);
    setState(() {
      _familyOffsets[familyId] =
          (_familyOffsets[familyId] ?? Offset.zero) + worldDelta;
    });
  }

  /// R21：拖动手势结束（按下→抬起 = 一次拖动）→ 记一条日志：
  /// 记录家族起始位置与终点位置；回退该条日志可恢复位置。
  void _onFamilyDragEnd() {
    final start = _dragFamilyStart;
    _dragFamilyStart = null;
    if (start == null) return;
    final engine = _engine;
    if (engine == null) return;
    for (final f in _familyOffsets.keys) {
      final s = start[f] ?? Offset.zero;
      final t = _familyOffsets[f] ?? Offset.zero;
      if ((s - t).distance.abs() < 0.01) continue;
      _pushLog('移动家族 ${engine.familyLabel(f)}：'
          '(${s.dx.round()}, ${s.dy.round()}) → (${t.dx.round()}, ${t.dy.round()})');
    }
  }

  void _toggleTrackSex(bool v) {
    setState(() => _trackSex = v);
    final e = _engine;
    if (e != null) {
      e.trackSex = v;
      // 立即重算，让已有世代的桶带上/去掉雌雄比标注
      if (e.maxGeneration > 0) {
        e.recomputeFrom(0);
        e.ensureOffspringCoverage();
      }
    }
    setState(() {});
    _toast(v ? '已开启 XY 性别存证：计算桶标注雌雄比（1:1）。' : '已关闭 XY 性别存证。');
  }

  // ── 伴性遗传：下拉填 X=/x=/Y=/y= 表型标签 ─────────────
  /// 2.3 重构阶段 4：对话框 UI 已抽取为顶层函数
  /// showPedigreeSexLinkedDialog（widgets/pedigree_dialogs.dart），
  /// 此处只做状态接线（应用配置 + 重算 + 提示），行为不变。
  Future<void> _showSexLinkedDialog() async {
    final cfg = await showPedigreeSexLinkedDialog(
        context: context, current: _sexLinked);
    if (cfg == null || !mounted) return;
    setState(() => _sexLinked = cfg.isEmpty ? null : cfg);
    final e = _engine;
    if (e != null) {
      e.sexLinked = _sexLinked;
      if (e.maxGeneration > 0) {
        e.recomputeFrom(0);
        e.ensureOffspringCoverage();
      }
    }
    setState(() {});
    _toast(cfg.isEmpty ? '已清空伴性遗传标注。' : '伴性遗传标注已应用并重算。');
  }

  // ── v2.1 亲本预置 / 基因频率 / 位点致死筛选 ──────────────

  /// v2.1 亲本「预置」对话框：列全部预置组合，点选同时填 ♂+♀。
  /// 2.3 重构阶段 4：UI 在 widgets/pedigree_dialogs.dart，此处接线。
  Future<void> _showPresetDialog() async {
    final choice = await showPedigreePresetDialog(context);
    if (choice == null || !mounted) return;
    setState(() {
      _p1Ctrl.text = choice.male;
      _p2Ctrl.text = choice.female;
    });
    if (isPolyploidGenotype(choice.male) && !_allowPolyploid) {
      _toast('该预置为多倍体（3n 以上），请先开启「多倍体」开关再计算。');
    } else {
      // P0-6：点预置 = 直接算（等同点「计算」）。回填后把老师留在空画布上
      // 再自己找按钮，是首用走查里最贵的一步；announce:false 避免两条 toast。
      _derive(announce: false);
      _toast(_error ?? '已按预置「${choice.name}」算出子代');
    }
  }

  /// v2.1 「计算基因频率」对话框：位点 | p | q | AA | Aa | aa 频率表。
  /// 2.3 重构阶段 4：UI 在 widgets/pedigree_dialogs.dart，此处接线。
  Future<void> _showFreqDialog() async {
    final engine = _engine;
    if (engine == null) return;
    await showPedigreeFreqDialog(context: context, engine: engine);
  }

  /// v2.1c「位点致死筛选」对话框（2.3 重构阶段 4：UI 已抽取至
  /// widgets/pedigree_dialogs.dart）：确定后把确认的工作副本应用到
  /// 引擎并立即重算，行为与抽取前一致。
  Future<void> _showLethalDialog() async {
    final engine = _engine;
    if (engine == null) return;
    final list = await showPedigreeLethalDialog(
        context: context, engine: engine, allowPolyploid: _allowPolyploid);
    if (list == null || !mounted) return;
    engine.clearLethal();
    for (final g in list) {
      engine.addLethal(g);
    }
    setState(() {
      _lethalGenotype = engine.lethalGens.isEmpty
          ? null
          : engine.lethalGens.join('、');
      // v2.1i 致死生效后自动展开各家族当前前沿代（让用户看到所有活+致死子代，
      // 否则默认折叠会只显示 1 个最高概率的活子代，看不到致死桶）。
      if (engine.lethalGens.isNotEmpty) {
        final fams = <int>{for (final n in engine.nodes) n.familyId};
        final maxG = engine.maxGeneration;
        for (final fam in fams) {
          _expandedKeys.add('$fam:$maxG');
        }
      }
    });
    if (_computed) _derive(); // 立即重算（引擎在 _derive 内重新应用致死）
    _toast(engine.lethalGens.isEmpty
        ? '已清除致死筛选。'
        : '已应用致死筛选，子代不含 ${engine.lethalGens.join('、')}。');
  }

  // ── R3 右键空白 → 添加样本 ───────────────────────────
  Future<void> _onBlankSecondaryTap(int generation, Offset viewportPos) async {
    final engine = _engine;
    if (engine == null) return;
    // v3.5：右键快捷菜单收纳画布动作（电脑端友好）——添加家族 /
    // 添加样本 / 计算下一代；移动端走底部条与左面板按钮。
    final choice = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(viewportPos.dx, viewportPos.dy,
          viewportPos.dx, viewportPos.dy),
      items: [
        const PopupMenuItem(value: 'addFamily', child: Text('添加家族')),
        PopupMenuItem(value: 'add', child: Text('添加样本')),
        if (engine.maxGeneration < PedigreeGraphEngine.safetyMaxGeneration)
          const PopupMenuItem(value: 'next', child: Text('计算下一代')),
      ],
    );
    if (!mounted || choice == null) return;
    switch (choice) {
      case 'addFamily':
        await _showAddFamilyDialog();
      case 'add':
        await _showAddSampleDialog(generation);
      case 'next':
        _expandNext();
    }
  }

  /// 2.3 重构阶段 4：对话框 UI 已抽取至 widgets/pedigree_dialogs.dart，
  /// 此处只做校验/入引擎/记日志接线，行为与抽取前一致。
  Future<void> _showAddSampleDialog(int tappedGen) async {
    final engine = _engine;
    if (engine == null) return;
    final res = await showPedigreeAddSampleDialog(
        context: context,
        engine: engine,
        tappedGen: tappedGen,
        p1: _p1Ctrl.text.trim(),
        p2: _p2Ctrl.text.trim());
    if (res == null || !mounted) return;
    final genotype = res.genotype;
    if (genotype.isEmpty || genotype.length % 2 != 0) {
      _toast('基因型无效：请输入成对字母，如 AaBb。');
      return;
    }
    try {
      if (res.kind == PedigreeNodeKind.group) {
        engine.addExternalGroup(
            generation: res.generation,
            genotype: genotype,
            familyId: res.familyId);
      } else {
        engine.addExternal(
            generation: res.generation,
            kind: res.kind,
            genotype: genotype,
            familyId: res.familyId);
      }
      setState(_clearFocus);
      final sexLabel = res.kind == PedigreeNodeKind.group
          ? '混合 ♂♀'
          : res.kind == PedigreeNodeKind.male
              ? '雄 ♂'
              : '雌 ♀';
      _pushLog('添加样本：$genotype'
          '（F${res.generation} · $sexLabel'
          ' · ${engine.familyLabel(res.familyId)}）');
      _toast('已添加样本，点「计算」让它参与重算。');
    } catch (e) {
      _toast('添加失败：$e');
    }
  }

  // ── R14 多家族：添加独立家族 ───────────────────────────
  /// 新家族双亲落在 P 代、独立繁衍（自己的交配池）；与既有家族成员
  /// 连线（点选-点选，跨栏也可以连）即发生跨家族交配，子代进入
  /// 合并家族（如 A×B），新基因型/伴性信息随之进入谱系。
  /// 2.3 重构阶段 4：对话框 UI 已抽取至 widgets/pedigree_dialogs.dart。
  Future<void> _showAddFamilyDialog() async {
    final engine = _engine;
    if (engine == null) return;
    final res = await showPedigreeAddFamilyDialog(
        context: context,
        p1: _p1Ctrl.text.trim(),
        p2: _p2Ctrl.text.trim());
    if (res == null || !mounted) return;
    final fg = res.father;
    final mg = res.mother;
    if (fg.isEmpty || fg.length % 2 != 0 || mg.isEmpty || mg.length % 2 != 0) {
      _toast('基因型无效：请输入成对字母，如 AaBb。');
    } else {
      try {
        final k =
            engine.addFamily(fatherGenotype: fg, motherGenotype: mg);
        setState(_clearFocus);
        _pushLog('添加家族 ${engine.familyLabel(k)}：$fg × $mg');
        _toast('已添加家族 ${engine.familyLabel(k)}（独立繁衍），点「计算下一代」产生它的 F1。');
      } catch (e) {
        _toast('添加失败：$e');
      }
    }
  }

  // ── 右键节点：外来样本可编辑 / 删除 ──────────────────
  Future<void> _onNodeSecondaryTap(
      PedigreeNode node, Offset viewportPos) async {
    final engine = _engine;
    if (engine == null) return;
    // R15：桶的雌雄分裂已常驻化（组合桶内含雄□/雌○，直接点选半边），
    // 右键不再提供分裂入口。
    // v2.19.16（DeepSeek 找茬 🟡2）：收线能力对**任意节点**成立（引擎
    // matingEdgesOf 不限 isExternal/kind），原实现把它放在 group toast
    // 与 isExternal 早退之后 → 计算节点右键只能吃提示 toast，与提示条
    // 「右键菜单=收线」互相打脸。统一前置：有连线 → 右键出收线菜单
    // （计算节点/组合桶连线普遍多，收线是高频；group 无连线时保留
    // 原「点半边配对」教学提示）。
    final hasWires =
        engine.edges.any((e) => e.fromId == node.id || e.toId == node.id);
    if (hasWires) {
      final items = <PopupMenuEntry<String>>[
        // 组合桶：R15 教学提示内嵌菜单顶部（右键桶不再只弹 toast——
        // 已连线时收线入口与教学提示一并给出，互不遮挡）。
        if (node.kind == PedigreeNodeKind.group)
          const PopupMenuItem(
            enabled: false,
            child: Text('桶内含 雄□/雌○：开「连线」直接点选半边配对'),
          ),
        const PopupMenuItem(value: 'detach', child: Text('收回此节点连线')),
        if (node.isExternal && node.kind != PedigreeNodeKind.group) ...[
          const PopupMenuItem(value: 'edit', child: Text('编辑样本')),
          const PopupMenuItem(value: 'del', child: Text('删除样本')),
        ],
      ];
      final choice = await showMenu<String>(
        context: context,
        position: RelativeRect.fromLTRB(viewportPos.dx, viewportPos.dy,
            viewportPos.dx, viewportPos.dy),
        items: items,
      );
      if (!mounted) return;
      if (choice == 'detach') {
        _onWireDetach(node); // 与长按节点收线同路径
      } else if (choice == 'edit') {
        await _showEditSampleDialog(node);
      } else if (choice == 'del') {
        await _deleteExternalNode(node, engine);
      }
      return;
    }
    if (node.kind == PedigreeNodeKind.group) {
      _toast('桶已内含 雄□/雌○ 两边：开「连线」后直接点选半边即可配对。');
      return;
    }
    if (!node.isExternal) {
      _toast('计算产出的群体节点不可编辑；只有外来样本可以编辑/删除。');
      return;
    }
    // 无连线外来样本：编辑/删除两项菜单。
    final choice = await showMenu<String>(
      context: context,
      position:
          RelativeRect.fromLTRB(viewportPos.dx, viewportPos.dy, viewportPos.dx, viewportPos.dy),
      items: const [
        PopupMenuItem(value: 'edit', child: Text('编辑样本')),
        PopupMenuItem(value: 'del', child: Text('删除样本')),
      ],
    );
    if (!mounted) return;
    if (choice == 'edit') {
      await _showEditSampleDialog(node);
    } else if (choice == 'del') {
      await _deleteExternalNode(node, engine);
    }
  }

  /// 删除外来样本（v2.19.16 从右键菜单内联提取，两处菜单共用）。
  Future<void> _deleteExternalNode(
      PedigreeNode node, PedigreeGraphEngine engine) async {
    if (engine.removeExternal(node.id)) {
      if (_selectedId == node.id) _selectedId = null;
      // 删除后下游同样不再可靠，重算刷新
      if (engine.maxGeneration > node.generation) {
        engine.recomputeFrom(node.generation);
      }
      setState(_clearFocus);
      _pushLog('删除样本：${node.id}（${node.genotype}）');
      _toast('已删除样本并重算下游。');
    } else {
      _toast('该节点不可删除。');
    }
  }

  /// 编辑外来样本：改基因型/性别后，原有下游数据不再可靠 → 立即重算刷新。
  /// 2.3 重构阶段 4：对话框 UI 已抽取至 widgets/pedigree_dialogs.dart。
  Future<void> _showEditSampleDialog(PedigreeNode node) async {
    final engine = _engine;
    if (engine == null) return;
    final res = await showPedigreeEditSampleDialog(
        context: context,
        node: node,
        p1: _p1Ctrl.text.trim(),
        p2: _p2Ctrl.text.trim());
    if (res == null || !mounted) return;
    final genotype = res.genotype;
    // 混合桶只改基因型：kind 传 null 保留 group（传 group 会被引擎拦）
    final ok = engine.editExternal(node.id,
        genotype: genotype,
        kind: node.kind == PedigreeNodeKind.group ? null : res.kind);
    if (!ok) {
      _toast('编辑失败：基因型需为成对字母，且基因对数需保持不变（与原样本一致）。');
    } else {
      // 原有下游数据不再可靠 → 从该样本所在世代重算刷新
      if (engine.maxGeneration > node.generation) {
        engine.recomputeFrom(node.generation);
      }
      setState(_clearFocus);
      _pushLog('编辑样本：${node.id} → $genotype');
      _toast('样本已更新，下游世代已重算。');
    }
  }

  /// v2.19 连线样式（正交/曲线蜘蛛网）——侧栏「曲线连线」chip 切换。
  PdEdgeStyle _edgeStyle = PdEdgeStyle.orthogonal;

  /// R16 操作日志 + 任意步回退 ─────────────────────────────
  /// 记录一步操作（快照=操作完成后的状态；家族偏移一并入日志）。
  void _pushLog(String label) {
    final engine = _engine;
    if (engine == null) return;
    final redoClear = _redoStack;
    redoClear.clear();
    final f = _focusSet;
    _opLog.add(_LogEntry(label, engine.takeSnapshot(), Map.of(_familyOffsets),
        Set.of(_picked), f == null ? null : Set.of(f), _mode));
  }

  // ── v2.1 计算历史 + 新对话（白板）─────────────────────────
  /// 计算历史（内存缓存；持久化见 HistoryStore）。
  late List<HistoryEntry> _history;

  Future<void> _loadHistory() async {
    final h = await HistoryStore.load();
    if (mounted) setState(() => _history = List.of(h)); // 拷贝为可变列表
  }

  /// 当前会话要追加的历史条目（自动记录每次计算）。
  HistoryEntry? _buildHistoryEntry({bool includeUntouched = false}) {
    final engine = _engine;
    if (engine == null) return null;
    final p1 = _p1Ctrl.text.trim();
    final p2 = _p2Ctrl.text.trim();
    if (p1.isEmpty && p2.isEmpty && !includeUntouched) return null;
    final fams = engine.familyIds.map(engine.familyLabel).join('、');
    final maxGen = engine.maxGeneration;
    final sb = StringBuffer();
    for (var g = 1; g <= maxGen; g++) {
      final nodes = engine
          .nodesOf(g)
          .where((n) => !n.id.startsWith('SPLIT#'))
          .toList();
      if (nodes.isEmpty) continue;
      final parts = nodes
          .map((n) => n.isExternal
              ? '外来 ${n.genotype}'
              : n.isLethal
                  ? '${n.genotype}（致死）${(n.probability * 100).toStringAsFixed(1)}%'
                  : '${n.genotype} ${(n.probability * 100).toStringAsFixed(1)}%')
          .toList();
      if (parts.length > 6) {
        sb.writeln('F$g：${parts.take(6).join('、')} …等 ${parts.length} 种');
      } else {
        sb.writeln('F$g：${parts.join('、')}');
      }
    }
    final detail = sb.toString().trim();
    final label = '♂$p1 × ♀$p2 · 家族 ${fams.isEmpty ? 'A' : fams}'
        '${maxGen > 0 ? ' · 产出至 F$maxGen' : ' · 未计算'}';
    return HistoryEntry(
        label: label, epochMs: DateTime.now().millisecondsSinceEpoch,
        detail: detail.isEmpty ? '（尚无计算产出）' : detail);
  }

  /// 自动归档当前计算（每次「计算」/「计算下一代」后调用）。
  Future<void> _appendHistory() async {
    final e = _buildHistoryEntry();
    if (e == null) return;
    // v2.13+ 合并磁盘最新：计算器 tab 的 HistoryStore.append 与本页
    // 内存缓存并发写同一文件——直接 save(_history) 会覆盖对方记录
    // （讲题回放卡丢数据的隐蔽 bug）。
    final fresh = await HistoryStore.load();
    final merged = [...fresh, e];
    _history = List.of(merged);
    await HistoryStore.save(merged);
    if (mounted) setState(() {});
  }

  /// 保存当前白板到历史，并开启新对话（清空引擎/输入/日志，隔离）。
  /// P0 修复（v2.1）：调用方负责在对话框 pop 后延迟一帧再调用本方法；
  /// 本方法首行有 mounted 守卫 + try/catch——任何异常转 toast 不死机。
  Future<void> _startNewConversation() async {
    if (!mounted) return;
    try {
      final e = _buildHistoryEntry(includeUntouched: true);
      if (e != null) {
        // 合并磁盘最新（同 _appendHistory 的并发写防护）。
        final fresh = await HistoryStore.load();
        final merged = [...fresh, e];
        _history = List.of(merged);
        await HistoryStore.save(merged);
      }
      await Future<void>.delayed(const Duration(milliseconds: 30));
      if (!mounted) return;
      setState(() {
        _engine = null;
        // ⛔ 用出厂常量而非字面量：这条路径把页面**恢复成出厂状态**，
        // 字面量一旦与 `_kDefaultP1/_kDefaultP2` 分叉，`isPristine` 就会
        // 把「刚重置好的出厂页」误判成 dirty ⇒ 深链被无理由拒掉。
        _p1Ctrl.text = _kDefaultP1;
        _p2Ctrl.text = _kDefaultP2;
        _opLog.clear();
        _redoStack.clear();
        _selectedId = null;
        _armedId = null;
        _flashIds = {};
        _flashTimer?.cancel();
        _flashTimer = null;
        _focusSet = null;
        _picked.clear();
        _mode = _CanvasMode.browse;
        _expandedKeys.clear();
        _hiddenBackcross.clear();
        _error = null;
        _linkageOn = false;
        _familyOffsets.clear();
        _canvasLocked = false;
      });
      _toast('已保存当前记录，开启新对话（新白板）。');
    } catch (e) {
      _toast('保存失败：$e');
    }
  }

  // ── v2.1 基因型编辑 ──────────────────────────────────────
  /// 选中节点是否可编辑基因型（外来样本 / P 代初始双亲；子代只读）。
  bool _editableGenotype(PedigreeNode n) =>
      (n.isExternal || n.generation == 0) && !n.id.startsWith('SPLIT#');

  /// 打开基因型编辑对话框；成功后重算后代并记日志。
  /// 2.3 重构阶段 4：对话框 UI 已抽取至 widgets/pedigree_dialogs.dart
  /// （确认按钮内直接调 engine.editGenotype 校验，错误就地在框内展示）。
  Future<void> _editGenotype(PedigreeNode n) async {
    final engine = _engine;
    if (engine == null || !_editableGenotype(n)) return;
    final confirmed = await showPedigreeEditGenotypeDialog(
        context: context, engine: engine, n: n);
    if (!confirmed || !mounted) return;
    PedigreeNode? updated;
    for (final x in engine.nodes) {
      if (x.id == n.id) {
        updated = x;
        break;
      }
    }
    setState(() {
      engine.recomputeFrom(0);
      engine.ensureOffspringCoverage();
      _clearFocus();
      _pushLog(
          '编辑基因型：${n.genotype} → ${updated?.genotype ?? '(已移除)'}');
    });
    _report(_p1Ctrl.text, _p2Ctrl.text);
    await _appendHistory();
    _toast('已编辑基因型并重算。');
  }

  /// v3.4 撤销回退栈：_revertTo 丢弃的历史段（index+1 起）压栈，
  /// 「撤销上一步回退」按 LIFO 恢复——实现 Ctrl+Shift+Z 语义。
  final List<List<_LogEntry>> _redoStack = [];

  /// 应用某条日志对应的状态（引擎快照 + UI 开关回写 + 家族偏移）。
  /// _revertTo 与 _redoLastRevert 共用。
  void _applyEntry(_LogEntry entry) {
    final engine = _engine!;
    engine.restoreSnapshot(entry.snapshot);
    setState(() {
      // 快照含开关状态 → 回写 UI 开关，保持一致
      _trackSex = engine.trackSex;
      _allowSameSex = engine.allowSameSexMating;
      _allowMissingGene = engine.allowMissingGeneMating;
      _sexLinked = engine.sexLinked;
      // v2.1 多倍体/致死随快照回写（快照字段已含二者）
      _allowPolyploid = engine.allowPolyploid;
      _lethalGenotype = engine.lethalGenotype;
      // v2.19.6：恢复该步骤的选择/聚焦视图态（旧日志条目字段为 null
      // → 保持"清空瞬态"的既有行为）。
      final p = entry.picked, f = entry.focusSet, m = entry.mode;
      if (p != null) {
        _picked
          ..clear()
          ..addAll(p);
      } else {
        _picked.clear();
      }
      _focusSet = f == null ? null : Set.of(f);
      _mode = m ?? _CanvasMode.browse;
      // 其余瞬态照旧清理
      _selectedId = null;
      _armedId = null;
      _flashIds = {};
      // fork 并入：回退/重算时掐掉待触发的连线闪光 timer（性能修，
      // 防泄漏到已不存在的节点上闪）。
      _flashTimer?.cancel();
      _flashTimer = null;
      _expandedKeys.clear();
      _hiddenBackcross.clear();
      // R21：恢复该步骤的家族手动位置
      _familyOffsets
        ..clear()
        ..addAll(entry.familyOffsets);
    });
  }

  /// 回退到第 [index] 条日志对应的状态，其后的历史进入撤销回退栈。
  /// index=0 即「最开始」（初始计算后），天然封顶——不存在回退到 -1。
  void _revertTo(int index) {
    final engine = _engine;
    if (engine == null || index < 0 || index >= _opLog.length) return;
    if (index == _opLog.length - 1) return; // 已是当前状态
    final discarded = _opLog.sublist(index + 1);
    _applyEntry(_opLog[index]);
    _opLog.removeRange(index + 1, _opLog.length);
    if (discarded.isNotEmpty) _redoStack.add(discarded);
    _toast(index == 0
        ? '已回退到最开始（第 0 步）。'
        : '已回退到第 $index 步：${_opLog[index].label}');
  }

  /// 回退一步（Ctrl+Z）：回到上一条日志对应的状态。
  void _undoStep() {
    if (_opLog.length > 1) _revertTo(_opLog.length - 2);
  }

  /// 撤销最近一次回退（Ctrl+Shift+Z / 日志对话框按钮）：把回退时
  /// 丢弃的历史段恢复回来（状态 = 回退前最后一条日志）。
  void _redoLastRevert() {
    if (_engine == null || _redoStack.isEmpty) return;
    final seg = _redoStack.removeLast();
    final entry = seg.last; // 回退前状态
    _applyEntry(entry);
    _opLog.addAll(seg);
    _toast('已撤销回退：恢复为「${entry.label}」（第 ${_opLog.length - 1} 步）。');
  }

  /// 日志面板：最新在上；每条可「回退到此处」（第 0 步=最开始）；
  /// v3.4「撤销上一步回退」撤销最近一次回退（Ctrl+Shift+Z 语义）。
  /// 2.3 重构阶段 4：UI 已抽取至 widgets/pedigree_dialogs.dart
  /// （_LogEntry 为页面私有类型，对话框侧只收 labels + 回调）。
  void _showLogDialog() {
    showPedigreeLogDialog(
      context: context,
      labels: [for (final e in _opLog) e.label],
      canRedoRevert: _redoStack.isNotEmpty,
      onRevertTo: _revertTo,
      onRedoRevert: _redoLastRevert,
    );
  }

  /// v2.1 历史面板：自动记录的每次计算（基因型/家族/产出）；顶部
  /// 「保存当前并开新对话」= 归档当下白板（含家族）后清空开始新对话，
  /// 与历史完全隔离（历史只读回看）。
  /// 2.3 重构阶段 4：UI 已抽取至 widgets/pedigree_dialogs.dart，此处接线。
  void _showHistoryDialog() {
    showPedigreeHistoryDialog(
      context: context,
      history: _history,
      isMounted: () => mounted,
      onSaveAndNew: _startNewConversation,
    );
  }

  void _toast(String msg) {
    if (!mounted) return;
    // v3.5：提示框位于底部操作条上方，且动态让开左侧控制面板——
    // 不遮挡底部删除/计算按钮、也不遮挡左面板下部按钮
    //（原默认贴底 SnackBar 会盖底部条；v3.5 初版抬升后横贯全宽又
    // 压住左面板按钮，故按面板显隐调整左边距）。
    // v2.19.11（老师走查 🟡#5）：底边距抬离底栏。
    // v2.19.13（老师找茬 🔴2 修正）：固定 100 在课堂模式会糊在画布
    // 末代节点上（课堂底栏 80px + 100 = toast 坐画布下 1/3）。改为
    // 动态 = 底栏实际高 + 8：普通底栏 ~64 → 72；课堂底栏 ~80 → 88。
    // toast 紧贴底栏上缘露出，不遮画布主体。
    final panelShownNow = !widget.navCollapsed;
    final bottomPad = PresentModeController.instance.enabled ? 88.0 : 72.0;
    // 收起上一条要**立即移除**，不能用 hideCurrentSnackBar：它只是让
    // 旧提示播完退场动画，新提示排在队列里等旧的 2 秒走完——连续两步
    // 操作时后一条提示看起来「没出来」。
    ScaffoldMessenger.of(context)
      ..removeCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(msg),
        behavior: SnackBarBehavior.floating,
        margin: EdgeInsets.fromLTRB(
            // v2.19.26（手机 P2-5）：面板占位让位公式只适用宽屏——
            // 窄屏（<900，覆盖式面板）若照套 296 左边距，toast 可用宽
            // 只剩 78dp（约 5 个汉字）几乎不可读。窄屏固定 16 全宽。
            (MediaQuery.sizeOf(context).width >= 900 && panelShownNow)
                ? 296
                : 16,
            0,
            16,
            bottomPad),
        duration: const Duration(seconds: 2),
      ));
  }

  /// 把当前分析上下文写入全局状态，供 AI 助手读取。
  /// R17：上下文全量化——不再只报「主要基因型」，图上所有元素
  /// （每个节点的世代/家族/性别/基因型/概率/外来标记 + 每条连线
  /// 及其回交标注 + 语义开关）都发给 AI。
  ///
  /// v2.22.0+1 复核 MEDIUM：**「参考表型比例」也在这里同步**（唯一写入口）。
  /// 之前它由 `_applyCrossRef` 自己 `report`，而「双亲基因型」仍按主输入
  /// 上报 ⇒ 学生已有系谱时追加 AAbb × aaBB，AI 看到的却是
  /// 「双亲基因型：AABBCC × aabbcc」+ 一条不带亲本的裸比例，极易把参考
  /// 比例错挂到旧亲本上。现在值里带本次杂交的 p1 × p2 与来源，并与主输入
  /// 分成两个键并列上报（旧主输入照旧上报，公开契约不变）。
  /// 字段为空时摘键（先摘再 report：随后的 report 会 notifyListeners，
  /// 监听者重读快照时已是清理后的状态）。
  void _report(String p1, String p2) {
    final engine = _engine;
    if (engine == null) return;
    final state = AppState.instance;
    final refRatio = _crossRefRatio;
    if (refRatio == null) {
      state.contextFields.remove(_kRefRatioKey);
    }
    state.report('双亲基因型', '♂ $p1  ×  ♀ $p2');
    state.report('计算代数', '至 F${engine.maxGeneration}');
    state.report('语义开关',
        'XY 性别${_trackSex ? '开' : '关'}；同性交配${_allowSameSex ? '开' : '关'}');
    state.report('完整图谱', _fullGraphText(engine));
    if (refRatio != null) {
      final genotypes = _crossRefGenotypes;
      state.report(
          _kRefRatioKey,
          '$refRatio'
          '${genotypes == null ? '' : '（本次杂交 $genotypes）'}'
          '（来自${_crossRefSource ?? '计算器'}，参考值；非引擎推算）');
    }
  }

  /// 全量图谱文本：图上每个节点与每条连线的完整清单（供 AI 上下文）。
  String _fullGraphText(PedigreeGraphEngine engine) {
    final sb = StringBuffer();
    final idName = <String, String>{};
    String kindMark(PedigreeNode n) => switch (n.kind) {
          PedigreeNodeKind.male => '♂',
          PedigreeNodeKind.female => '♀',
          PedigreeNodeKind.group => '混合桶',
        };
    String genLabel(int g) => g == 0 ? 'P 代' : 'F$g';
    final multiFamily = engine.familyIds.length > 1;

    // SPLIT 半边不进节点清单（基因型与母桶重复），但要给连线端点留名
    for (final n in engine.nodes) {
      if (n.id.startsWith('SPLIT#')) {
        idName[n.id] = '${genLabel(n.generation)}·${n.genotype}'
            '${n.kind == PedigreeNodeKind.male ? '♂' : '♀'}半边';
      }
    }

    for (var g = 0; g <= engine.maxGeneration; g++) {
      final list = engine
          .nodesOf(g)
          .where((n) => !n.id.startsWith('SPLIT#'))
          .toList();
      if (list.isEmpty) continue;
      final parts = <String>[];
      for (final n in list) {
        final fam = multiFamily ? '·${engine.familyLabel(n.familyId)}' : '';
        final prob = n.isExternal
            ? '外来'
            : '${(n.probability * 100).toStringAsFixed(1)}%';
        final split = n.kind == PedigreeNodeKind.group &&
                engine.halfNode(n.id, PedigreeNodeKind.male) != null
            ? '·已分半边'
            : '';
        parts.add('${kindMark(n)} ${n.genotype}（$prob$fam$split）');
        idName[n.id] = '${genLabel(g)}·${n.genotype}';
      }
      sb.writeln('${genLabel(g)}：${parts.join('｜')}');
    }

    final mates = engine.edges
        .where((e) => e.kind == PedigreeEdgeKind.mating)
        .toList();
    if (mates.isNotEmpty) {
      final desc = mates.map((e) {
        final a = idName[e.fromId] ?? e.fromId;
        final b = idName[e.toId] ?? e.toId;
        final back = engine.isBackcross(e.fromId, e.toId) ? '（回交）' : '';
        return '$a × $b$back';
      }).join('；');
      sb.writeln('连线：$desc');
    }

    var text = sb.toString().trim();
    const cap = 3500; // 防御性截断：超大图谱不撑爆 prompt
    if (text.length > cap) {
      text = '${text.substring(0, cap)}\n……（图谱过大已截断，全文 $cap+ 字）';
    }
    return text.isEmpty ? '（图上暂无元素）' : text;
  }

  // ── R8 全屏 ─────────────────────────────────────────
  /// v3.5 多模态「问 AI」：先实时截取画布（内容包围盒 ROI，跳过
  /// 空白；家族移动后内容区自动变化，每次截图即最新），注入全局
  /// AI 控制器后打开助手面板。截图失败退化为纯文本问答。
  Future<void> _askAi() async {
    String? img;
    if (_computed) {
      try {
        img = await _captureCanvasImage();
      } catch (_) {
        img = null;
      }
    }
    if (!mounted) return;
    AiChatController.instance.pendingCanvasImage = img;
    showAiAssistant(context);
  }

  /// 画布存为 PNG（v2.4 功能 2）：复用 _captureCanvasImage 的
  /// 内容包围盒裁剪截图，落盘到图片目录（Biology板书）。
  ///
  /// v2.13 R4f（P1-2 · 四轮重审 Fix）：工具栏「存为图片」对齐 sheet 路径
  /// （_saveCanvasPng）——① 落盘成功后同样归档一份到 board_history/
  /// （_archiveBoardPng），否则老师卡「板书历史」永远列不到工具栏导出的
  /// PNG（此前只有 sheet「保存为 PNG 文件」归档）；② SnackBar 补 action：
  /// Android [分享]（走 biology/share_file → 微信群，与 sheet 一致），
  /// 桌面 [打开所在目录]（文件在 ~/.biology_app/Pictures/Biology板书）。
  Future<void> _exportCanvasPng() async {
    final b64 = await _captureCanvasImage();
    if (!mounted) return;
    if (b64 == null) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('画布暂无可截内容')));
      return;
    }
    final bytes = base64Decode(b64);
    final r = await writePng(bytes, '系谱图');
    if (!mounted) return;
    // 与 _saveCanvasPng 对齐：写盘成功后归档板书历史副本（失败不阻塞，
    // _archiveBoardPng 内部吞错）。Web r.path 恒 null，自动跳过。
    if (r.path != null) {
      await _archiveBoardPng(bytes);
    }
    if (!mounted) return; // archive await 之后重新确认 mounted（analyzer 守卫）
    final isAndroid = MistakeBookExporter.isAndroidExport;
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(SnackBar(
      // v2.13 R4-2（P1-2 EACCES 修复）：Android 上 writePng 落应用专属
      // 目录（getFilesDir 下），不显示私有绝对路径（/data/data/...），
      // 文案诚实告知位置。
      content: Text(
        r.path != null
            ? (isAndroid
                ? '已保存到应用目录（可导出/分享）'
                : '已保存：${r.path}')
            : r.error ?? '导出失败',
      ),
      duration: const Duration(seconds: 4),
      action: r.path != null
          ? SnackBarAction(
              label: isAndroid ? '分享' : '打开所在目录',
              onPressed: isAndroid
                  ? () => _shareBoardPng(r.path!)
                  : () async {
                      // 与 _saveCanvasPng 同款：消费 openInExplorer 返回值，
                      // 失败弹 SnackBar（不静默）。
                      final err =
                          await MistakeBookExporter.openInExplorer(r.path!);
                      if (err != null && mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text(err)),
                        );
                      }
                    },
            )
          : null,
    ));
  }

  /// v2.19.13（学生找茬 🟡6）：E（不带修饰键）= 一键直出 SVG 文本——
  /// 跳过选择菜单（Ctrl+Shift+E 仍走菜单：板书/PNG/存历史三选一）。
  /// 学生提案「复制比导出更常用」的语义对齐。
  Future<void> _copySvgQuick() async {
    if (_engine == null) {
      _toast('请先计算系谱图（点「计算」按钮）');
      return;
    }
    // v3.6：导出与屏上可见视图一致（智能密线同样作用于导出）。
    final g = _viewportGraph();
    await _copySvgText(g.nodes, g.edges);
  }

  /// v2.12.0+2 hotfix：板书 SVG 复制到剪贴板。
  /// 把当前引擎节点/边序列化为标准 SVG XML 字符串，写入系统剪贴板，
  /// 老师可直接粘到微信/Word/富文本编辑器。剪贴板跨三端都能读。
  Future<void> _exportCanvasSvg() async {
    final engine = _engine;
    if (engine == null) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('请先计算系谱图（点「计算」按钮）')));
      return;
    }
    if (!mounted) return;
    final choice = await showModalBottomSheet<_SvgCopyChoice>(
      context: context,
      builder: (ctx) => _SvgCopySheet(),
    );
    if (choice == null || !mounted) return;
    // v3.6：SVG / 板书导出与屏上可见视图一致（密线抽稀同样生效）。
    final g = _viewportGraph();
    switch (choice) {
      case _SvgCopyChoice.svg:
        await _copySvgText(g.nodes, g.edges);
        break;
      case _SvgCopyChoice.png:
        // v2.12+ R2 P0-B2：改走真实文件落盘（替代 v2.12.0+2 的 base64 字符串
        // 写剪贴板粘到微信/纯文本编辑器的乱码问题）。
        await _saveCanvasPng();
        break;
      case _SvgCopyChoice.saveAsBoard:
        // v2.12+ R2 P0-A1：写盘到 board_history/ 目录，dashboard 老师卡可见。
        await _saveAsBoard(g.nodes, g.edges);
        break;
    }
  }

  /// SVG 文本复制到剪贴板（v2.12.0+2 hotfix 原行为）。
  Future<void> _copySvgText(
      List<PedigreeNode> nodes, List<PedigreeEdge> edges) async {
    final svg = pedigreeToSvg(nodes, edges);
    await Clipboard.setData(ClipboardData(text: svg));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Text('SVG 文本已复制（粘到富文本编辑器 / 保存为 .svg）'),
      duration: Duration(seconds: 4),
    ));
  }

  /// v2.12+ R2 P0-B2：板书 PNG 落盘到下载目录（替代 v2.12.0+2 +
  /// R1 P0 #4 的「复制 PNG base64 到剪贴板」伪功能——粘到微信是乱码）。
  ///
  /// 行为变化：
  ///   - 桌面 / 安卓：复用 MistakeBookExporter.savePngToDownloads，
  ///     落盘到 ~/Downloads/（与 _exportCanvasPng 走 Pictures/Biology板书
  ///     区分——板书 PNG 是用户主动导出的「可分发文件」，放 Downloads 更
  ///     符合用户预期「老师课后用」）
  ///   - Web：触发浏览器 <a download> Blob 下载（MIME = image/png）
  ///   - 落盘 / 下载成功后 SnackBar 「板书已保存」+ （桌面 / macOS /
  ///     Linux）[打开下载目录] action 直接定位文件
  ///
  /// v2.13 R4 P1：桌面 / 安卓落盘成功后，另归档一份副本到
  /// board_history/（_archiveBoardPng，与 _saveAsBoard 的 SVG 归档
  /// 同目录）→ dashboard 老师卡「板书历史」能看到 PNG 条目。
  ///
  /// 错误处理：写盘失败 / Web 触发失败 SnackBar 提示错误（不静默吞错）。
  /// 复用 _captureCanvasImage() 抓 PNG（base64 → Uint8List）。
  Future<void> _saveCanvasPng() async {
    final b64 = await _captureCanvasImage();
    if (!mounted) return;
    if (b64 == null) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('画布暂无可截内容')));
      return;
    }
    final baseName = '系谱图_${DateTime.now().millisecondsSinceEpoch}';
    final bytes = base64Decode(b64);
    final r = await MistakeBookExporter.savePngToDownloads(bytes, baseName);
    if (!mounted) return;
    if (r == null || r.startsWith('导出失败') || r == '未找到可写目录') {
      // 错误路径
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(r ?? '导出失败'),
          duration: const Duration(seconds: 4),
        ),
      );
      return;
    }
    // 成功路径：
    //   - 桌面 / macOS / Linux：r 是文件路径 → [打开下载目录] action
    //   - Android（v2.13 R4-2）：r 是应用专属目录里的文件路径 →
    //     [分享] action（走 biology/share_file channel，老师板书 PNG
    //     → 微信群）
    //   - Web：r 是「已触发浏览器下载」 → action 隐藏
    final isFilePath = !r.startsWith('已触发');
    // v2.13 R4 P1：桌面/安卓路径再归档一份到 board_history/（与 SVG
    // 归档同目录），dashboard 老师卡「板书历史」能列到 PNG——修复
    // 「老师高频 PNG 路径永不进历史 → 历史恒空」的根因。
    if (isFilePath) {
      await _archiveBoardPng(bytes);
    }
    if (!mounted) return; // archive await 之后重新确认 mounted（analyzer 守卫）
    final isAndroid = MistakeBookExporter.isAndroidExport;
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          isFilePath
              ? (isAndroid
                  ? '板书已保存到应用目录（可导出/分享）'
                  : '板书已保存：${r.split(Platform.pathSeparator).last}')
              : r,
        ),
        duration: const Duration(seconds: 4),
        action: isFilePath
            ? SnackBarAction(
                label: isAndroid ? '分享' : '打开下载目录',
                onPressed: isAndroid
                    ? () => _shareBoardPng(r)
                    : () async {
                        // v2.13 R4 P1：消费 openInExplorer 返回值，失败弹
                        // SnackBar（此前忽略返回值 = 死 action，失败静默）。
                        final err = await MistakeBookExporter.openInExplorer(r);
                        if (err != null && mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text(err)),
                          );
                        }
                      },
              )
            : null,
      ),
    );
  }

  /// v2.13 R4-2：Android 分享已导出的板书 PNG（老师 → 微信群）。
  /// 走 biology/share_file channel（MainActivity Intent.ACTION_SEND +
  /// FileProvider content:// URI）。失败 SnackBar 透出错误原因。
  Future<void> _shareBoardPng(String path) async {
    final err = await shareFile(path, mimeType: 'image/png');
    if (!mounted) return;
    if (err != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(err), duration: const Duration(seconds: 4)),
      );
    }
  }

  /// v2.13 R4 P1：板书 PNG 归档副本——`savePngToDownloads` 写盘成功后
  /// 同写一份 `board_history/pedigree_<iso>.png`（与 `_saveAsBoard` 的
  /// SVG 归档同目录），dashboard 老师卡「板书历史」列到 PNG。
  ///
  /// 目录解析与 `_saveAsBoard` 一致：`debugBoardHistoryDirForTest` 优先，
  /// 否则 `userAppDir() + board_history`。
  ///
  /// 归档失败不阻塞主流程（Downloads 已保存成功，成功 SnackBar 已承诺
  /// 下载路径；归档只是历史副本）——吞掉 + debugPrint，不在成功路径
  /// 弹错误造成认知矛盾。
  Future<void> _archiveBoardPng(Uint8List bytes) async {
    try {
      final overrideDir = GeneticPedigreePage.debugBoardHistoryDirForTest;
      final dir = overrideDir != null
          ? Directory(overrideDir)
          : (() {
              final appDir = userAppDir();
              if (appDir == null) return null;
              return Directory(
                  '$appDir${Platform.pathSeparator}board_history');
            })();
      if (dir == null) return;
      if (!dir.existsSync()) dir.createSync(recursive: true);
      final ts = DateTime.now()
          .toIso8601String()
          .replaceAll(':', '-')
          .replaceAll('.', '-');
      final f = File(
          '${dir.path}${Platform.pathSeparator}pedigree_$ts.png');
      await f.writeAsBytes(bytes, flush: true);
    } catch (e) {
      debugPrint('板书 PNG 归档失败（不影响已保存的下载文件）：$e');
    }
  }

  /// v2.12+ R2 P0-A1：板书 SVG 存盘到 `~/.biology_app/board_history/`。
  ///
  /// 端到端真写盘，修复 R1 死链：commit 85a870e 承诺「存为板书」实
  /// 为「SVG/PNG 复制格式选择器」，dashboard 老师工具卡的「板书历史」
  /// 永远是空——本提交兑现真写盘承诺。
  ///
  /// 跨端：
  ///   - 桌面 / 安卓：writeAsString 到 ``<userAppDir>/board_history/
  ///     pedigree_<timestamp>.svg``。路径与 dashboard `_TeacherPage.
  ///     _boardHistoryDir()` 解析一致（都走 userAppDir 约定），保证
  ///     dashboard 列表能看到刚写的文件。
  ///   - Web：无文件系统概念，调条件导入的 `stubBoardDownload` 触发
  ///     Blob + ``<a download>``。MIME = image/svg+xml，文件名
  ///     ``pedigree_<timestamp>.svg``。dashboard 老师卡不会列该文件
  ///     （Web 端 _boardHistoryDir 返 null），但浏览器下载目录有。
  ///
  /// 错误处理：写盘失败 / Web 触发失败 SnackBar 提示错误（不静默吞错，
  /// 同 _saveCanvasPng 哲学）。写盘成功 SnackBar「已存为板书：<路径>」
  /// + 桌面端 [在文件管理器中显示] action 复走 MistakeBookExporter.
  /// openInExplorer（与 R2-B P0-B2 板书 PNG 行为一致）。
  Future<void> _saveAsBoard(
      List<PedigreeNode> nodes, List<PedigreeEdge> edges) async {
    final svg = pedigreeToSvg(nodes, edges);
    if (kIsWeb) {
      try {
        final ts = DateTime.now()
            .toIso8601String()
            .replaceAll(':', '-')
            .replaceAll('.', '-');
        stubBoardDownload(svg, 'pedigree_$ts.svg');
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('已触发浏览器下载 pedigree_<时间戳>.svg'),
          duration: Duration(seconds: 4),
        ));
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('存为板书失败：$e')),
        );
      }
      return;
    }
    // 桌面/安卓：File 写盘。debugBoardHistoryDirForTest 非空时
    // 走测试注入目录（避免污染真实 ~/.biology_app/board_history/）。
    final overrideDir = GeneticPedigreePage.debugBoardHistoryDirForTest;
    final dir = overrideDir != null
        ? Directory(overrideDir)
        : (() {
            final appDir = userAppDir();
            if (appDir == null) return null;
            return Directory('$appDir${Platform.pathSeparator}board_history');
          })();
    if (dir == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('存为板书失败：未找到应用目录'),
      ));
      return;
    }
    try {
      if (!dir.existsSync()) dir.createSync(recursive: true);
      final ts = DateTime.now()
          .toIso8601String()
          .replaceAll(':', '-')
          .replaceAll('.', '-');
      final file = File(
          '${dir.path}${Platform.pathSeparator}pedigree_$ts.svg');
      await file.writeAsString(svg, flush: true);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('已存为板书：${file.path}'),
          duration: const Duration(seconds: 4),
          action: SnackBarAction(
            label: '在文件管理器中显示',
            onPressed: () async {
              // v2.13 R4 P1：消费 openInExplorer 返回值，失败弹
              // SnackBar（此前忽略返回值 = 死 action，失败静默）。
              final err =
                  await MistakeBookExporter.openInExplorer(file.path);
              if (err != null && mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(err)),
                );
              }
            },
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('存为板书失败：$e')),
      );
    }
  }

  /// v2.13 R3 P1-D1：PNG 解码/裁剪/编码（纯 Dart，package:image）——
  /// UI 线程实测 544ms/次（2800×1800×2x 大画布，1860×1200 = 235ms）。
  /// native / VM 端由 `_captureCanvasImage` 包进 `Isolate.run` 执行，
  /// UI 线程只收 base64；web 端无真 isolate（dart2js/dartdevc 的
  /// `Isolate.spawn` 运行时抛 UnsupportedError，见 SDK
  /// js_runtime/lib/isolate_patch.dart）→ 保持原地执行，功能正确优先。
  ///
  /// [pngData] 为 `toByteData(png)` 的原始 PNG 字节；left/top/width/height
  /// 是 ROI × 2（pixelRatio=2 的截图像素坐标）。返回 base64 PNG，
  /// null = 解码失败（无可截内容）。
  static String? _cropEncodePng(
    Uint8List pngData,
    double left,
    double top,
    double width,
    double height,
  ) {
    // 测试 mock：模拟编码耗时（默认 0 = 不生效）。sleep 同步阻塞当前执行
    // 上下文——native 端在 isolate 里阻塞，UI 线程照常响应；测试借此
    // 断言编码已不在 UI 线程。
    final mockDelay = GeneticPedigreePage.debugEncodeDelayMs;
    if (mockDelay > 0) {
      sleep(Duration(milliseconds: mockDelay));
    }
    final decoded = img.decodePng(pngData);
    if (decoded == null) return null;
    final x = left.round().clamp(0, decoded.width - 1);
    final y = top.round().clamp(0, decoded.height - 1);
    final w = width.round().clamp(1, decoded.width - x);
    final h = height.round().clamp(1, decoded.height - y);
    final cropped = img.copyCrop(decoded, x: x, y: y, width: w, height: h);
    return base64Encode(img.encodePng(cropped));
  }

  /// 画布截图（PNG base64）：世界内容包围盒 → 屏幕 ROI（裁剪到
  /// 视口内）→ RepaintBoundary 2x 截图 → image 包 copyCrop 裁掉
  /// 空白 → 输出 PNG base64。返回 null 表示无可截内容。
  ///
  /// v2.13 R3 P1-D1：decode/crop/encode 移入 `Isolate.run`（native /
  /// VM），UI 线程不再被 544ms 编码冻结；传 isolate 的只有 PNG 字节 +
  /// ROI 四值（均可跨 isolate 传输），UI 线程只收 base64 字符串。
  Future<String?> _captureCanvasImage() async {
    final boundary = _canvasBoundaryKey.currentContext?.findRenderObject()
        as RenderRepaintBoundary?;
    final st = _canvasStateKey.currentState;
    if (boundary == null || st == null) return null;
    final world = st.debugContentRect();
    if (world == Rect.zero) return null;
    final m = st.contentTransform;
    final tl = MatrixUtils.transformPoint(m, world.topLeft);
    final br = MatrixUtils.transformPoint(m, world.bottomRight);
    var roi = Rect.fromPoints(tl, br);
    roi = roi.intersect(Offset.zero & boundary.size);
    if (roi.width < 16 || roi.height < 16) return null;
    try {
      final shot = await boundary.toImage(pixelRatio: 2);
      final bytes = await shot.toByteData(format: ui.ImageByteFormat.png);
      if (bytes == null) return null;
      // 拷贝成精确长度、独立缓冲区的 Uint8List（isolate 消息按底层
      // buffer 拷贝，视图会连多余字节一起带过去）。
      final pngData = Uint8List.fromList(
          bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes));
      final left = roi.left * 2;
      final top = roi.top * 2;
      final width = roi.width * 2;
      final height = roi.height * 2;
      if (kIsWeb) {
        // web：无真 isolate，原地执行（功能正确；冻结仅存在于 web，且
        // 画布尺寸受浏览器视口约束，远小于桌面 2800×1800）。
        return _cropEncodePng(pngData, left, top, width, height);
      }
      return await Isolate.run<String?>(
          () => _cropEncodePng(pngData, left, top, width, height));
    } catch (_) {
      return null;
    }
  }

  void _openFullscreen() {
    StateSetter? dialogSetState;
    showDialog<void>(
      context: context,
      barrierColor: AppColors.canvas,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          dialogSetState = setDialogState;
          _fullscreenSetState = setDialogState;
          return Dialog.fullscreen(
            backgroundColor: AppColors.canvas,
            child: CallbackShortcuts(
              bindings: {
                const SingleActivator(LogicalKeyboardKey.escape): () =>
                    Navigator.of(ctx).pop(),
                // v2.19.13（学生找茬 🔴1）：全屏讲课主场景补齐页面级
                // 快捷键——原只绑 Esc，Ctrl+Shift+E/V 在全屏里无响应，
                // 老师只能去悬浮面板点按钮。同回调同链。
                const SingleActivator(LogicalKeyboardKey.keyE,
                    control: true, shift: true): _exportCanvasSvg,
                // v2.19.15：同页面级——裸键 E 守卫输入框焦点（DeepSeek 🔴1）。
                const SingleActivator(LogicalKeyboardKey.keyE): () {
                  final focus = FocusManager.instance.primaryFocus;
                  // v2.19.26 同 main.dart 守卫修复：焦点挂在内部 Focus widget，
                  // 须祖先查找 EditableText。
                  if (focus?.context != null &&
                      focus!.context!
                              .findAncestorWidgetOfExactType<EditableText>() !=
                          null) return;
                  _copySvgQuick();
                },
                const SingleActivator(LogicalKeyboardKey.keyV,
                    control: true, shift: true): _saveCanvasPng,
              },
              child: Focus(
                autofocus: true,
                child: _buildCanvasArea(fullscreen: true),
              ),
            ),
          );
        },
      ),
    ).whenComplete(() {
      // 只清理本次 Dialog 的句柄，避免旧路由完成后误清新路由。
      if (identical(_fullscreenSetState, dialogSetState)) {
        _fullscreenSetState = null;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    /// v3.1：窄屏（<720 → v2.19.26 改 <900）时左控制面板以覆盖式呈现。
    /// 阈值上调原因（平板 F-5）：平板竖屏 800 宽走占位式，面板 280 +
    /// rail 72 把画布挤到 ~447px、初始 fit 缩放 ~0.56 难读；800..899
    /// 改覆盖式后画布全宽（面板 ☰ 召唤、可叠）。
    // v3.3：面板显隐统一跟随 HomeShell ☰（navCollapsed）——双向，
    // 右上角不再有独立面板开关（用户反馈"右上角多一个三杠按钮，
    // 图标还会变"的根因，已移除）。
    final narrow = MediaQuery.sizeOf(context).width < 900;
    final panelShown = !widget.navCollapsed;
    final canvasColumn = Column(
      children: [
        // P0-3：报错优先显示在亲本输入框上方（见 _withParentError）；
        // 左栏收起 / 窄屏折叠时这条贴画布顶部兜底，别让错误消失。
        if (_error != null && !panelShown)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(_error!,
                  style: AppText.caption.copyWith(color: AppColors.lethal)),
            ),
          ),
        // v3.6：9331 带进来的参考表型比（参考值，非引擎推算）。
        if (_crossRefRatio != null) _buildCrossRefBanner(),
        Expanded(
          child: _computed
              ? Column(
                  children: [
                    // v2.16 UI 重做：画布操作（模式/添加家族/添加样本/
                    // 全屏）迁入顶部命令栏左侧组——零画布遮挡（系谱
                    // 内容自上而下生长，底中央是交互雷区）， prominence
                    // 最高（常驻顶栏）。画布保持纯净。
                    Expanded(child: _buildCanvasAreaFull(false, panelShown)),
                    _buildDetailStrip(),
                  ],
                )
              : _buildEmptyState(),
        ),
      ],
    );

    return CallbackShortcuts(
      bindings: {
        // v3.4 撤销/撤销回退（Windows Ctrl+Z / Ctrl+Shift+Z 语义）
        const SingleActivator(LogicalKeyboardKey.keyZ, control: true):
            _undoStep,
        const SingleActivator(LogicalKeyboardKey.keyZ,
            control: true, shift: true): _redoLastRevert,
        // v2.19.11 键盘党（学生走查 #3）：Ctrl+Shift+E = 复制板书菜单
        // （板书/PNG/存历史三选一）；E（裸键）= 一键直出 SVG 文本
        // （v2.19.13 学生找茬 🟡6，跳过菜单，复制比导出更常用）。
        const SingleActivator(LogicalKeyboardKey.keyE,
            control: true, shift: true): _exportCanvasSvg,
        // v2.19.15（DeepSeek 找茬 🔴1）：裸键 E 必须守卫输入框焦点——
        // EditableText 不消费原始键事件（Flutter shortcuts_test.dart 实
        // 证：绑定到 Shortcuts 的动作会覆盖文本框），基因型框里敲 e
        // 会触发复制 SVG + 覆写剪贴板 + 莫名 toast。
        const SingleActivator(LogicalKeyboardKey.keyE): () {
          final focus = FocusManager.instance.primaryFocus;
          // v2.19.26 同 main.dart 守卫修复：焦点挂在内部 Focus widget，
              // 须祖先查找 EditableText。
              if (focus?.context != null &&
                  focus!.context!
                          .findAncestorWidgetOfExactType<EditableText>() !=
                      null) return;
          _copySvgQuick();
        },
        // v2.19.13 学生找茬轮 P2：Ctrl+Shift+V = 一键出板书 PNG（与
        // 顶栏「板书 PNG」按钮同链，免点按钮）。语义说明：学生提案直出
        // PNG 比复制 SVG 更常用——V 取「视图/View」首字母联想；
        // Ctrl+V 系粘贴但加 Shift 后在本应用无冲突占用。
        const SingleActivator(LogicalKeyboardKey.keyV,
            control: true, shift: true): _saveCanvasPng,
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          body: Column(
            children: [
              _buildCommandBar(narrow, panelShown),
              Expanded(
                // 宽屏：占位式（面板挤占画布左缘）；窄屏：覆盖式（浮于画布上）
                child: narrow
                    ? Stack(
                        children: [
                          Positioned.fill(child: canvasColumn),
                          if (panelShown)
                            Positioned(
                              left: 0,
                              top: 0,
                              bottom: 0,
                              child: _withParentError(_buildSidePanel(overlay: true)),
                            ),
                          if (_crossOpen)
                            Positioned(
                              right: 0,
                              top: 0,
                              bottom: 0,
                              child: _buildCrossPanel(overlay: true),
                            ),
                        ],
                      )
                    : Row(
                        children: [
                          if (panelShown)
                            _withParentError(_buildSidePanel(overlay: false)),
                          Expanded(child: canvasColumn),
                          if (_crossOpen) _buildCrossPanel(overlay: false),
                        ],
                      ),
              ),
              // 底部操作条：与「问 AI」FAB 同层，页面最底端（安卓小屏拇指区）
              _buildBottomBar(),
            ],
          ),
        ),
      ),
    );
  }

  /// 9331 → 系谱桥接带来的**参考**表型比例条。
  ///
  /// 刻意与引擎结果分开呈现：引擎按孟德尔分离逐代模拟，不建模基因
  /// 互作，9:7 / 15:1 等变式不会被它自动推出 —— 所以这里写明「参考值，
  /// 非引擎推算」。收起只移除横幅与 AI 上下文里的参考字段，不动引擎
  /// 与系谱本身。
  Widget _buildCrossRefBanner() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 6, 20, 0),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        decoration: BoxDecoration(
          color: AppColors.sand.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(AppTheme.radiusInput),
          border: Border.all(color: AppColors.sand.withValues(alpha: 0.35)),
        ),
        child: Row(
          children: [
            Icon(Icons.functions, size: 16, color: AppColors.sand),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '参考表型比例 ${_crossRefRatio!}'
                '${_crossRefGenotypes == null ? '' : '（${_crossRefGenotypes!}）'}'
                ' · 来自${_crossRefSource ?? '计算器'}，参考值，非引擎推算',
                style: AppText.caption.copyWith(color: AppColors.ink),
                softWrap: true,
              ),
            ),
            Tooltip(
              message: '返回原 9331 页面，保留原输入与结果',
              child: TextButton.icon(
                onPressed: ModuleFillBus.targetOf('cross_dihybrid') == null
                    ? null
                    : () => returnToCrossCalculator(),
                icon: const Icon(Icons.arrow_back, size: 17),
                label: const Text('返回 9331'),
              ),
            ),
            IconButton(
              tooltip: '收起参考比例',
              onPressed: () {
                setState(() {
                  _crossRefRatio = null;
                  _crossRefGenotypes = null;
                  _crossRefSource = null;
                });
                // 收起不仅是视觉动作：AI 也不能继续看到已撤下的参考值。
                _report(_p1Ctrl.text, _p2Ctrl.text);
              },
              icon: Icon(Icons.close, size: 16, color: AppColors.steel),
            ),
          ],
        ),
      ),
    );
  }

  /// v2.21.0 空态：单层薄壳 + 三步说明；不新增按钮或独立「计算」文本。
  /// v3.7 老师首用扩写：补「这是什么」「三步具体做什么」「算完能做什么」
  /// 「左栏还能开什么」四段。内容变长 → 整卡套滚动（390 窄屏 / 课堂大字
  /// 都不会撑破画布区），外层 Padding / Center / 680 视觉语言不变。
  Widget _buildEmptyState() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Center(
        child: SingleChildScrollView(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 680),
            child: ModuleSurface(
              padding: const EdgeInsets.fromLTRB(22, 20, 22, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Container(
                      width: 46,
                      height: 46,
                      decoration: BoxDecoration(
                        color: AppColors.tealWash,
                        borderRadius: BorderRadius.circular(13),
                        border: Border.all(
                            color: AppColors.teal.withValues(alpha: 0.35),
                            width: 1.5),
                      ),
                      child: Icon(Icons.account_tree_outlined,
                          size: 24, color: AppColors.teal),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text('填入双亲基因型，点击「计算」',
                          style: AppText.sectionTitle),
                    ),
                  ]),
                  const SizedBox(height: 10),
                  // 这是什么：一句话讲清产出，新手先有预期再看步骤。
                  Text(
                    '把双亲基因型填进去，就能算出子代的基因型、表现型与比例，'
                    '并按代画出关系图。',
                    style: AppText.body.copyWith(color: AppColors.graphite),
                  ),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _emptyStep('01 输入',
                          '左栏写亲本基因型，如 AaBb × AaBb；'
                          '大小写=显隐性，连写=多对基因同株'),
                      _emptyStep('02 计算',
                          '点底栏「计算」，画布按代出节点，节点标基因型与比例'),
                      _emptyStep('03 连线',
                          '开「连线」点父方再点母方，再点「计算」，'
                          '才按指定配对出子代；不连线用默认随机配对'),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _emptyNote('算完之后能做什么'),
                  Text(
                    '计算后可：点节点看信息 · 开「连线」配对 · '
                    '长按节点收线（多条可选） · 右键空白加样本',
                    style: AppText.caption,
                  ),
                  Text(
                    '长按空白=加样本 · 底栏「+」推下一代 · 垃圾桶删整代 · '
                    '「全部连线」恢复自动边 · 「只看所选」聚焦某一支',
                    style: AppText.caption,
                  ),
                  const SizedBox(height: 12),
                  _emptyNote('左栏还能开什么'),
                  Text(
                    '伴性遗传（XY）· 连锁互换 · 致死筛选 · 多倍体 · 基因频率'
                    '——按题目需要打开后重新「计算」。',
                    style: AppText.caption,
                  ),
                  const SizedBox(height: 12),
                  // 空态下画布未渲染、底部提示条也不存在，手势串只能写在这。
                  Text(
                    '画布操作：拖动或滚轮=平移 · Ctrl+滚轮或双指=缩放 · '
                    '点节点=查看信息 · 长按节点或右键=收线 · '
                    '右键或长按空白=加样本 · 缩放条 ⛶=适应视图',
                    style: AppText.caption,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// 空态里的小节标题（与 _emptyStep 的编号同色同字重）。
  Widget _emptyNote(String title) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Text(title,
            style: AppText.label.copyWith(
                color: AppColors.teal, letterSpacing: 0.4)),
      );

  /// 编号与动作名合并成一个 Text，避免劫持旧测试的按钮文案定位。
  Widget _emptyStep(String label, String detail) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.surfaceLow,
        borderRadius: BorderRadius.circular(AppTheme.radiusInput),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label,
              style: AppText.label.copyWith(
                  letterSpacing: 0.4, color: AppColors.teal)),
          const SizedBox(width: 8),
          Flexible(child: Text(detail, style: AppText.caption)),
        ],
      ),
    );
  }

  /// 页面内嵌画布区（v3.7：右上悬浮按钮面板只在全屏 Dialog 显示——
  /// 页面内控制功能全部收纳于 ☰ 左面板 / 底部操作条 / 缩放条 / 右键
  /// 菜单，不再有悬浮备份，避免与缩放条/面板互相遮挡）。
  Widget _buildCanvasAreaFull(bool fullscreen, bool panelShown) =>
      _buildCanvasArea(
          fullscreen: fullscreen, showFloatingActions: fullscreen);

  /// v3.1 命令栏（替掉默认 AppBar）：左 = 页面标题 + 状态摘要 chip；
  /// 右 = 控制面板开合按钮 + 页面级动作（问 AI）。
  /// 2.3 重构阶段 5：已抽取为 PedigreeCommandBar
  /// （widgets/pedigree_command_bar.dart），此处只做状态/回调接线。
  Widget _buildCommandBar(bool narrow, bool panelShown) {
    return PedigreeCommandBar(
      onNavPressed: widget.onNavPressed,
      computed: _computed,
      maxGeneration: _engine?.maxGeneration ?? 0,
      // v2.19.68 P2-1：_opLog 空列表（本次计算后还没做过任何操作）时
      // length-1 = -1，顶栏显示「日志（-1）」。历史记录为空 = 0 条可
      // 回退，clamp 到 0。既有回退/重做语义不变（pedigree_ui_test
      // 断言的 日志（0/1/2…） 分支都不受影响）。
      logCount: _opLog.length <= 1 ? 0 : _opLog.length - 1,
      historyCount: _history.length,
      crossOpen: _crossOpen,
      onShowLog: _showLogDialog,
      onShowHistory: _showHistoryDialog,
      onToggleCrossPanel: _toggleCrossPanel,
      onAskAi: _askAi,
      // v2.18 R7 #3：画布操作唯一事实源 = 底栏（顶栏左组已撤）。
      // v2.12.0+2 hotfix：宽屏命令栏「复制 SVG」入口（窄屏不放以
      // 避免命令栏挤断）。
      onExportSvg: _exportCanvasSvg,
    );
  }

  /// v3.2 底部操作条：页面最底端、与「问 AI」FAB 同层。常驻两个主操作：
  /// 左 =「删除整代」（lethal 描边，破坏性语义）；右 =「计算」主按钮。
  /// 2.3 重构阶段 5：已抽取为 PedigreeBottomBar
  /// （widgets/pedigree_bottom_bar.dart），此处只做可用态/回调接线。
  Widget _buildBottomBar() {
    return PedigreeBottomBar(
      engineAlive: _engine != null,
      onDeleteGeneration: _showDeleteGenerationDialog,
      onExpandNext: _expandNext,
      onDerive: _derive,
      // v2.17：画布编辑组收编底栏（>=1200 逻辑宽；课堂白板可达性——
      // 几米长白板上老师够不到上半屏，高频操作必须落在底缘）。
      wireModeOn: _mode == _CanvasMode.wire,
      onToggleWireMode: _toggleWireMode,
      selecting: _mode == _CanvasMode.select,
      focusing: _focusSet != null,
      pickedCount: _picked.length,
      onEnterSelect: _onEnterSelect,
      onApplyFocus: _onApplyFocus,
      onShowAll: _onShowAll,
      // v3.6：「全部连线」视图开关（与聚焦「显示全部」是两个动作）。
      allEdgesOn: _showAllEdges,
      onToggleAllEdges: _toggleAllEdges,
      // v2.19.2 R8 #1：曲线开关下沉底栏模式 segmented（白板可达）。
      curveLinesOn: _edgeStyle == PdEdgeStyle.curve,
      onToggleCurveLines: (v) => _setEdgeStyle(
          v ? PdEdgeStyle.curve : PdEdgeStyle.orthogonal),
      onAddFamily: _showAddFamilyDialog,
      onAddSample: () => _showAddSampleDialog(_engine!.maxGeneration),
      onFullscreen: _openFullscreen,
      // R8 老师走查 #6：⋯ 更多（顶栏四按钮的底缘第二入口）。
      onShowLog: _showLogDialog,
      onShowHistory: _showHistoryDialog,
      onToggleCrossPanel: _toggleCrossPanel,
      onExportSvg: _exportCanvasSvg,
      // O-6 同性交配开关底栏第二入口（白板可达）：>=1280 渲染
      // IconButton；<1280 由侧栏 ⋯ chip 承接。阈值 1280 是 O-6
      // 实测：1200 viewport 下底栏左编辑组+右簇相加 ≈ 1052.7 px
      // 溢出 0.7 px → 黄黑斜条覆盖侧栏 chip → R18/R21 hit test
      // 失败。回调复用 _toggleSameSex（不是上轮误名的
      // _toggleAllowSameSex——方法签名 (bool v)）。
      allowSameSex: _allowSameSex,
      onToggleSameSex: _toggleSameSex,
    );
  }

  /// 画布区：页面内嵌与全屏 Dialog 共用（各自独立的视口变换）。
  /// showFloatingActions：右上悬浮按钮面板是否显示（v3.1 与左控制
  /// 面板互斥：全屏 Dialog 无左面板 → 常驻；页面内左面板可见 → 隐藏）。
  /// 2.3 重构阶段 6：渲染树已抽取为 PedigreeCanvasArea
  /// （widgets/pedigree_canvas_area.dart）；此处保留折叠过滤/聚焦/
  /// solo 半边派生计算，只向组件注入算好的可见集与回调，行为不变。
  Widget _buildCanvasArea(
      {required bool fullscreen, bool showFloatingActions = true}) {
    final engine = _engine!;
    // wire 模式视觉只由 armed(紫) / flash(橙) 承担：普通选中光、相连
    // 柔光、选择绿勾一律不传给画布。这里是**状态隔离**（Page 侧），
    // Painter / Canvas 的公开参数契约保持不变。
    final wireMode = _mode == _CanvasMode.wire;
    // 折叠过滤：每代默认只显示最高概率桶（外来样本始终可见）；
    // R15 聚焦激活时：只有「有选中元素的世代」折叠为选择集，其余
    // 世代（P、上下各代）按原折叠规则照常呈现；聚焦代不出折叠芯片。
    final allNodes = engine.nodes;
    final visible = _visibleNodes(allNodes);
    final visibleEdges = _canvasEdges(visible, engine);
    // 聚焦代不出折叠芯片（该代由用户选择集接管），其余代照常
    final focusGens = _focusGens(_trackSex
        ? allNodes.where((n) => !n.id.startsWith('SPLIT#')).toList()
        : allNodes);
    final hidden = _hiddenCounts(allNodes, skipGens: focusGens);
    final collapsed = hidden.keys.toSet().difference(_expandedKeys);
    // R24：XY 存证开启时选择模式按半边圈选——勾选雄/雌 → 聚焦折叠
    // 只保留并圈选该半边（组合桶内非专注半边淡化）；XY 关闭维持
    // 整桶绑定（solo 为空 Map，行为同旧版）。两侧都勾选 → 整桶。
    //
    // ⛔ wire 模式必须传空：solo 是第 4 条独立视觉通道（Painter 对非
    // solo 半边会压掉光晕），若从 _picked/_focusSet 派生，选择雄半边
    // 后进 wire 点雌半边会「armed 成功但没有紫光」，成功橙闪也被压掉。
    // 浏览 / select 的原 solo 语义不变。
    final soloHalf = <String, PedigreeNodeKind>{};
    if (_trackSex && !wireMode) {
      final pickedNow = _focusSet ?? _picked;
      for (final pid in pickedNow) {
        final (base, half) = parseTapId(pid);
        if (half == null) continue;
        if (soloHalf[base] == null) {
          soloHalf[base] = half;
        } else if (soloHalf[base] != half) {
          soloHalf.remove(base);
        }
      }
    }
    return PedigreeCanvasArea(
      fullscreen: fullscreen,
      showFloatingActions: showFloatingActions,
      boundaryKey: fullscreen ? _fsBoundaryKey : _canvasBoundaryKey,
      canvasStateKey: fullscreen ? _fsCanvasStateKey : _canvasStateKey,
      // v2.4 功能 2：画布存 PNG（仅内嵌实例可截——全屏 Dialog 不传）。
      onExportPng: fullscreen ? null : _exportCanvasPng,
      // v2.12.0+2 hotfix：全屏 Dialog 悬浮面板也提供「复制 SVG」
      // 入口（与 PNG 按钮并列），方便全屏讲解时老师直接复制板书。
      onExportSvg: _exportCanvasSvg,
      nodes: visible,
      edges: visibleEdges,
      selectedId: wireMode ? null : _selectedId,
      onNodeTap: _onNodeTap,
      onNodeHalfTap: _onNodeHalfTap,
      onBlankTap: _onBlankTap,
      onWireDetach: _onWireDetach,
      armedId: _armedId,
      flashIds: _flashIds,
      dimIds: _wireDimIds(),
      showLineage: _showLineage,
      edgeStyle: _edgeStyle,
      showBackcross: _showBackcross,
      hiddenBackcrossKeys: _hiddenBackcross,
      onBlankSecondaryTap: _onBlankSecondaryTap,
      // v2.19.10：触屏长按空白 → 同款快捷菜单（添加家族/样本/下一代）。
      onBlankLongPress: _onBlankSecondaryTap,
      onNodeSecondaryTap: _onNodeSecondaryTap,
      collapsedKeys: collapsed,
      hiddenCounts: hidden,
      onToggleGen: _toggleGenKey,
      sexLinked: _sexLinked,
      familyLabels: {
        for (final f in engine.familyIds) f: engine.familyLabel(f)
      },
      sexSplitView: _trackSex,
      // 绿勾只在选择模式出现：wire 里即使还留着选择草稿也不传画布。
      pickedIds: _mode == _CanvasMode.select ? _picked : const {},
      locked: _canvasLocked,
      familyOffsets: _familyOffsets,
      onToggleLock: _toggleCanvasLock,
      onFullscreenTap: fullscreen ? null : _openFullscreen,
      onFamilyDragDelta: _onFamilyDragDelta,
      onFamilyDragEnd: _onFamilyDragEnd,
      connectedIds: wireMode ? const {} : _connectedIds,
      soloHalfIds: soloHalf,
      // v3.7：默认手势提示只在画布还没有子代时出现——一旦算出基因型
      // 节点（maxGeneration ≥ 1），用户已经在看结果，这串新手说明收成
      // 空串（画布区整条不渲染）。连线/选择两支是操作态提示，始终保留。
      // 「删除整代」把前沿截回 0 后，提示会自动回来。
      hintText: _mode == _CanvasMode.wire
          ? '连线模式：点节点=待命，再点另一节点=完成连线 · 再点「连线」退出'
          : _mode == _CanvasMode.select
              ? '选择模式：点元素勾选/取消（组合桶左右半=雄/雌单独选）· 点「只看所选」应用聚焦 · 聚焦后点「显示全部」恢复'
              : engine.maxGeneration == 0
                  // v2.19.10：「右键」补触屏等价「长按空白」（老师走查 M6：
                  // 触屏无右键，添加样本路径隐身）。
                  // v2.19.16：补充右键收线与适应视图入口提示。
                  // v3.6：补「全部连线」——默认智能密线会收起未聚焦的自动边。
                  ? '拖动/滚轮=平移 · 双指/Ctrl+滚轮=缩放 · 点节点=查看信息 · 开「连线」后可配对 · 长按节点/右键菜单=收线 · 右键/长按空白=添加 · 缩放条⛶=适应视图'
                      '${_showAllEdges ? '' : ' · 「全部连线」可恢复全部自动连线'}'
                  : '',
      onAddFamily: _showAddFamilyDialog,
      onAddSample: () => _showAddSampleDialog(_engine!.maxGeneration),
      onDeleteGeneration: _showDeleteGenerationDialog,
    );
  }

  // ── R19 单元素删除：选中 → 信息面板底部「删除」，删后立即重算 ──
  Future<void> _onDeleteSelected() async {
    final engine = _engine;
    final selId = _selectedId;
    if (engine == null || selId == null) return;
    final (baseId, half) = parseTapId(selId);
    final baseNode = engine.nodesById[baseId];
    if (baseNode == null) return;

    // R21 折叠态集合体：该代处于「收起」（每代只显示代表桶）时，点
    // 代表桶 = 删除整个集合（该家族该代及以后的全部计算桶，外来样本
    // 保留）；展开态 = 只删点中的这一个基因型。展开方式：点开代的
    // 展开 chip 后再删。
    final collapsedKeysLocal = _currentCollapsedGens();
    final isCollapsedSet =
        baseNode.generation >= 1 &&
        !baseNode.isExternal &&
        collapsedKeysLocal
            .contains('${baseNode.familyId}:${baseNode.generation}');

    final String genLabelTxt =
        baseNode.generation == 0 ? 'P' : 'F${baseNode.generation}';
    final bool ok;
    final String logText;
    if (isCollapsedSet) {
      // R8 学生走查 #4：收起代表桶的详情条删除 = 无确认删整代集合
      // （含全部隐藏基因型）+ 全引擎重算——与底栏「删除整代」的
      // 确认弹窗双标，误点不可逆。补同款确认。
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text('删除 $genLabelTxt 整代集合？'),
          content: Text(
              '将删除 ${engine.familyLabel(baseNode.familyId)} 的 $genLabelTxt'
              ' 及以后全部计算桶（代表桶 ${baseNode.genotype}，含隐藏的全部'
              '基因型），并立即重算。外来样本保留。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('删除'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
      ok = engine.removeFamilyGeneration(baseNode.familyId, baseNode.generation);
      logText = '删除整代集合：${engine.familyLabel(baseNode.familyId)} '
          '$genLabelTxt（${baseNode.genotype} 代表桶，含隐藏的全部基因型）';
    } else {
      // 半边：已分裂则删半边；未分裂（组合桶内 glyph）删整桶
      var target = baseId;
      if (half != null) {
        target = engine.halfNode(baseId, half)?.id ?? baseId;
      }
      ok = engine.removeElement(target);
      logText = '删除元素：${baseNode.genotype}'
          '（$genLabelTxt · ${engine.familyLabel(baseNode.familyId)}）';
    }
    if (!ok) {
      _toast('该元素不可删除（初始双亲等）。');
      return;
    }
    // 绑定了计算：删除后立即执行计算，不留空
    engine.recomputeFrom(0);
    // 黑名单一次性：删除生效只拦截刚才这次重算；之后点「计算」可
    // 重新推导（R20：删除的 F1 必须能再次计算出来）
    engine.clearRemovedGenotypes();
    setState(_clearFocus);
    _pushLog(logText);
    _toast(isCollapsedSet
        ? '已删除 $genLabelTxt 整代集合（含隐藏基因型）并重算。'
        : '已删除该元素并重算。');
  }

  /// R21/R26：当前处于「收起」状态的 (家族,世代) key 集合。
  /// 与 _buildCanvasArea 的折叠计算同源。
  Set<String> _currentCollapsedGens() {
    final engine = _engine;
    if (engine == null) return const {};
    final allNodes = engine.nodes;
    final focusGens = _focusGens(_trackSex
        ? allNodes.where((n) => !n.id.startsWith('SPLIT#')).toList()
        : allNodes);
    final hidden = _hiddenCounts(allNodes, skipGens: focusGens);
    return hidden.keys.toSet().difference(_expandedKeys);
  }

  // ── R19 按家族删代：删除栏（家族 × 世代，支持全部家族/全部代数） ──
  /// 2.3 重构阶段 6：对话框 UI 已抽取至 widgets/pedigree_dialogs.dart
  /// （showPedigreeDeleteGenerationDialog），此处做删除循环/重算/
  /// 清黑名单/记日志接线，行为与抽取前一致。
  Future<void> _showDeleteGenerationDialog() async {
    final engine = _engine;
    if (engine == null) return;
    final res = await showPedigreeDeleteGenerationDialog(
        context: context, engine: engine);
    if (res == null || !mounted) return;
    final gens = res.genChoice == -1 ? 1 : res.genChoice;
    final fams =
        res.famChoice == -1 ? engine.familyIds.toList() : [res.famChoice];
    var cnt = 0;
    for (final f in fams) {
      if (engine.removeFamilyGeneration(f, gens)) cnt++;
    }
    if (cnt == 0) {
      _toast('没有可删除的内容。');
      return;
    }
    engine.recomputeFrom(0); // 前沿已回退：重算只到新前沿，不再生
    // 黑名单一次性：删除整代后用户可重新计算（R20）
    engine.clearRemovedGenotypes();
    setState(_clearFocus);
    final famLabel = res.famChoice == -1
        ? '全部家族'
        : '家族 ${engine.familyLabel(res.famChoice)}';
    final genLabel = res.genChoice == -1 ? '全部代数' : 'F${res.genChoice}';
    _pushLog('删除整代：$famLabel · $genLabel');
    _toast('已删除并重算。');
  }

  // ══ v3.8 9331 杂交计算面板 ═════════════════════════════════

  // ── 持久化（v2.12 R1 C P0 #7 修复：走 platform_storage 中性 API）────
  //
  // 原 `Platform.environment['USERPROFILE']` + `File(...)` 在 Web 端
  // 抛 UnimplementedError，catch 吞掉 → 面板展开状态不持久 → 刷新
  // 回到默认关。本次改用 platform_storage 中性 API + isWebStorage 分支：
  // Web 端走 localStorage（key = `cross_panel_json`），桌面 / 安卓
  // 走 `~/.biology_app/cross_panel.json`。同 FirstRunStore / AppState
  // / ThemeController / PresentModeController 范式。测试 hook
  // （debugFilePath / debugWebStorage / debugForceIsWebStorage / debugResetHooks）
  // 挂在公开 `GeneticPedigreePage` 类上，便于 test 跨 import 边界访问。

  /// localStorage key。Web 端 load / save 走 storageGet / storageSet。
  static const String _crossKey = 'cross_panel_json';

  /// 当前是否走 web 存储路径（test hook 优先于真实 isWebStorage）。
  static bool get _isWebStorage =>
      GeneticPedigreePage.debugForceIsWebStorage ?? isWebStorage;

  /// 桌面 / 安卓路径：`<userAppDir>/cross_panel.json`。
  /// 注入的 debugFilePath 优先（同 FirstRunStore / AppState 等）。
  /// Web 端走 storageGet / storageSet，不会调到此处。
  static String _crossFile() {
    if (GeneticPedigreePage.debugFilePath != null) {
      return GeneticPedigreePage.debugFilePath!;
    }
    final appDir = userAppDir();
    if (appDir == null) return 'cross_panel.json'; // Web 兜底占位
    final dir = Directory(appDir);
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return '${dir.path}/cross_panel.json';
  }

  /// flutter test 下自动跳过磁盘读写（防真机配置文件污染测试）。
  /// 同时也是 `_loadCrossPanel` / `_toggleCrossPanel` 内部真正的"启用
  /// 持久化"开关：production（包括 web）走持久化；flutter test 跳过。
  ///
  /// ⚠️ v2.19.4 判定修正：旧版用 `const bool.fromEnvironment('FLUTTER_TEST')`
  /// ——flutter test 运行器不注入该 dart-define，判定恒 false→本 getter
  /// 恒 true→测试里真读写用户盘 cross_panel.json（与 edge_style 同型
  /// 事故）。改为与 HistoryStore 对齐的 `Platform.environment` 判定；
  /// 注入 debugWebStorage 时放行（持久化 round-trip 测试走内存存储）。
  static bool get _crossPersist =>
      kIsWeb ||
      !(Platform.environment['FLUTTER_TEST'] == 'true') ||
      GeneticPedigreePage.debugWebStorage != null;

  /// 启动时读一次磁盘 / localStorage。fire-and-forget 异步，
  /// 加载完成若面板应开则 setState 打开。
  void _loadCrossPanel() {
    if (!_crossPersist) return;
    () async {
      try {
        String? raw;
        if (_isWebStorage) {
          raw = _storageGet(_crossKey);
        } else {
          final f = File(_crossFile());
          if (!f.existsSync()) return; // 首次启动：保持默认关
          raw = f.readAsStringSync();
        }
        if (raw == null || raw.isEmpty) return;
        final j = jsonDecode(raw);
        if (j is Map && j['open'] == true && mounted && !_crossOpen) {
          setState(() => _crossOpen = true);
        }
      } catch (_) {/* 持久化尽力而为 */}
    }();
  }

  void _toggleCrossPanel() {
    setState(() => _crossOpen = !_crossOpen);
    if (!_crossPersist) return;
    () async {
      final s = jsonEncode({'open': _crossOpen});
      try {
        if (_isWebStorage) {
          await _storageSet(_crossKey, s);
          return;
        }
        final f = File(_crossFile());
        f.parent.createSync(recursive: true);
        f.writeAsStringSync(s);
      } catch (_) {/* 持久化尽力而为 */}
    }();
  }

  /// Web 端 storage 读。test 用 debugWebStorage 注入；生产用 platform_storage。
  static String? _storageGet(String key) {
    if (GeneticPedigreePage.debugWebStorage != null) {
      return GeneticPedigreePage.debugWebStorage![key];
    }
    return storageGet(key);
  }

  /// Web 端 storage 写。test 用 debugWebStorage 注入；生产用 platform_storage。
  static Future<void> _storageSet(String key, String value) async {
    if (GeneticPedigreePage.debugWebStorage != null) {
      GeneticPedigreePage.debugWebStorage![key] = value;
      return;
    }
    await storageSet(key, value);
  }

  /// v2.19.4：曲线/正交连线样式持久化（此前每次进页重置回正交，
  /// 用户开了曲线退出去再进就丢失）。范式照抄 cross_panel（同文件
  /// 下方 _crossKey/_crossFile/_storageGet/_storageSet + FLUTTER_TEST
  /// 守卫），独立文件 `edge_style.json`。
  static const String _edgeStyleKey = 'pedigree_edge_style';
  static String _edgeStyleFile() {
    if (GeneticPedigreePage.debugFilePath != null) {
      return GeneticPedigreePage.debugFilePath!;
    }
    final appDir = userAppDir();
    if (appDir == null) return 'edge_style.json'; // Web 兜底占位
    return '$appDir/edge_style.json';
  }

  /// 曲线样式持久化守卫（⚠️ 勿用 `_crossPersist`——那是
  /// `const bool.fromEnvironment('FLUTTER_TEST')`，dart-define 未传入
  /// 时 flutter test 下恒 false→_crossPersist 恒 true，持久化会在测试里
  /// 真读写用户盘（本函数曾因此让 edge_style 测试互染全红）。与
  /// HistoryStore 对齐用 `Platform.environment['FLUTTER_TEST']`；
  /// 注入 debugWebStorage 时放行（round-trip 测试走内存存储验证）。
  static bool get _edgeTestGuard =>
      !kIsWeb &&
      Platform.environment['FLUTTER_TEST'] == 'true' &&
      GeneticPedigreePage.debugWebStorage == null;

  /// 启动时读一次。fire-and-forget；读到 'curve' 则 setState 切曲线。
  void _loadEdgeStyle() {
    if (!_edgeTestGuard) {
      () async {
        try {
          String? raw;
          if (_isWebStorage) {
            raw = _storageGet(_edgeStyleKey);
          } else {
            final f = File(_edgeStyleFile());
            if (!f.existsSync()) return; // 首次启动：保持默认正交
            raw = f.readAsStringSync();
          }
          if (raw == null || raw.isEmpty) return;
          final v = jsonDecode(raw);
          if (v is Map && v['style'] == 'curve' && mounted) {
            setState(() => _edgeStyle = PdEdgeStyle.curve);
          }
        } catch (e) {
          // v2.19.6 polish（性能 🟡#4）：原本 catch(_) 静默吞 → 损坏文件
          // 或 Web 端 Storage 异常时用户零提示，重启后以为是"丢设置"实际
          // 是文件坏了。debugPrint 暴露根因 + 轻 toast 让用户知道已重置。
          debugPrint('[biology] _loadEdgeStyle 失败：$e');
          if (mounted) _toast('上次边样式设置损坏，已重置为正交');
        }
      }();
    }
  }

  /// 两处开关（底栏 segmented / 侧栏芯片）共用：切样式 + 落盘。
  void _setEdgeStyle(PdEdgeStyle v) {
    setState(() => _edgeStyle = v);
    if (_edgeTestGuard) return;
    () async {
      final s = jsonEncode({'style': v == PdEdgeStyle.curve ? 'curve' : 'orthogonal'});
      try {
        if (_isWebStorage) {
          await _storageSet(_edgeStyleKey, s);
          return;
        }
        final f = File(_edgeStyleFile());
        f.parent.createSync(recursive: true);
        f.writeAsStringSync(s);
      } catch (e) {
        // v2.19.6 polish（性能 🟡#4）：写盘失败（磁盘满 / Web Storage 写满）
        // 不再静默吞——UI 状态已经切了，用户误以为持久化成功，重启会丢。
        debugPrint('[biology] _setEdgeStyle 写盘失败：$e');
        if (mounted) _toast('边样式未持久化（写盘失败）');
      }
    }();
  }

  /// 轮流填充核心：当前槽位填入基因型后切到另一槽。
  void _fillCrossSlot(String genotype) {
    setState(() {
      if (_crossNextSlot == 1) {
        _crossP1Ctrl.text = genotype;
        _crossNextSlot = 2;
      } else {
        _crossP2Ctrl.text = genotype;
        _crossNextSlot = 1;
      }
    });
  }

  /// 画布点选自动填充（仅面板打开时；群体桶/基因缺失等非纯字母
  /// 基因型静默跳过——那是分布不是单基因型）。
  void _autoFillFromTap(String tapId) {
    final engine = _engine;
    if (engine == null) return;
    final (baseId, half) = parseTapId(tapId);
    var node = engine.nodesById[baseId];
    if (node == null) return;
    if (half != null) {
      final h = engine.halfNode(node.id, half);
      if (h != null) node = h;
    }
    final g = node.genotype.trim();
    if (g.isEmpty || !RegExp(r'^[A-Za-z]+$').hasMatch(g)) return;
    // R8 学生走查 #3：静默轮流覆盖亲本框，手输基因型被悄悄顶掉——
    // 补「已填入 + 目标槽位」toast（与「导入 9331」同款反馈）。
    final slot = _crossNextSlot;
    _fillCrossSlot(g);
    _toast('已填入亲本 $slot（点节点即填，「控制面板」可改）');
  }

  /// 信息面板「导入 9331」入口：填入选中元素基因型，面板未开则自动打开。
  void _importToCross(String genotype) {
    final g = genotype.trim();
    if (g.isEmpty || !RegExp(r'^[A-Za-z]+$').hasMatch(g)) {
      _toast('该元素基因型含缺失/群体混合标记，无法导入杂交计算');
      return;
    }
    if (!_crossOpen) _toggleCrossPanel();
    final slot = _crossNextSlot;
    _fillCrossSlot(g);
    _toast('已填入亲本 $slot');
  }

  /// 「开始计算」——懒计算唯一入口。
  void _startCross() {
    final a = _crossP1Ctrl.text.trim();
    final b = _crossP2Ctrl.text.trim();
    setState(() {
      _crossResult = _crossKaoji.crossAuto(p1: a, p2: b);
      _crossSnapshot = '$a × $b';
    });
    final r = _crossResult;
    if (r != null && r.result != null) {
      AppState.instance.report('杂交面板双亲', _crossSnapshot);
      AppState.instance.report('面板表型比例', r.result!.phenotypeRatio.toString());
    }
  }

  /// 2.3 重构：杂交面板已抽取为独立组件 PedigreeCrossPanel
  /// （widgets/pedigree_cross_panel.dart），此处只做状态/回调接线。
  /// v2.19.15 A 桥正向：onOpenInCalculator 把当前 p1/p2 经
  /// ModuleFillBus 送到 9331 页双基因 tab（完整棋盘/步骤/方法对比），
  /// 回程横幅（C 统一外壳）保证一键跳回系谱。
  Widget _buildCrossPanel({required bool overlay}) {
    return PedigreeCrossPanel(
      overlay: overlay,
      p1Ctrl: _crossP1Ctrl,
      p2Ctrl: _crossP2Ctrl,
      nextSlot: _crossNextSlot,
      result: _crossResult,
      snapshot: _crossSnapshot,
      onClose: _toggleCrossPanel,
      onStart: _startCross,
      onOpenInCalculator: _crossResult?.result == null
          ? null
          : () => ModuleFillBus.fill('cross_dihybrid', {
                'p1': _crossP1Ctrl.text.trim(),
                'p2': _crossP2Ctrl.text.trim(),
              }),
    );
  }

  /// 底部信息面板：显示当前选中节点的完整信息
  /// （基因型 / 概率 / 性别 / 世代 / 雌雄比 / 伴性标注 / 连线数）。
  /// 2.3 重构：详情面板已抽取为独立组件 PedigreeDetailStrip
  /// （widgets/pedigree_detail_strip.dart），此处只做状态/回调接线。
  Widget _buildDetailStrip() {
    return PedigreeDetailStrip(
      engine: _engine!,
      selectedId: _selectedId,
      expandedNodes: _expandedGenNodes(_engine!),
      connectedLabels: _connectedLabels,
      editableGenotype: _editableGenotype,
      onEditGenotype: (n) => _editGenotype(n),
      onImportToCross: _importToCross,
      onWireDetach: _onWireDetach,
      onDeleteSelected: _onDeleteSelected,
    );
  }

  /// v3.1 左侧控制面板（VS Code 双栏式）：亲本 / 模式 / 语义 / 画布
  /// 四分区。overlay=true 为窄屏覆盖式（浮于画布左缘、带投影），
  /// false 为宽屏占位式。所有控件文案与交互与旧顶部控制区一致
  /// （'计算'/'连线'/'同性交配' 等 label 不动——测试依赖）。
  /// 2.3 重构阶段 5：已抽取为 PedigreeSidePanel
  /// （widgets/pedigree_side_panel.dart），此处只做状态/回调接线。
  /// P0-3：把「计算」的报错挂在左栏最近输入区的位置。
  ///
  /// 左栏组件不接收 error 参数，页面只能在它上方挂一条；左栏收起
  /// （窄屏 ☰ 折叠）时由画布顶部那条兜底。
  Widget _withParentError(Widget panel) {
    final err = _error;
    if (err == null) return panel;
    return Column(
      children: [
        Container(
          width: 280,
          padding: const EdgeInsets.fromLTRB(16, 8, 12, 0),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.error_outline, size: 15, color: AppColors.lethal),
              const SizedBox(width: 6),
              Expanded(
                child: Text(err,
                    style: AppText.caption.copyWith(color: AppColors.lethal)),
              ),
            ],
          ),
        ),
        Expanded(child: panel),
      ],
    );
  }

  Widget _buildSidePanel({required bool overlay}) {
    return PedigreeSidePanel(
      overlay: overlay,
      p1Ctrl: _p1Ctrl,
      p2Ctrl: _p2Ctrl,
      computed: _computed,
      engineAlive: _engine != null,
      onShowPreset: _showPresetDialog,
      wireModeOn: _mode == _CanvasMode.wire,
      onToggleWireMode: _toggleWireMode,
      selecting: _mode == _CanvasMode.select,
      focusing: _focusSet != null,
      pickedCount: _picked.length,
      onEnterSelect: _onEnterSelect,
      onApplyFocus: _onApplyFocus,
      onShowAll: _onShowAll,
      allEdgesOn: _showAllEdges,
      onToggleAllEdges: _toggleAllEdges,
      // v2.16：<860 宽时面板承载画布动作；>=860 在命令栏左侧组。
      onFullscreen: _openFullscreen,
      onAddFamily: _showAddFamilyDialog,
      onAddSample: () => _showAddSampleDialog(_engine!.maxGeneration),
      onDerive: _derive,
      onShowFreq: _showFreqDialog,
      onShowLethal: _showLethalDialog,
      allowSameSex: _allowSameSex,
      onToggleSameSex: _toggleSameSex,
      trackSex: _trackSex,
      onToggleTrackSex: _toggleTrackSex,
      showLineage: _showLineage,
      onToggleLineage: (v) => setState(() => _showLineage = v),
      // v2.19 曲线连线开关。
      curveLinesOn: _edgeStyle == PdEdgeStyle.curve,
      onToggleCurveLines: (v) => _setEdgeStyle(
          v ? PdEdgeStyle.curve : PdEdgeStyle.orthogonal),
      showBackcross: _showBackcross,
      onToggleBackcross: (v) => setState(() => _showBackcross = v),
      backcrossEdges:
          _engine == null ? const <PedigreeEdge>[] : _backcrossEdges(_engine!),
      hiddenBackcrossKeys: _hiddenBackcross,
      onToggleBackcrossEdge: (key) => setState(() {
        if (!_hiddenBackcross.remove(key)) _hiddenBackcross.add(key);
      }),
      sexLinkedOn: _sexLinked != null,
      onShowSexLinked: () => _showSexLinkedDialog(),
      allowMissingGene: _allowMissingGene,
      onToggleMissingGene: _toggleMissingGene,
      linkageOn: _linkageOn,
      onToggleLinkage: _toggleLinkage,
      allowPolyploid: _allowPolyploid,
      // R8 学生走查 #11：多倍体开关静默置位（仅下次计算生效），
      // 与同性交配/XY 的即时反馈不一致——补生效时机提示。
      onTogglePolyploid: (v) {
        setState(() => _allowPolyploid = v);
        _toast(v ? '已开启多倍体，下次「计算」起生效' : '已关闭多倍体');
      },
      linkageSection: _buildLinkageSection(),
      // v2.16 UI 重做：模式区迁命令栏（宽屏）；窄屏仍在面板（下方
      // overlay && computed 条件渲染）。
    );
  }
}

// ===========================================================================
// v2.12 Round 1 P0 #4：板书复制 sheet 辅助类
// ===========================================================================

/// 底部 sheet 选择：SVG 文本 / PNG 图片。
enum _SvgCopyChoice { svg, png, saveAsBoard }

/// 底部 sheet：3 个选项（SVG 文本 / PNG 文件 / 存为板书），点击返回
/// _SvgCopyChoice。
class _SvgCopySheet extends StatelessWidget {
  _SvgCopySheet();

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
            child: Text(
              '选择复制格式',
              style: AppText.sectionTitle,
            ),
          ),
          ListTile(
            leading: const Icon(Icons.code_outlined),
            title: const Text('复制为 SVG 文本'),
            subtitle: const Text('XML 字符串，可粘到富文本编辑器或保存为 .svg'),
            onTap: () => Navigator.of(context).pop(_SvgCopyChoice.svg),
          ),
          ListTile(
            leading: const Icon(Icons.image_outlined),
            title: const Text('保存为 PNG 文件'),
            subtitle: const Text(
                '落盘到下载目录 / 浏览器自动下载，可直接发到微信群 / 课件'),
            onTap: () => Navigator.of(context).pop(_SvgCopyChoice.png),
          ),
          // v2.12+ R2 P0-A1：第 3 选项「存为板书」——真写盘到
          // ~/.biology_app/board_history/（dashboard 老师工具卡
          // 板书历史列表会列出）。R1 85a870e 承诺的「存为板书」
          // 实为格式选择器，本提交兑现真写盘。
          ListTile(
            leading: const Icon(Icons.save_alt_outlined),
            title: const Text('存为板书'),
            subtitle: Text(kIsWeb
                ? '下载 pedigree_<时间戳>.svg 到浏览器下载目录'
                : '写入 ~/.biology_app/board_history/，「老师工具」卡可看历史'),
            onTap: () => Navigator.of(context).pop(_SvgCopyChoice.saveAsBoard),
          ),
          // v2.13 R6-P1：sheet 底部加「图片 / SVG 原样保存，不脱敏」总提示
          // ——P1 隐私根因中「照片/截图/板书 SVG 不脱敏」一项在画布
          // 导出 sheet 的最小缓解。AES-GCM 对像素 / SVG 文本加密属重
          // 工程，推 R7 路线图；本轮先在 sheet 强提示导出前自审。
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: Row(
              children: [
                Icon(Icons.info_outline,
                    size: 14, color: AppColors.sand),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    '图片 / SVG 原样保存，不做脱敏；导出前请确认不含敏感信息（人名 / 学号 / 班级等）',
                    style: AppText.caption.copyWith(color: AppColors.sand),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}
