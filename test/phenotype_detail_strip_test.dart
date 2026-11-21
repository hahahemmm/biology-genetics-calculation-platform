// phenotype_detail_strip_test.dart —— 表型行 / 本代配比 / 折叠基因型列表
//
// 覆盖：单基因 3:1、双基因 9:3:3:1、伴性 X显、百分比回退、组数>4 截断，
// 以及 390 窄屏与课堂大屏 ×1.75 字号的溢出检查。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:biology/engine/pedigree_graph.dart';
import 'package:biology/engine/phenotype_grouper.dart';
import 'package:biology/pages/widgets/pedigree_detail_strip.dart';

/// 构造一个已展开到 F1 的引擎（照抄系谱页测试的推进模式）。
PedigreeGraphEngine engineWithF1(String father, String mother) {
  final engine =
      PedigreeGraphEngine(fatherGenotype: father, motherGenotype: mother);
  engine.recomputeFrom(0);
  engine.ensureOffspringCoverage();
  if (engine.maxGeneration == 0) engine.expandNextGeneration();
  return engine;
}

PedigreeDetailStrip strip(PedigreeGraphEngine engine, String? selectedId,
    {List<PedigreeNode> expandedNodes = const []}) {
  return PedigreeDetailStrip(
    engine: engine,
    selectedId: selectedId,
    expandedNodes: expandedNodes,
    connectedLabels: (_) => const [],
    editableGenotype: (_) => false,
    onEditGenotype: (_) {},
    onImportToCross: (_) {},
    onWireDetach: (_) {},
    onDeleteSelected: () {},
  );
}

void main() {
  group('配比纯函数', () {
    test('单基因 Aa 自交 → 表型 A显、配比 3 : 1', () {
      expect(phenotypeLabelOf('Aa'), 'A显');
      final groups = groupByPhenotype(const [
        GenotypeSample('AA', 0.25),
        GenotypeSample('Aa', 0.5),
        GenotypeSample('aa', 0.25),
      ]);
      expect(phenotypeRatioText(groups), 'A显 3 : A隐 1');
    });

    test('双基因 AaBb 9 种 → 配比 9 : 3 : 3 : 1', () {
      final groups = groupByPhenotype(const [
        GenotypeSample('AABB', 0.0625),
        GenotypeSample('AABb', 0.125),
        GenotypeSample('AAbb', 0.0625),
        GenotypeSample('AaBB', 0.125),
        GenotypeSample('AaBb', 0.25),
        GenotypeSample('Aabb', 0.125),
        GenotypeSample('aaBB', 0.0625),
        GenotypeSample('aaBb', 0.125),
        GenotypeSample('aabb', 0.0625),
      ]);
      expect(phenotypeRatioText(groups),
          'A显·B显 9 : A显·B隐 3 : A隐·B显 3 : A隐·B隐 1');
    });

    test('伴性节点 XBY → 表型 X显', () {
      expect(phenotypeLabelOf('XBY'), 'X显');
    });

    test('概率凑不成整数比 → 退回百分比（1 位小数）', () {
      // 0.1/0.2/0.7 会被 k=10 凑成 1:2:7；用三位小数确保 k=1..64 无解。
      final groups = groupByPhenotype(const [
        GenotypeSample('AAbb', 0.123),
        GenotypeSample('aaBB', 0.234),
        GenotypeSample('aabb', 0.643),
      ]);
      expect(phenotypeRatioText(groups),
          'A隐·B隐 64.3% : A隐·B显 23.4% : A显·B隐 12.3%');
    });

    test('组数 > 4 → 只显示前 3 组 + 等 N 类', () {
      final groups = [
        for (var i = 0; i < 5; i++)
          PhenotypeGroup(label: 'G${i + 1}', probability: 0.2, genotypes: ['g$i']),
      ];
      expect(phenotypeRatioText(groups), 'G1 1 : G2 1 : G3 1 : 等 2 类');
    });

    test('组数 = 4 不截断', () {
      final groups = const [
        PhenotypeGroup(label: 'A', probability: 0.4, genotypes: ['x']),
        PhenotypeGroup(label: 'B', probability: 0.3, genotypes: ['y']),
        PhenotypeGroup(label: 'C', probability: 0.2, genotypes: ['z']),
        PhenotypeGroup(label: 'D', probability: 0.1, genotypes: ['w']),
      ];
      expect(phenotypeRatioText(groups), 'A 4 : B 3 : C 2 : D 1');
    });
  });

  group('widget 接线', () {
    testWidgets('Aa 自交 F1：表型行 + 本代配比 3 : 1 + 展开基因型', (tester) async {
      final engine = engineWithF1('Aa', 'Aa');
      final sel =
          engine.nodes.firstWhere((x) => x.generation == 1 && x.genotype == 'AA');
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: strip(engine, sel.id))));
      await tester.pumpAndSettle();

      expect(find.text('表型 '), findsOneWidget);
      expect(find.text('A显'), findsOneWidget);
      expect(find.text('本代配比'), findsOneWidget);
      expect(find.text('A显 3 : A隐 1'), findsOneWidget);

      await tester.tap(find.text('展开基因型'));
      await tester.pumpAndSettle();
      expect(find.textContaining('AA'), findsWidgets);
      expect(find.textContaining('aa'), findsWidgets);
    });

    testWidgets('AaBb 自交 F1：配比含 9 : 3 : 3 : 1', (tester) async {
      final engine = engineWithF1('AaBb', 'AaBb');
      final sel = engine.nodes.firstWhere((x) => x.generation == 1);
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: strip(engine, sel.id))));
      await tester.pumpAndSettle();

      expect(
          find.text('A显·B显 9 : A显·B隐 3 : A隐·B显 3 : A隐·B隐 1'), findsOneWidget);
    });

    testWidgets('390 窄屏 + ×1.75 字号不溢出', (tester) async {
      final engine = engineWithF1('AaBb', 'AaBb');
      final sel = engine.nodes.firstWhere((x) => x.generation == 1);
      tester.view.physicalSize = const Size(390 * 3, 844 * 3);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(
              size: Size(390, 844), textScaler: TextScaler.linear(1.75)),
          child: Scaffold(body: strip(engine, sel.id)),
        ),
      ));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('课堂大屏 ×1.75 字号不溢出', (tester) async {
      final engine = engineWithF1('AaBb', 'AaBb');
      final sel = engine.nodes.firstWhere((x) => x.generation == 1);
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(
              size: Size(1280, 800), textScaler: TextScaler.linear(1.75)),
          child: Scaffold(body: strip(engine, sel.id)),
        ),
      ));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });

  group('已展开世代完整基因型配比', () {
    test('integerCountsOf：AaBb 自交 F1 九个概率 → 计数总和 16；凑不成 → null', () {
      final counts = integerCountsOf(const [
        0.0625, 0.125, 0.0625, 0.125, 0.25, 0.125, 0.0625, 0.125, 0.0625,
      ]);
      expect(counts, isNotNull);
      expect(counts!.fold<int>(0, (s, c) => s + c), 16);
      expect(integerCountsOf(const [0.123, 0.234, 0.643]), isNull);
    });

    test('genotypeShareGroups：AaBb 自交 F1 → 单组 9 条、共 16 份', () {
      final engine = engineWithF1('AaBb', 'AaBb');
      final groups = genotypeShareGroups(engine, engine.nodesOf(1));
      expect(groups, hasLength(1));
      expect(groups.first.label, 'F1');
      expect(groups.first.total, 16);
      expect(groups.first.entries, hasLength(9));
      expect(groups.first.entries.first.genotype, 'AaBb');
      expect(groups.first.entries.first.share, '4/16');
    });

    testWidgets('无选中 + 展开 F1：直接渲染配比面板，不再显示点击提示',
        (tester) async {
      final engine = engineWithF1('AaBb', 'AaBb');
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(
              body: strip(engine, null, expandedNodes: engine.nodesOf(1)))));
      await tester.pumpAndSettle();

      expect(find.text('F1 · 9 种基因型 · 共 16 个'), findsOneWidget);
      expect(find.textContaining('点击任意节点查看完整信息'), findsNothing);
    });

    testWidgets('多世代展开 F1+F2：两代配比面板同时显示', (tester) async {
      final engine = engineWithF1('AaBb', 'AaBb');
      engine.expandNextGeneration();
      final all = [...engine.nodesOf(1), ...engine.nodesOf(2)];
      await tester.pumpWidget(
          MaterialApp(home: Scaffold(body: strip(engine, null, expandedNodes: all))));
      await tester.pumpAndSettle();

      expect(find.text('F1 · 9 种基因型 · 共 16 个'), findsOneWidget);
      expect(find.text('F2 · 9 种基因型 · 共 16 个'), findsOneWidget);
    });

    test('致死基因型不混进配比：只报存活比例，header 注明剔除数', () {
      // 引擎给存活子代按「存活总和 = 1」归一化，致死桶保留未归一化的原始
      // 概率；混算会凑成 4:8:3 这种歪比例，正确存活比是 AA:Aa = 1:2。
      final nodes = [
        PedigreeNode(
            id: 'F1#1',
            kind: PedigreeNodeKind.group,
            genotype: 'Aa',
            generation: 1,
            probability: 2 / 3,
            isExternal: false,
            familyId: 0),
        PedigreeNode(
            id: 'F1#0',
            kind: PedigreeNodeKind.group,
            genotype: 'AA',
            generation: 1,
            probability: 1 / 3,
            isExternal: false,
            familyId: 0),
        PedigreeNode(
            id: 'Lf1#0',
            kind: PedigreeNodeKind.group,
            genotype: 'aa',
            generation: 1,
            probability: 0.25,
            isExternal: false,
            familyId: 0,
            isLethal: true),
      ];
      final engine =
          PedigreeGraphEngine(fatherGenotype: 'Aa', motherGenotype: 'Aa');
      final groups = genotypeShareGroups(engine, nodes);
      expect(groups, hasLength(1));
      final g = groups.single;
      expect(g.total, 3, reason: '存活比例 1:2 → 共 3 份，不含致死');
      expect(g.lethal, 1);
      expect(g.entries.map((e) => e.genotype).toList(), ['Aa', 'AA']);
      expect(g.entries.first.share, '2/3');
      expect(g.entries.first.share, isNot(contains('15')),
          reason: '致死混算会凑出 4/15 这类错值');
      expect(g.header, contains('致死 1 种已剔除'));
    });

    testWidgets('有选中 + 有展开：节点信息与配比面板同时渲染', (tester) async {
      final engine = engineWithF1('AaBb', 'AaBb');
      final sel = engine.nodesOf(1).first;
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(
              body: strip(engine, sel.id, expandedNodes: engine.nodesOf(1)))));
      await tester.pumpAndSettle();

      expect(find.text('本代配比'), findsOneWidget);
      expect(find.text('F1 · 9 种基因型 · 共 16 个'), findsOneWidget);
    });
  });
}
