// review_ladder_extension_test.dart —— v2.19.63 已掌握退避阶梯延长（4 级 → 6 级）
//
// 钉住（创新提案 #5 选定子项）：已掌握按 masteredStreak 退避
//   3 → 7 → 14 → 30 → 60 → 120 天（原 ≥4 次封顶 30 天）。
//
//   R1  逐档到期天数精确（用 dueEntries(now:) 注入可控时钟；streak 0..6）
//   R2  超大 streak（10）按 120 天封顶
//   R3  收口屏文案同步含「60」「120」（泵复习会话全掌握走完——比直接断言
//       源码字符串可靠：断言的是**真渲染到屏上的那句话**）
//   R4  回归：未复习 / 复习中 两种状态的到期规则与改动前逐字一致
//       （防这次只该动「已掌握」档、却顺手改歪另外两档）
//
// 数据铁律：MistakeBook 落独立临时目录，绝不碰真实库；题干唯一
// （存入按「题干 + 正确答案」去重，重复会互相顶替）。
//
// ⛔ 本轮**不做**「每日复习上限」——那是改变学习行为的产品决策，留待用户定。

import 'dart:io';

import 'package:biology/pages/mistake_book_page.dart';
import 'package:biology/state/mistake_book.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory tmp;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('review_ladder_ext');
    MistakeBook.debugFilePath = '${tmp.path}/mistakes.json';
    MistakeBook.debugTrashFilePath = '${tmp.path}/mistakes.trash.json';
    MistakeBook.instance.debugReset();
    // 写盘 debounce Timer：test 结束前 flush，否则框架断言 timersPending。
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

  // 题干 / 答案带单调计数器，保证每条唯一（去重键 = 题干+答案）。
  var seq = 0;
  MistakeEntry addOne() {
    final n = ++seq;
    return MistakeBook.instance.add(
      stem: '阶梯题$n：Aa × Aa 杂交，F₂ 表型比？',
      userAnswer: '1:1',
      correctAnswer: '3:1（第 $n 条正答）',
      errorType: MistakeErrorType.concept,
      subjectArea: '分离定律',
    );
  }

  // 注入时钟：reviewedAt 钉到 [base]，在 [base + days] 这天问是否到期。
  final base = DateTime(2026, 9, 13, 12);
  bool dueAfter(String id, int days) => MistakeBook.instance
      .dueEntries(now: base.add(Duration(days: days)))
      .any((x) => x.id == id);

  // ─────────────────────────────────────────────────────────────────
  //  R1：逐档到位天数精确
  // ─────────────────────────────────────────────────────────────────
  test('R1：已掌握退避阶梯逐档精确 3/7/14/30/60/120', () {
    final e = addOne();

    // streak 0（老 JSON 数据缺字段 / 尚未累计）：按 3 天档。
    MistakeBook.instance.update(
        e.id,
        (c) => c.copyWith(
              reviewStatus: MistakeReviewStatus.mastered,
              masteredStreak: 0,
              reviewedAt: base,
            ));
    expect(dueAfter(e.id, 2), isFalse, reason: 'streak 0 → 3 天档（2 天不到期）');
    expect(dueAfter(e.id, 3), isTrue, reason: 'streak 0 → 3 天档（3 天到期）');

    const ladder = <int, int>{1: 3, 2: 7, 3: 14, 4: 30, 5: 60, 6: 120};
    for (final entry in ladder.entries) {
      final streak = entry.key;
      final interval = entry.value;
      MistakeBook.instance.update(
          e.id,
          (c) => c.copyWith(
                reviewStatus: MistakeReviewStatus.mastered,
                masteredStreak: streak,
                reviewedAt: base,
              ));
      expect(dueAfter(e.id, interval - 1), isFalse,
          reason: 'streak $streak：第 ${interval - 1} 天不得到期（间隔 $interval）');
      expect(dueAfter(e.id, interval), isTrue,
          reason: 'streak $streak：第 $interval 天必须到期');
    }
  });

  // ─────────────────────────────────────────────────────────────────
  //  R2：超大 streak 按 120 天封顶
  // ─────────────────────────────────────────────────────────────────
  test('R2：超大 streak（10）按 120 天封顶', () {
    final e = addOne();
    MistakeBook.instance.update(
        e.id,
        (c) => c.copyWith(
              reviewStatus: MistakeReviewStatus.mastered,
              masteredStreak: 10,
              reviewedAt: base,
            ));
    expect(dueAfter(e.id, 119), isFalse, reason: 'streak 10 仍按 120 天顶');
    expect(dueAfter(e.id, 120), isTrue, reason: 'streak 10：120 天到期');
  });

  // ─────────────────────────────────────────────────────────────────
  //  R3：收口屏文案含 60 / 120（泵复习会话全掌握走完）
  // ─────────────────────────────────────────────────────────────────
  testWidgets('R3：收口屏退避阶梯文案含 60 / 120', (tester) async {
    final e = addOne();
    expect(MistakeBook.instance.dueEntries().any((x) => x.id == e.id), isTrue,
        reason: '前提：新错题即到期，页顶横幅会出现');

    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const MaterialApp(home: MistakeBookPage()));
    await tester.pumpAndSettle();

    // 进复习会话 → 揭示答案 → 判「掌握了」→ 收口屏。
    await tester.ensureVisible(find.text('开始复习'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('开始复习'));
    await tester.pumpAndSettle();

    await tester.tap(find.textContaining('显示答案（1）'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.textContaining('掌握了（1）'));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('掌握了（1）'));
    await tester.pumpAndSettle();

    expect(find.text('本轮复习完成'), findsOneWidget, reason: '前提：已到收口屏');
    // 逐字断言延到 6 级的整串（含 60 与 120 两个新档）。
    expect(find.textContaining('3→7→14→30→60→120 天'), findsOneWidget,
        reason: 'R3：收口屏那句必须同步延到 60 / 120');

    // 收尾：泵过写盘 debounce（markStatus → 定时写盘），别留 pending timer。
    await tester.pump(const Duration(milliseconds: 600));
  });

  // ─────────────────────────────────────────────────────────────────
  //  R4：回归——未复习 / 复习中 到期规则与改动前逐字一致
  // ─────────────────────────────────────────────────────────────────
  test('R4 回归：未复习随时到期；复习中 1 天到期（规则未动）', () {
    final a = addOne(); // 未复习 + reviewedAt 有值
    final b = addOne(); // 未复习 + reviewedAt 空
    final c = addOne(); // 复习中 + reviewedAt 有值
    final d = addOne(); // 复习中 + reviewedAt 空

    MistakeBook.instance.update(
        a.id,
        (x) => x.copyWith(
            reviewStatus: MistakeReviewStatus.unreviewed, reviewedAt: base));
    MistakeBook.instance.update(
        c.id,
        (x) => x.copyWith(
            reviewStatus: MistakeReviewStatus.reviewing, reviewedAt: base));
    MistakeBook.instance.update(
        d.id,
        (x) => x.copyWith(
            reviewStatus: MistakeReviewStatus.reviewing,
            clearReviewedAt: true));

    // 未复习：无论 reviewedAt 有值与否，随时到期。
    expect(dueAfter(a.id, 0), isTrue, reason: '未复习 + reviewedAt 有值 = 立即到期');
    expect(dueAfter(b.id, 0), isTrue, reason: '未复习 + reviewedAt 空 = 立即到期');

    // 复习中：reviewedAt 空 → 立即到期；有值 → ≥1 天才到期。
    expect(dueAfter(d.id, 0), isTrue, reason: '复习中 + reviewedAt 空 = 立即到期');
    expect(dueAfter(c.id, 0), isFalse, reason: '复习中 + 当天刚复习 = 不到期');
    expect(dueAfter(c.id, 1), isTrue, reason: '复习中 + 1 天 = 到期');
  });
}
