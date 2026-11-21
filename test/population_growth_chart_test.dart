// population_growth_chart_test.dart —— 种群增长对照图守卫
//
// 断的是几何与安全边界（不读像素）：
//   · 自动 y 上限覆盖全部数据与参考线；K / K/2 的位置按比例正确
//   · 两条曲线的每个点都在绘图区内；数量小的在下、大的在上
//   · 空数据 / 单点 / 极窄画布都不崩
//   · x 轴单位标签单独一行，不与末代刻度重叠、不越出画布
import 'dart:ui' as ui;

import 'package:biology/charts/population_growth_chart.dart';
import 'package:biology/engine/population_growth_engine.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const Size _kSize = Size(360, 220);

PopulationGrowthChartPainter _painter({
  List<GrowthSeries>? series,
  List<GrowthReference>? references,
}) {
  final c = comparePopulationGrowth(
      n0: 10, lambda: 1.5, k: 1000, r: 0.8, generations: 12);
  return PopulationGrowthChartPainter(
    series: series ??
        [
          GrowthSeries(
              label: 'J 型（λ 固定）',
              values: c.j.population,
              color: const Color(0xFF5C7265)),
          GrowthSeries(
              label: 'S 型（Logistic）',
              values: c.s.population,
              color: const Color(0xFF8F5B1E)),
        ],
    references: references ??
        [
          GrowthReference(
              value: c.s.halfK, label: 'K/2 = 500', color: const Color(0xFF61665C)),
          GrowthReference(
              value: c.s.k, label: 'K = 1000', color: const Color(0xFF4E534B)),
        ],
    inkColor: const Color(0xFF35322C),
    graphiteColor: const Color(0xFF4E534B),
    steelColor: const Color(0xFF61665C),
    borderColor: const Color(0xFFD2D7CD),
    xLabel: '代数 t',
  );
}

/// 真画一遍（不吞异常：paint 抛错会直接红）。
ui.Picture _paint(PopulationGrowthChartPainter p, Size size) {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  p.paint(canvas, size);
  return recorder.endRecording();
}

/// 记录型画布：只记「哪一类绘制、画在哪」，用来钉住**画序**。
///
/// 为什么不比较像素：缺陷形态是「后画的曲线划穿先画的标签」，
/// 只要证明底衬与文字都排在全部 drawPath（曲线）之后，缺陷就无法复现。
class _RecordingCanvas implements Canvas {
  final List<({String op, Object? arg})> calls =
      <({String op, Object? arg})>[];

  @override
  void drawPath(Path path, Paint paint) => calls.add((op: 'path', arg: null));

  @override
  void drawLine(Offset p1, Offset p2, Paint paint) =>
      calls.add((op: 'line', arg: null));

  @override
  void drawRect(Rect rect, Paint paint) => calls.add((op: 'rect', arg: rect));

  @override
  void drawRRect(RRect rrect, Paint paint) => calls.add((op: 'rrect', arg: rrect.outerRect));

  @override
  void drawCircle(Offset c, double radius, Paint paint) =>
      calls.add((op: 'circle', arg: c));

  @override
  void drawParagraph(ui.Paragraph paragraph, Offset offset) =>
      calls.add((op: 'paragraph', arg: offset));

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

void main() {
  group('自动 y 上限', () {
    test('取「好看的」档位，并覆盖最大值', () {
      expect(PopulationGrowthChartPainter.niceYCeil(1297.46337890625), 1500);
      expect(PopulationGrowthChartPainter.niceYCeil(10240), 12000);
      expect(PopulationGrowthChartPainter.niceYCeil(7), 8);
      expect(PopulationGrowthChartPainter.niceYCeil(0.5), closeTo(0.6, 1e-12));
      expect(PopulationGrowthChartPainter.niceYCeil(0), 1);
      expect(PopulationGrowthChartPainter.niceYCeil(double.nan), 1);
      expect(PopulationGrowthChartPainter.niceYCeil(double.infinity), 1);
    });

    test('参考线（K）也参与上限计算 ⇒ 永远画得下', () {
      final emptySeries = PopulationGrowthChartPainter(
        series: const [],
        references: const [
          GrowthReference(value: 8000, label: 'K = 8000', color: Colors.grey),
        ],
        inkColor: Colors.black,
        graphiteColor: Colors.black54,
        steelColor: Colors.grey,
        borderColor: Colors.grey,
        xLabel: '代数 t',
      );
      expect(emptySeries.yMax, greaterThanOrEqualTo(8000));
      final rect = emptySeries.plotRect(_kSize);
      final y = emptySeries.yForValue(8000, _kSize);
      expect(y, greaterThanOrEqualTo(rect.top - 1e-9),
          reason: '参考线顶端不得越出绘图区');
    });
  });

  group('几何：数据点与参考线', () {
    test('两条曲线每个点都在绘图区内', () {
      final p = _painter();
      final rect = p.plotRect(_kSize);
      final maxIdx = p.maxIndex;
      expect(maxIdx, 12);
      for (final s in p.series) {
        for (var i = 0; i < s.values.length; i++) {
          final o = p.pointFor(i, maxIdx, s.values[i], _kSize);
          expect(o.dx, inInclusiveRange(rect.left - 1e-9, rect.right + 1e-9),
              reason: '${s.label} 第 $i 点 x 越界');
          expect(o.dy, inInclusiveRange(rect.top - 1e-9, rect.bottom + 1e-9),
              reason: '${s.label} 第 $i 点 y 越界');
        }
      }
    });

    test('数量小的在下、大的在上（y 轴方向正确）', () {
      final p = _painter();
      expect(p.yForValue(0, _kSize),
          closeTo(p.plotRect(_kSize).bottom, 1e-9));
      expect(p.yForValue(p.yMax, _kSize),
          closeTo(p.plotRect(_kSize).top, 1e-9));
      expect(p.yForValue(100, _kSize), greaterThan(p.yForValue(1000, _kSize)));
      expect(p.yForValue(1297.46337890625, _kSize),
          lessThan(p.yForValue(10, _kSize)));
    });

    test('K 与 K/2 参考线位置按比例正确（yMax=1500）', () {
      final p = _painter();
      expect(p.yMax, 1500);
      final rect = p.plotRect(_kSize);
      final yK = p.yForValue(1000, _kSize);
      final yHalf = p.yForValue(500, _kSize);
      expect((rect.bottom - yK) / rect.height, closeTo(1000 / 1500, 1e-9));
      expect((rect.bottom - yHalf) / rect.height, closeTo(500 / 1500, 1e-9));
      expect(yHalf, greaterThan(yK), reason: 'K/2 在 K 下方');
    });

    test('单点序列：x 不除零（maxIndex=0 落在左边）', () {
      final p = _painter(
        series: const [
          GrowthSeries(label: '单点', values: [42], color: Colors.green),
        ],
        references: const [],
      );
      expect(p.maxIndex, 0);
      final rect = p.plotRect(_kSize);
      expect(p.pointFor(0, 0, 42, _kSize).dx, rect.left);
    });
  });

  group('空 / 单点 / 极窄都不崩', () {
    test('空数据：paint 不抛，画居中文案', () {
      final p = _painter(series: const [], references: const []);
      expect(p.hasData, isFalse);
      final pic = _paint(p, _kSize);
      expect(pic.approximateBytesUsed, greaterThan(0));
      pic.dispose();
    });

    test('单点：paint 不抛', () {
      final p = _painter(
        series: const [
          GrowthSeries(label: '单点', values: [42], color: Colors.green),
        ],
        references: const [
          GrowthReference(value: 40, label: 'K = 40', color: Colors.grey),
        ],
      );
      final pic = _paint(p, _kSize);
      expect(pic.approximateBytesUsed, greaterThan(0));
      pic.dispose();
    });

    test('极窄画布（10×10）：paint 直接返回，不炸除零', () {
      final p = _painter();
      expect(() => _paint(p, const Size(10, 10)), returnsNormally);
      final rect = p.plotRect(const Size(10, 10));
      expect(rect.width, 0, reason: '左右边距吃掉全部宽度 ⇒ 宽度夹到 0');
    });
  });

  group('x 轴标签不重叠', () {
    test('单位标签行在刻度行下方、且底边不越出画布', () {
      final p = _painter();
      final rect = p.plotRect(_kSize);
      final origin = p.xUnitLabelOrigin(_kSize, 30);
      const tickBottom =
          PopulationGrowthChartPainter.xTickLabelTop +
              PopulationGrowthChartPainter.axisTextHeight;
      expect(PopulationGrowthChartPainter.xUnitLabelTop,
          greaterThanOrEqualTo(tickBottom),
          reason: '单位标签行顶必须 ≥ 刻度行底（否则左右撞在一起）');
      expect(origin.dy, greaterThanOrEqualTo(rect.bottom + tickBottom - 1e-9));
      expect(origin.dy + PopulationGrowthChartPainter.axisTextHeight,
          lessThanOrEqualTo(_kSize.height),
          reason: '现有的 bottom 边距必须装得下两行字');
      expect(PopulationGrowthChartPainter.marginBottom,
          greaterThanOrEqualTo(PopulationGrowthChartPainter.xUnitLabelTop +
              PopulationGrowthChartPainter.axisTextHeight));
    });
  });

  group('widget 形态', () {
    testWidgets('默认数据在 390 宽下渲染零溢出，且有 RepaintBoundary',
        (tester) async {
      tester.view.physicalSize = const Size(390, 260);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: PopulationGrowthChart(series: _painter().series),
        ),
      ));
      expect(tester.takeException(), isNull);
      expect(find.byType(RepaintBoundary), findsWidgets);
      expect(find.byType(CustomPaint), findsWidgets);
    });

    testWidgets('空数据 widget 也不崩（画提示文案）', (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
          body: PopulationGrowthChart(series: []),
        ),
      ));
      expect(tester.takeException(), isNull);
    });
  });

  group('shouldRepaint', () {
    test('数据换了要求重绘；同实例不重绘', () {
      final a = _painter();
      final b = _painter();
      expect(a.shouldRepaint(a), isFalse);
      expect(a.shouldRepaint(b), isTrue);
    });
  });

  // ── P1 回归守卫：参考线标签必须最后画 + 不透明底衬包住文字 ──
  //
  // 缺陷形态（独立复核 P1）：标签先画、J/S 曲线后画 ⇒ 曲线划穿
  // 「K = 1000」「K/2 = 500」字样。本组用记录画布证明「底衬/文字都排在
  // 全部曲线之后」，并证明底衬完整包住文字区、不越出画布右缘。
  group('参考线标签：画序与覆盖（P1 守卫）', () {
    void verify(Size size) {
      final p = _painter();
      final canvas = _RecordingCanvas();
      p.paint(canvas, size);
      final calls = canvas.calls;

      final lastPath = calls.lastIndexWhere((c) => c.op == 'path');
      final lastLine = calls.lastIndexWhere((c) => c.op == 'line');
      expect(lastPath, greaterThanOrEqualTo(0), reason: '两条曲线必须画了');
      expect(calls.where((c) => c.op == 'path').length, 2,
          reason: 'J 型 + S 型各一条折线');
      expect(lastLine, greaterThanOrEqualTo(0), reason: '虚线参考线必须画了');

      final backings = calls.where((c) => c.op == 'rrect').toList();
      expect(backings.length, p.references.length,
          reason: '每个参考线标签一条底衬（图例色块是 rect，不会混淆）');

      for (final ref in p.references) {
        final layout = p.referenceLabelLayout(ref, size);
        final backingIdx = calls.indexWhere(
            (c) => c.op == 'rrect' && c.arg == layout.backing);
        expect(backingIdx, greaterThan(lastPath),
            reason: '「${ref.label}」底衬必须画在全部曲线之后');
        expect(backingIdx, greaterThan(lastLine),
            reason: '「${ref.label}」底衬必须盖住底下的虚线');
        final textIdx = calls.indexWhere(
            (c) => c.op == 'paragraph' && c.arg == layout.origin);
        expect(textIdx, greaterThan(backingIdx),
            reason: '「${ref.label}」文字必须在底衬之后（先铺底再压字）');
        expect(calls.lastIndexWhere((c) => c.op == 'paragraph'),
            greaterThan(lastPath),
            reason: '最后一个文字（参考线标签）必须晚于曲线');

        // 底衬完整包住文字区（四边都留出 padding）
        expect(layout.backing.left, lessThan(layout.textRect.left));
        expect(layout.backing.top, lessThan(layout.textRect.top));
        expect(layout.backing.right, greaterThanOrEqualTo(layout.textRect.right));
        expect(layout.backing.bottom,
            greaterThanOrEqualTo(layout.textRect.bottom));
        // 不越出画布、不被右缘裁切
        expect(layout.textRect.right, lessThanOrEqualTo(size.width));
        expect(layout.backing.right, lessThanOrEqualTo(size.width));
        expect(layout.backing.bottom, lessThanOrEqualTo(size.height));
        expect(layout.backing.top, greaterThanOrEqualTo(0));
        expect(layout.backing.left, greaterThanOrEqualTo(p.plotRect(size).left));
      }
    }

    test('桌面 360×220：标签后画 + 底衬包住文字', () => verify(_kSize));

    test('手机 320×220：同上', () => verify(const Size(320, 220)));

    test('更窄 260×200：同上（右缘不裁切）', () => verify(const Size(260, 200)));

    testWidgets('底衬色不透明（半透明会把曲线透出来 = 仍算划穿）', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: PopulationGrowthChart(series: _painter().series),
        ),
      ));
      final painter = tester
          .widgetList<CustomPaint>(find.byType(CustomPaint))
          .map((c) => c.painter)
          .whereType<PopulationGrowthChartPainter>()
          .single;
      expect((painter.backgroundColor.a * 255).round(), 255);
    });
  });
}
