// ctrl_s_9331_stale_gate_test.dart —— v2.19.56 9331 四 tab 存题 stale
// 快照门守卫网（找茬 D 收尾，照 v2.19.53 分子/变异试点）。
//
// 每个计算器节在算出那一刻存一份输入快照（_diSnap/_triSnap/_monoSnap/
// _sexSnap，mono 含非文本开关 _mod——照变异页「框+开关」先例），Ctrl+S
// 时「结果存在且快照==现文」才算新鲜；改输入/拨开关未重算 ⇒ 整节剔除
// （题干/答案/srcModule/srcParams 一并走）⇒ 全节 stale 时答案空串 ⇒
// saveToMistakeBook 既有「先算出结果」守卫拦下、零写入。
//
// 网型纪律（与 molecular_ctrl_s_save_test 同源）：取基准用鼠标通道
// （点 TabBar / tap 计算按钮 / enterText），Ctrl+S 是写入动作。
import 'dart:io';

import 'package:biology/engine/cross_engine.dart' show Modification;
import 'package:biology/pages/cross_calculator_page.dart';
import 'package:biology/pages/widgets/mono_cross_widget.dart';
import 'package:biology/state/first_run_store.dart';
import 'package:biology/state/mistake_book.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _ctrlS(WidgetTester t) async {
  await t.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  await t.sendKeyEvent(LogicalKeyboardKey.keyS);
  await t.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  await t.pumpAndSettle();
}

void main() {
  late Directory tmp;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('ctrl_s_9331_stale');
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
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  Future<void> pump9331(WidgetTester tester) async {
    tester.view.physicalSize = const Size(800, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const MaterialApp(home: CrossCalculatorPage()));
    await tester.pump();
  }

  // fake_async 语义：用例体内触发的写盘/AI debounce（500ms）必须在
  // **用例体内**显式取消——tearDown 跑在 body zone 之外，来不及。
  void cancelPendingTimers() {
    MistakeBook.instance.debugFlushSave();
    MistakeBook.instance.debugResetAiOrganize();
  }

  testWidgets('S1·双基因+三对基因 stale 闸：各自算出后改亲本不重算，'
      'Ctrl+S 均被「先算出结果」拦下、零写入（各自重算后同键必存）',
      (tester) async {
    await pump9331(tester);
    // ── tab0 双基因 9331 ──
    await tester.tap(find.text('计算比例'));
    await tester.pumpAndSettle();
    expect(find.textContaining('表型比'), findsWidgets,
        reason: '前提：双基因已算出（出厂 AaBb × AaBb）');
    // 改亲本 1 但不重算（题面与屏上结果开始自相矛盾）。
    await tester.enterText(
        find.widgetWithText(TextField, '亲本 1'), 'AABb');
    await tester.pump();
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump();
    await _ctrlS(tester);
    expect(find.textContaining('先算出结果'), findsOneWidget,
        reason: '双基因节 stale ⇒ 答案空 ⇒ 既有守卫应答');
    expect(MistakeBook.instance.entries, isEmpty,
        reason: '⛔ 双基因矛盾题（题干 AABb + 答案按 AaBb 算）不许入库');
    // 重算后同键必存——证明门只拦 stale，不过度拦新鲜节。
    await tester.tap(find.text('计算比例'));
    await tester.pumpAndSettle();
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump();
    await _ctrlS(tester);
    var entries = MistakeBook.instance.entries;
    expect(entries, hasLength(1));
    expect(entries.single.stem, contains('AABb × AaBb'),
        reason: '双基因题干取输入框现文');
    expect(entries.single.srcModule, 'cross_dihybrid',
        reason: '新鲜节保留回程参数');

    // ── tab1 三对基因（鼠标通道切签，异通道基线）──
    await tester.tap(find.text('三对基因'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('计算比例'));
    await tester.pumpAndSettle();
    expect(find.textContaining('表型比'), findsWidgets,
        reason: '前提：三对基因已算出（出厂 AaBbCc × AaBbCc）');
    await tester.enterText(
        find.widgetWithText(TextField, '亲本 2'), 'aabbcc');
    await tester.pump();
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump();
    await _ctrlS(tester);
    expect(find.textContaining('先算出结果'), findsOneWidget,
        reason: '三对节 stale ⇒ 答案空 ⇒ 既有守卫应答');
    expect(MistakeBook.instance.entries, hasLength(1),
        reason: '⛔ 三对矛盾题（题干 aabbcc + 答案按 AaBbCc 算）不许入库，'
            '且不得冲掉已存的双基因条目');
    await tester.tap(find.text('计算比例'));
    await tester.pumpAndSettle();
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump();
    await _ctrlS(tester);
    entries = MistakeBook.instance.entries;
    expect(entries, hasLength(2));
    expect(entries.first.stem, contains('AaBbCc × aabbcc'),
        reason: '三对题干取输入框现文（entries 按 createdAt 倒序，新条目在首）');
    expect(entries.first.srcModule, 'cross_trihybrid',
        reason: '新鲜节保留回程参数');
    cancelPendingTimers();
  });

  testWidgets('S2·单基因 stale 闸：算出后改亲本不重算，Ctrl+S 被'
      '「先算出结果」拦下、零写入（重算后同键必存）', (tester) async {
    await pump9331(tester);
    await tester.tap(find.text('单基因杂交'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('杂交'));
    await tester.pumpAndSettle();
    expect(MistakeBook.instance.entries, isEmpty);
    await tester.enterText(find.widgetWithText(TextField, '亲本 1'), 'AA');
    await tester.pump();
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump();
    await _ctrlS(tester);
    expect(find.textContaining('先算出结果'), findsOneWidget,
        reason: '单基因节 stale ⇒ 答案空 ⇒ 既有守卫应答');
    expect(MistakeBook.instance.entries, isEmpty,
        reason: '⛔ 单基因矛盾题（题干 AA + 答案按 Aa 算）不许入库');
    await tester.tap(find.text('杂交'));
    await tester.pumpAndSettle();
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump();
    await _ctrlS(tester);
    final entries = MistakeBook.instance.entries;
    expect(entries, hasLength(1));
    expect(entries.single.stem, contains('AA × Aa'),
        reason: '单基因题干取输入框现文');
    expect(entries.single.srcModule, 'cross_mono',
        reason: '新鲜节保留回程参数');
    cancelPendingTimers();
  });

  testWidgets('S3·单基因修饰模式（开关态）：拨遗传模式即算 ⇒ Ctrl+S 存'
      '的是新模式的题；随后改亲本不重算仍被拦、零写入', (tester) async {
    await pump9331(tester);
    await tester.tap(find.text('单基因杂交'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('杂交')); // 完全显性（出厂模式）
    await tester.pumpAndSettle();
    expect(MistakeBook.instance.entries, isEmpty);
    // 拨修饰模式开关。⚠️ mono 的遗传模式 dropdown 选模式**即算**（与
    // 变异页只 setState 的 ChoiceChip 不同）——快照随 _mod 同步，存题
    // 口径跟着新模式走；_mod 入快照后，任何「模式与结果错位」都算 stale。
    await tester
        .tap(find.byType(DropdownButtonFormField<Modification>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('不完全显性'));
    await tester.pumpAndSettle();
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump();
    await _ctrlS(tester);
    var entries = MistakeBook.instance.entries;
    expect(entries, hasLength(1));
    expect(entries.single.correctAnswer, contains('表型比 2:1:1'),
        reason: '拨模式即算 ⇒ 答案按不完全显性（Aa×Aa：中间型2/显性1/隐性1，'
            '引擎按表型名排序 ⇒ 2:1:1），⛔ 不得残留完全显性的 3:1');
    expect(entries.single.srcModule, 'cross_mono',
        reason: '开关态新鲜节保留回程参数');
    // 拨过模式之后再改亲本不重算：节照样 stale。
    await tester.enterText(find.widgetWithText(TextField, '亲本 1'), 'aa');
    await tester.pump();
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump();
    await _ctrlS(tester);
    expect(find.textContaining('先算出结果'), findsOneWidget,
        reason: '改输入未重算 ⇒ 节 stale ⇒ 既有守卫应答');
    entries = MistakeBook.instance.entries;
    expect(entries, hasLength(1),
        reason: '⛔ 矛盾题（题干 aa + 答案按 Aa 算）不许入库');
    cancelPendingTimers();
  });

  testWidgets('S4·伴性 stale 闸：算出后改母本不重算，Ctrl+S 被'
      '「先算出结果」拦下、零写入（重算后同键必存）', (tester) async {
    await pump9331(tester);
    await tester.tap(find.text('伴性遗传'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('计算子代'));
    await tester.pumpAndSettle();
    expect(MistakeBook.instance.entries, isEmpty);
    await tester.enterText(
        find.widgetWithText(TextField, '母亲基因型 ♀'), 'XAXA');
    await tester.pump();
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump();
    await _ctrlS(tester);
    expect(find.textContaining('先算出结果'), findsOneWidget,
        reason: '伴性节 stale ⇒ 答案空 ⇒ 既有守卫应答');
    expect(MistakeBook.instance.entries, isEmpty,
        reason: '⛔ 伴性矛盾题（题干 XAXA + 答案按 XAXa 算）不许入库');
    await tester.tap(find.text('计算子代'));
    await tester.pumpAndSettle();
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump();
    await _ctrlS(tester);
    final entries = MistakeBook.instance.entries;
    expect(entries, hasLength(1));
    expect(entries.single.stem, contains('♀XAXA'),
        reason: '伴性题干取输入框现文');
    expect(entries.single.srcModule, 'cross_sex_linked',
        reason: '新鲜节保留回程参数');
    cancelPendingTimers();
  });

  // v2.19.57 找茬 F2：显隐性字母（_domCtrl/_recCtrl）**直接喂引擎**
  // （singleGeneCross 的 dominant/recessive 参）⇒ 必须进杂交快照。曾漏
  // 掉：改字母不重算时门比对全中、照常入库，回程重算却按新字母出另一道
  // 题的答案 ⇒ 矛盾题。
  testWidgets('S5·单基因 dom 字母进门（F2 守卫）：算出后把「显性等位基因」'
      '改 B 不重算，Ctrl+S 被「先算出结果」拦下、零写入；重算后同键必存'
      '且口径随新字母改写（3:1→1:3、屏上「显性(B)」）', (tester) async {
    await pump9331(tester);
    await tester.tap(find.text('单基因杂交'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('杂交')); // 出厂 Aa × Aa、dom=A、rec=a
    await tester.pumpAndSettle();
    expect(MistakeBook.instance.entries, isEmpty);
    // 对照组基线：出厂字母 A ⇒ Aa×Aa 完全显性 = 3:1（下面改 B 后同口径
    // 必翻成 1:3 —— 这是「dom 字母确实进了引擎」的可观测指纹）。
    expect(find.text('3:1'), findsOneWidget,
        reason: '前提：出厂字母 A 的表型数量比 3:1');
    // 只改显性字母（出厂 A → B），⛔ 不点「杂交」重算。
    final domField = find.descendant(
      of: find.byType(MonoCrossWidget),
      matching: find.widgetWithText(TextField, '显性等位基因'),
    );
    expect(domField, findsOneWidget, reason: '前提：显性字母框可定位（源码 labelText）');
    await tester.ensureVisible(domField);
    await tester.pumpAndSettle();
    await tester.enterText(domField, 'B');
    await tester.pump();
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump();
    await _ctrlS(tester);
    expect(find.textContaining('先算出结果'), findsOneWidget,
        reason: 'dom 字母已改、未重算 ⇒ 节 stale ⇒ 既有守卫应答');
    expect(MistakeBook.instance.entries, isEmpty,
        reason: '⛔ 矛盾题（答案按旧字母 A 算 + 现文 B）不许入库');
    // 重算：快照随新字母同步 ⇒ 同键必存，且答案按新字母出题。
    await tester.tap(find.text('杂交'));
    await tester.pumpAndSettle();
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump();
    await _ctrlS(tester);
    final entries = MistakeBook.instance.entries;
    expect(entries, hasLength(1));
    // ⚠️ 实测：savePayload().correctAnswer 只拼「表型比 <比数>；基因型 <明细>」，
    // ⛔ 不含表型名 ⇒ 新字母 B **不可能**出现在 correctAnswer 里（原计划
    // 「correctAnswer 含 'B'」在该格式下无解）。可观测的等价牙齿：
    // ①答案比数被新字母改写（B 不在任何基因型里 ⇒ AA 归显性(B)、Aa/aa 归
    //   隐性(a) ⇒ 3:1 翻成 1:3），②屏上表型名逐字带 B（显性(B)）。
    expect(entries.single.correctAnswer, contains('1:3'),
        reason: '新字母 B 进了引擎口径（A：3:1 → B：1:3）');
    expect(entries.single.correctAnswer, isNot(contains('3:1')),
        reason: '⛔ 不得残留旧字母 A 算出的 3:1');
    expect(find.text('显性(B)'), findsOneWidget,
        reason: '屏上表型名由 dominantPhenotype 拼出 ⇒ 逐字含新字母 B');
    expect(entries.single.srcModule, 'cross_mono',
        reason: '新鲜节保留回程参数');
    cancelPendingTimers();
  });

  // v2.19.57 找茬 F3：测交引擎只消费 p1（testcross 内部拿 '$rec$rec'
  // 当另一方，⛔ 不读 _p2Ctrl）⇒ 快照剔除 p2；否则改「亲本 2」不重算会
  // 被误拦（安全方向的过度剔除，但学生困惑）。
  testWidgets('S6·单基因测交 p2 不再误拦（F3 守卫）：改「亲本 2」不重算'
      '照常入库；反向守卫——改「亲本 1」不重算仍被拦、零新增', (tester) async {
    await pump9331(tester);
    await tester.tap(find.text('单基因杂交'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('测交(×隐性纯合)'));
    await tester.pumpAndSettle();
    expect(MistakeBook.instance.entries, isEmpty);
    // 测交出厂亲本即可；改「亲本 2」为另一个 2 字符、⛔ 不重算。
    final p2Field = find.descendant(
      of: find.byType(MonoCrossWidget),
      matching: find.widgetWithText(TextField, '亲本 2'),
    );
    expect(p2Field, findsOneWidget, reason: '前提：亲本 2 框可定位');
    await tester.ensureVisible(p2Field);
    await tester.pumpAndSettle();
    await tester.enterText(p2Field, 'AA');
    await tester.pump();
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump();
    await _ctrlS(tester);
    expect(find.textContaining('先算出结果'), findsNothing,
        reason: '⛔ 测交不消费 p2 ⇒ 不得误拦（改 p2 不该判 stale）');
    var entries = MistakeBook.instance.entries;
    expect(entries, hasLength(1),
        reason: '测交节仍新鲜 ⇒ 照常入库（改 p2 不影响答案）');
    expect(entries.single.correctAnswer, isNotEmpty,
        reason: '⛔ 入库的必须是算得出的题（答案非空）');
    expect(entries.single.srcModule, 'cross_mono',
        reason: '新鲜节保留回程参数');
    // v2.19.57 找茬 F4：测交存题必须记引擎真实的第二亲本 rec+rec（'aa'），
    // ⛔ 不许记「亲本 2」框——回程 fillFromAi 是杂交重算，记错框会复现
    // 出另一道题（入库答案与重算答案不一致）。
    expect(entries.single.stem, contains('× aa'),
        reason: '测交题干记引擎真实杂交对象（隐性纯合 aa），非未消费的 p2 框');
    expect(entries.single.srcParams?['p2'], 'aa',
        reason: '回程参数同口径：p2 = rec+rec，重算即得入库那道题');
    // 反向守卫：改「亲本 1」不重算 ⇒ 测交结果过期 ⇒ 照旧被拦。
    final p1Field = find.descendant(
      of: find.byType(MonoCrossWidget),
      matching: find.widgetWithText(TextField, '亲本 1'),
    );
    await tester.ensureVisible(p1Field);
    await tester.pumpAndSettle();
    await tester.enterText(p1Field, 'AA');
    await tester.pump();
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump();
    await _ctrlS(tester);
    expect(find.textContaining('先算出结果'), findsOneWidget,
        reason: '测交吃 p1 ⇒ 改亲本 1 未重算 ⇒ 节 stale ⇒ 既有守卫应答');
    entries = MistakeBook.instance.entries;
    expect(entries, hasLength(1),
        reason: '⛔ 矛盾题（题干 AA + 答案按 Aa 测交算）不许入库，'
            '也不得冲掉已存的测交条目');
    cancelPendingTimers();
  });
}
