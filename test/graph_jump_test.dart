// graph_jump_test.dart —— v2.2 知识图谱节点 → 软件功能双向跳转验收
//
// 用户需求：图谱节点点击弹出详情，详情里给出该知识点对应的软件功能按钮，
// 点击直达功能页；且必须是双向跳转（与课标 chip 共用同一套机制：
// HomeShell 切导航索引 + 顶部回程横幅）。

import 'package:biology/main.dart';
import 'package:biology/pages/cross_calculator_page.dart';
import 'package:biology/pages/knowledge_graph_page.dart';
import 'package:biology/pages/molecular_page.dart';
import 'package:biology/state/theme_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/ready_app.dart';

void main() {
  Future<void> guardTheme(WidgetTester t) async {
    // ThemeController.load() 真实 I/O 竞态防护（既有模式）。
    final c = ThemeController.instance;
    await t.runAsync(() => c.debugEnsureLoaded());
    c.debugSetMode(ThemeMode.light);
    addTearDown(() => c.debugSetMode(ThemeMode.system));
  }

  testWidgets('节点详情功能按钮：显示→点击回调导航索引→sheet 关闭', (t) async {
    await guardTheme(t);
    int? jumped;
    await t.pumpWidget(
      MaterialApp(home: KnowledgeGraphPage(onOpenTool: (i) => jumped = i)),
    );
    await t.pumpAndSettle();

    // 经测试钩子弹「9331」节点详情（画布坐标点击在测试中太脆）
    final state = t.state(find.byType(KnowledgeGraphPage)) as dynamic;
    state.debugShowDetail('9331');
    await t.pumpAndSettle();

    // 详情 sheet：功能按钮 + 回程提示文案
    expect(
      find.text('打开对应功能：遗传计算器'),
      findsOneWidget,
      reason: '9331 节点应映射到遗传计算器',
    );
    expect(find.text('跳转后可点顶部横幅返回本页'), findsOneWidget);

    await t.tap(find.text('打开对应功能：遗传计算器'));
    await t.pumpAndSettle();
    expect(jumped, 2, reason: '回调应传出遗传计算器导航索引 2');
    expect(
      find.text('打开对应功能：遗传计算器'),
      findsNothing,
      reason: '跳转后详情 sheet 应关闭（不残留遮挡目标页）',
    );
  });

  testWidgets('映射表覆盖：全部节点都有功能映射', (t) async {
    // 泵出页面后通过 debugShowDetail 逐节点验证按钮存在成本太高；
    // 映射完整性由数据测试保证：19 个节点 id 全部在映射表内。
    // v2.21.0：映射表已迁到 lib/ui/module_link.dart（节点 → 稳定
    // destinationId + 展示 label，导航索引由 appNavigation 顺序派生），
    // 完整性由 test/module_link_test.dart 的 M2 逐条钉死；此处抽验代表节点
    // 仍能一路走到 onOpenTool(int)（索引与跳转行为不变）。
    await guardTheme(t);
    int? jumped;
    await t.pumpWidget(
      MaterialApp(home: KnowledgeGraphPage(onOpenTool: (i) => jumped = i)),
    );
    await t.pumpAndSettle();
    final state = t.state(find.byType(KnowledgeGraphPage)) as dynamic;

    // 系谱分析 → 遗传图谱（1）
    state.debugShowDetail('pedigree-analysis');
    await t.pumpAndSettle();
    expect(find.text('打开对应功能：遗传图谱'), findsOneWidget);
    await t.tap(find.text('打开对应功能：遗传图谱'));
    await t.pumpAndSettle();
    expect(jumped, 1);

    // DNA/基因 → 分子（5）
    state.debugShowDetail('dna-genes-alleles');
    await t.pumpAndSettle();
    expect(find.text('打开对应功能：分子遗传'), findsOneWidget);
    await t.tap(find.text('打开对应功能：分子遗传'));
    await t.pumpAndSettle();
    expect(jumped, 5);
  });

  testWidgets('端到端：图谱节点跳功能页 → 回程横幅 → 返回图谱（双向）', (t) async {
    await guardTheme(t);
    // 宽屏视口走 Rail（IndexedStack 非激活页 offstage，须先导航激活
    // 才能用默认 finder 拿到页面 state）。
    t.view.physicalSize = const Size(1400, 900);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);

    await pumpReadyBiologyApp(t);

    // 导航到图谱页
    final railGraph = find.descendant(
      of: find.byType(NavigationRail),
      matching: find.text('图谱'),
    );
    await t.tap(railGraph.first);
    await t.pumpAndSettle();

    // 点「9331 变式 9:7」节点（经钩子弹详情；画布坐标点击太脆）
    final state = t.state(find.byType(KnowledgeGraphPage)) as dynamic;
    state.debugShowDetail('9331-variant-97');
    await t.pumpAndSettle();
    await t.tap(find.text('打开对应功能：遗传计算器'));
    await t.pumpAndSettle();

    // ① 直达遗传计算器（导航索引 2），不压路由栈
    expect(t.widget<IndexedStack>(find.byType(IndexedStack)).index, 2);
    expect(
      t.state<NavigatorState>(find.byType(Navigator).first).canPop(),
      isFalse,
      reason: '必须是页面内跳转，不得 push 路由栈',
    );
    // ② 回程横幅显示来源（图谱）
    expect(find.text('来自知识图谱 · 点击返回图谱页'), findsOneWidget);

    // ③ 点横幅 → 回图谱页（索引 3）+ 横幅消失
    await t.tap(find.text('来自知识图谱 · 点击返回图谱页'));
    await t.pumpAndSettle();
    expect(t.widget<IndexedStack>(find.byType(IndexedStack)).index, 3);
    expect(find.text('来自知识图谱 · 点击返回图谱页'), findsNothing);
  });

  testWidgets('页内深链：伴性节点落到伴性页签，不回填学生原题', (t) async {
    await guardTheme(t);
    t.view.physicalSize = const Size(1400, 900);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    await pumpReadyBiologyApp(t);

    // 先在 9331 留下学生自己的题，再从图谱跳伴性；本题只能保活，不能被
    // 深链顺手改写成另一份示范参数。
    await t.tap(find.descendant(
      of: find.byType(NavigationRail),
      matching: find.text('9331'),
    ));
    await t.pumpAndSettle();
    await t.enterText(find.widgetWithText(TextField, '亲本 1'), 'AAbb');
    await t.pump();

    await t.tap(find.descendant(
      of: find.byType(NavigationRail),
      matching: find.text('图谱'),
    ));
    await t.pumpAndSettle();
    final graph = t.state(find.byType(KnowledgeGraphPage)) as dynamic;
    graph.debugShowDetail('sex-linked');
    await t.pumpAndSettle();
    await t.tap(find.text('打开对应功能：遗传计算器'));
    await t.pumpAndSettle();

    final tabBar = t.widget<TabBar>(find.descendant(
      of: find.byType(CrossCalculatorPage),
      matching: find.byType(TabBar),
    ));
    expect(tabBar.controller!.index, 3, reason: '伴性节点必须到伴性遗传页签');
    expect(find.byType(NavigationRail), findsOneWidget);
    expect(find.text('来自知识图谱 · 点击返回图谱页'), findsOneWidget);

    await t.tap(find.text('双基因 9331'));
    await t.pumpAndSettle();
    expect(
      t.widget<TextField>(find.widgetWithText(TextField, '亲本 1')).controller!.text,
      'AAbb',
      reason: '页签导览不得覆盖学生已有输入',
    );
  });

  testWidgets('DNA 纯导览：分子页已改也不拦切页签、不清实验', (t) async {
    await guardTheme(t);
    t.view.physicalSize = const Size(1400, 900);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    await pumpReadyBiologyApp(t);

    await t.tap(find.descendant(
      of: find.byType(NavigationRail),
      matching: find.text('分子'),
    ));
    await t.pumpAndSettle();
    await t.ensureVisible(find.text('基因工程'));
    await t.tap(find.text('基因工程'));
    await t.pumpAndSettle();
    await t.ensureVisible(find.text('示例·HindIII 单位点'));
    await t.pumpAndSettle();
    await t.tap(find.text('示例·HindIII 单位点'));
    await t.pumpAndSettle();
    expect(find.textContaining('长度核算：4 + 8 = 12 bp'), findsOneWidget);

    await t.tap(find.descendant(
      of: find.byType(NavigationRail),
      matching: find.text('图谱'),
    ));
    await t.pumpAndSettle();
    final graph = t.state(find.byType(KnowledgeGraphPage)) as dynamic;
    graph.debugShowDetail('dna-genes-alleles');
    await t.pumpAndSettle();
    await t.tap(find.text('打开对应功能：分子遗传'));
    await t.pumpAndSettle();

    final tabBar = t.widget<TabBar>(find.descendant(
      of: find.byType(MolecularPage),
      matching: find.byType(TabBar),
    ));
    expect(tabBar.controller!.index, 0,
        reason: '纯导览不应被“参数未写入”的脏页闸误拦');
    expect(find.textContaining('目标页签已有你自己的题'), findsNothing);

    await t.tap(find.text('基因工程'));
    await t.pumpAndSettle();
    expect(find.textContaining('长度核算：4 + 8 = 12 bp'), findsOneWidget,
        reason: '往返导览后，学生原来的 HindIII 实验仍在');
  });
}
