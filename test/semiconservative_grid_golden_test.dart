// semiconservative_grid_golden_test.dart —— 「半保留复制 2ⁿ 个分子」格阵
// 像素基线（浅 / 深）。
//
// 只拍示意图组件本身（不进宿主页）：裸宿主 + `AppColors.sync` 锁档 +
// `loadGoldenFonts` 装字体（⛔ 方框基线 = 假绿）+ `assertMonoLoaded`
// （⛔ 本图一格边长由 `AppFonts.mono` 量出，mono 不装 = 格宽是方框宽度、
// 基线对「一格 = 一个分子」的几何完全失明），拍带 RenderObject 的
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

import 'package:biology/engine/dna_engine.dart';
import 'package:biology/pages/widgets/semiconservative_grid.dart';
import 'package:biology/theme.dart';

import 'golden_fonts.dart';

/// 出厂复制次数。选 **3 代**（`copies = 3` ⇒ 分子总数 8、含亲代链 2、
/// 新合成链 14）：格阵里「8 格只亮 2 格」的对比最完整。
/// ⛔ **测试数据一律从引擎取**（`_data` getter），不在本文件里手抄
///    「引擎会输出什么」。
const int _kCopies = 3;

/// 图的宿主宽度。
///
/// ⚠️ ⛔ **本图必须给一个确定的宽度**：画布与容量都来自 `LayoutBuilder` 的
///    `c.maxWidth`，每行放几格与总容量按它算 ⇒ 宿主宽度一旦浮动（整屏 /
///    无界），基线就不可复现。这里锁 320（组件 `kSemiconservativeDesignWidth`
///    同档）⇒ 基线录在 **scale = 1.0** 上，像素与设计稿 1:1。
const double _kHostWidth = 320;

/// 裸宿主：只挂裸图 ⇒ 基线里出现的每一像素都来自图自己。
Widget _host(Brightness b, DnaReplicationResult r) => MaterialApp(
      theme: AppTheme.build(b),
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: _kHostWidth,
            child: SemiconservativeGrid(result: r),
          ),
        ),
      ),
    );

/// 拍照的 finder：`CustomPaint`（**带 RenderObject 的那一个**）。
///
/// ⛔ **不能**用 `find.byType(SemiconservativeGrid)`：那是
///    `StatelessWidget`，本身**不是 RenderObject**，`matchesGoldenFile`
///    取不到它的 render object，最后落到**整屏** ⇒ 基线对「宿主长什么样」
///    过度敏感、对「图画在哪」几乎无约束。
Finder _paintOf() => find
    .descendant(
        of: find.byType(SemiconservativeGrid),
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
    final a = File('${dir}semiconservative_grid_light.png');
    final b = File('${dir}semiconservative_grid_dark.png');
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
    testWidgets(
        '${tier.label}像素基线（3 次复制 ⇒ 8 个分子：2 格高亮、6 格普通）',
        (t) async {
      // ⛔ 字体不装载 ⇒ 基线里的说明文字与格宽会是一排空心方框，而布局
      //    正是按方框宽度算的 ⇒ 基线对「文本内容」完全失明（假绿）。mono
      //    尤为关键：一格边长 = mono 数字推进宽。
      await loadGoldenFonts();
      assertMonoLoaded();
      AppColors.sync(tier.b);
      await t.pumpWidget(_host(tier.b, _data));
      // ⛔ 这是纯 `CustomPaint`，**不需要** runAsync / precacheImage。
      await t.pump();
      expect(t.takeException(), isNull);
      await expectLater(_paintOf(),
          matchesGoldenFile('goldens/semiconservative_grid_${tier.tag}.png'));
    });
  }

  // ── K：⛔ 基线不许是一张「什么都没画」的图 ──────────────────────
  //
  // ⛔ **为什么必须先证明合法数据真的画得出来**：`dataReason` 判不过
  //    ⇒ 整棵子树收缩成 `SizedBox.shrink()` ⇒ 那样录出来的是一张纯底色
  //    小 PNG，它照样存在、照样比对通过。
  testWidgets('K1 喂引擎算出的合法数据 ⇒ 真的有 CustomPaint 且高度 = 版面总高',
      (t) async {
    await loadGoldenFonts();
    assertMonoLoaded();
    AppColors.sync(Brightness.light);
    expect(SemiconservativeGrid.dataReason(_data), isNull,
        reason: '⛔ 前提：引擎给的这份数据必须画得出来');
    expect(SemiconservativeGrid.skipReason(_data, _kHostWidth), isNull,
        reason: '⛔ 前提：$_kHostWidth 宽下必须画得下');
    // 期望高度由布局自己解算（与 painter 同一份几何），⛔ 不写死某个数。
    final layout = resolveSemiconservativeLayout(
      result: _data,
      availableWidth: _kHostWidth,
      ink: AppColors.ink,
      graphite: AppColors.graphite,
    );
    expect(layout, isNotNull);
    await t.pumpWidget(_host(Brightness.light, _data));
    await t.pump();
    final paint = _paintOf();
    expect(paint, findsOneWidget,
        reason: '⛔ 合法数据下组件必须真的画图；否则录出来的基线是空图');
    expect(t.getSize(paint).height, moreOrLessEquals(layout!.designHeight),
        reason: '⛔ 高度必须等于「布局自己算出的总高」，⛔ 不是某个写死的数');
    expect(t.takeException(), isNull);
  });

  testWidgets('K2 ⛔ 喂自相矛盾的数据 ⇒ 整棵子树收缩成 SizedBox.shrink',
      (t) async {
    // ⛔ 分子总数照抄引擎（8），但 `newStrands` 写成 13（真值 14）
    //    ⇒ 新合成链数与分子总数对不上（13 ≠ 8×2−2）⇒ 组件整棵子树收缩。
    final good = _data;
    final bad = DnaReplicationResult(
      copies: _kCopies,
      dnaMolecules: good.dnaMolecules,
      withParentStrand: good.withParentStrand,
      newStrands: good.newStrands - 1, // ⛔ 14 → 13
    );
    expect(SemiconservativeGrid.dataReason(bad), isNotNull,
        reason: '⛔ 前提：这组数据必须画不出来（新链数 ≠ 分子×2−2）');
    await loadGoldenFonts();
    AppColors.sync(Brightness.light);
    await t.pumpWidget(_host(Brightness.light, bad));
    await t.pump();
    expect(t.getSize(find.byType(SemiconservativeGrid)).height, 0,
        reason: '⛔ 画不出的数据下必须整体收缩，不留空框 / 依据行 / 占位');
    // ⛔ **这里不能写 `_paintOf()`**：它带 `.first`，子树收缩成一个都没有时
    //    finder 自己先抛 `Bad state: No element` ⇒ 断言根本走不到
    //    `findsNothing`。正确写法是同一条 descendant 链但**不取 first**。
    expect(
        find.descendant(
            of: find.byType(SemiconservativeGrid),
            matching: find.byType(CustomPaint)),
        findsNothing,
        reason: '⛔ 收缩 ⇒ 子树里连 CustomPaint 都不该有');
  });
}

/// 这一组出厂数据。⛔ 由引擎现算，⛔ 不缓存成常量 ——
/// 缓存下来就变成「测试里手抄了一份引擎输出」。
DnaReplicationResult get _data => dnaReplication(copies: _kCopies);
