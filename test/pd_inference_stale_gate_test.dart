// pd_inference_stale_gate_test.dart —— v2.19.56 系谱推断存题 stale
// 快照门守卫网（找茬 D 收尾，照 v2.19.53 分子/变异页 + v2.19.56 9331
// 四 tab 同款先例）。
//
// 推断视图唯一存题节（练习/推断结果）的输入面 = 成员行 _rows
// （id/性别/表型/父/母）：_run() 重算成功那一刻把行序列化落 _pdSnap
// （与 _outcome 同生——同一次 _run 的输入/输出严格同源），Ctrl+S 组装
// payload 时「结果存在且快照==现文」才算新鲜；成员变动未重跑 ⇒ 题干/
// 答案空串 ⇒ saveToMistakeBook 既有「先算出结果」守卫应答、零写入。
// userAnswer（学生作答）不是题面——stale 也照常带出。
//
// 网型纪律（与 molecular/9331 ctrl_s 测试同源）：取基准必须用一条与被测
// 动作不同的通道；Ctrl+S 是写入动作，基准（载入示例/运行推断/增员）一律
// 用「鼠标点 chip / tap 按钮」取得。
//
// 边界用例 S2 说明：现网所有编辑入口都随手清 _outcome（性别/表型/父母
// chip、增删、载入示例/识别、练习切换、清空），UI 走不到「结果还在、
// 题面已改」的态——S2 用 debugEditMemberKeepingOutcome 模拟「未来某个
// 编辑入口漏写 _outcome=null」的回归态，专钉快照门的兜底价值（门被摘 ⇒
// 矛盾题直写入库 ⇒ S2 红）。
import 'dart:io';

import 'package:biology/engine/pedigree_inference.dart';
import 'package:biology/pages/genetic_disease_page.dart';
import 'package:biology/pages/widgets/pedigree_inference_view.dart';
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

void main() {
  late Directory tmp;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('pd_inference_stale');
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
    tester.view.physicalSize = const Size(800, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const MaterialApp(home: GeneticDiseasePage()));
    await tester.pump();
    // v2.19.28 工作台化：推断器收在「系谱推断」tab——切过去即渲染。
    await tester.tap(find.text('系谱推断'));
    await tester.pumpAndSettle();
  }

  /// 鼠标通道：载入常隐金标准并运行推断（基准不用键盘）。
  Future<void> loadClassicAndRun(WidgetTester tester) async {
    await tester.tap(find.text('常隐·无中生有'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('运行推断'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('运行推断'));
    await tester.pumpAndSettle();
    expect(find.textContaining('最可能：'), findsOneWidget,
        reason: '前提：金标准已跑出结论');
  }

  // fake_async 语义：用例体内触发的写盘/AI debounce（500ms）必须在
  // **用例体内**显式取消——tearDown 跑在 body zone 之外，来不及（同 v213）。
  void cancelPendingTimers() {
    MistakeBook.instance.debugFlushSave();
    MistakeBook.instance.debugResetAiOrganize();
  }

  testWidgets(
      'S1·stale 闸（增员不重跑）：算出后添加成员不重跑，Ctrl+S 被'
      '「先算出结果」拦下、零写入（重跑后同键必存，题干含新成员口径）',
      (tester) async {
    await pumpPage(tester);
    await loadClassicAndRun(tester);
    expect(MistakeBook.instance.entries, isEmpty);
    // 增一名成员但不重跑（题面（_rows 现文）与屏上旧结论开始自相矛盾）。
    await tester.tap(find.text('添加成员'));
    await tester.pumpAndSettle();
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump();
    await _ctrlS(tester);
    expect(find.textContaining('先算出结果'), findsOneWidget,
        reason: '系谱节 stale（4 名成员未重跑）⇒ 答案空 ⇒ 既有守卫应答');
    expect(MistakeBook.instance.entries, isEmpty,
        reason: '⛔ 系谱矛盾题（题干 4 名成员 + 答案按 3 名成员算）'
            '不许入库存');
    // 重跑后同键必存——证明门只拦 stale，不过度拦新鲜节。
    await tester.ensureVisible(find.text('运行推断'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('运行推断'));
    await tester.pumpAndSettle();
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump();
    await _ctrlS(tester);
    final entries = MistakeBook.instance.entries;
    expect(entries, hasLength(1));
    expect(entries.single.stem, contains('4 名成员'),
        reason: '题干按现文（新成员已录入，重跑后题面与答案同源）');
    expect(entries.single.stem, contains('M4'),
        reason: '题干含新成员口径');
    expect(entries.single.correctAnswer, contains('最可能：'),
        reason: '重跑后答案非空');
    expect(entries.single.subjectArea, '人类遗传病', reason: '考点按节点名');
    cancelPendingTimers();
  });

  testWidgets(
      'S2·stale 闸（漏清结果回归态）：算出后模拟「编辑入口漏写 '
      '_outcome=null」，Ctrl+S 被「先算出结果」拦下、零写入（重跑后'
      '同键必存，题干含改动后口径）', (tester) async {
    await pumpPage(tester);
    await loadClassicAndRun(tester);
    expect(MistakeBook.instance.entries, isEmpty);
    // 回归态：I1 由正常改患病但 _outcome 未被清——此刻 best 仍是按旧行
    // 算的结论，题面与答案已不同源；生产 UI 走不到这态（所有编辑入口
    // 随手清 _outcome），debugEditMemberKeepingOutcome 专模拟「未来漏写」。
    final state = tester.state<PedigreeInferenceViewState>(
        find.byType(PedigreeInferenceView));
    state.debugEditMemberKeepingOutcome('I1', PdStatus.affected);
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump();
    await _ctrlS(tester);
    expect(find.textContaining('先算出结果'), findsOneWidget,
        reason: '结果还在但快照先于重算（题面 I1 患病 + 答案按 I1 正常'
            '算）⇒ stale ⇒ 既有守卫应答');
    expect(MistakeBook.instance.entries, isEmpty,
        reason: '⛔ 系谱矛盾题（题干 I1 患病 + 答案按旧行算）不许入库存');
    // 重跑后同键必存——题干按改动后现文。
    await tester.ensureVisible(find.text('运行推断'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('运行推断'));
    await tester.pumpAndSettle();
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump();
    await _ctrlS(tester);
    final entries = MistakeBook.instance.entries;
    expect(entries, hasLength(1));
    expect(entries.single.stem, contains('I1 男·患病'),
        reason: '题干含改动后口径（I1 已患病，重跑后题面与答案同源）');
    expect(entries.single.correctAnswer, contains('最可能：'),
        reason: '重跑后答案非空');
    cancelPendingTimers();
  });
}
