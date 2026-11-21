// theme_switch_deep_widget_test.dart —— v2.19.23 深层 const 去冻结端到端回归
//
// 背景：v2.19.20 只修了杂交面板迷你块一处 const 冻结；本轮（v2.19.23）
// 用常量校验脚本系统性扫出 37 处「消费 AppColors/AppText 的项目 widget
// 被 const 实例化」并全部去 const。本测试端到端验证修复：
// 完整 BiologyApp 首帧（dark）→ 锁 light → 导航到含深层 widget 的页 →
// 断言深层 widget（此前 const 的 _VariantRow/RatioPill/StepCard 等）的
// 显式 token 颜色跟随主题。修复前这些深层 widget 会永久冻结 inkD 米白。

import 'package:biology/main.dart';
import 'package:biology/state/theme_controller.dart';
import 'package:biology/theme.dart';
import 'package:flutter/material.dart';
// v2.22.0：套路卡从主导航撤下独立入口 ⇒ 改用数字键直达 pageIndex 8
// （LogicalKeyboardKey 在 services 里，material 不导出）。
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/ready_app.dart';

void main() {
  testWidgets('端到端：dark 首帧→锁 light→9331 页深层组件颜色必须渲染深墨',
      (t) async {
    t.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    addTearDown(() => t.platformDispatcher.clearPlatformBrightnessTestValue);
    t.view.physicalSize = const Size(1400, 900);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);

    final c = ThemeController.instance;
    await t.runAsync(() => c.debugEnsureLoaded());
    c.debugSetMode(ThemeMode.system); // 首帧：system + 平台 dark
    addTearDown(() => c.debugSetMode(ThemeMode.system));

    await pumpReadyBiologyApp(t);
    expect(AppColors.isDark, isTrue, reason: '首帧应为深色');

    c.debugSetMode(ThemeMode.light);
    await t.pumpAndSettle();

    // 导航到 9331 页（Rail 标签）
    final railLabel = find.descendant(
      of: find.byType(NavigationRail),
      matching: find.text('9331'),
    );
    await t.tap(railLabel.first);
    await t.pumpAndSettle();

    // 深层组件断言：变式速查区「标准 9:3:3:1」标题文本（_VariantRow 内，
    // v2.19.23 前被 const 实例化 → 冻结 inkD）。改后必须 inkL。
    final target = find.text('标准 9:3:3:1（两对等位基因独立分配）');
    expect(target, findsOneWidget, reason: '变式速查行应存在');
    final widget = t.widget<Text>(target);
    expect(widget.style?.color, AppColors.inkL,
        reason: '深层 const 修复后必须渲染浅色墨灰；冻结时此处为 inkD 米白');
  });

  // v2.19.25：新页「大题套路卡」纳入同一端到端断言——口诀正文
  // （Text.rich，样式 = AppText.body.copyWith(color: AppColors.ink)）
  // 锁 light 后必须渲染 inkL 而非首帧残留的 inkD。
  testWidgets('端到端：dark 首帧→锁 light→套路卡口诀颜色必须渲染深墨',
      (t) async {
    t.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    addTearDown(() => t.platformDispatcher.clearPlatformBrightnessTestValue);
    t.view.physicalSize = const Size(1400, 900);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);

    final c = ThemeController.instance;
    await t.runAsync(() => c.debugEnsureLoaded());
    c.debugSetMode(ThemeMode.system);
    addTearDown(() => c.debugSetMode(ThemeMode.system));

    await pumpReadyBiologyApp(t);
    expect(AppColors.isDark, isTrue, reason: '首帧应为深色');

    c.debugSetMode(ThemeMode.light);
    await t.pumpAndSettle();

    // 导航到套路卡页（pageIndex 8）。
    // v2.22.0：套路卡已从**主导航 / 首页**撤下独立入口，Rail 上不再有
    // 「套路卡」标签 ⇒ 改用数字键 9 直达（Shortcuts 表：digit9 → 索引 8，
    // 深链能力保留）。本用例**不删**——深层 const 冻结的巡检价值不变。
    await t.sendKeyEvent(LogicalKeyboardKey.digit9);
    await t.pumpAndSettle();
    expect(
      t.widget<IndexedStack>(find.byType(IndexedStack)).index,
      8,
      reason: '数字键 9 应直达套路卡页（pageIndex 8）',
    );

    // 口诀块（「一句话背下来：」+ 口诀）整体是 Text.rich，
    // textContaining 命中其 plainText。
    final target = find.textContaining('无中生有为隐性，有中生无为显性');
    expect(target, findsOneWidget, reason: '首卡口诀应存在');
    final widget = t.widget<Text>(target);
    expect(widget.style?.color, AppColors.inkL,
        reason: '锁 light 后口诀必须渲染浅色墨灰；冻结时此处为 inkD 米白');
  });
}
