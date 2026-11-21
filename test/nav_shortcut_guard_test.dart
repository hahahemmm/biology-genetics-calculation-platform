// nav_shortcut_guard_test.dart —— v2.19.26 数字键守卫回归（定谳转正）
//
// 事故（三找茬代理交叉 P1 + widget 实测定谳）：旧守卫
// `focus.context.widget is EditableText` 恒 false——TextField 的焦点
// 挂在内部 Focus widget 上，输入框里敲「9331」按到第 2 个键就把
// 整页切走（套路卡搜索框首当其冲）。修复 = 祖先查找 EditableText。
// 本测试锁两条语义：聚焦输入框按数字键不切页；无输入框焦点时
// 数字键导航仍可用（守卫不是全禁）。

import 'package:biology/main.dart';
import 'package:biology/state/first_run_store.dart';
import 'package:biology/state/theme_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> pumpApp(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.runAsync(() => ThemeController.instance.debugEnsureLoaded());
    await FirstRunStore.instance.setRole(UserRole.student);
    addTearDown(FirstRunStore.instance.debugReset);
    await tester.pumpWidget(const BiologyApp());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  testWidgets('聚焦输入框时按数字键不切页（守卫祖先查找版）', (tester) async {
    await pumpApp(tester);

    // 切到分子页（index 5）。
    await tester.tap(find.descendant(
        of: find.byType(NavigationRail), matching: find.text('分子')).first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    // 聚焦输入框。
    await tester.tap(find.byType(TextField).first);
    await tester.pump();
    expect(FocusManager.instance.primaryFocus?.context != null &&
        FocusManager.instance.primaryFocus!.context!
                .findAncestorWidgetOfExactType<EditableText>() !=
            null, isTrue, reason: '前置：焦点确在输入框内（祖先可查）');

    // 输入框里敲 9331 的首键——守卫成立则页不动。
    await tester.sendKeyEvent(LogicalKeyboardKey.digit3);
    await tester.pump();
    expect(tester.widget<IndexedStack>(find.byType(IndexedStack)).index, 5,
        reason: '输入框聚焦时按数字键不得切页（旧守卫恒失效事故回归）');
  });

  testWidgets('无输入框焦点时数字键导航仍可用（守卫非全禁）', (tester) async {
    await pumpApp(tester);
    // 首帧焦点在 app 级 Focus(autofocus)，不在任何输入框。
    await tester.sendKeyEvent(LogicalKeyboardKey.digit6); // → index 5 分子
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.widget<IndexedStack>(find.byType(IndexedStack)).index, 5,
        reason: '非输入框焦点下 digit6 → 分子页（index 5）');
  });
}
