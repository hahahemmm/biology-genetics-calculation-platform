// pedigree_2_1_tools_test.dart —— v2.1 图谱页 UI 集成：
// 预置亲本 / 基因频率对话框 / 位点致死筛选 / 多倍体开关（含双模式冒烟）。
//
// 参照 pedigree_history_test 的 pumpHome / _derive 模式；历史存储注入
// 临时文件隔离真实用户数据（同 pedigree_history_test）。
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:biology/pages/genetic_pedigree_page.dart';
import 'package:biology/pages/widgets/pedigree_canvas.dart';
import 'package:biology/state/history_store.dart';
import 'package:biology/state/theme_controller.dart';

Widget _app() => const MaterialApp(home: GeneticPedigreePage());

Future<void> pumpHome(WidgetTester tester) async {
  tester.view.physicalSize = const Size(800, 800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(_app());
}

Future<void> _derive(WidgetTester tester) async {
  await tester.tap(find.text('计算').first);
  await tester.pumpAndSettle();
}

Future<void> _enterParents(WidgetTester tester, String p1, String p2) async {
  await tester.enterText(find.widgetWithText(TextField, '亲本 ♂'), p1);
  await tester.enterText(find.widgetWithText(TextField, '亲本 ♀'), p2);
}

void main() {
  setUp(() {
    HistoryStore.debugFilePath =
        '${Directory.systemTemp.createTempSync('biology_2_1_').path}/history.json';
  });
  tearDown(() => HistoryStore.debugFilePath = null);

  testWidgets('预置亲本：弹窗列题名，点选同时填入 ♂/♀ 输入框', (tester) async {
    await pumpHome(tester);
    await _derive(tester); // 默认 AABBCC × aabbcc
    // 先改成别的组合，验证预置真正回填而非巧合
    await _enterParents(tester, 'aaBBcc', 'AAbbcc');
    await tester.tap(find.text('预置'));
    await tester.pumpAndSettle();
    expect(find.text('纯合显性 × 纯合隐性（三对基因）'), findsOneWidget,
        reason: '预置对话框列出题名');
    expect(find.text('测交（三对基因）'), findsOneWidget);
    // 预置 9 条起超出弹窗可视高度：末条（多倍体示例）要滚到底才构建；
    // 断言完滚回头条再点选，回填验证不变。
    final list = find.descendant(
        of: find.byType(AlertDialog), matching: find.byType(Scrollable));
    await tester.scrollUntilVisible(find.textContaining('三倍体示例'), 120,
        scrollable: list);
    expect(find.textContaining('三倍体示例'), findsOneWidget);
    await tester.drag(list, const Offset(0, 600)); // 滚回头条再点选
    await tester.pumpAndSettle();
    await tester.tap(find.text('纯合显性 × 纯合隐性（三对基因）'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(TextField, 'AABBCC'), findsOneWidget,
        reason: '♂ 输入框被预置回填');
    expect(find.widgetWithText(TextField, 'aabbcc'), findsOneWidget,
        reason: '♀ 输入框被预置回填');
  });

  testWidgets('基因频率：对话框列位点/等位/基因型频率（A/a p=q=50.0%）',
      (tester) async {
    await pumpHome(tester);
    await _derive(tester); // 默认 AABBCC × aabbcc
    await tester.tap(find.text('计算基因频率'));
    await tester.pumpAndSettle();
    final dlg = find.byType(AlertDialog);
    expect(dlg, findsOneWidget, reason: '基因频率对话框弹出');
    expect(find.descendant(of: dlg, matching: find.text('基因频率')),
        findsOneWidget);
    expect(find.descendant(of: dlg, matching: find.text('位点')), findsOneWidget);
    expect(find.descendant(of: dlg, matching: find.text('A/a')), findsOneWidget,
        reason: 'A/a 位点行');
    expect(find.descendant(of: dlg, matching: find.text('B/b')), findsOneWidget);
    expect(find.descendant(of: dlg, matching: find.text('C/c')), findsOneWidget);
    expect(find.descendant(of: dlg, matching: find.text('AA')), findsOneWidget,
        reason: 'AA 列');
    expect(find.descendant(of: dlg, matching: find.text('50.0%')), findsWidgets,
        reason: 'p=q=0.5 → 50.0%');
  });

  testWidgets('致死筛选 v2.1i：Aa×Aa+AA 致死 → AA 保留+isLethal，活 Aa:aa=2:1',
      (tester) async {
    await pumpHome(tester);
    await _enterParents(tester, 'Aa', 'Aa');
    await _derive(tester);
    await tester.tap(find.text('致死'));
    await tester.pumpAndSettle();
    expect(find.text('位点致死筛选'), findsOneWidget, reason: '致死对话框弹出');
    await tester.enterText(
        find.widgetWithText(TextField, '致死基因型（如 AA / aa / BB…）'), 'AA');
    await tester.ensureVisible(find.text('添加'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('添加'));
    await tester.pumpAndSettle();
    expect(find.textContaining('A 位点：AA 纯合致死'), findsOneWidget,
        reason: '列表显示已设条件');
    // 多倍体未开时 AAA 被拒
    await tester.enterText(
        find.widgetWithText(TextField, '致死基因型（如 AA / aa / BB…）'), 'AAA');
    await tester.tap(find.text('添加'));
    await tester.pumpAndSettle();
    expect(find.textContaining('未开启多倍体'), findsOneWidget);
    // 再加 BB → 第二位点致死（不限于 A）
    await tester.enterText(
        find.widgetWithText(TextField, '致死基因型（如 AA / aa / BB…）'), 'BB');
    await tester.tap(find.text('添加'));
    await tester.pumpAndSettle();
    expect(find.textContaining('B 位点：BB 纯合致死'), findsOneWidget);
    await tester.tap(find.byTooltip('删除该致死条件').last);
    await tester.pumpAndSettle();
    expect(find.textContaining('B 位点：BB 纯合致死'), findsNothing);
    await tester.tap(find.text('确定'));
    await tester.pumpAndSettle();
    final c = tester.widget<PedigreeCanvas>(find.byType(PedigreeCanvas));
    final f1 = c.nodes.where((n) => n.generation == 1).toList();
    // v2.1i 致死节点保留在 F1，画 ✕ + lethal 色
    final lethal = f1.where((n) => n.isLethal).toList();
    expect(lethal.length, 1, reason: 'AA 致死后剩 1 个致死节点');
    expect(lethal.single.genotype, 'AA');
    // 致死节点内部归一：单桶 = 1.0
    expect(lethal.single.probability, closeTo(1.0, 1e-9),
        reason: '致死桶内部归一');
    // 存活子代内部归一：Aa(2/3) + aa(1/3)
    final alive = f1.where((n) => !n.isLethal).toList();
    expect(alive.length, 2, reason: 'A 位点 Aa + aa 两桶');
    final aliveByG = {for (final n in alive) n.genotype: n.probability};
    expect(aliveByG['Aa'], closeTo(2 / 3, 1e-9));
    expect(aliveByG['aa'], closeTo(1 / 3, 1e-9));
    expect(alive.every((n) => !n.genotype.startsWith('AA')), isTrue,
        reason: '存活子代不包含 AA');
    // canvas widget 含致死节点（id 前缀 Lf1#）
    expect(c.nodes.any((n) => n.isLethal && n.genotype == 'AA'), isTrue);
  });

  testWidgets('多倍体：未开启 3n 报错；开启开关后计算成功', (tester) async {
    await pumpHome(tester);
    await _enterParents(tester, 'AaaBbbCcc', 'AaaBbbCcc');
    await _derive(tester);
    expect(find.textContaining('成对字母'), findsOneWidget,
        reason: '严格 2n 模式拒绝 3n 输入并提示');
    // 开启「多倍体」开关 → 重算成功
    await tester.tap(find.text('多倍体'));
    await tester.pumpAndSettle();
    await _derive(tester);
    final c = tester.widget<PedigreeCanvas>(find.byType(PedigreeCanvas));
    expect(c.nodes.length, greaterThan(2), reason: '画布出现节点');
    expect(tester.takeException(), isNull, reason: '3n 计算无异常');
  });

  testWidgets('双模式冒烟：浅/深各 pump 含新按钮页面，无异常', (tester) async {
    // 深色
    ThemeController.instance.debugSetMode(ThemeMode.dark);
    await pumpHome(tester);
    await _derive(tester);
    expect(find.text('预置'), findsOneWidget);
    expect(find.text('计算基因频率'), findsOneWidget);
    expect(find.text('致死'), findsOneWidget);
    expect(find.text('多倍体'), findsOneWidget);
    expect(tester.takeException(), isNull, reason: '深色模式无异常');
    // 浅色（重新 pump，冷启动路径）
    ThemeController.instance.debugSetMode(ThemeMode.light);
    await pumpHome(tester);
    await _derive(tester);
    expect(find.text('预置'), findsOneWidget);
    expect(find.text('计算基因频率'), findsOneWidget);
    expect(find.text('致死'), findsOneWidget);
    expect(find.text('多倍体'), findsOneWidget);
    expect(tester.takeException(), isNull, reason: '浅色模式无异常');
    ThemeController.instance.debugSetMode(ThemeMode.system);
  });
}