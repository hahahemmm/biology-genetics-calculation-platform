// nav_global_ai_fab_test.dart —— v2.22.0 全页面统一「问 AI」回归网
//
// 用户习惯契约：所有页面右下角都有同一个全局「问 AI」，页内上下文
// 讲解按钮不再让全局 FAB 消失。拍题 FAB 始终保留。
// 另钉住引导文案与课堂快捷条位置：切页不应让 FAB 或快捷条跳动。
import 'package:biology/guide/guide_controller.dart';
import 'package:biology/guide/guide_keys.dart';
import 'package:biology/main.dart';
import 'package:biology/state/first_run_store.dart';
import 'package:biology/state/present_mode_controller.dart';
import 'package:biology/state/theme_controller.dart';
import 'package:biology/ui/app_navigation.dart';
import 'package:biology/ui/classroom_quick_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 有页内「问 AI」按钮的页面 id（逐页 grep showAiAssistant 核对结果）。
const Set<String> _inlineAiPages = <String>{
  'pedigree',
  'cross',
  'graph',
  'curriculum',
  'molecular',
  'evolution',
  'ploidy',
  'cards',
  'variation',
  'disease',
};

void main() {
  Future<void> pumpShell(WidgetTester tester, Size size) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.runAsync(() => ThemeController.instance.debugEnsureLoaded());
    await tester.runAsync(
        () => PresentModeController.instance.debugEnsureLoaded());
    PresentModeController.instance.debugSetEnabled(false);
    addTearDown(PresentModeController.instance.debugReset);
    await FirstRunStore.instance.setRole(UserRole.student);
    addTearDown(FirstRunStore.instance.debugReset);
    await tester.pumpWidget(const BiologyApp());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
  }

  /// 走 Rail 的生产回调切页。
  ///
  /// v2.22.0：Rail 只渲染**可见**目的地（套路卡等隐藏页不在其中）⇒
  /// Rail 回调收到的是**可见索引**，必须换回 pageIndex 才能切到目标页
  /// （否则「设置」(pageIndex 11) 会被当成可见索引 11 = 关于）。
  Future<void> gotoPage(WidgetTester tester, int navIndex) async {
    final visible = appNavVisiblePageIndexes.indexOf(navIndex);
    expect(visible, greaterThanOrEqualTo(0),
        reason: 'pageIndex $navIndex 必须在主导航条上可见');
    tester
        .widget<NavigationRail>(find.byType(NavigationRail))
        .onDestinationSelected!(visible);
    await tester.pumpAndSettle();
  }

  // ── A1 目录元数据 ─────────────────────────────────────────────
  testWidgets('A1：hasInlineAi 逐页取值与「页内确有按钮」一致', (tester) async {
    for (final d in appNavDestinations) {
      expect(d.hasInlineAi, _inlineAiPages.contains(d.id),
          reason: '页面「${d.id}」的 hasInlineAi 与实测不一致：'
              'false 却页内无入口 ⇒ 该页没有问 AI；'
              'true 却页内没按钮 ⇒ 该页被误砍掉唯一入口');
    }
  });

  // ── A2 页内有上下文动作 ⇒ 全局 FAB 仍常驻，拍题也保留 ─────────
  testWidgets('A2 @1280：课标 / 分子页保留下方统一问 AI 与拍题入口',
      (tester) async {
    await pumpShell(tester, const Size(1280, 900));

    for (final entry in <int, String>{4: '课标', 5: '分子'}.entries) {
      await gotoPage(tester, entry.key);
      expect(find.byKey(GuideKeys.aiFab), findsOneWidget,
          reason: '${entry.value} 页必须有右下角统一「问 AI」');
      expect(
          find.descendant(
            of: find.byType(AppBar),
            matching: find.text('问 AI'),
          ),
          findsOneWidget,
          reason: '${entry.value} 页内上下文动作保持原样');
      expect(find.text('问 AI'), findsNWidgets(2),
          reason: '${entry.value} 页当前是页内动作 + 全局 FAB 两枚');
      expect(find.byTooltip('拍题识别（上传题目图片）'), findsOneWidget,
          reason: '${entry.value} 页拍题 FAB 必须保留');
      expect(find.byType(FloatingActionButton), findsNWidgets(2),
          reason: '${entry.value} 页 FAB 区应有拍题与统一问 AI');
      expect(tester.takeException(), isNull);
    }
  });

  // ── A3 无页内入口 ⇒ 全局 FAB 仍在 ────────────────────────────
  testWidgets('A3 @1280：首页 / 设置 / 关于仍有 1 枚全局「问 AI」+ 拍题入口',
      (tester) async {
    await pumpShell(tester, const Size(1280, 900));

    for (final entry in <int, String>{0: '首页', 11: '设置', 12: '关于'}.entries) {
      await gotoPage(tester, entry.key);
      expect(find.byKey(GuideKeys.aiFab), findsOneWidget,
          reason: '${entry.value} 页无页内入口 ⇒ 全局「问 AI」FAB 必须存在');
      expect(find.text('问 AI'), findsOneWidget,
          reason: '${entry.value} 页「问 AI」应是唯一一枚（全局 FAB）');
      expect(GuideKeys.aiFab.currentContext, isNotNull,
          reason: '${entry.value} 页 GuideKeys.aiFab 必须在树（引导挖孔依赖它）');
      expect(find.byTooltip('拍题识别（上传题目图片）'), findsOneWidget,
          reason: '${entry.value} 页拍题 FAB 必须保留');
      expect(tester.takeException(), isNull);
    }
  });

  // ── A4 引导「问 AI」步不丢 key ───────────────────────────────
  testWidgets('A4 引导「问 AI」步的宿主页仍渲染全局 FAB（key 不丢）',
      (tester) async {
    final steps = GuideController.instance.stepsFor(wide: true);
    final i = steps.indexWhere((s) => s.target == GuideKeys.aiFab);
    expect(i, greaterThan(0), reason: '引导表里应有「问 AI」步');

    // 该步 pageIndex = -1（不切页）：它停在前一步所在的页上。
    expect(steps[i].pageIndex, -1, reason: '「问 AI」步不切页，靠前一页的壳层 FAB');
    expect(steps[i].body, contains('任何页面'));
    expect(steps[i].body, contains('右下角'),
        reason: '引导必须与所有页面统一的右下角入口一致');
    expect(steps[i].body, isNot(contains('工具页点顶部')),
        reason: '不得再把工具页引导到位置不同的入口');
    final hostIndex = steps[i - 1].pageIndex;
    expect(hostIndex, inInclusiveRange(0, appNavDestinations.length - 1),
        reason: '前一页必须是真实页面索引（不能是 -1 居中卡）');

    // 真壳里再确认一次：宿主页上 GuideKeys.aiFab 有 RenderObject。
    await pumpShell(tester, const Size(1280, 900));
    await gotoPage(tester, hostIndex);
    expect(GuideKeys.aiFab.currentContext, isNotNull,
        reason: '引导宿主页 ${appNavDestinations[hostIndex].name} 的 aiFab 必须在树');
  });

  // ── A5 课堂快捷条不随页面跳动 ────────────────────────────────
  testWidgets('A5 @1280 课堂模式：全局 FAB 常驻，快捷条切页不跳动',
      (tester) async {
    await pumpShell(tester, const Size(1280, 900));
    PresentModeController.instance.debugSetEnabled(true);
    await tester.pumpAndSettle();

    await gotoPage(tester, 0);
    expect(find.byKey(GuideKeys.aiFab), findsOneWidget);
    final onHome = tester.getRect(find.byType(ClassroomQuickBar));

    await gotoPage(tester, 4);
    expect(find.byKey(GuideKeys.aiFab), findsOneWidget);
    final onCurriculum = tester.getRect(find.byType(ClassroomQuickBar));

    expect(onCurriculum.top, closeTo(onHome.top, 1.0),
        reason: '统一 FAB 后，课堂快捷条不应在页面切换时上下跳动');
    expect(tester.takeException(), isNull);
  });
}
