// evolution_chart.dart —— 进化树 CustomPainter 图表（v2.12 Wave 3-A 进化页图表化）
//
// 场景：lib/pages/evolution_page.dart 进化·基因频率页顶部插入本图表，
// 替代原「共同祖先证据 / 现代生物进化理论 / 物种形成」三个纯文字分区
// 的"先导图"，把抽象概念变成可视化时间树。
//
// 设计要点：
// - 纯 CustomPainter widget，**不引入新依赖**（只走 Flutter 自身
//   dart:ui + material）。三端通用。
// - 输入：List<EvolutionNode>（id / parent / generation / trait）。
//   parent 为 null = 根；parent 引用的 id 不在 nodes 中时按「无父
//   连线降级」处理（节点仍渲染，不抛异常）。自环 / 环引用同样降级。
// - 布局：水平时间轴（gen=min 在左 → gen=max 在右）+ **树状分层**
//   y（叶子按 id 序占行，父节点取子节点行的中点 ⇒ 兄弟分行、父节点
//   居中于子节点之间，不会被读成一条直系链）。
//   （v2.20 修复：旧版按「同代内序号」排 y，导致 gen1/2/3 全部落在
//   同一行，root→真核→动物→脊椎动物 看起来像直系链，与 parent
//   数据矛盾。）
// - 节点：r=10 圆形，描边 teal 配色，填充 tealWash 强调。
// - trait 标签：节点**右侧**水平排列（与文件头一致）。右侧放不下时
//   按可用宽度省略号截断（不压圆盘、不越画布）；右侧连可用宽度都
//   没有（极窄画布 / 单列）时收到节点上（下）方。
//   标签底边抬到节点水平轴之上 2px ⇒ 父→子折线的水平段不会划穿文字。
//   （v2.20 修复：旧版把标签水平居中画在圆心，圆盘盖住中间的字。）
// - 留 20px 水平边距 + 28px 顶部 / 36px 底部节点区 + 时间轴刻度行。
// - 空列表：返回最小尺寸 widget（64×64），不崩。

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme.dart';

/// 进化树节点（不可变）。
class EvolutionNode {
  /// 稳定唯一 id（如 'LUCA' / 'E1' / 'fish' / 'tetrapod'）。
  final String id;

  /// 父节点 id；null = 根节点。
  final String? parent;

  /// 世代（0 = 最早，n = 最新）。
  final int generation;

  /// 性状 / 节点标签文本。
  final String trait;

  const EvolutionNode({
    required this.id,
    required this.parent,
    required this.generation,
    required this.trait,
  });
}

/// trait 标签相对节点圆盘的落位。
enum EvolutionLabelSide {
  /// 节点右侧（默认）。
  right,

  /// 节点上方 / 下方（右侧挤不出可用宽度时的极窄兜底）。
  above,
}

/// 进化树几何布局结果（节点圆心 + 标签矩形 + 代际 x 映射）。
///
/// 从 painter 里抽出来，便于纯 Dart 单元测试直接断言
/// 「标签不压圆盘 / 不越界 / 父子拓扑位置正确」，不必截图比对。
class EvolutionChartGeometry {
  const EvolutionChartGeometry({
    required this.positions,
    required this.labelRects,
    required this.labelSides,
    required this.generationX,
    required this.branchMidX,
  });

  /// 空图（无节点）。
  static const EvolutionChartGeometry empty = EvolutionChartGeometry(
    positions: <String, Offset>{},
    labelRects: <String, Rect>{},
    labelSides: <String, EvolutionLabelSide>{},
    generationX: <int, double>{},
    branchMidX: <String, double>{},
  );

  /// 节点 id → 圆心坐标。
  final Map<String, Offset> positions;

  /// 节点 id → 标签绘制矩形（已 clamp 在画布内、与圆盘不重叠）。
  final Map<String, Rect> labelRects;

  /// 节点 id → 标签落位（右 / 上）。
  final Map<String, EvolutionLabelSide> labelSides;

  /// 代际 → 该代的 x 中心。
  final Map<int, double> generationX;

  /// 子节点 id → 父→子折线中段竖线的 x（已避开父节点标签）。
  ///
  /// 缺省（同列 / 逆向 / 父缺失）表示直连两点、无中段。
  final Map<String, double> branchMidX;

  /// 节点圆盘半径（painter 与测试共用，避免两处常量漂移）。
  static const double nodeRadius = 10;

  /// 单节点圆盘的外接矩形（供测试与命中判断复用）。
  static Rect circleRect(Offset center) =>
      Rect.fromCircle(center: center, radius: nodeRadius);
}

/// 进化树图表 widget。
///
/// 接受 [nodes]（树状序列）+ 可选 [height]（默认 220）。
/// 用 [RepaintBoundary] 包一层便于未来扩截图（与 v2.4 png_export
/// 的 boundaryKey 模式一致）。
class EvolutionChart extends StatelessWidget {
  const EvolutionChart({
    super.key,
    required this.nodes,
    this.height = 220,
  });

  final List<EvolutionNode> nodes;
  final double height;

  @override
  Widget build(BuildContext context) {
    if (nodes.isEmpty) {
      // 空态：固定最小尺寸，避免父 ListView 高度坍塌。
      return SizedBox(
        height: 64,
        child: Center(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.account_tree_outlined,
                  size: 18, color: AppColors.steel),
              const SizedBox(width: 6),
              Text('（暂无进化树节点）', style: AppText.caption),
            ],
          ),
        ),
      );
    }
    return RepaintBoundary(
      child: SizedBox(
        height: height,
        width: double.infinity,
        child: CustomPaint(
          painter: EvolutionChartPainter(
            nodes: nodes,
            inkColor: AppColors.ink,
            tealColor: AppColors.teal,
            tealWashColor: AppColors.tealWash,
            graphiteColor: AppColors.graphite,
            borderColor: AppColors.border,
            onTeal: AppColors.onTeal,
          ),
        ),
      ),
    );
  }
}

class EvolutionChartPainter extends CustomPainter {
  EvolutionChartPainter({
    required this.nodes,
    required this.inkColor,
    required this.tealColor,
    required this.tealWashColor,
    required this.graphiteColor,
    required this.borderColor,
    required this.onTeal,
  });

  final List<EvolutionNode> nodes;
  final Color inkColor;
  final Color tealColor;
  final Color tealWashColor;
  final Color graphiteColor;
  final Color borderColor;
  final Color onTeal;

  // 几何常量
  static const double _marginX = 20; // 左右留白
  static const double _marginTop = 28; // 节点区上沿
  static const double _marginBottom = 36; // 节点区下沿（下方留给时间轴）
  static const double _axisFromBottom = 20; // 时间轴 baseline 距底边
  static const double _nodeR = EvolutionChartGeometry.nodeRadius;
  static const double _labelGap = 8; // 节点 → 标签间距
  static const double _pad = 4; // 标签离画布边缘的最小距离
  static const double _labelLift = 2; // 标签底边离节点水平轴的距离
  static const double _minLabelWidth = 28; // 低于此宽度视为「放不下」

  /// 时间轴 baseline 的 y。
  double _axisY(Size size) => size.height - _axisFromBottom;

  /// 标签可用区的下沿（不压时间轴刻度）。
  double _labelBottom(Size size) => _axisY(size) - 4;

  /// 计算整张图的几何：节点圆心、标签矩形、代际 x。
  ///
  /// 纯函数（不依赖 canvas），公开以便单元测试。
  EvolutionChartGeometry computeGeometry(Size size) {
    if (nodes.isEmpty) return EvolutionChartGeometry.empty;

    // 1) id → 节点。重复 id 取最后一个（与旧版 posOf 覆盖语义一致）。
    final byId = <String, EvolutionNode>{};
    for (final n in nodes) {
      byId[n.id] = n;
    }

    // 2) 建父子索引。根 / 自环 / 父缺失 → 独立根（降级，不抛）。
    final childrenOf = <String, List<EvolutionNode>>{};
    final roots = <EvolutionNode>[];
    for (final n in byId.values) {
      final p = n.parent;
      if (p == null || p == n.id || !byId.containsKey(p)) {
        roots.add(n);
      } else {
        childrenOf.putIfAbsent(p, () => <EvolutionNode>[]).add(n);
      }
    }
    roots.sort((a, b) => a.id.compareTo(b.id));
    for (final list in childrenOf.values) {
      list.sort((a, b) => a.id.compareTo(b.id));
    }

    // 3) 树状分层：叶子按序遍历占行，父节点取子节点行的中点。
    //    ⇒ 兄弟分行、父节点居中于其间，父子关系一眼可读。
    final rowOf = <String, double>{};
    var nextLeafRow = 0.0;

    double assignRow(EvolutionNode node, Set<String> path) {
      final known = rowOf[node.id];
      if (known != null) return known;
      if (!path.add(node.id)) return 0.0; // 环兜底：重复进场不做行分配
      final kids = childrenOf[node.id] ?? const <EvolutionNode>[];
      double row;
      if (kids.isEmpty) {
        row = nextLeafRow;
        nextLeafRow += 1;
      } else {
        var lo = double.infinity;
        var hi = -double.infinity;
        for (final k in kids) {
          final r = assignRow(k, path);
          if (r < lo) lo = r;
          if (r > hi) hi = r;
        }
        row = (lo + hi) / 2;
      }
      path.remove(node.id);
      rowOf[node.id] = row;
      return row;
    }

    for (final r in roots) {
      assignRow(r, <String>{});
    }
    // 环内节点从根不可达：单独当根兜底，仍然不抛。
    final leftover = byId.values
        .where((n) => !rowOf.containsKey(n.id))
        .toList()
      ..sort((a, b) => a.id.compareTo(b.id));
    for (final n in leftover) {
      assignRow(n, <String>{});
    }

    // 4) x：按代际均分（末代右侧留一列宽度给标签）。
    final gens = byId.values.map((n) => n.generation).toSet().toList()..sort();
    final minGen = gens.first;
    final maxGen = gens.last;
    final span = maxGen - minGen;
    final columnStep =
        span <= 0 ? 0.0 : (size.width - 2 * _marginX) / (span + 1);
    final generationX = <int, double>{
      for (final g in gens)
        g: span <= 0 ? size.width / 2 : _marginX + (g - minGen) * columnStep,
    };

    // 5) y：行号 → 像素。
    final maxRow = rowOf.values.fold<double>(0, (m, r) => r > m ? r : m);
    final top = _marginTop;
    final bottom = math.max(top, size.height - _marginBottom);
    final rowStep = maxRow <= 0 ? 0.0 : (bottom - top) / maxRow;

    final positions = <String, Offset>{};
    for (final n in byId.values) {
      final row = rowOf[n.id] ?? 0;
      positions[n.id] = Offset(
        generationX[n.generation] ?? size.width / 2,
        maxRow <= 0 ? (top + bottom) / 2 : top + row * rowStep,
      );
    }

    // 6) 标签：优先排在节点右侧；右侧挤不出可用宽度时收到节点上（下）方。
    final labelRects = <String, Rect>{};
    final labelSides = <String, EvolutionLabelSide>{};
    final ordered = byId.values.toList()
      ..sort((a, b) {
        final g = a.generation.compareTo(b.generation);
        if (g != 0) return g;
        return a.id.compareTo(b.id);
      });

    final bottomLimit = _labelBottom(size);

    for (final n in ordered) {
      final pos = positions[n.id];
      if (pos == null) continue;

      final natural = _layoutLabel(n.trait, double.infinity);
      final naturalW = natural.width;
      final naturalH = natural.height;
      natural.dispose();

      final rightAnchor = pos.dx + _nodeR + _labelGap;
      // 右侧空间：避开「下一列」的节点圆盘；已是末代则用到画布右沿。
      final hasNextColumn = columnStep > 0 && n.generation != maxGen;
      final rightLimit = hasNextColumn
          ? math.min(size.width - _pad,
              pos.dx + columnStep - _nodeR - _labelGap)
          : size.width - _pad;
      final avail = rightLimit - rightAnchor;

      if (avail < _minLabelWidth) {
        // 右侧挤不出可用宽度（极窄画布 / 单列）：标签收到节点上（下）方。
        final boxW = math.min(naturalW, math.max(size.width - 2 * _pad, 0.0));
        final above = pos.dy - _nodeR - _labelGap - naturalH >= _pad;
        final dyRaw = above
            ? pos.dy - _nodeR - _labelGap - naturalH
            : pos.dy + _nodeR + _labelGap;
        final maxLeft = math.max(_pad, size.width - _pad - boxW);
        final maxTop = math.max(_pad, bottomLimit - naturalH);
        labelRects[n.id] = Rect.fromLTWH(
          (pos.dx - boxW / 2).clamp(_pad, maxLeft),
          dyRaw.clamp(_pad, maxTop),
          boxW,
          naturalH,
        );
        labelSides[n.id] = EvolutionLabelSide.above;
        continue;
      }

      // 放得下就用自然宽度；放不下按可用宽度省略号截断（不压圆盘、不越界）。
      final tp = _layoutLabel(n.trait, math.min(avail, naturalW));
      final boxW = tp.width; // 可能因省略号缩短
      final boxH = tp.height;
      tp.dispose();

      final maxLeft = math.max(_pad, size.width - _pad - boxW);
      final maxTop = math.max(_pad, bottomLimit - boxH);
      // 底边抬到节点水平轴之上：父→子折线的水平段与文字不再叠压。
      labelRects[n.id] = Rect.fromLTWH(
        rightAnchor.clamp(_pad, maxLeft),
        (pos.dy - _labelLift - boxH).clamp(_pad, maxTop),
        boxW,
        boxH,
      );
      labelSides[n.id] = EvolutionLabelSide.right;
    }

    return EvolutionChartGeometry(
      positions: positions,
      labelRects: labelRects,
      labelSides: labelSides,
      generationX: generationX,
      branchMidX: _computeBranchMidX(
        ordered: ordered,
        positions: positions,
        labelRects: labelRects,
      ),
    );
  }

  /// 父子折线「中段竖线」的 x：默认取两列中点；若会划穿父节点标签，
  /// 右移到标签右沿 + gap 之外（仍保持在子节点左沿以内）。
  Map<String, double> _computeBranchMidX({
    required List<EvolutionNode> ordered,
    required Map<String, Offset> positions,
    required Map<String, Rect> labelRects,
  }) {
    final midOf = <String, double>{};
    for (final n in ordered) {
      final p = n.parent;
      if (p == null || p == n.id) continue;
      final parentPos = positions[p];
      final childPos = positions[n.id];
      if (parentPos == null || childPos == null) continue;
      final px = parentPos.dx + _nodeR;
      final cx = childPos.dx - _nodeR;
      if (cx - px < 2) continue; // 同列 / 逆向：直连，无中段
      var mid = (px + cx) / 2;
      final labelRight = labelRects[p]?.right;
      if (labelRight != null) {
        final floor = labelRight + _labelGap;
        // 标签右沿之外仍有两列间的空地：竖直段贴到子节点左沿
        // （正交树的常见走法），既不划穿文字也不压圆盘。
        if (mid < floor) mid = math.min(floor, cx);
      }
      if (mid < px) mid = px;
      midOf[n.id] = mid;
    }
    return midOf;
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (nodes.isEmpty) return; // 空图不画时间轴（widget 层已走占位文案）
    final geo = computeGeometry(size);

    // 按 (generation, id) 稳定排序，便于 diff。
    final sortedNodes = [...nodes]..sort((a, b) {
        final g = a.generation.compareTo(b.generation);
        if (g != 0) return g;
        return a.id.compareTo(b.id);
      });

    // 1) 时间轴（水平 baseline + 刻度标签）。
    _drawTimeAxis(canvas, size, geo);

    // 2) 连线（父→子折线）。仅在父节点存在时画。
    final edgePaint = Paint()
      ..color = graphiteColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    for (final n in sortedNodes) {
      final p = n.parent;
      if (p == null) continue;
      final childPos = geo.positions[n.id];
      final parentPos = geo.positions[p];
      if (childPos == null || parentPos == null) continue; // 父缺失降级
      _drawBranch(canvas, parentPos, childPos, edgePaint,
          geo.branchMidX[n.id]);
    }

    // 3) 节点（圆 + 标签）。先圆后文字，节点压住线段端点。
    final fillPaint = Paint()..color = tealWashColor;
    final strokePaint = Paint()
      ..color = tealColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8;
    for (final n in sortedNodes) {
      final pos = geo.positions[n.id];
      if (pos == null) continue;
      canvas.drawCircle(pos, _nodeR, fillPaint);
      canvas.drawCircle(pos, _nodeR, strokePaint);

      final rect = geo.labelRects[n.id];
      if (rect == null) continue;
      // 与 computeGeometry 同参数重排一次，保证宽度/可读性一致。
      final tp = _layoutLabel(n.trait, rect.width);
      tp.paint(canvas, rect.topLeft);
      tp.dispose();
    }
  }

  /// trait 标签排版（单行 + 省略号）。
  TextPainter _layoutLabel(String text, double maxWidth) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: AppText.caption.copyWith(
          color: inkColor,
          fontWeight: FontWeight.w600,
          fontSize: 12,
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: '…',
    );
    tp.layout(
      maxWidth: maxWidth.isFinite ? math.max(maxWidth, 0.0) : maxWidth,
    );
    return tp;
  }

  /// 水平时间轴：底边线 + 代际刻度文字。
  void _drawTimeAxis(Canvas canvas, Size size, EvolutionChartGeometry geo) {
    final axisPaint = Paint()
      ..color = borderColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;
    final y = _axisY(size);
    canvas.drawLine(
      Offset(_marginX, y),
      Offset(size.width - _marginX, y),
      axisPaint,
    );

    final gens = geo.generationX.keys.toList()..sort();
    for (final g in gens) {
      final x = geo.generationX[g]!;
      // 刻度线
      canvas.drawLine(Offset(x, y - 3), Offset(x, y + 3), axisPaint);
      // 标签
      final label = g == 0 ? '起点' : '第 $g 代';
      final tp = TextPainter(
        text: TextSpan(
          text: label,
          style: AppText.caption.copyWith(
            color: graphiteColor,
            fontSize: 11,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(
        canvas,
        Offset(
          (x - tp.width / 2).clamp(_pad, size.width - _pad - tp.width),
          y + 4,
        ),
      );
      tp.dispose();
    }
  }

  /// 父→子折线：父右沿 → 中段竖线 → 子左沿。
  ///
  /// [midX] 由 [computeGeometry] 给（已避开父节点标签）；缺省取两列中点。
  void _drawBranch(
    Canvas canvas,
    Offset parent,
    Offset child,
    Paint paint, [
    double? midX,
  ]) {
    final px = parent.dx + _nodeR;
    final cx = child.dx - _nodeR;
    if (cx - px < 2) {
      // 同列 / 逆向（代际数据不一致）：直连两点，避免折线自交。
      canvas.drawLine(parent, child, paint);
      return;
    }
    var mid = midX ?? (px + cx) / 2;
    if (mid < px) mid = px;
    if (mid > cx) mid = cx;
    final path = Path()
      ..moveTo(px, parent.dy)
      ..lineTo(mid, parent.dy)
      ..lineTo(mid, child.dy)
      ..lineTo(cx, child.dy);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant EvolutionChartPainter old) {
    return old.nodes != nodes ||
        old.inkColor != inkColor ||
        old.tealColor != tealColor;
  }
}
