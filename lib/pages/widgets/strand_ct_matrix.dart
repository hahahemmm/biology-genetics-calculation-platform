// strand_ct_matrix.dart —— 「两链 C/T 计数」三行四列格阵
// （v2.19.167，分子遗传页 tab0「碱基组成」的两链 C/T 计数互推）
//
// ── 它补的是哪一步（实测）──────────────────────────────────────
//
// 出厂输入（链1 C=10 T=20；链2 C=15 T=25）点「计算全分子碱基」之后，
// 屏上真实渲染出来的是这么几行（`flutter test` 抓的 `Text`，非凭想象）：
//
//     题干数据   链1 C=10 T=20；链2 C=15 T=25
//     互补配对   A=T₁+T₂，G=C₁+C₂
//                链1 的 A 配对链2 的 T，链1 的 G 配对链2 的 C
//     全分子结果 A=45　T=45　G=25　C=25
//                碱基总数 140 个
//
// ⛔ **链1、链2 各自那一行的数字，屏上一个都没出现。**
// 这不是本组件偷懒：`strandCountsFromCT`（`dna_strand_engine.dart:182`）
// 只给出 `c1 / t1 / c2 / t2` 与**全分子**的 `aTotal / tTotal / gTotal /
// cTotal / total`，它**没有** `a1 / g1 / a2 / g2` 这四个字段
// （已核该文件全文：⛔ 无 `a1`、`g1`、`a2`、`g2` 字段）。
// ⇒ 3 行 × 4 列共 12 格里，**引擎只填了 8 格**（c1/t1/c2/t2 四个 +
//   全分子四个），另外 4 格（链1 的 A、链2 的 A、链1 的 G、链2 的 G）
//   是空的。
//
// ── ⛔⛔ 空格不许填 0（本作最重要的一条）──────────────────────
//
// 把空格画成 0，等于宣称「链1 的 A 是 0 个」。这**不是引擎算出来的**，
// 是本图自己编的 ⇒ 违反诚实红线。空格画成**只有框、没有字**，
// 并由图例明写「空格 = 引擎没有给出这一格的数量，本图不代填」。
//
// 附带一条**不能自己补**的理由：学生若把链1 的 A 补成 `t2`，
// 那一步是「另一条推论」，而屏上此刻并没有算它 —— 图一旦代填，
// 图与依据行就会各说各话。
//
// ── ⛔ 本图不画碱基配对双螺旋 ────────────────────────────────
//
// 引擎给的是 4 个整数 + 4 个整数，**没有任何序列**
// （`StrandCTResult` 全文 9 个 int 字段，见上）。
// 画双螺旋就得自己编一条序列出来 ⇒ 编内容，本图不画。
//
// ── 数字纪律 ─────────────────────────────────────────────────
//
// 格子里每一个字都直接读引擎字段（见 [StrandCtMatrix.cellValue]：
// 一张 switch 表，⛔ 无任何算术）。整幅图 ⛔ 不出现 `+ - * /` 参与数值。

import 'package:flutter/material.dart';

import '../../engine/dna_strand_engine.dart';
import '../../theme.dart';

// ─────────────────────────── 绘制记录钩（仅供测试注入）───────────

/// 绘制事件种类。`pass` = 一遍重画开始（测试按它清账）。
/// ⛔ `cell` 上报的是 **painter 真正落到屏上的那个数字**，
///   `blankCell` 上报的是**空格子**（引擎没给的那 6 格）。
typedef StrandCtPaintProbe = void Function(String kind, String? text);

/// ⛔ 仅供 widget 测试注入。**生产代码永不赋值。**
StrandCtPaintProbe? testStrandCtPaintProbe;

// ─────────────────────────── 屏上文案（守卫直接引用）────────

/// 四列的碱基名。列序 = 引擎字段给出的顺序（`c1,t1,c2,t2` 与
/// `aTotal,tTotal,gTotal,cTotal` 都是 A,T,G,C 这套口径）。
const List<String> kStrandCtColumns = <String>['A', 'T', 'G', 'C'];

/// 三行：链1 / 链2 / 全分子。
const List<String> kStrandCtRows = <String>['链1', '链2', '全分子'];

/// ⛔ 空格的含义。图例**定义级**的话：它说的是「本图不画什么」。
const String kStrandCtBlankLegend = '空格 = 引擎没有给出这一格的数量，本图不代填';

/// 本图渲染在屏上的**全部**静态文案（守卫直接遍历，不在测试里重抄）。
const List<String> kStrandCtVisibleCopy = <String>[
  kStrandCtBlankLegend,
  ...kStrandCtColumns,
  ...kStrandCtRows,
];

// ─────────────────────────── 版面常数 ───────────────────────────

/// 格内数字的候选字号，**从大到小**试。
/// ⛔ 不得低于 8：再小就看不出是几位数了（实测：8pt 等宽一个数字
/// 宽 8.0 逻辑像素，低于 8 时三位数与两位数几乎一样宽）。
const List<double> kStrandCtFontCandidates = <double>[13, 12, 11, 10, 9, 8];

/// 行首标注槽与网格之间的缝。
const double _gutterGap = 6;

/// 列与列之间的缝。
const double _colGap = 4;

/// 格内左右 / 上下留白。
const double _padX = 5;
const double _padY = 4;

/// 图例字号 / 依据行字号（中文用 sans，⛔ 不挂 mono）。
const double _legendSize = 11;
const double _basisSize = 11;

/// 图例与网格之间、网格与依据行之间的缝。
const double _legendGap = 6;
const double _basisGap = 8;

const double _padTop = 2;
const double _padBottom = 8;

/// 设计宽度（逻辑像素）。仅在父级给出**无界宽度**时兜底。
const double kStrandCtDesignWidth = 320;

/// 版面解算结果。**painter 与测试读同一份**。
@immutable
class StrandCtMatrixLayout {
  const StrandCtMatrixLayout({
    required this.fontSize,
    required this.rowPitch,
    required this.gutter,
    required this.colWidths,
    required this.colLefts,
    required this.width,
    required this.legendHeight,
    required this.basisHeight,
    required this.basis,
  });

  /// 数字实际用的字号（候选里第一个装得下的）。
  final double fontSize;

  /// 相邻两行**网格**上边缘之差（列名行与三个数据行共用同一节奏）。
  final double rowPitch;

  /// 行首标注槽宽度。
  final double gutter;

  /// 四列各自占的宽（按该列最宽的数字量，⛔ 不写死）。
  final List<double> colWidths;

  /// 四列各自的左边缘。
  final List<double> colLefts;

  final double width;

  /// 图例那一行按实测宽度折行后的高度。
  final double legendHeight;

  /// 依据行折行后的高度。
  final double basisHeight;

  /// 依据行原文（守卫与测试共用同一份，⛔ 不各写一遍）。
  final String basis;

  /// 列名行的上边缘。
  double get headerTop => _padTop + legendHeight + _legendGap;

  /// 第 `row` 行（0 = 列名行，1..3 = 链1/链2/全分子）的上边缘。
  double rowTop(int row) => headerTop + row * rowPitch;

  /// 第 `row` 行第 `col` 列的矩形。
  Rect cellRect(int row, int col) => Rect.fromLTWH(
      colLefts[col], rowTop(row), colWidths[col], rowPitch);

  /// 依据行的上边缘。
  double get basisTop => rowTop(kStrandCtRows.length + 1) + _basisGap;

  /// 整图高度。
  double get designHeight => basisTop + basisHeight + _padBottom;

  /// 网格实际占用的宽度（不含行首槽）。
  double get gridWidth =>
      colWidths.fold(0.0, (a, b) => a + b) + _colGap * (colWidths.length - 1);
}

/// 量一段文字的宽 / 高（⛔ 唯一的排版测量入口，painter 与解算共用）。
class StrandCtText {
  StrandCtText(this.size, this.mono, this.color);
  final double size;
  final bool mono;
  final Color color;

  TextStyle get style => mono
      ? TextStyle(
          fontFamily: AppFonts.mono,
          fontFamilyFallback: AppFonts.monoFallback,
          fontSize: size,
          fontWeight: FontWeight.w600,
          color: color,
        )
      : TextStyle(
          fontFamily: AppFonts.sans,
          fontFamilyFallback: AppFonts.sansFallback,
          fontSize: size,
          fontWeight: FontWeight.w600,
          color: color,
        );

  double widthOf(String s) => _tp(s, size).width;

  double heightOf(String s, {double? maxWidth}) =>
      _tp(s, size, maxWidth: maxWidth).height;

  TextPainter _tp(String s, double size, {double? maxWidth}) => TextPainter(
        text: TextSpan(text: s, style: style),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: maxWidth ?? double.infinity);

  void paint(Canvas canvas, String s, Offset at) {
    _tp(s, size).paint(canvas, at);
  }

  /// 按 `maxWidth` 折行后逐行绘制，返回绘制高度。
  void paintWrapped(Canvas canvas, String s, Offset at, double maxWidth) {
    _tp(s, size, maxWidth: maxWidth).paint(canvas, at);
  }
}

/// 求解版面。⛔ **一个字宽都不许在测试里另抄一份**：
/// 另抄一份只能证明抄对了，测不出 painter 少画一列。
///
/// [textScale] 是课堂大屏字号倍率（标准档 1.0）。⚠️ v2.19.172（R58）起它
/// **只乘在「量」的那一层**：[StrandCtText] 拿到的字号是 `字号 × 倍率`
/// ⇒ 行首槽、列宽、行距、图例与依据行的高度全部按放大后的字重新量。
/// ⛔ `_padX/_padY/_colGap/_gutterGap/_legendGap/_basisGap/_padTop/
/// _padBottom` 是设计稿写死的缝与内边距，⛔ 不乘。
/// [StrandCtMatrixLayout.fontSize] 存的仍是**未乘**的字号（painter 会再乘
/// 一次）—— 两边乘数相同才自洽，⛔ 不许在这里存放大后的字号。
/// `textScale == 1.0` 时每一个乘数都是 1.0（IEEE-754 精确）⇒ 标准档逐像素不变。
StrandCtMatrixLayout? resolveStrandCtLayout({
  required StrandCTResult result,
  required double availableWidth,
  required Color ink,
  required Color graphite,
  double textScale = 1.0,
}) {
  final width = availableWidth.isFinite && availableWidth > 0
      ? availableWidth
      : kStrandCtDesignWidth;

  // 行首槽：三条行名里最宽的那条（实测，⛔ 不写死 46）。
  final nameProbe = StrandCtText(11.5 * textScale, false, graphite);
  var gutter = 0.0;
  for (final n in kStrandCtRows) {
    final w = nameProbe.widthOf(n);
    if (w > gutter) gutter = w;
  }
  gutter += _gutterGap;

  final basis = strandCtBasisLine(result);
  final basisProbe = StrandCtText(_basisSize * textScale, false, graphite);
  final legendProbe = StrandCtText(_legendSize * textScale, false, graphite);
  final legendHeight = legendProbe.heightOf(kStrandCtBlankLegend,
      maxWidth: width);
  final basisHeight = basisProbe.heightOf(basis, maxWidth: width);

  // 12 格的文字先量出来（⛔ 值只来自引擎，空格算 null）。
  for (final size in kStrandCtFontCandidates) {
    final num = StrandCtText(size * textScale, true, ink);
    final colW = List<double>.filled(kStrandCtColumns.length, 0.0);
    for (var row = 0; row < kStrandCtRows.length; row++) {
      for (var col = 0; col < kStrandCtColumns.length; col++) {
        final v = StrandCtMatrix.cellValue(result, row, col);
        if (v == null) continue;
        final w = num.widthOf('$v') + 2 * _padX;
        if (w > colW[col]) colW[col] = w;
      }
    }
    // 列名自身也要装得下。
    final headProbe = StrandCtText(size * textScale, true, graphite);
    for (var col = 0; col < kStrandCtColumns.length; col++) {
      final w = headProbe.widthOf(kStrandCtColumns[col]) + 2 * _padX;
      if (w > colW[col]) colW[col] = w;
    }
    final total = gutter + colW.fold(0.0, (a, b) => a + b) +
        _colGap * (kStrandCtColumns.length - 1);
    if (total > width) continue;

    final rowPitch = num.heightOf('0') + 2 * _padY;
    final lefts = <double>[];
    var x = gutter;
    for (final cw in colW) {
      lefts.add(x);
      x += cw + _colGap;
    }
    return StrandCtMatrixLayout(
      fontSize: size,
      rowPitch: rowPitch,
      gutter: gutter,
      colWidths: colW,
      colLefts: lefts,
      width: width,
      legendHeight: legendHeight,
      basisHeight: basisHeight,
      basis: basis,
    );
  }
  return null; // 最小的字号也装不下 ⇒ 交给调用方处理（不留空框）
}

/// 依据行：**只复述引擎算出了什么**。
/// ⛔ 每一个数都直接取字段，⛔ 不出现任何推论、任何评价。
String strandCtBasisLine(StrandCTResult r) =>
    '引擎给出：链1 C=${r.c1}、T=${r.t1}；链2 C=${r.c2}、T=${r.t2}；'
    '全分子 A=${r.aTotal}、T=${r.tTotal}、G=${r.gTotal}、C=${r.cTotal}；'
    '碱基总数 ${r.total}。';

// ─────────────────────────── 组件 ───────────────────────────

/// 「两链 C/T 计数」三行四列格阵。
///
/// ## ⛔ 不可画时**什么都不留**
/// 数据对不上（负数 / A≠T / G≠C / 碱基总数对不上）或最小字号仍装不下
/// ⇒ 整个组件收缩成 `SizedBox.shrink()`：**不留空框、不留标题、
/// 不留占位**（与 `offspring_diagram.dart` / `dogma_strand_diagram.dart`
/// 同一道闸）。
class StrandCtMatrix extends StatelessWidget {
  const StrandCtMatrix({
    super.key,
    required this.result,
    this.textScale = 1.0,
  });

  /// 引擎算出的两链 C/T 计数结果。⛔ 本组件**不重算、不写死**。
  final StrandCTResult result;

  /// v2.19.172（R54）：课堂大屏字号倍率（标准模式 1.0 = 逐像素零变化）。
  ///
  /// 【为什么需要它】课堂模式的全局放大只经 `MaterialApp.builder` 注入
  /// `MediaQuery.textScaler`，那只对 **`Text` widget** 生效。本图上的格内
  /// 数字（8~13px，按列宽实测验出）、列名（同行）、行名（11.5px）、图例与
  /// 依据行（11px）全部是 `TextPainter` 自绘，而 `TextPainter.textScaler`
  /// 默认 `TextScaler.noScaling` ——**不经过 MediaQuery** ⇒ 课堂大屏下这些
  /// 数字**完全没被放大**；那个 8px 档在 10 米外是噪点。
  ///
  /// ⚠️ v2.19.172（R54）只把它接到了 painter 上，版面解算
  /// [resolveStrandCtLayout] 读不到本字段 ⇒ 课堂档下列宽 / 行距仍按 1.0
  /// 那一档算。R58 起该函数收下 [textScale]，两侧用同一个乘数。
  ///
  /// 【怎么用】宿主（`molecular_page.dart` 构造本组件处）在
  /// `PresentModeController.instance.enabled` 时传
  /// `PresentModeController.textScale`，否则传 1.0。
  final double textScale;

  /// 某格显示的数字。⛔ **纯字段读取**：return 的一律是引擎字段本身，
  /// ⛔ 全表没有任何算术。返回 `null` = 引擎没给这一格 ⇒ **画成空格**。
  static int? cellValue(StrandCTResult r, int row, int col) =>
      switch ((row, col)) {
        (0, 1) => r.t1,
        (0, 3) => r.c1,
        (1, 1) => r.t2,
        (1, 3) => r.c2,
        (2, 0) => r.aTotal,
        (2, 1) => r.tTotal,
        (2, 2) => r.gTotal,
        (2, 3) => r.cTotal,
        _ => null,
      };

  /// 该格引擎给了没有。
  static bool isGiven(StrandCTResult r, int row, int col) =>
      cellValue(r, row, col) != null;

  /// ⛔ **数据闸**：数据自身对不上时给出一句屏上说明（返回 null = 可画）。
  ///
  /// 三条判据都直接来自引擎自己的构造（`dna_strand_engine.dart:191-196`）：
  /// `aTotal = tTotal = T₁+T₂`、`gTotal = cTotal = C₁+C₂`、
  /// `total = (A+G)×2`。任一条对不上，说明传进来的不是引擎那一份结果。
  static String? dataReason(StrandCTResult? r) {
    if (r == null) return '还没有算出两链 C/T 的计数，本图没有数据可画。';
    for (final v in [r.c1, r.t1, r.c2, r.t2, r.aTotal, r.tTotal, r.gTotal,
        r.cTotal, r.total]) {
      if (v < 0) return '引擎给出的计数里出现了负数，本图不画。';
    }
    if (r.aTotal != r.tTotal || r.gTotal != r.cTotal) {
      return '全分子的 A 与 T、G 与 C 两处计数对不上，本图不画。';
    }
    if (r.total != (r.aTotal + r.gTotal) * 2) {
      return '碱基总数与各格的计数对不上，本图不画。';
    }
    return null;
  }

  /// ⛔ 完整闸：**数据 + 当前宽度**都放行才画。
  /// 返回非 null = 不画的那一句（⛔ 调用方要把它印在屏上，
  /// ⛔ **零静默截断**）。
  ///
  /// [textScale] 让调用方能按**它真正要画的那一档**字号来问这道闸
  /// （标准档 1.0 = 既有行为，既有调用点一个字都不用改）。
  static String? skipReason(StrandCTResult? r, double availableWidth,
      {double textScale = 1.0}) {
    final d = dataReason(r);
    if (d != null) return d;
    final l = resolveStrandCtLayout(
      result: r!, availableWidth: availableWidth,
      ink: AppColors.ink, graphite: AppColors.graphite,
      textScale: textScale,
    );
    if (l == null) {
      return '这一组计数在当前宽度下用最小的字号也排不进 4 列，本图不画；'
          '屏上的文字结果不受影响。';
    }
    return null;
  }

  static bool canDraw(StrandCTResult? r, double availableWidth,
          {double textScale = 1.0}) =>
      skipReason(r, availableWidth, textScale: textScale) == null;

  /// 屏上语义标签（读屏用户也是学生）。
  static String semanticsLabel(StrandCTResult r) {
    final b = StringBuffer('两链 C/T 计数格阵：');
    for (var row = 0; row < kStrandCtRows.length; row++) {
      b.write('${kStrandCtRows[row]}：');
      final parts = <String>[];
      for (var col = 0; col < kStrandCtColumns.length; col++) {
        final v = cellValue(r, row, col);
        parts.add('${kStrandCtColumns[col]}'
            '${v == null ? '（引擎没给）' : v}');
      }
      b.write('${parts.join('、')}；');
    }
    b.write(kStrandCtBlankLegend);
    b.write(strandCtBasisLine(r));
    return b.toString();
  }

  @override
  Widget build(BuildContext context) {
    if (dataReason(result) != null) return const SizedBox.shrink();

    // ⛔ AppColors 的 20 个 token **全是 getter**（亮度随档位实时派生）。
    //   在这里取值再传给 painter，⛔ 不让 painter 自己去读、
    //   ⛔ 也不冻进 static final（冻了就停在首次访问那一刻，切深色时不跟）。
    return Semantics(
      label: semanticsLabel(result),
      child: RepaintBoundary(
        child: LayoutBuilder(
          builder: (context, c) {
            final layout = resolveStrandCtLayout(
              result: result,
              availableWidth: c.maxWidth,
              ink: AppColors.ink,
              graphite: AppColors.graphite,
              // v2.19.172（R58）：课堂倍率必须进版面解算 —— 否则行首槽、
              // 列宽与行距仍按 1.0 那一档算，格里的数字放大后顶出格外
              // （实测课堂档 25.0 宽挤进 24.3 的列 = 1.03×）。
              textScale: textScale,
            );
            if (layout == null) return const SizedBox.shrink();
            return SizedBox(
              width: double.infinity,
              height: layout.designHeight,
              child: CustomPaint(
                painter: StrandCtPainter(
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

/// 真正落笔的那一层。⛔ 颜色**全部由构造器传入**。
class StrandCtPainter extends CustomPainter {
  StrandCtPainter({
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

  final StrandCTResult result;
  final StrandCtMatrixLayout layout;

  final Color ink;
  final Color graphite;
  final Color steel;
  final Color border;
  final Color teal;
  final Color wash;
  final Color surface;

  /// v2.19.172（R54）：课堂大屏字号倍率。宿主在课堂档传
  /// `PresentModeController.textScale`，标准档传 1.0。详见
  /// [StrandCtMatrix.textScale] 的完整理由。
  final double textScale;

  /// 把一个**字号**乘上课堂倍率。
  ///
  /// ⚠️ 本文件的样式出口 [StrandCtText] 是**按字号**寻址的（它拿一个
  /// `size` 现场拼 `TextStyle`），不像同批组件那样收一个成品 `TextStyle`
  /// ⇒ 倍率只能加在**字号**这一层，语义与其它组件的 `_scaled(TextStyle)`
  /// 完全等价（都是 `fs * textScale`）。
  ///
  /// `textScale == 1.0` 时 `size * 1.0 == size`（IEEE-754 精确）⇒ 标准模式
  /// 逐像素零变化。乘在 [StrandCtText] 的构造参数上而不是改 [StrandCtText]
  /// 本身，是为了 ⛔ 不动那个**版面解算与测试共用**的类（改了会让
  /// `resolveStrandCtLayout` 与 painter 读到的字号对不上号）。
  double _scaled(double size) => size * textScale;

  void _emit(String kind, [String? text]) =>
      testStrandCtPaintProbe?.call(kind, text);

  @override
  void paint(Canvas canvas, Size size) {
    // ⛔ 一遍重画开始：之前那一遍全部作废（数的是屏上此刻这一遍）。
    _emit('pass');

    _legend(canvas).paintWrapped(canvas, kStrandCtBlankLegend,
        const Offset(0, _padTop), layout.width);
    _emit('label', kStrandCtBlankLegend);

    _paintHeader(canvas);
    for (var row = 0; row < kStrandCtRows.length; row++) {
      _paintRow(canvas, row);
    }

    _basisText(canvas)
        .paintWrapped(canvas, layout.basis, Offset(0, layout.basisTop),
            layout.width);
    _emit('label', layout.basis);
  }

  // ── 五个画字出口，⛔ 每一处都必须经 [_scaled]（漏一处 = 半张图没放大）──
  StrandCtText _legend(Canvas _) =>
      StrandCtText(_scaled(_legendSize), false, graphite);
  StrandCtText _basisText(Canvas _) =>
      StrandCtText(_scaled(_basisSize), false, graphite);
  StrandCtText _num(Canvas _) =>
      StrandCtText(_scaled(layout.fontSize), true, ink);
  StrandCtText _name(Canvas _) => StrandCtText(_scaled(11.5), false, graphite);
  StrandCtText _head(Canvas _) =>
      StrandCtText(_scaled(layout.fontSize), true, graphite);

  void _paintHeader(Canvas canvas) {
    final t = _head(canvas);
    for (var col = 0; col < kStrandCtColumns.length; col++) {
      final r = layout.cellRect(0, col);
      final s = kStrandCtColumns[col];
      t.paint(canvas, s,
          Offset(r.left + (r.width - t.widthOf(s)) / 2, r.top + _padY));
      _emit('header', s);
    }
  }

  void _paintRow(Canvas canvas, int row) {
    // 行首标注（⛔ 走行首槽，⛔ 不用方向词）。
    final name = _name(canvas);
    final n = kStrandCtRows[row];
    final r0 = layout.cellRect(row + 1, 0);
    name.paint(canvas, n,
        Offset(0, r0.top + (r0.height - name.heightOf(n)) / 2));
    _emit('label', n);

    final num = _num(canvas);
    for (var col = 0; col < kStrandCtColumns.length; col++) {
      final v = StrandCtMatrix.cellValue(result, row, col);
      final r = layout.cellRect(row + 1, col);
      if (v == null) {
        // ⛔ 空格子：**只有框、没有字**。⛔ 绝不许写 0。
        _frame(canvas, r, border);
        _emit('blankCell', '${n}/${kStrandCtColumns[col]}');
        continue;
      }
      final s = '$v';
      _cell(canvas, r, fill: wash, stroke: teal);
      num.paint(canvas, s,
          Offset(r.left + (r.width - num.widthOf(s)) / 2, r.top + _padY));
      _emit('cell', s);
    }
  }

  void _cell(Canvas canvas, Rect r, {required Color fill, required Color stroke}) {
    final rr = RRect.fromRectAndRadius(r, const Radius.circular(3));
    canvas.drawRRect(rr, Paint()..color = fill);
    _frame(canvas, r, stroke);
  }

  void _frame(Canvas canvas, Rect r, Color c) {
    canvas.drawRRect(
      RRect.fromRectAndRadius(r, const Radius.circular(3)),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0
        ..color = c,
    );
  }

  @override
  bool shouldRepaint(covariant StrandCtPainter old) =>
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
