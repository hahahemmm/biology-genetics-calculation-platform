// ════════════════════════════════════════════════════════════════
//  test/mutation_diff_golden_test.dart
//  变异页「基因突变」前后对照图：**浅 / 深** 两档像素基线
// ════════════════════════════════════════════════════════════════
//
//  ## 本文件为什么存在
//
//  这张图（`lib/pages/widgets/mutation_diff_diagram.dart`，651 行）从 B 仓
//  移植落地并挂在变异页上，但 `test/goldens/` 下**一张基线都没有**
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
//     不装字体 ⇒ 基线里的碱基字母与中文图注全是**空心方框**，而布局正是
//     按方框宽度算的 ⇒ 基线对「文本内容」完全失明（假绿）。
//  ② `AppColors.sync(...)` + `tearDown` 里复位。⛔ AppColors 的 token 是
//     getter，亮度靠 sync 切换，不复位的话同进程里后面的用例会录在错的档上。
//  ③ 两条 Z 自检：`两档互不相同` + `基线必须已存在且不是空图`。
// ════════════════════════════════════════════════════════════════

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:biology/engine/mutation_engine.dart';
import 'package:biology/pages/widgets/mutation_diff_diagram.dart';
import 'package:biology/theme.dart';

import 'golden_fonts.dart';

// ─────────────────────────── 出厂输入 ───────────────────────────
//
// ⛔ **测试数据一律从引擎取**，不在本文件里手抄「引擎会输出什么」——
//    原串 / 突变串 / 受影响密码子 / 位移提示全是引擎算出来的。
//
// 来源：`mutation_engine.dart` 的 `mutateSequence`。
// 选 `ATGGCTTAA`（9 bp = 3 个密码子）的**第 1 位替换** `T→C`：
//  · 受影响的是第 0 个密码子（`ATG → ACG`）⇒ 非同义，图上「受影响密码子变了」
//    那条图注走的是实路，不是「没变」的兜底；
//  · 长度差为 0（替换）⇒ 不触发位移文案那条分支，基线版面稳定。
const String _kSequence = 'ATGGCTTAA';
const String _kType = 'sub'; // 引擎认 'sub' / 'ins' / 'del'
const int _kPosition = 1;
const String _kNewBase = 'C';

/// 图的宿主宽度。
///
/// ⚠️ 本图**不用 LayoutBuilder**：画布走 `kMutationDiffDesignWidth`
///    （=280，painter 的设计坐标），与宿主给多宽无关 ⇒ 这里锁 280
///    ⇒ 基线录在 **scale = 1.0** 上，像素与设计稿 1:1。
const double _kHostWidth = 280;

/// 裸宿主：只挂裸图 ⇒ 基线里出现的每一像素都来自图自己。
Widget _host(Brightness b, MutatedSequence r) => MaterialApp(
      theme: AppTheme.build(b),
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: _kHostWidth,
            child: MutationDiffDiagram(result: r),
          ),
        ),
      ),
    );

/// 拍照的 finder：`CustomPaint`（**带 RenderObject 的那一个**）。
///
/// ⛔ **不能**用 `find.byType(MutationDiffDiagram)`：那是 `StatelessWidget`，
///    本身**不是 RenderObject**，`matchesGoldenFile` 取不到它的 render
///    object，最后落到**整屏** ⇒ 基线对「宿主长什么样」过度敏感、
///    对「图画在哪」几乎无约束（既有 golden 测试的同款警示）。
Finder _paintOf() => find
    .descendant(
        of: find.byType(MutationDiffDiagram), matching: find.byType(CustomPaint))
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
    _failIfBaselineMissing('${dir}mutation_diff_light.png');
    _failIfBaselineMissing('${dir}mutation_diff_dark.png');
    final a = File('${dir}mutation_diff_light.png').readAsBytesSync();
    final b = File('${dir}mutation_diff_dark.png').readAsBytesSync();
    expect(a.length, greaterThan(1000), reason: '基线太小，多半是空图');
    expect(b.length, greaterThan(1000));
    expect(a, isNot(equals(b)), reason: '浅色与深色录成了同一张');
  });

  test('Z 浅色基线必须已存在且不是空图（本文件不许自己录）', () {
    // ⚠️ 普通 `test()` 的 CWD 是**包根** ⇒ 这里必须写全路径前缀。
    const p = 'test/goldens/mutation_diff_light.png';
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
    testWidgets('A/${tier.label}像素基线（ATGGCTTAA 第 1 位 T→C：原 / 突变两条读码框）',
        (t) async {
      // ⛔ 字体不装载 ⇒ 基线里的碱基字母与中文图注会是一排空心方框，
      //    而布局正是按方框宽度算的 ⇒ 基线对「文本内容」完全失明（假绿）。
      await loadGoldenFonts(cjk: true);
      AppColors.sync(tier.b);
      await t.pumpWidget(_host(tier.b, _data));
      // ⛔ 这是纯 `CustomPaint`，**不需要** runAsync / precacheImage。
      await t.pump();
      await expectLater(_paintOf(),
          matchesGoldenFile('goldens/mutation_diff_${tier.tag}.png'));
    });
  }

  // ── K：⛔ 基线不许是一张「什么都没画」的图 ──────────────────────
  //
  // ⛔ **为什么必须先证明合法数据真的画得出来**：`mutationDiffIsDrawable`
  //    判不过 ⇒ 整棵子树收缩成 `SizedBox.shrink()`
  //    （`mutation_diff_diagram.dart:405`）⇒ 那样录出来的是一张纯底色
  //    小 PNG，它照样存在、照样比对通过。
  testWidgets('K1 喂引擎算出的合法数据 ⇒ 真的有 CustomPaint 且高度 > 0', (t) async {
    await loadGoldenFonts(cjk: true);
    AppColors.sync(Brightness.light);
    expect(mutationDiffIsDrawable(_data), isTrue,
        reason: '⛔ 前提：引擎给的这份数据必须画得出来');
    await t.pumpWidget(_host(Brightness.light, _data));
    await t.pump();
    final paint = _paintOf();
    expect(paint, findsOneWidget,
        reason: '⛔ 合法数据下组件必须真的画图；否则录出来的基线是空图');
    expect(t.getSize(paint).height, greaterThan(0));
    expect(t.getSize(paint).width, kMutationDiffDesignWidth);
    expect(t.takeException(), isNull);
  });

  testWidgets('K2 ⛔ 喂自相矛盾的数据 ⇒ 整棵子树收缩成 SizedBox.shrink', (t) async {
    // ⛔ 只把 `originalCodon` 改坏（改成串里根本没有的 3 个字母），
    //    其余字段逐字取自引擎 ⇒ 判据是「字段与串不自洽」
    //    （`mutation_diff_diagram.dart:258`），且这个坏例只证明这一件事。
    final good = _data;
    final bad = MutatedSequence(
      original: good.original,
      mutated: good.mutated,
      type: good.type,
      position: good.position,
      codonIndex: good.codonIndex,
      originalCodon: 'ZZZ', // ⛔ 与 original 在该密码子上的 3 个碱基对不上
      mutatedCodon: good.mutatedCodon,
      silent: good.silent,
    );
    expect(mutationDiffIsDrawable(bad), isFalse,
        reason: '⛔ 前提：这组数据必须画不出来');
    await loadGoldenFonts(cjk: true);
    AppColors.sync(Brightness.light);
    await t.pumpWidget(_host(Brightness.light, bad));
    await t.pump();
    expect(t.getSize(find.byType(MutationDiffDiagram)).height, 0,
        reason: '⛔ 画不出的数据下必须整体收缩，不留空框 / 图例 / 占位');
    // ⛔ **这里不能写 `_paintOf()`**：它带 `.first`，子树收缩成一个都没有时
    //    finder 自己先抛 `Bad state: No element` ⇒ 断言根本走不到 `findsNothing`
    //    （多个文件同时栽过：K2 全红，而红的原因与被测行为无关）。
    //    正确写法是同一条 descendant 链但**不取 first**。
    expect(
        find.descendant(
            of: find.byType(MutationDiffDiagram),
            matching: find.byType(CustomPaint)),
        findsNothing,
        reason: '⛔ 收缩 ⇒ 子树里连 CustomPaint 都不该有');
  });
}

/// 这一组出厂数据。⛔ 由引擎现算，⛔ 不缓存成常量 ——
/// 缓存下来就变成「测试里手抄了一份引擎输出」。
MutatedSequence get _data => mutateSequence(
      sequence: _kSequence,
      type: _kType,
      position: _kPosition,
      newBase: _kNewBase,
    );
