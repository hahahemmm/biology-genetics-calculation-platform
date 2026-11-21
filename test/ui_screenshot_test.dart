// ui_screenshot_test.dart —— UI 截图工具（生成 golden PNG 供视觉检查）
// 运行：flutter test --update-goldens test/ui_screenshot_test.dart
// 产物：test/goldens/*.png，可上传用 describe_images 查看布局/溢出/连线。
// v3.1：视口 1000×800（宽屏阈值 840 之上），保证左侧控制面板与
// 导航 Rail 完整入镜（v3.3 窄屏默认折叠，若用 800 宽面板不可见）。
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:biology/engine/pedigree_graph.dart';
import 'package:biology/main.dart';
import 'package:biology/ui/ai_chat_controller.dart' show appCanvasKey;
import 'package:biology/pages/widgets/pedigree_canvas.dart';
import 'package:biology/pages/widgets/pedigree_side_panel.dart';
import 'package:biology/state/app_state.dart';
import 'package:biology/state/first_run_store.dart';
import 'package:biology/state/present_mode_controller.dart';
import 'package:biology/state/theme_controller.dart';

import 'golden_fonts.dart';

// 跑马灯动画在 widget 测试中禁用（常驻 repeat 会让 pumpAndSettle 永不 settle）
void main() {
  late Directory tmp;

  // ── 用户数据隔离（2026-10-29）──
  // 泵 BiologyApp 会经 ThemeController / PresentModeController /
  // FirstRunStore / AppState 的默认路径（`~/.biology_app/*.json`）读开发机
  // 真实偏好：主题档决定配色、课堂 hc 决定高对比配色、first_run 角色决定
  // 是否弹首启 dialog（dialog 会盖住「遗传图谱」等点击目标）。读真机文件
  // 既让 golden 随日常使用漂移，也违反「测试不读写真实用户偏好」。
  // 每个用例自建临时目录，四个 debugFilePath 全指向其中；tearDown 摘
  // hook + reset 单例 + 删目录，绝不落到真实用户目录。
  setUp(() {
    tmp = Directory.systemTemp.createTempSync('biology_ui_shot');
    final sep = Platform.pathSeparator;
    ThemeController.debugFilePath = '${tmp.path}${sep}theme.json';
    PresentModeController.debugFilePath = '${tmp.path}${sep}present.json';
    FirstRunStore.debugFilePath = '${tmp.path}${sep}first_run.json';
    AppState.debugFilePath = '${tmp.path}${sep}app_state.json';
    ThemeController.instance.debugReset();
    PresentModeController.instance.debugReset();
    FirstRunStore.instance.debugReset();
    AppState.instance.debugResetPrefs();
  });

  tearDown(() {
    ThemeController.instance.debugReset();
    PresentModeController.instance.debugReset();
    FirstRunStore.instance.debugReset();
    AppState.instance.debugResetPrefs();
    ThemeController.debugFilePath = null;
    PresentModeController.debugFilePath = null;
    FirstRunStore.debugFilePath = null;
    AppState.debugFilePath = null;
    // best-effort：Windows 上临时文件可能仍被 Image 缓存/句柄占着，
    // deleteSync 抛错不该把用例判红（隔离已随 hook 清空生效）。
    try {
      if (tmp.existsSync()) tmp.deleteSync(recursive: true);
    } catch (_) {}
  });

  /// 顺序纪律：debugFilePath（setUp 已设）→ debugEnsureLoaded → 用例
  /// 显式 debugSetMode。临时文件里没有任何值 ⇒ 加载只落在默认态，
  /// 且 initState 的 load() 因 _loaded 早返，不会把磁盘值覆盖回来。
  /// 角色写 student：临时文件是首启（role=null）⇒ 首启 dialog 会挡住
  /// 导航点击；本文件只截页面画布，不受角色卡片差异影响。
  Future<void> primeIsolatedPrefs(WidgetTester tester) async {
    await tester.runAsync(() async {
      await ThemeController.instance.debugEnsureLoaded();
      await PresentModeController.instance.debugEnsureLoaded();
      await FirstRunStore.instance.debugEnsureLoaded();
      await FirstRunStore.instance.setRole(UserRole.student);
    });
  }

  Future<void> setView(WidgetTester tester) async {
    // R13-1 统一字体 harness：4 个截图用例全部经 setView 走，装在这里
    // 保证每个测试都执行到（原来 4 张 golden 的中文/基因型都是方框）。
    await loadGoldenFonts();
    assertMaterialIconsLoaded();
    assertMonoLoaded();

    tester.view.physicalSize = const Size(1000, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  // 2.2 批次4a 后默认页是「首页」仪表盘，需先点导航进遗传图谱页。
  Future<void> gotoPedigree(WidgetTester tester) async {
    await tester.tap(find.text('遗传图谱'));
    await tester.pumpAndSettle();
  }

  testWidgets('遗传图谱页截图（计算后）', (tester) async {
    await setView(tester);
    await primeIsolatedPrefs(tester);
    ThemeController.instance.debugSetMode(ThemeMode.light);
    await tester.pumpWidget(const BiologyApp());
    await tester.pumpAndSettle();
    await gotoPedigree(tester);

    // 填入双亲 + 点计算
    await tester.tap(find.text('计算').first); // v3：页面上有两颗「计算」
    await tester.pumpAndSettle();

    await expectLater(
      find.byKey(appCanvasKey),
      matchesGoldenFile('goldens/pedigree_derived.png'),
    );
  });

  testWidgets('深色模式截图（计算后）', (tester) async {
    await setView(tester);
    await primeIsolatedPrefs(tester);
    ThemeController.instance.debugSetMode(ThemeMode.dark);
    addTearDown(() => ThemeController.instance.debugSetMode(ThemeMode.system));
    await tester.pumpWidget(const BiologyApp());
    await tester.pumpAndSettle();
    await gotoPedigree(tester);

    await tester.tap(find.text('计算').first); // v3：页面上有两颗「计算」
    await tester.pumpAndSettle();

    await expectLater(
      find.byKey(appCanvasKey),
      matchesGoldenFile('goldens/pedigree_dark.png'),
    );
  });

  testWidgets('R15 组合桶截图（XY 性别 + 半边连线 + 连线模式发光）',
      (tester) async {
    await setView(tester);
    await primeIsolatedPrefs(tester);
    ThemeController.instance.debugSetMode(ThemeMode.light);
    await tester.pumpWidget(const BiologyApp());
    await tester.pumpAndSettle();
    await gotoPedigree(tester);

    await tester.tap(find.text('计算').first); // v3：页面上有两颗「计算」
    await tester.pumpAndSettle();
    // R16：XY 常驻默认开启 → group 桶已是组合体（大矩形内含 雄□+雌○）
    // 开连线模式（chip 发光），点选桶的雄半边待命（紫光）。
    // 按 FilterChip 整控件定位：tap 文本会被框架 _RenderChip.hitTest
    // （chip.dart:1907）重定向成假 "would not hit test" 告警。
    // 不滚动：本用例 1000×800 下「连线」chip 已在可视区，ensureVisible
    // 会挪动侧栏滚动位，把全窗 golden 打偏（实测 9.59% 像素差）。
    final wireChip = find.widgetWithText(FilterChip, '连线');
    expect(wireChip, findsOneWidget);
    await tester.tap(wireChip);
    await tester.pumpAndSettle();
    expect(
      tester.widget<PedigreeSidePanel>(find.byType(PedigreeSidePanel))
          .wireModeOn,
      isTrue,
      reason: '点「连线」后应进入连线模式（下面的紫光/待命画面才成立）',
    );
    final state =
        tester.state<PedigreeCanvasState>(find.byType(PedigreeCanvas));
    expect(state.widget.sexSplitView, isTrue);
    final bucket = state.widget.nodes.firstWhere(
        (n) => n.kind == PedigreeNodeKind.group && n.generation == 1);
    state.widget.onNodeHalfTap!(bucket, PedigreeNodeKind.male);
    await tester.pump();

    await expectLater(
      find.byKey(appCanvasKey),
      matchesGoldenFile('goldens/pedigree_combo_bucket.png'),
    );
  });

  testWidgets('9331 页截图', (tester) async {
    await setView(tester);
    await primeIsolatedPrefs(tester);
    ThemeController.instance.debugSetMode(ThemeMode.light);
    await tester.pumpWidget(const BiologyApp());
    await tester.pumpAndSettle();

    // 切到 9331 页（索引 1）
    await tester.tap(find.text('9331'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('计算比例'));
    await tester.pumpAndSettle();

    await expectLater(
      find.byKey(appCanvasKey),
      matchesGoldenFile('goldens/calculator_9331.png'),
    );
  });
}