// nav_shell_test.dart —— v3.7 导航常驻 + ☰ 只控制系谱面板 回归
//
// ☰ = 控制面板折叠开关：桌面 NavigationRail / 移动底部 NavigationBar
// 一律常驻，绝不被 ☰ 隐藏；☰ 只折叠/展开系谱左控制面板。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:biology/main.dart';
import 'package:biology/pages/genetic_pedigree_page.dart';
import 'package:biology/pages/widgets/pedigree_canvas.dart';

import 'support/ready_app.dart';

void main() {
  /// 2.2 批次4a：启动页=首页（Dashboard），进系谱页先点导航「遗传图谱」。
  Future<void> gotoPedigree(WidgetTester tester) async {
    await tester.tap(find.text('遗传图谱').first);
    await tester.pumpAndSettle();
  }

  testWidgets('☰ 只折叠系谱控制面板：导航 Rail 常驻，再按恢复面板',
      (tester) async {
    tester.view.physicalSize = const Size(1000, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await pumpReadyBiologyApp(tester);
    await gotoPedigree(tester);

    // 初始：宽屏 Rail 常驻 + 系谱左面板 + 命令栏 ☰
    expect(find.byType(NavigationRail), findsOneWidget,
        reason: '宽屏默认显示导航侧栏');
    expect(find.byIcon(Icons.menu), findsOneWidget, reason: '命令栏 ☰ 存在');
    await tester.tap(find.text('计算').first);
    await tester.pumpAndSettle();
    expect(find.text('同性交配'), findsOneWidget, reason: '左面板可见');

    // ☰ 折叠：只收面板，导航 Rail 必须仍在（v3.7 关键语义）
    await tester.tap(find.byIcon(Icons.menu));
    await tester.pumpAndSettle();
    expect(find.byType(NavigationRail), findsOneWidget,
        reason: '☰ 折叠不得隐藏导航侧栏（用户裁定导航常驻）');
    expect(find.text('同性交配'), findsNothing,
        reason: '折叠后系谱左面板收起');
    expect(find.byType(NavigationDrawer), findsNothing,
        reason: '不弹抽屉（☰ 为双向 toggle）');

    // 折叠后底部操作条仍常驻（计算/删除整代/计算下一代）
    expect(find.text('计算'), findsWidgets, reason: '底部计算按钮常驻');
    expect(find.text('删除整代'), findsOneWidget, reason: '底部删除按钮常驻');
    expect(find.text('计算下一代'), findsOneWidget, reason: '底部下一代按钮常驻');

    // 再点 ☰ → 面板完整恢复（双向）
    await tester.tap(find.byIcon(Icons.menu));
    await tester.pumpAndSettle();
    expect(find.byType(NavigationRail), findsOneWidget,
        reason: '再点 ☰ 导航侧栏仍常驻');
    expect(find.text('同性交配'), findsOneWidget,
        reason: '再点 ☰ 系谱左面板恢复');

    // 无「右上角面板开合按钮」残留
    expect(find.byIcon(Icons.view_sidebar_outlined), findsNothing);
    expect(find.byIcon(Icons.tune), findsNothing);
  });

  testWidgets('窄屏默认折叠：☰ 打开覆盖式控制面板，再按收起',
      (tester) async {
    // v2.19.26：导航阈值 840→600，「窄屏」用例视口从 600 改为 390×844
    //（真机手机语义；600 已命中 rail 档）。
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await pumpReadyBiologyApp(tester);
    await gotoPedigree(tester);
    await tester.tap(find.text('计算').first);
    await tester.pumpAndSettle();

    // 窄屏：底部横向滚导常驻 + 控制面板默认折叠（画布最大化）
    expect(find.byType(NavigationRail), findsNothing);
    // v2.0 自研横向滚导（2.1 起 11 项可达：含 真题/系谱/课标/分子/进化）
    expect(find.text('进化'), findsOneWidget, reason: '窄屏底导含新条目');
    expect(find.text('课标'), findsOneWidget, reason: '窄屏底导含课标条目');
    expect(find.text('同性交配'), findsNothing, reason: '窄屏默认面板折叠');

    // ☰ → 覆盖式控制面板出现（含计算/XY 等，可操作）
    await tester.tap(find.byIcon(Icons.menu));
    await tester.pumpAndSettle();
    expect(find.text('同性交配'), findsOneWidget,
        reason: '☰ 打开覆盖式控制面板');
    // v2.19.26：「删除整代」断言移除——390 宽下底缘操作条走横向滚动
    // 兜底（按钮被裁出视口但仍在树内可滑达），底部条常驻语义已由
    // 宽屏用例（:48-51）覆盖，这里不重复。

    // 再按 → 收起
    await tester.tap(find.byIcon(Icons.menu));
    await tester.pumpAndSettle();
    expect(find.text('同性交配'), findsNothing, reason: '再按收起面板');
  });

  testWidgets('画布内容包围盒：计算后非零且包含 P 代区域（AI 截图 ROI）',
      (tester) async {
    tester.view.physicalSize = const Size(1000, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
        const MaterialApp(home: GeneticPedigreePage()));
    await tester.pumpAndSettle();
    // 未计算：画布尚未挂载（空状态页）
    expect(find.byType(PedigreeCanvas), findsNothing,
        reason: '未计算时无画布');
    await tester.tap(find.text('计算').first);
    await tester.pumpAndSettle();
    final st = tester
        .state<PedigreeCanvasState>(find.byType(PedigreeCanvas));
    final roi = st.debugContentRect();
    expect(roi.isEmpty, isFalse, reason: '计算后 ROI 非空');
    expect(roi.width, greaterThan(0), reason: 'ROI 有宽度');
    expect(roi.height, greaterThan(0), reason: 'ROI 有高度');
  });

  testWidgets('页面独立构造（无 ☰ 注入）不渲染汉堡按钮', (tester) async {
    await tester.pumpWidget(
        const MaterialApp(home: GeneticPedigreePage()));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.menu), findsNothing,
        reason: '独立构造（测试/嵌入）不渲染 ☰');
    expect(find.text('同性交配'), findsOneWidget, reason: '左面板照常显示');
  });

  testWidgets('移动端「全部」导航面板：完整名称+用途教学，点项直达', (tester) async {
    // 窄屏手机视口：底导项多文字小，「全部」入口弹出完整导航。
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await pumpReadyBiologyApp(tester);

    // 底导最左「全部」入口存在
    expect(find.text('全部'), findsOneWidget, reason: '底导应有「全部」入口');
    await tester.tap(find.text('全部'));
    await tester.pumpAndSettle();

    // 面板：标题 + 教学引导文案 + 完整功能名（底导缩写「倍性」→ 完整「染色体倍性」）
    expect(find.text('全部功能导航'), findsOneWidget);
    expect(find.textContaining('底部导航栏可左右滑动'), findsOneWidget,
        reason: '面板应教学底导可滑动');
    expect(find.text('遗传图谱计算'), findsWidgets,
        reason: '面板列出完整功能名（非底导缩写）');

    // 点面板内「染色体倍性」→ 直达倍性页 + 面板关闭。
    //
    // v2.20.0：「全部」面板是 0.82×屏高的 ListView（标题 + 13 项），
    // ListView 惰性布局 ⇒ 390×844 下靠后的项可能还没构建，直接
    // find.text + tap 会「找不到/点不着」。正确姿势：先在**面板自己的
    // Scrollable** 里 scrollUntilVisible 滚到目标，再点——不碰生产语义
    // （面板仍是同一个懒加载 ListView）。
    final sheetItem = find.descendant(
      of: find.byType(BottomSheet),
      matching: find.text('染色体倍性'),
    );
    final sheetScrollable = find.descendant(
      of: find.byType(BottomSheet),
      matching: find.byType(Scrollable),
    );
    await tester.scrollUntilVisible(sheetItem, 120,
        scrollable: sheetScrollable);
    await tester.pumpAndSettle();
    await tester.tap(sheetItem);
    await tester.pumpAndSettle();
    expect(find.text('全部功能导航'), findsNothing, reason: '点项后面板应关闭');
    final stack = tester.widget<IndexedStack>(find.byType(IndexedStack));
    expect(stack.index, 7, reason: '应直达倍性页（导航索引 7）');
  });
}