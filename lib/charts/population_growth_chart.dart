// population_growth_chart.dart —— 种群增长对照折线图（J 型 / S 型共用坐标轴）
//
// 场景：进化页第 6 页签「种群增长」把两条曲线画在同一张图上——
// 横轴是代数 t、纵轴是种群数量 N，学生一眼看出「J 型一路往上冲、
// S 型趋近 K」的差别。
//
// 设计要点（对齐 frequency_curve_chart.dart 的纪律）：
// - 纯 CustomPainter，零新依赖，三端通用。
// - **不复用 FrequencyCurveChart**：那张图的 y 轴固定 0..1（频率语义），
//   种群数量的量级差几个数量级，硬套只会得到一条贴着底边的假曲线。
//   本图按数据自动取 y 上限（[PopulationGrowthChartPainter.niceYCeil]），
//   并把 K / K/2 参考线一起算进上限 ⇒ 参考线永远画得下。
// - 参考线（K、K/2）用虚线 + 参考线标签，语义与 UI 文案一致：只画在
//   数据真的覆盖到的范围内，不凭空延长。
// - 空序列 / 单点 / 极窄画布都不崩：空数据画居中提示，单点只画一个点。
// - 位置计算抽成 public 方法（[plotRect] / [yForValue] / [pointFor]），
//   测试不必读像素就能钉住「数据点不越界」「K 参考线位置正确」。

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme.dart';

/// 一条折线（J 型或 S 型）。
class GrowthSeries {
  const GrowthSeries({
    required this.label,
    required this.values,
    required this.color,
  });

  final String label;
  final List<double> values;
  final Color color;
}

/// 一条水平参考线（K / K/2）。
class GrowthReference {
  const GrowthReference({
    required this.value,
    required this.label,
    required this.color,
  });

  final double value;

  /// 参考线标签（如「K = 1000」），⛔ 由调用方给完整文案，本图不拼单位。
  final String label;
  final Color color;
}

/// 参考线标签的几何（文字 origin + 不透明底衬矩形）。
///
/// 抽成公开返回值只为**可测**：守卫测试用它断言「底衬完全包住文字区、
/// 不越出画布、且画序在全部曲线之后」，从而不必读像素。
class GrowthReferenceLabelLayout {
  const GrowthReferenceLabelLayout({
    required this.painter,
    required this.origin,
    required this.backing,
  });

  /// 已 layout 好的文字（宽度 = [textRect] 的宽）。
  final TextPainter painter;
  final Offset origin;

  /// 不透明底衬（含 padding），四边都包住 [textRect]。
  final Rect backing;

  Rect get textRect =>
      Rect.fromLTWH(origin.dx, origin.dy, painter.width, painter.height);
}

/// J 型 / S 型对照折线图。
class PopulationGrowthChart extends StatelessWidget {
  const PopulationGrowthChart({
    super.key,
    required this.series,
    this.references = const <GrowthReference>[],
    this.height = 220,
    this.xLabel = '代数 t',
    this.emptyText = '（暂无种群数量数据）',
  });

  final List<GrowthSeries> series;
  final List<GrowthReference> references;
  final double height;
  final String xLabel;
  final String emptyText;

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: SizedBox(
        height: height,
        width: double.infinity,
        child: CustomPaint(
          painter: PopulationGrowthChartPainter(
            series: series,
            references: references,
            inkColor: AppColors.ink,
            graphiteColor: AppColors.graphite,
            steelColor: AppColors.steel,
            borderColor: AppColors.border,
            // 参考线标签底衬用**卡片底色**（不透明）：标签最后画时把
            // 底下的虚线/曲线尾段盖掉，读起来是「标签干净地压在上面」。
            backgroundColor: AppColors.surface,
            xLabel: xLabel,
            emptyText: emptyText,
          ),
        ),
      ),
    );
  }
}

class PopulationGrowthChartPainter extends CustomPainter {
  PopulationGrowthChartPainter({
    required this.series,
    required this.references,
    required this.inkColor,
    required this.graphiteColor,
    required this.steelColor,
    required this.borderColor,
    required this.xLabel,
    this.backgroundColor = const Color(0xFFFBF9F5),
    this.emptyText = '（暂无种群数量数据）',
  });

  final List<GrowthSeries> series;
  final List<GrowthReference> references;
  final Color inkColor;
  final Color graphiteColor;
  final Color steelColor;
  final Color borderColor;
  final String xLabel;
  final String emptyText;

  /// 参考线标签底衬色（调用方给卡片 surface；⛔ 必须不透明，
  /// 半透明底衬会把曲线透出来 = 标签仍被划穿）。
  final Color backgroundColor;

  static const double marginLeft = 52; // y 轴刻度留宽
  static const double marginRight = 14;
  static const double marginTop = 12;
  static const double marginBottom = 28; // x 轴刻度行 + 单位标签行

  /// 轴文字的行高（`height: 1.0` 的 10px 字 —— 两行才能塞进 28px 底边距）。
  static const double axisTextHeight = 10;

  /// 刻度数字相对绘图区底边的行顶偏移。
  static const double xTickLabelTop = 5;

  /// x 轴单位标签的行顶偏移（⛔ 必须 ≥ [xTickLabelTop] + [axisTextHeight]：
  /// 与末代刻度同一行会左右撞在一起，实测过一次）。
  static const double xUnitLabelTop = 16;

  /// 画布上真的有数据要画吗（空数据只画提示，不画坐标轴）。
  bool get hasData => series.any((s) => s.values.isNotEmpty);

  /// 所有序列里最大的下标（决定 x 轴范围；空数据 = 0）。
  int get maxIndex {
    var m = 0;
    for (final s in series) {
      final last = s.values.length - 1;
      if (last > m) m = last;
    }
    return m;
  }

  /// y 轴上限：数据与参考线一起取「好看的」天花板。
  double get yMax {
    var raw = 0.0;
    for (final s in series) {
      for (final v in s.values) {
        if (v.isFinite && v > raw) raw = v;
      }
    }
    for (final r in references) {
      if (r.value.isFinite && r.value > raw) raw = r.value;
    }
    return niceYCeil(raw);
  }

  /// 「好看的」y 上限：留 2% 余量后向上取到 1/1.2/1.5/2/…×10ⁿ 档。
  ///
  /// 留余量是为了不让最高的点正好压在顶边框上（描边会被裁掉一半）。
  static double niceYCeil(double raw) {
    if (!raw.isFinite || raw <= 0) return 1;
    const steps = <double>[1, 1.2, 1.5, 2, 2.5, 3, 4, 5, 6, 8, 10];
    final target = raw * 1.02;
    final exp = (math.log(target) / math.ln10).floor();
    final base = math.pow(10.0, exp).toDouble();
    final norm = target / base;
    for (final s in steps) {
      if (norm <= s + 1e-9) return s * base;
    }
    return 10 * base;
  }

  /// 绘图区（不含轴外侧留白）。
  Rect plotRect(Size size) => Rect.fromLTRB(
        marginLeft,
        marginTop,
        math.max(marginLeft, size.width - marginRight),
        math.max(marginTop, size.height - marginBottom),
      );

  /// 第 [index] 代对应的 x 坐标（[maxIndex] 传曲线最大下标）。
  double xForIndex(int index, int maxIndex, Size size) {
    final rect = plotRect(size);
    if (maxIndex <= 0) return rect.left;
    final f = (index / maxIndex).clamp(0.0, 1.0);
    return rect.left + rect.width * f;
  }

  /// 数量 [value] 对应的 y 坐标（0 在底、[yMax] 在顶）。
  double yForValue(double value, Size size) {
    final rect = plotRect(size);
    final f = (value / yMax).clamp(0.0, 1.0);
    return rect.bottom - rect.height * f;
  }

  /// 一个数据点的坐标（测试用来断言「不越界 / 大 N 在上」）。
  Offset pointFor(int index, int maxIndex, double value, Size size) =>
      Offset(xForIndex(index, maxIndex, size), yForValue(value, size));

  /// x 轴单位标签的左上角落位（宽由字宽决定，由调用方量）。
  ///
  /// 测试用它做几何断言：单位标签行必须整体落在刻度行下方，
  /// 且底边不越出画布（[marginBottom] 只够两行 10px 字）。
  Offset xUnitLabelOrigin(Size size, double textWidth) => Offset(
        plotRect(size).right - textWidth,
        plotRect(size).bottom + xUnitLabelTop,
      );

  /// 参考线标签的底衬内边距（水平 / 垂直）。
  static const double labelPadH = 4;
  static const double labelPadV = 2;

  /// 参考线标签的落位与底衬。
  ///
  /// 位置策略：**左上区内侧**（增长曲线都从左边低处起步，K 线左段通常
  /// 空白）；参考线贴近顶边（< 22% 高度）时改画在线**下方**，避免压住
  /// 左上角图例。底衬 = 文字区 + [labelPadH]/[labelPadV]，右/下边夹进画布。
  GrowthReferenceLabelLayout referenceLabelLayout(
      GrowthReference ref, Size size) {
    final tp = _tp(ref.label, color: ref.color, weight: FontWeight.w600);
    final rect = plotRect(size);
    final y = yForValue(ref.value, size);
    final left = rect.left + 6;
    var top = y < rect.top + rect.height * 0.22
        ? y + 2 // 贴近顶边 ⇒ 画在线下方（让开图例）
        : y - tp.height - 2; // 常规：画在线上方
    top = top.clamp(0.0, math.max(0.0, size.height - tp.height - labelPadV));
    final backing = Rect.fromLTRB(
      left - labelPadH,
      top - labelPadV,
      math.min(left + tp.width + labelPadH, size.width),
      math.min(top + tp.height + labelPadV, size.height),
    );
    return GrowthReferenceLabelLayout(
      painter: tp,
      origin: Offset(left, top),
      backing: backing,
    );
  }

  @override
  void paint(Canvas canvas, Size size) {
    final rect = plotRect(size);
    if (rect.width <= 1 || rect.height <= 1) return;
    if (!hasData) {
      _paintCentered(canvas, size, emptyText);
      return;
    }

    final top = yMax;
    final gridPaint = Paint()
      ..color = borderColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8;

    // 1) 横向网格 + y 轴刻度（0 / 25% / 50% / 75% / 100%）。
    for (var i = 0; i <= 4; i++) {
      final value = top * i / 4;
      final y = yForValue(value, size);
      canvas.drawLine(Offset(rect.left, y), Offset(rect.right, y), gridPaint);
      final tp = _tp(axisLabel(value), color: graphiteColor);
      tp.paint(canvas, Offset(rect.left - tp.width - 6, y - tp.height / 2));
    }

    // 2) x 轴与刻度（最多 7 个，含首尾）。
    canvas.drawLine(
        Offset(rect.left, rect.bottom), Offset(rect.right, rect.bottom),
        gridPaint);
    final maxIdx = maxIndex;
    final step = maxIdx <= 6 ? 1 : (maxIdx / 6).ceil();
    final ticks = <int>{for (var t = 0; t <= maxIdx; t += step) t, maxIdx};
    for (final t in ticks) {
      final x = xForIndex(t, maxIdx, size);
      canvas.drawLine(Offset(x, rect.bottom), Offset(x, rect.bottom + 3),
          gridPaint);
      final tp = _tp('$t', color: graphiteColor);
      tp.paint(canvas,
          Offset(x - tp.width / 2, rect.bottom + xTickLabelTop));
    }
    // 单位标签单独一行（在刻度行下方），⛔ 不再与末代刻度挤同一行右端。
    final unit = _tp(xLabel, color: graphiteColor);
    unit.paint(
        canvas, Offset(rect.right - unit.width, rect.bottom + xUnitLabelTop));

    // 3) 参考线（K / K/2）：**只画虚线**。标签留到最后画——先画标签会被
    //    后画的 J/S 曲线划穿（M3.1 复核 P1 的原始缺陷）。
    final drawnRefs = <GrowthReference>[];
    for (final r in references) {
      if (!r.value.isFinite || r.value <= 0) continue;
      drawnRefs.add(r);
      final y = yForValue(r.value, size);
      _drawDashedLine(
        canvas,
        Offset(rect.left, y),
        Offset(rect.right, y),
        Paint()
          ..color = r.color.withValues(alpha: 0.75)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.1,
      );
    }

    // 4) 折线 + 每代圆点（首尾加大）。
    for (final s in series) {
      if (s.values.isEmpty) continue;
      final linePaint = Paint()
        ..color = s.color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round;
      final dotPaint = Paint()
        ..color = s.color
        ..style = PaintingStyle.fill;
      final path = Path();
      for (var i = 0; i < s.values.length; i++) {
        final p = pointFor(i, maxIdx, s.values[i], size);
        if (i == 0) {
          path.moveTo(p.dx, p.dy);
        } else {
          path.lineTo(p.dx, p.dy);
        }
      }
      canvas.drawPath(path, linePaint);
      for (var i = 0; i < s.values.length; i++) {
        final p = pointFor(i, maxIdx, s.values[i], size);
        final end = i == 0 || i == s.values.length - 1;
        canvas.drawCircle(p, end ? 3.2 : 2.0, dotPaint);
      }
    }

    // 5) 图例：左上角（增长曲线由左下往右上走，左上通常空白）。
    var legendX = rect.left + 6;
    final legendY = rect.top + 4;
    for (final s in series) {
      canvas.drawRect(
        Rect.fromLTWH(legendX, legendY + 4, 10, 3),
        Paint()..color = s.color,
      );
      final tp = _tp(s.label, color: inkColor, weight: FontWeight.w600);
      tp.paint(canvas, Offset(legendX + 14, legendY - 2));
      legendX += 14 + tp.width + 14;
    }

    // 6) 参考线标签**最后**画：先用不透明卡片底色铺一层底衬（盖住底下的
    //    虚线尾段与碰巧经过的曲线），再压文字。底衬与文字都夹在画布内，
    //    右缘不裁切；K/K2 与曲线的其余部分仍完整可见。
    for (final r in drawnRefs) {
      final layout = referenceLabelLayout(r, size);
      canvas.drawRRect(
        RRect.fromRectAndRadius(layout.backing, const Radius.circular(3)),
        Paint()..color = backgroundColor,
      );
      layout.painter.paint(canvas, layout.origin);
    }
  }

  /// 轴刻度数值的紧凑写法（1.5k / 12k），避免长数字挤占绘图区。
  static String axisLabel(double v) {
    if (!v.isFinite) return '—';
    final a = v.abs();
    if (a >= 10000) return '${(v / 1000).toStringAsFixed(0)}k';
    if (a >= 1000) {
      final k = v / 1000;
      final s = k == k.roundToDouble()
          ? k.toStringAsFixed(0)
          : k.toStringAsFixed(1);
      return '${s}k';
    }
    if ((v - v.roundToDouble()).abs() < 1e-9) {
      return v.toStringAsFixed(0);
    }
    return v.toStringAsFixed(1);
  }

  TextPainter _tp(String text,
          {required Color color,
          double size = 10,
          FontWeight weight = FontWeight.w500}) =>
      TextPainter(
        text: TextSpan(
          text: text,
          style: AppText.caption.copyWith(
              color: color,
              fontSize: size,
              height: 1.0,
              fontWeight: weight),
        ),
        textDirection: TextDirection.ltr,
      )..layout();

  void _drawDashedLine(
      Canvas canvas, Offset a, Offset b, Paint paint) {
    const dash = 5.0;
    const gap = 4.0;
    final total = (b - a).distance;
    if (total <= 0) return;
    final dir = (b - a) / total;
    var covered = 0.0;
    while (covered < total) {
      final end = math.min(covered + dash, total);
      canvas.drawLine(a + dir * covered, a + dir * end, paint);
      covered = end + gap;
    }
  }

  void _paintCentered(Canvas canvas, Size size, String text) {
    final tp = _tp(text, color: steelColor);
    tp.paint(canvas,
        Offset((size.width - tp.width) / 2, (size.height - tp.height) / 2));
  }

  @override
  bool shouldRepaint(covariant PopulationGrowthChartPainter old) =>
      old.series != series ||
      old.references != references ||
      old.inkColor != inkColor ||
      old.graphiteColor != graphiteColor ||
      old.steelColor != steelColor ||
      old.borderColor != borderColor ||
      old.backgroundColor != backgroundColor ||
      old.xLabel != xLabel ||
      old.emptyText != emptyText;
}
