// v21968_k_key_inapp_test.dart —— v2.19.68 「按 K 看这道题的套路卡」真实壳内探针
//
// 背景（P2-2 看官裁定复核）：K 快捷键在 v2.19.59 已实现
// （CardLinkKeyHost 挂在 CrossCalculatorPage 容器页，card_link_key_9331_test
// 13 例全绿——但那个 harness 泵的是**裸页面**，没有 HomeShell 的
// PageActivationScope/PageActivationMarker 闸与 Shortcuts 表）。看官实测
// "提示不兑现"，本文件补真实壳内的接线证明：BiologyApp → digit3 切到
// 9331 → 计算出结果 → 按 K → 套路卡页真的被 push（IndexedStack 里
// 常驻的那实例之外多出第二实例 = 新路由）。
//
// 若本探针全绿，则"提示不兑现"为现场环境因素（焦点在输入框时 K 让路
// 是设计语义 / 中文输入法吞键），不属代码缺陷——修复动作是"证明 + 留
// 守卫网"，不再另造一套跳转。

import 'dart:io';

import 'package:biology/main.dart';
import 'package:biology/pages/big_question_cards_page.dart';
import 'package:biology/state/first_run_store.dart';
import 'package:biology/state/present_mode_controller.dart';
import 'package:biology/state/theme_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory tmp;
  late String filePath;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('v21968_k_inapp');
    filePath = '${tmp.path}/first_run.json';
    FirstRunStore.debugFilePath = filePath;
    FirstRunStore.debugWebStorage = null;
    FirstRunStore.debugForceIsWebStorage = false;
    FirstRunStore.instance.debugReset();
    File(filePath).writeAsStringSync('{"role":"student"}');
    // K 触发成功会走 ShortcutNudge.maybeNotify——先标已示，免 SnackBar
    // 噪音（card_link_key_9331_test 同款）。
    FirstRunStore.instance.markShortcutNudgeShown();
  });

  tearDown(() {
    FirstRunStore.debugFilePath = null;
    FirstRunStore.debugWebStorage = null;
    FirstRunStore.debugForceIsWebStorage = null;
    FirstRunStore.instance.debugReset();
    PresentModeController.instance.debugSetEnabled(false);
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  testWidgets('真实壳：digit3 → 9331 算出结果（尾注在屏）→ 按 K 推入套路卡',
      (tester) async {
    tester.view.physicalSize = const Size(1280, 860);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.runAsync(() async {
      await ThemeController.instance.debugEnsureLoaded();
      await PresentModeController.instance.debugEnsureLoaded();
    });
    PresentModeController.instance.debugSetEnabled(false);
    await tester.pumpWidget(const BiologyApp());
    await tester.pumpAndSettle();

    // IndexedStack 常驻：壳里本来就有一枚套路卡页实例（nav 8）。
    // ⚠️ finder 默认 skipOffstage:true，IndexedStack 未选中页视为
    // offstage 被过滤——用 skipOffstage:false 才能看到常驻实例。
    expect(find.byType(BigQuestionCardsPage, skipOffstage: false),
        findsOneWidget,
        reason: '前提：套路卡页常驻 IndexedStack（nav 8）');

    // 数字键 3 → 主导航第 2 项（9331，Shortcuts 表同款路径）。
    await tester.sendKeyEvent(LogicalKeyboardKey.digit3);
    await tester.pumpAndSettle();

    // 算出结果 ⇒ 结果区副标题带「按 K 看这道题的套路卡」尾注。
    final calc = find.text('计算比例');
    expect(calc, findsOneWidget, reason: '9331 页签计算按钮在屏');
    await tester.ensureVisible(calc);
    await tester.pump();
    await tester.tap(calc);
    await tester.pumpAndSettle();
    expect(find.textContaining('按 K 看这道题的套路卡'), findsOneWidget,
        reason: '前提：结果区尾注在屏（提示印得出 ⇒ 键必跳的同一判据）');

    // 交还焦点（计算按钮的 InkWell 焦点不拦 K；EditableText 才拦），
    // 按 K → 套路卡页被 push = 常驻实例之外多出第二实例。
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.keyK);
    await tester.pumpAndSettle();
    expect(find.byType(BigQuestionCardsPage, skipOffstage: false),
        findsNWidgets(2),
        reason: '真实 HomeShell 壳内按 K 必须推入套路卡路由'
            '（IndexedStack 常驻 1 枚 + push 1 枚 = 2）');
  });
}
