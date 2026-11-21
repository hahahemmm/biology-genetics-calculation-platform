// graph_weakness_test.dart —— v2.19.63 知识图谱「薄弱点着色 + 先修补课」守卫
//
// 创新提案 #4：图谱节点按错题本挂题数分层着色（1-2 琥珀 / ≥3 红描边），
// 并在「有错题 + 有先修」的节点详情里给出「先修补这课」——跳到先修节点并高亮。
//
// 全部数据引擎驱动（禁位图）：
//   - 挂题数 = graphWeaknessCounts(subjectArea 文本 …)（纯函数，engine 侧）
//   - 着色阈值 = KnowledgeGraphPainter.weaknessStroke（琥珀/红，空数据 = null 基线）
//
// 守卫：
//   G1：3 条命中某节点 ⇒ 该节点红描边
//   G2：1 条 ⇒ 琥珀；空错题本 ⇒ 全 0 ⇒ 描走基线（null，像素零变化）
//   G3：挂题>0 + 有先修 ⇒ 按钮在屏；挂题>0 但无先修 ⇒ 按钮不渲染
//   G4：「先修补这课」点击 ⇒ 高亮/选中落到先修节点
//   G5：错题本走独立临时目录 + 题干唯一计数器

import 'dart:io';

import 'package:biology/engine/knowledge_graph.dart';
import 'package:biology/pages/knowledge_graph_page.dart';
import 'package:biology/state/mistake_book.dart';
import 'package:biology/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory tmp;
  int stemSeq = 0;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('graph_weakness_test');
    MistakeBook.debugFilePath = '${tmp.path}/mistake_book.json';
    MistakeBook.instance.debugReset();
    stemSeq = 0;
    // 深/浅 token 确定性：本测试锁定浅色（AppColors.lethal / flash 取值稳定）。
    AppColors.sync(Brightness.light);
    // add() 后 500ms 落盘 debounce Timer——test 结束框架断言「无 pending timer」，
    // addTearDown 在 invariants 前跑，flush 取消。
    addTearDown(() => MistakeBook.instance.debugFlushSave());
  });

  tearDown(() {
    MistakeBook.debugFilePath = null;
    MistakeBook.instance.debugReset();
    AppColors.debugClearOverride();
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  /// 往错题本塞一条 subjectArea 命中某节点的错题（题干用唯一计数器，防重复合并）。
  void addMistake(String subjectArea) {
    stemSeq++;
    MistakeBook.instance.add(
      stem: '守卫题 #$stemSeq',
      userAnswer: '错',
      correctAnswer: '对',
      errorType: MistakeErrorType.concept,
      subjectArea: subjectArea,
    );
    // add() 排了 500ms 落盘 debounce Timer；testWidgets 结束会断言「无 pending
    // timer」——立即 flush 取消它（幂等，teardown 再调一次也无害）。
    MistakeBook.instance.debugFlushSave();
  }

  /// 泵图谱页（大视口，详情 sheet 内容不折行/不截断），返回页面 State（debug 钩子）。
  Future<dynamic> pumpGraph(WidgetTester t) async {
    t.view.physicalSize = const Size(1200, 1600);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    await t.pumpWidget(MaterialApp(
        theme: AppTheme.light(), home: const KnowledgeGraphPage()));
    await t.pumpAndSettle();
    return t.state(find.byType(KnowledgeGraphPage));
  }

  /// 从树里取出图谱绘制器（唯一 KnowledgeGraphPainter，painter 数据断言最可靠）。
  KnowledgeGraphPainter painterOf(WidgetTester t) {
    for (final cp in t.widgetList<CustomPaint>(find.byType(CustomPaint))) {
      final p = cp.painter;
      if (p is KnowledgeGraphPainter) return p;
    }
    fail('未找到 KnowledgeGraphPainter');
  }

  // ─────────────────────────────────────────────
  // 纯函数口径（engine 侧；快、稳，先跑）
  // ─────────────────────────────────────────────
  group('graphWeaknessCounts 口径', () {
    test('命中即计数；空串跳过；每节点都出现（零值保留）', () {
      final c = graphWeaknessCounts(['分离定律', '', '测交（testcross）']);
      expect(c['law-of-segregation'], 1);
      expect(c['testcross'], 1);
      expect(c['backcross'], 0, reason: '未命中节点零值保留');
      expect(c.length, graphNodeKeywords.length);
    });

    test('同一节点多关键词同时命中只记 1 次（break）', () {
      // '基因型与表型' 同时含 genotype-phenotype 的两个关键词
      final c = graphWeaknessCounts(['基因型与表型']);
      expect(c['genotype-phenotype'], 1, reason: '一条错题对同一节点不重复计');
    });

    test('空输入 ⇒ 全 0', () {
      final c = graphWeaknessCounts(const []);
      expect(c.values.every((v) => v == 0), isTrue);
    });
  });

  group('着色阈值（painter 分层）', () {
    test('0 ⇒ 基线（null）；1-2 ⇒ 琥珀；≥3 ⇒ 红', () {
      expect(KnowledgeGraphPainter.weaknessStroke(0), isNull);
      expect(KnowledgeGraphPainter.weaknessStroke(1), AppColors.flash);
      expect(KnowledgeGraphPainter.weaknessStroke(2), AppColors.flash);
      expect(KnowledgeGraphPainter.weaknessStroke(3), AppColors.lethal);
      expect(KnowledgeGraphPainter.weaknessStroke(9), AppColors.lethal);
      expect(AppColors.flash, isNot(AppColors.lethal), reason: '琥珀 ≠ 红');
    });
  });

  // ─────────────────────────────────────────────
  // widget 守卫
  // ─────────────────────────────────────────────
  testWidgets('G1：3 条命中某节点 ⇒ 该节点红描边', (t) async {
    addMistake('分离定律');
    addMistake('分离定律综合题');
    addMistake('分离定律');

    final state = await pumpGraph(t);
    final painter = painterOf(t);

    expect(painter.weaknessCounts['law-of-segregation'], 3);
    expect(
        KnowledgeGraphPainter.weaknessStroke(
            painter.weaknessCounts['law-of-segregation']!),
        AppColors.lethal);
    // 页面 debug 钩子与 painter 数据同源
    expect(state.debugWeaknessCounts['law-of-segregation'], 3);
    // 未命中节点仍是 0（基线）
    expect(painter.weaknessCounts['testcross'], 0);
  });

  testWidgets('G2：1 条 ⇒ 琥珀；别的节点仍基线', (t) async {
    addMistake('测交');

    await pumpGraph(t);
    final painter = painterOf(t);

    expect(painter.weaknessCounts['testcross'], 1);
    expect(
        KnowledgeGraphPainter.weaknessStroke(
            painter.weaknessCounts['testcross']!),
        AppColors.flash);
    expect(painter.weaknessCounts['backcross'], 0);
    expect(KnowledgeGraphPainter.weaknessStroke(0), isNull,
        reason: '0 挂题走基线描边（像素不变）');
  });

  testWidgets('G2b：空错题本 ⇒ 全节点 0 挂题 ⇒ 描走基线', (t) async {
    final state = await pumpGraph(t);
    final painter = painterOf(t);

    for (final n in defaultKnowledgeGraph.nodes) {
      expect(painter.weaknessCounts[n.id], 0, reason: '${n.id} 应为 0');
    }
    expect(state.debugWeaknessCounts.values.every((v) => v == 0), isTrue);
    // 全 0 ⇒ painter 逐节点都走基线描边（weaknessStroke null）
    expect(KnowledgeGraphPainter.weaknessStroke(0), isNull);
  });

  testWidgets('G3：挂题>0 且该节点有先修 ⇒ 「先修补这课」在屏', (t) async {
    // law-of-segregation 的先修是 dominant-recessive（prerequisite 边）
    expect(defaultKnowledgeGraph.prerequisitesOf('law-of-segregation'),
        isNotEmpty);
    addMistake('分离定律');

    final state = await pumpGraph(t);
    state.debugShowDetail('law-of-segregation');
    await t.pumpAndSettle();

    expect(find.text('先修补这课'), findsOneWidget);
  });

  testWidgets('G3b：挂题>0 但该节点无先修 ⇒ 按钮不渲染', (t) async {
    // 9331-variant-97 只有 related 入边，无 prerequisite 先修
    expect(defaultKnowledgeGraph.prerequisitesOf('9331-variant-97'), isEmpty);
    addMistake('9331 变式：9:7');

    final state = await pumpGraph(t);
    expect(state.debugWeaknessCounts['9331-variant-97'], greaterThan(0),
        reason: '该节点确实挂了错题');
    state.debugShowDetail('9331-variant-97');
    await t.pumpAndSettle();

    expect(find.text('先修补这课'), findsNothing,
        reason: '无先修 ⇒ 零像素诚实，不渲染按钮');
  });

  testWidgets('G4：点「先修补这课」⇒ 高亮/选中落到先修节点', (t) async {
    addMistake('分离定律');

    final state = await pumpGraph(t);
    expect(state.debugFocusedNodeId, isNull);

    state.debugShowDetail('law-of-segregation');
    await t.pumpAndSettle();
    await t.ensureVisible(find.text('先修补这课'));
    await t.tap(find.text('先修补这课'));
    await t.pumpAndSettle();

    expect(state.debugFocusedNodeId, 'dominant-recessive',
        reason: '高亮应落到先修节点');
    expect(find.text('先修补这课'), findsNothing, reason: '点击后详情 sheet 关闭');
  });

  testWidgets('G6：弱点覆盖层与普通节点一致，再点同节点取消且不重复弹 Sheet',
      (t) async {
    addMistake('分离定律');
    addMistake('分离定律综合题');
    addMistake('分离定律');

    final state = await pumpGraph(t);
    final tip = find.byTooltip('这里错得多');
    expect(tip, findsOneWidget, reason: '≥3 错题节点的覆盖层应存在');

    await t.tap(tip);
    await t.pumpAndSettle();
    expect(state.debugSelectedNodeId, 'law-of-segregation');
    expect(find.text('分离定律（孟德尔第一定律）'), findsOneWidget);

    // 关闭详情但保留画布选中，再走同一个覆盖层的真实点击路径。
    await t.tapAt(const Offset(10, 10));
    await t.pumpAndSettle();
    expect(find.text('分离定律（孟德尔第一定律）'), findsNothing);
    expect(state.debugSelectedNodeId, 'law-of-segregation');

    await t.tap(tip);
    await t.pumpAndSettle();
    expect(state.debugSelectedNodeId, isNull,
        reason: '覆盖层不得绕过「再点取消焦点」');
    expect(find.text('分离定律（孟德尔第一定律）'), findsNothing,
        reason: '第二次点击不得重新打开详情 Sheet');
  });

  testWidgets('G5：错题本独立临时目录 + 题干唯一计数器', (t) async {
    addMistake('测交');
    addMistake('测交');

    expect(MistakeBook.debugFilePath, contains(tmp.path));
    expect(MistakeBook.instance.entries.length, 2);
    expect(MistakeBook.instance.entries.map((e) => e.stem).toSet().length, 2,
        reason: '题干唯一计数器：两条题干不同');
  });
}
