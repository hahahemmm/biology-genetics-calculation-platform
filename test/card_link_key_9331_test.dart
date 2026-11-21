// card_link_key_9331_test.dart —— v2.19.59 9331 五面「K 看这道题的套路卡」守卫网
//
// ## 为什么会有这张网（形态论证与 v2.19.57 的 Ctrl+S 收编逐字同款）
// 9331 容器页七个页签**全部 keep-alive**，而 SDK 的 HardwareKeyboard 语义是
// 「所有 handler 都收到事件，返回值只做 OR 汇总」（没有 CallbackShortcuts 时代
// 的焦点链消费）⇒ 每 tab 各挂一枚键宿主时，按一次 K = 每个访问过的页签各跳
// 一次（连跳，且第二枚把第一枚的 push 再叠一层）。修复形态：容器页
// **唯一一枚** CardLinkKeyHost，cardId 按 `_tab.index` 在按键那一刻现取。
//
// ## 五个「有配套卡」的计算面（考点 → 卡 id）
// 判据真源 `lib/data/big_question_cards.dart` 的 `findCardIdForTopic`：
//   '自由组合定律' → b9331-bianshi（键 '自由组合'）——双基因 / 三对基因 / 自由交配
//   '分离定律'     → fan-tui-qinben（键 '分离定律'）——单基因
//   '伴性遗传'     → banxing-buzhou（键 '伴性'）——伴性
// 方法对比 / 连锁互换**没有**「存入错题本」口径（读源码确认：两页既无
// SavePayload 也无 subjectArea）⇒ 无考点 ⇒ 无卡 ⇒ 按 K 无声让路。
//
// ## 屏上提示与按键是同一个判据（本文件两条腿钉住）
// 「屏上印不印」与「键认不认领」只要各写一份判据，迟早分叉成「印着提示但按
// 不动」或「印着一枚根本不存在的卡」（B 仓 v2.19.249 教训）。故：
//   · A5 读源码：考点字面量**只有一处定义**（各自文件里的那条 const）、
//     `findCardIdForTopic(` 在容器页**只有一处调用**；
//   · 行为侧两层语义（v2.19.59 主线程裁定，八面孔径一致）：尾注的闸 =
//     「有结果 && 考点有卡」（A2 钉无结果不印）；K 的判据 = 「考点有卡」
//     一道（A2 同时钉无结果也跳——套路卡是学习材料，B 仓 v2.19.245 原始
//     语义）。提示印得出 ⇒ 键必跳；提示没印 ⇏ 键不应答。
//
// ## 进页 / 计算的 harness
// 与 `test/ctrl_s_9331_single_host_test.dart` 逐字同源（800×900 窄屏 ⇒ 输入
// 面板内联在结果区上方，无宽屏 rail 副本），MistakeBook / FirstRunStore 落
// 独立临时目录（绝不碰真实库）。

import 'dart:io';

import 'package:biology/data/big_question_cards.dart';
import 'package:biology/pages/big_question_cards_page.dart';
import 'package:biology/pages/cross_calculator_page.dart';
import 'package:biology/pages/widgets/card_link_key_host.dart';
import 'package:biology/state/first_run_store.dart';
import 'package:biology/state/mistake_book.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// 屏上那句尾注（禁 markdown 星号、禁方向词）。
const String _kHintSuffix = ' · 按 K 看这道题的套路卡';

/// 五个「有配套卡」的计算面：页签文案 → 该页签的计算按钮文案。
const List<({String tab, String button})> _facesWithCard = [
  (tab: '双基因 9331', button: '计算比例'),
  (tab: '三对基因', button: '计算比例'),
  (tab: '单基因杂交', button: '杂交'),
  (tab: '伴性遗传', button: '计算子代'),
  (tab: '自由交配', button: '计算子代'),
];

/// 双基因页签「有结果」那一支副标题的逐字原文（尾注拼在它后面）。
const String _kDihybridSubtitle = '配子 · F2 表型/基因型比例 · 基因型明细';

/// ⛔ 方向词黑名单（与 `test/dna_label_bands_diagram_test.dart` 同款，一个字
/// 都不放宽）：读屏软件把方向词读出来等于没有，屏上要点名对象。
const List<String> _kBannedDirWords = <String>[
  '上面',
  '下面',
  '上边',
  '下边',
  '左边',
  '右边',
  '左侧',
  '右侧',
  '上方',
  '下方',
  '上一行',
  '下一行',
];

void main() {
  late Directory tmp;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('card_link_key_9331');
    MistakeBook.debugFilePath = '${tmp.path}/mistakes.json';
    MistakeBook.debugTrashFilePath = '${tmp.path}/mistakes.trash.json';
    MistakeBook.instance.debugReset();
    FirstRunStore.debugFilePath = '${tmp.path}/first_run.json';
    FirstRunStore.debugWebStorage = null;
    FirstRunStore.debugForceIsWebStorage = false;
    FirstRunStore.instance.debugReset();
    // 一次性指引（ShortcutNudge）已在 setUp 里标过 ⇒ 本文件不掺 SnackBar 噪音
    // （K 触发成功仍会走完 maybeNotify 这条路径，只是它立刻 no-op）。
    FirstRunStore.instance.markShortcutNudgeShown();
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

  /// 切到指定页签。
  Future<void> goTab(WidgetTester tester, String tabLabel) async {
    await tester.ensureVisible(find.text(tabLabel));
    await tester.tap(find.text(tabLabel));
    await tester.pumpAndSettle();
  }

  /// 点当前页签的计算按钮（默认出厂输入即可算出）。
  Future<void> compute(WidgetTester tester, String buttonLabel) async {
    final btn = find.text(buttonLabel);
    expect(btn, findsOneWidget,
        reason: '前提：当前页签的计算按钮「$buttonLabel」唯一在屏');
    await tester.ensureVisible(btn);
    await tester.pump();
    await tester.tap(btn);
    await tester.pumpAndSettle();
  }

  /// 按键前先交还焦点（焦点落在输入框里时 K 是输入的一部分，宿主让路）。
  Future<void> releaseFocus(WidgetTester tester) async {
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump();
  }

  /// 按 K（宿主读的是 KeyDownEvent）。
  Future<void> pressK(WidgetTester tester) async {
    await tester.sendKeyEvent(LogicalKeyboardKey.keyK);
    await tester.pumpAndSettle();
  }

  // ══════════════════════════════════════════════════════════════════
  //  A1. 有结果 ⇒ 尾注在屏 + 按 K 推入套路卡页（五个计算面逐个）
  // ══════════════════════════════════════════════════════════════════

  for (final f in _facesWithCard) {
    testWidgets('A1·${f.tab}：算出结果 → 副标题含尾注、按 K 推入套路卡页',
        (tester) async {
      await pump9331(tester);
      await goTab(tester, f.tab);
      await compute(tester, f.button);

      expect(find.textContaining(_kHintSuffix), findsOneWidget,
          reason: 'A1①：${f.tab} 有结果 ⇒ 结果区副标题必须含「$_kHintSuffix」');

      await releaseFocus(tester);
      await pressK(tester);
      expect(find.byType(BigQuestionCardsPage), findsOneWidget,
          reason: 'A1②：${f.tab} 的考点命中配套卡 ⇒ 按 K 必须真的推入套路卡页');
    });
  }

  /// 双基因页签的逐字格式锚（防「只加了个空格」这类静默漂移）。
  testWidgets('A1b·双基因：副标题逐字为「$_kDihybridSubtitle$_kHintSuffix」',
      (tester) async {
    await pump9331(tester);
    await compute(tester, '计算比例');

    expect(find.text('$_kDihybridSubtitle$_kHintSuffix'), findsOneWidget,
        reason: '尾注是原句 + 「$_kHintSuffix」，中间不多不少一个空格');
  });

  // ══════════════════════════════════════════════════════════════════
  //  A2. 未计算 ⇒ 整句不渲染；但 K 仍跳（键判据=考点有卡，与提示解耦）
  // ══════════════════════════════════════════════════════════════════

  testWidgets('A2·未计算：副标题无尾注；按 K 仍跳（两个页签各验一次）',
      (tester) async {
    await pump9331(tester);
    // 出厂态的双基因页签：无结果 ⇒ 副标题是「未计算」那一句。
    expect(find.text('设定亲本后点「计算比例」，这里展开配子、F2 比例与基因型明细'),
        findsOneWidget,
        reason: '前提：出厂态双基因页签没有结果');
    expect(find.textContaining(_kHintSuffix), findsNothing,
        reason: 'A2①：没算出结果 ⇒ 副标题不加尾注');

    await releaseFocus(tester);
    await pressK(tester);
    expect(find.byType(BigQuestionCardsPage), findsOneWidget,
        reason: 'A2②：双基因考点有卡 ⇒ 没算出结果按 K 也跳'
            '（套路卡是学习材料；B 仓 v2.19.245 原始语义）');

    // 退卡，换伴性页签再验一遍（防「只看 tab 0」的假绿）。
    await tester.pageBack();
    await tester.pumpAndSettle();
    await goTab(tester, '伴性遗传');
    expect(find.textContaining(_kHintSuffix), findsNothing);
    await releaseFocus(tester);
    await pressK(tester);
    expect(find.byType(BigQuestionCardsPage), findsOneWidget,
        reason: 'A2③：伴性页签未计算 ⇒ 同样跳');
  });

  // ══════════════════════════════════════════════════════════════════
  //  A3. 考点命不中卡的页签（方法对比）⇒ 无尾注、按 K 无导航
  // ══════════════════════════════════════════════════════════════════

  testWidgets('A3·方法对比：算出结果也没有尾注、按 K 无导航', (tester) async {
    await pump9331(tester);
    await goTab(tester, '方法对比');
    await compute(tester, '开始对比');
    // 前提：确实算出了结果（否则「无尾注」断言是空过的）。
    expect(find.text('设定亲本后点「开始对比」，这里并排展示两种解法'), findsNothing,
        reason: '前提：方法对比已算出结果（未计算提示消失）');

    expect(find.textContaining(_kHintSuffix), findsNothing,
        reason: 'A3①：方法对比没有「存入错题本」口径 ⇒ 无考点 ⇒ 不加尾注');
    await releaseFocus(tester);
    await pressK(tester);
    expect(find.byType(BigQuestionCardsPage), findsNothing,
        reason: 'A3②：无考点 ⇒ 无卡 ⇒ 按 K 必须无声让路（⛔ 不替它编一个考点）');
  });

  // ══════════════════════════════════════════════════════════════════
  //  A4. 焦点闸成对：持焦让路 / 失焦必跳
  // ══════════════════════════════════════════════════════════════════

  testWidgets('A4·焦点在输入框里按 K 让路；失焦后同一枚键必跳', (tester) async {
    await pump9331(tester);
    await compute(tester, '计算比例');
    expect(find.textContaining(_kHintSuffix), findsOneWidget,
        reason: '前提：已有结果、屏上已印尾注');

    final field = find.byType(TextField).first;
    await tester.ensureVisible(field);
    await tester.pumpAndSettle();
    await tester.tap(field);
    await tester.pump();
    final focus = FocusManager.instance.primaryFocus;
    expect(focus?.context?.findAncestorWidgetOfExactType<EditableText>(), isNotNull,
        reason: '前提：焦点确实挂在 EditableText 里');

    await pressK(tester);
    expect(find.byType(BigQuestionCardsPage), findsNothing,
        reason: '持焦让路：敲到一半的题干里按 K 是输入的一部分');

    await releaseFocus(tester);
    await pressK(tester);
    expect(find.byType(BigQuestionCardsPage), findsOneWidget,
        reason: '守卫成对：失焦后同一枚键必须跳（否则就是「快捷键看着存在、按了没反应」）');
  });

  // ══════════════════════════════════════════════════════════════════
  //  A5. 源码级：考点常量只一处定义 + findCardIdForTopic 只一处调用
  // ══════════════════════════════════════════════════════════════════

  test('A5·源码级：屏上尾注与按键宿主共用同一判据（各面考点只有一处定义）',
      () {
    final containerSrc =
        File('lib/pages/cross_calculator_page.dart').readAsStringSync();
    final monoSrc =
        File('lib/pages/widgets/mono_cross_widget.dart').readAsStringSync();
    final sexSrc =
        File('lib/pages/widgets/sex_linked_tab.dart').readAsStringSync();

    // ① 容器页只有**一处** `findCardIdForTopic(` 调用：宿主 cardId 与屏上尾注
    //    都从顶层 `_cardIdForTopic` 走 ⇒ 两处不可能分叉。
    expect('findCardIdForTopic('.allMatches(containerSrc).length, 1,
        reason: 'A5①：判据只许有一个调用点（多一处就是「键认领」与「屏上印」'
            '各写一份的开端）');

    // ② 三个考点字面量各只有一处定义（= 各自那条 const），且 subjectArea
    //    一律引用常量（⛔ 没有任何 `subjectArea: '…'` 字面量残留）。
    expect("'自由组合定律'".allMatches(containerSrc).length, 1,
        reason: 'A5②：kFreeCombinationSubjectArea 的定义');
    expect("'分离定律'".allMatches(monoSrc).length, 1,
        reason: 'A5②：kMonoCrossSubjectArea 的定义');
    expect("'伴性遗传'".allMatches(sexSrc).length, 1,
        reason: 'A5②：kSexLinkedSubjectArea 的定义');
    for (final src in [containerSrc, monoSrc, sexSrc]) {
      expect(src.contains("subjectArea: '"), isFalse,
          reason: 'A5②：subjectArea 必须引用考点常量，不许再写字面量');
    }

    // ③ 容器页的考点分派引用的是**那三处**常量定义（不另抄字面量）。
    for (final name in [
      'kFreeCombinationSubjectArea',
      'kMonoCrossSubjectArea',
      'kSexLinkedSubjectArea',
    ]) {
      expect(containerSrc.contains(name), isTrue,
          reason: 'A5③：容器页的 _currentTabTopic() 必须引用 $name');
    }

    // ④ 行为等价锚：这三个考点确实都命中卡（⇒ 三个面「有卡」这一前提成立）。
    for (final topic in ['自由组合定律', '分离定律', '伴性遗传']) {
      expect(findCardIdForTopic(topic), isNotNull,
          reason: 'A5④：$topic 必须命中一张卡（否则上面的尾注断言是空过的）');
    }
  });

  // ══════════════════════════════════════════════════════════════════
  //  A6. 整页只有一枚 CardLinkKeyHost（防每 tab 一枚的连跳复发）
  // ══════════════════════════════════════════════════════════════════

  testWidgets('A6·走遍七个页签后树里仍只有一枚 CardLinkKeyHost', (tester) async {
    await pump9331(tester);
    for (final tab in [
      '双基因 9331',
      '三对基因',
      '单基因杂交',
      '伴性遗传',
      '方法对比',
      '连锁互换',
      '自由交配',
    ]) {
      await goTab(tester, tab);
    }
    // skipOffstage: false —— keep-alive 的兄弟页签即使 offstage 也一起数，
    // 否则「每 tab 一枚」的旧形态可能被 offstage 遮住而假绿。
    expect(find.byType(CardLinkKeyHost, skipOffstage: false), findsOneWidget,
        reason: 'A6：宿主只能有一枚（多枚 = 同一枚按键被多次认领 = 连跳）');
  });

  // ══════════════════════════════════════════════════════════════════
  //  A8. 屏上文案纪律：零 markdown 星号、零方向词（本仓同款黑名单）
  // ══════════════════════════════════════════════════════════════════

  test('A8·尾注文案零 markdown 星号、零方向词', () {
    final src = File('lib/pages/cross_calculator_page.dart').readAsStringSync();
    // 只取那一条常量的值（其余 UI 文案不在本轮改动范围，不越权断言）。
    final m = RegExp(r"const String kCardKeyHint = '([^']*)';").firstMatch(src);
    expect(m, isNotNull, reason: '前置：kCardKeyHint 常量还在（唯一一处定义）');
    final hint = m!.group(1)!;
    expect(hint, contains(CardLinkKeyHost.keyLabel),
        reason: '文案必须点名那把键（与宿主的 keyLabel 同源，不另写一份）');
    expect(hint.contains('*'), isFalse, reason: '「$hint」含 markdown 星号');
    for (final w in _kBannedDirWords) {
      expect(hint.contains(w), isFalse, reason: '「$hint」含方向词「$w」');
    }
  });

  // ══════════════════════════════════════════════════════════════════
  //  A7. 改输入未重算（stale）：尾注还在（只认有没有结果），按 K 照常跳
  // ══════════════════════════════════════════════════════════════════

  testWidgets('A7·改输入未重算：尾注还在、按 K 仍跳（stale 不影响键）',
      (tester) async {
    await pump9331(tester);
    await compute(tester, '计算比例');
    final field = find.byType(TextField).first;
    await tester.ensureVisible(field);
    await tester.pumpAndSettle();
    await tester.enterText(field, 'AABB');
    await releaseFocus(tester);

    // 存题走 stale 门（剔除旧结果），但**屏上那一节没动**（旧结果还在屏上，
    // 尾注也还在）⇒ 尾注必须照旧在屏（它只认 `_result != null` 那一支，
    // 不认 stale）；K 的判据是考点有卡，stale 本来就不影响它。
    expect(find.text('$_kDihybridSubtitle$_kHintSuffix'), findsOneWidget,
        reason: '改输入不重算时结果区仍是旧结果那一支 ⇒ 尾注照旧在屏');
    await pressK(tester);
    expect(find.byType(BigQuestionCardsPage), findsOneWidget,
        reason: 'A7：stale 状态下按 K 照常跳（键判据与重算状态解耦）');
  });
}
