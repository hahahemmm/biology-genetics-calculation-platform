// semiconservative_grid.dart —— 「半保留复制 2ⁿ 个分子」格阵
// （v2.19.167，分子遗传页 tab1「复制与标记」的 DNA 半保留复制一节）
//
// ── 它补的是哪一步（实测）──────────────────────────────────────
//
// 出厂 copies=3，点「计算复制结果」之后屏上真实渲染出来的是：
//
//     2^3 = 8 个
//     含亲代链的 DNA      2 个（半保留复制特征）
//     新合成链数         14 条
//
// ⛔ 「8 个里有 2 个带亲代链」屏上只有**两个数字**，没有一个方块。
// 学生看到「2^3 = 8」时，脑子里那 8 格仍然是空的；
// 而「**只有 2 格**」这件事恰恰是半保留复制的全部看点——
// 一个空格阵里只有两格被点亮，比两个数字直观得多。
//
// ── ⛔⛔ 关于「恰好 2 个」：能画，但不许推广 ──────────────────
//
// `withParentStrand: 2` 在引擎里是**硬编码常量**
// （`dna_engine.dart:119`，不是算出来的），它描述的是
// 「**一个** DNA 分子复制 n 次」这一固定起点。
// ⇒ 本图画「恰好 2 个高亮」是忠实的；⛔ 但屏上**一个字都不许**
//   把它说成任何一般性结论（不许出现「无论几个」「总是」「恒为」
//   一类措辞）。依据行只写「引擎算出含亲代链的分子是 N 个」。
//
// ── ⛔ 高亮格的位置：软件没给，本图自己挑，并说明 ────────────
//
// 引擎只给一个**个数**，没给是哪几个。
// 若悄悄点亮前两格而不说明，学生会以为位置也有讲究。
// ⇒ 图上明写「软件只给出个数，没有指定位置；图上取靠前的高亮格」。
//
// ── ⛔⛔ 2ⁿ 会爆：上限闸是**实测**的 ──────────────────────────
//
// 引擎允许 copies ≤ 40 ⇒ 2⁴⁰ = 1 099 511 627 776 格。
// 一格的边长由**实测**决定（见 [semiconservativeCellSide]）。
// 放不下就整图不画，屏上明写「共 X 个分子 … 只放得下 Y 格」，
// ⛔ **零静默截断**（悄悄画一部分等于宣称「这就是全部」）。
//
// ── 与同 tab 的 [CentrifugeBandDiagram] 说的话**不重叠** ───────
//
//   · 本图：总数 2ⁿ 里**哪两个**带亲代链（无密度、无 ¹⁵N/¹⁴N）；
//   · 离心管图：同样这 2ⁿ 个**按密度分到哪条带**。
//
// ── 颜色 ─────────────────────────────────────────────────────
//
// ⛔ 一律 `AppColors.*`（20 个 token，**全是 getter**，⛔ 不冻进
//   `static final`）。⛔ 不许 `Color(0x`。⛔ 不用 `AppColors.lethal`。

import 'package:flutter/material.dart';

import '../../engine/dna_engine.dart';
import '../../theme.dart';

// ─────────────────────────── 绘制记录钩（仅供测试注入）───────────

/// `pass` = 一遍重画开始；`moleculeCell` = 一格真的画了（text = '高亮' / '普通'）；
/// `label` / `legend` / `note` / `basis` = 屏上其余字符串。
typedef SemiconservativePaintProbe = void Function(String kind, String? text);

/// ⛔ 仅供 widget 测试注入。**生产代码永不赋值。**
SemiconservativePaintProbe? testSemiconservativePaintProbe;

// ─────────────────────────── 屏上文案（守卫直接引用）────────

/// 图例：格子是什么意思。⛔ 「高亮」只描述**图形**，不解释成因。
const String kSemiconservativeLegend = '一格 = 一个 DNA 分子，高亮格是含亲代链的分子';

/// 位置的诚实说明：软件给了个数，没给位置。
const String kSemiconservativePositionNote =
    '软件只给出含亲代链的分子个数，没有指定它们在格阵里的位置；'
    '图上取靠前的高亮格。';

const List<String> kSemiconservativeVisibleCopy = <String>[
  kSemiconservativeLegend,
  kSemiconservativePositionNote,
];

/// 屏上给高亮格的那个词（守卫用它数格）。
const String kSemiconservativeHighlightTag = '高亮';

// ─────────────────────────── 版面常数 ───────────────────────────

/// 一格边长的**实测**基准字号（等宽 ⇒ 一个数字的推进宽 = 字号）。
/// ⛔ 一格不取比它还细的尺寸：格子比图上最细的字还窄时，
///   学生读到的是一片噪点，不是「一格一个分子」。
const double kSemiconservativeCellFontSize = 9;

/// 相邻两格之间的缝（1 逻辑像素 ⇒ 格与格在屏上仍分开）。
const double kSemiconservativeCellGap = 1;

/// 格阵四周的内边距。
const double kSemiconservativePad = 2;

/// 格阵净高（逻辑像素）。⛔ 由此算出能放几行，⛔ 不是随便定的：
/// 一格的步距 = 边长 + 缝（实测 9.0 + 1.0 = 10.0），180 ÷ 10 = 18 行的空间；
/// 整图（含图例与依据行）约 240px，不到一屏的三分之一。
const double kSemiconservativeGridHeight = 180;

const double kSemiconservativeLabelSize = 11.5;
const double kSemiconservativeBasisSize = 11;

const double _legendGap = 8;
const double _noteGap = 8;
const double _basisGap = 8;
const double _padTop = 2;
const double _padBottom = 8;

/// 设计宽度（逻辑像素）。仅在父级给出**无界宽度**时兜底。
const double kSemiconservativeDesignWidth = 320;

// ─────────────────────────── 版面解算（几何单一真相）──────────

@immutable
class SemiconservativeLayout {
  const SemiconservativeLayout({
    required this.width,
    required this.cellSide,
    required this.cols,
    required this.rows,
    required this.legendHeight,
    required this.noteHeight,
    required this.basisHeight,
  });

  final double width;

  /// 一格的边长（实测值，⛔ 不写死）。
  final double cellSide;

  /// 每行几格 / 一共几行。
  final int cols;
  final int rows;

  final double legendHeight;
  final double noteHeight;
  final double basisHeight;

  double get pitch => cellSide + kSemiconservativeCellGap;

  double get legendTop => _padTop;
  double get gridTop => legendTop + legendHeight + _legendGap;
  double get gridBottom => gridTop + kSemiconservativeGridHeight;
  double get noteTop => gridBottom + _noteGap;
  double get basisTop => noteTop + noteHeight + _basisGap;

  double get designHeight => basisTop + basisHeight + _padBottom;

  /// 本图最多能画几格（= 行 × 列）。
  int get capacity => cols * rows;

  /// 第 `i` 格（0 起，按行优先）的矩形。
  Rect cellRect(int i) => Rect.fromLTWH(
        kSemiconservativePad + (i % cols) * pitch,
        gridTop + kSemiconservativePad + (i ~/ cols) * pitch,
        cellSide,
        cellSide,
      );
}

/// 一格的边长：**实测**。⛔ 与 [CentrifugeBandDiagram.semiconservativeCellSide]
/// 同一把尺（同仓两份实现各自实测，⛔ 不跨文件互相 import）。
double semiconservativeCellSide(Color ink) {
  final tp = TextPainter(
    text: TextSpan(text: '1', style: _cellFontStyle(ink)),
    textDirection: TextDirection.ltr,
  )..layout();
  return tp.width;
}

TextStyle _cellFontStyle(Color c) => TextStyle(
      fontFamily: AppFonts.mono,
      fontFamilyFallback: AppFonts.monoFallback,
      fontSize: kSemiconservativeCellFontSize,
      fontWeight: FontWeight.w600,
      color: c,
    );

TextStyle semiconservativeLabelStyleFor(Color c,
        {double size = kSemiconservativeLabelSize}) =>
    TextStyle(
      fontFamily: AppFonts.sans,
      fontFamilyFallback: AppFonts.sansFallback,
      fontSize: size,
      fontWeight: FontWeight.w600,
      color: c,
    );

TextPainter _tp(String s, TextStyle st, {double? maxWidth}) =>
    TextPainter(
      text: TextSpan(text: s, style: st),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: maxWidth ?? double.infinity);

/// 依据行：**只复述引擎算出了什么**。
/// ⛔ 每一个数都直接取字段；⛔ 不出现「无论」「总是」「恒为」
///   一类把硬编码常量说成一般结论的措辞。
String semiconservativeBasisText(DnaReplicationResult r) =>
    '引擎给出：复制 ${r.copies} 次后共 ${r.dnaMolecules} 个 DNA 分子，'
    '含亲代链的 ${r.withParentStrand} 个，新合成链 ${r.newStrands} 条。';

/// 求解版面。`null` = 当前宽度下连一格都放不下。
SemiconservativeLayout? resolveSemiconservativeLayout({
  required DnaReplicationResult result,
  required double availableWidth,
  required Color ink,
  required Color graphite,
}) {
  final width = availableWidth.isFinite && availableWidth > 0
      ? availableWidth
      : kSemiconservativeDesignWidth;
  final cellSide = semiconservativeCellSide(ink);
  final pitch = cellSide + kSemiconservativeCellGap;
  final innerW = width - 2 * kSemiconservativePad;
  if (innerW < pitch) return null;
  final cols = (innerW / pitch).floor();
  final rows =
      ((kSemiconservativeGridHeight - 2 * kSemiconservativePad) / pitch).floor();
  if (cols < 1 || rows < 1) return null;

  final label = semiconservativeLabelStyleFor(graphite);
  final basis = semiconservativeLabelStyleFor(graphite, size: kSemiconservativeBasisSize);
  return SemiconservativeLayout(
    width: width,
    cellSide: cellSide,
    cols: cols,
    rows: rows,
    legendHeight: _tp(kSemiconservativeLegend, label, maxWidth: width).height,
    noteHeight: _tp(kSemiconservativePositionNote, label, maxWidth: width).height,
    basisHeight: _tp(semiconservativeBasisText(result), basis, maxWidth: width).height,
  );
}

// ─────────────────────────── 组件 ───────────────────────────

class SemiconservativeGrid extends StatelessWidget {
  const SemiconservativeGrid({
    super.key,
    required this.result,
    this.textScale = 1.0,
  });

  /// 引擎算出的半保留复制结果。⛔ 本组件**不重算、不写死**。
  final DnaReplicationResult result;

  /// v2.19.172（R54）：课堂大屏字号倍率（标准模式 1.0 = 逐像素零变化）。
  ///
  /// 【为什么需要它】课堂模式的全局放大只经 `MaterialApp.builder` 注入
  /// `MediaQuery.textScaler`，那只对 **`Text` widget** 生效。本图上的字
  /// （图例 / 位置说明 / 依据行，11~11.5px 那批）全部是 `TextPainter` 自绘，
  /// 而 `TextPainter.textScaler` 默认 `TextScaler.noScaling`
  /// ——**不经过 MediaQuery** ⇒ 课堂大屏下这些字**完全没被放大**，
  /// 而同屏栏标题是 21~24.5px。
  ///
  /// 【怎么用】宿主（`molecular_page.dart` 构造本组件处）在
  /// `PresentModeController.instance.enabled` 时传
  /// `PresentModeController.textScale`，否则传 1.0。
  final double textScale;

  /// ⛔ **数据闸**（与宽度无关）：返回 null = 数据可画。
  ///
  /// 两条判据都直接来自引擎自己的构造（`dna_engine.dart:115-121`）：
  /// `molecules = 1 << copies`、`newStrands = molecules×2 − 2`。
  static String? dataReason(DnaReplicationResult? r) {
    if (r == null) return '还没有算出半保留复制的结果，本图没有数据可画。';
    for (final v in [r.copies, r.dnaMolecules, r.withParentStrand,
        r.newStrands]) {
      if (v < 0) return '引擎给出的计数里出现了负数，本图不画。';
    }
    if (r.copies < 1) return '复制次数至少为 1，本图不画。';
    if (r.dnaMolecules < 1) return '引擎给出的分子数为 0，本图不画。';
    if (r.withParentStrand > r.dnaMolecules) {
      return '含亲代链的分子数超过了分子总数，本图不画。';
    }
    if (r.newStrands != r.dnaMolecules * 2 - 2) {
      return '新合成链数与分子总数对不上，本图不画。';
    }
    return null;
  }

  /// ⛔ **完整闸**：数据 + 当前宽度都放行才画。
  /// 非 null = 不画的那一句，⛔ **调用方要把它印在屏上**。
  static String? skipReason(DnaReplicationResult? r, double availableWidth) {
    final d = dataReason(r);
    if (d != null) return d;
    final l = resolveSemiconservativeLayout(
      result: r!,
      availableWidth: availableWidth,
      ink: AppColors.ink,
      graphite: AppColors.graphite,
    );
    if (l == null) {
      return '当前宽度下格阵放不下一格分子，本图不画；'
          '屏上的文字结果不受影响。';
    }
    if (r.dnaMolecules > l.capacity) {
      return '共 ${r.dnaMolecules} 个分子，本图在当前宽度下每行 '
          '${l.cols} 格、共 ${l.rows} 行，最多画 ${l.capacity} 格，'
          '超出的不画（不是只画一部分）；屏上的文字结果不受影响。';
    }
    return null;
  }

  static bool canDraw(DnaReplicationResult? r, double availableWidth) =>
      skipReason(r, availableWidth) == null;

  /// 屏上语义标签。
  static String semanticsLabel(DnaReplicationResult r) =>
      '半保留复制格阵：共 ${r.dnaMolecules} 个 DNA 分子，'
      '其中 ${r.withParentStrand} 格高亮，是含亲代链的分子。'
      '$kSemiconservativeLegend$kSemiconservativePositionNote'
      '${semiconservativeBasisText(r)}';

  @override
  Widget build(BuildContext context) {
    if (dataReason(result) != null) return const SizedBox.shrink();

    return Semantics(
      label: semanticsLabel(result),
      child: RepaintBoundary(
        child: LayoutBuilder(
          builder: (context, c) {
            final layout = resolveSemiconservativeLayout(
              result: result,
              availableWidth: c.maxWidth,
              ink: AppColors.ink,
              graphite: AppColors.graphite,
            );
            if (layout == null) return const SizedBox.shrink();
            if (result.dnaMolecules > layout.capacity) {
              return const SizedBox.shrink();
            }
            return SizedBox(
              width: double.infinity,
              height: layout.designHeight,
              child: CustomPaint(
                painter: SemiconservativePainter(
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

class SemiconservativePainter extends CustomPainter {
  SemiconservativePainter({
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

  final DnaReplicationResult result;
  final SemiconservativeLayout layout;

  final Color ink;
  final Color graphite;
  final Color steel;
  final Color border;
  final Color teal;
  final Color wash;
  final Color surface;

  /// v2.19.172（R54）：课堂大屏字号倍率。宿主在课堂档传
  /// `PresentModeController.textScale`，标准档传 1.0。详见
  /// [SemiconservativeGrid.textScale] 的完整理由。
  final double textScale;

  /// 把一个 `TextStyle` 的 `fontSize` 乘上课堂倍率。
  ///
  /// `textScale == 1.0` 时 `fs * 1.0 == fs`（IEEE-754 精确），因此标准模式
  /// 逐像素零变化；这也是「组件级基线不该被顶红」的接线级前提。
  /// `fontSize` 为 null 时原样返回。
  TextStyle _scaled(TextStyle style) {
    final fs = style.fontSize;
    if (fs == null) return style;
    return style.copyWith(fontSize: fs * textScale);
  }

  void _emit(String kind, [String? text]) =>
      testSemiconservativePaintProbe?.call(kind, text);

  @override
  void paint(Canvas canvas, Size size) {
    _emit('pass');

    _paintText(canvas, kSemiconservativeLegend, layout.legendTop,
        kSemiconservativeLabelSize, 'legend');
    _paintCells(canvas);
    _paintText(canvas, kSemiconservativePositionNote, layout.noteTop,
        kSemiconservativeLabelSize, 'note');
    _paintText(canvas, semiconservativeBasisText(result), layout.basisTop,
        kSemiconservativeBasisSize, 'basis');
  }

  void _paintCells(Canvas canvas) {
    // ⛔ 格数逐字取自 `dnaMolecules`，高亮格数逐字取自
    //   `withParentStrand`，⛔ 本 painter 不做任何换算。
    for (var i = 0; i < result.dnaMolecules; i++) {
      final r = layout.cellRect(i);
      final on = i < result.withParentStrand;
      _cell(canvas, r, highlight: on);
      _emit('moleculeCell', on ? kSemiconservativeHighlightTag : '普通');
    }
  }

  void _cell(Canvas canvas, Rect r, {required bool highlight}) {
    final rr = RRect.fromRectAndRadius(r, const Radius.circular(1.5));
    canvas.drawRRect(
      rr,
      Paint()..color = highlight ? teal : surface,
    );
    canvas.drawRRect(
      rr,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = highlight ? 1.4 : 1.0
        ..color = highlight ? graphite : steel,
    );
  }

  void _paintText(Canvas canvas, String s, double top, double size,
      String kind) {
    final tp = _tp(
        s,
        _scaled(semiconservativeLabelStyleFor(graphite, size: size)),
        maxWidth: layout.width);
    tp.paint(canvas, Offset(0, top));
    _emit(kind, s);
  }

  @override
  bool shouldRepaint(covariant SemiconservativePainter old) =>
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
