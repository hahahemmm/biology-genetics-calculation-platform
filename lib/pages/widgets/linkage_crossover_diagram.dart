// linkage_crossover_diagram.dart —— 连锁互换概念示意图（**代码绘制**，非位图）
//
// ## 为什么是代码绘制而不是生成位图
//
// 本项目试过生成位图并**目检否决**：它把交换点画成**两条非同源染色体的横杆
// 交叉**——减数分裂的互换必须发生在**同源染色体的非姐妹染色单体之间**，那是有
// 生物学错误的画法，对教学工具比没有图更糟。
// ⛔ 但**不是所有图都不该生成**：`phenotype_gallery` 的 4 张豌豆就是
// `generate_image` 生成的且通过了目检。判据是「**结构关系是否必须逐条成立**」：
// 实物 / 纹理 / 材质可以用生成模型；结构示意必须代码绘制。
//
// ## 核心简化：配子就是那 4 条染色单体
//
// 减数第一次分裂后，**每条染色单体成为一个配子**。所以 ⛔ **不另画一排
// 「配子胶囊」** —— 画完交换后的那 4 条染色单体，**它本身就是 4 个配子**。
// 这样「重组型为什么是重组型」在图上自带答案：没参与交换的两条就是亲本型，
// 参与交换的那两条左右两段换过、就是重组型。
//
// ## ⛔ 本轮（v2.19.161）：从「硬编码」升级成「数据驱动」
//
// 上一版把顺式两座（`AB/ab`）**写死在两个枚举里**（`CrossingChromatid` /
// `CrossoverBeforeChromatid`），于是**反式（`Ab/aB`）、三位点、`r = 0`
// 三类真实输入要么画错、要么被宿主的闸门硬挡掉**。本轮把枚举删掉，改成
// 调用方只传一个值对象 [CrossoverFigure]，图上**每一条色带、每一个编号、
// 「是否参与交换」全部由这份数据推导**。⛔ 组件里**不再有任何 `AB`/`ab`/
// `Ab`/`aB` 字面量**。
//
// ### 「参与交换」的推导规则（逐条；守卫落在这些**公开**成员上）
//
// 记两条亲本单倍型为 `hap1` / `hap2`（位点数 = `hap1.length` = 2 或 3），
// 减数分裂时每条同源染色体复制出两条**姐妹染色单体** ⇒ 一共 4 条。
//
// ① **一次单交换的产物**（`CrossoverFigure.recombinant1/2`，i = 0…位点数-2，
//    即「在第 i 位与第 i+1 位之间发生交换」）：
//      recombinant1 = hap1[0..i] + hap2[i+1..]   （前段取 hap1 ⇒ 同源染色体 1）
//      recombinant2 = hap2[0..i] + hap1[i+1..]   （前段取 hap2 ⇒ 同源染色体 2）
// ② **一条染色单体属于哪条同源染色体** = 它等于是 hap1 / hap2 本身
//    （`== hap1` ⇒ 1，`== hap2` ⇒ 2）**或**它是上面哪一种重组产物；
//    四条都不匹配 ⇒ 调用方给了对不上的数据 ⇒ **抛错**（画错不如炸）。
// ③ **是否参与交换** = 「它不是 hap1 也不是 hap2」。⛔ **这是推出来的**：
//    [CrossoverFigure] 上**没有任何 bool 字段**，`CrossoverChromatid.participated`
//    在构造时算出来。理由见下。
// ④ **编号**（`1a`/`1b`/`2a`/`2b`）= 同源染色体号 + 后缀；后缀 `a` 给
//    **参与了交换**的那条（它的左右两段换过），`b` 给没参与的那条。
// ⑤ **行序**：没参与的先（1 号、2 号），参与的随后（1 号、2 号）
//    ⇒ 顺式与反式拿到的都是 `1b / 2b / 1a / 2a` 四行，**两块的行位一一对齐**
//    这件事与「顺式还是反式」无关。
//
// ### ⛔ 为什么「是否参与交换」必须是推出来的，而不是传进来的
//
// 第一版让调用方传一个 `participated` 布尔。那等于**把判断责任推回调用方**
// —— 而调用方（`linkage_tab.dart`）正是本轮要修的地方：它得自己判断
// 「哪条是重组型」，一旦判错，图就在教一件不成立的事，而**图自己毫无察觉**。
// 规则①③把判断收进图里：图是**唯一**知道「单交换的产物长什么样」的地方，
// 而这件事**逐字等同于引擎 `gametesOf` 的算法**（`linkage_engine.dart:155-158`
// 与 :168-171），两处同源。
//
// ### ⛔ `r = 0` 的诚实处理（**不给图**，外加组件兜底）
//
// `r = 0` 时引擎 `out.removeWhere(isZero)` 把重组型删掉了 ⇒ **那次交换概率为 0**。
// 宿主（`linkage_tab.dart` 的 `_crossoverFigure`）在 `r = 0` 时**返回 null、
// 不挂这张图**：⛔ **不许画一张声称发生了交换的图**。
// 为什么选「不给图」而不是「给一张空的对照图」：这张图**存在的唯一理由**是
// 解释「重组型是怎么来的」；没有重组型时它只剩两块重复的色带，学生看见一张
// 结构完整、内容为空的图，比看不见更容易误以为「有四行却什么都没发生」。
// ⇒ **诚实 = 这一题上没有重组型可解释，所以不解释。**
//
// 组件侧**另有一道兜底**（防将来有人绕过宿主直接挂它）：若真有人把一组
// 「谁都没参与交换」的数据喂进来（例如 `afterGametes` 全是亲本单倍型），
// 图会 ⛔ **不出「交换后」而说「未发生交换」**（`hasCrossover == false` ⇒
// 块标签换成 [kCrossoverNoExchangeLabel]、语义标签明说「没有重组型」），
// 而不是照旧渲染一个空壳「交换后」块。
//
// ### ⛔ 位点数：**只画 2 个位点**（不是 3 个位点画不出，是「6 条染色单体」不存在）
//
// `parseParent`（engine:105）只收**两条**单倍型 ⇒ 一次减数分裂里**只有
// 4 条染色单体**，与位点数无关。三位点时 `gametesOf` 出 **6 个键**
// （engine:164-172：2 亲本 + 2 个区间 × 2），但那 6 个是**不同减数分裂里
// 各自可能出现的 6 种配子**（教学口径「只算一次互换」下的集合），**不是同一次
// 减数分裂里的 6 条染色单体**：第 1 区间交换与第 2 区间交换发生在**不同的
// 减数分裂**里，各有自己的交换前形态。⇒ 把它们画成「上下两块各 6 行、每行一条
// 染色单体」就是**教一件不存在的事**（一次减数分裂里没有第 3 条同源染色单体），
// 且「交换前」那一行对第 3、4 种重组型**根本没有定义**。⇒ 本轮**不画**三位点，
// 宿主在闸门里挡掉；组件本身对 3 个位点仍然可用（每条 3 个色带、几何不挤），
// 但**没有任何调用方会那样调它**。
//
// ## 基因座的编码约定
//
// · **实心带 = 大写等位基因**（该位点是大写字母）
// · **空心带 = 小写等位基因**（该位点是小写字母）
// · 重组型（参与了交换的那两条）**不需要额外的记号**——它们的「一实一空」
//   混合带本身就是证据。⚠️ 第一版在参与交换的两行下画了一道 `AppColors.select`
//   的短刻痕，**已删**，理由记在下面那段「为什么没有记号」里。
//
// ## 纯概念图 ⇒ ⛔ 不印任何数字/百分比
//
// 具体比例属于**软件算出来**的东西，由结果区的依据行负责
// （依据行只描述「软件算出了什么」）。⚠️ 「交换前」那块尤其不许印
// 「交换率」——交换率是算出来的量，不是这张概念图讲的东西。
// ⚠️ 编号（`1a` / `2b`）与基因型（`AB` / `Ab`）是**点名对象**，不是数值，不在此列。
//
// ## ⛔ 禁红
//
// 本仓 `AppColors.lethal` 红 = **致死**语义（纯合/杂合模型在用），
// 把红画在「交换」上会与产品既有语义撞车。
//
// ## ⚠️ 为什么图上**没有**「参与了交换」的记号（实测后删掉的）
//
// 第一版给参与交换的两行（1a / 2a）在杆下画了一道 `AppColors.select` 短刻痕。
// 录出基线后目检，**两个字都不合格**：
//
// ① **语义撞车**：`selectL = #9A3412`（深琥珀陶土）与 `lethalL = #B91C1C`
//    （致死/错误红）是**相邻色相**。10 米投影上学生只会读成「红 = 死」。
//    ⇒ 躲开 `lethal` 换到 `select` **并没有解决问题**，只是换了一支同样红的。
//
// ② ⛔ **更根本：它不携带任何信息**。参与交换的**恰好就是**那两行，
//    而那两行**已经**被「同一编号的交换前 / 交换后对照」区分出来了。
//    ⇒ 记号是**纯装饰**，与「空胶囊 = 装饰，色带才 = 证据」是同一条判据。
//    删掉它，图反而更清楚，语义撞车归零。
//
// ⚠️ **上一版这条注释里的「一实一空」只对顺式成立**（它写死了顺式两座）。
// 数据驱动之后才发现：反式 `Ab/aB` 时**亲本型才是「一实一空」**，
// 而重组型 `AB`/`ab` 是「两实」与「两空」—— ⛔ 所以「一实一空 = 重组型」
// **不是**通用判据，通用判据只有两条：
//   · 重组型**恰好**是 hap1/hap2 在某一位点之后对调的产物（数据侧推出来）；
//   · 同一编号在「交换前」「交换后」两块的实空状态**逐位对照**，
//     **恰好两行**前后不同。
// ⇒ 这也说明「参与交换」一旦改成数据推导，原来那些**跟着顺式走的视觉约定**
//   必须一起改口径，否则反式那张图就会靠一个假约定讲因果。
//
// ⇒ **判据**：要往图上加一个元素，先问「它说的这件事，别的元素说不说不出来」。
//    说不出来 ⇒ 才是证据；说得出来 ⇒ 删掉，否则它只是在图上多占一处颜色语义。
//
// ────────────────────────────────────────────────────────────────────
// ## 版面：上下堆叠的「交换前 / 交换后」两块
//
// 设计尺寸 **320 × 367**。⛔ **宽度不加宽**（360 窄屏不许溢出），
// 加高的全部来源是**标签带**，不是把行距/字号/杆身压小 ——
// `_kRowH` 26 / `_kRowGap` 11（行距 37）、`_kRodH` 12、`_kBandH` 20、
// `_kBandW` 9、`_kIdW` 30、`_kGameteW` 42、行内字号 12
// **全部沿用第一版，一个都没动**。数据驱动之后**也没有动**（见下面的
// 「为什么位点数变了也不用改版面」）。
//
// | 元素                 | y 区间（设计坐标）            |
// |----------------------|-------------------------------|
// | 块标签「交换前」       | 18 … 34                      |
// | 交换前 4 行行区        | 42 … 179（行心 55/92/129/166）|
// | 块标签「交换后」       | 193 … 209                    |
// | 交换后 4 行行区        | 217 … 354（行心 230/267/304/341）|
// | 下边距                | 354 … 367                    |
//
// 两块之间的偏移 175 = 行区高 137 + 块间距 14 + 标签带 24。
// 175 不是 37 的整数倍，但**每块内部**的行距仍是 37 ⇒ 两块的「行 → 编号」
// 映射完全同构，这就是行位对齐的根据。
//
// ### 为什么位点数变了也不用改版面
//
// 4 条染色单体是**同源染色体的条数**决定的（2 条 × 2 姐妹），**与位点数无关**
// ⇒ 行数恒为 4 + 4 = 8，版面一个字都不用改。位点数只改**每条杆上色带的个数**
// 与它们的横向位置（[CrossoverPainter.locusRatios]）。
//
// ### 为什么「上下堆叠 + 行位对齐」就是全部教学点
//
// 两块的**行序相同**（`1b / 2b / 1a / 2a`）、x 几何也逐字相同
// （同一份 `_kIdW` / `_kGameteW` / `locusRatios`）⇒
// 交换前 `1a` 与 `1b` **完全相同**、`2a` 与 `2b` **完全相同**；
// 交换后**恰好两条**（后缀 a 的那两条）变成重组型。
// ⇒ **因果全靠对照说清楚，一个记号都不需要** —— 这也正是上面那条判据
// 在这块上的应用：任何「哪一行参与了交换」的箭头/刻痕/高亮都是纯装饰。
//
// ### 「交换前」块为什么不标配子名
//
// 配子是**减数第一次分裂之后**才有的东西，交换前还没有配子。
// ⛔ 所以「交换前」的行在**数据层就没有 `gamete`**（恒 null）——
// 做成「有值但画的时候不画」等于给自己留后门：哪天有人图省事把它画出来，
// 图就在教一件不存在的事。守卫也从数据侧钉住这一点。
// ────────────────────────────────────────────────────────────────────
// 【本仓移植注记（v2.19.40，本文件自备份仓逐段搬入）】
// · 引擎侧逐字相同：`lib/engine/linkage_engine.dart` 与来源仓**字节级一致**，
//   上面所有 `engine:105 / :155-158 / :164-172 / fraction.dart` 的行号引用
//   在本仓**依然成立**（移植时逐条核对过）。
// · 下面 `_deriveChromatids` 里那段关于 markdown 星号的注释提到的
//   `on_screen_star_literal_guard_test` 是**来源仓**的全仓字面量守卫；
//   本仓目前**没有**那条测试 ⇒ 判据（报错串里不许出现 `**`）本身仍然成立，
//   守护它的是本文件的测试里「屏上文案禁星号」那条断言。

import 'package:flutter/material.dart';

import '../../theme.dart';

/// 一次单交换的产物①：前段取 [a]、后段取 [b]（交换点在第 [i] 位与第 i+1 位之间）。
///
/// [i] = 0 即两个位点之间那次经典交换。⛔ 这是**推导用的公式，不是数据**：
/// 组件与守卫都从它出发，绝不各自手抄一遍。
String recombinant1(String a, String b, int i) =>
    a.substring(0, i + 1) + b.substring(i + 1);

/// 一次单交换的产物②：前段取 [b]、后段取 [a]。
String recombinant2(String a, String b, int i) =>
    b.substring(0, i + 1) + a.substring(i + 1);

/// 按「实心带 = 大写 / 空心带 = 小写」把等位基因串拆成逐位点的大写标志。
List<bool> _upperFlags(String gamete) => <bool>[
      for (var i = 0; i < gamete.length; i++)
        gamete.codeUnitAt(i) >= 0x41 && gamete.codeUnitAt(i) <= 0x5A, // 'A'..'Z'
    ];

/// 图上的一条染色单体（**由 [CrossoverFigure] 推导出来的**，不是调用方传的）。
///
/// 字段与真值一一对应：一次减数分裂里同源染色体 1 的两条姐妹染色单体
/// （`1a` / `1b`）都携带 `hap1`，同源染色体 2 的两条都携带 `hap2`；
/// 交换之后，其中**每条同源染色体各有一条**（后缀 a）左右两段换过 ⇒ 重组型。
class CrossoverChromatid {
  const CrossoverChromatid({
    required this.id,
    required this.homolog,
    required this.gamete,
    required this.parentalGamete,
    required this.participated,
  });

  /// 染色单体编号（`1a` / `1b` / `2a` / `2b`）。点名对象，不说「上面那条」。
  final String id;

  /// 1 或 2：属于第几条同源染色体。
  final int homolog;

  /// 交换**之后**这条染色单体携带的配子串。
  final String gamete;

  /// 交换**之前**这条染色单体携带的单倍型（同源染色体 1 ⇒ [CrossoverFigure.hap1]）。
  final String parentalGamete;

  /// 是否参与了交换。⛔ **推出来的**（见文件头规则①③），不是调用方传的。
  final bool participated;

  /// 交换后逐位点：大写 = 实心带。
  List<bool> get upper => _upperFlags(gamete);

  /// 交换前逐位点：大写 = 实心带。
  List<bool> get parentalUpper => _upperFlags(parentalGamete);
}

/// 连锁互换概念图的数据。⛔ **只传结构化数据，不传布尔标志。**
///
/// 调用方要给的只有三样：两条亲本单倍型 + 交换后每条染色单体携带的配子串。
/// 「哪条是亲本型」「哪条参与了交换」「编号怎么排」「每行几座、实心还是空心」
/// 全部由本类推导（规则见文件头）。
class CrossoverFigure {
  CrossoverFigure({
    required this.hap1,
    required this.hap2,
    required List<String> afterGametes,
  }) : afterGametes = List<String>.unmodifiable(afterGametes) {
    // ⛔ 这些前提不是「礼貌检查」，是**图能画对的前提**。违反其中任何一条，
    //    图就会说一件不成立的事（见文件头「为什么必须是推出来的」）。
    assert(hap1.length == hap2.length,
        '两条亲本单倍型必须等长：$hap1 / $hap2');
    assert(hap1.length >= 2, '至少两个位点才谈得上「之间发生交换」：$hap1');
    assert(hap1 != hap2,
        '两条亲本单倍型相同（$hap1）⇒ 配子只有一种，'
        '「哪条同源染色体 / 是否重组」都没有定义，图会画错');
    assert(this.afterGametes.length == 4,
        '一次减数分裂里同源染色体 2 条 × 姐妹染色单体 2 条 = 4 条染色单体，'
        '实际收到 ${this.afterGametes.length} 条：${this.afterGametes}');
    assert(
        this.afterGametes.every((g) => g.length == hap1.length),
        '每条配子串都必须与亲本等长（${hap1.length} 位点）：${this.afterGametes}');
    // ⛔ **构造即校验**（不是 `late` 懒算）：推导规则③④⑤ 里有「抛错」那条路
    //    （对不上的数据、两条参与者来自不同交换区间、超过 2 条参与…）——
    //    懒算会让「数据不合法」这件事推迟到 build() 之后才炸，那时已经是屏上
    //    的半个红屏。宁可构造时就炸。
    chromatids = _deriveChromatids();
  }

  /// 第一条同源染色体携带的单倍型（如顺式两座的 `AB`、反式的 `Ab`）。
  final String hap1;

  /// 第二条同源染色体携带的单倍型（如 `ab` / `aB`）。
  final String hap2;

  /// 交换后 4 条染色单体各自携带的配子串。
  ///
  /// ⚠️ 顺序**不影响**结果（[chromatids] 会按规则⑤重排），但内容必须与
  ///    [hap1] / [hap2] 对得上，否则推导会抛错 —— 宁可炸也不画错。
  final List<String> afterGametes;

  /// 位点数（= 2 或 3）。
  int get locusCount => hap1.length;

  /// 4 条染色单体，**顺序就是绘制顺序**（规则⑤）。
  ///
  /// ⛔ 在**构造器体里**赋值（不是 `late` 懒算）：推导里那几条「宁可炸」的
  ///    校验必须发生在**构造时**，而不是等谁第一次读它。
  late final List<CrossoverChromatid> chromatids;

  /// 有没有发生交换（= 存在参与了交换的染色单体）。
  ///
  /// 宿主在 `r = 0` 时根本不挂这张图；这条是**组件侧的兜底**（文件头
  /// 「`r = 0` 的诚实处理」）：万一流进来一组「谁都没参与」的数据，
  /// 图会改说「未发生交换」，⛔ 绝不照旧渲染一个空壳「交换后」块。
  bool get hasCrossover => chromatids.any((c) => c.participated);

  /// 全部可能的重组型（每个可交换位点之后各两个），供守卫与调用方核对。
  Set<String> get recombinantCandidates => <String>{
        for (var i = 0; i < locusCount - 1; i++) ...<String>{
          recombinant1(hap1, hap2, i),
          recombinant2(hap1, hap2, i),
        },
      };

  /// 推导 [chromatids]（构造器体里调用，见上面「构造即校验」那条注释）。
  ///
  /// ⚠️ 下面的步骤编号是**本方法的**步骤，与文件头那五条**推导规则**编号
  ///    不是同一套 —— 头里那五条是「规则」，这里是「按什么顺序执行」。
  List<CrossoverChromatid> _deriveChromatids() {
    // 步骤 1 逐条染色单体：按文件头规则②③ 定出「属于哪条同源染色体」
    // 与「是否参与交换」。
    final raw = <_RawChromatid>[];
    for (var k = 0; k < afterGametes.length; k++) {
      final g = afterGametes[k];
      int? homolog;
      var participated = true;
      if (g == hap1) {
        homolog = 1;
        participated = false; // 规则③：没参与 ⇒ 就是亲本型本身
      } else if (g == hap2) {
        homolog = 2;
        participated = false;
      } else {
        for (var i = 0; i < locusCount - 1; i++) {
          if (g == recombinant1(hap1, hap2, i)) {
            homolog = 1;
            break;
          }
          if (g == recombinant2(hap1, hap2, i)) {
            homolog = 2;
            break;
          }
        }
        if (homolog == null) {
          // 规则②：四条都不匹配 ⇒ 调用方给了对不上的数据。画错不如炸。
          throw StateError(
              '配子 $g 既不是亲本单倍型 $hap1 / $hap2，'
              '也不是这两条之间任一位点之后单交换的产物（位点数=$locusCount）');
        }
      }
      raw.add(_RawChromatid(g, homolog, participated, k));
    }

    // 步骤 2 行序（文件头规则⑤）：没参与的先（1 号、2 号），参与的随后（1 号、2 号）。
    raw.sort((a, b) {
      final c = (a.participated ? 1 : 0).compareTo(b.participated ? 1 : 0);
      if (c != 0) return c;
      final d = a.homolog.compareTo(b.homolog);
      return d != 0 ? d : a.inputIndex.compareTo(b.inputIndex);
    });

    // 步骤 3 ⛔ 一次减数分裂只可能有一处交换：参与的那两条必须是**同一处交换**的
    //    那一对**非姐妹**染色单体（各属一条同源染色体）。传进来的数据若违反
    //    这一条，图就会在同一格子里说「两处交换」或「姐妹染色单体互相交换」
    //    —— 宁可炸，也不画。
    final on = raw.where((r) => r.participated).toList();
    if (on.length > 2) {
      throw StateError('一次减数分裂里只有 2 条染色单体参与交换，实际收到 ${on.length} 条：'
          '${on.map((r) => r.gamete).toList()}');
    }
    if (on.length == 2) {
      if (on[0].homolog == on[1].homolog) {
        throw StateError('参与交换的 ${on[0].gamete} 与 ${on[1].gamete} '
            '属于同一条同源染色体（姐妹染色单体之间不发生交换）');
      }
      var sameInterval = false;
      for (var i = 0; i < locusCount - 1 && !sameInterval; i++) {
        final a1 = recombinant1(hap1, hap2, i);
        final a2 = recombinant2(hap1, hap2, i);
        sameInterval = (on[0].gamete == a1 && on[1].gamete == a2) ||
            (on[0].gamete == a2 && on[1].gamete == a1);
      }
      if (!sameInterval) {
        // ⛔ 报错串里不许有 markdown 星号：`**` 是「关于」页**上屏**文案的加粗
        //    写法（那里由 `_featureRow` 真的渲染成粗体），而这里是
        //    `StateError` 的消息，**永远不会被渲染**。`＊＊` 出现在非上屏语境
        //    只会顶红 `on_screen_star_literal_guard_test`（它扫全 `lib/`
        //    的字面量，命中集必须**恰好等于**显式白名单，两个方向都判）。
        //    ⇒ 正确写法是**去掉**，⛔ 不是登记白名单：报错的读者在日志里，
        //    不需要粗体。
        throw StateError('参与交换的 ${on[0].gamete} 与 ${on[1].gamete} '
            '来自不同的交换区间（$hap1/$hap2 共 ${locusCount - 1} 个可交换位点）：'
            '一次减数分裂只发生一次交换，图不能在同一次分裂里说两处');
      }
    }

    // 步骤 4 编号（文件头规则④）：同源染色体号 + 后缀（a = 参与交换的那条，
    //    b = 没参与的）。
    //    ⚠️ 编号在**每条同源染色体内部**发（参与的那条先拿 a），
    //    发出顺序与行序（步骤 2）不是一回事 —— 别把两步合成一步。
    final ids = <int, String>{};
    for (final h in const <int>[1, 2]) {
      final group = raw.where((r) => r.homolog == h).toList()
        ..sort((a, b) {
          final c = (b.participated ? 1 : 0).compareTo(a.participated ? 1 : 0);
          return c != 0 ? c : a.inputIndex.compareTo(b.inputIndex);
        });
      assert(group.length <= 2,
          '同源染色体 $h 上不该有多于 2 条染色单体（姐妹染色单体只有两条）');
      for (var j = 0; j < group.length; j++) {
        ids[group[j].inputIndex] = '$h${'ab'[j]}';
      }
    }

    // 步骤 5 按行序（步骤 2）发出。
    return List<CrossoverChromatid>.unmodifiable(raw.map((r) => CrossoverChromatid(
          id: ids[r.inputIndex]!,
          homolog: r.homolog,
          gamete: r.gamete,
          parentalGamete: r.homolog == 1 ? hap1 : hap2,
          participated: r.participated,
        )));
  }

  @override
  String toString() => 'CrossoverFigure($hap1/$hap2, $afterGametes)';

  @override
  bool operator ==(Object other) =>
      other is CrossoverFigure &&
      other.hap1 == hap1 &&
      other.hap2 == hap2 &&
      other.afterGametes.length == afterGametes.length &&
      List<String>.generate(
              afterGametes.length, (i) => afterGametes[i])
          .join('/') ==
          afterGametes.join('/');

  @override
  int get hashCode => Object.hash(hap1, hap2, afterGametes.join('/'));
}

/// 推导过程中的中间态（不进公开 API）。
class _RawChromatid {
  _RawChromatid(this.gamete, this.homolog, this.participated, this.inputIndex);

  final String gamete;
  final int homolog;
  final bool participated;
  final int inputIndex;
}

/// 图上一行染色单体（= 一块里的一行），供守卫逐条读。
///
/// ⚠️ 为什么把行数据做成公开的类：[rows] 里每一行的 [centerY] 就是
///    `paint()` 真正画在哪儿，守卫读它等于读**画上去的东西**；
///    如果让测试自己重抄一遍 `top + i * pitch + h/2` 的公式，
///    那只能证明「测试里的算式自洽」，证明不了 painter 画在了那儿
///    —— 本项目在这类「重抄公式」上栽过（R10-5 图标 / R11-3 中文 / R12-1 基因型）。
class CrossoverRow {
  const CrossoverRow({
    required this.chromatid,
    required this.upper,
    required this.alleles,
    required this.gamete,
    required this.centerY,
    required this.before,
    required this.participated,
  });

  /// 编号：`1a` / `1b` / `2a` / `2b`（⛔ 不写死字面量，由 [CrossoverFigure] 推）。
  final String chromatid;

  /// 逐位点：大写 = 实心带。长度 = 位点数。
  final List<bool> upper;

  /// 这一行携带的等位基因串（交换前 = 亲本单倍型，交换后 = 配子串）。
  final String alleles;

  /// 右端配子名。⛔ **「交换前」的行恒为 null**（那时还没有配子）。
  final String? gamete;

  /// 行心 y（设计坐标，⛔ 不含按可用宽度的缩放）。
  final double centerY;

  /// 是否属于「交换前」块。
  final bool before;

  /// 是否参与了交换。⛔ **「交换前」的行恒为 false** ——
  /// 「有没有参与交换」是交换**之后**才成其为事实的说法（见
  /// [CrossoverChromatid.participated]）。
  final bool participated;

  /// 位点数（= 本行色带个数）。
  int get locusCount => upper.length;
}

/// 「交换前」块标签。⚠️ 这是**屏上文案**。
const String kCrossoverBeforeLabel = '交换前';

/// 「交换后」块标签。⚠️ 这是**屏上文案**。
const String kCrossoverAfterLabel = '交换后';

/// 一次交换都没发生时**替换掉** [kCrossoverAfterLabel] 的块标签。
///
/// ⚠️ 存在的理由不是「文案更好听」，是 ⛔ **不许画一张声称发生了交换的图**：
/// 全连锁（`r = 0`）时那次交换概率为 0，块头还写「交换后」就是在教一件
/// 没发生的事（见文件头「`r = 0` 的诚实处理」）。
const String kCrossoverNoExchangeLabel = '未发生交换';

/// 连锁互换概念示意图：「交换前」与「交换后」两块**上下堆叠、行位对齐**。
class LinkageCrossoverDiagram extends StatelessWidget {
  const LinkageCrossoverDiagram({super.key, required this.figure});

  /// 这张图讲的是**哪一次**交换（⛔ 结构化数据，无布尔标志）。
  final CrossoverFigure figure;

  /// 设计尺寸（逻辑像素）。实际按**可用宽度等比缩放**，⛔ 不固定像素宽。
  ///
  /// ⛔ **宽度保持 320 不加宽** —— 360 窄屏不许溢出。
  /// 高度 367 = 上边距 18 + 2 × 块高 161 + 块间距 14 + 下边距 13，
  /// 块高 161 = 标签带 16 + 标签下留白 8 + 行区 137（4×26 + 3×11）。
  /// 每块的 y 偏移见文件头「版面」那张表。
  ///
  /// ⚠️ 高度**与位点数无关**：染色单体条数 = 同源染色体数 × 2 = 恒 4
  ///（见文件头「为什么位点数变了也不用改版面」）。
  static const double designWidth = 320;
  static const double designHeight = 367;

  @override
  Widget build(BuildContext context) {
    // ⛔ AppColors 的 token 是 **getter**，亮度由 main.dart 顶层 build 调
    // AppColors.sync 切换 ⇒ 在这里**取值**再传给 painter，
    // ⛔ 不让 painter 自己去读（照 lib/charts/pedigree_chart.dart 的形状）。
    final teal = AppColors.teal;
    return Semantics(
      label: semanticsLabel(figure),
      child: RepaintBoundary(
        child: SizedBox(
          width: double.infinity,
          child: AspectRatio(
            aspectRatio: designWidth / designHeight,
            child: CustomPaint(
              painter: CrossoverPainter(
                figure: figure,
                canvasColor: AppColors.canvas,
                rodColor: AppColors.surfaceLow,
                bandColor: teal,
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
  /// ⛔ 三条硬规矩：禁 markdown 星号（屏幕阅读器会念出来）；禁方向词
  ///   （不说「上面那条」——位置在读屏里既错又不稳定，要点名对象）；
  ///   不印任何数字/百分比（比例是**算出来**的东西，由结果区的依据行负责）。
  ///   「交换前」「交换后」「未发生交换」是**点名状态**，不是方向词，可以用；
  ///   两块的关系靠**状态名**说，不靠「上面那块」这种位置说。
  static String semanticsLabel(CrossoverFigure f) {
    final cs = f.chromatids;
    final buf = StringBuffer();
    // ⛔ 条数用**汉字**（`_cn`），⛔ 不印阿拉伯数字：这张图是纯概念图，
    //    屏上一个数字都容易被读成「某个算出来的量」。
    buf.write('连锁互换的前后对照，交换前与交换后是同一组${_cn(cs.length)}条染色单体，'
        '编号次序相同。');
    // 交换前：同一同源染色体的两条姐妹染色单体完全相同（它们还没分开过）。
    for (final h in const <int>[1, 2]) {
      final g = cs.where((c) => c.homolog == h).toList();
      if (g.isEmpty) continue;
      buf.write('交换前：${g.map((c) => c.id).join(' 与 ')} 完全相同，'
          '都是${_bands(g.first.parentalUpper)}；');
    }
    buf.write('交换前还没有配子，所以只标染色单体编号。');
    // 交换后：没参与的 vs 参与的，两类都点名。
    final not = cs.where((c) => !c.participated).toList();
    final yes = cs.where((c) => c.participated).toList();
    if (not.isNotEmpty) {
      buf.write('交换后：${not.map((c) => c.id).join(' 和 ')} 没有参与交换，'
          '配子分别是 ${not.map((c) => c.gamete).join(' 和 ')}；');
    }
    if (yes.isNotEmpty) {
      buf.write('${yes.map((c) => c.id).join(' 和 ')} 参与了交换，'
          '基因座之间的左右两段换过，'
          '配子分别是 ${yes.map((c) => c.gamete).join(' 和 ')}，它们就是重组型。');
    } else {
      buf.write('没有任何一条染色单体参与交换，交换前后完全相同，也没有重组型。');
    }
    // 逐条对照：同一编号的交换前 / 交换后。
    for (final c in cs) {
      buf.write('${c.id} 交换前是${_bands(c.parentalUpper)}，'
          '交换后是${_bands(c.upper)}；');
    }
    buf.write('实心色带是大写等位基因，空心色带是小写等位基因。');
    return buf.toString();
  }

  static String _bands(List<bool> upper) =>
      upper.map((u) => u ? '实心' : '空心').join('加');

  /// 1…8 的汉字写法（⛔ 语义标签里不许出现阿拉伯数字）。
  static String _cn(int n) => const <String>[
        '零',
        '一',
        '二',
        '三',
        '四',
        '五',
        '六',
        '七',
        '八',
      ][n];
}

/// 交叉互换示意图的 painter。
///
/// 照 `lib/charts/pedigree_chart.dart` 的 `PedigreeChartPainter` 形状：
/// 颜色**全部由构造器传入**，`paint()` 第一件事铺近白底。
/// 图上的**内容**则全部由 [figure] 推导 —— ⛔ 这里没有任何基因型字面量。
class CrossoverPainter extends CustomPainter {
  CrossoverPainter({
    required CrossoverFigure figure,
    required this.canvasColor,
    required this.rodColor,
    required this.bandColor,
    required this.textColor,
  })  : figure = figure,
        rows = _buildRows(figure);

  /// 本图讲的是哪一次交换（行数据由它推导，⛔ 不是这里现算的）。
  final CrossoverFigure figure;

  final Color canvasColor;
  final Color rodColor;
  final Color bandColor;
  final Color textColor;

  /// 图上全部 8 行（交换前 4 行 + 交换后 4 行），**顺序就是绘制顺序**。
  ///
  /// ⚠️ 为什么不放在 `paint()` 里现算：`paint()` 遍历的就是这个列表 ⇒
  ///    「守卫读到的」与「画出去的」天生同源，不存在两处公式各写一遍、
  ///    改了一处忘了另一处的可能。
  final List<CrossoverRow> rows;

  /// 「交换前」那 4 行。
  List<CrossoverRow> get beforeRows =>
      rows.where((r) => r.before).toList(growable: false);

  /// 「交换后」那 4 行。
  List<CrossoverRow> get afterRows =>
      rows.where((r) => !r.before).toList(growable: false);

  /// 有没有发生交换（⛔ `r = 0` 时为 false ⇒ 块标签换成
  /// [kCrossoverNoExchangeLabel]，不许照旧渲染「交换后」）。
  bool get hasCrossover => figure.hasCrossover;

  /// 「交换后」块的标签：**跟着数据走**。
  String get afterBlockLabel =>
      hasCrossover ? kCrossoverAfterLabel : kCrossoverNoExchangeLabel;

  /// 本图用到的**全部**颜色，供守卫逐条钉住。
  ///
  /// ⚠️ 存在的理由不是方便，是**给「不许多出第 5 种颜色」这条断言一个落点**。
  /// 图上每多一种颜色，就等于在本仓那张**每支都带既定语义**的调色板上
  /// 再占一支（红 = 致死、select = 选中、flash = 连线成功、connect = 相连高亮……）。
  /// 装饰性的一笔不是「不要钱」，它是**在借一支已经有话要说的颜色**。
  ///
  /// 判据：想加一个元素时先问「它说的这件事，别的元素说不说不出来」。
  /// 说不出来 ⇒ 是证据，可以加，并同步更新本守卫；
  /// 说得出来 ⇒ 删掉它。（本轮第一版的交换刻痕就是被这一问删掉的。）
  /// ⛔ 数据驱动**没有**放宽这条：4 条色带的实/空只由数据决定，
  /// 并没有因此多出「第 5 种颜色」来标记重组。
  List<Color> get colors =>
      <Color>[canvasColor, rodColor, bandColor, textColor];

  /// 行距（行区顶到下一行行区顶）。守卫用来证明两块之间还有净空。
  double get rowPitch => _kRowH + _kRowGap;

  /// 色带半高（= 色带上下各露多少）。守卫用它把「色带底缘」换算成 y，
  /// 才知道两块之间是**真的留了净空**还是只是行心坐标不一样。
  double get bandHalfHeight => _kBandH / 2;

  /// 色带宽（水平方向）。守卫用它验「几位点的色带都不会互相压上」。
  static double get bandWidth => _kBandW;

  /// 版面各段高度（设计坐标），供守卫把 `designHeight` 与算式对上。
  ///
  /// 存在的理由同 [colors]：那条「高度 = 上边距 + 2×块高 + 块间距 + 下边距」
  /// 的等式**跨两个成员**（designHeight 写在 widget 上、算式在 painter 里），
  /// Dart 没有 `static_assert` 能在这儿编译期自证 ⇒ 守卫 E6 重新算一遍。
  ({double padTop, double blockH, double blockGap, double padBottom})
      get layout => (
            padTop: _kPadTop,
            blockH: _kBlockH,
            blockGap: _kBlockGap,
            padBottom: _kPadBottom,
          );

  /// 「交换前」块**不**渲染配子名（数据层也没有：那些行的 `gamete` 恒 null）。
  static const bool kBeforeRendersGametes = false;

  /// 「交换后」块**渲染**配子名 —— 那 4 条染色单体本身就是 4 个配子。
  static const bool kAfterRendersGametes = true;

  /// 各位点色带在杆内的**相对位置**（0…1），按位点数给。
  ///
  /// ⚠️ 两位点时**逐字**返回常量 [0.34, 0.68]（已目检、已录进基线）；
  ///   一般公式只在 3 位点时生效。用常量分支而不是直接跑公式，是因为
  ///   `0.34 + (0.68 - 0.34)` 在 IEEE754 下是 `0.6799999999999999`，
  ///   会让已录基线**差最后一两个像素**。
  static List<double> locusRatios(int locusCount) {
    if (locusCount == 2) return const <double>[0.34, 0.68];
    if (locusCount < 2) return const <double>[0.34];
    final step = (_kLocusLast - _kLocusFirst) / (locusCount - 1);
    return <double>[
      for (var i = 0; i < locusCount; i++) _kLocusFirst + step * i,
    ];
  }

  // ── 版面（设计坐标）──────────────────────────────────────────
  // ⚠️ 下面带 ⛔ 注释的常量是**第一版沿用下来的**，数据驱动这一轮一个字
  //    都没改：它们是**已目检 + 已录基线**的那一版几何。
  static const double _kPadTop = 18; // 画布上边距（= 第一块标签的顶）
  static const double _kRowH = 26; // ⛔ 沿用
  static const double _kRowGap = 11; // ⛔ 沿用（行距 37）
  static const double _kIdW = 30; // ⛔ 沿用：左侧染色单体编号列
  static const double _kGameteW = 42; // ⛔ 沿用：右侧配子名列
  static const double _kRodH = 12; // ⛔ 沿用
  static const double _kBandW = 9; // ⛔ 沿用
  static const double _kBandH = 20; // ⛔ 沿用：色带比杆身高，露出来
  static const double _kLocusFirst = 0.34; // ⛔ 沿用：首个座在杆内的相对位置
  static const double _kLocusLast = 0.68; // ⛔ 沿用：末个座
  static const double _kFontSize = 12; // ⛔ 沿用：行内文字（编号 / 配子名）

  // ── 块标签带（高度的唯一来源）────────────────────────
  static const double _kBlockLabelH = 16; // 标签的预留行高
  static const double _kBlockLabelGap = 8; // 标签底 → 该块行区顶
  static const double _kBlockGap = 14; // 交换前行区底 → 交换后标签顶
  static const double _kBlockLabelFontSize = 11; // 「小字标签」：比行内 12 小 1 号
  static const double _kBlockLabelX = _kIdW; // 标签左缘对齐杆身左缘（= 30）
  static const double _kPadBottom = 13; // 行区底 → 画布下边距

  /// 一个块的标签带 + 行区总高：16 + 8 + (4×26 + 3×11) = 161。
  static const double _kBlockH =
      _kBlockLabelH + _kBlockLabelGap + 4 * _kRowH + 3 * _kRowGap;

  /// 「交换前」块 4 行的行区顶：18 + 16 + 8 = 42。
  static const double _kRowsTopBefore = _kPadTop + _kBlockLabelH + _kBlockLabelGap;

  /// 「交换后」块 4 行的行区顶：42 + 137 + 14 + 16 + 8 = 217。
  static const double _kRowsTopAfter =
      _kRowsTopBefore + 4 * _kRowH + 3 * _kRowGap + _kBlockGap +
          _kBlockLabelH + _kBlockLabelGap;

  // ⚠️ 「designHeight 是否与上面这套算式一致」是一条**跨成员**的等式
  //   （designHeight 写在 widget 上、算式在 painter 里），Dart 没有
  //   `static_assert` 可以在这里编译期自证 ⇒ 守卫 E6 在测试里把这条等式
  //   重新算一遍。改了块高 / 标签带 / 块间距却忘了改 designHeight，E6 会红，
  //   而不是等录基线时才发现图被切掉一截。

  /// 按 [CrossoverChromatid] 的行序（= 图上行序）造出全部 8 行。
  ///
  /// 两块用**同一个** [_rowCenterY] 公式、同一个行距 ⇒ 块内的
  /// 「行 → 编号」映射天然同构，这就是行位对齐的根据。
  static List<CrossoverRow> _buildRows(CrossoverFigure f) {
    final out = <CrossoverRow>[];
    final cs = f.chromatids;
    for (var i = 0; i < cs.length; i++) {
      final c = cs[i];
      out.add(CrossoverRow(
        chromatid: c.id,
        upper: c.parentalUpper,
        alleles: c.parentalGamete,
        // ⛔ 交换前没有配子 ⇒ 这里**不给** gamete。
        gamete: null,
        centerY: _rowCenterY(_kRowsTopBefore, i),
        before: true,
        // ⛔ 「有没有参与交换」是交换**之后**才成其为事实的说法。
        participated: false,
      ));
    }
    for (var i = 0; i < cs.length; i++) {
      final c = cs[i];
      out.add(CrossoverRow(
        chromatid: c.id,
        upper: c.upper,
        alleles: c.gamete,
        gamete: c.gamete,
        centerY: _rowCenterY(_kRowsTopAfter, i),
        before: false,
        participated: c.participated,
      ));
    }
    return List<CrossoverRow>.unmodifiable(out);
  }

  static double _rowCenterY(double rowsTopY, int i) =>
      rowsTopY + i * (_kRowH + _kRowGap) + _kRowH / 2;

  @override
  void paint(Canvas canvas, Size size) {
    // 背景（照 pedigree_chart：先铺近白底，导出 PNG 打印友好）。
    canvas.drawRect(Offset.zero & size, Paint()..color = canvasColor);

    // 按可用宽度等比缩放（⛔ 不固定像素宽，360 窄屏也不会溢出）。
    final s = size.width / LinkageCrossoverDiagram.designWidth;
    canvas.save();
    canvas.scale(s);

    // 「交换前」：标签 + 4 行（⛔ 不画配子名）
    _blockLabel(canvas, kCrossoverBeforeLabel, _kPadTop);
    _drawRows(canvas, beforeRows, withGameteLabels: kBeforeRendersGametes);

    // 「交换后」：标签 + 4 行（画配子名）。⛔ 标签跟着数据走：
    // 一次交换都没发生时，它说的是「未发生交换」而不是「交换后」。
    _blockLabel(canvas, afterBlockLabel,
        _kRowsTopBefore + 4 * _kRowH + 3 * _kRowGap + _kBlockGap);
    _drawRows(canvas, afterRows, withGameteLabels: kAfterRendersGametes);

    canvas.restore();
  }

  /// 画一块的 4 行。**两块走的是同一段代码**，x 几何逐字相同
  /// （同一份 `_kIdW` / `_kGameteW` / [locusRatios]）⇒
  /// 块内第 i 行与另一块第 i 行落在同一条竖直线上，这就是行位对齐。
  void _drawRows(Canvas canvas, List<CrossoverRow> rs,
      {required bool withGameteLabels}) {
    final rodLeft = _kIdW;
    final rodRight = LinkageCrossoverDiagram.designWidth - _kGameteW;
    final rodW = rodRight - rodLeft;

    for (final r in rs) {
      final cy = r.centerY;

      // 杆身
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(rodLeft, cy - _kRodH / 2, rodW, _kRodH),
          const Radius.circular(_kRodH / 2),
        ),
        Paint()..color = rodColor,
      );

      // ⛔ 几座 = 几个色带，位置按位点数给（数据驱动）。
      final ratios = locusRatios(r.locusCount);
      for (var i = 0; i < r.upper.length; i++) {
        _locus(canvas, rodLeft + rodW * ratios[i], cy, upper: r.upper[i]);
      }

      // 左：染色单体编号
      _text(canvas, r.chromatid, Offset(_kIdW - 6, cy), right: true);

      // 右：配子名（**只有「交换后」块有**；⛔ 交换前连数据都没有）
      if (withGameteLabels && r.gamete != null) {
        _text(canvas, r.gamete!, Offset(rodRight + 6, cy));
      }
    }
  }

  /// 画一块的标签（「交换前」/「交换后」/「未发生交换」）。
  ///
  /// ⚠️ 标签只用 `textColor`：**不许**为了「标签淡一点、跟正文有层次」
  /// 就去取 `AppColors.steel` / `graphite` —— 那是**第 5 种颜色**。
  void _blockLabel(Canvas canvas, String s, double topY) {
    final tp = TextPainter(
      text: TextSpan(text: s, style: blockLabelTextStyle),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(_kBlockLabelX, topY + (_kBlockLabelH - tp.height) / 2));
  }

  void _locus(Canvas canvas, double cx, double cy, {required bool upper}) {
    final r = Rect.fromCenter(
      center: Offset(cx, cy),
      width: _kBandW,
      height: _kBandH,
    );
    final rr = RRect.fromRectAndRadius(r, const Radius.circular(2));
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

  /// 行内文字（染色单体编号 / 配子名）的样式。
  ///
  /// ⚠️⚠️ **fontFamily 不是可选项**（实测栽在这里，记下来免得复发）：
  ///   `CustomPainter` 里的 `TextPainter` **没有 BuildContext**、拿不到
  ///   `DefaultTextStyle`，所以一个不声明 family 的 `TextStyle` 不会
  ///   「继承主题字体」，而是直接落回 **flutter_tester 的引擎测试字体
  ///   FlutterTest** —— 那里每个字形都画成**实心方块**。
  ///   `test/golden_fonts.dart` 装载的是「PingFang SC」/「JetBrains Mono」
  ///   /「Consolas」三个**具名** family，没被具名命中的一个都取不到。
  ///   ⇒ 症状：编号与基因型在基线里全变成黑色方块，而
  ///     **布局是按方框宽度算的 ⇒ 这类基线对文本内容零敏感，是假绿**
  ///     （与 R10-5 图标 / R11-3 中文 / R12-1 基因型三轮方框盲区同源，
  ///       只是那一三轮在 widget 上，这一轮长在 painter 里）。
  ///
  /// 选 **mono** 而不是 sans：基因型与等位基因标识（`AB` / `Ab` / `1a`）
  /// 本仓一律挂 `AppFonts.mono`（`AppText.genotype` / `monoSmall`），
  /// 这里必须与它们同族，否则同一屏上两种字母风格并存。
  /// ⚠️ 家族名必须与 `test/golden_fonts.dart` 装载时的名字**逐字一致**：
  ///   R12-1 实测「注册成 Consolas、primary 仍写 JetBrains Mono」**无效**，
  ///   载荷必须是 `AppFonts.mono` 那个名字。
  TextStyle get rowTextStyle => TextStyle(
        fontFamily: AppFonts.mono,
        fontFamilyFallback: AppFonts.monoFallback,
        fontSize: _kFontSize,
        fontWeight: FontWeight.w600, // 与 AppText.genotype 的字重一致
        color: textColor,
      );

  /// 块标签（「交换前」/「交换后」/「未发生交换」）的样式。
  ///
  /// ⚠️⚠️ 为什么中文标签**不能**跟行内文字一样挂 `AppFonts.mono`：
  ///   `AppFonts.monoFallback` 是 `['Consolas', 'Menlo', 'monospace']`，
  ///   **一支都没有汉字**；而 `test/golden_fonts.dart` 的文件头（R12-1 实测）
  ///   写明：flutter_tester 里 primary family 没装载时引擎**根本不去查
  ///   `fontFamilyFallback`**，直接落回 FlutterTest 方框字体
  ///   ⇒ `交换前` 三个字在基线里会变成三个方框，
  ///   **而且布局按方框宽度算 ⇒ 基线对「标签文案」零敏感，又是假绿**。
  ///   ⇒ 标签挂 [AppFonts.sans]（= `'PingFang SC'`，正是
  ///     `loadGoldenFonts(cjk: true)` 装载的那个名字，载荷是雅黑 ⇒ 真字形）。
  ///   这与行内文字挂 mono 并不矛盾：**基因型走 mono、中文界面文字走 sans**
  ///   本来就是本仓的分工（`AppText.genotype` vs 其余 AppText.*）。
  TextStyle get blockLabelTextStyle => TextStyle(
        fontFamily: AppFonts.sans,
        fontFamilyFallback: AppFonts.sansFallback,
        fontSize: _kBlockLabelFontSize,
        fontWeight: FontWeight.w600,
        color: textColor, // ⛔ 第 4 种颜色；不许再取一支灰
      );

  void _text(Canvas canvas, String s, Offset at,
      {bool right = false, TextStyle? style}) {
    final tp = TextPainter(
      text: TextSpan(text: s, style: style ?? rowTextStyle),
      textDirection: TextDirection.ltr,
    )..layout();
    final dx = right ? at.dx - tp.width : at.dx;
    tp.paint(canvas, Offset(dx, at.dy - tp.height / 2));
  }

  @override
  bool shouldRepaint(covariant CrossoverPainter old) =>
      old.figure != figure ||
      old.canvasColor != canvasColor ||
      old.rodColor != rodColor ||
      old.bandColor != bandColor ||
      old.textColor != textColor;
}
