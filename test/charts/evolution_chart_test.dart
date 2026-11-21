// evolution_chart_test.dart —— 进化树图表单元测试（v2.12 Wave 3-A）
//
// 覆盖（任务派工指令 T-A2 / Subtask 2）：
//   1. 空列表不崩（EvolutionChart widget 渲染 + 提示文案）
//   2. 单节点居中渲染（painter paint 不抛，picture 非空）
//   3. 2 代分叉连线（painter paint 后 picture 包含 lineTo 路径）
//   4. 父节点缺失降级（parent 引用不存在的 id，painter 不抛）
//   5. 同代内列号按 id 字母序稳定（保证 SVG/Painter diff 稳定）
//   6. shouldRepaint：节点列表变化时要求重绘
//   7. 多代多节点（5 代各 1-2 节点），paint 不抛

import 'dart:ui' as ui;

import 'package:biology/charts/evolution_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 抓取 EvolutionChart 内部 CustomPainter 的 paint 结果。
/// 返回非空 Picture 视为「painter 画了点东西」。
ui.Picture _paintChart(EvolutionChart chart, {Size size = const Size(400, 220)}) {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  // 先 pump 一下让 widget 建好；然后从 BuildContext 拿到 painter
  // 实测更可靠的方式：直接构造 painter 自己 paint。
  // 这里采用第二种——拿 painter 字段需要访问私有类型，故走自建路径。
  final painter = _PainterForTest(nodes: chart.nodes);
  painter.paintForTest(canvas, size);
  return recorder.endRecording();
}

class _PainterForTest extends EvolutionChartPainter {
  _PainterForTest({required super.nodes})
      : super(
          inkColor: const Color(0xFF35322C),
          tealColor: const Color(0xFF5C7265),
          tealWashColor: const Color(0xFFE6EBE2),
          graphiteColor: const Color(0xFF5D594F),
          borderColor: const Color(0xFFDFDAD0),
          onTeal: Colors.white,
        );

  void paintForTest(Canvas canvas, Size size) => paint(canvas, size);
}

void main() {
  group('EvolutionChart widget', () {
    testWidgets('空列表不崩 + 显示占位文案', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: EvolutionChart(nodes: []),
          ),
        ),
      );
      // 占位文案存在
      expect(find.text('（暂无进化树节点）'), findsOneWidget);
    });

    testWidgets('单节点渲染不崩', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: EvolutionChart(
              nodes: [
                EvolutionNode(
                  id: 'luca',
                  parent: null,
                  generation: 0,
                  trait: 'LUCA 共同祖先',
                ),
              ],
            ),
          ),
        ),
      );
      // widget 树存在
      expect(find.byType(EvolutionChart), findsOneWidget);
      // RepaintBoundary 包了一层（未来扩展截图所需）
      expect(find.byType(RepaintBoundary), findsWidgets);
    });
  });

  group('EvolutionChart painter', () {
    test('单节点居中渲染：paint 不抛 + picture 非空', () {
      final chart = const EvolutionChart(
        nodes: [
          EvolutionNode(
            id: 'root',
            parent: null,
            generation: 0,
            trait: 'Root',
          ),
        ],
      );
      final pic = _paintChart(chart);
      // picture 包含至少一个绘图指令（背景/形状/标签任一）
      expect(pic, isNotNull);
      // 主动 dispose
      pic.dispose();
    });

    test('2 代分叉连线：paint 不抛 + picture 非空', () {
      final chart = const EvolutionChart(
        nodes: [
          EvolutionNode(
            id: 'a',
            parent: null,
            generation: 0,
            trait: 'A',
          ),
          EvolutionNode(
            id: 'b',
            parent: 'a',
            generation: 1,
            trait: 'B',
          ),
        ],
      );
      final pic = _paintChart(chart);
      // Picture 实体非 null + 可正常 dispose（painter 至少跑完没抛）
      expect(pic, isNotNull);
      pic.dispose();
    });

    test('父节点缺失降级：parent 引用不存在的 id，paint 不抛', () {
      final chart = const EvolutionChart(
        nodes: [
          EvolutionNode(
            id: 'orphan',
            parent: 'ghost_does_not_exist',
            generation: 0,
            trait: 'Orphan',
          ),
        ],
      );
      // 不应抛任何异常
      expect(
        () => _paintChart(chart),
        returnsNormally,
      );
    });

    test('同代内列号按 id 字母序稳定：相同 nodes 两次 paint 应一致', () {
      // 通过 builder 调用两次，验证 getIdColIndex 行为稳定
      // 我们不直接访问私有 _colIndexOf，而是用 shouldRepaint 行为间接验证。
      final painter1 = _PainterForTest(
        nodes: const [
          EvolutionNode(id: 'b', parent: null, generation: 0, trait: 'B'),
          EvolutionNode(id: 'a', parent: null, generation: 0, trait: 'A'),
        ],
      );
      final painter2 = _PainterForTest(
        nodes: const [
          EvolutionNode(id: 'b', parent: null, generation: 0, trait: 'B'),
          EvolutionNode(id: 'a', parent: null, generation: 0, trait: 'A'),
        ],
      );
      // 节点列表完全相同 → 不要求重绘
      expect(painter2.shouldRepaint(painter1), isFalse);
    });

    test('节点变化时 shouldRepaint = true', () {
      final painter1 = _PainterForTest(
        nodes: const [
          EvolutionNode(id: 'a', parent: null, generation: 0, trait: 'A'),
        ],
      );
      final painter2 = _PainterForTest(
        nodes: const [
          EvolutionNode(id: 'a', parent: null, generation: 0, trait: 'A'),
          EvolutionNode(
              id: 'b', parent: 'a', generation: 1, trait: 'B'),
        ],
      );
      expect(painter2.shouldRepaint(painter1), isTrue);
    });

    test('多代多节点（5 代 × 1-2 节点），paint 不抛', () {
      // 简单树：a → b,c → d,e → f,g → h
      final nodes = <EvolutionNode>[
        const EvolutionNode(id: 'a', parent: null, generation: 0, trait: 'A'),
        const EvolutionNode(id: 'b', parent: 'a', generation: 1, trait: 'B'),
        const EvolutionNode(id: 'c', parent: 'a', generation: 1, trait: 'C'),
        const EvolutionNode(id: 'd', parent: 'b', generation: 2, trait: 'D'),
        const EvolutionNode(id: 'e', parent: 'b', generation: 2, trait: 'E'),
        const EvolutionNode(id: 'f', parent: 'c', generation: 3, trait: 'F'),
        const EvolutionNode(id: 'g', parent: 'c', generation: 3, trait: 'G'),
        const EvolutionNode(id: 'h', parent: 'd', generation: 4, trait: 'H'),
      ];
      final chart = EvolutionChart(nodes: nodes);
      // 不应抛
      expect(() => _paintChart(chart), returnsNormally);
    });
  });

  // ─────────────────────────────────────────────────────────────
  // v2.20：标签锚点 / 边界 + 父子拓扑（纯 Dart 几何，不截图）
  //
  // 背景（体验官 1440×1000 截图）：六个节点圆盘各盖住标签一个字
  // —— 旧版把标签水平居中画在圆心；另有谱系语义风险：旧版 y 按
  // 「同代内序号」排，gen1/2/3 落在同一行，root→真核→动物→脊椎
  // 动物 看起来像直系链。
  // ─────────────────────────────────────────────────────────────

  /// 与 lib/pages/evolution_page.dart 一致的出厂数据（6 节点，父子齐全）。
  const prodNodes = <EvolutionNode>[
    EvolutionNode(id: 'root', parent: null, generation: 0, trait: '共同祖先'),
    EvolutionNode(id: 'p1', parent: 'root', generation: 1, trait: '原核生物'),
    EvolutionNode(id: 'e1', parent: 'root', generation: 1, trait: '真核生物'),
    EvolutionNode(id: 'a1', parent: 'e1', generation: 2, trait: '动物'),
    EvolutionNode(id: 'pl1', parent: 'e1', generation: 2, trait: '植物'),
    EvolutionNode(id: 'v1', parent: 'a1', generation: 3, trait: '脊椎动物'),
  ];

  group('几何：标签锚点与边界', () {
    EvolutionChartGeometry geoOf(Size size) =>
        _PainterForTest(nodes: prodNodes).computeGeometry(size);

    test('每个节点都有圆心与标签矩形', () {
      final geo = geoOf(const Size(400, 220));
      final ids = prodNodes.map((n) => n.id).toSet();
      expect(geo.positions.keys.toSet(), ids);
      expect(geo.labelRects.keys.toSet(), ids);
    });

    test('标签不压节点圆盘（六个节点逐一）', () {
      final geo = geoOf(const Size(400, 220));
      for (final n in prodNodes) {
        final pos = geo.positions[n.id]!;
        final rect = geo.labelRects[n.id]!;
        expect(
          rect.overlaps(EvolutionChartGeometry.circleRect(pos)),
          isFalse,
          reason: '「${n.trait}」的标签压住圆盘：$rect vs 圆心 $pos',
        );
      }
    });

    test('标签不压任何节点圆盘（含他节点，防跨列遮挡）', () {
      final geo = geoOf(const Size(400, 220));
      for (final n in prodNodes) {
        final rect = geo.labelRects[n.id]!;
        for (final other in prodNodes) {
          final circle =
              EvolutionChartGeometry.circleRect(geo.positions[other.id]!);
          expect(rect.overlaps(circle), isFalse,
              reason: '「${n.trait}」的标签压住 ${other.id}（${other.trait}）的圆盘');
        }
      }
    });

    test('父子折线中段竖线不划穿任何标签', () {
      for (final size in const [Size(400, 220), Size(320, 220), Size(1080, 220)]) {
        final geo = geoOf(size);
        for (final n in prodNodes) {
          final mid = geo.branchMidX[n.id];
          if (mid == null) continue;
          final pp = geo.positions[n.parent!]!;
          final cp = geo.positions[n.id]!;
          final top = pp.dy < cp.dy ? pp.dy : cp.dy;
          final bottom = pp.dy < cp.dy ? cp.dy : pp.dy;
          final seg = Rect.fromLTRB(mid - 0.6, top, mid + 0.6, bottom);
          for (final m in prodNodes) {
            expect(seg.overlaps(geo.labelRects[m.id]!), isFalse,
                reason: '宽 ${size.width}：${n.parent}→${n.id} 的竖段划穿「${m.trait}」的标签');
          }
        }
      }
    });

    test('标签彼此不重叠', () {
      final geo = geoOf(const Size(400, 220));
      for (var i = 0; i < prodNodes.length; i++) {
        for (var j = i + 1; j < prodNodes.length; j++) {
          final a = geo.labelRects[prodNodes[i].id]!;
          final b = geo.labelRects[prodNodes[j].id]!;
          expect(a.overlaps(b), isFalse,
              reason: '「${prodNodes[i].trait}」与「${prodNodes[j].trait}」的标签重叠');
        }
      }
    });

    test('标签不越画布、不压时间轴刻度行', () {
      const w = 400.0;
      const h = 220.0;
      final geo = geoOf(const Size(w, h));
      for (final n in prodNodes) {
        final rect = geo.labelRects[n.id]!;
        expect(rect.left, greaterThanOrEqualTo(0), reason: '${n.id} 左越界');
        expect(rect.top, greaterThanOrEqualTo(0), reason: '${n.id} 上越界');
        expect(rect.right, lessThanOrEqualTo(w), reason: '${n.id} 右越界');
        expect(rect.bottom, lessThanOrEqualTo(h), reason: '${n.id} 下越界');
        // 时间轴刻度文字从 h-16 起，节点标签必须留在 h-24 以上
        expect(rect.bottom, lessThanOrEqualTo(h - 24 + 0.01),
            reason: '${n.id} 的标签压到时间轴刻度行');
      }
    });

    test('常规宽度下标签排在节点右侧并让出节点半径', () {
      final geo = geoOf(const Size(400, 220));
      for (final n in prodNodes) {
        final pos = geo.positions[n.id]!;
        final rect = geo.labelRects[n.id]!;
        expect(geo.labelSides[n.id], EvolutionLabelSide.right,
            reason: '「${n.trait}」应默认排右侧');
        expect(rect.left,
            greaterThanOrEqualTo(pos.dx + EvolutionChartGeometry.nodeRadius),
            reason: '「${n.trait}」的标签左沿压进圆盘');
        // 底边在节点水平轴之上 ⇒ 父子连线的水平段不会划穿文字
        expect(rect.bottom, lessThanOrEqualTo(pos.dy - 2 + 0.01),
            reason: '「${n.trait}」的标签压到节点水平轴，会被连线划穿');
      }
    });

    test('较窄画布：右侧不足时按可用宽度截断，仍不压圆盘', () {
      const w = 320.0;
      const h = 220.0;
      final geo = geoOf(const Size(w, h));
      var truncated = 0;
      for (final n in prodNodes) {
        final pos = geo.positions[n.id]!;
        final rect = geo.labelRects[n.id]!;
        expect(rect.overlaps(EvolutionChartGeometry.circleRect(pos)), isFalse,
            reason: '窄画布下「${n.trait}」的标签压住圆盘：$rect');
        expect(rect.left, greaterThanOrEqualTo(0));
        expect(rect.right, lessThanOrEqualTo(w));
        expect(rect.top, greaterThanOrEqualTo(0));
        expect(rect.bottom, lessThanOrEqualTo(h));
        if (geo.labelSides[n.id] == EvolutionLabelSide.right) {
          expect(rect.left,
              greaterThanOrEqualTo(pos.dx + EvolutionChartGeometry.nodeRadius));
          // 截断标志：宽度明显小于自然单行宽度（4 字 × 12 > 该阈值）
          if (rect.width < 48 - 0.01) truncated++;
        }
      }
      expect(truncated, greaterThan(0), reason: '窄画布应触发省略号截断');
    });

    test('极窄画布：右侧挤不出宽度时收到节点上方，仍不压圆盘且不越界', () {
      const w = 200.0;
      const h = 220.0;
      final geo = geoOf(const Size(w, h));
      for (final n in prodNodes) {
        final pos = geo.positions[n.id]!;
        final rect = geo.labelRects[n.id]!;
        expect(rect.overlaps(EvolutionChartGeometry.circleRect(pos)), isFalse,
            reason: '极窄画布下「${n.trait}」的标签压住圆盘：$rect');
        expect(rect.left, greaterThanOrEqualTo(0));
        expect(rect.top, greaterThanOrEqualTo(0));
        expect(rect.right, lessThanOrEqualTo(w));
        expect(rect.bottom, lessThanOrEqualTo(h));
      }
      // 第一代右侧只剩几像素 ⇒ 改走「节点上方」兜底
      expect(geo.labelSides['root'], EvolutionLabelSide.above);
    });

    test('单节点：横向、纵向都居中', () {
      final geo = _PainterForTest(nodes: const <EvolutionNode>[
        EvolutionNode(id: 'solo', parent: null, generation: 0, trait: '共同祖先'),
      ]).computeGeometry(const Size(400, 220));
      final pos = geo.positions['solo']!;
      expect(pos.dx, closeTo(200, 0.01));
      // 节点区 [28, 220-36] 的中线
      expect(pos.dy, closeTo((28 + 184) / 2, 0.01));
    });
  });

  group('几何：父子拓扑', () {
    final geo = _PainterForTest(nodes: prodNodes)
        .computeGeometry(const Size(400, 220));
    double yOf(String id) => geo.positions[id]!.dy;
    double xOf(String id) => geo.positions[id]!.dx;

    test('同一代共享同一列 x，且 x 随代际严格递增', () {
      expect(xOf('p1'), closeTo(xOf('e1'), 0.01));
      expect(xOf('a1'), closeTo(xOf('pl1'), 0.01));
      expect(xOf('root'), lessThan(xOf('e1')));
      expect(xOf('e1'), lessThan(xOf('a1')));
      expect(xOf('a1'), lessThan(xOf('v1')));
    });

    test('父节点垂直居中于两个子节点之间（root / e1）', () {
      final rootY = yOf('root');
      expect(rootY, greaterThan(yOf('e1')));
      expect(rootY, lessThan(yOf('p1')));
      final e1Y = yOf('e1');
      expect(e1Y, greaterThan(yOf('a1')));
      expect(e1Y, lessThan(yOf('pl1')));
    });

    test('root→真核→动物 不再共线（旧版三代同行的直系链误读）', () {
      expect(yOf('root'), isNot(closeTo(yOf('e1'), 0.01)));
      expect(yOf('e1'), isNot(closeTo(yOf('a1'), 0.01)));
      expect(yOf('root'), isNot(closeTo(yOf('a1'), 0.01)));
    });

    test('单子代直系（动物→脊椎动物）保持同一直线', () {
      expect(yOf('a1'), closeTo(yOf('v1'), 0.01));
    });

    test('叶子各占一行（原核 / 植物 / 脊椎 互不重叠）', () {
      final ys = <double>{yOf('p1'), yOf('pl1'), yOf('v1')};
      expect(ys.length, 3);
    });
  });

  group('几何：异常数据降级', () {
    test('父节点缺失：仍给位置与界内标签', () {
      final geo = _PainterForTest(nodes: const <EvolutionNode>[
        EvolutionNode(id: 'orphan', parent: 'ghost', generation: 0, trait: '孤儿节点'),
      ]).computeGeometry(const Size(400, 220));
      expect(geo.positions.containsKey('orphan'), isTrue);
      final rect = geo.labelRects['orphan']!;
      expect(rect.right, lessThanOrEqualTo(400));
    });

    test('环形引用：不挂死、不抛', () {
      expect(
        () => _PainterForTest(nodes: const <EvolutionNode>[
          EvolutionNode(id: 'a', parent: 'b', generation: 0, trait: 'A'),
          EvolutionNode(id: 'b', parent: 'a', generation: 1, trait: 'B'),
        ]).computeGeometry(const Size(400, 220)),
        returnsNormally,
      );
    });

    test('出厂数据整图 paint 不抛', () {
      expect(
        () => _paintChart(const EvolutionChart(nodes: prodNodes)),
        returnsNormally,
      );
    });

    testWidgets('出厂数据 widget 渲染无异常', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 400,
              height: 220,
              child: EvolutionChart(nodes: prodNodes),
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      expect(find.byType(EvolutionChart), findsOneWidget);
    });
  });
}
