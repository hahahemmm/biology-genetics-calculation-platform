// cause_radar.dart —— 错因雷达（v2.19.61 自评视图 / v2.19.62 AI 判视图）
//
// ── 它补的是哪一步 ─────────────────────────────────────────────
//
// 错题本列表能按「错因类型」筛选，但学生要先**一条条翻**才知道自己
// 主要错在哪一类。错题本页顶部这张「错因分布」卡把错因的**条数**画成
// 一张雷达图：哪根轴伸得最远，哪类错因最多，一眼就能看出来。
//
// ── 两个视图、两个数据口径 ─────────────────────────────────────
//
//   · 「自评」视图（默认）：五轴 = [MistakeErrorType]。数据 =
//     `mistakeCauseCounts(entries)`——按每条错题**用户自评的** errorType
//     计数，五键全出现（零值也保留）。
//   · 「AI 判」视图（v2.19.62）：六轴 = [MistakeCauseKey]。数据 =
//     `mistakeCauseKeyCounts(entries)`——按每条错题**AI 判定的** causeKey
//     计数，null / 未判的条目归入 [MistakeCauseKey.unclassified] 桶，六键
//     全出现。全库无一条 causeKey 非空时，本视图渲染诚实空态、**不画图**。
//
// ⛔ 两个视图都不在图上写死数值：轴名逐字取自各枚举的 displayName，轴长
// 逐字取自对应 counts。本图**不**调 AI、**不**读 aiSummary。
//
// ── ⛔ 画法：引擎数据 + CustomPainter，禁位图 / AI 图 ─────────────
//
// 教学图一律自绘（本仓家规）。正多边形：轴从正上开始顺时针均匀分布，
// 网格环画在 0 / 50% / 100% 三档高度，数据多边形用 AppColors.teal
// 半透明填充 + 实线描边，每个顶点点一枚圆点。零值的轴顶点落在**中心**。
// 轴条数由数据驱动（五轴 / 六轴同一套几何，见 [CauseRadarGeometry.axisCount]）。
//
// ── 为什么轴标签是 Text widget 而不是 painter 里画的字 ──────────
//
// 自绘文字（TextPainter）在 widget 树里**不是 Text**，`find.text` 找不到，
// 屏幕阅读器也读不到。故本图把多边形交给 CustomPainter，各轴名用
// Positioned Text 叠在图上——文字进树、可被检索、可被朗读，字形仍走
// 主题字体栈。⚠️ 因此本组件**不得**被 `const` 实例化（消费 AppColors
// token，const 会冻结主题色）。

import 'dart:math' as math;

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';

import '../../state/mistake_book.dart';
import '../../theme.dart';

// ─────────────────────────── 轴定义（单一真相）───────────────────

/// 自评视图五轴顺序 = 枚举顺序（概念 → 计算 → 理解 → 粗心 → 其他）。
List<MistakeErrorType> get causeRadarAxes => MistakeErrorType.values;

/// AI 判视图六轴顺序 = 枚举顺序（漏算一对基因 → … → 未归类）。
List<MistakeCauseKey> get causeKeyRadarAxes => MistakeCauseKey.values;

// ─────────────────────────── 版面常数 ───────────────────────────

/// 四周为轴标签预留的边距（占边长比例）。
const double kCauseRadarLabelReserveRatio = 0.24;

/// 轴标签中心相对多边形外缘再外推的距离（占边长比例）。
const double kCauseRadarLabelAnchorRatio = 0.07;

/// 错题本页「错因分布」小卡里用的推荐边长。
///
/// ⛔ 本图要挤在列表可视区**上方**；组件默认的 [CauseRadarChart.size]=220
/// 会把列表压掉一屏可见题数——ListView 是懒构建的，只有落在**绘制区**
/// 内的题才会被看见、才能被 `find.text` 检索到。故页内小卡用这个紧凑
/// 尺寸（见 mistake_book_page.dart 的高度预算说明）。
const double kCauseRadarCardChartSize = 136;

/// 轴标签字号（AppText.caption 级）。
const double kCauseRadarLabelFontSize = 12;

/// 轴标签行高倍率（与 AppText.caption 的 height 一致）。
const double kCauseRadarLabelHeightFactor = 1.5;

/// 轴标签的定宽盒宽（中文三字 12px ≈ 36px，留余量）。
const double kCauseRadarLabelBoxWidth = 48;

/// 网格环的高度档位（相对最长轴）：0 / 50% / 100%。
/// ⛔ 0 档落在中心，画作一个中心点（半径 0 的环退化成一个点）。
const List<double> kCauseRadarGridLevels = <double>[0.0, 0.5, 1.0];

// ─────────────────────────── 版面几何（单一真相）─────────────────

/// 雷达几何解算：轴角、多边形半径、轴标签落点。
///
/// v2.19.62：轴条数由 [axisCount] 参数化——五轴（自评）/ 六轴（AI 判）
/// 共用同一套几何，⛔ 角度公式与半径公式一字未改（只是把「五」换成
/// `axisCount`）。
@immutable
class CauseRadarGeometry {
  const CauseRadarGeometry({required this.size, required this.axisCount});

  /// 整块画布边长（正方形）。
  final double size;

  /// 轴条数（≥3）。自评视图 5 / AI 判视图 6。
  final int axisCount;

  /// 中心。
  Offset get center => Offset(size / 2, size / 2);

  /// 数据多边形外缘（100% 档）距中心的半径。
  double get polygonRadius => size / 2 - size * kCauseRadarLabelReserveRatio;

  /// 轴标签中心距中心的半径（在多边形外缘再往外推一点）。
  double get labelAnchorRadius =>
      polygonRadius + size * kCauseRadarLabelAnchorRatio;

  /// 第 `i` 轴的角度（弧度）：从正上（-90°）开始顺时针均匀分布。
  double angleOf(int i) => -math.pi / 2 + 2 * math.pi * i / axisCount;

  /// 第 `i` 轴、距中心 `ratio`（0~1）处的点。ratio ≤ 0 ⇒ 落在中心。
  Offset pointAt(int i, double ratio) {
    final a = angleOf(i);
    final r = polygonRadius * ratio;
    return center + Offset(math.cos(a) * r, math.sin(a) * r);
  }

  /// 第 `i` 轴标签的**中心**落点。
  Offset labelCenter(int i) {
    final a = angleOf(i);
    return center +
        Offset(math.cos(a) * labelAnchorRadius, math.sin(a) * labelAnchorRadius);
  }

  /// 轴标签文字盒的半高分（用于把标签垂直居中到落点）。
  double get labelHalfHeight =>
      kCauseRadarLabelFontSize * kCauseRadarLabelHeightFactor / 2;
}

// ─────────────────────────── 最高频错因文案 ──────────────────────

/// 一句最高频错因文案（**自评视图**）。⛔ 零 markdown 星号、零箭头方向符。
///
/// 并列最高时取 [MistakeErrorType.values] 里靠前的那一类（确定性）。
/// 「点下方筛选看这类题」对应列表的错因筛选 chips——文案只说路，不替点。
String mistakeCauseSummary(Map<MistakeErrorType, int> counts) {
  var top = causeRadarAxes.first;
  var topCount = counts[top] ?? 0;
  for (final t in causeRadarAxes) {
    final c = counts[t] ?? 0;
    if (c > topCount) {
      top = t;
      topCount = c;
    }
  }
  return '${top.displayName}最多（$topCount 道）——点下方筛选看这类题';
}

/// 一句最高频错因文案（**AI 判视图**，v2.19.62）。
///
/// ⛔ 与自评视图不同：列表**没有** causeKey 筛选入口，故本句不写「点下方
/// 筛选」（那是死路）。并列最高取 [MistakeCauseKey.values] 靠前的一类。
String mistakeCauseKeySummary(Map<MistakeCauseKey, int> counts) {
  var top = causeKeyRadarAxes.first;
  var topCount = counts[top] ?? 0;
  for (final k in causeKeyRadarAxes) {
    final c = counts[k] ?? 0;
    if (c > topCount) {
      top = k;
      topCount = c;
    }
  }
  return 'AI 判为「${top.displayName}」最多（$topCount 道）';
}

// ─────────────────────────── 组件 ───────────────────────────

/// 错因雷达（**自评视图**）：五轴正多边形，轴名 = 错因类型，轴长 = 条数。
///
/// ⛔ **纯函数式**：只画 `counts` 给的东西，不读全局。空不空由宿主决定
/// （本组件在 `counts` 全零时也照样画零轴，宿主负责「空错题本不挂它」）。
class CauseRadarChart extends StatelessWidget {
  const CauseRadarChart({super.key, required this.counts, this.size = 220});

  /// 五类错因 → 条数。零值键也要在（图要画零轴）。
  final Map<MistakeErrorType, int> counts;

  /// 整块画布边长（正方形）。
  final double size;

  /// 屏上语义标签（无障碍 / 测试共用）。
  String get semanticsLabel {
    final parts = [
      for (final t in causeRadarAxes) '${t.displayName} ${counts[t] ?? 0} 道',
    ];
    return '错因分布雷达图（自评）：${parts.join('，')}。';
  }

  @override
  Widget build(BuildContext context) {
    return _CauseRadarBody(
      labels: [for (final t in causeRadarAxes) t.displayName],
      values: [for (final t in causeRadarAxes) counts[t] ?? 0],
      size: size,
      semanticsLabel: semanticsLabel,
    );
  }
}

/// 错因雷达（**AI 判视图**，v2.19.62）：六轴正多边形，轴名 = [MistakeCauseKey]，
/// 轴长 = AI 判定该类的条数（未判 / 非法的条目计入 [MistakeCauseKey.unclassified]）。
///
/// ⛔ 与 [CauseRadarChart] 同一套几何/画法，只是轴条数由 5 变 6（数据驱动）。
class CauseKeyRadarChart extends StatelessWidget {
  const CauseKeyRadarChart({super.key, required this.counts, this.size = 220});

  /// 六类错因 key → 条数。零值键也要在（图要画零轴）。
  final Map<MistakeCauseKey, int> counts;

  /// 整块画布边长（正方形）。
  final double size;

  /// 屏上语义标签（无障碍 / 测试共用）。
  String get semanticsLabel {
    final parts = [
      for (final k in causeKeyRadarAxes) '${k.displayName} ${counts[k] ?? 0} 道',
    ];
    return '错因分布雷达图（AI 判）：${parts.join('，')}。';
  }

  @override
  Widget build(BuildContext context) {
    return _CauseRadarBody(
      labels: [for (final k in causeKeyRadarAxes) k.displayName],
      values: [for (final k in causeKeyRadarAxes) counts[k] ?? 0],
      size: size,
      semanticsLabel: semanticsLabel,
    );
  }
}

/// 雷达图本体（画法与轴数无关）：多边形交给 [CauseRadarPainter]，
/// 轴名用 Positioned Text 叠在图上（文字进树、可检索 / 可朗读）。
class _CauseRadarBody extends StatelessWidget {
  const _CauseRadarBody({
    required this.labels,
    required this.values,
    required this.size,
    required this.semanticsLabel,
  }) : assert(labels.length == values.length);

  final List<String> labels;
  final List<int> values;
  final double size;
  final String semanticsLabel;

  @override
  Widget build(BuildContext context) {
    final geom = CauseRadarGeometry(size: size, axisCount: labels.length);
    return Semantics(
      label: semanticsLabel,
      child: SizedBox(
        width: size,
        height: size,
        child: Stack(
          children: [
            Positioned.fill(
              child: CustomPaint(
                painter: CauseRadarPainter(
                  values: values,
                  geometry: geom,
                  grid: AppColors.border,
                  teal: AppColors.teal,
                  tealWash: AppColors.tealWash,
                ),
              ),
            ),
            for (var i = 0; i < labels.length; i++)
              Positioned(
                left: geom.labelCenter(i).dx - kCauseRadarLabelBoxWidth / 2,
                top: geom.labelCenter(i).dy - geom.labelHalfHeight,
                width: kCauseRadarLabelBoxWidth,
                child: Text(
                  labels[i],
                  textAlign: TextAlign.center,
                  style: AppText.caption.copyWith(
                    color: AppColors.graphite,
                    fontSize: kCauseRadarLabelFontSize,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────── painter ───────────────────────────

/// 自绘雷达（轴条数数据驱动）。所有颜色由宿主从 AppColors 注入
/// （跟随明暗主题）。
class CauseRadarPainter extends CustomPainter {
  CauseRadarPainter({
    required this.values,
    required this.geometry,
    required this.grid,
    required this.teal,
    required this.tealWash,
  }) : assert(values.length == geometry.axisCount);

  /// 各轴数值（长度 = [geometry.axisCount]）。
  final List<int> values;
  final CauseRadarGeometry geometry;

  /// 网格环 / 轴线颜色。
  final Color grid;

  /// 数据多边形描边 + 顶点圆点颜色。
  final Color teal;

  /// 数据多边形填充色（半透明）。
  final Color tealWash;

  int get _axisCount => geometry.axisCount;

  @override
  void paint(Canvas canvas, Size size) {
    _paintGrid(canvas);
    _paintData(canvas);
  }

  void _paintGrid(Canvas canvas) {
    final ringPaint = Paint()
      ..color = grid
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;
    final spokePaint = Paint()
      ..color = grid
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    // 轴线：中心 → 各轴外缘。
    for (var i = 0; i < _axisCount; i++) {
      canvas.drawLine(
        geometry.center,
        geometry.pointAt(i, 1.0),
        spokePaint,
      );
    }

    // 网格环：0 / 50% / 100%。0 档落在中心 ⇒ 画一个中心点。
    for (final level in kCauseRadarGridLevels) {
      if (level <= 0) {
        canvas.drawCircle(
          geometry.center,
          1.5,
          Paint()..color = grid,
        );
        continue;
      }
      canvas.drawPath(_ringPath(level), ringPaint);
    }
  }

  void _paintData(Canvas canvas) {
    var maxCount = 0;
    for (final c in values) {
      if (c > maxCount) maxCount = c;
    }

    final path = Path();
    final vertices = <Offset>[];
    for (var i = 0; i < _axisCount; i++) {
      final c = values[i];
      // 零值 ⇒ ratio 0 ⇒ 顶点落在中心（无 max 时全部落中心）。
      final ratio = maxCount > 0 ? c / maxCount : 0.0;
      final p = geometry.pointAt(i, ratio);
      vertices.add(p);
      if (i == 0) {
        path.moveTo(p.dx, p.dy);
      } else {
        path.lineTo(p.dx, p.dy);
      }
    }
    path.close();

    canvas.drawPath(
      path,
      Paint()..color = teal.withValues(alpha: 0.18),
    );
    canvas.drawPath(
      path,
      Paint()
        ..color = teal
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..strokeJoin = StrokeJoin.round,
    );

    // 每个顶点点一枚圆点（零值顶点在中心）。
    final dotPaint = Paint()..color = teal;
    for (final v in vertices) {
      canvas.drawCircle(v, 3.0, dotPaint);
    }
  }

  Path _ringPath(double level) {
    final path = Path();
    for (var i = 0; i < _axisCount; i++) {
      final p = geometry.pointAt(i, level);
      if (i == 0) {
        path.moveTo(p.dx, p.dy);
      } else {
        path.lineTo(p.dx, p.dy);
      }
    }
    return path..close();
  }

  @override
  bool shouldRepaint(covariant CauseRadarPainter old) =>
      !listEquals(old.values, values) ||
      old.geometry != geometry ||
      old.grid != grid ||
      old.teal != teal ||
      old.tealWash != tealWash;
}
