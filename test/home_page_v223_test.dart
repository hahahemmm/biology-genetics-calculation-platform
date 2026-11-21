// home_page_v223_test.dart —— 关于页版本号契约（非 golden）。
//
// 版本只有一条线：关于页版本标签必须来自 lib/app_version.dart，页面与测试
// 都不得写死版本字面量；左栏只有「软件 / 技术」两组，没有版本历史分组。
// golden 只能证明像素变了，证不了分组真的没了，故保留本文件。
//
// 【用户数据隔离】泵 HomePage 本身不读偏好，但同批视觉测试
// （page_scan_interact / v213_r13_projection）曾因读开发机
// `~/.biology_app` 的主题档、课堂 hc、角色出现假回归。本文件沿用同一
// 纪律：四个偏好单例的 debugFilePath 全部指向临时目录并 reset，
// 用例结束摘 hook、reset 单例、删临时目录。rootBundle 只加载随包发布的
// data/syllabus_gaokao.json，不触碰真实历史 / 错题 / 主题文件。
import 'dart:io';

import 'package:biology/app_version.dart';
import 'package:biology/pages/home_page.dart';
import 'package:biology/state/app_state.dart';
import 'package:biology/state/first_run_store.dart';
import 'package:biology/state/present_mode_controller.dart';
import 'package:biology/state/theme_controller.dart';
import 'package:biology/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory tmp;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('biology_home_version');
    final sep = Platform.pathSeparator;
    ThemeController.debugFilePath = '${tmp.path}${sep}theme.json';
    PresentModeController.debugFilePath = '${tmp.path}${sep}present.json';
    FirstRunStore.debugFilePath = '${tmp.path}${sep}first_run.json';
    AppState.debugFilePath = '${tmp.path}${sep}app_state.json';
    ThemeController.instance.debugReset();
    PresentModeController.instance.debugReset();
    FirstRunStore.instance.debugReset();
    AppState.instance.debugResetPrefs();
    AppColors.sync(Brightness.light);
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
    AppColors.sync(Brightness.light);
    // best-effort：Windows 上临时文件可能仍被句柄占着，清理失败不该判红。
    try {
      if (tmp.existsSync()) tmp.deleteSync(recursive: true);
    } catch (_) {}
  });

  test('版本标签 = v + 版本号 + 开源版', () {
    expect(appVersionLabel, 'v$appVersionNumber · 开源版');
    expect(appVersionLabel, contains(appVersionNumber),
        reason: '标签与版本号必须同源，否则关于页显示与诊断日志会各说各话');
  });

  testWidgets('关于页：版本号单源，且不残留旧版本号与已剥离功能文案',
      (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: HomePage(navCollapsed: false, onNavPressed: () {}),
      ),
    );
    // 首分区只读随包 asset（考纲 JSON）。放行一小段真实异步 I/O，
    // 避免 FutureBuilder 停在等待态干扰后续 settle。
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await tester.pumpAndSettle();

    // 默认停在「本软件概览」：版本号单源，且带开源版标签。
    expect(find.text('本软件概览'), findsWidgets);
    expect(find.text(appVersionLabel), findsOneWidget,
        reason: '关于页版本号必须与 app_version 单源一致');

    // 左栏没有版本历史分组，自然也没有旧版本入口。
    expect(find.text('更新日志'), findsNothing,
        reason: '关于页左栏只有软件 / 技术两组');
    expect(find.text('2.23 更新'), findsNothing,
        reason: '页面不得出现非当前版本的历史入口');

    // 整页文本层面兜底：不得残留 2.x 版本号，也不得宣传已剥离的教材对照。
    final texts = tester
        .widgetList<Text>(find.byType(Text))
        .map((t) => t.data ?? '')
        .join('\n');
    expect(texts.contains('v2.23'), isFalse,
        reason: '版本号只来自 app_version，不得出现 2.x 字面量');
    expect(texts.contains('教材章节对照'), isFalse,
        reason: '教材章节对照功能已剥离，文案不得残留');
    expect(tester.takeException(), isNull);
  });
}
