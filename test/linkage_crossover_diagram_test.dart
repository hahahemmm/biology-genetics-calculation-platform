// ════════════════════════════════════════════════════════════════
//  test/linkage_crossover_diagram_test.dart
//  连锁互换「重组型是怎么来的」概念图：**推导规则守卫 + 端到端挂载 + 像素基线**
// ════════════════════════════════════════════════════════════════
//
//  ## 这份文件守什么
//
//  图本体是 `lib/pages/widgets/linkage_crossover_diagram.dart`（**纯代码绘制**、
//  零引擎依赖，只认一个值对象 [CrossoverFigure]）；宿主是
//  `lib/pages/widgets/linkage_tab.dart` 的 `_crossoverFigure` 闸门（五道判据，
//  null = 不挂图）。⇒ 每条用例都在问同一件事：**这张图会不会说错 / 该不该出现**。
//
//  五组断言：
//
//  · D 推导规则 —— 值对象自己：编号、参与交换、逐位互补、亲本型是谁、
//    实心/空心编码、一次分裂只一处交换。判据全部落在**产品自己的公开成员**
//    （`CrossoverFigure.chromatids`）上，⛔ 测试里不重抄一遍单交换的公式。
//  · F 数据驱动 —— 顺式 `AB/ab`、**反式 `Ab/aB`**、三位点**硬停**、
//    `r = 0` 的诚实处理、「参与交换」是推出来的。
//  · S 屏上文案 —— ⛔ 禁方向词、禁 markdown 星号（见下面「为什么扫的是这些串」）。
//  · E 端到端 —— 走**本仓**容器页：算出结果 ⇒ 图在；`r = 0` ⇒ 图不在。
//  · A 像素基线 —— 浅色 + 深色两张。
//
//  ## 为什么方向词守卫扫的是「图自己拼出来的串」而不是 `find.text`
//
//  这张图是**纯 CustomPaint**（`TextPainter` 直接画在 canvas 上），图内
//  **一个 `Text` widget 都没有** ⇒ 扫 `find.text` 只会扫到空集，是**假绿**。
//  ⇒ 判据落在 [LinkageCrossoverDiagram.semanticsLabel] 与 painter 的行数据
//    （编号 / 等位基因串 / 配子名）上：那正是 paint() 画出去的每一个串。
//    端到端那条另外扫一遍图子树的 `Text`，是为了钉住「屏上那一句小标题」也没
//    混进位置词。
//
//  ## 基线由谁录
//
//  ⛔ 录完必须**主线程目检**：`flutter test --update-goldens` 产出的两张 PNG
//     只在「版式没跑偏」这一层可信；字体是不是真字形（不是方框）仍要人眼确认。
//     本仓 `test/golden_fonts.dart` 的 `loadGoldenFonts` 保证了字体装载，
//     但**装载成功 ≠ 载荷里有汉字**（R12-1 记过两次静默失效）。
//
//  ## 测试数据一律从引擎取
//
//  ⛔ 不手抄「引擎会输出什么」：顺式/反式/三位的配子串都由
//    `LinkageEngine.gametesOf` 现算，再原样交给值对象。排序与「哪条参与交换」
//    是**产品代码**的活，测试不插手。
// ════════════════════════════════════════════════════════════════

import 'dart:io';

import 'package:biology/engine/fraction.dart';
import 'package:biology/engine/linkage_engine.dart';
import 'package:biology/pages/cross_calculator_page.dart';
import 'package:biology/pages/widgets/linkage_crossover_diagram.dart';
import 'package:biology/pages/widgets/linkage_tab.dart';
import 'package:biology/state/present_mode_controller.dart';
import 'package:biology/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'golden_fonts.dart';

/// 图的宿主。宽度锁在 [LinkageCrossoverDiagram.designWidth]（=320，
/// 也就是 painter 的设计坐标）⇒ 基线录在 **scale = 1.0** 上。
const double _kHostWidth = 320;

/// 顺式两座出厂输入（也是**像素基线**录的那一组）。
const String _kCisParent = 'AB/ab';

final LinkageEngine _engine = LinkageEngine();

/// ⛔ **测试数据一律从引擎取**，不手抄「引擎会输出什么」。
///
/// 顺式 `AB/ab` r=20% ⇒ `AB`/`ab` 各 0.4、`Ab`/`aB` 各 0.1；
/// 反式 `Ab/aB` r=20% ⇒ 亲本型是 `Ab`/`aB`，重组型才是 `AB`/`ab`。
/// 本函数只做「把引擎的输出原样交给值对象」，⛔ **不做任何取舍或排序**。
CrossoverFigure _figureOf(String parent, [Fraction? r]) {
  final p = _engine.parseParent(parent);
  final g = _engine.gametesOf(p, r ?? Fraction.approx(0.2));
  return CrossoverFigure(
    hap1: p.hap1,
    hap2: p.hap2,
    afterGametes: g.keys.toList(),
  );
}

/// 反式两座（`Ab/aB`）r=20%。
CrossoverFigure get _transFigure => _figureOf('Ab/aB');

/// `r = 0` 的那组数据（引擎把零概率的重组型删掉了 ⇒ 只剩两个键）。
/// 本文件用它**绕过宿主**直接喂给组件，验组件侧的兜底。
CrossoverFigure _noCrossoverFigure() {
  final p = _engine.parseParent(_kCisParent);
  final g = _engine.gametesOf(p, Fraction.zero);
  return CrossoverFigure(
    hap1: p.hap1,
    hap2: p.hap2,
    // 引擎此刻只给出两个键（重组型概率为 0 被删了）；一次减数分裂里恒有
    // 4 条染色单体 ⇒ 两条未参与的那条复制成两份（姐妹染色单体本就相同）。
    afterGametes: <String>[...g.keys, ...g.keys],
  );
}

/// ⛔ 方向词黑名单。点名对象（「1a」「Ab」「交换前」）而不是位置 —— 位置在
///    屏幕阅读器里是错的，而且深色档/窄屏/横屏下「上面」到底指哪条会变。
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

/// 按**编号**在一块行里取行（点名取，不用「第一条 / 最后一条」）。
///
/// 理由与 [_kBannedDirWords] 同源：断言里一旦出现「第 3 行」这种位置指代，
/// 哪天调了行序，断言就会指向另一条染色单体却仍然「绿」。
CrossoverRow _rowById(List<CrossoverRow> rs, String id) => rs.firstWhere(
      (r) => r.chromatid == id,
      orElse: () => throw StateError('这一块里没有编号 $id 的行，'
          '实际编号=${rs.map((r) => r.chromatid).toList()}'),
    );

/// 取值对象自己推出来的那条染色单体（**产品自己的公开成员**）。
CrossoverChromatid _chromatidById(CrossoverFigure f, String id) =>
    f.chromatids.firstWhere(
      (c) => c.id == id,
      orElse: () => throw StateError('没有编号 $id 的染色单体，'
          '实际编号=${f.chromatids.map((c) => c.id).toList()}'),
    );

/// 直接造 painter（**不建树**）：行数据、块标签、行文字样式都是纯函数，
/// 拿来守「图在教什么」不必付一次 pump 的钱。颜色逐个照
/// `LinkageCrossoverDiagram.build` 的实参给，不自造。
CrossoverPainter _painterOf(CrossoverFigure f) => CrossoverPainter(
      figure: f,
      canvasColor: AppColors.canvas,
      rodColor: AppColors.surfaceLow,
      bandColor: AppColors.teal,
      textColor: AppColors.ink,
    );

/// 图宿主（只挂裸图，不加标题/图例）。
Widget _host(Brightness b, [CrossoverFigure? figure]) => MaterialApp(
      theme: AppTheme.build(b),
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: _kHostWidth,
            child: LinkageCrossoverDiagram(
              figure: figure ?? _figureOf(_kCisParent),
            ),
          ),
        ),
      ),
    );

/// 拍照用 finder：⛔ **不能**用 `find.byType(LinkageCrossoverDiagram)`
/// （那是 StatelessWidget，本身不是 RenderObject ⇒ 基线会落到整屏，
/// 对「图画在哪」几乎无约束）。改拍带 RenderObject 的 `CustomPaint`。
Finder _paintFinder() => find.descendant(
      of: find.byType(LinkageCrossoverDiagram),
      matching: find.byType(CustomPaint),
    );

/// ⛔ 读 `lib/` 下某个源文件的**类体**（按花括号配平），供 F5 那条
///    「值对象里没有布尔标志」做**源码级**判据用。
String _classBodyOf(String libRelativePath, String className) {
  final f = File(libRelativePath);
  expect(f.existsSync(), isTrue, reason: '源文件应存在：$libRelativePath');
  final src = f.readAsStringSync();
  final head = src.indexOf('class $className');
  expect(head >= 0, isTrue, reason: '源文件里找不到 class $className');
  final open = src.indexOf('{', head);
  var depth = 0;
  for (var i = open; i < src.length; i++) {
    if (src[i] == '{') {
      depth++;
    } else if (src[i] == '}') {
      depth--;
      if (depth == 0) return src.substring(open + 1, i);
    }
  }
  fail('class $className 的花括号不配平');
}

/// 图**自己拼出来上屏**的每一个串（语义标签 + 两块标签 + 行内编号/基因型/配子名）。
///
/// ⚠️ 这才是方向词守卫真正该扫的集合：paint() 画出去的字就是这些，
///    而图内**没有 `Text` widget** 可以扫。
List<String> _onScreenStrings(CrossoverPainter p) => <String>[
      LinkageCrossoverDiagram.semanticsLabel(p.figure),
      kCrossoverBeforeLabel,
      p.afterBlockLabel,
      for (final r in p.rows) ...<String>[
        r.chromatid,
        r.alleles,
        if (r.gamete != null) r.gamete!,
      ],
    ];

/// 断言一串上屏文案：⛔ 禁 markdown 星号、⛔ 禁方向词。
void _expectNoDirWords(String s, {required String what}) {
  expect(s.contains('*'), isFalse,
      reason: '$what 禁 markdown 星号：屏幕阅读器会把 * 念出来。串=$s');
  for (final w in _kBannedDirWords) {
    expect(s.contains(w), isFalse,
        reason: '$what 禁方向词「$w」：要点名对象（如「1a」「Ab」「交换前」），'
            '位置在屏幕阅读器里既错又不稳定。串=$s');
  }
}

/// 取「从 [anchor] 那句起、到下一个分句为止」的那一段。
///
/// 用途：端到端那条要证明**亲本型与重组型分别被点名**，而语义标签是
/// 「……没有参与交换，配子分别是 X 和 Y；……参与了交换，……它们就是重组型。」
/// 这样一句话的形式 ⇒ 光 `contains` 分不出谁是谁，必须按分句读。
String _clauseFrom(String label, String anchor) {
  final i = label.indexOf(anchor);
  expect(i >= 0, isTrue, reason: '语义标签里应含「$anchor」。实际=$label');
  final rest = label.substring(i);
  final j = rest.indexOf('；');
  return j < 0 ? rest : rest.substring(0, j);
}

// ────────────────────────────────────────────────────────────────────
// 端到端动线（走**本仓**容器页，照 test/module_fill_overwrite_cross_guard_test.dart
// 的 `_pumpPage` / `_gotoTab` 形状）
// ────────────────────────────────────────────────────────────────────

void _setSurface(WidgetTester t, double w, double h) {
  t.view.physicalSize = Size(w, h);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
}

Future<void> _pumpPage(WidgetTester t) async {
  _setSurface(t, 1600, 2400);
  await t.pumpWidget(const MaterialApp(home: CrossCalculatorPage()));
  await t.pump();
  await t.pump(const Duration(milliseconds: 600));
  await t.pumpAndSettle();
}

Finder _tab(String label) =>
    find.descendant(of: find.byType(TabBar), matching: find.text(label));

/// 切到「连锁互换」页签。
///
/// ⚠️ 必须在 TabBar 子树里找：页签 body's 输入面板上还有一个
/// `AppChip('连锁互换')`，全树 find.text 会撞多个。
Future<void> _gotoLinkageTab(WidgetTester t) async {
  expect(_tab('连锁互换'), findsOneWidget,
      reason: '前提：宽屏 TabBar 里有且只有一个「连锁互换」');
  await t.tap(_tab('连锁互换'));
  await t.pumpAndSettle();
}

/// 在左栏 rail 里点「计算子代」。
Future<void> _computeInRail(WidgetTester t) async {
  final btn = find.ancestor(
      of: find.text('计算子代'), matching: find.byType(FilledButton));
  expect(btn, findsOneWidget, reason: '前提：rail 里「计算子代」按钮唯一');
  await t.tap(btn);
  await t.pump();
  await t.pump(const Duration(milliseconds: 600));
  await t.pumpAndSettle();
}

/// 键入并证明字符真进了框（⛔ 不能只 `enterText` 就当成功）。
Future<void> _type(WidgetTester t, Finder field, String text) async {
  expect(field, findsOneWidget, reason: '前提：目标输入框唯一');
  await t.tap(field);
  await t.pump();
  t.testTextInput.enterText(text);
  await t.pump();
  expect(t.widget<TextField>(field).controller?.text, text,
      reason: '前提：输入框内容确实是「$text」');
}

/// 把连锁互换页签的列表滚到底。
///
/// ⚠️ 必须限定在 [LinkageTab] 子树内：`TabBarView` 会把建过的页签留在树里。
/// 负例（r = 0）必须先滚到底，否则「图不存在」只是「图还没被懒构建」= 自欺。
Future<void> _scrollTabToEnd(WidgetTester t) async {
  final scroller = find.descendant(
      of: find.byType(LinkageTab), matching: find.byType(Scrollable));
  expect(scroller, findsAtLeastNWidgets(1),
      reason: '前提：连锁互换页签里至少有一个可滚列表');
  final pos = t.state<ScrollableState>(scroller.first).position;
  pos.jumpTo(pos.maxScrollExtent);
  await t.pumpAndSettle();
}

Finder _diagram() => find.byType(LinkageCrossoverDiagram);

/// 端到端里读图自己的语义标签（刻意读 widget 的 `properties.label`）。
String _labelOfMounted(WidgetTester t) {
  final sem = t.widget<Semantics>(
      find.descendant(of: _diagram(), matching: find.byType(Semantics)));
  return sem.properties.label ?? '';
}

/// 屏上**应该**出现的那份表型整数比（作为「真的算成了」的物证）。
///
/// ⚠️ 为什么不把串**手抄**进来：r=0 的测交是 `1 : 1`、反式自交是
/// `75 : 24 : 1`。直接问引擎 ⇒ 既给出该出现的串，又顺带证明引擎收得了这组输入。
String _ratioOf(String p1, String p2, String r) =>
    LinkageEngine().cross(p1, p2, r).phenotypeRatio.join(' : ');

void main() {
  tearDown(() {
    // ⛔ AppColors 的 token 是 **getter**，亮度靠 sync 切换 ⇒ 收尾复位。
    AppColors.sync(Brightness.light);
    // ⛔ 高对比开关同理：它是**全局**单例上的一个 bool。
    PresentModeController.instance.debugReset();
  });

  // ── D：推导规则（判据落在产品的公开成员上）────────────────────
  group('D 推导规则', () {
    test('D1 四条染色单体编号 4 个互不相同、都不为空', () {
      for (final parent in const <String>['AB/ab', 'Ab/aB']) {
        final cs = _figureOf(parent).chromatids;
        expect(cs.length, 4, reason: '一次减数分裂恒有 4 条染色单体（$parent）');
        expect(cs.map((c) => c.id).toSet().length, 4,
            reason: '编号重名会让语义标签里的指代不清（$parent）：'
                '${cs.map((c) => c.id).toList()}');
        expect(cs.any((c) => c.id.isEmpty), isFalse, reason: '不许有空编号');
      }
    });

    test('D2 参与交换的恰好 2 条、各属一条同源染色体、且逐位互补', () {
      // ⚠️ ⛔ **判据不能是「一实一空」**：那条只对顺式成立。反式 `Ab/aB` 时
      //    亲本型（`Ab`/`aB`）才是「一实一空」，重组型是 `AB`（两实）与
      //    `ab`（两空）⇒ 拿「一实一空」当判据，反式那张图必红，而图本身没错。
      //    唯一与连锁相无关的判据是**逐位互补**：一次单交换的两条产物在
      //    **每一位**上一个来自 hap1、一个来自 hap2。
      for (final parent in const <String>['AB/ab', 'Ab/aB']) {
        final f = _figureOf(parent);
        final on = f.chromatids.where((c) => c.participated).toList();
        expect(on.length, 2,
            reason: '参与交换的必须恰好 2 条（$parent）：1 条是画错了，'
                '3 条就等于全换了一遍，不是「交换」；'
                '4 条则等于两条同源染色体的两条姐妹染色单体都参与了');
        expect(on.map((c) => c.homolog).toSet().length, 2,
            reason: '参与交换的必须是**非姐妹**染色单体（各属一条同源染色体），'
                '${on.map((c) => '${c.id}(同源${c.homolog})').toList()}');
        expect(on.map((c) => c.gamete).toSet().length, 2,
            reason: '参与交换的两条必须互不相同：'
                '${on.map((c) => c.gamete).toList()}');
        for (var i = 0; i < f.locusCount; i++) {
          expect(on[0].upper[i], isNot(on[1].upper[i]),
              reason: '$parent 第 ${i + 1} 座：参与交换的两条在这一位上必须'
                  '一个来自 hap1、一个来自 hap2（实/空相反）。'
                  '实际 ${on[0].gamete} / ${on[1].gamete}');
        }
        // 两条参与者都**不等于**自己的亲本形态（否则那次交换没发生在这条上）。
        for (final c in on) {
          expect(c.gamete, isNot(c.parentalGamete),
              reason: '${c.id} 参与了交换却与交换前完全相同');
        }
      }
    });

    test('D3 没参与交换的另外 2 条：逐字等于两条亲本单倍型', () {
      for (final parent in const <String>['AB/ab', 'Ab/aB']) {
        final f = _figureOf(parent);
        final off = f.chromatids.where((c) => !c.participated).toList();
        expect(off.length, 2, reason: '未参与交换的必须恰好 2 条（$parent）');
        expect(off.map((c) => c.gamete).toSet(),
            equals(<String>{f.hap1, f.hap2}),
            reason: '没参与交换的那两条必须**逐字**是两条亲本单倍型'
                '（$parent ⇒ ${f.hap1}/${f.hap2}），'
                '实际 ${off.map((c) => c.gamete).toList()}：'
                '「它没变」这件事是整张图的因果对照，不能靠画得像');
        // 每条同源染色体的两条姐妹染色单体必须都携带同一条单倍型。
        for (final h in const <int>[1, 2]) {
          final g = f.chromatids.where((c) => c.homolog == h).toList();
          expect(g.length, 2, reason: '同源染色体 $h 上恒有 2 条姐妹染色单体');
          expect(g.map((c) => c.parentalGamete).toSet().length, 1,
              reason: '同源染色体 $h 的两条姐妹染色单体交换前必须完全相同');
        }
      }
    });

    test('D4 实心/空心带必须与配子串的大小写一致（编码约定）', () {
      // 图上「实心带 = 大写、空心带 = 小写」是这套图的编码约定。
      // 若某一条的实空状态与它标的等位基因串对不上，图就在教一件不成立的事，
      // 而像素基线未必看得出来（两处都是小方块）。
      for (final parent in const <String>['AB/ab', 'Ab/aB']) {
        final f = _figureOf(parent);
        for (final c in f.chromatids) {
          expect(c.upper.length, c.gamete.length,
              reason: '${c.id} 的色带个数必须等于它的位点数（${c.gamete}）');
          for (var i = 0; i < c.gamete.length; i++) {
            final isUpper = c.gamete[i] == c.gamete[i].toUpperCase();
            expect(c.upper[i], isUpper,
                reason: '${c.id} 第 ${i + 1} 座：${c.gamete[i]} '
                    '${isUpper ? '是大写 ⇒ 应为实心带' : '是小写 ⇒ 应为空心带'}');
          }
        }
      }
    });

    test('D5 同一次减数分裂只可能有一处交换（⛔ 两条参与者必须同区间）', () {
      // 参与交换的恰好 2 条，且必须是**同一处交换**的那一对非姐妹染色单体。
      // ⚠️ 这里用三位点才验得出来：两位点只有 1 个可交换位点。
      final p = _engine.parseParent('ABC/abc');
      // ⛔ 构造一组「一条参与第 1 区间、另一条参与第 2 区间」的假数据 ⇒ 必须被拒。
      expect(
        () => CrossoverFigure(
          hap1: p.hap1,
          hap2: p.hap2,
          afterGametes: <String>[
            p.hap2,
            p.hap1,
            recombinant1(p.hap1, p.hap2, 0),
            recombinant1(p.hap1, p.hap2, 1),
          ],
        ),
        throwsA(anything),
        reason: '两条参与交换的染色单体来自**不同的交换区间** ⇒ '
            '图会在同一格子里说两处交换发生，拒绝它',
      );
      // 对照：同一区间的两个重组型**必须**被接受（否则上面那条就是恒红）。
      expect(
        CrossoverFigure(
          hap1: p.hap1,
          hap2: p.hap2,
          afterGametes: <String>[
            p.hap1,
            p.hap2,
            recombinant1(p.hap1, p.hap2, 1),
            recombinant2(p.hap1, p.hap2, 1),
          ],
        ).chromatids.where((c) => c.participated).length,
        2,
        reason: '同一区间的两个重组型是合法的一组数据（对照：上面那条才非法）',
      );
    });
  });

  // ── F：数据驱动的判据 ────────────────────────────────────────
  group('F 数据驱动', () {
    test('F1 顺式 `AB/ab`：四个编号 1b/2b/1a/2a，1a 变 Ab、2a 变 aB', () {
      final p = _painterOf(_figureOf(_kCisParent));
      final f = _figureOf(_kCisParent);

      // 判据全部落在产品数据上（⛔ 不看像素 —— 像素那一层由 A 组守）。
      expect(p.afterRows.map((r) => r.chromatid).toList(),
          equals(<String>['1b', '2b', '1a', '2a']),
          reason: '顺式两座的行序必须是 1b / 2b / 1a / 2a');
      expect(p.beforeRows.length, 4, reason: '上下各 4 行');
      expect(p.afterRows.where((r) => r.participated).map((r) => r.chromatid),
          equals(<String>['1a', '2a']),
          reason: '⛔ 这两条是**推**出来的（见 F5），不是写死的');

      // 逐条对照（点名取行，不用「第 3 行」）。
      expect(_rowById(p.beforeRows, '1a').alleles, f.hap1,
          reason: '1a 交换前是 hap1');
      expect(_rowById(p.afterRows, '1a').alleles,
          recombinant1(f.hap1, f.hap2, 0),
          reason: '1a 交换后是重组型①（参与交换、前段取 hap1）');
      expect(_rowById(p.beforeRows, '2a').alleles, f.hap2);
      expect(_rowById(p.afterRows, '2a').alleles,
          recombinant2(f.hap1, f.hap2, 0),
          reason: '2a 交换后是重组型②（参与交换、前段取 hap2）');
      for (final id in const <String>['1b', '2b']) {
        expect(_rowById(p.afterRows, id).alleles,
            _rowById(p.beforeRows, id).alleles,
            reason: '$id 没有参与交换，交换前后必须完全相同');
      }
      expect(p.afterRows.map((r) => r.alleles).toList(),
          equals(<String>['AB', 'ab', 'Ab', 'aB']),
          reason: '顺式两座交换后的四行应逐字是 AB / ab / Ab / aB');
    });

    test('F2 反式 `Ab/aB`：恰好两行变了，变的是 1a→AB、2a→ab，其余两条不动', () {
      final f = _transFigure;
      final p = _painterOf(f);

      // ① 亲本型在反式时是 `Ab` / `aB`（不是 `AB` / `ab`）。
      expect(f.hap1, 'Ab');
      expect(f.hap2, 'aB');
      expect(f.afterGametes.toSet(),
          equals(<String>{'Ab', 'aB', 'AB', 'ab'}),
          reason: '前提：反式时引擎给的就是这 4 个配子（亲本型概率高）');

      // ② 交换前：同源染色体的两条完全相同，且**没有出现过重组型**。
      //    ⚠️ 判据不能写「不许有混合带」：反式时亲本型（Ab / aB）**才是**
      //    混合的 ⇒ 那样判会把一张没问题的图判成红的。通用判据只有一条：
      //    交换前的每一行都逐字落在两条亲本单倍型里。
      for (final h in const <int>[1, 2]) {
        final g = p.beforeRows
            .where((r) => _chromatidById(f, r.chromatid).homolog == h)
            .toList();
        expect(g.length, 2);
        expect(g[0].upper, equals(g[1].upper),
            reason: '交换前同源染色体 $h 的两条必须完全相同');
        expect(<String>{g[0].alleles, g[1].alleles}.length, 1,
            reason: '交换前同源染色体 $h 的两条必须携带同一条单倍型');
        expect(f.recombinantCandidates.contains(g[0].alleles), isFalse,
            reason: '⛔ 重组型在交换前不存在：同源染色体 $h 被画成了重组型');
      }
      expect(p.beforeRows.map((r) => r.alleles).toSet(),
          equals(<String>{f.hap1, f.hap2}));

      // ③ ⛔ 核心：交换后**恰好两行**变了，其余两条逐字未变。
      final changed = <String>[];
      for (final id in p.beforeRows.map((r) => r.chromatid)) {
        final b = _rowById(p.beforeRows, id);
        final a = _rowById(p.afterRows, id);
        if (b.alleles != a.alleles) changed.add(id);
      }
      expect(changed, equals(<String>['1a', '2a']),
          reason: '反式下参与交换的仍然是 1a 与 2a；实际变了的是 $changed');
      expect(p.afterRows.where((r) => r.participated).map((r) => r.chromatid),
          equals(changed),
          reason: '「变了的两条」与「推出来的参与了交换的两条」必须逐条相同');

      // ④ 它们的结果 = 重组型 = 那两条**与亲本型不同**的配子。
      expect(_rowById(p.afterRows, '1a').alleles,
          recombinant1(f.hap1, f.hap2, 0),
          reason: '1a 交换后 = hap1 前段 + hap2 后段 = 重组型①');
      expect(_rowById(p.afterRows, '2a').alleles,
          recombinant2(f.hap1, f.hap2, 0),
          reason: '2a 交换后 = hap2 前段 + hap1 后段 = 重组型②');
      expect(f.recombinantCandidates, equals(<String>{'AB', 'ab'}),
          reason: '前提：反式时重组型**才是** AB / ab');
      expect(_rowById(p.afterRows, '1a').alleles, isNot(f.hap1));
      expect(_rowById(p.afterRows, '2a').alleles, isNot(f.hap2));

      // ⑤ 1b / 2b：没参与交换 ⇒ 交换前后逐字相同（**各断言一次**）。
      expect(_rowById(p.afterRows, '1b').alleles,
          _rowById(p.beforeRows, '1b').alleles);
      expect(_rowById(p.afterRows, '1b').alleles, f.hap1);
      expect(_rowById(p.afterRows, '2b').alleles,
          _rowById(p.beforeRows, '2b').alleles);
      expect(_rowById(p.afterRows, '2b').alleles, f.hap2);
    });

    test('F3 三位点 `ABC/abc`：引擎出 6 个键，组件⛔拒绝把它们当 6 条染色单体',
        () {
      final p = _engine.parseParent('ABC/abc');
      final g = _engine.gametesOf(p, Fraction.approx(0.2));
      expect(g.length, 6,
          reason: '前提：三位点时引擎给 6 个配子（2 亲本 + 2 区间 × 2）');

      // ① 那 6 个键里，2 个是亲本型、4 个是重组型，分属**两个不同的区间**。
      final parental = <String>{p.hap1, p.hap2};
      expect(g.keys.where(parental.contains).toSet(), equals(parental));
      final rec = g.keys.where((k) => !parental.contains(k)).toSet();
      expect(rec.length, 4);
      final byInterval = <int, Set<String>>{
        for (var i = 0; i < 2; i++)
          i: <String>{
            recombinant1(p.hap1, p.hap2, i),
            recombinant2(p.hap1, p.hap2, i),
          },
      };
      expect(rec, equals(<String>{...byInterval[0]!, ...byInterval[1]!}));
      // ⛔ 这就是硬停的根据：第 1 区间的两个重组型与第 2 区间的两个来自
      //    **不同的减数分裂**，各自的「交换前」形态不同 ⇒ 画成上下两块各 6 行
      //    就是教一件不存在的事：一次减数分裂里只有 4 条染色单体。
      expect(byInterval[0]!.intersection(byInterval[1]!), isEmpty,
          reason: '两个区间的重组型必须互不相同，否则它们可能来自同一次分裂');

      // ② 组件必须**拒绝**这 6 个键：一次减数分裂恒 4 条染色单体。
      expect(
        () => CrossoverFigure(
          hap1: p.hap1,
          hap2: p.hap2,
          afterGametes: g.keys.toList(),
        ),
        throwsA(anything),
        reason: '⛔ 6 条染色单体不存在（2 同源 × 2 姐妹 = 4 条）'
            '⇒ 组件必须拒绝这组数据，而不是画一张说错的图',
      );

      // ③ 单个区间的 4 条染色单体**画得出来**（组件对 3 个位点本身可用）——
      //    但宿主**不会**这样调它：引擎给的是 6 个键，闸门判据③
      //    （`gametesP1.length != 4`）因此挡下。
      final single = CrossoverFigure(
        hap1: p.hap1,
        hap2: p.hap2,
        afterGametes: <String>[p.hap1, p.hap2, ...byInterval[1]!],
      );
      expect(single.locusCount, 3);
      expect(single.chromatids.length, 4);
      expect(single.chromatids.where((c) => c.participated).length, 2,
          reason: '第 2 区间那一次交换 ⇒ 恰好 2 条参与');
      expect(single.chromatids.every((c) => c.upper.length == 3), isTrue,
          reason: '三条染色单体各 3 个色带');
    });

    test('F4 `r = 0`：组件不声称重组（块标签换文案、语义标签明说没有重组型）',
        () {
      final f = _noCrossoverFigure();
      expect(f.hasCrossover, isFalse,
          reason: '前提：r=0 时重组型概率为 0、被引擎删掉了，谁都没参与交换');
      final p = _painterOf(f);

      // ① 屏上不许有「重组型」的说法。
      expect(p.hasCrossover, isFalse);
      expect(p.afterBlockLabel, kCrossoverNoExchangeLabel,
          reason: '⛔ 一次交换都没发生，块头不许还写「交换后」');
      expect(p.afterBlockLabel, isNot(kCrossoverAfterLabel));
      final label = LinkageCrossoverDiagram.semanticsLabel(f);
      expect(label.contains('没有重组型'), isTrue,
          reason: '语义标签必须明说「没有重组型」');
      expect(label.contains('它们就是重组型'), isFalse,
          reason: '⛔ 不许出现「它们就是重组型」这种声称重组的说法');

      // ② 数据上也不许：没有任何一行参与交换，「交换后」与「交换前」逐行相同。
      expect(p.afterRows.where((r) => r.participated), isEmpty);
      for (final b in p.beforeRows) {
        final a = _rowById(p.afterRows, b.chromatid);
        expect(a.alleles, b.alleles, reason: '${b.chromatid} 前后必须逐字相同');
        expect(a.upper, equals(b.upper));
      }
      expect(p.afterRows.map((r) => r.alleles).toSet(),
          equals(<String>{f.hap1, f.hap2}),
          reason: '⛔ 屏上不许出现重组型的等位基因串');
    });

    test('F5 值对象上不存在布尔标志，且参与交换与「传进来的顺序」无关', () {
      // ① 源码级：`CrossoverFigure` **既没有 bool 字段、也没有 bool 参数**。
      //    ⛔ 不靠运行时反射（本仓没引 `dart:mirrors`）——「API 上没有 bool」
      //    本来就得看声明。⚠️ 判据只查「声明」不查「类体里出现过 bool 这个词」：
      //    `bool get hasCrossover` 是**推出来的**只读属性（不占字段、不由
      //    调用方给），拿它当违规会把「派生」与「传入」混为一谈。
      const src = 'lib/pages/widgets/linkage_crossover_diagram.dart';
      final body = _classBodyOf(src, 'CrossoverFigure')
          .split('\n')
          .where((l) => !l.trimLeft().startsWith('//'))
          .join('\n');
      final fieldDecls = RegExp(
              r'^\s*(final\s+)?(bool)\s+(?!operator\b)\w+\s*[=;]', multiLine: true)
          .allMatches(body)
          .map((m) => m.group(0)!.trim())
          .toList();
      expect(fieldDecls, isEmpty,
          reason: '⛔ CrossoverFigure 上不许有 bool 字段：「是否参与交换」必须'
              '由数据推出来。传布尔标志等于把判断责任推回调用方。实际字段：$fieldDecls');
      final ctor = RegExp(r'CrossoverFigure\(\{([\s\S]*?)\}\)').firstMatch(body);
      expect(ctor, isNotNull, reason: '应能找到 CrossoverFigure 的构造器');
      expect(RegExp(r'\bbool\b').hasMatch(ctor!.group(1)!), isFalse,
          reason: '⛔ CrossoverFigure 的构造参数不许有 bool。实际：${ctor.group(1)}');
      expect(RegExp(r'final\s+bool\s+participated').hasMatch(body), isFalse,
          reason: '⛔ 不许把「参与交换」做成 final bool 字段（那正是把判断'
              '责任推回调用方的写法）');

      // ② 行为级：同一组数据换个**传进来的顺序**，图必须一模一样 ——
      //    若是「按位置判断参与」，换序就会换答案。
      final f = _figureOf(_kCisParent);
      final shuffled = CrossoverFigure(
        hap1: f.hap1,
        hap2: f.hap2,
        afterGametes: f.afterGametes.reversed.toList(),
      );
      expect(shuffled.chromatids.map((c) => c.id).toList(),
          f.chromatids.map((c) => c.id).toList());
      expect(
          shuffled.chromatids
              .map((c) => '${c.id}:${c.gamete}:${c.participated}')
              .toList(),
          f.chromatids.map((c) => '${c.id}:${c.gamete}:${c.participated}').toList(),
          reason: '「参与交换」必须只由 hap1/hap2/gamete 的**内容**决定');

      // ③ 宿主那一侧：调用点只传结构化数据（⛔ 不传布尔标志）。
      const tabSrc = 'lib/pages/widgets/linkage_tab.dart';
      final tab = File(tabSrc).readAsStringSync();
      final call = tab.indexOf('LinkageCrossoverDiagram(');
      expect(call >= 0, isTrue, reason: '宿主的渲染处应有一个 LinkageCrossoverDiagram(...)');
      final callText = tab.substring(call, tab.indexOf(')', call) + 1);
      expect(RegExp(r'\w+\s*:').allMatches(callText).length, 1,
          reason: '⛔ 调用点只许传一个参数（figure:），不许夹带布尔标志。实际：$callText');
      expect(callText.contains('figure:'), isTrue,
          reason: '调用点必须传结构化数据。实际：$callText');
    });
  });

  // ── S：屏上文案（⛔ 禁方向词、禁 markdown 星号）────────────────
  group('S 屏上文案', () {
    test('S1 顺式 / 反式两套数据的上屏文案都不许出现方向词或星号', () {
      for (final parent in const <String>['AB/ab', 'Ab/aB']) {
        final p = _painterOf(_figureOf(parent));
        final strings = _onScreenStrings(p);
        expect(strings, isNotEmpty, reason: '前提：$parent 拼出了上屏串');
        for (final s in strings) {
          _expectNoDirWords(s, what: '图上屏串（$parent）');
        }
        // 前提自证：这套黑名单**不是恒真** ——「交换前」「交换后」是点名状态，
        // 必须**在**，否则上面那圈断言可能是「扫了个空集」。
        final label = LinkageCrossoverDiagram.semanticsLabel(_figureOf(parent));
        for (final w in const <String>['交换前', '交换后', '编号次序相同']) {
          expect(label.contains(w), isTrue,
              reason: '前提（$parent）：语义标签必须点名「$w」：'
                  '两块靠状态名区分，不靠「上面那块」');
        }
      }
    });

    test('S2 「交换前」块的数据层就没有配子名（⛔ 交换前还没有配子）', () {
      final f = _figureOf(_kCisParent);
      final p = _painterOf(f);
      expect(CrossoverPainter.kBeforeRendersGametes, isFalse,
          reason: '「交换前」不渲染配子名');
      expect(CrossoverPainter.kAfterRendersGametes, isTrue,
          reason: '「交换后」那 4 条染色单体本身就是 4 个配子，必须渲染');
      // ⛔ 数据层（更硬的一道）：不是「画的时候不画」，而是**根本没有**。
      expect(p.beforeRows.map((r) => r.gamete), everyElement(isNull),
          reason: '配子是减数第一次分裂之后才有的，交换前连数据里都不该有配子名');
      for (final r in p.afterRows) {
        expect(r.gamete, _chromatidById(f, r.chromatid).gamete,
            reason: '${r.chromatid} 在「交换后」的配子名必须与值对象推导的一致');
      }
    });
  });

  // ── E：端到端（走本仓宿主）────────────────────────────────────
  group('E 端到端挂载', () {
    testWidgets('E1 出厂 `AB/ab × ab/ab` r=20%：图在屏上，并分别点名亲本型与重组型',
        (t) async {
      await _pumpPage(t);
      expect(t.takeException(), isNull, reason: '首帧无异常');
      await _gotoLinkageTab(t);

      await _computeInRail(t);
      // 前提自证：确实算出了顺式测交的结果（不是算炸了才没图）。
      expect(find.text('4 : 4 : 1 : 1'), findsOneWidget,
          reason: '前提：AB/ab × ab/ab 且 r=20% 的子代表型整数比是 4:4:1:1');

      await _scrollTabToEnd(t);
      expect(find.text('重组型是怎么来的'), findsOneWidget,
          reason: '概念图的小标题应与图同屏');
      expect(_diagram(), findsOneWidget,
          reason: 'E1：顺式两位点 + 0<r<1/2 ⇒ 概率高的那两条正是 parent1 的'
              '两条单倍型（AB / ab），图该在');
      expect(t.takeException(), isNull, reason: 'E1 不许带来任何异常');

      // ⛔ 光「图在」不够：还得证明它**点名了**亲本型与重组型（各是哪些配子）。
      //    判据落在图自己的语义标签上，按分句读（为什么不能只 contains：
      //    四个配子名都在同一段话里，contains 分不出谁是谁）。
      final label = _labelOfMounted(t);
      final parentalClause = _clauseFrom(label, '没有参与交换');
      final recClause = _clauseFrom(label, '参与了交换');
      for (final g in const <String>['AB', 'ab']) {
        expect(parentalClause.contains(g), isTrue,
            reason: '亲本型那一句必须点名 $g（它没参与交换 ⇒ 就是亲本型）');
      }
      for (final g in const <String>['Ab', 'aB']) {
        expect(recClause.contains(g), isTrue,
            reason: '重组型那一句必须点名 $g（左右两段换过 ⇒ 重组型）');
      }
      expect(recClause.contains('重组型'), isTrue,
          reason: '重组型那一句必须明说「它们就是重组型」');
      // 前提自证：两句各自**不含**对方那对配子（否则上面的点名是巧合）。
      expect(recClause.contains('AB'), isFalse,
          reason: '重组型那一句不该出现亲本型配子 AB。实际=$recClause');
      expect(parentalClause.contains('aB'), isFalse,
          reason: '亲本型那一句不该出现重组型配子 aB。实际=$parentalClause');

      // S 组的黑名单在**真树上**再钉一遍：图子树的 Text 与语义标签。
      _expectNoDirWords(label, what: '端到端语义标签');
      final textsInDiagram = t
          .widgetList<Text>(find.descendant(of: _diagram(), matching: find.byType(Text)))
          .map((w) => w.data ?? '')
          .toList();
      for (final s in textsInDiagram) {
        _expectNoDirWords(s, what: '图子树内的 Text');
      }
    });

    testWidgets('E2 r=0：图不在（重组型概率为 0，⛔ 不许画一张讲发生了交换的图）',
        (t) async {
      await _pumpPage(t);
      await _gotoLinkageTab(t);
      await _computeInRail(t);
      await _scrollTabToEnd(t);
      // ⚠️ 先证明探针**看得见**这张图：否则下一条「不在」是自欺。
      expect(_diagram(), findsOneWidget, reason: 'E2 前提：r=20% 时图必须在');

      await _type(t, find.widgetWithText(TextField, '交换值 r'), '0');
      await _computeInRail(t);
      await _scrollTabToEnd(t);
      // 前提：这次真的算成了（不是算炸了才没图）。
      expect(find.text('4 : 4 : 1 : 1'), findsNothing,
          reason: '前提：屏上已不是 r=20% 的旧账');
      expect(find.text(_ratioOf('AB/ab', 'ab/ab', '0')), findsOneWidget,
          reason: '前提：r=0 的测交确实算成功了（重组型概率为 0，子代全是亲本型）；'
              '算不成的话下面那条「不在」就没有意义');
      expect(_diagram(), findsNothing,
          reason: 'E2（核心守卫）：r=0 时重组型不存在，'
              '这张解释「重组型是怎么来的」图**画不出可解释的内容** ⇒ 不挂');
    });
  });

  // ── A：像素基线 ──────────────────────────────────────────────
  group('A 像素基线', () {
    for (final tier in const <({String tag, String label, Brightness b})>[
      (tag: 'light', label: '浅色', b: Brightness.light),
      (tag: 'dark', label: '深色', b: Brightness.dark),
    ]) {
      testWidgets('A/${tier.label}像素基线（上下两块：交换前 4 行 + 交换后 4 行）',
          (t) async {
        // ⛔ 字体先装：注释与基因型落在 painter 的 `TextPainter` 里，
        //    那里没有 BuildContext、拿不到 DefaultTextStyle，不显式声明
        //    family 就落回 flutter_tester 的方框字体 ⇒ 基线对文本零敏感（假绿）。
        await loadGoldenFonts(cjk: true);
        assertMaterialIconsLoaded();
        assertMonoLoaded();
        AppColors.sync(tier.b);
        await t.pumpWidget(_host(tier.b));
        await t.pump();
        await expectLater(
          _paintFinder(),
          matchesGoldenFile('goldens/linkage_crossover_${tier.tag}.png'),
        );
      });
    }

    test('Z 两张基线必须互不相同，且都不是空图（防恒等三元 / 纯底色小图）', () {
      // ⚠️ 普通 `test()` 的 CWD 是**包根**，而 `matchesGoldenFile` 的路径相对
      //    **测试文件所在目录**（test/）⇒ 读盘时必须自己带 `test/` 前缀。
      const dir = 'test/goldens/';
      final light = File('${dir}linkage_crossover_light.png');
      final dark = File('${dir}linkage_crossover_dark.png');
      for (final f in <File>[light, dark]) {
        expect(f.existsSync(), isTrue, reason: '基线还没录：${f.path}');
        // ⛔ 光「存在」不够：组件哪天什么都不画，录出来的就是**一张纯底色小
        //    PNG**，它照样存在、照样比对通过 ⇒ 下限把「空图」挡在外面。
        expect(f.lengthSync(), greaterThan(1000),
            reason: '基线 ${f.path} 只有 ${f.lengthSync()} 字节，'
                '多半是一张没画任何东西的纯底色小图');
      }
      expect(light.readAsBytesSync(), isNot(equals(dark.readAsBytesSync())),
          reason: '浅色与深色录成了同一张 ⇒ 分档测试自己骗自己');
    });
  });
}
