// pedigree_canvas.dart —— 计算系谱画布组件（R1/R2/R4/R7/R9/R10）
//
// 世界坐标分层布局 + InteractiveViewer 视口变换：
//  - 每代一行，行内节点均分并整树水平居中（R10）；
//  - CustomPainter 视口裁剪，只画可见节点与相关边（R7）；
//  - 手势全部由本组件接管（InteractiveViewer 的 pan/scale 关闭）：
//    滚动输入=二维平移，Ctrl/Meta+滚轮=光标锚点缩放（Web 触控板捏合同路径），
//    onScale 系列回调同时覆盖 触屏双指捏合 / Precision Touchpad 捏合
//    （PointerPanZoom 序列由 ScaleGestureRecognizer 自动接入）与
//    空白左键拖平移、节点拖出连线（R4/R9）；
//  - 点击命中用「视口坐标 → 世界坐标逆变换 + 节点矩形命中」（R1），
//    起点/落点都做「最近圆心 + 随缩放换算的吸附半径」（React Flow 式）。

import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../engine/pedigree_graph.dart';
import '../../state/present_mode_controller.dart';
import '../../theme.dart';
import '../../ui/canvas_input.dart';
import 'laser_pointer_layer.dart';
import 'spotlight_layer.dart';

// 阶段 7 拆分：PedigreePainter 迁至 pedigree_painter.dart（part of 本库，
// 共享 import 与 halfTapId/parseTapId/halfRectOf/backcrossEdgeKey 等顶层工具，
// 页面/侧栏/详情条/测试的既有 import 零改动）。
part 'pedigree_painter.dart';

/// 回交边取色：按端点散列取调色板颜色，同一对端点颜色稳定。
/// 页面「回交线显隐」菜单与画布共用，保证菜单色块 = 画布线条色。
Color backcrossEdgeColor(PedigreeEdge e) => AppColors.backcrossPalette[
    (e.fromId.hashCode ^ e.toId.hashCode).abs() %
        AppColors.backcrossPalette.length];

/// 回交边稳定 key（显隐过滤用）。
String backcrossEdgeKey(PedigreeEdge e) => '${e.fromId}|${e.toId}';

// ── R15 组合桶半边协议 ─────────────────────────────────────────
/// 组合桶半边点选的合成 id：`groupId + "::male"` / `groupId + "::female"`。
/// 页面 selectedId / armedId / flashIds / pickedIds 均可携带该后缀，
/// 画布据此只点亮组合桶内对应性别的半边 glyph。
String halfTapId(String groupId, PedigreeNodeKind sex) =>
    '$groupId::${sex.name}';

/// 解析合成 id → (基础节点 id, 性别半边)；无 '::' 后缀时 half 为 null。
(String, PedigreeNodeKind?) parseTapId(String id) {
  final i = id.indexOf('::');
  if (i < 0) return (id, null);
  final tail = id.substring(i + 2);
  return (
    id.substring(0, i),
    tail == 'male'
        ? PedigreeNodeKind.male
        : tail == 'female'
            ? PedigreeNodeKind.female
            : null
  );
}

/// 组合桶内半边 glyph 的世界矩形（雄=左小矩形，雌=右圆外接矩形）。
/// State 命中判定与 Painter 绘制共用，保证点到的就是看到的。
Rect halfRectOf(Rect groupRect, PedigreeNodeKind sex) {
  final cy = groupRect.center.dy + 5;
  if (sex == PedigreeNodeKind.male) {
    return Rect.fromCenter(
        center: Offset(groupRect.left + groupRect.width * 0.27, cy),
        width: 30,
        height: 30);
  }
  return Rect.fromCenter(
      center: Offset(groupRect.left + groupRect.width * 0.73, cy),
      width: 32,
      height: 32);
}

/// 系谱画布。数据来源是引擎快照（nodes/edges），交互通过回调上报给页面。
class PedigreeCanvas extends StatefulWidget {
  final List<PedigreeNode> nodes;
  final List<PedigreeEdge> edges;
  final String? selectedId;

  /// 点按节点（R12 点选-点选连线：页面负责「待命→连线」状态机）。
  final ValueChanged<PedigreeNode>? onNodeTap;

  /// 点按组合桶的性别半边（R15）：(group 桶, male/female)。
  /// 仅在 sexSplitView 开启且命中组合桶时触发；普通节点仍走 onNodeTap。
  final void Function(PedigreeNode group, PedigreeNodeKind sex)?
      onNodeHalfTap;

  /// 点按空白（页面用来解除待命/清空选中）。
  final VoidCallback? onBlankTap;

  /// 长按节点 = 收回该节点最近一条连线（移动端友好的收线入口）。
  final ValueChanged<PedigreeNode>? onWireDetach;

  /// 待命中的连线起点 id（点选的第一个节点，画布画紫罗兰光晕）。
  final String? armedId;

  /// 连线成功瞬间的双节点 id（画布画橙光，约 2 秒后页面清除）。
  final Set<String> flashIds;

  /// v2.19.5 连线性别互斥：待命起点已定时不可连接的节点 id 集合
  /// （同性且未开同性交配）——画布整节点变暗，只留可连接目标亮起。
  final Set<String> dimIds;

  /// 线路可见性开关：主干线（lineage 灰）/ 回交线（跨代 mating 彩）。
  final bool showLineage;

  /// v2.19 连线样式（正交/曲线蜘蛛网），透传画家。
  final PdEdgeStyle edgeStyle;
  final bool showBackcross;

  /// 逐条隐藏的回交边 key 集合（见 backcrossEdgeKey）。
  final Set<String> hiddenBackcrossKeys;

  /// 右键空白：给出命中的世代与视口坐标（用于弹出菜单，R3）。
  final void Function(int generation, Offset viewportPos)? onBlankSecondaryTap;

  /// v2.19.10：触屏长按空白 = 弹同款快捷菜单（触屏无右键，老师走查
  /// M6——「添加外来样本」功能在触屏上隐身；长按节点仍 = 收线）。
  final void Function(int generation, Offset viewportPos)? onBlankLongPress;

  /// 右键节点（用于外来样本删除菜单）。
  final void Function(PedigreeNode node, Offset viewportPos)? onNodeSecondaryTap;

  /// 折叠状态：哪些 (家族:世代) 处于「只显示最高概率桶」（页面持有）。
  /// R26：每家族每代独立 chip。
  final Set<String> collapsedKeys;

  /// 每个折叠 (家族:世代) 被隐藏的桶数（画「+N 种基因型」芯片用）。
  final Map<String, int> hiddenCounts;

  /// 点击 (家族:世代) 的 展开/收起 芯片。
  final ValueChanged<String>? onToggleGen;

  /// 伴性遗传标注：非空时桶内 X/x/Y/y 染色（大 X 蓝、小 x 黄）
  /// 并在节点内追加「X=病」等表型标注行。
  final SexLinkedConfig? sexLinked;

  /// 家族编号 → 显示名（R14 家族分栏横幅；空 = 单家族不画横幅）。
  final Map<int, String> familyLabels;

  /// R15 组合桶渲染：开启后 group 桶画成「大矩形内含雄□雌○」，
  /// 半边可独立点选；SPLIT 半桶节点不再单独占位（其边路由到半边）。
  /// 页面随「XY 性别」开关（trackSex）传入。
  final bool sexSplitView;

  /// R15 选择模式：已勾选元素 id 集合（可含 '::male/::female' 合成
  /// id），画布给它们画 teal 勾选高亮。
  final Set<String> pickedIds;

  /// R23/R25 相连元素弱光：baseId -> 相连那侧 kind 集合（粒度到性别
  /// 半边；组合桶只给对应半边柔光，普通节点整节点）。
  final Map<String, Set<PedigreeNodeKind>> connectedIds;

  /// R24 组合桶半边专注：baseId → 只显示该性别半边（XY 存证开启 +
  /// 选择模式勾选单个半边时，聚焦折叠只圈选那个雄/雌，而不是整桶；
  /// 关闭 XY 存证时为空 Map = 维持整桶绑定）。
  final Map<String, PedigreeNodeKind> soloHalfIds;

  /// R18 画布锁：锁定后滚动平移/缩放、拖拽平移/捏合与缩放控件全部禁用，
  /// 此时按住家族横幅可整体拖动该家族（解决多家族遮挡）。
  final bool locked;

  /// R18 家族手动位移：家族编号 → 世界坐标偏移（页面持有，
  /// 布局时在分栏位置基础上叠加；连线随节点矩形自动跟随）。
  final Map<int, Offset> familyOffsets;

  /// v3.5 全屏：缩放条末尾的全屏按钮回调（页面 _openFullscreen。
  /// 全屏 Dialog 内传 null = 不渲染该按钮——退出走悬浮面板）。
  final VoidCallback? onFullscreenTap;

  /// R18 锁定开关（左上角缩放控件末尾的锁按钮）。
  final VoidCallback? onToggleLock;

  /// R18 家族拖动：上报世界坐标增量（已除缩放）。
  final void Function(int familyId, Offset worldDelta)? onFamilyDragDelta;

  /// R21 家族拖动结束（手指/鼠标抬起）：页面在本回调里把
  /// 「按下→抬起」记为一整条日志（起点→终点）。
  final VoidCallback? onFamilyDragEnd;

  const PedigreeCanvas({
    super.key,
    required this.nodes,
    required this.edges,
    this.selectedId,
    this.onNodeTap,
    this.onBlankTap,
    this.onWireDetach,
    this.armedId,
    this.flashIds = const {},
    this.dimIds = const {},
    this.showLineage = true,
    this.edgeStyle = PdEdgeStyle.orthogonal,
    this.showBackcross = true,
    this.hiddenBackcrossKeys = const {},
    this.onBlankSecondaryTap,
    this.onBlankLongPress,
    this.onNodeSecondaryTap,
    this.collapsedKeys = const {},
    this.hiddenCounts = const {},
    this.onToggleGen,
    this.sexLinked,
    this.familyLabels = const {},
    this.onNodeHalfTap,
    this.sexSplitView = false,
    this.pickedIds = const {},
    this.locked = false,
    this.familyOffsets = const {},
    this.onToggleLock,
    this.onFullscreenTap,
    this.onFamilyDragDelta,
    this.onFamilyDragEnd,
    this.connectedIds = const {},
    this.soloHalfIds = const {},
  });

  @override
  State<PedigreeCanvas> createState() => PedigreeCanvasState();
}

class PedigreeCanvasState extends State<PedigreeCanvas> {
  final TransformationController _viewCtrl = TransformationController();

  /// 测试挂钩：读取当前视图变换矩阵（缩放/平移断言用）。
  @visibleForTesting
  Matrix4 get debugTransform => _viewCtrl.value;

  /// v2.11 H4：生产路径用此 API。修复 `genetic_pedigree_page.dart`
  /// 生产代码调 `debugTransform`（标 @visibleForTesting）触发 analyze 警告
  /// `invalid_use_of_visible_for_testing_member`——公开包装避免删除
  /// debug* 字段时编译失败。语义与 debugTransform 完全一致。
  Matrix4 get contentTransform => _viewCtrl.value;

  /// 测试挂钩：家族编号 → 家族横幅命中矩形（世界坐标，R18 拖动测试用）。
  @visibleForTesting
  Map<int, Rect> get debugFamilyLabelRects => _familyLabelRects;

  /// v3.5 内容包围盒（世界坐标）：全部节点矩形并集（已含家族偏移）
  /// + 24px 留白。供页面做截图 ROI 裁剪（多模态问 AI 跳过空白区）。
  Rect debugContentRect() {
    if (_rects.isEmpty) return Rect.zero;
    var b = _rects.values.first;
    for (final r in _rects.values) {
      b = b.expandToInclude(r);
    }
    return b.inflate(24);
  }

  // ── 布局常量（世界坐标） ──────────────────────────────
  static const double kNodeSize = 64; // male 方块 / female 圆 直径
  static const double kGroupW = 128;
  static const double kGroupH = 60;
  static const double kGapX = 28; // 行内节点间距（网格布局收紧）
  static const double kRowGapY = 28; // 世代内多行之间的行距
  static const double kGenGapY = 120; // 世代之间的垂直间距
  static const double kPad = 80;

  /// 世代内每行最多节点数（超出则换行成网格，参考 d3-pedigree-tree 的
  /// 同胞组换行）。9 列 × 128px ≈ 1400px 世界宽，一屏可读。
  static const int kMaxCols = 9;

  // ── 多家族分栏（R14） ─────────────────────────────────
  static const double kFamilyGap = 140; // 家族栏之间的水平间隙
  static const double kFamilyPadX = 36; // 栏背景相对节点的水平外扩
  static const double kBannerH = 34; // 栏顶家族横幅高度

  static const double _minScale = 0.2;
  static const double _maxScale = 3.0;

  /// 世代 → 该代顶部世界 y（_computeLayout 时更新）。
  final Map<int, double> _genTop = {};

  Map<String, Rect> _rects = {};
  Size _worldSize = Size.zero;
  Size _viewportSize = Size.zero;
  Size _fittedFor = Size.zero;

  /// (家族:世代) 展开/收起 芯片的世界坐标矩形（_computeLayout 时更新）。
  Map<String, Rect> _chipRects = {};

  /// 家族编号 → 分栏背景矩形（_computeLayout 时更新，R14）。
  Map<int, Rect> _familyStripRects = {};

  /// 家族编号 → 横幅命中矩形（_computeLayout 时更新，R18 家族拖动）。
  Map<int, Rect> _familyLabelRects = {};

  /// R18 家族拖动：当前被拖拽的家族（null = 未在拖）。
  int? _dragFamily;

  /// R18：最近一次指针 down 的视口坐标（ScaleStart 触发时指针已越过
  /// touch slop，命中横幅必须用 down 时的精确起点，不能用手势触发点）。
  Offset? _downLocal;

  /// v2.22.1：当前按下的指针数 + 本轮触控是否出现过 ≥2 指。
  /// 双指轻点不该被当成点选（见 [_onTapUp]）。
  int _pointersDown = 0;
  bool _multiTouchSeen = false;

  // R12：连线改点选-点选，拖拽只负责平移（拖线/携线状态已移除）
  bool _panning = false;

  // 捏合手势起始缩放（onScale*：触屏双指 + Precision Touchpad）
  double _pinchStartScale = 1.0;

  /// 当前视口缩放（世界 1px = scale 屏幕 px）。
  double get _scale => _viewCtrl.value.getMaxScaleOnAxis();

  @override
  void dispose() {
    _viewCtrl.dispose();
    super.dispose();
  }

  // ── 世界坐标布局（R14 多家族分栏） ─────────────────────
  // 思维导图「森林」布局：每个家族 = 一棵独立树，横向各占一栏
  // （栏间 kFamilyGap），栏内按世代行网格（kMaxCols 换行、行内居中
  // 于栏）。世代仍全局水平对齐：同一代所有家族共享同一 y 区间，
  // 世代行高取跨家族最大值。单家族时与旧版逐像素一致（栏宽=内容宽）。
  void _computeLayout() {
    // 家族 → 世代 → 节点
    final famGen = <int, Map<int, List<PedigreeNode>>>{};
    var maxGen = 0;
    for (final n in widget.nodes) {
      // R15：组合桶渲染下 SPLIT 半桶不单独占位（由父桶内 glyph 代表）
      if (widget.sexSplitView && n.id.startsWith('SPLIT#')) continue;
      famGen
          .putIfAbsent(n.familyId, () => {})
          .putIfAbsent(n.generation, () => [])
          .add(n);
      if (n.generation > maxGen) maxGen = n.generation;
    }
    final famIds = famGen.keys.toList()..sort();

    double widthOf(PedigreeNode n) =>
        n.kind == PedigreeNodeKind.group ? kGroupW : kNodeSize;
    double heightOf(PedigreeNode n) =>
        n.kind == PedigreeNodeKind.group ? kGroupH : kNodeSize;

    // 一组节点按 kMaxCols 折行后的网格宽/高
    double gridW(List<PedigreeNode> list) {
      final cols = list.length > kMaxCols ? kMaxCols : list.length;
      var w = 0.0;
      for (var i = 0; i < cols; i++) {
        w += widthOf(list[i]);
      }
      return w + kGapX * (cols - 1);
    }

    double gridH(List<PedigreeNode> list) {
      final rows = (list.length + kMaxCols - 1) ~/ kMaxCols;
      final rowH = list.map(heightOf).reduce(math.max);
      return rows * rowH + (rows - 1) * kRowGapY;
    }

    // 栏宽 = 该家族各世代网格宽的最大值
    final stripW = <int, double>{};
    for (final f in famIds) {
      var w = kNodeSize;
      famGen[f]!.forEach((_, list) {
        final gw = gridW(list);
        if (gw > w) w = gw;
      });
      stripW[f] = w;
    }

    // 世代高度 = 跨家族该代最大网格高度
    final genH = <int, double>{};
    for (var g = 0; g <= maxGen; g++) {
      var h = kNodeSize;
      for (final f in famIds) {
        final list = famGen[f]![g];
        if (list == null) continue;
        final gh = gridH(list);
        if (gh > h) h = gh;
      }
      genH[g] = h;
    }

    // 可折叠 (家族:世代) 芯片：hiddenCounts 全量出矩形，不做折叠/选中过滤。
    // 早先为了少遮挡，只在「折叠中 ∪ 选中组」才出芯片（展开未选中直接
    // 不画不命中）——代价是展开成了单向操作：展开后画布上没有任何可点的
    // 收起入口，用户实测「展开了就回不去」。现全部保留，靠 painter 分形态：
    //   · 折叠且未选中 → 小徽标「+N 种基因型」+ 下三角
    //   · 展开且未选中 → 小徽标「收起」+ 上三角（收起入口）
    //   · 选中（折叠或展开）→ 大胶囊（104×34）
    final chipKeys = widget.hiddenCounts.keys.toSet();
    // 世界宽度余量按 hiddenCounts 全量预留（不随选中态收缩）——否则
    // chipKeys 随选中变化会让 worldW 跳动，画布布局抖。
    final chipExtra = widget.hiddenCounts.isEmpty ? 0.0 : 132.0;

    // 栏 x：kPad 起逐栏排列，栏间 kFamilyGap
    final stripX = <int, double>{};
    var x = kPad;
    for (var i = 0; i < famIds.length; i++) {
      stripX[famIds[i]] = x;
      x += stripW[famIds[i]]! + (i == famIds.length - 1 ? 0 : kFamilyGap);
    }
    final worldW = x + kPad + chipExtra;

    // 世代垂直位置：累计上一世代高度 + 世代间距
    final genTop = <int, double>{};
    var y = kPad;
    for (var g = 0; g <= maxGen; g++) {
      genTop[g] = y;
      y += genH[g]! + kGenGapY;
    }
    final worldH = y - kGenGapY + kPad; // 末代底部 + 下边距

    final rects = <String, Rect>{};
    // R26/R27：chip 位置在家族偏移后派生（见下方），此处仅声明
    final chipRects = <String, Rect>{};
    final stripRects = <int, Rect>{};
    for (final f in famIds) {
      final x0 = stripX[f]!;
      final sw = stripW[f]!;
      double? topY;
      double? botY;
      famGen[f]!.forEach((gen, list) {
        final cols = list.length > kMaxCols ? kMaxCols : list.length;
        final rows = (list.length + kMaxCols - 1) ~/ kMaxCols;
        final rowH = list.map(heightOf).reduce(math.max);
        for (var i = 0; i < list.length; i++) {
          final n = list[i];
          final col = i % cols;
          final row = i ~/ cols;
          final w = widthOf(n);
          final h = heightOf(n);
          // 行内居中于栏（单家族时等价于旧版的居中于内容宽）
          final rowCount = row == rows - 1 ? list.length - row * cols : cols;
          var rw = 0.0;
          for (var j = 0; j < rowCount; j++) {
            rw += widthOf(list[row * cols + j]);
          }
          rw += kGapX * (rowCount - 1);
          final rowX0 = x0 + (sw - rw) / 2;
          // 行内逐节点 x：累加前序节点宽度+间距
          var nx = rowX0;
          for (var j = 0; j < col; j++) {
            nx += widthOf(list[row * cols + j]) + kGapX;
          }
          final cy = genTop[gen]! + row * (rowH + kRowGapY) + rowH / 2;
          rects[n.id] = Rect.fromCenter(
              center: Offset(nx + w / 2, cy), width: w, height: h);
        }
        final gTop = genTop[gen]!;
        final gBot = gTop + gridH(list);
        topY = topY == null ? gTop : math.min(topY!, gTop);
        botY = botY == null ? gBot : math.max(botY!, gBot);
      });
      if (topY != null) {
        // 栏背景：顶部为横幅留位（kBannerH+8），底部外扩 16
        stripRects[f] = Rect.fromLTRB(x0 - kFamilyPadX, topY! - kBannerH - 8,
            x0 + sw + kFamilyPadX, botY! + 16);
      }
    }
    // R18 家族手动位移：锁定时用户拖动家族横幅得到的偏移，叠加到该
    // 家族所有节点矩形 + 分栏矩形上（连线端点取自这些矩形，自动跟随；
    // 其他家族一律不动）。世界尺寸按正向外扩，防止拖出右/下缘被裁。
    final labelRects = <int, Rect>{};
    var extraW = 0.0, extraH = 0.0;
    if (widget.familyOffsets.isNotEmpty) {
      final nodeFam = {for (final n in widget.nodes) n.id: n.familyId};
      widget.familyOffsets.forEach((f, off) {
        if (off == Offset.zero) return;
        final sr = stripRects[f];
        if (sr != null) stripRects[f] = sr.shift(off);
        for (final entry in nodeFam.entries) {
          if (entry.value != f) continue;
          final r = rects[entry.key];
          if (r != null) rects[entry.key] = r.shift(off);
        }
        if (off.dx > extraW) extraW = off.dx;
        if (off.dy > extraH) extraH = off.dy;
      });
    }
    // R27：chip 位置从「偏移后」的家族分栏与节点矩形派生——每个
    // (家族:世代) 的芯片贴在该家族该代行的实际垂直区间（y 中点），
    // x 在该家族分栏右缘外侧（栏间/右缘预留区）。家族拖动后 rects/
    // strips 已偏移 → 芯片自动跟随家族方块，不再乱飘。
    for (final key in chipKeys) {
      final fg = key.split(':');
      final f = int.tryParse(fg[0]) ?? 0;
      final gen = int.tryParse(fg[1] ?? '') ?? 0;
      final strip = stripRects[f];
      if (strip == null) continue;
      double? topY;
      double? botY;
      for (final n in widget.nodes) {
        if (n.familyId != f || n.generation != gen) continue;
        final r = rects[n.id];
        if (r == null) continue;
        topY = topY == null ? r.top : math.min(topY!, r.top);
        botY = botY == null ? r.bottom : math.max(botY!, r.bottom);
      }
      if (topY == null) continue;
      // 贴住本栏右缘（不再额外 +8）：芯片右缘 = strip.right + 104，正好等于
      // 相邻家族最左节点列的 x（栏间距 140 - 栏内边距 36），多 8px 会压到
      // 下一个家族最左节点的左边框。
      var cx = strip.right + 52;
      if (cx > worldW + extraW - kPad * 0.5) {
        cx = worldW + extraW - kPad * 0.5 - 52;
      }
      chipRects[key] = Rect.fromCenter(
          center: Offset(cx, (topY! + botY!) / 2),
          width: 104,
          height: 34);
    }
    // 横幅命中矩形：分栏顶部 kBannerH 横带（painter 的胶囊在此区域内）
    stripRects.forEach((f, r) {
      labelRects[f] =
          Rect.fromLTRB(r.left, r.top, r.right, r.top + kBannerH);
    });

    _rects = rects;
    _chipRects = chipRects;
    _familyStripRects = stripRects;
    _familyLabelRects = labelRects;
    _genTop
      ..clear()
      ..addAll(genTop);
    _worldSize = Size(worldW + extraW, worldH + extraH);
  }

  /// v2.19.13（老师验证 🟡3）：世代推断改基于节点实际渲染位置——
  /// 原实现用 _genTop（未加 familyOffsets 的网格线），家族垂直拖动后
  /// （R22 支持各家族独立 y 位置）空白处推断错位。现从 _rects（已含
  /// familyOffsets）按世代聚合节点中心 y、取中位数为该代代表位置，
  /// 空白点归到最近世代中心。O(n) 每次右键/长按，n 为节点数无感。
  int _genAtSceneY(double sceneY) {
    final byGen = <int, List<double>>{};
    for (final n in widget.nodes) {
      final r = _rects[n.id];
      if (r == null) continue;
      byGen.putIfAbsent(n.generation, () => []).add(r.center.dy);
    }
    if (byGen.isEmpty) return 0;
    var best = 0;
    var bestDist = double.infinity;
    byGen.forEach((g, ys) {
      ys.sort();
      final c = ys[ys.length ~/ 2];
      final d = (sceneY - c).abs();
      if (d < bestDist) {
        bestDist = d;
        best = g;
      }
    });
    return best;
  }

  /// 初始/尺寸变化时适配：缩放至全部可见并居中（手法同 knowledge_graph_page）。
  /// R20：家族拖动中（familyOffsets 非空）跳过——拖拽导致 worldSize
  /// 外扩会触发 re-fit，画面整体跳变，必须屏蔽。
  /// v2.19.15（DeepSeek 找茬 🟡6）：[force] = 用户点「适应视图」按钮——
  /// 跳过 R20 的 familyOffsets 短路（那次拖动后自动适配永久关闭，新
  /// 家族/新世代可能落在视口外且无入口回来）。
  void _fitToView({bool force = false}) {
    if (!force && widget.familyOffsets.isNotEmpty) return;
    if (force) _fittedFor = Size.zero; // 强制重新计算（即使世界尺寸没变）
    // v2.19.26（平板 F-3）：re-fit 触发键去掉「视口高度」——底部详情条
    // 随选中在 ~46↔156 间变化（纯高度变化），旧键会把一次「点选节点」
    // 误判为视口变化、把学生手动缩放/平移一把拉回适配视图。旋转必
    // 变宽度（→键变→refit ✓）；世界尺寸变化（新一代/新家族）也必变。
    // 纯高度变化（详情条/键盘）不再触发。
    final key = Size(_worldSize.width + _viewportSize.width, _worldSize.height);
    if (key == _fittedFor || _worldSize == Size.zero) return;
    _fittedFor = key;
    final scale = math
        .min(_viewportSize.width / _worldSize.width,
            _viewportSize.height / _worldSize.height)
        .clamp(_minScale, 1.0);
    final dx = (_viewportSize.width - _worldSize.width * scale) / 2;
    final dy = (_viewportSize.height - _worldSize.height * scale) / 2;
    _viewCtrl.value = Matrix4.identity()
      ..translateByDouble(dx, dy, 0, 1)
      ..scaleByDouble(scale, scale, scale, 1);
  }

  /// 点选最小触控尺寸（屏幕 px）：教室大触控屏上单指/双指都要点得中，
  /// 命中区按屏幕尺寸补到 48×48（与全局 48/52px 触控约定同口径，
  /// 见 whiteboard_touch_test）。
  static const double _kTapHitMinScreen = 48;

  /// 指腹抖动容错（屏幕 px）：节点身体外再留 10px，斜着点也不落空。
  static const double _kTapFuzzScreen = 10;

  /// 命中节点：矩形外扩命中 + 圆心最近决胜。
  /// v2.18 R8 学生走查 #1：旧实现用「圆心距 ≤ 40/scale」——放大后
  /// 节点身体远大于命中圆，点身体外缘直接落空（点选/连线/收线全
  /// 受影响）。改为 rect.inflate(10 屏幕px→世界单位)：命中区贴着
  /// 可视身体走，任何缩放下一致；外扩重叠区（密集网格的窄缝）仍
  /// 由圆心最近保证稳定指向真正近的那个。
  /// v2.22 大屏触控加固（2026-10-27）：10 屏幕 px 容错在缩到 0.2 时只有
  /// 12.8+20≈33 屏幕 px，手指点不中（R1 点选-点选连线的第一下就丢）。
  /// 现按较窄边把整块命中区补到 [_kTapHitMinScreen]（48px），再取 10px
  /// 容错与补足量的较大者；密集区仍由圆心最近决胜，坐标/Painter 不变。
  /// [precise] = 长按/精确场景（v2.19.13 老师找茬 🔴3）：外扩仅
  /// [inflate] 世界 px，不用点击容错、也不补 48px——缩小画布后节点
  /// 间隙不被侵入，空白长按才走得到。
  PedigreeNode? _hitNode(Offset scenePos,
      {double inflate = 0, bool precise = false}) {
    final fuzz = math.max(inflate, _kTapFuzzScreen / _scale);
    PedigreeNode? best;
    var bestD = double.infinity;
    for (final n in widget.nodes) {
      final r = _rects[n.id];
      if (r == null) continue;
      // 每节点单独算：组合桶 128×60 与普通节点 64×64 的短边不同，
      // 补足量必须按各自短边算，才能都达到 48 屏幕 px。
      final grow = precise
          ? inflate
          : math.max(
              fuzz,
              (_kTapHitMinScreen - math.min(r.width, r.height) * _scale) /
                  2 /
                  _scale);
      if (!r.inflate(grow).contains(scenePos)) continue;
      final d = (r.center - scenePos).distance;
      if (d < bestD) {
        bestD = d;
        best = n;
      }
    }
    return best;
  }

  /// 组合桶半边判定（R15）：命中组合桶时按 x 位置分半（左雄右雌）。
  /// 非组合渲染 / 非桶节点返回 null（走整节点 onNodeTap）。
  PedigreeNodeKind? _halfAt(PedigreeNode n, Offset scenePos) {
    if (!widget.sexSplitView) return null;
    if (n.kind != PedigreeNodeKind.group) return null;
    final r = _rects[n.id];
    if (r == null) return null;
    return scenePos.dx < r.center.dx
        ? PedigreeNodeKind.male
        : PedigreeNodeKind.female;
  }

  /// v2.19.16（DeepSeek 找茬 🔴1）：画布局部坐标 → **overlay 坐标**。
  /// showMenu 的 RelativeRect 语义是 overlay 坐标系（框架 PopupMenuButton
  /// 自己走 localToGlobal(ancestor: overlay)）；原实现直接塞画布局部
  /// 坐标 → 内嵌页菜单弹在离光标 (353,52)（课堂 385,52）的错位处，
  /// 全屏 Dialog 因画布原点=(0,0) 恰好正确所以一直没暴露。
  Offset _toMenuPos(Offset local) {
    final box = context.findRenderObject()! as RenderBox;
    final overlay =
        Overlay.of(context).context.findRenderObject()! as RenderBox;
    return box.localToGlobal(local, ancestor: overlay);
  }

  /// 命中 (家族:世代) 展开/收起 芯片。
  String? _hitGenChip(Offset scenePos) {
    String? best;
    var bestDist = double.infinity;
    for (final entry in _chipRects.entries) {
      final r = entry.value;
      // v2.19.11（老师走查 H5 半程方案）：命中区按屏幕尺寸钳制——
      // chip 是世界坐标绘制，画布缩小后屏幕命中区跟着缩（缩放 0.4 时
      // 总高约 37 屏幕 px，手指点不中）。垂直方向补到屏幕命中 ≥48px
      // （触控下限），水平 ±16 屏幕 px。
      // v2.23.1（2026-11-03 徽标交互优化）：命中区硬下限 40×40 逻辑
      // 像素。撤销 v2.19.12 的「扩展量封顶一个 chip 高」——那会把
      // 0.2 缩放下的屏幕命中压到 ~20px；低缩放偷点相邻代的风险由
      // _hitAnyNodeBody 身体优先裁决兜底。
      final extraWorldH =
          math.max(0.0, (48.0 - r.height * _scale) / 2 / _scale);
      final hit = Rect.fromCenter(
        center: r.center,
        width: math.max(r.width + 32 / _scale, 40.0 / _scale),
        height: math.max(r.height + 2 * extraWorldH, 40.0 / _scale),
      );
      if (!hit.contains(scenePos)) continue;
      // 低缩放下命中区按屏幕 48px 反算世界宽（0.2 缩放约 260 世界 px），
      // 相邻家族的芯片命中区会重叠——取中心离点击点最近的一个，而不是
      // 遍历顺序里的第一个（否则点 B 家族的芯片可能展开 A 家族）。
      final d = (scenePos - r.center).distanceSquared;
      if (d < bestDist) {
        bestDist = d;
        best = entry.key;
      }
    }
    return best;
  }

  // ── 手势（R9 + R4 + R1 + R3） ─────────────────────────

  /// 滚动输入=二维平移；Ctrl/Meta+滚轮=以光标为锚缩放。
  ///
  /// 鸿合等 Windows 白板可能把触摸手势转成滚轮，而不是原生触点。
  /// 统一把滚动解释为平移后，无论应用收到物理滚轮还是驱动映射事件，
  /// 都不会在用户想移动画布时意外缩放。原生单/双指仍走 onScale。
  void _onPointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent) return;
    if (widget.locked) return; // R18：锁定画布时滚动平移/缩放均禁用
    if (canvasZoomModifierPressed) {
      // 横向滚动没有缩放语义；Web 触控板捏合的 wheel+ctrl 也走这里。
      if (event.scrollDelta.dy == 0) return;
      // 指数曲线兼容鼠标整格与触控板细滚，避免一滑直接顶到限位。
      final current = _scale;
      final factor = math.exp(-event.scrollDelta.dy * 0.001);
      _zoomAt(event.localPosition, current * factor);
      return;
    }
    if (event.scrollDelta == Offset.zero) return;
    setState(() {
      _viewCtrl.value = canvasPanAfterScroll(_viewCtrl.value, event.scrollDelta);
    });
  }

  /// 以视口坐标 [anchor] 为不动点缩放到 [next]。
  void _zoomAt(Offset anchor, double next) {
    final current = _scale;
    next = next.clamp(_minScale, _maxScale);
    if (next == current) return;
    final sceneAnchor = _viewCtrl.toScene(anchor);
    final scale = next / current;
    setState(() {
      _viewCtrl.value = _viewCtrl.value.clone()
        ..translateByDouble(sceneAnchor.dx, sceneAnchor.dy, 0, 1)
        ..scaleByDouble(scale, scale, scale, 1)
        ..translateByDouble(-sceneAnchor.dx, -sceneAnchor.dy, 0, 1);
    });
  }

  /// R12 点选-点选连线：点按只上报命中结果，「待命→连线」状态机在页面层。
  /// 点节点=onNodeTap（页面决定 待命/连线/解除），点空白=onBlankTap。
  void _onTapUp(TapUpDetails d) {
    // v2.22.1（2026-10-27 复核）：双指轻点（两指按下即抬、无位移）时
    // ScaleGestureRecognizer 还没越过 slop，竞技场判给 TapGestureRecognizer
    // → 会误报一次点选（教室大屏上两指顺手碰一下很常见，等于凭空配对）。
    // 本轮触控出现过 ≥2 指就不算点选；单指路径完全不变。
    if (_multiTouchSeen) return;
    final scene = _viewCtrl.toScene(d.localPosition);
    final node = _hitNode(scene);
    final chip = _hitGenChip(scene);
    // v2.22.1 低缩放冲突裁决（2026-10-27 复核）：节点命中区补到 48 屏幕
    // px 后，0.2 缩放下会盖住世代芯片左侧约 42%（芯片左缘距节点右缘仅
    // 44 世界 px）。裁决按「点是否落在节点**实际身体**里」分两档：
    //   · 点在任一节点可视 body 内 → 仍节点优先（v2.19.15 防的是芯片
    //     扩区偷节点身体，这条防线不能丢）；
    //   · 节点只是靠 48px 外扩命中 → 芯片优先（低缩放时用户想点的
    //     多半是栏右缘那枚芯片，而不是 12px 见方的节点）。
    if (chip != null && !_hitAnyNodeBody(scene)) {
      widget.onToggleGen?.call(chip);
      return;
    }
    if (node != null) {
      // R15：组合桶按点击位置拆成雄/雌半边上报（页面合成 id 处理）
      final half = _halfAt(node, scene);
      if (half != null && widget.onNodeHalfTap != null) {
        widget.onNodeHalfTap!(node, half);
      } else {
        widget.onNodeTap?.call(node);
      }
      return;
    }
    widget.onBlankTap?.call();
  }

  /// 点是否落在任一节点的**可视身体**内（无外扩）——只用于芯片/节点
  /// 冲突裁决，不影响 `_hitNode` 的最近圆心决胜。
  bool _hitAnyNodeBody(Offset scenePos) {
    for (final n in widget.nodes) {
      final r = _rects[n.id];
      if (r != null && r.contains(scenePos)) return true;
    }
    return false;
  }

  /// 长按节点 = 收回该节点最近一条连线（移动端没有右键，收线走这里）；
  /// v2.19.10：长按空白 = 弹快捷菜单（添加家族/样本/下一代，同右键），
  /// 触屏上不再依赖右键键码。
  /// v2.19.13（老师找茬 🔴3）：长按命中用精确模式（2 屏幕 px 容错）——
  /// 原 _hitNode 默认 10/scale 世界 px 外扩，缩放 0.2 时外扩 50 世界
  /// px，节点间隙 28 全被侵入 → 缩小画布后长按永远命中节点、空白
  /// 菜单路径被堵死。长按是"已定位"手势，不需点击容错。
  void _onLongPressStart(LongPressStartDetails d) {
    // v2.22.1（2026-10-27 二次复核）：双指静置 ≥500ms 会让长按识别器
    // 收线/弹空白菜单（教室里手搭在屏上说话就会误触）。多指时不算长按；
    // 单指路径不受影响，也和捏合不冲突。
    if (_multiTouchSeen) return;
    final scene = _viewCtrl.toScene(d.localPosition);
    final node = _hitNode(scene, inflate: 2 / _scale, precise: true);
    if (node != null) {
      widget.onWireDetach?.call(node);
      return;
    }
    final gen = _genAtSceneY(scene.dy);
    widget.onBlankLongPress?.call(gen, _toMenuPos(d.localPosition));
  }

  void _onSecondaryTapUp(TapUpDetails d) {
    final scene = _viewCtrl.toScene(d.localPosition);
    // v2.22.1（2026-10-27 复核）：右键/触控板菜单同长按一样是「已定位」
    // 手势，用精确命中（2 屏幕 px 容错）——否则缩小到 0.2 后 48px 点选
    // 命中区会把空白右键挤成节点菜单，空白处加样本/家族的入口被堵。
    final node = _hitNode(scene, inflate: 2 / _scale, precise: true);
    if (node != null) {
      widget.onNodeSecondaryTap?.call(node, _toMenuPos(d.localPosition));
      return;
    }
    // 空白：按 y 坐标推断世代行（R3）
    final gen = _genAtSceneY(scene.dy);
    widget.onBlankSecondaryTap?.call(gen, _toMenuPos(d.localPosition));
  }

  void _onPointerDown(PointerDownEvent e) {
    _downLocal = e.localPosition;
    // 只有「新一轮的第一根指针」才复位多指标记：双指手势各自的 up 与
    // recognizer 回调顺序不可假定（见 [_onPointerUpOrCancel]）。
    if (_pointersDown == 0) _multiTouchSeen = false;
    _pointersDown++;
    if (_pointersDown >= 2) _multiTouchSeen = true;
  }

  /// 指针抬起/取消：**只递减计数，不清 [_multiTouchSeen]**。
  /// Flutter 派发顺序：hit-test path 里的 RenderPointerListener 先收到 up，
  /// GestureBinding 最后才 pointerRouter.route(up) → TapGestureRecognizer
  /// ._checkUp。若在这里按「计数归零」清标志，「次指先抬、主指后抬」时
  /// 主指的 onTapUp 会读到已清的标志 → 双指轻点仍被误判成点选。
  /// 标志改由下一轮首指 down 复位，覆盖整轮直到最后一根指针的 recognizer
  /// 回调结束。
  void _onPointerUpOrCancel(PointerEvent _) {
    if (_pointersDown > 0) _pointersDown--;
  }

  /// Scale 手势是 Pan 的超集：单指/鼠标拖 = scale 恒 1 + focalPointDelta；
  /// 触屏双指捏合与 Precision Touchpad 捏合（PointerPanZoom 序列）都会
  /// 自动接入 ScaleGestureRecognizer —— 三类输入一套代码。
  /// R12：拖拽一律平移（连线走点选-点选，不再从节点拖线）。
  /// R18：锁定画布时不平移/不捏合；按住家族横幅 = 整体拖动该家族。
  void _onScaleStart(ScaleStartDetails d) {
    if (widget.locked) {
      // 命中判定用指针 down 起点（ScaleStart 触发时已越过 slop，
      // focalPoint 不在原地，会脱离窄横幅）
      final scene = _viewCtrl.toScene(_downLocal ?? d.localFocalPoint);
      for (final entry in _familyLabelRects.entries) {
        if (entry.value.inflate(12 / _scale).contains(scene)) {
          _dragFamily = entry.key;
          return;
        }
      }
      _panning = false; // 锁定且未命中横幅：拖拽什么都不做
      return;
    }
    _pinchStartScale = _scale;
    _panning = true;
  }

  void _onScaleUpdate(ScaleUpdateDetails d) {
    // R18 家族拖动：只移动被按住的那个家族（世界增量 = 屏幕增量/缩放）
    final dragFam = _dragFamily;
    if (widget.locked) {
      if (dragFam != null && d.scale == 1.0) {
        widget.onFamilyDragDelta
            ?.call(dragFam, d.focalPointDelta / _scale);
      }
      return;
    }
    if (!_panning) return;
    setState(() {
      // 平移（单指拖 / 触控板双指滚 = focalPointDelta）。左乘屏幕
      // 位移，低缩放下手指移多少、画布就移多少，不再被倍率二次缩小。
      _viewCtrl.value =
          canvasPanByScreenDelta(_viewCtrl.value, d.focalPointDelta);
    });
    // 捏合缩放（d.scale 是本手势累计缩放；单指拖时恒为 1）
    if (d.scale != 1.0) {
      _zoomAt(d.localFocalPoint, _pinchStartScale * d.scale);
    }
  }

  void _onScaleEnd(ScaleEndDetails d) {
    final wasDraggingFamily = widget.locked && _dragFamily != null;
    _panning = false;
    _dragFamily = null;
    _downLocal = null;
    // R21：按下→抬起算一次家族拖动，结束回调让页面记日志（起点→终点）
    if (wasDraggingFamily) widget.onFamilyDragEnd?.call();
  }

  /// R16 缩放控件（左上角）：－ / 滑块 / ＋ + 百分比，作用等同滚轮
  /// 缩放——手机端没有滚轮/捏合不便时用。锚点取视口中心。
  Widget _buildZoomBar() {
    final center = _viewportSize.center(Offset.zero);
    return Container(
      key: const Key('pedigree-zoom-bar'),
      decoration: BoxDecoration(
        color: AppColors.overlayBar,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border),
        boxShadow: AppColors.cardShadow,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: const Icon(Icons.remove, size: 18),
            tooltip: '缩小',
            onPressed:
                widget.locked ? null : () => _zoomAt(center, _scale / 1.25),
          ),
          SizedBox(
            width: 110,
            child: Slider(
              value: _scale,
              min: _minScale,
              max: _maxScale,
              onChanged: widget.locked ? null : (v) => _zoomAt(center, v),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.add, size: 18),
            tooltip: '放大',
            onPressed:
                widget.locked ? null : () => _zoomAt(center, _scale * 1.25),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 4),
            child: Text('${(_scale * 100).round()}%',
                style: AppText.monoSmall.copyWith(fontSize: 11)),
          ),
          // R18 画布锁：锁定后禁缩放/平移，解锁家族横幅整体拖动
          IconButton(
            icon: Icon(
                widget.locked ? Icons.lock : Icons.lock_open,
                size: 18,
                color: widget.locked ? AppColors.armed : AppColors.steel),
            tooltip: widget.locked ? '解锁画布（恢复缩放/平移）' : '锁定画布：可拖动家族横幅',
            onPressed: widget.onToggleLock,
          ),
          // v2.3 课堂模式：聚光灯开关（仅课堂模式显示；会话级，
          // 画布整体压暗、亮区跟随手指——白板讲课聚焦注意力）。
          ListenableBuilder(
            listenable: PresentModeController.instance,
            builder: (context, _) {
              if (!PresentModeController.instance.enabled) {
                return const SizedBox.shrink();
              }
              final on = PresentModeController.instance.spotlightOn;
              return IconButton(
                icon: Icon(
                    on ? Icons.highlight : Icons.highlight_outlined,
                    size: 18,
                    color: on ? AppColors.armed : AppColors.steel),
                tooltip: on ? '关闭聚光灯' : '聚光灯：亮区跟随手指，其余压暗',
                onPressed: () =>
                    PresentModeController.instance.setSpotlightOn(!on),
              );
            },
          ),
          // v2.19.15（DeepSeek 找茬 🟡6）：「适应视图」——拖动过一次
          // 家族后自动适配被 R20 短路永久关闭（防拖动中跳变），新内
          // 容可能落在视口外且无入口。此按钮强制重新适配全系谱。
          IconButton(
            icon: Icon(Icons.fit_screen_outlined,
                size: 18, color: AppColors.graphite),
            tooltip: '适应视图：缩放平移回到全系谱可见',
            onPressed: () => _fitToView(force: true),
          ),
          // v3.5 全屏：与缩放/锁并列（用户裁定：全屏不放画布本身，
          // 而是与「调节放大倍率」「锁定画布」同排）。
          if (widget.onFullscreenTap != null)
            IconButton(
              icon: const Icon(Icons.fullscreen, size: 18),
              tooltip: '全屏',
              onPressed: widget.onFullscreenTap,
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (ctx, constraints) {
        _viewportSize = Size(constraints.maxWidth, constraints.maxHeight);
        _computeLayout();
        _fitToView();
        return Stack(
          // expand：让手势层撑满视口——loose 下 Listener 只有世界尺寸大，
          // 视口其余空白区收不到滚轮/拖拽（滚轮缩放测试复现确认）。
          fit: StackFit.expand,
          children: [
            Listener(
          onPointerDown: _onPointerDown,
          onPointerUp: _onPointerUpOrCancel,
          onPointerCancel: _onPointerUpOrCancel,
          onPointerSignal: _onPointerSignal,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapUp: _onTapUp,
            onSecondaryTapUp: _onSecondaryTapUp,
            onLongPressStart: _onLongPressStart,
            // 注：长按 500ms 时延定制（老师走查 🟡5）需 RawGestureDetector
            //  recognizer 层实现——GestureDetector 无公开 longPressDuration
            //  参数，本轮不引复杂度，留下轮。
            onScaleStart: _onScaleStart,
            onScaleUpdate: _onScaleUpdate,
            onScaleEnd: _onScaleEnd,
            // R11：弃用 InteractiveViewer——它内部常驻 GestureDetector 会在
            // 手势竞技场里以「最内层」身份抢走所有指针事件，即使 pan/scale
            // 被禁用（widget 测试双指捏合复现确认）。改为 ClipRect+Transform
            // 自管变换：GestureDetector 是唯一手势消费者，捏合/拖线/点按
            // 全部可达；矩阵仍由 _viewCtrl 统一维护。
            child: ClipRect(
              child: Transform(
                transform: _viewCtrl.value,
                child: CustomPaint(
                  size: _worldSize,
                  painter: PedigreePainter(
                    nodes: widget.nodes,
                    edges: widget.edges,
                    rects: _rects,
                    selectedId: widget.selectedId,
                    viewTransform: _viewCtrl.value,
                    viewportSize: _viewportSize,
                    collapsedKeys: widget.collapsedKeys,
                    hiddenCounts: widget.hiddenCounts,
                    genChipRects: _chipRects,
                    genTop: _genTop,
                    sexLinked: widget.sexLinked,
                    armedId: widget.armedId,
                    flashIds: widget.flashIds,
                    dimIds: widget.dimIds,
                    showLineage: widget.showLineage,
                    edgeStyle: widget.edgeStyle,
                    showBackcross: widget.showBackcross,
                    hiddenBackcrossKeys: widget.hiddenBackcrossKeys,
                    familyStripRects: _familyStripRects,
                    familyLabels: widget.familyLabels,
                    sexSplitView: widget.sexSplitView,
                    pickedIds: widget.pickedIds,
                    connectedIds: widget.connectedIds,
                    soloHalfIds: widget.soloHalfIds,
                  ),
                ),
              ),
            ),
          ),
            ),
            // R16：缩放控件——v2.18 R8 下沉画布左下（白板可达；原
            // 左上角几米白板够不到，且会压住家族横幅角）。
            Positioned(
              left: 10,
              bottom: 44,
              child: _buildZoomBar(),
            ),
            // v2.3 课堂模式：激光笔层（跟随指针的红色光点+渐隐轨迹，
            // 白板讲课引导全班视线；课堂模式内可单独开关，
            // 完全关闭时零开销不挂载）。
            ListenableBuilder(
              listenable: PresentModeController.instance,
              builder: (context, _) =>
                  PresentModeController.instance.enabled &&
                          PresentModeController.instance.laserEnabled
                      ? const Positioned.fill(child: LaserPointerLayer())
                      : const SizedBox.shrink(),
            ),
            // v2.3 课堂模式：聚光灯层（画布整体压暗、亮区跟随手指；
            // 课堂模式 + 缩放条开关双条件；translucent 旁听不挡手势）。
            ListenableBuilder(
              listenable: PresentModeController.instance,
              builder: (context, _) => Positioned.fill(
                child: SpotlightLayer(
                  active: PresentModeController.instance.enabled &&
                      PresentModeController.instance.spotlightOn,
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
