// genetic_disease_ctrl_s_save_test.dart —— v2.19.51 遗传病页 Ctrl+S 存题守卫网
//
// 网型纪律（与 molecular/evolution/ploidy/variation ctrl_s_save_test 同源）：
// **取基准必须用一条与被测动作不同的通道**；Ctrl+S 是写入动作，基准
// （页签/输入/结果）一律用「鼠标点 TabBar / tap 计算按钮 / enterText /
// Alt+数字」取得。
//
// 本页 3 个页签只有 tab0（遗传咨询）有计算器；tab1（系谱推断）内嵌
// PedigreeInferenceView 自带「存入错题本」按钮 + CallbackShortcuts 形态
// 的页面级 Ctrl+S（v2.19.15）⇒ 本页宿主对 tab1 必须 null 让路（闸④），
// S2 只钉「本页宿主没写库」（让路后事件沿焦点链由内嵌视图自己应答，
// 应答与否取决于焦点落点，不替它断言）；tab2（分类与预防）是纯内容区
// ⇒ S5 钉 null 闸（编造题干闸）。「有计算器但未算出」的空答案守卫由
// 宿主文件头闸④口径 + S5 的无声断言共同钉住。
// v2.19.53（找茬 D）：S6/S7 钉「新鲜度」门——本页唯一的计算器节输入 =
// 父框 + 母框 + 显隐开关（非文本状态，照倍性/变异「框+开关」入快照先例）：
// S6 改父/母输入不重算、S7 只拨显隐开关不重算，两形态都必须是「答案空
// ⇒ 既有『先算出结果』守卫应答、零写入」。
import 'dart:io';

import 'package:biology/pages/genetic_disease_page.dart';
import 'package:biology/state/first_run_store.dart';
import 'package:biology/state/mistake_book.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

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
    tmp = Directory.systemTemp.createTempSync('genetic_disease_ctrl_s');
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

  Future<void> pumpPage(WidgetTester tester) async {
    tester.view.physicalSize = const Size(800, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const MaterialApp(home: GeneticDiseasePage()));
    await tester.pump();
  }

  // fake_async 语义：用例体内触发的写盘/AI debounce（500ms）必须在
  // **用例体内**显式取消——tearDown 跑在 body zone 之外，来不及（同 v213）。
  void cancelPendingTimers() {
    MistakeBook.instance.debugFlushSave();
    MistakeBook.instance.debugResetAiOrganize();
  }

  Future<void> tapCalc(WidgetTester tester) async {
    final b = find.text('计算');
    expect(b, findsOneWidget, reason: '前提：tab0 计算按钮在屏');
    await tester.ensureVisible(b);
    await tester.pump();
    await tester.tap(b);
    await tester.pumpAndSettle();
  }

  testWidgets('S1·tab0 遗传咨询算出后 Ctrl+S：条目原样入库（题干/答案/考点/来源）', (tester) async {
    await pumpPage(tester);
    final fF = find.widgetWithText(TextField, '父亲基因型（如 Aa / XAY）');
    expect(fF, findsOneWidget);
    await tester.ensureVisible(fF);
    await tester.pump();
    await tester.enterText(fF, 'Aa'); // 覆盖出厂 XAY，验现文
    await tester.pump();
    final fM = find.widgetWithText(TextField, '母亲基因型（如 Aa / XAXa）');
    expect(fM, findsOneWidget);
    await tester.ensureVisible(fM);
    await tester.pump();
    await tester.enterText(fM, 'aa'); // 覆盖出厂 XAXa
    await tester.pump();
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump();
    await tapCalc(tester);
    expect(
      find.textContaining('患病概率'),
      findsWidgets,
      reason: '前提：结果已算出（Aa × aa 隐性 ⇒ 患病 50%）',
    );

    await _ctrlS(tester);

    expect(
      find.textContaining('已加入错题本'),
      findsOneWidget,
      reason: '存入回执 SnackBar',
    );
    final entries = MistakeBook.instance.entries;
    expect(entries, hasLength(1));
    expect(
      entries.single.stem,
      contains('父亲基因型 Aa'),
      reason: '题干取输入框现文（Aa 是学生刚敲的，非出厂 XAY）',
    );
    expect(
      entries.single.stem,
      contains('母亲基因型 aa'),
      reason: '题干覆盖母亲输入现文（非出厂 XAXa）',
    );
    expect(
      entries.single.stem,
      contains('隐性患病'),
      reason: '题干带显隐模式中文标签（出厂 _rec=true）',
    );
    expect(
      entries.single.stem,
      isNot(contains('XAY')),
      reason: '⛔ 题干里不许残留出厂父亲基因型 XAY',
    );
    expect(
      entries.single.correctAnswer,
      contains('患病概率 50.0%'),
      reason: '答案取引擎字段 DiseaseRiskResult.affectedRate（_pct 同款）',
    );
    expect(
      entries.single.correctAnswer,
      contains('携带者概率 50.0%'),
      reason: '答案取引擎字段 carrierRate（Aa × aa 隐性 ⇒ 杂合携带 50%）',
    );
    expect(
      entries.single.correctAnswer,
      contains('常染色体单基因遗传'),
      reason: '答案取引擎字段 note',
    );
    expect(
      entries.single.correctAnswer,
      contains('亲本配子'),
      reason: '答案全引擎字段：fatherGametes/motherGametes/offspring 都在',
    );
    expect(entries.single.subjectArea, '遗传咨询（单基因遗传病风险）', reason: '考点按页签点名');
    expect(
      entries.single.srcModule,
      'disease_risk',
      reason:
          'disease_risk 是 HomeShell 常驻注册的真 target（main.dart '
          'registerAppLevelModuleTargets）：fill 的 push 分支入队 params + '
          'push 新实例，新实例 initState consumePending → _applyDiseaseRisk '
          '真实回填 _fCtrl/_mCtrl/_rec 并重算（参数键 father/mother/mode）'
          '⇒ 回程按钮不是摆设',
    );
    expect(entries.single.srcParams?['father'], 'Aa');
    expect(entries.single.srcParams?['mother'], 'aa');
    expect(entries.single.srcParams?['mode'], 'rec');
    cancelPendingTimers();
  });

  testWidgets('S2·stale-capture 闸：切到「系谱推断」后 Ctrl+S 本页宿主没写库，'
      '切回 tab0 存上（⛔ 不许把已切走那道写进错题本）', (tester) async {
    await pumpPage(tester);
    await tapCalc(tester); // tab0 遗传咨询算出（出厂 XAY × XAXa 隐性）
    expect(MistakeBook.instance.entries, isEmpty);

    // 键盘通道切到 tab1「系谱推断」：内嵌 PedigreeInferenceView 自带
    // 「存入错题本」按钮 + CallbackShortcuts 形态的页面级 Ctrl+S
    // （v2.19.15）——本页宿主对这一签返回 null 让路（闸④），事件沿焦点链
    // 由内嵌视图自己应答（应答与否取决于焦点落点，这里只钉本页宿主
    // 没写库；⛔ 绝不允许 tab1 把题写两遍）。
    await _altDigit(tester, LogicalKeyboardKey.digit2);
    await _ctrlS(tester);
    expect(
      MistakeBook.instance.entries,
      isEmpty,
      reason: '⛔ 已切走页签的题不许被无声写库（B 仓 v2.19.173 真 bug 形态）',
    );
    expect(
      find.textContaining('已加入错题本'),
      findsNothing,
      reason: '本页宿主没写库 ⇒ 没有存入回执',
    );

    // 键盘通道切回 tab0，同一枚键存上已算出的那道。
    await _altDigit(tester, LogicalKeyboardKey.digit1);
    await _ctrlS(tester);
    final entries = MistakeBook.instance.entries;
    expect(entries, hasLength(1));
    expect(
      entries.single.stem,
      contains('父亲基因型 XAY'),
      reason: '切回后入库的是 tab0 现文题干（出厂 XAY × XAXa）',
    );
    expect(
      entries.single.stem,
      isNot(contains('系谱')),
      reason: '⛔ 题干里不许混入 tab1 系谱推断的内容',
    );
    expect(entries.single.subjectArea, '遗传咨询（单基因遗传病风险）');
    cancelPendingTimers();
  });

  testWidgets('S3·输入焦点让路：TextField 持焦时 Ctrl+S 无声无写，失焦后必存', (tester) async {
    await pumpPage(tester);
    await tapCalc(tester);
    // 再聚焦输入框（持焦态）。
    final f = find.widgetWithText(TextField, '父亲基因型（如 Aa / XAY）');
    expect(f, findsOneWidget);
    await tester.ensureVisible(f);
    await tester.pump();
    await tester.tap(f);
    await tester.pump();
    await _ctrlS(tester);
    expect(MistakeBook.instance.entries, isEmpty, reason: '闸③：敲到一半/持焦时不存');
    expect(find.textContaining('已加入错题本'), findsNothing);
    expect(
      find.textContaining('先算出结果'),
      findsNothing,
      reason: '让路 = 无声，连守卫 SnackBar 也不弹',
    );
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump();
    await _ctrlS(tester);
    expect(
      MistakeBook.instance.entries,
      hasLength(1),
      reason: '失焦后同一枚键必存——证明刚才确系焦点闸拦的',
    );
    cancelPendingTimers();
  });

  testWidgets('S4·Ctrl+Alt+S 不认领（闸①修饰键精确）', (tester) async {
    await pumpPage(tester);
    await tapCalc(tester);
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.alt);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyS);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.alt);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    expect(MistakeBook.instance.entries, isEmpty);
  });

  testWidgets('S5·无计算器页签（分类与预防）null 闸：tab0 算出后切 tab3 按 '
      'Ctrl+S 无声无写（闸④编造题干闸）', (tester) async {
    await pumpPage(tester);
    await tapCalc(tester); // tab0 已算出（库中仍空）
    expect(MistakeBook.instance.entries, isEmpty);

    // 键盘通道切到 tab2「分类与预防」：纯内容区，没有计算器。
    await _altDigit(tester, LogicalKeyboardKey.digit3);
    expect(
      find.text('遗传病分类速查'),
      findsOneWidget,
      reason: '前提：tab2 分类与预防在屏（body 区标题）',
    );
    await _ctrlS(tester);
    expect(
      MistakeBook.instance.entries,
      isEmpty,
      reason: '⛔ 切走后在无计算器页签按 Ctrl+S，已切走那道也不许被写库',
    );
    expect(find.textContaining('已加入错题本'), findsNothing);
    expect(
      find.textContaining('先算出结果'),
      findsNothing,
      reason: 'null 闸 = 无声让路，连守卫 SnackBar 也不弹',
    );
  });

  testWidgets('S6·stale 闸（单节全剔）：算出后改父/母输入不重算，Ctrl+S 被'
      '「先算出结果」守卫拦下、零写入', (tester) async {
    await pumpPage(tester);
    await tapCalc(tester); // tab0 遗传咨询算出（出厂 XAY × XAXa 隐性）
    expect(MistakeBook.instance.entries, isEmpty);
    // 改输入但不重算（题面与屏上结果开始自相矛盾）。
    final fF = find.widgetWithText(TextField, '父亲基因型（如 Aa / XAY）');
    expect(fF, findsOneWidget);
    await tester.ensureVisible(fF);
    await tester.pump();
    await tester.enterText(fF, 'Aa');
    await tester.pump();
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump();
    await _ctrlS(tester);
    expect(find.textContaining('先算出结果'), findsOneWidget,
        reason: '唯一的一节 stale ⇒ 答案空 ⇒ 既有守卫应答');
    expect(MistakeBook.instance.entries, isEmpty,
        reason: '⛔ 矛盾题（题干 Aa + 答案按 XAY 算）不许入库存');
  });

  testWidgets('S7·stale 闸（开关态矛盾）：tab0 算出后只拨显隐开关不重算，'
      'Ctrl+S 被「先算出结果」守卫拦下、零写入（框+开关入快照先例）',
      (tester) async {
    await pumpPage(tester);
    await tapCalc(tester); // tab0（出厂 XAY / XAXa / 隐性）算出
    expect(MistakeBook.instance.entries, isEmpty);
    // 只拨开关不重算：题干会说「显性」而答案仍是按隐性算的——显隐开关
    // 直接喂引擎（照倍性/变异「框+开关」入快照先例）⇒ 只拨开关同样算 stale。
    final chip = find.widgetWithText(ChoiceChip, '显性患病');
    expect(chip, findsOneWidget, reason: '前提：tab0 显隐开关在屏');
    await tester.tap(chip);
    await tester.pumpAndSettle();
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump();
    await _ctrlS(tester);
    expect(find.textContaining('先算出结果'), findsOneWidget,
        reason: '唯一的一节 stale ⇒ 答案空 ⇒ 既有守卫应答');
    expect(MistakeBook.instance.entries, isEmpty,
        reason: '⛔ 矛盾题（题干显性 + 答案按隐性算）不许入库存');
  });
}
