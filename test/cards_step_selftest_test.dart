// cards_step_selftest_test.dart —— v2.19.61 套路卡「步骤遮挡自测」守卫网
//
// ## 这条网守什么
// 套路卡详情「套路步骤」区块多了一枚「遮着背」开关：打开后每条步骤变成
// 灰遮罩（真文不显示，只印「第 N 步 · 点我揭示」），点哪条揭示哪条；
// 揭示区尾部两枚动作 = 把「刚才卡住的那一步」存进错题本 / 问 AI 讲这步。
//
// ## 断言分组
//   S1 出厂第一张卡切自测态 ⇒ 每步遮罩文案在屏、真文一步都不在屏
//   S2 点「第 2 步」遮罩 ⇒ 只这条揭示，另两步仍遮（成对，防「一点全露」）
//   S3 存进错题本 ⇒ 条目/题干/考点/错因正确；再点一次不重复且回执区分
//   S4 默认背卡态 ⇒ 遮罩与四枚自测按钮一个都不在屏（findsNothing 全套）
//      + 标题行没被开关撑高（否则整页下移，p10 golden 差异就不再局限在
//      标题行那条带——这是本用例存在的最硬理由）
//   S5 「问 AI 讲这步」⇒ AiChatController 队列收到含步骤全文 + 前后步上下文的待发消息
//   S6 @390 窄屏：自测态（含全揭示 + 尾部两枚动作，最宽那一帧）无溢出
//   D1 数据级：14 张卡的考点文案经 findCardIdForTopic 反查回到本卡（错题本回链）
//   D2 数据级：14 张卡全部步骤拼出的题干零 markdown 星号、零方向词
//
// ## 诚实记账
// ① 老师角色守卫（老师模式不写错题本）**没有**端到端覆盖——出厂/测试默认
//    角色是 null（未选），走不到 teacher 分支；该分支与 saveToMistakeBook
//    逐字同款，属于复用既有口径而非本轮新语义。
// ② 「遮罩态与真文行等高」只做了**不整行跳动**的实测（S2 之后不崩不溢），
//    没有断言像素等高——遮罩只印一行提示、真文可折两三行，等高做不到，
//    规格也只承诺「可接受轻微 resize」。

import 'dart:io';

import 'package:biology/data/big_question_cards.dart';
import 'package:biology/services/ai_client.dart';
import 'package:biology/pages/big_question_cards_page.dart';
import 'package:biology/pages/settings_page.dart' show AiChatStore, AiSettingsStore;
import 'package:biology/state/big_question_cards_store.dart';
import 'package:biology/state/first_run_store.dart';
import 'package:biology/state/mistake_book.dart';
import 'package:biology/ui/ai_chat_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 出厂第一张卡（首章首卡）——本网的被测卡。
final BigQuestionCard _firstCard = bigQuestionChapters[0].cards[0];

/// ⛔ 方向词黑名单（与 `cards_page_alt_l_test.dart` 同款，一个字都不放宽）。
const List<String> _kBannedDirWords = <String>[
  '上面', '下面', '上边', '下边', '左边', '右边', //
  '左侧', '右侧', '上方', '下方', '上一行', '下一行',
];

const String _kMask = '点我揭示';
const String _kToggleOn = '遮着背';
const String _kToggleOff = '展开恢复';
const String _kSaveAction = '这步卡住了，存进错题本';
const String _kAskAction = '问 AI 讲这步';

String _maskOf(int i) => '第 ${i + 1} 步 · $_kMask';

void main() {
  late Directory tmp;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('cards_step_selftest');
    // 错题本隔离（存进错题本那条断言全靠它）。
    MistakeBook.debugFilePath = '${tmp.path}/mistakes.json';
    MistakeBook.debugTrashFilePath = '${tmp.path}/mistakes.trash.json';
    MistakeBook.instance.debugReset();
    // 套路卡「已背熟」标记隔离（本网不写它，但页面 initState 会 load）。
    BigQuestionCardsStore.debugFilePath = '${tmp.path}/cards_mastered.json';
    BigQuestionCardsStore.mastered.value = <String>{};
    // 首启/角色隔离：默认角色 = null（≠ teacher）。
    FirstRunStore.debugFilePath = '${tmp.path}/first_run.json';
    FirstRunStore.debugWebStorage = null;
    FirstRunStore.debugForceIsWebStorage = false;
    FirstRunStore.instance.debugReset();
    FirstRunStore.instance.markShortcutNudgeShown();
    // AI 通道隔离：空配置 ⇒ 绝不碰真实网络（同 pages_ask_ai_test）。
    AiChatStore.debugFilePath = '${tmp.path}/ai_chat_history.json';
    AiSettingsStore.debugConfig =
        const AiConfig(baseUrl: '', apiKey: '', model: '');
    AiChatController.instance.reset();
  });

  tearDown(() {
    MistakeBook.instance.debugResetAiOrganize();
    MistakeBook.instance.debugReset();
    MistakeBook.debugFilePath = null;
    MistakeBook.debugTrashFilePath = null;
    BigQuestionCardsStore.debugFilePath = null;
    BigQuestionCardsStore.mastered.value = <String>{};
    FirstRunStore.instance.debugReset();
    FirstRunStore.debugFilePath = null;
    FirstRunStore.debugWebStorage = null;
    AiChatStore.debugFilePath = null;
    AiSettingsStore.debugConfig = null;
    AiChatController.instance.reset();
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  /// fake_async 语义：用例体内触发的写盘/AI debounce（500ms）必须在
  /// **用例体内**显式取消（tearDown 跑在 body zone 之外，来不及）。
  void cancelPendingTimers() {
    MistakeBook.instance.debugFlushSave();
    MistakeBook.instance.debugResetAiOrganize();
  }

  /// 泵整页。默认窗口给得高（1400×2400）——S1/S4 的「真文不在屏」这类
  /// **否定**断言必须发生在「该区块确实在屏」的前提下才有意义（区块若
  /// 根本没挂载，findsNothing 是空断言）。
  Future<void> pumpCards(WidgetTester t,
      {Size size = const Size(1400, 2400), Widget? page}) async {
    t.view.physicalSize = size;
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    await t.pumpWidget(MaterialApp(home: page ?? const BigQuestionCardsPage()));
    await t.pumpAndSettle();
  }

  /// 打开自测态（开关在「套路步骤」标题行，窄屏/默认窗口下先滚进视口）。
  Future<void> openSelfTest(WidgetTester t) async {
    final toggle = find.text(_kToggleOn);
    expect(toggle, findsOneWidget, reason: '前提：屏上应有「$_kToggleOn」开关');
    await t.ensureVisible(toggle);
    await t.pumpAndSettle();
    await t.tap(toggle);
    await t.pumpAndSettle();
    expect(find.text(_kToggleOff), findsOneWidget, reason: '开关应翻成「$_kToggleOff」');
  }

  Future<void> tapText(WidgetTester t, String label) async {
    final f = find.text(label);
    expect(f, findsOneWidget, reason: '前提：屏上应有「$label」');
    await t.ensureVisible(f);
    await t.pumpAndSettle();
    await t.tap(f);
    await t.pumpAndSettle();
  }

  // ══════════════════════════════════════════════════════════════════
  //  S1. 切自测态 ⇒ 每步遮罩在屏，真文一步都不在屏
  // ══════════════════════════════════════════════════════════════════
  testWidgets('S1·切自测态：每步遮罩在屏 / 真文全不在屏', (tester) async {
    await pumpCards(tester);
    // 前提：背卡态真文在屏（否则下面那条否定断言是空断言）。
    for (final s in _firstCard.steps) {
      expect(find.text(s), findsOneWidget, reason: '前提：背卡态应印出步骤全文');
    }

    await openSelfTest(tester);

    for (var i = 0; i < _firstCard.steps.length; i++) {
      expect(find.text(_maskOf(i)), findsOneWidget,
          reason: '第 ${i + 1} 步应有遮罩文案「${_maskOf(i)}」');
    }
    for (var i = 0; i < _firstCard.steps.length; i++) {
      expect(find.text(_firstCard.steps[i]), findsNothing,
          reason: '⛔ 遮罩态下第 ${i + 1} 步的真文不许露在屏上');
    }
  });

  // ══════════════════════════════════════════════════════════════════
  //  S2. 点第 2 步遮罩 ⇒ 只这条揭示（其余仍遮）
  // ══════════════════════════════════════════════════════════════════
  testWidgets('S2·点「第 2 步」遮罩：只有这条揭示，另两步仍遮', (tester) async {
    await pumpCards(tester);
    await openSelfTest(tester);

    await tapText(tester, _maskOf(1));

    expect(find.text(_firstCard.steps[1]), findsOneWidget,
        reason: 'S2：点到的那一步必须揭示真文');
    expect(find.text(_maskOf(1)), findsNothing, reason: '已揭示的这条不再是遮罩');
    // 成对：另外两步一步都不许顺带露出来（否则「点一条露一片」）。
    expect(find.text(_maskOf(0)), findsOneWidget);
    expect(find.text(_maskOf(2)), findsOneWidget);
    expect(find.text(_firstCard.steps[0]), findsNothing);
    expect(find.text(_firstCard.steps[2]), findsNothing);
  });

  // ══════════════════════════════════════════════════════════════════
  //  S3. 存进错题本：条目 / 题干 / 考点 / 错因 + 查重回执
  // ══════════════════════════════════════════════════════════════════
  testWidgets('S3·「这步卡住了」入库 + 再点不重复（回执区分）', (tester) async {
    await pumpCards(tester);
    await openSelfTest(tester);
    await tapText(tester, _maskOf(1)); // 卡在第 2 步

    // 尾部两枚动作只在「已有一步被揭示」时渲染——它此刻必须在屏。
    expect(find.text(_kSaveAction), findsOneWidget,
        reason: '揭示一条之后才谈得上「这步卡住了」');

    await tapText(tester, _kSaveAction);

    final entries = MistakeBook.instance.entries;
    expect(entries, hasLength(1), reason: '恰好入库 1 条');
    final e = entries.single;
    expect(e.stem, contains(_firstCard.title), reason: '题干必须带卡名（认得出是哪张卡）');
    expect(e.stem, contains('第 2 步'), reason: '题干必须带步骤序号');
    expect(e.stem, isNot(contains(_firstCard.steps[1])),
        reason: '⛔ 步骤全文不许进题干（题干带答案 ⇒ 复习时等于白送）');
    expect(e.correctAnswer, _firstCard.steps[1], reason: '答案 = 该步骤全文');
    expect(e.errorType, MistakeErrorType.concept,
        reason: '自测卡住 = 做法没进脑子，不是算错数 ⇒ concept');
    expect(e.subjectArea, subjectAreaForBigQuestionCard(_firstCard));
    expect(findCardIdForTopic(e.subjectArea), _firstCard.id,
        reason: '考点文案必须能反查回本卡（错题本「看套路卡」回链靠它）');
    expect(e.userAnswer, '', reason: '自测没有作答 ⇒ 空串（不是占位串）');
    expect(find.textContaining('已加入错题本'), findsOneWidget);

    // 再点一次：同卡同步题干逐字相同 ⇒ 不重复入库，回执区分。
    await tapText(tester, _kSaveAction);
    expect(MistakeBook.instance.entries, hasLength(1),
        reason: '⛔ 同卡同步不重复入库（AI 整理也不该被重复入队）');
    expect(find.textContaining('这步已在错题本里'), findsOneWidget,
        reason: '重复时回执必须与「已加入」区分开');
    expect(find.textContaining('已加入错题本'), findsNothing,
        reason: '重复时不许再报一次「已加入」');

    cancelPendingTimers();
  });

  // ══════════════════════════════════════════════════════════════════
  //  S4. 默认态零自测痕 + 标题行没被开关撑高
  // ══════════════════════════════════════════════════════════════════
  testWidgets('S4·默认态：遮罩与四枚自测按钮全不在屏（且标题行未变高）',
      (tester) async {
    await pumpCards(tester);

    expect(find.textContaining(_kMask), findsNothing,
        reason: '默认态不许有遮罩文案');
    expect(find.text(_kSaveAction), findsNothing);
    expect(find.text(_kAskAction), findsNothing);
    expect(find.text('全部揭示'), findsNothing);
    expect(find.text('重新遮'), findsNothing);
    // 反向成对：真文在屏（证明上面那几条不是在空区块上断言的）。
    expect(find.text(_firstCard.steps[0]), findsOneWidget);
    expect(find.text(_kToggleOn), findsOneWidget,
        reason: '开关本身在默认态就在（学生得先看得见它）');

    // ⛔ 等高：套路步骤标题行 = 识别信号标题行（都没有 trailing 时的行高）。
    // 开关一旦比标题文字行高，本卡的标题行就变高、整页内容下移，p10
    // golden 的差异从「标题行那条带」扩成「标题行到页底」。
    final stepsRow = tester.getSize(find.byKey(const ValueKey('blockTitle:套路步骤')));
    final signalsRow =
        tester.getSize(find.byKey(const ValueKey('blockTitle:识别信号')));
    expect(stepsRow.height, signalsRow.height,
        reason: '「遮着背」开关把标题行撑高了（$stepsRow vs $signalsRow）⇒ '
            '整个卡片内容会跟着下移，p10 golden 的差异不再局限在标题行那条带');
  });

  // ══════════════════════════════════════════════════════════════════
  //  S5. 问 AI 讲这步 ⇒ 队列收到含步骤全文 + 前后步上下文
  // ══════════════════════════════════════════════════════════════════
  testWidgets('S5·「问 AI 讲这步」⇒ 队列收下含步骤与前后文的待发消息',
      (tester) async {
    await pumpCards(tester);
    await openSelfTest(tester);
    await tapText(tester, _maskOf(1));

    // ⛔ 让 queueSend 走**排队**分支（空闲时会当场 send，队列看不到）：
    // 与 ai_chat_controller_concurrency_test 断言 ctrl.queue 的手法同款。
    final ctrl = AiChatController.instance;
    ctrl.busy = true;

    final ask = find.text(_kAskAction);
    await tester.ensureVisible(ask);
    await tester.pumpAndSettle();
    await tester.tap(ask);
    // ⛔ 面板有常驻呼吸动画（repeat），pumpAndSettle 永不 settle ⇒ 定长 pump
    //（照 pages_ask_ai_test 的 settle 手法）。
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(ctrl.queue, isNotEmpty, reason: '回答中点「问 AI 讲这步」应入队');
    final queued = ctrl.queue.join('\n');
    expect(queued, contains(_firstCard.title), reason: '待发消息应带卡名');
    expect(queued, contains(_firstCard.steps[1]), reason: '待发消息应带这一步全文');
    expect(queued, contains(_firstCard.steps[0]),
        reason: '待发消息应带前一步上下文（第 2 步的前一步是第 1 步）');
    expect(find.text('AI 遗传助手'), findsOneWidget, reason: '助手面板应打开');

    // 收尾：面板还开着（呼吸动画在跑），关掉它再退出，别把动画留给下一个用例。
    ctrl.busy = false;
    ctrl.reset();
  });

  // ══════════════════════════════════════════════════════════════════
  //  S6. @390 窄屏：自测态（最宽那一帧）无溢出
  // ══════════════════════════════════════════════════════════════════
  testWidgets('S6·390 窄屏自测态（全揭示 + 尾部两枚动作）无 RenderFlex overflow',
      (tester) async {
    await pumpCards(tester, size: const Size(390, 844));
    await openSelfTest(tester);
    expect(tester.takeException(), isNull, reason: '自测态首帧无溢出');

    // 全部揭示 = 自测态最宽那一帧（真文行 + 四枚小按钮同屏）。
    await tapText(tester, '全部揭示');
    for (var i = 0; i < _firstCard.steps.length; i++) {
      expect(find.text(_firstCard.steps[i]), findsOneWidget,
          reason: '「全部揭示」应把第 ${i + 1} 步全放出来');
    }
    expect(find.text(_kSaveAction), findsOneWidget);
    expect(find.text(_kAskAction), findsOneWidget);
    expect(tester.takeException(), isNull,
        reason: '全揭示后 390 窄屏仍无 RenderFlex overflow');
  });

  // ══════════════════════════════════════════════════════════════════
  //  D1. 数据级：14 张卡考点文案经反查回到本卡
  // ══════════════════════════════════════════════════════════════════
  test('D1·14 张卡的考点文案都能反查回本卡（错题本回链不断）', () {
    final cards = bigQuestionChapters.expand((c) => c.cards).toList();
    expect(cards, hasLength(14), reason: '前提：出厂 14 张卡');
    for (final c in cards) {
      final area = subjectAreaForBigQuestionCard(c);
      expect(area, isNotEmpty, reason: '${c.id} 的考点文案不许为空');
      expect(findCardIdForTopic(area), c.id,
          reason: '${c.id} 的考点文案「$area」反查到了别的卡（或 null）⇒ '
              '错题本里那条「卡在第几步」的条目点「看套路卡」会跳错/无反应');
    }
  });

  // ══════════════════════════════════════════════════════════════════
  //  D2. 数据级：题干零 markdown 星号、零方向词
  // ══════════════════════════════════════════════════════════════════
  test('D2·题干卫生：零 markdown 星号 / 零方向词 / 书名号成对', () {
    for (final c in bigQuestionChapters.expand((cc) => cc.cards)) {
      for (var i = 0; i < c.steps.length; i++) {
        final stem = stuckStepStem(c, i);
        expect(stem, contains('「'), reason: '$stem 缺少中文书名号');
        expect(stem, contains('」'), reason: '$stem 缺少中文书名号');
        expect(stem.contains('*'), isFalse, reason: '「$stem」含 markdown 星号');
        for (final w in _kBannedDirWords) {
          expect(stem.contains(w), isFalse, reason: '「$stem」含方向词「$w」');
        }
        expect(stem, contains('第 ${i + 1} 步'), reason: '$stem 缺少步骤序号');
      }
    }
  });
}
