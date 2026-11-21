// ════════════════════════════════════════════════════════════════
//  test/strand_ct_matrix_test.dart
//  分子页「两链 C/T 计数」三行四列格阵：两道闸 + 空格纪律守卫
// ════════════════════════════════════════════════════════════════
//
//  ## 这张图最该被钉住的一件事（空格）
//
//  `strandCountsFromCT`（dna_strand_engine.dart:182）只给
//  `c1/t1/c2/t2` 与**全分子**的 `aTotal/tTotal/gTotal/cTotal/total`，
//  ⛔ **没有** `a1/g1/a2/g2`（L1a 在源码级钉死这一点）。
//  ⇒ 12 格里引擎只填 8 格，另外 4 格（链1/链2 各自的 A 与 G）必须**留空**，
//  ⛔ 绝不许填 0 —— 填 0 = 宣称「链1 的 A 是 0 个」，那是本图替引擎编数据。
//
//  ## ⛔ 反假绿纪律
//
//  · 数字判据**不许**去数 `result.某字段`（那是自证）。判据一律取自
//    `testStrandCtPaintProbe` 上报的 **painter 真正落笔的那一笔**：
//    把 painter 里的循环改成少画一格 / 把空格填成 0 ⇒ 对应用例必红。
//  · 期望值直接从引擎字段取（`'${r.t1}'` 这种），⛔ 不在测试里手抄数字。
//  · 收缩判据是**实测高度 0** + 子树里没有 `CustomPaint` + 一条上报都没有，
//    ⛔ 不是「widget 在不在」。
//  · 屏上文案守卫扫的是 **painter 落笔的字符串**（屏上文案 = painter 画的 +
//    那份原样上屏的 `kStrandCtVisibleCopy`），判据是禁词表，不是屏上文案本身。
//
//  ## ⛔ 本轮不录基线
//
//  本文件**没有任何 golden 用例**，**绝不**使用 `--update-goldens`，
//  也不碰 `test/goldens/` 下任何 `.png`。像素基线由主线程录。
// ════════════════════════════════════════════════════════════════

import 'dart:io';

import 'package:biology/engine/dna_strand_engine.dart';
import 'package:biology/pages/widgets/strand_ct_matrix.dart';
import 'package:biology/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 组件源码路径（F 组逐条扫它）。
const String _sourcePath = 'lib/pages/widgets/strand_ct_matrix.dart';

/// 引擎源码路径（L1a 逐条扫它）。
const String _enginePath = 'lib/engine/dna_strand_engine.dart';

// ─────────────────────────── 屏上禁词（判据，不是屏上文案）───────────

/// 方向词。⛔ 本文件里它是**判据**：painter 落笔的任何一个字符串都不得含。
const List<String> kBannedDirectionWords = <String>[
  '上面', '下面', '上边', '下边', '左边', '右边',
  '上方', '下方', '上一行', '下一行', '左端', '右端',
];

// ─────────────────────────── 落笔记录器 ───────────────────────────

/// painter 上报统一记账（`pass` = 一遍重画开始 ⇒ 之前的全部作废）。
class PaintLog {
  final Map<String, List<String>> byKind = <String, List<String>>{};

  List<String> get(String kind) => byKind[kind] ?? const <String>[];

  /// painter 画在屏上的**全部**字符串（S 组扫的就是它）。
  List<String> get allDrawnText => <String>[
        ...get('label'),
        ...get('header'),
        ...get('cell'),
        ...get('blankCell'),
      ];

  void attach() => testStrandCtPaintProbe = record;

  void detach() => testStrandCtPaintProbe = null;

  void record(String kind, String? text) {
    if (kind == 'pass') {
      byKind.clear();
      return;
    }
    byKind.putIfAbsent(kind, () => <String>[]).add(text ?? '');
  }
}

final PaintLog log = PaintLog();

/// 把组件放进一个**已知宽度**的盒子里（宽度决定 4 列装不装得下，必须可控）。
Future<void> pumpBox(WidgetTester tester, double width, Widget child) async {
  tester.view.physicalSize = Size(width, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: Align(
        alignment: Alignment.topLeft,
        child: SizedBox(width: width, child: child),
      ),
    ),
  ));
  await tester.pump();
}

/// ⛔ 收缩判据：**实测高度 0** + 无 `CustomPaint` + 一条上报都没有。
void expectCollapsed(WidgetTester tester) {
  expect(tester.getSize(find.byType(StrandCtMatrix)).height, 0,
      reason: '⛔ 不可画时必须收缩成 0 高度');
  expect(
      find.descendant(
          of: find.byType(StrandCtMatrix), matching: find.byType(CustomPaint)),
      findsNothing,
      reason: '⛔ 不留空框');
  expect(log.byKind, isEmpty, reason: '⛔ 不留图例 / 依据行 / 占位');
}

void main() {
  setUp(() {
    AppColors.sync(Brightness.light);
    log.attach();
    log.byKind.clear();
  });
  tearDown(() {
    log.detach();
    AppColors.debugClearOverride();
  });

  // ═══════════════ L 组：引擎基线（实测钉死）═══════════════

  group('L 引擎基线：字段逐字实测 + 引擎没有 a1/g1/a2/g2', () {
    test('L1 strandCountsFromCT 两组输入的真实字段', () {
      final a = strandCountsFromCT(c1: 10, t1: 20, c2: 15, t2: 25);
      expect(
          <int>[
            a.c1, a.t1, a.c2, a.t2, a.aTotal, a.tTotal, a.gTotal, a.cTotal,
            a.total,
          ],
          <int>[10, 20, 15, 25, 45, 45, 25, 25, 140]);
      final b = strandCountsFromCT(c1: 7, t1: 3, c2: 11, t2: 9);
      expect(
          <int>[
            b.c1, b.t1, b.c2, b.t2, b.aTotal, b.tTotal, b.gTotal, b.cTotal,
            b.total,
          ],
          <int>[7, 3, 11, 9, 12, 12, 18, 18, 60]);
      expect(() => strandCountsFromCT(c1: -1, t1: 0, c2: 0, t2: 0),
          throwsArgumentError);
    });

    // L1a ⛔ StrandCTResult 只有 8 个 int 字段（c1/t1/c2/t2/aTotal/tTotal/gTotal/cTotal），
    //    ⛔ 没有 a1/g1/a2/g2 —— 引擎没给链1/链2 各自的 A 与 G ⇒ 那 4 格必须留空。
    //    这条在源码级钉死：字段名单写死，多一个 int 字段即红（引擎若补了 a1 等，本图的空格就该补上）。
    test('L1a StrandCTResult int 字段名单钉死（无 a1/g1/a2/g2）', () {
      // L1a 正则逐条断：StrandCTResult 类体内不得出现 a1/g1/a2/g2 字段。
      // ⛔ 这是「那 4 格必须留空」的源码级依据：引擎没给链1/链2 各自的 A 与 G。
      //    逗号并列（`final int a1, t1, g1, c1;`）也会被 `a1`/`g1` 命中。
      final src = File(_enginePath).readAsStringSync();
      final m = RegExp(r'class\s+StrandCTResult\s*\{(.*?)\n\}', dotAll: true)
          .firstMatch(src);
      expect(m, isNotNull, reason: 'StrandCTResult 类必须存在');
      final body = m!.group(1)!;
      for (final f in const <String>['a1', 'g1', 'a2', 'g2']) {
        expect(RegExp('\\b$f\\b').hasMatch(body), isFalse,
            reason: '⛔ StrandCTResult 不该有字段 $f —— 若新增了，本图的空格就该补上');
      }
      // 正向锚：类体内必须确有 c1/t1/c2/t2 与 aTotal/tTotal/gTotal/cTotal（8 格数据源）。
      for (final f in const <String>[
        'c1', 't1', 'c2', 't2', 'aTotal', 'tTotal', 'gTotal', 'cTotal'
      ]) {
        expect(RegExp('\\b$f\\b').hasMatch(body), isTrue,
            reason: 'StrandCTResult 必须有字段 $f（本图 8 格的数据源）');
      }
    });
  });

  // ═══════════════ A 组：数据闸 dataReason（逐条）═══════════════

  group('A 数据闸 dataReason：每条违例各给一句屏上说明，合法返 null', () {
    final ok = strandCountsFromCT(c1: 10, t1: 20, c2: 15, t2: 25);

    StrandCTResult copy({
      int? c1,
      int? t1,
      int? c2,
      int? t2,
      int? aTotal,
      int? tTotal,
      int? gTotal,
      int? cTotal,
      int? total,
    }) =>
        StrandCTResult(
          c1: c1 ?? ok.c1,
          t1: t1 ?? ok.t1,
          c2: c2 ?? ok.c2,
          t2: t2 ?? ok.t2,
          aTotal: aTotal ?? ok.aTotal,
          tTotal: tTotal ?? ok.tTotal,
          gTotal: gTotal ?? ok.gTotal,
          cTotal: cTotal ?? ok.cTotal,
          total: total ?? ok.total,
        );

    test('A0 合法数据 ⇒ null（可画）', () {
      expect(StrandCtMatrix.dataReason(ok), isNull);
    });

    test('A1 null 结果 ⇒ 说明里没有数据可画', () {
      expect(StrandCtMatrix.dataReason(null),
          '还没有算出两链 C/T 的计数，本图没有数据可画。');
    });

    test('A2 任一为负 ⇒ 负数那一句（9 个字段逐个打）', () {
      expect(StrandCtMatrix.dataReason(copy(c1: -1)),
          '引擎给出的计数里出现了负数，本图不画。');
      expect(StrandCtMatrix.dataReason(copy(t1: -1)),
          '引擎给出的计数里出现了负数，本图不画。');
      expect(StrandCtMatrix.dataReason(copy(c2: -1)),
          '引擎给出的计数里出现了负数，本图不画。');
      expect(StrandCtMatrix.dataReason(copy(t2: -1)),
          '引擎给出的计数里出现了负数，本图不画。');
      expect(StrandCtMatrix.dataReason(copy(aTotal: -1)),
          '引擎给出的计数里出现了负数，本图不画。');
      expect(StrandCtMatrix.dataReason(copy(tTotal: -1)),
          '引擎给出的计数里出现了负数，本图不画。');
      expect(StrandCtMatrix.dataReason(copy(gTotal: -1)),
          '引擎给出的计数里出现了负数，本图不画。');
      expect(StrandCtMatrix.dataReason(copy(cTotal: -1)),
          '引擎给出的计数里出现了负数，本图不画。');
      expect(StrandCtMatrix.dataReason(copy(total: -1)),
          '引擎给出的计数里出现了负数，本图不画。');
    });

    test('A3 aTotal != tTotal ⇒ A/T、G/C 对不上那一句', () {
      expect(StrandCtMatrix.dataReason(copy(aTotal: ok.aTotal + 1)),
          '全分子的 A 与 T、G 与 C 两处计数对不上，本图不画。');
      expect(StrandCtMatrix.dataReason(copy(tTotal: ok.tTotal - 1)),
          '全分子的 A 与 T、G 与 C 两处计数对不上，本图不画。');
    });

    test('A4 gTotal != cTotal ⇒ 同一句（这条独立存在，删任一半都红）', () {
      expect(StrandCtMatrix.dataReason(copy(gTotal: ok.gTotal + 1)),
          '全分子的 A 与 T、G 与 C 两处计数对不上，本图不画。');
      expect(StrandCtMatrix.dataReason(copy(cTotal: ok.cTotal - 1)),
          '全分子的 A 与 T、G 与 C 两处计数对不上，本图不画。');
    });

    test('A5 total != (aTotal+gTotal)*2 ⇒ 总数对不上那一句', () {
      expect(StrandCtMatrix.dataReason(copy(total: ok.total + 2)),
          '碱基总数与各格的计数对不上，本图不画。');
      expect(StrandCtMatrix.dataReason(copy(total: ok.total - 1)),
          '碱基总数与各格的计数对不上，本图不画。');
    });

    test('A6 三条判据同假只报第一条：数据优先于宽度（skipReason 里再验）', () {
      // aTotal!=tTotal 与 total 错同时存在 ⇒ 必须先报 A/T、G/C 那一句。
      final both = copy(aTotal: ok.aTotal + 1, total: ok.total + 2);
      expect(StrandCtMatrix.dataReason(both),
          '全分子的 A 与 T、G 与 C 两处计数对不上，本图不画。');
    });
  });

  // ═══════════════ B 组：宽度闸 skipReason ═══════════════

  group('B 宽度闸 skipReason：装不下 4 列 ⇒ 一句说明；数据闸优先', () {
    final ok = strandCountsFromCT(c1: 10, t1: 20, c2: 15, t2: 25);

    test('B1 320 宽合法数据 ⇒ null（且 canDraw 为真）', () {
      expect(StrandCtMatrix.skipReason(ok, 320), isNull);
      expect(StrandCtMatrix.canDraw(ok, 320), isTrue);
    });

    test('B2 极小宽度 ⇒ 排不进 4 列那一句（⛔ 零静默）', () {
      final reason = StrandCtMatrix.skipReason(ok, 8);
      expect(reason, isNotNull);
      expect(reason, contains('最小的字号也排不进 4 列'));
      expect(reason, contains('本图不画'));
      expect(StrandCtMatrix.canDraw(ok, 8), isFalse);
      // ⛔ 文字结果不受影响：这句承诺也要在屏上说清。
      expect(reason, contains('屏上的文字结果不受影响'));
    });

    test('B3 数据闸优先：数据错 + 宽度够 ⇒ 报数据那一句', () {
      final bad = StrandCTResult(
        c1: 10, t1: 20, c2: 15, t2: 25,
        aTotal: 45, tTotal: 44, gTotal: 25, cTotal: 25, total: 140,
      );
      expect(StrandCtMatrix.skipReason(bad, 320),
          '全分子的 A 与 T、G 与 C 两处计数对不上，本图不画。',
          reason: '⛔ 数据闸必须先于宽度闸判（删 skipReason 里的 dataReason 调用即红）');
    });

    test('B4 数据错 + 宽度也极小 ⇒ 仍报数据那一句（宽度闸不许抢跑）', () {
      final bad = StrandCTResult(
        c1: 10, t1: 20, c2: 15, t2: 25,
        aTotal: 45, tTotal: 45, gTotal: 25, cTotal: 24, total: 140,
      );
      expect(StrandCtMatrix.skipReason(bad, 8),
          '全分子的 A 与 T、G 与 C 两处计数对不上，本图不画。');
    });

    test('B5 无界 / 非正宽度 ⇒ 走设计宽度兜底 320，仍判得出', () {
      // availableWidth <= 0 或无限 ⇒ resolve 用 kStrandCtDesignWidth(320)。
      expect(StrandCtMatrix.skipReason(ok, double.infinity), isNull);
      expect(StrandCtMatrix.skipReason(ok, 0), isNull);
      expect(StrandCtMatrix.skipReason(ok, -5), isNull);
    });

    test('B6 闸门给出的那句说明自身合规（无星号、无方向词）', () {
      for (final r in <String?>[
        StrandCtMatrix.skipReason(null, 320),
        StrandCtMatrix.skipReason(ok, 8),
      ]) {
        expect(r, isNotNull);
        expect(r!.contains('*'), isFalse, reason: '⛔ 屏上文案禁 markdown 星号');
        for (final w in kBannedDirectionWords) {
          expect(r.contains(w), isFalse, reason: '⛔ 屏上禁方向词：$w');
        }
      }
    });
  });

  // ═══════════════ C 组：格值逐字来自引擎 ═══════════════

  group('C 组件：格上的数字逐字等于引擎字段（判据取自 painter 落笔）', () {
    testWidgets('C1 8 格数字 == 引擎字段，列名 == 四列，顺序 == 行优先列序',
        (tester) async {
      final r = strandCountsFromCT(c1: 10, t1: 20, c2: 15, t2: 25);
      await pumpBox(tester, 320, StrandCtMatrix(result: r));
      // ⛔ 期望值直接从引擎字段取，⛔ 不在测试里手抄数字。
      // 行优先：链1(T,C) → 链2(T,C) → 全分子(A,T,G,C)。
      expect(log.get('cell'), <String>[
        '${r.t1}', '${r.c1}', // 链1：T、C（引擎没给 A、G）
        '${r.t2}', '${r.c2}', // 链2
        '${r.aTotal}', '${r.tTotal}', '${r.gTotal}', '${r.cTotal}', // 全分子
      ]);
      expect(log.get('header'), kStrandCtColumns,
          reason: '⛔ 列名就是 kStrandCtColumns 那四个，⛔ 不在 painter 里另写一遍');
      expect(log.get('label'), contains(kStrandCtBlankLegend));
      expect(log.get('label'), contains('链1'));
      expect(log.get('label'), contains('链2'));
      expect(log.get('label'), contains('全分子'));
      expect(log.get('label'), contains(strandCtBasisLine(r)),
          reason: '⛔ 依据行 == 组件那份原文，守卫与图共用同一份');
    });

    test('C2 cellValue 静态表：12 格里恰 8 格非空，且逐字等于引擎字段', () {
      final r = strandCountsFromCT(c1: 7, t1: 3, c2: 11, t2: 9);
      // 行优先全表（null = 引擎没给）。
      final expected = <List<int?>>[
        <int?>[null, r.t1, null, r.c1],
        <int?>[null, r.t2, null, r.c2],
        <int?>[r.aTotal, r.tTotal, r.gTotal, r.cTotal],
      ];
      for (var row = 0; row < 3; row++) {
        for (var col = 0; col < 4; col++) {
          expect(StrandCtMatrix.cellValue(r, row, col), expected[row][col],
              reason: '⛔ ($row,$col) 必须是引擎字段本身或 null，⛔ 不许有算术');
          expect(StrandCtMatrix.isGiven(r, row, col),
              expected[row][col] != null);
        }
      }
      // ⛔ 空格位置由「引擎有没有这个字段」决定，⛔ 不由数值大小决定。
      final zero = strandCountsFromCT(c1: 0, t1: 0, c2: 0, t2: 0);
      for (var row = 0; row < 2; row++) {
        for (final col in const <int>[0, 2]) {
          expect(StrandCtMatrix.cellValue(zero, row, col), isNull,
              reason: '⛔ 即使输入全 0，链1/链2 的 A、G 仍没字段 ⇒ 仍必须是空格');
        }
      }
    });

    test('C3 依据行只复述引擎字段：每个数都在原文里', () {
      final r = strandCountsFromCT(c1: 10, t1: 20, c2: 15, t2: 25);
      final b = strandCtBasisLine(r);
      for (final v in <int>[
        r.c1, r.t1, r.c2, r.t2, r.aTotal, r.tTotal, r.gTotal, r.cTotal, r.total,
      ]) {
        expect(b.contains('$v'), isTrue, reason: '⛔ 依据行漏了引擎给的数 $v');
      }
    });
  });

  // ═══════════════ D 组：blankCell 不代填 ═══════════════

  group('D 空格纪律：引擎没给的 4 格只画空框，⛔ 绝不填 0', () {
    testWidgets('D1 标准输入：恰 4 格 blankCell，8 格数字，数字里没有 0',
        (tester) async {
      final r = strandCountsFromCT(c1: 10, t1: 20, c2: 15, t2: 25);
      await pumpBox(tester, 320, StrandCtMatrix(result: r));
      expect(log.get('blankCell'), <String>['链1/A', '链1/G', '链2/A', '链2/G'],
          reason: '⛔ 12 − 8 = 4 格引擎没给（链1/链2 各自的 A 与 G）');
      expect(log.get('cell').length, 8,
          reason: '⛔ 只画 8 个数字；多一个就是有人替引擎编了一个数');
      expect(log.get('cell').contains('0'), isFalse,
          reason: '⛔ 这一组输入下引擎没给出任何 0，屏上就不该冒出一个 0');
      for (final s in log.get('blankCell')) {
        // ⛔ 空格上报里不许夹带数字（链名里的 1/2 是链号，斜杠后才是格名）。
        expect(RegExp(r'\d').hasMatch(s.substring(s.indexOf('/'))), isFalse,
            reason: '⛔ 空格上报里不许夹带数字：$s');
      }
    });

    testWidgets('D2 ⛔ 全 0 输入：合法的 8 个 0 照画，空格仍恰 4 格（两者不许混）',
        (tester) async {
      final r = strandCountsFromCT(c1: 0, t1: 0, c2: 0, t2: 0);
      expect(r.total, 0);
      await pumpBox(tester, 320, StrandCtMatrix(result: r));
      expect(log.get('blankCell').length, 4);
      expect(log.get('cell').length, 8);
      expect(log.get('cell'), everyElement('0'),
          reason: '⛔ 引擎给的合法 0 要照画；空格仍不许被填');
      expect(log.get('cell').where((s) => s == '0').length, 8);
    });
  });

  // ═══════════════ E 组：不可画 ⇒ 收缩 ═══════════════

  group('E 不可画：整棵子树收缩成 SizedBox.shrink，⛔ 不留空框/标题/占位', () {
    testWidgets('E1 数据闸违例（tTotal 44）⇒ 收缩', (tester) async {
      final bad = StrandCTResult(
        c1: 10, t1: 20, c2: 15, t2: 25,
        aTotal: 45, tTotal: 44, gTotal: 25, cTotal: 25, total: 140,
      );
      expect(StrandCtMatrix.dataReason(bad), isNotNull);
      expect(StrandCtMatrix.skipReason(bad, 320), isNotNull);
      await pumpBox(tester, 320, StrandCtMatrix(result: bad));
      expectCollapsed(tester);
      expect(tester.takeException(), isNull);
    });

    // ⛔ widget 的 result 字段非空（宿主只在做完闸门后才挂组件），
    //    null 那一路由闸门层覆盖（A1 / B3）⇒ 这里不重复造。

    testWidgets('E3 宽度闸违例（8px）⇒ 收缩', (tester) async {
      final ok = strandCountsFromCT(c1: 10, t1: 20, c2: 15, t2: 25);
      expect(StrandCtMatrix.skipReason(ok, 8), isNotNull);
      await pumpBox(tester, 8, StrandCtMatrix(result: ok));
      expectCollapsed(tester);
    });

    testWidgets('E4 合法数据 + 320 宽 ⇒ 真的画（高 > 0，有 CustomPaint）',
        (tester) async {
      final ok = strandCountsFromCT(c1: 10, t1: 20, c2: 15, t2: 25);
      await pumpBox(tester, 320, StrandCtMatrix(result: ok));
      expect(tester.getSize(find.byType(StrandCtMatrix)).height,
          greaterThan(0));
      expect(
          find.descendant(
              of: find.byType(StrandCtMatrix),
              matching: find.byType(CustomPaint)),
          findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  // ═══════════════ S 组：屏上文案守卫 ═══════════════

  group('S 屏上文案：无星号、无方向词，图例定义级', () {
    testWidgets('S1 painter 落笔的每一个字符串都合规', (tester) async {
      final r = strandCountsFromCT(c1: 10, t1: 20, c2: 15, t2: 25);
      await pumpBox(tester, 320, StrandCtMatrix(result: r));
      expect(log.allDrawnText, isNotEmpty,
          reason: '⛔ 前提：这一遍真的画了东西');
      for (final s in log.allDrawnText) {
        expect(s.contains('*'), isFalse, reason: '⛔ 屏上文案禁 markdown 星号：$s');
        for (final w in kBannedDirectionWords) {
          expect(s.contains(w), isFalse, reason: '⛔ 屏上禁方向词 $w：$s');
        }
      }
      // ⛔ 空格的含义必须是「定义级」那一句，⛔ 不许在 painter 里另写一版。
      expect(log.get('label'), contains(kStrandCtBlankLegend));
      expect(log.get('label').where((s) => s == kStrandCtBlankLegend).length, 1,
          reason: '⛔ 图例只画一遍');
    });

    test('S2 kStrandCtVisibleCopy 自身合规（它就是会被画上屏的那份清单）', () {
      for (final s in kStrandCtVisibleCopy) {
        expect(s.contains('*'), isFalse, reason: '⛔ 禁星号：$s');
        for (final w in kBannedDirectionWords) {
          expect(s.contains(w), isFalse, reason: '⛔ 禁方向词 $w：$s');
        }
      }
      expect(kStrandCtVisibleCopy, contains(kStrandCtBlankLegend));
      expect(kStrandCtVisibleCopy, containsAll(kStrandCtColumns));
      expect(kStrandCtVisibleCopy, containsAll(kStrandCtRows));
    });

    test('S3 语义标签对读屏用户也诚实：空格说「引擎没给」', () {
      final r = strandCountsFromCT(c1: 10, t1: 20, c2: 15, t2: 25);
      final label = StrandCtMatrix.semanticsLabel(r);
      expect(label, contains(kStrandCtBlankLegend));
      expect(label, contains('（引擎没给）'));
      expect(label, contains('${r.total}'));
    });
  });

  // ═══════════════ F 组：源码级诚实守卫 ═══════════════

  group('F 源码级：禁位图、禁代填、cellValue 纯字段读取', () {
    test('F1 ⛔ 禁位图：组件源码不得引用任何位图/Image 出口', () {
      final src = File(_sourcePath).readAsStringSync();
      for (final banned in const <String>[
        'AssetImage', 'NetworkImage', 'FileImage', 'MemoryImage',
        'Image.asset', 'Image.network', 'Image.file', 'Image.memory',
        'SvgPicture', 'PictureProvider',
      ]) {
        expect(src.contains(banned), isFalse,
            reason: '⛔ 本图纯 CustomPainter/TextPainter 代码绘制，禁位图：$banned');
      }
      // 正向锚：图必须真走 CustomPainter。
      expect(src.contains('extends CustomPainter'), isTrue);
      expect(src.contains('CustomPaint('), isTrue);
    });

    test('F2 ⛔ cellValue 表是全文件唯一的数字来源：源码里 painter 不得另起算术',
        () {
      final src = File(_sourcePath).readAsStringSync();
      // 锚住纪律注释与 switch 表都在（注释被删 = 有人想藏改写历史）。
      expect(src.contains('纯字段读取'), isTrue,
          reason: '⛔ cellValue 的纪律注释必须在');
      expect(src.contains('return 的一律是引擎字段本身'), isTrue);
      // ⛔ 空格分支不许出现填 0 的写法（painter 的 blank 分支里出现 0 即红）。
      // 锚 painter 的空格分支：`if (v == null) { ... _frame ... continue;`。
      // ⚠️ 组件里有两处 `if (v == null)`：一处在 semanticsLabel（`:413` 三元的
      // `v == null ?` 不是这个形态）、一处在 painter（`:576` 带 `_frame`）。
      // 用 `_frame` 正向锚住 painter 那一支，别误匹配 semantics 的短分支。
      final blankBranch = RegExp(
          r'if \(v == null\) \{\s*//[^\n]*\n\s*_frame\(canvas, r, border\);',
          dotAll: true);
      final m = blankBranch.firstMatch(src);
      expect(m, isNotNull, reason: '⛔ 空格分支必须存在（只有框、没有字）');
      final branch = m!.group(0)!;
      expect(branch.contains('_frame'), isTrue,
          reason: '⛔ 空格分支只画框（_frame），⛔ 不画字');
      // ⛔ 空格分支里绝不允许出现「填 0」一类的字面条目（只画框、没有字）。
      //    断 `cellValue` 返回 null 时 painter 不得把空格画成 '0' 这个字面。
      expect(branch.contains("'0'"), isFalse,
          reason: "⛔ 空格分支里绝不允许出现 '0' 字面条目（填 0 = 替引擎编数据）");
    });
  });
}
