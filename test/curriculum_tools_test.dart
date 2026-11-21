// curriculum_tools_test.dart —— v2.0 课标工具三页 widget 冒烟
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:biology/data/curriculum_2020.dart';
import 'package:biology/pages/curriculum_page.dart';
import 'package:biology/pages/evolution_page.dart';
import 'package:biology/pages/genetic_disease_page.dart';
import 'package:biology/pages/molecular_page.dart';

/// ListView 惰性构建：先滚到树中，再 ensureVisible 拉进视口（缓存区
/// 内的元素树中存在但不可点）。返回后目标保证 hit-testable。
/// v2.19.21：工作台化后页面主体是 SingleChildScrollView（非 ListView），
/// drag 循环仅在 ListView 存在时执行。
Future<void> _reveal(WidgetTester tester, Finder finder) async {
  final listView = find.byType(ListView);
  for (var i = 0; i < 14 && finder.evaluate().isEmpty && listView.evaluate().isNotEmpty; i++) {
    await tester.drag(listView.first, const Offset(0, -160));
    await tester.pumpAndSettle();
  }
  if (finder.evaluate().isNotEmpty) {
    await tester.ensureVisible(finder.first);
    await tester.pumpAndSettle();
  }
  expect(finder, findsWidgets, reason: '滚动后目标应可见');
}

/// v2.19.21 工作台化：顶部 TabBar 切 tab（目标 tab 懒构建后才可交互）。
Future<void> _switchTab(WidgetTester tester, String label) async {
  await tester.tap(find.text(label));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('课标体系页：左树导航分概念渲染、概览可开（v2.19.28 工作台）',
      (tester) async {
    // v2.19.28 UI 统一：课标页改左树导航 + 右条目工作台——宽视口走
    // 左栏（条目全渲染、无横滚懒构建），先切到目标分组再断言。
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const MaterialApp(home: CurriculumPage()));
    await tester.pumpAndSettle();
    // 左栏组头 = 大概念全称（「概念3」字样不再单独出现）。
    expect(find.textContaining('遗传信息控制生物性状'), findsWidgets);
    // 默认选中概念3 首个概念（3.1）：3.1.1 条目直接平铺右区。
    expect(find.text('3.1.1'), findsOneWidget,
        reason: '默认选中概念3·3.1，其条目可见');
    // 点 3.2 概念 → 其下 3.2.3「分离和自由组合」条目平铺右区。
    await tester.tap(find.text('有性生殖中基因的分离和重组'));
    await tester.pumpAndSettle();
    expect(find.textContaining('基因的分离和自由组合'), findsWidgets,
        reason: '3.2 概念下 3.2.3 可见');
    // 点概念4 的 4.2 → 4.2.2「优势性状」可见。
    await tester.tap(find.text('适应是自然选择的结果'));
    await tester.pumpAndSettle();
    expect(find.textContaining('优势性状'), findsWidgets);
    // 概览对话框（AppBar 直达，布局无关）。
    await tester.tap(find.text('概览'));
    await tester.pumpAndSettle();
    expect(find.text('课标覆盖概览'), findsOneWidget);
    // 右区说明文字亦含「22 条」→ 断言放宽为 findsWidgets（概览含统计）。
    expect(find.textContaining('22 条'), findsWidgets);
  });

  testWidgets('进化页：30/60/10 → A=60%、平衡判定偏离；淘汰模拟有结果',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(home: EvolutionPage()));
    await tester.pumpAndSettle();
    // v2.19.21 工作台化：基因频率在「基因频率」tab
    await _switchTab(tester, '基因频率');
    // 默认输入 10/60/30 → 计算
    await tester.tap(find.text('计算基因频率'));
    await tester.pumpAndSettle();
    await _reveal(tester, find.textContaining('A = 60.0%'));
    expect(find.textContaining('A = 60.0%'), findsOneWidget);
    expect(find.textContaining('偏离'), findsOneWidget,
        reason: '30:60:10 基因型频率不满足 p²/2pq/q²（教学反例）');
    // 选择模拟：默认 q0=0.5, 5 代, 淘汰隐性 → F0..F5 输出
    await _switchTab(tester, '选择模拟');
    await tester.tap(find.text('开始模拟'));
    await tester.pumpAndSettle();
    expect(find.textContaining('F0 = 50.0%'), findsOneWidget);
    expect(find.textContaining('F1 = 33.3%'), findsOneWidget,
        reason: '淘汰隐性纯合后 a 频率 1/3');
    expect(find.textContaining('a 频率持续下降'), findsOneWidget);
  });

  testWidgets('分子页：碱基互补 30→G=C=20、复制 3 次 8 分子、6:3:1、配子 2ⁿ',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(home: MolecularPage()));
    await tester.pumpAndSettle();
    // v2.19.21 工作台化：Tab0「碱基组成」默认挂载
    await tester.tap(find.text('计算碱基组成'));
    await tester.pumpAndSettle();
    expect(find.textContaining('G=20.0%'), findsOneWidget);
    await _switchTab(tester, '复制与标记');
    await tester.tap(find.text('计算复制结果'));
    await tester.pumpAndSettle();
    expect(find.textContaining('2^3 = 8 个'), findsOneWidget);
    expect(find.textContaining('2 个（半保留复制特征）'), findsOneWidget);
    await _switchTab(tester, '基因表达');
    await tester.tap(find.text('计算各阶段碱基数'));
    await tester.pumpAndSettle();
    expect(find.textContaining('mRNA 碱基数'), findsWidgets);
    expect(find.text('300'), findsWidgets, reason: '50 氨基酸 → mRNA 300');
    await _switchTab(tester, '配子种类');
    await tester.tap(find.text('计算配子种类'));
    await tester.pumpAndSettle();
    expect(find.textContaining('2ⁿ = 4 种'), findsOneWidget,
        reason: '2 对 → 4 种');
  });

  // v2.19.36：携带者口径修正（纯合显性 XAXA 不再是携带者）——
  // XAY × XAXa 的携带者**只有 XAXa = 1/4**（旧引擎误把 XAXA 计入 = 1/2，
  // 备份仓 v2.19.163 同款病灶）。患病 1/4（XaY）与携带 1/4（XAXa）同值 ⇒
  // 「25.0%」出现两次。守卫网 CG7g 与 genetic_disease_test 携带者组同口径。
  testWidgets('遗传病页：默认 XAY×XAXa 隐性 → 患病 25%、携带 25%；分类速查可见',
      (tester) async {
    await tester.pumpWidget(
        const MaterialApp(home: GeneticDiseasePage()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('计算'));
    await tester.pumpAndSettle();
    await _reveal(tester, find.text('25.0%').first);
    expect(find.text('25.0%'), findsNWidgets(2),
        reason: 'XaY 患病率 1/4 + XAXa 携带率 1/4（各一行，同值不同义）');
    // v2.19.28 工作台化：分类速查收在「分类与预防」tab（index 2）。
    await tester.tap(find.text('分类与预防'));
    await tester.pumpAndSettle();
    expect(find.text('伴 X 隐性'), findsOneWidget,
        reason: '分类速查含伴 X 隐性类目');
  });

  test('课标数据：22 条且含 8 个工具映射', () {
    expect(curriculum2020.length, 22);
    expect(curriculum2020.where((i) => i.tool != null).length, greaterThan(7));
    expect(curriculum2020.first.code, '3.1.1');
    expect(curriculum2020.last.code, '4.2.5');
  });
}