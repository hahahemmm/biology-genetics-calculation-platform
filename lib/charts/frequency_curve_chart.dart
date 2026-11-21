// frequency_curve_chart.dart —— 逐代基因频率折线图（v2.13 自然选择模拟）
//
// 场景：进化页「自然选择模拟」卡的结果可视化——把 qPerGen/pPerGen
// 数列画成折线，替代纯文字「F0=…　F1=…」扫读（课堂演示向）。
//
// 设计要点（对齐 evolution_chart.dart 的纪律）：
// - 纯 CustomPainter widget，零新依赖，三端通用。
// - 输入：series 列表（标签 + 取值序列 + 颜色），x = 代数（0..n）。
// - y 轴固定 [0,1]（频率语义天然有界），画 0%/50%/100% 三条参考线，
//   学生一眼读出「频率往哪走、走多快」。
// - 空序列 / 单点：画坐标轴不画线，不崩。
// - RepaintBoundary 包住，便于后续截图导出复用。

import 'package:flutter/material.dart';

import '../theme.dart';

/// 一条折线序列。
class FreqSeries {
  final String label;
  final List<double> values;
  final Color color;

  const FreqSeries({
    required this.label,
    required this.values,
    required this.color,
  });
}

/// 逐代频率折线图 widget。
class FrequencyCurveChart extends StatelessWidget {
  const FrequencyCurveChart({
    super.key,
    required this.series,
    this.height = 180,
    this.xLabel = '代',
  });

  final List<FreqSeries> series;
  final double height;

  /// x 轴单位标签（默认「代」）。
  final String xLabel;

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: SizedBox(
        height: height,
        width: double.infinity,
        child: CustomPaint(
          painter: FrequencyCurveChartPainter(
            series: series,
            inkColor: AppColors.ink,
            graphiteColor: AppColors.graphite,
            borderColor: AppColors.border,
            xLabel: xLabel,
          ),
        ),
      ),
    );
  }
}

class FrequencyCurveChartPainter extends CustomPainter {
  FrequencyCurveChartPainter({
    required this.series,
    required this.inkColor,
    required this.graphiteColor,
    required this.borderColor,
    required this.xLabel,
  });

  final List<FreqSeries> series;
  final Color inkColor;
  final Color graphiteColor;
  final Color borderColor;
  final String xLabel;

  static const double _marginL = 44; // y 轴刻度留宽
  static const double _marginR = 12;
  static const double _marginT = 14;
  static const double _marginB = 26; // x 轴标签留高

  @override
  void paint(Canvas canvas, Size size) {
    final plotW = size.width - _marginL - _marginR;
    final plotH = size.height - _marginT - _marginB;
    if (plotW <= 0 || plotH <= 0) return;

    // 1) y 轴参考线（0% / 50% / 100%）。
    final gridPaint = Paint()
      ..color = borderColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8;
    for (final f in [0.0, 0.5, 1.0]) {
      final y = _marginT + plotH * (1 - f);
      canvas.drawLine(
          Offset(_marginL, y), Offset(_marginL + plotW, y), gridPaint);
      final tp = TextPainter(
        text: TextSpan(
          text: '${(f * 100).round()}%',
          style: AppText.caption.copyWith(
              color: graphiteColor, fontSize: 10),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(_marginL - tp.width - 6, y - tp.height / 2));
    }

    // 数据代数范围（所有 series 一致；空数据时按 1 代防除零）。
    final maxGen =
        series.isEmpty ? 1 : series.map((s) => s.values.length - 1).reduce((a, b) => a > b ? a : b);
    if (maxGen < 1) {
      _drawEmpty(canvas, size);
      return;
    }

    // x 轴刻度（最多 6 个，含首尾）。
    final tickStep = (maxGen / 5).ceil();
    for (var g = 0; g <= maxGen; g += tickStep) {
      final x = _marginL + plotW * (g / maxGen);
      final tp = TextPainter(
        text: TextSpan(
          text: g == 0 ? '起始' : '$g',
          style:
              AppText.caption.copyWith(color: graphiteColor, fontSize: 10),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas,
          Offset(x - tp.width / 2, _marginT + plotH + 6));
    }
    final xUnit = TextPainter(
      text: TextSpan(
        text: xLabel,
        style: AppText.caption.copyWith(color: graphiteColor, fontSize: 10),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    xUnit.paint(
        canvas, Offset(_marginL + plotW - xUnit.width, _marginT + plotH + 6));

    // 2) 折线 + 端点。
    final pointPaint = Paint()..style = PaintingStyle.fill;
    for (final s in series) {
      if (s.values.isEmpty) continue;
      final linePaint = Paint()
        ..color = s.color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0
        ..strokeJoin = StrokeJoin.round;
      final path = Path();
      for (var i = 0; i < s.values.length; i++) {
        final x = _marginL + plotW * (i / maxGen);
        final y = _marginT + plotH * (1 - s.values[i].clamp(0.0, 1.0));
        if (i == 0) {
          path.moveTo(x, y);
        } else {
          path.lineTo(x, y);
        }
      }
      canvas.drawPath(path, linePaint);
      // 端点小圆（首/尾强调）。
      pointPaint.color = s.color;
      for (final i in [0, s.values.length - 1]) {
        final x = _marginL + plotW * (i / maxGen);
        final y = _marginT + plotH * (1 - s.values[i].clamp(0.0, 1.0));
        canvas.drawCircle(Offset(x, y), 3, pointPaint);
      }
    }

    // 3) 图例（右上， series 顺序排列）。
    var legendX = _marginL + 8.0;
    final legendY = _marginT - 12;
    for (final s in series) {
      final swatch = Paint()..color = s.color;
      canvas.drawRect(
          Rect.fromLTWH(legendX, legendY + 2, 10, 3), swatch);
      final tp = TextPainter(
        text: TextSpan(
          text: s.label,
          style: AppText.caption.copyWith(
              color: inkColor, fontSize: 10, fontWeight: FontWeight.w600),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(legendX + 14, legendY - 2));
      legendX += 14 + tp.width + 14;
    }
  }

  void _drawEmpty(Canvas canvas, Size size) {
    final tp = TextPainter(
      text: TextSpan(
        text: '（暂无模拟数据）',
        style: AppText.caption,
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas,
        Offset((size.width - tp.width) / 2, (size.height - tp.height) / 2));
  }

  @override
  bool shouldRepaint(covariant FrequencyCurveChartPainter old) {
    return old.series != series;
  }
}
