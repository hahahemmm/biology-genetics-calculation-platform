// ════════════════════════════════════════════════════════════════
//  test/strand_ct_golden_test.dart
//  分子页「两链 C/T 计数」格阵：**浅 / 深** 两档像素基线
// ════════════════════════════════════════════════════════════════
//
//  ## 本文件为什么存在
//
//  这张图（`lib/pages/widgets/strand_ct_matrix.dart`，620 行）从 B 仓
//  移植落地并挂在分子页上，但 `test/goldens/` 下**一张基线都没有**
//  ⇒ 它的像素级回归网为零。既有惯例是每张概念图配档位基线，本文件补齐。
//
//  ## ⛔ 本文件只提供脚手架，基线由主线程录、再肉眼目检
//
//  ⛔ 本文件**不许**用 `flutter test --update-goldens` 产出 PNG
//     （哪怕只跑这一个文件也不行）—— 基线必须是主线程目检过的那一份。
//  ⛔ 因此在本基线录好之前，本文件**预期是红的**，且红的信息必须说清
//     是「基线还没录」而不是别的什么。
//
//  ## ⛔ 三条不许省的样板（每条都有存在过的理由）
//
//  ① `await loadGoldenFonts(cjk: true);` 必须在**每次** `pumpWidget` 之前。
//     不装字体 ⇒ 基线里的链名与格中数字全是**空心方框**，而布局正是按方框
//     宽度算的 ⇒ 基线对「文本内容」完全失明（假绿）。
//  ② `AppColors.sync(...)` + `tearDown` 里复位。⛔ AppColors 的 token 是
//     getter，亮度靠 sync 切换，不复位的话同进程里后面的用例会录在错的档上。
//  ③ 两条 Z 自检：`两档互不相同` + `基线必须已存在且不是空图`。
//
//  ## 这张图最该被像素钉住的一件事
//
//  引擎只有 `c1/t1/c2/t2` 与全分子四个计数，⛔ 没有 `a1/g1/a2/g2`
//  ⇒ 链1/链2 的 A、G 四格画成**空框 + 图例**，⛔ 绝不代填 0。
//  谁哪天替引擎编一个 0 填进去，基线立刻红。
// ════════════════════════════════════════════════════════════════

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:biology/engine/dna_strand_engine.dart';
import 'package:biology/pages/widgets/strand_ct_matrix.dart';
import 'package:biology/theme.dart';

import 'golden_fonts.dart';

// ─────────────────────────── 出厂输入 ───────────────────────────
//
// ⛔ **测试数据一律从引擎取**，不在本文件里手抄「引擎会输出什么」——
//    格内那 8 个数字全是 `strandCountsFromCT` 直接搬过来的引擎字段。
//
// 来源：`dna_strand_engine.dart` 的 `strandCountsFromCT`。
// 选 `链1 C=10 T=20；链2 C=15 T=25` 这组：
//  · 引擎给 `aTotal = tTotal = 45`、`gTotal = cTotal = 25`、`total = 140`
//    （`test/strand_ct_matrix_test.dart` 的 L1 已逐字钉死）；
//  · ⛔ 引擎**压根没有** `a1/g1/a2/g2` 四个字段 ⇒ 链 1 / 链 2 的 A 与 G
//    四格必须画成**空格**。这正是这张图最该被像素钉住的一件事。
const int _kC1 = 10;
const int _kT1 = 20;
const int _kC2 = 15;
const int _kT2 = 25;

/// 图的宿主宽度。
///
/// ⚠️ ⛔ **本图必须给一个确定的宽度**：版面解算走 `LayoutBuilder` 的
///    `c.maxWidth`（组件 `build` 内），列宽按它算 ⇒ 宿主宽度一旦浮动
///    （整屏 / 无界），基线就不可复现。这里锁 320（= 组件的
///    `kStrandCtDesignWidth`）⇒ 基线录在 **scale = 1.0** 上，
///    像素与设计稿 1:1。
const double _kHostWidth = 320;

/// 裸宿主：只挂裸图 ⇒ 基线里出现的每一像素都来自图自己。
Widget _host(Brightness b, StrandCTResult r) => MaterialApp(
      theme: AppTheme.build(b),
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: _kHostWidth,
            child: StrandCtMatrix(result: r),
          ),
        ),
      ),
    );

/// 拍照的 finder：`CustomPaint`（**带 RenderObject 的那一个**）。
///
/// ⛔ **不能**用 `find.byType(StrandCtMatrix)`：那是 `StatelessWidget`，
///    本身**不是 RenderObject**，`matchesGoldenFile` 取不到它的 render
///    object，最后落到**整屏** ⇒ 基线对「宿主长什么样」过度敏感、
///    对「图画在哪」几乎无约束（既有 golden 测试的同款警示）。
Finder _paintOf() => find
    .descendant(
        of: find.byType(StrandCtMatrix), matching: find.byType(CustomPaint))
    .first;

/// 两个档位（浅 / 深；按任务口径不录夜间高对比档）。
const List<({String tag, String label, Brightness b})> _kTiers =
    <({String tag, String label, Brightness b})>[
  (tag: 'light', label: '浅色', b: Brightness.light),
  (tag: 'dark', label: '深色', b: Brightness.dark),
];

/// ⛔ 基线不存在时**必须红**，且红的信息要说清是「还没录」。
///   这不是 bug，是本轮的正确结果（基线由主线程录）。
void _failIfBaselineMissing(String p) {
  final f = File(p);
  if (!f.existsSync()) {
    fail('基线还没录：$p。⛔ 本文件不许自己录（不许跑 --update-goldens），'
        '由主线程在隔离环境变量下录、再肉眼目检。');
  }
}

void main() {
  tearDown(() {
    // ⛔ AppColors 的 token 是 **getter**，亮度靠 sync 切换 ⇒ 收尾复位。
    AppColors.sync(Brightness.light);
  });

  // ── Z：基线自检 ────────────────────────────────────────────────
  test('Z 两档基线必须互不相同（防两档录成一张图）', () {
    // ⚠️ 恒等检查：少了这条，一个「两档其实录的是同一个东西」的测试照样全绿。
    // ⚠️ 普通 `test()` 的 CWD 是**包根**，而 `matchesGoldenFile` 的路径相对
    //    **测试文件所在目录**（test/）⇒ 这里必须写全路径前缀。
    const dir = 'test/goldens/';
    _failIfBaselineMissing('${dir}strand_ct_light.png');
    _failIfBaselineMissing('${dir}strand_ct_dark.png');
    final a = File('${dir}strand_ct_light.png').readAsBytesSync();
    final b = File('${dir}strand_ct_dark.png').readAsBytesSync();
    expect(a.length, greaterThan(1000), reason: '基线太小，多半是空图');
    expect(b.length, greaterThan(1000));
    expect(a, isNot(equals(b)), reason: '浅色与深色录成了同一张');
  });

  test('Z 浅色基线必须已存在且不是空图（本文件不许自己录）', () {
    // ⚠️ 普通 `test()` 的 CWD 是**包根** ⇒ 这里必须写全路径前缀。
    const p = 'test/goldens/strand_ct_light.png';
    final f = File(p);
    if (!f.existsSync()) {
      fail('基线还没录：$p。⛔ 本文件不许自己录（不许跑 --update-goldens），'
          '由主线程在隔离环境变量下录、再肉眼目检。');
    }
    // ⛔ 光「存在」不够：组件要是哪天什么都不画，录出来的就是**一张纯底色
    //    的小 PNG**，它照样存在、照样比对通过 —— 一条自己骗自己的基线
    //    等于没有基线。下限 1000B 把「纯底色小图」挡在外面。
    expect(f.lengthSync(), greaterThan(1000),
        reason: '基线 $p 只有 ${f.lengthSync()} 字节，'
            '多半是一张没画任何东西的纯底色小图。');
  });

  // ── A：像素基线（录之前预期红）────────────────────────────────
  for (final tier in _kTiers) {
    testWidgets(
        'A/${tier.label}像素基线（链1 C=10 T=20；链2 C=15 T=25：'
        '8 格数字 + 4 格空格 + 图例 + 依据行）', (t) async {
      // ⛔ 字体不装载 ⇒ 基线里的链名与格中数字会是一排空心方框，
      //    而布局正是按方框宽度算的 ⇒ 基线对「文本内容」完全失明（假绿）。
      await loadGoldenFonts(cjk: true);
      AppColors.sync(tier.b);
      await t.pumpWidget(_host(tier.b, _data));
      // ⛔ 这是纯 `CustomPaint`，**不需要** runAsync / precacheImage。
      await t.pump();
      await expectLater(_paintOf(),
          matchesGoldenFile('goldens/strand_ct_${tier.tag}.png'));
    });
  }

  // ── K：⛔ 基线不许是一张「什么都没画」的图 ──────────────────────
  //
  // ⛔ **为什么必须先证明合法数据真的画得出来**：`dataReason` 判不过
  //    ⇒ 整棵子树收缩成 `SizedBox.shrink()` ⇒ 那样录出来的是一张纯底色
  //    小 PNG，它照样存在、照样比对通过。
  testWidgets('K1 喂引擎算出的合法数据 ⇒ 真的有 CustomPaint 且高度 > 0', (t) async {
    await loadGoldenFonts(cjk: true);
    AppColors.sync(Brightness.light);
    expect(StrandCtMatrix.dataReason(_data), isNull,
        reason: '⛔ 前提：引擎给的这份数据必须画得出来');
    expect(StrandCtMatrix.skipReason(_data, _kHostWidth), isNull,
        reason: '⛔ 前提：$_kHostWidth 宽下必须画得下');
    await t.pumpWidget(_host(Brightness.light, _data));
    await t.pump();
    final paint = _paintOf();
    expect(paint, findsOneWidget,
        reason: '⛔ 合法数据下组件必须真的画图；否则录出来的基线是空图');
    expect(t.getSize(paint).height, greaterThan(0));
    expect(t.takeException(), isNull);
  });

  testWidgets('K2 ⛔ 喂自相矛盾的数据 ⇒ 整棵子树收缩成 SizedBox.shrink', (t) async {
    // ⛔ 四个链内计数照抄引擎，但 `tTotal` 写成 44（真值是 45）
    //    ⇒ 判据「aTotal == tTotal」不过 ⇒ 组件整棵子树收缩。
    //    引擎自己永远给不出这种组合，它正是「数据被换掉了」的情形。
    final bad = StrandCTResult(
      c1: _kC1,
      t1: _kT1,
      c2: _kC2,
      t2: _kT2,
      aTotal: _data.aTotal,
      tTotal: _data.tTotal - 1, // ⛔ 45 → 44，与引擎口径对不上
      gTotal: _data.gTotal,
      cTotal: _data.cTotal,
      total: _data.total,
    );
    expect(StrandCtMatrix.dataReason(bad), isNotNull,
        reason: '⛔ 前提：这组数据必须画不出来');
    await loadGoldenFonts(cjk: true);
    AppColors.sync(Brightness.light);
    await t.pumpWidget(_host(Brightness.light, bad));
    await t.pump();
    expect(t.getSize(find.byType(StrandCtMatrix)).height, 0,
        reason: '⛔ 画不出的数据下必须整体收缩，不留空框 / 依据行 / 占位');
    // ⛔ **这里不能写 `_paintOf()`**：它带 `.first`，子树收缩成一个都没有时
    //    finder 自己先抛 `Bad state: No element` ⇒ 断言根本走不到 `findsNothing`
    //    （多个文件同时栽过：K2 全红，而红的原因与被测行为无关）。
    //    正确写法是同一条 descendant 链但**不取 first**。
    expect(
        find.descendant(
            of: find.byType(StrandCtMatrix), matching: find.byType(CustomPaint)),
        findsNothing,
        reason: '⛔ 收缩 ⇒ 子树里连 CustomPaint 都不该有');
  });

  // ── R58 回归哨：课堂倍率必须同时进 painter 与 layout ─────────────
  //
  // ⛔ R58 类事故：只把 textScale 接进 painter、没接进 layout ⇒ 课堂档下
  //    格阵仍按 1.0 算、字按 1.75× 放大 ⇒ 溢出。这条用 320 窄宿主 + 课堂档
  //    倍率泵一遍，断言组件仍装得下（不溢出、无异常），把「半接线」从
  //    「靠人工比对 golden 才暴露」变成自动化红。
  testWidgets('R58 回归哨：课堂倍率 1.75× 下 320 窄宿主不溢出、无异常',
      (t) async {
    await loadGoldenFonts();
    assertMaterialIconsLoaded();
    assertMonoLoaded();
    AppColors.sync(Brightness.light);
    const textScale = 1.75; // PresentModeController.textScale 课堂档
    await t.pumpWidget(MaterialApp(
      theme: AppTheme.build(Brightness.light),
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 320, // 比设计稿还窄 ⇒ 最容易触发溢出
            child: StrandCtMatrix(result: _data, textScale: textScale),
          ),
        ),
      ),
    ));
    await t.pump();
    expect(t.takeException(), isNull,
        reason: '⛔ 课堂倍率 + 窄宿主下不允许抛溢出/越界异常');
    expect(t.getSize(find.byType(StrandCtMatrix)).width,
        lessThanOrEqualTo(320),
        reason: '⛔ 组件宽不得超出 320 窄宿主（R58 半接线会顶出去）');
    expect(t.getSize(find.byType(StrandCtMatrix)).height, greaterThan(0),
        reason: '⛔ 课堂倍率下仍要真画得出（高度 > 0），不能收缩成空');
  });
}

/// 这一组出厂数据。⛔ 由引擎现算，⛔ 不缓存成常量 ——
/// 缓存下来就变成「测试里手抄了一份引擎输出」。
StrandCTResult get _data =>
    strandCountsFromCT(c1: _kC1, t1: _kT1, c2: _kC2, t2: _kT2);
