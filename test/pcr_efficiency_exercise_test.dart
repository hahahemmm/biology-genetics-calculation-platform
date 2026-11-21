import 'package:biology/data/bio_knowledge_data.dart';
import 'package:biology/engine/pcr_engine.dart';
import 'package:biology/pages/widgets/pcr_efficiency_exercise.dart';
import 'package:biology/ui/tex_formula.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PCR 恒定效率数学模型', () {
    test('100% 与理想模型一致，90% 四轮为 13.0321', () {
      expect(pcrConstantEfficiencyProduct(cycles: 4, efficiency: 1), 16);
      expect(
        pcrConstantEfficiencyProduct(cycles: 4, efficiency: 0.9),
        closeTo(13.0321, 1e-10),
      );
      expect(
        pcrConstantEfficiencyProduct(cycles: 10, efficiency: 0.8),
        closeTo(357.0467226624, 1e-9),
      );
    });

    test('0 次循环或 0% 效率保留初始模板，支持多份模板', () {
      expect(
        pcrConstantEfficiencyProduct(
          initialTemplates: 3,
          cycles: 0,
          efficiency: 0.8,
        ),
        3,
      );
      expect(
        pcrConstantEfficiencyProduct(
          initialTemplates: 3,
          cycles: 10,
          efficiency: 0,
        ),
        3,
      );
      expect(
        pcrConstantEfficiencyProduct(
          initialTemplates: 3,
          cycles: 10,
          efficiency: 0.8,
        ),
        closeTo(1071.1401679872, 1e-9),
      );
    });

    test('拒绝非法效率、非有限数与越界计数', () {
      for (final efficiency in [-0.01, 1.01, double.nan, double.infinity]) {
        expect(
          () => pcrConstantEfficiencyProduct(cycles: 4, efficiency: efficiency),
          throwsA(isA<ArgumentError>()),
          reason: 'efficiency=$efficiency',
        );
      }
      expect(
        () => pcrConstantEfficiencyProduct(
          initialTemplates: 0,
          cycles: 4,
          efficiency: 0.9,
        ),
        throwsArgumentError,
      );
      for (final cycles in [-1, 31]) {
        expect(
          () => pcrConstantEfficiencyProduct(cycles: cycles, efficiency: 0.9),
          throwsArgumentError,
        );
      }
    });
  });

  test('效率证据来自真实 PubMed 条目且离线筛选不混入平台期综述', () {
    final record = kBioKnowledgeRecords.singleWhere((r) => r.id == '8013946');
    expect(record.title, 'Quantitative analysis in molecular diagnostics.');
    expect(record.subtitle, contains('1994'));
    expect(record.summary, contains('指数阶段'));
    expect(record.summary, contains('平台期'));
    expect(record.caution, contains('恒定效率'));
    expect(record.url, 'https://pubmed.ncbi.nlm.nih.gov/8013946/');
    expect(
      record.facts.map((fact) => fact.value),
      containsAll(<String>['8013946', '10.1016/0046-8177(94)90221-6']),
    );
    expect(filterBioKnowledge(query: 'PCR 效率对照').map((r) => r.id), <String>[
      '23399825',
      '8013946',
    ]);
  });

  testWidgets('对照卡动态显示 TeX、效率结果和模型边界', (tester) async {
    var evidenceCalls = 0;
    tester.view.physicalSize = const Size(390, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: PcrEfficiencyExercise(onShowEvidence: () => evidenceCalls++),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final result = find.byKey(const Key('pcr-efficiency-result'));
    expect(find.byKey(const Key('pcr-efficiency-exercise')), findsOneWidget);
    expect(find.text('理想模型：16 份'), findsOneWidget);
    expect(find.text('恒定效率模型：13.0321 份（约为理想的 81.45%）'), findsOneWidget);
    expect(
      find.descendant(of: result, matching: find.byType(TexFormula)),
      findsNWidgets(2),
    );
    expect(tester.getSemantics(result).label, contains('每轮效率 90%'));

    await tester.tap(find.byKey(const Key('pcr-efficiency-percent-80')));
    await tester.tap(find.byKey(const Key('pcr-efficiency-cycle-10')));
    await tester.pumpAndSettle();
    expect(find.text('理想模型：1024 份'), findsOneWidget);
    expect(find.text('恒定效率模型：357.0467 份（约为理想的 34.87%）'), findsOneWidget);
    expect(find.textContaining('本卡没有模拟平台期'), findsOneWidget);

    await tester.tap(find.byKey(const Key('pcr-efficiency-percent-100')));
    await tester.pumpAndSettle();
    expect(find.text('恒定效率模型：1024.0000 份（约为理想的 100.00%）'), findsOneWidget);
    await tester.tap(find.widgetWithText(ActionChip, '查看效率与平台期证据'));
    expect(evidenceCalls, 1);
    semantics.dispose();
    expect(tester.takeException(), isNull);
  });
}
