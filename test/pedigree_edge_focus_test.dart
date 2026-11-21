// pedigree_edge_focus_test.dart —— 智能密线派生层（纯函数）测试
//
// 覆盖：默认抽稀密线 / 「全部连线」恢复 / 选中元素的边保留 /
// 学生手连的回交线一条不删 / 逐代追踪链路存在。

import 'package:biology/engine/pedigree_graph.dart';
import 'package:biology/pages/widgets/pedigree_edge_focus.dart';
import 'package:flutter_test/flutter_test.dart';

PedigreeGraphEngine _engine() {
  final e = PedigreeGraphEngine(
      fatherGenotype: 'AaBb', motherGenotype: 'AaBb');
  e.recomputeFrom(0);
  e.ensureOffspringCoverage();
  return e;
}

List<PedigreeEdge> _lineage(List<PedigreeEdge> edges) =>
    edges.where((x) => x.kind == PedigreeEdgeKind.lineage).toList();

void main() {
  test('默认智能密线：密线组只留主干，mating 边一条不少', () {
    final e = _engine();
    final all = e.edges;
    final smart = deriveCanvasEdges(edges: all, nodesById: e.nodesById);

    expect(smart.length, lessThan(all.length),
        reason: 'F1 密线（2 父 × 多桶）应被抽稀');
    expect(
        smart.where((x) => x.kind == PedigreeEdgeKind.mating).length,
        all.where((x) => x.kind == PedigreeEdgeKind.mating).length,
        reason: 'mating 边（含手连）全留');
    expect(
        smart.any((x) =>
            x.kind == PedigreeEdgeKind.lineage && x.toId == 'F1#0'),
        isTrue,
        reason: '代表桶（最高概率）的主干边保留');
    expect(_lineage(smart).length, lessThan(_lineage(all).length),
        reason: '被收起的是自动推导的 lineage 边');
  });

  test('「全部连线」开关：不过滤，原样返回引擎全部边', () {
    final e = _engine();
    final smart = deriveCanvasEdges(
        edges: e.edges, nodesById: e.nodesById, showAllAuto: true);
    expect(smart.length, e.edges.length);
    expect(smart.map((x) => '${x.fromId}|${x.toId}|${x.kind.name}').toList(),
        e.edges.map((x) => '${x.fromId}|${x.toId}|${x.kind.name}').toList(),
        reason: '顺序与内容都与引擎一致（不伪造）');
  });

  test('选中元素：与它相关的自动边恢复显示', () {
    final e = _engine();
    const tapId = 'F1#5';
    final smart = deriveCanvasEdges(
        edges: e.edges, nodesById: e.nodesById, selectedTapId: tapId);
    final related = _lineage(smart).where((x) => x.toId == tapId).toList();
    expect(related, isNotEmpty, reason: '选中桶的双亲连线要看得见');
    expect(related.length,
        _lineage(e.edges).where((x) => x.toId == tapId).length,
        reason: '与选中元素相关的边全留（不半留）');
  });

  test('展开的世代不抽稀：整代摊开后每个桶都留亲代连线', () {
    final e = _engine();
    final f1 = e.nodes.firstWhere((n) => n.generation == 1);
    final key = '${f1.familyId}:${f1.generation}';
    final kids =
        e.nodes.where((n) => n.generation == 1).map((n) => n.id).toSet();

    final collapsed = deriveCanvasEdges(edges: e.edges, nodesById: e.nodesById);
    final hidden = kids
        .difference(_lineage(collapsed).map((x) => x.toId).toSet());
    expect(hidden, isNotEmpty, reason: '折叠态只留主干是既有行为');

    final expanded = deriveCanvasEdges(
        edges: e.edges, nodesById: e.nodesById, expandedGroupKeys: {key});
    expect(
        kids.difference(_lineage(expanded).map((x) => x.toId).toSet()), isEmpty,
        reason: '展开后每个桶都要看得见亲代，不能只连一个');
  });

  test('半边合成 id 也能匹配到基础节点的边', () {
    final e = _engine();
    const groupId = 'F1#5';
    final smart = deriveCanvasEdges(
        edges: e.edges,
        nodesById: e.nodesById,
        selectedTapId: '$groupId::male');
    expect(_lineage(smart).any((x) => x.toId == groupId), isTrue);
  });

  test('学生手连的回交线在智能密线下一条不删', () {
    final e = _engine();
    final extId = e.addExternal(
        generation: 1,
        kind: PedigreeNodeKind.female,
        genotype: 'Aabb');
    expect(e.connect('P-father', extId), isTrue, reason: '回交边建立成功');
    final smart = deriveCanvasEdges(edges: e.edges, nodesById: e.nodesById);
    expect(
        smart.any((x) =>
            x.kind == PedigreeEdgeKind.mating &&
            ((x.fromId == 'P-father' && x.toId == extId) ||
                (x.fromId == extId && x.toId == 'P-father'))),
        isTrue,
        reason: '手连回交线不得被智能密线悄悄收起');
  });

  test('isManualMatingEdge：只把各家族双亲自带配对判为自动', () {
    expect(
        isManualMatingEdge(const PedigreeEdge(
            'P-father', 'P-mother', PedigreeEdgeKind.mating)),
        isFalse);
    expect(
        isManualMatingEdge(const PedigreeEdge(
            'P2-father', 'P2-mother', PedigreeEdgeKind.mating)),
        isFalse);
    expect(
        isManualMatingEdge(const PedigreeEdge(
            'P-father', 'F1#3', PedigreeEdgeKind.mating)),
        isTrue);
    expect(
        isManualMatingEdge(const PedigreeEdge(
            'F1#0', 'F1#1', PedigreeEdgeKind.lineage)),
        isFalse);
  });

  test('逐代追踪：选中深层节点时，向上至少一代的链路可见', () {
    final e = _engine();
    e.expandNextGeneration(); // → F2
    final f2 = e.nodes.where((n) => n.generation == 2).toList();
    expect(f2, isNotEmpty);
    final sel = f2.first;
    final smart = deriveCanvasEdges(
        edges: e.edges, nodesById: e.nodesById, selectedTapId: sel.id);

    final parents = _lineage(smart)
        .where((x) => x.toId == sel.id)
        .map((x) => x.fromId)
        .toSet();
    expect(parents, isNotEmpty, reason: '选中节点的双亲边可见');
    expect(
        _lineage(smart).any((x) => parents.contains(x.toId)),
        isTrue,
        reason: '上一代再往上还有一条可追踪的链路（不用整代铺满）');
  });
}
