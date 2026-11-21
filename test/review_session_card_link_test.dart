// ════════════════════════════════════════════════════════════════════════
//  test/review_session_card_link_test.dart
//  v2.19.58：复习会话 → 套路卡回链（揭示区 / 收口屏逐条 / 再练这 X 道）。
// ════════════════════════════════════════════════════════════════════════
//
//  ## 本文件钉住的三块
//  ① 揭示区「看这道题的套路卡（K）」+ K 快捷键：判据 `linkedCardIdOf`
//     与列表卡片同源，命中才渲染、才跳转；未揭示 / 无配套卡都不动路由。
//  ② 收口屏把「还需复习」逐条列出；有配套卡的行给一枚「看套路卡」。
//  ③ 收口屏「再练这 X 道」：拿刚才判「还需复习」的那几道重开一轮。
//
//  ## 数据铁律
//  题干**必须唯一**：MistakeBook 的存入类入口按「题干+答案」去重，题干重复
//  会让两条题在库/屏上互相顶替。故一律用单调计数器拼题干，绝不用
//  `DateTime.now`（同毫秒会撞）。
//
//  ## 命中哪张卡（A 组的考点词）
//  `lib/data/big_question_cards.dart:487 findCardIdForTopic` 对考点做
//  全角→半角 + 小写归一后按 `kCardTopicKeywords` 的**插入顺序**返回首个
//  命中的卡 id。「分离定律」在表里只出现在 `fan-tui-qinben` 的键值
//  （`['反推', '分离定律', '亲本基因型']`）⇒ 命中 `fan-tui-qinben`，唯一。
//  ⇒ A 组「有配套卡」的考点词用「分离定律」。
//
//  ## 视口 / finder 作用域
//  · 800×1200 @1.0：收口屏是居中 Column，题多时保证不溢出。
//  · 复习会话盖在错题本列表**之上**，列表卡片仍在树里（非 offstage）⇒
//    所有 finder 收在 `find.byType(Dialog)` 作用域内，避免命中列表卡片。
//
//  ## ⚠️ 隔离：MistakeBook 落到独立临时目录，绝不碰真实库。

import 'dart:io';

import 'package:biology/pages/big_question_cards_page.dart';
import 'package:biology/pages/mistake_book_page.dart';
import 'package:biology/state/mistake_book.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// 命中 `fan-tui-qinben` 的考点词（见文件头「命中哪张卡」）。
const _kTopicWithCard = '分离定律';

/// 揭示区那枚按钮的文案（禁方向词、禁 markdown 星号）。
const _kRevealCardLabel = '看这道题的套路卡（K）';

/// 题干计数器：保证每条题干唯一。
int _stemSeq = 0;

void main() {
  late Directory tmp;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('review_card_link');
    MistakeBook.debugFilePath = '${tmp.path}/mistakes.json';
    MistakeBook.debugTrashFilePath = '${tmp.path}/mistakes.trash.json';
    MistakeBook.instance.debugReset();
  });

  tearDown(() {
    MistakeBook.instance.debugFlushSave();
    MistakeBook.instance.debugResetAiOrganize();
    MistakeBook.instance.debugReset();
    MistakeBook.debugFilePath = null;
    MistakeBook.debugTrashFilePath = null;
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  /// 存一条错题（题干唯一，单调计数器拼）；返回条目本体。
  MistakeEntry seed({String subjectArea = ''}) {
    final n = ++_stemSeq;
    return MistakeBook.instance.add(
      stem: '卡链题$n',
      userAnswer: '我答$n',
      correctAnswer: '正答$n',
      errorType: MistakeErrorType.concept,
      subjectArea: subjectArea,
    );
  }

  Future<void> pumpPage(WidgetTester tester) async {
    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const MaterialApp(home: MistakeBookPage()));
    await tester.pumpAndSettle();
  }

  /// 进复习会话（页顶横幅 → 开始复习）。
  Future<void> enterReview(WidgetTester tester) async {
    await tester.ensureVisible(find.text('开始复习'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('开始复习'));
    await tester.pumpAndSettle();
  }

  /// 揭示当前题答案，按 [mastered] 作答（掌握 / 还需复习）。
  Future<void> revealAndAnswer(WidgetTester tester,
      {required bool mastered}) async {
    await tester.tap(find.textContaining('显示答案（1）'));
    await tester.pumpAndSettle();
    final label = mastered ? '掌握了（1）' : '还需复习（2）';
    await tester.ensureVisible(find.textContaining(label));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining(label));
    await tester.pumpAndSettle();
  }

  /// 只揭示当前题答案（不作答）。
  Future<void> revealOnly(WidgetTester tester) async {
    await tester.tap(find.textContaining('显示答案（1）'));
    await tester.pumpAndSettle();
  }

  /// finder 收在复习对话框作用域内（列表卡片仍留在树里）。
  Finder inDialog(Finder matching) =>
      find.descendant(of: find.byType(Dialog), matching: matching);

  /// 按 K（揭示区 = 看套路卡；收口屏 = 无事发生）。
  Future<void> pressK(WidgetTester tester) async {
    await tester.sendKeyEvent(LogicalKeyboardKey.keyK);
    await tester.pumpAndSettle();
  }

  /// 收尾：泵过写盘 debounce，别留 pending timer。
  Future<void> settle(WidgetTester tester) async {
    await tester.pump(const Duration(milliseconds: 600));
  }

  // ══════════════════════════════════════════════════════════════════
  //  A. 揭示区「看这道题的套路卡（K）」+ K 快捷键
  // ══════════════════════════════════════════════════════════════════

  testWidgets('A1：有配套卡 → 揭示后按钮在屏；按 K 推入套路卡页',
      (tester) async {
    seed(subjectArea: _kTopicWithCard);
    await pumpPage(tester);
    await enterReview(tester);

    await revealOnly(tester);
    expect(inDialog(find.text(_kRevealCardLabel)), findsOneWidget,
        reason: '揭示后、有配套卡 ⇒ 揭示区那枚按钮在屏上');

    await pressK(tester);
    expect(find.byType(BigQuestionCardsPage), findsOneWidget,
        reason: 'A1：按 K 必须真的推入套路卡页（与按钮同一条 push 路径）');

    await settle(tester);
  });

  testWidgets('A2：未揭示 → 按钮不在、按 K 不导航', (tester) async {
    seed(subjectArea: _kTopicWithCard);
    await pumpPage(tester);
    await enterReview(tester);

    // 未揭示：遮罩态，揭示区那枚根本没渲染。
    expect(inDialog(find.text(_kRevealCardLabel)), findsNothing,
        reason: '未揭示 ⇒ 揭示区按钮不渲染');
    await pressK(tester);
    expect(find.byType(BigQuestionCardsPage), findsNothing,
        reason: 'A2：未揭示时按 K 不得有任何导航');

    await settle(tester);
  });

  testWidgets('A3：考点空 → 无按钮、按 K 不导航', (tester) async {
    seed(subjectArea: '');
    await pumpPage(tester);
    await enterReview(tester);

    await revealOnly(tester);
    expect(inDialog(find.text(_kRevealCardLabel)), findsNothing,
        reason: '考点空 ⇒ 命不中卡 ⇒ 揭示区无按钮');
    await pressK(tester);
    expect(find.byType(BigQuestionCardsPage), findsNothing,
        reason: 'A3：无配套卡时按 K 不得有任何导航');

    await settle(tester);
  });

  testWidgets('A4：收口屏状态按 K 不做任何事', (tester) async {
    seed(subjectArea: _kTopicWithCard);
    await pumpPage(tester);
    await enterReview(tester);
    await revealAndAnswer(tester, mastered: true);
    expect(find.text('本轮复习完成'), findsOneWidget, reason: '前提：已到收口屏');

    await pressK(tester);
    expect(find.byType(BigQuestionCardsPage), findsNothing,
        reason: 'A4：收口屏 _index 已越界 ⇒ 按 K 必须什么都不做');

    await settle(tester);
  });

  // ══════════════════════════════════════════════════════════════════
  //  B. 收口屏列出「还需复习」+ 逐条看套路卡
  // ══════════════════════════════════════════════════════════════════

  testWidgets('B1：两道判「还需复习」逐条列出；「掌握了」的不列',
      (tester) async {
    // 三条：按出现顺序前两条判「还需复习」、第三条判「掌握了」。
    seed(subjectArea: '');
    seed(subjectArea: '');
    seed(subjectArea: '');
    final due = MistakeBook.instance.dueEntries();
    expect(due.length, 3, reason: '前提：三条都到期');
    final missedA = due[0].stem;
    final missedB = due[1].stem;
    final masteredStem = due[2].stem;

    await pumpPage(tester);
    await enterReview(tester);
    await revealAndAnswer(tester, mastered: false);
    await revealAndAnswer(tester, mastered: false);
    await revealAndAnswer(tester, mastered: true);

    expect(find.text('本轮复习完成'), findsOneWidget);
    expect(inDialog(find.text('这几道还需复习')), findsOneWidget,
        reason: '有「还需复习」的题 ⇒ 收口屏出现这一段标题');
    expect(inDialog(find.text(missedA)), findsOneWidget,
        reason: 'B1：第一条「还需复习」的题干必须逐条列出');
    expect(inDialog(find.text(missedB)), findsOneWidget,
        reason: 'B1：第二条「还需复习」的题干必须逐条列出');
    expect(inDialog(find.text(masteredStem)), findsNothing,
        reason: 'B1：「掌握了」的题不得出现在「还需复习」清单里');

    await settle(tester);
  });

  testWidgets('B2：全判掌握 → 无「这几道还需复习」段', (tester) async {
    seed(subjectArea: '');
    await pumpPage(tester);
    await enterReview(tester);
    await revealAndAnswer(tester, mastered: true);

    expect(find.text('本轮复习完成'), findsOneWidget);
    expect(inDialog(find.text('这几道还需复习')), findsNothing,
        reason: 'B2：全部掌握 ⇒ 一个像素都不加');

    await settle(tester);
  });

  testWidgets('B3：missed 里带卡的题 → 该行「看套路卡」可点并推入',
      (tester) async {
    seed(subjectArea: _kTopicWithCard);
    await pumpPage(tester);
    await enterReview(tester);
    await revealAndAnswer(tester, mastered: false);

    final rowBtn = inDialog(find.widgetWithText(TextButton, '看套路卡'));
    expect(rowBtn, findsOneWidget,
        reason: 'B3：带卡的「还需复习」行必须给一枚「看套路卡」');
    await tester.ensureVisible(rowBtn);
    await tester.pumpAndSettle();
    await tester.tap(rowBtn);
    await tester.pumpAndSettle();
    expect(find.byType(BigQuestionCardsPage), findsOneWidget,
        reason: 'B3：收口屏那枚必须真的推入套路卡页');

    await settle(tester);
  });

  testWidgets('B4：missed 里无配套卡的题 → 只有题干，无按钮', (tester) async {
    final e = seed(subjectArea: '');
    await pumpPage(tester);
    await enterReview(tester);
    await revealAndAnswer(tester, mastered: false);

    expect(inDialog(find.text(e.stem)), findsOneWidget,
        reason: 'B4：无配套卡的题只印题干');
    expect(inDialog(find.widgetWithText(TextButton, '看套路卡')), findsNothing,
        reason: 'B4：无配套卡 ⇒ 这一行不给按钮');

    await settle(tester);
  });

  // ══════════════════════════════════════════════════════════════════
  //  C. 创新：收口屏「再练这 X 道」
  // ══════════════════════════════════════════════════════════════════

  testWidgets('C1：判错两道 → 点「再练这 2 道」回到第 1/2 道',
      (tester) async {
    seed(subjectArea: '');
    seed(subjectArea: '');
    final due = MistakeBook.instance.dueEntries();
    expect(due.length, 2, reason: '前提：两条都到期');
    final firstStem = due[0].stem;

    await pumpPage(tester);
    await enterReview(tester);
    await revealAndAnswer(tester, mastered: false);
    await revealAndAnswer(tester, mastered: false);
    expect(find.text('本轮复习完成'), findsOneWidget, reason: '前提：已到收口屏');

    final retry = inDialog(find.textContaining('再练这'));
    expect(retry, findsOneWidget, reason: '有「还需复习」的题 ⇒ 收口屏给「再练」按钮');
    expect(inDialog(find.text('再练这 2 道')), findsOneWidget,
        reason: 'C1：按钮要报出 2 道');
    await tester.ensureVisible(retry);
    await tester.pumpAndSettle();
    await tester.tap(retry);
    await tester.pumpAndSettle();

    expect(find.text('本轮复习完成'), findsNothing,
        reason: 'C1：再练后回到题目视图，收口屏消失');
    expect(inDialog(find.text('第 1 / 2 道')), findsOneWidget,
        reason: 'C1：计数文案归位到第 1 / 2 道');
    expect(inDialog(find.text(firstStem)), findsOneWidget,
        reason: 'C1：第一道（即刚才判错的第一道）的题干重新在屏上');

    await settle(tester);
  });

  testWidgets('C2：全掌握 → 无「再练」按钮', (tester) async {
    seed(subjectArea: '');
    await pumpPage(tester);
    await enterReview(tester);
    await revealAndAnswer(tester, mastered: true);

    expect(find.text('本轮复习完成'), findsOneWidget);
    expect(inDialog(find.textContaining('再练这')), findsNothing,
        reason: 'C2：全部掌握 ⇒ 无「再练这 X 道」按钮');

    await settle(tester);
  });
}
