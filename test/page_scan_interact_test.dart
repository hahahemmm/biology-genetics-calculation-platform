// page_scan_interact_test.dart —— 交互态截图：每页执行关键操作后截取真实渲染
// 目的：给视觉模型看"用户实际看到的交互后状态"，定位白字残留
import 'dart:io';

import 'package:biology/main.dart';
import 'package:biology/ui/ai_chat_controller.dart' show appCanvasKey;
import 'package:biology/state/app_state.dart';
import 'package:biology/state/first_run_store.dart';
import 'package:biology/state/present_mode_controller.dart';
import 'package:biology/state/theme_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'golden_fonts.dart';

Future<void> _nav(WidgetTester tester, String label) async {
  final railLabel = find.descendant(
    of: find.byType(NavigationRail),
    matching: find.text(label),
  );
  await tester.tap(railLabel.first);
  await tester.pumpAndSettle();
}

void main() {
  late Directory tmp;

  // ── 用户数据隔离（2026-10-29）──
  // pump BiologyApp 会读开发机真实 `~/.biology_app` 的主题档 / 课堂 hc /
  // 角色（首启 dialog 会挡住 9331 输入框）。每个用例自建临时目录承接
  // 四个 debugFilePath，tearDown 摘 hook + reset 单例 + 删目录。
  setUp(() {
    tmp = Directory.systemTemp.createTempSync('biology_page_scan');
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
    // best-effort：Windows 上临时文件可能仍被句柄占着，清理失败不该判红。
    try {
      if (tmp.existsSync()) tmp.deleteSync(recursive: true);
    } catch (_) {}
  });

  /// 顺序纪律：debugFilePath（setUp 已设）→ debugEnsureLoaded → 用例显式
  /// 设定浅色。临时文件无值 ⇒ 加载只落默认态；随后的 pumpWidget 里
  /// initState 的 load() 因 _loaded 早返，不会把磁盘值覆盖回来。
  Future<void> primeIsolatedPrefs(WidgetTester tester) async {
    await tester.runAsync(() async {
      await ThemeController.instance.debugEnsureLoaded();
      await PresentModeController.instance.debugEnsureLoaded();
      await FirstRunStore.instance.debugEnsureLoaded();
      // 临时文件是首启（role=null）⇒ 会弹角色 dialog 盖住页面；显式落
      // student（本 golden 只截页面画布，不受角色卡片差异影响）。
      await FirstRunStore.instance.setRole(UserRole.student);
    });
  }

  Future<void> setView(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  testWidgets('交互态截图', (tester) async {
    // R13-1 统一字体 harness：换掉写死 msyh.ttc 的私有 _loadFonts
    // （漏 MaterialIcons 与 mono → icon / 基因型全方框）。
    await loadGoldenFonts();
    assertMaterialIconsLoaded();
    assertMonoLoaded();

    await setView(tester);
    await primeIsolatedPrefs(tester);
    ThemeController.instance.debugSetMode(ThemeMode.light);
    addTearDown(() => ThemeController.instance.debugSetMode(ThemeMode.system));

    await tester.pumpWidget(const BiologyApp());
    await tester.pumpAndSettle();

    // ── 9331：输入 + 计算 ──
    await _nav(tester, '9331');
    final p1 = find.byType(TextField).at(0);
    final p2 = find.byType(TextField).at(1);
    if (p1.evaluate().isNotEmpty && p2.evaluate().isNotEmpty) {
      await tester.enterText(p1, 'AaBb');
      await tester.enterText(p2, 'AaBb');
      // 真实主按钮文案是「计算比例」；旧选择器找「计算」时永远找不到，
      // 使这张“计算后”基线长期停在等待态，失去结果区巡检意义。
      final calc = find.widgetWithText(FilledButton, '计算比例');
      if (calc.evaluate().isNotEmpty) {
        await tester.tap(calc.first);
        await tester.pumpAndSettle();
      }
    }
    await expectLater(
      find.byKey(appCanvasKey),
      matchesGoldenFile('goldens/scan_i01_9331_计算后.png'),
    );

    // 2.2 批次2：练习/真题/系谱/变式页随刷题模块移除，对应交互截图段删除。
  });
}