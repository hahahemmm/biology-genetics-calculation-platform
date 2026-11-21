// ctrl_s_9331_migration_test.dart —— v2.19.55 9331 旧宿主迁移守卫网
//
// v2.19.55 把 9331 三 tab / 系谱推断共 8 处 CallbackShortcuts 旧宿主迁到
// SaveMistakeKeyHost（按下现取 + 激活闸 + 焦点让路）。本文件钉迁移后的
// 关键行为，含一处**有意行为变更**：焦点在输入框时 Ctrl+S 现在无声让路
// （旧宿主会存下敲到一半的题干）——与五算题页同 UX。
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
    tmp = Directory.systemTemp.createTempSync('ctrl_s_9331');
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

  testWidgets('M1·双基因算出后 Ctrl+S：入库且带来源回程（迁移不丢功能）',
      (tester) async {
    await pump9331(tester);
    final calc = find.text('计算比例');
    expect(calc, findsOneWidget, reason: '前提：双基因页签的计算按钮');
    await tester.ensureVisible(calc);
    await tester.pump();
    await tester.tap(calc);
    await tester.pumpAndSettle();
    expect(find.textContaining('表型比'), findsWidgets,
        reason: '前提：结果已算出');
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump();
    await _ctrlS(tester);
    final entries = MistakeBook.instance.entries;
    expect(entries, hasLength(1));
    expect(entries.single.subjectArea, '自由组合定律');
    expect(entries.single.srcModule, 'cross_dihybrid',
        reason: '⛔ 迁移后 Ctrl+S 存的必须仍带来源（与按钮同口径）');
    MistakeBook.instance.debugFlushSave();
    MistakeBook.instance.debugResetAiOrganize();
  });

  testWidgets('M2·焦点闸迁移生效：持焦 Ctrl+S 无声无写，失焦后同键必存',
      (tester) async {
    await pump9331(tester);
    // 聚焦第一个亲本输入框（持焦态）。
    await tester.tap(find.byType(TextField).first);
    await tester.pump();
    await _ctrlS(tester);
    expect(MistakeBook.instance.entries, isEmpty,
        reason: 'v2.19.55 行为变更守卫：9331 旧宿主存半串题干 ⇒ 新宿主让路');
    expect(find.textContaining('先算出结果'), findsNothing,
        reason: '让路 = 无声（连守卫 SnackBar 也不弹）');
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump();
    await _ctrlS(tester);
    expect(find.textContaining('先算出结果'), findsOneWidget,
        reason: '失焦后同一枚键到达宿主 ⇒ 空答案守卫应答（还没算题）');
  });
}
