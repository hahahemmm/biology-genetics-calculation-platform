// ════════════════════════════════════════════════════════════════
//  test/sex_linked_punnett_diagram_test.dart
//  伴性遗传（9331 第 4 页签）概念示意图：闸门守卫 + 端到端点名 + 像素基线
// ════════════════════════════════════════════════════════════════
//
//  ## 这张图回答什么
//
//  > 父亲的两种配子 × 母亲的两种配子 = 四种子代；而决定孩子是儿子还是女儿的，
//  > 是父亲给出去的那一条是 X 还是 Y。
//
//  ## 本文件守四组
//
//  · A 引擎前提闸门：前提被违反 ⇒ `maybeFromEngine` 返 **null**（宿主据此整图不
//    渲染），`fromEngine` 直接抛。三条前提逐条断（缺光杆 Y / 母亲超两种 / 键不认识）。
//  · B 因果落点：[PunnettCell.isDaughter] **只看父亲那一条** —— 与母亲给哪条 X
//    完全无关。这是本图全部因果的落点，必须能被单独钉住。
//  · C 宿主闸门 + 端到端：**没算过 ⇒ 屏上一个像素都不加**；算出伴性结果后图才
//    出现，且图上**点名对象**（「母亲给的 XA」「父亲Y」），⛔ 零方向词。
//  · D 像素基线：浅色 + 深色各一张（先 `loadGoldenFonts`，⛔ 少装一个字族就是
//    一批方框基线 = 假绿）。
//
//  ## ⛔ 反假绿纪律
//
//  · ⛔ 文案判据扫的是 **painter 真正拿去排版的 span**（`sexLabelSpan` /
//    `cellLabelSpan`）**加**组件自己的语义标签，⛔ 不是一堆测试内常量拼出来的
//    「屏上文字合集」——那样哪天有人往画布上写个「上面那条」，断言照样绿。
//  · ⛔ 「未计算 ⇒ 不渲染」判据是**树里没有** `SexLinkedPunnettDiagram`，不是
//    「画成 0×0」（组件本来就可能存在而什么都不画）。
//  · ⛔ 端到端**先证明算成了**（屏上不再是等待文案），再谈图在不在。
//  · ⛔ 配子表一律**问引擎**，⛔ 不在测试里重抄一遍「母亲两条、父亲两条各 1/2」。
//
//  ## 基线由本轮录出后交主线程目检
//
//  本文件**用** `--update-goldens` 录了 light / dark 两张，录完必须由主线程
//  目检（尤其：中文不是方框、基因型是真字、色带是深浅两套而非同一张）。
// ════════════════════════════════════════════════════════════════

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:biology/engine/fraction.dart';
import 'package:biology/engine/sex_linked_engine.dart';
import 'package:biology/pages/widgets/sex_linked_punnett_diagram.dart';
import 'package:biology/pages/widgets/sex_linked_tab.dart';
import 'package:biology/state/first_run_store.dart';
import 'package:biology/state/mistake_book.dart';
import 'package:biology/theme.dart';

import 'golden_fonts.dart';

// ── 出厂值（与 `sex_linked_tab.dart` 的 `_kDefaultFemale/_kDefaultMale` 同款，
//    但这里**自己写一遍**是有意的：守卫要钉住「出厂就是这一题」，题面串若从
//    被测文件里读，改了默认值这条守卫会跟着一起漂）────────────────────────
const String _kFemale = 'XAXa';
const String _kMale = 'XAY';

/// 图的宿主宽度锁在 [SexLinkedPunnettDiagram.designWidth]（= 320，也就是
/// painter 的设计坐标）⇒ 基线录在 **scale = 1.0** 上，像素与设计稿 1:1。
const double _kHostWidth = 320;

/// ⛔ 方向词黑名单（一个字都不放宽）。点名对象（「母亲给的 XA」）而不是位置 ——
///    位置在屏幕阅读器里是错的，且深色档 / 窄屏 / 横屏下「上面」到底指哪条会变。
const List<String> _kBannedDirWords = <String>[
  '上面',
  '下面',
  '上面那条',
  '下面那条',
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

/// ⛔ 图**不许**说的话（引擎结构上给不出 ⇒ 画它就是凭空引入引擎里不存在的假设）。
const List<String> _kBannedClaims = <String>[
  '男孩更多',
  '女孩更多',
  '男孩',
  '女孩',
  '性别比',
  '105',
  '比例',
  '概率',
  '%',
  '％',
];

/// ⛔ 比例**一律问引擎**：`cross()` 归一化两个亲本 ⇒ 用归一化后的串取配子表，
///    这样行序稳定（显性在前），基线才可复现。
SexLinkedPunnettFigure _figureOf(String female, String male) {
  final res = SexLinkedEngine().cross(female, male);
  return SexLinkedPunnettFigure.fromEngine(
    femaleGametes: SexLinkedEngine.femaleGametes(res.femaleParent),
    maleGametes: SexLinkedEngine.maleGametes(res.maleParent),
  );
}

/// 裸宿主：只挂图，不加标题 / 图例 ⇒ 基线里每一像素都是图自己画的。
Widget _host(Brightness b) => MaterialApp(
      theme: AppTheme.build(b),
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: _kHostWidth,
            child: SexLinkedPunnettDiagram(figure: _figureOf(_kFemale, _kMale)),
          ),
        ),
      ),
    );

/// 取出图里的 painter。
///
/// ⚠️ `PunnettPainter` 是 **CustomPainter，不是 Widget** ⇒ 它不在组件树里，
///    `find.byType(PunnettPainter)` 会**永远返回 0 个**。正确取法是从
///    `CustomPaint.painter` 拿。
PunnettPainter _painterOf(WidgetTester t) {
  final paint = t.widget<CustomPaint>(
    find
        .descendant(
            of: find.byType(SexLinkedPunnettDiagram),
            matching: find.byType(CustomPaint))
        .first,
  );
  final p = paint.painter;
  expect(p, isA<PunnettPainter>(),
      reason: 'CustomPaint 上的 painter 不是 PunnettPainter');
  return p as PunnettPainter;
}

/// 取组件自己声明的语义标签。
String _labelOf(WidgetTester t) {
  final sem = t.widget<Semantics>(
    find
        .descendant(
            of: find.byType(SexLinkedPunnettDiagram),
            matching: find.byType(Semantics))
        .first,
  );
  return sem.properties.label ?? '';
}

/// 图上**真正排版出去**的全部屏上文字：语义标签 + 两块标签 + 行头 / 列头配子名
/// + 每格的性别标注与两条归属词。
///
/// ⚠️ 全部取自 **painter 画的时候用的那一个 span**（`sexLabelSpan` /
///    `cellLabelSpan`），⛔ 不用测试内常量拼一份「屏上文字合集」：那样哪天有人
///    往画布上写一句「上面那条」，黑名单一个字都扫不到。
List<String> _allScreenText(String label, PunnettPainter p) => <String>[
      label,
      kPunnettMotherLabel,
      kPunnettFatherLabel,
      for (final g in p.rowGametes) g.name,
      for (final g in p.columnGametes) g.name,
      for (final plate in p.plates)
        for (final c in plate.row.cells) ...<String>[
          p.sexLabelSpan(c).toPlainText(),
          p.cellLabelSpan(c.maternal).toPlainText(),
          p.cellLabelSpan(c.paternal).toPlainText(),
        ],
    ];

/// 逐条把黑名单钉在**每一段**屏上文字上（不是钉在合集的并集上）。
void _expectNoBannedText(List<String> all) {
  for (final s in all) {
    expect(s, isNotEmpty, reason: '图上不许出现空文案');
    expect(s.contains('*'), isFalse,
        reason: '屏上文案禁 markdown 星号（屏幕阅读器会把 * 念出来）：「$s」');
    for (final w in _kBannedDirWords) {
      expect(s.contains(w), isFalse,
          reason: '⛔ 屏上文案禁方向词「$w」：要点名对象（如「母亲给的 XA」），'
              '位置在屏幕阅读器里既错又不稳定；出现在「$s」里');
    }
    expect(RegExp(r'[0-9]').hasMatch(s), isFalse,
        reason: '⛔ 屏上禁任何数字：比例是**算出来**的东西，由结果区的两张表负责；'
            '出现在「$s」里');
    for (final w in _kBannedClaims) {
      expect(s.contains(w), isFalse,
          reason: '⛔ 图不许说「$w」：引擎 `maleGametes` 恒给 X 与 Y 各一半、'
              '全仓也没有任何致死率 / 性别差异存活率参数，'
              '画这类说法就是凭空引入引擎里不存在的假设；出现在「$s」里');
    }
  }
}

/// 本仓 [SexLinkedTab] 的窄态宿主（900×1400，⛔ 必须窄于 1200：宽屏下输入面板
/// 由 9331 页注入左栏 rail，单独起 widget 时只有窄态才自渲染「计算子代」）。
///
/// ⚠️ `Scaffold` 不是装饰：Tab 里有 `TextField`，而它要求祖先链上有 `Material`
///    （`MaterialApp(home: tab)` 直接挂会抛「No Material widget found」）。
Future<void> _pumpTab(WidgetTester t) async {
  t.view.physicalSize = const Size(900, 1400);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.resetPhysicalSize);
  addTearDown(t.view.resetDevicePixelRatio);
  await t.pumpWidget(const MaterialApp(home: Scaffold(body: SexLinkedTab())));
  await t.pump();
  await t.pump(const Duration(milliseconds: 400));
}

/// 点「计算子代」，并**证明真的算成了**。
Future<void> _computeInTab(WidgetTester t) async {
  final btn = find.text('计算子代');
  await t.ensureVisible(btn);
  await t.pumpAndSettle();
  await t.tap(btn);
  await t.pumpAndSettle();
  expect(find.text('等待计算：结果将在这里展开'), findsNothing,
      reason: '前提：这一笔真的算出来了（没算出来时屏上没有子代表）');
}

void main() {
  late Directory tmp;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('sex_linked_punnett');
    // ⛔ 错题本 / 首次运行状态要隔离到临时文件：本页的保存按钮与 Ctrl+S 宿主
    //    都会读它们，不隔离就会去动用户真实数据。
    MistakeBook.debugFilePath = '${tmp.path}/mistakes.json';
    MistakeBook.debugTrashFilePath = '${tmp.path}/mistakes.trash.json';
    MistakeBook.instance.debugReset();
    FirstRunStore.debugFilePath = '${tmp.path}/first_run.json';
    FirstRunStore.debugWebStorage = null;
    FirstRunStore.debugForceIsWebStorage = false;
    FirstRunStore.instance.debugReset();
  });

  tearDown(() {
    MistakeBook.instance.debugFlushSave();
    MistakeBook.instance.debugResetAiOrganize();
    MistakeBook.instance.debugReset();
    MistakeBook.debugFilePath = null;
    MistakeBook.debugTrashFilePath = null;
    FirstRunStore.debugFilePath = null;
    FirstRunStore.debugWebStorage = null;
    FirstRunStore.debugForceIsWebStorage = false;
    FirstRunStore.instance.debugReset();
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
    // ⛔ AppColors 的 token 是 **getter**，亮度靠 sync 切换 ⇒ 收尾复位，否则
    //    同一进程后面那条浅色基线会偷偷录成深色。
    AppColors.sync(Brightness.light);
  });

  // ── A 组：引擎前提闸门 ──────────────────────────────────────────

  group('A 引擎前提被违反 ⇒ 整张图不给', () {
    // ⛔ 前提**逐条**断，且每条都断言两种出口：`fromEngine` 抛（画错不如炸）、
    //    `maybeFromEngine` 返 null（宿主据此一个像素都不加）。
    test('A1 三条前提逐条断：缺光杆 Y / 母亲超两种 / 键形状不认识', () {
      final goodMale = SexLinkedEngine.maleGametes(_kMale);
      final goodFemale = SexLinkedEngine.femaleGametes(_kFemale);
      final onlyX = goodMale.keys
          .firstWhere((k) => k != kPunnettYGamete, orElse: () => 'XA');

      // 前提先立住：不违反前提时图**必须**有（否则下面三条「返 null」是恒真的）。
      expect(
        SexLinkedPunnettFigure.maybeFromEngine(
          femaleGametes: goodFemale,
          maleGametes: goodMale,
        ),
        isNotNull,
        reason: '前提：出厂这一题上前提全部成立 ⇒ 必须给图，'
            '否则后面三条「返 null」证明不了任何事',
      );

      // ① 父亲只剩一条（缺光杆 Y）⇒ 「性别由父亲的哪一条决定」在图上失去着落。
      final noY = <String, Fraction>{onlyX: Fraction.half};
      expect(
        () => SexLinkedPunnettFigure.fromEngine(
            femaleGametes: goodFemale, maleGametes: noY),
        throwsStateError,
        reason: '① fromEngine 必须抛（画错不如炸）',
      );
      expect(
        SexLinkedPunnettFigure.maybeFromEngine(
            femaleGametes: goodFemale, maleGametes: noY),
        isNull,
        reason: '① 父亲缺光杆 Y 时必须不给图',
      );

      // ② 母亲配子超过两种（引擎结构上不可能，但守卫要挡住将来的一天）。
      final tooMany = <String, Fraction>{
        'XA': Fraction.half,
        'Xa': Fraction.half,
        'Xb': Fraction.half,
      };
      expect(
        () => SexLinkedPunnettFigure.fromEngine(
            femaleGametes: tooMany, maleGametes: goodMale),
        throwsStateError,
        reason: '② fromEngine 必须抛',
      );
      expect(
        SexLinkedPunnettFigure.maybeFromEngine(
            femaleGametes: tooMany, maleGametes: goodMale),
        isNull,
        reason: '② 母亲配子超过两种时必须不给图',
      );

      // ③ 键形状不认识（`XAXA` 是基因型不是配子键）⇒ 不许画错。
      final badKey = <String, Fraction>{'XAXA': Fraction.half};
      expect(
        () => SexLinkedPunnettFigure.fromEngine(
            femaleGametes: badKey, maleGametes: goodMale),
        throwsStateError,
        reason: '③ fromEngine 必须抛',
      );
      expect(
        SexLinkedPunnettFigure.maybeFromEngine(
            femaleGametes: badKey, maleGametes: goodMale),
        isNull,
        reason: '③ 不认识的配子键必须不给图而不是画错',
      );
    });

    test('A2 母亲一条配子（纯合）⇒ 前提成立，图仍有内容、格数 = 1 × 2', () {
      final f = _figureOf('XAXA', _kMale);
      expect(f.rowCount, 1, reason: '纯合母亲的配子只有一种（引擎把两半合并）');
      expect(f.columnCount, 2, reason: '父亲的配子恒两种');
      expect(f.cellCount, 2, reason: '格数 = 母亲的配子种数 × 父亲的配子种数');
      for (final c in f.cells) {
        expect(c.maternal.gamete.alleleString, 'A',
            reason: '纯合 ⇒ 母亲那一条恒是 A');
      }
      // 高度随行数走：1 行比 2 行矮（高度的唯一来源是行数）。
      expect(SexLinkedPunnettDiagram.designHeightFor(1),
          lessThan(SexLinkedPunnettDiagram.designHeightFor(2)),
          reason: '高度的唯一来源是行数');
    });
  });

  // ── B 组：因果落点（isDaughter 只看父亲那一条）─────────────────

  group('B 性别只看父亲给的那一条，与母亲给哪条 X 无关', () {
    PunnettCell cellOf(String maternalKey, String paternalKey) => PunnettCell(
          maternal: PunnettChromosome(
              gamete: PunnettGamete.fromKey(maternalKey),
              origin: PunnettOrigin.mother),
          paternal: PunnettChromosome(
              gamete: PunnettGamete.fromKey(paternalKey),
              origin: PunnettOrigin.father),
          rowGamete: PunnettGamete.fromKey(maternalKey),
          columnGamete: PunnettGamete.fromKey(paternalKey),
        );

    test('B1 父亲给 XA ⇒ 无论母亲给 XA 还是 Xa，两格都是女儿', () {
      final a = cellOf('XA', 'XA');
      final b = cellOf('Xa', 'XA');
      expect(a.isDaughter, isTrue, reason: '父亲给的不是 Y ⇒ 女儿');
      expect(b.isDaughter, isTrue,
          reason: '⛔ 本条是本图全部因果的落点：母亲给 Xa 也不该把女儿变成儿子');
      // 两格母亲那一条**不同**（证明「无关」不是因为数据没变）。
      expect(a.maternal.gamete.name, isNot(b.maternal.gamete.name));
      expect(a.maternal.gamete.alleleString, 'A');
      expect(b.maternal.gamete.alleleString, 'a');
    });

    test('B2 父亲给 Y ⇒ 无论母亲给 XA 还是 Xa，两格都是儿子', () {
      final a = cellOf('XA', kPunnettYGamete);
      final b = cellOf('Xa', kPunnettYGamete);
      expect(a.isSon, isTrue, reason: '父亲给的是 Y ⇒ 儿子');
      expect(b.isSon, isTrue);
      expect(a.maternal.gamete.name, isNot(b.maternal.gamete.name),
          reason: '前提：母亲那一条换了，性别仍然只看父亲那一条');
      // 儿子的 Y 上没有位点 ⇒ 不给它画色带（不是「画一个空的」）。
      expect(a.paternal.gamete.hasLocus, isFalse, reason: '⛔ Y 上没有位点');
      expect(a.paternal.gamete.alleleString, isEmpty);
    });

    test('B3 sexLabel 由 isDaughter 推出，isSon 严格互补', () {
      for (final m in const <String>['XA', 'Xa']) {
        for (final p in const <String>['XA', kPunnettYGamete]) {
          final c = cellOf(m, p);
          expect(c.sexLabel, c.isDaughter ? kPunnettDaughterLabel : kPunnettSonLabel,
              reason: '$m × $p：性别标注必须跟着父亲那一条走，⛔ 不是手写字面量');
          expect(c.isSon, !c.isDaughter, reason: '女儿与儿子必须严格互补');
          expect(c.sexLabel, isNotEmpty);
        }
      }
    });

    test('B4 整张图上：同一列两格性别一致，且每格性别与引擎 cross() 对得上', () {
      final f = _figureOf(_kFemale, _kMale);
      final res = SexLinkedEngine().cross(_kFemale, _kMale);
      // ⛔ 引擎的性别按基因型签名索引（⛔ 不许把 `cross` 的排序规则抄一遍）。
      final sexByAlleles = <String, String>{};
      for (final o in res.offspring) {
        final letters = o.genotype.replaceAll('X', '').split('')..sort();
        sexByAlleles[letters.join()] = o.sex;
      }
      expect(f.cells, hasLength(4), reason: '出厂值下四格');
      for (final c in f.cells) {
        final letters = <String>[
          ...c.maternal.gamete.name.replaceAll('X', '').split(''),
          ...c.paternal.gamete.name.replaceAll('X', '').split(''),
        ]..sort();
        final sig = letters.join();
        expect(sexByAlleles.containsKey(sig), isTrue,
            reason: '格 $c 的签名在引擎 cross() 的输出里不存在 —— '
                '图画了一格引擎没算出来的子代');
        expect(sexByAlleles[sig], c.isDaughter ? '雌性' : '雄性',
            reason: '格 $c 的性别与引擎给的对不上（图只凭父亲那一条判性别，'
                '判错就等于教错了因果）');
      }
      for (var j = 0; j < f.columnCount; j++) {
        final byColumn = <bool>{for (final r in f.rows) r.cells[j].isDaughter};
        expect(byColumn.length, 1,
            reason: '⛔ 同一列（同一个父亲配子）下两格性别必须一致 —— '
                '不一致就等于说「性别由母亲给的那条 X 决定」');
      }
    });
  });

  // ── C 组：宿主闸门 + 端到端点名 ────────────────────────────────

  group('C 宿主闸门与端到端', () {
    testWidgets('C1 没算过 ⇒ 整张图不在树上（一个像素都不加）', (t) async {
      await _pumpTab(t);
      expect(find.text('等待计算：结果将在这里展开'), findsOneWidget,
          reason: '前提：出厂态确实是「等计算」');
      expect(find.byType(SexLinkedPunnettDiagram), findsNothing,
          reason: '⛔ 未计算时图**整个组件**都不许挂（不是「挂上去画成 0×0」）');
      // 反向自证：这条不是「探针看不见」蒙对的 —— 点完计算它就出现了（C2）。
      expect(t.takeException(), isNull);
    });

    testWidgets('C2 算出伴性结果 ⇒ 图上点名「母亲给的」「父亲给的」，零方向词',
        (t) async {
      await loadGoldenFonts();
      assertMaterialIconsLoaded();
      assertMonoLoaded();
      await _pumpTab(t);
      await _computeInTab(t);

      expect(find.byType(SexLinkedPunnettDiagram), findsOneWidget,
          reason: 'C2：算出结果后这张图必须上屏');
      expect(find.text('子代是怎么来的'), findsOneWidget,
          reason: '图上方那个块标签必须跟着图一起上屏');
      expect(t.takeException(), isNull);

      final p = _painterOf(t);
      final label = _labelOf(t);

      // ① 语义标签点名对象（B 的实际文案：「女儿：母亲给的 XA 与父亲给的 XA。」）。
      expect(label, isNotEmpty, reason: '图必须有语义标签（纯 CustomPaint 没有文本节点）');
      expect(label.contains('母亲给的'), isTrue, reason: '要点名「母亲给的」');
      expect(label.contains('父亲给的'), isTrue, reason: '要点名「父亲给的」');
      expect(label.contains('母亲给的 XA'), isTrue,
          reason: '⛔ 点名必须是「母亲给的 XA」这种**带对象**的说法，'
              '不能是「母亲给的那一条」这种仍要靠位置消解的说法');
      expect(label.contains('父亲给的 $kPunnettYGamete'), isTrue,
          reason: '「儿子配到的就是父亲给的 Y」必须是看得见的字');
      expect(label.contains('只看父亲给出去的那一条'), isTrue,
          reason: '语义标签必须说清性别由父亲给的是 X 还是 Y 决定');
      expect(label.contains('不同的染色体'), isTrue,
          reason: '语义标签必须说清 X 与 Y 是两条不同的染色体');

      // ② 画布上**看得见**的归属词：每格两条杆各写「母亲/父亲 + 配子名」。
      var rods = 0;
      for (final plate in p.plates) {
        for (final c in plate.row.cells) {
          final m = p.cellLabelSpan(c.maternal).toPlainText();
          final f = p.cellLabelSpan(c.paternal).toPlainText();
          expect(m, startsWith(kPunnettMotherSource),
              reason: '母亲那一条正下方必须写着「$kPunnettMotherSource」，实际「$m」');
          expect(f, startsWith(kPunnettFatherSource),
              reason: '父亲那一条正下方必须写着「$kPunnettFatherSource」，实际「$f」');
          expect(m, endsWith(c.maternal.gamete.name),
              reason: '母亲的归属词里必须连配子名一起写出来（$m）');
          expect(f, endsWith(c.paternal.gamete.name),
              reason: '父亲的归属词里必须连配子名一起写出来（$f）');
          // ③ 性别标注也必须每格一个、且由 isDaughter 推。
          expect(p.sexLabelSpan(c).toPlainText(), c.sexLabel);
          expect(p.measureSpan(p.sexLabelSpan(c)), greaterThan(0),
              reason: '性别标注排版宽度必须 > 0（否则等于没画）');
          expect(p.measureSpan(p.cellLabelSpan(c.paternal)), greaterThan(0),
              reason: '归属词排版宽度必须 > 0（否则等于没画）');
          // 归属词画在杆的**正下方**、性别标注在杆的**正上方**。
          expect(plate.cellLabelCenterY, greaterThan(plate.centerY));
          expect(plate.sexLabelCenterY, lessThan(plate.centerY));
          rods += 2;
        }
      }
      expect(rods, 8, reason: '出厂值下 4 格 × 2 条 = 8 根杆，每根都要有归属标记');
      // 儿子那格父亲给的是 Y ⇒ 写成字，不是「一条没色带的杆」让学生自己推。
      for (final plate in p.plates) {
        for (final c in plate.row.cells.where((c) => c.isSon)) {
          expect(p.cellLabelSpan(c.paternal).toPlainText(),
              '$kPunnettFatherSource$kPunnettYGamete',
              reason: '⛔ 儿子那格父亲给的必须是 $kPunnettYGamete，且写在杆下面');
        }
      }

      // ④ ⛔ 全点名、零方向词：扫**画布上真正排版出去的每一段** + 语义标签。
      _expectNoBannedText(_allScreenText(label, p));
      // 反向自证：点名对象一个都不许少（否则上面几条黑名单是「因为没东西」而绿）。
      for (final w in const <String>['母亲', '父亲', '女儿', '儿子']) {
        expect(_allScreenText(label, p).any((s) => s.contains(w)), isTrue,
            reason: '屏上必须出现「$w」：归属与性别都必须是**看得见**的字');
      }
    });

    testWidgets('C3 图不挂在「存为图片」导出的那棵子树里', (t) async {
      await loadGoldenFonts();
      await _pumpTab(t);
      await _computeInTab(t);
      expect(find.byType(SexLinkedPunnettDiagram), findsOneWidget,
          reason: 'C3 前提：算出结果后图必须在屏上');

      // ⛔ 不能用 `find.byType(RepaintBoundary)` 认边界：这张图**自己内部**也有一个
      //    （`sex_linked_punnett_diagram.dart` 的 `RepaintBoundary`），而它恰恰是
      //    本用例要证明**不在**导出范围里的那个邻居。改用「子树里含某个已知结果
      //    文本」来证明认对了边界。
      final boundary = find.ancestor(
        of: find.text('按性别看表型（条件概率）'),
        matching: find.byType(RepaintBoundary),
      );
      expect(boundary, findsAtLeastNWidgets(1), reason: '前提：结果区有 RepaintBoundary');
      expect(
        find.descendant(of: boundary.first, matching: find.text('按性别看表型（条件概率）')),
        findsOneWidget,
        reason: '前提：认到的最内层 boundary 子树含条件概率卡，它就是 `_resultKey` 那个',
      );
      expect(find.descendant(of: boundary.first, matching: find.byType(SexLinkedPunnettDiagram)),
          findsNothing,
          reason: 'C3：概念图挂在 `FlatSection` 之后、是 `_resultKey` 那个 boundary 的'
              '**兄弟** ⇒ 学生导出的 PNG 只会有子代表与条件概率，不会有这张图');
      // 反向自证：导出用的 boundary 子树非空（不是空树蒙对）+ 图自己内部那个
      // RepaintBoundary 仍在屏上（不是「图没了」蒙对）。
      expect(find.descendant(of: boundary.first, matching: find.byType(Text)), findsWidgets,
          reason: '前提：导出用的 boundary 子树非空');
      expect(
        find.descendant(
            of: find.byType(SexLinkedPunnettDiagram), matching: find.byType(RepaintBoundary)),
        findsOneWidget,
        reason: '前提：图自己内部的 RepaintBoundary 还在 ⇒ 上面 findsNothing 是'
            '「不在导出子树内」，不是「图不在屏上」',
      );
    });
  });

  // ── D 组：像素基线 ────────────────────────────────────────────
  //
  // ⚠️ 少装一个字族就是一批**方框**基线：布局按方框宽度算 ⇒ 这类基线对文本内容
  //    零敏感，是假绿（本项目在图标 / 中文 / 等宽三个字族上各栽过一次）。
  //    ⇒ 每条 golden 用例都先 `loadGoldenFonts()` + 两个自检。
  // ⚠️ 拍照的 finder **不能**用 `find.byType(SexLinkedPunnettDiagram)`：那是
  //    `StatelessWidget`，本身不是 RenderObject ⇒ `matchesGoldenFile` 取不到它的
  //    render object，最后落到**整屏**（基线会对「宿主长什么样」过度敏感）。
  //    改拍带 RenderObject 的 `CustomPaint`。
  for (final tier in const <({String tag, String label, Brightness b})>[
    (tag: 'light', label: '浅色', b: Brightness.light),
    (tag: 'dark', label: '深色', b: Brightness.dark),
  ]) {
    testWidgets('D ${tier.label}像素基线（父亲的两种配子 × 母亲的两种配子 = 四格）',
        (t) async {
      await loadGoldenFonts();
      assertMaterialIconsLoaded();
      assertMonoLoaded();
      AppColors.sync(tier.b);
      await t.pumpWidget(_host(tier.b));
      await t.pump();
      expect(t.takeException(), isNull);
      await expectLater(
        find
            .descendant(
                of: find.byType(SexLinkedPunnettDiagram),
                matching: find.byType(CustomPaint))
            .first,
        matchesGoldenFile('goldens/sex_linked_punnett_${tier.tag}.png'),
      );
    });
  }

  test('D3 两张基线必须已存在、不是空图，且彼此不同（防恒等三元录成一张）', () {
    // ⚠️ 普通 `test()` 的 CWD 是**包根**，而 `matchesGoldenFile` 的路径相对
    //    **测试文件所在目录**（`test/`）⇒ 这里必须写全路径前缀。
    const dir = 'test/goldens/';
    final a = File('${dir}sex_linked_punnett_light.png');
    final b = File('${dir}sex_linked_punnett_dark.png');
    for (final f in <File>[a, b]) {
      expect(f.existsSync(), isTrue, reason: '基线还没录：${f.path}');
      expect(f.lengthSync(), greaterThan(1000),
          reason: '基线 ${f.path} 只有 ${f.lengthSync()} 字节，'
              '多半是一张没画任何东西的纯底色小图（假绿）');
    }
    expect(a.readAsBytesSync(), isNot(equals(b.readAsBytesSync())),
        reason: '浅色与深色录成了同一张 —— 那等于没有深色基线');
  });
}
