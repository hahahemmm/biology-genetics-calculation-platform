// pedigree_history_test.dart —— v2.1 基因型编辑 + 计算历史/新白板
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'dart:io';

import 'package:biology/pages/genetic_pedigree_page.dart';
import 'package:biology/state/history_store.dart';
import 'package:biology/pages/widgets/pedigree_canvas.dart';

Widget _app() => const MaterialApp(home: GeneticPedigreePage());

Future<void> pumpHome(WidgetTester tester) async {
  // v2.19.27：系谱面板占位/覆盖阈值 720→900——800 宽由占位式变为
  // 覆盖式（平板竖屏语义），这两个测试按占位式布局断言，视口升到 1000。
  tester.view.physicalSize = const Size(1000, 800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(_app());
}

Future<void> _derive(WidgetTester tester) async {
  await tester.tap(find.text('计算').first);
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    HistoryStore.debugFilePath =
        '${Directory.systemTemp.createTempSync('biology_hist_').path}/history.json';
  });
  tearDown(() => HistoryStore.debugFilePath = null);

  testWidgets('编辑：P 代双亲基因型大字+铅笔，保存后重算 F1 跟随',
      (tester) async {
    await pumpHome(tester);
    await _derive(tester);
    final c = tester.widget<PedigreeCanvas>(find.byType(PedigreeCanvas));
    c.onNodeTap!(c.nodes.firstWhere((n) => n.id == 'P-father'));
    await tester.pumpAndSettle();
    // 基因型大字（AABBCC）+ 编辑入口
    expect(find.text('AABBCC'), findsWidgets);
    expect(find.text('编辑'), findsOneWidget,
        reason: 'P 代双亲可编辑');
    await tester.tap(find.text('编辑'));
    await tester.pumpAndSettle();
    expect(find.text('编辑基因型'), findsOneWidget);
    await tester.enterText(
        find.widgetWithText(TextField, '新基因型（如 AaBbCc）'), 'aabbCC');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    final c2 = tester.widget<PedigreeCanvas>(find.byType(PedigreeCanvas));
    expect(c2.nodes.firstWhere((n) => n.id == 'P-father').genotype,
        'aabbCC', reason: '基因型已更新');
    expect(c2.nodes.where((n) => n.generation == 1).every(
            (n) => n.genotype.startsWith('a')),
        isTrue, reason: '重算后 F1 携带父本新配子');
  });

  testWidgets('计算产出子代只读（无编辑入口）', (tester) async {
    await pumpHome(tester);
    await _derive(tester);
    final c = tester.widget<PedigreeCanvas>(find.byType(PedigreeCanvas));
    final f1 = c.nodes.firstWhere((n) => n.generation == 1);
    c.onNodeTap!(f1);
    await tester.pumpAndSettle();
    expect(find.textContaining('只读'), findsWidgets,
        reason: '组合桶子代显示只读');
    expect(find.text('编辑'), findsNothing, reason: '子代无编辑入口');
  });

  testWidgets('P0 回归：连续两次「保存并开新对话」+ 中途重算不死机（异步时序压力）',
      (tester) async {
    await pumpHome(tester);
    await _derive(tester);
    // 第一次保存开新
    await tester.tap(find.text('历史（1）'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('保存当前并开新对话'));
    await tester.pumpAndSettle();
    expect(find.text('填入双亲基因型，点击「计算」'), findsOneWidget);
    // 立刻重新计算 → 立刻再保存开新（重入/时序压力）
    await _derive(tester);
    await tester.pumpAndSettle();
    await tester.tap(find.text('历史（3）'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('保存当前并开新对话'));
    await tester.pumpAndSettle();
    // 没死机：回到空白板 + 历史累计
    expect(find.text('填入双亲基因型，点击「计算」'), findsOneWidget);
    expect(tester.takeException(), isNull, reason: '全程无异常');
    expect(find.text('历史（4）'), findsOneWidget);
    // 再打开历史回看不崩
    await tester.tap(find.text('历史（4）'));
    await tester.pumpAndSettle();
    expect(find.text('计算历史'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('历史：计算自动记录；「保存并开新对话」清空画布且历史保留',
      (tester) async {
    await pumpHome(tester);
    await _derive(tester);
    await tester.pumpAndSettle();
    // 计算后命令栏出现 历史（1）
    final histBtn = find.text('历史（1）');
    expect(histBtn, findsOneWidget);
    await tester.tap(histBtn);
    await tester.pumpAndSettle();
    expect(find.text('计算历史'), findsOneWidget);
    expect(find.textContaining('♀aabbcc'), findsWidgets,
        reason: '历史摘要含双亲基因型');
    expect(find.text('保存当前并开新对话'), findsOneWidget);
    // 保存并新开
    await tester.tap(find.text('保存当前并开新对话'));
    await tester.pumpAndSettle();
    // 画布重置为空状态
    expect(find.text('填入双亲基因型，点击「计算」'), findsOneWidget,
        reason: '新白板 = 空状态');
    expect(find.byType(PedigreeCanvas), findsNothing);
    // 历史保留（旧记录 + 新存档 = 2，且与白板隔离）
    expect(find.text('历史（2）'), findsOneWidget,
        reason: '历史已新增存档且未丢失');
    await tester.tap(find.text('历史（2）'));
    await tester.pumpAndSettle();
    expect(find.text('计算历史'), findsOneWidget);
    expect(find.textContaining('♀aabbcc'), findsWidgets,
        reason: '历史只读回看不受新白板影响');
  });
}