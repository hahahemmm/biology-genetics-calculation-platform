// mutation_diff_diagram.dart —— 基因突变页「原序列 / 突变后序列」密码子对照图
//                                        （代码绘制，非位图）
//
// ## 这张图只回答一件事
//
// > **突变位置落在第几个密码子上，两条序列各自被框起来的那 3 个碱基分别是什么。**
//
// 变异页「基因突变」页签的结果区本来只有几行文字（原序列 / 突变后序列 /
// 受影响密码子 / 结果判定）。学生看到的是两条**纯文字**的碱基串，看不出
// 「密码子框从第 1 个碱基起、每 3 个一个」这件事落在哪一格。这张图是那个模型。
//
// ────────────────────────────────────────────────────────────────────
// ## ⛔ 数据全部来自引擎（本文件不推算任何序列、不重切任何密码子）
//
// 图上每一个碱基都逐字取自 `MutatedSequence.original` / `.mutated`
// （`mutation_engine.dart:9`）。本文件只做四件事：把每条序列按
// **各自行内的下标**每 3 个碱基画一个框、在 `codonIndex` 那一框上加重框、
// 在 `position` 那个碱基下画一枚三角标、读 `originalCodon` / `mutatedCodon`
// 决定图例那一句「这个密码子变没变」。
//
// ⛔ 密码子的切法只有一处：[mutationDiffCodonText]，切法与引擎
//    `mutation_engine.dart:138-143` 逐字同源（从下标 0 起、每 3 个、末端
//    不足 3 个就取到串尾）。本文件**不另切一遍**，也不按 `position` 反推框位。
//
// ────────────────────────────────────────────────────────────────────
// ## ⛔ 四条不许越界的线（引擎给不出的话，屏上一个字都不许有）
//
// ① ⛔ **屏上不许出现任何氨基酸名字**（中文名 / 三字母 / 一字母代码）。
//    理由：**全仓没有密码子到氨基酸的对照表**——`dna_engine.geneExpression()`
//    的 `aminoAcids` 是**学生手输的整数**（`dna_engine.dart:36,126-130`），
//    不是查表推出来的；教材里也只有一句「64 个密码子」的
//    教科书散文。本图能画，是因为引擎已经把「哪一段变了」算出来了；
//    引擎没算的东西，本图一句都不许替它说。
// ② ⛔ **屏上不许说多肽链变没变**。引擎只给了 `silent`（`mutation_engine.dart:153`
//    ：`originalCodon == mutatedCodon`），它没有、也不可能告诉我们多肽链变不变。
//    ⇒ 图例只说「受影响密码子没变 / 受影响密码子变了」，这是**逐字读两个 codon
//    字段**（[mutationDiffCodonUnchanged]），不是因果推断。
// ③ ⛔ **不许画碱基配对双螺旋、不许画染色体**：引擎只给一维字符串。
// ④ ⛔ `AppColors.lethal` 红在本仓是致死 / 错误语义，与本页无关 ⇒ 本图一处都不用。
//
// ────────────────────────────────────────────────────────────────────
// ## ⛔ 插入 / 缺失：两条序列长度不同，本图的对齐口径必须写在屏上
//
// `type` 为「插入」「缺失」时 `original.length != mutated.length`。
// ⛔ **本图绝不按「同下标同 x 坐标」把两条串画成一条对齐线**——那样突变点之后
// 的碱基会整体错位一格，图就在说假话。
//
// 本图采用的口径是：**两条序列各画各的，每条都按自己行内的下标每 3 个碱基一框**
// （口径本身写在图例里，见 [kMutationDiffCodonRule]）。后果是：替换时两行的框
// 恰好逐格重合（长度相同 ⇒ 下标相同 ⇒ 同一框内是同一位置的两个碱基）；
// 插入 / 缺失时两行从突变点起自然分岔（长度差 1 ⇒ 下标差 1），**这个分岔就是事实**。
// 为了不让「分岔」被读成「排版没对齐」，[mutationDiffShiftNote] 会把位移量
// **以数字写在屏上**（序号加 1 / 序号减 1），⛔ 不用方向词。
//
// ────────────────────────────────────────────────────────────────────
// ## 颜色：只用 AppColors 的 getter，⛔ 不许 Color(0x…) 字面量
//
// · 画布 `AppColors.canvas`、框底 `AppColors.surface`、细框 `AppColors.border`、
//   标签 `AppColors.graphite`、碱基 `AppColors.ink`。
// · 受影响密码子那一框：`AppColors.tealWash` 底 + `AppColors.teal` 粗描边 +
//   `AppColors.tealDark` 加粗字 + `AppColors.teal` 三角标。与结果区既有那段
//   富文本高亮（`variation_page.dart:692-694` 用的就是 tealDark / tealWash）
//   同一套视觉语言。
// · ⛔ **颜色取值全部在 `paint()` / `build()` 里现读 getter**：`AppColors.*`
//   全部是 **getter 不是 const 字段**（深浅色 / 高对比会换档）⇒ 任何
//   `static final Color` 都会把颜色**冻在首次访问那一刻**，切主题即失效。
// · 「受影响密码子」不靠颜色单独承载：粗描边 + 加粗字 + 三角标 + 图例点名，
//   四处冗余 ⇒ 投影偏色 / 黑白打印时仍可读。
//
// ## 屏上文案硬规矩
//
// ⛔ 禁 markdown 星号；⛔ 禁方向词（要点名对象，不说「那条」）；全部文案集中在
// 文件顶部的常量与 [mutationDiffShiftNote] 里，测试逐条断。

import 'package:flutter/material.dart';

import '../../engine/mutation_engine.dart';
import '../../theme.dart';

// ────────────────────────────────────────────────────────────────────
// 屏上文案（测试逐条断；⛔ 这里不许出现方向词 / 星号 / 氨基酸名）
// ────────────────────────────────────────────────────────────────────

/// 行标签：原序列。
const String kMutationDiffOriginalLabel = '原序列';

/// 行标签：突变后序列。
const String kMutationDiffMutatedLabel = '突变后序列';

/// 图例：加重描边的那一框是什么。
const String kMutationDiffMarkedLabel = '粗框 = 受影响密码子';

/// 图例：两个 codon 字段逐字相同。
const String kMutationDiffUnchangedLabel = '受影响密码子没变';

/// 图例：两个 codon 字段逐字不同。
const String kMutationDiffChangedLabel = '受影响密码子变了';

/// 图例：**本图采用的对齐口径**（插入 / 缺失时两条串长度不同，必须写明）。
const String kMutationDiffCodonRule = '每 3 个碱基一个框，各序列分别从第 1 个碱基起数';

/// 位移说明。⛔ 位移量由 [MutatedSequence.mutated] 与 [MutatedSequence.original]
/// 的**长度差**算出（插入 ⇒ 正、缺失 ⇒ 负、替换 ⇒ 0），一个字都没写死。
///
/// `delta == 0`（替换）⇒ 返回空串，调用方**不许**渲染空文案（那等于屏上多一行
/// 空白）。类型与长度差对不上 ⇒ 同样返回空串；那种数据根本进不到图里
/// （[mutationDiffIsDrawable] 会拒绝，见文件头④）。
String mutationDiffShiftNote(MutatedSequence r) {
  final delta = r.mutated.length - r.original.length;
  if (delta == 0) return '';
  if (r.type == '插入' && delta > 0) {
    return '插入 $delta 个碱基：突变点之后的碱基在突变后序列里的序号都加 $delta';
  }
  if (r.type == '缺失' && delta < 0) {
    final n = 0 - delta;
    return '缺失 $n 个碱基：突变点之后的碱基在突变后序列里的序号都减 $n';
  }
  return '';
}

// ────────────────────────────────────────────────────────────────────
// 版面常量（设计坐标；⛔ 与 disease_punnett_diagram 各画各的，不共用代码）
// ────────────────────────────────────────────────────────────────────

/// 设计宽度。
///
/// ⚠️ **为什么是 280 而不是 320**（实测，不是估的）：宿主是
/// `ToolWorkbench` 窄屏分支，内容区 `padding: EdgeInsets.fromLTRB(16, 12, 16, 24)`
/// （`tool_workbench.dart:228`）⇒ 360 宽的屏可画区是 `360 - 32 = 328`，
/// **320 宽的屏只有 `320 - 32 = 288`**。取 280 ⇒ 两个最窄目标都留得下余量。
const double kMutationDiffDesignWidth = 280;

/// 可画上限：任一条序列的密码子框数超过它就**不画**（见 [mutationDiffIsDrawable]）。
///
/// ⛔ 这是**可读性阈值**，不是性能阈值：超过 [kMutationDiffMaxCodons] 框时图
/// 高到要滚很久才看得全，那种图比没有图更糟。与 punnett 那张图「格宽塞不下字
/// 就不画」同款纪律（⛔ 不做「画一半」）。
const int kMutationDiffMaxCodons = 24;

const double _sideMargin = 8;

/// 行标签列宽：「突变后序列」5 个汉字 @10px = 50px（⛔ 汉字是全角 1em）。
const double _labelWidth = 50;

const double _labelGap = 5;

/// 单个碱基格宽。等宽 14px + 字距 1.0 的前进宽度约 9.4px，14 留了余量。
const double _baseCellWidth = 14;

/// 密码子框内的横向留白。
const double _boxPadX = 3;

/// 一个密码子框的宽（3 个碱基格 + 两道留白）。
const double _codonBoxWidth = 3 * _baseCellWidth + 2 * _boxPadX;

/// 相邻密码子框的间距。
const double _codonBoxPitch = _codonBoxWidth + 3;

/// 一个密码子框的高。
const double _codonBoxHeight = 20;

/// 三角标占的高。
const double _markerHeight = 6;

/// 行内序号标尺占的高（⛔ 两条序列**各画各的**标尺，见 [MutationDiffLayout]）。
const double _rulerHeight = 12;

/// 同一序列内两行框之间的距离。
const double _rowGap = 6;

/// 两条序列之间的距离。
const double _stripGap = 16;

const double _marginTop = 6;
const double _marginBottom = 6;

/// 一行框的整高（框 + 三角标 + 标尺 + 行距）。
const double _rowPitch = _codonBoxHeight + _markerHeight + _rulerHeight + _rowGap;

/// 密码子框数 —— **由碱基数与「3 个碱基一框」算出**，⛔ 不是写死的个数。
int mutationDiffCodonCount(int baseCount) =>
    baseCount <= 0 ? 0 : (baseCount + 2) ~/ 3;

// ────────────────────────────────────────────────────────────────────
// 判据函数（⛔ painter 与测试共用同一份，这是它们之间唯一有牙齿的接缝）
// ────────────────────────────────────────────────────────────────────

/// 这一框在图上是不是**被加重描边的那一框**。
///
/// ⛔ **painter 只准认这一个函数**（⛔ 不许在 painter 里另写一遍 `index == …`）。
/// 理由：把它改错（例如改成 `index + 1`），测试里「加重描边的那一框落在
/// `codonIndex` 上」这条立刻红。
bool mutationDiffMarksCodon(MutatedSequence r, int index) => index == r.codonIndex;

/// 受影响的密码子**没变**吗。
///
/// ⛔ 逐字读两个 codon 字段（[MutatedSequence.originalCodon] /
/// [MutatedSequence.mutatedCodon]），**不碰多肽链**——引擎没有那张表，
/// 也没有任何能推出多肽链的字段（见文件头①②）。
bool mutationDiffCodonUnchanged(MutatedSequence r) =>
    r.originalCodon == r.mutatedCodon;

/// 突变后序列第 [j] 个碱基**对应**的原序列下标。
///
/// ## 这就是本图采用的对齐口径（⛔ 导出是为了让它有牙齿）
///
/// 两条序列**各按自己的下标编号**，屏上每条序列各画一条序号标尺（画的编号
/// 就是这个下标每 3 个一组的组号）。本图 ⛔ **不**宣称「同一个 x 坐标 = 同一个
/// 位置」：
/// · 替换：恒等（两条串等长，同下标确实对应）；
/// · 插入：突变点之前恒等，**之后整体 -1**（多出来的那一个碱基没有对应项）；
/// · 缺失：突变点之前恒等，**之后整体 +1**（少掉的那一个碱基没有对应项）。
///
/// ⛔ 本函数**不推算任何突变、不产生任何碱基**，只把引擎已经算好的两条串
///    按位对上。测试拿它与「同下标对齐」（恒等）逐项对撞——恒等就是错位。
int mutationDiffCounterpartIndex(MutatedSequence r, int j) {
  if (r.type == '插入') return j <= r.position ? j : j - 1;
  if (r.type == '缺失') return j < r.position ? j : j + 1;
  return j;
}

/// 第 [index] 框里那一行的碱基串 —— **切法与引擎逐字同源**
/// （`mutation_engine.dart:138-143`）：从下标 0 起、每 3 个一框、末端不足
/// 3 个就取到串尾。
///
/// ⛔ 本文件**只有这一处**切密码子；painter 画的每一个碱基都取自它的返回值。
String mutationDiffCodonText(String sequence, int index) {
  final start = index * 3;
  if (start >= sequence.length) return '';
  final rawEnd = start + 3;
  return sequence.substring(start, rawEnd > sequence.length ? sequence.length : rawEnd);
}

/// 这一份 [MutatedSequence] 可以画吗。
///
/// ⛔ 这不是「引擎重复校验」——引擎早就在 `mutateSequence` 里校验过了。本函数
/// 守的是**组件这一侧**：万一有人手工拼一个 `MutatedSequence` 直接塞进来，
/// 或把它从两次不同的运行里混起来，画出来就是一句假话。逐条不成立就不画：
/// ① 两条串非空，且**只含 A/T/G/C**；
/// ② `position` 落在引擎的边界内（插入可等于串长，替换 / 缺失不可）；
/// ③ [MutatedSequence.originalCodon] / [MutatedSequence.mutatedCodon] 确实
///    就是**这两条串**在 `codonIndex` 上的 3 个碱基（字段与串自洽）；
/// ④ `type` 与两条串的**长度差**自洽（替换 ⇒ 0、插入 ⇒ 正、缺失 ⇒ 负）；
/// ⑤ 框数不超过 [kMutationDiffMaxCodons]（可读性，见该常量）。
bool mutationDiffIsDrawable(MutatedSequence r) {
  if (r.original.isEmpty || r.mutated.isEmpty) return false;
  for (final c in r.original.split('')) {
    if (c != 'A' && c != 'T' && c != 'G' && c != 'C') return false;
  }
  for (final c in r.mutated.split('')) {
    if (c != 'A' && c != 'T' && c != 'G' && c != 'C') return false;
  }
  // 引擎的边界（`mutation_engine.dart:113-115`）：插入可等于串长，其余不可。
  if (r.position < 0) return false;
  if (r.position > r.original.length) return false;
  if (r.type != '插入' && r.position >= r.original.length) return false;
  // 字段与串自洽：两个 codon 字段必须就是这两条串在 codonIndex 上的 3 个碱基。
  if (mutationDiffCodonText(r.original, r.codonIndex) != r.originalCodon) {
    return false;
  }
  if (mutationDiffCodonText(r.mutated, r.codonIndex) != r.mutatedCodon) {
    return false;
  }
  // 类型与长度差自洽。
  final delta = r.mutated.length - r.original.length;
  if (r.type == '替换' && delta != 0) return false;
  if (r.type == '插入' && delta <= 0) return false;
  if (r.type == '缺失' && delta >= 0) return false;
  // 可读性上限。
  if (mutationDiffCodonCount(r.original.length) > kMutationDiffMaxCodons) {
    return false;
  }
  if (mutationDiffCodonCount(r.mutated.length) > kMutationDiffMaxCodons) {
    return false;
  }
  return true;
}

// ────────────────────────────────────────────────────────────────────
// 几何 —— ⛔ 唯一的排版真相（painter 与测试共用）
// ────────────────────────────────────────────────────────────────────

/// 两条序列的框位几何。
///
/// ⚠️ 在测试里另抄一遍格宽 / 行高只能证明抄对了（测不出 painter 少画一行）；
/// 让 painter 与断言都读同一个 [MutationDiffLayout] 才是真牙齿。
class MutationDiffLayout {
  const MutationDiffLayout({
    required this.originalCodonCount,
    required this.mutatedCodonCount,
  });

  /// 原序列的框数（由 [MutatedSequence.original] 的长度算出）。
  final int originalCodonCount;

  /// 突变后序列的框数（由 [MutatedSequence.mutated] 的长度算出）。
  final int mutatedCodonCount;

  /// 序列区的可用宽。
  double get stripWidth =>
      kMutationDiffDesignWidth - _sideMargin * 2 - _labelWidth - _labelGap;

  /// 序列区的起始 x。
  double get stripLeft => _sideMargin + _labelWidth + _labelGap;

  /// **一行放得下几个密码子**（= 一行放得下几个碱基 × 3）。
  int get codonsPerRow => stripWidth ~/ _codonBoxPitch;

  /// [boxes] 个框要占几行。
  int rowsFor(int boxes) =>
      boxes <= 0 ? 0 : (boxes + codonsPerRow - 1) ~/ codonsPerRow;

  /// 原序列那一段的起始 y。
  double get originalTop => _marginTop;

  /// 突变后序列那一段的起始 y（跟着原序列的行数走）。
  double get mutatedTop =>
      _marginTop + rowsFor(originalCodonCount) * _rowPitch - _rowGap + _stripGap;

  /// 第 [index] 框的矩形（[index] 从 0 起，**跨行连号**）。
  ///
  /// [strip] 传 0 取原序列的框位、传 1 取突变后序列的框位。
  Rect boxRectAt(int index, int strip) {
    final perRow = codonsPerRow;
    final row = index ~/ perRow;
    final col = index % perRow;
    final top = strip == 0 ? originalTop : mutatedTop;
    return Rect.fromLTWH(
      stripLeft + col * _codonBoxPitch,
      top + row * _rowPitch,
      _codonBoxWidth,
      _codonBoxHeight,
    );
  }

  /// 标尺那一行的顶缘 y（[strip] 0 = 原序列、1 = 突变后序列，[row] 从 0 起）。
  double rulerTop(int strip, int row) {
    final top = strip == 0 ? originalTop : mutatedTop;
    return top + row * _rowPitch + _codonBoxHeight + _markerHeight;
  }

  /// 突变位置三角标的顶点。
  ///
  /// ⛔ `position` 是**该行自己的下标**（原序列用原串下标、突变后序列用突变串
  /// 下标）—— 插入时两条串各自的 `position` 指的是不同的碱基，这正是事实。
  /// [sequenceLength] 是该行自己的串长（用来把「插到串尾」那一种夹住）。
  Offset markerAnchor(int position, int strip, int sequenceLength) {
    final pos = position > sequenceLength ? sequenceLength : position;
    final boxIndex = pos ~/ 3;
    final inBox = pos % 3;
    final box = boxRectAt(boxIndex, strip);
    return Offset(
      box.left + _boxPadX + inBox * _baseCellWidth + _baseCellWidth / 2,
      box.bottom + 1,
    );
  }
}

/// 总高（宿主用它给 `CustomPaint` 一个确定的高度）。
double mutationDiffTotalHeight(MutationDiffLayout layout) {
  final h1 = layout.rowsFor(layout.originalCodonCount) * _rowPitch - _rowGap;
  final h2 = layout.rowsFor(layout.mutatedCodonCount) * _rowPitch - _rowGap;
  return _marginTop + h1 + _stripGap + h2 + _marginBottom;
}

// ────────────────────────────────────────────────────────────────────
// 组件
// ────────────────────────────────────────────────────────────────────

/// 基因突变页的「原序列 / 突变后序列」密码子对照图。
///
/// ## 挂载闸门在**本组件内部**（⛔ 不靠宿主自觉）
///
/// [build] 的第一件事就是判可画性（[mutationDiffIsDrawable]）：不可画 ⇒
/// **整棵子树**是 [SizedBox.shrink]。⛔ **不留标题、不留图例、不留空框、
/// 不留占位**——与 `disease_punnett_diagram.dart:204-215` 的既有纪律同款。
class MutationDiffDiagram extends StatelessWidget {
  const MutationDiffDiagram({
    super.key,
    required this.result,
    this.textScale = 1.0,
  });

  /// 引擎的逐条结果。图上每一个碱基都取自它。
  final MutatedSequence result;

  /// v2.19.172（R54）：课堂大屏字号倍率（标准模式 1.0 = 逐像素零变化）。
  ///
  /// 【为什么需要它】课堂模式的全局放大只经 `MaterialApp.builder` 注入
  /// `MediaQuery.textScaler`，那只对 **`Text` widget** 生效。本图上的行标签
  /// （10px）、格内碱基（`AppText.genotype` 14px）与行内序号尺（9px）是
  /// `TextPainter` 自绘，而 `TextPainter.textScaler` 默认
  /// `TextScaler.noScaling` ——**不经过 MediaQuery** ⇒ 课堂大屏下这些字
  /// **完全没被放大**，而那个 9px 的序号尺是全仓这批图上最难读的一处。
  /// （图表**外面**那几行图例是真正的 `Text` widget，已经吃 1.75×。）
  ///
  /// 【怎么用】宿主（`variation_page.dart` 构造本组件处）在
  /// `PresentModeController.instance.enabled` 时传
  /// `PresentModeController.textScale`，否则传 1.0。
  final double textScale;

  @override
  Widget build(BuildContext context) {
    // ⛔ 闸门在**建任何子 widget 之前**：不可画 ⇒ 屏幕上什么也不多出来。
    if (!mutationDiffIsDrawable(result)) return const SizedBox.shrink();
    final layout = MutationDiffLayout(
      originalCodonCount: mutationDiffCodonCount(result.original.length),
      mutatedCodonCount: mutationDiffCodonCount(result.mutated.length),
    );
    final note = mutationDiffShiftNote(result);
    return Padding(
      // 这点间距由组件**自己**带：不可画时它是零，而不是在宿主里留一道
      // 会把结果区几行文字顶开的空白。
      padding: const EdgeInsets.only(top: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          ClipRect(
            child: CustomPaint(
              size: Size(kMutationDiffDesignWidth,
                  mutationDiffTotalHeight(layout)),
              painter: _MutationDiffPainter(
                  result: result, layout: layout, textScale: textScale),
            ),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 12,
            runSpacing: 2,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(kMutationDiffMarkedLabel, style: AppText.caption),
              Text(
                mutationDiffCodonUnchanged(result)
                    ? kMutationDiffUnchangedLabel
                    : kMutationDiffChangedLabel,
                style: AppText.caption,
              ),
              Text(kMutationDiffCodonRule, style: AppText.caption),
              if (note.isNotEmpty) Text(note, style: AppText.caption),
            ],
          ),
        ],
      ),
    );
  }
}

class _MutationDiffPainter extends CustomPainter {
  _MutationDiffPainter({
    required this.result,
    required this.layout,
    this.textScale = 1.0,
  });

  final MutatedSequence result;
  final MutationDiffLayout layout;

  /// v2.19.172（R54）：课堂大屏字号倍率。宿主在课堂档传
  /// `PresentModeController.textScale`，标准档传 1.0。详见
  /// [MutationDiffDiagram.textScale] 的完整理由。
  final double textScale;

  /// 把一个 `TextStyle` 的 `fontSize` 乘上课堂倍率。
  ///
  /// `textScale == 1.0` 时 `fs * 1.0 == fs`（IEEE-754 精确）⇒ 标准模式逐
  /// 像素零变化。
  TextStyle _scaled(TextStyle style) {
    final fs = style.fontSize;
    if (fs == null) return style;
    return style.copyWith(fontSize: fs * textScale);
  }

  @override
  void paint(Canvas canvas, Size size) {
    // ⛔ 颜色一律**现读 getter**（见文件头「颜色」一节）。
    final canvasColor = AppColors.canvas;
    final surface = AppColors.surface;
    final border = AppColors.border;
    final graphite = AppColors.graphite;
    final ink = AppColors.ink;
    final teal = AppColors.teal;
    final tealDark = AppColors.tealDark;
    final tealWash = AppColors.tealWash;

    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()..color = canvasColor,
    );

    _paintStrip(
      canvas,
      sequence: result.original,
      strip: 0,
      label: kMutationDiffOriginalLabel,
      surface: surface,
      border: border,
      graphite: graphite,
      ink: ink,
      teal: teal,
      tealDark: tealDark,
      tealWash: tealWash,
    );
    _paintStrip(
      canvas,
      sequence: result.mutated,
      strip: 1,
      label: kMutationDiffMutatedLabel,
      surface: surface,
      border: border,
      graphite: graphite,
      ink: ink,
      teal: teal,
      tealDark: tealDark,
      tealWash: tealWash,
    );
  }

  void _paintStrip(
    Canvas canvas, {
    required String sequence,
    required int strip,
    required String label,
    required Color surface,
    required Color border,
    required Color graphite,
    required Color ink,
    required Color teal,
    required Color tealDark,
    required Color tealWash,
  }) {
    // 行标签（⛔ 颜色现读 getter）。
    _paintText(
      canvas,
      label,
      TextStyle(
        fontFamily: AppFonts.sans,
        fontFamilyFallback: AppFonts.sansFallback,
        fontSize: 10,
        color: graphite,
      ),
      Offset(_sideMargin, strip == 0 ? layout.originalTop : layout.mutatedTop),
    );

    final boxes = strip == 0 ? layout.originalCodonCount : layout.mutatedCodonCount;
    for (var i = 0; i < boxes; i++) {
      // ⛔ 框里的碱基逐字取自 [mutationDiffCodonText]（与引擎同源的唯一切法），
      // ⛔ 被加重描边的判断只认 [mutationDiffMarksCodon]。
      final text = mutationDiffCodonText(sequence, i);
      final marked = mutationDiffMarksCodon(result, i);
      final rect = layout.boxRectAt(i, strip);
      final rounded = RRect.fromRectAndRadius(rect, const Radius.circular(4));
      canvas.drawRRect(
        rounded,
        Paint()
          ..style = PaintingStyle.fill
          ..color = marked ? tealWash : surface,
      );
      canvas.drawRRect(
        rounded,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = marked ? 1.8 : 1.0
          ..color = marked ? teal : border,
      );
      // 框内逐个碱基：⛔ 每一个字符都来自引擎给的串，本组件不重排、不补字。
      final baseStyle = marked
          ? AppText.genotype.copyWith(
              color: tealDark, fontWeight: FontWeight.w800)
          : AppText.genotype.copyWith(color: ink);
      for (var k = 0; k < text.length; k++) {
        _paintText(
          canvas,
          text[k],
          baseStyle,
          Offset(rect.left + _boxPadX + k * _baseCellWidth,
              rect.top + (_codonBoxHeight - 14) / 2),
          centerInWidth: _baseCellWidth,
        );
      }

      // 行内序号标尺：⛔ 两条序列**各画各的**，画的组号就是**该行自己**的
      // 密码子序号（从第 1 个碱基起数）。这是本图 ⛔ 不宣称「同一个 x 坐标
      // 就是同一个位置」的可见依据：插入 / 缺失时两条串从突变点起组号对不上，
      // 屏上就写着对不上。
      final rulerY = layout.rulerTop(strip, i ~/ layout.codonsPerRow);
      canvas.drawLine(
        Offset(rect.left, rulerY + 3),
        Offset(rect.right, rulerY + 3),
        Paint()
          ..strokeWidth = 1
          ..color = marked ? teal : border,
      );
      _paintText(
        canvas,
        '${i + 1}',
        TextStyle(
          fontFamily: AppFonts.mono,
          fontFamilyFallback: AppFonts.monoFallback,
          fontSize: 9,
          fontWeight: marked ? FontWeight.w800 : FontWeight.w400,
          color: marked ? tealDark : graphite,
        ),
        Offset(rect.left, rulerY + 5),
        centerInWidth: _codonBoxWidth,
      );
    }

    // 突变位置三角标：⛔ 非颜色冗余线索（投影偏色 / 黑白打印仍可读），
    // 读法由图例点名。⛔ 顶点位置只认 [MutationDiffLayout.markerAnchor]，
    // 与测试读的是同一份几何。
    final anchor = layout.markerAnchor(result.position, strip, sequence.length);
    final tri = Path()
      ..moveTo(anchor.dx, anchor.dy)
      ..lineTo(anchor.dx - 3.5, anchor.dy + _markerHeight - 1)
      ..lineTo(anchor.dx + 3.5, anchor.dy + _markerHeight - 1)
      ..close();
    canvas.drawPath(tri, Paint()..color = teal);
  }

  void _paintText(
    Canvas canvas,
    String text,
    TextStyle style,
    Offset at, {
    double centerInWidth = 0,
  }) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: _scaled(style)),
      textDirection: TextDirection.ltr,
    )..layout();
    final dx =
        centerInWidth > 0 ? at.dx + (centerInWidth - painter.width) / 2 : at.dx;
    painter.paint(canvas, Offset(dx, at.dy));
    painter.dispose();
  }

  @override
  bool shouldRepaint(_MutationDiffPainter old) =>
      old.result.original != result.original ||
      old.result.mutated != result.mutated ||
      old.result.type != result.type ||
      old.result.position != result.position ||
      old.result.codonIndex != result.codonIndex ||
      old.result.originalCodon != result.originalCodon ||
      old.result.mutatedCodon != result.mutatedCodon ||
      // v2.19.172（R54）：课堂倍率必须参与比较——否则课堂上切换课堂模式时
      // 画布复用旧 painter，字号停在标准模式那一档。
      old.textScale != textScale;
}
