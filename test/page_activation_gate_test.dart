// page_activation_gate_test.dart —— v2.19.52 找茬 P1（激活页闸）守卫网
//
// 病灶（找茬代理 2026-10-09 取证）：HomeShell 用 IndexedStack + Visibility
// 常驻 10 页 ⇒ 各页 HardwareKeyboard handler 同时存活，ModalRoute.isCurrent
// 对壳内非激活页恒真 ⇒ 按一次 Ctrl+S 五页全部写库、Alt+数字六页全部切页签；
// 且任一宿主 return true 会把事件从焦点链抽走（SDK：handler 返回值 OR 汇总，
// true ⇒ 焦点系统收不到），饿死激活页内嵌组件自己的快捷键。
// 修法：PageActivationScope/Marker + 三宿主激活闸（lib/ui/page_activation.dart）。
// 本文件用 mini 壳（IndexedStack + 双真页）复现多页共存场景——既有 26 例
// Ctrl+S/12 例页签守卫全是单页泵（无标记 ⇒ 回退激活），钉不到这个病。
import 'dart:io';

import 'package:biology/pages/evolution_page.dart';
import 'package:biology/pages/molecular_page.dart';
import 'package:biology/state/first_run_store.dart';
import 'package:biology/state/mistake_book.dart';
import 'package:biology/ui/page_activation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

class _MiniShell extends StatefulWidget {
  const _MiniShell();

  @override
  State<_MiniShell> createState() => _MiniShellState();
}

class _MiniShellState extends State<_MiniShell> {
  int index = 0;

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
                    onPressed: () => setState(() => index = 1),
                    child: const Text('go-1')),
              ]),
              Expanded(
                child: PageActivationScope(
                  currentIndex: index,
                  child: IndexedStack(
                    index: index,
                    children: const [
                      PageActivationMarker(
                          pageIndex: 0, child: MolecularPage()),
                      PageActivationMarker(
                          pageIndex: 1, child: EvolutionPage()),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      );
}

Future<void> _ctrlS(WidgetTester t) async {
  await t.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  await t.sendKeyEvent(LogicalKeyboardKey.keyS);
  await t.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
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
    tmp = Directory.systemTemp.createTempSync('page_activation_gate');
    MistakeBook.debugFilePath = '${tmp.path}/mistakes.json';
    MistakeBook.debugTrashFilePath = '${tmp.path}/mistakes.trash.json';
    MistakeBook.instance.debugReset();
    FirstRunStore.debugFilePath = '${tmp.path}/first_run.json';
    FirstRunStore.debugWebStorage = null;
    FirstRunStore.debugForceIsWebStorage = false;
    FirstRunStore.instance.debugReset();
  });

  tearDown(() {
    MistakeBook.instance.debugFlushSave();
    MistakeBook.instance.debugResetAiOrganize();
    MistakeBook.instance.debugReset();
    MistakeBook.debugFilePath = null;
    MistakeBook.debugTrashFilePath = null;
    FirstRunStore.debugFilePath = null;
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  Future<void> pumpShell(WidgetTester tester) async {
    tester.view.physicalSize = const Size(900, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const _MiniShell());
    await tester.pump();
  }

  /// 让**两页**都持有已算出的结果（payload 非空），回到 index 0。
  /// 前置病灶形态：没有激活闸时，一次 Ctrl+S 两页都会写库。
  /// ⚠️ 进化的页签也必须停在「基因频率」——payload 按当前页签组装，
  /// 进化树签无计算器返 null，病灶形不成（A3 曾以单页视角踩过这个坑）。
  Future<void> armBothPages(WidgetTester tester) async {
    // 页 0（分子，激活）：tab0 算碱基组成。
    await tester.enterText(find.byType(TextField).first, '30');
    await tester.pump();
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump();
    await tester.tap(find.text('计算碱基组成'));
    await tester.pumpAndSettle();
    // 切到页 1（进化）：页签切到「基因频率」+「全部计算」一次算全 tab。
    await tester.tap(find.text('go-1'));
    await tester.pumpAndSettle();
    await tester.tap(find.descendant(
        of: find.byType(TabBar), matching: find.text('基因频率')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('全部计算'));
    await tester.pumpAndSettle();
    // 回页 0。
    await tester.tap(find.text('go-0'));
    await tester.pumpAndSettle();
  }

  testWidgets('A1·双页均有结果时按一次 Ctrl+S：⛔ 只写激活页一道'
      '（非激活页宿主让路，不是截断）', (tester) async {
    await pumpShell(tester);
    await armBothPages(tester);
    expect(MistakeBook.instance.entries, isEmpty);

    await _ctrlS(tester);

    final entries = MistakeBook.instance.entries;
    expect(entries, hasLength(1),
        reason: '⛔ 病灶形态下此处为 2（分子+进化各写一道）；'
            '激活闸落地后非激活页必须无声让路');
    expect(entries.single.subjectArea, '碱基组成（DNA 碱基互补）',
        reason: '写的是激活页（分子）的题');
    expect(find.textContaining('已加入错题本'), findsOneWidget);
    MistakeBook.instance.debugFlushSave();
    MistakeBook.instance.debugResetAiOrganize();
  });

  testWidgets('A2·Alt+数字只切激活页的页签：非激活页页签逐项不动', (tester) async {
    await pumpShell(tester);
    final tabIndexes = () => find
        .byType(TabBar, skipOffstage: false)
        .evaluate()
        .map((e) => (e.widget as TabBar).controller!.index)
        .toList();
    expect(tabIndexes(), [0, 0], reason: '前提：两页都在各自 tab0');

    await _altDigit(tester, LogicalKeyboardKey.digit2);

    expect(tabIndexes(), [1, 0],
        reason: '⛔ 病灶形态下为 [1,1]（两页同切）；'
            '激活闸落地后非激活页（进化）页签必须不动');
  });

  testWidgets('A3·激活态切换后新激活页可写（闸不误杀）', (tester) async {
    await pumpShell(tester);
    await armBothPages(tester);
    // 切到页 1（进化），再把它自己的页签切到「基因频率」（payload 按当前
    // 页签组装——进化树签无计算器返 null，得切到有计算器的签）。
    await tester.tap(find.text('go-1'));
    await tester.pumpAndSettle();
    await tester.tap(find.descendant(
        of: find.byType(TabBar), matching: find.text('基因频率')));
    await tester.pumpAndSettle();
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump();
    await _ctrlS(tester);
    final entries = MistakeBook.instance.entries;
    expect(entries, hasLength(1));
    expect(entries.single.subjectArea, '基因频率（按个体数计算）',
        reason: '激活页换成进化后，写库权跟着走');
    MistakeBook.instance.debugFlushSave();
    MistakeBook.instance.debugResetAiOrganize();
  });

  testWidgets('A4·push 路由覆顶：激活闸与路由闸合取，全让路', (tester) async {
    await pumpShell(tester);
    await armBothPages(tester);
    final ctx = tester.element(find.byType(MolecularPage));
    Navigator.of(ctx).push(MaterialPageRoute<void>(
      builder: (_) => const Scaffold(body: Text('cover-route')),
    ));
    await tester.pumpAndSettle();
    await _ctrlS(tester);
    expect(MistakeBook.instance.entries, isEmpty,
        reason: '被 push 盖住 ⇒ ModalRoute.isCurrent=false ⇒ 路由闸让路'
            '（与激活闸无关的另一道闸）');
  });
}
