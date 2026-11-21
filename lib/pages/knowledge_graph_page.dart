// knowledge_graph_page.dart —— 知识图谱页
//
// CustomPainter 画「网状」节点连线图：方块节点 + 先修/关联连线，
// 支持搜索高亮、点击节点查看详情（先修/后继链路）。
// 右上角「考点速查」抽屉：从 data/kaodian_compilation.json 加载考点，
// 图谱给结构，考点给应试口径。
// 视觉遵循 lib/theme.dart（docs/ARCHITECTURE.md 的设计约定）：teal 强调、无蓝绿混用、等宽比例。
//
// v2.21.0（焦点连线 + 模块链接）：
//   · 节点 → 功能页的映射搬到 lib/ui/module_link.dart（稳定 destinationId
//     + 展示 label，索引由 appNavigation 顺序派生），本页只留「按 id 取链接」。
//   · 画布新增独立选中态 _selectedNodeId：首次点节点＝选中并开原详情，
//     再点同一节点＝只收镜头不重复弹 sheet，点空白＝清除。选中时只做
//     **视觉降权**（一跳全强度 / 相关边提亮最后画 / 其余压暗但仍画），
//     布局、正交避障车道、箭头落点、缩放与弱点提示一律不动，不换力导向。
//   · 容器复用 lib/ui/module_surface.dart：搜索工具条 + 画布薄壳，
//     保持有界尺寸（不加 maxWidth、不加滚动、不设常驻右栏）。

import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../engine/kaodian_loader.dart';
import '../engine/knowledge_graph.dart';
import '../guide/guide_keys.dart';
import '../state/app_state.dart';
// v2.19.63：读错题本（只读）驱动「薄弱点着色 + 先修补课」。
import '../state/mistake_book.dart';
import '../state/present_mode_controller.dart';
import '../ui/ai_chat_controller.dart';
import '../ui/assistant_panel.dart';
import '../ui/canvas_input.dart';
import '../ui/module_fill.dart';
// 图谱节点 → 页面与可选页内页签的只读导览链接。
import '../ui/module_link.dart';
// v2.21.0：模块化工作台薄壳（标题 / 细边框 / 圆角排版）。
import '../ui/module_surface.dart';
import '../ui/step_card.dart';
import '../theme.dart';

class KnowledgeGraphPage extends StatefulWidget {
  const KnowledgeGraphPage({
    super.key,
    this.navCollapsed = false,
    this.onNavPressed,
    this.onOpenTool,
  });

  /// v3.3 侧栏折叠联动（HomeShell 注入）；独立构造时不渲染 ☰。
  final bool navCollapsed;
  final VoidCallback? onNavPressed;

  /// v2.2 双向跳转：节点详情「打开对应功能」经 HomeShell 回调切导航索引
  /// （页面内跳转，与课标 chip 共用同一套机制）。null 时按钮不显示。
  final void Function(int navIndex)? onOpenTool;

  @override
  State<KnowledgeGraphPage> createState() => _KnowledgeGraphPageState();
}

class _KnowledgeGraphPageState extends State<KnowledgeGraphPage> {
  final _graph = defaultKnowledgeGraph;
  String _query = '';

  // 计算布局（缓存在 build 时按节点顺序分配坐标，世界坐标系）
  Map<String, Offset>? _positions;

  /// v2.19.63：「先修补课」跳转后的高亮节点 id（null = 无）。
  /// 与搜索高亮叠加；点任意节点详情/搜索时清空。
  String? _focusedNodeId;

  /// 画布视口控制：滚动平移、Ctrl/Meta+滚轮缩放、原生拖动/捏合、初始适配。
  final TransformationController _viewCtrl = TransformationController();
  Size _worldSize = Size.zero;
  Size _fittedFor = Size.zero; // 已做初始适配的（世界+视口）组合键

  /// v2.6 ☰ 工具抽屉：Scaffold key + 画布视口尺寸缓存（抽屉节点定位用）。
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  Size _viewportSize = Size.zero;

  static const _nodeW = 150.0;
  static const _nodeH = 56.0;
  static const _gapX = 40.0;
  static const _rowH = 120.0;
  static const _pad = 60.0;
  static const _minScale = 0.2;
  static const _maxScale = 3.0;

  /// v2.22.0 阅读优先：默认初始视图的**最低适配尺度**。
  ///
  /// 19 节点分层后世界约 2170×960，桌面 1400×900 视口里全图适配只有
  /// ≈0.62 ⇒ 12px 节点标题压到 7.5px（v221_graph_focus.png 的实测观感：
  /// 「蚂蚁字」）。阅读视图因此**不再以「装下全世界」为目标**：适配尺度
  /// 取 `max(全图适配, 本常量)` = 0.8 ⇒ 节点标题 9.6px、卡片描边/连线
  /// 也回到可辨尺寸；代价是横向外围不进画面，用拖动看（InteractiveViewer
  /// boundaryMargin 400 一直是开着的）。
  ///
  /// 三种语义互不混淆：
  ///   · 阅读（默认，本常量）——为「读节点」服务；
  ///   · 全图（用户显式点「全图」/ 课堂缩放条「适配全图」）——真装下全部
  ///     节点，允许压回 [_minScale]；
  ///   · 手势缩放——用户自己拖着看，两者都不再插手（适配缓存键不变）。
  static const _readingMinScale = 0.8;

  // ── 右下角 shell 浮层的竖向占位（课堂模式）─────────────────────
  // 与 main.dart 的 FAB 列 / 课堂快捷条同源（那边的注释与本组常量是
  // 同一份事实，改一侧必须同步）：
  //   · Scaffold endFloat 底距 16 + 拍题 FAB 40 + 间距 10 + 问 AI FAB 56
  //     ⇒ FAB 列顶在页面底边上方 122；
  //   · 课堂快捷条贴列上沿留 12 ⇒ 条底 134，展开高 54（48 触控面 +
  //     上下 padding 2×2 + 描边 2）⇒ 条顶 188。
  // 缩放条同时要躲开**这两层**（原来是 bottom:16，正压在拍题 FAB 上），
  // 故其底缘必须 ≥ 188 + 12 = 200。
  static const _shellFabColumnTop = 16.0 + 40.0 + 10.0 + 56.0; // 122
  static const _shellQuickBarBottom = _shellFabColumnTop + 12.0; // 134
  static const _shellQuickBarHeight = 54.0;
  static const _shellClearance =
      _shellQuickBarBottom + _shellQuickBarHeight + 12.0; // 200

  /// 图例行高（1 行 ≈ 18 文本 + 上下 4/12 内边距）。本 Stack 的下边界在
  /// 图例之上，所以「相对页面底边的 200」要扣掉这一行才是 Stack 内的 bottom。
  static const _legendRowHeight = 34.0;

  /// 缩放条的 Stack 内 bottom（= 200 − 图例 34）。1 行图例时净空正好 200；
  /// 图例换行到 2 行只会让缩放条更高一点，永不反向压回 FAB 列。
  static const _zoomBarBottom = _shellClearance - _legendRowHeight; // 166

  /// v2.21.0：画布选中节点（**独立于** [_focusedNodeId]）。
  ///
  /// 语义：首次点节点 ⇒ 选中并开原详情；再点当前节点 ⇒ 只取消选中、
  /// 不重复弹 sheet；点空白 ⇒ 清除。与「先修补课」的 [_focusedNodeId]
  /// 互不复用：后者是搜索期的高亮叠加，前者是画布镜头。
  String? _selectedNodeId;

  /// v2.22.0 视图语义：false = 阅读优先（默认，见 [_readingMinScale]）；
  /// true = 显式「全图总览」（用户点了图例「全图」或课堂缩放条「适配全图」）。
  /// 只有这两条入口会把它置 true；手势缩放不改它（缩放不重算适配）。
  bool _overview = false;

  /// 测试钩子：当前画布变换矩阵（抽屉节点定位验收用）。
  Matrix4 get debugViewTransform => _viewCtrl.value;

  /// v2.22.0 测试钩子：当前生效缩放尺度（阅读视图 / 全图语义断言用）。
  double get debugViewScale => _viewCtrl.value.getMaxScaleOnAxis();

  /// v2.22.0 测试钩子：是否处于「显式全图总览」语义（false = 阅读优先）。
  bool get debugOverviewMode => _overview;

  /// v2.22.0 测试钩子：世界坐标尺寸（阅读尺度换算用）。
  Size get debugWorldSize => _worldSize;

  /// v2.22.0 测试钩子：与图例「全图」/ 缩放条「适配全图」同源的显式全图。
  void debugFitOverview() => _fitOverview(_viewportSize);

  /// v2.19.63 测试钩子：当前节点挂题数（错题本 subjectArea → 节点）。
  Map<String, int> get debugWeaknessCounts => _weaknessCounts;

  /// v2.19.63 测试钩子：「先修补课」跳转后高亮的先修节点 id（null = 无）。
  String? get debugFocusedNodeId => _focusedNodeId;

  /// v2.21.0 测试钩子：画布选中节点 id（null = 未选中）。
  String? get debugSelectedNodeId => _selectedNodeId;

  /// v2.19.63：节点挂题数（错题本**只读**驱动；不 load、不写）。
  /// 错题本为空（未加载 / 测试环境）时全 0 ⇒ 描边走基线分支，像素零变化。
  Map<String, int> get _weaknessCounts => graphWeaknessCounts(
    MistakeBook.instance.entries.map((e) => e.subjectArea),
  );

  /// 测试钩子：按节点 id 弹出详情 sheet（画布坐标点击在测试中太脆）。
  ///
  /// v2.21.0：与真实点击同源——经 [_showDetail] 顺带同步画布选中
  /// （[debugSelectedNodeId]），不另开一条只弹 sheet 的旁路。
  void debugShowDetail(String nodeId) {
    final node = _graph.nodeById(nodeId);
    if (node != null) _showDetail(node);
  }

  @override
  void initState() {
    super.initState();
    // v2.19.63：错题本变化 → 重算挂题着色（只读订阅，不改错题本）。
    MistakeBook.instance.addListener(_onMistakeBookChanged);
  }

  void _onMistakeBookChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    MistakeBook.instance.removeListener(_onMistakeBookChanged);
    _viewCtrl.dispose();
    super.dispose();
  }

  List<KnowledgeNode> get _filtered {
    if (_query.isEmpty) return _graph.nodes;
    final q = _query.toLowerCase();
    return _graph.nodes.where((n) {
      return n.title.toLowerCase().contains(q) ||
          n.description.toLowerCase().contains(q) ||
          n.tags.any((t) => t.toLowerCase().contains(q));
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    // v2.19.63：挂题数（错题本空 ⇒ 全 0 ⇒ 描走基线，像素零变化）。
    final weakness = _weaknessCounts;
    // v2.21.0：工具条要显示「当前过滤 / 总数」，与画布共用同一份过滤结果。
    final shown = _filtered;
    return Scaffold(
      key: _scaffoldKey,
      // v2.6 ☰ 工具抽屉：仅 HomeShell 注入 onNavPressed 时挂载（独立
      // 构造/测试照旧无 ☰ 无抽屉）。抽屉默认关闭，页面布局零像素变化。
      drawer: widget.onNavPressed == null
          ? null
          : Drawer(
              width: 320,
              backgroundColor: AppColors.surface,
              child: SafeArea(
                child: _GraphToolsDrawer(
                  nodes: _graph.nodes,
                  onJumpToNode: _jumpToNode,
                  onOpenKaodian: _showKaodianSheet,
                ),
              ),
            ),
      appBar: AppBar(
        // ☰ 死按钮修复：有 HomeShell 注入时 ☰ 改为打开本页工具抽屉
        // （原回调翻动的全局状态对本页无效）；无注入照旧不渲染。
        leading: appNavButton(
          widget.onNavPressed != null
              ? () => _scaffoldKey.currentState?.openDrawer()
              : null,
        ),
        title: const Text('知识图谱'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: OutlinedButton.icon(
              onPressed: _showKaodianSheet,
              icon: const Icon(Icons.toc_outlined, size: 16),
              label: const Text('考点速查'),
            ),
          ),
          TextButton.icon(
            onPressed: () {
              AiChatController.instance.queueSend(
                '【知识图谱】当前搜索：${_query.isEmpty ? '（全部节点）' : _query}。'
                '考点速查抽屉已加载资料库考点，请就遗传知识网的关联'
                '关系与考点展开讲解。',
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
        ],
      ),
      body: Column(
        children: [
          // v2.21.0 容器统一：搜索工具条走 ModuleSurface（标题「知识关系
          // 视图」+ hub 图标 + 当前过滤/总数），仍是文档流里的有界块——
          // 不加滚动、不加 maxWidth，桌面/手机同一份排版。
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: ModuleSurface(
              title: '知识关系视图',
              icon: Icons.hub_outlined,
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
              trailing: AppChip(
                '${shown.length} / ${_graph.nodeCount} 个节点',
                icon: Icons.filter_alt_outlined,
              ),
              child: TextField(
                onChanged: (v) => setState(() => _query = v),
                decoration: InputDecoration(
                  hintText: '搜索知识点（如 分离、9331、伴性、测交）',
                  hintStyle: AppText.caption,
                  prefixIcon: Icon(
                    Icons.search,
                    size: 20,
                    color: AppColors.steel,
                  ),
                  suffixIcon: _query.isEmpty
                      ? null
                      : IconButton(
                          icon: Icon(
                            Icons.clear,
                            size: 18,
                            color: AppColors.steel,
                          ),
                          onPressed: () => setState(() => _query = ''),
                        ),
                ),
              ),
            ),
          ),
          Expanded(
            child: LayoutBuilder(
              builder: (ctx, constraints) {
                final shownNodes = shown;
                if (shownNodes.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.hub_outlined,
                          size: 40,
                          color: AppColors.steel,
                        ),
                        const SizedBox(height: 12),
                        Text('未找到匹配的知识点', style: AppText.sectionTitle),
                        const SizedBox(height: 6),
                        Text('换个关键词试试，如「分离」「变式」', style: AppText.caption),
                      ],
                    ),
                  );
                }
                // 世界坐标布局：画布大小由内容决定，超宽层不再溢出屏幕
                _positions = _computeLayeredLayout(shownNodes);
                _worldSize = _computeWorldSize(shownNodes);
                _viewportSize = Size(
                  constraints.maxWidth,
                  constraints.maxHeight,
                );
                _fitToView(_viewportSize);
                // v2.19.63：搜索高亮 + 「先修补课」跳转高亮（并集）。
                final highlighted = <String>{
                  if (_query.isNotEmpty) ...shownNodes.map((n) => n.id),
                  ?_focusedNodeId,
                };
                // v2.21.0：画布薄壳（ModuleSurface 只给边框/圆角，padding 0）
                // ——包围盒仍是 LayoutBuilder 的实测尺寸，InteractiveViewer、
                // 世界坐标定位、弱点 tooltip 视口换算全部沿用原坐标系。
                Widget canvas = ModuleSurface(
                  padding: EdgeInsets.zero,
                  child: Listener(
                    key: GuideKeys.graphCanvas, // 新手引导高亮目标
                    onPointerSignal: _onPointerSignal,
                    child: InteractiveViewer(
                      transformationController: _viewCtrl,
                      constrained: false,
                      boundaryMargin: const EdgeInsets.all(400),
                      minScale: _minScale,
                      maxScale: _maxScale,
                      // InteractiveViewer 自带「鼠标滚动=缩放」会与页面统一
                      // 输入约定竞争。infinity 让其滚动缩放恒为 1（不改双指
                      // 捏合），滚轮统一由外层 Listener 做平移/Ctrl 缩放。
                      scaleFactor: double.infinity,
                      child: GestureDetector(
                        onTapUp: (details) {
                          // 已在变换后的坐标系内，直接命中测试
                          _handleTap(details.localPosition, shownNodes);
                        },
                        child: CustomPaint(
                          painter: KnowledgeGraphPainter(
                            graph: _graph,
                            nodes: shownNodes,
                            positions: _positions!,
                            highlighted: highlighted,
                            // v2.19.63：挂题数（空 = {} 时按 0 处理，走基线）
                            weaknessCounts: weakness,
                            // v2.21.0：画布选中节点（只决定强弱，不改布局）
                            focusedNodeId: _selectedNodeId,
                          ),
                          size: _worldSize,
                        ),
                      ),
                    ),
                  ),
                );
                // v2.19.63：≥3 题的节点挂「这里错得多」tooltip（数据引擎驱动；
                // 空错题本 ⇒ 零节点 ⇒ 不加 Stack ⇒ 像素零变化）。
                canvas = _withWeaknessTips(canvas, shownNodes, weakness);
                // v2.3.4 白板触控缩放条：大屏白板没有滚轮，拖平移费胳膊
                // ——课堂模式右下角常驻「放大/缩小/适配全图」三个大按钮
                //（56px 触控目标，教鞭/胳膊可点）。
                final viewport = Size(
                  constraints.maxWidth,
                  constraints.maxHeight,
                );
                return ListenableBuilder(
                  listenable: PresentModeController.instance,
                  builder: (ctx2, _) {
                    if (!PresentModeController.instance.enabled) {
                      return canvas;
                    }
                    return Stack(
                      children: [
                        canvas,
                        Positioned(
                          // v2.22.0：给右下「拍题 + 问 AI」FAB 列与课堂快捷条
                          // 让位（原 bottom:16 直接压在拍题 FAB 上）。
                          right: 16,
                          bottom: _zoomBarBottom,
                          child: _GraphZoomBar(
                            onZoomIn: () => _zoomBy(1.25, viewport),
                            onZoomOut: () => _zoomBy(1 / 1.25, viewport),
                            onFit: () => _fitOverview(viewport),
                          ),
                        ),
                      ],
                    );
                  },
                );
              },
            ),
          ),
          // 图例
          // v2.19.26 手机 9:16 实修（176px 右溢出）：3 圆点 + 两段说明
          // 文字在 390 宽放不下——改 Wrap 自动换行（Spacer 在 Wrap 内
          // 非法，宽屏单行自然排、窄屏两行承接）。
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
            child: Wrap(
              spacing: 16,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                _legendDot(AppColors.graphite, '先修链'),
                _legendDot(AppColors.teal, '关联'),
                _legendDot(AppColors.sand, '基础概念'),
                Text(
                  '拖动/滚轮平移 · 双指或 Ctrl+滚轮缩放',
                  style: AppText.caption.copyWith(color: AppColors.steel),
                ),
                // v2.21.0：选中态的可发现性（再点同一节点收回关联）。
                Text(
                  '点节点看关联 · 再点收回',
                  style: AppText.caption.copyWith(color: AppColors.steel),
                ),
                Text(
                  '${_graph.nodeCount} 个知识点 · ${_graph.edgeCount} 条关系',
                  style: AppText.caption,
                ),
                // v2.22.0：默认是「阅读优先」视图（不再自动装下全世界），
                // 所以**必须给一个显式全图入口**——否则学生模式（无课堂
                // 缩放条）只剩捏合缩放，看不到全局结构。与缩放条第三个键
                // 共用 _fitOverview，两个语义各自可达。
                TextButton.icon(
                  onPressed: () => _fitOverview(_viewportSize),
                  icon: const Icon(Icons.fit_screen, size: 16),
                  label: const Text('全图'),
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.teal,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    minimumSize: const Size(0, 28),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _legendDot(Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        const SizedBox(width: 5),
        Text(label, style: AppText.caption),
      ],
    );
  }

  /// 分层布局（世界坐标）：按先修依赖拓扑分层，每层内节点横向排开并居中。
  /// 画布宽度由最宽层决定，不会再溢出可视范围。
  /// v2.3.3：层内按先修父节点 x 重心排序（Sugiyama 一趟重心法），
  /// 显著减少跨层连线交叉（AI 评审二轮：连线穿透/蜘蛛网）。
  Map<String, Offset> _computeLayeredLayout(List<KnowledgeNode> nodes) {
    final groups = _layersOf(nodes);
    final worldW = _worldWidth(groups);
    final positions = <String, Offset>{};
    final nodeSet = nodes.map((n) => n.id).toSet();
    // 先修父节点索引（depth 保证父层 < 子层，升层处理时父节点必已就位）
    final parentsOf = <String, List<String>>{};
    for (final e in _graph.edges) {
      if (e.kind == 'prerequisite' &&
          nodeSet.contains(e.from) &&
          nodeSet.contains(e.to)) {
        parentsOf.putIfAbsent(e.to, () => []).add(e.from);
      }
    }
    final layers = groups.keys.toList()..sort();
    for (final layer in layers) {
      final list = List<KnowledgeNode>.of(groups[layer]!);
      if (layer != layers.first) {
        final index = {for (var i = 0; i < list.length; i++) list[i].id: i};
        double bary(KnowledgeNode n) {
          final xs = (parentsOf[n.id] ?? const <String>[])
              .map((p) => positions[p])
              .whereType<Offset>()
              .toList();
          if (xs.isEmpty) return double.nan; // 父被搜索过滤：保持原相对序
          return xs.map((o) => o.dx).reduce((a, b) => a + b) / xs.length;
        }

        list.sort((a, b) {
          final ba = bary(a), bb = bary(b);
          if (ba.isNaN || bb.isNaN) return index[a.id]! - index[b.id]!;
          final c = ba.compareTo(bb);
          return c != 0 ? c : index[a.id]! - index[b.id]!;
        });
      }
      final rowWidth = list.length * (_nodeW + _gapX) - _gapX;
      var x = (worldW - rowWidth) / 2;
      final y = _pad + layer * _rowH;
      for (final n in list) {
        positions[n.id] = Offset(x, y);
        x += _nodeW + _gapX;
      }
    }
    return positions;
  }

  Map<int, List<KnowledgeNode>> _layersOf(List<KnowledgeNode> nodes) {
    final layerOf = <String, int>{};
    final nodeSet = nodes.map((n) => n.id).toSet();

    // 计算每个节点的层级（longest path 到最前驱）
    int depth(String id) {
      if (layerOf.containsKey(id)) return layerOf[id]!;
      var d = 0;
      for (final e in _graph.edges) {
        if (e.to == id &&
            nodeSet.contains(e.from) &&
            e.kind == 'prerequisite') {
          d = math.max(d, depth(e.from) + 1);
        }
      }
      layerOf[id] = d;
      return d;
    }

    for (final n in nodes) {
      depth(n.id);
    }

    final groups = <int, List<KnowledgeNode>>{};
    for (final n in nodes) {
      groups.putIfAbsent(layerOf[n.id]!, () => []).add(n);
    }
    return groups;
  }

  double _worldWidth(Map<int, List<KnowledgeNode>> groups) {
    var widest = 0.0;
    groups.forEach((_, list) {
      final w = list.length * (_nodeW + _gapX) - _gapX;
      if (w > widest) widest = w;
    });
    return widest + _pad * 2;
  }

  Size _computeWorldSize(List<KnowledgeNode> nodes) {
    final groups = _layersOf(nodes);
    final layerCount = groups.isEmpty ? 1 : groups.keys.reduce(math.max) + 1;
    return Size(_worldWidth(groups), _pad * 2 + layerCount * _rowH);
  }

  /// 初始适配：世界或视口尺寸变化时，缩放并居中。
  ///
  /// v2.22.0：适配尺度分两种语义（见 [_readingMinScale]）——
  ///   · 阅读优先（默认）：`max(全图适配, _readingMinScale)`，宁可裁掉外围；
  ///   · 全图总览（[_overview]）：原样全图适配，允许压到 [_minScale]。
  /// 居中基准不变（仍按世界中心），只有尺度被抬高时世界左右/上下会超出
  /// 视口，由 InteractiveViewer 的拖动承接。
  void _fitToView(Size viewport) {
    final key = Size(
      _worldSize.width + viewport.width,
      _worldSize.height + viewport.height,
    );
    if (key == _fittedFor || _worldSize == Size.zero) return;
    _fittedFor = key;
    final fitted = math.min(
      viewport.width / _worldSize.width,
      viewport.height / _worldSize.height,
    );
    final scale =
        (_overview ? fitted : math.max(fitted, _readingMinScale)).clamp(
      _minScale,
      1.0,
    );
    final dx = (viewport.width - _worldSize.width * scale) / 2;
    final dy = (viewport.height - _worldSize.height * scale) / 2;
    _viewCtrl.value = Matrix4.identity()
      ..translateByDouble(dx, dy, 0, 1)
      ..scaleByDouble(scale, scale, scale, 1);
  }

  /// 滚动输入平移，Ctrl/Meta+滚轮以光标位置为锚缩放。
  /// 同时兼容物理滚轮与白板驱动映射来的滚动事件。
  void _onPointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent) return;
    if (canvasZoomModifierPressed) {
      if (event.scrollDelta.dy == 0) return;
      final factor = event.scrollDelta.dy < 0 ? 1.12 : 1 / 1.12;
      _zoomBy(factor, null, anchor: event.localPosition);
      return;
    }
    if (event.scrollDelta == Offset.zero) return;
    setState(() {
      _viewCtrl.value = canvasPanAfterScroll(
        _viewCtrl.value,
        event.scrollDelta,
      );
    });
  }

  /// 以锚点为中心缩放（锚点 null 时以视口中心——触控缩放条场景）。
  void _zoomBy(double factor, Size? viewport, {Offset? anchor}) {
    final current = _viewCtrl.value.getMaxScaleOnAxis();
    final next = (current * factor).clamp(_minScale, _maxScale);
    if (next == current) return;
    final sceneAnchor = _viewCtrl.toScene(
      anchor ??
          (viewport == null
              ? Offset.zero
              : Offset(viewport.width / 2, viewport.height / 2)),
    );
    final scale = next / current;
    setState(() {
      _viewCtrl.value = _viewCtrl.value.clone()
        ..translateByDouble(sceneAnchor.dx, sceneAnchor.dy, 0, 1)
        ..scaleByDouble(scale, scale, scale, 1)
        ..translateByDouble(-sceneAnchor.dx, -sceneAnchor.dy, 0, 1);
    });
  }

  /// 「适配全图」：**显式全图总览**（与默认阅读视图是两个语义）。
  ///
  /// 置 [_overview] = true 后清掉适配缓存重算——此时适配尺度不设阅读下限，
  /// 真的把 19 节点全部装进视口（可压到 [_minScale]）。图例「全图」与课堂
  /// 缩放条第三个键共用本方法，保证两条入口行为逐像素一致。
  void _fitOverview(Size viewport) {
    setState(() {
      _overview = true;
      _fittedFor = Size.zero;
      _fitToView(viewport);
    });
  }

  void _handleTap(Offset local, List<KnowledgeNode> shownNodes) {
    for (final n in shownNodes) {
      final pos = _positions?[n.id];
      if (pos == null) continue;
      final rect = Rect.fromLTWH(pos.dx, pos.dy, _nodeW, _nodeH);
      if (!rect.contains(local)) continue;
      _toggleNodeSelection(n);
      return;
    }
    // 点空白 ⇒ 清除选中（其余状态不动）。
    if (_selectedNodeId != null) setState(() => _selectedNodeId = null);
  }

  /// 普通节点与弱点覆盖层共用的选中切换，避免覆盖层绕过「再点取消」。
  void _toggleNodeSelection(KnowledgeNode n) {
    // 首次点 ⇒ 选中 + 开原详情；再点当前节点 ⇒ 只收镜头、不重复弹 sheet。
    final wasSelected = _selectedNodeId == n.id;
    setState(() {
      _selectedNodeId = wasSelected ? null : n.id;
      // 原行为：点节点即清掉「先修补课」的搜索期高亮。
      _focusedNodeId = null;
    });
    if (!wasSelected) _showDetail(n);
  }

  /// v2.19.63：给「挂题 ≥3」的节点挂一枚 tooltip「这里错得多」。
  ///
  /// 纯叠加层：节点世界坐标 → 视口坐标随 [_viewCtrl] 实时重算
  /// （AnimatedBuilder）。空数据时**不加 Stack**（返回原 canvas），
  /// 保证空错题本像素零变化。叠加层 opaque 接管点击，但与普通节点
  /// 共用选中切换：首次弹详情，再点同一节点取消焦点，不重复弹 Sheet。
  Widget _withWeaknessTips(
    Widget canvas,
    List<KnowledgeNode> nodes,
    Map<String, int> weakness,
  ) {
    final tips = <Widget>[];
    for (final n in nodes) {
      if ((weakness[n.id] ?? 0) < KnowledgeGraphPainter.redThreshold) continue;
      final pos = _positions?[n.id];
      if (pos == null) continue;
      tips.add(
        AnimatedBuilder(
          animation: _viewCtrl,
          builder: (ctx, _) {
            final m = _viewCtrl.value;
            final scale = m.getMaxScaleOnAxis();
            final tl = MatrixUtils.transformPoint(m, pos);
            return Positioned(
              left: tl.dx,
              top: tl.dy,
              width: _nodeW * scale,
              height: _nodeH * scale,
              child: Tooltip(
                message: '这里错得多',
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => _toggleNodeSelection(n),
                  child: const SizedBox.expand(),
                ),
              ),
            );
          },
        ),
      );
    }
    if (tips.isEmpty) return canvas;
    return Stack(children: [canvas, ...tips]);
  }

  /// v2.21.0：「先修补课」：跳到先修节点并高亮（点节点详情会清空高亮）。
  /// 镜头也落到该节点（选中态跟随），否则「补这课」后画布仍围着原节点
  /// 打光，看起来像没跳。
  void _focusPrerequisite(KnowledgeNode node) {
    setState(() {
      _focusedNodeId = node.id;
      _selectedNodeId = node.id;
      // 该节点可能被页面搜索过滤掉（无坐标）——清搜索词，下一帧再定位。
      if (!_filtered.any((n) => n.id == node.id)) _query = '';
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final pos = _positions?[node.id];
      if (pos == null || _viewportSize == Size.zero) return;
      const scale = 1.0;
      final center = Offset(pos.dx + _nodeW / 2, pos.dy + _nodeH / 2);
      setState(() {
        _viewCtrl.value = Matrix4.identity()
          ..translateByDouble(
            _viewportSize.width / 2 - center.dx * scale,
            _viewportSize.height / 2 - center.dy * scale,
            0,
            1,
          )
          ..scaleByDouble(scale, scale, scale, 1);
      });
    });
  }

  /// v2.6 抽屉节点定位：把节点平移居中到视口并弹详情。
  /// 抽屉搜索是抽屉内部状态，页面搜索可能已过滤掉该节点（无坐标）——
  /// 先清页面搜索词，等下一帧布局完成后再取坐标。
  void _jumpToNode(KnowledgeNode node) {
    if (!_filtered.any((n) => n.id == node.id)) {
      setState(() {
        _query = '';
        _focusedNodeId = null;
      });
    } else if (_focusedNodeId != null) {
      setState(() => _focusedNodeId = null);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final pos = _positions?[node.id];
      if (pos == null || _viewportSize == Size.zero) return;
      // 定位阅读尺度取 1.0（夹在 [_minScale, _maxScale] 区间内）
      const scale = 1.0;
      final center = Offset(pos.dx + _nodeW / 2, pos.dy + _nodeH / 2);
      setState(() {
        _viewCtrl.value = Matrix4.identity()
          ..translateByDouble(
            _viewportSize.width / 2 - center.dx * scale,
            _viewportSize.height / 2 - center.dy * scale,
            0,
            1,
          )
          ..scaleByDouble(scale, scale, scale, 1);
      });
      _showDetail(node);
    });
  }

  void _showDetail(KnowledgeNode node) {
    // v2.21.0：详情与画布选中同源——任何入口打开详情（点节点 / 抽屉定位 /
    // 「先修补课」/ 弱点 tooltip / 测试钩子 debugShowDetail）都把镜头落到
    // 该节点；已选中的节点不重复触发重建。
    if (_selectedNodeId != node.id) {
      setState(() => _selectedNodeId = node.id);
    }
    AppState.instance.report('正在查看知识点', node.title);
    AppState.instance.report('知识点说明', node.description);
    final prereq = _graph.prerequisitesOf(node.id);
    final succ = _graph.successorsOf(node.id);
    // v2.19.63：该节点挂题数（错题本只读驱动）。
    final weakness = _weaknessCounts[node.id] ?? 0;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.7,
        maxChildSize: 0.9,
        builder: (ctx, scrollController) => _NodeDetail(
          node: node,
          prereq: prereq,
          succ: succ,
          scrollController: scrollController,
          // v2.21.0：节点 → 功能页链接（稳定 destinationId + 展示 label；
          // 未知节点 / 未知目的地 ⇒ null ⇒ 按钮不渲染）。
          tool: knowledgeGraphLinkForNode(node.id),
          // v2.19.63：有错题 + 有先修 ⇒ 才给「先修补这课」
          //（否则 null ⇒ 按钮不渲染，零像素诚实）。
          weaknessCount: weakness,
          onPrereqRemediate: (weakness > 0 && prereq.isNotEmpty)
              ? () {
                  Navigator.pop(ctx);
                  _focusPrerequisite(prereq.first);
                }
              : null,
          onOpenTool: widget.onOpenTool == null
              ? null
              : (link) {
                  // 先关 sheet 再切页。页内深链只切到正确页签，不填题；
                  // 旧目标未注册时回退到原有导航索引，保留公开契约。
                  Navigator.pop(ctx);
                  final moduleId = link.moduleId;
                  if (moduleId != null &&
                      ModuleFillBus.fill(
                        moduleId,
                        link.linkParams,
                        sourceLabel: '知识图谱',
                      )) {
                    return;
                  }
                  widget.onOpenTool!(link.navIndex!);
                },
          onNodeTap: (n) {
            Navigator.pop(ctx);
            _showDetail(n);
          },
        ),
      ),
    );
  }

  void _showKaodianSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.85,
        maxChildSize: 0.95,
        builder: (ctx, scrollController) =>
            _KaodianSheet(scrollController: scrollController),
      ),
    );
  }
}

/// 网状知识图谱绘制器：方块节点 + 连线（先修/关联）。
class KnowledgeGraphPainter extends CustomPainter {
  final KnowledgeGraph graph;
  final List<KnowledgeNode> nodes;
  final Map<String, Offset> positions;
  final Set<String> highlighted;

  /// v2.19.63：节点挂题数（nodeId → 条数）。空 map / 缺键一律按 0
  /// 处理 ⇒ 走基线描边，默认（空错题本）逐像素不变。
  final Map<String, int> weaknessCounts;

  /// v2.21.0：画布选中节点 id（null = 常态，无镜头）。
  ///
  /// **只决定绘制强弱**，不参与布局或路由：分层坐标、正交避障车道、
  /// 箭头落点、`highlighted` 搜索高亮、`weaknessCounts` 描边全部照旧
  /// 生效（不换力导向、不重排节点）。
  final String? focusedNodeId;

  static const nodeW = 150.0;
  static const nodeH = 56.0;

  /// v2.19.63 挂题分层阈值：≥[redThreshold] 红描边；≥[amberThreshold] 琥珀。
  static const int amberThreshold = 1;
  static const int redThreshold = 3;

  // ── v2.21.0 边的强弱档（课堂上投影能看清的下限，别再往下调）──
  /// 常态：先修 1.7px / 0.34，关联 1.1px / 0.22（结构在，节点是主角）。
  static const double edgePrereqWidth = 1.7;
  static const double edgePrereqAlpha = 0.34;
  static const double edgeRelatedWidth = 1.1;
  static const double edgeRelatedAlpha = 0.22;

  /// 选中：相关边提亮并最后绘制（压在同层其他线之上）。
  static const double focusEdgeWidth = 2.6;
  static const double focusEdgeAlpha = 0.92;

  /// 选中：非相关边只留一线结构（0.08），不抢镜头但路线不消失。
  static const double dimEdgeAlpha = 0.08;

  /// 选中：一跳之外的节点保留权重（仍画，只降权）。
  static const double dimNodeWeight = 0.45;

  /// 非焦点节点的标题权重。**故意高于卡片权重**：背景/描边降权用于
  /// 聚焦，文字仍必须可读；0.45 直接乘到标题上时浅色对比仅 2.48:1，
  /// 非焦点内容名义上「保留」却无法阅读。0.72 在三套主题、普通与
  /// 基础概念节点上均超过 WCAG AA 4.5:1（回归测试逐档复算）。
  static const double dimNodeLabelWeight = 0.72;

  /// 把卡片权重映射为标题权重；焦点/搜索/薄弱点仍是全强度。
  static double nodeLabelWeight(double weight) =>
      weight >= 1.0 ? 1.0 : dimNodeLabelWeight;

  KnowledgeGraphPainter({
    required this.graph,
    required this.nodes,
    required this.positions,
    required this.highlighted,
    this.weaknessCounts = const {},
    this.focusedNodeId,
  });

  /// v2.19.63：挂题数 → 描边色（null = 走基线描边）。
  /// **只**决定描边色/宽度，不碰填充（[weaknessStroke] 与 paint 内分层同源）。
  static Color? weaknessStroke(int count) {
    if (count >= redThreshold) return AppColors.lethal;
    if (count >= amberThreshold) return AppColors.flash;
    return null;
  }

  /// v2.21.0：一跳邻域（含自身）。选中时这一圈保持全强度，
  /// 不论边的方向与 kind（先修/关联都算「一跳」）。
  static Set<String> focusNeighborhood(KnowledgeGraph graph, String focusId) {
    final ids = <String>{focusId};
    for (final e in graph.edges) {
      if (e.from == focusId) ids.add(e.to);
      if (e.to == focusId) ids.add(e.from);
    }
    return ids;
  }

  /// v2.21.0：节点绘制权重（1.0 = 常态 / [dimNodeWeight] = 选中时降权）。
  ///
  /// 搜索高亮（[highlighted]）与薄弱点描边是**数据信号**，一律不降权——
  /// 镜头不得把「搜到的」「错得多的」压暗。
  static double nodeWeight({
    required bool hasFocus,
    required bool inNeighborhood,
    required bool highlighted,
    required bool hasWeakness,
  }) {
    if (!hasFocus || inNeighborhood || highlighted || hasWeakness) return 1.0;
    return dimNodeWeight;
  }

  /// v2.21.0：通道错峰量由 from/to/kind **稳定派生**（-16 / -8 / 0 / 8 / 16）。
  ///
  /// 改前按边在数组里的序号取模：搜索一过滤，显示集合变短，同一条边的
  /// 序号漂移 ⇒ 路线「换道」，看着像布局抖动。现在只由边自身决定。
  static double channelOffset(String from, String to, String kind) {
    var h = 0;
    for (final unit in '$from>$to#$kind'.codeUnits) {
      h = (h * 31 + unit) & 0x7fffffff;
    }
    return ((h % 5) - 2) * 8.0;
  }

  /// 按权重压透明度（权重 1.0 原样返回，基线像素不变）。
  static Color _weighted(Color color, double weight) =>
      weight >= 1.0 ? color : color.withValues(alpha: color.a * weight);

  /// 生效的选中节点：必须真的在当前显示集合里有坐标，否则按常态处理。
  String? get _resolvedFocus {
    final id = focusedNodeId;
    if (id == null) return null;
    return positions.containsKey(id) ? id : null;
  }

  bool _touchesFocus(KnowledgeEdge e, String focus) =>
      e.from == focus || e.to == focus;

  /// 一条边的画笔：常态降权 / 选中相关提亮 / 选中非相关压到一线。
  Paint _edgePaint(KnowledgeEdge e, String? focus) {
    final isPrereq = e.kind == 'prerequisite';
    final related = focus != null && _touchesFocus(e, focus);
    final double width;
    final double alpha;
    if (focus == null) {
      width = isPrereq ? edgePrereqWidth : edgeRelatedWidth;
      alpha = isPrereq ? edgePrereqAlpha : edgeRelatedAlpha;
    } else if (related) {
      width = focusEdgeWidth;
      alpha = focusEdgeAlpha;
    } else {
      width = isPrereq ? edgePrereqWidth : edgeRelatedWidth;
      alpha = dimEdgeAlpha;
    }
    // 连线按 kind 对齐图例：先修 = graphite / 关联 = teal。
    return Paint()
      ..strokeWidth = width
      // drawPath 默认 fill！缺了这行肘形路径会被填成实心多边形
      ..style = PaintingStyle.stroke
      ..strokeJoin = StrokeJoin.round
      ..color = (isPrereq ? AppColors.graphite : AppColors.teal).withValues(
        alpha: alpha,
      );
  }

  /// 基础概念三件套（图谱的根）用 sand 标记，其余 teal 系。
  bool _isRootConcept(KnowledgeNode n) =>
      n.id == 'dna-genes-alleles' ||
      n.id == 'genotype-phenotype' ||
      n.id == 'dominant-recessive';

  @override
  void paint(Canvas canvas, Size size) {
    // v2.21.0：生效选中（无选中 / 节点被搜索过滤掉 ⇒ 常态）。
    final focus = _resolvedFocus;
    // 先画连线。选中态分两趟：非相关边先画（压暗），相关边最后画
    // （提亮并压在同层任何线之上）。画的仍是同一批边、同一条路线。
    for (final e in graph.edges) {
      if (focus != null && _touchesFocus(e, focus)) continue;
      _paintEdge(canvas, e, focus);
    }
    if (focus != null) {
      for (final e in graph.edges) {
        if (_touchesFocus(e, focus)) _paintEdge(canvas, e, focus);
      }
    }

    // 主干集合：出现在先修链上的节点（描边加深，区分核心/变式层级）
    final mainChain = <String>{};
    for (final e in graph.edges) {
      if (e.kind == 'prerequisite') {
        mainChain.add(e.from);
        mainChain.add(e.to);
      }
    }

    // 画节点（方块）
    // v2.21.0：选中时一跳之外降权（仍画、仍在原坐标）；搜索高亮与薄弱点
    // 描边属数据信号，nodeWeight 一律给 1.0，不被镜头压掉。
    final neighborhood = focus == null
        ? const <String>{}
        : focusNeighborhood(graph, focus);
    for (final n in nodes) {
      final pos = positions[n.id]!;
      final rect = Rect.fromLTWH(pos.dx, pos.dy, nodeW, nodeH);
      final isHi = highlighted.contains(n.id);
      final isRoot = _isRootConcept(n);
      final isCore = mainChain.contains(n.id);
      // v2.19.63：薄弱点着色——**只改描边**（琥珀/红），填充一律不动。
      // 挂题 0 ⇒ weaknessStroke 返 null ⇒ 基线描边原样，像素不变。
      final weak = weaknessCounts[n.id] ?? 0;
      final weakStroke = weaknessStroke(weak);
      final weight = nodeWeight(
        hasFocus: focus != null,
        inNeighborhood: neighborhood.contains(n.id),
        highlighted: isHi,
        hasWeakness: weakStroke != null,
      );

      // 基础概念（根节点）常态也用 sand 描边/浅底，与图例「基础概念」对齐
      final fill = Paint()
        ..color = _weighted(
          isHi
              ? (isRoot
                    ? AppColors.sand.withValues(alpha: 0.12)
                    : AppColors.tealWash)
              : (isRoot
                    ? AppColors.sand.withValues(alpha: 0.10)
                    : AppColors.surface),
          weight,
        );
      final border = Paint()
        ..color = _weighted(
          isHi
              ? (isRoot ? AppColors.sand : AppColors.teal)
              : (isRoot
                    ? AppColors.sand
                    : (isCore
                          ? AppColors.graphite.withValues(alpha: 0.65)
                          : AppColors.border)),
          weight,
        )
        ..style = PaintingStyle.stroke
        ..strokeWidth = isHi ? 1.8 : ((isRoot || isCore) ? 1.6 : 1.0);
      if (weakStroke != null) {
        border.color = weakStroke;
        border.strokeWidth = weak >= redThreshold ? 2.4 : 1.8;
      }
      // 圆角方块
      final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(10));
      canvas.drawRRect(rrect, fill);
      canvas.drawRRect(rrect, border);

      // 文字（标题居中，可能两行）
      final tp = TextPainter(
        text: TextSpan(
          text: n.title,
          style: TextStyle(
            fontFamily: AppFonts.sans,
            fontFamilyFallback: AppFonts.sansFallback,
            fontSize: 12,
            fontWeight: FontWeight.w600, // 投影可读性：常态也 w600
            height: 1.35,
            color: _weighted(
              isHi
                  ? (isRoot ? AppColors.sand : AppColors.tealDark)
                  : AppColors.ink,
              nodeLabelWeight(weight),
            ),
          ),
        ),
        textDirection: TextDirection.ltr,
        maxLines: 2,
        textAlign: TextAlign.center,
      )..layout(maxWidth: nodeW - 12);
      tp.paint(
        canvas,
        Offset(
          pos.dx + (nodeW - tp.width) / 2,
          pos.dy + (nodeH - tp.height) / 2,
        ),
      );
    }
  }

  /// 画一条边（含箭头）。v2.3.3 的肘形避障路由原样搬进来：
  /// 起点/终点、通道路径、车道挑选、箭头落点全部不变，只有画笔
  /// （粗细/透明度）随 [focus] 分档，以及错峰量改为稳定派生。
  void _paintEdge(Canvas canvas, KnowledgeEdge e, String? focus) {
    final from = positions[e.from];
    final to = positions[e.to];
    if (from == null || to == null) return;
    // 通道错峰：同一通道的多条水平段 ±16px 铺开，避免共线合并成
    // 「总线」导致关系不可追溯（AI 评审四轮）；错峰量由边自身派生，
    // 不随显示集合/数组序号漂移。
    final off = channelOffset(e.from, e.to, e.kind);
    final paint = _edgePaint(e, focus);
    // 从节点中心出发
    final f = Offset(from.dx + nodeW / 2, from.dy + nodeH / 2);
    final t = Offset(to.dx + nodeW / 2, to.dy + nodeH / 2);
    // v2.3.3：肘形路由（AI 评审二轮「连线穿透节点」实锤 + 解析复核 12 处）。
    // 只有「邻层且横移 ≤60」的短边保留直线（线段只穿越空通道，必不碰
    // 节点）；其余一律肘形，水平段全落在行间空通道，垂直段车道经碰撞
    // 检测挑选（_pickFreeLane）：
    //   下行（目标在下）：A 底 → 通道横移 → B 行上通道 → B 顶，箭头朝下
    //   上行/同行：A 底 → A 行下通道 → B 行下通道 → B 底，箭头朝上
    final gap = to.dy - (from.dy + nodeH); // B 顶 - A 底（同行为 -nodeH）
    final dxAbs = (t.dx - f.dx).abs();
    if (gap > 0 && gap <= 70 && dxAbs <= 60) {
      canvas.drawLine(f, t, paint);
      _drawArrow(canvas, f, t, paint);
    } else if (gap > 0) {
      final start = Offset(f.dx, from.dy + nodeH);
      final end = Offset(t.dx, to.dy);
      final channelY = to.dy - 32 + off; // 目标行上方通道（错峰）
      final lane = _pickFreeLane(start, channelY, from, to);
      final path = Path()
        ..moveTo(start.dx, start.dy)
        ..lineTo(start.dx, start.dy + 10)
        ..lineTo(lane, start.dy + 10)
        ..lineTo(lane, channelY)
        ..lineTo(end.dx, channelY)
        ..lineTo(end.dx, end.dy);
      canvas.drawPath(path, paint);
      _drawArrow(canvas, Offset(end.dx, channelY), end, paint);
    } else {
      // 上行或同行：走下方通道绕行，箭头从 B 底边向上入
      final start = Offset(f.dx, from.dy + nodeH);
      final end = Offset(t.dx, to.dy + nodeH);
      final chA = start.dy + 32 + off; // A 行下通道（错峰）
      final chB = end.dy + 32 + off; // B 行下通道（错峰）
      final lane = _pickFreeLane(Offset(start.dx, chB), chA, from, to);
      final path = Path()
        ..moveTo(start.dx, start.dy)
        ..lineTo(start.dx, chA)
        ..lineTo(lane, chA)
        ..lineTo(lane, chB)
        ..lineTo(end.dx, chB)
        ..lineTo(end.dx, end.dy);
      canvas.drawPath(path, paint);
      _drawArrow(canvas, Offset(end.dx, chB), end, paint);
    }
  }

  /// 为跨层肘形路由挑选避障车道 x：候选车道依次尝试，返回垂直段
  /// （start.dy → channelY）不与任何中间层节点（外扩 14px，兼顾视觉
  /// 间距——8px 在 fit-to-view 缩放后只剩 4px，看起来仍像贴边）相撞
  /// 的第一个。源/目标节点本身除外（垂直段端点在它们之外）。
  double _pickFreeLane(Offset start, double channelY, Offset from, Offset to) {
    final candidates = <double>[
      start.dx,
      to.dx + nodeW / 2,
      (start.dx + to.dx + nodeW / 2) / 2,
      start.dx + 24,
      start.dx - 24,
      to.dx + nodeW / 2 + 24,
      to.dx + nodeW / 2 - 24,
      start.dx + 48,
      start.dx - 48,
    ];
    bool hits(double x) {
      for (final e in positions.entries) {
        if (e.value == from || e.value == to) continue;
        final r = Rect.fromLTWH(
          e.value.dx,
          e.value.dy,
          nodeW,
          nodeH,
        ).inflate(14);
        // 只关心中间层：节点垂直范围与垂直段有交叠才检测
        if (r.bottom <= start.dy + 1 || r.top >= channelY) continue;
        if (x > r.left && x < r.right) return true;
      }
      return false;
    }

    for (final c in candidates) {
      if (!hits(c)) return c;
    }
    // 固定候选全撞（超长跨层边垂直走廊挤满节点）：
    // 全宽扫描车道（步长 20px，距源 x 近者优先），页边通道必空。
    final maxX =
        positions.values.map((p) => p.dx + nodeW).reduce(math.max) + 60;
    for (var off = 20.0; off < maxX; off += 20) {
      for (final c in [start.dx + off, start.dx - off]) {
        if (c > 10 && c < maxX - 10 && !hits(c)) return c;
      }
    }
    return 30; // 左页边通道兜底
  }

  void _drawArrow(Canvas canvas, Offset from, Offset to, Paint paint) {
    final dir = to - from;
    final len = dir.distance;
    if (len < 1) return;
    final ux = dir.dx / len, uy = dir.dy / len;
    final tip = Offset(to.dx - 4 * ux, to.dy - 4 * uy);
    final left = Offset(tip.dx - ux * 8 + uy * 5, tip.dy - uy * 8 - ux * 5);
    final right = Offset(tip.dx - ux * 8 - uy * 5, tip.dy - uy * 8 + ux * 5);
    final path = Path()
      ..moveTo(tip.dx, tip.dy)
      ..lineTo(left.dx, left.dy)
      ..lineTo(right.dx, right.dy)
      ..close();
    // 箭头头是闭合三角形，必须填充（edge paint 已改为 stroke 画肘线）
    canvas.drawPath(
      path,
      Paint()
        ..color = paint.color
        ..style = PaintingStyle.fill,
    );
  }

  @override
  bool shouldRepaint(covariant KnowledgeGraphPainter oldDelegate) =>
      oldDelegate.positions != positions ||
      oldDelegate.highlighted != highlighted ||
      oldDelegate.weaknessCounts != weaknessCounts ||
      // v2.21.0：选中态变化必须重绘（否则镜头拖动/取消后线宽留旧样）
      oldDelegate.focusedNodeId != focusedNodeId ||
      oldDelegate.nodes != nodes;
}

/// 课堂模式触控缩放条（v2.3.4）：白板无滚轮，拖拽平移费胳膊——
/// 右下常驻三个 56px 大按钮：放大 / 缩小 / 适配全图。
class _GraphZoomBar extends StatelessWidget {
  final VoidCallback onZoomIn;
  final VoidCallback onZoomOut;
  final VoidCallback onFit;
  const _GraphZoomBar({
    required this.onZoomIn,
    required this.onZoomOut,
    required this.onFit,
  });

  @override
  Widget build(BuildContext context) {
    // 不 const：消费 AppColors 静态 token（课堂模式切换时随主题刷新）。
    Widget btn(IconData icon, String tip, VoidCallback onTap) => Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Material(
        color: AppColors.surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: AppColors.border),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Tooltip(
            message: tip,
            child: SizedBox(
              width: 56,
              height: 56,
              child: Icon(icon, size: 26, color: AppColors.teal),
            ),
          ),
        ),
      ),
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        btn(Icons.add, '放大', onZoomIn),
        btn(Icons.remove, '缩小', onZoomOut),
        btn(Icons.fit_screen, '适配全图', onFit),
      ],
    );
  }
}

class _NodeDetail extends StatelessWidget {
  final KnowledgeNode node;
  final List<KnowledgeNode> prereq;
  final List<KnowledgeNode> succ;
  final ScrollController scrollController;
  final ValueChanged<KnowledgeNode> onNodeTap;

  /// v2.2 / v2.21.0：节点对应的功能页链接（稳定 destinationId + 展示
  /// label）；null = 无对应功能页 / 未知节点 ⇒ 按钮不渲染。
  final AppModuleLink? tool;

  /// v2.19.63：该节点挂题数（错题本只读驱动；0 = 无错题 ⇒ 不渲染薄弱 UI）。
  final int weaknessCount;

  /// v2.19.63：有错题 + 有先修时给的「先修补这课」回调；
  /// null ⇒ 按钮**不渲染**（sheet 已由调用方关闭，跳到先修节点并高亮）。
  final VoidCallback? onPrereqRemediate;

  /// v2.2 双向跳转：点击功能按钮时回调（sheet 已由调用方关闭）。
  /// 携带完整链接，以便优先落到页内页签再回退主导航。
  final ValueChanged<AppModuleLink>? onOpenTool;

  const _NodeDetail({
    required this.node,
    required this.prereq,
    required this.succ,
    required this.scrollController,
    required this.onNodeTap,
    this.tool,
    this.weaknessCount = 0,
    this.onPrereqRemediate,
    this.onOpenTool,
  });

  @override
  Widget build(BuildContext context) {
    // v2.21.0：导航索引由 appNavDestinations 顺序派生（不写死数字）；
    // 未知节点 / 目的地已下线 ⇒ navIndex == null ⇒ 入口不渲染。
    final link = tool;
    final navIndex = link?.navIndex;
    return ListView(
      controller: scrollController,
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      children: [
        Center(
          child: Container(
            width: 40,
            height: 4,
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              color: AppColors.border,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
        // 2.2 推广：节点详情卡片化（StepCard step: 0 纯分区卡）；
        // 先修/关联列表保持可点（_LinkedNodeTile.onTap 不动）。
        StepCard(
          step: 0,
          title: node.title,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (node.tags.isNotEmpty) ...[
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: node.tags.map((t) => AppChip(t)).toList(),
                ),
                const SizedBox(height: 12),
              ],
              Text(node.description, style: AppText.body),
              if (node.milestoneExercises.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  '里程碑题目：${node.milestoneExercises.join(', ')}',
                  style: AppText.monoSmall.copyWith(color: AppColors.steel),
                ),
              ],
              // v2.4 N8：易错点速查（平度九中教研实证的学生高频错误），
              // 讲课到该节点时随手带出。
              if (nodePitfalls[node.id] != null) ...[
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.sand.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: AppColors.sand.withValues(alpha: 0.4),
                    ),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.warning_amber_rounded,
                        size: 16,
                        color: AppColors.sand,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '易错点：${nodePitfalls[node.id]}',
                          style: AppText.caption.copyWith(
                            color: AppColors.graphite,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              // v2.19.63：薄弱点提示（挂题 >0 才渲染；0 ⇒ 零像素）。
              if (weaknessCount > 0) ...[
                const SizedBox(height: 12),
                _weaknessBanner(weaknessCount),
              ],
              // v2.19.63：「先修补这课」——先补先修节点再回来。
              // 有错题 + 有先修才渲染（onPrereqRemediate==null ⇒ 不渲染）。
              if (onPrereqRemediate != null) ...[
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: onPrereqRemediate,
                    icon: const Icon(Icons.healing_outlined, size: 17),
                    label: const Text('先修补这课'),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(0, 40),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
                ),
              ],
              // v2.2：知识点 → 对应软件功能直达按钮（双向跳转：
              // 跳转后目标页顶部出现「返回图谱」横幅）。
              if (link != null && navIndex != null && onOpenTool != null) ...[
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: () => onOpenTool!(link),
                    icon: const Icon(Icons.open_in_new, size: 17),
                    label: Text('打开对应功能：${link.displayLabel}'),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(0, 40),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '跳转后可点顶部横幅返回本页',
                  style: AppText.caption.copyWith(color: AppColors.steel),
                ),
              ],
            ],
          ),
        ),
        if (prereq.isNotEmpty)
          StepCard(
            step: 0,
            title: '先修知识点',
            child: Column(
              children: [
                for (final n in prereq)
                  _LinkedNodeTile(
                    node: n,
                    icon: Icons.arrow_back,
                    onTap: () => onNodeTap(n),
                  ),
              ],
            ),
          ),
        if (succ.isNotEmpty)
          StepCard(
            step: 0,
            title: '关联 / 后续知识点',
            child: Column(
              children: [
                for (final n in succ)
                  _LinkedNodeTile(
                    node: n,
                    icon: Icons.arrow_forward,
                    onTap: () => onNodeTap(n),
                  ),
              ],
            ),
          ),
      ],
    );
  }

  /// v2.19.63：挂题提示条（≥3 红「这里错得多」；1-2 琥珀）。
  Widget _weaknessBanner(int count) {
    final red = count >= KnowledgeGraphPainter.redThreshold;
    final color = red ? AppColors.lethal : AppColors.flash;
    final text = red ? '这里错得多（错题本挂了 $count 条）' : '错题本有 $count 条挂在这个知识点';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.error_outline, size: 16, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: AppText.caption.copyWith(color: AppColors.graphite),
            ),
          ),
        ],
      ),
    );
  }
}

class _LinkedNodeTile extends StatelessWidget {
  final KnowledgeNode node;
  final IconData icon;
  final VoidCallback onTap;
  const _LinkedNodeTile({
    required this.node,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon, size: 18, color: AppColors.teal),
      title: Text(node.title, style: AppText.body),
      subtitle: node.id.startsWith('9331')
          ? Text('9331 变式', style: AppText.caption)
          : null,
      onTap: onTap,
    );
  }
}

// ─────────────────────────────────────────────
// 考点速查抽屉
// ─────────────────────────────────────────────

class _KaodianSheet extends StatefulWidget {
  final ScrollController scrollController;
  const _KaodianSheet({required this.scrollController});

  @override
  State<_KaodianSheet> createState() => _KaodianSheetState();
}

class _KaodianSheetState extends State<_KaodianSheet> {
  late final Future<KaodianBank> _future = _load();
  String _query = '';

  Future<KaodianBank> _load() async {
    try {
      final raw = await rootBundle.loadString('data/kaodian_compilation.json');
      return parseKaodianJson(raw);
    } on FlutterError {
      return const KaodianBank(name: '', items: []);
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<KaodianBank>(
      future: _future,
      builder: (context, snap) {
        final bank = snap.data ?? const KaodianBank(name: '', items: []);
        final items = bank.search(_query);
        return Column(
          children: [
            const SizedBox(height: 12),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 8),
              child: Row(
                children: [
                  Text('考点速查', style: AppText.pageTitle),
                  const SizedBox(width: 10),
                  if (bank.items.isNotEmpty)
                    AppChip(
                      '${bank.items.length} 条',
                      icon: Icons.bookmark_outline,
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: TextField(
                onChanged: (v) => setState(() => _query = v),
                decoration: InputDecoration(
                  hintText: '搜索考点（如 致死、连锁、9:7）',
                  hintStyle: AppText.caption,
                  prefixIcon: Icon(
                    Icons.search,
                    size: 20,
                    color: AppColors.steel,
                  ),
                ),
              ),
            ),
            Expanded(
              child: snap.connectionState != ConnectionState.done
                  ? const SizedBox.shrink()
                  : bank.items.isEmpty
                  ? Center(
                      child: Text(
                        '考点库为空，请确认 asset 已打包。',
                        style: AppText.caption,
                      ),
                    )
                  : ListView.builder(
                      controller: widget.scrollController,
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                      itemCount: items.length,
                      itemBuilder: (ctx, i) => _KaodianTile(item: items[i]),
                    ),
            ),
          ],
        );
      },
    );
  }
}

class _KaodianTile extends StatelessWidget {
  final KaodianItem item;
  const _KaodianTile({required this.item});

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        tilePadding: EdgeInsets.zero,
        childrenPadding: const EdgeInsets.only(bottom: 12),
        iconColor: AppColors.teal,
        collapsedIconColor: AppColors.steel,
        title: Text(item.name, style: AppText.label),
        subtitle: item.typicalRatio.isNotEmpty
            ? Text(
                item.typicalRatio,
                style: AppText.monoSmall.copyWith(color: AppColors.teal),
              )
            : null,
        onExpansionChanged: (expanded) {
          if (expanded) {
            AppState.instance.report(
              '正在查看考点',
              '${item.id} ${item.name} · ${item.typicalRatio}',
            );
          }
        },
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: Text(item.content, style: AppText.body),
          ),
          if (item.source.isNotEmpty) ...[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                item.source,
                style: AppText.caption,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────
// v2.6 ☰ 图谱工具抽屉（节点索引 / 搜索 / 易错点筛选 / 定位）
// ─────────────────────────────────────────────

/// 抽屉内容自持有状态（搜索词、易错点开关都在抽屉 State 内部）——
/// DrawerController 关闭抽屉只 deactivate 不 dispose，若读页面层可变
/// 状态重开会显示旧值；内聚后该坑不存在，且重开时搜索词自然保留。
class _GraphToolsDrawer extends StatefulWidget {
  final List<KnowledgeNode> nodes;

  /// 点节点：抽屉已关，页面负责画布定位 + 弹详情。
  final ValueChanged<KnowledgeNode> onJumpToNode;

  /// 底部「考点速查」入口：抽屉已关，页面负责弹 sheet。
  final VoidCallback onOpenKaodian;

  const _GraphToolsDrawer({
    required this.nodes,
    required this.onJumpToNode,
    required this.onOpenKaodian,
  });

  @override
  State<_GraphToolsDrawer> createState() => _GraphToolsDrawerState();
}

class _GraphToolsDrawerState extends State<_GraphToolsDrawer> {
  String _query = '';
  bool _onlyPitfalls = false;

  List<KnowledgeNode> get _items {
    final q = _query.trim().toLowerCase();
    return widget.nodes.where((n) {
      if (_onlyPitfalls && !nodePitfalls.containsKey(n.id)) return false;
      if (q.isEmpty) return true;
      return n.title.toLowerCase().contains(q) ||
          n.tags.any((t) => t.toLowerCase().contains(q));
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final items = _items;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
          child: Row(
            children: [
              Text('图谱工具', style: AppText.pageTitle),
              const SizedBox(width: 10),
              AppChip('${widget.nodes.length} 个节点', icon: Icons.hub_outlined),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
          child: TextField(
            onChanged: (v) => setState(() => _query = v),
            decoration: InputDecoration(
              hintText: '搜索节点标题或标签',
              hintStyle: AppText.caption,
              prefixIcon: Icon(Icons.search, size: 20, color: AppColors.steel),
            ),
          ),
        ),
        SwitchListTile(
          value: _onlyPitfalls,
          onChanged: (v) => setState(() => _onlyPitfalls = v),
          title: Text('只看易错点', style: AppText.body),
          secondary: Icon(
            Icons.warning_amber_rounded,
            size: 18,
            color: AppColors.sand,
          ),
          dense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 16),
        ),
        Divider(height: 1, color: AppColors.border),
        Expanded(
          child: items.isEmpty
              ? Center(child: Text('没有匹配的节点', style: AppText.caption))
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  itemCount: items.length,
                  itemBuilder: (ctx, i) {
                    final n = items[i];
                    final hasPitfall = nodePitfalls.containsKey(n.id);
                    return ListTile(
                      dense: true,
                      leading: Icon(
                        hasPitfall
                            ? Icons.warning_amber_rounded
                            : Icons.hub_outlined,
                        size: 16,
                        color: hasPitfall ? AppColors.sand : AppColors.steel,
                      ),
                      title: Text(n.title, style: AppText.body),
                      onTap: () {
                        Navigator.pop(ctx);
                        widget.onJumpToNode(n);
                      },
                    );
                  },
                ),
        ),
        Divider(height: 1, color: AppColors.border),
        ListTile(
          leading: Icon(Icons.toc_outlined, size: 18, color: AppColors.teal),
          title: Text('考点速查', style: AppText.body),
          subtitle: Text('资料库考点与应试口径', style: AppText.caption),
          onTap: () {
            Navigator.pop(context);
            widget.onOpenKaodian();
          },
        ),
      ],
    );
  }
}
