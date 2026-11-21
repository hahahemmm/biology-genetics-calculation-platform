// curriculum_coverage_gap_test.dart —— 「课标在工具上零入口」的覆盖缺口守卫
//
// ## 它守的是什么
//
// 22 条课标在 v2.19.35 之前**一条都不带参着陆**：`curriculum_page.dart` 的
// `_openTool` 只做字符串匹配 → 切导航索引 / push 一份新实例，送不到页内的
// 页签，更送不到输入框里的示范题。本轮把 22 条逐条裁定完，分账是：
//
//   · **接上 18 条**（`_shouldHaveEntry` 逐字钉 moduleId）；
//   · **仍然不给 4 条**（`_mustStayBare`，理由逐条写在下面 + 数据层注释里）。
//
// ## 两条纪律贯穿全文件
//
//   ① **宁可不给，也不给错。** 挂一个不存在的 moduleId = 学生点下去必然失败；
//      挂一个**部分**匹配的工具 = 老师点过去发现正文讲的是另一件事，而屏上
//      完全看不出来。后者比前者更坏。
//   ② **前提断言排在牙齿后面。** 「表里有这个字段」是前提，「参数真的被目标页
//      消费了」才是牙齿。前提在前 ⇒ 字段被删时守卫只是空转全绿。
//
// ## 本仓与备份仓 B 的三处**结构性**差异（不是笔误，是本仓事实）
//
//   1. **参数键以本仓各 `apply` 的真实校验器为准**，逐条在 CG5 钉死。已核对的
//      差异：`pedigree` 认 `{father, mother}`（也兼容 `p1/p2` 兜底，
//      `genetic_pedigree_page.dart:334-342`），**不是** B 以为的 `{p1, p2}`；
//      `cross_linkage` 多一个 `r`；`evolution` / `molecular` / `ploidy` 的
//      `{tab}` 分支**只切页签、不自动计算**（无 p/q、无 template 时）。
//   2. **逐枚 chip 已落地**（v2.19.36）：`_itemTile` 按 `/` 拆段逐枚渲染
//      （`curriculumToolSegments`）⇒ 3.2.3（`遗传图谱/9331`）的
//      `chipLinks` index 0/1 **都可达**：第 0 枚（`null`）走 navIndex 1
//      原通路、第 1 枚（`cross_dihybrid`）走逐枚深链（消费侧双断言见
//      `curriculum_forward_badge_test.dart` 的 B1）。**条目级
//      `linkModuleId` 仍必须为 null**（会被这一条目的所有 chip 劫持），
//      本文件 CG3 钉的就是这件事。
//   3. **反向桥是上一轮落的**（`curriculumReverseAnchors` /
//      `curriculumReverseCodeOf` / `CurriculumPage.focusCode`），本文件
//      ⛔ 不改它一个字，只钉「正向接线没有把多义 moduleId 变成单义」。
//
// ## ⛔ 本文件**没有**覆盖的（诚实记账，勿当已覆盖）
//
//   · 3.1.5 / 3.3.3 / 3.3.5 为什么**不给**（3.2.3 条目级同理）——只钉了
//     「不许有深链」，**没有**钉「将来也不许给」。
//   · v2.19.35 主线程裁定**翻案两条**（翻案记录写在数据层注释里）：
//     3.3.6 —— 总线新增 fill 的 sourceLabel 透传（consumePushSourceLabel，
//     取后即焚），push 回程横幅的「来自拍题识别」假话解堵后接上；
//     4.1.2 —— 进化理论 tab 4 有「细胞与分子」共同特征原文 + 与 4.1.1
//     并列徽章，证据强度高于 B 当初，tab 4 即落点。
//   · 变异页 / 倍性页 / 分子页 / 进化页的 `Alt+K` 不绑：全部因
//     `curriculumReverseCodeOf` 返 null（多义或无课标点名），CG9c 钉住
//     「多义页不绑」，但没有钉「将来加了课标点名就必须补绑」。
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:biology/data/curriculum_2020.dart';
import 'package:biology/pages/cross_calculator_page.dart';
import 'package:biology/pages/curriculum_page.dart';
import 'package:biology/pages/evolution_page.dart';
import 'package:biology/pages/genetic_disease_page.dart';
import 'package:biology/pages/genetic_pedigree_page.dart';
import 'package:biology/pages/variation_page.dart';
import 'package:biology/ui/module_fill.dart';

/// 全量输入框文本——「参数真的写进去了吗」只能这么判。
String _fieldsOf(WidgetTester t) => t
    .widgetList<TextField>(find.byType(TextField))
    .map((w) => w.controller?.text ?? '')
    .join(' | ');

CurriculumItem _item(String code) =>
    curriculum2020.firstWhere((e) => e.code == code); // 硬前提：code 必须存在

/// 本轮接上的条目，逐条写死它**到底**挂在哪（18 条；3.3.6/4.1.2 为
/// v2.19.35 主线程翻案补上）。
const Map<String, String> _shouldHaveEntry = <String, String>{
  '3.1.1': 'molecular',
  '3.1.2': 'molecular',
  '3.1.3': 'molecular',
  '3.1.4': 'molecular',
  '3.2.1': 'molecular',
  '3.2.2': 'pedigree',
  '3.2.4': 'cross_sex_linked',
  '3.3.1': 'gene_mutation',
  '3.3.2': 'gene_mutation',
  '3.3.4': 'cross_linkage',
  '3.3.6': 'disease_risk',
  '4.1.1': 'evolution',
  '4.1.2': 'evolution',
  '4.2.1': 'evolution',
  '4.2.2': 'evolution',
  '4.2.3': 'evolution',
  '4.2.4': 'evolution',
  '4.2.5': 'evolution',
};

/// 「宁可不给」的 4 条 + 理由（理由也进断言 message，将来改数据的人会看到）。
const Map<String, String> _mustStayBare = <String, String>{
  '3.1.5': '表观遗传：全仓没有任何计算模块（grep 表观 lib/ 只命中纯文字）',
  '3.2.3': '条目级深链会被这一条目的**每一枚** chip 劫持 ⇒ 逐枚深链走 chipLinks',
  '3.3.3': 'mutationFactors 是 const 文字表，屏上不产出任何数字',
  '3.3.5': 'chip 逐字写「组数判断」（数量），唯一可接的 target 答的是结构变异',
};

/// 参数键核对表：本仓 `apply` **实际消费**的键（⛔ 不是 B 数据里的键名）。
/// 键集合写死 ⇒ 日后谁把 `linkParams` 的键名抄错，这里立刻红。
const Map<String, Set<String>> _expectedParamKeys = <String, Set<String>>{
  '3.1.1': {'tab'},
  '3.1.2': {'tab'},
  '3.1.3': {'tab'},
  '3.1.4': {'tab'},
  '3.2.1': {'tab'},
  '3.2.2': {'father', 'mother'}, // pedigree._applyAiParams
  '3.2.4': {'p1', 'p2'}, // cross_sex_linked._applySexFill
  '3.3.1': {'sequence', 'type', 'position'}, // variation._applyGeneMutation
  '3.3.2': {'sequence', 'type', 'position'},
  '3.3.4': {'p1', 'p2', 'r'}, // cross_linkage._applyLinkFill
  '3.3.6': {'father', 'mother', 'mode'}, // genetic_disease._applyDiseaseRisk
  '4.1.1': {'tab'},
  '4.1.2': {'tab'},
  '4.2.1': {'tab'},
  '4.2.2': {'tab'},
  '4.2.3': {'tab'},
  '4.2.4': {'tab'},
  '4.2.5': {'tab'},
};

/// 各 target 页签的**出厂默认题**（牙齿守卫的锚点，出处逐条写明）。
/// 示范题与出厂值逐字相同 ⇒「示范题已写入」那条断言恒真 ⇒ 守卫成了摆设。
const Map<String, List<String>> _factoryValues = <String, List<String>>{
  // genetic_pedigree_page.dart:144-145
  'pedigree': ['AABBCC', 'aabbcc'],
  // sex_linked_tab.dart:59-60
  'cross_sex_linked': ['XAXa', 'XAY'],
  // linkage_tab.dart:38-40
  'cross_linkage': ['AB/ab', 'ab/ab', '20%'],
  // variation_page.dart 的 _kDefaultMutSequence/_kDefaultMutPosition/_kDefaultMutType
  'gene_mutation': ['ATGCCGTA', '2', '替换'],
  // genetic_disease_page.dart:47-49（father / mother）
  'disease_risk': ['XAY', 'XAXa'],
};

void main() {
  setUp(ModuleFillBus.resetForTest);

  // ══════════════════════════════════════════════════════════
  // CG0 前提：22 条一条不多一条不少
  // ══════════════════════════════════════════════════════════
  test('CG0：22 条，接上 18 + 不给 4 = 22（两份清单不许漏项/重项）', () {
    expect(curriculum2020.length, 22);
    final covered = {..._shouldHaveEntry.keys, ..._mustStayBare.keys};
    expect(covered.length, 22, reason: '两份清单加起来必须正好覆盖 22 条');
    for (final it in curriculum2020) {
      expect(covered.contains(it.code), isTrue,
          reason: '${it.code} 既不在 _shouldHaveEntry 也不在 _mustStayBare');
    }
  });

  // ══════════════════════════════════════════════════════════
  // CG1 正向桥：本轮接上的条目**都**有入口（成对律复述）
  // ══════════════════════════════════════════════════════════
  test('CG1：接上的 16 条都拿到了入口，且都带非空参数', () {
    for (final code in _shouldHaveEntry.keys) {
      final it = _item(code); // 前提：code 真实存在
      expect(it.linkModuleId, _shouldHaveEntry[code],
          reason: '$code 的入口指向写错了');
      expect(it.linkParams, isNotNull, reason: '$code 挂了 moduleId 必须带参数');
      expect(it.linkParams!.isNotEmpty, isTrue);
      for (final e in it.linkParams!.entries) {
        expect(e.value.trim(), isNotEmpty,
            reason: '$code 的 ${e.key} 是空串（apply 会当成没给）');
      }
    }
  });

  // ══════════════════════════════════════════════════════════
  // CG2 「宁可不给」回归网（逐条带理由）
  // ══════════════════════════════════════════════════════════
  test('CG2：不给的 4 条一条都不许有条目级深链', () {
    for (final entry in _mustStayBare.entries) {
      final it = _item(entry.key); // 前提
      expect(it.linkModuleId, isNull,
          reason: '${entry.key} 本轮明确不给——${entry.value}');
      expect(it.linkParams, isNull, reason: '${entry.key} 不许带参数');
    }
  });

  // ══════════════════════════════════════════════════════════
  // CG3 3.2.3 逐枚：第 0 枚**故意不带**（不许被条目级劫持）
  // ══════════════════════════════════════════════════════════
  test('CG3：3.2.3 的 chipLinks 按下标与 `/` 分段一一对齐，第 0 枚为 null', () {
    final it = _item('3.2.3');
    expect(it.linkModuleId, isNull,
        reason: '条目级深链会被这一条目的所有 chip 劫持');
    expect(it.linkParams, isNull, reason: '同上');
    final chips = it.chipLinks; // 前提
    expect(chips, isNotNull);
    expect(chips, hasLength(2));
    // 工具文本按 `/` 拆出来的段数必须与 chip 枚数一一对应，否则按下标错位。
    final segments = it.tool!
        .split(RegExp(r'[/／]'))
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
    expect(segments, hasLength(chips!.length),
        reason: 'chipLinks 按下标与 `/` 分段一一对齐，段数必须相等');
    expect(segments.first, '遗传图谱', reason: '第 0 枚 = 遗传图谱（navIndex 1 原通路）');
    expect(chips[0], isNull, reason: '⛔ 第 0 枚故意不带深链：挂了就把它拽到 9331 去');
    expect(chips[1]!.moduleId, 'cross_dihybrid');
    expect(chips[1]!.params, {'p1': 'AaBb', 'p2': 'AaBb'});
    // 牙齿（消费侧）：第 0 枚解析为「无深链」⇒ 那一枚回落原导航。
    expect(resolveCurriculumLink(it, 0), isNull,
        reason: '第 0 枚 null ⇒ 不得产生任何深链（否则把「遗传图谱」拽到 9331）');
    // 第 1 枚**已生效**（v2.19.36 逐枚渲染）：消费侧双断言见
    // `curriculum_forward_badge_test.dart` 的 B1。
    final second = resolveCurriculumLink(it, 1);
    expect(second!.moduleId, 'cross_dihybrid');
    // 越界 ⇒ 回落条目级（这里是 null）。
    expect(resolveCurriculumLink(it, 7), isNull);
  });

  // ══════════════════════════════════════════════════════════
  // CG4 逐枚回落规则的牙齿（合成条目：真实数据只用到了 3.2.3 那一档）
  // ══════════════════════════════════════════════════════════
  test('CG4：越界/元素 null ⇒ 回落条目级；空参 ⇒ 一律不采纳', () {
    const itemLevel = CurriculumItem(
      code: 'X.1',
      text: 't',
      bigIdea: '概念3',
      keyConcept: '3.1',
      heat: 0,
      tool: 'A/B',
      linkModuleId: 'molecular',
      linkParams: {'tab': '1'},
      chipLinks: [
        null,
        (moduleId: 'cross_mono', params: {'p1': 'Aa', 'p2': 'Aa'}),
      ],
    );
    // ① 元素 null ⇒ 回落条目级（不是「无深链」）。
    expect(resolveCurriculumLink(itemLevel, 0)!.moduleId, 'molecular');
    expect(resolveCurriculumLink(itemLevel, 0)!.params, {'tab': '1'});
    // ② 越界 ⇒ 回落条目级。
    expect(resolveCurriculumLink(itemLevel, 2)!.moduleId, 'molecular');
    // ③ 负下标不得抛异常，也回落条目级。
    expect(resolveCurriculumLink(itemLevel, -1)!.moduleId, 'molecular');
    // ④ 逐枚非空 ⇒ 用逐枚。
    expect(resolveCurriculumLink(itemLevel, 1)!.moduleId, 'cross_mono');
    // ⑤ ⛔ 空参数深链比不深链更糟：逐枚与条目级的空参都必须被**拒绝**。
    const emptyChip = CurriculumItem(
      code: 'X.2',
      text: 't',
      bigIdea: '概念3',
      keyConcept: '3.1',
      heat: 0,
      tool: 'A',
      linkModuleId: 'molecular',
      chipLinks: [(moduleId: 'cross_mono', params: {})],
    );
    expect(resolveCurriculumLink(emptyChip, 0), isNull);
    const blankValue = CurriculumItem(
      code: 'X.3',
      text: 't',
      bigIdea: '概念3',
      keyConcept: '3.1',
      heat: 0,
      tool: 'A',
      linkModuleId: 'molecular',
      linkParams: {'tab': '  '},
    );
    expect(resolveCurriculumLink(blankValue, 0), isNull,
        reason: 'apply 会 int.tryParse(空串) 失败 ⇒ 不得当成有效深链');
  });

  // ══════════════════════════════════════════════════════════
  // CG5 参数键核对表（本仓 apply 真正消费的键）
  // ══════════════════════════════════════════════════════════
  test('CG5：每条接线传的键集合与本仓 apply 实际消费的键**逐字相同**', () {
    for (final entry in _expectedParamKeys.entries) {
      final it = _item(entry.key);
      expect(it.linkParams!.keys.toSet(), entry.value,
          reason: '${entry.key} 的参数键与本仓 apply 的校验器不一致——'
              '多一个键 apply 不看，少一个键 apply 拒收');
    }
  });

  // ══════════════════════════════════════════════════════════
  // CG6 牙齿前置：示范题 ≠ 出厂默认题
  // ══════════════════════════════════════════════════════════
  test('CG6：带参的示范题与该页签出厂默认题**可区分**（否则守卫恒真）', () {
    for (final it in curriculum2020) {
      final lp = it.linkParams;
      if (lp == null || it.linkModuleId == null) continue;
      final factory = _factoryValues[it.linkModuleId];
      if (factory == null) continue; // 该 target 出厂态与本轮无关（如 tab 类）
      // ⚠️ 判据是「**整道题**与出厂默认题可区分」，不是「每个键都不同」——
      // 3.2.4 的 p1 保持 `XAXa` 是**教学选择**（携带者母亲 × 患病父亲，
      // 伴 X 隐性最常考的那一模型），可区分性由 p2 承担。
      expect(lp.values.any((v) => !factory.contains(v)), isTrue,
          reason: '${it.code} 的示范题 $lp 与出厂值 $factory 逐字相同 ⇒ '
              '「示范题已写入」这条断言恒真，守卫是摆设');
    }
    // 3.3.1 / 3.3.2 是**三键全换**（序列、位置、类型），单独钉一道更强的：
    for (final code in ['3.3.1', '3.3.2']) {
      final lp = _item(code).linkParams!;
      expect(lp['sequence'], isNot('ATGCCGTA'));
      expect(lp['position'], isNot('2'));
      expect(lp['type'], isNot('替换'));
      expect(lp['type'], anyOf('替换', '插入', '缺失'),
          reason: 'type 取值必须是**页内 ChoiceChip 的原文**（_typeToEngine 的键）');
    }
  });

  // ══════════════════════════════════════════════════════════
  // CG7 端到端：芯片 → fill → 参数真写进**出厂态**目标页
  // ══════════════════════════════════════════════════════════
  testWidgets('CG7a：3.2.2 ⇒ 系谱页双亲真被写成 Aa，出厂串 AABBCC 被顶掉',
      (t) async {
    await t.pumpWidget(
        const MaterialApp(home: GeneticPedigreePage()));
    await t.pumpAndSettle();
    expect(_fieldsOf(t), contains('AABBCC'),
        reason: '前提：出厂是 AABBCC / aabbcc（genetic_pedigree_page.dart:144-145）');

    ModuleFillBus.navigator = (_) {};
    final it = _item('3.2.2');
    final link = resolveCurriculumLink(it, 0)!; // 牙齿：数据确实解析出了深链
    expect(link.moduleId, 'pedigree');
    expect(ModuleFillBus.fill(link.moduleId, link.params), isTrue);
    await t.pumpAndSettle();

    expect(_fieldsOf(t), contains('Aa'), reason: '示范题必须真的写进输入框');
    expect(_fieldsOf(t), isNot(contains('AABBCC')),
        reason: '出厂串必须被顶掉 —— 否则这条断言恒真');
  });

  testWidgets('CG7b：3.3.1 ⇒ 变异页三键真被写入并真的算出突变后序列',
      (t) async {
    await t.pumpWidget(const MaterialApp(home: VariationPage()));
    await t.pumpAndSettle();
    // 前提：出厂是 ATGCCGTA / 2 / 替换。
    expect(_fieldsOf(t), contains('ATGCCGTA'));

    ModuleFillBus.navigator = (_) {};
    final link = resolveCurriculumLink(_item('3.3.1'), 0)!;
    expect(link.moduleId, 'gene_mutation');
    expect(ModuleFillBus.fill(link.moduleId, link.params), isTrue);
    await t.pumpAndSettle();

    expect(_fieldsOf(t), contains('ATGGCCAAT'), reason: '序列必须真写进输入框');
    expect(_fieldsOf(t), isNot(contains('ATGCCGTA')), reason: '出厂串必须被顶掉');
    expect(find.text('突变后序列'), findsOneWidget,
        reason: '结果区只在真的算出结果时渲染（出厂是空态）');
    expect(find.text('ATGGCCAAT'), findsWidgets,
        reason: '结果区「原序列」必须显示填进来的序列（真算过了，不是空态）');
    expect(find.textContaining('ATGAGCCAAT'), findsWidgets,
        reason: '第 3 位插入 A ⇒ 突变后序列 ATGAGCCAAT（apply 真的调了引擎）');
  });

  testWidgets('CG7c：3.3.2 ⇒ 同一枚 target 落在**另一个**突变类型（缺失）',
      (t) async {
    await t.pumpWidget(const MaterialApp(home: VariationPage()));
    await t.pumpAndSettle();

    ModuleFillBus.navigator = (_) {};
    final link = resolveCurriculumLink(_item('3.3.2'), 0)!;
    expect(ModuleFillBus.fill(link.moduleId, link.params), isTrue);
    await t.pumpAndSettle();

    expect(_fieldsOf(t), contains('ATGAGCTAA'));
    expect(_fieldsOf(t), isNot(contains('ATGCCGTA')));
    expect(find.text('突变后序列'), findsOneWidget, reason: '必须真的算出结果');
    expect(find.textContaining('缺失'), findsWidgets,
        reason: '类型必须是「缺失」⇒ apply 走 _typeToEngine 的 del 分支');
    expect(find.textContaining('ATGACTAA'), findsWidgets,
        reason: '第 4 位缺失 ⇒ 突变后序列 ATGACTAA（与 3.3.1 的插入结果不同）');
  });

  testWidgets('CG7d：3.2.4 ⇒ 伴性页真切到该页签并把父本写成 XaY（出厂 XAY）',
      (t) async {
    t.view.physicalSize = const Size(1600, 1200);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    await t.pumpWidget(const MaterialApp(home: CrossCalculatorPage()));
    await t.pumpAndSettle();
    // 前提：出厂停在双基因页签，伴性页签的输入框还没建。
    expect(_fieldsOf(t), isNot(contains('XAY')), reason: '前提：伴性页签未挂载');

    ModuleFillBus.navigator = (_) {};
    final link = resolveCurriculumLink(_item('3.2.4'), 0)!;
    expect(link.moduleId, 'cross_sex_linked');
    expect(ModuleFillBus.fill(link.moduleId, link.params), isTrue);
    await t.pumpAndSettle();

    expect(_fieldsOf(t), contains('XaY'), reason: '父本必须真被写成 XaY');
    expect(_fieldsOf(t), isNot(contains('XAY')), reason: '出厂串 XAY 必须被顶掉');
    expect(find.text('子代结果'), findsOneWidget,
        reason: '必须真的切到伴性页签并算出了结果（出厂停在双基因页签）');
  });

  testWidgets('CG7e：3.3.4 ⇒ 连锁互换页签 + 交换率真被写成 10%（出厂 20%）',
      (t) async {
    t.view.physicalSize = const Size(1600, 1200);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    await t.pumpWidget(const MaterialApp(home: CrossCalculatorPage()));
    await t.pumpAndSettle();
    expect(_fieldsOf(t), isNot(contains('20%')), reason: '前提：连锁页签未挂载');

    ModuleFillBus.navigator = (_) {};
    final link = resolveCurriculumLink(_item('3.3.4'), 0)!;
    expect(link.moduleId, 'cross_linkage');
    expect(ModuleFillBus.fill(link.moduleId, link.params), isTrue);
    await t.pumpAndSettle();

    expect(_fieldsOf(t), contains('10%'), reason: '交换率必须真被写成 10%');
    expect(_fieldsOf(t), isNot(contains('20%')), reason: '出厂串 20% 必须被顶掉');
    expect(find.text('亲本型'), findsWidgets, reason: '连锁计算真的跑了');
  });

  testWidgets('CG7f：4.1.2 ⇒ 进化页真切到「进化理论」页签（tab 4，翻案落点）',
      (t) async {
    await t.pumpWidget(const MaterialApp(home: EvolutionPage()));
    await t.pumpAndSettle();
    expect(t.widget<TabBar>(find.byType(TabBar)).controller!.index, 0,
        reason: '前提：出厂停在第 0 页签（进化树）');

    ModuleFillBus.navigator = (_) {};
    final link = resolveCurriculumLink(_item('4.1.2'), 0)!;
    expect(link.moduleId, 'evolution');
    expect(ModuleFillBus.fill(link.moduleId, link.params), isTrue);
    await t.pumpAndSettle();

    expect(t.widget<TabBar>(find.byType(TabBar)).controller!.index, 4,
        reason: '「共同特征」的落点是 tab 4「进化理论」（翻案记录见数据层注释）');
  });

  testWidgets('CG7g：3.3.6 ⇒ 遗传病页双亲真被写入 + 回程横幅写「来自课标」'
      '（⛔ 不许回落「来自拍题识别」）', (t) async {
    await t.pumpWidget(
        const MaterialApp(home: Scaffold(body: SizedBox())));
    final ctx = t.element(find.byType(Scaffold));
    ModuleFillBus.pusher = (WidgetBuilder b) {
      Navigator.of(ctx).push(MaterialPageRoute(builder: b));
    };
    final link = resolveCurriculumLink(_item('3.3.6'), 0)!;
    expect(link.moduleId, 'disease_risk');
    // disease_risk 是 App 级注册（main.dart），测试环境没有 HomeShell ⇒
    // 这里复刻生产注册（push 型 + sourceLabel 从总线取）——被测对象
    // 正是这条 pushFactory 的横幅真话链路。
    ModuleFillBus.register(ModuleFillTarget(
      moduleId: 'disease_risk',
      pageIndex: -1,
      label: '遗传病页·风险计算',
      apply: (_) => false,
      pushFactory: (_) => GeneticDiseasePage(
          sourceLabel: ModuleFillBus.consumePushSourceLabel('disease_risk') ??
              '拍题识别'),
    ));
    // v2.19.35：课标深链带 sourceLabel —— 横幅假话解堵的端到端证据。
    expect(
        ModuleFillBus.fill(link.moduleId, link.params,
            sourceLabel: '课标'),
        isTrue);
    await t.pumpAndSettle();

    expect(_fieldsOf(t), contains('XaY'), reason: '父本必须真被写成 XaY');
    expect(_fieldsOf(t), isNot(contains('XAY')),
        reason: '出厂父本 XAY 必须被顶掉（示范题≠出厂，CG6 同口径）');
    expect(find.textContaining('来自课标'), findsOneWidget,
        reason: '回程横幅必须写课标来源（总线 sourceLabel 透传生效）');
    expect(find.textContaining('来自拍题识别'), findsNothing,
        reason: '⛔ 写死来源的假话横幅一旦回归即红');
  });

  testWidgets('CG7h：push 进来的课标页点 3.3.6 chip ⇒ 遗传病页留栈顶 + '
      '横幅「来自课标」+ pending/标签零幽灵（独立验证者 P0 回归）', (t) async {
    t.view.physicalSize = const Size(1400, 5200);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    await t.pumpWidget(
        const MaterialApp(home: Scaffold(body: SizedBox())));
    final ctx = t.element(find.byType(Scaffold));
    // 模拟「课标 X」徽章的 push：无 onOpenTool 的课标页实例。⛔ 不 const。
    Navigator.of(ctx)
        .push(MaterialPageRoute(builder: (_) => CurriculumPage()));
    await t.pumpAndSettle();
    // 复刻 main.dart 的 App 级注册（被测对象含 pushFactory 的横幅真话链路）。
    ModuleFillBus.register(ModuleFillTarget(
      moduleId: 'disease_risk',
      pageIndex: -1,
      label: '遗传病页·风险计算',
      apply: (_) => false,
      pushFactory: (_) => GeneticDiseasePage(
          sourceLabel: ModuleFillBus.consumePushSourceLabel('disease_risk') ??
              '拍题识别'),
    ));
    ModuleFillBus.pusher = (WidgetBuilder b) {
      Navigator.of(ctx).push(MaterialPageRoute(builder: b));
    };
    // 展开概念 3.3 并点 3.3.6 的 chip（超高视口全构建，同 lightwhite 用例）。
    await t.tap(find.text('可遗传的变异（突变/重组/染色体变异）'));
    await t.pumpAndSettle();
    await t.tap(find.textContaining('遗传病速查'));
    await t.pumpAndSettle();

    expect(find.textContaining('来自课标'), findsOneWidget,
        reason: 'push 型深链的目标页必须留在栈顶（被 popUntil 弹掉即红）');
    expect(find.textContaining('XaY'), findsWidgets,
        reason: '示范题父本真写进遗传病页输入框');
    expect(find.byType(CurriculumPage), findsNothing,
        reason: '课标页（无 onOpenTool 的 push 实例）让位于目标页');
    expect(ModuleFillBus.consumePending('disease_risk'), isNull,
        reason: '⛔ 幽灵 params 回归即红');
    expect(ModuleFillBus.consumePushSourceLabel('disease_risk'), isNull,
        reason: '⛔ 幽灵来源标签回归即红（下次拍题横幅会说「来自课标」）');
  });

  // ══════════════════════════════════════════════════════════
  // CG8 芯片 → fill 的接线（数据真被消费侧读到）
  // ══════════════════════════════════════════════════════════
  testWidgets('CG8：点 3.1.3 的芯片 ⇒ fill 收到 molecular + {tab:1}',
      (t) async {
    t.view.physicalSize = const Size(1400, 1200);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    // 假 target：只记参数，不真路由（守卫只管「数据有没有到消费侧」）。
    final got = <String, Map<String, String>>{};
    ModuleFillBus.register(ModuleFillTarget(
      moduleId: 'molecular',
      pageIndex: 5,
      label: '假分子页',
      apply: (params) {
        got['molecular'] = Map.of(params);
        return true;
      },
    ));
    ModuleFillBus.navigator = (_) {};
    await t.pumpWidget(const MaterialApp(home: CurriculumPage()));
    await t.pumpAndSettle();

    final chip = find.text('工具：DNA复制计算器 →');
    expect(chip, findsOneWidget, reason: '3.1.3 的芯片应可见（默认选中 3.1）');
    await t.tap(chip);
    await t.pumpAndSettle();

    expect(got['molecular'], {'tab': '1'},
        reason: '芯片必须把数据层的 moduleId + params 原样交给 ModuleFillBus');
  });

  // ══════════════════════════════════════════════════════════
  // CG9 Alt+K：只认领「唯一反查得到 code」的那一栏
  // ══════════════════════════════════════════════════════════
  testWidgets('CG9a：9331 页 Alt+K ⇒ 跳课标页并高亮 focusCode 指的那一条',
      (t) async {
    t.view.physicalSize = const Size(1600, 1200);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    await t.pumpWidget(const MaterialApp(home: CrossCalculatorPage()));
    await t.pumpAndSettle();
    // 前提：双基因页签 = cross_dihybrid ⇒ 唯一反查 3.2.3。
    expect(curriculumReverseCodeOf('cross_dihybrid'), '3.2.3');

    await _altK(t);
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('curriculum-item-3.2.3')), findsOneWidget,
        reason: 'push 出去的课标页必须高亮 focusCode 指的那**一条**');
    expect(find.text('正在查看'), findsOneWidget);

    // 退回工具页，换到伴性页签 ⇒ code 必须跟着换（3.2.4），且是**新**的一份实例。
    t.state<NavigatorState>(find.byType(Navigator).first).pop();
    await t.pumpAndSettle();
    await t.tap(find.text('伴性遗传'));
    await t.pumpAndSettle();
    await _altK(t);
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('curriculum-item-3.2.4')), findsOneWidget,
        reason: 'code 必须按按下那一刻的页签现算，否则跳的是旧那一栏的课标');
    expect(find.byKey(const ValueKey('curriculum-item-3.2.3')), findsNothing,
        reason: '⛔ 伴性页签不许再认领 3.2.3（双基因那一栏的 code）');
  });

  testWidgets('CG9b：遗传病页「遗传咨询」栏 Alt+K ⇒ 高亮 3.3.6', (t) async {
    t.view.physicalSize = const Size(1600, 1200);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    await t.pumpWidget(const MaterialApp(home: GeneticDiseasePage()));
    await t.pumpAndSettle();
    expect(curriculumReverseCodeOf('disease_risk'), '3.3.6');

    await _altK(t);
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('curriculum-item-3.3.6')), findsOneWidget);
  });

  testWidgets('CG9c：⛔ 多义/未点名的栏**不绑** Alt+K（变异页整页不认领）',
      (t) async {
    t.view.physicalSize = const Size(1600, 1200);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    // 前提：变异页可反查的两枚 moduleId 都是多义（本轮把 3.3.1/3.3.2 都
    // 指到了 gene_mutation ⇒ 更必须返 null）。
    expect(curriculumReverseCodeOf('gene_mutation'), isNull);
    expect(curriculumReverseCodeOf('cross_chromosomal_struct'), isNull);
    await t.pumpWidget(const MaterialApp(home: VariationPage()));
    await t.pumpAndSettle();

    await _altK(t);
    await t.pumpAndSettle();
    expect(find.byType(CurriculumPage), findsNothing,
        reason: '多义页不认领 Alt+K——挑一条挂上就是编造对应关系');
  });

  testWidgets('CG9d：⛔ 在输入框里打字时 Alt+K 让路（不跳页、不打断输入）',
      (t) async {
    t.view.physicalSize = const Size(1600, 1200);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    await t.pumpWidget(const MaterialApp(home: GeneticDiseasePage()));
    await t.pumpAndSettle();
    await t.tap(find.byType(TextField).first);
    await t.pumpAndSettle();

    await _altK(t);
    await t.pumpAndSettle();
    expect(find.byType(CurriculumPage), findsNothing,
        reason: '学生正在敲基因型时按 Alt+K 什么也不该发生');
  });

  // ══════════════════════════════════════════════════════════
  // CG10 零像素变化的凭据：22 条 chip 文本逐字未变
  // ══════════════════════════════════════════════════════════
  test('CG10：22 条的 tool 文本逐字未变（本簇对既有屏零像素变化）', () {
    const snapshot = <String, String>{
      '3.1.1': '中心法则页·基因概念卡',
      '3.1.2': 'DNA计算器',
      '3.1.3': 'DNA复制计算器',
      '3.1.4': '转录翻译计算器',
      '3.1.5': '课标体系页·概念卡',
      '3.2.1': '减数分裂配子种类计算',
      '3.2.2': '遗传图谱',
      '3.2.3': '遗传图谱/9331',
      '3.2.4': '伴性遗传',
      '3.3.1': '变异页·基因突变模拟',
      '3.3.2': '变异页·缺失位点',
      '3.3.3': '变异页·诱变因素卡',
      '3.3.4': '连锁互换 + 9331',
      '3.3.5': '变异页·染色体组数判断',
      '3.3.6': '遗传病速查 + 图谱概率',
      '4.1.1': '进化页·证据速览',
      '4.1.2': '进化页·共同特征卡',
      '4.2.1': '基因频率计算器',
      '4.2.2': '基因频率计算器',
      '4.2.3': '基因频率计算器',
      '4.2.4': '进化页·理论脉络',
      '4.2.5': '进化页·物种形成三步',
    };
    for (final it in curriculum2020) {
      expect(it.tool, snapshot[it.code],
          reason: '${it.code} 的芯片文本被改了 ⇒ 既有屏有像素变化');
    }
  });
}

/// Alt+K 一次（按住 alt 再敲 K）。
Future<void> _altK(WidgetTester t) async {
  await t.sendKeyDownEvent(LogicalKeyboardKey.alt);
  await t.sendKeyEvent(LogicalKeyboardKey.keyK);
  await t.sendKeyUpEvent(LogicalKeyboardKey.alt);
  await t.pumpAndSettle();
}
