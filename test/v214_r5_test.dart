// v214_r5_test.dart —— R5 双 persona 走查修复的回归测试（v2.14）
//
// 覆盖（2026-09-13 R5 走查 → 修复）：
//   1. 引擎：copyWith(clearReviewedAt) 真清空——「还需复习 = 今晚立即到期」
//      此前是死代码（copyWith(reviewedAt: null) 被 ?? 吞掉）
//   2. 引擎：已掌握间隔按 masteredStreak 退避 3→7→14→30 天（原固定 3 天
//      永久轮回：越用功复习债越多）
//   3. 引擎：addOrFind 按 题干+正确答案 查重（连点/多入口重复存入）
//   4. HistoryStore.append：同 label 10 分钟去重窗口 + 串行链
//   5. scanActionLabel：add_member / set_parents 中文映射（原裸英文类型名）
//   6. 练习模式：录入非空 → 确认弹窗 → 退出恢复系谱快照 + 本轮战绩 chip

import 'dart:io';

import 'package:biology/pages/genetic_disease_page.dart';
import 'package:biology/state/history_store.dart';
import 'package:biology/state/mistake_book.dart';
import 'package:biology/ui/scan_upload_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('MistakeBook R5 引擎修订', () {
    late Directory tmp;

    setUp(() {
      tmp = Directory.systemTemp.createTempSync('v214_r5_test');
      MistakeBook.debugFilePath = '${tmp.path}/mistakes.json';
      MistakeBook.debugTrashFilePath = '${tmp.path}/mistakes.trash.json';
      MistakeBook.instance.debugReset();
      addTearDown(() {
        MistakeBook.instance.debugFlushSave();
        MistakeBook.instance.debugResetAiOrganize();
      });
    });

    tearDown(() {
      MistakeBook.debugFilePath = null;
      MistakeBook.debugTrashFilePath = null;
      MistakeBook.instance.debugReset();
      if (tmp.existsSync()) tmp.deleteSync(recursive: true);
    });

    MistakeEntry addOne() => MistakeBook.instance.add(
          stem: 'Aa × Aa 杂交，F₂ 表型比？',
          userAnswer: '1:1',
          correctAnswer: '3:1',
          errorType: MistakeErrorType.concept,
          subjectArea: '分离定律',
        );

    test('clearReviewedAt 真正清空——「还需复习」今晚立即到期', () {
      final e = addOne();
      MistakeBook.instance.markStatus(e.id, MistakeReviewStatus.reviewing);
      var cur = MistakeBook.instance.entries.singleWhere((x) => x.id == e.id);
      expect(cur.reviewedAt, isNotNull, reason: 'markStatus 写了 now');

      // 旧写法 copyWith(reviewedAt: null) 是死代码——?? 保留原值。
      MistakeBook.instance
          .update(e.id, (c) => c.copyWith(clearReviewedAt: true));
      cur = MistakeBook.instance.entries.singleWhere((x) => x.id == e.id);
      expect(cur.reviewedAt, isNull, reason: '显式开关才真正清空');

      expect(
        MistakeBook.instance.dueEntries().any((x) => x.id == e.id),
        isTrue,
        reason: 'reviewing + reviewedAt 空 → 立即到期（今晚还能再练）',
      );
    });

    test('已掌握间隔按 masteredStreak 退避 3→7→14→30 天', () {
      final e = addOne();
      final base = DateTime(2026, 9, 13, 12);
      bool dueAfter(int days) => MistakeBook.instance
          .dueEntries(now: base.add(Duration(days: days)))
          .any((x) => x.id == e.id);

      void ageToBase() => MistakeBook.instance
          .update(e.id, (c) => c.copyWith(reviewedAt: base));

      // streak 1：3 天。
      MistakeBook.instance.markStatus(e.id, MistakeReviewStatus.mastered);
      ageToBase();
      expect(dueAfter(2), isFalse);
      expect(dueAfter(3), isTrue, reason: '首次掌握 = 3 天间隔');

      // streak 2：7 天。
      MistakeBook.instance.markStatus(e.id, MistakeReviewStatus.mastered);
      ageToBase();
      expect(dueAfter(6), isFalse, reason: '第二次掌握退避到 7 天');
      expect(dueAfter(7), isTrue);

      // streak 3：14 天。
      MistakeBook.instance.markStatus(e.id, MistakeReviewStatus.mastered);
      ageToBase();
      expect(dueAfter(13), isFalse, reason: '第三次掌握退避到 14 天');
      expect(dueAfter(14), isTrue);

      // streak 4：30 天。
      MistakeBook.instance.markStatus(e.id, MistakeReviewStatus.mastered);
      ageToBase();
      expect(dueAfter(29), isFalse, reason: '第四次掌握退避到 30 天');
      expect(dueAfter(30), isTrue);

      // 答错清零：标「还需复习」后 masteredStreak 归零。
      MistakeBook.instance.markStatus(e.id, MistakeReviewStatus.reviewing);
      var cur = MistakeBook.instance.entries.singleWhere((x) => x.id == e.id);
      expect(cur.masteredStreak, 0, reason: '回来一道 = 上次掌握判定作废');
      MistakeBook.instance.markStatus(e.id, MistakeReviewStatus.mastered);
      ageToBase();
      expect(dueAfter(2), isFalse);
      expect(dueAfter(3), isTrue, reason: 'streak 清零后重新从 3 天起');
    });

    test('addOrFind：同题干+同答案复用旧条目（查重）', () {
      final r1 = MistakeBook.instance.addOrFind(
        stem: 'Aa × Aa 杂交，F₂ 表型比？',
        userAnswer: '',
        correctAnswer: '3:1',
        errorType: MistakeErrorType.other,
        subjectArea: '分离定律',
      );
      expect(r1.isNew, isTrue);

      // 同题干同答案（trim 后）→ 命中旧条目，不新增。
      final r2 = MistakeBook.instance.addOrFind(
        stem: ' Aa × Aa 杂交，F₂ 表型比？ ',
        userAnswer: '随便',
        correctAnswer: '3:1',
        errorType: MistakeErrorType.concept,
        subjectArea: '别的考点',
      );
      expect(r2.isNew, isFalse);
      expect(r2.entry.id, r1.entry.id);
      expect(MistakeBook.instance.entries.length, 1);

      // 答案不同 → 允许新条目（同题不同问法各收一道是合理语义）。
      final r3 = MistakeBook.instance.addOrFind(
        stem: 'Aa × Aa 杂交，F₂ 表型比？',
        userAnswer: '',
        correctAnswer: '3:1；基因型 1:2:1',
        errorType: MistakeErrorType.other,
        subjectArea: '分离定律',
      );
      expect(r3.isNew, isTrue);
      expect(MistakeBook.instance.entries.length, 2);
    });
  });

  group('HistoryStore.append（R5 串行链 + 同 label 去重窗口）', () {
    late Directory tmp;

    setUp(() {
      tmp = Directory.systemTemp.createTempSync('v214_hist_test');
      HistoryStore.debugFilePath = '${tmp.path}/history.json';
    });

    tearDown(() {
      HistoryStore.debugFilePath = null;
      if (tmp.existsSync()) tmp.deleteSync(recursive: true);
    });

    HistoryEntry e(String label, DateTime t) =>
        HistoryEntry(label: label, epochMs: t.millisecondsSinceEpoch, detail: '');

    test('同 label 10 分钟内去重；异 label / 超窗正常追加', () async {
      final t0 = DateTime(2026, 9, 13, 10);
      await HistoryStore.append(e('A', t0));
      await HistoryStore.append(e('A', t0.add(const Duration(minutes: 2))));
      expect((await HistoryStore.load()).length, 1,
          reason: '同题 2 分钟内重算 = 内存去重置顶语义，磁盘不追加');

      await HistoryStore.append(e('B', t0.add(const Duration(minutes: 3))));
      expect((await HistoryStore.load()).length, 2);

      await HistoryStore.append(e('A', t0.add(const Duration(minutes: 30))));
      expect((await HistoryStore.load()).length, 3,
          reason: '超出 10 分钟窗口 → 正常追加（跨课重讲同题要留痕）');
    });
  });

  group('scanActionLabel（R5 中文映射）', () {
    test('add_member / set_parents 落到中文，未知类型原样返回', () {
      expect(
        scanActionLabel(
            {'type': 'add_member', 'id': 'I1', 'sex': 'male', 'status': 'affected'}),
        '录入成员 I1·男·患病',
      );
      expect(
        scanActionLabel({
          'type': 'add_member',
          'id': 'II2',
          'sex': 'female',
          'status': 'normal'
        }),
        '录入成员 II2·女·正常',
      );
      expect(
        scanActionLabel({
          'type': 'set_parents',
          'father': 'XAY',
          'mother': 'XAXa',
          'mode': 'rec'
        }),
        contains('设双亲'),
      );
      expect(scanActionLabel({'type': 'next_generation'}), '计算下一代');
      // 未知类型不崩、原样呈现（比静默吞掉强）。
      expect(scanActionLabel({'type': 'future_action'}), 'future_action');
    });
  });

  group('练习模式（R5 确认 + 快照恢复 + 战绩）', () {
    testWidgets('录入非空 → 确认弹窗；退出练习恢复系谱快照', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: GeneticDiseasePage()));
      await tester.pumpAndSettle();
      // v2.19.28 工作台化：推断器收在「系谱推断」tab——切过去即渲染。
      await tester.tap(find.text('系谱推断'));
      await tester.pumpAndSettle();

      // 学生真实场景：录到一半好奇点开练习。
      await tester.tap(find.text('添加成员'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('添加成员'));
      await tester.pumpAndSettle();
      expect(find.text('M2'), findsOneWidget);

      // 开练习 → 确认弹窗（rows 非空才弹）。
      await tester.tap(find.text('练习模式'));
      await tester.pumpAndSettle();
      expect(find.text('进入练习模式？'), findsOneWidget,
          reason: '替换录入前必须确认（老师走查 P0）');

      // 取消 → 原系谱不动。
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(find.text('M2'), findsOneWidget);
      expect(find.textContaining('你的判断'), findsNothing,
          reason: '取消后未进入练习');

      // 确认进入 → 示例载入（录入成员被替换），战绩 chip 出现。
      await tester.tap(find.text('练习模式'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('进入练习'));
      await tester.pumpAndSettle();
      expect(find.text('I1'), findsWidgets, reason: '载入经典示例');
      expect(find.text('M2'), findsNothing, reason: '录入成员被示例替换');
      expect(find.textContaining('本轮 0 对 0'), findsOneWidget,
          reason: '本轮战绩 chip（学生走查：积累感）');

      // 退出练习 → 恢复快照。
      await tester.tap(find.text('练习中'));
      await tester.pumpAndSettle();
      expect(find.text('M2'), findsOneWidget, reason: '退出练习恢复录入系谱');
      expect(find.text('I1'), findsNothing, reason: '示例成员退场');
    });
  });
}
