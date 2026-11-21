// ════════════════════════════════════════════════════════════════
//  test/tetraploid_gamete_diagram_test.dart
//  倍性页「育种应用 · 同源四倍体配子比例」示意图的守卫测试（自参考实现移植）
// ════════════════════════════════════════════════════════════════
//
//  ## 本文件守 5 条验收判据（与主线程的验收清单逐条对应）
//
//  A 组＝判据 1：4 根棒上的字母**逐字等于** `result.genotype` 里那 4 个字母。
//  B 组＝判据 2：框数 == `result.counts.length`；框里的基因型 == key；
//    屏上份数 == `counts[key]`；所有框的份数之和 == **counts 之和**
//    （⛔ 期望值由引擎算出，不写死 6）。
//  H 组＝判据 3：输入非法 ⇒ 组件整棵子树收缩成 `SizedBox.shrink`
//    （不留标题 / 图例 / 空框 / 占位）。
//  S 组＝判据 4：源码级守卫（无颜色字面量 / 无星号 / 无方向词 / 无「西瓜」类词）。
//  D 组＝判据 5：至少一条断言在**深色档**下也成立。
//
//  ## ⛔ 本轮最要紧的一条实测：引擎的 `AAAa` 是 **3 : 3**，不是 1 : 1
//
//  `ploidy_engine.dart` 的注释写「`AAAa → AA:Aa = 1:1`」，但引擎**实际
//  吐出**的是 `{AA: 3, Aa: 3}`（6 份里的 3 份与 3 份，比值相同、**未约分**）。
//  实测（直接跑引擎，非本文件推断）：
//    AAaa → {AA: 1, Aa: 4, aa: 1}  3 key  合计 6
//    AAAa → {AA: 3, Aa: 3}          2 key  合计 6
//    Aaaa → {Aa: 3, aa: 3}          2 key  合计 6
//  ⇒ ① **框数不是恒等于 3**：2 或 3 都有，图必须跟着 `counts.length` 走；
//    ② ⛔ **不许顺手替引擎约分成 1**（B3 / A2 就是这两颗钉子）。
//
//  ## ⛔ 反假绿纪律
//
//  · A / B 组的判据**都从引擎重新跑一遍**取期望值，⛔ 不抄上表当常量。
//  · 「屏上印的份数」只认 `tetraploidDiagramShareText(plan, i)`——
//    ⛔ **painter 只准调这一个出口**（把它改坏，B1 立刻红）。
//  · H 组的收缩判据是**实测高度为 0** + 子树里没有 `CustomPaint` +
//    没有依据行，**不是**「widget 在不在」（组件本来就可以在树里而
//    渲染成 0×0）。
//  · S5 的源码断言**先剥注释**再查 `Color(0x…)`：本文件的文档里**正当地**
//    提到了那个被禁的写法（禁令本身），不剥掉就是「禁令把自己的守卫弄红」。
//    ⇒ 但「方向词 / 西瓜类词」在**屏上文案常量**上**不剥注释**地查（它们
//    是屏上文字，不是注释），且组件源码里也一个字都没有（已实测）。
//
//  ## ⛔ 本轮不录基线
//
//  本文件**没有**任何 golden 用例，**绝不**使用 `--update-goldens`。
//  像素基线由主线程录（见 test/tetraploid_gamete_golden_test.dart）。
import 'dart:io';

import 'package:biology/services/ai_client.dart';
import 'package:biology/engine/ploidy_engine.dart';
import 'package:biology/pages/ploidy_page.dart';
import 'package:biology/pages/settings_page.dart' show AiSettingsStore;
import 'package:biology/pages/widgets/tetraploid_gamete_diagram.dart';
import 'package:biology/theme.dart';
import 'package:biology/ui/ai_chat_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // ───────────────── E 组：引擎实况（锚点先断）─────────────────

  group('E 引擎实况：三输入的 counts 逐字钉死', () {
    // ── E1 出厂值 AAaa ──
    test('E1 AAaa → 3 个 key：AA:1 Aa:4 aa:1', () {
      final r = tetraploidGametes('AAaa');
      expect(r.counts.keys.toList(), ['AA', 'Aa', 'aa'],
          reason: '引擎按键排好序；图上框的顺序必须跟它一致');
      expect(r.counts['AA'], 1);
      expect(r.counts['Aa'], 4);
      expect(r.counts['aa'], 1);
    });

    // ── E2 ⛔ 本轮最要紧的一条实测：注释说 1:1，引擎给 3:3 ──
    test('E2 AAAa / Aaaa 只有 2 个 key，份数是 3 与 3（⛔ 不是 1 与 1）', () {
      final aa = tetraploidGametes('AAAa');
      expect(aa.counts.keys.toList(), ['AA', 'Aa'],
          reason: '⛔ 框数不是恒等于 3：AAAa 只有 2 种配子');
      expect(aa.counts['AA'], 3, reason: '引擎注释写 1:1，引擎实际给 3');
      expect(aa.counts['Aa'], 3);

      final aaaa = tetraploidGametes('Aaaa');
      expect(aaaa.counts.keys.toList(), ['Aa', 'aa']);
      expect(aaaa.counts['Aa'], 3);
      expect(aaaa.counts['aa'], 3);
    });

    // ── E3 份数之和恒为 6，但判据写成「counts 之和」而不是写死 6 ──
    test('E3 三个输入的 counts 之和都等于 6（引擎侧的事实）', () {
      for (final g in const ['AAaa', 'AAAa', 'Aaaa']) {
        final r = tetraploidGametes(g);
        final sum = r.counts.values.fold<int>(0, (a, b) => a + b);
        expect(sum, 6, reason: '$g：C(4,2)=6 种等概率组合');
      }
    });

    // ── E4 非法输入：引擎抛 ArgumentError（组件的闸门据此而设）──
    test('E4 非法输入逐条抛 ArgumentError', () {
      expect(() => tetraploidGametes('AAa'), throwsArgumentError,
          reason: '4 字母不足');
      expect(() => tetraploidGametes('AAaaaa'), throwsArgumentError);
      expect(() => tetraploidGametes('AaBb'), throwsArgumentError,
          reason: '4 个字母不是同一基因');
      expect(() => tetraploidGametes('ABCD'), throwsArgumentError);
    });
  });

  // ───────────────── A 组：验收判据 1（4 根棒的字母）─────────────────

  group('A 判据 1：棒上字母逐字 == genotype 里那 4 个字母', () {
    test('A1 三输入：棒上字母 == genotype 的字母（不排序、不去重）', () {
      for (final g in const ['AAaa', 'AAAa', 'Aaaa']) {
        final r = tetraploidGametes(g);
        final plan = tetraploidDiagramPlan(r)!;
        expect(plan.alleles, tetraploidDiagramAlleles(r.genotype),
            reason: '$g：棒的字母必须逐字取自 genotype');
        expect(plan.alleles.length, 4, reason: '$g：恒 4 根棒');
        expect(plan.allBarRects().length, 4,
            reason: '$g：画出来的棒数必须 == 4（少画一根这里就红）');
      }
    });

    // ── A2 ⛔ 反写死锚点：把 4 根棒写死成 AAaa ⇒ 这条必红 ──
    test('A2 AAAa 的棒必须读 A A A a（写死 AAaa 就是 A A a a）', () {
      final r = tetraploidGametes('AAAa');
      final plan = tetraploidDiagramPlan(r)!;
      expect(plan.alleles, ['A', 'A', 'A', 'a'],
          reason: 'AAAa 的第 3 根棒是大写 A；写死成 aa 就红');
      expect(plan.alleles.join(), isNot('AAaa'),
          reason: '⛔ 棒上不许写死 AAaa');
    });

    // ── A3 不许标基因名 / 不许画形态：屏上文案里没有这类词 ──
    test('A3 棒上只有字母本身：没有基因名 / 形态词混进文案', () {
      for (final s in const [
        kTetraAllelesLabel,
        kTetraGameteLabel,
        kTetraSharesLabel,
        kTetraBasisLabel,
      ]) {
        for (final b in const ['着丝粒', '染色体形态', '长棒', '短棒', '基因名']) {
          expect(s.contains(b), isFalse, reason: '「$s」含形态/基因名类词「$b」');
        }
      }
    });
  });

  // ───────────────── B 组：验收判据 2（框与份数）─────────────────

  group('B 判据 2：框数/基因型/份数全部由 counts 算出', () {
    // ── B1 逐框对撞：⛔ 期望值从引擎重跑，不抄表 ──
    test('B1 框数 == counts.length；框基因型 == key；屏上份数 == counts 的值', () {
      for (final g in const ['AAaa', 'AAAa', 'Aaaa']) {
        final r = tetraploidGametes(g);
        final plan = tetraploidDiagramPlan(r)!;
        expect(plan.boxes.length, r.counts.length,
            reason: '$g：框数必须由 counts.length 算出');
        for (var i = 0; i < plan.boxes.length; i++) {
          final key = r.counts.keys.elementAt(i);
          expect(plan.boxes[i].genotype, key,
              reason: '$g：第 $i 个框的字母必须逐字等于 key「$key」');
          expect(plan.boxes[i].shares, r.counts[key],
              reason: '$g：第 $i 个框的份数必须等于 counts[$key]');
          expect(tetraploidDiagramShareText(plan, i), '${r.counts[key]}',
              reason: '$g：屏上印出来的份数字符串');
        }
      }
    });

    // ── B2 份数之和 == counts 之和（⛔ 不写死 6 作期望值）──
    test('B2 所有框的份数之和 == counts 之和（期望值由引擎算出）', () {
      for (final g in const ['AAaa', 'AAAa', 'Aaaa']) {
        final r = tetraploidGametes(g);
        final plan = tetraploidDiagramPlan(r)!;
        final fromEngine = r.counts.values.fold<int>(0, (a, b) => a + b);
        final fromBoxes = plan.boxes.fold<int>(0, (a, b) => a + b.shares);
        expect(plan.totalShares, fromEngine,
            reason: '$g：和必须等于 counts 之和，不是某个写死的数');
        expect(fromBoxes, fromEngine,
            reason: '$g：框上的份数加起来必须等于引擎的份数');
      }
    });

    // ── B3 ⛔ 反写死锚点：份数差一 ⇒ 必红 ──
    test('B3 AAAa 屏上印的是 3 与 3（⛔ 差一、约成 1、或写死 1:4:1 都红）', () {
      final r = tetraploidGametes('AAAa');
      final plan = tetraploidDiagramPlan(r)!;
      final texts = <String>[
        for (var i = 0; i < plan.boxes.length; i++)
          tetraploidDiagramShareText(plan, i),
      ];
      expect(texts, ['3', '3'], reason: '引擎给 3 与 3，图必须照抄');
      expect(texts, isNot(contains('1')),
          reason: '⛔ 不许顺手替引擎约分成 1');
      expect(texts, isNot(contains('4')), reason: '⛔ 不许写死 1:4:1 的那个 4');
    });

    test('B3b AAaa 屏上印的是 1 / 4 / 1，且与引擎键序一致', () {
      final r = tetraploidGametes('AAaa');
      final plan = tetraploidDiagramPlan(r)!;
      expect(plan.boxes.map((b) => b.genotype).toList(), ['AA', 'Aa', 'aa']);
      expect(
        <String>[
          for (var i = 0; i < plan.boxes.length; i++)
            tetraploidDiagramShareText(plan, i),
        ],
        ['1', '4', '1'],
      );
    });

    // ── B4 屏上比例一个字都不许由本组件产生（比例归 RatioPill）──
    test('B4 图里没有比例串：屏上文案不含 1:4:1 / 1:1 / 百分号', () {
      for (final s in const [
        kTetraAllelesLabel,
        kTetraGameteLabel,
        kTetraSharesLabel,
        kTetraBasisLabel,
      ]) {
        expect(s.contains('%'), isFalse, reason: '「$s」含百分号');
        expect(RegExp(r'\d\s*[:：]\s*\d').hasMatch(s), isFalse,
            reason: '「$s」含比例串——比例由宿主的 RatioPill 负责');
      }
    });
  });

  // ───────────────── G 组：320 宽屏排得下吗（实量）─────────────────

  group('G 版面：320 宽的实量数字', () {
    test('G1 可用宽 296；3 框 280/3≈93.3，2 框 144.0；框越多越窄', () {
      final p3 = tetraploidDiagramPlan(tetraploidGametes('AAaa'))!;
      final p2 = tetraploidDiagramPlan(tetraploidGametes('AAAa'))!;
      expect(p3.boxes.length, 3);
      expect(p2.boxes.length, 2);
      expect(p3.usableWidth, 296, reason: '320 − 2×12 边距');
      expect(p3.boxWidth, closeTo((320 - 24 - 2 * 8) / 3, 1e-9));
      expect(p2.boxWidth, closeTo((320 - 24 - 1 * 8) / 2, 1e-9));
      expect(p3.boxWidth, lessThan(p2.boxWidth),
          reason: '框宽必须由框数算出，不是写死的');
      expect(p3.boxWidth, greaterThan(kTetraDiagramMinBoxWidth));
      expect(p2.boxWidth, greaterThan(kTetraDiagramMinBoxWidth));
    });

    test('G2 4 根棒 + 全部框都落在 320 × 总高之内（⛔ 窄屏不溢出）', () {
      for (final g in const ['AAaa', 'AAAa', 'Aaaa']) {
        final plan = tetraploidDiagramPlan(tetraploidGametes(g))!;
        expect(plan.totalHeight, greaterThan(0));
        for (final r in <Rect>[...plan.allBarRects(), ...plan.allBoxRects()]) {
          expect(r.left, greaterThanOrEqualTo(0), reason: '$g 越过画布左边界');
          expect(r.right, lessThanOrEqualTo(kTetraDiagramDesignWidth + 1e-9),
              reason: '$g 越过 320 设计宽：$r');
          expect(r.bottom, lessThanOrEqualTo(plan.totalHeight + 1e-9),
              reason: '$g 越过总高：$r');
        }
        // 框与框不重叠（否则「哪个数字属于哪个框」就说不清了）。
        final boxes = plan.allBoxRects();
        for (var i = 1; i < boxes.length; i++) {
          expect(boxes[i].left,
              greaterThanOrEqualTo(boxes[i - 1].right - 1e-9),
              reason: '$g：第 $i 个框与第 ${i - 1} 个框重叠');
        }
      }
    });

    test('G3 几何跟着数据走：框数 3 vs 2、列起点个数随之变化', () {
      final p3 = tetraploidDiagramPlan(tetraploidGametes('AAaa'))!;
      final p2 = tetraploidDiagramPlan(tetraploidGametes('AAAa'))!;
      expect(p3.allBoxRects().length, 3);
      expect(p2.allBoxRects().length, 2);
      expect(p3.allBoxRects().map((r) => r.left).toSet().length, 3);
      expect(p2.allBoxRects().map((r) => r.left).toSet().length, 2);
      expect(p3.allBarRects().map((r) => r.left).toSet().length, 4,
          reason: '4 根棒的起点必须各不相同（挤在一起就红）');
    });
  });

  // ───────────────── H 组：验收判据 3（非法输入收缩）─────────────────

  group('H 判据 3：非法输入 ⇒ 整棵子树收缩成 SizedBox.shrink', () {
    Future<void> pumpDiag(WidgetTester tester, TetraploidGametes? r) async {
      tester.view.physicalSize = const Size(1200, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [TetraploidGameteDiagram(result: r)],
            ),
          ),
        ),
      ));
      await tester.pump();
    }

    testWidgets('H1 4 字母不足（AAa）⇒ 高度 0、无 CustomPaint、无依据行',
        (tester) async {
      // ⛔ 引擎对这种输入**根本不会返回结果**（E4 已钉死它抛错）；这里手工
      //    拼一个自相矛盾的结果喂进组件，是组件**自己**的第二道闸门。
      await pumpDiag(tester,
          const TetraploidGametes(genotype: 'AAa', counts: {'Aa': 3}));
      final d = find.byType(TetraploidGameteDiagram);
      expect(d, findsOneWidget, reason: '组件在树里，但它渲染成 0×0');
      expect(tester.getSize(d).height, 0, reason: '⛔ 不许留占位高度');
      expect(find.text(kTetraBasisLabel), findsNothing,
          reason: '⛔ 不许留依据行（那等于宣称「这里本该有图」）');
      expect(find.text(kTetraAllelesLabel), findsNothing);
      expect(find.text(kTetraGameteLabel), findsNothing);
      expect(
          find.descendant(
              of: d, matching: find.byType(CustomPaint)),
          findsNothing,
          reason: '⛔ 不许留空框 / 不许建 CustomPaint');
      expect(tester.takeException(), isNull);
    });

    testWidgets('H2 4 个字母不是同一基因（AaBb）⇒ 同样整体收缩',
        (tester) async {
      await pumpDiag(tester,
          const TetraploidGametes(genotype: 'AaBb', counts: {'AB': 6}));
      final d = find.byType(TetraploidGameteDiagram);
      expect(tester.getSize(d).height, 0);
      expect(find.text(kTetraBasisLabel), findsNothing);
      expect(
          find.descendant(of: d, matching: find.byType(CustomPaint)),
          findsNothing);
      expect(tetraploidDiagramPlan(const TetraploidGametes(
              genotype: 'AaBb', counts: {'AB': 6})),
          isNull,
          reason: '闸门函数本身也必须返回 null');
      expect(tester.takeException(), isNull);
    });

    testWidgets('H3 框里的基因型不在 4 根棒里（BB）⇒ 自相矛盾，不画',
        (tester) async {
      await pumpDiag(tester,
          const TetraploidGametes(genotype: 'AAaa', counts: {'BB': 6}));
      final d = find.byType(TetraploidGameteDiagram);
      expect(tester.getSize(d).height, 0,
          reason: '⛔ 图上不许出现棒上根本没有的基因');
      expect(
          find.descendant(of: d, matching: find.byType(CustomPaint)),
          findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('H4 没有结果（null）⇒ 收缩，且不留任何文字', (tester) async {
      await pumpDiag(tester, null);
      expect(tester.getSize(find.byType(TetraploidGameteDiagram)).height, 0);
      expect(find.text(kTetraBasisLabel), findsNothing);
      expect(
          find.descendant(
              of: find.byType(TetraploidGameteDiagram),
              matching: find.byType(CustomPaint)),
          findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('H5 合法 ⇒ 有 CustomPaint，实测高度 == 算出的总高',
        (tester) async {
      for (final g in const ['AAaa', 'AAAa', 'Aaaa']) {
        final r = tetraploidGametes(g);
        final plan = tetraploidDiagramPlan(r)!;
        await pumpDiag(tester, r);
        final paint = find.descendant(
            of: find.byType(TetraploidGameteDiagram),
            matching: find.byType(CustomPaint));
        expect(paint, findsOneWidget, reason: '$g：合法输入必须画得出来');
        expect(tester.getSize(paint).width, kTetraDiagramDesignWidth);
        expect(tester.getSize(paint).height, plan.totalHeight,
            reason: '$g：高度必须由版面计划算出，不是写死的数');
        expect(find.text(kTetraBasisLabel), findsOneWidget,
            reason: '$g：依据行在场');
        expect(tester.takeException(), isNull,
            reason: '$g：⛔ 320 宽下不许有 overflow 异常');
      }
    });
  });

  // ───────────────── S 组：验收判据 4（源码级 / 文案纪律）─────────────────

  group('S 判据 4：屏上文案与源码纪律', () {
    const copy = <String>[
      kTetraAllelesLabel,
      kTetraGameteLabel,
      kTetraSharesLabel,
      kTetraBasisLabel,
      '$kTetraGameteLabel · $kTetraSharesLabel',
    ];
    const banned = <String>[
      '上面', '下面', '上边', '下边', '左边', '右边', '上方', '下方',
      '上一行', '下一行', '顶部', '底部', '左列', '右列',
    ];

    test('S1 无 markdown 星号 / 下划线', () {
      for (final s in copy) {
        expect(s.contains('*'), isFalse, reason: '「$s」含 markdown 星号');
        expect(s.contains('_'), isFalse, reason: '「$s」含 markdown 下划线');
      }
    });

    test('S2 无方向词（一个字都不放宽）', () {
      for (final s in copy) {
        for (final b in banned) {
          expect(s.contains(b), isFalse, reason: '「$s」含方向词「$b」');
        }
      }
    });

    // ── S3 ⛔ 引擎给不出的词一律不许出现在屏上 ──
    test('S3 无「西瓜」「不育」「可育」等引擎给不出的字样', () {
      for (final s in copy) {
        for (final b in const ['西瓜', '不育', '可育', '高度不育', '联会', '果实']) {
          expect(s.contains(b), isFalse,
              reason: '「$s」含「$b」——引擎的 fertile 只是组数奇偶启发式'
                  '（ploidy_engine.dart），把它印成事实就是造假');
        }
      }
    });

    test('S4 依据行不许出现只在某条件下为真的说法', () {
      // 依据行只描述「软件算出了什么」⇒ 不许带条件词 / 教材结论词。
      for (final b in const ['若', '如果', '当', '可能', '约', '通常', '一般']) {
        expect(kTetraBasisLabel.contains(b), isFalse,
            reason: '依据行含条件词「$b」——屏上不许出现只在某条件下为真的说法');
      }
    });

    // ── S5 ⛔ 源码级：颜色纪律 ──
    test('S5 源码级：剥注释后无 Color(0x…) / 无 static final Color / 无裸 Colors.', () {
      // ⚠️ 这一条是**源码级**守卫：颜色取值若被冻进 `static final Color`，
      // 切深色 / 高对比时就会停在首次访问那一刻，而这类 bug 在浅色档的
      // widget 测试里**完全看不出来**（颜色一样绿）。
      final raw = File('lib/pages/widgets/tetraploid_gamete_diagram.dart')
          .readAsStringSync();
      // ⛔ 先剥掉注释：本文件的文档里**正当地**提到了 `Color(0x…)` 这个
      //    被禁的写法（禁令本身），不剥掉就是「禁令把自己的守卫弄红」。
      final code = raw
          .split('\n')
          .map((l) => l.contains('//') ? l.substring(0, l.indexOf('//')) : l)
          .join('\n');
      expect(code.contains('Color(0x'), isFalse,
          reason: '⛔ 图内不许出现 Color(0x…) 字面量，一律走 AppColors.*');
      expect(code.contains('static final Color'), isFalse,
          reason: '⛔ AppColors.* 全是 getter，冻进 static final 会在切主题时失真');
      // ⚠️ 判据必须是「**不是 App 前缀**的 Colors.」：直接 contains('Colors.')
      //    会把 `AppColors.teal` 一起判成违规。
      expect(RegExp(r'(?<![A-Za-z])Colors\.').hasMatch(code), isFalse,
          reason: '⛔ 连 Material 的 Colors.* 也不许用（不在本仓 token 体系内）');
      for (final t in const [
        'AppColors.teal',
        'AppColors.sand',
        'AppColors.surface',
        'AppColors.ink',
        'AppColors.graphite',
        'AppColors.steel',
      ]) {
        expect(code.contains(t), isTrue, reason: '必须真的用到 $t');
      }
    });

    // ── S6 ⛔ lethal 红 = 致死语义，与本页无关，一个字都不许出现 ──
    test('S6 ⛔ AppColors.lethal 一次都不许用（致死语义，当装饰色即造假）', () {
      final raw = File('lib/pages/widgets/tetraploid_gamete_diagram.dart')
          .readAsStringSync();
      final code = raw
          .split('\n')
          .map((l) => l.contains('//') ? l.substring(0, l.indexOf('//')) : l)
          .join('\n');
      expect(code.contains('AppColors.lethal'), isFalse,
          reason: '⛔ lethal = 致死/错误语义，本页没有负面状态可标');
    });

    // ── S7 源码里也不许有方向词 / 西瓜类词（不靠剥注释蒙混）──
    test('S7 整份源码（含注释）无方向词与西瓜类词', () {
      final raw = File('lib/pages/widgets/tetraploid_gamete_diagram.dart')
          .readAsStringSync();
      for (final b in const [...banned, '西瓜', '不育', '可育']) {
        expect(raw.contains(b), isFalse, reason: '源码含禁词「$b」');
      }
    });
  });

  // ───────────────── D 组：验收判据 5（深色档）─────────────────

  group('D 判据 5：深色档下断言照样成立', () {
    tearDown(AppColors.debugClearOverride);

    test('D1 深色档：取色确实换档（证明颜色是现读 getter、没被冻住）', () {
      AppColors.sync(Brightness.light);
      final lightInk = AppColors.ink;
      final lightTeal = AppColors.teal;
      final lightSand = AppColors.sand;

      AppColors.sync(Brightness.dark);
      expect(AppColors.ink, isNot(lightInk), reason: 'ink 必须换档');
      expect(AppColors.teal, isNot(lightTeal), reason: 'teal 必须换档');
      expect(AppColors.sand, isNot(lightSand), reason: 'sand 必须换档');

      // ⛔ 关键：换档后再跑一遍数据侧断言，说明「档位不影响图上的数据」。
      final r = tetraploidGametes('AAaa');
      final plan = tetraploidDiagramPlan(r)!;
      expect(plan.alleles.length, 4);
      expect(plan.boxes.length, r.counts.length);
      expect(plan.totalShares, r.counts.values.fold<int>(0, (a, b) => a + b));
      expect(tetraploidDiagramShareText(plan, 1), '4');
    });

    testWidgets('D2 深色档：widget 仍渲染出同样的 CustomPaint 高度与份数',
        (tester) async {
      AppColors.sync(Brightness.dark);
      final r = tetraploidGametes('AAAa');
      final plan = tetraploidDiagramPlan(r)!;

      tester.view.physicalSize = const Size(1200, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [TetraploidGameteDiagram(result: r)],
            ),
          ),
        ),
      ));
      await tester.pump();

      final paint = find.descendant(
          of: find.byType(TetraploidGameteDiagram),
          matching: find.byType(CustomPaint));
      expect(paint, findsOneWidget, reason: '深色档下不许整张图不画');
      expect(tester.getSize(paint).height, plan.totalHeight,
          reason: '深色档下高度与浅色档同源（几何不依赖档位）');
      expect(tester.getSize(paint).width, kTetraDiagramDesignWidth);
      expect(find.text(kTetraBasisLabel), findsOneWidget);
      // 深色档下份数仍是引擎的 3 与 3（⛔ 不许因为换档就改数）。
      for (var i = 0; i < plan.boxes.length; i++) {
        expect(tetraploidDiagramShareText(plan, i), '${r.counts.values.elementAt(i)}');
      }
      expect(tester.takeException(), isNull);
    });

    testWidgets('D3 深色档：图照样画得出来且无异常（⛔ 高对比那一维本条不覆盖）',
        (tester) async {
      // ⚠️ **测试名只写「深色」，不写「高对比」**：高对比是 `_hc` 那一维，
      // ⛔ 不动它（会写盘）；本条只钉「深色」这维，因为 `AppColors.sync`
      // 只切亮度。名实相符比名字好听重要 —— 一个叫「高对比」却只测深色的
      // 用例，会让人以为高对比已覆盖。
      AppColors.sync(Brightness.dark);
      final r = tetraploidGametes('AAaa');
      tester.view.physicalSize = const Size(1200, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: TetraploidGameteDiagram(result: r),
          ),
        ),
      ));
      await tester.pump();
      final plan = tetraploidDiagramPlan(r)!;
      expect(tester.getSize(find.byType(TetraploidGameteDiagram)).height,
          greaterThan(0));
      expect(
          find.descendant(
              of: find.byType(TetraploidGameteDiagram),
              matching: find.byType(CustomPaint)),
          findsOneWidget);
      expect(plan.boxes.length, 3);
      expect(tester.takeException(), isNull);
    });
  });

  // ───────────────── P 组：页面挂载 ─────────────────

  group('P 页面：图挂在「配子比例」那一行的兄弟位置', () {
    setUp(() {
      // ⛔ 空配置注入：「问 AI」不会碰真实网络（本仓工作台页泵法惯例）。
      AiSettingsStore.debugConfig =
          const AiConfig(baseUrl: '', apiKey: '', model: '');
      AiChatController.instance.reset();
    });

    tearDown(() {
      AiSettingsStore.debugConfig = null;
      AiChatController.instance.reset();
    });

    Future<void> mountBreeding(WidgetTester tester) async {
      // 1400 宽 = 工作台骨架的宽屏分支（≥1200 输入面板常驻左栏、整树
      // 非懒构建），3000 高保证整个输入面板都在视口内（同
      // module_fill_overwrite_guard_test 的 _pump 取法）。
      tester.view.physicalSize = const Size(1400, 3000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(const MaterialApp(home: PloidyPage()));
      await tester.pump();
      await tester.tap(find.text('育种应用'));
      await tester.pumpAndSettle();
    }

    Future<void> calc(WidgetTester tester) async {
      final btn = find.text('计算配子比例');
      expect(btn, findsOneWidget, reason: '前提：计算按钮在场上（唯一）');
      await tester.tap(btn);
      await tester.pump();
      await tester.pumpAndSettle();
    }

    testWidgets('P1 出厂 AAaa：算出后图在屏上，且排在「配子比例」那枚 pill 之下',
        (tester) async {
      await mountBreeding(tester);
      expect(find.byType(TetraploidGameteDiagram), findsNothing,
          reason: '未算 ⇒ 图不在（结果区还在占位）');

      await calc(tester);

      // ⛔ 前提硬断言：屏上那个比例此刻存在，后面的图断言才不是无意义。
      final pill = find.text('AA : Aa : aa = 1 : 4 : 1');
      expect(pill, findsOneWidget, reason: '前提：引擎的比例已印出');

      final d = find.byType(TetraploidGameteDiagram);
      expect(d, findsOneWidget, reason: '算出结果后图必须挂上');
      expect(tester.getSize(d).height, greaterThan(0));

      final r = tetraploidGametes('AAaa');
      final plan = tetraploidDiagramPlan(r)!;
      final paint = find.descendant(
          of: d, matching: find.byType(CustomPaint));
      expect(paint, findsOneWidget);
      expect(tester.getSize(paint).height, plan.totalHeight,
          reason: '图高由引擎结果算出的版面计划给出');
      expect(tester.getSize(paint).width, kTetraDiagramDesignWidth);

      // 挂点是那枚 pill 的**兄弟位置**（平级、排在它之后），不是塞进它里面。
      expect(tester.getTopLeft(d).dy, greaterThan(tester.getTopLeft(pill).dy),
          reason: '图必须排在「配子比例」那枚 pill 之下');
      expect(find.text(kTetraBasisLabel), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('P2 改成 AAAa：图上的份数跟着引擎从 1:4:1 变成 3:3',
        (tester) async {
      await mountBreeding(tester);
      final field = fieldLike('四倍体基因型');
      expect(field, findsOneWidget, reason: '前提：四倍体输入框唯一');

      await tester.enterText(field, 'AAAa');
      await tester.pump();
      // ⚠️ `enterText` **不会**触发 onSubmitted ⇒ 必须再点一次计算按钮。
      await calc(tester);

      expect(find.text('AA : Aa = 3 : 3'), findsOneWidget,
          reason: '前提：引擎对 AAAa 给的是 3 : 3（未约分）');

      final r = tetraploidGametes('AAAa');
      final plan = tetraploidDiagramPlan(r)!;
      expect(plan.boxes.length, 2, reason: '⛔ 框数跟着 counts.length 走（2 不是 3）');
      expect(tetraploidDiagramShareText(plan, 0), '3');
      expect(tetraploidDiagramShareText(plan, 1), '3');
      expect(plan.alleles, ['A', 'A', 'A', 'a'],
          reason: '⛔ 棒上不许写死 AAaa');
      expect(tester.takeException(), isNull);
    });

    testWidgets('P3 非法输入 ⇒ 引擎抛错 ⇒ 图整棵子树不在树上、无依据行',
        (tester) async {
      await mountBreeding(tester);
      await calc(tester);
      expect(find.byType(TetraploidGameteDiagram), findsOneWidget,
          reason: '前置：先算出一次结果（出厂值合法）');
      expect(find.text(kTetraBasisLabel), findsOneWidget);

      final field = fieldLike('四倍体基因型');
      expect(field, findsOneWidget);
      await tester.enterText(field, 'AaBb'); // 4 字母但不是同一基因
      await tester.pump();
      await calc(tester);

      expect(find.byType(TetraploidGameteDiagram), findsNothing,
          reason: '结果被清空 ⇒ 图整棵子树都不许留在树上');
      expect(find.text(kTetraBasisLabel), findsNothing,
          reason: '⛔ 报错后不许留下依据行（那等于屏上宣称「这里本该有图」）');
      expect(tester.takeException(), isNull);
    });

    testWidgets('P4 4 字母不足（AAa）⇒ 同样报错并清空图', (tester) async {
      await mountBreeding(tester);
      await calc(tester);
      expect(find.byType(TetraploidGameteDiagram), findsOneWidget);

      final field = fieldLike('四倍体基因型');
      expect(field, findsOneWidget);
      await tester.enterText(field, 'AAa');
      await tester.pump();
      await calc(tester);

      expect(find.byType(TetraploidGameteDiagram), findsNothing);
      expect(find.text(kTetraBasisLabel), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });
}

/// 按 `InputDecoration.labelText` 的**前缀**认输入框。
///
/// [prefix] 是 label 的稳定词头，**不是**整句照抄。保持 `startsWith`：
/// 放宽成 `contains` 会把无关字段一起拖进来 ⇒ `findsOneWidget` 变红、
/// `enterText` 抛「Too many elements」。（与本仓
/// module_fill_overwrite_guard_test.dart 里的同名 helper 同构。）
Finder fieldLike(String prefix) => find.byWidgetPredicate(
      (w) => w is TextField && (w.decoration?.labelText ?? '').startsWith(prefix),
      description: 'TextField(label 以「$prefix」开头)',
    );
