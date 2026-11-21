// evolution_ctrl_s_save_test.dart —— v2.19.51 进化页 Ctrl+S 存题守卫网
//
// 网型纪律（与 molecular_ctrl_s_save_test 同源）：**取基准必须用一条与被测
// 动作不同的通道**；Ctrl+S 是写入动作，基准（页签/输入/结果）一律用
// 「鼠标点 TabBar / tap 计算按钮 / enterText」取得。
import 'dart:io';

import 'package:biology/pages/evolution_page.dart';
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

Future<void> _altDigit(WidgetTester t, LogicalKeyboardKey d) async {
  await t.sendKeyDownEvent(LogicalKeyboardKey.alt);
  await t.sendKeyEvent(d);
  await t.sendKeyUpEvent(LogicalKeyboardKey.alt);
  await t.pumpAndSettle();
}

void main() {
  late Directory tmp;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('evolution_ctrl_s');
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

  Future<void> pumpPage(WidgetTester tester) async {
    tester.view.physicalSize = const Size(800, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const MaterialApp(home: EvolutionPage()));
    await tester.pump();
  }

  // fake_async 语义：用例体内触发的写盘/AI debounce（500ms）必须在
  // **用例体内**显式取消——tearDown 跑在 body zone 之外，来不及（同 v213）。
  void cancelPendingTimers() {
    MistakeBook.instance.debugFlushSave();
    MistakeBook.instance.debugResetAiOrganize();
  }

  /// 切到「基因频率」页签（鼠标通道，异通道基线）。
  Future<void> gotoFreqTab(WidgetTester tester) async {
    await tester.tap(find.descendant(
        of: find.byType(TabBar), matching: find.text('基因频率')));
    await tester.pumpAndSettle();
  }

  testWidgets('S1·tab1 算出结果后 Ctrl+S：条目原样入库（题干/答案/考点）',
      (tester) async {
    await pumpPage(tester);
    await gotoFreqTab(tester);
    await tester.enterText(find.byType(TextField).first, '30');
    await tester.pump();
    // 失焦（不走键盘通道），让 Ctrl+S 能认领。
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump();
    await tester.tap(find.text('计算基因频率'));
    await tester.pumpAndSettle();
    expect(find.textContaining('A = 50.0%'), findsWidgets,
        reason: '前提：结果已算出（aa=30/Aa=60/AA=30 ⇒ A=50%）');

    await _ctrlS(tester);

    expect(find.textContaining('已加入错题本'), findsOneWidget,
        reason: '存入回执 SnackBar');
    final entries = MistakeBook.instance.entries;
    expect(entries, hasLength(1));
    expect(entries.single.stem, contains('aa=30'),
        reason: '题干取的是输入框现文');
    expect(entries.single.correctAnswer, contains('A=50.0%'),
        reason: '答案取的是引擎字段');
    expect(entries.single.subjectArea, '基因频率（按个体数计算）',
        reason: '考点按页签点名，不五签共用一签');
    cancelPendingTimers();
  });

  testWidgets('S2·stale-capture 闸：切页签后 Ctrl+S 存的是**新**页签的题，'
      '⛔ 不许把已切走那道写进错题本', (tester) async {
    await pumpPage(tester);
    await gotoFreqTab(tester);
    await tester.enterText(find.byType(TextField).first, '30');
    await tester.pump();
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump();
    await tester.tap(find.text('计算基因频率'));
    await tester.pumpAndSettle();
    expect(MistakeBook.instance.entries, isEmpty);

    // 键盘通道切到 tab2「遗传平衡」（未算任何东西）。
    await _altDigit(tester, LogicalKeyboardKey.digit3);
    await _ctrlS(tester);
    // 新页签未算出 ⇒ 既有守卫应答，⛔ 且库里不得出现 tab1 那道题。
    expect(find.textContaining('先算出结果'), findsOneWidget);
    expect(MistakeBook.instance.entries, isEmpty,
        reason: '⛔ 已切走页签的题不许被无声写库（B 仓 v2.19.173 真 bug 形态）');

    // 在 tab2 改 p/q 并预测，再 Ctrl+S ⇒ 入库的是 tab2 的题。
    final fP = find.widgetWithText(TextField, 'A 基因频率 p');
    expect(fP, findsOneWidget);
    await tester.ensureVisible(fP);
    await tester.pump();
    await tester.enterText(fP, '0.8');
    await tester.pump();
    final fQ = find.widgetWithText(TextField, 'a 基因频率 q');
    expect(fQ, findsOneWidget);
    await tester.ensureVisible(fQ);
    await tester.pump();
    await tester.enterText(fQ, '0.2');
    await tester.pump();
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump();
    final cta = find.text('预测下一代');
    await tester.ensureVisible(cta);
    await tester.pump();
    await tester.tap(cta);
    await tester.pumpAndSettle();
    await _ctrlS(tester);
    final entries = MistakeBook.instance.entries;
    expect(entries, hasLength(1));
    expect(entries.single.stem, contains('p=0.8'),
        reason: '入库的是**新**页签的题，不是已切走的 tab1');
    expect(entries.single.subjectArea, '遗传平衡（哈迪-温伯格预测）');
    cancelPendingTimers();
  });

  testWidgets('S3·输入焦点让路：TextField 持焦时 Ctrl+S 无声无写，失焦后必存',
      (tester) async {
    await pumpPage(tester);
    await gotoFreqTab(tester);
    await tester.enterText(find.byType(TextField).first, '30');
    await tester.pump();
    await tester.tap(find.text('计算基因频率'));
    await tester.pumpAndSettle();
    // 再聚焦输入框（持焦态）。
    await tester.tap(find.byType(TextField).first);
    await tester.pump();
    await _ctrlS(tester);
    expect(MistakeBook.instance.entries, isEmpty,
        reason: '闸③：敲到一半/持焦时不存');
    expect(find.textContaining('已加入错题本'), findsNothing);
    expect(find.textContaining('先算出结果'), findsNothing,
        reason: '让路 = 无声，连守卫 SnackBar 也不弹');
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump();
    await _ctrlS(tester);
    expect(MistakeBook.instance.entries, hasLength(1),
        reason: '失焦后同一枚键必存——证明刚才确系焦点闸拦的');
    cancelPendingTimers();
  });

  testWidgets('S4·Ctrl+Alt+S 不认领（闸①修饰键精确）', (tester) async {
    await pumpPage(tester);
    await gotoFreqTab(tester);
    await tester.tap(find.text('计算基因频率'));
    await tester.pumpAndSettle();
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.alt);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyS);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.alt);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    expect(MistakeBook.instance.entries, isEmpty);
  });

  testWidgets('S5·遗传平衡那节带来源回程：srcModule=evolution 且参数回填',
      (tester) async {
    await pumpPage(tester);
    await tester.tap(find.descendant(
        of: find.byType(TabBar), matching: find.text('遗传平衡')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('预测下一代'));
    await tester.pumpAndSettle();
    expect(find.textContaining('AA = 49.0%'), findsWidgets,
        reason: '前提：默认 p=0.7/q=0.3 ⇒ AA=49%');
    await _ctrlS(tester);
    final entries = MistakeBook.instance.entries;
    expect(entries, hasLength(1));
    expect(entries.single.srcModule, 'evolution',
        reason: '遗传平衡有真 target（p/q 回填 + 切 tab2）');
    expect(entries.single.srcParams?['p'], '0.7');
    expect(entries.single.srcParams?['q'], '0.3');
    cancelPendingTimers();
  });

  testWidgets('S6·无计算器页签（进化树）Ctrl+S 无声无写（闸④编造题干闸）',
      (tester) async {
    await pumpPage(tester);
    // 默认 tab0 = 进化树：纯展示，没有计算器。
    expect(find.text('生物进化树'), findsOneWidget,
        reason: '前提：tab0 进化树在屏（sidePanel 区标题）');
    await _ctrlS(tester);
    expect(MistakeBook.instance.entries, isEmpty);
    expect(find.textContaining('已加入错题本'), findsNothing);
    expect(find.textContaining('先算出结果'), findsNothing,
        reason: 'null 闸 = 无声让路，连守卫 SnackBar 也不弹');
  });

  // v2.19.53（找茬 D）：stale 快照门在进化页落地（蓝本：分子页 S6）。
  // 每个计算器节在算出那一刻存一份输入快照（_xxxSnap），Ctrl+S 时
  // 「结果存在且快照==现文」才算新鲜；改输入未重算 ⇒ 该节题干/答案
  // 全剔 ⇒ 答案空串 ⇒ 既有「先算出结果」守卫拦下。
  testWidgets('S7·stale 闸（单节全剔）：tab1 算出后改 aa 输入不重算，'
      'Ctrl+S 被「先算出结果」守卫拦下、零写入', (tester) async {
    await pumpPage(tester);
    await gotoFreqTab(tester);
    await tester.enterText(find.byType(TextField).first, '30');
    await tester.pump();
    // 失焦（不走键盘通道），让 Ctrl+S 能认领。
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump();
    await tester.tap(find.text('计算基因频率'));
    await tester.pumpAndSettle();
    expect(MistakeBook.instance.entries, isEmpty);
    // 改 aa 输入但不重算（题面与屏上结果开始自相矛盾）。
    await tester.enterText(find.byType(TextField).first, '40');
    await tester.pump();
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump();
    await _ctrlS(tester);
    expect(find.textContaining('先算出结果'), findsOneWidget,
        reason: '唯一的一节 stale ⇒ 答案空 ⇒ 既有守卫应答');
    expect(MistakeBook.instance.entries, isEmpty,
        reason: '⛔ 矛盾题（题干 aa=40 + 答案按 aa=30 算）不许入库存');
  });
}
