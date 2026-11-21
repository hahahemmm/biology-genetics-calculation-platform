// tetraploid_gamete_diagram.dart —— 同源四倍体配子示意图（**代码绘制**，非位图）
//
// ## 这张图只回答一件事
//
// > **输入的那 4 个字母，被软件枚举成了哪几种配子、每种占几份。**
//
// 倍性页「育种应用」页签的「同源四倍体配子比例」分区（`ploidy_page.dart`
// 「同源四倍体配子比例 · 结果」）此前把「4 条同源染色体随机 2 条进配子」
// 排成**纯文字**：一个 `RatioPill` 印一行 `AA : Aa : aa = 1 : 4 : 1`。
// 那行字是对的，但**指不出 `4` 是怎么来的**——学生看到 1:4:1 时，
// 屏上没有一样东西能指着说「就是这一份」。这张图就是那个模型。
//
// ────────────────────────────────────────────────────────────────────
// ## ⛔ 数据全部来自引擎（本文件**不推算任何组合、不重算任何份数**）
//
// 图上每一个字母、每一个份数都直接取自 `tetraploidGametes(...)` 返回的
// [TetraploidGametes]（`ploidy_engine.dart:213`）：
//   · 4 根棒上的字母 ← `result.genotype` 里的 4 个字母（**按出现顺序**）；
//   · 每个框里的基因型 ← `result.counts` 的 **key**（逐字，一个字都不改）；
//   · 每个框里的份数 ← `result.counts` 的 **value**。
//
// ⛔ **本文件不重枚举那 C(4,2)=6 种组合**：引擎的出口是「配子字符串 →
//    几份」的 Map，**没有**暴露「哪两条配成了一种」这个映射。凭空补上
//    连线，就等于宣称引擎算过逐对配对——它没算。
//
// ⛔ **不许写死 `1:4:1` / `1:1` / 6**：引擎实测的 `AAAa` 是
//    `{AA: 3, Aa: 3}`、`Aaaa` 是 `{Aa: 3, aa: 3}`（各 6 份里的 3 份），
//    **与引擎注释里写的 `1:1` 字面不同**（比值相同、未约分）。本图照抄
//    引擎的 `3`，不约、不改、不替引擎"修正"成 1。屏上比例仍由宿主那枚
//    `RatioPill` 负责，图是它的解释，不是它的副本。
//
// ────────────────────────────────────────────────────────────────────
// ## ⛔ 三条不许越界的线
//
// ① ⛔ **不许标基因名、不许画染色体形态**（着丝粒 / 大小 / 形状）。
//    引擎**没有**「基因 ↔ 染色体」的映射（`setsByMorphology` 只给 4 个
//    int）⇒ 画出来就是编造。4 根棒只是**那 4 个字母本身**。
// ② ⛔ **不许画育性图标、不许画果实**。引擎的 `fertile` 是
//    **组数奇偶启发式**（`ploidy_engine.dart:118` 的 `sets % 2 == 0`），
//    把教材近似印成事实是本项目明令禁止的。
// ③ ⛔ **不许画「哪两根配成哪一种」的连线**。见上一节：引擎没给这个映射。
//
// ## 颜色：只用 AppColors 的 getter，⛔ 不许颜色字面量
//
// · 画布不用（宿主给）、格底 `AppColors.surface`、结构线 `AppColors.border`、
//   次要文字 `AppColors.graphite`、字母 `AppColors.ink`。
// · 4 根棒 `AppColors.teal`；配子框 `AppColors.sand`（与宿主那枚
//   `RatioPill` 同色系，图与屏上比例读起来是一家人）。
// · ⛔ `AppColors.lethal` 红 = **致死**语义，与本页无关，**一个字都不许出现**。
// · ⛔ **颜色取值全部在 `paint()` / `build()` 里现读 getter**。`AppColors.*`
//   全部是 **getter 不是 const 字段**（深浅色 / 高对比会换档）⇒ 任何
//   `static final Color` 都会把颜色**冻在首次访问那一刻**，切主题即失效。
//
// ## 比例不靠颜色单独承载
//
// 份数同时有**两处**非颜色冗余线索：数字本身（等宽字体、加大），
// 以及框的描边。投影偏色 / 打印黑白时仍然可读。
//
// ## 屏上文案三条硬规矩
//
// ⛔ 禁 markdown 星号；⛔ 禁方向词（点名对象，不说「靠边的那根」）；
// ⛔ 禁任何比例字面量。全部文案集中在末段的常量里，测试逐条断。

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../engine/ploidy_engine.dart';
import '../../theme.dart';

/// 屏上文案：4 根棒的块标签（那 4 个字母就是基因型本身）。
const String kTetraAllelesLabel = '四倍体基因型';

/// 屏上文案：配子框的块标签。
const String kTetraGameteLabel = '配子基因型';

/// 屏上文案：框上那个数字是什么。
const String kTetraSharesLabel = '份数';

/// 屏上文案：依据行。
///
/// ⛔ 只描述「软件算出了什么」，**不描述任何教材结论**：它说的是
/// 「份数是软件枚举出来的组合份数」，这句话在**任何**输入下都成立
/// （引擎要么抛错、要么给出 `counts`，不存在「有结果但没有份数」）。
const String kTetraBasisLabel = '份数为软件枚举的组合份数';

// ────────────────────────────────────────────────────────────────────
// 版面常量（设计坐标，与遗传咨询那张方格图**各画各的**、不共用代码）
// ────────────────────────────────────────────────────────────────────

/// 设计宽度。320 窄屏不许溢出 ⇒ 父级必须限宽（宿主已限）。
const double kTetraDiagramDesignWidth = 320;

/// 可画上限：框数超过它就**不画**（见 `TetraploidGameteDiagram.build`）。
///
/// ⚠️ **实测**（不是估的）：320 − 2×12 = 296 可用宽。
/// · 3 框：(296 − 2×8) / 3 = **93.3 px/框**
/// · 2 框：(296 − 1×8) / 2 = **144.0 px/框**
/// 引擎的 `counts.length` 实测只有 **2 或 3**（见文件头），两条都远宽于
/// [kTetraDiagramMinBoxWidth]。
const int kTetraDiagramMaxBoxes = 3;

/// 框宽下限：再窄就宁可整张图不出现（基因型串会塞不下）。
const double kTetraDiagramMinBoxWidth = 56;

const double _marginTop = 12;
const double _marginBottom = 12;
const double _sideMargin = 12;

const double _blockLabelHeight = 15;
const double _blockGap = 12;

const double _barHeight = 34;
const double _barGap = 6;

const double _boxHeight = 46;
const double _boxGap = 8;

/// 4 根棒的总高（根数恒为 4，⛔ 不写成数据推导的量）。
const double _barsBlockHeight = _barHeight;

/// 总高 —— ⛔ **唯一的排版真相**，宿主用它给 `CustomPaint` 一个确定的高度。
///
/// v2.19.172（R58）：[textScale] 是**课堂大屏字号倍率**（标准档 1.0）。
/// ⚠️ 三个「装字的带」（块标签行 / 棒 / 配子框）的高度必须跟着倍率走：
///    v2.19.172 之前它们是写死的常量，而框里的字已经乘了倍率 ⇒ 字变高、
///    带没变 ⇒ 份数那一行顶出框底（实测 27.0 / 19.0 = 1.42×）。
/// ⛔ **只乘这三个带**：边距与带之间的缝是设计稿常量，不动。
/// `textScale == 1.0` 时三个乘数都是 1.0（IEEE-754 精确）⇒ 标准档逐像素不变。
double tetraploidDiagramTotalHeight([double textScale = 1.0]) =>
    _marginTop +
    _blockLabelHeight * textScale +
    _barsBlockHeight * textScale +
    _blockGap +
    _blockLabelHeight * textScale +
    _boxHeight * textScale +
    _marginBottom;

/// 配子框里那个数字的屏上字符串 —— ⛔ **painter 只准认这一个函数**。
///
/// ⛔ **不许在 painter 里另写一遍 `'${shares}'`**：那会让「屏上印的份数」
///    变成一个只能靠肉眼/基线发现的视觉事实。把它收成有牙齿的函数后，
///    「图上印的份数」与「引擎的 `counts`」之间那条接缝就能被测试直接钉住
///    （`test/ui/tetraploid_gamete_diagram_test.dart` 逐框对撞）。
String tetraploidDiagramShareText(TetraploidDiagramPlan plan, int index) =>
    '${plan.boxes[index].shares}';

// ────────────────────────────────────────────────────────────────────
// 数据形状
// ────────────────────────────────────────────────────────────────────

/// 一个配子框：**基因型字符串**（== 引擎 `counts` 的 key）+ **份数**。
class TetraploidDiagramBox {
  const TetraploidDiagramBox({required this.genotype, required this.shares});

  /// 逐字等于 `result.counts` 的某个 key。
  final String genotype;

  /// 逐字等于 `result.counts[genotype]`。
  final int shares;

  @override
  bool operator ==(Object other) =>
      other is TetraploidDiagramBox &&
      other.genotype == genotype &&
      other.shares == shares;

  @override
  int get hashCode => Object.hash(genotype, shares);
}

/// 版面计划 —— ⛔ **排版与数据的唯一真相**，painter 与测试**共用**这一份。
///
/// ⚠️ 在测试里另抄一份宽度只能证明抄对了（测不出 painter 少画一根棒）；
/// 让 painter 与断言都读同一个 [TetraploidDiagramPlan] 才是真牙齿：
/// 改这里一处，画出来的与断言的**同时**变。
class TetraploidDiagramPlan {
  const TetraploidDiagramPlan({
    required this.alleles,
    required this.boxes,
    required this.totalShares,
    this.textScale = 1.0,
  });

  /// 4 根棒上的字母，**按 `result.genotype` 里的出现顺序**（⛔ 不排序、
  /// ⛔ 不去重——`AAaa` 就该读成 `A A a a`）。
  final List<String> alleles;

  /// 配子框，顺序 == `result.counts` 的迭代顺序（引擎已按键排好序）。
  final List<TetraploidDiagramBox> boxes;

  /// 所有框的份数之和（⛔ 由 `counts` 求出，**不是写死的 6**）。
  final int totalShares;

  /// v2.19.172（R58）：课堂大屏字号倍率（标准档 1.0）。
  ///
  /// 【为什么版面计划要带它】v2.19.172 之前，本计划的三条「装字的带」
  /// （块标签行 / 棒 / 配子框）的高度是**写死的常量**，而 painter 画出去
  /// 的字已经乘了课堂倍率 ⇒ 课堂档下格子没变、字变大 ⇒ 溢出（实测：框里
  /// 份数那一行 27.0 高，而框只分到 19.0，1.42×）。
  ///
  /// ⛔ **不许改** `_marginTop/_marginBottom/_sideMargin/_blockGap/_boxGap/
  ///    _barGap`：那六个是设计稿写死的边距与缝，与字号无关。
  final double textScale;

  /// 块标签那一行的高度（⛔ 随字号倍率走，见 [textScale]）。
  double get blockLabelHeight => _blockLabelHeight * textScale;

  /// 每根棒的高度（⛔ 随字号倍率走，见 [textScale]）。
  double get barHeight => _barHeight * textScale;

  /// 每个配子框的高度（⛔ 随字号倍率走，见 [textScale]）。
  double get boxHeight => _boxHeight * textScale;

  /// 可用宽度。
  double get usableWidth => kTetraDiagramDesignWidth - _sideMargin * 2;

  /// 每根棒的宽度（4 根棒恒定 ⇒ 恒定宽度）。
  double get barWidth => (usableWidth - _barGap * (alleles.length - 1)) / alleles.length;

  /// 每个框的宽度 —— ⛔ **由框数算出**（3 框 93.3 / 2 框 144.0）。
  double get boxWidth =>
      (usableWidth - _boxGap * (boxes.length - 1)) / boxes.length;

  /// 第 [index] 根棒的矩形。
  Rect barRectAt(int index) => Rect.fromLTWH(
        _sideMargin + index * (barWidth + _barGap),
        _marginTop + blockLabelHeight,
        barWidth,
        barHeight,
      );

  /// 全部 4 根棒的矩形，**逐根**。
  List<Rect> allBarRects() =>
      <Rect>[for (var i = 0; i < alleles.length; i++) barRectAt(i)];

  /// 配子框区的顶缘。
  double get boxesTop =>
      _marginTop + blockLabelHeight + barHeight + _blockGap + blockLabelHeight;

  /// 第 [index] 个框的矩形（**按 `counts` 的迭代顺序**）。
  Rect boxRectAt(int index) => Rect.fromLTWH(
        _sideMargin + index * (boxWidth + _boxGap),
        boxesTop,
        boxWidth,
        boxHeight,
      );

  /// 全部配子框的矩形，**逐框**。
  List<Rect> allBoxRects() =>
      <Rect>[for (var i = 0; i < boxes.length; i++) boxRectAt(i)];

  double get totalHeight => tetraploidDiagramTotalHeight(textScale);
}

/// 字母过滤规则 —— 与 `ploidy_engine.dart` 里那**同一条** `[A-Za-z]`。
///
/// ⚠️ **本函数不重算任何组合**：它只是在读引擎已经存好的
/// [TetraploidGametes.genotype] 时，沿用引擎的字母定义把那 4 个字母取出来。
/// 引擎的 `genotype` 存的是**原始输入**（`tetraploidGametes` 内部把非字母
/// 滤掉后才枚举，但 `genotype:` 字段传的是原串）⇒ 不滤一遍，棒上就会
/// 印进空格。
List<String> tetraploidDiagramAlleles(String genotype) => genotype
    .split('')
    .where((c) => RegExp(r'[A-Za-z]').hasMatch(c))
    .toList();

/// 由引擎结果建版面计划；**任何一条不自洽就返回 null**（⇒ 整张图不画）。
///
/// 判据逐条都能被测试打到：
/// ① 没有结果 / `counts` 为空；
/// ② `genotype` 里的字母**不是 4 个**（引擎对这种输入抛 `ArgumentError`，
///    这里防的是有人手工拼一个假结果喂进来）；
/// ③ 4 个字母**不是同一基因**（不分大小写）——同 ②；
/// ④ 框数超出可画上限（见 [kTetraDiagramMaxBoxes]）；
/// ⑤ 有框的份数 **< 1**（0 份的框不该占位）；
/// ⑥ **某个框的基因型不是那 4 个字母里挑 2 个拼出来的**（自相矛盾：
///    框里会出现棒上根本没有的基因）；
/// ⑦ 框宽低于 [kTetraDiagramMinBoxWidth]（画不下，见该常量注释）。
///
/// ⛔ 这里**没有**「份数之和必须等于 6」这一条：6 是 C(4,2) 的组合数，
///    把它写成闸门就是**把 6 冻进组件**。本组件只保证「图上的份数逐框
///    等于引擎的 `counts`」，对账交给测试。
TetraploidDiagramPlan? tetraploidDiagramPlan(
  TetraploidGametes? result, {
  double textScale = 1.0,
}) {
  if (result == null) return null;
  final counts = result.counts;
  if (counts.isEmpty) return null;

  final alleles = tetraploidDiagramAlleles(result.genotype);
  if (alleles.length != 4) return null;
  if (alleles.map((c) => c.toUpperCase()).toSet().length != 1) return null;

  if (counts.length > kTetraDiagramMaxBoxes) return null;
  for (final v in counts.values) {
    if (v < 1) return null;
  }

  // 判据 ⑥：框里的两个字母都必须出自那 4 根棒（不分大小写）。
  // 判据 ③ 已保证那 4 个字母同一基因 ⇒ 这一条同时把框里的基因也锁死在
  // 同一个基因上（框里出现棒上根本没有的基因 = 自相矛盾，不画）。
  final pool = alleles.map((c) => c.toUpperCase()).toSet();
  for (final key in counts.keys) {
    final letters =
        key.split('').where((c) => RegExp(r'[A-Za-z]').hasMatch(c)).toList();
    if (letters.length != 2) return null;
    if (letters.any((c) => !pool.contains(c.toUpperCase()))) return null;
  }

  final boxes = <TetraploidDiagramBox>[
    for (final e in counts.entries) TetraploidDiagramBox(genotype: e.key, shares: e.value),
  ];
  final plan = TetraploidDiagramPlan(
    alleles: alleles,
    boxes: boxes,
    totalShares: boxes.fold<int>(0, (a, b) => a + b.shares),
    textScale: textScale,
  );

  // 判据 ⑦：框宽下限。
  if (plan.boxWidth < kTetraDiagramMinBoxWidth) return null;
  return plan;
}

// ────────────────────────────────────────────────────────────────────
// 组件
// ────────────────────────────────────────────────────────────────────

/// 同源四倍体配子示意图。
///
/// ## 挂载闸门在**本组件内部**（⛔ 不靠宿主自觉）
///
/// [build] 的第一件事就是建 [TetraploidDiagramPlan]：建不出来 ⇒ **整棵
/// 子树**是 `SizedBox.shrink`。⛔ **不留标题、不留图例、不留空框、
/// 不留占位**——与 `disease_punnett_diagram.dart:205-209` 的既有纪律同款。
/// 理由：结果区那一行 `RatioPill` 在窄屏下已经占满，留一个空框比没有图
/// 更让人以为「这里本该有图」。
class TetraploidGameteDiagram extends StatelessWidget {
  const TetraploidGameteDiagram({
    super.key,
    required this.result,
    this.textScale = 1.0,
  });

  /// 引擎结果。⛔ 图上每一个字母与每一个份数都只从它取。
  final TetraploidGametes? result;

  /// v2.19.172（R54）：课堂大屏字号倍率（标准模式 1.0 = 逐像素零变化）。
  ///
  /// 【为什么需要它】课堂模式的全局放大只经 `MaterialApp.builder` 注入
  /// `MediaQuery.textScaler`，那只对 **`Text` widget** 生效。本图上的块标签
  /// （11px）、棒上字母（15px）与框内份数（13px）是 `TextPainter` 自绘，而
  /// `TextPainter.textScaler` 默认 `TextScaler.noScaling`
  /// ——**不经过 MediaQuery** ⇒ 课堂大屏下这些字**完全没被放大**。
  /// （节点方框区域内那行由本组件自绘；网格**外面**那行依据是真正的 `Text` widget，已经吃 1.75×，⛔ 不在本组件管辖内。）
  ///
  /// 【怎么用】宿主（`ploidy_page.dart` 构造本组件处）在
  /// `PresentModeController.instance.enabled` 时传
  /// `PresentModeController.textScale`，否则传 1.0。
  final double textScale;

  @override
  Widget build(BuildContext context) {
    // ⛔ 闸门在**建任何子 widget 之前**：不可画 ⇒ 屏幕上什么也不多出来。
    // v2.19.172（R58）：课堂倍率**一并交给版面计划** —— 否则格子仍按 1.0
    // 那一档算，字放大后顶出框底（见 [TetraploidDiagramPlan.textScale]）。
    final plan = tetraploidDiagramPlan(result, textScale: textScale);
    if (plan == null) return const SizedBox.shrink();
    return Padding(
      // 这点间距由组件**自己**带：不可画时它是零，而不是在宿主里留一道
      // 会把那枚 `RatioPill` 顶开的空白。
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          ClipRect(
            child: CustomPaint(
              size: Size(kTetraDiagramDesignWidth, plan.totalHeight),
              painter: _TetraploidPainter(plan: plan, textScale: textScale),
            ),
          ),
          const SizedBox(height: 6),
          Text(kTetraBasisLabel, style: AppText.caption),
        ],
      ),
    );
  }
}

class _TetraploidPainter extends CustomPainter {
  _TetraploidPainter({required this.plan, this.textScale = 1.0});

  /// ⛔ 几何与数据都出自 [TetraploidDiagramPlan]（与测试同源）。
  final TetraploidDiagramPlan plan;

  /// v2.19.172（R54）：课堂大屏字号倍率。宿主在课堂档传
  /// `PresentModeController.textScale`，标准档传 1.0。详见
  /// [TetraploidGameteDiagram.textScale] 的完整理由。
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
    final teal = AppColors.teal;
    final sand = AppColors.sand;
    final border = AppColors.border;
    final surface = AppColors.surface;
    final graphite = AppColors.graphite;
    final ink = AppColors.ink;
    final steel = AppColors.steel;

    // ── 块标签 1：那 4 个字母是什么 ──
    _paintText(
      canvas,
      kTetraAllelesLabel,
      TextStyle(
        fontFamily: AppFonts.sans,
        fontFamilyFallback: AppFonts.sansFallback,
        fontSize: 11,
        color: graphite,
      ),
      Offset(_sideMargin,
          _marginTop + (plan.blockLabelHeight - 11 * textScale) / 2),
    );

    // ── 4 根棒：⛔ 棒上**只有那 4 个字母本身**。
    //    不画着丝粒 / 不画长短 / 不画形态差别 / 不标基因名 ——
    //    引擎没有「基因 ↔ 染色体」的映射，画出来就是编造。
    final barRects = plan.allBarRects();
    for (var i = 0; i < barRects.length && i < plan.alleles.length; i++) {
      final rect = barRects[i];
      final rounded = RRect.fromRectAndRadius(rect, const Radius.circular(5));
      canvas.drawRRect(
        rounded,
        Paint()
          ..style = PaintingStyle.fill
          ..color = teal.withValues(alpha: 0.14),
      );
      canvas.drawRRect(
        rounded,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2
          ..color = teal,
      );
      _paintText(
        canvas,
        plan.alleles[i],
        AppText.genotype.copyWith(
          fontSize: 15,
          fontWeight: FontWeight.w700,
          color: ink,
        ),
        Offset(rect.left, rect.top + (plan.barHeight - 18 * textScale) / 2),
        centerInWidth: rect.width,
      );
    }

    // ── 块标签 2：配子基因型 · 份数 ──
    final label2 = '$kTetraGameteLabel · $kTetraSharesLabel';
    _paintText(
      canvas,
      label2,
      TextStyle(
        fontFamily: AppFonts.sans,
        fontFamilyFallback: AppFonts.sansFallback,
        fontSize: 11,
        color: graphite,
      ),
      Offset(_sideMargin,
          plan.boxesTop -
              plan.blockLabelHeight +
              (plan.blockLabelHeight - 11 * textScale) / 2),
    );

    // ── 配子框：⛔ 基因型逐字取 `counts` 的 key，份数逐字取 `counts` 的 value。
    //    ⛔ **不重枚举组合、不写死 1:4:1 / 1:1**。
    final boxRects = plan.allBoxRects();
    for (var i = 0; i < boxRects.length && i < plan.boxes.length; i++) {
      final rect = boxRects[i];
      final rounded = RRect.fromRectAndRadius(rect, const Radius.circular(6));
      canvas.drawRRect(
        rounded,
        Paint()
          ..style = PaintingStyle.fill
          ..color = surface,
      );
      canvas.drawRRect(
        rounded,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2
          ..color = sand,
      );
      // 框内：基因型（逐字 == key）+ 份数（逐字 == value，⛔ 唯一出口
      // [tetraploidDiagramShareText]）。
      //
      // ⚠️ v2.19.172（R58）：**行内的 7 / 27 这两个内边距要跟着课堂倍率走**
      //（它们是「字块」在框内的相对位置，不是设计稿的边距）：框高已经按
      // `plan.boxHeight` 放大，若这两处不动，基因型行底会压到份数行顶上
      // （实测课堂档两行重叠 11px）。`textScale == 1.0` 时乘数是 1.0
      // （IEEE-754 精确）⇒ 标准档逐像素不变。
      _paintText(
        canvas,
        plan.boxes[i].genotype,
        AppText.genotype.copyWith(
          fontSize: 15,
          fontWeight: FontWeight.w700,
          color: ink,
        ),
        Offset(rect.left, rect.top + 7 * textScale),
        centerInWidth: rect.width,
      );
      _paintText(
        canvas,
        tetraploidDiagramShareText(plan, i),
        AppText.monoFigure.copyWith(
          fontSize: 13,
          fontWeight: FontWeight.w700,
          color: steel,
        ),
        Offset(rect.left, rect.top + 27 * textScale),
        centerInWidth: rect.width,
      );
    }
  }

  /// 画一行字。[centerInWidth] > 0 时按该宽度**居中**。
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
    final dx = centerInWidth > 0 ? at.dx + (centerInWidth - painter.width) / 2 : at.dx;
    painter.paint(canvas, Offset(dx, at.dy));
    painter.dispose();
  }

  @override
  bool shouldRepaint(_TetraploidPainter old) =>
      !listEquals(old.plan.alleles, plan.alleles) ||
      !listEquals(old.plan.boxes, plan.boxes) ||
      // v2.19.172（R54）：课堂倍率必须参与比较——否则课堂上切换课堂模式时
      // 画布复用旧 painter，字号停在标准模式那一档。
      old.textScale != textScale;
}
