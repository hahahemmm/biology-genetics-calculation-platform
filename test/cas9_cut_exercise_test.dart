import 'package:biology/pages/widgets/cas9_cut_exercise.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _proto = 'ACGTACGTACGTACGTACGT';
const _inputKey = Key('cas9-sequence-input');

Future<void> _pumpExercise(
  WidgetTester tester, {
  Size size = const Size(900, 1800),
  bool showInputs = true,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: Cas9CutExercise(showInputs: showInputs),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('上链示例给出 PAM、20 nt 原间隔序列与第 22／23 位切口', (tester) async {
    await _pumpExercise(tester);

    await tester.tap(find.text('上链 NGG 示例'));
    await tester.pumpAndSettle();

    expect(find.text('位点 1 · 上链 NGG'), findsOneWidget);
    expect(find.text('TGG'), findsOneWidget);
    expect(find.text(_proto), findsOneWidget);
    expect(find.text('顶链第 22 位与第 23 位之间（两条链同一边界）'), findsOneWidget);
    expect(find.textContaining('5′-TTTTT${_proto}TGG'), findsOneWidget);
    expect(find.textContaining('↓'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('互补链示例不镜像错：PAM 为 CGG，切在第 10／11 位', (tester) async {
    await _pumpExercise(tester);

    await tester.tap(find.text('互补链 NGG 示例'));
    await tester.pumpAndSettle();

    expect(find.text('位点 1 · 互补链 NGG（顶链 CCN）'), findsOneWidget);
    expect(find.text('CGG'), findsOneWidget);
    expect(find.text('ACGTACGTACGTACGTACGT'), findsOneWidget);
    expect(find.text('顶链第 10 位与第 11 位之间（两条链同一边界）'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('无 PAM 与旁侧不足 20 nt 给出不同教学提示', (tester) async {
    await _pumpExercise(tester);

    await tester.enterText(find.byKey(_inputKey), 'A' * 23);
    await tester.tap(find.text('判断切割位置'));
    await tester.pumpAndSettle();
    expect(find.text('未找到经典 NGG 位点'), findsOneWidget);
    expect(find.textContaining('两条链都未检测到'), findsOneWidget);

    await tester.enterText(find.byKey(_inputKey), 'AGG${'A' * 20}');
    await tester.tap(find.text('判断切割位置'));
    await tester.pumpAndSettle();
    expect(find.text('发现 PAM，但原间隔序列不足 20 nt'), findsOneWidget);
    expect(find.textContaining('1 个 NGG motif'), findsOneWidget);
  });

  testWidgets('非法字符、过短与过长输入均显示可读错误', (tester) async {
    await _pumpExercise(tester);

    await tester.enterText(find.byKey(_inputKey), 'ACGTNACGTACGTACGTACGTACGT');
    await tester.tap(find.text('判断切割位置'));
    await tester.pumpAndSettle();
    expect(find.textContaining('只能含 A、T、C、G'), findsOneWidget);

    await tester.enterText(find.byKey(_inputKey), 'A' * 22);
    await tester.tap(find.text('判断切割位置'));
    await tester.pumpAndSettle();
    expect(find.textContaining('至少 23 bp'), findsOneWidget);

    await tester.enterText(find.byKey(_inputKey), 'A' * 121);
    await tester.tap(find.text('判断切割位置'));
    await tester.pumpAndSettle();
    expect(find.textContaining('上限 120 bp'), findsOneWidget);
  });

  testWidgets('Unicode 非法输入显示可读错误并能通过示例恢复', (tester) async {
    await _pumpExercise(tester);
    final raw = List.filled(121, '\uFB03').join();

    await tester.enterText(find.byKey(_inputKey), raw);
    await tester.tap(find.text('判断切割位置'));
    await tester.pumpAndSettle();

    expect(find.textContaining('只能含 A、T、C、G'), findsOneWidget);
    expect(find.textContaining('先选一个示例'), findsNothing);
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('上链 NGG 示例'));
    await tester.pumpAndSettle();
    expect(find.textContaining('只能含 A、T、C、G'), findsNothing);
    expect(find.text('位点 1 · 上链 NGG'), findsOneWidget);
    expect(find.text('顶链第 22 位与第 23 位之间（两条链同一边界）'), findsOneWidget);
  });

  testWidgets('编辑序列立即清除旧结果，避免旧切口冒充新答案', (tester) async {
    await _pumpExercise(tester);
    await tester.tap(find.text('上链 NGG 示例'));
    await tester.pumpAndSettle();
    expect(find.text('位点 1 · 上链 NGG'), findsOneWidget);

    await tester.enterText(find.byKey(_inputKey), 'A' * 23);
    await tester.pump();

    expect(find.text('位点 1 · 上链 NGG'), findsNothing);
    expect(find.text('顶链第 22 位与第 23 位之间（两条链同一边界）'), findsNothing);
    expect(find.text('先选一个示例，或输入一段 DNA'), findsOneWidget);
  });

  testWidgets('showInputs=false 只保留结果区，不渲染练习输入框', (tester) async {
    await _pumpExercise(tester, showInputs: false);

    expect(find.byType(TextField), findsNothing);
    expect(find.text('判断切割位置'), findsNothing);
    expect(find.text('SpCas9 切割位置练习'), findsOneWidget);
  });

  testWidgets('390 窄屏输入与双链结果零溢出，长序列仅局部横滚', (tester) async {
    await _pumpExercise(tester, size: const Size(390, 1400));
    await tester.enterText(
      find.byKey(_inputKey),
      '${'A' * 97}${'ACGT' * 5}TGG',
    );
    await tester.tap(find.text('判断切割位置'));
    await tester.pumpAndSettle();

    final strandScroll = find.byKey(const Key('cas9-strand-scroll-0'));
    expect(strandScroll, findsOneWidget);
    final scrollable = find.descendant(
      of: strandScroll,
      matching: find.byType(Scrollable),
    );
    final position = tester.state<ScrollableState>(scrollable).position;
    expect(position.maxScrollExtent, greaterThan(0));
    await tester.drag(strandScroll, const Offset(-180, 0));
    await tester.pump();
    expect(position.pixels, greaterThan(0));
    expect(tester.takeException(), isNull);
  });
}
