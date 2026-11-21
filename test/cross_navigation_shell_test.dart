// cross_navigation_shell_test.dart —— 9331 ⇄ 系谱的真实导航壳验收
//
// 防回到历史事故：跨模块跳转不得 Navigator.push、不得吃掉常驻 Rail，
// 且正向/反向都必须可再次返回，不需要重启应用。

import 'package:biology/main.dart';
import 'package:biology/pages/cross_calculator_page.dart';
import 'package:biology/pages/genetic_pedigree_page.dart';
import 'package:biology/state/theme_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/ready_app.dart';

void main() {
  testWidgets('9331 ⇄ 系谱：Rail 常驻、路由不压栈、双向均可返回', (t) async {
    t.view.physicalSize = const Size(1400, 1100);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    final c = ThemeController.instance;
    await t.runAsync(() => c.debugEnsureLoaded());
    c.debugSetMode(ThemeMode.light);
    addTearDown(() => c.debugSetMode(ThemeMode.system));

    await pumpReadyBiologyApp(t);
    final rail9331 = find.descendant(
      of: find.byType(NavigationRail),
      matching: find.text('9331'),
    );
    expect(rail9331, findsOneWidget);
    await t.tap(rail9331);
    await t.pumpAndSettle();

    await t.tap(find.text('系谱展开'));
    await t.pumpAndSettle();
    expect(t.widget<IndexedStack>(find.byType(IndexedStack)).index, 1);
    expect(
      find.byType(NavigationRail),
      findsOneWidget,
      reason: '跳转到系谱后全局 Rail 必须继续可见',
    );
    expect(find.text('来自遗传计算器 · 点击返回9331页'), findsOneWidget);
    final pedigree = t.state(find.byType(GeneticPedigreePage)) as dynamic;
    expect(pedigree.debugCrossP1, 'AaBb', reason: '右侧杂交面板也要看到同一道原题');
    expect(pedigree.debugCrossP2, 'AaBb');
    expect(
      t.state<NavigatorState>(find.byType(Navigator).first).canPop(),
      isFalse,
      reason: '跨页只切 IndexedStack，不 push 新路由',
    );

    // 系谱参考条显式回程：只切页，9331 原题仍保留；同时生成反方向横幅。
    await t.tap(find.text('返回 9331'));
    await t.pumpAndSettle();
    expect(t.widget<IndexedStack>(find.byType(IndexedStack)).index, 2);
    expect(find.byType(NavigationRail), findsOneWidget);
    expect(find.text('来自遗传图谱计算 · 点击返回遗传图谱页'), findsOneWidget);
    expect(
      find.byType(SnackBar),
      findsNothing,
      reason: '旧页提示不得跨页残留并压住 9331 结果',
    );
    expect(find.widgetWithText(TextField, '亲本 1'), findsOneWidget);
    expect(
      t
          .widget<TextField>(find.widgetWithText(TextField, '亲本 1'))
          .controller!
          .text,
      'AaBb',
      reason: '回程不得清空或重填 9331 原输入',
    );
    final scrolls = t.widgetList<SingleChildScrollView>(
      find.descendant(
        of: find.byType(CrossCalculatorPage),
        matching: find.byType(SingleChildScrollView),
      ),
    );
    expect(
      scrolls.any((s) => s.padding is EdgeInsets &&
          (s.padding! as EdgeInsets).right == 112 &&
          (s.padding! as EdgeInsets).bottom == 96),
      isTrue,
      reason: '宽屏结果区要给右下 FAB 列留出横向净空',
    );

    // 顶部横幅还能再回系谱，证明不是只能返回一次的单向桥。
    await t.tap(find.text('来自遗传图谱计算 · 点击返回遗传图谱页'));
    await t.pumpAndSettle();
    expect(t.widget<IndexedStack>(find.byType(IndexedStack)).index, 1);
    expect(find.byType(NavigationRail), findsOneWidget);
  });
}
