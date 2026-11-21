// nav_order_guard_test.dart —— v2.19.60 主导航重排守卫网
//
// 需求（用户原话）：设置页与「关于/详情」页应排在导航栏最后一个位置。
// 本轮把 HomeShell 的四张并行表（_pageNames/_navLabels/_navIcons/
// _navIconsSelected/_navDescs）与 _buildPages() 一起重排：
//   0首页 1遗传图谱计算 2遗传计算器 3知识图谱 4课标 5分子 6进化
//   7染色体倍性 8大题套路卡 9变异 10人类遗传病 11设置 12关于
// 只有最后四项换位（变异/遗传病提前到 9/10，设置/关于落到 11/12）。
//
// 本文件把「导航末位 = 设置/关于」钉成回归网：
//   G1 宽屏 NavigationRail 的 **12 个可见 label** 逐字等于可见顺序表；
//   G2 窄屏「全部」面板逐行列出 **12 个可见页**，末两行是设置/关于；
//   G3 快捷键速览键表（rowsByPage）键集合/键 9/键 10 的内容随页归位；
//   G4 源级钉死 _pageNames 的 **13 项完整顺序**（顺序表即唯一真相）。
//
// v2.22.0「只减入口、不删能力」：**完整目录仍是 13 页**（含 pageIndex 8
// 的「大题套路卡」），只是它从**显示层**（Rail / 底导 /「全部」面板）
// 撤下独立入口。故本文件同时留两套期望表：
//   · 完整目录表（13 项）——G4 钉死 pageNamesForTest，不得被「修」成 12；
//   · 可见表（12 项，去掉套路卡）——G1/G2 钉死显示层；
// 两表差集恒为「套路卡」一项，任何一侧被误改都会立刻红。
//
// 泵法照抄 test/mobile_smoke_test.dart 的 BiologyApp 全壳泵法
// （ThemeController.debugEnsureLoaded + FirstRunStore.setRole(student)
// 先落地，避免首启角色 dialog 干扰）。
import 'package:biology/main.dart';
import 'package:biology/pages/big_question_cards_page.dart'
    show CardPracticeKeyHost;
import 'package:biology/pages/curriculum_page.dart'
    show CurriculumFocusShortcuts;
import 'package:biology/pages/widgets/save_mistake_key_host.dart';
import 'package:biology/pages/widgets/shortcut_cheatsheet.dart';
import 'package:biology/state/first_run_store.dart';
import 'package:biology/state/theme_controller.dart';
import 'package:biology/ui/app_navigation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 完整目录顺序（唯一真相，逐字）：13 页 —— **含「大题套路卡」**。
///
/// ⚠ 这张表钉的是**页面目录**（pageIndex 空间）：套路卡只是从显示层撤下
/// 入口，条目与 pageIndex 8 一个都不许动。
const List<String> _expectedPageNames = <String>[
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

/// 完整目录短标签（同序，13 项）——同样钉**目录**事实源。
const List<String> _expectedNavLabels = <String>[
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

/// 可见页全名（12 项）——显示层期望：完整目录去掉「大题套路卡」。
const List<String> _expectedVisiblePageNames = <String>[
  '首页',
  '遗传图谱计算',
  '遗传计算器',
  '知识图谱',
  '课标',
  '分子',
  '进化',
  '染色体倍性',
  '变异',
  '人类遗传病',
  '设置',
  '关于',
];

/// 可见短标签（12 项）——Rail / 底导显示层的顺序。
const List<String> _expectedVisibleNavLabels = <String>[
  '首页',
  '遗传图谱',
  '9331',
  '图谱',
  '课标',
  '分子',
  '进化',
  '倍性',
  '变异',
  '遗传病',
  '设置',
  '关于',
];

void main() {
  /// 泵真实 BiologyApp 全壳：固定视口，等首帧与异步数据落地。
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

  testWidgets('G1 @1280×800：NavigationRail 12 个**可见** label 逐字等于可见表，'
      '设置/关于恰在末两位', (tester) async {
    await pumpShell(tester, const Size(1280, 800));

    expect(find.byType(NavigationRail), findsOneWidget,
        reason: '1280 宽 ≥ 600 阈值应出现 Rail');
    final rail = tester.widget<NavigationRail>(find.byType(NavigationRail));
    // v2.22.0：套路卡从显示层撤下 ⇒ Rail 12 项（**目录仍是 13 页**，
    // 由 G4 钉死）。
    expect(rail.destinations, hasLength(12),
        reason: 'Rail 可见项 = 12（完整目录 13 − 套路卡 1）');

    // destination.label 是 Text(_nav[navIndex].shortName)（main.dart
    // buildRail）——从 widget 树读回短标签，即验证导航顺序事实源。
    final labels = rail.destinations
        .map((d) => (d.label as Text).data)
        .toList(growable: false);
    expect(labels, _expectedVisibleNavLabels,
        reason: 'Rail 可见 label 顺序必须逐字等于可见表（12 项）');
    expect(labels, isNot(contains('套路卡')),
        reason: 'v2.22.0：套路卡不得再作为 Rail 独立入口出现');
    expect(labels.sublist(labels.length - 2), <String>['设置', '关于'],
        reason: '设置/关于必须落在导航末两位（用户明确要求）');
    expect(tester.takeException(), isNull);
  });

  testWidgets('G2 @390×844：底导「全部」面板逐行列出 12 个**可见**页，'
      '末两行是设置、关于', (tester) async {
    await pumpShell(tester, const Size(390, 844));

    expect(find.byType(NavigationRail), findsNothing,
        reason: '390 宽 < 600 应走底导，无 Rail');
    await tester.tap(find.text('全部'));
    await tester.pumpAndSettle();
    expect(find.text('全部功能导航'), findsOneWidget, reason: '面板应打开');

    // 面板 = BottomSheet ▸ ListView（默认构造 = SliverChildListDelegate）
    // ▸ 标题/说明 + 12 个 Padding(ListTile(title=_pageNames[i]))。
    // ⛔ 不在树里滚 ListTile 收集：shrinkWrap ListView 惰性布局，滚动会把
    // 首行（首页）滚出并销毁 → 顺序断言取不全。改读 childrenDelegate 的
    // 构造期 children 列表——与布局无关，稳定拿到「逐行」的 12 页。
    final listView = find.descendant(
      of: find.byType(BottomSheet),
      matching: find.byType(ListView),
    );
    expect(listView, findsOneWidget, reason: '面板应有一个功能列表');
    final delegate = tester.widget<ListView>(listView).childrenDelegate;
    expect(delegate, isA<SliverChildListDelegate>());
    final titles = <String>[];
    for (final w in (delegate as SliverChildListDelegate).children) {
      if (w is Padding && w.child is ListTile) {
        titles.add(((w.child as ListTile).title as Text).data!);
      }
    }
    expect(titles, _expectedVisiblePageNames,
        reason: '面板应逐行列出 12 个可见页完整名（新顺序）');
    expect(titles, isNot(contains('大题套路卡')),
        reason: 'v2.22.0：套路卡不得再作为「全部功能」面板的独立入口出现');
    expect(titles.sublist(titles.length - 2), <String>['设置', '关于'],
        reason: '末两行必须是设置、关于');
  });

  testWidgets('G3：快捷键速览键表随页归位（键集 {2,5,6,7,8,9,10}；'
      '键 9=变异、键 10=遗传病含 Ctrl+S 与 Alt+K；键 8=套路卡含 Alt+L）', (tester) async {
    // 断言用 rowsByPage 的**源码级**常量（本表是 const Map，即键位→页的
    // 事实源；比弹卡再读文本更直接、更不易被 pump 时序干扰）。
    expect(
        ShortcutCheatsheet.rowsByPage.keys.toSet(), <int>{2, 5, 6, 7, 8, 9, 10},
        reason: 'v2.19.60：变异 11→9、遗传病 12→10；2/5/6/7 不变；'
            '8=套路卡（Alt+L，v2.19.60 去练键）；设置/关于（11/12）无键表行保持无');

    final row8 = ShortcutCheatsheet.rowsByPage[8]!;
    expect(row8.map((r) => r.keys), contains(CardPracticeKeyHost.keyLabel),
        reason: '套路卡页（index 8）应含 Alt+L 行（v2.19.60 去练键）');

    final row9 = ShortcutCheatsheet.rowsByPage[9]!;
    expect(row9.map((r) => r.keys), contains(SaveMistakeKeyHost.keyLabel),
        reason: '变异页（index 9）应含 Ctrl+S 行');

    final row10 = ShortcutCheatsheet.rowsByPage[10]!;
    final keys10 = row10.map((r) => r.keys).toList();
    expect(keys10, contains(SaveMistakeKeyHost.keyLabel),
        reason: '遗传病页（index 10）应含 Ctrl+S 行');
    expect(keys10, contains(CurriculumFocusShortcuts.keyLabel),
        reason: '遗传病页（index 10）应含 Alt+K 行（CurriculumFocusShortcuts）');
  });

  testWidgets('G4：_pageNames 顺序表逐字钉死（源级常量，改动即红）',
      (tester) async {
    // 选「暴露只读快照」而非「读 widget 树」作 G4 的理由：读树要 pump 全壳
    // 且与 G1/G2 重叠，而 pageNamesForTest 是一个编译期常量别名，测试 import
    // 后逐字 compare 即可，改动最小、对结构性重排最敏感。
    //
    // ⚠ v2.22.0：这里锁的是**完整目录 13 项**（含「大题套路卡」）——
    //   套路卡只是从显示层撤下入口，条目与 pageIndex 一个都不许动。
    //   「12 可见」由 G1/G2 单独钉；两张表的差集恒为套路卡一项。
    expect(HomeShellState.pageNamesForTest, _expectedPageNames,
        reason: 'v2.19.60 顺序：设置/关于固定末位（11/12）；'
            'v2.22.0：完整目录仍是 13 项（含大题套路卡），不得被改成 12');

    // 目录本体同样逐字钉死（id / 短名 / 顺序）。
    expect(appNavDestinations, hasLength(13),
        reason: '目录条目一个都不许删（只减入口、不删能力）');
    expect(
      <String>[for (final d in appNavDestinations) d.shortName],
      _expectedNavLabels,
      reason: '完整目录短名顺序 = pageIndex 顺序（13 项）',
    );
    expect(appNavDestinations[8].id, 'cards',
        reason: '套路卡的 pageIndex 必须仍是 8（深链 / 数字键 9 / 快捷键依赖）');
    expect(appNavDestinations[8].visibleInNav, isFalse,
        reason: '套路卡只是从显示层撤下入口（visibleInNav = false）');

    // 可见集合 = 完整目录去掉套路卡 —— 12 项，短名逐字等于可见表。
    expect(appNavVisiblePageIndexes, hasLength(12),
        reason: '可见项 = 完整目录 13 − 套路卡 1');
    expect(
      <String>[
        for (final i in appNavVisiblePageIndexes) appNavDestinations[i].shortName
      ],
      _expectedVisibleNavLabels,
      reason: '可见短名顺序 = 显示层顺序（12 项）',
    );
  });
}
