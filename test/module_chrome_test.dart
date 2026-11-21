// 全模块巡航回归：没有本地工具抽屉的页面不得出现跨页改状态的死 ☰。

import 'package:biology/main.dart';
import 'package:biology/pages/genetic_disease_page.dart';
import 'package:biology/pages/variation_page.dart';
import 'package:biology/state/theme_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/ready_app.dart';

void main() {
  testWidgets('变异与遗传病页不渲染无效工具面板按钮', (t) async {
    t.view.physicalSize = const Size(1400, 900);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    final theme = ThemeController.instance;
    await t.runAsync(() => theme.debugEnsureLoaded());
    theme.debugSetMode(ThemeMode.light);
    addTearDown(() => theme.debugSetMode(ThemeMode.system));
    await pumpReadyBiologyApp(t);

    final cases = <String, Type>{
      '变异': VariationPage,
      '遗传病': GeneticDiseasePage,
    };
    for (final entry in cases.entries) {
      await t.tap(find.descendant(
        of: find.byType(NavigationRail),
        matching: find.text(entry.key),
      ));
      await t.pumpAndSettle();
      final appBar = find.descendant(
        of: find.byType(entry.value),
        matching: find.byType(AppBar),
      );
      expect(appBar, findsOneWidget);
      expect(
        find.descendant(of: appBar, matching: find.byTooltip('工具面板')),
        findsNothing,
        reason: '${entry.key}页没有本地抽屉，不能显示跨页偷改系谱状态的 ☰',
      );
    }
  });
}
