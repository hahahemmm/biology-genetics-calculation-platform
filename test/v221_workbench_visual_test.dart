// v221_workbench_visual_test.dart —— v2.21.0 模块化工作台视觉验收
//
// 只覆盖本轮新信息架构与焦点连线；历史全页浅/深巡检仍由
// light_full_scan_test.dart / dark_full_scan_test.dart 负责。
// 新增基线必须逐张目检，禁止因其他测试变红而批量接受。
//
// ⚠️ 角色隔离（v2.22.0+1）：首页两张 golden 基线是**学生**视图
//（错题本卡在、老师工具卡不在）。角色是全局单例 + 真实磁盘
// `~/.biology_app/first_run.json`，全仓并发时别的套件（如
// settings/导航相关）会把真实文件写成 teacher ⇒ 本文件的结果取决于
// 执行顺序（测试污染）。所以这里自带临时角色文件并显式固定 student，
// 每个用例重置，tearDown 摘 hook；golden 文件本身一张不动。

import 'dart:io';

import 'package:biology/main.dart';
import 'package:biology/pages/cross_calculator_page.dart';
import 'package:biology/pages/dashboard_page.dart';
import 'package:biology/pages/genetic_pedigree_page.dart';
import 'package:biology/pages/knowledge_graph_page.dart';
import 'package:biology/state/app_state.dart';
import 'package:biology/state/first_run_store.dart';
import 'package:biology/state/present_mode_controller.dart';
import 'package:biology/state/theme_controller.dart';
import 'package:biology/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'golden_fonts.dart';

void main() {
  late Directory tmp;

  setUp(() async {
    tmp = Directory.systemTemp.createTempSync('biology_v221_visual');
    final sep = Platform.pathSeparator;
    FirstRunStore.debugFilePath = '${tmp.path}${sep}first_run.json';
    // 2026-10-29：角色之外，主题档 / 课堂 hc 也是真实的
    // `~/.biology_app/{theme_mode,present_mode}.json`——不隔离则浅色基线
    // 会跟着开发机的深色档 / 高对比档漂移。四类偏好同一套临时目录。
    ThemeController.debugFilePath = '${tmp.path}${sep}theme.json';
    PresentModeController.debugFilePath = '${tmp.path}${sep}present.json';
    AppState.debugFilePath = '${tmp.path}${sep}app_state.json';
    FirstRunStore.debugWebStorage = null;
    FirstRunStore.debugForceIsWebStorage = false;
    ThemeController.instance.debugReset();
    PresentModeController.instance.debugReset();
    AppState.instance.debugResetPrefs();
    // reset + load（临时文件不存在 ⇒ 首启），再显式写 student：
    // HomeShell 里的 `load()` 因已 loaded 直接早返，不会去读真实用户配置，
    // 因此桌面 HomeShell 与直接 pump 的 DashboardPage 都是 deterministic
    // 的学生视图。
    await FirstRunStore.instance.debugEnsureLoaded();
    await FirstRunStore.instance.setRole(UserRole.student);
    // 主题同理：先在临时文件上落定 loaded，再显式钉浅色（本文件 5 张
    // golden 都是浅色基线），initState 的 load() 不会再覆盖。
    await ThemeController.instance.debugEnsureLoaded();
    await PresentModeController.instance.debugEnsureLoaded();
    ThemeController.instance.debugSetMode(ThemeMode.light);
  });

  tearDown(() {
    ThemeController.instance.debugReset();
    PresentModeController.instance.debugReset();
    AppState.instance.debugResetPrefs();
    FirstRunStore.instance.debugReset();
    ThemeController.debugFilePath = null;
    PresentModeController.debugFilePath = null;
    AppState.debugFilePath = null;
    FirstRunStore.debugFilePath = null;
    FirstRunStore.debugWebStorage = null;
    FirstRunStore.debugForceIsWebStorage = null;
    // best-effort：Windows 上临时文件可能仍被句柄占着，清理失败不该判红。
    try {
      if (tmp.existsSync()) tmp.deleteSync(recursive: true);
    } catch (_) {}
  });

  Future<void> setView(WidgetTester tester, Size size) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 400)),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('桌面首页：展开侧栏、三核心与分组层级', (tester) async {
    await loadGoldenFonts();
    assertMaterialIconsLoaded();
    assertMonoLoaded();
    await setView(tester, const Size(1400, 900));
    ThemeController.instance.debugSetMode(ThemeMode.light);
    addTearDown(() => ThemeController.instance.debugSetMode(ThemeMode.system));
    await tester.pumpWidget(const BiologyApp());
    await settle(tester);
    await expectLater(
      find.byType(HomeShell),
      matchesGoldenFile('goldens/v221_home_desktop.png'),
    );
  });

  testWidgets('手机首页：核心卡全宽、模块双列、末屏可达', (tester) async {
    await loadGoldenFonts();
    assertMaterialIconsLoaded();
    assertMonoLoaded();
    await setView(tester, const Size(390, 844));
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: DashboardPage(onOpenTool: (_) {}),
      ),
    );
    await settle(tester);
    await expectLater(
      find.byType(DashboardPage),
      matchesGoldenFile('goldens/v221_home_mobile_top.png'),
    );
    await tester.ensureVisible(find.text('关于'));
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(DashboardPage),
      matchesGoldenFile('goldens/v221_home_mobile_bottom.png'),
    );
  });

  testWidgets('知识图谱：选中后相关连线高亮、其余仍保留', (tester) async {
    await loadGoldenFonts();
    assertMaterialIconsLoaded();
    assertMonoLoaded();
    await setView(tester, const Size(1400, 900));
    await tester.pumpWidget(
      MaterialApp(theme: AppTheme.light(), home: const KnowledgeGraphPage()),
    );
    await settle(tester);
    final state = tester.state(find.byType(KnowledgeGraphPage)) as dynamic;
    state.debugShowDetail('law-of-segregation');
    await tester.pumpAndSettle();
    expect(find.text('分离定律（孟德尔第一定律）'), findsOneWidget);
    // 收起详情，检查画布焦点；选中态不随 Sheet 关闭而丢失。
    await tester.tapAt(const Offset(20, 20));
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(KnowledgeGraphPage),
      matchesGoldenFile('goldens/v221_graph_focus.png'),
    );
  });

  testWidgets('9331：宽屏输入与结果形成明确双工作区', (tester) async {
    await loadGoldenFonts();
    assertMaterialIconsLoaded();
    assertMonoLoaded();
    await setView(tester, const Size(1400, 900));
    await tester.pumpWidget(
      MaterialApp(theme: AppTheme.light(), home: const CrossCalculatorPage()),
    );
    await settle(tester);
    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), 'AaBb');
    await tester.enterText(fields.at(1), 'AaBb');
    await tester.tap(find.widgetWithText(FilledButton, '计算比例').first);
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(CrossCalculatorPage),
      matchesGoldenFile('goldens/v221_cross_result.png'),
    );
  });

  testWidgets('系谱：空态步骤与计算后画布容器', (tester) async {
    await loadGoldenFonts();
    assertMaterialIconsLoaded();
    assertMonoLoaded();
    await setView(tester, const Size(1400, 900));
    await tester.pumpWidget(
      MaterialApp(theme: AppTheme.light(), home: const GeneticPedigreePage()),
    );
    await settle(tester);
    await expectLater(
      find.byType(GeneticPedigreePage),
      matchesGoldenFile('goldens/v221_pedigree_empty.png'),
    );
    await tester.tap(find.text('计算').first);
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(GeneticPedigreePage),
      matchesGoldenFile('goldens/v221_pedigree_derived.png'),
    );
  });
}
