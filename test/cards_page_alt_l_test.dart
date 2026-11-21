// cards_page_alt_l_test.dart —— v2.19.60 套路卡页 `Alt + L`（去练）键盘入口守卫网
//
// ## 这条网守什么
// 屏上那枚「去练」按钮（`_cardDetail` 里的 `OutlinedButton.icon`）有了键盘入口：
// 学生按住 `Alt` 再按 `L` 就进那枚按钮要去的地方，与鼠标点它**完全同一条**
// `_openLink`。判据 = `_hasPracticeLink(card)`（当前卡**屏上真有**那枚按钮），
// ⛔ 不是 `linkModuleId != null`（后者只是 `_openLink` 体内第一条深链分支）。
//
// ## 断言分组
//   A1 出厂卡按 `Alt + L` → 回退 `onOpenTool`（测试未注册深链 target 时）
//   A2 按一次只跳一次（合成器发不出 KeyRepeat，repeat 由 KeyDownEvent 类型闸守）
//   A3 焦点在输入框里让路 / 失焦后同一枚键必跳（成对）
//   A4 裸 L / Ctrl+L / Meta+L 都不认领
//   D1 源码级：判据单一真相（按钮处 / 键处同调 `_hasPracticeLink`，无第二份）
//   D2 数据级：出厂 14 张卡全部有练习入口（⛔ 将来出现「只配一半」的卡就红）
//
// ## ⛔ D2 的诚实记账（照抄 B 仓 v2.19.252 的处置）
// 「没有练习入口 ⇒ 不认领」这条负向分支**在出厂数据上根本不可达**（14 张卡
// 全配齐）⇒ 本轮**没有端到端验证过**它。D2 把该事实钉成断言：将来出现没有
// 练习入口的卡时这条红，那时才需要补负向用例。

import 'dart:io';

import 'package:biology/data/big_question_cards.dart';
import 'package:biology/pages/big_question_cards_page.dart';
import 'package:biology/state/first_run_store.dart';
import 'package:biology/ui/module_fill.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// 屏上那句尾注（禁 markdown 星号、禁方向词）。
const String _kHint = '按 Alt+L 去练';

/// ⛔ 方向词黑名单（与 `card_link_key_9331_test.dart` 同款，一个字都不放宽）。
const List<String> _kBannedDirWords = <String>[
  '上面', '下面', '上边', '下边', '左边', '右边', //
  '左侧', '右侧', '上方', '下方', '上一行', '下一行',
];

/// 按 `Alt + L`（宿主读的是 KeyDownEvent；修饰键精确 Alt）。
Future<void> _altL(WidgetTester t) async {
  await t.sendKeyDownEvent(LogicalKeyboardKey.alt);
  await t.sendKeyEvent(LogicalKeyboardKey.keyL);
  await t.sendKeyUpEvent(LogicalKeyboardKey.alt);
  await t.pumpAndSettle();
}

/// 按住修饰键再按 L。
Future<void> _modL(WidgetTester t, LogicalKeyboardKey mod) async {
  await t.sendKeyDownEvent(mod);
  await t.sendKeyEvent(LogicalKeyboardKey.keyL);
  await t.sendKeyUpEvent(mod);
  await t.pumpAndSettle();
}

void main() {
  late Directory tmp;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('cards_alt_l');
    FirstRunStore.debugFilePath = '${tmp.path}/first_run.json';
    FirstRunStore.debugWebStorage = null;
    FirstRunStore.debugForceIsWebStorage = false;
    FirstRunStore.instance.debugReset();
    // 一次性指引已在 setUp 标过 ⇒ 本文件不掺 SnackBar 噪音。
    FirstRunStore.instance.markShortcutNudgeShown();
    // 深链总线清空 ⇒ fill 必然返回 false ⇒ 走 onOpenTool 回退分支（可断言）。
    ModuleFillBus.resetForTest();
  });

  tearDown(() {
    ModuleFillBus.resetForTest();
    FirstRunStore.debugFilePath = null;
    FirstRunStore.debugWebStorage = null;
    FirstRunStore.instance.debugReset();
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  Future<void> pumpCards(WidgetTester t, {void Function(int)? onOpenTool}) async {
    await t.pumpWidget(MaterialApp(
      home: BigQuestionCardsPage(onOpenTool: onOpenTool),
    ));
    await t.pumpAndSettle();
  }

  // ══════════════════════════════════════════════════════════════════
  //  A1. 出厂卡（linkModuleId 非空的第一张 = 首张）按 Alt+L → 去练
  // ══════════════════════════════════════════════════════════════════
  testWidgets('A1·出厂首卡按 Alt+L：回退 onOpenTool（与该卡 linkNavIndex 一致）',
      (tester) async {
    // 前提：屏上默认卡 = 首章首卡，且它是「linkModuleId 非空的第一张」。
    final first = bigQuestionChapters[0].cards[0];
    expect(first.linkModuleId, isNotNull,
        reason: '前提：首张卡有深链 moduleId（出厂数据）');
    expect(first.linkLabel, isNotNull);
    final nav = first.linkNavIndex;
    expect(nav, isNotNull, reason: '前提：首张卡有回退导航索引');

    final got = <int>[];
    await pumpCards(tester, onOpenTool: got.add);

    expect(find.text(_kHint), findsOneWidget, reason: '屏上应印「$_kHint」');

    await _altL(tester);
    expect(got, [nav], reason: 'A1：Alt+L 必须与点那枚「去练」按钮同一条路');
  });

  // ══════════════════════════════════════════════════════════════════
  //  A2. 按一次只跳一次（合成器发不出 repeat ⇒ repeat 由类型闸守，非端到端）
  // ══════════════════════════════════════════════════════════════════
  testWidgets('A2·按一次 Alt+L 只跳一次', (tester) async {
    final got = <int>[];
    await pumpCards(tester, onOpenTool: got.add);

    await _altL(tester);
    // ⛔ 诚实记账：测试合成器发不出 KeyRepeatEvent（长按连发），
    // 本用例只证「一次物理按键 = 一次应答」；repeat 由宿主
    // `if (event is! KeyDownEvent) return false` 那道类型闸守住（读源码）。
    expect(got.length, 1, reason: '一次 Alt+L ⇒ 恰好一次跳转');
  });

  // ══════════════════════════════════════════════════════════════════
  //  A3. 焦点闸成对：输入框持焦让路 / 失焦必跳
  // ══════════════════════════════════════════════════════════════════
  testWidgets('A3·焦点在搜索框里按 Alt+L 让路；失焦后同一枚键必跳', (tester) async {
    final got = <int>[];
    await pumpCards(tester, onOpenTool: got.add);

    final field = find.byType(TextField).first;
    await tester.ensureVisible(field);
    await tester.pumpAndSettle();
    await tester.tap(field);
    await tester.pump();
    final focus = FocusManager.instance.primaryFocus;
    expect(focus?.context?.findAncestorWidgetOfExactType<EditableText>(),
        isNotNull,
        reason: '前提：焦点确实挂在 EditableText 里');

    await _altL(tester);
    expect(got, isEmpty, reason: '持焦让路：敲到一半的搜索词里按 L 是输入的一部分');

    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump();
    await _altL(tester);
    expect(got.length, 1,
        reason: '守卫成对：失焦后同一枚键必须跳（否则「看着有快捷键、按了没反应」）');
  });

  // ══════════════════════════════════════════════════════════════════
  //  A4. 修饰键精确：裸 L / Ctrl+L / Meta+L 都不认领
  // ══════════════════════════════════════════════════════════════════
  testWidgets('A4·裸 L / Ctrl+L / Meta+L 都不触发', (tester) async {
    final got = <int>[];
    await pumpCards(tester, onOpenTool: got.add);

    await tester.sendKeyEvent(LogicalKeyboardKey.keyL);
    await tester.pumpAndSettle();
    expect(got, isEmpty, reason: '裸 L 不认领（放映层课堂聚光灯用的是裸 L）');

    await _modL(tester, LogicalKeyboardKey.controlLeft);
    expect(got, isEmpty, reason: 'Ctrl+L 不认领');

    await _modL(tester, LogicalKeyboardKey.metaLeft);
    expect(got, isEmpty, reason: 'Meta+L 不认领');

    // 反向成对：同一枚键加 Alt 必跳（否则上面三条是空断言）。
    await _altL(tester);
    expect(got.length, 1, reason: '对照：Alt+L 必跳');
  });

  // ══════════════════════════════════════════════════════════════════
  //  D1. 源码级：判据单一真相（按钮处 / 键处同调 _hasPracticeLink，无第二份）
  // ══════════════════════════════════════════════════════════════════
  test('D1·源码级：按钮条件与键认领共用 _hasPracticeLink，无第二份判据', () {
    final src =
        File('lib/pages/big_question_cards_page.dart').readAsStringSync();

    // ① 按钮的渲染条件改成调 _hasPracticeLink（不是内联判据）。
    expect(src.contains('if (_hasPracticeLink(card))'), isTrue,
        reason: 'D1①：按钮条件必须调 _hasPracticeLink');
    // ② 键宿主的认领判据也调它（按下那刻现取屏上卡）。
    expect(src.contains('_hasPracticeLink(_visibleCard())'), isTrue,
        reason: 'D1②：键认领必须与按钮同源');
    // ③ 内联的旧判据必须**消失**（否则就是第二份真相的开端）。
    expect(src.contains('if (card.linkLabel != null'), isFalse,
        reason: 'D1③：不许再有内联判据');
    // ④ 键位文案常量存在（唯一一处定义）。
    expect(src.contains("static const String keyLabel = 'Alt + L'"), isTrue);

    // ⑤ 屏上提示文案零 markdown 星号、零方向词。
    final m = RegExp(r"Text\('(按 [^']*去练)'").firstMatch(src);
    expect(m, isNotNull, reason: 'D1⑤：屏上提示常量还在');
    final hint = m!.group(1)!;
    expect(hint.contains('*'), isFalse, reason: '「$hint」含 markdown 星号');
    for (final w in _kBannedDirWords) {
      expect(hint.contains(w), isFalse, reason: '「$hint」含方向词「$w」');
    }
  });

  // ══════════════════════════════════════════════════════════════════
  //  D2. 数据级：出厂 14 张卡全部有练习入口（见文件头诚实记账）
  // ══════════════════════════════════════════════════════════════════
  test('D2·出厂 14 张卡全部 _hasPracticeLink（出现缺口的卡就该补负向用例）', () {
    final cards = bigQuestionChapters.expand((c) => c.cards).toList();
    expect(cards.length, 14, reason: '前提：出厂 14 张卡');
    for (final c in cards) {
      expect(c.linkLabel != null && c.linkNavIndex != null, isTrue,
          reason: '${c.id} 今天必须有练习入口——一旦此条红，说明出现了'
              '「没有练习入口 ⇒ Alt+L 不认领」这条**本轮未端到端覆盖**的'
              '负向分支，那时请补一条负向用例'); 
    }
  });
}
