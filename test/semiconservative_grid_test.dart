// semiconservative_grid_test.dart —— 「半保留复制 2ⁿ 个分子」格阵守卫
//
// ## 本文件守五组
//
// · A 数据闸 `dataReason` / `skipReason` / `canDraw` 逐条：null / 负数计数 /
//   复制次数 < 1 / 分子总数 < 1 / 含亲代链分子数超总数 / 新合成链数与
//   分子总数对不上（≠ 分子×2−2，引擎构造公式的逆校验）/ 引擎现算
//   n=1 与 n=3 ⇒ 画 / 容量闸（2ⁿ 爆格 ⇒ 明写「本图不画」，零静默截断）。
// · B 格数逐字取自引擎字段：端到端探针数出「高亮」格数 ==
//   `withParentStrand`、总格数 == `dnaMolecules`；变异 `withParentStrand`
//   ⇒ 高亮格数跟着变（⛔ 高亮数不写死成 2）。
// · C 诚实缺口与措辞守卫：位置说明句（软件只给个数、没给位置、图上
//   取靠前的）真的画在屏上；屏上文案与依据行零推广词（无论/总是/恒为/
//   永远/一般/必然/任意/一定等于）、零 markdown 星号、零方向词。
// · D 源码级诚实守卫：数据闸判据逐字在源、格数与高亮数逐字取自引擎
//   字段、纯代码零位图（drawImage / AssetImage / …）、零写死比例
//   （不出现 `labeledMoleculeRatio`、无 `数字%` 字面量）、textScale 传递链
//   完整、可见文案集合 ⊇ 组件自己声明的那一份（⛔ 不在测试里重抄）。
// · E `shouldRepaint` 对课堂倍率敏感（切档不复用旧 painter）。
//
// ## ⛔ 反假绿纪律
//
// · 测试数据一律由 `dnaReplication` 现算（`_valid` getter），⛔ 不缓存
//   成常量——缓存下来就变成「测试里手抄了一份引擎输出」。
// · 探针数以「最近一个 `pass` 事件之后」为准——一次交互可能触发多遍重画，
//   全量累加会让格数假红。
// · 「收缩」判据是**子树里没有 CustomPaint**，不是「画成 0×0」。
// · 凡碰 `resolveSemiconservativeLayout` / `TextPainter` 的用例一律
//   `testWidgets`（普通 `test()` 没有 binding，`TextPainter.layout()` 会抛）。
// · 容量边界（320 宽 ⇒ n≤9 那一档）依赖字体实测 advance，跨环境会漂移 ⇒
//   本文件只断「n=3 必画、n=40 必拒」这两个远离边界的档位，不碰 n=9/10。
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:biology/engine/dna_engine.dart';
import 'package:biology/pages/widgets/semiconservative_grid.dart';
import 'package:biology/theme.dart';

import 'golden_fonts.dart';

/// ⛔ 推广词黑名单（一个字都不放宽）。依据行只许复述引擎算出了什么，
///    不许把引擎的硬编码常量说成一般性结论。
const List<String> _kBannedGeneralizationWords = <String>[
  '无论',
  '总是',
  '恒为',
  '永远',
  '一般',
  '必然',
  '任意',
  '一定等于',
];

/// ⛔ 方向词黑名单（一个字都不放宽）。图上点名对象（「高亮格」「格阵」），
///    不用「上面/下面/左/右」——读屏软件把方向词读出来等于没有。
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

/// 引擎现算的合法结果（n=3 ⇒ 8 分子 / 含亲代链 2 / 新合成链 14）。
/// ⛔ 不缓存成常量——缓存就变成「测试里手抄了一份引擎输出」。
DnaReplicationResult get _valid => dnaReplication(copies: 3);

/// 以合法结果为底、单字段变异出手造数据（引擎自己永远给不出的那种，
/// 正是「数据被换掉了」的情形）。
DnaReplicationResult _mutated({
  int? copies,
  int? dnaMolecules,
  int? withParentStrand,
  int? newStrands,
}) =>
    DnaReplicationResult(
      copies: copies ?? _valid.copies,
      dnaMolecules: dnaMolecules ?? _valid.dnaMolecules,
      withParentStrand: withParentStrand ?? _valid.withParentStrand,
      newStrands: newStrands ?? _valid.newStrands,
    );

/// 裸宿主：锁 320 宽（组件 `kSemiconservativeDesignWidth` 同档），标准档。
Widget _host(DnaReplicationResult r, {double textScale = 1.0}) => MaterialApp(
      theme: AppTheme.build(Brightness.light),
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 320,
            child: SemiconservativeGrid(result: r, textScale: textScale),
          ),
        ),
      ),
    );

void main() {
  tearDown(AppColors.debugClearOverride);

  // ── A：数据闸逐条 ────────────────────────────────────────────────
  test('A1 null ⇒ 不画（dataReason 给一句人话）', () {
    expect(SemiconservativeGrid.dataReason(null), isNotNull);
    expect(SemiconservativeGrid.canDraw(null, 320), isFalse);
  });

  test('A2 计数出现负数 ⇒ 不画', () {
    expect(SemiconservativeGrid.dataReason(_mutated(dnaMolecules: -1)),
        isNotNull);
    expect(SemiconservativeGrid.dataReason(_mutated(newStrands: -1)),
        isNotNull);
  });

  test('A3 复制次数 < 1 ⇒ 不画', () {
    expect(SemiconservativeGrid.dataReason(_mutated(copies: 0)), isNotNull);
  });

  test('A4 分子总数 < 1 ⇒ 不画', () {
    expect(SemiconservativeGrid.dataReason(_mutated(dnaMolecules: 0)),
        isNotNull);
  });

  test('A5 含亲代链分子数超总数 ⇒ 不画', () {
    expect(
        SemiconservativeGrid.dataReason(
            _mutated(withParentStrand: _valid.dnaMolecules + 1)),
        isNotNull);
  });

  test('A6 新合成链数与分子总数对不上 ⇒ 不画（引擎构造公式的逆校验）', () {
    // ⛔ 8 分子 ⇒ 引擎恒给新链 14；写成 13 = 数据被换掉 ⇒ 整图不画。
    final bad = _mutated(newStrands: _valid.newStrands - 1);
    expect(bad.newStrands, isNot(_valid.dnaMolecules * 2 - 2),
        reason: '⛔ 前提：这组数据确实违反 newStrands == 分子×2−2');
    expect(SemiconservativeGrid.dataReason(bad), isNotNull);
    expect(SemiconservativeGrid.canDraw(bad, 320), isFalse);
  });

  test('A7 引擎 n=1 ⇒ 画', () {
    final r = dnaReplication(copies: 1);
    expect(SemiconservativeGrid.dataReason(r), isNull);
    expect(SemiconservativeGrid.canDraw(r, 320), isTrue,
        reason: '⛔ 前提：n=1 必须画得出来，否则 B 组用例白搭');
  });

  test('A8 引擎 n=3 ⇒ 画', () {
    expect(SemiconservativeGrid.dataReason(_valid), isNull);
    expect(SemiconservativeGrid.canDraw(_valid, 320), isTrue);
  });

  testWidgets('A9 容量闸：2ⁿ 爆格 ⇒ 明写「本图不画」，不是静默截断', (t) async {
    await loadGoldenFonts();
    AppColors.sync(Brightness.light);
    final ok = dnaReplication(copies: 3);
    expect(SemiconservativeGrid.skipReason(ok, 320), isNull,
        reason: '⛔ 前提：n=3 在 320 宽下必须画得出来');
    final over = dnaReplication(copies: 40);
    expect(over.dnaMolecules, 1099511627776,
        reason: '⛔ 这组输入引擎算得出来，拒的是本图的格子数上限');
    final reason = SemiconservativeGrid.skipReason(over, 320);
    expect(reason, isNotNull, reason: '⛔ n=40 在 320 宽下必须拒');
    expect(reason, contains('${over.dnaMolecules}'));
    // ⛔ 组件 skipReason 文案是「超出的不画（不是只画一部分）」（非「本图不画」）。
    //    判据是「容量爆格时明写原因、零静默截断」⇒ 断「超出的不画」+ 分子总数。
    expect(reason, contains('超出的不画'));
  });

  // ── B：格数逐字取自引擎字段，高亮数不写死 ──────────────────────
  testWidgets(
      'B1 n=3 ⇒ 当前这一遍的总格数 == dnaMolecules、'
      '高亮格数 == withParentStrand', (t) async {
    final events = <(String, String?)>[];
    testSemiconservativePaintProbe = (k, x) => events.add((k, x));
    addTearDown(() => testSemiconservativePaintProbe = null);

    await loadGoldenFonts();
    AppColors.sync(Brightness.light);
    final r = _valid;
    await t.pumpWidget(_host(r));
    await t.pump();

    // ⛔ 只数「最近一个 pass 之后」的那一遍（一次交互可触发多遍重画）。
    final passIdx = events.lastIndexWhere((e) => e.$1 == 'pass');
    expect(passIdx, greaterThanOrEqualTo(0), reason: 'painter 开画必报 pass');
    final pass = events.sublist(passIdx + 1);

    expect(pass.where((e) => e.$1 == 'moleculeCell').length, r.dnaMolecules,
        reason: '⛔ 一格 = 一个分子：总格数 == 引擎 dnaMolecules');
    expect(
        pass
            .where((e) =>
                e.$1 == 'moleculeCell' && e.$2 == kSemiconservativeHighlightTag)
            .length,
        r.withParentStrand,
        reason: '⛔ 高亮格数 == 引擎 withParentStrand（验收判据，不硬编码）');
    expect(pass.where((e) => e.$1 == 'legend').length, 1);
    expect(pass.where((e) => e.$1 == 'note').length, 1);
    expect(pass.where((e) => e.$1 == 'basis').length, 1);
    expect(t.takeException(), isNull);
  });

  testWidgets('B2 变异 withParentStrand=3 ⇒ 高亮格数跟着变（不写死成 2）',
      (t) async {
    // ⛔ 引擎自己恒给 2；手造 3 是模拟「引擎将来给出别的数」——
    //    组件必须照字段画，而不是偷偷画回 2。
    final mutated = _mutated(withParentStrand: 3);
    expect(SemiconservativeGrid.dataReason(mutated), isNull,
        reason: '⛔ 前提：3 ≤ 8 且新链数仍对得上 ⇒ 数据闸放行');

    final events = <(String, String?)>[];
    testSemiconservativePaintProbe = (k, x) => events.add((k, x));
    addTearDown(() => testSemiconservativePaintProbe = null);

    await loadGoldenFonts();
    AppColors.sync(Brightness.light);
    await t.pumpWidget(_host(mutated));
    await t.pump();

    final passIdx = events.lastIndexWhere((e) => e.$1 == 'pass');
    final pass = events.sublist(passIdx + 1);
    expect(
        pass
            .where((e) =>
                e.$1 == 'moleculeCell' && e.$2 == kSemiconservativeHighlightTag)
            .length,
        3,
        reason: '⛔ 高亮格数必须等于变异后的字段值 3（写死成 2 会漏画）');
    expect(pass.where((e) => e.$1 == 'moleculeCell').length,
        mutated.dnaMolecules);
  });

  // ── C：诚实缺口与措辞守卫 ──────────────────────────────────────
  testWidgets('C1 位置说明句（软件只给个数、图上取靠前的）真的画在屏上',
      (t) async {
    final events = <(String, String?)>[];
    testSemiconservativePaintProbe = (k, x) => events.add((k, x));
    addTearDown(() => testSemiconservativePaintProbe = null);

    await loadGoldenFonts();
    AppColors.sync(Brightness.light);
    await t.pumpWidget(_host(_valid));
    await t.pump();

    final passIdx = events.lastIndexWhere((e) => e.$1 == 'pass');
    final pass = events.sublist(passIdx + 1);
    final drawnStrings =
        pass.map((e) => e.$2).whereType<String>().toList();
    // ⛔ 组件声明的可见文案每一句都真的画在屏上（一个都不能少）。
    for (final expected in kSemiconservativeVisibleCopy) {
      expect(drawnStrings.any((s) => s.contains(expected)), isTrue,
          reason: '组件声明的可见文案「$expected」必须在屏上');
    }
    // 诚实缺口句逐字上报（note 事件文本 == 位置说明常量，一字不差）。
    expect(
        pass
            .where((e) => e.$1 == 'note')
            .map((e) => e.$2)
            .whereType<String>(),
        contains(kSemiconservativePositionNote));
  });

  test('C2 屏上文案与依据行零推广词、零星号、零方向词', () {
    final basis = semiconservativeBasisText(_valid);
    final semantics = SemiconservativeGrid.semanticsLabel(_valid);
    final all = <String>[
      ...kSemiconservativeVisibleCopy,
      basis,
      semantics,
    ];
    for (final s in all) {
      expect(s.contains('*'), isFalse, reason: '「$s」含 markdown 星号');
      for (final w in _kBannedGeneralizationWords) {
        expect(s.contains(w), isFalse, reason: '「$s」含推广词「$w」');
      }
      for (final w in _kBannedDirWords) {
        expect(s.contains(w), isFalse, reason: '「$s」含方向词「$w」');
      }
    }
  });

  // ── D：源码级诚实守卫 ────────────────────────────────────────────
  final src =
      File('lib/pages/widgets/semiconservative_grid.dart').readAsStringSync();

  /// 剥掉注释后的「纯代码」文本。
  ///
  /// ⛔ 为什么必须剥注释：组件文件头用注释记录了设计取舍（那里面**本来
  ///    就会**出现「位图」「比例」「无论/总是」这些词——它们是禁令本身）。
  ///    判据要钉的是**代码与字符串字面量**，不是作者留下的设计笔记 ——
  ///    对着原文扫会先被文件头弄红（守卫自证 = 假绿）。
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
    expect(src, contains('if (r.copies < 1)'));
    expect(src, contains('if (r.dnaMolecules < 1)'));
    expect(src, contains('if (r.withParentStrand > r.dnaMolecules)'));
    expect(src, contains('if (r.newStrands != r.dnaMolecules * 2 - 2)'));
    expect(src, contains('if (result.dnaMolecules > layout.capacity)'));
  });

  test('D2 格数与高亮数逐字取自引擎字段（不重算、不写死）', () {
    expect(src, contains('i < result.dnaMolecules'));
    expect(src, contains('i < result.withParentStrand'));
    expect(src, contains('on ? kSemiconservativeHighlightTag'));
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

  test('D4 纯代码零写死比例（引擎给什么画什么）', () {
    // ⛔ 依据行的任何数字都来自引擎字段插值；源码里不许出现「数字%」
    //    字面量（% 比例是引擎文本自己的格式化，不经组件源码）。
    expect(codeOnly(src), isNot(contains('labeledMoleculeRatio')));
    expect(RegExp(r'\d+(?:\.\d+)?%').hasMatch(codeOnly(src)), isFalse,
        reason: '⛔ 组件源码出现「数字%」= 写死了比例');
  });

  test('D5 textScale 传递链完整（painter 构造 / shouldRepaint / 字号放大）', () {
    expect(src, contains('textScale: textScale'));
    expect(src, contains('old.textScale != textScale'));
    expect(src, contains('fontSize: fs * textScale'));
  });

  test('D6 屏上文案零 markdown 星号、零方向词（遍历组件导出的那份）', () {
    for (final s in kSemiconservativeVisibleCopy) {
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
    SemiconservativePainter mk(double s) {
      final layout = resolveSemiconservativeLayout(
        result: _valid,
        availableWidth: 320,
        ink: const Color(0xFF111111),
        graphite: const Color(0xFF222222),
      )!;
      return SemiconservativePainter(
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
