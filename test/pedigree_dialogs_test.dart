// pedigree_dialogs_test.dart —— 操作日志 / 计算历史对话框结构锁：
// 空状态三件套（图标 + 标题 + 说明）+ 有数据时的列表渲染 + 关闭按钮 pop。
// 最小夹具（按钮触发），不依赖整页。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:biology/engine/pedigree_graph.dart';
import 'package:biology/pages/widgets/pedigree_dialogs.dart';
import 'package:biology/state/history_store.dart';

Widget _harness(void Function(BuildContext) open) => MaterialApp(
      home: Builder(
        builder: (ctx) => ElevatedButton(
          onPressed: () => open(ctx),
          child: const Text('open'),
        ),
      ),
    );

void main() {
  testWidgets('操作日志·空状态三件套：图标 + 暂无操作记录 + 说明', (tester) async {
    await tester.pumpWidget(_harness((ctx) => showPedigreeLogDialog(
          context: ctx,
          labels: const [],
          canRedoRevert: false,
          onRevertTo: (_) {},
          onRedoRevert: () {},
        )));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.byType(Icon), findsWidgets, reason: '空状态有图标');
    expect(find.byIcon(Icons.history_toggle_off), findsOneWidget);
    expect(find.text('暂无操作记录'), findsOneWidget, reason: '空状态标题');
    expect(find.textContaining('每一步操作都会记录在这里'), findsOneWidget,
        reason: '空状态说明');
  });

  testWidgets('操作日志·有数据：渲染对应条数且无「暂无操作记录」', (tester) async {
    const labels = ['添加样本 Aa', '回退到第 1 步', '删除 F2 世代'];
    await tester.pumpWidget(_harness((ctx) => showPedigreeLogDialog(
          context: ctx,
          labels: labels,
          canRedoRevert: false,
          onRevertTo: (_) {},
          onRedoRevert: () {},
        )));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.byType(ListTile), findsNWidgets(labels.length),
        reason: '一条日志一个 ListTile');
    for (final l in labels) {
      expect(find.text(l), findsOneWidget);
    }
    expect(find.text('暂无操作记录'), findsNothing);
  });

  testWidgets('操作日志·「关闭」按钮 pop 对话框', (tester) async {
    await tester.pumpWidget(_harness((ctx) => showPedigreeLogDialog(
          context: ctx,
          labels: const ['添加样本 Aa'],
          canRedoRevert: false,
          onRevertTo: (_) {},
          onRedoRevert: () {},
        )));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    await tester.tap(find.text('关闭'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing, reason: '关闭后对话框已 pop');
  });

  testWidgets('计算历史·空状态三件套：图标 + 暂无历史记录 + 说明', (tester) async {
    await tester.pumpWidget(_harness((ctx) => showPedigreeHistoryDialog(
          context: ctx,
          history: const [],
          isMounted: () => true,
          onSaveAndNew: () async {},
        )));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.byType(Icon), findsWidgets, reason: '空状态有图标');
    expect(find.byIcon(Icons.inbox_outlined), findsOneWidget);
    expect(find.text('暂无历史记录'), findsOneWidget, reason: '空状态标题');
    expect(find.textContaining('会自动记录在这里'), findsOneWidget,
        reason: '空状态说明');
  });

  testWidgets('计算历史·有数据：渲染对应条数且无「暂无历史记录」', (tester) async {
    const history = [
      HistoryEntry(label: '历史条目 0', epochMs: 1730000000000, detail: '详情 0'),
      HistoryEntry(label: '历史条目 1', epochMs: 1730000060000, detail: '详情 1'),
      HistoryEntry(label: '历史条目 2', epochMs: 1730000120000, detail: '详情 2'),
    ];
    await tester.pumpWidget(_harness((ctx) => showPedigreeHistoryDialog(
          context: ctx,
          history: history,
          isMounted: () => true,
          onSaveAndNew: () async {},
        )));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.byType(ListTile), findsNWidgets(history.length),
        reason: '一条历史一个 ListTile');
    for (final h in history) {
      expect(find.text(h.label), findsOneWidget);
    }
    expect(find.text('暂无历史记录'), findsNothing);
  });

  testWidgets('计算历史·「关闭」按钮 pop 对话框', (tester) async {
    await tester.pumpWidget(_harness((ctx) => showPedigreeHistoryDialog(
          context: ctx,
          history: const [],
          isMounted: () => true,
          onSaveAndNew: () async {},
        )));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    await tester.tap(find.text('关闭'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing, reason: '关闭后对话框已 pop');
  });

  // ── isPolyploidGenotype：跳过连字符、大小写归一后，最大连续份数 >2 ──
  test('isPolyploidGenotype·同一字母归一后超过 2 份为多倍体', () {
    expect(isPolyploidGenotype('Aaa'), isTrue, reason: '归一后 AAA 连续 3 份');
    expect(isPolyploidGenotype('AaA'), isTrue, reason: '大小写归一后连续 3 份');
  });

  test('isPolyploidGenotype·最多 2 份不算；AAaa 归一后 4 份算', () {
    expect(isPolyploidGenotype('Aa'), isFalse, reason: 'maxRun == 2 不算');
    expect(isPolyploidGenotype('AAaa'), isTrue,
        reason: '大小写归一后 AAAA 连续 4 份，仍 >2');
  });

  test('isPolyploidGenotype·AAAA 四份同字母为多倍体', () {
    expect(isPolyploidGenotype('AAAA'), isTrue);
  });

  test('isPolyploidGenotype·连字符忽略后按连续份数判定', () {
    expect(isPolyploidGenotype('A-aa-a'), isTrue, reason: '跳过 - 后 Aaaa 连续 4 份');
    expect(isPolyploidGenotype('A-a-a'), isTrue,
        reason: '跳过 - 后 Aaa 连续 3 份，仍 >2');
    expect(isPolyploidGenotype('A-a'), isFalse, reason: '2 份不算');
  });

  // ── showPedigreeSexLinkedDialog 返回值契约 ──
  testWidgets('伴性遗传标注·填 X=病 点「应用」：xLabel=病，未填字段为 null',
      (tester) async {
    SexLinkedConfig? result;
    await tester.pumpWidget(_harness((ctx) {
      showPedigreeSexLinkedDialog(context: ctx, current: null)
          .then((v) => result = v);
    }));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'X ='), '病');
    await tester.tap(find.text('应用'));
    await tester.pumpAndSettle();
    expect(result, isNotNull, reason: '「应用」返回配置');
    expect(result!.xLabel, '病');
    expect(result!.xLowerLabel, isNull, reason: '未填字段为 null');
    expect(result!.yLabel, isNull);
    expect(result!.yLowerLabel, isNull);
    await tester.pump(const Duration(milliseconds: 500)); // 冲掉控制器延迟 dispose 定时器
  });

  testWidgets('伴性遗传标注·点「关闭」返回 null', (tester) async {
    SexLinkedConfig? result;
    var returned = false;
    await tester.pumpWidget(_harness((ctx) {
      showPedigreeSexLinkedDialog(context: ctx, current: null).then((v) {
        result = v;
        returned = true;
      });
    }));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('关闭'));
    await tester.pumpAndSettle();
    expect(returned, isTrue, reason: 'future 已完成');
    expect(result, isNull, reason: '「关闭」未确认返回 null');
    await tester.pump(const Duration(milliseconds: 500));
  });
}
