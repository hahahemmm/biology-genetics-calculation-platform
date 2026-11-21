// ctrl_s_9331_single_host_test.dart —— v2.19.57 9331 页级单宿主守卫网
//
// 背景（找茬双 verifier 独立收敛的 blocker B1）：9331 七个页签全部
// keep-alive，v2.19.55 迁移后页内存活 7 枚 SaveMistakeKeyHost
// （双基因 build+sidePanel 两枚、单基因两枚、伴性两枚、三对基因一枚）。
// SDK 语义：HardwareKeyboard 的 handler **全部收到事件**，返回值只做
// OR 汇总——没有 CallbackShortcuts 时代「内层消费」的互斥。于是：
//   (a) 访问过 N 个页签后按一次 Ctrl+S = N 个页签各自入库（3 条非用户
//       本意），未算出的页签还连弹「先算出结果」；
//   (b) 同 tab 双宿主时第二枚的「已在错题本里」把第一枚的
//       「已加入错题本（含撤销）」顶掉——回执与撤销按钮丢失。
// 修复：容器页收编为**一枚**页级宿主，payload 按 _tab.index 分派到
// 当前页签 State 的 savePayload()（⛔ 不用 build 期预取）；宿主组件
// 另加「同键互斥消费闸」（Expando 标记同一次按键只应答一次）。
//
// 本文件在**修复前**跑必红（entries 4 条 / 回执被顶），修复后必绿。
import 'dart:io';

import 'package:biology/pages/cross_calculator_page.dart';
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
    tmp = Directory.systemTemp.createTempSync('ctrl_s_9331_single_host');
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

  /// 切到指定页签并点它的计算按钮（默认出厂输入即算）。
  Future<void> computeOnTab(
      WidgetTester tester, String tabLabel, String buttonLabel) async {
    await tester.ensureVisible(find.text(tabLabel));
    await tester.tap(find.text(tabLabel));
    await tester.pumpAndSettle();
    final btn = find.text(buttonLabel);
    expect(btn, findsOneWidget, reason: '前提：$tabLabel 的计算按钮 $buttonLabel');
    await tester.ensureVisible(btn);
    await tester.pump();
    await tester.tap(btn);
    await tester.pumpAndSettle();
  }

  testWidgets('S1·访问四个页签各算出后按一次 Ctrl+S：只存当前页签一题',
      (tester) async {
    await pump9331(tester);
    await computeOnTab(tester, '双基因 9331', '计算比例');
    await computeOnTab(tester, '三对基因', '计算比例');
    await computeOnTab(tester, '单基因杂交', '杂交');
    await computeOnTab(tester, '伴性遗传', '计算子代');
    // 回到双基因页签（跨页连发的触发位）。
    await tester.ensureVisible(find.text('双基因 9331'));
    await tester.tap(find.text('双基因 9331'));
    await tester.pumpAndSettle();
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump();

    await _ctrlS(tester);

    // 修复前实际：4 条全入库（di/tri/mono/sex 各一）+ 连弹守卫条。
    final entries = MistakeBook.instance.entries;
    expect(entries, hasLength(1),
        reason: '一次按键只应答一次：只存当前页签（双基因）这一题');
    expect(entries.single.subjectArea, '自由组合定律');
    expect(find.textContaining('已加入错题本'), findsOneWidget,
        reason: '成功回执独占（修复前被「已在错题本里」顶掉）');
    expect(find.textContaining('已在错题本里'), findsNothing,
        reason: '双宿主/跨页签连发的典型症状：回执被顶成重复提示');
    expect(find.textContaining('先算出结果'), findsNothing,
        reason: '其余页签的宿主不应再应答这枚键');
    MistakeBook.instance.debugFlushSave();
    MistakeBook.instance.debugResetAiOrganize();
  });

  testWidgets('S2·双基因单 tab 内 Ctrl+S：回执为「已加入」且撤销可用',
      (tester) async {
    await pump9331(tester);
    await computeOnTab(tester, '双基因 9331', '计算比例');
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump();

    await _ctrlS(tester);

    // 修复前（双宿主同键各存一次）：第二枚宿主的去重回执顶掉第一枚。
    expect(find.textContaining('已加入错题本'), findsOneWidget);
    expect(find.textContaining('已在错题本里'), findsNothing);
    expect(MistakeBook.instance.entries, hasLength(1));
    MistakeBook.instance.debugFlushSave();
    MistakeBook.instance.debugResetAiOrganize();
  });
}
