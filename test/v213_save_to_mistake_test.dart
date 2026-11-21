// v213_save_to_mistake_test.dart —— 「存入错题本」共享按钮测试（v2.13）
//
// 覆盖（2026-09-12 学生 persona 走查 P1#4 的修复）：
//   1. 学生角色：tap → MistakeBook +1（stem/correctAnswer/subjectArea 原样写入）
//      + SnackBar「已加入错题本」
//   2. 撤销 action → 条目软删进回收站（entries 归零）
//   3. 老师角色：守卫 SnackBar + 零写入（错题本是学生私人空间）
//
// 隔离：MistakeBook.debugFilePath / FirstRunStore.debugFilePath 注入临时文件；
// AI 整理 debounce（500ms）在测试内不推进时钟不触发，tearDown 显式取消。

import 'dart:io';

import 'package:biology/state/first_run_store.dart';
import 'package:biology/state/mistake_book.dart';
import 'package:biology/pages/widgets/save_to_mistake_book.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory tmp;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('v213_save_test');
    MistakeBook.debugFilePath = '${tmp.path}/mistakes.json';
    MistakeBook.debugTrashFilePath = '${tmp.path}/mistakes.trash.json';
    MistakeBook.instance.debugReset();
    FirstRunStore.debugFilePath = '${tmp.path}/first_run.json';
    FirstRunStore.debugWebStorage = null;
    FirstRunStore.debugForceIsWebStorage = false;
    FirstRunStore.instance.debugReset();
  });

  tearDown(() {
    // add() 自带 500ms 写盘 debounce（_saveDebounce）+ AI 整理 debounce，
    // 两者都必须显式取消，否则测试收尾报 Pending timer。
    MistakeBook.instance.debugFlushSave();
    MistakeBook.instance.debugResetAiOrganize();
    MistakeBook.instance.debugReset();
    MistakeBook.debugFilePath = null;
    MistakeBook.debugTrashFilePath = null;
    FirstRunStore.debugFilePath = null;
    FirstRunStore.debugWebStorage = null;
    FirstRunStore.debugForceIsWebStorage = false;
    FirstRunStore.instance.debugReset();
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  Future<void> pumpButton(WidgetTester tester) async {
    // 加大视口：SnackBar action 位于屏幕底部，默认 600 高视口下其中心
    // 会落在 600 之外（y=624）导致 tap 命中失败（撤销用例）。
    tester.view.physicalSize = const Size(800, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: SaveToMistakeBookButton(
          stem: 'Aa × Aa 杂交，后代表型比和基因型比分别是？',
          correctAnswer: '表型比 3:1；基因型 1:2:1',
          subjectArea: '分离定律',
        ),
      ),
    ));
    await tester.pumpAndSettle();
  }

  // fake_async 语义：body 内创建的 Timer 必须在 test body 内取消——
  // package:test 的 tearDown 跑在 body zone 之外，取消不及时。
  // add() 自带 500ms 写盘 debounce + AI 整理 debounce，两者都要清。
  void cancelPendingTimers() {
    MistakeBook.instance.debugFlushSave();
    MistakeBook.instance.debugResetAiOrganize();
  }

  testWidgets('学生角色：tap 写入错题本 + SnackBar 反馈', (tester) async {
    await pumpButton(tester);
    expect(MistakeBook.instance.entries, isEmpty);

    await tester.tap(find.text('存入错题本'));
    await tester.pump(); // 只推进一帧，不越过 500ms AI debounce

    expect(MistakeBook.instance.entries.length, 1,
        reason: 'tap 后应写入 1 条错题');
    final e = MistakeBook.instance.entries.first;
    expect(e.stem, 'Aa × Aa 杂交，后代表型比和基因型比分别是？');
    expect(e.correctAnswer, '表型比 3:1；基因型 1:2:1');
    expect(e.subjectArea, '分离定律');
    expect(e.userAnswer, isEmpty, reason: '收藏场景「我的答案」留空待补');
    expect(find.text('已加入错题本'), findsOneWidget,
        reason: 'SnackBar 反馈可见');
    expect(find.text('去错题本'), findsOneWidget,
        reason: 'UX 走查 P0：存入后一键跳转确认收录');
    expect(find.text('撤销'), findsOneWidget);

    cancelPendingTimers();
  });

  testWidgets('撤销 action：条目软删进回收站', (tester) async {
    await pumpButton(tester);
    await tester.tap(find.text('存入错题本'));
    await tester.pumpAndSettle(); // SnackBar 滑入动画彻底完成（0 高→48px 需要 ~400ms+）
    expect(MistakeBook.instance.entries.length, 1);

    await tester.tap(find.text('撤销'));
    await tester.pump();

    expect(MistakeBook.instance.entries, isEmpty,
        reason: '撤销后 entries 归零');
    expect(MistakeBook.instance.trash.length, 1,
        reason: '软删除进回收站（可从错题本页恢复）');

    cancelPendingTimers();
  });

  testWidgets('老师角色：守卫 SnackBar + 零写入', (tester) async {
    await FirstRunStore.instance.setRole(UserRole.teacher);
    await pumpButton(tester);
    expect(MistakeBook.instance.entries, isEmpty);

    await tester.tap(find.text('存入错题本'));
    await tester.pump();

    expect(MistakeBook.instance.entries, isEmpty,
        reason: '老师守卫：不写入学生私人错题本');
    expect(find.textContaining('错题本是学生功能'), findsOneWidget,
        reason: '守卫提示可见且主语清晰');
  });

  // R5 老师走查（练习判错链路）：userAnswer 透传——复习会话「你当时写」
  // 与 AI 错因归类依赖这个信号。
  testWidgets('userAnswer 参数落库（练习判错场景）', (tester) async {
    tester.view.physicalSize = const Size(800, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: SaveToMistakeBookButton(
          stem: '系谱判断练习：4 名成员（1 名患者）…',
          correctAnswer: '最可能：常染色体隐性',
          subjectArea: '人类遗传病',
          userAnswer: '伴X隐性',
        ),
      ),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('存入错题本'));
    await tester.pump();

    expect(MistakeBook.instance.entries.length, 1);
    expect(MistakeBook.instance.entries.single.userAnswer, '伴X隐性',
        reason: '判错的选项原样进错题本');
    cancelPendingTimers();
  });

  // R5 学生走查：同题干+同答案连存两次 → 查重提示、条目不重复、
  // AI 整理不重复入队。
  testWidgets('重复存入查重：同题干同答案不新增条目', (tester) async {
    await pumpButton(tester);

    await tester.tap(find.text('存入错题本'));
    await tester.pump();
    expect(MistakeBook.instance.entries.length, 1);
    cancelPendingTimers();

    // 第二次存入完全相同的题干+答案（连点/多入口场景）。
    await tester.tap(find.text('存入错题本'));
    await tester.pump();

    expect(MistakeBook.instance.entries.length, 1,
        reason: '查重命中：不产生重复条目');
    expect(find.textContaining('已在错题本'), findsOneWidget,
        reason: '查重提示替代「已加入」');
    cancelPendingTimers();
  });
}
