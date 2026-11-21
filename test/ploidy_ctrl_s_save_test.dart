// ploidy_ctrl_s_save_test.dart —— v2.19.51 倍性页 Ctrl+S 存题守卫网
//
// 网型纪律（与 molecular/evolution ctrl_s_save_test 同源）：**取基准必须
// 用一条与被测动作不同的通道**；Ctrl+S 是写入动作，基准（页签/输入/结果）
// 一律用「鼠标点 TabBar / tap 计算按钮 / enterText / Alt+数字」取得。
//
// 本页 3 个页签（组数判断 / 倍性与育性 / 育种应用）全部有计算器 ⇒ 无
// evolution 页那种「无计算器页签返 null」的 S6 用例；「未算出结果」的空
// 答案守卫由 S2 第一阶段钉住。
import 'dart:io';

import 'package:biology/pages/ploidy_page.dart';
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
    tmp = Directory.systemTemp.createTempSync('ploidy_ctrl_s');
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
    await tester.pumpWidget(const MaterialApp(home: PloidyPage()));
    await tester.pump();
  }

  // fake_async 语义：用例体内触发的写盘/AI debounce（500ms）必须在
  // **用例体内**显式取消——tearDown 跑在 body zone 之外，来不及（同 v213）。
  void cancelPendingTimers() {
    MistakeBook.instance.debugFlushSave();
    MistakeBook.instance.debugResetAiOrganize();
  }

  Future<void> enterTotal(WidgetTester tester, String v) async {
    final f = find.widgetWithText(TextField, '染色体总条数');
    expect(f, findsOneWidget);
    await tester.ensureVisible(f);
    await tester.pump();
    await tester.enterText(f, v);
    await tester.pump();
  }

  Future<void> tapCalc(WidgetTester tester, String label) async {
    final b = find.text(label);
    expect(b, findsOneWidget, reason: '前提：按钮 $label 在屏');
    await tester.ensureVisible(b);
    await tester.pump();
    await tester.tap(b);
    await tester.pumpAndSettle();
  }

  testWidgets('S1·tab0 两节算出后 Ctrl+S：条目原样入库（题干/答案/考点）',
      (tester) async {
    await pumpPage(tester);
    await enterTotal(tester, '16'); // 形态法 16÷4=4 组（默认 8→改为 16 验现文）
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump();
    await tapCalc(tester, '计算组数');
    await tapCalc(tester, '按基因型判断');
    expect(find.text('A×3　B×3'), findsOneWidget,
        reason: '前提：基因型法默认 AaaBBb ⇒ A×3/B×3、3 组');

    await _ctrlS(tester);

    expect(find.textContaining('已加入错题本'), findsOneWidget,
        reason: '存入回执 SnackBar');
    final entries = MistakeBook.instance.entries;
    expect(entries, hasLength(1));
    expect(entries.single.stem, contains('染色体总条数 16'),
        reason: '题干取的是输入框现文（16 是学生刚敲的，非出厂 8）');
    expect(entries.single.stem, contains('基因型 AaaBBb'),
        reason: '题干覆盖已算出两节：形态法 + 基因型法');
    expect(entries.single.correctAnswer, contains('组数 4 个'),
        reason: '答案取引擎字段：16÷4=4 组（SetsByMorphology.sets）');
    expect(entries.single.correctAnswer, contains('组数 3 个'),
        reason: '答案取引擎字段：AaaBBb ⇒ 3 组（SetsByGenotype.sets）');
    expect(entries.single.subjectArea, '染色体组数判断（形态法与基因型法）',
        reason: '考点按页签点名，不三签共用一签');
    cancelPendingTimers();
  });

  testWidgets('S2·stale-capture 闸：切页签后 Ctrl+S 存的是**新**页签的题，'
      '⛔ 不许把已切走那道写进错题本', (tester) async {
    await pumpPage(tester);
    await tapCalc(tester, '计算组数'); // tab0 形态法（默认 8÷4=2 组）算出
    expect(MistakeBook.instance.entries, isEmpty);

    // 键盘通道切到 tab1「倍性与育性」（未算任何东西）。
    await _altDigit(tester, LogicalKeyboardKey.digit2);
    await _ctrlS(tester);
    // 新页签未算出 ⇒ 既有守卫应答（本页三签全有计算器，payload 永不 null，
    // 由空答案守卫拦）；⛔ 且库里不得出现 tab0 那道题。
    expect(find.textContaining('先算出结果'), findsOneWidget);
    expect(MistakeBook.instance.entries, isEmpty,
        reason: '⛔ 已切走页签的题不许被无声写库（B 仓 v2.19.173 真 bug 形态）');

    // 在 tab1 判定倍性（默认组数 3、受精卵发育），再 Ctrl+S ⇒ 入库 tab1 的题。
    await tapCalc(tester, '判定倍性');
    expect(find.textContaining('三倍体（不育）'), findsWidgets,
        reason: '前提：默认 3 组 + 受精卵发育 ⇒ 三倍体（不育）');
    await _ctrlS(tester);
    final entries = MistakeBook.instance.entries;
    expect(entries, hasLength(1));
    expect(entries.single.stem, contains('受精卵发育'),
        reason: '入库的是**新**页签的题，不是已切走的 tab0');
    expect(entries.single.stem, isNot(contains('形态种数')),
        reason: '⛔ 题干里不许残留已切走 tab0 的输入');
    expect(entries.single.subjectArea, '倍性判定与育性（三倍体无子西瓜）');
    expect(entries.single.correctAnswer, contains('三倍体'));
    expect(entries.single.correctAnswer, contains('不育'));
    cancelPendingTimers();
  });

  testWidgets('S3·输入焦点让路：TextField 持焦时 Ctrl+S 无声无写，失焦后必存',
      (tester) async {
    await pumpPage(tester);
    await tapCalc(tester, '计算组数');
    // 再聚焦输入框（持焦态）。
    final f = find.widgetWithText(TextField, '染色体总条数');
    expect(f, findsOneWidget);
    await tester.ensureVisible(f);
    await tester.pump();
    await tester.tap(f);
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
    await tapCalc(tester, '计算组数');
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

  testWidgets('S5·srcModule 一律为 null：ploidy 深链 apply 只切 tab、'
      '不回填任何计算器输入（无真 target 可传）', (tester) async {
    await pumpPage(tester);
    await tapCalc(tester, '计算组数');
    await tapCalc(tester, '按基因型判断');
    await _ctrlS(tester);
    final entries = MistakeBook.instance.entries;
    expect(entries, hasLength(1));
    expect(entries.single.srcModule, isNull,
        reason: 'initState 注册的 moduleId=ploidy 其 apply 只解析 tab 参数做 '
            '_tab.animateTo——没有任何分支写 _setsCtrl/_triXCtrl/_breedCtrl 等 '
            '计算器输入 ⇒ 存进去的节没有一个能被真实回填，传了会出现点下去'
            '必落回出厂题的回程按钮');
    expect(entries.single.srcParams, isNull);
    cancelPendingTimers();
  });

  // v2.19.53（找茬 D）：stale 快照门在倍性页落地（蓝本：分子页 S6/S7、
  // 进化页 S7）。每个计算器节在算出那一刻存一份输入快照（_xxxSnap），
  // Ctrl+S 时「结果存在且快照==现文」才算新鲜；改输入未重算 ⇒ 该节
  // 题干/答案全剔 ⇒ 全节 stale 时答案空串 ⇒ 既有「先算出结果」守卫拦下。
  testWidgets('S6·stale 闸（单节全剔）：tab0 形态法算出后改总条数不重算，'
      'Ctrl+S 被「先算出结果」守卫拦下、零写入', (tester) async {
    await pumpPage(tester);
    await tapCalc(tester, '计算组数'); // 形态法（默认 8÷4=2 组）算出
    expect(MistakeBook.instance.entries, isEmpty);
    // 改输入但不重算（题面与屏上结果开始自相矛盾）。
    await enterTotal(tester, '16');
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump();
    await _ctrlS(tester);
    expect(find.textContaining('先算出结果'), findsOneWidget,
        reason: '唯一的一节 stale ⇒ 答案空 ⇒ 既有守卫应答');
    expect(MistakeBook.instance.entries, isEmpty,
        reason: '⛔ 矛盾题（题干 16 条 + 答案按 8 条算）不许入库存');
  });

  testWidgets('S7·stale 闸（多节外科手术）：tab2 三节都算出后只改四倍体'
      '基因型不重算，Ctrl+S 存的是剔掉 stale 节后仍自洽的那道',
      (tester) async {
    await pumpPage(tester);
    // 键盘通道切到 tab2「育种应用」（三节同签：单倍体 / 杂交 / 四倍体）。
    await _altDigit(tester, LogicalKeyboardKey.digit3);
    // 节 A：单倍体育种（默认 AaBb）。节 B：杂交育种（默认 AaBb × AAbb）。
    // 节 C：同源四倍体配子（默认 AAaa）。
    await tapCalc(tester, '列出花粉与加倍结果');
    await tapCalc(tester, '推算育种流程');
    await tapCalc(tester, '计算配子比例');
    expect(MistakeBook.instance.entries, isEmpty);
    // 只改节 C 的输入不重算 ⇒ 节 C stale，节 A/B 仍新鲜。
    final fTetra = find.widgetWithText(
        TextField, '四倍体基因型（如 AAaa / AAAa / Aaaa）');
    expect(fTetra, findsOneWidget);
    await tester.ensureVisible(fTetra);
    await tester.pump();
    await tester.enterText(fTetra, 'AAAa');
    await tester.pump();
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump();
    await _ctrlS(tester);
    final entries = MistakeBook.instance.entries;
    expect(entries, hasLength(1),
        reason: '节 A/B 自洽可存，整道不被拦');
    expect(entries.single.stem, isNot(contains('同源四倍体基因型')),
        reason: '⛔ stale 节（四倍体）从题干剔除');
    expect(entries.single.stem, isNot(contains('AAAa')),
        reason: '⛔ 新输入一个字都不许漏进题干（那是一道没算过的题）');
    expect(entries.single.stem, contains('单倍体育种的花粉'),
        reason: '新鲜节（单倍体）保留');
    expect(entries.single.stem, contains('推算杂交育种流程'),
        reason: '新鲜节（杂交育种）保留');
    expect(entries.single.correctAnswer,
        isNot(contains('AA : Aa : aa = 1 : 4 : 1')),
        reason: '⛔ stale 节的答案一并剔除（AAaa 是按旧输入算的）');
    expect(entries.single.correctAnswer, contains('纯合子比例 100%'),
        reason: '新鲜节（单倍体）的答案保留');
    expect(entries.single.correctAnswer, contains('分离世代基因型'),
        reason: '新鲜节（杂交育种）的答案保留');
    cancelPendingTimers();
  });
}
