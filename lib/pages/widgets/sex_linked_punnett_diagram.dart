// sex_linked_punnett_diagram.dart —— 伴性遗传概念示意图（**代码绘制**，非位图）
//
// ## 这张图只回答一件事
//
// > **父亲的两种配子 × 母亲的两种配子 = 四种子代；而决定孩子是儿子还是女儿的，
// > 是父亲给出去的那一条是 X 还是 Y。**
//
// 伴性遗传页（9331 第 4 个页签，`sex_linked_tab.dart` 的 `SexLinkedTab`）本来只有
// 两张表：子代明细表 + 条件概率卡。学生看到「患病男孩 1/2」这类数字，却没有一个模型
// 能解释**它从哪来**。这张图就是那个模型。
//
// ────────────────────────────────────────────────────────────────────
// ## ⛔ 三条不许越界的线（本项目铁律，违反即否决）
//
// ① ⛔ **不许画「男孩更多 / 性别比」**。`SexLinkedEngine.maleGametes` 恒返
//    `{X: 1/2, Y: 1/2}`（`sex_linked_engine.dart:130`）⇒ **引擎在结构上永远给不出
//    「男孩更多」**；全仓也没有任何致死率 / 性别差异存活率参数。画它就是凭空引入
//    引擎里不存在的假设。
// ② ⛔ **不许印任何概率 / 比例 / 百分比数字**。屏上比例由已有的「子代表型」表负责；
//    本图是**概念图**。图上唯一的「数字感」来自基因型串（`XA` / `Xa` / `Y`），
//    它们是**点名对象**，不是数值（与 `linkage_crossover_diagram.dart` 已立的同款
//    规矩：屏上文案禁 markdown 星号、禁方向词、禁数字）。
// ③ ⛔ 图里**唯一不能画错**的关系：X 与 Y 是**两条不同的染色体**；女儿的两条 X
//    **一条来自母亲、一条来自父亲**；儿子的 X **必然来自母亲**、Y **来自父亲**。
//    这三条各自都有对应的守卫，理由写在 [PunnettCell] 与测试 S4/S5 上。
//
// ## 数据全部来自引擎（本文件**不推算任何概率**）
//
// 工厂 [SexLinkedPunnettFigure.fromEngine] 的入参就是引擎那两个静态方法的返回值
// （`SexLinkedEngine.femaleGametes` / `maleGametes`）：它只取**键**（配子名），
// 把概率原样丢掉。⇒ 图上不可能出现一个引擎没算出来的组合，也不可能印出比例。
// 「父亲给出去的是 X 还是 Y 决定性别」这句话在代码里的落点是
// [PunnettCell.isDaughter] —— 它**只看父亲那一条**（[PunnettCell.paternal]），
// 与母亲给哪一条完全无关。
//
// ## ⛔ 挂载闸门在宿主，不在本文件
//
// 图**不是**「总是显示」：`sex_linked_tab.dart` 的 `_punnettFigure` getter 逐条判据
// 见那里的注释（未算 ⇒ 不给；配子表现算 ⇒ 不读输入框；任一条前提不成立 ⇒ 给 null）。
// 本文件侧另有一道兜底 [SexLinkedPunnettFigure.maybeFromEngine]：任何一条前提被违反
// 都**返回 null 而不是画错**。
//
// ────────────────────────────────────────────────────────────────────
// ## ⚠️ 与连锁互换那张图存在**形状重复**（等位基因色带的画法）
//
// `linkage_crossover_diagram.dart` 的「杆 + 实心/空心色带」与本图的「杆 + 色带」是
// 同一套画法（实心 = 大写、空心 = 小写）。本轮 ⛔ **不许**复用它的私有绘制代码
// （另一个 worker 正在改那个文件，碰了必冲突）⇒ **照抄结构、各自实现**。
// **等那张图定稿后应合并为一个共享 helper**（`LocusRodPainter` 之类），本文件与它
// 都要在合并时改；在那之前两份实现各自目检、各自录基线。
//
// ────────────────────────────────────────────────────────────────────
// ## 版面（**v2.19.161 第二版**：第一版 140px 被目检打回，见下）
//
// 第一版被主线程目检**打回**，四条理由与本版的逐条修法：
//
// ① 「每格两条杆，**图上没有任何东西标明哪条来自母亲、哪条来自父亲**」——第一版
//    只靠「靠左 / 靠右」的 x 坐标，而那是几何推断、学生看不见。⇒ 本版把归属
//    **写在杆的正下方**（`母亲XA` / `父亲XA`），词由 [PunnettChromosome.sourceWord]
//    从 `origin` 推出（`cellLabelSpan`）。
// ② 「女儿 / 儿子在图上没有任何**正向**标注」——第一版只能靠「哪条杆没色带」
//    反推，而无色带的杆在学生眼里是「这条没有信息」。⇒ 本版**每格**顶部写性别，
//    由 [PunnettCell.sexLabel]（即 `isDaughter`）推出。
// ③ 「读不出**方格结构**」——第一版没有格线，表头与格子离得远。⇒ 本版画外框 +
//    列分隔线 + 行分隔线（[PunnettPainter.gridRect] / `gridVerticalDividers` /
//    `gridHorizontalDividers`），且列头杆与格内「父亲那一条」同 x、行头杆与格内
//    两条杆同行心。
// ④ 根因是**版面太挤**：140px 要塞「表头行 + 2 个子代行」，每行只剩十几像素。
//    ⇒ 本版**只加高、不压扁**（字号 ≥ 11、杆高 ≥ 10 是常量下限，P3 守卫钉住）。
//
// 设计宽度仍是 **320**（360 窄屏不许溢出）。高度按需要涨：**2 行 = 210**、
// **1 行 = 140**（母亲纯合）。
//
// | 元素                     | 值（设计坐标）               | 为什么是这个数              |
// |--------------------------|-----------------------------|----------------------------|
// | 画布上边距                | 12                          |                            |
// | 块标签带（11px 中文）      | 16                          | 「母亲的配子」5 个汉字要放得下 |
// | 块标签 → 列头名 间距      | 6                           |                            |
// | 列头配子名带（12px 等宽）   | 16                          |                            |
// | 列头名 → 列头杆 间距       | 4                           |                            |
// | 列头杆（父亲的染色体）      | 12（= 杆高）                 |                            |
// | 列头杆 → 方格 间距         | 8                           |                            |
// | **方格顶**                | **74**                      | 以上七项之和               |
// | 格内性别标注带（11px）      | 14                          | 第一版**没有**这一带        |
// | 性别标注 → 杆 间距         | 4                           |                            |
// | 杆高                      | 12                          | ⛔ 下限 10                  |
// | 杆 → 归属词 间距           | 4                           |                            |
// | 归属词带（11+12px）         | 16                          | 第一版**没有**这一带        |
// | **一行内容高**             | **50**                      | 14+4+12+4+16               |
// | 行与行之间净空             | 20                          | 分隔线取中点 = 格边界       |
// | 画布下边距                | 16                          |                            |
// | **总高（2 行）**           | **210**                     | 74+50+20+50+16             |
// | 总高（1 行）               | 140                         | 74+50+16                   |
//
// 横向：行头列 = 杆 30 + 名字 18 + 间距 8 ⇒ **方格左缘 68**、右缘 312 ⇒ 每列
// **122**；格内两条杆 40 宽、中间 12、两端各留 15（两条杆在格里居中）。
//
// ### 为什么「性别」不画在列头而画在每格
//
// 性别确实由**列**决定（同一个父亲配子 ⇒ 同一列性别相同）。但审查要求
// 「**每一个格子**都有正向的性别标注」，而且重复成本极低（两个字）⇒ 每格写一份。
// S5 另有一条反向守卫：**同一列两格性别必须一致**，一旦不一致就等于图在说
// 「性别由母亲给的那条 X 决定」。
//
// ### 为什么归属词里还写配子名（`母亲XA`）
//
// 色带编码（实心/空心）看不见摸不着，而「这条没有色带」在学生眼里是「这条没有
// 信息」。归属词**把这条杆是什么**直接写出来：女儿的 `父亲XA`、儿子的 `父亲Y`
// ——「儿子那格父亲给的是 Y」因此是**看得见的字**，而不是一条空杆加一次推理。
//
// ### ⛔ 唯一的教学点怎么落在几何上
//
// · **行** = 母亲的一种配子（行头杆 + 行头名字）；**列** = 父亲的一种配子（列头杆 +
//   列头名字）。
// · 每一格里是**两条并排的杆**：靠母亲那一侧的那条继承**行头**，靠父亲那一侧的那条
//   继承**列头** —— ⛔ 而且**列头杆的杆心 x 与每格「父亲那一条」的杆心 x 逐格相同**，
//   眼睛顺着一条竖线看下去就是「父亲给的就是这一条」。这条对齐就是「女儿的两条 X
//   一条来自母亲、一条来自父亲」在图上的全部依据，**不需要任何箭头或记号**。
// · 儿子那两格里，靠父亲一侧的杆**没有色带**（Y 上无位点，引擎
//   `normalizeMale` 只保留 `X+allele`）⇒ ⛔ 「儿子的 X 来自父亲」在图上**画不出来**，
//   因为那一格的父亲那一条根本没有位点可给。
// · 「性别由父亲的哪一条决定」**不靠记号表达**，靠「同一格里靠母亲一侧的杆永远是 X
//   （有位点）、而性别由靠父亲那一侧是不是 Y 决定」这一对照。⇒ 任何给儿子加一枚
//   「♂」徽章或高亮的做法都删掉了：它说的话（性别由这条决定）图上已经处处成立，
//   纯属装饰，还会占用一支已有语义的色。
//
// ## 基因座的编码约定（与连锁互换那张图同款）
//
// · **实心带 = 大写等位基因**（该位点是大写字母）
// · **空心带 = 小写等位基因**（该位点是小写字母）
// · **没有色带 = 该染色体上没有位点**（只可能是 Y）
//
// ## ⛔ 禁红
//
// 本仓 `AppColors.lethal` 红 = **致死 / 错误**语义；本图讲的是「哪一条染色体决定
// 性别」，与致死无关 ⇒ 4 种颜色只用画布 / 杆 / 基因座 / 文字四支。
//
// ## 屏上文案三条硬规矩（语义标签同样适用）
//
// ⛔ 禁 markdown 星号（屏幕阅读器会念出来）；⛔ 禁方向词（要点名对象，不说
// 「上面那条」）；⛔ 禁任何数字 / 百分比。

import 'package:flutter/material.dart';

import '../../engine/fraction.dart';
import '../../theme.dart';

/// 父亲那条染色体的**光杆键名**，与引擎 `maleGametes` 返回的键逐字一致
/// （`sex_linked_engine.dart:130` 返回字面量 `'Y'`）。
const String kPunnettYGamete = 'Y';

/// 屏上文案：行头块标签。
const String kPunnettMotherLabel = '母亲的配子';

/// 屏上文案：列头块标签。
const String kPunnettFatherLabel = '父亲的配子';

/// 屏上文案：**格子里**那两条杆的归属标记（母亲给的那一条 / 父亲给的那一条）。
///
/// ⚠️ 为什么必须有这两个词：v2.19.161 第一版只靠「靠左那条 = 母亲、靠右那条 =
///    父亲」的**几何**表达归属，被目检打回 —— 那是几何推断，学生看不见，而这恰恰
///    是整张图唯一要教的事。现在每个格子把归属**写在杆的正下方**，且这个词由
///    [PunnettChromosome.origin] 推出来（`sourceWord`），⛔ 不是画的时候手挑的。
const String kPunnettMotherSource = '母亲';
const String kPunnettFatherSource = '父亲';

/// 屏上文案：女儿 / 儿子。⚠️ 这两个是**点名状态**，不是方向词、不是数值
/// （引擎在结构上给不出「男孩更多」，⛔ 全仓也没有任何性别比参数）。
const String kPunnettDaughterLabel = '女儿';
const String kPunnettSonLabel = '儿子';

/// 一条染色体**来自谁**。
///
/// ⚠️ 为什么是枚举而不是 `bool fromMother`：布尔量读起来要靠注释才知道哪一头是真，
/// 而这张图最要紧的断言（S5）恰恰是「来源」——枚举让守卫可以直接读。
enum PunnettOrigin { mother, father }

/// 图上的一条染色体（父或母给的**一条**）。
///
/// [upper] 逐位点：大写 = 实心带。⛔ **`Y` 恒为空列表** —— Y 上没有位点，
/// [PunnettGamete.hasLocus] 为 false，painter 因此**一个色带都不画**。
/// 「性别决定于父亲那一条」与「Y 无位点」这两件事不许互相顶替：前者是因果，
/// 后者是事实，图上必须同时成立。
class PunnettGamete {
  /// 由引擎给的配子键构造。⛔ 键的形式由本方法**逐条校验**，不合就抛：
  /// 这张图只认引擎 `maleGametes` / `femaleGametes` 真正会给的那两种形状
  /// （`X{一个等位基因}` 与光杆 `Y`）。
  factory PunnettGamete.fromKey(String key) {
    if (key == kPunnettYGamete) {
      // ⛔ Y 上**没有位点**：这里给的是空列表，不是「某个位点是小写」。
      return PunnettGamete._(name: key, upper: const <bool>[]);
    }
    final isSingleLocusX =
        key.length == 2 && key.codeUnitAt(0) == _kUnitX && _isLetter(key.codeUnitAt(1));
    if (!isSingleLocusX) {
      throw StateError(
          '配子键 $key 不是本图认识的形状：只接受 `X{一个等位基因字母}` 或光杆 `Y`'
          '（引擎 `femaleGametes` / `maleGametes` 只会给这两种）');
    }
    return PunnettGamete._(
        name: key, upper: <bool>[_isUpperLetter(key.codeUnitAt(1))]);
  }

  PunnettGamete._({required this.name, required List<bool> upper})
      : upper = List<bool>.unmodifiable(upper);

  /// 配子名（`XA` / `Xa` / `Y`），**逐字等于引擎给的键**。
  final String name;

  /// 逐位点：大写 = 实心带。长度为 0（Y）或 1（X）。
  final List<bool> upper;

  /// 是不是那条光杆 Y。
  bool get isY => name == kPunnettYGamete;

  /// 有没有位点。⛔ **没有位点 ⇒ 不画色带**（不是「画一个空的」）。
  bool get hasLocus => upper.isNotEmpty;

  /// 位点数（伴性遗传恒为 0 或 1）。
  int get locusCount => upper.length;

  /// 按图上的编码（实心 = 大写 / 空心 = 小写）把色带**还原**成等位基因串。
  ///
  /// ⚠️ 测试核对「色带 = 引擎给的配子串」时**必须调这个方法**，⛔ 不许在测试里
  /// 再抄一遍大写/小写的判定 —— 抄一遍只能证明抄对了（连锁那张图栽过的坑）。
  /// `Y` 返回空串（它本来就没有等位基因）。
  String get alleleString {
    final letter = name.length > 1 ? name.substring(1) : '';
    final buf = StringBuffer();
    for (final u in upper) {
      buf.write(u ? letter.toUpperCase() : letter.toLowerCase());
    }
    return buf.toString();
  }

  static bool _isUpperLetter(int unit) => unit >= 0x41 && unit <= 0x5A; // 'A'..'Z'

  /// 任意一个拉丁字母（**大小写都算**）。
  ///
  /// ⚠️ 这里与 [_isUpperLetter] 分成两个函数，是因为二者回答的是不同的问题：
  /// 「**这个键的形状对不对**」问的是「等位基因位上有没有字母」（`Xa` 的**小写 a**
  /// 是完全合法的隐性等位基因）；「**这一位是大写还是小写**」才是实心/空心的根据。
  /// 第一版把两者合成一个（形状校验顺带要求大写）⇒ 隐性配子 `Xa` 被当成非法键，
  /// 图在**第一格之前**就没了；教训记在这里。
  static bool _isLetter(int unit) =>
      (unit >= 0x41 && unit <= 0x5A) || (unit >= 0x61 && unit <= 0x7A); // A-Z / a-z

  /// 染色体字母 `X` 的码点（引擎 `parseGenotype` 只把小写 `x` 归一成 `X`）。
  static const int _kUnitX = 0x58;

  @override
  String toString() => 'PunnettGamete($name)';

  @override
  bool operator ==(Object other) =>
      other is PunnettGamete && other.name == name;

  @override
  int get hashCode => name.hashCode;
}

/// 图上一格里的**一条**染色体 = 父或母给的那一条。
class PunnettChromosome {
  const PunnettChromosome({required this.gamete, required this.origin});

  /// 这一条的内容（[PunnettGamete]，⛔ 同一个对象同时出现在行头/列头 ⇒ 图上
  /// 「继承自哪一条」是**同一份数据**，不是注释里的一句说明）。
  final PunnettGamete gamete;

  /// 它来自谁。
  final PunnettOrigin origin;

  /// 屏上写在这条杆**正下方**的归属词（母亲 / 父亲）。
  ///
  /// ⛔ **由 [origin] 推出来的唯一落点**（图上、语义标签、守卫都读它）。
  ///   第一版没有它，归属只存在于「靠左 / 靠右」的 x 坐标里 ⇒ 目检打回：
  ///   图唯一要教的事恰恰是唯一说不出口的那件。现在它被**画在杆下面**。
  String get sourceWord =>
      origin == PunnettOrigin.mother ? kPunnettMotherSource : kPunnettFatherSource;

  @override
  String toString() => 'PunnettChromosome(${gamete.name}, $origin)';

  @override
  bool operator ==(Object other) =>
      other is PunnettChromosome &&
      other.gamete == gamete &&
      other.origin == origin;

  @override
  int get hashCode => Object.hash(gamete, origin);
}

/// 图上的一格 = **一个子代** = 母亲给的一条 + 父亲给的一条。
class PunnettCell {
  const PunnettCell({
    required this.maternal,
    required this.paternal,
    required this.rowGamete,
    required this.columnGamete,
  });

  /// 母亲给的那一条（⛔ 恒是 X，因为母亲只有 X 染色体）。
  final PunnettChromosome maternal;

  /// 父亲给的那一条（`X{等位基因}` 或 `Y`）。
  final PunnettChromosome paternal;

  /// 这一格所属**行**的配子（母亲的），供守卫点名取用。
  final PunnettGamete rowGamete;

  /// 这一格所属**列**的配子（父亲的），供守卫点名取用。
  final PunnettGamete columnGamete;

  /// 两条并排的染色体，索引 0 = 母亲的、1 = 父亲的。
  List<PunnettChromosome> get chromosomes =>
      <PunnettChromosome>[maternal, paternal];

  /// ⛔⛔ **本图全部因果的落点**：孩子是女儿，当且仅当**父亲给的那一条不是 Y**。
  ///
  /// ⚠️ 这里**故意只读 [paternal]**。性别**不**由「哪条 X」决定（X 决定的是
  /// 半合子表型，见引擎 `sex_linked_engine.dart:152-154`）⇒ 把「母亲给了哪条 X」
  /// 也写进这个判断，就是把一件引擎里没有的事画成结构。
  bool get isDaughter => !paternal.gamete.isY;

  /// ⛔ 与 [isDaughter] 严格互补，同样**只看** [paternal]。
  bool get isSon => paternal.gamete.isY;

  /// 屏上写在这一格里的性别标注。⚠️ **由 [isDaughter] 推出**（第一版图上根本没有
  /// 这两个字，学生只能靠「哪条杆没色带」反推，被目检打回），⛔ 不是手写的字面量。
  String get sexLabel => isDaughter ? kPunnettDaughterLabel : kPunnettSonLabel;

  @override
  String toString() =>
      'PunnettCell(${rowGamete.name} × ${columnGamete.name} ⇒ $sexLabel)';
}

/// 图上的一行 = **母亲的一种配子** × 父亲的全部配子。
class PunnettRow {
  PunnettRow({required this.gamete, required List<PunnettCell> cells})
      : cells = List<PunnettCell>.unmodifiable(cells);

  /// 母亲的这一种配子（行头）。
  final PunnettGamete gamete;

  /// 这一行上的每一格（= 母亲这一条 × 父亲每一种配子）。
  final List<PunnettCell> cells;

  @override
  String toString() => 'PunnettRow(${gamete.name}, ${cells.length} 格)';
}

/// 伴性遗传概念图的数据。⛔ **只传结构化数据，不传布尔标志。**
///
/// 唯一的构造入口是 [SexLinkedPunnettFigure.fromEngine]：入参是引擎那两个静态方法
/// 的返回值，⛔ **本类不推算任何概率**（只取键，把概率丢掉）。
class SexLinkedPunnettFigure {
  /// 由引擎的配子表造出图的数据。前提不成立就**抛**（画错不如炸）。
  factory SexLinkedPunnettFigure.fromEngine({
    required Map<String, Fraction> femaleGametes,
    required Map<String, Fraction> maleGametes,
  }) {
    // ① 父亲必须恰好**两条不同的**染色体。
    //    ⛔ 绝不许把 X 与 Y 合成一条（那等于教「Y 是 X 的另一种叫法」）。
    //    引擎 `maleGametes`（:130）恒给 `{X{等位基因}: 1/2, Y: 1/2}`；一旦不是
    //    两条，「性别由父亲给的是 X 还是 Y 决定」这句话就没有着落，列头会画错。
    if (maleGametes.length != 2) {
      throw StateError(
          '父亲的配子必须恰好两条（X{等位基因} 与 Y），实际 ${maleGametes.length} 条：'
          '${maleGametes.keys.toList()}');
    }
    if (!maleGametes.containsKey(kPunnettYGamete)) {
      throw StateError(
          '父亲的配子里必须有一条光杆 $kPunnettYGamete（Y 上没有位点），'
          '实际 ${maleGametes.keys.toList()} —— 缺了它，「性别由父亲的哪一条决定」'
          '在图上就没有对应物');
    }
    // ② 母亲的配子：至少一条、至多两条（引擎 `parseGenotype` 只收两个等位基因
    //    ⇒ 结构上最多两种；纯合时合并为 1 条）。
    if (femaleGametes.isEmpty || femaleGametes.length > 2) {
      throw StateError(
          '母亲的配子必须是一或两条，实际 ${femaleGametes.length} 条：'
          '${femaleGametes.keys.toList()}');
    }
    // ③ 逐条校验键的形状（`X{一个等位基因字母}` 或光杆 `Y`）；不合就抛。
    //    顺序固定：母亲按引擎给的插入序（`cross` 传进来的是**标准化后**的串
    //    ⇒ 显性在前，行序稳定，基线才可复现）；父亲**X 在前、Y 在后**
    //    （⛔ 不依赖 Map 的插入序，避免哪天引擎换个构造顺序就换掉整张图）。
    final fgs = <PunnettGamete>[
      for (final k in femaleGametes.keys) PunnettGamete.fromKey(k)
    ];
    final mgs = <PunnettGamete>[
      PunnettGamete.fromKey(maleGametes.keys
          .firstWhere((k) => k != kPunnettYGamete, orElse: () => '')),
      PunnettGamete.fromKey(kPunnettYGamete),
    ];

    return SexLinkedPunnettFigure._(femaleGametes: fgs, maleGametes: mgs);
  }

  /// 宿主用的闸门入口：任何一条前提被违反都**返回 null**（宁可没有这张图，
  /// 也不要一张讲错关系的图）。⛔ 不吞异常的原因码 —— 前提的理由写在
  /// [fromEngine] 的每一条抛错里。
  static SexLinkedPunnettFigure? maybeFromEngine({
    required Map<String, Fraction> femaleGametes,
    required Map<String, Fraction> maleGametes,
  }) {
    try {
      return SexLinkedPunnettFigure.fromEngine(
        femaleGametes: femaleGametes,
        maleGametes: maleGametes,
      );
    } on StateError {
      return null;
    }
  }

  SexLinkedPunnettFigure._({
    required List<PunnettGamete> femaleGametes,
    required List<PunnettGamete> maleGametes,
  })  : femaleGametes = List<PunnettGamete>.unmodifiable(femaleGametes),
        maleGametes = List<PunnettGamete>.unmodifiable(maleGametes);

  /// 母亲的每一种配子（一行一种）。纯合时只有一条。
  final List<PunnettGamete> femaleGametes;

  /// 父亲的每一种配子（一列一种）= `X{等位基因}` 与 `Y` 两条**不同**的染色体。
  final List<PunnettGamete> maleGametes;

  /// 全部行（**顺序就是绘制顺序**）。
  late final List<PunnettRow> rows = _buildRows();

  /// 行数（母亲的配子种数：1 或 2）。
  int get rowCount => femaleGametes.length;

  /// 列数（父亲的配子种数，恒 2）。
  int get columnCount => maleGametes.length;

  /// 格子总数 = 母亲的配子种数 × 父亲的配子种数（出厂值下 = 4）。
  int get cellCount => rows.length * columnCount;

  /// 全部格子（按行优先），供守卫一次性遍历。
  List<PunnettCell> get cells =>
      <PunnettCell>[for (final r in rows) ...r.cells];

  List<PunnettRow> _buildRows() => <PunnettRow>[
        for (final fg in femaleGametes)
          PunnettRow(
            gamete: fg,
            cells: <PunnettCell>[
              for (final mg in maleGametes)
                PunnettCell(
                  // 母亲的配子对象**原样**交给这一格 ⇒ 「这一格的母亲那一条就是
                  // 行头那一条」是对象同一性，不是两处各写一遍的巧合。
                  maternal: PunnettChromosome(
                      gamete: fg, origin: PunnettOrigin.mother),
                  paternal: PunnettChromosome(
                      gamete: mg, origin: PunnettOrigin.father),
                  rowGamete: fg,
                  columnGamete: mg,
                ),
            ],
          ),
      ];

  @override
  String toString() => 'SexLinkedPunnettFigure('
      '母 ${femaleGametes.map((g) => g.name).toList()} / '
      '父 ${maleGametes.map((g) => g.name).toList()})';

  @override
  bool operator ==(Object other) =>
      other is SexLinkedPunnettFigure &&
      other.femaleGametes.length == femaleGametes.length &&
      other.maleGametes.length == maleGametes.length &&
      other.femaleGametes.join('/') == femaleGametes.join('/') &&
      other.maleGametes.join('/') == maleGametes.join('/');

  @override
  int get hashCode => Object.hash(femaleGametes.join('/'), maleGametes.join('/'));
}

/// 图上的**一行**（= 母亲的一种配子）连同它在设计坐标里的几何。
///
/// ⚠️ 为什么不把几何留在 painter 的 `paint()` 里现算：[plates] 里每一行的
/// [centerY] / [headerRodCx] / [cellXs] **就是 painter 画在哪儿**，守卫读它等于
/// 读「画上去的东西」；测试自己重抄一遍 `top + i * pitch` 只能证明抄对了（本项目在
/// 「测试重抄公式」上栽过三次）。
class PunnettPlate {
  const PunnettPlate({
    required this.row,
    required this.centerY,
    required this.sexLabelCenterY,
    required this.cellLabelCenterY,
    required this.headerRodCx,
    required this.cellXs,
  });

  /// 本行的生物学内容（母亲的一种配子 × 父亲的每一种配子）。
  final PunnettRow row;

  /// 行心 y（= 杆心 y，设计坐标，⛔ 不含按可用宽度的缩放）。
  final double centerY;

  /// 这一行里「女儿 / 儿子」标注的行心 y。
  final double sexLabelCenterY;

  /// 这一行里每格两条归属词（母亲 / 父亲）的行心 y。
  final double cellLabelCenterY;

  /// 行头（母亲那一条）杆心 x。
  final double headerRodCx;

  /// 每一格两条杆的杆心 x（第一项 = 母亲的、第二项 = 父亲的）。
  ///
  /// ⚠️ 归属词就画在这两个 x 上（正下方）⇒ **x 不再独自承担归属**。
  final List<({double maternalCx, double paternalCx})> cellXs;

  @override
  String toString() => 'PunnettPlate(${row.gamete.name}, centerY=$centerY)';
}

/// 伴性遗传概念示意图：父亲的两种配子 × 母亲的两种配子。
class SexLinkedPunnettDiagram extends StatelessWidget {
  const SexLinkedPunnettDiagram({super.key, required this.figure});

  /// 这张图讲的是哪一笔杂交（⛔ 结构化数据，无布尔标志）。
  final SexLinkedPunnettFigure figure;

  /// 设计宽度（逻辑像素）。实际按**可用宽度等比缩放**，⛔ 不固定像素宽。
  static const double designWidth = 320;

  /// 列数恒为 2（父亲的 `X{等位基因}` 与 `Y`）。写死是因为**图只讲这件事**；
  /// 引擎若不再是两条，[SexLinkedPunnettFigure.fromEngine] 会先抛，图根本不挂。
  static const int columnCount = 2;

  /// 行数上限（母亲的配子种数上限；纯合时是 1）。
  static const int maxRowCount = 2;

  /// 设计高度（逻辑像素）= 方格顶 + (行数-1) × 行距 + 一行内容高 + 下边距。
  ///
  /// ⚠️ v2.19.161 第一版是 **140**，被目检打回：每行只剩十几像素，格内塞不下
  ///    「性别标注 + 两条杆 + 两条归属词」。本版**只加高不压扁**：
  ///    2 行 = **210**、1 行 = 140（纯合）。⚠️ ⛔ 不许用缩小字号 / 压扁杆高来把
  ///    高度换回来（下限写在 [PunnettPainter.minFontSize] / [PunnettPainter.minRodHeight]）。
  static double designHeightFor(int rowCount) {
    assert(rowCount >= 1 && rowCount <= maxRowCount,
        '行数必须在一到 $maxRowCount 之间（母亲的配子种数）：实际 $rowCount');
    return PunnettPainter.rowsTop +
        (rowCount - 1) * PunnettPainter.rowPitch +
        PunnettPainter.rowContent +
        PunnettPainter.padBottom;
  }

  @override
  Widget build(BuildContext context) {
    // ⛔ AppColors 的 token 是 **getter**，亮度由 main.dart 顶层 build 调
    // AppColors.sync 切换 ⇒ 在这里**取值**再传给 painter，
    // ⛔ 不让 painter 自己去读（照 `linkage_crossover_diagram.dart` 的形状）。
    return Semantics(
      label: semanticsLabel(figure),
      child: RepaintBoundary(
        child: SizedBox(
          width: double.infinity,
          child: AspectRatio(
            aspectRatio: designWidth / designHeightFor(figure.rowCount),
            child: CustomPaint(
              painter: PunnettPainter(
                figure: figure,
                canvasColor: AppColors.canvas,
                rodColor: AppColors.surfaceLow,
                bandColor: AppColors.teal,
                textColor: AppColors.ink,
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// 本图的语义标签（**跟着数据走**）。
  ///
  /// ⛔ 三条硬规矩：禁 markdown 星号（屏幕阅读器会念出来）；禁方向词（不说
  /// 「上面那条」——位置在读屏里既错又不稳定，要**点名对象**：点名「母亲给的 XA」
  /// 而不是说「左边那条」）；⛔ 不印任何数字 / 百分比（比例是**算出来**的东西，
  /// 由结果区的两张表负责）。
  static String semanticsLabel(SexLinkedPunnettFigure f) {
    final buf = StringBuffer();
    buf.write('${kPunnettMotherLabel}：${f.femaleGametes.map((g) => g.name).join('、')}。');
    buf.write('${kPunnettFatherLabel}：${f.maleGametes.map((g) => g.name).join('、')}，'
        '这是两条不同的染色体，Y 染色体上没有位点。');
    buf.write('方格按母亲的配子分行、按父亲的配子分列，每一格是一个子代。');
    buf.write('每一格标出性别，并标出两条染色体分别是谁给的。');
    for (final row in f.rows) {
      for (final c in row.cells) {
        buf.write('${c.sexLabel}：母亲给的 ${c.maternal.gamete.name} 与'
            '父亲给的 ${c.paternal.gamete.name}。');
      }
    }
    buf.write('孩子是女儿还是儿子，只看父亲给出去的那一条是 X 还是 Y。');
    buf.write('实心色带是大写等位基因，空心色带是小写等位基因；'
        'Y 染色体没有位点，所以不画色带。');
    return buf.toString();
  }
}

/// 伴性遗传概念图的 painter。
///
/// 照 `linkage_crossover_diagram.dart` 的 `CrossoverPainter` 形状：
/// 颜色**全部由构造器传入**，`paint()` 第一件事铺近白底。
/// 图上的**内容**则全部由 [figure] 推导 —— ⛔ 这里没有任何基因型字面量。
class PunnettPainter extends CustomPainter {
  PunnettPainter({
    required SexLinkedPunnettFigure figure,
    required this.canvasColor,
    required this.rodColor,
    required this.bandColor,
    required this.textColor,
  })  : figure = figure,
        plates = _buildPlates(figure);

  /// 本图讲的是哪一笔杂交（几何由它推导，⛔ 不是 `paint()` 里现算的）。
  final SexLinkedPunnettFigure figure;

  final Color canvasColor;
  final Color rodColor;
  final Color bandColor;
  final Color textColor;

  /// 图上全部行（**顺序就是绘制顺序**）。
  ///
  /// ⚠️ 为什么不放在 `paint()` 里现算：`paint()` 遍历的就是这个列表 ⇒
  /// 「守卫读到的」与「画出去的」天生同源，不存在两处公式各写一遍、
  /// 改了一处忘了另一处的可能。
  final List<PunnettPlate> plates;

  /// 列数（恒 2）。
  int get columnCount => figure.columnCount;

  /// 行数（1 或 2）。
  int get rowCount => figure.rowCount;

  /// 格子总数。
  int get cellCount => figure.cellCount;

  /// 列头（父亲的配子）。
  List<PunnettGamete> get columnGametes => figure.maleGametes;

  /// 行头（母亲的配子）。
  List<PunnettGamete> get rowGametes => figure.femaleGametes;

  /// 本图用到的**全部**颜色，供守卫逐条钉住。
  ///
  /// ⚠️ 存在的理由不是方便，是**给「不许多出第 5 种颜色」这条断言一个落点**。
  /// 本仓调色板上每支颜色都带着既定语义（红 = 致死 / 错误、`select` = 选中…）；
  /// 装饰性的一笔不是「不要钱」，它是**在借一支已经有话要说的颜色**。
  /// 判据：想加一个元素时先问「它说的这件事，别的元素说不说不出来」。说不出来
  /// ⇒ 是证据，可以加并同步更新守卫；说得出来 ⇒ 删掉它。
  List<Color> get colors => <Color>[canvasColor, rodColor, bandColor, textColor];

  /// 行距（行区顶到下一行行区顶）。
  static double get rowPitch => rowContent + rowGap;

  /// 行与行之间的净空（方格横分隔线就取它的中点）。
  static double get rowGap => _kRowGap;

  /// ⛔ 本图的**下限常量**（P3 守卫逐条钉住）：字号与杆高**不许**为了塞下而压扁。
  /// v2.19.161 第一版 140px 高之所以不够，根因就是每一行只剩十几像素、杆高 12、
  /// 行内没有任何标注；这里把「不许低于」写成常量，将来谁想压扁会先撞守卫。
  static const double minRodHeight = 10;
  static const double minFontSize = 11;

  /// 一行（= 一个子代行）里三条内容带加起来的高。
  static double get rowContent =>
      sexLabelBand + _kCellRodPadY + rodH + _kCellLabelPadY + _kCellLabelBand;

  /// 行高（杆高）。
  static double get rowH => rodH;

  /// 行区顶（第一行格区的上边缘）。
  static double get rowsTop => _kRowsTop;

  /// 画布下边距。
  static double get padBottom => _kPadBottom;

  /// 方格外框（= 整个 Punnett 方格的包围盒），供守卫确认「格子是有边界的」。
  Rect get gridRect => Rect.fromLTRB(
        _kGridLeft,
        rowsTop,
        gridRight,
        rowsTop + (plates.length - 1) * rowPitch + rowContent,
      );

  /// 方格内部竖分隔线的 x（列与列之间）。2 列 ⇒ 1 条。
  List<double> get gridVerticalDividers => <double>[
        for (var j = 1; j < columnCount; j++) _kGridLeft + j * _cellWidth,
      ];

  /// 方格内部横分隔线的 y（行与行之间，取行间距的中点）。
  List<double> get gridHorizontalDividers => <double>[
        for (var i = 0; i < plates.length - 1; i++)
          rowsTop + i * rowPitch + rowContent + rowGap / 2,
      ];

  /// 一格的矩形（守「每格内容都落在自己那一格里」用）。
  Rect cellRect(int i, int j) {
    final top = rowsTop + i * rowPitch;
    return Rect.fromLTRB(
      _kGridLeft + j * _cellWidth,
      top,
      _kGridLeft + (j + 1) * _cellWidth,
      top + rowContent,
    );
  }

  /// 版面各段（设计坐标），供守卫把 [SexLinkedPunnettDiagram.designHeightFor]
  /// 与算式对上（那条等式跨 widget 与 painter 两个成员，Dart 没有
  /// `static_assert` 能在这儿编译期自证）。
  ({double padTop, double blockLabelBand, double colNameBand, double rodH, double rowContent, double rowGap, double rowsTop, double padBottom})
      get layout => (
            padTop: _kPadTop,
            blockLabelBand: _kBlockLabelBand,
            colNameBand: _kColNameBand,
            rodH: rodH,
            rowContent: rowContent,
            rowGap: _kRowGap,
            rowsTop: rowsTop,
            padBottom: padBottom,
          );

  /// 色带半高（色带上下各露多少）。守卫用它把「色带顶 / 底缘」换算成 y，
  /// 才知道两行之间是真的留了净空还是只是行心不一样。
  double get bandHalfHeight => _kBandH / 2;

  /// 色带宽（水平方向）。
  static double get bandWidth => _kBandW;

  /// 列头杆的杆心 x —— ⛔ 与每一格「父亲那一条」的杆心 x **逐格相同**。
  ///
  /// ⚠️ 这条对齐现在只承担「这一列是父亲的哪一种配子」，⛔ **不再独自承担归属**
  /// （归属由画在杆正下方的 [PunnettChromosome.sourceWord] 说出来）。
  List<double> get columnRodCxs => <double>[
        for (var j = 0; j < columnCount; j++) _paternalRodCx(j),
      ];

  /// 列头杆心 y。
  double get columnRodCenterY => _columnRodTop + rodH / 2;

  /// 列头配子名（`XA` / `Y`）的行心 y。
  double get columnNameCenterY =>
      _kPadTop + _kBlockLabelBand + _kBlockLabelGap + _kColNameBand / 2;

  /// 行头杆宽。
  static double get rowHeaderRodWidth => _kRowRodW;

  /// 一列占的宽。
  double get _cellWidth =>
      (gridRight - _kGridLeft) / columnCount;

  /// 方格右缘（列头杆心 x = 格内父亲那一条的杆心 x，仍是同一条竖线）。
  double get gridRight => SexLinkedPunnettDiagram.designWidth - _kGridPadRight;

  // ── 版面（设计坐标）──────────────────────────────────────────
  //
  // ⚠️ v2.19.161 第一版（高 140）被目检打回：每行只剩十几像素、格与格之间没有
  //    边界、归属只能靠 x 推断。⇒ 本版**只加高、不压扁**：设计宽仍是 320
  //    （360 窄屏不许溢出），高度按需要涨到 210（1 行 140）。每一行现在是
  //    「性别标注带 + 两条杆 + 两条归属词」三条内容带，行与行之间有 20px 的
  //    方格净空。
  static const double _kPadX = 8; // 画布左边距
  static const double _kPadTop = 12; // 画布上边距（= 块标签的顶）
  static const double _kBlockLabelBand = 16; // 块标签的预留行高（11px 中文）
  static const double _kBlockLabelGap = 6; // 块标签底 → 列头配子名顶
  static const double _kColNameBand = 16; // 列头配子名的预留行高（12px 等宽）
  static const double _kColNameGap = 4; // 配子名底 → 列头杆顶
  static const double rodH = 12; // 杆高（⛔ 不许低于 [minRodHeight]）
  static const double _kColRodGapY = 8; // 列头杆底 → 方格顶
  static const double _kRowRodW = 30; // 行头（母亲那一条）杆宽
  static const double _kRowNameX = _kPadX + _kRowRodW + 4; // 行头配子名左缘（42）
  static const double _kRowNameW = 18; // 行头配子名预留宽（`XA` 实测 ≈16）
  static const double _kGridGapX = 8; // 行头列 → 方格左缘
  static const double _kGridPadRight = 8; // 方格右缘 → 画布右边距
  static const double _kCellPadX = 15; // 格内左边距（两条杆一起居中）
  static const double _kCellRodW = 40; // 格内杆宽（母亲那条与父亲那条同宽）
  static const double _kCellRodGapX = 12; // 格内两条杆之间
  static const double sexLabelBand = 14; // 格内「女儿/儿子」标注带（11px 中文）
  static const double _kCellRodPadY = 4; // 性别标注带 → 杆
  static const double _kCellLabelPadY = 4; // 杆 → 归属词
  static const double _kCellLabelBand = 16; // 归属词带（11px 中文 + 12px 等宽）
  static const double _kRowGap = 20; // 行与行之间的方格净空（分隔线取中点）
  static const double _kPadBottom = 16; // 末行格区底 → 画布下边距
  static const double _kBandW = 10; // 色带宽
  static const double _kBandH = 20; // 色带比杆身高，露出来
  static const double _kGameteFontSize = 12; // 配子名（等宽）
  static const double _kChineseFontSize = 11; // 中文（块标签 / 性别 / 归属词）
  static const double _kLocusRatio = 0.5; // ⛔ 恒 0.5：伴性遗传只有**一个**位点
  static const double _kGridStrokeW = 1; // 方格分隔线宽

  /// 方格左缘 = 行头列（含名字）之后。
  static double get _kGridLeft =>
      _kPadX + _kRowRodW + 4 + _kRowNameW + _kGridGapX;

  /// 列头杆顶。
  static double get _columnRodTop =>
      _kPadTop + _kBlockLabelBand + _kBlockLabelGap + _kColNameBand + _kColNameGap;

  /// 方格顶 = 列头杆底 + 方格上方留白。
  static double get _kRowsTop => _columnRodTop + rodH + _kColRodGapY;

  static double _rowCenterY(int i) => _kRowsTop + i * rowPitch + sexLabelBand +
      _kCellRodPadY +
      rodH / 2;

  /// 一格靠母亲那一条的杆心 x。
  double _maternalRodCx(int j) =>
      _kGridLeft + j * _cellWidth + _kCellPadX + _kCellRodW / 2;

  /// 一格靠父亲那一条的杆心 x。⛔ **列头杆用的就是这个 x**（同一竖线）。
  double _paternalRodCx(int j) =>
      _maternalRodCx(j) + _kCellRodW + _kCellRodGapX;

  /// 按 [SexLinkedPunnettFigure] 的行序造出全部行（几何 + 内容）。
  static List<PunnettPlate> _buildPlates(SexLinkedPunnettFigure f) {
    // 列数恒 2 ⇒ 两条杆心 x 只与列下标有关，先算出来复用（列头杆与格内父亲那条
    // 走的是**同一个**函数，这是那条对齐的全部来源）。
    final cw = (SexLinkedPunnettDiagram.designWidth -
            _kGridLeft -
            _kGridPadRight) /
        f.columnCount;
    final matCxs = <double>[
      for (var j = 0; j < f.columnCount; j++)
        _kGridLeft + j * cw + _kCellPadX + _kCellRodW / 2,
    ];
    final patCxs = <double>[for (final cx in matCxs) cx + _kCellRodW + _kCellRodGapX];
    // 归属词带的行心 = 性别带 + 上留白 + 杆 + 下留白，再加归属词带的一半。
    final content = _kCellRodPadY + rodH + _kCellLabelPadY;
    return List<PunnettPlate>.unmodifiable(<PunnettPlate>[
      for (var i = 0; i < f.rows.length; i++)
        PunnettPlate(
          row: f.rows[i],
          centerY: _rowCenterY(i),
          sexLabelCenterY: _kRowsTop + i * rowPitch + sexLabelBand / 2,
          cellLabelCenterY:
              _kRowsTop + i * rowPitch + sexLabelBand + content + _kCellLabelBand / 2,
          headerRodCx: _kPadX + _kRowRodW / 2,
          cellXs: <({double maternalCx, double paternalCx})>[
            for (var j = 0; j < f.rows[i].cells.length; j++)
              (maternalCx: matCxs[j], paternalCx: patCxs[j]),
          ],
        ),
    ]);
  }

  @override
  void paint(Canvas canvas, Size size) {
    // 背景（照 lineage 那套：先铺近白底，导出 PNG 打印友好）。
    canvas.drawRect(Offset.zero & size, Paint()..color = canvasColor);

    // 按可用宽度等比缩放（⛔ 不固定像素宽，360 窄屏也不会溢出）。
    final s = size.width / SexLinkedPunnettDiagram.designWidth;
    canvas.save();
    canvas.scale(s);

    // ① 方格：外框 + 列分隔线 + 行分隔线。⛔ 颜色只用 [textColor] 的低透明度
    //    版本（不引入第 5 支色）；线画在**所有内容之下**，不压杆也不压字。
    //
    //    为什么它不是纯装饰：v2.19.161 第一版没有它，被目检判为「读不出方格结构」——
    //    「哪一行归哪个母亲的配子、哪一列归哪个父亲的配子」全靠学生自己猜。
    _grid(canvas);

    // 块标签：「母亲的配子」**居中于行头列**、「父亲的配子」**居中于方格**。
    // ⚠️ 居中而不是各自顶格左对齐：第一版两个标签都顶在左边、彼此只差几像素，
    //    录出来读成**一串连续的字**（「母亲的配子父亲的配子」），等于没分组。
    _blockLabel(canvas, kPunnettMotherLabel, (_kPadX + _kGridLeft - _kGridGapX) / 2);
    _blockLabel(canvas, kPunnettFatherLabel, (_kGridLeft + gridRight) / 2);

    // 列头：父亲的每一种配子（名字 + 杆）。⛔ 杆心 x 与格内「父亲那一条」相同。
    for (var j = 0; j < columnCount; j++) {
      final g = columnGametes[j];
      _textCentered(canvas, g.name, _paternalRodCx(j), columnNameCenterY);
      _rod(canvas, _paternalRodCx(j), columnRodCenterY, _kCellRodW, g);
    }

    // 每一行：行头（母亲的那一种配子）+ 每格「性别标注 + 两条杆 + 两条归属词」。
    for (var i = 0; i < plates.length; i++) {
      final plate = plates[i];
      _textLeft(canvas, plate.row.gamete.name, _kRowNameX, plate.centerY);
      _rod(canvas, plate.headerRodCx, plate.centerY, _kRowRodW, plate.row.gamete);
      for (var j = 0; j < plate.cellXs.length; j++) {
        final cell = plate.row.cells[j];
        // ② 性别标注：⛔ 由 [PunnettCell.sexLabel]（即 isDaughter）推出，
        //    写在格内两条杆的**正上方**，每格一个 ⇒ 不靠「哪条杆没色带」反推。
        _spanCentered(canvas, sexLabelSpan(cell),
            _kGridLeft + (j + 0.5) * _cellWidth,
            plate.sexLabelCenterY);
        _rod(canvas, plate.cellXs[j].maternalCx, plate.centerY, _kCellRodW,
            cell.maternal.gamete);
        _rod(canvas, plate.cellXs[j].paternalCx, plate.centerY, _kCellRodW,
            cell.paternal.gamete);
        // ③ 归属词：母亲 / 父亲，各写在**自己那条杆的正下方**（⛔ 不再只靠
        //    x 坐标对齐来表达归属 —— 第一版就是这么被目检打回的）。
        _cellLabel(canvas, cell.maternal, plate.cellXs[j].maternalCx,
            plate.cellLabelCenterY);
        _cellLabel(canvas, cell.paternal, plate.cellXs[j].paternalCx,
            plate.cellLabelCenterY);
      }
    }

    canvas.restore();
  }

  /// 画 Punnett 方格：外框 + 列分隔线 + 行分隔线。
  ///
  /// ⚠️ 颜色只用 [textColor] 的低透明度版本：`rodColor` 太浅（与画布只差一个色阶），
  ///    当格线看不见；而取 `AppColors.border` 会变成**第 5 支颜色**（本仓调色板每支
  ///    都带既定语义）⇒ 用 `textColor` 的 alpha 变体，与参考图里空心色带用
  ///    `bandColor.withValues(alpha: 0.16)` 是同一手法。
  void _grid(Canvas canvas) {
    final p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = _kGridStrokeW
      ..color = textColor.withValues(alpha: 0.22);
    canvas.drawRect(gridRect, p);
    for (final x in gridVerticalDividers) {
      canvas.drawLine(Offset(x, gridRect.top), Offset(x, gridRect.bottom), p);
    }
    for (final y in gridHorizontalDividers) {
      canvas.drawLine(Offset(gridRect.left, y), Offset(gridRect.right, y), p);
    }
  }

  /// 画一条染色体：杆身 + 它那一个位点的色带。
  ///
  /// ⛔ [PunnettGamete.upper] 为空（Y）时**一个色带都不画** —— 「Y 上没有位点」
  /// 是这条杆与一条 `Xa` 杆在图上的**唯一**区别，混起来就等于教「Y 上也有个
  /// 隐性基因」。
  void _rod(Canvas canvas, double cx, double cy, double w, PunnettGamete g) {
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(cx - w / 2, cy - rodH / 2, w, rodH),
        const Radius.circular(rodH / 2),
      ),
      Paint()..color = rodColor,
    );
    for (final upper in g.upper) {
      _locus(canvas, cx + (w - _kBandW) * _kLocusRatio, cy, upper: upper);
    }
  }

  /// 画一个位点的色带：实心 = 大写；空心 = 小写。
  void _locus(Canvas canvas, double cx, double cy, {required bool upper}) {
    final rr = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: Offset(cx, cy),
        width: _kBandW,
        height: _kBandH,
      ),
      const Radius.circular(2),
    );
    if (upper) {
      canvas.drawRRect(rr, Paint()..color = bandColor);
    } else {
      // 空心：小写等位基因 —— 极淡的底 + 描边，
      // 保证在深色档也看得见轮廓（⛔ 不用「比底色深一点」那种隐含假设）。
      canvas.drawRRect(rr, Paint()..color = bandColor.withValues(alpha: 0.16));
      canvas.drawRRect(
        rr,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.6
          ..color = bandColor,
      );
    }
  }

  /// 块标签。⚠️ [centerX] = 该标签**管辖的那一组**的中点（行头列 / 方格），
  ///   不是左边距 —— 两个标签顶格左对齐时会读成一串连续的字。
  void _blockLabel(Canvas canvas, String s, double centerX) {
    final tp = TextPainter(
      text: TextSpan(text: s, style: blockLabelTextStyle),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas,
        Offset(centerX - tp.width / 2, _kPadTop + (_kBlockLabelBand - tp.height) / 2));
  }

  void _textCentered(Canvas canvas, String s, double cx, double cy,
      {TextStyle? style}) {
    final tp = _painterOf(s, style);
    tp.paint(canvas, Offset(cx - tp.width / 2, cy - tp.height / 2));
  }

  void _textLeft(Canvas canvas, String s, double x, double cy,
      {TextStyle? style}) {
    final tp = _painterOf(s, style);
    tp.paint(canvas, Offset(x, cy - tp.height / 2));
  }

  /// 一条杆正下方的归属词（母亲 + 配子名）。
  ///
  /// ⚠️ 这是**一行里的两种字体**：归属词是中文 ⇒ 挂 [chineseTextStyle]（sans）；
  ///    配子名是基因型 ⇒ 挂 [gameteTextStyle]（mono）。两段**各自**显式声明
  ///    family（⛔ 不靠继承、⛔ 不给中文挂 mono），否则基线里中文变方框、而布局
  ///    按方框宽度算 ⇒ 基线对文案零敏感（假绿）。
  void _cellLabel(Canvas canvas, PunnettChromosome c, double cx, double cy) {
    _spanCentered(canvas, cellLabelSpan(c), cx, cy);
  }

  void _spanCentered(Canvas canvas, TextSpan span, double cx, double cy) {
    final tp = TextPainter(text: span, textDirection: TextDirection.ltr)
      ..layout();
    tp.paint(canvas, Offset(cx - tp.width / 2, cy - tp.height / 2));
  }

  /// 这一条杆正下方那一段文字的 `TextSpan`（**画上去的就是它**）。
  ///
  /// ⚠️ 暴露成公开成员不是为了方便，是给「归属标记**画出来了**吗」这条守卫一个
  ///    落点：守卫读的就是这里返回的 span，⛔ 不许断言一个只有测试里存在的标记。
  TextSpan cellLabelSpan(PunnettChromosome c) => TextSpan(children: <InlineSpan>[
        TextSpan(text: c.sourceWord, style: chineseTextStyle),
        TextSpan(text: c.gamete.name, style: gameteTextStyle),
      ]);

  /// 这一格「女儿 / 儿子」标注的 `TextSpan`（⛔ 文案由 [PunnettCell.sexLabel] 推，
  ///   即由 `isDaughter` 推，⛔ 不是这里手写的字面量）。
  TextSpan sexLabelSpan(PunnettCell c) =>
      TextSpan(text: c.sexLabel, style: chineseTextStyle);

  /// 把一个 span 真排一遍版，返回它的宽。
  ///
  /// ⚠️ 存在的理由：守卫要能证明「这段文字**真的被排版、真的画得出来**」，而不是
  ///    断言一个产品里存在但 `paint()` 没调用的字符串。测的是**宽度 > 0**
  ///    （即这段字确实有字形宽度），不是某个具体像素数。
  double measureSpan(TextSpan span) {
    final tp = TextPainter(text: span, textDirection: TextDirection.ltr)
      ..layout();
    return tp.width;
  }

  TextPainter _painterOf(String s, TextStyle? style) => TextPainter(
        text: TextSpan(text: s, style: style ?? gameteTextStyle),
        textDirection: TextDirection.ltr,
      )..layout();

  /// 配子名（`XA` / `Xa` / `Y`）的样式。
  ///
  /// ⚠️⚠️ **fontFamily 不是可选项**（与连锁那张图同源的实测坑）：
  ///   `CustomPainter` 里的 `TextPainter` **没有 BuildContext**、拿不到
  ///   `DefaultTextStyle`，所以一个不声明 family 的 `TextStyle` 不会「继承主题
  ///   字体」，而是直接落回 **flutter_tester 的引擎测试字体 FlutterTest** ——
  ///   那里每个字形都画成**实心方块**，而**布局是按方框宽度算的 ⇒ 这类基线对
  ///   文本内容零敏感，是假绿**（R10-5 图标 / R11-3 中文 / R12-1 基因型 /
  ///   连锁那张图第 4 轮，同一个坑的第 4 次出现）。
  ///   `test/golden_fonts.dart` 装载的是「PingFang SC」/「JetBrains Mono」/
  ///   「Consolas」三个**具名** family，没被具名命中的一个都取不到。
  ///
  /// 选 **mono**：基因型与等位基因标识本仓一律挂 `AppFonts.mono`
  /// （`AppText.genotype` / `monoSmall`），这里必须与它们同族，否则同一屏上两种
  /// 字母风格并存。⚠️ 家族名必须与 `test/golden_fonts.dart` 装载时的名字**逐字
  /// 一致**（R12-1 实测「注册成 Consolas、primary 仍写 JetBrains Mono」无效）。
  TextStyle get gameteTextStyle => TextStyle(
        fontFamily: AppFonts.mono,
        fontFamilyFallback: AppFonts.monoFallback,
        fontSize: _kGameteFontSize,
        fontWeight: FontWeight.w600, // 与 AppText.genotype 的字重一致
        color: textColor,
      );

  /// 中文通路（块标签 / 性别标注 / 归属词）的样式。
  ///
  /// ⚠️⚠️ 为什么中文**不能**挂 `AppFonts.mono`：
  ///   `AppFonts.monoFallback` 是 `['Consolas', 'Menlo', 'monospace']`，
  ///   **一支都没有汉字**；而 `test/golden_fonts.dart` 的文件头（R12-1 实测）写明：
  ///   flutter_tester 里 primary family 没装载时引擎**根本不去查
  ///   `fontFamilyFallback`**，直接落回 FlutterTest 方框字体 ⇒ 中文在基线里会变成
  ///   方框，**而且布局按方框宽度算 ⇒ 基线对文案零敏感，又是假绿**。
  ///   ⇒ 中文挂 [AppFonts.sans]（= `'PingFang SC'`，正是
  ///     `loadGoldenFonts(cjk: true)` 装载的那个名字）。
  ///
  /// ⚠️ 块标签（「母亲的配子」）比它小一号：它是块头不是正文；但 ⛔ **两者都不得
  ///   低于 [minFontSize]**（P3 守卫钉住，见版面注释里「不许压扁」那条）。
  TextStyle get chineseTextStyle => TextStyle(
        fontFamily: AppFonts.sans,
        fontFamilyFallback: AppFonts.sansFallback,
        fontSize: _kChineseFontSize,
        fontWeight: FontWeight.w600,
        color: textColor, // ⛔ 第 4 种颜色；不许再取一支灰
      );

  /// 块标签比格内中文小一号（块头 vs 正文）。
  TextStyle get blockLabelTextStyle => chineseTextStyle;

  /// 格内中文通路的字号（性别标注与归属词用），供守卫读。
  double get chineseFontSize => _kChineseFontSize;

  /// 配子名的字号，供守卫读。
  double get gameteFontSize => _kGameteFontSize;

  @override
  bool shouldRepaint(covariant PunnettPainter old) =>
      old.figure != figure ||
      old.canvasColor != canvasColor ||
      old.rodColor != rodColor ||
      old.bandColor != bandColor ||
      old.textColor != textColor;
}
