// molecular_ctrl_s_save_test.dart —— v2.19.51 分子页 Ctrl+S 存题守卫网
//
// 网型纪律（与 tab_jump_shortcuts_test 同源）：**取基准必须用一条与被测
// 动作不同的通道**；Ctrl+S 是写入动作，基准（页签/输入/结果）一律用
// 「鼠标点 TabBar / tap 计算按钮 / enterText」取得。
import 'dart:io';

import 'package:biology/pages/molecular_page.dart';
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
    tmp = Directory.systemTemp.createTempSync('molecular_ctrl_s');
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
    await tester.pumpWidget(const MaterialApp(home: MolecularPage()));
    await tester.pump();
  }

  // fake_async 语义：用例体内触发的写盘/AI debounce（500ms）必须在
  // **用例体内**显式取消——tearDown 跑在 body zone 之外，来不及（同 v213）。
  void cancelPendingTimers() {
    MistakeBook.instance.debugFlushSave();
    MistakeBook.instance.debugResetAiOrganize();
  }

  /// 切到「复制与标记」页签（鼠标通道，异通道基线）。
  Future<void> gotoReplicationTab(WidgetTester tester) async {
    await tester.tap(find.descendant(
        of: find.byType(TabBar), matching: find.text('复制与标记')));
    await tester.pumpAndSettle();
  }

  testWidgets('S1·tab0 算出结果后 Ctrl+S：条目原样入库（题干/答案/考点）',
      (tester) async {
    await pumpPage(tester);
    await tester.enterText(find.byType(TextField).first, '30');
    await tester.pump();
    // 失焦（不走键盘通道），让 Ctrl+S 能认领。
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump();
    await tester.tap(find.text('计算碱基组成'));
    await tester.pumpAndSettle();
    expect(find.textContaining('T=30.0%'), findsWidgets,
        reason: '前提：结果已算出（A=30 ⇒ T=30）');

    await _ctrlS(tester);

    expect(find.textContaining('已加入错题本'), findsOneWidget,
        reason: '存入回执 SnackBar');
    final entries = MistakeBook.instance.entries;
    expect(entries, hasLength(1));
    expect(entries.single.stem, contains('A 占 30%'),
        reason: '题干取的是输入框现文');
    expect(entries.single.correctAnswer, contains('T=30.0%'),
        reason: '答案取的是引擎字段');
    expect(entries.single.subjectArea, '碱基组成（DNA 碱基互补）',
        reason: '考点按页签点名，不四签共用一签');
    cancelPendingTimers();
  });

  testWidgets('S2·stale-capture 闸：切页签后 Ctrl+S 存的是**新**页签的题，'
      '⛔ 不许把已切走那道写进错题本', (tester) async {
    await pumpPage(tester);
    await tester.enterText(find.byType(TextField).first, '30');
    await tester.pump();
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump();
    await tester.tap(find.text('计算碱基组成'));
    await tester.pumpAndSettle();
    expect(MistakeBook.instance.entries, isEmpty);

    // 键盘通道切到 tab1（未算任何东西）。
    await _altDigit(tester, LogicalKeyboardKey.digit2);
    await _ctrlS(tester);
    // 新页签未算出 ⇒ 既有守卫应答，⛔ 且库里不得出现 tab0 那道题。
    expect(find.textContaining('先算出结果'), findsOneWidget);
    expect(MistakeBook.instance.entries, isEmpty,
        reason: '⛔ 已切走页签的题不许被无声写库（B 仓 v2.19.173 真 bug 形态）');

    // 在 tab1 算出标记分布，再 Ctrl+S ⇒ 入库的是 tab1 的题。
    final fN = find.widgetWithText(TextField, '复制代数 n（标记分布用）');
    expect(fN, findsOneWidget);
    await tester.ensureVisible(fN);
    await tester.pump();
    await tester.enterText(fN, '3');
    await tester.pump();
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump();
    final cta = find.text('计算标记分布');
    await tester.ensureVisible(cta);
    await tester.pump();
    await tester.tap(cta);
    await tester.pumpAndSettle();
    await _ctrlS(tester);
    final entries = MistakeBook.instance.entries;
    expect(entries, hasLength(1));
    expect(entries.single.stem, contains('标记 DNA 移入无标记培养基复制 3 代'));
    expect(entries.single.subjectArea, '复制与标记（半保留复制与密度梯度）');
    cancelPendingTimers();
  });

  testWidgets('S3·输入焦点让路：TextField 持焦时 Ctrl+S 无声无写，失焦后必存',
      (tester) async {
    await pumpPage(tester);
    await tester.enterText(find.byType(TextField).first, '30');
    await tester.pump();
    await tester.tap(find.text('计算碱基组成'));
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
    await tester.tap(find.text('计算碱基组成'));
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

  testWidgets('S6·stale 闸（单节全剔）：算出后改输入不重算，Ctrl+S 被'
      '「先算出结果」守卫拦下、零写入', (tester) async {
    await pumpPage(tester);
    await tester.enterText(find.byType(TextField).first, '30');
    await tester.pump();
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump();
    await tester.tap(find.text('计算碱基组成'));
    await tester.pumpAndSettle();
    expect(MistakeBook.instance.entries, isEmpty);
    // 改输入但不重算（题面与屏上结果开始自相矛盾）。
    await tester.enterText(find.byType(TextField).first, '40');
    await tester.pump();
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump();
    await _ctrlS(tester);
    expect(find.textContaining('先算出结果'), findsOneWidget,
        reason: '唯一的一节 stale ⇒ 答案空 ⇒ 既有守卫应答');
    expect(MistakeBook.instance.entries, isEmpty,
        reason: '⛔ 矛盾题（题干 40% + 答案按 30% 算）不许入库存');
  });

  testWidgets('S7·stale 闸（多节外科手术）：两节都算出后只改其中一节输入，'
      'Ctrl+S 存的是剔掉 stale 节后仍自洽的那道', (tester) async {
    await pumpPage(tester);
    await gotoReplicationTab(tester);
    // 节 A：复制结果（rep=3 默认）。
    await tester.tap(find.text('计算复制结果'));
    await tester.pumpAndSettle();
    // 节 B：标记分布（n=3 默认）。
    final cta = find.text('计算标记分布');
    await tester.ensureVisible(cta);
    await tester.pump();
    await tester.tap(cta);
    await tester.pumpAndSettle();
    expect(MistakeBook.instance.entries, isEmpty);
    // 只改「复制次数」不重算 ⇒ 节 A stale，节 B 仍新鲜。
    final fRep = find.widgetWithText(TextField, '复制次数 n');
    expect(fRep, findsOneWidget);
    await tester.ensureVisible(fRep);
    await tester.pump();
    await tester.enterText(fRep, '5');
    await tester.pump();
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump();
    await _ctrlS(tester);
    final entries = MistakeBook.instance.entries;
    expect(entries, hasLength(1),
        reason: '节 B 自洽可存，整道不被拦');
    expect(entries.single.stem, isNot(contains('新合成链数')),
        reason: '⛔ stale 节（复制）从题干剔除（「复制 3 代」字样属新鲜节，不算）');
    expect(entries.single.stem, contains('标记 DNA'),
        reason: '新鲜节（标记分布）保留');
    expect(entries.single.correctAnswer, isNot(contains('含亲代链')),
        reason: '⛔ stale 节的答案一并剔除（题干推不出）');
    expect(entries.single.correctAnswer, contains('总分子'),
        reason: '新鲜节的答案保留');
    cancelPendingTimers();
  });

  testWidgets('S5·中心法则那节带来源回程：srcModule=molecular 且参数回填',
      (tester) async {
    await pumpPage(tester);
    await tester.tap(find.descendant(
        of: find.byType(TabBar), matching: find.text('基因表达')));
    await tester.pumpAndSettle();
    final fD = find.widgetWithText(TextField, '模板链序列（如 TACGGATTA）');
    expect(fD, findsOneWidget, reason: '前提：中心法则输入框在树');
    await tester.ensureVisible(fD);
    await tester.pump();
    await tester.enterText(fD, 'TACGGATTA');
    await tester.pump();
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump();
    await tester.tap(find.text('推出各链'));
    await tester.pumpAndSettle();
    await _ctrlS(tester);
    final entries = MistakeBook.instance.entries;
    expect(entries, hasLength(1));
    expect(entries.single.srcModule, 'molecular',
        reason: '中心法则有真 target（template 回填 + 切 tab2）');
    expect(entries.single.srcParams?['template'], 'TACGGATTA');
    cancelPendingTimers();
  });
}
