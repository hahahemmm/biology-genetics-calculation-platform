// curriculum_jump_test.dart —— v2.2 课标页工具 chip 双向跳转验收
//
// 修复前：chip 走 Navigator.push 新开路由页——跳过去后没有显性回程
// （桌面宽屏下路由页无 Rail，返回箭头不显眼），用户报"单向跳转"。
// 修复后：
//   1. chip 经 HomeShell 回调切导航索引（页面内跳转，不压路由栈）；
//   2. 目标页顶部出现「返回课标」横幅，点击跳回；
//   3. Rail「课标」同样可跳回（Rail 常驻 = 天然双向）。

import 'package:biology/main.dart';
import 'package:biology/state/theme_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/ready_app.dart';

void main() {
  testWidgets('课标 chip：页面内跳转（不压栈）+ 返回课标横幅双向回程', (t) async {
    // 超高视口：课标列表全量构建，chip 直接可见可点，避免 ListView
    // 懒挂载滚动链路的脆弱性（同 lightwhite_repro 既有模式）。
    t.view.physicalSize = const Size(1400, 5200);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);

    // ThemeController.load() 真实 I/O 竞态防护（既有模式）：
    // 先确保加载完成再泵，避免磁盘值覆盖测试模式。
    final c = ThemeController.instance;
    await t.runAsync(() => c.debugEnsureLoaded());
    c.debugSetMode(ThemeMode.light);
    addTearDown(() => c.debugSetMode(ThemeMode.system));

    await pumpReadyBiologyApp(t);

    // 导航到课标页
    final railLabel = find.descendant(
      of: find.byType(NavigationRail),
      matching: find.text('课标'),
    );
    expect(railLabel, findsWidgets, reason: '宽屏应有 Rail 标签「课标」');
    await t.tap(railLabel.first);
    await t.pumpAndSettle();
    expect(find.text('课标 · 遗传与进化'), findsOneWidget);

    // v2.19.28 UI 统一：3.3.4 收在关键概念 3.3 下——先点左栏概念渲染条目。
    await t.tap(find.text('可遗传的变异（突变/重组/染色体变异）'));
    await t.pumpAndSettle();

    // 点 chip「连锁互换 + 9331」（3.3.4 条目）
    final chip = find.textContaining('连锁互换 + 9331');
    expect(chip, findsOneWidget, reason: '超高视口下课标全列表应一次构建');
    await t.tap(chip);
    await t.pumpAndSettle();

    // ① 跳到了 9331 页。
    // ⚠️ v2.19.35：3.3.4 现在带**正向深链**（`cross_linkage` +
    // `{p1:'AB/ab', p2:'ab/ab', r:'10%'}`，见 `curriculum_2020.dart`）⇒ 落点
    // 从「出厂第 0 个页签（双基因 9:3:3:1）」改成**连锁互换**页签并带上示范题
    // ——chip 上写「连锁互换」，屏上就该是连锁互换。
    // 原来那句 `find.text('常见 9331 变式速查')` 钉的是**双基因页签专属**的一节
    // （`cross_calculator_page.dart` 的 dihybrid 结果区），本轮随落点一起换掉：
    // 「亲本型」只在连锁互换页签算完后渲染 ⇒ 它同时钉住「切对了页签」+「算过了」。
    expect(find.text('遗传计算器'), findsOneWidget, reason: 'chip 应切到 9331 页');
    expect(find.text('亲本型'), findsWidgets,
        reason: '深链必须把示范题带进连锁互换页签并算出结果');
    // 页面内跳转：不压路由栈（push 会 canPop=true）
    final nav = t.state<NavigatorState>(find.byType(Navigator).first);
    expect(nav.canPop(), isFalse,
        reason: 'chip 跳转不得 push 新路由（叠栈/多窗口隐患），'
            '必须走 HomeShell 切导航索引');
    // ③ 回程横幅出现
    expect(find.text('来自课标 · 点击返回课标页'), findsOneWidget,
        reason: '跳转后应显示「返回课标」横幅');

    // ④ 点横幅 → 回到课标页，横幅消失
    await t.tap(find.text('来自课标 · 点击返回课标页'));
    await t.pumpAndSettle();
    expect(find.text('课标 · 遗传与进化'), findsOneWidget,
        reason: '点横幅应跳回课标页');
    expect(find.text('来自课标 · 点击返回课标页'), findsNothing,
        reason: '回到课标后横幅应消失');

    // ⑤ Rail 回程路径：再次跳出，点 Rail「课标」同样跳回且横幅清除
    await t.tap(chip);
    await t.pumpAndSettle();
    expect(find.text('遗传计算器'), findsOneWidget);
    expect(find.text('亲本型'), findsWidgets,
        reason: '第二次同样落在连锁互换页签（深链是幂等的）');
    expect(find.text('来自课标 · 点击返回课标页'), findsOneWidget);
    await t.tap(railLabel.first);
    await t.pumpAndSettle();
    expect(find.text('课标 · 遗传与进化'), findsOneWidget,
        reason: 'Rail「课标」应可跳回（常驻 Rail = 天然双向）');
    expect(find.text('来自课标 · 点击返回课标页'), findsNothing,
        reason: '手动导航应清除回程横幅');
  });
}
