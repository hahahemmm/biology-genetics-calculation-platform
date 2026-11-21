// tetraploid_gamete_golden_test.dart —— 同源四倍体配子示意图像素基线（浅 / 深）。
//
// 只拍示意图组件本身（不进宿主页）：裸宿主 + `AppColors.sync` 锁档 +
// `loadGoldenFonts` 装字体（⛔ 方框基线 = 假绿），拍带 RenderObject 的
// `CustomPaint`（StatelessWidget 本身不是 RenderObject）。
//
// ## ⛔ 本文件只提供脚手架，基线由主线程录、再肉眼目检
//
//  ⛔ 本文件**不许**用 `flutter test --update-goldens` 产出 PNG——基线必须
//     是主线程目检过的那一份。因此在基线录好之前，A 组用例**预期是红的**，
//     且 Z 组自检会先以「基线还没录」失败把话说清。
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:biology/engine/ploidy_engine.dart';
import 'package:biology/pages/widgets/tetraploid_gamete_diagram.dart';
import 'package:biology/theme.dart';

import 'golden_fonts.dart';

/// 出厂输入 `AAaa`：3 种组合（AA:1 / Aa:4 / aa:1）+ 4 根棒，信息量最大一档。
/// ⛔ 测试数据由引擎现算（`_data` getter），不在本文件手抄引擎输出。
const String _kGenotype = 'AAaa';

/// 图的宿主宽度：本图走 `kTetraDiagramDesignWidth`（=320）设计坐标，
/// 几何全由 `tetraploidDiagramPlan` 从引擎字段算出 ⇒ 锁 320，基线录在
/// scale = 1.0 上，像素与设计稿 1:1。
const double _kHostWidth = 320;

/// 裸宿主：只挂裸图 ⇒ 基线里出现的每一像素都来自图自己。
Widget _host(Brightness b, TetraploidGametes r) => MaterialApp(
      theme: AppTheme.build(b),
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: _kHostWidth,
            child: TetraploidGameteDiagram(result: r),
          ),
        ),
      ),
    );

/// 拍照的 finder：`CustomPaint`（**带 RenderObject 的那一个**）。
///
/// ⛔ **不能**用 `find.byType(TetraploidGameteDiagram)`：那是
///    `StatelessWidget`，本身**不是 RenderObject**，`matchesGoldenFile`
///    取不到它的 render object，最后落到**整屏** ⇒ 基线对「宿主长什么样」
///    过度敏感、对「图画在哪」几乎无约束。
Finder _paintOf() => find
    .descendant(
        of: find.byType(TetraploidGameteDiagram),
        matching: find.byType(CustomPaint))
    .first;

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
  tearDown(AppColors.debugClearOverride);

  // ── Z：基线自检（录好之前先红，把「还没录」说清楚）─────────────
  test('Z 浅 / 深两张基线必须都已存在、不是空图，且互不相同', () {
    // ⚠️ 普通 `test()` 的 CWD 是**包根**，而 `matchesGoldenFile` 的路径相对
    //    **测试文件所在目录**（test/）⇒ 这里必须写全路径前缀。
    const dir = 'test/goldens/';
    final a = File('${dir}tetraploid_gamete_light.png');
    final b = File('${dir}tetraploid_gamete_dark.png');
    _failIfBaselineMissing(a.path);
    _failIfBaselineMissing(b.path);
    // ⛔ 光「存在」不够：组件要是哪天什么都不画，录出来的就是**一张纯底色
    //    的小 PNG**，它照样存在、照样比对通过 —— 一条自己骗自己的基线
    //    等于没有基线。下限 1000B 把「纯底色小图」挡在外面。
    expect(a.lengthSync(), greaterThan(1000),
        reason: '基线 ${a.path} 只有 ${a.lengthSync()} 字节，多半是空图');
    expect(b.lengthSync(), greaterThan(1000));
    expect(a.readAsBytesSync(), isNot(equals(b.readAsBytesSync())),
        reason: '浅 / 深两张基线逐字节相同 —— 多半是主题 token 没跟着亮度走');
  });

  // ── A：浅 / 深两档像素基线（录之前预期红）────────────────────
  for (final tier in const <({String tag, String label, Brightness b})>[
    (tag: 'light', label: '浅色', b: Brightness.light),
    (tag: 'dark', label: '深色', b: Brightness.dark),
  ]) {
    testWidgets('${tier.label}像素基线（AAaa：4 根棒 + 3 种配子框）', (t) async {
      // ⛔ 字体不装载 ⇒ 基线里的基因型与中文图注会是一排空心方框，
      //    而布局正是按方框宽度算的 ⇒ 基线对「文本内容」完全失明（假绿）。
      await loadGoldenFonts();
      assertMaterialIconsLoaded();
      assertMonoLoaded();
      AppColors.sync(tier.b);
      await t.pumpWidget(_host(tier.b, _data));
      // ⛔ 这是纯 `CustomPaint`，**不需要** runAsync / precacheImage。
      await t.pump();
      expect(t.takeException(), isNull);
      await expectLater(_paintOf(),
          matchesGoldenFile('goldens/tetraploid_gamete_${tier.tag}.png'));
    });
  }

  // ── K：⛔ 基线不许是一张「什么都没画」的图 ──────────────────────
  //
  // ⛔ **为什么必须先证明合法数据真的画得出来**：`tetraploidDiagramPlan`
  //    建不出来 ⇒ 整棵子树收缩成 `SizedBox.shrink` ⇒ 那样录出来的是一张纯
  //    底色小 PNG，它照样存在、照样比对通过。
  testWidgets('K1 喂引擎算出的合法数据 ⇒ 真的有 CustomPaint 且高度 > 0', (t) async {
    await loadGoldenFonts();
    assertMaterialIconsLoaded();
    assertMonoLoaded();
    AppColors.sync(Brightness.light);
    expect(tetraploidDiagramPlan(_data), isNotNull,
        reason: '⛔ 前提：引擎给的这份数据必须画得出来');
    await t.pumpWidget(_host(Brightness.light, _data));
    await t.pump();
    final paint = _paintOf();
    expect(paint, findsOneWidget,
        reason: '⛔ 合法数据下组件必须真的画图；否则录出来的基线是空图');
    expect(t.getSize(paint).height, greaterThan(0));
    expect(t.getSize(paint).width, kTetraDiagramDesignWidth);
    // ⛔ 高度必须等于「布局自己算出的总高」，⛔ 不是某个写死的数。
    expect(t.getSize(paint).height,
        tetraploidDiagramPlan(_data)!.totalHeight);
    expect(t.takeException(), isNull);
  });

  testWidgets('K2 ⛔ 喂自相矛盾的数据 ⇒ 整棵子树收缩成 SizedBox.shrink', (t) async {
    // ⛔ 基因型合法但 `counts` 为空 ⇒ 组件无从画出配子框 ⇒ 闸门第一判据
    //    就拒。引擎自己永远给不出这种组合，它正是「数据被换掉了」的情形。
    final bad = TetraploidGametes(genotype: _kGenotype, counts: const {});
    expect(tetraploidDiagramPlan(bad), isNull,
        reason: '⛔ 前提：这组数据必须画不出来');
    await loadGoldenFonts();
    AppColors.sync(Brightness.light);
    await t.pumpWidget(_host(Brightness.light, bad));
    await t.pump();
    expect(t.getSize(find.byType(TetraploidGameteDiagram)).height, 0,
        reason: '⛔ 画不出的数据下必须整体收缩，不留空框 / 图注 / 占位');
    // ⛔ **这里不能写 `_paintOf()`**：它带 `.first`，子树收缩成一个都没有时
    //    finder 自己先抛 `Bad state: No element` ⇒ 断言根本走不到
    //    `findsNothing`（红的原因与被测行为无关）。正确写法是同一条
    //    descendant 链但**不取 first**。
    expect(
        find.descendant(
            of: find.byType(TetraploidGameteDiagram),
            matching: find.byType(CustomPaint)),
        findsNothing,
        reason: '⛔ 收缩 ⇒ 子树里连 CustomPaint 都不该有');
  });
}

/// 这一组出厂数据。⛔ 由引擎现算，⛔ 不缓存成常量 ——
/// 缓存下来就变成「测试里手抄了一份引擎输出」。
TetraploidGametes get _data => tetraploidGametes(_kGenotype);
