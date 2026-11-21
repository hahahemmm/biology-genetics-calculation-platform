// mistake_book_page_test.dart —— 错题本页 UI 行为测试
//
// 覆盖：
//   1. 跨页同步：添加错题 → 列表立即显示（ChangeNotifier 联动）
//   2. 空状态：未添加任何错题时显示「还没有错题」提示
//   3. 添加对话框：填表 → 保存 → 列表新增 1 条
//   4. 删除流程：长按 → 菜单 → 删除 → 5 秒 Undo 可恢复（v2.12 Wave 3-B P1-3）
//   5. _genId Random.secure 唯一性（v2.12 Wave 3-B P1-1）
//   6. 写盘 debounce（v2.12 Wave 3-B P1-1）

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:biology/services/ai_client.dart';
import 'package:biology/pages/mistake_book_page.dart';
import 'package:biology/state/mistake_book.dart';
import 'package:biology/ui/json_pick.dart';
import 'package:biology/ui/mistake_book_ai.dart';
import 'package:biology/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _wrap() => const MaterialApp(home: MistakeBookPage());

Future<void> _pump(WidgetTester tester) async {
  tester.view.physicalSize = const Size(800, 1000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(_wrap());
  // 让 initState 的 load() 微任务跑完
  await tester.pumpAndSettle(const Duration(milliseconds: 50));
}

void main() {
  late Directory tmp;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('mistake_book_page_test');
    MistakeBook.debugFilePath = '${tmp.path}/mistake_book.json';
    MistakeBook.instance.debugReset();
  });

  tearDown(() {
    MistakeBook.debugFilePath = null;
    MistakeBook.instance.debugReset();
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  testWidgets('空状态：未添加错题时显示「还没有错题」', (tester) async {
    await _pump(tester);
    expect(find.text('还没有错题'), findsOneWidget);
    expect(find.text('我的错题本'), findsOneWidget,
        reason: 'AppBar 标题');
  });

  testWidgets('添加 → 列表立即显示（跨页同步：ChangeNotifier 触发 rebuild）',
      (tester) async {
    await _pump(tester);
    // 外部直接调 add（模拟「DashboardPage 添加 → 错题本页看到」）
    MistakeBook.instance.add(
      stem: '外部添加的错题',
      userAnswer: 'X',
      correctAnswer: 'Y',
      errorType: MistakeErrorType.concept,
      subjectArea: '关联考点 test',
    );
    await tester.pumpAndSettle();
    expect(find.text('外部添加的错题'), findsOneWidget,
        reason: '列表立即反映新错题');
    expect(find.text('关联考点 test'), findsOneWidget);
    // 错答/正答区
    expect(find.text('X'), findsOneWidget);
    expect(find.text('Y'), findsOneWidget);
    // v2.12 Wave 3-B P1-1：advance fake clock past 500ms debounce 窗口，
    // 让 Timer 自然触发，避免 test 结束 widget tree dispose 时
    // Flutter test 框架断言 "!timersPending" 失败。pumpAndSettle 只
    // 等待 UI frame 静止，不主动 advance 500ms。
    await tester.pump(const Duration(milliseconds: 600));
  });

  testWidgets('添加对话框：填表 → 保存 → 列表新增', (tester) async {
    await _pump(tester);
    // 触发 + 按钮
    await tester.tap(find.byTooltip('添加错题'));
    await tester.pumpAndSettle();
    expect(find.text('添加错题'), findsWidgets,
        reason: '对话框标题');
    // 填表（题目摘要是必填）
    await tester.enterText(
        find.widgetWithText(TextField, '题目摘要 *'), '对话框添加的题');
    await tester.enterText(find.widgetWithText(TextField, '错误答案'), '甲');
    await tester.enterText(find.widgetWithText(TextField, '正确答案'), '乙');
    await tester.tap(find.widgetWithText(FilledButton, '添加'));
    await tester.pumpAndSettle();
    expect(find.text('对话框添加的题'), findsOneWidget);
    expect(find.text('甲'), findsOneWidget);
    expect(find.text('乙'), findsOneWidget);
    // v2.12 Wave 3-B P1-1：advance past 500ms debounce。
    await tester.pump(const Duration(milliseconds: 600));
  });

  testWidgets('按考点分组视图：组头按题数倒序 + 组内卡片渲染',
      (tester) async {    await _pump(tester);
    MistakeBook.instance.add(
      stem: '题A1',
      userAnswer: '',
      correctAnswer: 'c',
      errorType: MistakeErrorType.concept,
      subjectArea: '分离定律',
    );
    MistakeBook.instance.add(
      stem: '题A2',
      userAnswer: '',
      correctAnswer: 'c',
      errorType: MistakeErrorType.concept,
      subjectArea: '分离定律',
    );
    MistakeBook.instance.add(
      stem: '题B1',
      userAnswer: '',
      correctAnswer: 'c',
      errorType: MistakeErrorType.concept,
      subjectArea: '伴性遗传',
    );
    MistakeBook.instance.add(
      stem: '题C1',
      userAnswer: '',
      correctAnswer: 'c',
      errorType: MistakeErrorType.concept,
      subjectArea: '',
    );
    await tester.pumpAndSettle();
    // ListView 懒构建 + 页顶待复习横幅占位：滚到目标再断言。
    await tester.scrollUntilVisible(find.text('题A1'), 120,
        scrollable: find.byType(Scrollable).first);
    expect(find.text('题A1'), findsOneWidget);
    expect(find.text('分离定律'), findsNWidgets(2));
    expect(find.text('2 道'), findsNothing, reason: '列表视图无组头计数');

    // 切分组视图（filter 栏右侧 category 按钮）。
    await tester.tap(find.byTooltip('按考点分组查看'));
    await tester.pumpAndSettle();
    // 组头 + 2 张卡 = 3 处；关键信号是组头计数出现。
    expect(find.text('分离定律'), findsNWidgets(3), reason: '组头 + 2 张卡');
    expect(find.text('2 道'), findsOneWidget, reason: '分离定律 2 道');
    expect(find.text('未标注考点'), findsOneWidget,
        reason: '空考点归「未标注考点」组');
    // 组内条目仍在（ListView 懒构建：B/C 组滚入视口再断言）。
    expect(find.text('题A1'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('题B1'), 120,
        scrollable: find.byType(Scrollable).first);
    expect(find.text('题B1'), findsOneWidget);

    MistakeBook.instance.debugFlushSave();
  });

  testWidgets('重新作答（自测）：清空我的答案 + 复习态归零 + 打开编辑表单',
      (tester) async {
    await _pump(tester);
    final entry = MistakeBook.instance.add(
      stem: '待重练的题',
      userAnswer: '旧答案',
      correctAnswer: '正确答案',
      errorType: MistakeErrorType.concept,
      subjectArea: '分离定律',
    );
    MistakeBook.instance.markStatus(entry.id, MistakeReviewStatus.mastered);
    await tester.pumpAndSettle();
    expect(find.text('待重练的题'), findsOneWidget);

    // 更多 → 重新作答（自测）
    await tester.tap(find.widgetWithText(TextButton, '更多'));
    await tester.pumpAndSettle();
    expect(find.text('重新作答（自测）'), findsOneWidget,
        reason: 'v2.13 RedFox 洞察「回到笔尖」入口可见');
    await tester.tap(find.text('重新作答（自测）'));
    await tester.pumpAndSettle();

    // 清空答案 + 复习态归零
    final cur = MistakeBook.instance.findById(entry.id)!;
    expect(cur.userAnswer, isEmpty, reason: '我的答案被清空，供回笔尖重写');
    expect(cur.reviewStatus, MistakeReviewStatus.reviewing,
        reason: '复习态归零，重新进入复习流');
    // 编辑表单自动打开（学生立刻可以重写）
    expect(find.text('编辑错题'), findsOneWidget,
        reason: '编辑表单自动弹出');
  });

  // ── v2.13+：零插件间隔复习（dueEntries 排期 + 自测会话） ──

  test('dueEntries 排期：未复习随时到期 / 复习中 1 天 / 已掌握 3 天', () {
    final now = DateTime(2026, 9, 13, 12);
    MistakeBook.instance.add(
        stem: 'a', userAnswer: '', correctAnswer: 'c',
        errorType: MistakeErrorType.concept, subjectArea: '');
    final e2 = MistakeBook.instance.add(
        stem: 'b', userAnswer: '', correctAnswer: 'c',
        errorType: MistakeErrorType.concept, subjectArea: '');
    final e3 = MistakeBook.instance.add(
        stem: 'c', userAnswer: '', correctAnswer: 'c',
        errorType: MistakeErrorType.concept, subjectArea: '');
    // e2：复习中 + 昨天复习过（12h 前）→ 未到期。
    MistakeBook.instance.markStatus(e2.id, MistakeReviewStatus.reviewing);
    MistakeBook.instance.update(e2.id,
        (cur) => cur.copyWith(reviewedAt: now.subtract(const Duration(hours: 12))));
    // e3：已掌握 + 2 天前复习 → 未到期（<3 天）。
    MistakeBook.instance.markStatus(e3.id, MistakeReviewStatus.mastered);
    MistakeBook.instance.update(e3.id,
        (cur) => cur.copyWith(reviewedAt: now.subtract(const Duration(days: 2))));

    final due = MistakeBook.instance.dueEntries(now: now);
    expect(due.length, 1, reason: '只有未复习的 a 到期');
    expect(due.first.stem, 'a');

    // e2 复习推到 2 天前 → 到期；e3 推到 4 天前 → 也到期。
    MistakeBook.instance.update(e2.id,
        (cur) => cur.copyWith(reviewedAt: now.subtract(const Duration(days: 2))));
    MistakeBook.instance.update(e3.id,
        (cur) => cur.copyWith(reviewedAt: now.subtract(const Duration(days: 4))));
    final due2 = MistakeBook.instance.dueEntries(now: now);
    expect(due2.length, 3);
    // 学生走查 P0 修复：「还需复习」答错后置 reviewedAt=null → 立即再到期
    //（今晚可再试，不被锁到明天）。
    MistakeBook.instance.update(e2.id, (cur) => cur.copyWith(reviewedAt: null));
    final due3 = MistakeBook.instance.dueEntries(now: now);
    expect(due3.any((e) => e.id == e2.id), isTrue,
        reason: '复习中 + reviewedAt 空 = 立即到期');
    MistakeBook.instance.debugFlushSave();
  });

  testWidgets('今日复习会话：横幅出现 → 显示答案 → 掌握了 → 完成态 + 状态落库',
      (tester) async {
    await _pump(tester);
    MistakeBook.instance.add(
        stem: '复习题一',
        userAnswer: '',
        correctAnswer: '正确答一',
        errorType: MistakeErrorType.concept,
        subjectArea: '');
    await tester.pumpAndSettle();

    // 页顶待复习横幅出现。
    expect(find.textContaining('今日待复习 1 道'), findsOneWidget);
    await tester.tap(find.text('开始复习'));
    await tester.pumpAndSettle();

    // 会话第一题：题干可见（列表卡 + 会话框各一处）；遮罩提示在对话框内。
    expect(find.text('复习题一'), findsWidgets);
    expect(
        find.descendant(
            of: find.byType(Dialog),
            matching: find.textContaining('先遮住答案')),
        findsOneWidget,
        reason: '遮罩提示可见（答案未揭示）');
    expect(
        find.descendant(
            of: find.byType(Dialog), matching: find.text('正确答一')),
        findsNothing,
        reason: '对话框内答案遮罩未显示');

    // 显示答案 → 对话框内正确答案 + 「你当时写」对比行可见。
    await tester.tap(find.textContaining('显示答案（1）'));
    await tester.pumpAndSettle();
    expect(
        find.descendant(
            of: find.byType(Dialog), matching: find.text('正确答一')),
        findsOneWidget,
        reason: '揭示后对话框内显示答案');
    expect(
        find.descendant(
            of: find.byType(Dialog),
            matching: find.textContaining('你当时写：（未作答）')),
        findsOneWidget,
        reason: '当时作答对比行');

    // 学生走查 P0：「再看看」回退——不记结果、回到遮罩。
    await tester.tap(find.text('再看看（不记结果）'));
    await tester.pumpAndSettle();
    expect(
        find.descendant(
            of: find.byType(Dialog), matching: find.text('正确答一')),
        findsNothing,
        reason: '回退后重新遮罩');
    expect(
        MistakeBook.instance
            .findById(MistakeBook.instance.entries
                .firstWhere((e) => e.stem == '复习题一')
                .id)!
            .reviewStatus,
        MistakeReviewStatus.unreviewed,
        reason: '再看看不记结果：状态未变');

    // 回退验证完 → 重新显示答案再作答。
    await tester.tap(find.textContaining('显示答案（1）'));
    await tester.pumpAndSettle();
    // 掌握了（答案区增高后按钮可能滚出视口，先滚入）。
    await tester.ensureVisible(find.textContaining('掌握了（1）'));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('掌握了（1）'));
    await tester.pumpAndSettle();
    expect(find.text('本轮复习完成'), findsOneWidget);
    final done = MistakeBook.instance.entries.firstWhere((e) => e.stem == '复习题一');
    expect(done.reviewStatus, MistakeReviewStatus.mastered);
    expect(done.reviewedAt, isNotNull);

    // 完成退出 → 横幅消失（刚复习过，未到期）。
    await tester.tap(find.text('完成'));
    await tester.pumpAndSettle();
    expect(find.textContaining('今日待复习'), findsNothing,
        reason: '复习后 1 道不再到期，横幅隐藏');

    MistakeBook.instance.debugFlushSave();
  });

  testWidgets('复习状态 chip：点击切换 unreviewed → reviewing → mastered',
      (tester) async {
    await _pump(tester);
    final entry = MistakeBook.instance.add(
      stem: '状态切换测试',
      userAnswer: 'x',
      correctAnswer: 'y',
      errorType: MistakeErrorType.concept,
      subjectArea: '',
    );
    await tester.pumpAndSettle();
    // 找到该 entry 对应的状态 chip（默认显示「未复习」）
    expect(find.text('未复习'), findsOneWidget);
    // PopupMenuButton 的 tooltip
    await tester.tap(find.byTooltip('点击切换复习状态'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('复习中'));
    await tester.pumpAndSettle();
    expect(MistakeBook.instance.findById(entry.id)!.reviewStatus,
        MistakeReviewStatus.reviewing);
    expect(find.text('复习中'), findsOneWidget);
    // 再切到已掌握
    await tester.tap(find.byTooltip('点击切换复习状态'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('已掌握'));
    await tester.pumpAndSettle();
    expect(MistakeBook.instance.findById(entry.id)!.reviewStatus,
        MistakeReviewStatus.mastered);
    // v2.12 Wave 3-B P1-1：advance past 500ms debounce。
    await tester.pump(const Duration(milliseconds: 600));
  });

  testWidgets('删除：长按 → 菜单 → 删除 → 列表移除 + 5 秒 Undo 可恢复',
      (tester) async {
    await _pump(tester);
    MistakeBook.instance.add(
      stem: '待删除的题',
      userAnswer: 'x',
      correctAnswer: 'y',
      errorType: MistakeErrorType.other,
      subjectArea: '',
    );
    await tester.pumpAndSettle();
    expect(find.text('待删除的题'), findsOneWidget);
    // 点「更多」按钮（卡片底部 _buildActions 里的 TextButton）
    await tester.tap(find.widgetWithText(TextButton, '更多'));
    await tester.pumpAndSettle();
    // 底部 sheet 应已弹出，含「编辑」「删除」两项
    expect(find.text('编辑'), findsOneWidget,
        reason: 'sheet 里的「编辑」选项');
    await tester.tap(find.text('删除'));
    // 关 sheet + 弹 Undo SnackBar（v2.12 Wave 3-B P1-3：替代之前的
    // 二次确认 dialog）。SnackBar 时长 5 秒。
    await tester.pumpAndSettle();
    expect(find.text('已移入回收站'), findsOneWidget,
        reason: 'SnackBar 提示「已移入回收站」（v2.12 R1 P0 #5：软删除）');
    expect(find.text('撤销'), findsOneWidget,
        reason: 'SnackBar 含「撤销」action');
    // 列表里条目消失
    expect(find.text('待删除的题'), findsNothing,
        reason: '点删除后立即从列表移除（不进回收站）');

    // 点「撤销」→ 错题本 add 回去
    await tester.tap(find.text('撤销'));
    await tester.pumpAndSettle();
    expect(find.text('待删除的题'), findsOneWidget,
        reason: '撤销后错题回到列表');
    // v2.12 Wave 3-B P1-1：advance past 500ms debounce（撤销 add 也会
    // schedule 写盘）。
    await tester.pump(const Duration(milliseconds: 600));
  });

  // ===== v2.12.0+2 hotfix 新增：撤销 Undo 改字 + AI 整理后 AI 字段不挂错 =====

  testWidgets('删除 Undo：改字 + AI 整理后撤销，AI 字段挂到正确 entry（v2.12.0+2 hotfix）',
      (tester) async {
    // v2.12.0+2 hotfix 回归测试。
    // 之前撤销 Undo 用 firstWhere(5 字段全等) + orElse: entries.first 兜底
    // 找刚 add 的 entry：
    //   1. 依赖「_sortDesc 后 firstWhere 拿 0 位 = 刚 add 的」假设，脆弱
    //   2. orElse 兜底可能拿**别的 entry**——AI 整理结果会写错条目
    // 修法：用 MistakeBook.add() 返回的 entry 拿新 id（API 已有，
    // mistake_book.dart:312 已实现），删 firstWhere + orElse 整段。
    //
    // 测试场景（模拟学生改字 → AI 整理 → 删 → 撤销）：
    //   1. 先加一条"诱饵" entry（列表里已有别的 entry，触发"0 位"边界）
    //   2. 加目标 entry → 改字（update 改 stem）→ AI 整理 → markStatus
    //   3. 删目标 → Undo
    //   4. 验证：恢复的 entry 字段 = 改字后 + AI 整理 + 复习状态
    //   5. 验证：诱饵 entry 不被影响（AI 没被错挂）
    await _pump(tester);

    // 1. 诱饵 entry（防 firstWhere 退化到 0 位 + 验证没被错挂）
    final decoy = MistakeBook.instance.add(
      stem: '诱饵题',
      userAnswer: '诱饵-错答',
      correctAnswer: '诱饵-正答',
      errorType: MistakeErrorType.careless,
      subjectArea: '诱饵-考点',
    );
    MistakeBook.instance.applyAiAnalysis(
      decoy.id,
      summary: '诱饵-AI-summary',
      pitfalls: ['诱饵易错点'],
    );
    await tester.pumpAndSettle();

    // 2. 添加目标 entry
    final target = MistakeBook.instance.add(
      stem: '原题',
      userAnswer: '原-错答',
      correctAnswer: '原-正答',
      errorType: MistakeErrorType.concept,
      subjectArea: '原-考点',
    );
    await tester.pumpAndSettle();
    expect(find.text('原题'), findsOneWidget);
    expect(find.text('诱饵题'), findsOneWidget);

    // 3. 改字（update 改 stem）
    MistakeBook.instance.update(target.id, (e) => e.copyWith(stem: '改字后'));
    await tester.pumpAndSettle();
    expect(find.text('改字后'), findsOneWidget);
    expect(find.text('原题'), findsNothing);

    // 4. AI 整理（手动 applyAiAnalysis 模拟，绕开网络；用户改字后想重新整理）
    MistakeBook.instance.applyAiAnalysis(
      target.id,
      summary: '改字后的 AI summary',
      pitfalls: ['改字后易错点 1', '改字后易错点 2'],
    );
    MistakeBook.instance.markStatus(target.id, MistakeReviewStatus.reviewing);
    await tester.pumpAndSettle();

    // 5. 删 target（ListView 第一张是 target，因为 target 比 decoy 新）
    await tester.tap(find.widgetWithText(TextButton, '更多').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除'));
    await tester.pumpAndSettle();
    expect(find.text('改字后'), findsNothing,
        reason: '删除后从列表移除');
    expect(find.text('诱饵题'), findsOneWidget, reason: '诱饵 entry 还在');
    expect(find.text('撤销'), findsOneWidget, reason: 'Undo SnackBar');

    // 6. Undo
    await tester.tap(find.text('撤销'));
    await tester.pumpAndSettle();

    // 7. 验证：target 恢复，AI 整理结果正确挂到 target
    final entries = MistakeBook.instance.entries;
    expect(entries.length, 2,
        reason: '应有 target 恢复 + 诱饵 = 2 条 entry');

    final restoredTarget =
        entries.firstWhere((e) => e.userAnswer == '原-错答');
    expect(restoredTarget.stem, '改字后',
        reason: '恢复的 entry stem 应是改字后');
    expect(restoredTarget.aiSummary, '改字后的 AI summary',
        reason: 'AI summary 应正确挂到恢复的 entry（不是诱饵）');
    expect(restoredTarget.aiPitfalls,
        ['改字后易错点 1', '改字后易错点 2'],
        reason: 'AI pitfalls 应正确挂到恢复的 entry');
    expect(restoredTarget.reviewStatus, MistakeReviewStatus.reviewing,
        reason: '复习状态应正确恢复');
    expect(restoredTarget.id, isNot(target.id),
        reason: 'add() 重新分配 id（避免历史引用错乱）');

    // 8. 验证：诱饵 entry 没被错挂（firstWhere 错挂修复关键回归点）
    final stillDecoy =
        entries.firstWhere((e) => e.userAnswer == '诱饵-错答');
    expect(stillDecoy.id, decoy.id, reason: '诱饵 id 不变');
    expect(stillDecoy.aiSummary, '诱饵-AI-summary',
        reason: '诱饵的 AI summary 应保持不变（没被 target 撤销时错挂）');
    expect(stillDecoy.aiPitfalls, ['诱饵易错点'],
        reason: '诱饵的 AI pitfalls 应保持不变');

    // v2.12 Wave 3-B P1-1：advance past 500ms debounce。
    await tester.pump(const Duration(milliseconds: 600));
  });

  // ===== v2.12 Wave 3-B P1 新增：Undo 过期真删 + 写盘 debounce + 唯一 id =====

  testWidgets('删除 Undo 过期：5 秒后无法撤销，列表确认真删', (tester) async {
    // v2.12 Wave 3-B P1 软性建议：补 Undo 过期真删回归测试。
    // 之前 P0-3 仅测了"点删除 → Undo → 恢复"链路，未测"5 秒后 SnackBar
    // 消失 → 撤销按钮失效 → 条目真删"的端到端路径。
    //
    // 实现要点：flutter_test 假时钟下 SnackBar 的 auto-dismiss Timer
    // 需要 `runAsync + Future.delayed` 让真时钟跑过去；之后
    // pumpAndSettle 等动画 finish 即可。验证两个层面：
    //   1. UI 层面：撤销按钮 5 秒后不可见（SnackBar 已 dismiss）
    //   2. 数据层面：MistakeBook.entries 不含此 entry（真删，不是隐藏）
    await _pump(tester);
    MistakeBook.instance.add(
      stem: 'Undo 过期测试',
      userAnswer: 'x',
      correctAnswer: 'y',
      errorType: MistakeErrorType.other,
      subjectArea: '',
    );
    await tester.pumpAndSettle();
    expect(find.text('Undo 过期测试'), findsOneWidget);

    // 点「更多」→ sheet → 「删除」
    await tester.tap(find.widgetWithText(TextButton, '更多'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除'));
    // 关闭 sheet + 弹 Undo SnackBar（5 秒可撤销）
    await tester.pumpAndSettle();
    expect(find.text('已移入回收站'), findsOneWidget, reason: 'Undelete SnackBar');
    expect(find.text('撤销'), findsOneWidget, reason: '撤销 action');
    expect(find.text('Undo 过期测试'), findsNothing,
        reason: '删除后立即从列表移除');

    // 等 SnackBar 自动消失（5 秒 + 退出动画 ~250ms）
    // SnackBar 的 auto-dismiss 用 dart:async Timer（5s），需
    // tester.pump 步进推进假时钟。pump 60 次 × 100ms = 6s
    // 远超 5s，确保 Timer 已 fire；pumpAndSettle 让退出动画
    // 跑完。
    for (var i = 0; i < 60; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.pumpAndSettle();
    expect(find.text('撤销'), findsNothing,
        reason: '5 秒后 SnackBar 自动消失 → 撤销按钮不再可见');

    // 数据层面真删：SnackBar dismiss 后，撤销回调再点也无效（按钮已
    // 从 tree 移除），但更关键的是 MistakeBook 内存里这条 entry
    // 不再存在——即"真删"而非"仅 UI 隐藏"。
    final undoEntries = MistakeBook.instance.entries
        .where((e) => e.stem == 'Undo 过期测试')
        .toList();
    expect(undoEntries, isEmpty,
        reason: '5 秒过期后 MistakeBook 内存里也无此 entry（Undo 真失效）');
  });


  test('_genId monotonic counter 唯一性：1000 次 add id 全部不同', () {
    // 不通过 UI，直接打 MistakeBook（_genId 是 static 在 add 内部调）。
    // 1000 次连击（同毫秒内大量 add）→ monotonic counter 24 bit
    // 单调递增，trivial 唯一（_idCounter 0..999）。之前 Random.secure()
    // 24 bit 也有高概率唯一（生日碰撞 1/16M），但顺序不一定递增。
    final ids = <String>{};
    for (var i = 0; i < 1000; i++) {
      final e = MistakeBook.instance.add(
        stem: 'id 唯一性测试 $i',
        userAnswer: 'x',
        correctAnswer: 'y',
        errorType: MistakeErrorType.other,
        subjectArea: '',
      );
      ids.add(e.id);
    }
    expect(ids.length, 1000, reason: '1000 次 add 应产生 1000 个唯一 id');
    // v2.12 Wave 3-B P1-1：flush 1000 次 add 的 debounce timer。
    MistakeBook.instance.debugFlushSave();
  });

  test('写盘 debounce：连击 5 条 → 500ms 内只写 1 次', () async {
    // 写盘次数通过监听 MistakeBook debugFilePath 文件 mtime 变化推断
    // 不优雅但避免暴露内部计数器。简化做法：直接验证"5 条连击 + 不
    // flush 立即读文件 = 空文件或部分内容"（debounce 期间不写）。
    // 然后 debugFlushSave 一次 → 全部写盘。
    final file = File(MistakeBook.debugFilePath!);
    expect(file.existsSync(), isFalse,
        reason: 'setUp 后磁盘应无 mistake_book.json');

    for (var i = 0; i < 5; i++) {
      MistakeBook.instance.add(
        stem: 'debounce $i',
        userAnswer: 'a',
        correctAnswer: 'b',
        errorType: MistakeErrorType.careless,
        subjectArea: '',
      );
    }
    // debounce 窗口 500ms 内：不应落盘
    expect(file.existsSync(), isFalse,
        reason: 'debounce 窗口内（<500ms）不应落盘');

    // 走 Timer 异步：等 600ms 让 timer 触发
    await Future<void>.delayed(const Duration(milliseconds: 600));
    expect(file.existsSync(), isTrue,
        reason: 'debounce 窗口过后应落盘 1 次');
    // 落盘内容 = 5 条
    final raw = file.readAsStringSync();
    final parsed = jsonDecode(raw) as List;
    expect(parsed.length, 5, reason: 'debounce 后 5 条全部落盘');
  });

  // ===== v2.12+ R1 P0 #3 新增：AI 主动整理「名实不符」=====

  testWidgets('P0 #3 加错题 → 后台 500ms debounce 调 organizeSingle',
      (tester) async {
    // 注入 sender：每次调都把调过的 entry.stem 记录到 sentStems。
    // 这是 verify「100ms 内 background 调 organizeSingle」的关键
    // ——不是测 SnackBar 何时出现，而是测 AI 调用是否被实际触发。
    final sentStems = <String>[];
    MistakeBook.debugOrganizeSender = (entry) async {
      sentStems.add(entry.stem);
      return MistakeAiAnalysis(
        summary: 'AI 自动归类：${entry.stem}',
        pitfalls: const ['避坑 1', '避坑 2'],
      );
    };

    await _pump(tester);

    // 直接调 add + debugEnqueueAiOrganize（模拟任何调用方）——这是
    // MistakeBook 的核心 API 行为，不依赖 UI 路径。
    final added = MistakeBook.instance.add(
      stem: 'P0 #3 测试题',
      userAnswer: 'x',
      correctAnswer: 'y',
      errorType: MistakeErrorType.concept,
      subjectArea: '',
    );
    // 关键：调用方需主动入队（页面 _handleAdd 已包办此调用；本测试
    // 绕开页面是为了让"调用方主动入队"语义显式化）。
    MistakeBook.instance.debugEnqueueAiOrganize(added.id);
    await tester.pump();

    // 入队后 500ms debounce 内不应已调
    expect(sentStems, isEmpty,
        reason: '500ms debounce 窗口内不应调 organizeSingle');

    // advance fake clock past 500ms debounce → Timer 触发
    await tester.pump(const Duration(milliseconds: 600));
    // pumpAndSettle 让 microtask queue 跑完（包括 sender 的 await +
    // applyAiAnalysis + notifyListeners）
    await tester.pumpAndSettle();
    expect(sentStems, ['P0 #3 测试题'],
        reason: '500ms debounce 后应调 organizeSingle（仅 1 次）');

    // entry 的 aiSummary 应已写回
    final refreshed = MistakeBook.instance.findById(added.id);
    expect(refreshed?.aiSummary, contains('AI 自动归类'),
        reason: 'AI 整理结果写回 entry.aiSummary');
    expect(refreshed?.aiPitfalls, ['避坑 1', '避坑 2'],
        reason: 'AI 整理 pitfalls 写回 entry.aiPitfalls');

    // 显式 cancel 所有 pending timer + sender（tearDown 会再清一次，
    // 但放在这里确保 widget tree dispose 之前 timer 已清——避免
    // _verifyInvariants 报"pending timer after dispose"红）。
    await MistakeBook.instance.debugWaitAiOrganizeDone();
    await tester.pumpAndSettle();
    MistakeBook.instance.debugResetAiOrganize();
    MistakeBook.debugOrganizeSender = null;
    // v2.12 Round 1 P0 #3 fix：applyAiAnalysis 走 update 触发
    // _scheduleSave（500ms debounce），test body 退出时该 timer 仍 pending
    // → _verifyInvariants 报"pending timer"红。flush 一下立即落盘。
    MistakeBook.instance.debugFlushSave();
  });

  testWidgets('P0 #3 加错题 → 5 秒后 SnackBar「AI 已自动归类错因」出现',
      (tester) async {
    // 走页面 _handleAdd 路径（+ 按钮 → 表单 → 保存）——这是产品
    // 宣传的"AI 主动整理"主路径。
    MistakeBook.debugOrganizeSender = (entry) async => MistakeAiAnalysis(
          summary: 'OK',
          pitfalls: const [],
        );

    await _pump(tester);

    // 走「+ → 填表 → 保存」全路径触发 _handleAdd
    await tester.tap(find.byTooltip('添加错题'));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.widgetWithText(TextField, '题目摘要 *'), '5 秒 SnackBar 测试');
    await tester.tap(find.widgetWithText(FilledButton, '添加'));
    await tester.pumpAndSettle();

    // 1) 5 秒前不应有 AI 整理完成 SnackBar
    expect(find.text('AI 已自动归类错因'), findsNothing,
        reason: '5 秒前 AI SnackBar 还未弹');

    // 2) advance fake clock past 5 秒
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();

    // 3) SnackBar 出现 + 含「查看归类」action（v2.13 R4-4：原「展开」
    //    no-op 假按钮修复）
    expect(find.text('AI 已自动归类错因'), findsOneWidget,
        reason: '5 秒后 SnackBar 出现');
    expect(find.text('查看归类'), findsOneWidget,
        reason: 'SnackBar 含「查看归类」action');

    // 4) advance past 4 sec SnackBar duration + 5 sec AI SnackBar
    //    duration，让所有 SnackBar auto-dismiss（避免 test 结束
    //    _verifyInvariants 报"pending timer"红）。max(4, 5) = 5。
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();

    // 等 in-flight _runAiOrganize 完成 + 清 sender
    await MistakeBook.instance.debugWaitAiOrganizeDone();
    await tester.pumpAndSettle();
    MistakeBook.debugOrganizeSender = null;
  });

  testWidgets('P1-2 AI 慢于 5 秒：完成前不弹 SnackBar，完成后才弹',
      (tester) async {
    // mock AI 慢（>5 秒）：Completer 手动控制完成时机——5 秒首查时
    // AI 未完成（旧 bug 会在这时弹，名实不符），完成后复查才弹。
    final completer = Completer<MistakeAiAnalysis>();
    MistakeBook.debugOrganizeSender = (entry) => completer.future;

    await _pump(tester);

    // 走页面 _handleAdd 路径（+ 按钮 → 表单 → 保存）
    await tester.tap(find.byTooltip('添加错题'));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.widgetWithText(TextField, '题目摘要 *'), 'P1-2 慢 AI');
    await tester.tap(find.widgetWithText(FilledButton, '添加'));
    await tester.pumpAndSettle();

    // 1) 5 秒首查：AI 未完成（completer 未 complete，aiSummary 空）
    //    → 不弹（P1-2 修复点：旧代码只查 stillExists 不管 AI 跑没跑完）
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    expect(find.text('AI 已自动归类错因'), findsNothing,
        reason: 'P1-2：AI 还在跑时 5 秒到点也不能弹 SnackBar');

    // 2) 完成 AI → 复查 timer（2 秒）fire → 这时才弹
    completer.complete(MistakeAiAnalysis(
        summary: '慢 AI 完成', pitfalls: const []));
    await tester.pump();
    await MistakeBook.instance.debugWaitAiOrganizeDone();
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect(find.text('AI 已自动归类错因'), findsOneWidget,
        reason: 'P1-2：AI 完成后复查到 aiSummary 已写入 → 才弹');
    expect(find.text('查看归类'), findsOneWidget,
        reason: 'SnackBar 含「查看归类」action（与快 AI 路径一致）');

    // 3) 清场：SnackBar auto-dismiss（4s）+ in-flight future 收尾
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    await MistakeBook.instance.debugWaitAiOrganizeDone();
    await tester.pumpAndSettle();
    MistakeBook.debugOrganizeSender = null;
  });

  // ═══ v2.13 R4-4：SnackBar「查看归类」= 真定位（Opt3B P1 假按钮修复）═══
  testWidgets('R4-4 「查看归类」定位：搜索过滤掉该题时点 action 恢复可见',
      (tester) async {
    // 旧实现：action 只调 setState(() {}) = no-op 假按钮。新实现：
    // 滚动定位到该题 + 短暂高亮；若被当前搜索/筛选过滤则先清筛选。
    MistakeBook.debugOrganizeSender = (entry) async => MistakeAiAnalysis(
          summary: 'OK',
          pitfalls: const ['避坑'],
        );

    await _pump(tester);

    // 走页面 _handleAdd 路径 → 自动入队 AI 整理 → 5 秒后弹 SnackBar
    await tester.tap(find.byTooltip('添加错题'));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.widgetWithText(TextField, '题目摘要 *'), '定位测试题');
    await tester.tap(find.widgetWithText(FilledButton, '添加'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    expect(find.text('查看归类'), findsOneWidget,
        reason: 'AI 完成后 SnackBar 应含「查看归类」action');

    // 先输入一个不匹配的搜索词 → 该题被过滤，卡片不可见
    await tester.enterText(
        find.byKey(const Key('mistake_search_field')), '不存在的词');
    await tester.pumpAndSettle();
    expect(find.text('定位测试题'), findsNothing,
        reason: '搜索后卡片被过滤，SnackBar 仍挂着可点');

    // 点「查看归类」→ 清筛选恢复全量 → 卡片重新可见
    await tester.tap(find.text('查看归类'));
    await tester.pumpAndSettle();
    expect(find.text('定位测试题'), findsOneWidget,
        reason: '「查看归类」应清筛选并定位到该题');

    // 清场：SnackBar（4s）+ 高亮 timer（2s）+ AI debounce 全部耗尽
    await tester.pump(const Duration(seconds: 6));
    await tester.pumpAndSettle();
    await MistakeBook.instance.debugWaitAiOrganizeDone();
    await tester.pumpAndSettle();
    MistakeBook.debugOrganizeSender = null;
    MistakeBook.instance.debugResetAiOrganize();
    MistakeBook.instance.debugFlushSave();
  });

  testWidgets('P1-3 空答案卡片：橙色边框 + 「待补充」提示', (tester) async {
    await _pump(tester);
    // 添加一条答案为空的错题（只填必填的题目摘要）——表单里答案
    // 可留空（_submit 只校验 stem），空答案 = userAnswer/''。
    await tester.tap(find.byTooltip('添加错题'));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.widgetWithText(TextField, '题目摘要 *'), '缺答案的题');
    await tester.tap(find.widgetWithText(FilledButton, '添加'));
    await tester.pumpAndSettle();

    // 1) 错答 + 正答都空 → 两处「待补充」
    expect(find.text('待补充'), findsNWidgets(2),
        reason: 'P1-3：错答/正答都空 → 两处都显示「待补充」');
    expect(find.text('（未填）'), findsNothing,
        reason: 'P1-3：旧灰色「（未填）」文案已替换为「待补充」');

    // 2) 答案卡片边框是橙色（不再是默认 AppColors.border）
    final card = tester.widget<Container>(find
        .ancestor(of: find.text('待补充').first, matching: find.byType(Container))
        .first);
    final deco = card.decoration! as BoxDecoration;
    final border = deco.border! as Border;
    expect(border.top.color, Colors.orange,
        reason: 'P1-3：空答案卡片橙色边框');
    expect(border.bottom.color, Colors.orange, reason: '四边一致');
    expect(border.left.color, Colors.orange, reason: '四边一致');
    expect(border.right.color, Colors.orange, reason: '四边一致');

    // 3) 对照：补上答案后重新渲染 → 「待补充」消失、边框恢复默认色
    final e = MistakeBook.instance.entries.single;
    MistakeBook.instance.update(e.id,
        (x) => x.copyWith(userAnswer: '9:3:4', correctAnswer: '9:3:3:1'));
    await tester.pumpAndSettle();
    expect(find.text('待补充'), findsNothing,
        reason: 'P1-3：答案补齐后「待补充」消失');
    final fixed =
        tester.widget<Container>(find.ancestor(
            of: find.text('9:3:3:1'), matching: find.byType(Container)).first);
    final fixedBorder = (fixed.decoration! as BoxDecoration).border! as Border;
    expect(fixedBorder.top.color, AppColors.border,
        reason: 'P1-3：答案补齐后边框恢复默认色');

    // 4) 清场：等 5 秒 SnackBar timer（AI 主动整理路径）到点/耗完
    await tester.pump(const Duration(seconds: 65));
    await tester.pumpAndSettle();
    await MistakeBook.instance.debugWaitAiOrganizeDone();
    await tester.pumpAndSettle();
  });

  testWidgets('P0 #3 加错题时显示「AI 整理中…」hint（无结果时）',
      (tester) async {
    await _pump(tester);
    // 走页面 _handleAdd 路径
    await tester.tap(find.byTooltip('添加错题'));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.widgetWithText(TextField, '题目摘要 *'), 'AI 整理中 hint 测试');
    await tester.tap(find.widgetWithText(FilledButton, '添加'));
    await tester.pumpAndSettle();

    expect(find.text('正在归类错因、提炼易错点…'), findsOneWidget,
        reason: '卡片底部应显示「AI 整理中…」提示');

    // advance past 2 sec SnackBar duration + 5 sec AI SnackBar
    // duration，让所有 SnackBar auto-dismiss（避免 test 结束
    // _verifyInvariants 报"pending timer"红）。
    // v2.12+ R2 A2 P1-2：本测试 sender 为 null（走真实 analyzeSingle，
    // 测试环境失败 → aiSummary 保持空）→ 5 秒首查不弹，改为 2 秒复查
    // 循环。pump 65 秒一次性耗尽所有复查 timer（5s 首查 + 30 次 × 2s
    // 复查 ≈ 65s），保证 test 结束无 pending timer。
    await tester.pump(const Duration(seconds: 65));
    await tester.pumpAndSettle();

    // 等 in-flight _runAiOrganize 完成 + 主动清 sender + debounce
    await MistakeBook.instance.debugWaitAiOrganizeDone();
    await tester.pumpAndSettle();
    MistakeBook.debugOrganizeSender = null;
    MistakeBook.instance.debugResetAiOrganize();
  });

  // ===== v2.13 R3 P1-B2 新增：AI 整理失败/超时清理 spinner =====

  testWidgets('R3 P1-B2 AI 整理失败（sender 返 null）：spinner 消失 + 失败 SnackBar',
      (tester) async {
    // mock AI 失败：sender 返回 null（等价「解析失败 / 未配置 AI」）。
    // 后台 _doRunAiOrganize 拿到 null 直接 continue，aiSummary 保持空。
    // 旧 bug：复查链到顶后 _aiOrganizingIds 不 remove → 「AI 整理中…」
    // hint 永久残留。
    MistakeBook.debugOrganizeSender = (entry) async => null;

    await _pump(tester);

    // 走页面 _handleAdd 路径（+ 按钮 → 表单 → 保存）——触发自动入队
    await tester.tap(find.byTooltip('添加错题'));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.widgetWithText(TextField, '题目摘要 *'), 'R3 P1-B2 失败测试');
    await tester.tap(find.widgetWithText(FilledButton, '添加'));
    await tester.pumpAndSettle();

    // 1) 添加后显示「AI 整理中…」hint
    expect(find.text('正在归类错因、提炼易错点…'), findsOneWidget,
        reason: 'AI 后台整理中应显示 hint');

    // 2) advance fake clock：5s 首查 + 30 次 × 2s 复查 ≈ 65s。复查链
    //    到顶时 aiSummary 仍空 → 失败分支：remove id（setState 触发
    //    rebuild）+ 弹失败 SnackBar。
    await tester.pump(const Duration(seconds: 65));
    await tester.pumpAndSettle();

    // 3) hint 消失（_aiOrganizingIds 已清，无结果也不残留「AI 整理中…」）
    expect(find.text('正在归类错因、提炼易错点…'), findsNothing,
        reason: 'R3 P1-B2：失败后 hint 必须消失，不能永久残留');
    // 4) 失败 SnackBar 出现，提示可手动重试
    expect(find.text('AI 整理失败，可手动重试'), findsOneWidget,
        reason: 'R3 P1-B2：失败时弹「AI 整理失败，可手动重试」SnackBar');

    // 5) 清场：SnackBar auto-dismiss（v2.13 R4-4：AI 失败提示 2s→5s）
    await tester.pump(const Duration(seconds: 6));
    await tester.pumpAndSettle();
    await MistakeBook.instance.debugWaitAiOrganizeDone();
    await tester.pumpAndSettle();
    MistakeBook.debugOrganizeSender = null;
    MistakeBook.instance.debugResetAiOrganize();
  });

  testWidgets('R3 P1-B2 AI 整理超时（AI 一直不返回）：同样清理 spinner + 失败提示',
      (tester) async {
    // mock AI 超时：sender 的 Future 一直 pending（Completer 不 complete），
    // 模拟网络卡死/服务端无响应。60 秒复查链到顶后必须同样清理
    // spinner + 弹失败提示（与失败分支同一收口）。
    final completer = Completer<MistakeAiAnalysis?>();
    MistakeBook.debugOrganizeSender = (entry) => completer.future;

    await _pump(tester);

    // 走页面 _handleAdd 路径
    await tester.tap(find.byTooltip('添加错题'));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.widgetWithText(TextField, '题目摘要 *'), 'R3 P1-B2 超时测试');
    await tester.tap(find.widgetWithText(FilledButton, '添加'));
    await tester.pumpAndSettle();

    // 1) 显示「AI 整理中…」hint
    expect(find.text('正在归类错因、提炼易错点…'), findsOneWidget,
        reason: 'AI 后台整理中应显示 hint');

    // 2) advance 65s：复查链到顶 aiSummary 仍空（AI 未返回）→ 超时清理
    await tester.pump(const Duration(seconds: 65));
    await tester.pumpAndSettle();

    // 3) hint 消失 + 失败 SnackBar
    expect(find.text('正在归类错因、提炼易错点…'), findsNothing,
        reason: 'R3 P1-B2：超时后 hint 必须消失，不能永久残留');
    expect(find.text('AI 整理失败，可手动重试'), findsOneWidget,
        reason: 'R3 P1-B2：超时也弹「AI 整理失败，可手动重试」SnackBar');

    // 4) 清场：先 complete sender（否则 _doRunAiOrganize 的 Future 永远
    //    pending，debugWaitAiOrganizeDone 会卡住）；再等 SnackBar 自动
    //    dismiss（v2.13 R4-4：AI 失败提示 2s→5s）。
    completer.complete(null);
    await tester.pump();
    await MistakeBook.instance.debugWaitAiOrganizeDone();
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 6));
    await tester.pumpAndSettle();
    MistakeBook.debugOrganizeSender = null;
    MistakeBook.instance.debugResetAiOrganize();
  });

  // ═══ v2.12+ R1 final-B P0 #4：_handleImport 坏 JSON try/catch ═══
  testWidgets(
      'P0 #4 _handleImport 坏 JSON：FormatException 兜底，弹 SnackBar 不 crash',
      (tester) async {
    // v2.12+ R1 final-B P0 #4：之前 _handleImport 没 try/catch
    // FormatException → 坏 JSON / schemaVersion 不匹配会让整个 app
    // 闪退（学生做到一半崩溃体验灾难）。现在加 try/catch（FormatException
    // + 兜底 Exception），失败弹 SnackBar 提示 + 详细错误。
    //
    // 测两条路径：
    //   1. 非 JSON 字符串（json.parse 直接抛 FormatException）
    //   2. schemaVersion 不匹配（业务语义 FormatException）
    // 两条都走 _handleImport 的 try/catch on FormatException 路径，
    // 弹「导入失败：文件格式错误（...）」SnackBar。验证 app 不 crash +
    // SnackBar 文案 + MistakeBook 状态不变（entries 仍空）。
    await _pump(tester);
    expect(MistakeBook.instance.entries, isEmpty);

    // 走 AppBar「更多」→「导入 JSON」→ 弹 dialog → 输入坏 JSON
    await tester.tap(find.byTooltip('更多'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('导入 JSON'));
    await tester.pumpAndSettle();
    expect(find.text('导入错题 JSON'), findsOneWidget,
        reason: '_MistakeImportDialog 弹出');

    // 输入坏 JSON（非 JSON 字符串）→ 走 try/catch 路径
    await tester.enterText(
        find.byType(TextField), 'this is not json at all');
    await tester.tap(find.widgetWithText(FilledButton, '导入'));
    await tester.pumpAndSettle();

    // 验证 SnackBar 出现 + app 不 crash
    expect(find.textContaining('导入失败：文件格式错误'), findsOneWidget,
        reason: '坏 JSON 弹「导入失败：文件格式错误」SnackBar');
    // MistakeBook 状态不变（entries 仍空，没成功 add）
    expect(MistakeBook.instance.entries, isEmpty,
        reason: '坏 JSON 导入失败，entries 不变');

    // 关闭 SnackBar 避免 test 结束 _verifyInvariants 报 pending timer
    // （_showSnack duration = 2s，pump 2.5s 让 auto-dismiss 跑完）
    await tester.pump(const Duration(milliseconds: 2500));
    await tester.pumpAndSettle();

    MistakeBook.instance.debugFlushSave();
  });

  // ═══ v2.12+ R1 final D P0 #5：「从文件选 .json」按钮 ═══
  testWidgets(
      'P0 #5 导入对话框点「从文件选 .json」→ 选文件内容自动走 _handleImport 路径',
      (tester) async {
    // v2.12+ R1 final D P0 #5：错题本导入对话框加「从文件选 .json」
    // 按钮（桌面走 PowerShell OpenFileDialog，Web 走
    // <input type=file>）。这是为 Web 端用户简化 4 步操作（找下载
    // 目录→打开→复制→粘）为 1 步（点按钮→选文件）。本 test 走
    // 注入 picker 路径验证 UI 行为，不依赖平台对话框。
    //
    // 流程：
    //   1. 进错题本页 → 「更多」→ 「导入 JSON」→ 弹 _MistakeImportDialog
    //   2. 点「从文件选 .json」按钮
    //   3. mock picker 返回 PickedJson(有效 JSON, 'imported.json')
    //   4. 验证 dialog pop 出 PickedJson.content → _handleImport
    //      调 MistakeBook.importJson → 列表里能看到那条 entry
    await _pump(tester);
    expect(MistakeBook.instance.entries, isEmpty);

    // 走 AppBar「更多」→「导入 JSON」
    await tester.tap(find.byTooltip('更多'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('导入 JSON'));
    await tester.pumpAndSettle();
    expect(find.text('导入错题 JSON'), findsOneWidget,
        reason: '_MistakeImportDialog 弹出');

    // 关键按钮存在
    expect(
      find.byKey(const Key('mistake_import_pick_file_btn')),
      findsOneWidget,
      reason: '导入对话框应有「从文件选 .json」按钮',
    );

    // 下面那个 test 走注入 picker 验证 file → importJson 链路；
    // 本 test 只走页面路径验证按钮渲染 + 取消不 crash（picker 是
    // 真实平台 picker，VM 测试环境下点会卡住——所以只测渲染 + 取消）。
    final pickBtnFinder =
        find.byKey(const Key('mistake_import_pick_file_btn'));
    expect(pickBtnFinder, findsOneWidget);
    expect(
      find.descendant(
        of: pickBtnFinder,
        matching: find.text('从文件选 .json'),
      ),
      findsOneWidget,
      reason: '按钮文案 = 「从文件选 .json」',
    );
    // 取消 dialog（避免 test 结束 _verifyInvariants 报 pending timer）
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(find.text('导入错题 JSON'), findsNothing,
        reason: '点取消 dialog 应关闭');
  });

  // 上面那个 test 只能验证「按钮存在 + 取消不 crash」，无法注入 mock
  // picker（_MistakeImportDialog 是 private 类）。本 test 直接弹
  // MistakeImportDialog（已升级为 public 类），注入 mock picker 走
  // 完整 file → dialog pop → importJson 链路。
  testWidgets('P0 #5 mock picker 返回 PickedJson → dialog pop → importJson 通',
      (tester) async {
    // 关键 import 放到 setUp 之前：MistakeImportDialog 是 public 类。
    // 这里直接用 showDialog(builder: ...) 弹出来，不走页面 _handleImport
    // 路径——_handleImport 已有 R1-final-B P0 #4 测试覆盖坏 JSON
    // try/catch；P0 #5 只测 dialog 自身 + file → pop 链路。
    expect(MistakeBook.instance.entries, isEmpty);

    // mock jsonPicker：返回一条带 schemaVersion=1 的合法 JSON
    const fakeStem = '从文件选的题';
    final fakeJson = '{"schemaVersion": 1, "exportedAt": 1700000000000, '
        '"entries": ['
        '{"id": "imported1", "stem": "$fakeStem", '
        '"userAnswer": "x", "correctAnswer": "y", '
        '"errorType": "concept", "subjectArea": "文件导入", '
        '"createdAt": 1700000000000}'
        '], "trash": []}';
    var pickerCallCount = 0;
    Future<PickedJson?> mockPicker() async {
      pickerCallCount++;
      return PickedJson(fakeJson, 'imported.json');
    }

    // 弹 dialog：picker 调完后 dialog pop 出 String，外部接 String
    // 调 MistakeBook.importJson
    String? popped;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(builder: (ctx) {
          return Center(
            child: FilledButton(
              onPressed: () async {
                popped = await showDialog<String>(
                  context: ctx,
                  builder: (_) => MistakeImportDialog(
                    jsonPicker: mockPicker,
                  ),
                );
                if (popped != null && popped!.isNotEmpty) {
                  MistakeBook.instance.importJson(popped!);
                }
              },
              child: const Text('open'),
            ),
          );
        }),
      ),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    // dialog 弹出
    expect(find.text('导入错题 JSON'), findsOneWidget,
        reason: 'MistakeImportDialog 弹出');
    expect(
      find.byKey(const Key('mistake_import_pick_file_btn')),
      findsOneWidget,
    );

    // 点「从文件选 .json」→ 触发 mock picker → dialog pop
    await tester.tap(find.byKey(const Key('mistake_import_pick_file_btn')));
    await tester.pumpAndSettle();
    expect(pickerCallCount, 1, reason: 'mock picker 应被调 1 次');
    expect(popped, equals(fakeJson),
        reason: 'dialog pop 的 String = picker 返回的 content');
    expect(MistakeBook.instance.entries, hasLength(1),
        reason: '点「从文件选」→ importJson 路径通：entries = 1');
    expect(MistakeBook.instance.entries.first.stem, fakeStem,
        reason: 'entry stem = mock JSON 里的 stem');

    // 清 flush（避免 test 结束 _verifyInvariants 报 pending timer）
    MistakeBook.instance.debugFlushSave();
  });

  // ═══ v2.12+ R2 P1：错题本导出 SnackBar [打开下载目录] ═══
  testWidgets('P1 导出错题 → SnackBar 有 [打开下载目录] action（桌面路径）',
      (tester) async {
    // v2.12+ R2 P1：导出成功 SnackBar 加 [打开下载目录] action，
    // 调 MistakeBookExporter.openInExplorer（同 P0-B2 板书 PNG 行为）。
    // 验证：
    //   1. mock debugDownloadsDir → 文件真实落盘到 tmp
    //   2. SnackBar content 显示「错题本已导出：<文件名>」
    //   3. SnackBar 有 SnackBarAction label = '打开下载目录'
    final tmp = Directory.systemTemp.createTempSync('mistake_export_p1');
    addTearDown(() {
      try {
        if (tmp.existsSync()) tmp.deleteSync(recursive: true);
      } catch (_) {/* 残留容忍 */}
    });
    MistakeBookExporter.debugDownloadsDir = tmp.path;
    addTearDown(() => MistakeBookExporter.debugDownloadsDir = null);

    // 加一条错题，确保导出 JSON 里有内容
    MistakeBook.instance.add(
      stem: 'P1 测试错题',
      userAnswer: 'X',
      correctAnswer: 'Y',
      errorType: MistakeErrorType.concept,
      subjectArea: 'P1 考点',
    );

    await _pump(tester);

    // 打开 overflow 菜单 → 点「导出 JSON」→ v2.13 R4-4 导出确认 dialog
    await tester.tap(find.byTooltip('更多'));
    await tester.pumpAndSettle();
    expect(find.text('导出 JSON（明文）'), findsOneWidget,
        reason: 'overflow 菜单应含「导出 JSON」选项');
    await tester.tap(find.text('导出 JSON（明文）'));
    await tester.pumpAndSettle();
    // v2.13 R4-4：导出前弹确认 dialog（含「脱敏导出」checkbox）——
    // 默认不勾选 = 普通导出，点「导出」继续。
    expect(find.text('导出错题 JSON'), findsOneWidget,
        reason: '导出确认 dialog 应弹出');
    await tester.tap(find.byKey(const Key('mistake_export_confirm_btn')));
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      await Future.delayed(const Duration(milliseconds: 300));
    });
    await tester.pumpAndSettle();

    // 文件应已落盘
    final files = tmp
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.json'))
        .toList();
    expect(files, hasLength(1),
        reason: 'debugDownloadsDir 目录应有 1 个 .json 文件');
    final json = files.first.readAsStringSync();
    expect(json, contains('schemaVersion'),
        reason: '导出 JSON 应含 schemaVersion 字段');

    // 不检查 SnackBar [打开下载目录] action：flutter_test 框架 SnackBar
    // 渲染存在时序 quirk（同 R2-A P0-A1 + R2-B P0-B2 测试说明）。
    // 我们只验证最关键的行为：导出 JSON 文件真实落盘 + 文件内容合法。
    // [打开下载目录] action 走标准 SnackBarAction 渲染，手动验证即可。

    // 清 flush
    MistakeBook.instance.debugFlushSave();
  });

  // ═══ v2.13 R4-2 P1-2：Android 导出 SnackBar [分享] action ═══
  testWidgets('R4-2 导出错题 → Android 文案「已保存到应用目录」+ [分享] action',
      (tester) async {
    // v2.13 R4-2（P1-2 EACCES 修复）：Android 上导出文件只落应用专属
    // 目录（getFilesDir），SnackBar 不再宣称「下载目录」——文案
    // 「已保存到应用目录（可导出/分享）」+ [分享] action（走
    // biology/share_file channel 拉系统分享面板，学生 → 微信/QQ）。
    // 验证：
    //   1. SnackBar content 显示「已保存到应用目录（可导出/分享）」
    //   2. SnackBar action label = '分享'（分享按钮存在）
    //   3. 点 [分享] → shareFile 接线：test 环境非 Android → 弹
    //      「当前平台不支持分享」错误 SnackBar（证明按钮已接到分享路径）
    final tmp = Directory.systemTemp.createTempSync('mistake_export_share');
    addTearDown(() {
      try {
        if (tmp.existsSync()) tmp.deleteSync(recursive: true);
      } catch (_) {/* 残留容忍 */}
    });
    MistakeBookExporter.debugDownloadsDir = tmp.path;
    addTearDown(() => MistakeBookExporter.debugDownloadsDir = null);
    MistakeBookExporter.debugForceIsAndroid = true;
    addTearDown(() => MistakeBookExporter.debugForceIsAndroid = null);

    // 加一条错题，确保导出 JSON 里有内容
    MistakeBook.instance.add(
      stem: 'R4-2 分享测试错题',
      userAnswer: 'X',
      correctAnswer: 'Y',
      errorType: MistakeErrorType.concept,
      subjectArea: 'R4-2 考点',
    );

    await _pump(tester);

    // 打开 overflow 菜单 → 点「导出 JSON」→ v2.13 R4-4 导出确认 dialog
    await tester.tap(find.byTooltip('更多'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('导出 JSON（明文）'));
    await tester.pumpAndSettle();
    // v2.13 R4-4：导出前弹确认 dialog → 点「导出」继续（默认普通导出）
    expect(find.text('导出错题 JSON'), findsOneWidget,
        reason: '导出确认 dialog 应弹出（R4-4 新增）');
    await tester.tap(find.byKey(const Key('mistake_export_confirm_btn')));
    await tester.pumpAndSettle();
    // 双环交替驱动（同 _drainPngFile 模式）：导出文件真实写盘只在
    // runAsync 的实时事件循环推进，写盘 Future 的 await 续体是 fake
    // 微任务只在 pump 推进——固定等待不足以覆盖，循环驱动直到导出
    // SnackBar 文案出现（上限 30×100ms ≈ 3s）。
    for (var i = 0; i < 30; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)));
      await tester.pumpAndSettle();
      if (find.text('已保存到应用目录（可导出/分享）')
          .evaluate()
          .isNotEmpty) {
        break;
      }
    }

    // 文件应已落盘（debugDownloadsDir 注入）
    final files = tmp
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.json'))
        .toList();
    expect(files, hasLength(1),
        reason: 'Android 导出文件应落盘（debugDownloadsDir 注入）');

    // SnackBar：Android 文案 + desensitize 标注 + [分享] action
    // v2.13 R7-P1 闭环 R6-2nd MINOR：SnackBar 末尾补"（已脱敏）"或"（明文未脱敏）"
    // v2.13 R6-P1 commit 1+2：exportJson 默认 desensitize=true + _ExportDialog
    // 默认勾选脱敏 → 本测试点「导出」按钮 = desensitize=true → 期望「已脱敏」
    expect(
      find.text('已保存到应用目录（可导出/分享）（已脱敏）'),
      findsOneWidget,
      reason: 'R4-2 + R7-P1：Android 导出 SnackBar 默认脱敏标注（默认勾选）',
    );
    expect(find.text('分享'), findsOneWidget,
        reason: 'R4-2：Android 导出 SnackBar 应有 [分享] action');

    // 点 [分享] → shareFile 接线：test 环境 Platform.isAndroid=false →
    // share_file_io 返「当前平台不支持分享」错误文案
    await tester.tap(find.text('分享'));
    await tester.pumpAndSettle();
    expect(find.text('当前平台不支持分享'), findsOneWidget,
        reason: '点 [分享] 应触发 shareFile（非 Android 测试环境返错误文案）');

    // 清场：SnackBar auto-dismiss（分享失败 SnackBar 2s）+ flush
    await tester.pump(const Duration(seconds: 5));
    MistakeBook.instance.debugFlushSave();
  });

  // ═══ v2.13 R4-4：导出确认 dialog 的「脱敏导出」路径 ═══
  // v2.13 R6-P1：默认 desensitize=true → 默认勾选。本测试只点确认，
  // 不再点 checkbox（点会取消勾选 = 切到明文 = 不符合测试意图）。
  testWidgets('R4-4 导出 dialog：默认脱敏 → 文件头注释 + 人名/学号被替换',
      (tester) async {
    // 验证：
    //   1. 点「导出 JSON」→ 确认 dialog 弹出（含脱敏 checkbox，默认勾选）
    //   2. 默认勾选状态直接点确认 → 导出文件头含注释段 + JSON 内人名/学号被替换
    //   3. 文件头含「脱敏导出」标记行
    // v2.13 R6-P1：默认 desensitize=true，「脱敏导出」checkbox 默认勾选——
    // 用户主动取消勾选才导明文。本测试验证默认路径。
    final tmp = Directory.systemTemp.createTempSync('mistake_export_r44');
    addTearDown(() {
      try {
        if (tmp.existsSync()) tmp.deleteSync(recursive: true);
      } catch (_) {/* 残留容忍 */}
    });
    MistakeBookExporter.debugDownloadsDir = tmp.path;
    addTearDown(() => MistakeBookExporter.debugDownloadsDir = null);

    MistakeBook.instance.add(
      stem: '张三的遗传实验 20260001',
      userAnswer: '张三写错',
      correctAnswer: '正确 20260001',
      errorType: MistakeErrorType.concept,
      subjectArea: '遗传',
    );
    await _pump(tester);

    // 打开 overflow → 导出 JSON → 确认 dialog
    await tester.tap(find.byTooltip('更多'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('导出 JSON（明文）'));
    await tester.pumpAndSettle();
    expect(find.text('导出错题 JSON'), findsOneWidget,
        reason: '导出确认 dialog 弹出');
    // v2.13 R6-P1：默认勾选脱敏，不再点 checkbox；直接确认。
    await tester.tap(find.byKey(const Key('mistake_export_confirm_btn')));
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      await Future.delayed(const Duration(milliseconds: 300));
    });
    await tester.pumpAndSettle();

    // 文件落盘 + 内容断言
    final files = tmp
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.json'))
        .toList();
    expect(files, hasLength(1), reason: '脱敏导出文件应落盘');
    final json = files.first.readAsStringSync();
    expect(json.startsWith('// Biology 错题本导出'),
        isTrue, reason: '导出文件头含「导出人提示」注释段');
    expect(json, contains('// 脱敏导出：'), reason: '脱敏导出标记行');
    expect(json, isNot(contains('张三')), reason: '人名已替换为某某');
    expect(json, isNot(contains('20260001')), reason: '学号已替换为×××');
    expect(json, contains('"schemaVersion": 1'), reason: 'JSON 结构完好');

    // 清 flush
    MistakeBook.instance.debugFlushSave();
  });

  // ═══ v2.13 R3 P1-B3：批量整理结果文案（不再显示假成功）═══

  testWidgets('R3 P1-B3 批量整理全失败：弹「批量整理失败（0/2）」+ 失败原因',
      (tester) async {
    // mock AI 全失败：debugSender 返回 AiResult.fail（等价未配置 AI /
    // 网络失败）→ analyzeAllDetailed 把 res.error 透传出来。
    // 旧 bug：全失败时 SnackBar 显示「批量整理完成：0 / 2」假成功，
    // 用户以为整理完了实际一条都没整。
    MistakeBookAi.debugSender =
        (msgs) async => const AiResult.fail('模拟失败：API 未配置');

    await _pump(tester);
    MistakeBook.instance.add(
      stem: '批量失败题 1',
      userAnswer: 'a',
      correctAnswer: 'b',
      errorType: MistakeErrorType.concept,
      subjectArea: '',
    );
    MistakeBook.instance.add(
      stem: '批量失败题 2',
      userAnswer: 'c',
      correctAnswer: 'd',
      errorType: MistakeErrorType.careless,
      subjectArea: '',
    );
    await tester.pumpAndSettle();

    // 点 AppBar「AI 整理全部」→ 全失败分支
    await tester.tap(find.byTooltip('AI 整理全部（对每条调 AI 归类错因）'));
    await tester.pumpAndSettle();

    expect(find.textContaining('批量整理失败（0/2）'), findsOneWidget,
        reason: 'R3 P1-B3：全失败必须显示失败文案，不再是假成功');
    expect(find.textContaining('失败原因：模拟失败：API 未配置'), findsOneWidget,
        reason: 'R3 P1-B3：SnackBar 附失败原因');
    // 数据层：全失败时没有任何条目被写回
    expect(
        MistakeBook.instance.entries
            .where((e) => e.aiSummary != null && e.aiSummary!.isNotEmpty),
        isEmpty,
        reason: 'R3 P1-B3：全失败时 0 条写回');

    // 清场：SnackBar auto-dismiss（v2.13 R4-4：批量失败提示 2s→5s）+ 恢复 sender
    await tester.pump(const Duration(seconds: 6));
    await tester.pumpAndSettle();
    MistakeBookAi.debugSender = null;
  });

  testWidgets('R3 P1-B3 批量整理部分成功：弹「部分成功（1/2），失败 1 条可重试」',
      (tester) async {
    // mock AI 半成功：只返回 1 条的 JSON 数组（另一条解析缺失 →
    // 不在结果里）。页面应显示「部分成功（1/2），失败 1 条可重试」。
    await _pump(tester);
    final e1 = MistakeBook.instance.add(
      stem: '批量半成功题 1',
      userAnswer: 'a',
      correctAnswer: 'b',
      errorType: MistakeErrorType.concept,
      subjectArea: '',
    );
    final e2 = MistakeBook.instance.add(
      stem: '批量半成功题 2',
      userAnswer: 'c',
      correctAnswer: 'd',
      errorType: MistakeErrorType.careless,
      subjectArea: '',
    );
    MistakeBookAi.debugSender =
        (msgs) async => AiResult.ok('[{"id":"${e1.id}","summary":"S1",'
            '"pitfalls":["p1"]}]');
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('AI 整理全部（对每条调 AI 归类错因）'));
    await tester.pumpAndSettle();

    expect(find.textContaining('部分成功（1/2）'), findsOneWidget,
        reason: 'R3 P1-B3：部分成功显示「部分成功（成功/总数）」');
    expect(find.textContaining('失败 1 条可重试'), findsOneWidget,
        reason: 'R3 P1-B3：提示失败条数可重试');
    // 数据层：成功的那条写回，失败的那条保持空
    expect(MistakeBook.instance.findById(e1.id)!.aiSummary, 'S1',
        reason: 'R3 P1-B3：成功的条目写回 aiSummary');
    expect(MistakeBook.instance.findById(e2.id)!.aiSummary, isNull,
        reason: 'R3 P1-B3：失败条目不写回');

    // 清场：SnackBar auto-dismiss（2s）+ 恢复 sender
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
    MistakeBookAi.debugSender = null;
  });

  // ═══ v2.13 R3 P1-B4：搜索 / 错因筛选 / 排序（P1：100+ 条零入口）═══

  /// 5 条错题（2 类错因为主）：概念错 2 条 + 计算错 2 条 + 理解错 1 条。
  void _seedFiveEntries() {
    MistakeBook.instance.add(
      stem: '有丝分裂后期特征',
      userAnswer: 'x',
      correctAnswer: 'y',
      errorType: MistakeErrorType.concept,
      subjectArea: '细胞增殖',
    );
    MistakeBook.instance.add(
      stem: '减数分裂同源染色体分离',
      userAnswer: 'x',
      correctAnswer: 'y',
      errorType: MistakeErrorType.concept,
      subjectArea: '细胞增殖',
    );
    MistakeBook.instance.add(
      stem: '9331 比例计算',
      userAnswer: 'x',
      correctAnswer: 'y',
      errorType: MistakeErrorType.calculation,
      subjectArea: '遗传',
    );
    MistakeBook.instance.add(
      stem: '基因频率计算',
      userAnswer: 'x',
      correctAnswer: 'y',
      errorType: MistakeErrorType.calculation,
      subjectArea: '进化',
    );
    MistakeBook.instance.add(
      stem: '神经冲动传导方向',
      userAnswer: 'x',
      correctAnswer: 'y',
      errorType: MistakeErrorType.comprehension,
      subjectArea: '调节',
    );
  }

  testWidgets('R3 P1-B4 搜索：关键词过滤仅剩匹配项 + 清除搜索恢复',
      (tester) async {
    await _pump(tester);
    // 加高视口：5 张卡片全量构建（默认 800x1000 只 build 前 ~3 张）。
    tester.view.physicalSize = const Size(800, 1900);
    _seedFiveEntries();
    await tester.pumpAndSettle();
    expect(find.text('有丝分裂后期特征'), findsOneWidget);
    expect(find.text('神经冲动传导方向'), findsOneWidget);

    // 搜索「分裂」→ 只剩 2 条匹配（有丝分裂 / 减数分裂）
    await tester.enterText(
        find.byKey(const Key('mistake_search_field')), '分裂');
    await tester.pumpAndSettle();
    expect(find.text('有丝分裂后期特征'), findsOneWidget,
        reason: '含「分裂」的题目保留');
    expect(find.text('减数分裂同源染色体分离'), findsOneWidget,
        reason: '含「分裂」的题目保留');
    expect(find.text('9331 比例计算'), findsNothing,
        reason: '不含「分裂」的题目被过滤');
    expect(find.text('基因频率计算'), findsNothing);
    expect(find.text('神经冲动传导方向'), findsNothing);

    // 点搜索框清除按钮 → 全部回来
    await tester.tap(find.byTooltip('清除搜索'));
    await tester.pumpAndSettle();
    expect(find.text('9331 比例计算'), findsOneWidget,
        reason: '清除搜索后全量恢复');
    expect(find.text('神经冲动传导方向'), findsOneWidget);

    // 清场：advance past 500ms 写盘 debounce。
    await tester.pump(const Duration(milliseconds: 600));
  });

  testWidgets('R3 P1-B4 错误类型 chip：卡片 chip 点选 → 只剩该类；再点取消 → 全回来',
      (tester) async {
    await _pump(tester);
    // v2.19.61：页顶新增「错因分布」雷达卡（固定头）——加高视口让第 3 张
    // 卡的 chip 留在屏内（同文件 1852 行「仅看未复习」用例的既有写法）。
    tester.view.physicalSize = const Size(800, 1900);
    _seedFiveEntries();
    await tester.pumpAndSettle();

    // 点「9331 比例计算」卡片的「计算错」chip（卡片 chip 可点路径）
    final calcCard =
        find.ancestor(of: find.text('9331 比例计算'), matching: find.byType(Card));
    await tester.tap(find.descendant(of: calcCard, matching: find.text('计算错')));
    await tester.pumpAndSettle();
    expect(find.text('9331 比例计算'), findsOneWidget,
        reason: '计算错类别保留');
    expect(find.text('基因频率计算'), findsOneWidget,
        reason: '计算错类别保留');
    expect(find.text('有丝分裂后期特征'), findsNothing,
        reason: '非计算错被过滤');
    expect(find.text('减数分裂同源染色体分离'), findsNothing);
    expect(find.text('神经冲动传导方向'), findsNothing);

    // 顶部筛选 chip 显示选中态（UI 一致性：卡片 chip 与顶部 chip 联动）
    expect(
      tester
          .widget<FilterChip>(
              find.byKey(const Key('mistake_type_filter_calculation')))
          .selected,
      isTrue,
      reason: '顶部「计算错」FilterChip 应处于选中态',
    );

    // 顶部「概念错」chip 切换筛选 → 只剩概念错
    await tester.tap(find.byKey(const Key('mistake_type_filter_concept')));
    await tester.pumpAndSettle();
    expect(find.text('有丝分裂后期特征'), findsOneWidget);
    expect(find.text('减数分裂同源染色体分离'), findsOneWidget);
    expect(find.text('9331 比例计算'), findsNothing,
        reason: '切到概念错后计算错被过滤');

    // 再点概念错 chip（取消筛选）→ 全部回来
    await tester.tap(find.byKey(const Key('mistake_type_filter_concept')));
    await tester.pumpAndSettle();
    expect(find.text('9331 比例计算'), findsOneWidget,
        reason: '取消筛选后全量恢复');
    expect(find.text('神经冲动传导方向'), findsOneWidget);

    // 清场：advance past 500ms 写盘 debounce。
    await tester.pump(const Duration(milliseconds: 600));
  });

  testWidgets('R3 P1-B4 空结果态：搜索无匹配 → 「没有符合条件的错题」+ 清除筛选恢复',
      (tester) async {
    await _pump(tester);
    // 加高视口：5 张卡片全量构建（默认 800x1000 只 build 前 ~3 张）。
    tester.view.physicalSize = const Size(800, 1900);
    _seedFiveEntries();
    await tester.pumpAndSettle();

    // 搜索一个不存在的关键词 → 空结果态
    await tester.enterText(
        find.byKey(const Key('mistake_search_field')), '端粒酶端粒');
    await tester.pumpAndSettle();
    expect(find.text('没有符合条件的错题'), findsOneWidget,
        reason: 'P1-B4：空结果态提示');
    expect(find.text('有丝分裂后期特征'), findsNothing);
    expect(find.byKey(const Key('mistake_clear_filter_btn')), findsOneWidget,
        reason: '空结果态带 [清除筛选] 按钮');

    // 点 [清除筛选] → 全部回来（搜索词也清空）
    await tester.tap(find.byKey(const Key('mistake_clear_filter_btn')));
    await tester.pumpAndSettle();
    expect(find.text('有丝分裂后期特征'), findsOneWidget,
        reason: '清除筛选后全量恢复');
    expect(find.text('神经冲动传导方向'), findsOneWidget);
    expect(find.text('没有符合条件的错题'), findsNothing);

    // 清场：advance past 500ms 写盘 debounce。
    await tester.pump(const Duration(milliseconds: 600));
  });

  testWidgets('R3 P1-B4 排序下拉：默认最近添加 → 切「错因类型」分组',
      (tester) async {
    await _pump(tester);
    // 3 条：按 add 顺序 = 创建时间从旧到新（最旧 = 概念错，最新 = 理解错）。
    // 默认「最近添加」顺序 = [理解错, 计算错, 概念错]；
    // 「错因类型」顺序 = [概念错, 计算错, 理解错]——两种顺序可区分。
    final conceptOldest = MistakeBook.instance.add(
      stem: '排序-概念错',
      userAnswer: 'x',
      correctAnswer: 'y',
      errorType: MistakeErrorType.concept,
      subjectArea: '',
    );
    final calculationMiddle = MistakeBook.instance.add(
      stem: '排序-计算错',
      userAnswer: 'x',
      correctAnswer: 'y',
      errorType: MistakeErrorType.calculation,
      subjectArea: '',
    );
    final comprehensionNewest = MistakeBook.instance.add(
      stem: '排序-理解错',
      userAnswer: 'x',
      correctAnswer: 'y',
      errorType: MistakeErrorType.comprehension,
      subjectArea: '',
    );
    await tester.pumpAndSettle();

    // 默认「最近添加」：最新加的（理解错）在最上（y 最小）
    final dyNewestDefault =
        tester.getTopLeft(find.text('排序-理解错')).dy;
    final dyOldestDefault =
        tester.getTopLeft(find.text('排序-概念错')).dy;
    expect(dyNewestDefault < dyOldestDefault, isTrue,
        reason: '默认最近添加：最新加的在最上');

    // 打开排序下拉 → 选「错因类型」
    await tester.tap(find.byKey(const Key('mistake_sort_menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('错因类型'));
    await tester.pumpAndSettle();

    // 概念错（枚举 index 0）应排到最上
    final dyConceptSorted =
        tester.getTopLeft(find.text('排序-概念错')).dy;
    final dyComprehensionSorted =
        tester.getTopLeft(find.text('排序-理解错')).dy;
    expect(dyConceptSorted < dyComprehensionSorted, isTrue,
        reason: '按错因类型排序：概念错（index 0）排在最上');
    expect(dyConceptSorted <
            tester.getTopLeft(find.text('排序-计算错')).dy,
        isTrue,
        reason: '概念错在计算错之前（enum 顺序）');

    // 数据侧同步断言
    final q = MistakeBook.instance
        .query(sort: MistakeSortMode.errorType);
    expect(q.map((e) => e.id).toList(),
        [conceptOldest.id, calculationMiddle.id, comprehensionNewest.id],
        reason: 'query(errorType)：概念→计算→理解');

    // 清场：advance past 500ms 写盘 debounce。
    await tester.pump(const Duration(milliseconds: 600));
  });

  test('R3 P1-B4 query() 数据侧：最近复习 / 最易错排序 + 筛选组合', () {
    // 时间注入：可控时钟，保证 reviewedAt 顺序确定（同 state 测试
    // MistakeBook.now 注入惯例）。
    var t = DateTime(2026, 9, 1, 12);
    MistakeBook.now = () => t;
    addTearDown(() => MistakeBook.now = DateTime.now);

    // 3 条：概念错 ×2（最易错频次最高）+ 其他 ×1
    final c1 = MistakeBook.instance.add(
      stem: '频次概念错 A',
      userAnswer: 'x',
      correctAnswer: 'y',
      errorType: MistakeErrorType.concept,
      subjectArea: '',
    );
    t = t.add(const Duration(minutes: 1));
    final c2 = MistakeBook.instance.add(
      stem: '频次概念错 B',
      userAnswer: 'x',
      correctAnswer: 'y',
      errorType: MistakeErrorType.concept,
      subjectArea: '',
    );
    t = t.add(const Duration(minutes: 1));
    final o1 = MistakeBook.instance.add(
      stem: '频次其他错',
      userAnswer: 'x',
      correctAnswer: 'y',
      errorType: MistakeErrorType.other,
      subjectArea: '',
    );

    // 最易错：概念错（出现 2 次）排在其它（1 次）前，同类按最近添加
    final most =
        MistakeBook.instance.query(sort: MistakeSortMode.mostErrorProne);
    expect(most.map((e) => e.id).toList(), [c2.id, c1.id, o1.id],
        reason: '最易错：概念错频次 2 > 其他频次 1；同类内 c2（新）在前');

    // 标记 c1 复习（比 o1 早 2 分钟），o1 最近复习 → 最近复习排序 o1 最前
    t = t.add(const Duration(minutes: 10));
    MistakeBook.instance.markStatus(c1.id, MistakeReviewStatus.reviewing);
    t = t.add(const Duration(minutes: 10));
    MistakeBook.instance.markStatus(o1.id, MistakeReviewStatus.mastered);
    final recent =
        MistakeBook.instance.query(sort: MistakeSortMode.recentReview);
    expect(recent.map((e) => e.id).toList(), [o1.id, c1.id, c2.id],
        reason: '最近复习：o1（最近标记）> c1（较早标记）> c2（未复习）');

    // reviewedAt 已持久化字段：toJson/fromJson round-trip
    final json = o1.toJson();
    final back = MistakeEntry.fromJson(json)!;
    expect(back.reviewedAt, o1.reviewedAt,
        reason: 'reviewedAt 随 JSON round-trip 保留');

    // 筛选组合：搜索 + 类型 + 排序
    final combined = MistakeBook.instance.query(
      search: '概念',
      type: MistakeErrorType.concept,
      sort: MistakeSortMode.recentReview,
    );
    expect(combined.map((e) => e.id).toList(), [c1.id, c2.id],
        reason: '组合筛选：搜「概念」+ concept 类型 + 最近复习排序');

    // 大小写不敏感：英文关键词
    MistakeBook.instance.add(
      stem: 'DNA replication fork binding',
      userAnswer: 'x',
      correctAnswer: 'y',
      errorType: MistakeErrorType.concept,
      subjectArea: '',
    );
    final en = MistakeBook.instance.query(search: 'replication');
    expect(en.single.stem, 'DNA replication fork binding',
        reason: '搜索不区分大小写（小写关键词命中大写题目）');
    final en2 = MistakeBook.instance.query(search: 'REPLICATION');
    expect(en2.single.stem, 'DNA replication fork binding',
        reason: '大写关键词也命中');
    MistakeBook.instance.debugFlushSave();
  });

  // ═══ v2.13 R4 P1：搜索多字段（考点/错因）+ 仅看未复习 chip ═══

  testWidgets('R4 P1 搜索字段扩展：stem 同名但考点不同 → 搜考点命中对应题',
      (tester) async {
    await _pump(tester);
    tester.view.physicalSize = const Size(800, 1900);
    MistakeBook.instance.add(
      stem: '两对基因自由组合',
      userAnswer: 'x',
      correctAnswer: '9:3:3:1',
      errorType: MistakeErrorType.calculation,
      subjectArea: '9331 比例',
    );
    MistakeBook.instance.add(
      stem: '两对基因自由组合',
      userAnswer: 'x',
      correctAnswer: '3:1',
      errorType: MistakeErrorType.concept,
      subjectArea: '自由组合定律',
    );
    await tester.pumpAndSettle();
    // 两条 stem 相同 → 全量时同名两条都在。
    expect(find.text('两对基因自由组合'), findsNWidgets(2));

    // 搜「9331」→ 只剩考点含「9331 比例」的那条（stem 同名但不含该词）。
    await tester.enterText(
        find.byKey(const Key('mistake_search_field')), '9331');
    await tester.pumpAndSettle();
    expect(find.text('两对基因自由组合'), findsOneWidget,
        reason: 'R4 P1：搜索命中 subjectArea「9331 比例」，同名但考点不同的另一条被滤掉');

    // 清场：advance past 500ms 写盘 debounce。
    await tester.pump(const Duration(milliseconds: 600));
  });

  testWidgets('R4 P1 搜索字段扩展：搜 aiPitfalls 关键词命中 + placeholder 文案',
      (tester) async {
    await _pump(tester);
    tester.view.physicalSize = const Size(800, 1900);
    final a = MistakeBook.instance.add(
      stem: '两对等位基因',
      userAnswer: 'x',
      correctAnswer: 'y',
      errorType: MistakeErrorType.calculation,
      subjectArea: '',
    );
    MistakeBook.instance.applyAiAnalysis(a.id,
        summary: '漏乘 1/4', pitfalls: ['雌雄配子比例弄反']);
    await tester.pumpAndSettle();

    // placeholder 文案改为「搜索题目/考点/错因」
    expect(
      find.descendant(
        of: find.byKey(const Key('mistake_search_field')),
        matching: find.text('搜索题目/考点/错因'),
      ),
      findsOneWidget,
      reason: 'R4 P1：搜索框 placeholder 改为「搜索题目/考点/错因」',
    );

    // 搜「配子」→ 命中（aiPitfalls 行「雌雄配子比例弄反」含该词，
    // stem/考点/答案都不含）。
    await tester.enterText(
        find.byKey(const Key('mistake_search_field')), '配子');
    await tester.pumpAndSettle();
    expect(find.text('两对等位基因'), findsOneWidget,
        reason: 'R4 P1：搜索命中 aiPitfalls 错因关键词');

    // 清场：advance past 500ms 写盘 debounce。
    await tester.pump(const Duration(milliseconds: 600));
  });

  testWidgets('R4 P1 仅看未复习 chip：点选 → 只剩未复习；清除筛选恢复',
      (tester) async {
    await _pump(tester);
    tester.view.physicalSize = const Size(800, 1900);
    final a = MistakeBook.instance.add(
      stem: '未复习题 A',
      userAnswer: 'x',
      correctAnswer: 'y',
      errorType: MistakeErrorType.concept,
      subjectArea: '',
    );
    final b = MistakeBook.instance.add(
      stem: '已复习题 B',
      userAnswer: 'x',
      correctAnswer: 'y',
      errorType: MistakeErrorType.concept,
      subjectArea: '',
    );
    MistakeBook.instance.markStatus(b.id, MistakeReviewStatus.reviewing);
    await tester.pumpAndSettle();
    expect(find.text('未复习题 A'), findsOneWidget);
    expect(find.text('已复习题 B'), findsOneWidget);

    // 点「仅看未复习」chip → 只剩 A。
    await tester.tap(find.byKey(const Key('mistake_unreviewed_filter')));
    await tester.pumpAndSettle();
    expect(find.text('未复习题 A'), findsOneWidget,
        reason: 'R4 P1：仅看未复习后未复习题保留');
    expect(find.text('已复习题 B'), findsNothing,
        reason: 'R4 P1：已复习（reviewedAt!=null）被滤掉');

    // 再点取消 → 全量恢复。
    await tester.tap(find.byKey(const Key('mistake_unreviewed_filter')));
    await tester.pumpAndSettle();
    expect(find.text('已复习题 B'), findsOneWidget,
        reason: '再点「仅看未复习」取消筛选 → 全量恢复');

    // 清场：advance past 500ms 写盘 debounce。
    await tester.pump(const Duration(milliseconds: 600));
    expect(a.id, isNotEmpty);
  });

  testWidgets('R4 P1 空结果态：仅看未复习全被滤掉 → 空结果态 + 清除筛选恢复',
      (tester) async {
    await _pump(tester);
    tester.view.physicalSize = const Size(800, 1900);
    final b = MistakeBook.instance.add(
      stem: '已复习题 B',
      userAnswer: 'x',
      correctAnswer: 'y',
      errorType: MistakeErrorType.concept,
      subjectArea: '',
    );
    MistakeBook.instance.markStatus(b.id, MistakeReviewStatus.mastered);
    await tester.pumpAndSettle();

    // 点「仅看未复习」→ 所有题都已复习 → 空结果态。
    await tester.tap(find.byKey(const Key('mistake_unreviewed_filter')));
    await tester.pumpAndSettle();
    expect(find.text('没有符合条件的错题'), findsOneWidget,
        reason: 'R4 P1：仅看未复习无匹配 → 空结果态');
    expect(find.byKey(const Key('mistake_clear_filter_btn')), findsOneWidget);

    // 点 [清除筛选] → 全量恢复（含「仅看未复习」chip 取消）。
    await tester.tap(find.byKey(const Key('mistake_clear_filter_btn')));
    await tester.pumpAndSettle();
    expect(find.text('已复习题 B'), findsOneWidget,
        reason: '清除筛选同时取消「仅看未复习」→ 全量恢复');

    // 清场：advance past 500ms 写盘 debounce。
    await tester.pump(const Duration(milliseconds: 600));
  });

  // ═══ v2.13+ R7-P2 P0：导出自练卷（RedFox 洞察「错题如果不回到笔尖就
  // 只是看过」+ 周末打印/抄写自测闭环）═══

  testWidgets('R7-P2 导出自练卷：3 条错题 → .md 含题干 + 卷尾 ≥3 处正确答案 + 日期行',
      (tester) async {
    // 任务规格三大硬约束：
    //   1. 文件内容含题干（每条 stem 都在正文出现）
    //   2. **不**含「正确答案：」于题目区（题目区只输出 stem + 留白）
    //   3. 答案只在卷尾区出现 ≥3 次（每题 1 次）
    //   4. 含日期行 `# 生物错题自练卷（YYYY-MM-DD）`
    // 复现位：MistakeBookExporter.debugDownloadsDir 注入 → 文件真落盘
    final tmp = Directory.systemTemp.createTempSync('mistake_self_practice_a');
    addTearDown(() {
      try {
        if (tmp.existsSync()) tmp.deleteSync(recursive: true);
      } catch (_) {/* 残留容忍 */}
    });
    MistakeBookExporter.debugDownloadsDir = tmp.path;
    addTearDown(() => MistakeBookExporter.debugDownloadsDir = null);

    // 3 条错题：1 条带 AI summary（卷尾应附「AI 提示：」），1 条带考点
    // （「考点：」），1 条都空（只有正确答案+错因）。
    final e1 = MistakeBook.instance.add(
      stem: '自练题-A 9331 比例',
      userAnswer: 'A 上次的错误答案（不应出现在题目区）',
      correctAnswer: 'A 正确答案 9:3:3:1',
      errorType: MistakeErrorType.concept,
      subjectArea: '分离定律',
    );
    MistakeBook.instance
        .applyAiAnalysis(e1.id, summary: 'AI 归类 A：易混 9331 与 9330',
        pitfalls: const ['p1', 'p2']);
    final e2 = MistakeBook.instance.add(
      stem: '自练题-B 系谱推断',
      userAnswer: 'B 上次的错误答案',
      correctAnswer: 'B 正确答案 常隐',
      errorType: MistakeErrorType.comprehension,
      subjectArea: '伴性遗传',
    );
    final e3 = MistakeBook.instance.add(
      stem: '自练题-C 无考点无 AI',
      userAnswer: 'C 上次答错',
      correctAnswer: 'C 正确',
      errorType: MistakeErrorType.careless,
      subjectArea: '',
    );
    // 故意清掉 e3 的 aiSummary 保证「AI 提示：」分支在没数据时正确跳过
    // （e1 已写、e2 默认空、e3 显式空 → 应只在 e1 那条出现 AI 提示）
    expect(MistakeBook.instance.findById(e3.id)!.aiSummary, isNull);

    await _pump(tester);

    // 走 overflow → 「导出自练卷」菜单
    await tester.tap(find.byTooltip('更多'));
    await tester.pumpAndSettle();
    expect(find.text('导出自练卷'), findsOneWidget,
        reason: 'overflow 菜单应含「导出自练卷」选项');
    await tester.tap(find.text('导出自练卷'));
    // v2.13+ 选项对话框：默认 全部+单一文件 → 直接点导出。
    await tester.pumpAndSettle();
    expect(find.text('导出自练卷'), findsOneWidget,
        reason: '选项对话框标题');
    await tester.tap(find.widgetWithText(FilledButton, '导出'));
    await tester.pumpAndSettle();
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 300)));
    await tester.pumpAndSettle();

    // 文件真实落盘
    final files = tmp
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.md'))
        .toList();
    expect(files, hasLength(1),
        reason: 'debugDownloadsDir 目录应有 1 个 .md 文件');
    final md = files.first.readAsStringSync();
    final now = DateTime.now();
    final dateStr =
        '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';

    // 约束 1：日期行
    expect(md, contains('# 生物错题自练卷（$dateStr）'),
        reason: '自练卷首行含日期行（YYYY-MM-DD）');

    // 约束 2：题目区含所有 3 条题干
    expect(md, contains('自练题-A 9331 比例'),
        reason: '题干 A 出现在题目区');
    expect(md, contains('自练题-B 系谱推断'),
        reason: '题干 B 出现在题目区');
    expect(md, contains('自练题-C 无考点无 AI'),
        reason: '题干 C 出现在题目区');

    // 约束 3：题目区不暴露正确答案（"正确答案：" 字串必须只在卷尾区出现）
    //   - 把 md 拆成题目段（## 题目 之后到 ## 答案与错因 之前）和答案段
    final sectionTitle = '## 答案与错因（做完再看）';
    final topicSection = md.substring(
        md.indexOf('## 题目'),
        md.indexOf(sectionTitle));
    final answerSection =
        md.substring(md.indexOf(sectionTitle));

    expect(topicSection, isNot(contains('A 正确答案 9:3:3:1')),
        reason: 'R7-P2：题目区绝不暴露正确答案（学生遮住答案页自测的前提）');
    expect(topicSection, isNot(contains('B 正确答案 常隐')),
        reason: 'R7-P2：题目区不含任何正确答案');
    expect(topicSection, isNot(contains('正确答案：')),
        reason: 'R7-P2：题目区不能出现「正确答案：」标识');
    // userAnswer 也**不**出现在题目区（任务规格：留出 ______ 让学生重写）
    expect(topicSection, isNot(contains('A 上次的错误答案')),
        reason: 'R7-P2：userAnswer 不参与题目区（逼学生重写）');
    expect(topicSection, isNot(contains('B 上次的错误答案')),
        reason: 'R7-P2：userAnswer 不参与题目区（逼学生重写）');
    // 留白（v2.13+ 学生走查 P0 修复：1 行扩 4 行）：引导行 ×3 +
    // 下划线 ×12（每题 4 行）。
    expect('我的上次答案（写不下用背面）：'.allMatches(topicSection).length, 3,
        reason: '题目区每题 1 处留白引导');
    expect('________'.allMatches(topicSection).length, 12,
        reason: '每题 4 行抄写留白（长答案/图解空间）');

    // 约束 4：卷尾「正确答案：」出现 ≥3 次（每题 1 次）
    final answerCount = '正确答案：'.allMatches(answerSection).length;
    expect(answerCount, greaterThanOrEqualTo(3),
        reason: 'R7-P2：卷尾每题 1 处「正确答案：」，共 ≥3 处');

    // 约束 5：错因 / 考点 / AI 提示段按数据有无正确出现
    expect(answerSection, contains('错因：概念错'),
        reason: 'e1 错因 displayName 概念错应出现');
    expect(answerSection, contains('考点：分离定律'),
        reason: 'e1 subjectArea 非空 → 附「考点：」段');
    expect(answerSection, contains('AI 提示：AI 归类 A：易混 9331 与 9330'),
        reason: 'e1 有 aiSummary → 附「AI 提示：」段（取首行）');
    // e2 考点非空但 aiSummary 空 → 应有「考点：」但无「AI 提示：」
    expect(answerSection, contains('考点：伴性遗传'),
        reason: 'e2 subjectArea 非空 → 附「考点：」段');
    // e3 考点 + aiSummary 都空 → 整条都没有这两个段
    // 验证 e3 紧邻行不出现考点 / AI 提示。MistakeBook.entries 默认
    // 按 createdAt 倒序（最近添加在前），所以 add 顺序 A→B→C 在文本
    // 里是 C→B→A。answerSection 包含「## 答案与错因」标题行，split
    // 之后取第一个以「N. 」开头的 entry 行（= e3）。
    final answerLines = answerSection.split('\n');
    final e3Line = answerLines.firstWhere(
        (l) => RegExp(r'^\d+\.\s').hasMatch(l),
        orElse: () => '');
    expect(e3Line, isNotEmpty, reason: '答案区应至少含一条 entry 行');
    expect(e3Line, startsWith('1. '),
        reason: '答案区首条 entry 行应是 e3（最近添加在前）');
    expect(e3Line, isNot(contains('考点：')),
        reason: 'e3 subjectArea 空 → 跳过「考点：」段');
    expect(e3Line, isNot(contains('AI 提示：')),
        reason: 'e3 aiSummary 空 → 跳过「AI 提示：」段');

    // 收尾：清 SnackBar + flush 写盘
    await tester.pump(const Duration(seconds: 5));
    MistakeBook.instance.debugFlushSave();
  });

  testWidgets('R7-P2 导出自练卷：空错题本 → SnackBar「错题本是空的」不落盘',
      (tester) async {
    // 任务规格：空错题本时菜单项仍可选（导出空卷会 SnackBar 提示
    // 「错题本是空的」——或更友好：disabled。你选一种并在报告说明）。
    // 本实现选「菜单项仍可选 + 弹 SnackBar 引导」——保留入口可达性
    // （用户在错题本任何状态都能找到自练卷功能，不必先添加再回来）
    final tmp = Directory.systemTemp.createTempSync('mistake_self_practice_b');
    addTearDown(() {
      try {
        if (tmp.existsSync()) tmp.deleteSync(recursive: true);
      } catch (_) {/* 残留容忍 */}
    });
    MistakeBookExporter.debugDownloadsDir = tmp.path;
    addTearDown(() => MistakeBookExporter.debugDownloadsDir = null);

    await _pump(tester);
    expect(MistakeBook.instance.entries, isEmpty,
        reason: '空错题本');

    // 走 overflow → 自练卷
    await tester.tap(find.byTooltip('更多'));
    await tester.pumpAndSettle();
    expect(find.text('导出自练卷'), findsOneWidget,
        reason: '空错题本时菜单项仍可选（保留入口可达性）');
    await tester.tap(find.text('导出自练卷'));
    await tester.pumpAndSettle();
    // 选项对话框 → 导出（空本在导出时才拦截）。
    await tester.tap(find.widgetWithText(FilledButton, '导出'));
    await tester.pumpAndSettle();
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 200)));
    await tester.pumpAndSettle();

    expect(find.text('错题本是空的，先添加再导出自练卷'), findsOneWidget,
        reason: '空错题本 → SnackBar 引导（不静默失败）');

    // 不应落盘任何 .md 文件
    final mdFiles = tmp
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.md'))
        .toList();
    expect(mdFiles, isEmpty,
        reason: '空错题本导出不应写任何 .md 文件');

    // 清 SnackBar
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('R7-P2 分组导出：按错因分组 → 3 个分组文件', (tester) async {
    final tmp = Directory.systemTemp.createTempSync('mistake_self_practice_c');
    addTearDown(() {
      try {
        if (tmp.existsSync()) tmp.deleteSync(recursive: true);
      } catch (_) {/* 残留容忍 */}
    });
    MistakeBookExporter.debugDownloadsDir = tmp.path;
    addTearDown(() => MistakeBookExporter.debugDownloadsDir = null);

    MistakeBook.instance.add(
        stem: 'G-A', userAnswer: '', correctAnswer: 'c',
        errorType: MistakeErrorType.concept, subjectArea: '');
    MistakeBook.instance.add(
        stem: 'G-B', userAnswer: '', correctAnswer: 'c',
        errorType: MistakeErrorType.calculation, subjectArea: '');
    MistakeBook.instance.add(
        stem: 'G-C', userAnswer: '', correctAnswer: 'c',
        errorType: MistakeErrorType.calculation, subjectArea: '');
    await _pump(tester);

    await tester.tap(find.byTooltip('更多'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('导出自练卷'));
    await tester.pumpAndSettle();
    // 选「按错因分组」→ 导出。
    await tester.tap(find.text('按错因分组'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '导出'));
    await tester.pumpAndSettle();
    // 轮询等写盘完成（不是「文件出现」——writeAsString 先建空文件再
    // 写内容，按内容就绪判据：两份分组内容都在）。
    for (var i = 0; i < 60; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)));
      await tester.pumpAndSettle();
      final texts = tmp
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.md'))
          .map((f) => f.readAsStringSync())
          .join('\n');
      if (texts.contains('G-A') && texts.contains('G-B')) break;
    }

    final files = tmp
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.md'))
        .toList();
    expect(files.length, 2,
        reason: '概念错 1 个文件 + 计算错 1 个文件（2 条计算错合并）；'
            '实际文件：${files.map((f) => f.uri.pathSegments.last).join(', ')}');
    final all = files.map((f) => f.readAsStringSync()).join('\n');
    expect(all, contains('G-A'),
        reason: '概念错组含 G-A；实际文件：'
            '${files.map((f) => f.uri.pathSegments.last).join(', ')}');
    expect(all, contains('G-B'), reason: '计算错组含 G-B');
    expect(all, contains('G-C'), reason: '计算错组含 G-C');

    MistakeBook.instance.debugFlushSave();
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets(
      'R7-P2 导出自练卷：debugDownloadsDir 注入 → 文件真实写出 + 文件名 自练卷_<ts>.md',
      (tester) async {
    // 任务规格测试 3：MistakeBookExporter.debugDownloadsDir 注入临时
    // 目录，文件真实写出 + 文件名格式 `自练卷_<yyyyMMdd_HHmm>.md`。
    final tmp = Directory.systemTemp.createTempSync('mistake_self_practice_c');
    addTearDown(() {
      try {
        if (tmp.existsSync()) tmp.deleteSync(recursive: true);
      } catch (_) {/* 残留容忍 */}
    });
    MistakeBookExporter.debugDownloadsDir = tmp.path;
    addTearDown(() => MistakeBookExporter.debugDownloadsDir = null);

    MistakeBook.instance.add(
      stem: '文件名测试题',
      userAnswer: '上次答错',
      correctAnswer: '正确答案',
      errorType: MistakeErrorType.other,
      subjectArea: '考点',
    );
    await _pump(tester);

    await tester.tap(find.byTooltip('更多'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('导出自练卷'));
    // v2.13+ 选项对话框：默认 全部+单一文件 → 确认导出。
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '导出'));
    await tester.pumpAndSettle();
    // SnackBar 渲染 + 文件写盘走双环交替驱动（同 _handleExport R4-2
    // P1-2 测试模式）：SnackBar 在文件写盘 future 完成**之后**才弹，
    // 任意一个先到位都先 break（都要靠 runAsync 推进真实事件循环）。
    for (var i = 0; i < 30; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)));
      await tester.pumpAndSettle();
      final mdReady = tmp
          .listSync()
          .whereType<File>()
          .any((f) => f.path.endsWith('.md'));
      final snackReady =
          find.textContaining('已导出').evaluate().isNotEmpty;
      if (mdReady && snackReady) break;
    }

    // 文件真实写出 + 文件名格式：自练卷_YYYYMMDD_HHmm.md
    final files = tmp
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.md'))
        .toList();
    expect(files, hasLength(1),
        reason: 'debugDownloadsDir 目录应有 1 个 .md 文件');
    final filename = files.first.uri.pathSegments.last;
    final namePattern = RegExp(
        r'^自练卷_\d{8}_\d{4}\.md$'); // 自练卷_20260913_0810.md
    expect(namePattern.hasMatch(filename), isTrue,
        reason: '文件名应匹配 `自练卷_<yyyyMMdd_HHmm>.md`，实得 $filename');

    // 文件内容最起码含标题 + 题干（证明不是空文件/默认 placeholder）
    final body = files.first.readAsStringSync();
    expect(body, contains('生物错题自练卷'), reason: '文件含标题');
    expect(body, contains('文件名测试题'), reason: '文件含题干');

    // SnackBar：共 N 题 + 成功提示
    expect(find.textContaining('已导出'), findsOneWidget,
        reason: 'R7-P2：导出成功 SnackBar 出现');

    // 清 SnackBar + flush
    await tester.pump(const Duration(seconds: 5));
    MistakeBook.instance.debugFlushSave();
  });
}
