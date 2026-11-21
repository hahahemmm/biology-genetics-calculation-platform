// pedigree_chart.dart —— 标准系谱图渲染器（v2.13+）
//
// 课本规范：男性=方框，女性=圆形，患者=实心填充，正常=空心；
// 世代自上而下分层（I 代在最上）；夫妻之间横线，亲子之间竖线+
// 横线（「T」形）。推断器录入成员后实时呈现——教师看一眼即知
// 录入对不对，且可导出 PNG 当作业/试卷插图（出题神器）。
//
// 布局算法（v1，诚实文档）：按世代分行，行内按录入顺序等距排位；
// 婚姻线 = 两亲本图形之间的水平线，亲子线 = 婚姻线中点垂直到子代行。
// 极端乱序录入会产生交叉线——已知限制，引导「按世代顺序录入」。

import 'package:flutter/material.dart';

import '../engine/pedigree_inference.dart';
import '../theme.dart';

/// 系谱图 widget（固定高度，宽度撑满）。导出 PNG 时外层包
/// RepaintBoundary 已由本组件内置。
class PedigreeChart extends StatelessWidget {
  const PedigreeChart({
    super.key,
    required this.members,
    required this.relations,
    required this.genOf,
    this.height = 170,
  });

  final List<PdMember> members;
  final List<PdRelation> relations;

  /// 代际推导函数（宿主 view 的 _genOf，保持单一事实源）。
  final int Function(PdMember) genOf;

  final double height;

  @override
  Widget build(BuildContext context) {
    if (members.isEmpty) return const SizedBox.shrink();
    return RepaintBoundary(
      child: SizedBox(
        height: height,
        width: double.infinity,
        child: CustomPaint(
          painter: PedigreeChartPainter(
            members: members,
            relations: relations,
            genOf: genOf,
            inkColor: AppColors.ink,
            borderColor: AppColors.border,
            canvasColor: AppColors.surface,
          ),
        ),
      ),
    );
  }
}

class PedigreeChartPainter extends CustomPainter {
  PedigreeChartPainter({
    required this.members,
    required this.relations,
    required this.genOf,
    required this.inkColor,
    required this.borderColor,
    required this.canvasColor,
  });

  final List<PdMember> members;
  final List<PdRelation> relations;
  final int Function(PdMember) genOf;
  final Color inkColor;
  final Color borderColor;
  final Color canvasColor;

  @override
  void paint(Canvas canvas, Size size) {
    // 背景（导出 PNG 打印友好：近白底）。
    canvas.drawRect(Offset.zero & size, Paint()..color = canvasColor);

    final rows = <int, List<PdMember>>{};
    for (final m in members) {
      rows.putIfAbsent(genOf(m), () => []).add(m);
    }
    final gens = rows.keys.toList()..sort();
    if (gens.isEmpty) return;
    final rowCount = gens.last + 1;

    final rowH = size.height / (rowCount + 0.6);
    const r = 12.0; // 方形半边长 / 圆半径
    final centers = <String, Offset>{};
    for (final g in gens) {
      final list = rows[g]!;
      final y = rowH * (g + 0.5);
      for (var i = 0; i < list.length; i++) {
        final x = size.width * (i + 1) / (list.length + 1);
        centers[list[i].id] = Offset(x, y);
      }
    }

    final parentsOf = <String, List<String>>{};
    for (final rel in relations) {
      parentsOf.putIfAbsent(rel.childId, () => []).add(rel.parentId);
    }

    final linePaint = Paint()
      ..color = inkColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;

    // 双亲（≥2）：婚姻横线 + 「T」形亲子线。
    for (final entry in parentsOf.entries) {
      if (entry.value.length < 2) continue;
      final a = centers[entry.value[0]];
      final b = centers[entry.value[1]];
      final childC = centers[entry.key];
      if (a == null || b == null || childC == null) continue;
      final midY = (a.dy + b.dy) / 2;
      canvas.drawLine(Offset(a.dx, midY), Offset(b.dx, midY), linePaint);
      final midX = (a.dx + b.dx) / 2;
      canvas.drawLine(Offset(midX, midY), Offset(midX, childC.dy), linePaint);
      canvas.drawLine(
          Offset(midX, childC.dy), Offset(childC.dx, childC.dy), linePaint);
    }
    // 单亲：直接连线（事实单亲也能表达）。
    for (final entry in parentsOf.entries) {
      if (entry.value.length >= 2) continue;
      final p = centers[entry.value.first];
      final c = centers[entry.key];
      if (p == null || c == null) continue;
      canvas.drawLine(p, c, linePaint);
    }

    // 成员图形：男=方、女=圆；患病=实心、正常=空心。
    final outlinePaint = Paint()
      ..color = inkColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6;
    for (final m in members) {
      final c = centers[m.id]!;
      final paint = Paint()
        ..color = m.isAffected ? inkColor : canvasColor
        ..style = m.isAffected ? PaintingStyle.fill : PaintingStyle.stroke
        ..strokeWidth = 1.6;
      if (m.sex == PdSex.male) {
        final rect =
            Rect.fromCenter(center: c, width: r * 2, height: r * 2);
        canvas.drawRect(rect, paint);
        if (!m.isAffected) canvas.drawRect(rect, outlinePaint);
      } else {
        canvas.drawCircle(c, r, paint);
        if (!m.isAffected) canvas.drawCircle(c, r, outlinePaint);
      }
      // id 标注（导出后教师可辨）。
      final tp = TextPainter(
        text: TextSpan(
          text: m.id,
          style: AppText.caption.copyWith(
              color: inkColor,
              fontSize: 10,
              fontWeight: FontWeight.w600),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(c.dx - tp.width / 2, c.dy + r + 2));
    }

    // 世代标签（I/II/III… 行左侧）。
    for (final g in gens) {
      final tp = TextPainter(
        text: TextSpan(
          text: _roman(g + 1),
          style: AppText.caption.copyWith(color: borderColor, fontSize: 10),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(4, rowH * (g + 0.5) - tp.height / 2));
    }
  }

  /// 罗马数字（I..VIII 够用）。
  static String _roman(int n) {
    const table = ['I', 'II', 'III', 'IV', 'V', 'VI', 'VII', 'VIII'];
    return n <= table.length ? table[n - 1] : '$n';
  }

  @override
  bool shouldRepaint(covariant PedigreeChartPainter old) {
    return old.members != members ||
        old.relations != relations ||
        old.genOf != genOf;
  }
}
