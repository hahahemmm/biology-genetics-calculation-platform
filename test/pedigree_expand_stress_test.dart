// pedigree_expand_stress_test.dart —— 大规模展开回归锁
//
// 场景：AaBbCc × AaBbCc 自交 → F2 27 桶（3^3）→ 再一代 F3。
// 规模说明：3 对杂合基因每代桶数上限就是 3^3 = 27；F3 池随机交配后
// 每个位点回归 1:2:1，仍是 27 桶，不会爆炸（100+ 桶需要 ≥4 对基因，
// 不在本用例的 AaBbCc 范围内）。所以不砍到 F2，F2/F3 都按 27 桶测试；
// F3 的真实压力在边数：27 个 F2 桶都是贡献者 → 27×27 = 729 条 lineage 边。
//
// 断言：展开不抛异常；展开后节点数 == 引擎桶数；每个桶都有 lineage
// 入边（「只连一条」缺陷的回归锁）；收起后节点/边数回到折叠态。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:biology/engine/pedigree_graph.dart';
import 'package:biology/pages/genetic_pedigree_page.dart';
import 'package:biology/pages/widgets/pedigree_canvas.dart';

Widget _app() => const MaterialApp(home: GeneticPedigreePage());

/// 与 pedigree_ui_test.dart 的 pumpHome 同一套脚手架（1000×800 视口）。
Future<void> _pumpHome(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1000, 800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(_app());
}

PedigreeCanvas _canvas(WidgetTester tester) =>
    tester.widget<PedigreeCanvas>(find.byType(PedigreeCanvas));

Future<void> _derive(WidgetTester tester) async {
  await tester.tap(find.text('计算').first);
  await tester.pumpAndSettle();
  expect(find.byType(PedigreeCanvas), findsOneWidget);
}

/// 独立跑一遍同构引擎，给出各代桶数（页面用的就是同一构造参数）。
Map<int, int> _engineBuckets() {
  final e = PedigreeGraphEngine(
      fatherGenotype: 'AaBbCc', motherGenotype: 'AaBbCc');
  final out = <int, int>{};
  for (var g = 1; g <= 3; g++) {
    e.expandNextGeneration();
    out[g] = e.nodesOf(g).length;
  }
  return out;
}

/// 展开后每个桶都必须至少有一条 lineage 入边。
void _expectEveryNodeHasLineageSink(
    PedigreeCanvas c, int generation, int expectedBuckets) {
  final ids = c.nodes
      .where((n) => n.generation == generation)
      .map((n) => n.id)
      .toSet();
  expect(ids.length, expectedBuckets,
      reason: 'F$generation 展开后节点数应等于引擎桶数');
  final sinks = c.edges
      .where((e) =>
          e.kind == PedigreeEdgeKind.lineage && ids.contains(e.toId))
      .map((e) => e.toId)
      .toSet();
  expect(ids.difference(sinks), isEmpty,
      reason: 'F$generation 每个桶都必须有 lineage 入边（不得只连一条）');
}

/// 该代可见的 lineage 入边总条数。
int _lineageIntoSinks(PedigreeCanvas c, Set<String> ids) => c.edges
    .where((e) => e.kind == PedigreeEdgeKind.lineage && ids.contains(e.toId))
    .length;

void main() {
  test('引擎：AaBbCc 自交 F1/F2/F3 都是 27 桶，F3 有 729 条 lineage 边', () {
    final buckets = _engineBuckets();
    // 每对基因独立 1:2:1 → 子代基因型 3^3 = 27 种，各成一桶；
    // 折叠成 1 桶只是画布层的显示规则，引擎层 F1 起就是 27 桶。
    expect(buckets[1], 27, reason: '3 对杂合 → F1 已是 3^3 = 27 个基因型桶');
    expect(buckets[2], 27, reason: '3 对杂合 → 3^3 = 27 个基因型桶');
    expect(buckets[3], 27, reason: 'F3 池随机交配后位点分布不变，不爆炸');

    final e = PedigreeGraphEngine(
        fatherGenotype: 'AaBbCc', motherGenotype: 'AaBbCc');
    for (var i = 0; i < 3; i++) {
      e.expandNextGeneration();
    }
    expect(
        e.edges
            .where((x) =>
                x.kind == PedigreeEdgeKind.lineage &&
                e.nodesById[x.toId]?.generation == 3)
            .length,
        27 * 27,
        reason: 'F3 每个桶都连向 F2 全部 27 个贡献者');
  });

  testWidgets('展开/收起 F2+F3 共 27 桶：不崩、不丢线、可回到折叠态',
      (tester) async {
    final buckets = _engineBuckets();
    await _pumpHome(tester);
    await _derive(tester);

    // ── F2：默认折叠 1 桶，展开 27 桶 ──────────────────
    await tester.tap(find.text('计算下一代'));
    await tester.pumpAndSettle();
    var c = _canvas(tester);
    expect(c.nodes.where((n) => n.generation == 2).length, 1,
        reason: '折叠态 F2 只显示最高概率桶');
    expect(c.hiddenCounts['0:2'], 26);
    final foldedF2Nodes = c.nodes.length;
    final foldedF2Edges = c.edges.length;

    c.onToggleGen!('0:2');
    await tester.pumpAndSettle();
    c = _canvas(tester);
    expect(tester.takeException(), isNull, reason: '展开 F2 不得抛异常');
    _expectEveryNodeHasLineageSink(c, 2, buckets[2]!);
    expect(c.nodes.where((n) => n.generation == 2).length, 27);
    final expF2Nodes = c.nodes.length;
    final expF2Edges = c.edges.length;

    // 收起回折叠态 → 与展开前完全一致（同一世代集合内往返）
    c.onToggleGen!('0:2');
    await tester.pumpAndSettle();
    c = _canvas(tester);
    expect(tester.takeException(), isNull, reason: '收起 F2 不得抛异常');
    expect(c.nodes.length, foldedF2Nodes, reason: '收起后回到折叠态节点数一致');
    expect(c.edges.length, foldedF2Edges, reason: '收起后回到折叠态边数一致');

    // 再展开，F2 保持展开态进入 F3 流程
    c.onToggleGen!('0:2');
    await tester.pumpAndSettle();
    c = _canvas(tester);
    expect(c.nodes.length, expF2Nodes);
    expect(c.edges.length, expF2Edges);

    // ── F3：再一代，默认折叠 1 桶（F2 保持展开） ─────────
    await tester.tap(find.text('计算下一代'));
    await tester.pumpAndSettle();
    c = _canvas(tester);
    expect(c.nodes.where((n) => n.generation == 3).length, 1,
        reason: '折叠态 F3 只显示最高概率桶');
    expect(c.hiddenCounts['0:3'], 26);
    final foldedF3Nodes = c.nodes.length;
    final foldedF3Edges = c.edges.length;

    c.onToggleGen!('0:3');
    await tester.pumpAndSettle();
    c = _canvas(tester);
    expect(tester.takeException(), isNull, reason: '展开 F3 不得抛异常');
    _expectEveryNodeHasLineageSink(c, 3, buckets[3]!);

    // 展开的组不抽稀：F3 的 729 条 lineage 边一条不少。
    final f3Ids = c.nodes
        .where((n) => n.generation == 3)
        .map((n) => n.id)
        .toSet();
    expect(_lineageIntoSinks(c, f3Ids), 27 * 27,
        reason: 'F3 展开后不得抽稀，27×27 条 lineage 全留');

    // ── 收起 F3：节点/边数回到折叠态 ────────────────────
    c.onToggleGen!('0:3');
    await tester.pumpAndSettle();
    c = _canvas(tester);
    expect(tester.takeException(), isNull, reason: '收起 F3 不得抛异常');
    expect(c.nodes.length, foldedF3Nodes);
    expect(c.edges.length, foldedF3Edges);
    expect(c.nodes.where((n) => n.generation == 3).length, 1);

    // ── 收起 F2：回到折叠特征 ──────────────────────────
    c.onToggleGen!('0:2');
    await tester.pumpAndSettle();
    c = _canvas(tester);
    expect(tester.takeException(), isNull, reason: '收起 F2 不得抛异常');
    // foldedF2 基线产生于 F3 之前，此时 F3 已存在，总节点/边数不能再与
    // 旧基线硬比；「回到折叠态一致」由上方 F2 展开-收起往返段验证。
    expect(c.nodes.where((n) => n.generation == 2).length, 1);
    expect(c.hiddenCounts['0:2'], 26);
  });
}
