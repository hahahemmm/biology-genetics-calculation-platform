// ════════════════════════════════════════════════════════════════
//  test/mutation_diff_diagram_test.dart
//  变异页「基因突变」页签：原序列 / 突变后序列 密码子对照图
// ════════════════════════════════════════════════════════════════
//
//  ## 这张图能画，是因为引擎**已经把「哪一段变了」算出来了**
//
//  图上每一个碱基都逐字取自 `MutatedSequence.original` / `.mutated`。
//  引擎给不出的东西，图上一个字都不许替它说：
//
//  · ⛔ **不许出现任何氨基酸名字**（中文名 / 三字母 / 一字母代码）。全仓
//    **没有密码子到氨基酸的对照表**：`dna_engine.geneExpression()` 的
//    `aminoAcids` 是**学生手输的整数**（`dna_engine.dart:36,126-130`），
//    教材里也只有一句「64 个密码子」的教科书散文。
//    （E6 把这条钉成**源码级**守卫：全文件扫中文名 + 三字母代码。）
//  · ⛔ **不许说多肽链变没变**。引擎只给了 `silent`
//    （`mutation_engine.dart:153`：`originalCodon == mutatedCodon`），
//    它没有、也不可能推出多肽链。⇒ 图例只说「受影响密码子没变 / 变了」，
//    那是逐字读两个 codon 字段（`mutationDiffCodonUnchanged`）。
//  · ⛔ 不许画碱基配对双螺旋 / 染色体：引擎只给一维字符串。
//
//  ## ⛔ 反假绿纪律
//
//  · B 组 ⛔ **不许在测试里自己切一遍密码子**：判据取自
//    `mutationDiffCodonText`（与 `mutation_engine.dart:138-143` 逐字同源的
//    唯一切法，painter 画的每个碱基都取自它的返回值）。在测试里另切一份
//    只能证明抄对了。
//  · B2 ⛔ 断言的是**「标出的那一框」**，用 `mutationDiffMarksCodon` 定位，
//    ⛔ 不是「最后一框」/「第一框」。
//  · C 组 ⛔ 对齐口径的**参考模型不许读本文件的函数**：`referenceCounterpart`
//    是测试自己按「插入点之后整体 -1」写的，图的
//    `mutationDiffCounterpartIndex` 逐项对撞它。C4 再拿**恒等映射**
//    （= 同下标对齐）证明它就是错位。
//  · D 组 ⛔ 收缩判据是**实测高度为 0** + **子树里没有 CustomPaint / 图例文字**，
//    不是「widget 在不在」——组件本来就可以在树里而渲染成 0×0。
//  · E6 ⛔ 扫的是**全文件**（含注释），因为诚实红线是「这个文件里不许有这些字」。
//    E1/E2/E5/E8 扫的是**剥掉注释后的代码**（本文件的文档正当地提到了
//    `Color(0x…)` / `lethal` / `**` 这些被禁的写法本身，禁令不能把自己的守卫弄红）。
//
//  ## ⛔ 本轮不录基线
//
//  本文件**没有**任何 golden 用例，**绝不**使用 `--update-goldens`。
//  像素基线由主线程录。**没有像素基线就意味着「画得像不像」没有牙齿**——
//  B6 只能证明框位几何算对了，证不了笔画落在像素上；那一层由主线程目检兜底。
// ════════════════════════════════════════════════════════════════

import 'dart:io';
import 'dart:math' show pow;

import 'package:biology/engine/mutation_engine.dart';
import 'package:biology/pages/variation_page.dart';
import 'package:biology/pages/widgets/mutation_diff_diagram.dart';
import 'package:biology/state/first_run_store.dart';
import 'package:biology/state/mistake_book.dart';
import 'package:biology/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 本文件的源码路径（E 组逐条扫它）。
const String _sourcePath = 'lib/pages/widgets/mutation_diff_diagram.dart';

/// 四条实测用例（引擎实跑的字段值见 A 组，此处只放输入）。
///
/// 第 4 条是**同义**那一种：缺失一个碱基恰好让该密码子逐字不变
/// （`AAAAAA` 缺首位 ⇒ 原 `AAA`、新 `AAA`），用来把
/// `mutationDiffCodonUnchanged == true` 那一半也断到。
const List<(String, String, int, String?)> _cases = [
  ('ATGCCGTA', 'sub', 2, 'A'),
  ('ATGGCCAAT', 'ins', 3, 'A'),
  ('ATGGCCAAT', 'del', 3, null),
  ('AAAAAA', 'del', 0, null),
];

MutatedSequence _run((String, String, int, String?) c) => mutateSequence(
      sequence: c.$1,
      type: c.$2,
      position: c.$3,
      newBase: c.$4,
    );

/// 测试自带的参考模型（⛔ 不读本文件的函数）：突变后序列第 [j] 个碱基对应的
/// 原序列下标。插入点之后整体 -1 / +1，就是「按偏移量对齐」的真定义。
int referenceCounterpart(String type, int position, int j) {
  if (type == '插入') return j <= position ? j : j - 1;
  if (type == '缺失') return j < position ? j : j + 1;
  return j;
}

void main() {
  // ───────────────── A 组：引擎实测基线 ─────────────────

  group('A 引擎实测：四种输入的逐字字段值（现象发不发作的锚点）', () {
    test('A1 替换 ATGCCGTA 位置 2 → ATA', () {
      final r = _run(_cases[0]);
      expect(r.type, '替换');
      expect(r.original, 'ATGCCGTA');
      expect(r.mutated, 'ATACCGTA');
      expect(r.position, 2);
      expect(r.codonIndex, 0);
      expect(r.originalCodon, 'ATG');
      expect(r.mutatedCodon, 'ATA');
      expect(r.silent, isFalse);
      expect(r.original.length, 8);
      expect(r.mutated.length, 8, reason: '替换：两条串等长');
    });

    test('A2 插入 ATGGCCAAT 位置 3 插 A → ATGAGCCAAT（长度 +1）', () {
      final r = _run(_cases[1]);
      expect(r.type, '插入');
      expect(r.original, 'ATGGCCAAT');
      expect(r.mutated, 'ATGAGCCAAT');
      expect(r.position, 3);
      expect(r.codonIndex, 1);
      expect(r.originalCodon, 'GCC');
      expect(r.mutatedCodon, 'AGC');
      expect(r.silent, isFalse);
      expect(r.mutated.length, r.original.length + 1);
    });

    test('A3 缺失 ATGGCCAAT 位置 3 → ATGCCAAT（长度 -1）', () {
      final r = _run(_cases[2]);
      expect(r.type, '缺失');
      expect(r.original, 'ATGGCCAAT');
      expect(r.mutated, 'ATGCCAAT');
      expect(r.position, 3);
      expect(r.codonIndex, 1);
      expect(r.originalCodon, 'GCC');
      expect(r.mutatedCodon, 'CCA');
      expect(r.silent, isFalse);
      expect(r.mutated.length, r.original.length - 1);
    });

    test('A4 缺失 AAAAAA 位置 0 → AAAAA：silent = true（两个 codon 逐字相同）',
        () {
      final r = _run(_cases[3]);
      expect(r.type, '缺失');
      expect(r.mutated, 'AAAAA');
      expect(r.codonIndex, 0);
      expect(r.originalCodon, 'AAA');
      expect(r.mutatedCodon, 'AAA');
      expect(r.silent, isTrue);
      expect(mutationDiffCodonUnchanged(r), isTrue,
          reason: '图例要说「受影响密码子没变」的那一半必须被断到');
    });

    test('A5 位置越界 ⇒ 引擎抛 ArgumentError（现象真的发作了）', () {
      expect(
          () => mutateSequence(sequence: 'ATGCCGTA', type: 'sub', position: 99),
          throwsA(isA<ArgumentError>()));
      expect(
          () => mutateSequence(sequence: 'ATGCCGTA', type: 'ins', position: 99),
          throwsA(isA<ArgumentError>()));
      try {
        mutateSequence(sequence: 'ATGCCGTA', type: 'sub', position: 99);
        fail('位置越界必须抛错');
      } on ArgumentError catch (e) {
        expect(e.message, '位置越界');
      }
      // 边界：插入可等于串长（追加到末尾），替换不可。
      final atEnd = mutateSequence(sequence: 'ATG', type: 'ins', position: 3);
      expect(atEnd.mutated, 'ATGA');
      expect(mutationDiffIsDrawable(atEnd), isTrue,
          reason: '合法边界不许被闸门误杀');
    });
  });

  // ───────────────── B 组：图与引擎的接缝（验收 1 / 2 / 3） ─────────────────

  group('B 图：每个碱基逐字来自引擎、框数由长度算出、标框落在 codonIndex', () {
    test('B1 框数 == 由 original.length 算出的「3 碱基一框」个数', () {
      for (final c in _cases) {
        final r = _run(c);
        expect(mutationDiffCodonCount(r.original.length),
            (r.original.length + 2) ~/ 3,
            reason: '${r.type}：框数必须由原序列长度算出');
        expect(mutationDiffCodonCount(r.mutated.length),
            (r.mutated.length + 2) ~/ 3,
            reason: '${r.type}：突变后序列的框数由它自己的长度算出');
      }
      // ⛔ 框数不是写死的：8 → 3 框、9 → 3 框、10 → 4 框、1 → 1 框。
      expect(mutationDiffCodonCount(8), 3);
      expect(mutationDiffCodonCount(9), 3);
      expect(mutationDiffCodonCount(10), 4);
      expect(mutationDiffCodonCount(1), 1);
      expect(mutationDiffCodonCount(0), 0);
    });

    test('B2 标出的那一框落在 codonIndex 上，且框里两串逐字等于两个 codon 字段',
        () {
      for (final c in _cases) {
        final r = _run(c);
        final marked = [
          for (var i = 0;
              i < mutationDiffCodonCount(r.original.length);
              i++)
            if (mutationDiffMarksCodon(r, i)) i,
        ];
        expect(marked, [r.codonIndex],
            reason: '${r.type}：有且只有一框被标出，且下标 == codonIndex');

        // ⛔ 判据取自 painter 画字用的那个函数（唯一切法）。
        expect(mutationDiffCodonText(r.original, marked.single),
            r.originalCodon,
            reason: '${r.type}：标出的框里原序列那 3 个碱基必须逐字等于 originalCodon');
        expect(mutationDiffCodonText(r.mutated, marked.single),
            r.mutatedCodon,
            reason: '${r.type}：标出的框里突变后那 3 个碱基必须逐字等于 mutatedCodon');
      }
    });

    test('B3 图上画出的碱基逐字等于两条串（逐框拼起来就是原串，⛔ 没写死）', () {
      for (final c in _cases) {
        final r = _run(c);
        for (final seq in [r.original, r.mutated]) {
          final boxes = mutationDiffCodonCount(seq.length);
          final painted = List.generate(
                  boxes, (i) => mutationDiffCodonText(seq, i))
              .join();
          expect(painted, seq,
              reason: '${r.type}：${boxes} 个框拼起来必须逐字还原引擎那条串');
        }
      }
      // ⛔ 换一条完全不同的序列，判据跟着走（证明不是拿第一条用例的答案写死的）。
      //    实测：'TTTAAACCCGGG' 下标 7 是 C，换成 T ⇒ 'TTTAAACTCGGG'，
      //    受影响密码子下标 2（CCC → CTC）。
      final other = mutateSequence(
          sequence: 'TTTAAACCCGGG', type: 'sub', position: 7, newBase: 'T');
      expect(other.original, 'TTTAAACCCGGG');
      expect(other.mutated, 'TTTAAACTCGGG');
      expect(other.codonIndex, 2);
      expect(other.originalCodon, 'CCC');
      expect(other.mutatedCodon, 'CTC');
      expect(mutationDiffCodonText(other.original, other.codonIndex),
          other.originalCodon);
      expect(List.generate(mutationDiffCodonCount(12),
              (i) => mutationDiffCodonText(other.mutated, i))
          .join(),
          other.mutated);
    });

    test('B4 几何：框位按 codonIndex 落位，跨行连号（codonsPerRow = 4）', () {
      const layout = MutationDiffLayout(
          originalCodonCount: 12, mutatedCodonCount: 12);
      expect(layout.codonsPerRow, 4, reason: '实测：一行 4 个密码子 = 12 个碱基');
      final boxes = List.generate(12, (i) => layout.boxRectAt(i, 0));
      expect(boxes.length, 12);
      // 第 1 行的 4 框同高，第 2 行的 4 框同高且更靠后。
      expect(boxes.take(4).map((r) => r.top).toSet().length, 1);
      expect(boxes.skip(4).take(4).map((r) => r.top).toSet().length, 1);
      expect(boxes[4].top, greaterThan(boxes[0].top));
      expect(boxes[4].left, boxes[0].left, reason: '换行后回到该行第 1 列');
      // 标出的那一框就是 codonIndex 那一框（不是第一框、不是最后一框）。
      final r = _run(_cases[2]); // codonIndex = 1
      expect(mutationDiffMarksCodon(r, r.codonIndex), isTrue);
      expect(mutationDiffMarksCodon(r, 0), isFalse);
      expect(mutationDiffMarksCodon(r, 2), isFalse);
      // 两条序列的框位不重叠（各画各的标尺与框）。
      expect(layout.boxRectAt(0, 1).top,
          greaterThan(layout.boxRectAt(11, 0).bottom));
    });

    test('B5 同义那一种：图例那一半也说「没变」', () {
      final r = _run(_cases[3]);
      expect(r.silent, isTrue);
      expect(mutationDiffCodonUnchanged(r), isTrue);
      expect(mutationDiffCodonUnchanged(_run(_cases[0])), isFalse);
    });
  });

  // ───────────────── C 组：插入 / 缺失的对齐（验收 4） ─────────────────

  group('C 插入 / 缺失：两条串长度不同，本图不按同下标对齐', () {
    test('C1 插入：mutated 在突变点之后那段 == 原串相应片段与新碱基拼起来', () {
      final r = _run(_cases[1]);
      final p = r.position;
      final rebuilt = r.original.substring(0, p) +
          r.mutated.substring(p, p + 1) +
          r.original.substring(p);
      expect(rebuilt, r.mutated,
          reason: '插入 1 个碱基：原串 + 突变点那一位 = 突变后串');
      expect(r.mutated.substring(0, p), r.original.substring(0, p),
          reason: '突变点之前逐位一致');
      expect(r.mutated.substring(p + 1), r.original.substring(p),
          reason: '突变点之后那一段逐字等于原串从突变点起的片段（整体挪了 1 位）');
    });

    test('C2 缺失：mutated == 原串去掉突变点那一位', () {
      final r = _run(_cases[2]);
      final p = r.position;
      expect(r.original.substring(0, p) + r.original.substring(p + 1),
          r.mutated);
      expect(r.mutated.substring(0, p), r.original.substring(0, p));
      expect(r.mutated.substring(p), r.original.substring(p + 1),
          reason: '缺失点之后那一段逐字等于原串从缺失点之后起的片段（整体挪了 1 位）');
    });

    test('C3 图采用的对齐口径 == 独立参考模型（⛔ 参考模型不读本文件的函数）', () {
      for (final c in _cases) {
        final r = _run(c);
        for (var j = 0; j < r.mutated.length; j++) {
          expect(
              mutationDiffCounterpartIndex(r, j),
              referenceCounterpart(r.type, r.position, j),
              reason: '${r.type}：突变后串第 $j 位的对应下标必须与参考模型一致');
          // ⛔ 对应关系必须真的在引擎给的两条串上成立（不是空对账）。
          final cp = referenceCounterpart(r.type, r.position, j);
          if (r.type == '替换') {
            // 恒等对应：⛔ 替换那一位**本来就是不一样的碱基**，所以这里只断
            // 对应关系（见 C4），⛔ 不许拿「字符相同」当对应关系。
            expect(cp, j);
          } else if (r.type == '插入') {
            if (j == r.position) {
              expect(r.mutated[j], isNot(r.original[j]),
                  reason: '插入点那一位在原串里没有对应项');
            } else {
              expect(r.mutated[j], r.original[cp],
                  reason: '插入点之后逐位对得上偏移后的原串位置');
            }
          } else {
            expect(r.mutated[j], r.original[cp],
                reason: '缺失点之后逐位对得上偏移后的原串位置');
          }
        }
      }
    });

    test('C4 恒等映射（同下标对齐）就是错位 —— 口径函数必须与它不同', () {
      final ins = _run(_cases[1]);
      final del = _run(_cases[2]);
      // 插入：突变点之后恒等会把「插入」画成「替换」。
      expect(mutationDiffCounterpartIndex(ins, ins.position + 1),
          ins.position,
          reason: '突变后串第 position+1 位对应的是原串第 position 位');
      // 缺失：突变点之后恒等会把「缺失」画成「替换」。
      expect(mutationDiffCounterpartIndex(del, del.position),
          del.position + 1,
          reason: '突变后串第 position 位对应的是原串第 position+1 位');
      // ⛔ 替换那一路恒等是对的（等长 ⇒ 同下标确实对应）。
      final sub = _run(_cases[0]);
      for (var j = 0; j < sub.mutated.length; j++) {
        expect(mutationDiffCounterpartIndex(sub, j), j);
      }
    });

    test('C5 屏上把位移量写成数字（⛔ 不是写死的 1，是长度差）', () {
      expect(mutationDiffShiftNote(_run(_cases[0])), '',
          reason: '替换：长度没变 ⇒ 屏上不许多出位移文案');
      expect(mutationDiffShiftNote(_run(_cases[1])),
          '插入 1 个碱基：突变点之后的碱基在突变后序列里的序号都加 1');
      expect(mutationDiffShiftNote(_run(_cases[2])),
          '缺失 1 个碱基：突变点之后的碱基在突变后序列里的序号都减 1');
      // ⛔ 文案里的数字必须等于两条串的长度差（⛔ 不是写死的 1）。
      for (final c in _cases) {
        final r = _run(c);
        final delta = (r.mutated.length - r.original.length).abs();
        final note = mutationDiffShiftNote(r);
        if (delta == 0) {
          expect(note, isEmpty);
        } else {
          expect(note, contains('$delta'),
              reason: '${r.type}：位移数字必须等于长度差 $delta');
        }
      }
      // ⚠️ 本引擎一次只插 / 删 1 个碱基（`mutation_engine.dart:124-131`），
      // 所以长度差只可能是 0 / ±1，⛔ 造不出「差 2」的真实数据来断；
      // 「数字由长度差算出」这一点由上面那句 `contains('$delta')` 承担，
      // 而 `mutationDiffShiftNote` 的契约（差 0 ⇒ 空串）由上面第一句承担。
    });
  });

  // ───────────────── D 组：非法输入 ⇒ 收缩（验收 5） ─────────────────

  group('D 非法输入：组件收缩成 SizedBox.shrink，不留标题 / 图例 / 占位', () {
    Future<void> pumpDiagram(WidgetTester tester, MutatedSequence r) async {
      tester.view.physicalSize = const Size(1200, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: MutationDiffDiagram(result: r),
          ),
        ),
      ));
      await tester.pump();
    }

    void expectShrunk(WidgetTester tester) {
      expect(tester.getSize(find.byType(MutationDiffDiagram)).height, 0,
          reason: '不可画时实测高度必须是 0');
      expect(find.text(kMutationDiffMarkedLabel), findsNothing,
          reason: '⛔ 不留图例（那等于屏上宣称「这里本该有图」）');
      expect(find.text(kMutationDiffCodonRule), findsNothing);
      expect(
          find.descendant(
              of: find.byType(MutationDiffDiagram),
              matching: find.byType(CustomPaint)),
          findsNothing,
          reason: '⛔ 不留空框');
    }

    testWidgets('D1 位置越界（手工拼的）⇒ 整棵子树收缩', (tester) async {
      final bad = MutatedSequence(
        original: 'ATGCCGTA',
        mutated: 'ATGCCGTA',
        type: '替换',
        position: 99,
        codonIndex: 33,
        originalCodon: 'TAA',
        mutatedCodon: 'TAA',
        silent: true,
      );
      expect(mutationDiffIsDrawable(bad), isFalse);
      await pumpDiagram(tester, bad);
      expectShrunk(tester);
      expect(tester.takeException(), isNull);
    });

    testWidgets('D2 替换类位置等于串长 ⇒ 越界 ⇒ 收缩', (tester) async {
      final bad = MutatedSequence(
        original: 'ATGCCGTA',
        mutated: 'ATGCCGTA',
        type: '替换',
        position: 8,
        codonIndex: 2,
        originalCodon: 'GTA',
        mutatedCodon: 'GTA',
        silent: true,
      );
      expect(mutationDiffIsDrawable(bad), isFalse);
      await pumpDiagram(tester, bad);
      expectShrunk(tester);
    });

    testWidgets('D3 codon 字段与两条串不自洽（混了两次运行）⇒ 收缩', (tester) async {
      final real = _run(_cases[0]);
      final mixed = MutatedSequence(
        original: real.original,
        mutated: real.mutated,
        type: real.type,
        position: real.position,
        codonIndex: real.codonIndex,
        originalCodon: 'TTT', // ⛔ 与 original 在 codonIndex 上那 3 个碱基不符
        mutatedCodon: real.mutatedCodon,
        silent: false,
      );
      expect(mutationDiffIsDrawable(mixed), isFalse,
          reason: '字段与串对不上，画出来就是一句假话');
      await pumpDiagram(tester, mixed);
      expectShrunk(tester);
    });

    testWidgets('D4 含非 A/T/G/C ⇒ 收缩', (tester) async {
      final bad = MutatedSequence(
        original: 'ATGNCGTA',
        mutated: 'ATGNCGTA',
        type: '替换',
        position: 2,
        codonIndex: 0,
        originalCodon: 'ATG',
        mutatedCodon: 'ATG',
        silent: true,
      );
      expect(mutationDiffIsDrawable(bad), isFalse);
      await pumpDiagram(tester, bad);
      expectShrunk(tester);
    });

    testWidgets('D5 类型与长度差不自洽 ⇒ 收缩（⛔ 不做「画一半」）', (tester) async {
      final real = _run(_cases[1]); // 插入：长度 +1
      final lying = MutatedSequence(
        original: real.original,
        mutated: real.mutated,
        type: '替换', // ⛔ 说是替换，长度却多 1
        position: real.position,
        codonIndex: real.codonIndex,
        originalCodon: real.originalCodon,
        mutatedCodon: real.mutatedCodon,
        silent: false,
      );
      expect(mutationDiffIsDrawable(lying), isFalse);
      await pumpDiagram(tester, lying);
      expectShrunk(tester);
    });

    testWidgets('D6 框数超可读上限 ⇒ 收缩（80 个碱基 = 27 框 > 24）',
        (tester) async {
      final seq = List.filled(10, 'ATGCCGTA').join();
      expect(seq.length, 80, reason: '10 × 8 = 80 个碱基 ⇒ 27 个框');
      final long = mutateSequence(sequence: seq, type: 'sub', position: 2);
      expect(mutationDiffCodonCount(long.original.length), 27);
      expect(mutationDiffCodonCount(long.original.length),
          greaterThan(kMutationDiffMaxCodons));
      expect(mutationDiffIsDrawable(long), isFalse);
      await pumpDiagram(tester, long);
      expectShrunk(tester);
    });

    testWidgets('D7 合法输入 ⇒ 有 CustomPaint、图例齐全、实测高度 > 0',
        (tester) async {
      await pumpDiagram(tester, _run(_cases[0]));
      final d = find.byType(MutationDiffDiagram);
      expect(tester.getSize(d).height, greaterThan(0));
      final paint = find.descendant(
          of: d, matching: find.byType(CustomPaint));
      expect(paint, findsOneWidget);
      expect(tester.getSize(paint).width, kMutationDiffDesignWidth);
      expect(find.text(kMutationDiffMarkedLabel), findsOneWidget);
      expect(find.text(kMutationDiffChangedLabel), findsOneWidget,
          reason: '本例是替换且两个 codon 逐字不同 ⇒ 图例必须是「变了」那一句');
      expect(find.text(kMutationDiffUnchangedLabel), findsNothing,
          reason: '⛔ 不许两句话同时出现');
      expect(find.text(kMutationDiffCodonRule), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('D8 插入 / 缺失 ⇒ 位移文案上屏，替换 ⇒ 不上屏', (tester) async {
      await pumpDiagram(tester, _run(_cases[1]));
      expect(find.text(mutationDiffShiftNote(_run(_cases[1]))), findsOneWidget);
      expect(find.text(kMutationDiffChangedLabel), findsOneWidget);
      await pumpDiagram(tester, _run(_cases[0]));
      expect(find.text(mutationDiffShiftNote(_run(_cases[0]))), findsNothing,
          reason: '⛔ 替换长度没变，屏上不许出现位移文案（连空行都不许）');
    });
  });

  // ───────────────── E 组：源码级诚实守卫（验收 6） ─────────────────

  group('E 源码级：颜色只走 getter、屏上文案与诚实红线', () {
    /// 剥掉 `//` 注释（本文件的文档**正当地**提到了被禁的写法本身）。
    String codeOnly() => File(_sourcePath)
        .readAsStringSync()
        .split('\n')
        .map((l) => l.contains('//') ? l.substring(0, l.indexOf('//')) : l)
        .join('\n');

    /// 屏上真正会出现的全部文案（图例三句 + 位移说明）。
    List<String> screenCopy() => [
          kMutationDiffOriginalLabel,
          kMutationDiffMutatedLabel,
          kMutationDiffMarkedLabel,
          kMutationDiffUnchangedLabel,
          kMutationDiffChangedLabel,
          kMutationDiffCodonRule,
          for (final c in _cases) mutationDiffShiftNote(_run(c)),
        ].where((s) => s.isNotEmpty).toList();

    test('E1 颜色：无 Color(0x…) 字面量、无冻结颜色、无 Material Colors.*', () {
      final code = codeOnly();
      expect(code.contains('Color(0x'), isFalse,
          reason: '⛔ 界面里不许出现 Color(0x…) 字面量，一律走 AppColors.*');
      expect(code.contains('static final Color'), isFalse,
          reason: '⛔ AppColors.* 全是 getter，冻进 static final 会在切主题时失真');
      expect(RegExp(r'(?<![A-Za-z])Colors\.').hasMatch(code), isFalse,
          reason: '⛔ 连 Material 的 Colors.* 也不许用（不在本仓 20 个 token 内）');
      for (final t in const [
        'AppColors.canvas',
        'AppColors.surface',
        'AppColors.border',
        'AppColors.graphite',
        'AppColors.ink',
        'AppColors.teal',
        'AppColors.tealDark',
        'AppColors.tealWash',
      ]) {
        expect(code.contains(t), isTrue, reason: '必须真的用到 $t');
      }
    });

    test('E2 ⛔ AppColors.lethal 一处都不用（红 = 致死语义，与本页无关）', () {
      final code = codeOnly();
      expect(code.contains('lethal'), isFalse,
          reason: '⛔ 本页没有致死语义，lethal 不可当装饰色');
    });

    test('E3 ⛔⛔ 本轮诚实红线的牙齿：全文件不许出现氨基酸名字面量', () {
      // ⛔ 扫的是**全文件（含注释）**：诚实红线是「这个文件里不许有这些字」，
      //    写在注释里也算——注释会被人复制到别处。
      final raw = File(_sourcePath).readAsStringSync();
      const chineseAminoAcids = [
        '丙氨酸', '苯丙氨酸', '甘氨酸', '赖氨酸', '亮氨酸', '丝氨酸',
        '酪氨酸', '色氨酸', '谷氨酸', '天冬氨酸', '门冬酰胺', '谷氨酰胺',
        '精氨酸', '苏氨酸', '缬氨酸', '半胱氨酸', '甲硫氨酸', '组氨酸',
        '脯氨酸', '异亮氨酸',
      ];
      for (final a in chineseAminoAcids) {
        expect(raw.contains(a), isFalse, reason: '⛔ 全仓没有密码子表，屏上不许出现「$a」');
      }
      const threeLetter = [
        'Ala', 'Phe', 'Leu', 'Ser', 'Tyr', 'Trp', 'Arg', 'Lys', 'Asn', 'Gln',
        'Cys', 'Met', 'His', 'Ile', 'Pro', 'Val', 'Gly', 'Asp', 'Glu', 'Thr',
      ];
      for (final a in threeLetter) {
        expect(RegExp('(?<![A-Za-z])$a(?![A-Za-z])').hasMatch(raw), isFalse,
            reason: '⛔ 三字母代码「$a」同样不许出现');
      }
      // ⛔ 多肽链层面的断言也不许有（引擎只给了 silent，给不出这个结论）。
      expect(raw.contains('蛋白质'), isFalse,
          reason: '⛔ 引擎只能说「这个密码子变没变」，说不出多肽链变没变');
    });

    test('E4 屏上文案：无 markdown 标记、无方向词（一个字都不放宽）', () {
      const banned = [
        '上面', '下面', '上边', '下边', '左边', '右边', '上方', '下方',
        '上一行', '下一行', '顶部', '底部', '左列', '右列', '上面一行', '下面一行',
        '左', '右',
      ];
      for (final s in screenCopy()) {
        expect(s.contains('*'), isFalse, reason: '「$s」含 markdown 星号');
        expect(s.contains('_'), isFalse, reason: '「$s」含 markdown 下划线');
        for (final b in banned) {
          expect(s.contains(b), isFalse, reason: '「$s」含方向词「$b」');
        }
      }
      // ⛔ 剥注释后的代码里也不许有 markdown 粗体标记（本文件用 ⛔ 等字符强调）。
      expect(codeOnly().contains('**'), isFalse,
          reason: '⛔ 源码里不许出现 markdown 粗体标记');
    });

    test('E5 ⛔ 屏上文案不许出现密码子表以外的东西：只逐字读引擎字段', () {
      // 图例那一句的判据就是两个 codon 字段，⛔ 引擎没给的东西不许出现在屏上。
      for (final c in _cases) {
        final r = _run(c);
        final label = mutationDiffCodonUnchanged(r)
            ? kMutationDiffUnchangedLabel
            : kMutationDiffChangedLabel;
        expect(
            label == kMutationDiffUnchangedLabel,
            r.originalCodon == r.mutatedCodon,
            reason: '${r.type}：图例那一句必须与两个 codon 字段逐字一致');
        expect(label.contains('密码子'), isTrue,
            reason: '⛔ 只能说密码子变没变，不许越过引擎多说一层');
      }
      expect(kMutationDiffUnchangedLabel.contains('蛋白'), isFalse);
      expect(kMutationDiffChangedLabel.contains('蛋白'), isFalse);
    });
  });

  // ───────────────── F 组：深色档（验收 7） ─────────────────

  group('F 深色档：颜色随档位变，高对比仍然成立', () {
    tearDown(AppColors.debugClearOverride);

    /// WCAG 相对亮度。
    double lum(Color c) {
      double ch(double v) =>
          v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4).toDouble();
      return 0.2126 * ch(c.r) + 0.7152 * ch(c.g) + 0.0722 * ch(c.b);
    }

    double contrast(Color a, Color b) {
      final la = lum(a), lb = lum(b);
      final hi = la > lb ? la : lb, lo = la > lb ? lb : la;
      return (hi + 0.05) / (lo + 0.05);
    }

    test('F1 浅色档：受影响的粗框与画布对比度 ≥ 3（图形件底线）', () {
      AppColors.sync(Brightness.light);
      final c = contrast(AppColors.teal, AppColors.canvas);
      expect(c, greaterThanOrEqualTo(3.0),
          reason: '浅色档 teal ${AppColors.teal} on canvas ${AppColors.canvas}'
              ' 实测 $c:1');
      // 加重框里的字与它自己的底也要分得开。
      expect(contrast(AppColors.tealDark, AppColors.tealWash),
          greaterThanOrEqualTo(3.0));
    });

    test('F2 ⛔ 深色档下同一条断言也成立（验收 7）', () {
      AppColors.sync(Brightness.dark);
      final c = contrast(AppColors.teal, AppColors.canvas);
      expect(c, greaterThanOrEqualTo(3.0),
          reason: '深色档 teal ${AppColors.teal} on canvas ${AppColors.canvas}'
              ' 实测 $c:1');
      expect(contrast(AppColors.tealDark, AppColors.tealWash),
          greaterThanOrEqualTo(3.0));
      // 非颜色冗余线索不受影响：加重描边 / 加粗字 / 三角标 / 标尺四处在两档都在。
      expect(AppColors.border, isNot(AppColors.teal));
    });

    test('F3 ⛔ 颜色确实随档位变（证明没被冻住）', () {
      AppColors.sync(Brightness.light);
      final lightCanvas = AppColors.canvas;
      final lightTeal = AppColors.teal;
      AppColors.sync(Brightness.dark);
      expect(AppColors.canvas, isNot(lightCanvas),
          reason: '画布色必须随档位换，否则就是冻住了');
      expect(AppColors.teal, isNot(lightTeal));
      expect(AppColors.ink, isNot(AppColors.graphite));
    });

    testWidgets('F4 深色档下整图渲染无异常、几何不变', (tester) async {
      tester.view.physicalSize = const Size(1200, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final r = _run(_cases[1]);

      AppColors.sync(Brightness.light);
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(
              body: SingleChildScrollView(
                  child: MutationDiffDiagram(result: r)))));
      await tester.pump();
      final lightSize = tester.getSize(find.byType(MutationDiffDiagram));

      AppColors.sync(Brightness.dark);
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(
              body: SingleChildScrollView(
                  child: MutationDiffDiagram(result: r)))));
      await tester.pump();
      final darkSize = tester.getSize(find.byType(MutationDiffDiagram));

      expect(darkSize, lightSize, reason: '切档位只换颜色，不许改变版面');
      expect(darkSize.height, greaterThan(0));
      expect(find.text(kMutationDiffMarkedLabel), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  // ───────────────── H 组：版面实测数字 ─────────────────

  group('H 版面：实测宽度与高度', () {
    test('H1 设计宽度在 320 屏的可用区之内（⛔ 实测，不是估的）', () {
      // 宿主 ToolWorkbench 窄屏分支 padding = fromLTRB(16, 12, 16, 24)。
      const availableAt360 = 360.0 - 32;
      const availableAt320 = 320.0 - 32;
      expect(availableAt360, 328.0);
      expect(availableAt320, 288.0);
      expect(kMutationDiffDesignWidth, lessThanOrEqualTo(availableAt320),
          reason: '⛔ 320 宽的屏可画区只有 288，设计宽度超了就会溢出');
    });

    test('H2 一行放得下 4 个密码子 = 12 个碱基（实测值钉死）', () {
      const layout =
          MutationDiffLayout(originalCodonCount: 3, mutatedCodonCount: 3);
      expect(layout.stripWidth, 209.0);
      expect(layout.codonsPerRow, 4);
      expect(layout.codonsPerRow * 3, 12);
      expect(layout.stripLeft, 63.0);
    });

    test('H3 高度由框数算出（不是写死的单个数）', () {
      const one = MutationDiffLayout(originalCodonCount: 3, mutatedCodonCount: 3);
      const two = MutationDiffLayout(originalCodonCount: 8, mutatedCodonCount: 8);
      expect(mutationDiffTotalHeight(one), 104.0);
      expect(mutationDiffTotalHeight(two), greaterThan(mutationDiffTotalHeight(one)),
          reason: '8 框要两行 ⇒ 必须更高');
      // 换行后框位不越出画布。
      for (var i = 0; i < 8; i++) {
        final rect = two.boxRectAt(i, 0);
        expect(rect.right, lessThanOrEqualTo(kMutationDiffDesignWidth));
        expect(rect.bottom, lessThanOrEqualTo(mutationDiffTotalHeight(two)));
      }
    });
  });

  // ───────────────── G 组：页面挂载 ─────────────────

  group('G 页面：图挂在结果区的平级兄弟位置', () {
    late Directory _tmp;

    setUp(() {
      _tmp = Directory.systemTemp.createTempSync('r35_mutation_diff');
      final firstRun = '${_tmp.path}/first_run.json';
      File(firstRun).writeAsStringSync('{"role":"teacher"}', flush: true);
      FirstRunStore.debugFilePath = firstRun;
      FirstRunStore.debugWebStorage = null;
      FirstRunStore.debugForceIsWebStorage = false;
      FirstRunStore.instance.debugReset();
      MistakeBook.debugFilePath = '${_tmp.path}/mistakes.json';
      MistakeBook.debugTrashFilePath = '${_tmp.path}/mistakes.trash.json';
      MistakeBook.instance.debugReset();
    });

    tearDown(() {
      MistakeBook.debugFilePath = null;
      MistakeBook.debugTrashFilePath = null;
      MistakeBook.instance.debugReset();
      FirstRunStore.debugFilePath = null;
      FirstRunStore.debugWebStorage = null;
      FirstRunStore.debugForceIsWebStorage = false;
      FirstRunStore.instance.debugReset();
      if (_tmp.existsSync()) _tmp.deleteSync(recursive: true);
    });

    Future<void> pumpPage(WidgetTester tester) async {
      // ⛔ 1100 宽 = ToolWorkbench 的**窄屏**分支（>=1200 才走左栏 rail）。
      tester.view.physicalSize = const Size(1100, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(const MaterialApp(home: VariationPage()));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
    }

    testWidgets('G1 出厂默认（替换）算出后图在屏上，且排在「受影响密码子」之下',
        (tester) async {
      await pumpPage(tester);

      // 未算 ⇒ 图不在树里（闸门的第一条：没有结果就不画）。
      expect(find.byType(MutationDiffDiagram), findsNothing);

      await tester.tap(find.widgetWithText(FilledButton, '模拟突变'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));

      // ⛔ 前提硬断言：结果那几行真的印出来了，后面的图断言才不是无意义。
      expect(find.text('替换（位置 2）'), findsOneWidget);
      expect(find.text('ATGCCGTA'), findsWidgets);
      expect(find.textContaining('ATG → ATA'), findsOneWidget);

      final d = find.byType(MutationDiffDiagram);
      expect(d, findsOneWidget, reason: '算出结果后图必须挂上');
      expect(tester.getSize(d).height, greaterThan(0));

      // 挂点是**平级兄弟**：图排在「受影响密码子」那一行之后，不是塞进某一格里。
      final rowTop =
          tester.getTopLeft(find.textContaining('ATG → ATA').first).dy;
      final diagramTop = tester.getTopLeft(d).dy;
      expect(diagramTop, greaterThan(rowTop),
          reason: '图必须排在结果数字之下（平级兄弟）');

      // 画布宽度正好是设计宽度，⛔ 不许溢出宿主。
      final paint =
          find.descendant(of: d, matching: find.byType(CustomPaint));
      expect(tester.getSize(paint).width, kMutationDiffDesignWidth);
      expect(tester.getSize(paint).width, lessThanOrEqualTo(328.0));
      expect(tester.takeException(), isNull);
    });

    testWidgets('G2 位置越界 ⇒ 引擎抛错 ⇒ 图整棵子树都不在树上', (tester) async {
      await pumpPage(tester);
      await tester.tap(find.widgetWithText(FilledButton, '模拟突变'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.byType(MutationDiffDiagram), findsOneWidget,
          reason: '先算出一次结果（出厂值合法）');

      // ⚠️ `enterText` 不会触发 `onSubmitted` ⇒ 必须再点一次「模拟突变」。
      await tester.enterText(
          find.widgetWithText(TextField, '突变位置（0 起点，数字）'), '99');
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, '模拟突变'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));

      expect(find.text('位置越界'), findsWidgets,
          reason: '屏上必须印出引擎的原文报错');
      expect(find.byType(MutationDiffDiagram), findsNothing,
          reason: '结果被清空 ⇒ 图整棵子树都不许留在树上');
      expect(find.text(kMutationDiffMarkedLabel), findsNothing,
          reason: '⛔ 报错后不许留下图例文字');
      expect(tester.takeException(), isNull);
    });
  });
}
