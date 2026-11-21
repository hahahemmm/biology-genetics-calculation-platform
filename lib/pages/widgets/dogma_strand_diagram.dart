// dogma_strand_diagram.dart —— 「模板链 → mRNA → 密码子/反密码子」配对图
// （v2.19.163，分子遗传页 tab「基因表达」）
//
// ── 它补的是哪一步 ───────────────────────────────────────────────
//
// 实测（360 宽，模板链 `TACGGATTA`，9 bp）屏上原文只有 4 行纯文字：
//
//     模板链（3′→5′）      TACGGATTA
//     转录（互补，T→U）    mRNA：AUGCCUAAU
//                          编码链：ATGCCTAAT
//     翻译配对            密码子：AUG  CCU  AAU
//                          反密码子：UAC  GGA  UUA
//
// ⛔ **「哪三个字母是一个密码子」这件事，屏上只由两个半角空格承担。**
// 换句话说，把 `join('  ')` 改成 `join(' ')`，屏上几乎看不出区别——
// 空格不是编码。而这恰恰是本页最容易失分的一步。
//
// 本图把这一步画成**框**：一个竖框正好圈住 3 个相邻的 mRNA 碱基。
// ⛔ 全图不出现任何氨基酸：见下一节。
//
// ── ⛔⛔ 为什么只能画到密码子为止（本文件最重要的一条）─────────
//
// **全仓没有密码子 → 氨基酸的对照表。** 已核：
//   · `lib/engine/dna_strand_engine.dart:150-152` 只按 3 位切片，
//     **不查表**（实现逐字：`codons = [for (var i = 0; i < mrna.length; i += 3) …]`）；
//   · 关键词 `密码子表 / 遗传密码 / codonTable / aminoAcid / 翻译表 /
//     多肽 / polypeptide` 在 `lib/` 下**零命中**；
//   · 20 个标准氨基酸中文名 + 三字母代码在 `lib/` 下**零命中**
//     （教材里「苯丙氨酸」只作为囊性纤维化的一句课文叙述出现，
//     **不是查表**）；
//   · 全部可作为氨基酸依据的，只有一句事实：「64 个密码子 / 21 种
//     氨基酸」（教材里只有这一句叙述，没有对照表）。
//
// ⇒ 画一条多肽链、标出每个氨基酸的名字，等于**凭空编课标内容**。
// ⛔ 本图**只画引擎算得出来的东西**：模板链的碱基、mRNA 的碱基、
//   逐位互补的配对线、按 3 个一组的密码子框、按 3 个一组的反密码子框、
//   以及每条链的 3′/5′ 方向。
// ⛔ 不画多肽链、不标氨基酸名、不写「翻译成 X 个氨基酸」。
//
// ── 数据全部取自引擎 ────────────────────────────────────────────
//
// ⛔ 本文件**不自己重新切密码子、不写死任何序列**。模板链 / mRNA /
//   密码子 / 反密码子四个字段全部由 [CentralDogmaResult] 提供
//   （`centralDogmaFromTemplate(...)` 的返回值，调用方传入）。
//
// ── 布局为什么必须换行（实测，不是审美）──────────────────────────
//
// flutter_tester 实测：15pt 下「AUG」宽 **45.0** 逻辑像素（等宽 ⇒
// 每字母 15.0）。360 宽的屏扣掉行首标注槽 44 + 间隙 6 + 右侧留白 2
// ⇒ 可用 **308**：
//   · 3 个密码子（9 bp）一行装得下 ⇒ 单行；
//   · ⛔ 而引擎上限是 **30 bp = 10 个密码子**
//     （`dna_strand_engine.dart:115`）⇒ 10 列 450px 放不下 308。
// ⇒ 本图按**实测可用宽度**算每行几列，装不下就换行；每行列数由
//   `columnsPerRow` 决定，⛔ 不写死。

import 'package:flutter/material.dart';

import '../../engine/dna_strand_engine.dart';
import '../../theme.dart';

// ─────────────────────────── 绘制记录钩（仅供测试注入）───────────

/// 绘制事件种类：**每画出一个实际图形**，painter 就上报一次。
///
/// ⛔ **这是给验收判据 1 用的牙齿**：判据是「框数 == `codons.length`」，
/// 而 `[CentralDogmaResult].codons` 是**数据**。若测试只数数据，那就是
/// 自证（「数据有 3 个，数据的个数当然是 3」），测不出 painter 少画一个。
/// ⇒ 这里上报的是 **painter 真正画过的那一笔**，与屏上像素一一对应。
///   - `templateCell` / `mrnaCell` / `anticodonCell`：一个碱基格
///   - `codonFrame`：⛔ 密码子框（验收判据 1 数的就是它）
///   - `anticodonFrame`：反密码子框
///   - `label`：画在图上的每一个字符串（验收判据 3 扫的就是它）
typedef DogmaPaintProbe = void Function(String kind, String? text);

/// ⛔ 仅供 widget 测试注入。**生产代码永不赋值。**
///
/// 与 `offspring_diagram.dart:86` 的 `testOffspringImageOverride`
/// 同一道口子、同一份纪律。
DogmaPaintProbe? testDogmaPaintProbe;

// ─────────────────────────── 屏上文案（可被守卫直接引用）────────

/// 图例行：解释「一个框」是什么。这句是**定义级**的
/// （3 个相邻碱基 = 1 个密码子），引擎与教材都成立，⛔ 不需要任何查表。
const String kDogmaStrandFrameLabel = '一个框 = 3 个相邻碱基 = 1 个密码子';

/// 配对关系的文字说明：**逐位互补**是引擎做的事
/// （`compRna` / `compRnaRna`），⛔ 不涉及任何查表。
const String kDogmaStrandPairingLabel = '模板链与 mRNA 逐位互补；反密码子与密码子逐位互补';

/// 行首标注：链名 + 方向。方向用**生化惯例的 3′/5′**，
/// 与屏上既有文案「模板链（3′→5′）」同一套口径。
const String kDogmaStrandTemplateLabel = '模板链';
const String kDogmaStrandMrnaLabel = 'mRNA';
const String kDogmaStrandAnticodonLabel = '反密码子';
const String kDogmaStrandTemplateDir = '3′→5′';
const String kDogmaStrandMrnaDir = '5′→3′';
const String kDogmaStrandAnticodonDir = '3′→5′';

/// 本图渲染在屏上的**全部**静态文案。守卫直接遍历它
/// （⛔ 不在测试里重抄一份，避免「守卫自证」）。
const List<String> kDogmaStrandVisibleCopy = <String>[
  kDogmaStrandFrameLabel,
  kDogmaStrandPairingLabel,
  kDogmaStrandTemplateLabel,
  kDogmaStrandMrnaLabel,
  kDogmaStrandAnticodonLabel,
  kDogmaStrandTemplateDir,
  kDogmaStrandMrnaDir,
  kDogmaStrandAnticodonDir,
];

/// ⛔ 本图**不该**在屏上出现的东西（判定「某个密码子编码哪个氨基酸」
///   需要一张全仓没有的表，见文件头）。这份禁用清单**只住在守卫测试里**
///   ——⛔ 本文件一个字都不许持有它，否则「源码不许出现氨基酸字面量」
///   那条守卫会先被自己的清单弄红（守卫自证 = 假绿）。

// ─────────────────────────── 版面常数 ───────────────────────────

/// 碱基字号。⛔ 不得低于此值：投影上「看得出是一个框」比「塞进更多列」重要。
const double kDogmaStrandFontSize = 15;

/// 设计宽度（逻辑像素）。仅在父级给出**无界宽度**时兜底。
const double kDogmaStrandDesignWidth = 320;

/// 行首标注槽宽度（「反密码子」4 个汉字在 11.5pt 下最宽）。
const double kDogmaStrandGutter = 46;

/// 行首标注槽与网格之间的缝。
const double kDogmaStrandGutterGap = 6;

/// 网格右侧留白。
const double kDogmaStrandPadRight = 2;

/// 一格碱基内部的左右留白。
const double _cellPadX = 7;
const double _cellPadY = 6;

/// 同一密码子内 3 格之间的缝（比密码子之间的缝小，读起来才是一「组」）。
const double _cellGapX = 2;

/// 两个密码子列之间的缝。
const double _columnGap = 12;

/// 模板↔mRNA、mRNA↔反密码子两条配对线各自占的高度。
const double _connectorH = 8;

/// 图例行高度 / 图例与网格之间的缝。
const double _legendH = 16;
const double _legendGap = 8;

/// 换行后两行之间的缝。
const double _rowGap = 14;

const double _padTop = 4;
const double _padBottom = 20;

/// 版面解算结果。**painter 与测试读同一份**，不各算一遍
/// （抄一份几何只能证明抄对了，测不出 painter 少画一行）。
@immutable
class DogmaStrandLayout {
  const DogmaStrandLayout({
    required this.codonCount,
    required this.anticodonCount,
    required this.columnsPerRow,
    required this.rowCount,
    required this.cellWidth,
    required this.cellHeight,
    required this.columnPitch,
    required this.rowPitch,
    required this.originX,
    required this.width,
    this.textScale = 1.0,
    this.gutterForTier = kDogmaStrandGutter,
  });

  /// 密码子个数 = `result.codons.length`（⛔ 由引擎给，不自己切）。
  final int codonCount;
  final int anticodonCount;

  /// 每行放几个密码子列（实测可用宽度算出，⛔ 不写死）。
  final int columnsPerRow;
  final int rowCount;

  final double cellWidth;
  final double cellHeight;

  /// 相邻两列左边缘之差。
  final double columnPitch;

  /// 相邻两行**网格**上边缘之差。
  final double rowPitch;

  /// 网格左边缘（紧贴行首标注槽之后，⛔ 不居中：
  /// 各行内部左对齐才保住「3′→5′」那个从左到右的读法）。
  final double originX;

  final double width;

  /// v2.19.172（R58）：课堂大屏字号倍率（标准档 1.0）。
  ///
  /// 【为什么版面解算要带它】本类在 v2.19.172 之前是**纯静态**的：行首标注槽
  /// 是常数 46、格高是常数 27，而 painter 画出去的字已经乘了课堂倍率 ⇒
  /// 课堂档下「反密码子」四个字 80.5 宽挤进 46 的槽（1.75× 溢出）、
  /// 格里的碱基字母 31 高挤进 27 的格（1.15× 溢出）。
  ///
  /// ⛔ **只乘「装字的那几处」**：行首标注槽、碱基格、图例行高、底部留白。
  ///    `_cellPadX/_cellPadY/_columnGap/_rowGap/_connectorH/_padTop/
  ///    _gutterGap` 是设计稿写死的缝与内边距，与字号无关，⛔ 不动。
  /// `textScale == 1.0` 时全部乘数都是 1.0（IEEE-754 精确）⇒ 标准档逐像素不变。
  final double textScale;

  /// 行首标注槽宽度（**本档实际分配到的那一档**）。
  ///
  /// ⚠️ 与 [gutter] 的区别：[gutter] 是**设计稿常数** 46（标准档的值，
  ///    既有守卫按它断言）；本字段是它按课堂倍率放大后的**分配值**。
  final double gutterForTier;

  static const double gutter = kDogmaStrandGutter;
  static const double gutterGap = kDogmaStrandGutterGap;
  static const double padRight = kDogmaStrandPadRight;

  /// 网格可用宽度（扣掉行首标注槽 + 间隙 + 右侧留白）。
  double get gridWidth => width - gutterForTier - gutterGap - padRight;

  /// 一格碱基的高度（随课堂倍率放大，见 [textScale]）。
  double get cellH => (kDogmaStrandFontSize + 2 * _cellPadY) * textScale;

  /// 图例那一行的高度（随课堂倍率放大，见 [textScale]）。
  double get legendH => _legendH * textScale;

  /// 网格底下的留白（随课堂倍率放大，见 [textScale]）。
  ///
  /// ⚠️ 底部那行说明的字也乘了倍率 ⇒ 留白不放大，它就会压到最后一格上。
  double get padBottom => _padBottom * textScale;

  /// 求解版面。⛔ `letterWidth` 必须**实测**（`TextPainter` 量），
  /// 不许拿常数冒充——那会让换行点在真机上算错。
  ///
  /// [textScale] 是课堂大屏字号倍率：⛔ **不改格子的字号**，只把**分配给格子
  /// 与行首标注槽的空间**按同一个倍率放大 ⇒ 课堂档下字与格子同步变大，
  /// 标准档（1.0）每一个乘数都是 1.0 ⇒ 逐像素零变化。
  factory DogmaStrandLayout.resolve({
    required int codonCount,
    required int anticodonCount,
    required double letterWidth,
    required double availableWidth,
    double textScale = 1.0,
  }) {
    final cellW = letterWidth * textScale + 2 * _cellPadX;
    final cellH = (kDogmaStrandFontSize + 2 * _cellPadY) * textScale;
    final columnW = 3 * cellW + 2 * _cellGapX;
    final gutterW = _gutterFor(textScale);
    final grid = availableWidth - gutterW - gutterGap - padRight;
    final perRow = grid <= 0
        ? 1
        : ((grid + _columnGap) / (columnW + _columnGap))
            .floor()
            .clamp(1, codonCount < 1 ? 1 : codonCount);
    final rows = codonCount <= 0 ? 0 : (codonCount / perRow).ceil();
    return DogmaStrandLayout(
      codonCount: codonCount,
      anticodonCount: anticodonCount,
      columnsPerRow: perRow,
      rowCount: rows,
      cellWidth: cellW,
      cellHeight: cellH,
      columnPitch: columnW + _columnGap,
      rowPitch: 3 * cellH + 2 * _connectorH + _rowGap,
      originX: gutterW + gutterGap,
      width: availableWidth,
      textScale: textScale,
      gutterForTier: gutterW,
    );
  }

  /// 行首标注槽在课堂档该分到多宽。
  ///
  /// ⚠️ **标准档（`textScale <= 1.0`）直接返回设计稿常数 46，一个字都不量**
  /// —— 那不是省事，是**保证**：本函数要在没装 golden 字体的测试环境里也被
  /// 调用，而那里量到的是 flutter_tester 的方框字体宽度（与真机字宽无关）
  /// ⇒ 一旦拿实测值当分配值，标准档的几何就会随「装没装字体」漂移，
  /// 既有基线随之假红。课堂档才按实测值分配（那时字也确实按实测值画）。
  static double _gutterFor(double textScale) {
    if (textScale <= 1.0) return kDogmaStrandGutter;
    // ⚠️ 只量**真的会被画进这个槽里**的六个串（三条链名 + 三个方向）。
    var need = 0.0;
    for (final (s, size) in <(String, double)>[
      (kDogmaStrandTemplateLabel, 11.5),
      (kDogmaStrandMrnaLabel, 11.5),
      (kDogmaStrandAnticodonLabel, 11.5),
      (kDogmaStrandTemplateDir, 9.5),
      (kDogmaStrandMrnaDir, 9.5),
      (kDogmaStrandAnticodonDir, 9.5),
    ]) {
      final style = DogmaStrandDiagram.labelStyleFor(
        AppColors.graphite,
        size: size * textScale,
      );
      final tp = TextPainter(
        text: TextSpan(text: s, style: style),
        textDirection: TextDirection.ltr,
      )..layout();
      if (tp.width > need) need = tp.width;
      tp.dispose();
    }
    // ⚠️ **为什么还要加半个行首缝**：设计稿那个 46 恰好**等于**「反密码子」
    // 在 11.5pt 下的实测字宽（零余量）⇒ 照搬 `46 × 倍率` 之后余量仍然是 0，
    // 而投影上字形的抗锯齿边缘会糊到网格左缘上。课堂档因此额外留半个
    // [kDogmaStrandGutterGap]（3px）。⛔ 标准档走上面那条短路，这个余量
    // 一次都不会被加上 ⇒ 标准档逐像素不变。
    return need + kDogmaStrandGutterGap * 0.5;
  }

  /// 第 `row` 行**网格**的上边缘。
  double gridTop(int row) => _padTop + legendH + _legendGap + row * rowPitch;

  /// 第 `row` 行第 `band` 条链（0=模板链 / 1=mRNA / 2=反密码子）上边缘。
  double bandTop(int row, int band) =>
      gridTop(row) + band * (cellHeight + _connectorH);

  /// 某密码子列的左边缘。
  double columnX(int codonIndex) =>
      originX + (codonIndex % columnsPerRow) * columnPitch;

  /// 某密码子列所在行。
  int rowOf(int codonIndex) => codonIndex ~/ columnsPerRow;

  /// 模板链第 `baseIndex` 个碱基格（`codonIndex` 是第几个密码子）。
  Rect templateCell(int codonIndex, int baseIndex) => Rect.fromLTWH(
      columnX(codonIndex) + baseIndex * (cellWidth + _cellGapX),
      bandTop(rowOf(codonIndex), 0),
      cellWidth,
      cellHeight);

  /// mRNA 第 `baseIndex` 个碱基格。
  Rect mrnaCell(int codonIndex, int baseIndex) => Rect.fromLTWH(
      columnX(codonIndex) + baseIndex * (cellWidth + _cellGapX),
      bandTop(rowOf(codonIndex), 1),
      cellWidth,
      cellHeight);

  /// 反密码子第 `baseIndex` 个碱基格。
  Rect anticodonCell(int codonIndex, int baseIndex) => Rect.fromLTWH(
      columnX(codonIndex) + baseIndex * (cellWidth + _cellGapX),
      bandTop(rowOf(codonIndex), 2),
      cellWidth,
      cellHeight);

  /// ⛔ **密码子框**：正好圈住 3 个相邻的 mRNA 碱基格。
  ///
  /// 这就是本图要教的那一步——「一个框 = 3 个碱基 = 1 个密码子」。
  /// 框圈的是 **mRNA** 上的三个格（密码子定义在 mRNA 上），
  /// ⛔ 不是模板链。
  Rect codonFrame(int codonIndex) => _wrap3(mrnaCell(codonIndex, 0),
      mrnaCell(codonIndex, 2));

  /// 反密码子框：同样圈住 3 个相邻的反密码子碱基格。
  Rect anticodonFrame(int codonIndex) => _wrap3(anticodonCell(codonIndex, 0),
      anticodonCell(codonIndex, 2));

  /// 模板链的「同一条分界线」参考框（中性描边，⛔ 不与密码子框抢眼）。
  ///
  /// ✅ 之所以能画：引擎的 `mrna[i]` 与 `template[i]` 逐位互补
  ///   （`compRna`，`dna_strand_engine.dart:149`），而 `codons` 是
  ///   从 mRNA 下标 0 起按 3 切的 ⇒ 第 k 个模板三联体**恒等于**
  ///   第 k 个密码子的补集，框线必然对齐。这是引擎构造保证的，
  ///   ⛔ 不需要任何查表。
  Rect templateGroupFrame(int codonIndex) => _wrap3(
      templateCell(codonIndex, 0), templateCell(codonIndex, 2));

  Rect _wrap3(Rect first, Rect last) => Rect.fromLTRB(
      first.left - _cellPadX * 0.4,
      first.top - _cellPadY * 0.4,
      last.right + _cellPadX * 0.4,
      last.bottom + _cellPadY * 0.4);

  /// 图例那一行的基线。
  double get legendBaselineY => _padTop + legendH * 0.72;

  /// 图例右侧那个「示意小框」的左上角。
  Offset get legendSwatchOrigin =>
      Offset(originX, gridTop(0) - _legendGap - legendH * 0.5);

  /// 整图高度。
  double get designHeight =>
      _padTop +
      legendH +
      _legendGap +
      (rowCount <= 0 ? 0 : rowCount * rowPitch - _rowGap) +
      padBottom;
}

// ─────────────────────────── 组件 ───────────────────────────

/// 「模板链 → mRNA → 密码子/反密码子」配对图。
///
/// ## ⛔ 不可画时**什么都不留**
///
/// 数据自相矛盾（没有密码子、密码子数与反密码子数对不上、碱基数对不上、
/// 有密码子不是 3 个字母）⇒ 整个组件收缩成 `SizedBox.shrink()`：
/// **不留空框、不留标题、不留占位**。与 `offspring_diagram.dart:25-27`
/// 同一道闸——
///
///   > 匹配不到就不画
///   > —— `_assetFor` 返回 null 时整个组件收缩成 `SizedBox.shrink()`：
///   > **不留空框、不留标题、不留占位**。
///
/// 屏上留一个空框等于宣称「这里本该有图」，而学生看不出为什么没有。
class DogmaStrandDiagram extends StatelessWidget {
  const DogmaStrandDiagram({
    super.key,
    required this.result,
    this.textScale = 1.0,
  });

  /// 引擎算出的中心法则互推结果。⛔ 本组件**不重算、不写死**。
  final CentralDogmaResult result;

  /// v2.19.172（R54）：课堂大屏字号倍率（标准模式 1.0 = 逐像素零变化）。
  ///
  /// 【为什么需要它】课堂模式的全局放大只经 `MaterialApp.builder` 注入
  /// `MediaQuery.textScaler`，那只对 **`Text` widget** 生效。本图上的碱基字母
  /// （15px）、链名（11.5px）、链方向 `3′→5′`（9.5px）与图例（11px）全部是
  /// `TextPainter` 自绘，而 `TextPainter.textScaler` 默认
  /// `TextScaler.noScaling` ——**不经过 MediaQuery** ⇒ 课堂大屏下这些字
  /// **完全没被放大**。那个 9.5px 的方向标注是全仓这批图上最难读的一处。
  ///
  /// v2.19.172（R58）：本倍率**同时**进 painter（字号）与
  /// [DogmaStrandLayout.resolve]（版面分配），两侧用同一个乘数。
  /// 【怎么用】宿主（`molecular_page.dart` 构造本组件处）在
  /// `PresentModeController.instance.enabled` 时传
  /// `PresentModeController.textScale`，否则传 1.0。
  ///
  /// ⚠️ v2.19.172（R54）只把它接到了 painter 上，版面解算仍是纯静态 ⇒
  /// 课堂档「反密码子」四个字 80.5 宽挤进 46 的行首标注槽（1.75× 溢出）。
  /// R58 起 [DogmaStrandLayout.textScale] 补上这一半。
  final double textScale;

  /// ⛔ 自检：这份数据画得出来吗？
  ///
  /// 三条「对得上」都是从**引擎自己的切法**推出来的，不是本组件另立规矩：
  ///   · `codons` 每 3 位一个（`dna_strand_engine.dart:150-152`）
  ///     ⇒ 密码子数 == mRNA 碱基数 / 3；
  ///   · `anticodons` 是 `codons` 逐位映射的结果（同文件 `:158`）
  ///     ⇒ 个数必然相同，对不上就是数据被换掉了；
  ///   · 每个密码子、反密码子都恰好 3 个字母（切片的定义）。
  static bool canDraw(CentralDogmaResult? r) {
    if (r == null) return false;
    if (r.codons.isEmpty || r.anticodons.isEmpty) return false;
    if (r.codons.length != r.anticodons.length) return false;
    if (r.codons.length * 3 != r.mrna.length) return false;
    if (r.mrna.length != r.template.length) return false;
    for (final c in [...r.codons, ...r.anticodons]) {
      if (c.length != 3) return false;
    }
    return true;
  }

  /// 屏上语义标签（跟着数据走，⛔ 同样不许出现查表才有的说法）。
  static String semanticsLabel(CentralDogmaResult r) {
    final b = StringBuffer('配对图：');
    b.write('${kDogmaStrandTemplateLabel} ${r.template}（3 端到 5 端）；');
    b.write('${kDogmaStrandMrnaLabel} ${r.mrna}（5 端到 3 端），'
        '按每 3 个碱基切一组，共 ${r.codons.length} 组：');
    b.write('${r.codons.join('、')}；');
    b.write('${kDogmaStrandAnticodonLabel}：${r.anticodons.join('、')}。');
    b.write(kDogmaStrandPairingLabel);
    return b.toString();
  }

  @override
  Widget build(BuildContext context) {
    if (!canDraw(result)) return const SizedBox.shrink();

    // ⛔ AppColors 的 20 个 token **全是 getter**（亮度随档位实时派生）。
    //   在这里取值再传给 painter，⛔ 不让 painter 自己去读、⛔ 也不冻进
    //   static final（冻了就停在首次访问那一刻，切深色时不跟）。
    return Semantics(
      label: semanticsLabel(result),
      child: RepaintBoundary(
        child: LayoutBuilder(
          builder: (context, c) {
            final width = c.maxWidth.isFinite && c.maxWidth > 0
                ? c.maxWidth
                : kDogmaStrandDesignWidth;
            final layout = DogmaStrandLayout.resolve(
              codonCount: result.codons.length,
              anticodonCount: result.anticodons.length,
              letterWidth: measureLetterWidth(result),
              availableWidth: width,
              // v2.19.172（R58）：课堂倍率必须进版面解算 —— 否则行首标注槽
              // 与碱基格仍按 15px 那一档算，字放大后顶出槽外 / 格外。
              textScale: textScale,
            );
            return SizedBox(
              width: double.infinity,
              height: layout.designHeight,
              child: CustomPaint(
                painter: DogmaStrandPainter(
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

  /// ⛔ **实测**格内会出现的那个最宽字母的宽度。
  ///
  /// 为什么不拿常数：换行点 = f(字宽, 可用宽度)。拿常数冒充 ⇒ 真机上
  /// 换行位置算错，10 个密码子会挤成一行或留一大片空。
  /// 只量**真的会印进格子里**的那些字母（⛔ 不拿永不出现的宽字母凑数）。
  static double measureLetterWidth(CentralDogmaResult r) {
    final style = letterStyleFor(AppColors.ink);
    var w = 0.0;
    final seen = <String>{};
    for (final src in [r.template, r.mrna, ...r.anticodons]) {
      for (final ch in src.split('')) {
        if (!seen.add(ch)) continue;
        final tp = TextPainter(
          text: TextSpan(text: ch, style: style),
          textDirection: TextDirection.ltr,
        )..layout();
        if (tp.width > w) w = tp.width;
      }
    }
    return w == 0 ? kDogmaStrandFontSize * 0.6 : w;
  }

  /// 碱基字母的样式。⛔ **必须显式声明 fontFamily**：
  /// `CustomPainter` 里的 `TextPainter` 没有 `BuildContext`、拿不到
  /// `DefaultTextStyle`，不声明就会落回 flutter_tester 的方框字体，
  /// 而布局按方框宽度算 ⇒ 基线对文本零敏感（假绿）。
  /// 详见 `sex_linked_punnett_diagram.dart:1048-1064` 记录的第 4 次同源坑。
  static TextStyle letterStyleFor(Color c) => TextStyle(
        fontFamily: AppFonts.mono,
        fontFamilyFallback: AppFonts.monoFallback,
        fontSize: kDogmaStrandFontSize,
        fontWeight: FontWeight.w600,
        color: c,
      );

  /// 中文标签的样式：⛔ 不挂 mono（`monoFallback` 一支汉字都没有，
  /// 详见 `sex_linked_punnett_diagram.dart:1072-1082`）。
  static TextStyle labelStyleFor(Color c, {double size = 11.5}) => TextStyle(
        fontFamily: AppFonts.sans,
        fontFamilyFallback: AppFonts.sansFallback,
        fontSize: size,
        fontWeight: FontWeight.w600,
        color: c,
      );
}

// ─────────────────────────── painter ───────────────────────────

/// 真正落笔的那一层。⛔ 颜色**全部由构造器传入**
/// （来自 `AppColors.*` getter），本类不读任何全局亮度状态。
class DogmaStrandPainter extends CustomPainter {
  DogmaStrandPainter({
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

  final CentralDogmaResult result;
  final DogmaStrandLayout layout;

  final Color ink;
  final Color graphite;
  final Color steel;
  final Color border;
  final Color teal;
  final Color wash;
  final Color surface;

  /// v2.19.172（R54）：课堂大屏字号倍率。宿主在课堂档传
  /// `PresentModeController.textScale`，标准档传 1.0。详见
  /// [DogmaStrandDiagram.textScale] 的完整理由。
  final double textScale;

  /// 把一个 `TextStyle` 的 `fontSize` 乘上课堂倍率。
  ///
  /// `textScale == 1.0` 时 `fs * 1.0 == fs`（IEEE-754 精确）⇒ 标准模式逐
  /// 像素零变化。
  ///
  /// ✅ 本 painter 的**全部**画字都经 [_text]（格内字母 / 链名 / 方向 /
  /// 图例 / 底部说明），而 [_text] 是唯一建 `TextPainter` 的地方 ⇒ 乘一次
  /// 即全覆盖，⛔ 不必在 `paint()` 里逐个样式套。
  TextStyle _scaled(TextStyle style) {
    final fs = style.fontSize;
    if (fs == null) return style;
    return style.copyWith(fontSize: fs * textScale);
  }

  void _emit(String kind, [String? text]) =>
      testDogmaPaintProbe?.call(kind, text);

  @override
  void paint(Canvas canvas, Size size) {
    // ⛔ 开画前先报一个 `pass` 闸：页面一次交互可能触发**多次重画**
    //    （setState / 主题档位切换 / 滚动），守卫要数的是「**屏上此刻**
    //    那一遍」画了几个框，⛔ 不是把历次重画累加起来。
    //    （实测：页面上点一次「推出各链」会 paint 2 遍，累加 = 6 个框。）
    _emit('pass');
    final letter = DogmaStrandDiagram.letterStyleFor(ink);
    final nameStyle = DogmaStrandDiagram.labelStyleFor(graphite);
    final dirStyle = DogmaStrandDiagram.labelStyleFor(steel, size: 9.5);
    final legendStyle = DogmaStrandDiagram.labelStyleFor(graphite, size: 11);

    _paintLegend(canvas, letter, legendStyle);
    _paintBottomNote(canvas, legendStyle);
    _paintGutterLabels(canvas, nameStyle, dirStyle);

    for (var i = 0; i < layout.codonCount; i++) {
      _paintColumn(canvas, i, letter);
    }
  }

  /// 图例：文字 + 右侧一个 3 格小框，让「框」这件事有实物对照。
  void _paintLegend(Canvas canvas, TextStyle letter, TextStyle legend) {
    _text(canvas, kDogmaStrandFrameLabel, Offset(0, layout.legendBaselineY),
        legend);
    // 小框示意：3 格 + 1 个框，与真正的密码子框**同一套画法**。
    final cell = 9.0;
    final gap = 1.5;
    final o = layout.legendSwatchOrigin;
    final w = 3 * cell + 2 * gap;
    for (var b = 0; b < 3; b++) {
      final r = Rect.fromLTWH(o.dx + b * (cell + gap), o.dy, cell, cell);
      canvas.drawRRect(
        RRect.fromRectAndRadius(r, const Radius.circular(1.5)),
        Paint()..color = wash,
      );
    }
    canvas.drawRRect(
      RRect.fromRectAndRadius(
          Rect.fromLTWH(o.dx - 1.5, o.dy - 1.5, w + 3, cell + 3),
          const Radius.circular(3)),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4
        ..color = teal,
    );
  }

  void _paintBottomNote(Canvas canvas, TextStyle legend) {
    _text(canvas, kDogmaStrandPairingLabel,
        Offset(0, layout.designHeight - 6), legend);
  }

  /// 行首标注：每条链的**名字 + 方向**。
  ///
  /// ⛔ 名字与方向**逐行**都画（不只第一行），因为密码子一多就会换行，
  /// 换行后的行首若不标，学生只能靠数格子猜哪条是哪条。
  /// ⛔ 名字走**行首槽**，⛔ 不用「上面/下面」这类方向词
  /// （读屏软件把方向词读出来等于没有）。
  void _paintGutterLabels(Canvas canvas, TextStyle name, TextStyle dir) {
    const names = [
      kDogmaStrandTemplateLabel,
      kDogmaStrandMrnaLabel,
      kDogmaStrandAnticodonLabel,
    ];
    const dirs = [
      kDogmaStrandTemplateDir,
      kDogmaStrandMrnaDir,
      kDogmaStrandAnticodonDir,
    ];
    for (var r = 0; r < layout.rowCount; r++) {
      for (var band = 0; band < 3; band++) {
        final cell = layout.cellHeight;
        final top = layout.bandTop(r, band);
        _text(canvas, names[band], Offset(1, top + cell * 0.40), name);
        _text(canvas, dirs[band], Offset(1, top + cell * 0.90), dir);
      }
    }
  }

  void _paintColumn(Canvas canvas, int i, TextStyle letter) {
    // 模板链 3 格。
    for (var b = 0; b < 3; b++) {
      final s = result.template[i * 3 + b];
      _cell(canvas, layout.templateCell(i, b), s, letter,
          fill: surface, stroke: border);
      _emit('templateCell', s);
    }
    // 模板链分界参考框（中性描边，⛔ 不与密码子框抢眼）。
    _frame(canvas, layout.templateGroupFrame(i), border, width: 1.0);

    // 模板↔mRNA 配对线（逐位）。
    for (var b = 0; b < 3; b++) {
      final t = layout.templateCell(i, b);
      final m = layout.mrnaCell(i, b);
      _connector(canvas, Offset(t.center.dx, t.bottom),
          Offset(m.center.dx, m.top));
    }

    // mRNA 3 格 ⛔ 密码子定义在这一行上。
    for (var b = 0; b < 3; b++) {
      final s = result.mrna[i * 3 + b];
      _cell(canvas, layout.mrnaCell(i, b), s, letter, fill: wash, stroke: teal);
      _emit('mrnaCell', s);
    }

    // ⛔ 密码子框：验收判据 1 数的就是它。
    _frame(canvas, layout.codonFrame(i), teal, width: 2.0);
    _emit('codonFrame', result.codons[i]);

    // mRNA↔反密码子 配对线（逐位）。
    for (var b = 0; b < 3; b++) {
      final m = layout.mrnaCell(i, b);
      final a = layout.anticodonCell(i, b);
      _connector(canvas, Offset(m.center.dx, m.bottom),
          Offset(a.center.dx, a.top));
    }

    // 反密码子 3 格 + 它自己的框。
    for (var b = 0; b < 3; b++) {
      final s = result.anticodons[i][b];
      _cell(canvas, layout.anticodonCell(i, b), s, letter,
          fill: surface, stroke: steel);
      _emit('anticodonCell', s);
    }
    _frame(canvas, layout.anticodonFrame(i), steel, width: 1.6);
    _emit('anticodonFrame', result.anticodons[i]);
  }

  void _cell(Canvas canvas, Rect r, String s, TextStyle style,
      {required Color fill, required Color stroke}) {
    final rr = RRect.fromRectAndRadius(r, const Radius.circular(3));
    canvas.drawRRect(rr, Paint()..color = fill);
    canvas.drawRRect(
      rr,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0
        ..color = stroke,
    );
    // ⚠️ v2.19.172（R58）：那个 `+5` 是**按 15px 字号调出来的基线偏移**，
    // 字号乘课堂倍率后必须同步放大，否则 26.25px 的字母会从格子上缘顶出去。
    _text(canvas, s, Offset(r.center.dx, r.center.dy + 5 * textScale), style,
        centered: true);
  }

  void _frame(Canvas canvas, Rect r, Color c, {required double width}) {
    canvas.drawRRect(
      RRect.fromRectAndRadius(r, const Radius.circular(5)),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = width
        ..color = c,
    );
  }

  void _connector(Canvas canvas, Offset from, Offset to) {
    canvas.drawLine(
      from,
      to,
      Paint()
        ..strokeWidth = 1.2
        ..color = steel,
    );
  }

  void _text(Canvas canvas, String s, Offset at, TextStyle style,
      {bool centered = false}) {
    final tp = TextPainter(
      text: TextSpan(text: s, style: _scaled(style)),
      textDirection: TextDirection.ltr,
    )..layout();
    final dx = centered ? at.dx - tp.width / 2 : at.dx;
    tp.paint(canvas, Offset(dx, at.dy - tp.height));
    _emit('label', s);
  }

  @override
  bool shouldRepaint(covariant DogmaStrandPainter old) =>
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
