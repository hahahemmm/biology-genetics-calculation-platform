// nav_extended_rail_test.dart —— v2.21.0 宽档文字侧栏阈值守卫
import 'dart:io';

import 'package:biology/main.dart';
import 'package:biology/state/first_run_store.dart';
import 'package:biology/state/present_mode_controller.dart';
import 'package:biology/state/theme_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory tmp;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('nav_extended_rail');
    FirstRunStore.debugFilePath = '${tmp.path}/first_run.json';
    File(FirstRunStore.debugFilePath!)
        .writeAsStringSync('{"role":"student","nudge":true}');
    FirstRunStore.debugWebStorage = null;
    FirstRunStore.debugForceIsWebStorage = false;
    FirstRunStore.instance.debugReset();

    ThemeController.debugFilePath = '${tmp.path}/theme.json';
    ThemeController.instance.debugReset();
    PresentModeController.debugFilePath = '${tmp.path}/present.json';
    PresentModeController.instance.debugReset();
  });

  tearDown(() {
    FirstRunStore.debugFilePath = null;
    FirstRunStore.debugWebStorage = null;
    FirstRunStore.debugForceIsWebStorage = null;
    FirstRunStore.instance.debugReset();
    ThemeController.debugFilePath = null;
    ThemeController.instance.debugReset();
    PresentModeController.debugFilePath = null;
    PresentModeController.instance.debugReset();
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  Future<void> pumpShell(WidgetTester tester, Size size) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.runAsync(() async {
      await ThemeController.instance.debugEnsureLoaded();
      await PresentModeController.instance.debugEnsureLoaded();
    });
    ThemeController.instance.debugSetMode(ThemeMode.light);
    PresentModeController.instance.debugSetEnabled(false);
    await tester.pumpWidget(const BiologyApp());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
  }

  testWidgets('@1280：展开单栏文字侧栏与品牌区', (tester) async {
    await pumpShell(tester, const Size(1280, 900));
    final rail = tester.widget<NavigationRail>(find.byType(NavigationRail));
    expect(rail.extended, isTrue);
    expect(rail.labelType, NavigationRailLabelType.none);
    expect(rail.scrollable, isTrue);
    expect(find.byKey(const Key('navigation_brand')), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(NavigationRail),
        matching: find.text('遗传计算工作台'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byType(NavigationRail),
        matching: find.text('关于'),
      ),
      findsOneWidget,
      reason: 'extended 下文字标签仍持续显示，不是折叠导航',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('@800：回到紧凑 Rail，不占系谱画布宽度', (tester) async {
    await pumpShell(tester, const Size(800, 900));
    final rail = tester.widget<NavigationRail>(find.byType(NavigationRail));
    expect(rail.extended, isFalse);
    expect(rail.labelType, NavigationRailLabelType.all);
    expect(rail.scrollable, isTrue);
    expect(find.byKey(const Key('navigation_brand')), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
