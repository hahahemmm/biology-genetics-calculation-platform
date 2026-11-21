// dna_label_bands_diagram_test.dart —— 「离心管带型」条图守卫（¹⁵N 密度梯度离心）
//
// ## 本文件守五组
//
// · A 数据闸 `dataReason` / `skipReason` / `canDraw` 逐条：null / 负数计数 /
//   含标记分子数超总数 / 全无标记分子数超总数 / 重带差额 ≠ 0（引擎的带型
//   文本对每个 n 都写「无重带」，差额非 0 = 数据不是引擎那一份）/
//   引擎现算 n=1（轻带 0 合法）与 n=3 ⇒ 画 / 容量闸（2ⁿ 爆格 ⇒ 明写
//   「本图不画」，零静默截断）。
// · B 带型逐字照抄引擎、不约分：`bandCellsOf` 三条（重 = 三字段之差、
//   中 = labeledMolecules、轻 = unlabeledOnlyMolecules）+ 三带之和 ==
//   totalMolecules（一格 = 一个分子）+ 布局解算不另算一份带型。
// · C 端到端：假数据 ⇒ 整树收缩（连 CustomPaint 都不留）；真数据 ⇒ 探针在
//   「**当前这一遍**」画出的格数逐字等于引擎字段，且屏上文字集合 ⊇
//   `kCentrifugeVisibleCopy`（⛔ 遍历组件导出的那份，不在测试里重抄）；
//   n=1 轻带 0 格 ⇒ 留一条中性细线（bandEmptyMark）。
// · D 源码级诚实守卫：数据闸判据逐字在源、`bandCellsOf` 逐字取自引擎字段、
//   纯代码零位图（drawImage / AssetImage / …）、纯代码零硬编码带型比例
//   （不出现 `labeledMoleculeRatio`、无 `%`）、textScale 传递链完整、
//   屏上文案零 markdown 星号与方向词。
// · E `shouldRepaint` 对课堂倍率敏感（切档不复用旧 painter）。
//
// ## ⛔ 反假绿纪律
//
// · 测试数据一律由 `dnaLabelReplication` 现算（`_valid` getter），⛔ 不缓存
//   成常量——缓存下来就变成「测试里手抄了一份引擎输出」。
// · 探针数以「最近一个 `pass` 事件之后」为准——一次交互可能触发多遍重画，
//   全量累加会让格数假红。
// · 「收缩」判据是**子树里没有 CustomPaint**，不是「画成 0×0」。
// · 凡碰 `resolveCentrifugeLayout` / `TextPainter` 的用例一律 `testWidgets`
//   （普通 `test()` 没有 binding，`TextPainter.layout()` 会抛）。
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:biology/engine/dna_strand_engine.dart';
import 'package:biology/pages/widgets/centrifuge_band_diagram.dart';
import 'package:biology/theme.dart';

import 'golden_fonts.dart';

/// ⛔ 方向词黑名单（一个字都不放宽）。图上点名对象（「重带」「中带」
///    「轻带」「离心管」），不用「上面/下面/左/右」——读屏软件把方向词
///    读出来等于没有。
const List<String> _kBannedDirWords = <String>[
  '上面',
  '下面',
  '上边',
  '下边',
  '左边',
  '右边',
  '左侧',
  '右侧',
  '上方',
  '下方',
  '上一行',
  '下一行',
];

/// 引擎现算的合法结果（n=3 ⇒ 8 分子 / 中带 2 / 轻带 6 / 重带 0）。
/// ⛔ 不缓存成常量——缓存就变成「测试里手抄了一份引擎输出」。
DnaLabelResult get _valid => dnaLabelReplication(generations: 3);

/// 以合法结果为底、单字段变异出手造数据（引擎自己永远给不出的那种，
/// 正是「数据被换掉了」的情形）。
DnaLabelResult _mutated({
  int? generations,
  int? totalMolecules,
  int? labeledMolecules,
  int? unlabeledOnlyMolecules,
  int? labeledStrands,
  int? totalStrands,
}) =>
    DnaLabelResult(
      generations: generations ?? _valid.generations,
      totalMolecules: totalMolecules ?? _valid.totalMolecules,
      labeledMolecules: labeledMolecules ?? _valid.labeledMolecules,
      unlabeledOnlyMolecules:
          unlabeledOnlyMolecules ?? _valid.unlabeledOnlyMolecules,
      labeledStrands: labeledStrands ?? _valid.labeledStrands,
      totalStrands: totalStrands ?? _valid.totalStrands,
      centrifugeBands: '（测试造的数据）',
    );

/// 裸宿主：锁 320 宽（组件 `kCentrifugeDesignWidth` 同档），标准档。
Widget _host(DnaLabelResult r, {double textScale = 1.0}) => MaterialApp(
      theme: AppTheme.build(Brightness.light),
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 320,
            child: CentrifugeBandDiagram(result: r, textScale: textScale),
          ),
        ),
      ),
    );

/// 拍照 finder：`CustomPaint`（带 RenderObject 的那一个），不是 StatelessWidget。
Finder _paintOf() => find
    .descendant(
        of: find.byType(CentrifugeBandDiagram),
        matching: find.byType(CustomPaint))
    .first;

void main() {
  tearDown(AppColors.debugClearOverride);

  // ── A：数据闸逐条 ────────────────────────────────────────────────
  test('A1 null ⇒ 不画（dataReason 给一句人话）', () {
    expect(CentrifugeBandDiagram.dataReason(null), isNotNull);
    expect(CentrifugeBandDiagram.canDraw(null, 320), isFalse);
  });

  test('A2 计数出现负数 ⇒ 不画', () {
    expect(CentrifugeBandDiagram.dataReason(_mutated(totalMolecules: -1)),
        isNotNull);
    expect(CentrifugeBandDiagram.dataReason(_mutated(labeledStrands: -1)),
        isNotNull);
  });

  test('A3 含亲代标记链分子数超总数 ⇒ 不画', () {
    expect(
        CentrifugeBandDiagram.dataReason(
            _mutated(labeledMolecules: _valid.totalMolecules + 1)),
        isNotNull);
  });

  test('A4 全无标记分子数超总数 ⇒ 不画', () {
    expect(
        CentrifugeBandDiagram.dataReason(
            _mutated(unlabeledOnlyMolecules: _valid.totalMolecules + 1)),
        isNotNull);
  });

  test('A5 重带差额 ≠ 0 ⇒ 不画（引擎每个 n 都写「无重带」）', () {
    // ⛔ 8 → 9：重带差额 = 9 − 2 − 6 = 1 ≠ 0 ⇒ 数据不是引擎那一份。
    final bad = _mutated(totalMolecules: _valid.totalMolecules + 1);
    expect(bandCellsOf(bad)[0], 1, reason: '⛔ 前提：差额确实是 1');
    expect(CentrifugeBandDiagram.dataReason(bad), isNotNull);
    expect(CentrifugeBandDiagram.canDraw(bad, 320), isFalse);
  });

  test('A6 引擎 n=1 ⇒ 画（轻带 0 是引擎的合法输出）', () {
    final r = dnaLabelReplication(generations: 1);
    expect(r.unlabeledOnlyMolecules, 0);
    expect(CentrifugeBandDiagram.dataReason(r), isNull);
    expect(CentrifugeBandDiagram.canDraw(r, 320), isTrue,
        reason: '⛔ 前提：n=1 必须画得出来，否则 C 组用例白搭');
  });

  test('A7 引擎 n=3 ⇒ 画', () {
    expect(CentrifugeBandDiagram.dataReason(_valid), isNull);
    expect(CentrifugeBandDiagram.canDraw(_valid, 320), isTrue);
  });

  testWidgets('A8 容量闸：2ⁿ 爆格 ⇒ 明写「本图不画」，不是静默截断', (t) async {
    await loadGoldenFonts();
    AppColors.sync(Brightness.light);
    final ok = dnaLabelReplication(generations: 8);
    expect(ok.totalMolecules, 256);
    expect(CentrifugeBandDiagram.skipReason(ok, 320), isNull,
        reason: '⛔ n=8 在 320 宽下必须画得出来');
    final over = dnaLabelReplication(generations: 40);
    expect(over.totalMolecules, 1099511627776,
        reason: '⛔ 这组输入引擎算得出来，拒的是本图的格子数上限');
    final reason = CentrifugeBandDiagram.skipReason(over, 320);
    expect(reason, isNotNull, reason: '⛔ n=40 在 320 宽下必须拒');
    expect(reason, contains('${over.totalMolecules}'));
    expect(reason, contains('本图不画'));
  });

  // ── B：带型逐字照抄引擎，不约分 ────────────────────────────────
  test('B1 bandCellsOf(n=3)：中 = labeledMolecules、轻 = unlabeledOnlyMolecules', () {
    final r = _valid;
    final cells = bandCellsOf(r);
    expect(cells.length, 3);
    // ⛔ 逐字取自引擎字段，不重算、不约分、不改比例。
    expect(cells[1], r.labeledMolecules,
        reason: '中带 = 引擎 labeledMolecules，逐字照抄');
    expect(cells[2], r.unlabeledOnlyMolecules,
        reason: '轻带 = 引擎 unlabeledOnlyMolecules，逐字照抄');
    expect(cells[0], r.totalMolecules - r.labeledMolecules - r.unlabeledOnlyMolecules,
        reason: '重带 = 三字段之差（引擎没有独立重带字段）');
    expect(cells[0], 0, reason: '引擎的带型文本对每个 n 都写「无重带」');
    // 一格 = 一个分子：三带格数之和 == 分子总数（不合并、不约分）。
    expect(cells[0] + cells[1] + cells[2], r.totalMolecules);
  });

  test('B2 bandCellsOf(n=1) = [0, 2, 0]（全中带，轻带 0）', () {
    final r = dnaLabelReplication(generations: 1);
    final cells = bandCellsOf(r);
    expect(cells[0], 0);
    expect(cells[1], r.labeledMolecules);
    expect(cells[2], r.unlabeledOnlyMolecules);
    expect(cells[2], 0);
  });

  test('B3 bandCellsOf(n=20)：大数也逐字照抄（2²⁰−2 不约分）', () {
    final r = dnaLabelReplication(generations: 20);
    expect(r.totalMolecules, 1048576);
    final cells = bandCellsOf(r);
    expect(cells[1], r.labeledMolecules);
    expect(cells[2], r.unlabeledOnlyMolecules);
    expect(cells[2], 1048574, reason: '轻带 = 2²⁰−2，引擎给什么画什么');
    expect(cells[0] + cells[1] + cells[2], r.totalMolecules);
  });

  testWidgets('B4 布局解算不另算一份带型（layout.bandCells == bandCellsOf）',
      (t) async {
    await loadGoldenFonts();
    AppColors.sync(Brightness.light);
    final layout = resolveCentrifugeLayout(
      result: _valid,
      availableWidth: 320,
      ink: AppColors.ink,
      graphite: AppColors.graphite,
    );
    expect(layout, isNotNull, reason: '⛔ 前提：320 宽下版面必须解得出来');
    expect(layout!.bandCells, bandCellsOf(_valid),
        reason: '⛔ 布局里的带型必须复用 bandCellsOf 那一份，不许重算');
  });

  // ── C：端到端 ────────────────────────────────────────────────────
  testWidgets('C1 假数据 ⇒ 整树收缩成 SizedBox.shrink', (t) async {
    final bad = _mutated(totalMolecules: _valid.totalMolecules + 1);
    expect(CentrifugeBandDiagram.canDraw(bad, 320), isFalse);
    await loadGoldenFonts();
    AppColors.sync(Brightness.light);
    await t.pumpWidget(_host(bad));
    await t.pump();
    expect(t.getSize(find.byType(CentrifugeBandDiagram)).height, 0,
        reason: '⛔ 画不出的数据必须整体收缩，不留空框 / 依据行 / 占位');
    // ⛔ 不取 .first：子树收缩成一个都没有时 finder 先抛 No element，
    //    断言根本走不到 findsNothing。
    expect(
        find.descendant(
            of: find.byType(CentrifugeBandDiagram),
            matching: find.byType(CustomPaint)),
        findsNothing,
        reason: '⛔ 收缩 ⇒ 子树里连 CustomPaint 都不该有');
  });

  testWidgets(
      'C2 n=3 ⇒ 当前这一遍的格数逐字等于引擎字段，'
      '屏上文字 ⊇ kCentrifugeVisibleCopy', (t) async {
    final events = <(String, String?)>[];
    testCentrifugePaintProbe = (k, x) => events.add((k, x));
    addTearDown(() => testCentrifugePaintProbe = null);

    await loadGoldenFonts();
    AppColors.sync(Brightness.light);
    final r = _valid;
    await t.pumpWidget(_host(r));
    await t.pump();

    // ⛔ 只数「最近一个 pass 之后」的那一遍（一次交互可触发多遍重画）。
    final passIdx = events.lastIndexWhere((e) => e.$1 == 'pass');
    expect(passIdx, greaterThanOrEqualTo(0), reason: 'painter 开画必报 pass');
    final pass = events.sublist(passIdx + 1);

    // 一格 = 一个分子：三带格数逐字等于引擎字段。
    expect(pass.where((e) => e.$1 == 'bandCell' && e.$2 == '重带').length, 0,
        reason: '⛔ 引擎写「无重带」⇒ 重带一格都不画');
    expect(pass.where((e) => e.$1 == 'bandCell' && e.$2 == '中带').length,
        r.labeledMolecules,
        reason: '⛔ 中带格数 == 引擎 labeledMolecules（验收判据）');
    expect(pass.where((e) => e.$1 == 'bandCell' && e.$2 == '轻带').length,
        r.unlabeledOnlyMolecules,
        reason: '⛔ 轻带格数 == 引擎 unlabeledOnlyMolecules（验收判据）');
    expect(pass.where((e) => e.$1 == 'bandCell').length, r.totalMolecules,
        reason: '⛔ 管里格数总数 == 引擎 totalMolecules，一格不多一格不少');
    expect(pass.where((e) => e.$1 == 'bandLabel').length, 3,
        reason: '⛔ 三条带各有一条「带名 + 格数」标注');
    expect(pass.where((e) => e.$1 == 'legend').length, 1);
    expect(pass.where((e) => e.$1 == 'basis').length, 1);

    // 屏上文字集合 ⊇ 组件自己声明的可见文案集合（⛔ 遍历导出那份，不重抄）。
    // ⚠️ 「basis」探针上报的是**整段依据行**（`引擎给出：…${centrifugeBands}
    //    $kCentrifugeHeavyNote` 拼接后的完整串），而 kCentrifugeVisibleCopy 里的
    //    kCentrifugeHeavyNote 是其中**一段**。直接 contains 整段会 false
    //    （basis 串比 HeavyNote 长）。⛔ 判据是「组件声明的每一句都真的画在
    //    屏上」⇒ 用 basis 串的**子串包含**断（HeavyNote 必须是 basis 的一部分）。
    final drawnStrings = pass.map((e) => e.$2).whereType<String>().toList();
    final basisText = pass
        .where((e) => e.$1 == 'basis')
        .map((e) => e.$2)
        .whereType<String>()
        .toList();
    for (final expected in kCentrifugeVisibleCopy) {
      final onScreen = drawnStrings.any((s) => s.contains(expected)) ||
          basisText.any((s) => s.contains(expected));
      expect(onScreen, isTrue,
          reason: '组件声明的可见文案「$expected」必须在屏上（一个都不能少）');
    }
    expect(t.takeException(), isNull);
  });

  testWidgets('C3 n=1 ⇒ 轻带 0 格也留一条中性细线（bandEmptyMark）', (t) async {
    final events = <(String, String?)>[];
    testCentrifugePaintProbe = (k, x) => events.add((k, x));
    addTearDown(() => testCentrifugePaintProbe = null);

    await loadGoldenFonts();
    AppColors.sync(Brightness.light);
    final r = dnaLabelReplication(generations: 1);
    expect(r.unlabeledOnlyMolecules, 0);
    await t.pumpWidget(_host(r));
    await t.pump();

    final passIdx = events.lastIndexWhere((e) => e.$1 == 'pass');
    final pass = events.sublist(passIdx + 1);
    expect(pass.where((e) => e.$1 == 'bandCell' && e.$2 == '轻带').length, 0);
    expect(pass.where((e) => e.$1 == 'bandEmptyMark' && e.$2 == '轻带').length,
        1,
        reason: '⛔ 0 格也要看得见那条带在那儿，否则学生会以为漏画了');
    expect(pass.where((e) => e.$1 == 'bandCell').length, r.totalMolecules);
  });

  // ── D：源码级诚实守卫 ────────────────────────────────────────────
  final src = File('lib/pages/widgets/centrifuge_band_diagram.dart')
      .readAsStringSync();

  /// 剥掉注释后的「纯代码」文本。
  ///
  /// ⛔ 为什么必须剥注释：组件文件头用注释记录了设计取舍（那里面**本来
  ///    就会**出现「位图」「比例」这些词）。判据要钉的是**代码与字符串
  ///    字面量**，不是作者留下的设计笔记 —— 对着原文扫会先被文件头弄红
  ///    （守卫自证 = 假绿）。
  /// ⚠️ 本组件串字面量里不含 `//`（无 URL），行注释正则可安全套用。
  String codeOnly(String s) {
    final noBlock = s.replaceAll(RegExp(r'/\*.*?\*/', dotAll: true), '');
    return noBlock
        .split('\n')
        .map((l) => l.replaceAll(RegExp(r'//.*'), ''))
        .join('\n');
  }

  test('D1 数据闸判据逐字在组件源里', () {
    expect(src,
        contains('if (dataReason(result) != null) return const SizedBox.shrink();'));
    expect(src, contains('if (v < 0)'));
    expect(src, contains('if (r.labeledMolecules > r.totalMolecules)'));
    expect(src, contains('if (r.unlabeledOnlyMolecules > r.totalMolecules)'));
    expect(src, contains('if (heavy != 0)'));
    expect(src, contains('if (layout.requiredRows > layout.rows)'));
  });

  test('D2 bandCellsOf 逐字取自引擎字段（不重算、不写死带型）', () {
    expect(src,
        contains('r.totalMolecules - r.labeledMolecules - r.unlabeledOnlyMolecules'));
    expect(src, contains('r.labeledMolecules'));
    expect(src, contains('r.unlabeledOnlyMolecules'));
  });

  test('D3 纯代码零位图（纯 CustomPainter / TextPainter 代码绘制）', () {
    for (final banned in <String>[
      'drawImage',
      'AssetImage',
      'ImageProvider',
      'MemoryImage',
      'FileImage',
      'NetworkImage',
      'precacheImage',
    ]) {
      expect(codeOnly(src), isNot(contains(banned)),
          reason: '⛔ 组件纯代码出现「$banned」= 用了位图，违反禁位图铁律');
    }
  });

  test('D4 纯代码零硬编码带型比例（引擎给什么画什么）', () {
    // ⛔ 引擎有 labeledMoleculeRatio 百分比 getter，组件一律不许碰；
    //    屏上也不许出现任何写死的百分比（带型比例逐格画，不约分）。
    expect(codeOnly(src), isNot(contains('labeledMoleculeRatio')));
    // ⚠️ 断的是「写死的带型百分比」，不是取模运算符 `%`——painter 网格
    //    布局 `i % layout.cols` 是合法算术。这里断的是 `%` 紧跟数字的
    //    「比例字面」形态（如 `50%`、`25.0%`），取模 `i % layout.cols`
    //    不匹配（`%` 后是空格+标识符）。
    expect(RegExp(r'\d+(?:\.\d+)?%').hasMatch(codeOnly(src)), isFalse,
        reason: '⛔ 组件源码出现「数字%」= 写死了带型比例（依据行的 % 来自引擎文本，'
            '由引擎自己格式化，组件源码里没有）');
  });

  test('D5 textScale 传递链完整（painter 构造 / shouldRepaint / 字号放大）', () {
    expect(src, contains('textScale: textScale'));
    expect(src, contains('old.textScale != textScale'));
    expect(src, contains('fontSize: fs * textScale'));
  });

  test('D6 屏上文案零 markdown 星号、零方向词', () {
    for (final s in kCentrifugeVisibleCopy) {
      expect(s.contains('*'), isFalse, reason: '「$s」含 markdown 星号');
      for (final w in _kBannedDirWords) {
        expect(s.contains(w), isFalse, reason: '「$s」含方向词「$w」');
      }
    }
  });

  // ── E：shouldRepaint 对课堂倍率敏感 ─────────────────────────────
  testWidgets('E1 倍率不同 ⇒ shouldRepaint true（课堂档切换不复用旧 painter）',
      (t) async {
    await loadGoldenFonts();
    AppColors.sync(Brightness.light);
    // ⚠️ 两个倍率必须用**各自独立**的 layout 实例：同一引用会让
    // shouldRepaint 的 `old.layout != layout` 恒 false、在第一处短路，
    // 把「textScale 敏感」这条真正的判据盖掉。
    CentrifugeBandPainter mk(double s) {
      final layout = resolveCentrifugeLayout(
        result: _valid,
        availableWidth: 320,
        ink: const Color(0xFF111111),
        graphite: const Color(0xFF222222),
      )!;
      return CentrifugeBandPainter(
        result: _valid,
        layout: layout,
        ink: const Color(0xFF111111),
        graphite: const Color(0xFF222222),
        steel: const Color(0xFF333333),
        border: const Color(0xFF444444),
        teal: const Color(0xFF555555),
        wash: const Color(0xFF666666),
        surface: const Color(0xFF777777),
        textScale: s,
      );
    }

    expect(mk(1.0).shouldRepaint(mk(1.75)), isTrue);
    expect(mk(1.75).shouldRepaint(mk(1.0)), isTrue);
  });
}
