// tab_jump_shortcuts_test.dart —— v2.19.49 Alt+数字 页签直跳守卫网
//
// 网型纪律（B 仓 v2.19.168 的教训固化）：**取基准必须用一条与被测动作
// 不同的通道**——基线页签一律用「初始态」或「鼠标点 TabBar」取得，
// 键盘只做被测动作；否则「每次按键都改写 controller」的变异会写进基准
// ⇒ 断言恒等 ⇒ 假绿。同理 G1（带 Alt 真切）与 G4（裸键让路）成对存在：
// 只有同一枚键在两个守卫里一「动」一「不动」，反向断言才不是空断言。
import 'package:biology/pages/cross_calculator_page.dart';
import 'package:biology/pages/evolution_page.dart';
import 'package:biology/pages/genetic_disease_page.dart';
import 'package:biology/pages/molecular_page.dart';
import 'package:biology/pages/ploidy_page.dart';
import 'package:biology/pages/variation_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _altDigit(WidgetTester t, LogicalKeyboardKey d) async {
  await t.sendKeyDownEvent(LogicalKeyboardKey.alt);
  await t.sendKeyEvent(d);
  await t.sendKeyUpEvent(LogicalKeyboardKey.alt);
  await t.pumpAndSettle();
}

/// 读当前页签下标：走 TabBar 的 controller（结构化读数，不靠屏上文字）。
/// 覆顶路由场景下被盖页的 TabBar 会离屏（offstage），故关 skipOffstage。
int _tabIndex(WidgetTester t) => t
    .widget<TabBar>(find.byType(TabBar, skipOffstage: false))
    .controller!
    .index;

void main() {
  // ── G1：六个多页签页 Alt+2 真切（每页一守卫）──
  for (final (name, page) in [
    ('分子页', const MolecularPage()),
    ('变异页', const VariationPage()),
    ('遗传病页', const GeneticDiseasePage()),
    ('进化页', const EvolutionPage()),
    ('倍性页', const PloidyPage()),
    ('9331', const CrossCalculatorPage()),
  ]) {
    testWidgets('G1·$name：Alt+2 直达第 2 个页签', (tester) async {
      await tester.pumpWidget(MaterialApp(home: page));
      await tester.pump();
      expect(_tabIndex(tester), 0, reason: '初始态基线（非键盘通道取得）');
      await _altDigit(tester, LogicalKeyboardKey.digit2);
      expect(_tabIndex(tester), 1, reason: 'Alt+2 → 页签下标 1');
    });
  }

  testWidgets('G2·9331：Alt+7 直达第 7 个页签（末页）', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: CrossCalculatorPage()));
    await tester.pump();
    await _altDigit(tester, LogicalKeyboardKey.digit7);
    expect(_tabIndex(tester), 6, reason: 'Alt+7 → 页签下标 6（0-based）');
  });

  testWidgets('G3·越界键让路：3 页签页按 Alt+4 原地不动', (tester) async {
    for (final page in [const PloidyPage(), const GeneticDiseasePage()]) {
      await tester.pumpWidget(MaterialApp(home: page));
      await tester.pump();
      await _altDigit(tester, LogicalKeyboardKey.digit4);
      expect(_tabIndex(tester), 0,
          reason: '页签数 3 < 4 ⇒ 闸 ⑤ 让路，键原样放行、不写数据');
    }
  });

  testWidgets('G4·裸数字让路：不按 Alt 时 digit2 不跳', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: MolecularPage()));
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.digit2);
    await tester.pumpAndSettle();
    expect(_tabIndex(tester), 0,
        reason: '无 Alt 修饰 ⇒ 闸 ① 让路（与 G1 成对，证明同一枚键两态');
  });

  testWidgets('G5·输入焦点让路：TextField 持焦时 Alt+2 不跳，失焦后跳',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(home: MolecularPage()));
    await tester.pump();
    await tester.enterText(find.byType(TextField).first, '30');
    await tester.pump();
    await _altDigit(tester, LogicalKeyboardKey.digit2);
    expect(_tabIndex(tester), 0,
        reason: '闸 ④：学生正在敲数字，键让路不抢输入');
    // 换焦（直接对焦点域操作，不走键盘通道），同一枚键此刻必须跳——
    // 证明刚才确实是焦点闸拦的，而不是这枚键整体失效。
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump();
    await _altDigit(tester, LogicalKeyboardKey.digit2);
    expect(_tabIndex(tester), 1);
  });

  testWidgets('G6·被盖住让路：push 路由覆顶时 Alt+2 不写本页页签',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(home: VariationPage()));
    await tester.pump();
    final ctx = tester.element(find.byType(VariationPage));
    Navigator.of(ctx).push(MaterialPageRoute<void>(
      builder: (_) => const Scaffold(body: Text('cover-route')),
    ));
    await tester.pumpAndSettle();
    expect(find.text('cover-route'), findsOneWidget, reason: '覆顶路由在场');
    await _altDigit(tester, LogicalKeyboardKey.digit2);
    expect(_tabIndex(tester), 0, reason: '闸 ③：本页不是当前路由 ⇒ 让路');
  });

  testWidgets('G7·只切页签不碰题面：键跳往返 + 鼠标跳，输入逐字不变',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(home: VariationPage()));
    await tester.pump();
    await tester.enterText(find.byType(TextField).first, 'ATCG');
    await tester.pump();
    // 焦点闸是 G5 的守卫对象——这里先摘焦（不走键盘通道），让键跳能发生。
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump();
    // 键盘通道：2 → 1 → 2 往返。
    await _altDigit(tester, LogicalKeyboardKey.digit2);
    expect(_tabIndex(tester), 1);
    await _altDigit(tester, LogicalKeyboardKey.digit1);
    expect(_tabIndex(tester), 0);
    // 鼠标通道（异通道基线）：点 TabBar 直达第 4 页签，再键回第 1 页签。
    await tester.tap(find.text('诱变与育种'));
    await tester.pumpAndSettle();
    expect(_tabIndex(tester), 3, reason: '鼠标点 TabBar = 页签切换的真基线');
    await _altDigit(tester, LogicalKeyboardKey.digit1);
    expect(_tabIndex(tester), 0);
    // 题面逐项不动。
    expect(
      tester
          .widget<TextField>(find.byType(TextField, skipOffstage: false).first)
          .controller!
          .text,
      'ATCG',
      reason: '⛔ 页签直跳只切页签：输入内容一个字符不许动',
    );
  });

  // ── G8/G9：闸 ② Modifier 精确——Ctrl / Meta 同按一律让路（补 2026-11-04）──
  Future<void> modAltDigit(
      WidgetTester t, LogicalKeyboardKey mod, LogicalKeyboardKey d) async {
    await t.sendKeyDownEvent(mod);
    await t.sendKeyDownEvent(LogicalKeyboardKey.alt);
    await t.sendKeyEvent(d);
    await t.sendKeyUpEvent(LogicalKeyboardKey.alt);
    await t.sendKeyUpEvent(mod);
    await t.pumpAndSettle();
  }

  testWidgets('G8·Ctrl+Alt+数字让路：Ctrl 同按时 digit2 不跳', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: MolecularPage()));
    await tester.pump();
    expect(_tabIndex(tester), 0, reason: '初始态基线（非键盘通道取得）');
    await modAltDigit(
        tester, LogicalKeyboardKey.control, LogicalKeyboardKey.digit2);
    expect(_tabIndex(tester), 0,
        reason: '闸 ②：Ctrl+Alt+数字无人认领 ⇒ 让路（与 G1 同一枚键两态）');
  });

  testWidgets('G9·Meta+Alt+数字让路：Meta 同按时 digit2 不跳', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: MolecularPage()));
    await tester.pump();
    expect(_tabIndex(tester), 0, reason: '初始态基线（非键盘通道取得）');
    await modAltDigit(
        tester, LogicalKeyboardKey.meta, LogicalKeyboardKey.digit2);
    expect(_tabIndex(tester), 0,
        reason: '闸 ②：Meta 同按 ⇒ 让路（修饰键必须精确只有 Alt）');
  });
}
