// centrifuge_band_diagram.dart —— 「离心管带型」图（v2.19.167）
// （分子遗传页 tab1「复制与标记」的 DNA 标记计算一节）
//
// ── 它补的是哪一步（实测）──────────────────────────────────────
//
// 出厂 n=3，点「计算标记分布」之后屏上真实渲染出来的是：
//
//     DNA 分子 2^n=8 个
//     含标记分子 2 个（占 25.0%）；标记链 2/16 条
//     全无标记分子 6 个；第 3 代：中带 2 个（占 25.0%），
//     轻带 6 个（占 75.0%）；无重带。
//
// ⛔ **8 个分子、三条带，全是同一行字里的三个数字。**
// 「2 个在中带、6 个在轻带」这件事，屏上既没有管，也没有带，
// 也没有任何一处能一眼看出**中带比轻带窄得多**——
// 而这正是密度梯度离心那一步要看的。
//
// ── 三段带各画几格（逐条对应引擎字段）─────────────────────────
//
//   · 中带 = `labeledMolecules`（引擎给的 int，⛔ 不重算）
//   · 轻带 = `unlabeledOnlyMolecules`（引擎给的 int，⛔ 不重算）
//   · 重带 = `totalMolecules − labeledMolecules − unlabeledOnlyMolecules`
//     ⛔ 重带**没有**独立的引擎字段（已核 `DnaLabelResult` 全文 6 个 int
//     + 1 个 String，无 heavy 计数）。所以它只能是这三个字段的差；
//     而 [CentrifugeBandDiagram.dataReason] **只放行这个差等于 0 的数据**
//     —— 引擎的 `centrifugeBands` 对每个 n 都写着「无重带」
//     （n=1 写「重带消失」，n≥2 写「无重带」，实测逐句抓过）。
//     ⇒ 差 ≠ 0 = 数据不是引擎那一份 ⇒ 整图不画，屏上写明为什么不画。
//
// ── ⛔⛔ 2ⁿ 会爆：上限闸是**实测**的，不是拍的 ──────────────────
//
// 引擎允许 n ≤ 40 ⇒ 2⁴⁰ = 1 099 511 627 776 格。
// 本图一格 = 一个分子，而一格的边长由**实测**决定（见
// [centrifugeCellSide]）。放不下就**不画**，
// 屏上明写「共 X 个分子 … 只放得下 Y 行」——⛔ **零静默截断**：
// 悄悄画一部分等于宣称「这就是全部」。
//
// ── 颜色 ─────────────────────────────────────────────────────
//
// ⛔ 一律 `AppColors.*`（20 个 token，**全是 getter**，⛔ 不冻进
//   `static final`）。⛔ 不许 `Color(0x`。⛔ 不用 `AppColors.lethal`
//   （那是致死语义，本图讲同位素带型，与遗传病无关）。

import 'package:flutter/material.dart';

import '../../engine/dna_strand_engine.dart';
import '../../theme.dart';

// ─────────────────────────── 绘制记录钩（仅供测试注入）───────────

/// `pass` = 一遍重画开始；`bandCell` = 一格里真的画了一格（text = 带名）；
/// `bandLabel` = 带上印的那句；`label` / `legend` = 其余字符串。
typedef CentrifugePaintProbe = void Function(String kind, String? text);

/// ⛔ 仅供 widget 测试注入。**生产代码永不赋值。**
CentrifugePaintProbe? testCentrifugePaintProbe;

// ─────────────────────────── 屏上文案（守卫直接引用）────────

/// 三条带的带名，**按管内出现的先后**（重 → 中 → 轻 = 密度由大到小）。
const List<String> kCentrifugeBandNames = <String>['重带', '中带', '轻带'];

/// 图例：一格的定义 + 三段的次序。
/// ⛔ 用「依次」而不是任何方位说法（⛔ 禁方向词）。
const String kCentrifugeLegend = '一格 = 一个 DNA 分子；管内依次是重带、中带、轻带';

// 重带那句（依据行之一）。⛔ 只描述软件算出了什么。
const String kCentrifugeHeavyNote =
    '重带格数 = 总分子 − 含亲代标记链分子 − 全无标记分子；本图只在这条差为 0 时画。';

const List<String> kCentrifugeVisibleCopy = <String>[
  kCentrifugeLegend,
  kCentrifugeHeavyNote,
  ...kCentrifugeBandNames,
];

// ─────────────────────────── 版面常数 ───────────────────────────

/// 分子格边长的**实测**基准字号（等宽 ⇒ 一个数字的推进宽 = 字号）。
/// ⛔ 一格不取比它还细的尺寸：格子比图上最细的字还窄时，
///   学生读到的是一片噪点，不是「一格一个分子」。
const double kCentrifugeCellFontSize = 9;

/// 相邻两格之间的缝（1 逻辑像素 ⇒ 格与格在屏上仍是分开的）。
const double kCentrifugeCellGap = 1;

/// 管壁到第一列格子之间的内边距（两侧各一份）。
const double kCentrifugeTubePad = 2;

/// 管内净高（逻辑像素）。⛔ 由此算出能放几行，⛔ 不是随便定的：
/// 一格的步距 = 边长 + 缝（实测 9.0 + 1.0 = 10.0），200 ÷ 10 = 20 行
/// 的空间；整图（含图例与依据行）约 260px，不到一屏的三分之一。
const double kCentrifugeTubeHeight = 200;

/// 行首标注槽最多占可用宽度的几成（⛔ 防止数字很长时把管挤没）。
const double kCentrifugeGutterCapRatio = 0.45;

/// 设计宽度（逻辑像素）。仅在父级给出**无界宽度**时兜底。
const double kCentrifugeDesignWidth = 320;

/// 带标注 / 图例 / 依据行的字号（中文走 sans，⛔ 不挂 mono）。
const double kCentrifugeLabelSize = 11.5;
const double kCentrifugeBasisSize = 11;

/// 图例与管之间、管与依据行之间的缝。
const double _legendGap = 8;
const double _basisGap = 8;
const double _padTop = 2;
const double _padBottom = 8;

// ─────────────────────────── 版面解算（几何单一真相）──────────

@immutable
class CentrifugeLayout {
  const CentrifugeLayout({
    required this.width,
    required this.cellSide,
    required this.cols,
    required this.rows,
    required this.gutter,
    required this.tubeLeft,
    required this.tubeWidth,
    required this.labelWidths,
    required this.bandCells,
    required this.bands,
    required this.legendHeight,
    required this.basisHeight,
  });

  final double width;

  /// 一格的边长（实测值，⛔ 不写死）。
  final double cellSide;

  /// 管内一行放得下几格。
  final int cols;

  /// 管内放得下几行。
  final int rows;

  /// 行首标注槽宽度（实测三条带名里最宽的那条 + 缝）。
  final double gutter;

  final double tubeLeft;
  final double tubeWidth;

  /// 三条带各自的标注宽度（实测）。
  final List<double> labelWidths;

  /// 三条带各自画几格。⛔ 前两条逐字取自引擎字段，第三条是那三个
  /// 字段的差（见文件头）。
  final List<int> bandCells;

  /// 三条带各自占几行（⛔ 由 [bandCells] 算出，不写死）。
  final List<int> bands;

  final double legendHeight;
  final double basisHeight;

  /// 图例上边缘。
  double get legendTop => _padTop;

  /// 管的上边缘。
  double get tubeTop => legendTop + legendHeight + _legendGap;

  /// 管的下边缘。
  double get tubeBottom => tubeTop + kCentrifugeTubeHeight;

  /// 第 `band` 条带第 `row` 行的上边缘（`row` 是管内第几行，不是全局）。
  double bandRowTop(int band, int row) => tubeTop + kCentrifugeTubePad +
      (_bandStartRow(band) + row) * pitch;

  double get pitch => cellSide + kCentrifugeCellGap;

  int _bandStartRow(int band) {
    var r = 0;
    for (var i = 0; i < band; i++) {
      r += bands[i];
    }
    return r;
  }

  /// 管内第 `globalRow` 行第 `col` 列的格子矩形。
  Rect cellRect(int globalRow, int col) => Rect.fromLTWH(
      tubeLeft + kCentrifugeTubePad + col * pitch,
      tubeTop + kCentrifugeTubePad + globalRow * pitch,
      cellSide,
      cellSide);

  /// 三条带的标注文字（⛔ 带名 + [bandCells] 里的格数）。
  List<String> get labels => <String>[
        for (var i = 0; i < kCentrifugeBandNames.length; i++)
          '${kCentrifugeBandNames[i]} ${bandCells[i]} 个',
      ];

  /// 整图高度。
  double get designHeight => tubeBottom + _basisGap + basisHeight + _padBottom;

  /// 本图最多能画几格（= 行 × 列）。
  int get capacity => cols * rows;

  /// 三条带一共要占几行。
  int get requiredRows =>
      bands.fold(0, (a, b) => a + b);
}

/// 一格的边长：**实测**。
///
/// ⛔ 取本图标注里最小字号（[kCentrifugeCellFontSize]）下
///   **一个等宽数字的推进宽度**——即「格子不细于图上最细的字」。
/// ⛔ 不许写死：换字体/换档位实测值会变，写死就等于把实测名存实亡。
double centrifugeCellSide(Color ink) {
  final tp = TextPainter(
    text: TextSpan(text: '1', style: _cellFontStyle(ink)),
    textDirection: TextDirection.ltr,
  )..layout();
  return tp.width;
}

TextStyle _cellFontStyle(Color c) => TextStyle(
      fontFamily: AppFonts.mono,
      fontFamilyFallback: AppFonts.monoFallback,
      fontSize: kCentrifugeCellFontSize,
      fontWeight: FontWeight.w600,
      color: c,
    );

TextStyle centrifugeLabelStyleFor(Color c, {double size = kCentrifugeLabelSize}) =>
    TextStyle(
      fontFamily: AppFonts.sans,
      fontFamilyFallback: AppFonts.sansFallback,
      fontSize: size,
      fontWeight: FontWeight.w600,
      color: c,
    );

double _measure(String s, TextStyle st, {double? maxWidth}) {
  final tp = TextPainter(
    text: TextSpan(text: s, style: st),
    textDirection: TextDirection.ltr,
  )..layout(maxWidth: maxWidth ?? double.infinity);
  return tp.width;
}

double _measureH(String s, TextStyle st, {double? maxWidth}) {
  final tp = TextPainter(
    text: TextSpan(text: s, style: st),
    textDirection: TextDirection.ltr,
  )..layout(maxWidth: maxWidth ?? double.infinity);
  return tp.height;
}

/// 三条带各画几格。⛔ 前两条**逐字取自引擎字段**；第三条是那三个字段
/// 的差（见文件头；⛔ 只放行为 0 的数据，见 [dataReason]）。
List<int> bandCellsOf(DnaLabelResult r) => <int>[
      r.totalMolecules - r.labeledMolecules - r.unlabeledOnlyMolecules,
      r.labeledMolecules,
      r.unlabeledOnlyMolecules,
    ];

/// 求解版面。`null` = 当前宽度下画不出来（管会窄到放不下一格）。
CentrifugeLayout? resolveCentrifugeLayout({
  required DnaLabelResult result,
  required double availableWidth,
  required Color ink,
  required Color graphite,
}) {
  final width = availableWidth.isFinite && availableWidth > 0
      ? availableWidth
      : kCentrifugeDesignWidth;
  final labelStyle = centrifugeLabelStyleFor(graphite);
  final basisStyle = centrifugeLabelStyleFor(graphite, size: kCentrifugeBasisSize);

  final cells = bandCellsOf(result);
  final labels = <String>[
    for (var i = 0; i < kCentrifugeBandNames.length; i++)
      '${kCentrifugeBandNames[i]} ${cells[i]} 个',
  ];
  final labelWidths =
      labels.map((s) => _measure(s, labelStyle)).toList(growable: false);

  var gutter = 0.0;
  for (final w in labelWidths) {
    if (w > gutter) gutter = w;
  }
  gutter = gutter + 6;
  if (gutter > width * kCentrifugeGutterCapRatio) {
    gutter = width * kCentrifugeGutterCapRatio;
  }

  final cellSide = centrifugeCellSide(ink);
  final pitch = cellSide + kCentrifugeCellGap;
  final tubeLeft = gutter;
  final tubeWidth = width - gutter;
  final innerW = tubeWidth - 2 * kCentrifugeTubePad;
  if (innerW < pitch) return null;
  final cols = (innerW / pitch).floor();
  final rows = ((kCentrifugeTubeHeight - 2 * kCentrifugeTubePad) / pitch).floor();
  if (cols < 1 || rows < 1) return null;

  final bands = <int>[
    for (final c in cells) c <= 0 ? 0 : (c / cols).ceil(),
  ];
  final basis = centrifugeBasisText(result);
  return CentrifugeLayout(
    width: width,
    cellSide: cellSide,
    cols: cols,
    rows: rows,
    gutter: gutter,
    tubeLeft: tubeLeft,
    tubeWidth: tubeWidth,
    labelWidths: labelWidths,
    bandCells: cells,
    bands: bands,
    legendHeight: _measureH(kCentrifugeLegend, labelStyle, maxWidth: width),
    basisHeight: _measureH(basis, basisStyle, maxWidth: width),
  );
}

/// 依据行：**只复述引擎算出了什么**（含引擎自己那段带型文本，逐字）。
String centrifugeBasisText(DnaLabelResult r) =>
    '引擎给出：第 ${r.generations} 代共 ${r.totalMolecules} 个分子，'
    '含亲代标记链的 ${r.labeledMolecules} 个，全无标记的 '
    '${r.unlabeledOnlyMolecules} 个。${r.centrifugeBands} $kCentrifugeHeavyNote';

// ─────────────────────────── 组件 ───────────────────────────

class CentrifugeBandDiagram extends StatelessWidget {
  const CentrifugeBandDiagram({
    super.key,
    required this.result,
    this.textScale = 1.0,
  });

  /// 引擎算出的标记分布结果。⛔ 本组件**不重算、不写死**。
  final DnaLabelResult result;

  /// v2.19.172（R54）：课堂大屏字号倍率（标准模式 1.0 = 逐像素零变化）。
  ///
  /// 【为什么需要它】课堂模式的全局放大只经 `MaterialApp.builder` 注入
  /// `MediaQuery.textScaler`，那只对 **`Text` widget** 生效。本图上的图例
  /// （11.5px）、带标注（11.5px）与依据行（11px）是 `TextPainter` 自绘，而
  /// `TextPainter.textScaler` 默认 `TextScaler.noScaling`
  /// ——**不经过 MediaQuery** ⇒ 课堂大屏下这些字**完全没被放大**。
  /// ⚠️ `kCentrifugeCellFontSize`(9px) 只用于**量**一格的边长
  /// （`centrifugeCellSide`），格子里**没有字** ⇒ ⛔ 不乘它（一乘就改几何）。
  ///
  /// 【怎么用】宿主（`molecular_page.dart` 构造本组件处）在
  /// `PresentModeController.instance.enabled` 时传
  /// `PresentModeController.textScale`，否则传 1.0。
  final double textScale;

  /// ⛔ **数据闸**（与宽度无关）：返回 null = 数据可画。
  static String? dataReason(DnaLabelResult? r) {
    if (r == null) return '还没有算出标记分布，本图没有数据可画。';
    for (final v in [r.generations, r.totalMolecules, r.labeledMolecules,
        r.unlabeledOnlyMolecules, r.labeledStrands, r.totalStrands]) {
      if (v < 0) return '引擎给出的计数里出现了负数，本图不画。';
    }
    if (r.labeledMolecules > r.totalMolecules) {
      return '含亲代标记链的分子数超过了分子总数，本图不画。';
    }
    if (r.unlabeledOnlyMolecules > r.totalMolecules) {
      return '全无标记的分子数超过了分子总数，本图不画。';
    }
    // ⛔ 重带差必须为 0（引擎的带型文本对每个 n 都写「无重带」）。
    final heavy = bandCellsOf(r)[0];
    if (heavy != 0) {
      return '总分子数与两条带的分子数对不上（差额 $heavy），本图不画。';
    }
    return null;
  }

  /// ⛔ **完整闸**：数据 + 当前宽度都放行才画。
  /// 非 null = 不画的那一句，⛔ **调用方要把它印在屏上**。
  static String? skipReason(DnaLabelResult? r, double availableWidth) {
    final d = dataReason(r);
    if (d != null) return d;
    final l = resolveCentrifugeLayout(
      result: r!,
      availableWidth: availableWidth,
      ink: AppColors.ink,
      graphite: AppColors.graphite,
    );
    if (l == null) {
      return '当前宽度下离心管放不下一格分子，本图不画；'
          '屏上的文字结果不受影响。';
    }
    if (l.requiredRows > l.rows) {
      return '共 ${r.totalMolecules} 个分子，按每行 ${l.cols} 格排要 '
          '${l.requiredRows} 行，管内只放得下 ${l.rows} 行，'
          '本图不画（不是只画一部分）；屏上的文字结果不受影响。';
    }
    return null;
  }

  static bool canDraw(DnaLabelResult? r, double availableWidth) =>
      skipReason(r, availableWidth) == null;

  /// 屏上语义标签。
  static String semanticsLabel(DnaLabelResult r) {
    final cells = bandCellsOf(r);
    final b = StringBuffer('离心管带型：');
    for (var i = 0; i < kCentrifugeBandNames.length; i++) {
      b.write('${kCentrifugeBandNames[i]} ${cells[i]} 个；');
    }
    b.write(kCentrifugeLegend);
    b.write(centrifugeBasisText(r));
    return b.toString();
  }

  @override
  Widget build(BuildContext context) {
    if (dataReason(result) != null) return const SizedBox.shrink();

    return Semantics(
      label: semanticsLabel(result),
      child: RepaintBoundary(
        child: LayoutBuilder(
          builder: (context, c) {
            final layout = resolveCentrifugeLayout(
              result: result,
              availableWidth: c.maxWidth,
              ink: AppColors.ink,
              graphite: AppColors.graphite,
            );
            if (layout == null) return const SizedBox.shrink();
            if (layout.requiredRows > layout.rows) {
              return const SizedBox.shrink();
            }
            return SizedBox(
              width: double.infinity,
              height: layout.designHeight,
              child: CustomPaint(
                painter: CentrifugeBandPainter(
                  result: result,
                  layout: layout,
                  ink: AppColors.ink,
                  graphite: AppColors.graphite,
                  steel: AppColors.steel,
                  border: AppColors.border,
                  teal: AppColors.teal,
                  wash: AppColors.tealWash,
                  surface: AppColors.surfaceLow,
                  textScale: textScale,
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

// ─────────────────────────── painter ───────────────────────────

class CentrifugeBandPainter extends CustomPainter {
  CentrifugeBandPainter({
    required this.result,
    required this.layout,
    required this.ink,
    required this.graphite,
    required this.steel,
    required this.border,
    required this.teal,
    required this.wash,
    required this.surface,
    this.textScale = 1.0,
  });

  final DnaLabelResult result;
  final CentrifugeLayout layout;

  final Color ink;
  final Color graphite;
  final Color steel;
  final Color border;
  final Color teal;
  final Color wash;
  final Color surface;

  /// v2.19.172（R54）：课堂大屏字号倍率。宿主在课堂档传
  /// `PresentModeController.textScale`，标准档传 1.0。详见
  /// [CentrifugeBandDiagram.textScale] 的完整理由。
  final double textScale;

  /// 把一个 `TextStyle` 的 `fontSize` 乘上课堂倍率。
  ///
  /// `textScale == 1.0` 时 `fs * 1.0 == fs`（IEEE-754 精确）⇒ 标准模式逐
  /// 像素零变化。
  ///
  /// ⚠️ 本 painter ⛔ **没有** 统一的画字 helper（图例 / 带标注 / 依据行
  /// 三处各自建 `TextPainter`），所以 `_scaled` 逐处显式套用——三处漏一处
  /// 就是课堂档半张图放大半张图没放大。
  TextStyle _scaled(TextStyle style) {
    final fs = style.fontSize;
    if (fs == null) return style;
    return style.copyWith(fontSize: fs * textScale);
  }

  void _emit(String kind, [String? text]) =>
      testCentrifugePaintProbe?.call(kind, text);

  @override
  void paint(Canvas canvas, Size size) {
    _emit('pass');

    _paintLegend(canvas);
    _paintTube(canvas);
    _paintBands(canvas);
    _paintBasis(canvas);
  }

  void _paintLegend(Canvas canvas) {
    final tp = TextPainter(
      text: TextSpan(
          text: kCentrifugeLegend,
          style: _scaled(centrifugeLabelStyleFor(graphite))),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: layout.width);
    tp.paint(canvas, Offset(0, layout.legendTop));
    _emit('legend', kCentrifugeLegend);
  }

  /// 管身：一个上圆角、下圆角更大的圆角矩形（离心管的样子）。
  void _paintTube(Canvas canvas) {
    final r = Rect.fromLTWH(layout.tubeLeft, layout.tubeTop, layout.tubeWidth,
        kCentrifugeTubeHeight);
    final rr = RRect.fromRectAndRadius(r, const Radius.circular(10));
    canvas.drawRRect(rr, Paint()..color = surface);
    canvas.drawRRect(
      rr,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..color = border,
    );
  }

  void _paintBands(Canvas canvas) {
    final cells = bandCellsOf(result);
    var rowCursor = 0;
    for (var band = 0; band < kCentrifugeBandNames.length; band++) {
      final name = kCentrifugeBandNames[band];
      final count = cells[band];
      final rows = count <= 0 ? 0 : (count / layout.cols).ceil();
      // 带标注（行首槽）：带名 + 引擎给的格数。
      final s = layout.labels[band];
      final labelTp = TextPainter(
        text: TextSpan(
            text: s, style: _scaled(centrifugeLabelStyleFor(graphite))),
        textDirection: TextDirection.ltr,
      )..layout();
      final top = layout.bandRowTop(band, 0);
      labelTp.paint(
          canvas, Offset(0, top + (layout.cellSide - labelTp.height) / 2));
      _emit('bandLabel', s);

      for (var i = 0; i < count; i++) {
        final r = rowCursor + i ~/ layout.cols;
        final c = i % layout.cols;
        final rect = layout.cellRect(r, c);
        _fillCell(canvas, rect, band);
        _emit('bandCell', name);
      }
      if (count == 0) {
        // ⛔ 0 格也要留一条**中性细线**标明这条带的位置，
        //   否则「轻带 0 个」在管里看不见，学生会以为漏画了。
        final y = layout.bandRowTop(band, 0);
        canvas.drawLine(
          Offset(layout.tubeLeft + kCentrifugeTubePad, y + layout.cellSide / 2),
          Offset(layout.tubeLeft + layout.tubeWidth - kCentrifugeTubePad,
              y + layout.cellSide / 2),
          Paint()
            ..strokeWidth = 1.0
            ..color = steel,
        );
        _emit('bandEmptyMark', name);
      }
      rowCursor += rows;
    }
  }

  void _fillCell(Canvas canvas, Rect r, int band) {
    // ⛔ 颜色一律由构造器传入（AppColors.* getter 现读）。
    //   ⛔ 不用 AppColors.lethal（致死语义）。
    final Paint fill = Paint()
      ..color = switch (band) {
        0 => steel,
        1 => wash,
        _ => surface,
      };
    canvas.drawRRect(
      RRect.fromRectAndRadius(r, const Radius.circular(1)),
      fill,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(r, const Radius.circular(1)),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.8
        ..color = switch (band) {
          0 => graphite,
          1 => teal,
          _ => steel,
        },
    );
  }

  void _paintBasis(Canvas canvas) {
    final s = centrifugeBasisText(result);
    final tp = TextPainter(
      text: TextSpan(
          text: s,
          style: _scaled(
              centrifugeLabelStyleFor(graphite, size: kCentrifugeBasisSize))),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: layout.width);
    tp.paint(canvas, Offset(0, layout.tubeBottom + _basisGap));
    _emit('basis', s);
  }

  @override
  bool shouldRepaint(covariant CentrifugeBandPainter old) =>
      old.result != result ||
      old.layout != layout ||
      old.ink != ink ||
      old.graphite != graphite ||
      old.steel != steel ||
      old.border != border ||
      old.teal != teal ||
      old.wash != wash ||
      old.surface != surface ||
      // v2.19.172（R54）：课堂倍率必须参与比较——否则课堂上切换课堂模式时
      // 画布复用旧 painter，字号停在标准模式那一档。
      old.textScale != textScale;
}
