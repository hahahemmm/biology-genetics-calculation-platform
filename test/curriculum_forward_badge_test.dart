// curriculum_forward_badge_test.dart —— v2.19.36 守卫（两块变更的牙齿）
//
//  · **A 正向徽章**（工具页结果区标题行）：⛔ 不是新造的一层「工具 ↔ 课标」
//    对应关系——code 仍由既有反向表 `curriculumReverseAnchors` 经
//    `curriculumReverseCodeOf` 从宿主页自己的 moduleId **唯一命中**反查，
//    公共口 = `curriculumReverseBadgeFor(context, moduleId)`（null 安全）。
//    守卫同时钉住反面：**多义** moduleId（分子页 `molecular` 一枚对
//    3.1.1/3.1.2/3.1.3/3.1.4/3.2.1 五条）一律**不挂**——挑一条就是凭空编造，
//    而学生在屏上**完全看不出来**（徽章照样可点、照样跳得过去）。
//  · **B 逐枚 chip**：3.2.3 的 `tool: '遗传图谱/9331'` 按 `/` 拆成两枚。
//    第 0 枚（`chipLinks[0] == null`）走原导航（主导航 1 号页 = 遗传图谱），
//    第 1 枚走 `chipLinks[1]` 的逐枚深链（`cross_dihybrid` + 示范题）。
//
// ## 判「可点」为什么不靠像素
// `curriculumReverseBadge` = `MouseRegion` + `Tooltip` + `InkWell` + `AppChip`，
// 其中 `Tooltip.message` 以「查看课标 」开头，而屏上那枚**静态** `AppChip`
// 没有这一层。「看着能点 vs 其实点不动」正是这层结构的差别，所以从结构钉。

import 'package:biology/main.dart';
import 'package:biology/pages/curriculum_page.dart';
import 'package:biology/pages/cross_calculator_page.dart';
import 'package:biology/pages/molecular_page.dart';
import 'package:biology/state/theme_controller.dart';
import 'package:biology/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/ready_app.dart';

/// 可点「课标 X」徽章的结构标记（见文件头）。
final Finder clickableCurriculumBadges = find.byWidgetPredicate(
  (w) => w is Tooltip && (w.message ?? '').startsWith('查看课标 '),
  description: '可点的「课标 X」徽章（Tooltip message 以「查看课标 」开头）',
);

void main() {
  // ══════════════════════════════════════════════════════════════
  // A：工具页结果区标题行的正向「课标 X」可点徽章
  // ══════════════════════════════════════════════════════════════

  testWidgets('A1：9331 双基因页签算出结果后，标题行出现**可点**的「课标 3.2.3」', (t) async {
    t.view.physicalSize = const Size(1600, 1000);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    AppColors.sync(Brightness.light);
    addTearDown(() => AppColors.sync(Brightness.light));

    await t.pumpWidget(const MaterialApp(home: CrossCalculatorPage()));
    await t.pumpAndSettle();

    // 前提：双基因页签 = `cross_dihybrid` ⇒ 唯一反查 3.2.3（同 CG8 判据）。
    // ⛔ 唯一命中才返回：这条断言同时钉住「公共 helper 复用既有反向表」，
    // 而不是在工具页里新写一张 code 表。
    expect(curriculumReverseCodeOf('cross_dihybrid'), '3.2.3');

    // 空态**不挂**：这一栏还没算出题，一枚可点徽章等于宣称一道**还不存在**
    // 的题考它（备份仓 `genetic_disease_page._consultCurriculumChip` 的
    // 同款纪律：静默把静态徽章变成「看着能点其实没题」比不给更糟）。
    expect(clickableCurriculumBadges, findsNothing, reason: '结果区空态不得出现可点徽章');

    await t.tap(find.text('计算比例'));
    await t.pumpAndSettle();

    expect(
      find.text('课标 3.2.3'),
      findsOneWidget,
      reason: '结果区标题行应挂一枚「课标 3.2.3」',
    );
    expect(
      clickableCurriculumBadges,
      findsOneWidget,
      reason: '必须是**可点**的那一枚（Tooltip 标记），不是静态 AppChip',
    );

    // 可点性：点一下 push 一份 focusCode=3.2.3 的课标页并高亮那一条。
    await t.tap(find.text('课标 3.2.3'));
    await t.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('curriculum-item-3.2.3')),
      findsOneWidget,
      reason:
          '点徽章必须 push 一份 focusCode=3.2.3 的课标页，'
          '并高亮**那一条**（守卫钉的 key）',
    );
    expect(find.text('正在查看'), findsOneWidget, reason: '被点名的那一条必须标出「正在查看」');
  });

  testWidgets('A2：多义页（分子页）**不挂**可点徽章——静态 chip 逐像素保留', (t) async {
    t.view.physicalSize = const Size(1600, 1000);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    AppColors.sync(Brightness.light);
    addTearDown(() => AppColors.sync(Brightness.light));

    await t.pumpWidget(const MaterialApp(home: MolecularPage()));
    await t.pumpAndSettle();

    // 前提：`molecular` 被 3.1.1 / 3.1.2 / 3.1.3 / 3.1.4 / 3.2.1 五条点名
    // ⇒ 多义 ⇒ 反查必须返 null（helper 据此不挂）。
    expect(
      curriculumReverseCodeOf('molecular'),
      isNull,
      reason: '多义 moduleId 必须返 null，helper 才能「不给」',
    );

    // 屏上那枚**静态** chip 仍在（`AppChip`，不可点）——本轮对它零像素变化。
    expect(find.text('课标 3.1.2'), findsWidgets, reason: '静态 chip 不许被本轮动过');

    // 算出结果（徽章唯一可能的挂点就是结果区标题行）⇒ 仍然零枚可点徽章。
    await t.tap(find.text('计算碱基组成'));
    await t.pumpAndSettle();
    expect(
      find.textContaining('A=30.0%'),
      findsOneWidget,
      reason: '前提：结果区确实算出来了（否则本例是恒真的空断言）',
    );

    expect(
      clickableCurriculumBadges,
      findsNothing,
      reason:
          '⛔ 多义页一枚可点课标徽章都不许有：'
          '挑一条就是替学生编造，而屏上完全看不出来',
    );
    expect(
      find.text('课标 3.1.2'),
      findsWidgets,
      reason: '静态 chip 仍在（本轮对它零像素变化）',
    );
  });

  // ══════════════════════════════════════════════════════════════
  // B：3.2.3 逐枚 chip（第 0 枚走导航 / 第 1 枚走深链）
  // ══════════════════════════════════════════════════════════════

  testWidgets('B1：3.2.3 拆成两枚——第 0 枚走原导航，第 1 枚走逐枚深链', (t) async {
    // 超高视口：课标列表全量构建，chip 直接可见可点（既有
    // curriculum_jump_test 同款口径，避开懒挂载滚动的脆弱性）。
    t.view.physicalSize = const Size(1400, 5200);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    AppColors.sync(Brightness.light);
    addTearDown(() => AppColors.sync(Brightness.light));

    // ThemeController.load() 真实 I/O 竞态防护（既有模式）。
    final c = ThemeController.instance;
    await t.runAsync(() => c.debugEnsureLoaded());
    c.debugSetMode(ThemeMode.light);
    addTearDown(() => c.debugSetMode(ThemeMode.system));

    await pumpReadyBiologyApp(t);

    final rail = find.descendant(
      of: find.byType(NavigationRail),
      matching: find.text('课标'),
    );
    expect(rail, findsWidgets, reason: '宽屏应有 Rail 标签「课标」');
    await t.tap(rail.first);
    await t.pumpAndSettle();

    // 3.2.3 收在关键概念 3.2 下。⚠️ 概念选中后左栏条目标签与右区分区
    // 标题**同名** ⇒ 第二次点它时命中 2 个，统一取 `.first`（左栏那条）。
    final concept32 = find.text('有性生殖中基因的分离和重组').first;
    await t.tap(concept32);
    await t.pumpAndSettle();

    // 逐枚渲染：两枚 chip 各带各的名字。
    // ⚠️ 3.2.2 的 `tool` 逐字也是「遗传图谱」⇒ 它的 chip 文字与 3.2.3 的
    // 第 0 枚**逐字相同**（两枚长得一样、落点不同，这正是逐枚化的现状）。
    // 所以两枚 chip 必须按**条目 tile** 作用域定位，否则 finder 命中 2 个。
    final tile323 = find.ancestor(
      of: find.textContaining('阐明有性生殖中基因的分离和自由组合'),
      matching: find.byType(ListTile),
    );
    final chip0 = find.descendant(
      of: tile323,
      matching: find.text('工具：遗传图谱 →'),
    );
    final chip1 = find.descendant(
      of: tile323,
      matching: find.text('工具：9331 →'),
    );
    expect(chip0, findsOneWidget, reason: '第 0 枚');
    expect(chip1, findsOneWidget, reason: '第 1 枚');
    expect(
      find.text('工具：遗传图谱/9331 →'),
      findsNothing,
      reason: '⛔ 整串 chip 必须消失（那正是「只落第一个目的地」的病灶）',
    );

    // 第 0 枚：`chipLinks[0] == null` ⇒ 无深链 ⇒ 回落**它自己那段文本**的
    // 字符串匹配 ⇒ 主导航 1 号页（遗传图谱），⛔ 不许被拽到 9331。
    await t.tap(chip0);
    await t.pumpAndSettle();
    expect(
      t.widget<NavigationRail>(find.byType(NavigationRail)).selectedIndex,
      1,
      reason:
          '第 0 枚（遗传图谱）必须走原导航：主导航 1 号页，'
          '⛔ 不许挂条目级/别枚的深链把它拽到 9331',
    );

    // 第 1 枚：走 `chipLinks[1]` 的逐枚深链 —— 切 9331 第 0 个页签
    // （双基因 9:3:3:1）并把示范题 AaBb × AaBb 真的算出来。
    await t.tap(rail.first);
    await t.pumpAndSettle();
    await t.tap(find.text('有性生殖中基因的分离和重组').first);
    await t.pumpAndSettle();

    await t.tap(chip1);
    await t.pumpAndSettle();
    expect(
      t.widget<NavigationRail>(find.byType(NavigationRail)).selectedIndex,
      2,
      reason: '第 1 枚（9331）应落到主导航 2 号页',
    );
    expect(
      find.text('9:3:3:1'),
      findsWidgets,
      reason:
          '深链必须把示范题带进 9331 并真算出结果'
          '（只在导航上「切了页」而没填题，这屏看着是另一道题）',
    );
  });
}
