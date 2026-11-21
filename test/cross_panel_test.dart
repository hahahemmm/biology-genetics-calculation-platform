// cross_panel_test.dart —— v3.8 系谱页内嵌 9331 杂交计算面板测试
//
// 覆盖：
//   1. 开关常驻关闭：默认不渲染面板，点「杂交计算」才展开；
//   2. 懒计算：改输入不触发计算，只有点「开始计算」才算；
//   3. 轮流填充：导入/点选依次填亲本1→亲本2→循环；
//   4. 倍性分支：三倍体给「联会紊乱」提示；一倍体正常出结果。
//
// v2.13 R5 P1A：setUp 注入 GeneticPedigreePage.debugFilePath 指向
// SystemTemp 下的临时文件，避免读到用户 ~/.biology_app/cross_panel.json
// 的 `{"open":true}` 残留状态——否则 initState 加载 → 面板默认展开
// → 「开关常驻关闭」与「轮流填充：导入自动打开」两个测试连环失败
// （expected findsNothing 但 findsWidgets("开始计算")）。

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:biology/engine/kaoji_calc.dart';
import 'package:biology/pages/genetic_pedigree_page.dart';
import 'package:biology/pages/widgets/pedigree_cross_panel.dart';
import 'package:biology/theme.dart';

late Directory _isolatedDir;
String _isolatedPath() => '${_isolatedDir.path}/cross_panel.json';

Widget _app() => const MaterialApp(home: GeneticPedigreePage());

Future<void> pumpHome(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1000, 800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(_app());
  await tester.pumpAndSettle();
}

Future<void> openPanel(WidgetTester tester) async {
  await tester.tap(find.text('杂交计算'));
  await tester.pumpAndSettle();
}

// v2.19.19：面板含 9331 块 + 单基因/连锁迷你块，「亲本 1/2」标签各
// 出现多次——first = 9331 块（Column 序最先），迷你块在其后。
Finder p1Field() =>
    find.widgetWithText(TextField, '亲本 1').first;
Finder p2Field() =>
    find.widgetWithText(TextField, '亲本 2').first;

void main() {
  setUp(() {
    GeneticPedigreePage.debugResetHooks();
    _isolatedDir = Directory.systemTemp.createTempSync('cross_panel_test_');
    GeneticPedigreePage.debugFilePath = _isolatedPath();
  });

  tearDown(() {
    GeneticPedigreePage.debugFilePath = null;
    GeneticPedigreePage.debugResetHooks();
    if (_isolatedDir.existsSync()) {
      _isolatedDir.deleteSync(recursive: true);
    }
  });

  testWidgets('开关常驻关闭：默认无面板，点「杂交计算」后展开', (tester) async {
    await pumpHome(tester);
    expect(find.text('开始计算'), findsNothing);
    expect(find.text('杂交计算'), findsOneWidget);
    await openPanel(tester);
    expect(find.text('开始计算'), findsOneWidget);
    expect(find.text('尚未计算'), findsOneWidget);
  });

  testWidgets('懒计算：输入不自动算，点「开始计算」才出 9:3:3:1',
      (tester) async {
    await pumpHome(tester);
    await openPanel(tester);
    await tester.enterText(p1Field(), 'AaBb');
    await tester.enterText(p2Field(), 'AaBb');
    await tester.pumpAndSettle();
    expect(find.text('9:3:3:1'), findsNothing, reason: '仅输入不得触发计算');

    await tester.tap(find.text('开始计算'));
    await tester.pumpAndSettle();
    expect(find.text('9:3:3:1'), findsOneWidget);
    expect(find.text('标准 9:3:3:1'), findsOneWidget);
    expect(find.text('二倍体 · 2 对基因'), findsOneWidget);
  });

  testWidgets('结果过期提示：计算后改输入不重算，提示结果来自上次',
      (tester) async {
    await pumpHome(tester);
    await openPanel(tester);
    await tester.enterText(p1Field(), 'AaBb');
    await tester.enterText(p2Field(), 'AaBb');
    await tester.tap(find.text('开始计算'));
    await tester.pumpAndSettle();
    expect(find.text('9:3:3:1'), findsOneWidget);

    await tester.enterText(p2Field(), 'aabb');
    await tester.pumpAndSettle();
    expect(find.text('9:3:3:1'), findsOneWidget, reason: '改输入不得重算');
    expect(find.textContaining('结果来自上次'), findsOneWidget);
  });

  testWidgets('轮流填充：导入依次填亲本1→亲本2→亲本1，且自动打开面板',
      (tester) async {
    await pumpHome(tester);
    expect(find.text('开始计算'), findsNothing);
    final state =
        tester.state(find.byType(GeneticPedigreePage)) as dynamic;
    state.debugImportToCross('AaBb');
    await tester.pumpAndSettle();
    expect(find.text('开始计算'), findsOneWidget, reason: '导入应自动打开面板');
    expect(state.debugCrossP1, 'AaBb');
    expect(state.debugCrossNextSlot, 2);

    state.debugImportToCross('AABB');
    await tester.pumpAndSettle();
    expect(state.debugCrossP2, 'AABB');
    expect(state.debugCrossNextSlot, 1);

    state.debugImportToCross('aabb');
    await tester.pumpAndSettle();
    expect(state.debugCrossP1, 'aabb', reason: '第三轮循环覆盖亲本1');

    // 非法基因型（含缺失标记）：toast 提示且不填
    state.debugImportToCross('A-Bb');
    await tester.pumpAndSettle();
    expect(state.debugCrossP2, 'AABB', reason: '非法输入不得覆盖');
  });

  testWidgets('三倍体：给联会紊乱提示，不出比例', (tester) async {
    await pumpHome(tester);
    await openPanel(tester);
    await tester.enterText(p1Field(), 'AAaBbb');
    await tester.enterText(p2Field(), 'AaaBBb');
    await tester.tap(find.text('开始计算'));
    await tester.pumpAndSettle();
    expect(find.textContaining('联会紊乱'), findsOneWidget);
    expect(find.text('表型比例'), findsNothing);
  });

  testWidgets('一倍体：AB × ab → 子代全为 AaBb', (tester) async {
    await pumpHome(tester);
    await openPanel(tester);
    await tester.enterText(p1Field(), 'AB');
    await tester.enterText(p2Field(), 'ab');
    await tester.tap(find.text('开始计算'));
    await tester.pumpAndSettle();
    expect(find.text('单倍体杂交'), findsOneWidget);
    expect(find.text('一倍体 · 2 对基因'), findsOneWidget);
    expect(find.text('AaBb'), findsWidgets);
  });

  testWidgets('位点数不一致：中文错误提示', (tester) async {
    await pumpHome(tester);
    await openPanel(tester);
    await tester.enterText(p1Field(), 'AaBb');
    await tester.enterText(p2Field(), 'AaBbCc');
    await tester.tap(find.text('开始计算'));
    await tester.pumpAndSettle();
    expect(find.textContaining('倍性须一致'), findsOneWidget);
  });

  // v2.19.20 回归：浅色字 bug 复发根因 = 迷你块被 const 实例化 →
  // canonicalize 后与旧 widget identical → Element.update 短路永不
  // rebuild → 主题切换时显式 style 色值永久冻结（v2.2 白底白字
  // b8b78c2/cdb4ebc 同型事故）。此处端到端验证：面板先以 light 构建，
  // 再整体切 dark rebuild，迷你块标题色必须跟随变化。
  testWidgets('主题切换：迷你块标题色必须跟随（identical 短路回归）',
      (tester) async {
    AppColors.debugClearOverride();
    addTearDown(AppColors.debugClearOverride);

    Widget shell(Brightness b) {
      final p1 = TextEditingController(text: 'Aa');
      final p2 = TextEditingController(text: 'Aa');
      addTearDown(() {
        p1.dispose();
        p2.dispose();
      });
      return MaterialApp(
        theme: b == Brightness.dark ? AppTheme.dark() : AppTheme.light(),
        home: Scaffold(
          body: SizedBox(
            width: 340,
            height: 900,
            child: PedigreeCrossPanel(
              overlay: true,
              p1Ctrl: p1,
              p2Ctrl: p2,
              nextSlot: 1,
              result: const AutoCrossResult(
                  error: '占位', ploidy: 2, loci: 2),
              snapshot: '',
              onClose: () {},
              onStart: () {},
              onOpenInCalculator: () {},
            ),
          ),
        ),
      );
    }

    AppColors.sync(Brightness.light);
    await tester.pumpWidget(shell(Brightness.light));
    await tester.pump();
    final lightColor =
        tester.widget<Text>(find.text('单基因速算')).style!.color!;
    expect(lightColor, AppColors.inkL);

    AppColors.sync(Brightness.dark);
    await tester.pumpWidget(shell(Brightness.dark));
    await tester.pump();
    final darkColor =
        tester.widget<Text>(find.text('单基因速算')).style!.color!;
    expect(darkColor, AppColors.inkD);
    expect(darkColor, isNot(lightColor),
        reason: '迷你块标题色必须随主题切换——若 identical 短路则两帧相同');
  });
}
