// cross_board_test.dart —— 杂交棋盘组件与合子拼接纯函数测试
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:biology/engine/kaoji_calc.dart';
import 'package:biology/engine/models.dart';
import 'package:biology/ui/cross_board.dart';

KaojiCalcResult _result({
  required List<String> g1,
  required List<String> g2,
  List<int> pheno = const [3, 1],
  List<String> phenoLabels = const ['显性', '隐性'],
}) {
  return KaojiCalcResult(
    gametesP1: g1,
    gametesP2: g2,
    genotypeRatio: const Ratio([1, 2, 1]),
    phenotypeRatio: Ratio(pheno),
    variantName: '分离定律',
    genotypeLabels: const ['AA', 'Aa', 'aa'],
    phenotypeLabels: phenoLabels,
  );
}

/// 按渲染顺序收集全部 Text 文本（验证行列不错位）。
List<String> _texts(WidgetTester tester) =>
    tester.widgetList<Text>(find.byType(Text)).map((t) => t.data ?? '').toList();

void main() {
  group('zygoteGenotype 纯函数', () {
    test('同型合子 AA / aa', () {
      expect(zygoteGenotype('A', 'A'), 'AA');
      expect(zygoteGenotype('a', 'a'), 'aa');
    });

    test('杂合 Aa 顺序无关，显性大写在前', () {
      expect(zygoteGenotype('A', 'a'), 'Aa');
      expect(zygoteGenotype('a', 'A'), 'Aa');
    });

    test('多位点 AB × ab → AaBb', () {
      expect(zygoteGenotype('AB', 'ab'), 'AaBb');
    });

    test('长度不等按短者截断，不抛异常', () {
      expect(zygoteGenotype('Aa', 'a'), 'Aa');
      expect(zygoteGenotype('a', 'Aa'), 'Aa');
    });

    test('异位点字符原样保留不崩溃', () {
      expect(zygoteGenotype('A', 'B'), 'AB');
    });
  });

  group('CrossBoardView 2×2 单基因棋盘', () {
    testWidgets('Aa × Aa → AA/Aa/Aa/aa，整行文本序列正确', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: CrossBoardView(
          result: _result(g1: const ['A', 'a'], g2: const ['A', 'a']),
          p1: 'Aa',
          p2: 'Aa',
        ),
      ));
      expect(_texts(tester), [
        'P：Aa  ×  Aa',
        '配子：A  a（纵）× A  a（横）',
        'F1', 'A', 'a',
        'A', 'AA', 'Aa',
        'a', 'Aa', 'aa',
        '表型比：3:1（显性 : 隐性）',
      ]);
    });

    testWidgets('行列标题与格内容对得上：行首=纵配子，列首=横配子，格=合子', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: CrossBoardView(
          result: _result(g1: const ['A', 'a'], g2: const ['A', 'a']),
          p1: 'Aa',
          p2: 'Aa',
        ),
      ));
      // 表头行：F1 + 横配子
      final rows = tester.widgetList<Row>(find.byType(Row)).toList();
      expect(rows.length, 3); // 1 表头 + 2 数据行
      // 各行首格文本即该行纵配子，数据行格值 = zygoteGenotype(行首, 列首)
      for (var i = 0; i < 2; i++) {
        final cells = (rows[i + 1].children).map((w) => (w as SizedBox).child as Text).toList();
        expect(cells.first.data, const ['A', 'a'][i]);
        for (var j = 0; j < 2; j++) {
          expect(cells[j + 1].data, zygoteGenotype(const ['A', 'a'][i], const ['A', 'a'][j]));
        }
      }
    });

    testWidgets('表型比行展示 ratio 与标签', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: CrossBoardView(
          result: _result(g1: const ['A', 'a'], g2: const ['A', 'a']),
          p1: 'Aa',
          p2: 'Aa',
        ),
      ));
      expect(find.text('表型比：3:1（显性 : 隐性）'), findsOneWidget);
    });
  });

  group('CrossBoardView 4×4 双基因棋盘', () {
    // 真实引擎数据：AaBb × AaBb
    final engineResult = KaojiCalc().dihybrid9331(p1: 'AaBb', p2: 'AaBb');

    testWidgets('配子 AB/Ab/aB/ab × 同 → 16 格齐全', (tester) async {
      expect(engineResult.gametesP1.toSet(), {'AB', 'Ab', 'aB', 'ab'});
      expect(engineResult.gametesP2.toSet(), {'AB', 'Ab', 'aB', 'ab'});
      await tester.pumpWidget(MaterialApp(
        home: CrossBoardView(result: engineResult, p1: 'AaBb', p2: 'AaBb'),
      ));
      final rows = tester.widgetList<Row>(find.byType(Row)).toList();
      expect(rows.length, 5); // 1 表头 + 4 数据行
      // 数据格总数 4×4 = 16
      var dataCells = 0;
      for (var i = 1; i < rows.length; i++) {
        dataCells += rows[i].children.length - 1;
      }
      expect(dataCells, 16);
    });

    testWidgets('抽查格值：AB×AB=AABB，ab×ab=aabb，Ab×aB=AaBb', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: CrossBoardView(result: engineResult, p1: 'AaBb', p2: 'AaBb'),
      ));
      expect(find.text('AABB'), findsOneWidget);
      expect(find.text('aabb'), findsOneWidget);
      expect(find.text('AaBb'), findsNWidgets(4)); // AB×ab / Ab×aB / aB×Ab / ab×AB 四格
    });
  });

  group('降级表现', () {
    testWidgets('空配子列表：不崩溃，只剩 F1 表头与表型行', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: CrossBoardView(
          result: _result(g1: const [], g2: const []),
          p1: '??',
          p2: '??',
        ),
      ));
      expect(tester.takeException(), isNull);
      expect(find.text('F1'), findsOneWidget);
      expect(find.text('表型比：3:1（显性 : 隐性）'), findsOneWidget);
    });

    testWidgets('单配子列表：1×1 棋盘只出一格', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: CrossBoardView(
          result: _result(g1: const ['A'], g2: const ['A']),
          p1: 'AA',
          p2: 'AA',
        ),
      ));
      final rows = tester.widgetList<Row>(find.byType(Row)).toList();
      expect(rows.length, 2);
      expect(find.text('AA'), findsOneWidget); // 只有合子格
      expect(find.text('A'), findsNWidgets(2)); // 行首 + 列首
    });
  });

  group('重复配子', () {
    testWidgets('两亲本均 Aa：配子各只展示一次 A、a', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: CrossBoardView(
          result: _result(g1: const ['A', 'a'], g2: const ['A', 'a']),
          p1: 'Aa',
          p2: 'Aa',
        ),
      ));
      // 配子行文本即去重后的展示（引擎侧去重）
      expect(find.text('配子：A  a（纵）× A  a（横）'), findsOneWidget);
    });

    testWidgets('配子列表含重复项时忠实渲染不吞列', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: CrossBoardView(
          result: _result(g1: const ['A', 'A'], g2: const ['A']),
          p1: 'Aa',
          p2: 'AA',
        ),
      ));
      // 行首出现两次 A（两行各一），列首一次 A —— 共 3 个 'A' 文本
      expect(find.text('A'), findsNWidgets(3));
    });
  });
}
