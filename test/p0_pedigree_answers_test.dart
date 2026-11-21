// p0_pedigree_answers_test.dart —— 老师首用走查四条 P0 的回归锁
//
// P0-1 未选中节点也直接给出最新一代表型比（点节点不是拿答案的前提）
// P0-3 报错就近显示在亲本输入框上方 + 示例统一两对基因
// P0-6 点预置 = 直接算出子代（不再只回填输入框）
// P0-7 计算成功给一条含基因型种数与表型比的文字确认
// 另锁：空态卡手势串（画布没渲染时唯一的手势说明处）。

import 'package:biology/engine/pedigree_graph.dart';
import 'package:biology/pages/genetic_pedigree_page.dart';
import 'package:biology/pages/widgets/pedigree_detail_strip.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const String _ratioAaBb =
    'A显·B显 9 : A显·B隐 3 : A隐·B显 3 : A隐·B隐 1';
const String _emptyTitle = '填入双亲基因型，点击「计算」';

PedigreeGraphEngine _engine(String father, String mother) {
  final e = PedigreeGraphEngine(fatherGenotype: father, motherGenotype: mother);
  e.recomputeFrom(0);
  e.ensureOffspringCoverage();
  if (e.maxGeneration == 0) e.expandNextGeneration();
  return e;
}

Widget _strip(PedigreeGraphEngine engine, String? selectedId) =>
    PedigreeDetailStrip(
      engine: engine,
      selectedId: selectedId,
      connectedLabels: (_) => const [],
      editableGenotype: (_) => false,
      onEditGenotype: (_) {},
      onImportToCross: (_) {},
      onWireDetach: (_) {},
      onDeleteSelected: () {},
    );

Future<void> _pumpPage(
  WidgetTester tester, {
  Size size = const Size(1280, 800),
  bool navCollapsed = false,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
      home: GeneticPedigreePage(navCollapsed: navCollapsed)));
  await tester.pumpAndSettle();
}

void main() {
  group('P0-1 未选中也出最新一代表型比', () {
    test('latestPhenotypeRatios：AaBb 自交 F1 → 单条 9:3:3:1', () {
      final rs = latestPhenotypeRatios(_engine('AaBb', 'AaBb'));
      expect(rs, hasLength(1));
      expect(rs.single.$1, '本代配比');
      expect(phenotypeRatioText(rs.single.$2), _ratioAaBb);
    });

    test('无子代（只有 P 代）→ 空表，交兜底文案', () {
      final e = PedigreeGraphEngine(fatherGenotype: 'AaBb', motherGenotype: 'AaBb');
      expect(latestPhenotypeRatios(e), isEmpty);
    });

    testWidgets('详情条未选中任何节点：直接显示本代配比', (tester) async {
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(body: _strip(_engine('AaBb', 'AaBb'), null))));
      await tester.pumpAndSettle();
      expect(find.text('本代配比'), findsOneWidget);
      expect(find.text(_ratioAaBb), findsOneWidget);
      expect(find.textContaining('点击任意节点查看完整信息'), findsNothing);
    });

    testWidgets('390 窄屏 + ×1.75 字号：未选中也出比例且不溢出', (tester) async {
      tester.view.physicalSize = const Size(390 * 3, 844 * 3);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(
              size: Size(390, 844), textScaler: TextScaler.linear(1.75)),
          child: Scaffold(body: _strip(_engine('AaBb', 'AaBb'), null)),
        ),
      ));
      await tester.pumpAndSettle();
      expect(find.text('本代配比'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('选中节点与未选中是同一份比例（只出现一处「本代配比」）',
        (tester) async {
      final engine = _engine('AaBb', 'AaBb');
      final sel = engine.nodes.firstWhere((n) => n.generation == 1);
      await tester.pumpWidget(
          MaterialApp(home: Scaffold(body: _strip(engine, sel.id))));
      await tester.pumpAndSettle();
      expect(find.text('本代配比'), findsOneWidget);
      expect(find.text(_ratioAaBb), findsOneWidget);
    });
  });

  group('P0-7 计算成功文字确认', () {
    test('AaBb 自交：9 种基因型 + 表型比 9:3:3:1', () {
      expect(deriveSuccessMessage(_engine('AaBb', 'AaBb')),
          '已算出子代：9 种基因型，表型比 9:3:3:1');
    });

    test('只有一种表型（AABBCC × aabbcc）→ 只报基因型数', () {
      expect(deriveSuccessMessage(_engine('AABBCC', 'aabbcc')),
          '已算出子代：1 种基因型');
    });

    testWidgets('点「计算」后出现一条成功 toast', (tester) async {
      await _pumpPage(tester);
      final fields = find.byType(TextField);
      expect(fields, findsNWidgets(2));
      await tester.enterText(fields.at(0), 'AaBb');
      await tester.enterText(fields.at(1), 'AaBb');
      await tester.pumpAndSettle();
      await tester.tap(find.text('计算').first);
      await tester.pumpAndSettle();
      expect(find.text('已算出子代：9 种基因型，表型比 9:3:3:1'), findsOneWidget);
      await tester.pump(const Duration(seconds: 3));
    });
  });

  group('P0-6 点预置直接出结果', () {
    testWidgets('回填 + 直接算，只留一条预置 toast', (tester) async {
      await _pumpPage(tester);
      await tester.tap(find.text('预置'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('双杂合自交（两对基因）'));
      await tester.pumpAndSettle();

      expect(find.text('已按预置「双杂合自交（两对基因）」算出子代'), findsOneWidget);
      expect(find.text(_emptyTitle), findsNothing, reason: '预置应直接出图');
      expect(find.text(_ratioAaBb), findsOneWidget, reason: '详情条直接给出 9:3:3:1');
      await tester.pump(const Duration(seconds: 3));
    });
  });

  group('P0-3 报错就近显示', () {
    const msg = '请输入有效的基因型（成对字母，如 AaBb / aabb）。';

    testWidgets('宽屏：报错挂在左栏，画布顶部不重复一条', (tester) async {
      await _pumpPage(tester);
      await tester.enterText(find.byType(TextField).first, 'AAB');
      await tester.pumpAndSettle();
      await tester.tap(find.text('计算').first);
      await tester.pumpAndSettle();
      expect(find.text(msg), findsOneWidget);
    });

    testWidgets('窄屏左栏收起：画布顶部那条兜底', (tester) async {
      // 先开面板填错（输入框只存在于面板里），再收起面板点底栏「计算」。
      await _pumpPage(tester, size: const Size(800, 800));
      await tester.enterText(find.byType(TextField).first, 'AAB');
      await tester.pumpAndSettle();
      await tester.pumpWidget(
          const MaterialApp(home: GeneticPedigreePage(navCollapsed: true)));
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsNothing, reason: '左栏已收起');
      await tester.tap(find.text('计算').first);
      await tester.pumpAndSettle();
      expect(find.text(msg), findsOneWidget);
    });
  });

  group('空态卡手势串', () {
    testWidgets('未计算时给出完整手势说明，标题逐字不变', (tester) async {
      await _pumpPage(tester);
      expect(find.text(_emptyTitle), findsOneWidget);
      expect(
          find.text('画布操作：拖动或滚轮=平移 · Ctrl+滚轮或双指=缩放 · '
              '点节点=查看信息 · 长按节点或右键=收线 · '
              '右键或长按空白=加样本 · 缩放条 ⛶=适应视图'),
          findsOneWidget);
    });
  });
}
