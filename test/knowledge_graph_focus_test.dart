// knowledge_graph_focus_test.dart —— v2.21.0 知识图谱「焦点连线」验收
//
// 需求（B 项）：新增**独立** selectedNodeId（不复用「先修补课」的
// _focusedNodeId）：
//   首次点节点 ⇒ 选中 + 开原详情；再点当前节点 ⇒ 只收镜头、不重复弹
//   sheet；点空白 ⇒ 清除。debugShowDetail 与真实点击同源（同步 selected），
//   保留原 bottom Sheet 与测试钩子。
//
// 绘制侧只做视觉降权，不动布局/路由：
//   常态 先修 1.7px/0.34、关联 1.1px/0.22；选中 一跳全强度、相关边
//   2.6px/0.92 且最后绘制、非相关边 0.08、非相关节点 0.45 权重仍在；
//   搜索 highlighted 与 weaknessStroke 不被覆盖；通道错峰由 from/to/kind
//   稳定派生（过滤不换道）。分层坐标/节点位置逐点不变（不换力导向）。

import 'package:biology/engine/knowledge_graph.dart';
import 'package:biology/pages/knowledge_graph_page.dart';
import 'package:biology/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(() {
    // 深/浅 token 确定性（本测试锁定浅色，只断言结构与常量）。
    AppColors.sync(Brightness.light);
  });

  tearDown(() {
    AppColors.debugClearOverride();
  });

  /// 泵图谱页（大视口：世界坐标 1:1 全可见，点节点不必额外平移）。
  Future<dynamic> pumpGraph(
    WidgetTester t, {
    void Function(int navIndex)? onOpenTool,
  }) async {
    t.view.physicalSize = const Size(1600, 1400);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    await t.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: KnowledgeGraphPage(onOpenTool: onOpenTool),
      ),
    );
    await t.pumpAndSettle();
    return t.state(find.byType(KnowledgeGraphPage));
  }

  Finder graphPaint() => find.byWidgetPredicate(
    (w) => w is CustomPaint && w.painter is KnowledgeGraphPainter,
  );

  KnowledgeGraphPainter painterOf(WidgetTester t) =>
      t.widget<CustomPaint>(graphPaint().first).painter!
          as KnowledgeGraphPainter;

  /// 点画布上的某个节点（世界坐标 → 屏幕坐标，走真实 tapUp 路径）。
  Future<void> tapNode(WidgetTester t, String nodeId) async {
    final pos = painterOf(t).positions[nodeId];
    expect(pos, isNotNull, reason: '$nodeId 不在当前画布（被搜索过滤？）');
    final box = t.renderObject<RenderBox>(graphPaint().first);
    final world = Offset(
      pos!.dx + KnowledgeGraphPainter.nodeW / 2,
      pos.dy + KnowledgeGraphPainter.nodeH / 2,
    );
    await t.tapAt(box.localToGlobal(world));
    await t.pumpAndSettle();
  }

  /// 点画布空白（世界底部中央）。阅读优先会裁掉世界左右两侧，
  /// 旧「左下角」可能已出视口；底部中央仍在屏内且位于末排节点之外。
  Future<void> tapBlank(WidgetTester t) async {
    final box = t.renderObject<RenderBox>(graphPaint().first);
    await t.tapAt(
      box.localToGlobal(Offset(box.size.width / 2, box.size.height - 5)),
    );
    await t.pumpAndSettle();
  }

  /// 关掉详情 sheet（点模态遮罩），选中态应保留。
  Future<void> dismissSheet(WidgetTester t) async {
    await t.tapAt(const Offset(8, 8));
    await t.pumpAndSettle();
  }

  // ─────────────────────────────────────────────
  // 交互守卫
  // ─────────────────────────────────────────────
  testWidgets('F1：首次点节点 ⇒ 选中 + 画布镜头同步 + 原详情 sheet', (t) async {
    final state = await pumpGraph(t, onOpenTool: (_) {});
    expect(state.debugSelectedNodeId, isNull);
    expect(painterOf(t).focusedNodeId, isNull);

    await tapNode(t, 'law-of-segregation');

    expect(state.debugSelectedNodeId, 'law-of-segregation');
    expect(
      painterOf(t).focusedNodeId,
      'law-of-segregation',
      reason: 'painter 必须收到选中节点，否则没有强弱分层',
    );
    // 原详情 sheet 照旧（先修卡 + 功能按钮）
    expect(find.text('先修知识点'), findsOneWidget);
    expect(find.text('打开对应功能：遗传计算器'), findsOneWidget);
    // 独立字段：「先修补课」高亮不被选中态污染
    expect(state.debugFocusedNodeId, isNull);
  });

  testWidgets('F2：再点当前节点 ⇒ 只收镜头，不重复弹详情', (t) async {
    final state = await pumpGraph(t);
    await tapNode(t, 'law-of-segregation');
    await dismissSheet(t);
    expect(find.text('先修知识点'), findsNothing, reason: 'sheet 已关');
    expect(
      state.debugSelectedNodeId,
      'law-of-segregation',
      reason: '关 sheet 不清选中',
    );

    await tapNode(t, 'law-of-segregation');

    expect(state.debugSelectedNodeId, isNull, reason: '再点同一节点 = 取消焦点');
    expect(painterOf(t).focusedNodeId, isNull);
    expect(find.text('先修知识点'), findsNothing, reason: '取消焦点不得重新弹详情');
    expect(find.byType(BottomSheet), findsNothing);
  });

  testWidgets('F3：点空白 ⇒ 清除选中', (t) async {
    final state = await pumpGraph(t);
    await tapNode(t, '9331');
    await dismissSheet(t);
    expect(state.debugSelectedNodeId, '9331');

    await tapBlank(t);

    expect(state.debugSelectedNodeId, isNull);
    expect(painterOf(t).focusedNodeId, isNull);
    expect(find.byType(BottomSheet), findsNothing);
  });

  testWidgets('F4：debugShowDetail 与真实点击同源（同步 selected）', (t) async {
    final state = await pumpGraph(t);
    state.debugShowDetail('9331');
    await t.pumpAndSettle();

    expect(state.debugSelectedNodeId, '9331');
    expect(painterOf(t).focusedNodeId, '9331');
    expect(state.debugFocusedNodeId, isNull, reason: '两套状态互不复用');
    expect(
      find.text('关联 / 后续知识点'),
      findsOneWidget,
      reason: '钩子仍弹原 bottom sheet',
    );
  });

  testWidgets('F5：选中不重排布局（节点坐标逐点不变）', (t) async {
    await pumpGraph(t);
    final before = Map<String, Offset>.of(painterOf(t).positions);

    await tapNode(t, 'gamete-formation');

    final after = painterOf(t).positions;
    expect(after, before, reason: '分层布局/坐标不得随选中变化（不换力导向）');
  });

  testWidgets('F6：搜索高亮与选中并存（highlighted 不被覆盖）', (t) async {
    await pumpGraph(t);
    await t.enterText(find.byType(TextField), '分离');
    await t.pumpAndSettle();

    final searchHi = painterOf(t).highlighted;
    expect(
      searchHi,
      contains('law-of-segregation'),
      reason: '搜索命中的节点在 highlighted 里',
    );

    await tapNode(t, 'law-of-segregation');

    final painter = painterOf(t);
    expect(painter.focusedNodeId, 'law-of-segregation');
    expect(painter.highlighted, searchHi, reason: '选中不得改写搜索高亮集合（两者叠加，不互相顶替）');
  });

  // ─────────────────────────────────────────────
  // 绘制契约（纯函数口径：快、稳、不依赖像素）
  // ─────────────────────────────────────────────
  group('F7 重绘契约', () {
    KnowledgeGraphPainter make({String? focus}) => KnowledgeGraphPainter(
      graph: defaultKnowledgeGraph,
      nodes: defaultKnowledgeGraph.nodes,
      positions: const {'a': Offset.zero},
      highlighted: const {},
      weaknessCounts: const {},
      focusedNodeId: focus,
    );

    test('只有 focusedNodeId 变化 ⇒ 必须重绘；全同 ⇒ 不重绘', () {
      expect(
        make(focus: 'x').shouldRepaint(make()),
        isTrue,
        reason: '选中/取消选中必须触发重绘',
      );
      expect(
        make().shouldRepaint(make(focus: 'x')),
        isTrue,
        reason: '取消选中同样要重绘（线宽/透明度要回到常态）',
      );
      expect(make(focus: 'x').shouldRepaint(make(focus: 'y')), isTrue);
      expect(make(focus: 'x').shouldRepaint(make(focus: 'x')), isFalse);
      expect(make().shouldRepaint(make()), isFalse);
    });

    test('原有触发条件仍有效（搜索/弱点/节点集）', () {
      final base = make();
      expect(
        KnowledgeGraphPainter(
          graph: defaultKnowledgeGraph,
          nodes: defaultKnowledgeGraph.nodes,
          positions: const {'a': Offset.zero},
          highlighted: const {'9331'},
        ).shouldRepaint(base),
        isTrue,
      );
      expect(
        KnowledgeGraphPainter(
          graph: defaultKnowledgeGraph,
          nodes: defaultKnowledgeGraph.nodes,
          positions: const {'a': Offset.zero},
          highlighted: const {},
          weaknessCounts: const {'9331': 3},
        ).shouldRepaint(base),
        isTrue,
      );
    });
  });

  group('F8 强弱档与降权口径', () {
    test('常态线：先修 1.7px/0.34、关联 1.1px/0.22（不低于可读下限）', () {
      expect(KnowledgeGraphPainter.edgePrereqWidth, 1.7);
      expect(KnowledgeGraphPainter.edgePrereqAlpha, 0.34);
      expect(KnowledgeGraphPainter.edgeRelatedWidth, 1.1);
      expect(KnowledgeGraphPainter.edgeRelatedAlpha, 0.22);
      expect(
        KnowledgeGraphPainter.edgePrereqWidth,
        greaterThan(KnowledgeGraphPainter.edgeRelatedWidth),
        reason: '先修链比关联线更实',
      );
      expect(
        KnowledgeGraphPainter.edgePrereqAlpha,
        greaterThanOrEqualTo(0.2),
        reason: '不得把常态线淡到课堂看不见',
      );
    });

    test('选中线：相关 2.6px/0.92 强于常态；非相关 0.08 仍 > 0', () {
      expect(KnowledgeGraphPainter.focusEdgeWidth, 2.6);
      expect(KnowledgeGraphPainter.focusEdgeAlpha, 0.92);
      expect(KnowledgeGraphPainter.dimEdgeAlpha, 0.08);
      expect(
        KnowledgeGraphPainter.focusEdgeAlpha,
        greaterThan(KnowledgeGraphPainter.edgePrereqAlpha),
      );
      expect(
        KnowledgeGraphPainter.dimEdgeAlpha,
        greaterThan(0),
        reason: '非相关边只压暗，不消失（结构仍可追溯）',
      );
    });

    test('节点降权 0.45：非一跳降权、其余（一跳/搜索/弱点）不降权', () {
      expect(KnowledgeGraphPainter.dimNodeWeight, 0.45);
      double w({
        required bool hasFocus,
        required bool inNeighborhood,
        bool highlighted = false,
        bool hasWeakness = false,
      }) => KnowledgeGraphPainter.nodeWeight(
        hasFocus: hasFocus,
        inNeighborhood: inNeighborhood,
        highlighted: highlighted,
        hasWeakness: hasWeakness,
      );
      expect(
        w(hasFocus: false, inNeighborhood: false),
        1.0,
        reason: '无选中 ⇒ 全强度（像素不变）',
      );
      expect(w(hasFocus: true, inNeighborhood: true), 1.0);
      expect(
        w(hasFocus: true, inNeighborhood: false),
        0.45,
        reason: '非一跳降权但仍绘制',
      );
      expect(
        w(hasFocus: true, inNeighborhood: false, highlighted: true),
        1.0,
        reason: '搜索高亮不被降权覆盖',
      );
      expect(
        w(hasFocus: true, inNeighborhood: false, hasWeakness: true),
        1.0,
        reason: '薄弱点描边不被降权覆盖',
      );
    });

    test('一跳邻域：连着选中节点的都算（先修/关联、入边/出边）', () {
      final n = KnowledgeGraphPainter.focusNeighborhood(
        defaultKnowledgeGraph,
        'law-of-segregation',
      );
      expect(n, contains('law-of-segregation'), reason: '自身在一跳圈内');
      expect(n, contains('dominant-recessive'), reason: '入边先修');
      expect(n, contains('gamete-formation'), reason: '出边先修');
      expect(n, contains('sex-linked'), reason: '出边先修');
      expect(n, contains('punnett-square'), reason: '入边关联也算一跳');
      expect(n, isNot(contains('codominance')), reason: '两跳之外');
      // 无入出边的孤立查询不会抛
      expect(
        KnowledgeGraphPainter.focusNeighborhood(
          defaultKnowledgeGraph,
          'no-such-node',
        ),
        {'no-such-node'},
      );
    });
  });

  group('F9 通道错峰稳定派生', () {
    test('同一条边永远同一个错峰量（与数组序号无关）', () {
      final a = KnowledgeGraphPainter.channelOffset(
        '9331',
        '9331-variant-97',
        'related',
      );
      final b = KnowledgeGraphPainter.channelOffset(
        '9331',
        '9331-variant-97',
        'related',
      );
      expect(a, b);
      expect(a, inInclusiveRange(-16.0, 16.0));
      expect(a % 8, 0, reason: '±16 内按 8px 步进铺开');
    });

    test('不同边拿到不同错峰量（不是一根总线）', () {
      final offsets = <double>{
        for (final e in defaultKnowledgeGraph.edges)
          KnowledgeGraphPainter.channelOffset(e.from, e.to, e.kind),
      };
      expect(
        offsets.length,
        greaterThanOrEqualTo(3),
        reason: '同一通道的线要错开，否则合并成总线不可追溯',
      );
    });

    test('kind 参与派生（同端点不同关系不共线）', () {
      expect(
        KnowledgeGraphPainter.channelOffset('9331', 'lethal-gene', 'related'),
        isNot(KnowledgeGraphPainter.channelOffset(
            '9331', 'lethal-gene', 'prerequisite')),
      );
      // from/to 反向不是同一条边，允许（也应）取到不同错峰
      final a = KnowledgeGraphPainter.channelOffset('a', 'b', 'related');
      final b = KnowledgeGraphPainter.channelOffset('b', 'a', 'related');
      expect(a, isA<double>());
      expect(b, isA<double>());
    });
  });
}
