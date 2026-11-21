// v21968_quick_bar_collapse_test.dart —— v2.19.68 课堂快捷条收起把手 + 拍题 FAB 单击提示
//
// 覆盖（GUI 看官 P1 / P2-4 修复回归网）：
//   1. 课堂快捷条展开态：五个功能键 + 收起键全在；
//   2. 点收起 → 只剩 40px 级半透明圆把手，功能键全部离场；
//   3. 点把手 → 展开回完整条（功能零损失）；
//   4. 课堂模式关 → 快捷条（含把手）不渲染；
//   5. 课堂模式拍题 FAB 单击：弹「课堂模式为防误触已关闭单击，请长按
//      拍题」SnackBar（单击静默修复，且只弹一条）；标准模式不弹。
//
// 快捷条直接泵（v27_classroom_bar_test 同款 harness）；FAB 用真实
// BiologyApp（main_test 同款 harness）。

import 'dart:io';

import 'package:biology/main.dart';
import 'package:biology/state/first_run_store.dart';
import 'package:biology/state/present_mode_controller.dart';
import 'package:biology/state/theme_controller.dart';
import 'package:biology/ui/classroom_quick_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  tearDown(() {
    PresentModeController.instance.debugSetEnabled(false);
    PresentModeController.instance.debugSetHighContrast(false);
    PresentModeController.instance.debugSetLaserEnabled(false);
    PresentModeController.instance.debugSetSpotlightOn(false);
  });

  // ── 收起把手（快捷条直接泵）──────────────────────────────────

  Future<void> pumpBar(WidgetTester t) async {
    await t.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Align(
          alignment: Alignment.bottomRight,
          child: ClassroomQuickBar(
            spotlightAvailable: true,
            // 生产路径由 main.dart 注入 push 动作；直泵 harness 给个空
            // 实现，让系谱推断键在树里（六键全量断言）。
            onOpenInference: () {},
          ),
        ),
      ),
    ));
    await t.pump();
  }

  testWidgets('收起把手：展开→收起→展开闭环，功能键零损失', (tester) async {
    final pm = PresentModeController.instance;
    pm.debugSetEnabled(true);
    await pumpBar(tester);

    // 展开态：五个功能键 + 收起键都在；把手不在。
    expect(find.byIcon(Icons.highlight_outlined), findsOneWidget);
    expect(find.byIcon(Icons.contrast_outlined), findsOneWidget);
    expect(find.byIcon(Icons.gps_fixed_outlined), findsOneWidget);
    expect(find.byIcon(Icons.account_tree_outlined), findsOneWidget);
    expect(find.byIcon(Icons.school_outlined), findsOneWidget);
    final collapseBtn = find.byKey(ClassroomQuickBar.collapseKey);
    expect(collapseBtn, findsOneWidget);
    expect(find.byKey(ClassroomQuickBar.handleKey), findsNothing);

    // 收起：功能键全部离场，只剩把手。
    await tester.tap(collapseBtn);
    await tester.pump();
    expect(find.byKey(ClassroomQuickBar.handleKey), findsOneWidget,
        reason: '收起后只剩小圆把手');
    expect(find.byIcon(Icons.contrast_outlined), findsNothing);
    expect(find.byIcon(Icons.school_outlined), findsNothing);

    // 把手 40px 级（半透明底不便于断言，尺寸钉死回归线）。
    final handle = tester.renderObject<RenderBox>(
        find.byKey(ClassroomQuickBar.handleKey));
    expect(handle.size.width, lessThanOrEqualTo(44));
    expect(handle.size.height, lessThanOrEqualTo(44));

    // 展开回完整条：功能键回归（聚光灯可用性延续）。
    await tester.tap(find.byKey(ClassroomQuickBar.handleKey));
    await tester.pump();
    expect(find.byIcon(Icons.contrast_outlined), findsOneWidget);
    expect(find.byIcon(Icons.school_outlined), findsOneWidget);
    expect(find.byKey(ClassroomQuickBar.handleKey), findsNothing);

    // 功能语义在收放闭环后仍然工作（高对比开关真实落 controller）。
    await tester.tap(find.byIcon(Icons.contrast_outlined));
    await tester.pump();
    expect(pm.highContrast, isTrue);
  });

  testWidgets('课堂模式关 → 快捷条（含把手）不渲染', (tester) async {
    PresentModeController.instance.debugSetEnabled(false);
    await pumpBar(tester);
    expect(find.byKey(ClassroomQuickBar.handleKey), findsNothing);
    expect(find.byIcon(Icons.contrast_outlined), findsNothing);
  });

  // ── 拍题 FAB 单击提示（真实 BiologyApp，main_test 同款 harness）──

  late Directory tmp;
  late String filePath;

  Finder scanFabFinder() => find.byWidgetPredicate(
        (w) => w is FloatingActionButton && w.heroTag == 'scanFab',
      );

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('v21968_fab_hint');
    filePath = '${tmp.path}/first_run.json';
    FirstRunStore.debugFilePath = filePath;
    FirstRunStore.debugWebStorage = null;
    FirstRunStore.debugForceIsWebStorage = false;
    FirstRunStore.instance.debugReset();
    File(filePath).writeAsStringSync('{"role":"teacher"}');
  });

  tearDown(() {
    FirstRunStore.debugFilePath = null;
    FirstRunStore.debugWebStorage = null;
    FirstRunStore.debugForceIsWebStorage = null;
    FirstRunStore.instance.debugReset();
  });

  testWidgets('课堂模式单击拍题 FAB：弹防误触提示且只弹一条', (tester) async {
    await tester.runAsync(() async {
      await ThemeController.instance.debugEnsureLoaded();
      await PresentModeController.instance.debugEnsureLoaded();
    });
    PresentModeController.instance.debugSetEnabled(true);
    await tester.pumpWidget(const BiologyApp());
    await tester.pumpAndSettle();

    await tester.tap(scanFabFinder());
    await tester.pump();

    expect(find.text('课堂模式为防误触已关闭单击，请长按拍题'), findsOneWidget,
        reason: '课堂单击 → 防误触提示（单击静默修复核心断言）');
  });

  testWidgets('非课堂模式单击拍题 FAB：不弹防误触提示（原行为开对话框）', (tester) async {
    await tester.runAsync(() async {
      await ThemeController.instance.debugEnsureLoaded();
      await PresentModeController.instance.debugEnsureLoaded();
    });
    PresentModeController.instance.debugSetEnabled(false);
    await tester.pumpWidget(const BiologyApp());
    await tester.pumpAndSettle();

    await tester.tap(scanFabFinder());
    await tester.pumpAndSettle();
    expect(find.text('课堂模式为防误触已关闭单击，请长按拍题'), findsNothing,
        reason: '标准模式单击直接进拍题对话框，无课堂防误触提示');
    expect(find.text('拍题识别'), findsOneWidget);
  });
}
