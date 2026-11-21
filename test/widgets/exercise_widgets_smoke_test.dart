import 'package:biology/pages/widgets/dna_ligase_bond_exercise.dart';
import 'package:biology/pages/widgets/pcr_amplification_exercise.dart';
import 'package:biology/pages/widgets/pcr_cycle_exercise.dart';
import 'package:biology/pages/widgets/primer_extension_exercise.dart';
import 'package:biology/pages/widgets/taq_heat_exercise.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> pumpExercise(WidgetTester tester, Widget exercise) async {
  tester.view.physicalSize = const Size(390, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(child: exercise),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('PcrAmplificationExercise', () {
    testWidgets('初始渲染显示标题与 1 份模板 0 循环的理想产物', (tester) async {
      await pumpExercise(tester, const PcrAmplificationExercise());

      expect(find.byKey(const Key('pcr-amplification-exercise')), findsOneWidget);
      expect(find.text('PCR 循环数如何影响理论产物？'), findsOneWidget);
      expect(find.text('理想产物：1 份目标 DNA 分子'), findsOneWidget);
      expect(find.text('相对初始模板放大 1 倍。'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('点选循环数 4 后产物变为 16 份', (tester) async {
      await pumpExercise(tester, const PcrAmplificationExercise());

      await tester.tap(find.byKey(const Key('pcr-amplification-cycle-4')));
      await tester.pumpAndSettle();

      expect(find.text('理想产物：16 份目标 DNA 分子'), findsOneWidget);
      expect(find.text('相对初始模板放大 16 倍。'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('点选 3 份模板与 4 次循环得 48 份，并提示指数误区', (tester) async {
      await pumpExercise(tester, const PcrAmplificationExercise());

      await tester.tap(find.byKey(const Key('pcr-amplification-initial-3')));
      await tester.tap(find.byKey(const Key('pcr-amplification-cycle-4')));
      await tester.pumpAndSettle();

      expect(find.text('理想产物：48 份目标 DNA 分子'), findsOneWidget);
      expect(
        find.text(
          '辨误区：不是 3 × 4 = 12。循环数在指数上，表示连续乘 4 次 2，'
          '而不是把循环数当作乘数。',
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('PcrCycleExercise', () {
    testWidgets('初始渲染有三步顺序按钮且无反馈', (tester) async {
      await pumpExercise(tester, const PcrCycleExercise());

      expect(find.byKey(const Key('pcr-cycle-exercise')), findsOneWidget);
      expect(find.text('PCR 温度循环的三步顺序是什么？'), findsOneWidget);
      expect(find.text('变性 → 退火 → 延伸'), findsOneWidget);
      expect(find.byKey(const Key('pcr-cycle-feedback')), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('点正确答案显示正确反馈', (tester) async {
      await pumpExercise(tester, const PcrCycleExercise());

      await tester.tap(find.byKey(const Key('pcr-cycle-correct-choice')));
      await tester.pumpAndSettle();

      expect(
        find.text(
          '正确。经典 PCR 按变性→退火→延伸反复循环：双链分开后，'
          '引物与互补序列配对，耐热 DNA 聚合酶再延伸引物、合成新链。',
        ),
        findsOneWidget,
      );
      expect(find.text('经典 PCR 三步顺序'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('点错误答案显示再想一想反馈', (tester) async {
      await pumpExercise(tester, const PcrCycleExercise());

      await tester.tap(find.byKey(const Key('pcr-cycle-anneal-first-choice')));
      await tester.pumpAndSettle();

      expect(
        find.text(
          '再想一想：经典 PCR 先使双链 DNA 变性分开，再降温让引物退火，'
          '不能跳过双链分离直接开始退火。',
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('PrimerExtensionExercise', () {
    testWidgets('初始渲染显示 3′-OH 标题且无反馈', (tester) async {
      await pumpExercise(tester, const PrimerExtensionExercise());

      expect(find.byKey(const Key('primer-extension-exercise')), findsOneWidget);
      expect(find.text('PCR 引物为什么需要游离 3′-OH？'), findsOneWidget);
      expect(find.byKey(const Key('primer-extension-feedback')), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('点正确答案显示 5′→3′ 正确反馈', (tester) async {
      await pumpExercise(tester, const PrimerExtensionExercise());

      await tester.tap(find.byKey(const Key('primer-three-oh-choice')));
      await tester.pumpAndSettle();

      expect(
        find.text(
          '正确。引物为延伸提供起点，新的脱氧核苷酸接到游离 3′-OH 端，'
          '所以新链按 5′→3′ 方向延伸；与之配对的模板链按 3′→5′ 方向被读取。',
        ),
        findsOneWidget,
      );
      expect(find.text('注意：5′→3′ 是此处新链的延伸方向，不是所有酶促反应的方向。'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('点中部接入的错误答案显示对应反馈', (tester) async {
      await pumpExercise(tester, const PrimerExtensionExercise());

      await tester.tap(find.byKey(const Key('primer-middle-choice')));
      await tester.pumpAndSettle();

      expect(
        find.text(
          '再想一想：脱氧核苷酸不是从引物中部随机接入，'
          '而是在已有引物的 3′ 末端继续延伸，方向并非不重要。',
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('TaqHeatExercise', () {
    testWidgets('初始渲染显示 Taq 标题且无反馈', (tester) async {
      await pumpExercise(tester, const TaqHeatExercise());

      expect(find.byKey(const Key('taq-heat-stable-exercise')), findsOneWidget);
      expect(find.text('Taq DNA 聚合酶为什么适合 PCR？'), findsOneWidget);
      expect(find.byKey(const Key('taq-heat-feedback')), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('点耐热性质的正确答案显示正确反馈', (tester) async {
      await pumpExercise(tester, const TaqHeatExercise());

      await tester.tap(find.byKey(const Key('taq-heat-stable-choice')));
      await tester.pumpAndSettle();

      expect(
        find.text(
          '正确。Taq DNA 聚合酶的耐热性质使 PCR 能在较高温度进行，'
          '并适应反复温度循环；这不等于温度越高越好或永远不会失活。',
        ),
        findsOneWidget,
      );
      expect(find.text('Taq 在延伸阶段合成新 DNA 链的方向'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('点温度越高的错误答案显示再想一想反馈', (tester) async {
      await pumpExercise(tester, const TaqHeatExercise());

      await tester.tap(find.byKey(const Key('taq-hotter-choice')));
      await tester.pumpAndSettle();

      expect(
        find.text(
          '再想一想：耐热不等于温度越高越好，也不等于永远不会失活。'
          'PCR 需要按规程控制各阶段温度。',
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('DnaLigaseBondExercise', () {
    testWidgets('初始渲染显示连接酶标题且无反馈', (tester) async {
      await pumpExercise(tester, const DnaLigaseBondExercise());

      expect(find.byKey(const Key('dna-ligase-bond-exercise')), findsOneWidget);
      expect(find.text('DNA 连接酶连接哪种化学键？'), findsOneWidget);
      expect(find.byKey(const Key('dna-ligase-feedback')), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('点磷酸二酯键的正确答案显示正确反馈', (tester) async {
      await pumpExercise(tester, const DnaLigaseBondExercise());

      await tester.tap(find.byKey(const Key('dna-ligase-phosphodiester-bond')));
      await tester.pumpAndSettle();

      expect(
        find.text(
          '正确。DNA 连接酶催化 DNA 骨架缺口处的 3′-OH 与 5′-磷酸'
          '形成磷酸二酯键，封闭缺口；不是连接碱基对之间的氢键。',
        ),
        findsOneWidget,
      );
      expect(find.text('成键位置（概念示意，非完整反应计量）'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('点氢键的错误答案显示再想一想反馈', (tester) async {
      await pumpExercise(tester, const DnaLigaseBondExercise());

      await tester.tap(find.byKey(const Key('dna-ligase-hydrogen-bond')));
      await tester.pumpAndSettle();

      expect(
        find.text(
          '再想一想：氢键负责碱基互补配对，不是连接酶催化的骨架共价连接。'
          '请重新选择。',
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });
  });
}
