// shortcut_cheatsheet_test.dart —— v2.19.54 ? 键速览 + 一次性指引守卫网
import 'dart:io';

import 'package:biology/pages/evolution_page.dart';
import 'package:biology/pages/molecular_page.dart';
import 'package:biology/pages/widgets/shortcut_cheatsheet.dart';
import 'package:biology/state/first_run_store.dart';
import 'package:biology/ui/page_activation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

class _MiniShell extends StatefulWidget {
  const _MiniShell({this.startIndex = 5});

  final int startIndex;

  @override
  State<_MiniShell> createState() => _MiniShellState();
}

class _MiniShellState extends State<_MiniShell> {
  late int index = widget.startIndex;

  @override
  Widget build(BuildContext context) => MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              Row(children: [
                TextButton(
                    onPressed: () => setState(() => index = 0),
                    child: const Text('go-0')),
                TextButton(
                    onPressed: () => setState(() => index = 5),
                    child: const Text('go-5')),
              ]),
              Expanded(
                child: PageActivationScope(
                  currentIndex: index,
                  child: ShortcutCheatsheet(
                    child: IndexedStack(
                      index: index,
                      children: const [
                        Text('home-page'),
                        Text('x1'),
                        Text('x2'),
                        Text('x3'),
                        Text('x4'),
                        PageActivationMarker(
                            pageIndex: 5, child: MolecularPage()),
                        PageActivationMarker(
                            pageIndex: 6, child: EvolutionPage()),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
}

Future<void> _shiftSlash(WidgetTester t) async {
  await t.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
  await t.sendKeyEvent(LogicalKeyboardKey.slash);
  await t.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
  await t.pumpAndSettle();
}

Future<void> _altDigit(WidgetTester t, LogicalKeyboardKey d) async {
  await t.sendKeyDownEvent(LogicalKeyboardKey.alt);
  await t.sendKeyEvent(d);
  await t.sendKeyUpEvent(LogicalKeyboardKey.alt);
  await t.pumpAndSettle();
}

void main() {
  late Directory tmp;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('cheatsheet');
    FirstRunStore.debugFilePath = '${tmp.path}/first_run.json';
    FirstRunStore.debugWebStorage = null;
    FirstRunStore.debugForceIsWebStorage = false;
    FirstRunStore.instance.debugReset();
  });

  tearDown(() {
    FirstRunStore.debugFilePath = null;
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  Future<void> pumpShell(WidgetTester tester, {int startIndex = 5}) async {
    tester.view.physicalSize = const Size(900, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(_MiniShell(startIndex: startIndex));
    await tester.pump();
  }

  testWidgets('C1·有键表页按 Shift+/：速览卡弹出且键名来自宿主常量',
      (tester) async {
    await pumpShell(tester);
    expect(find.text('本页快捷键'), findsNothing);
    await _shiftSlash(tester);
    expect(find.text('本页快捷键'), findsOneWidget);
    // 分子页挂三族宿主：键名逐字来自宿主静态常量（单一真相）。
    expect(find.text('Alt + 1 … 9'), findsOneWidget);
    expect(find.text('Ctrl + S'), findsOneWidget);
    // v2.19.59：分子页挂了 CardLinkKeyHost ⇒ 速览必须有 K 行（与宿主常量同源）。
    expect(find.text('K'), findsOneWidget,
        reason: '分子页 v2.19.59 起挂 CardLinkKeyHost，缺这行即缺口');
    // ⛔ B2：分子页未挂 CurriculumFocusShortcuts ⇒ 表里不许有 Alt + K
    // （编造对应关系；该宿主全局仅 9331 / 遗传病两处实例化）。
    expect(find.text('Alt + K'), findsNothing);
    // 用完关掉，不影响后续断言。
    await tester.tap(find.text('知道了'));
    await tester.pumpAndSettle();
    expect(find.text('本页快捷键'), findsNothing);
  });

  testWidgets('C1b·9331（遗传计算器，index 2）面板含 Ctrl + S 行', (tester) async {
    await pumpShell(tester, startIndex: 2);
    await _shiftSlash(tester);
    expect(find.text('本页快捷键'), findsOneWidget);
    expect(find.text('Alt + 1 … 9'), findsOneWidget);
    // B2 缺口：9331 已收编成一枚页级 SaveMistakeKeyHost。
    expect(find.text('Ctrl + S'), findsOneWidget,
        reason: '9331 收编页级宿主后缺这行即缺口');
    // 9331 确实挂 CurriculumFocusShortcuts ⇒ Alt + K 保留。
    expect(find.text('Alt + K'), findsOneWidget);
    await tester.tap(find.text('知道了'));
    await tester.pumpAndSettle();
  });

  testWidgets('C2·无键表页（首页 index 0）按 Shift+/：无声让路不弹卡',
      (tester) async {
    await pumpShell(tester, startIndex: 5);
    await tester.tap(find.text('go-0'));
    await tester.pumpAndSettle();
    await _shiftSlash(tester);
    expect(find.text('本页快捷键'), findsNothing,
        reason: '闸③：无键表页按了也无声——不为空表弹「暂无」噪音');
  });

  testWidgets('C3·修饰键精确：裸 / 与 Ctrl+Shift+/ 都不弹卡', (tester) async {
    await pumpShell(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.slash);
    await tester.pumpAndSettle();
    expect(find.text('本页快捷键'), findsNothing);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.slash);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    expect(find.text('本页快捷键'), findsNothing);
  });

  testWidgets('C4·push 覆顶时按 Shift+/：路由闸让路', (tester) async {
    await pumpShell(tester);
    final ctx = tester.element(find.byType(MolecularPage));
    Navigator.of(ctx).push(MaterialPageRoute<void>(
      builder: (_) => const Scaffold(body: Text('cover-route')),
    ));
    await tester.pumpAndSettle();
    await _shiftSlash(tester);
    expect(find.text('本页快捷键'), findsNothing);
  });

  testWidgets('C5·一次性指引：首次成功触发弹「按 ?」，其后不再弹且落盘',
      (tester) async {
    await pumpShell(tester);
    expect(FirstRunStore.instance.shortcutNudgeShown, isFalse);
    // 首次成功触发（Alt+2 切页签）。
    await _altDigit(tester, LogicalKeyboardKey.digit2);
    expect(find.textContaining('按 ?'), findsOneWidget,
        reason: '首次成功触发 ⇒ 指引 SnackBar');
    expect(FirstRunStore.instance.shortcutNudgeShown, isTrue,
        reason: '⛔ 先落盘再弹：下次启动不重弹');
    await tester.pumpAndSettle(const Duration(seconds: 5));
    // 第二次成功触发：不再弹。
    await _altDigit(tester, LogicalKeyboardKey.digit3);
    expect(find.textContaining('按 ?'), findsNothing,
        reason: '一次性：已弹过不再烦');
  });

  testWidgets('C6·让路路径不弹指引：按了不触发就没有「原来有快捷键」的事实',
      (tester) async {
    await pumpShell(tester);
    // Alt+9 对 4 页签的分子页越界（闸⑤让路）⇒ 不弹指引。
    await _altDigit(tester, LogicalKeyboardKey.digit9);
    expect(find.textContaining('按 ?'), findsNothing);
    expect(FirstRunStore.instance.shortcutNudgeShown, isFalse);
  });
}
