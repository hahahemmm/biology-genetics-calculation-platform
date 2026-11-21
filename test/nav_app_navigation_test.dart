// nav_app_navigation_test.dart —— v2.20.0 导航治理切片回归网
//
// 覆盖（本轮验收点对应）：
//   N1 导航目录本身：13 项、id 唯一、顺序即页面索引（全名/短名逐字）；
//   N2 @800×560：选「关于」后 Rail 的选中标签自动进入视口（原实现只可
//      滚不自动滚）；Rail 仍是 SDK NavigationRail（不自绘）；
//   N3 @390×844：经「全部」面板选「关于」后，底导的高亮项自动横向滚进
//      视口（横滑与「全部」入口都保留）；
//   N4 1400→390 跨档：_navCollapsed 按档位默认重置（宽展开 / 窄收起），
//      且同档窗口缩放不覆盖用户手动选择；
//   N5 首页主导航卡目的地集合恰为可见目录项（变异 / 人类遗传病在列，
//      套路卡已撤下首页入口），点击分别触发对应导航索引。
//
// v2.22.0「只减入口、不删能力」：目录仍是 13 项、pageIndex 一个不动，
// 只是套路卡（pageIndex 8）从**显示层**撤下 ⇒ Rail 只渲染 12 项。
// 本文件的 Rail 回调**必须走映射**（可见索引 → pageIndex）：
// `appNavVisiblePageIndexes.indexOf(pageIndex)`——直接传 pageIndex
// 会越界（Rail 只有 12 项）或切错页。
import 'package:biology/guide/guide_keys.dart';
import 'package:biology/main.dart';
import 'package:biology/pages/dashboard_page.dart';
import 'package:biology/state/first_run_store.dart';
import 'package:biology/state/theme_controller.dart';
import 'package:biology/ui/app_navigation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// G4 同款逐字顺序（全名）。
const List<String> _expectedNames = <String>[
  '首页',
  '遗传图谱计算',
  '遗传计算器',
  '知识图谱',
  '课标',
  '分子',
  '进化',
  '染色体倍性',
  '大题套路卡',
  '变异',
  '人类遗传病',
  '设置',
  '关于',
];

/// 逐字短名（Rail / 底导标签）。
const List<String> _expectedShortNames = <String>[
  '首页',
  '遗传图谱',
  '9331',
  '图谱',
  '课标',
  '分子',
  '进化',
  '倍性',
  '套路卡',
  '变异',
  '遗传病',
  '设置',
  '关于',
];

void main() {
  Future<void> pumpShell(WidgetTester tester, Size size) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.runAsync(() => ThemeController.instance.debugEnsureLoaded());
    await FirstRunStore.instance.setRole(UserRole.student);
    addTearDown(FirstRunStore.instance.debugReset);
    await tester.pumpWidget(const BiologyApp());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
  }

  /// label 是否完整落在 [viewport] 里（容 0.5px 浮点误差）。
  void expectInside(Rect inner, Rect viewport, String reason) {
    expect(inner.top, greaterThanOrEqualTo(viewport.top - 0.5), reason: reason);
    expect(
      inner.bottom,
      lessThanOrEqualTo(viewport.bottom + 0.5),
      reason: reason,
    );
  }

  // ── N1 导航目录 ────────────────────────────────────────────────
  testWidgets('N1：导航目录 13 项、id 唯一、顺序即页面索引', (tester) async {
    expect(appNavDestinations, hasLength(13),
        reason: '主导航 13 页——v2.22.0 只减**入口**，目录条目一个都不删');
    expect(
      <String>[for (final d in appNavDestinations) d.name],
      _expectedNames,
      reason: '全名顺序 = 页面索引（设置/关于固定末两位）',
    );
    expect(
      <String>[for (final d in appNavDestinations) d.shortName],
      _expectedShortNames,
      reason: '短名顺序 = Rail / 底导标签顺序',
    );
    final ids = <String>[for (final d in appNavDestinations) d.id];
    expect(ids.toSet(), hasLength(ids.length), reason: 'id 必须唯一（页面分支依据）');
    // HomeShell 的 pageNamesForTest 仍可用（守卫网依赖它）。
    expect(HomeShellState.pageNamesForTest, _expectedNames);
  });

  // ── N2 Rail 选中项自动进视口 ───────────────────────────────────
  testWidgets('N2 @800×560 紧凑 Rail：选「关于」后选中标签可见', (tester) async {
    // v2.22.0：套路卡撤下 Rail ⇒ 12 项在 800 高下**不再溢出**（末项直接
    // 可见），本用例测不到 ensureVisible ⇒ 视口压到 560 重新制造溢出。
    await pumpShell(tester, const Size(800, 560));

    expect(
      find.byType(NavigationRail),
      findsOneWidget,
      reason: '800 ≥ 600 ⇒ SDK NavigationRail（<1200 保持紧凑档）',
    );
    final rail = tester.widget<NavigationRail>(find.byType(NavigationRail));
    expect(rail.destinations, hasLength(12),
        reason: '套路卡撤下显示层 ⇒ Rail 12 项（目录仍是 13）');

    final railRect = tester.getRect(find.byType(NavigationRail));
    final aboutLabel = find.descendant(
      of: find.byType(NavigationRail),
      matching: find.text('关于'),
    );
    // 前提：12 项（≈800）在 560 高下必然溢出，末项初始不在视口内——
    // 否则本用例测不到 ensureVisible。
    final before = tester.getRect(aboutLabel);
    expect(
      before.bottom,
      greaterThan(railRect.bottom),
      reason: '前提：末项「关于」初始在 Rail 视口外',
    );

    // 走生产回调（Rail 的 onDestinationSelected == HomeShell._select）。
    // ⚠ Rail 回调给的是**可见索引** ⇒ 必须经 appNavVisiblePageIndexes
    // 换回 pageIndex（12 ⇒ 可见索引 11）；直接传 12 会 RangeError
    // （Rail 只有 12 项，索引 0..11）。
    rail.onDestinationSelected!(appNavVisiblePageIndexes.indexOf(12));
    await tester.pumpAndSettle();

    expect(
      tester.widget<IndexedStack>(find.byType(IndexedStack)).index,
      12,
      reason: '应切到「关于」（索引 12）',
    );
    expectInside(tester.getRect(aboutLabel), railRect, 'Rail 选中标签必须自动滚进视口');
    expect(tester.takeException(), isNull);
  });

  // ── N6 已可见项再次选中：不得被对齐到视口起点 ──────────────────
  testWidgets('N6 @800×560：已可见 Rail 项再次选中不产生滚动（旧实现会跳到起点）',
      (tester) async {
    // v2.22.0：12 项在 800 高下不再溢出 ⇒ 视口压到 560 才能滚到中间。
    await pumpShell(tester, const Size(800, 560));

    final railScrollable = tester.state<ScrollableState>(
      find
          .descendant(
            of: find.byType(NavigationRail),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    // 构造「目标已完整可见、但视口已滚到中间」的现场——旧实现
    // （keepVisibleAtStart）正是这种现场会把目标顶到视口起点。
    railScrollable.position.jumpTo(60);
    await tester.pumpAndSettle();
    final pixelsBefore = railScrollable.position.pixels;
    expect(pixelsBefore, greaterThan(0),
        reason: '前提：紧凑 Rail 确实能滚到中间，避免在不可滚布局里空测');

    final target = find.descendant(
      of: find.byType(NavigationRail),
      matching: find.text('图谱'), // pageIndex 3
    );
    final railRect = tester.getRect(find.byType(NavigationRail));
    final rectBefore = tester.getRect(target);
    expect(rectBefore.top, greaterThanOrEqualTo(railRect.top),
        reason: '前提：目标此刻已完整可见');

    // v2.22.0：Rail 回调给的是**可见索引** ⇒ 一律经
    // appNavVisiblePageIndexes 换回 pageIndex。pageIndex 3 在隐藏页
    // （套路卡 = 8）之前，可见索引恰好也是 3——但**不再依赖这个巧合**，
    // 显式走映射，避免下次隐藏页位置一变就静默切错页。
    tester
        .widget<NavigationRail>(find.byType(NavigationRail))
        .onDestinationSelected!(appNavVisiblePageIndexes.indexOf(3));
    await tester.pumpAndSettle();

    expect(
      tester.widget<IndexedStack>(find.byType(IndexedStack)).index,
      3,
      reason: '仍应正常切页（pageIndex 3 = 知识图谱）',
    );
    expect(railScrollable.position.pixels, pixelsBefore,
        reason: '已完全可见的项不得触发滚动（no-op）');
    // 标签 rect 会因「选中态字重/字号」变化几像素（不是滚动造成的），
    // 故只钉「仍完整可见 + 位移只可能来自样式」——**滚动的证据是上面的
    // pixels 必须逐位相同**，这里 16px 只是样式漂移上界，不是放宽滚动行为
    //（真滚一下至少是「把项对齐到视口起点」的几十像素级）。
    expectInside(tester.getRect(target), railRect, '已可见项必须仍完整可见');
    expect((tester.getRect(target).top - rectBefore.top).abs(), lessThan(16),
        reason: '已可见项不得被滚走（纵向位移仅来自选中态样式，实测 9px）');
    expect(tester.takeException(), isNull);
  });

  // ── N3 移动底导选中项自动进视口 ────────────────────────────────
  testWidgets('N3 @390×844：选「关于」后底导高亮项可见（横滑 + 全部保留）', (tester) async {
    await pumpShell(tester, const Size(390, 844));

    expect(
      find.byType(NavigationRail),
      findsNothing,
      reason: '390 < 600 ⇒ 移动底导',
    );
    expect(find.text('全部'), findsOneWidget, reason: '「全部」入口仍在');

    await tester.tap(find.text('全部'));
    await tester.pumpAndSettle();
    expect(find.text('全部功能导航'), findsOneWidget);

    // 面板 ListView 惰性布局：先滚到「关于」再点。
    final sheetItem = find.descendant(
      of: find.byType(BottomSheet),
      matching: find.text('关于'),
    );
    await tester.scrollUntilVisible(
      sheetItem,
      120,
      scrollable: find.descendant(
        of: find.byType(BottomSheet),
        matching: find.byType(Scrollable),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(sheetItem);
    await tester.pumpAndSettle();

    expect(find.text('全部功能导航'), findsNothing, reason: '点项后面板关闭');
    expect(
      tester.widget<IndexedStack>(find.byType(IndexedStack)).index,
      12,
      reason: '应切到「关于」（索引 12）',
    );

    // 底导高亮项（「关于」）必须自动横向滚进底栏视口。
    final bar = find.byKey(GuideKeys.navBar);
    final barRect = tester.getRect(bar);
    final itemRect = tester.getRect(
      find.descendant(of: bar, matching: find.text('关于')),
    );
    expect(
      itemRect.left,
      greaterThanOrEqualTo(barRect.left - 0.5),
      reason: '底导选中项左缘必须在视口内',
    );
    expect(
      itemRect.right,
      lessThanOrEqualTo(barRect.right + 0.5),
      reason: '底导选中项右缘必须在视口内',
    );
  });

  // ── N4 跨档位重置 / 同档不覆盖 ─────────────────────────────────
  testWidgets('N4 1400→390 跨档后面板自动收起；同档缩放保留手动选择', (tester) async {
    await pumpShell(tester, const Size(1400, 900));

    // 进系谱页：宽档默认面板展开（_navCollapsed=false）。
    await tester.tap(find.text('遗传图谱').first);
    await tester.pumpAndSettle();
    expect(find.byType(NavigationRail), findsOneWidget);
    expect(find.text('同性交配'), findsOneWidget, reason: '宽档默认展开控制面板');

    // 跨档到手机档：面板按窄档默认收起（原实现只在首帧初始化过一次，
    // 跨档后仍保持桌面档的展开态）。
    tester.view.physicalSize = const Size(390, 844);
    await tester.pumpAndSettle();
    expect(find.byType(NavigationRail), findsNothing, reason: '390 走底导');
    expect(find.text('同性交配'), findsNothing, reason: '跨档后按窄档默认收起');

    // 回宽档：按宽档默认重新展开。
    tester.view.physicalSize = const Size(1400, 900);
    await tester.pumpAndSettle();
    expect(find.text('同性交配'), findsOneWidget, reason: '跨档回宽档默认展开');

    // 用户手动收起 → 同档缩放（1400→1500）不得覆盖手动选择。
    await tester.tap(find.byIcon(Icons.menu));
    await tester.pumpAndSettle();
    expect(find.text('同性交配'), findsNothing, reason: '☰ 手动收起');
    tester.view.physicalSize = const Size(1500, 900);
    await tester.pumpAndSettle();
    expect(find.text('同性交配'), findsNothing, reason: '同档位窗口缩放不覆盖用户手动折叠');
    expect(tester.takeException(), isNull);
  });

  // ── N5 首页主导航卡：目的地集合 = 可见目录项 ───────────────────
  testWidgets('N5 首页主导航卡：目的地集合恰为可见目录项，变异/遗传病可点',
      (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await FirstRunStore.instance.setRole(UserRole.student);
    addTearDown(FirstRunStore.instance.debugReset);

    final opened = <int>[];
    await tester.pumpWidget(
      MaterialApp(home: DashboardPage(onOpenTool: opened.add)),
    );
    await tester.pumpAndSettle();

    // v2.22.0：套路卡撤下首页独立入口 ⇒ 首页只渲染**可见**目录项
    // （visibleInNav = true），隐藏页不占卡位。
    final visibleDestinations = <AppNavDestination>[
      for (final d in appNavDestinations.skip(1))
        if (d.visibleInNav) d,
    ];
    for (final d in visibleDestinations) {
      final card = find.text(d.dashboardTitle);
      await tester.scrollUntilVisible(
        card,
        160,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      expect(card, findsOneWidget, reason: '卡片「${d.dashboardTitle}」应存在');
      await tester.tap(card);
      await tester.pumpAndSettle();
    }

    expect(
      opened,
      <int>[for (final d in visibleDestinations) appNavDestinations.indexOf(d)],
      reason: '首页卡按目录顺序触发对应 pageIndex（套路卡已撤下 ⇒ 无 8）',
    );
    expect(opened, isNot(contains(8)),
        reason: '套路卡不得在首页出现独立入口（改由 9331 按 K / 错题本打开）');
  });
}
