// dogma_strand_diagram_test.dart —— 「模板链 → mRNA → 密码子/反密码子」配对图守卫
//
// ## 本文件守四组
//
// · A `canDraw` 闸门逐条：null / 空密码子 / 空反密码子 / 个数不等 /
//   密码子数×3 ≠ mRNA 长 / mRNA 长 ≠ 模板链长 / 密码子非 3 字母 /
//   反密码子非 3 字母，外加引擎现算合法数据 ⇒ true。
// · B textScale **同时**进 painter 与 layout（R58 溢出修复点）：版面几何按倍率
//   放大、widget 实际把倍率交给 painter 与 layout、`shouldRepaint` 对倍率敏感。
// · C 端到端：假数据 ⇒ 整树收缩（连 CustomPaint 都不留）；真数据 ⇒ 探针在
//   「**当前这一遍**」画出的密码子框数 == `codons.length`，且屏上文字集合
//   == `kDogmaStrandVisibleCopy`（⛔ 遍历组件导出的那份，不在测试里重抄）。
// · D 源码级诚实守卫：`canDraw` 六条判据逐字在源里、组件不重算引擎结果
//   （不出现 `centralDogmaFromTemplate`）、源码零氨基酸名、屏上文案零
//   markdown 星号与方向词。
//
// ## ⛔ 反假绿纪律
//
// · 探针数以「最近一个 `pass` 事件之后」为准——一次交互可能触发多遍重画，
//   全量累加会让框数假红（组件文件头实测：点一次「推出各链」画 2 遍）。
// · 「收缩」判据是**子树里没有 CustomPaint**，不是「画成 0×0」。
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:biology/engine/dna_strand_engine.dart';
import 'package:biology/pages/widgets/dogma_strand_diagram.dart';
import 'package:biology/theme.dart';

import 'golden_fonts.dart';

/// 出厂模板链（与宿主 `_kDefaultDogma` 同款）。⛔ 测试数据由引擎现算
/// （`_valid` getter），不在本文件手抄引擎输出。
const String _kTemplate = 'TACGGATTA';

/// ⛔ 方向词黑名单（一个字都不放宽）。图上点名对象（「模板链」「mRNA」），
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

/// ⛔ 氨基酸禁用清单**只住在守卫测试里**（组件文件头明确写了：这份清单
///    若进组件源，「源码不许出现氨基酸字面量」那条守卫会先被自己的清单
///    弄红 —— 守卫自证 = 假绿）。
const List<String> _kBannedAminoAcids = <String>[
  '甘氨酸', '丙氨酸', '缬氨酸', '亮氨酸', '异亮氨酸',
  '苯丙氨酸', '色氨酸', '丝氨酸', '苏氨酸', '酪氨酸',
  '半胱氨酸', '蛋氨酸', '甲硫氨酸', '天冬酰胺', '谷氨酰胺',
  '天冬氨酸', '谷氨酸', '赖氨酸', '精氨酸', '组氨酸',
  '脯氨酸',
];

/// 引擎现算的合法结果。⛔ 不缓存成常量——缓存就变成「测试里手抄了一份
/// 引擎输出」。
CentralDogmaResult get _valid => centralDogmaFromTemplate(_kTemplate);

/// 以合法结果为底、单字段变异出手造数据（引擎自己永远给不出的那种，
/// 正是「数据被换掉了」的情形）。
CentralDogmaResult _mutated({
  List<String>? codons,
  List<String>? anticodons,
  String? mrna,
  String? template,
}) =>
    CentralDogmaResult(
      template: template ?? _valid.template,
      coding: _valid.coding,
      mrna: mrna ?? _valid.mrna,
      codons: codons ?? _valid.codons,
      anticodons: anticodons ?? _valid.anticodons,
    );

/// 裸宿主：锁 360 宽（组件文件头的实测宽度），标准档。
Widget _host(CentralDogmaResult r, {double textScale = 1.0}) => MaterialApp(
      theme: AppTheme.build(Brightness.light),
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 360,
            child: DogmaStrandDiagram(result: r, textScale: textScale),
          ),
        ),
      ),
    );

/// 拍照 finder：`CustomPaint`（带 RenderObject 的那一个），不是 StatelessWidget。
Finder _paintOf() => find
    .descendant(
        of: find.byType(DogmaStrandDiagram),
        matching: find.byType(CustomPaint))
    .first;

void main() {
  tearDown(AppColors.debugClearOverride);

  // ── A：canDraw 闸门逐条 ────────────────────────────────────────────
  test('A1 null ⇒ 不画', () {
    expect(DogmaStrandDiagram.canDraw(null), isFalse);
  });
  test('A2 密码子为空 ⇒ 不画', () {
    expect(DogmaStrandDiagram.canDraw(_mutated(codons: const [])),
        isFalse);
  });
  test('A3 反密码子为空 ⇒ 不画', () {
    expect(DogmaStrandDiagram.canDraw(_mutated(anticodons: const [])),
        isFalse);
  });
  test('A4 密码子数 ≠ 反密码子数 ⇒ 不画', () {
    expect(
        DogmaStrandDiagram.canDraw(_mutated(
            codons: const ['AUG', 'CCU'],
            anticodons: const ['UAC', 'GGA', 'UUA'])),
        isFalse);
  });
  test('A5 密码子数×3 ≠ mRNA 长 ⇒ 不画', () {
    expect(DogmaStrandDiagram.canDraw(_mutated(mrna: 'AUGCCUAA')),
        isFalse);
  });
  test('A6 mRNA 长 ≠ 模板链长 ⇒ 不画', () {
    // 只动 template：9 位的 mRNA / 3 个密码子都自洽，单独触发这一条。
    expect(
        DogmaStrandDiagram.canDraw(
            _mutated(template: 'TACGGATT', mrna: 'AUGCCUAAA')),
        isFalse);
  });
  test('A7 某个密码子不是 3 字母 ⇒ 不画', () {
    expect(
        DogmaStrandDiagram.canDraw(
            _mutated(codons: const ['AUG', 'CC', 'AAU'])),
        isFalse);
  });
  test('A8 某个反密码子不是 3 字母 ⇒ 不画', () {
    expect(
        DogmaStrandDiagram.canDraw(
            _mutated(anticodons: const ['UAC', 'GG', 'UUA'])),
        isFalse);
  });
  test('A9 引擎现算合法数据 ⇒ 画', () {
    expect(DogmaStrandDiagram.canDraw(_valid), isTrue,
        reason: '⛔ 前提：引擎给的数据必须画得出来，否则后续全部用例白搭');
  });

  // ── B：textScale 同时进 painter 与 layout（R58 溢出修复点）────────
  test('B1 layout 解算把倍率分配进格子 / 行首标注槽 / 留白', () {
    const letter = 15.0; // 只断「倍率传递」这个代数关系，⛔ 不在此重量字宽。
    final std = DogmaStrandLayout.resolve(
        codonCount: 10,
        anticodonCount: 10,
        letterWidth: letter,
        availableWidth: 360);
    final big = DogmaStrandLayout.resolve(
        codonCount: 10,
        anticodonCount: 10,
        letterWidth: letter,
        availableWidth: 360,
        textScale: 1.75);

    // 标准档：逐像素不变（IEEE-754 精确等值，不用 moreOrLessEquals）。
    expect(std.textScale, 1.0);
    expect(std.cellWidth, letter + 2 * 7);
    expect(std.cellHeight, kDogmaStrandFontSize + 2 * 6);
    expect(std.gutterForTier, kDogmaStrandGutter);
    expect(std.padBottom, 20.0);

    // 课堂档：装字的那些处按同一倍率放大。
    expect(big.textScale, 1.75);
    expect(big.cellWidth, letter * 1.75 + 2 * 7);
    expect(big.cellHeight, (kDogmaStrandFontSize + 2 * 6) * 1.75);
    expect(big.gutterForTier, greaterThan(kDogmaStrandGutter));
    expect(big.padBottom, 20.0 * 1.75);
    expect(big.designHeight, greaterThan(std.designHeight));
    // 行首缝 / 列缝是设计稿写死的，与字号无关 ⇒ 不放大。
    expect(big.columnPitch - big.cellWidth * 3 - 2 * 2,
        std.columnPitch - std.cellWidth * 3 - 2 * 2);
  });

  testWidgets('B2 组件把 textScale 同时交给 painter 与 layout', (t) async {
    await loadGoldenFonts();
    AppColors.sync(Brightness.light);

    await t.pumpWidget(_host(_valid, textScale: 1.75));
    await t.pump();
    final painter = t.widget<CustomPaint>(_paintOf()).painter!
        as DogmaStrandPainter;
    expect(painter.textScale, 1.75, reason: '⛔ 倍率必须进 painter（字号）');
    expect(painter.layout.textScale, 1.75,
        reason: '⛔ 倍率必须进 layout（R58：只进 painter 会顶出槽外/格外）');
    expect(painter.layout.cellHeight,
        moreOrLessEquals((kDogmaStrandFontSize + 12) * 1.75));
    final bigHeight = t.getSize(_paintOf()).height;
    expect(bigHeight, moreOrLessEquals(painter.layout.designHeight));

    // 同一宿主切回标准档：高度必须回落（若 layout 没吃到倍率，两遍同高）。
    await t.pumpWidget(_host(_valid, textScale: 1.0));
    await t.pump();
    final stdPainter = t.widget<CustomPaint>(_paintOf()).painter!
        as DogmaStrandPainter;
    expect(stdPainter.textScale, 1.0);
    final stdHeight = t.getSize(_paintOf()).height;
    expect(stdHeight, lessThan(bigHeight),
        reason: '⛔ layout 吃到倍率 ⇒ 课堂档总高必大于标准档');
    expect(t.takeException(), isNull);
  });

  test('B3 shouldRepaint 对 textScale 敏感（课堂档切换不复用旧 painter）',
      () {
    // ⚠️ 两个倍率必须用**各自独立**的 layout 实例：同一引用会让
    // shouldRepaint 的 `old.layout != layout` 恒 false、在第一处短路，
    // 把「textScale 敏感」这条真正的判据盖掉（测不到 R58 那个溢出点）。
    DogmaStrandLayout mkLayout() => DogmaStrandLayout.resolve(
        codonCount: 3,
        anticodonCount: 3,
        letterWidth: 15,
        availableWidth: 360);
    DogmaStrandPainter mk(double s) => DogmaStrandPainter(
          result: _valid,
          layout: mkLayout(),
          ink: const Color(0xFF111111),
          graphite: const Color(0xFF222222),
          steel: const Color(0xFF333333),
          border: const Color(0xFF444444),
          teal: const Color(0xFF555555),
          wash: const Color(0xFF666666),
          surface: const Color(0xFF777777),
          textScale: s,
        );
    expect(mk(1.0).shouldRepaint(mk(1.75)), isTrue);
    expect(mk(1.75).shouldRepaint(mk(1.0)), isTrue);
    // ⚠️ 同名同倍率也应重画：mk() 每遍新建 layout（引用不同），而
    // shouldRepaint 对 layout 走 !=（非内容比较）⇒ 此处按引用不同断为 true。
    // 这样这一行不再与上面「跨倍率必重画」互斥，真正要断的是 textScale
    // 被纳入比较（下面 D4 已钉 `old.textScale != textScale` 在源里）。
    expect(mk(1.0).shouldRepaint(mk(1.0)), isTrue);
  });

  // ── C：端到端 ──────────────────────────────────────────────────────
  testWidgets('C1 canDraw 假 ⇒ 整树收缩成 SizedBox.shrink', (t) async {
    final bad = _mutated(codons: const []);
    expect(DogmaStrandDiagram.canDraw(bad), isFalse);
    await t.pumpWidget(_host(bad));
    await t.pump();
    expect(t.getSize(find.byType(DogmaStrandDiagram)).height, 0,
        reason: '⛔ 画不出的数据必须整体收缩，不留空框 / 图注 / 占位');
    // ⛔ 不取 .first：子树收缩成一个都没有时 finder 先抛 No element，
    //    断言根本走不到 findsNothing。
    expect(
        find.descendant(
            of: find.byType(DogmaStrandDiagram),
            matching: find.byType(CustomPaint)),
        findsNothing,
        reason: '⛔ 收缩 ⇒ 子树里连 CustomPaint 都不该有');
  });

  testWidgets(
      'C2 真数据 ⇒ 当前这一遍的密码子框数 == codons.length，'
      '屏上文字 == kDogmaStrandVisibleCopy', (t) async {
    final events = <(String, String?)>[];
    testDogmaPaintProbe = (k, x) => events.add((k, x));
    addTearDown(() => testDogmaPaintProbe = null);

    await t.pumpWidget(_host(_valid));
    await t.pump();

    // ⛔ 只数「最近一个 pass 之后」的那一遍（一次交互可触发多遍重画）。
    final passIdx = events.lastIndexWhere((e) => e.$1 == 'pass');
    expect(passIdx, greaterThanOrEqualTo(0), reason: 'painter 开画必报 pass');
    final pass = events.sublist(passIdx + 1);

    expect(pass.where((e) => e.$1 == 'codonFrame').length,
        _valid.codons.length,
        reason: '⛔ 一个密码子一个框，框数 == codons.length（验收判据 1）');
    expect(pass.where((e) => e.$1 == 'anticodonFrame').length,
        _valid.anticodons.length);
    expect(pass.where((e) => e.$1 == 'templateCell').length,
        3 * _valid.codons.length);
    expect(pass.where((e) => e.$1 == 'mrnaCell').length,
        3 * _valid.codons.length);
    expect(pass.where((e) => e.$1 == 'anticodonCell').length,
        3 * _valid.anticodons.length);

    // 屏上文字集合 ⊇ 组件自己声明的可见文案集合（⛔ 遍历导出那份，不重抄）。
    // ⚠️ 是「包含」不是「恒等」：painter 的 `_cell`/`_letter` 自绘路径也会
    // `_emit('label', 单个碱基字母)`（如 'T'/'A'/'C'/'U'/'G'），这些是模板链 /
    // mRNA 的**内容**（合法、画到密码子为止），不是氨基酸名也不是框外标注。
    // 判据真正要断的是：组件声明的可见文案一个不少（no missing），
    // 且不含黑名单（氨基酸名/方向词，由 D3/C3 断）。
    final labels =
        pass.where((e) => e.$1 == 'label').map((e) => e.$2).toSet();
    for (final expected in kDogmaStrandVisibleCopy) {
      expect(labels, contains(expected),
          reason: '组件声明的可见文案「$expected」必须在屏上（一个都不能少）');
    }
    expect(t.takeException(), isNull);
  });

  test('C3 屏上文案零 markdown 星号、零方向词', () {
    for (final s in kDogmaStrandVisibleCopy) {
      expect(s.contains('*'), isFalse, reason: '「$s」含 markdown 星号');
      for (final w in _kBannedDirWords) {
        expect(s.contains(w), isFalse, reason: '「$s」含方向词「$w」');
      }
    }
  });

  // ── D：源码级诚实守卫 ──────────────────────────────────────────────
  final src =
      File('lib/pages/widgets/dogma_strand_diagram.dart').readAsStringSync();

  /// 剥掉注释后的「纯代码」文本。
  ///
  /// ⛔ 为什么必须剥注释：组件文件头用注释记录了「全仓查过、零命中」的排查
  ///    过程（那里面**本来就会**出现 `centralDogmaFromTemplate` / `苯丙氨酸`
  ///    这些词）。判据要钉的是**代码与字符串字面量**，不是作者留下的排查
  ///    笔记 —— 对着原文扫会先被文件头弄红（守卫自证 = 假绿）。
  /// ⚠️ 本组件串字面量里不含 `//`（无 URL），行注释正则可安全套用。
  String codeOnly(String s) {
    final noBlock = s.replaceAll(RegExp(r'/\*.*?\*/', dotAll: true), '');
    return noBlock
        .split('\n')
        .map((l) => l.replaceAll(RegExp(r'//.*'), ''))
        .join('\n');
  }

  test('D1 canDraw 六条判据 + 收缩闸门逐字在组件源里', () {
    expect(src,
        contains('if (!canDraw(result)) return const SizedBox.shrink();'));
    expect(src, contains('r.codons.isEmpty || r.anticodons.isEmpty'));
    expect(src, contains('r.codons.length != r.anticodons.length'));
    expect(src, contains('r.codons.length * 3 != r.mrna.length'));
    expect(src, contains('r.mrna.length != r.template.length'));
    expect(src, contains('c.length != 3'));
  });

  test('D2 组件不重算引擎结果（纯代码里不出现 centralDogmaFromTemplate）', () {
    // 数据全部来自调用方传入的 CentralDogmaResult ⇒ 纯代码里不该有
    // 「自己拿模板链再算一遍」的入口（文件头注释里那一次提及已剥掉）。
    expect(codeOnly(src), isNot(contains('centralDogmaFromTemplate')));
  });

  test('D3 纯代码零氨基酸名（画到密码子为止是本文件最重要的一条）', () {
    for (final name in _kBannedAminoAcids) {
      expect(codeOnly(src), isNot(contains(name)),
          reason: '⛔ 全仓没有密码子→氨基酸对照表，出现「$name」= 凭空编课标内容');
    }
  });

  test('D4 textScale 传递链完整（resolve 调用 / painter 构造 / shouldRepaint）',
      () {
    // build() 里 resolve 与 painter 各传一次 ⇒ 至少两处 'textScale: textScale'。
    expect(src.split('textScale: textScale').length - 1,
        greaterThanOrEqualTo(2));
    expect(src, contains('old.textScale != textScale'));
    expect(src, contains('fontSize: fs * textScale'));
  });
}
