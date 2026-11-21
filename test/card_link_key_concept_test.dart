// ════════════════════════════════════════════════════════════════════════
//  test/card_link_key_concept_test.dart
//  v2.19.59：分子 / 进化 / 倍性三页接通「K 看这道题的套路卡」守卫网
// ════════════════════════════════════════════════════════════════════════
//
//  ## 被测接线（三页同款）
//  · 每页 body 挂一枚 `CardLinkKeyHost`（零像素宿主，走
//    HardwareKeyboard.addHandler）：`cardId: () => _linkedCardId` ——
//    **按下那一刻现取**（ToolWorkbench 切页签不让页面 State rebuild，
//    构造参数会滞留已切走页签的考点）。
//  · `_linkedCardId = findCardIdForTopic(_mistakeSubjectArea)`：考点就是
//    该页 Ctrl+S 存题用的那一份（页内状态）——⛔ 不按 `_tab.index` 另行
//    推导（B 仓 v2.19.251 教训：倍性页 3 页签 7 个子计算器）。
//  · 屏上提示句 = 结果区**副标题位**（`FlatSection.subtitle`），条件 =
//    「本节有结果 && `_linkedCardId` 非 null」；无结果 / 无卡 ⇒ 整句不渲染。
//
//  ## 命中词（A 组用例的前提；A0b 逐条钉住）
//  分子页 4 签：碱基组成（DNA 碱基互补）→ jianji-hubu（词「碱基互补」）；
//    复制与标记（半保留复制与密度梯度）→ biaoji-shidai（词「半保留」）；
//    基因表达（6:3:1 与中心法则）→ fanyi-huansuan（词「中心法则」）；
//    配子种类（减数分裂）→ null（表内无「配子种类」类词；「配子法」不是它）。
//  进化页 5 签：基因频率（按个体数计算）→ pinlv-susuan（词「基因频率」）；
//    遗传平衡（哈迪-温伯格预测）→ pingheng-panduan（词「遗传平衡」）；
//    进化树 / 选择模拟 / 进化理论 → null（表内无对应词）。
//  倍性页 3 签：育种应用（单倍体育种·杂交育种·四倍体配子）→
//    danbei-liucheng（词「单倍体」）；组数判断 / 倍性与育性 → null。
//
//  ## 提示句比宿主闸④**严一档**（A2 / A2b 分两条把真实语义钉住）
//  宿主闸④（`card_link_key_host.dart` `_onKey` 源码事实）只看「当前考点
//  有没有配套卡」——**不看有没有算出结果**；提示句还要求本节有结果。
//  ⇒ 未算出结果时按 K 仍会跳（A2 钉住），只有「考点命不中卡」才是无声
//  让路（A2b）。⛔ 本文件不把这条差异当 bug 修——判据函数（`findCardIdForTopic`
//  + `_mistakeSubjectArea`）两处同源，差异只在「有没有结果」这一个加项。
//
//  ## 通道纪律
//  取基准（页签 / 输入 / 结果）一律走鼠标 tap / enterText；被测动作 = 裸 K。
//  · 成功触发 K 会弹一次性「按 ?」指引 SnackBar（4s）⇒ 用例尾部把时钟推过
//    4s，否则报 pending timer（与 shortcut_cheatsheet_test C5 同款）。
//  · 写盘隔离：FirstRunStore 落独立临时目录；BigQuestionCardsStore 在
//    FLUTTER_TEST 下自身跳过真盘（见其 `_testSkip`）。

import 'dart:io';

import 'package:biology/data/big_question_cards.dart' show findCardIdForTopic;
import 'package:biology/pages/big_question_cards_page.dart';
import 'package:biology/pages/evolution_page.dart';
import 'package:biology/pages/molecular_page.dart';
import 'package:biology/pages/ploidy_page.dart';
import 'package:biology/pages/widgets/card_link_key_host.dart';
import 'package:biology/state/first_run_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// 屏上提示句。⛔ 按验收文案**硬编码**（不引用被测常量——那样写错文案也
/// 照样绿）；键位文案的唯一真相由 A0 单独钉（`keyLabel == 'K'`）。
const _kHint = '按 K 看这道题的套路卡';

Future<void> pumpPage(WidgetTester tester, Widget page) async {
  tester.view.physicalSize = const Size(800, 800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(MaterialApp(home: page));
  await tester.pump();
}

/// 按裸 K（被测动作）。
Future<void> pressK(WidgetTester tester) async {
  await tester.sendKeyEvent(LogicalKeyboardKey.keyK);
  await tester.pumpAndSettle();
}

/// 把时钟推过一次性指引 SnackBar 的 4s，免得用例结束报 pending timer。
Future<void> drainNudge(WidgetTester tester) async {
  await tester.pumpAndSettle(const Duration(seconds: 5));
}

/// 鼠标通道切页签（异通道基线）。
Future<void> tapTab(WidgetTester tester, String label) async {
  await tester.tap(find.descendant(
      of: find.byType(TabBar), matching: find.text(label)));
  await tester.pumpAndSettle();
}

/// 鼠标通道点计算按钮。
Future<void> tapCalc(WidgetTester tester, String label) async {
  final b = find.text(label);
  expect(b, findsOneWidget, reason: '前提：按钮「$label」在屏');
  await tester.ensureVisible(b);
  await tester.pump();
  await tester.tap(b);
  await tester.pumpAndSettle();
}

void main() {
  late Directory tmp;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('card_link_key');
    // 一次性「按 ?」指引会读/写这个 store ⇒ 隔离到临时目录，绝不碰真盘。
    FirstRunStore.debugFilePath = '${tmp.path}/first_run.json';
    FirstRunStore.debugWebStorage = null;
    FirstRunStore.debugForceIsWebStorage = false;
    FirstRunStore.instance.debugReset();
  });

  tearDown(() {
    FirstRunStore.instance.debugReset();
    FirstRunStore.debugFilePath = null;
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  /// 分子页 tab0「碱基组成」算出结果（沿用既有 Ctrl+S 守卫网同一条路）。
  Future<void> computeMolecularBase(WidgetTester tester) async {
    await tester.enterText(find.byType(TextField).first, '30');
    await tester.pump();
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump();
    await tapCalc(tester, '计算碱基组成');
    expect(find.textContaining('T=30.0%'), findsWidgets,
        reason: '前提：结果已算出（A=30 ⇒ T=30、G=C=20）');
  }

  // ══════════════════════════════════════════════════════════════════
  //  A0. 判据前置：键位文案 + 三页 12 个考点命中哪张卡
  // ══════════════════════════════════════════════════════════════════

  test('A0·键位文案唯一真相：宿主 keyLabel = K（提示句用的就是它）', () {
    expect(CardLinkKeyHost.keyLabel, 'K');
    expect(_kHint, contains(CardLinkKeyHost.keyLabel));
  });

  test('A0b·三页 12 个考点 → 配套卡（命中词见文件头，A 组前提）', () {
    // 分子页 4 签。
    expect(findCardIdForTopic('碱基组成（DNA 碱基互补）'), 'jianji-hubu',
        reason: '命中词「碱基互补」');
    expect(findCardIdForTopic('复制与标记（半保留复制与密度梯度）'), 'biaoji-shidai',
        reason: '命中词「半保留」');
    expect(findCardIdForTopic('基因表达（6:3:1 与中心法则）'), 'fanyi-huansuan',
        reason: '命中词「中心法则」');
    // v2.19.64：配子种类原本命不中（旧断言 isNull）；关键词表加窄词
    // 「配子种类」后命中 peizi-ziyoujiaopei（配子法卡覆盖 2ⁿ 配子计数，
    // 见 test/card_keyword_coverage_test.dart 决定表）。⛔ 没用宽词「配子」
    // ——那会让育种应用的「四倍体配子」从 danbei-liucheng 漂移（实测）。
    expect(findCardIdForTopic('配子种类（减数分裂）'), 'peizi-ziyoujiaopei',
        reason: 'v2.19.64 命中词「配子种类」（窄词，不抢育种应用）');
    // 进化页 5 签。
    expect(findCardIdForTopic('进化树（共同祖先·先导图）'), isNull);
    expect(findCardIdForTopic('基因频率（按个体数计算）'), 'pinlv-susuan',
        reason: '命中词「基因频率」');
    expect(findCardIdForTopic('遗传平衡（哈迪-温伯格预测）'), 'pingheng-panduan',
        reason: '命中词「遗传平衡」');
    expect(findCardIdForTopic('选择模拟（自然选择逐代递推）'), isNull);
    expect(findCardIdForTopic('进化理论（现代生物进化理论）'), isNull);
    // 倍性页 3 签（B 仓 v2.19.251 教训页）。
    expect(findCardIdForTopic('染色体组数判断（形态法与基因型法）'), isNull);
    expect(findCardIdForTopic('倍性判定与育性（三倍体无子西瓜）'), isNull);
    expect(findCardIdForTopic('育种应用（单倍体育种·杂交育种·四倍体配子）'),
        'danbei-liucheng',
        reason: '命中词「单倍体」（同一 entry 里还有「育种」）');
  });

  // ══════════════════════════════════════════════════════════════════
  //  A1. 分子页：①屏上提示句 ②按 K 推入套路卡页
  // ══════════════════════════════════════════════════════════════════

  testWidgets('A1·分子页算出结果：①屏上出提示句 ②按 K 推入套路卡页', (tester) async {
    await pumpPage(tester, const MolecularPage());
    expect(find.text(_kHint), findsNothing, reason: '前提：未算出结果时零提示句');

    await computeMolecularBase(tester);

    expect(find.text(_kHint), findsOneWidget,
        reason: '①：结果区副标题位出「按 K 看这道题的套路卡」'
            '（本用例只算出 1 节 ⇒ 恰好 1 句）');
    await pressK(tester);
    expect(find.byType(BigQuestionCardsPage), findsOneWidget,
        reason: '②：按 K 必须推入套路卡页（现取考点命中 jianji-hubu）');
    await drainNudge(tester);
  });

  // ══════════════════════════════════════════════════════════════════
  //  A2. 未算出结果 / 考点命不中卡——两态的真实语义分开钉
  // ══════════════════════════════════════════════════════════════════

  testWidgets('A2·未算出结果：屏上零提示句；宿主闸④只看考点 ⇒ 按 K 仍跳'
      '（真实语义见文件头）', (tester) async {
    await pumpPage(tester, const MolecularPage());
    expect(find.text(_kHint), findsNothing, reason: '未算出结果 ⇒ 整句不渲染');
    await pressK(tester);
    expect(find.byType(BigQuestionCardsPage), findsOneWidget,
        reason: '分子页 tab0 考点命中 jianji-hubu ⇒ 宿主闸④放行（该闸不看有没有'
            '结果）；「按 K 无导航」的真实语义只在考点命不中卡时成立，见 A2b');
    await drainNudge(tester);
  });

  // v2.19.64：本条原是「配子种类命不中卡」的负向用例（零提示+K 不导航）。
  // 关键词表加窄词「配子种类」后行为契约反转——改写成正向用例钉新契约：
  // 算出结果 ⇒ 提示句在屏，按 K ⇒ 推入配子法卡页。负向语义（命不中⇒
  // 无声让路）由 9331 侧 A3（方法对比页签）继续钉住，不丢覆盖。
  testWidgets('A2b·配子种类（v2.19.64 起有配套卡）：算出结果 ⇒ 提示句在屏、按 K 跳配子法卡',
      (tester) async {
    await pumpPage(tester, const MolecularPage());
    await tapTab(tester, '配子种类');
    await tapCalc(tester, '计算配子种类');
    expect(find.text('2ⁿ = 4 种'), findsOneWidget,
        reason: '前提：tab3 结果已算出（默认 n=2 ⇒ 4 种）');
    expect(find.text(_kHint), findsOneWidget,
        reason: 'v2.19.64：考点「配子种类」命中 peizi-ziyoujiaopei ⇒ 提示句照常在屏');
    await pressK(tester);
    expect(find.byType(BigQuestionCardsPage), findsOneWidget,
        reason: '闸④放行 ⇒ 按 K 推入套路卡页（与提示句同一判据）');
  });

  // ══════════════════════════════════════════════════════════════════
  //  A3. 焦点闸：EditableText 持焦让路 / 失焦必跳（成对）
  // ══════════════════════════════════════════════════════════════════

  testWidgets('A3·焦点在 EditableText 里按 K 不导航；失焦后同一枚键必跳',
      (tester) async {
    await pumpPage(tester, const MolecularPage());
    await computeMolecularBase(tester);
    expect(find.text(_kHint), findsOneWidget, reason: '前提：提示句在屏（可跳态）');

    // 持焦态：把焦点真放进 EditableText（showKeyboard ≡ 学生正在敲这个框）。
    // ⛔ 不许用 tap 拿焦点：本用例前面 tapCalc 的 ensureVisible 会把输入框
    // 滚到 AppBar 底下，tap 的落点被 TabBar 吃掉 ⇒ 焦点根本没进去、
    // 闸③ 拦的是「没焦点」而不是「焦点在输入框里」，用例会**假绿**。
    final field = find.byType(TextField).first;
    await tester.showKeyboard(field);
    await tester.pump();
    final editable = tester.widget<EditableText>(
        find.descendant(of: field, matching: find.byType(EditableText)));
    expect(editable.focusNode.hasFocus, isTrue,
        reason: '前提：焦点确实落在 EditableText 里（否则本用例测不到闸③）');

    await pressK(tester);
    expect(find.byType(BigQuestionCardsPage), findsNothing,
        reason: '闸③：敲到一半的题干里按 K 不跳转（也不得有任何导航）');

    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump();
    await pressK(tester);
    expect(find.byType(BigQuestionCardsPage), findsOneWidget,
        reason: '失焦后同一枚键必跳——证明刚才确系焦点闸拦的');
    await drainNudge(tester);
  });

  // ══════════════════════════════════════════════════════════════════
  //  A4. 进化 / 倍性两页同 A1 的 ①②（三页都要钉）
  // ══════════════════════════════════════════════════════════════════

  testWidgets('A4a·进化页 tab1（基因频率）算出结果：①提示句 ②按 K 推入',
      (tester) async {
    await pumpPage(tester, const EvolutionPage());
    await tapTab(tester, '基因频率');
    expect(find.text(_kHint), findsNothing, reason: '前提：未算出结果时零提示句');

    await tester.enterText(find.byType(TextField).first, '30');
    await tester.pump();
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump();
    await tapCalc(tester, '计算基因频率');
    expect(find.textContaining('A = 50.0%'), findsWidgets,
        reason: '前提：结果已算出（aa=30/Aa=60/AA=30 ⇒ A=50%）');

    expect(find.text(_kHint), findsOneWidget,
        reason: '①：考点「基因频率（按个体数计算）」命中 pinlv-susuan ⇒ 副标题位出提示句');
    await pressK(tester);
    expect(find.byType(BigQuestionCardsPage), findsOneWidget,
        reason: '②：按 K 必须推入套路卡页');
    await drainNudge(tester);
  });

  testWidgets('A4b·倍性页 tab2（育种应用）算出结果：①提示句 ②按 K 推入',
      (tester) async {
    await pumpPage(tester, const PloidyPage());
    await tapTab(tester, '育种应用');
    expect(find.text(_kHint), findsNothing, reason: '前提：未算出结果时零提示句');

    await tapCalc(tester, '列出花粉与加倍结果');
    expect(find.text('花粉（单倍体）'), findsOneWidget,
        reason: '前提：单倍体育种那节的结果已展开（默认亲本 AaBb）');

    expect(find.text(_kHint), findsOneWidget,
        reason: '①：考点「育种应用（单倍体育种·杂交育种·四倍体配子）」命中 '
            'danbei-liucheng ⇒ 副标题位出提示句');
    await pressK(tester);
    expect(find.byType(BigQuestionCardsPage), findsOneWidget,
        reason: '②：按 K 必须推入套路卡页');
    await drainNudge(tester);
  });

  // ══════════════════════════════════════════════════════════════════
  //  A5. 页面级唯一宿主
  // ══════════════════════════════════════════════════════════════════

  testWidgets('A5·三页树里 CardLinkKeyHost 恰好一枚（页面级唯一宿主）',
      (tester) async {
    for (final page in <Widget>[
      const MolecularPage(),
      const EvolutionPage(),
      const PloidyPage(),
    ]) {
      await pumpPage(tester, page);
      expect(find.byType(CardLinkKeyHost), findsOneWidget,
          reason: '${page.runtimeType} 必须恰好挂一枚 K 宿主（同键多宿主会连跳）');
    }
  });
}
