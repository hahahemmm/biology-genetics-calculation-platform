// variation_ctrl_s_save_test.dart —— v2.19.51 变异页 Ctrl+S 存题守卫网
//
// 网型纪律（与 molecular/evolution/ploidy ctrl_s_save_test 同源）：**取基准
// 必须用一条与被测动作不同的通道**；Ctrl+S 是写入动作，基准（页签/输入/
// 结果）一律用「鼠标点 TabBar / tap 计算按钮 / enterText / Alt+数字」取得。
//
// 本页 4 个页签里 tab2（结构变异）/ tab3（诱变与育种）是纯展示/知识区、
// 没有计算器 ⇒ S5 钉 null 闸（编造题干闸）：默认页签算出后切到 tab3 按
// Ctrl+S 必须无声无写；「有计算器但未算出」的空答案守卫由 S2 第一阶段钉住。
import 'dart:io';

import 'package:biology/pages/variation_page.dart';
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
    tmp = Directory.systemTemp.createTempSync('variation_ctrl_s');
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
    await tester.pumpWidget(const MaterialApp(home: VariationPage()));
    await tester.pump();
  }

  // fake_async 语义：用例体内触发的写盘/AI debounce（500ms）必须在
  // **用例体内**显式取消——tearDown 跑在 body zone 之外，来不及（同 v213）。
  void cancelPendingTimers() {
    MistakeBook.instance.debugFlushSave();
    MistakeBook.instance.debugResetAiOrganize();
  }

  Future<void> tapCalc(WidgetTester tester, String label) async {
    final b = find.text(label);
    expect(b, findsOneWidget, reason: '前提：按钮 $label 在屏');
    await tester.ensureVisible(b);
    await tester.pump();
    await tester.tap(b);
    await tester.pumpAndSettle();
  }

  testWidgets('S1·tab0 基因突变算出后 Ctrl+S：条目原样入库（题干/答案/考点/来源）',
      (tester) async {
    await pumpPage(tester);
    final fSeq = find.widgetWithText(TextField, 'DNA 序列（仅 A/T/G/C）');
    expect(fSeq, findsOneWidget);
    await tester.ensureVisible(fSeq);
    await tester.pump();
    await tester.enterText(fSeq, 'AATTGGCC'); // 覆盖出厂 ATGCCGTA，验现文
    await tester.pump();
    final fPos = find.widgetWithText(TextField, '突变位置（0 起点，数字）');
    expect(fPos, findsOneWidget);
    await tester.ensureVisible(fPos);
    await tester.pump();
    await tester.enterText(fPos, '5'); // 覆盖出厂 2
    await tester.pump();
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump();
    await tapCalc(tester, '模拟突变');
    expect(find.textContaining('TGG → TGA'), findsWidgets,
        reason: '前提：结果已算出（AATTGGCC 位置 5 替换 ⇒ 密码子 TGG→TGA）');

    await _ctrlS(tester);

    expect(find.textContaining('已加入错题本'), findsOneWidget,
        reason: '存入回执 SnackBar');
    final entries = MistakeBook.instance.entries;
    expect(entries, hasLength(1));
    expect(entries.single.stem, contains('AATTGGCC'),
        reason: '题干取的是输入框现文（AATTGGCC 是学生刚敲的，非出厂 ATGCCGTA）');
    expect(entries.single.stem, contains('位置 5'),
        reason: '题干覆盖位置输入现文（非出厂 2）');
    expect(entries.single.correctAnswer, contains('突变后序列 AATTGACC'),
        reason: '答案取引擎字段 MutatedSequence.mutated');
    expect(entries.single.correctAnswer, contains('TGG → TGA'),
        reason: '答案取引擎字段 originalCodon/mutatedCodon');
    expect(entries.single.subjectArea, '基因突变模拟（碱基替换/插入/缺失）',
        reason: '考点按页签点名，不四签共用一签');
    expect(entries.single.srcModule, 'gene_mutation',
        reason: '本页 initState 注册的 moduleId=gene_mutation 其 apply='
            '_applyGeneMutation：引擎探针校验后真实回填 _seqCtrl/_posCtrl/_mutType '
            '并 _calcMut 重算（参数键 sequence/type/position）⇒ 存进去的那节'
            '能被真实回填，传了回程按钮才不是摆设');
    expect(entries.single.srcParams?['sequence'], 'AATTGGCC');
    expect(entries.single.srcParams?['type'], '替换');
    expect(entries.single.srcParams?['position'], '5');
    cancelPendingTimers();
  });

  testWidgets('S2·stale-capture 闸：切页签后 Ctrl+S 存的是**新**页签的题，'
      '⛔ 不许把已切走那道写进错题本', (tester) async {
    await pumpPage(tester);
    await tapCalc(tester, '模拟突变'); // tab0 基因突变算出（出厂 ATGCCGTA/2/替换）
    expect(MistakeBook.instance.entries, isEmpty);

    // 键盘通道切到 tab1「染色体组数」（未算任何东西）。
    await _altDigit(tester, LogicalKeyboardKey.digit2);
    await _ctrlS(tester);
    // 新页签未算出 ⇒ 既有守卫应答；⛔ 且库里不得出现 tab0 那道题。
    expect(find.textContaining('先算出结果'), findsOneWidget);
    expect(MistakeBook.instance.entries, isEmpty,
        reason: '⛔ 已切走页签的题不许被无声写库（B 仓 v2.19.173 真 bug 形态）');

    // 在 tab1 判断组数（默认基因型改为 AAAaBBbb ⇒ 4 组），再 Ctrl+S ⇒
    // 入库 tab1 的题。
    final fGeno =
        find.widgetWithText(TextField, '基因型（字母表等位基因，不分大小写）');
    expect(fGeno, findsOneWidget);
    await tester.ensureVisible(fGeno);
    await tester.pump();
    await tester.enterText(fGeno, 'AAAaBBbb');
    await tester.pump();
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump();
    await tapCalc(tester, '判断染色体组数');
    expect(find.textContaining('4 个染色体组（四倍体）'), findsWidgets,
        reason: '前提：AAAaBBbb ⇒ 4 组（四倍体）');
    await _ctrlS(tester);
    final entries = MistakeBook.instance.entries;
    expect(entries, hasLength(1));
    expect(entries.single.stem, contains('AAAaBBbb'),
        reason: '入库的是**新**页签的题，不是已切走的 tab0');
    expect(entries.single.stem, isNot(contains('ATGCCGTA')),
        reason: '⛔ 题干里不许残留已切走 tab0 的输入');
    expect(entries.single.subjectArea, '染色体组数判断（基因型法）');
    expect(entries.single.correctAnswer, contains('4 个染色体组'));
    expect(entries.single.srcModule, isNull,
        reason: '本页唯一真 target gene_mutation 只回填 tab0 的 _seqCtrl/'
            '_posCtrl/_mutType；tab1 的 _genoCtrl 没有任何 target 能回填 '
            '（cross_chromosomal_struct 只高亮结构变异条目，且那一签没有'
            '计算器）⇒ 传了会出现点下去答非所问的回程按钮');
    expect(entries.single.srcParams, isNull);
    cancelPendingTimers();
  });

  testWidgets('S3·输入焦点让路：TextField 持焦时 Ctrl+S 无声无写，失焦后必存',
      (tester) async {
    await pumpPage(tester);
    await tapCalc(tester, '模拟突变');
    // 再聚焦输入框（持焦态）。
    final f = find.widgetWithText(TextField, 'DNA 序列（仅 A/T/G/C）');
    expect(f, findsOneWidget);
    await tester.ensureVisible(f);
    await tester.pump();
    await tester.tap(f);
    await tester.pump();
    await _ctrlS(tester);
    expect(MistakeBook.instance.entries, isEmpty,
        reason: '闸③：敲到一半/持焦时不存');
    expect(find.textContaining('已加入错题本'), findsNothing);
    expect(find.textContaining('先算出结果'), findsNothing,
        reason: '让路 = 无声，连守卫 SnackBar 也不弹');
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump();
    await _ctrlS(tester);
    expect(MistakeBook.instance.entries, hasLength(1),
        reason: '失焦后同一枚键必存——证明刚才确系焦点闸拦的');
    cancelPendingTimers();
  });

  testWidgets('S4·Ctrl+Alt+S 不认领（闸①修饰键精确）', (tester) async {
    await pumpPage(tester);
    await tapCalc(tester, '模拟突变');
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

  testWidgets('S5·无计算器页签（诱变与育种）null 闸：tab0 算出后切 tab4 按 '
      'Ctrl+S 无声无写（闸④编造题干闸）', (tester) async {
    await pumpPage(tester);
    await tapCalc(tester, '模拟突变'); // tab0 已算出（库中仍空）
    expect(MistakeBook.instance.entries, isEmpty);

    // 键盘通道切到 tab3「诱变与育种」：纯展示/知识区，没有计算器。
    await _altDigit(tester, LogicalKeyboardKey.digit4);
    expect(find.text('诱变因素'), findsOneWidget,
        reason: '前提：tab3 诱变与育种在屏（body 区标题）');
    await _ctrlS(tester);
    expect(MistakeBook.instance.entries, isEmpty,
        reason: '⛔ 切走后在无计算器页签按 Ctrl+S，已切走那道也不许被写库');
    expect(find.textContaining('已加入错题本'), findsNothing);
    expect(find.textContaining('先算出结果'), findsNothing,
        reason: 'null 闸 = 无声让路，连守卫 SnackBar 也不弹');
  });

  // v2.19.53（找茬 D）：stale 快照门在变异页落地（蓝本：分子页 S6/S7、
  // 进化页 S7、倍性页 S6/S7）。每个计算器节在算出那一刻存一份输入快照
  // （_xxxSnap），Ctrl+S 时「结果存在且快照==现文」才算新鲜；改输入未重算
  // ⇒ 该节题干/答案全剔 ⇒ 全节 stale 时答案空串 ⇒ 既有「先算出结果」守卫拦下。
  testWidgets('S6·stale 闸（单节全剔）：tab0 基因突变算出后改序列输入不重算，'
      'Ctrl+S 被「先算出结果」守卫拦下、零写入', (tester) async {
    await pumpPage(tester);
    await tapCalc(tester, '模拟突变'); // tab0（出厂 ATGCCGTA/2/替换）算出
    expect(MistakeBook.instance.entries, isEmpty);
    // 改输入但不重算（题面与屏上结果开始自相矛盾）。
    final fSeq = find.widgetWithText(TextField, 'DNA 序列（仅 A/T/G/C）');
    expect(fSeq, findsOneWidget);
    await tester.ensureVisible(fSeq);
    await tester.pump();
    await tester.enterText(fSeq, 'TTTTCCCC');
    await tester.pump();
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump();
    await _ctrlS(tester);
    expect(find.textContaining('先算出结果'), findsOneWidget,
        reason: '唯一的一节 stale ⇒ 答案空 ⇒ 既有守卫应答');
    expect(MistakeBook.instance.entries, isEmpty,
        reason: '⛔ 矛盾题（题干 TTTTCCCC + 答案按 ATGCCGTA 算）不许入库存');
  });

  testWidgets('S7·stale 闸（开关态矛盾）：tab0 算出后只拨突变类型开关不重算，'
      'Ctrl+S 被「先算出结果」守卫拦下、零写入（框+开关入快照先例）',
      (tester) async {
    await pumpPage(tester);
    await tapCalc(tester, '模拟突变'); // tab0（出厂 ATGCCGTA/2/替换）算出
    expect(MistakeBook.instance.entries, isEmpty);
    // 只拨开关不重算：题干会说「缺失」而答案仍是按替换算的——类型开关
    // 直接喂引擎（照倍性页「框+开关」入快照先例）⇒ 只拨开关同样算 stale。
    final chip = find.widgetWithText(ChoiceChip, '缺失');
    expect(chip, findsOneWidget, reason: '前提：tab0 突变类型开关在屏');
    await tester.tap(chip);
    await tester.pumpAndSettle();
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump();
    await _ctrlS(tester);
    expect(find.textContaining('先算出结果'), findsOneWidget,
        reason: '唯一的一节 stale ⇒ 答案空 ⇒ 既有守卫应答');
    expect(MistakeBook.instance.entries, isEmpty,
        reason: '⛔ 矛盾题（题干缺失 + 答案按替换算）不许入库存');
  });
}
