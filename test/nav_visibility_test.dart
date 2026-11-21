// nav_visibility_test.dart —— v2.22.0「只减入口、不删能力」守卫网
//
// 产品决定：大题套路卡（id='cards'，pageIndex 8）从**主导航与首页**撤下
// 独立入口，内容融入「9331 结果页按 K」与「错题本按需打开」。
//
// 本文件钉住两件相反的事同时成立：
//   ① **入口撤了**：桌面 Rail / 移动底导 /「全部功能」面板 / 首页
//      Dashboard 都不再出现「套路卡」；
//   ② **能力没删**：目录条目、pageIndex 8、深链（数字键 9）、K 快捷键
//      push、页面保活全部照旧，且直达隐藏页时 Rail **不高亮错项**、
//      **不越界**。
//
// ⚠ 守卫纪律：显示层（可见索引）与页面层（pageIndex）是两套下标空间，
//   任何一处混用都会导致「点了 A 页却到了 B 页」。本文件对两套空间
//   分别下钉。
import 'dart:io';

import 'package:biology/guide/guide_controller.dart';
import 'package:biology/guide/guide_keys.dart';
import 'package:biology/main.dart';
import 'package:biology/pages/big_question_cards_page.dart';
import 'package:biology/state/first_run_store.dart';
import 'package:biology/state/theme_controller.dart';
import 'package:biology/ui/app_navigation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory tmp;

  setUp(() {
    // 全仓并发时其他套件可能写真实 first_run.json（老师/学生角色不同）。
    // 本文件必须验证学生首页与角色相关入口，故每个用例独立角色文件，
    // 不让 HomeShell 的异步 load 读到外部套件的共享状态。
    tmp = Directory.systemTemp.createTempSync('biology_nav_visibility');
    FirstRunStore.debugFilePath = '${tmp.path}/first_run.json';
    FirstRunStore.debugWebStorage = null;
    FirstRunStore.debugForceIsWebStorage = false;
    FirstRunStore.instance.debugReset();
  });

  tearDown(() {
    FirstRunStore.instance.debugReset();
    FirstRunStore.debugFilePath = null;
    FirstRunStore.debugWebStorage = null;
    FirstRunStore.debugForceIsWebStorage = null;
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  Future<void> pumpShell(WidgetTester tester, Size size) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.runAsync(() => ThemeController.instance.debugEnsureLoaded());
    await FirstRunStore.instance.setRole(UserRole.student);
    await tester.pumpWidget(const BiologyApp());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
  }

  /// 套路卡在导航目录里的 pageIndex（不许被重排）。
  const int cardsPageIndex = 8;

  // ── V1 目录层：条目 / 顺序 / pageIndex 一个都不许动 ─────────────
  testWidgets('V1：目录仍是 13 项、顺序不变，套路卡只是 visibleInNav=false',
      (tester) async {
    expect(appNavDestinations, hasLength(13), reason: '目录条目一个都不能删');
    expect(appNavDestinations[cardsPageIndex].id, 'cards',
        reason: '套路卡的 pageIndex 必须仍是 8（深链/数字键/Mock 依赖）');
    expect(appNavDestinations[cardsPageIndex].visibleInNav, isFalse,
        reason: '套路卡只从主导航/首页撤下入口');
    for (final d in appNavDestinations.where((d) => d.id != 'cards')) {
      expect(d.visibleInNav, isTrue,
          reason: '页面「${d.id}」不该被误设为不可见');
    }
    // 可见索引 ↔ pageIndex 映射：套路卡缺席 ⇒ 其后项可见索引前移一格。
    expect(appNavVisiblePageIndexes, hasLength(12));
    expect(appNavVisiblePageIndexes, contains(0));
    expect(appNavVisiblePageIndexes, isNot(contains(cardsPageIndex)),
        reason: '套路卡不在主导航条上');
    expect(appNavVisibleIndexOf(cardsPageIndex), -1,
        reason: '隐藏页的可见索引必须是 -1（调用方据此不高亮）');
    expect(appNavVisibleIndexOf(9), 8,
        reason: '变异（pageIndex 9）的可见索引 = 8（套路卡缺席前移一格）');
  });

  // ── V2 桌面 Rail：12 项、无「套路卡」 ───────────────────────────
  testWidgets('V2 @1280×800：Rail 不含「套路卡」，选中态按可见索引',
      (tester) async {
    await pumpShell(tester, const Size(1280, 800));

    final rail = tester.widget<NavigationRail>(find.byType(NavigationRail));
    expect(rail.destinations, hasLength(12),
        reason: '套路卡撤下 ⇒ Rail 12 项');
    final labels = rail.destinations
        .map((d) => (d.label as Text).data)
        .toList(growable: false);
    expect(labels, isNot(contains('套路卡')),
        reason: 'Rail 不得出现「套路卡」独立入口');
    expect(labels, contains('变异'), reason: '其余项照旧');

    // 选中态：首页（pageIndex 0）⇒ 可见索引 0。
    expect(rail.selectedIndex, 0, reason: '可见索引 ≠ pageIndex 时不得串位');
  });

  // ── V3 移动底导：无「套路卡」，且 Key 仍按完整 pageIndex ───────
  testWidgets('V3 @390×844：底导无「套路卡」标签', (tester) async {
    await pumpShell(tester, const Size(390, 844));

    expect(find.byType(NavigationRail), findsNothing);
    expect(find.text('套路卡'), findsNothing,
        reason: '移动底导不得出现「套路卡」独立入口');
    // 只看底导子树（首页卡片里也有「变异」，不能混在一起数）。
    expect(
      find.descendant(
        of: find.byKey(GuideKeys.navBar),
        matching: find.text('变异'),
      ),
      findsOneWidget,
      reason: '其余项照旧',
    );
  });

  // ── V4 「全部功能」面板：无「套路卡」行 ─────────────────────────
  testWidgets('V4 @390×844：「全部功能」面板逐行无「套路卡」', (tester) async {
    await pumpShell(tester, const Size(390, 844));

    await tester.tap(find.text('全部'));
    await tester.pumpAndSettle();
    expect(find.text('全部功能导航'), findsOneWidget);

    final listView = find.descendant(
      of: find.byType(BottomSheet),
      matching: find.byType(ListView),
    );
    final delegate = tester.widget<ListView>(listView).childrenDelegate;
    final titles = <String>[];
    for (final w in (delegate as SliverChildListDelegate).children) {
      if (w is Padding && w.child is ListTile) {
        titles.add(((w.child as ListTile).title as Text).data!);
      }
    }
    expect(titles, isNot(contains('大题套路卡')),
        reason: '「全部功能」面板不得出现「套路卡」独立入口');
    expect(titles, hasLength(12));
    expect(titles.sublist(titles.length - 2), <String>['设置', '关于'],
        reason: '末两行仍是设置/关于（顺序未动）');
  });

  // ── V5 首页 Dashboard：无「套路卡」卡 ──────────────────────────
  testWidgets('V5 首页：不再渲染「套路卡」入口卡', (tester) async {
    await pumpShell(tester, const Size(1280, 800));

    // 首页在 IndexedStack 里常驻（首页 = pageIndex 0）。
    expect(find.text('大题套路卡'), findsNothing,
        reason: '首页不得出现「套路卡」独立入口');
    expect(find.text('课标体系'), findsOneWidget, reason: '学习组其余项照旧');
    expect(find.text('我的错题'), findsOneWidget);
  });

  // ── V6 直达隐藏页：不越界、不错误高亮 ─────────────────────────
  testWidgets('V6 @1280×800：数字键直达套路卡（pageIndex 8）不崩、不串高亮',
      (tester) async {
    await pumpShell(tester, const Size(1280, 800));

    // 数字键 9 → _NavIntent(8) → 套路卡页（深链能力保留）。
    await tester.sendKeyEvent(LogicalKeyboardKey.digit9);
    await tester.pumpAndSettle();

    expect(tester.widget<IndexedStack>(find.byType(IndexedStack)).index,
        cardsPageIndex, reason: '数字键 9 仍直达套路卡（pageIndex 8）');
    expect(tester.takeException(), isNull, reason: '直达隐藏页不得抛异常');

    final rail = tester.widget<NavigationRail>(find.byType(NavigationRail));
    expect(rail.selectedIndex, isNull,
        reason: '当前页不在 Rail 上 ⇒ 不得高亮任何一项（更不能错高亮别的页）');
    expect(rail.destinations, hasLength(12));
  });

  // ── V7 Rail 回调的可见索引 → pageIndex 映射 ────────────────────
  testWidgets('V7：点 Rail 可见项切到正确的 pageIndex（不串位）',
      (tester) async {
    await pumpShell(tester, const Size(1280, 800));

    final rail = tester.widget<NavigationRail>(find.byType(NavigationRail));
    // 可见索引 8 = 变异（pageIndex 9）——套路卡缺席导致的一位前移。
    // ⚠ 这里传的是**可见索引**（Rail 回调语义），不是 pageIndex：
    //   传 pageIndex 8 会切到套路卡页（隐藏页），可见索引 8 才 = 变异。
    expect(appNavVisiblePageIndexes[8], 9);
    rail.onDestinationSelected!(8);
    await tester.pumpAndSettle();
    expect(tester.widget<IndexedStack>(find.byType(IndexedStack)).index, 9,
        reason: '可见索引 8 必须切到 pageIndex 9（变异），不是 8（套路卡）');

    // 可见索引 11 = 关于（pageIndex 12）。
    expect(appNavVisiblePageIndexes[11], 12);
    rail.onDestinationSelected!(11);
    await tester.pumpAndSettle();
    expect(tester.widget<IndexedStack>(find.byType(IndexedStack)).index, 12);
    expect(tester.takeException(), isNull);
  });

  // ── V8 能力未删：K 快捷键仍能 push 套路卡页 ───────────────────
  testWidgets('V8 @1280×800：9331 结果页按 K 仍推入套路卡页',
      (tester) async {
    await pumpShell(tester, const Size(1280, 900));

    // 数字键 3 → 9331（pageIndex 2）。
    await tester.sendKeyEvent(LogicalKeyboardKey.digit3);
    await tester.pumpAndSettle();
    expect(tester.widget<IndexedStack>(find.byType(IndexedStack)).index, 2);

    // 「套路卡」页本体仍常驻在 IndexedStack 里（页面保活 + K push 双份）。
    expect(find.byType(BigQuestionCardsPage, skipOffstage: false),
        findsOneWidget, reason: '套路卡页本体仍在壳内保活');

    await tester.sendKeyEvent(LogicalKeyboardKey.keyK);
    await tester.pumpAndSettle();
    expect(find.byType(BigQuestionCardsPage, skipOffstage: false),
        findsNWidgets(2),
        reason: '按 K 必须真的 push 套路卡路由（内容融入按需打开）');
    expect(tester.takeException(), isNull);
  });

  // ── V10 导航条末项仍可达（可见索引 vs pageIndex 的 Key 不错位）──
  testWidgets('V10 @800×800：Rail 末项「关于」完整可见；@800×560 溢出时仍能滚进视口',
      (tester) async {
    await pumpShell(tester, const Size(800, 800));
    final railRect = tester.getRect(find.byType(NavigationRail));
    final about = find.descendant(
      of: find.byType(NavigationRail),
      matching: find.text('关于'),
    );
    // 12 项在 800 高下已不再溢出 ⇒ 末项直接可见（比旧 13 项更宽松）。
    expect(about, findsOneWidget);
    final aboutRect = tester.getRect(about);
    expect(aboutRect.bottom, lessThanOrEqualTo(railRect.bottom + 0.5),
        reason: '末项「关于」必须完整落在 Rail 视口内');
    expect(aboutRect.top, greaterThanOrEqualTo(railRect.top - 0.5));

    // 窗口再压矮 ⇒ Rail 溢出滚动；选中末项后必须自动滚进视口
    // （Key 按 pageIndex 取 ⇒ 隐藏页缺席不造成错位）。
    tester.view.physicalSize = const Size(800, 560);
    await tester.pumpAndSettle();
    final rail2 = tester.widget<NavigationRail>(find.byType(NavigationRail));
    final visibleAbout = appNavVisiblePageIndexes.indexOf(12);
    rail2.onDestinationSelected!(visibleAbout);
    await tester.pumpAndSettle();
    expect(tester.widget<IndexedStack>(find.byType(IndexedStack)).index, 12,
        reason: '可见索引 → pageIndex 映射正确（末位 = 关于 = 12）');
    final railRect2 = tester.getRect(find.byType(NavigationRail));
    final aboutRect2 = tester.getRect(about);
    expect(aboutRect2.bottom, lessThanOrEqualTo(railRect2.bottom + 0.5),
        reason: 'Rail 溢出时选中项必须自动滚进视口');
    expect(aboutRect2.top, greaterThanOrEqualTo(railRect2.top - 0.5));
    expect(tester.takeException(), isNull);
  });

  // ── V9 引导：不再把套路卡当独立目的地介绍 ─────────────────────
  testWidgets('V9 引导：套路卡不再是独立步骤，9331 步交代真实可达路径',
      (tester) async {
    final steps = GuideController.instance.stepsFor(wide: true);
    expect(steps.any((s) => s.pageIndex == cardsPageIndex), isFalse,
        reason: '引导不得再把套路卡作为独立目的地介绍');
    expect(steps.any((s) => s.title == '大题套路卡'), isFalse);

    final crossStep = steps.firstWhere((s) => s.pageIndex == 2);
    expect(crossStep.body, contains('按 K'),
        reason: '9331 步必须说明「结果页按 K 可看配套套路卡」');
    expect(crossStep.body, contains('错题本'),
        reason: '9331 步必须说明「错题本也可按需打开」');
  });
}
