// pedigree_edge_focus.dart —— 智能密线：画布可见边的纯派生层
//
// 只过滤「画布输入」，**不动引擎拓扑**：engine.edges 永远原样保留，
// 学生手动连的线（回交 / 点选连线）一条都不删；SVG / PNG 导出复用
// 同一份派生结果（所见即所导出）。
//
// 派生规则（默认智能密线）：
//   1. mating 边全留 —— 各家族自带的 P 双亲配对 + 学生手连的边；
//   2. lineage 边按 (家族, 子代世代) 分组，组内条数 ≤ 阈值时全留；
//   3. 超阈值的「密线组」只留在代表桶（最高概率）上的那几条主干；
//   4. 选中/待命/聚焦的元素相关边全留 —— 点谁就看谁，
//      并沿代表祖先逐代往上留一条可追踪的链（不把整代父本铺回来）。

import '../../engine/pedigree_graph.dart';

/// 同一 (家族, 子代世代) 下自动 lineage 边超过该条数即视为「密线」。
const int kPedigreeDenseLineageLimit = 8;

/// 组合桶半边合成 id → 基础节点 id（与画布 halfTapId 协议一致：
/// `groupId::male` / `groupId::female`）。
String pedigreeEdgeBaseId(String id) {
  final i = id.indexOf('::');
  return i < 0 ? id : id.substring(0, i);
}

/// 学生手动创建的 mating 边（回交 / 点选连线）。
///
/// 引擎只在一个地方自动建 mating 边：各家族创始双亲 `P$k-father ×
/// P$k-mother`（含 `P-father × P-mother`）。除此之外的 mating 边全部
/// 来自 `connect()`，即用户亲手连的线 —— 智能密线绝不收起它们。
bool isManualMatingEdge(PedigreeEdge e) {
  if (e.kind != PedigreeEdgeKind.mating) return false;
  const suffix = '-father';
  bool isParentPair(String father, String mother) {
    if (!father.startsWith('P') || !father.endsWith(suffix)) return false;
    final prefix = father.substring(0, father.length - suffix.length);
    return mother == '$prefix-mother';
  }

  return !(isParentPair(e.fromId, e.toId) || isParentPair(e.toId, e.fromId));
}

/// 画布应当收到的边序列（保持引擎顺序，便于稳定测试与导出）。
///
/// [showAllAuto] = 「全部连线」视图开关：true 时不过滤（恢复所有密线）。
/// [selectedTapId] = 当前选中/待命的 tapId（可带 `::male/::female` 后缀）。
/// [focusTapIds] = 聚焦集（同样可带半边后缀）。
/// [expandedGroupKeys] = 已展开的 `家族:世代` 键：抽稀只服务于折叠态
/// （折叠时该代本来就只剩一个代表桶，多画的线没有落点）。用户点了
/// 「+N 种基因型」把整代摊开后，每个桶都是屏幕上的实体，只留主干会
/// 让其余桶看起来「没有亲代」——所以展开的组一律画全。
List<PedigreeEdge> deriveCanvasEdges({
  required List<PedigreeEdge> edges,
  required Map<String, PedigreeNode> nodesById,
  bool showAllAuto = false,
  String? selectedTapId,
  Set<String> focusTapIds = const {},
  Set<String> expandedGroupKeys = const {},
}) {
  if (showAllAuto || edges.isEmpty) return List<PedigreeEdge>.of(edges);

  String baseOf(PedigreeEdge e, {required bool from}) =>
      pedigreeEdgeBaseId(from ? e.fromId : e.toId);

  final related = <String>{
    if (selectedTapId != null) pedigreeEdgeBaseId(selectedTapId),
    for (final id in focusTapIds) pedigreeEdgeBaseId(id),
  };

  // lineage 边按 (家族, 子代世代) 分组；记录哪些组已经「密」到要抽稀。
  final groupOf = <PedigreeEdge, String>{};
  final groupSize = <String, int>{};
  for (final e in edges) {
    if (e.kind != PedigreeEdgeKind.lineage) continue;
    final child = nodesById[baseOf(e, from: false)];
    final key = child == null ? '?' : '${child.familyId}:${child.generation}';
    groupOf[e] = key;
    groupSize[key] = (groupSize[key] ?? 0) + 1;
  }
  final denseKeys = <String>{
    for (final entry in groupSize.entries)
      if (entry.value > kPedigreeDenseLineageLimit &&
          !expandedGroupKeys.contains(entry.key))
        entry.key
  };

  // 密线组的主干落点：代表桶（最高概率；同概率取基因型字母序）。
  final spineTargets = <String>{};
  if (denseKeys.isNotEmpty) {
    final best = <String, PedigreeNode>{};
    for (final e in edges) {
      if (e.kind != PedigreeEdgeKind.lineage) continue;
      if (!denseKeys.contains(groupOf[e])) continue;
      final n = nodesById[baseOf(e, from: false)];
      if (n == null || n.isLethal || n.isExternal) continue;
      final cur = best[groupOf[e]!];
      if (cur == null ||
          n.probability > cur.probability ||
          (n.probability == cur.probability &&
              n.genotype.compareTo(cur.genotype) < 0)) {
        best[groupOf[e]!] = n;
      }
    }
    for (final n in best.values) {
      spineTargets.add(n.id);
    }
  }

  // 选中/聚焦元素沿代表祖先逐代向上的可追踪链。
  final spineAncestors =
      _spineAncestors(edges, nodesById, related, denseKeys);

  final out = <PedigreeEdge>[];
  for (final e in edges) {
    if (e.kind != PedigreeEdgeKind.lineage) {
      out.add(e); // mating（含手连回交）全留
      continue;
    }
    final key = groupOf[e];
    if (key == null || !denseKeys.contains(key)) {
      out.add(e);
      continue;
    }
    final from = baseOf(e, from: true);
    final to = baseOf(e, from: false);
    if (related.contains(from) ||
        related.contains(to) ||
        spineTargets.contains(to) ||
        spineAncestors.contains(from) ||
        spineAncestors.contains(to)) {
      out.add(e);
    }
  }
  return out;
}

/// 从 [related] 出发，沿 lineage 边向上每代只取一个代表祖先，形成
/// 一条可逐代追踪的链（返回链上祖先 id 集合，不含 related 自身）。
/// 只用于密线组——非密线组本来就全留。
Set<String> _spineAncestors(
  List<PedigreeEdge> edges,
  Map<String, PedigreeNode> nodesById,
  Set<String> related,
  Set<String> denseKeys,
) {
  final spine = <String>{};
  if (related.isEmpty || denseKeys.isEmpty) return spine;
  var frontier = <String>{...related};
  for (var step = 0; step < 24 && frontier.isNotEmpty; step++) {
    final picked = <String, String>{}; // (家族:世代) → 该代代表祖先 id
    for (final e in edges) {
      if (e.kind != PedigreeEdgeKind.lineage) continue;
      final to = pedigreeEdgeBaseId(e.toId);
      if (!frontier.contains(to)) continue;
      final from = pedigreeEdgeBaseId(e.fromId);
      final n = nodesById[from];
      final key = n == null ? '?$from' : '${n.familyId}:${n.generation}';
      picked.putIfAbsent(key, () => from);
    }
    if (picked.isEmpty) break;
    final next = <String>{
      for (final id in picked.values)
        if (!spine.contains(id) && !related.contains(id)) id
    };
    if (next.isEmpty) break;
    spine.addAll(next);
    frontier = next;
  }
  return spine;
}
