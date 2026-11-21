// scan_upload_dialog_test.dart —— 拍题识别对话框测试（v2.12+ R1 P0 #1）
//
// 覆盖：
//   1. 拍题 → 识别 → 点「存入错题本」→ 验证 entry 在 MistakeBook
//   2. 字段映射正确：stem = scan.summary, subjectArea = 模块名
//   3. SnackBar 「已加入错题本 → [查看]」5 秒可点
//   4. 「填入计算器」 + 「存入错题本」两按钮并存
//   5. v2.13 R3 P1-A1：识别失败弹 SnackBar「识别失败：…，请重试」
//      （成功不弹）——修复"失败只写聊天 messages、对话框零反馈"的静默
//   5. v2.13 R3 P1-A2：加错题后 AI 整理入队被调（与表单入口同款）
//
// 依赖既有 v210_scan_dialog_test.dart 的相同注入手法：
//   - AiSettingsStore.debugConfig = preset
//   - AiChatController.instance.debugScanSender = (msgs) => ok json
//   - widget.picker = () => PickedImage(bytes, name, ext)
// 这样不依赖真实网络/平台插件。

import 'dart:io';
import 'dart:typed_data';

import 'package:biology/services/ai_client.dart';
import 'package:biology/state/scan_bank_store.dart';
import 'package:biology/pages/settings_page.dart';
import 'package:biology/state/first_run_store.dart';
import 'package:biology/state/mistake_book.dart';
import 'package:biology/ui/ai_chat_controller.dart';
import 'package:biology/ui/image_pick.dart';
import 'package:biology/ui/mistake_book_ai.dart';
import 'package:biology/ui/module_fill.dart';
import 'package:biology/ui/scan_upload_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmp;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('scan_upload_dialog_test');
    ScanBankStore.debugFilePath = '${tmp.path}/scan_bank.json';
    MistakeBook.debugFilePath = '${tmp.path}/mistake_book.json';
    AiChatStore.debugFilePath = '${tmp.path}/ai_chat_history.json';
    // v2.13 R4-1 P0：角色守卫测试需要可控角色状态。debugFilePath 隔离
    // 写盘（setRole 不碰真实用户目录），debugReset 清掉上个用例残留。
    FirstRunStore.debugFilePath = '${tmp.path}/first_run.json';
    FirstRunStore.instance.debugReset();
    AiChatController.instance.reset();
    MistakeBook.instance.debugReset();
    ModuleFillBus.resetForTest();
  });

  tearDown(() {
    AiChatController.instance.debugScanSender = null;
    AiChatController.instance.reset();
    AiSettingsStore.debugConfig = null;
    ScanBankStore.debugFilePath = null;
    MistakeBook.debugFilePath = null;
    AiChatStore.debugFilePath = null;
    FirstRunStore.debugFilePath = null;
    FirstRunStore.instance.debugReset();
    ModuleFillBus.resetForTest();
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  // AI 返回一条 dihybrid 杂交（豌豆）的拍题识别结果。
  const scanJson = '{"summary":"豌豆 AaBb 自交 F2 9331 比例",'
      '"module":"cross_dihybrid","params":{"p1":"AaBb","p2":"AaBb"}}';

  /// 弹出拍题对话框。注入 picker 避免依赖平台插件。
  Future<void> openDialog(WidgetTester t) async {
    t.view.physicalSize = const Size(1400, 900);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);
    await t.pumpWidget(MaterialApp(
      home: Builder(
        builder: (ctx) => Scaffold(
          body: TextButton(
            onPressed: () => showScanUploadDialog(
              ctx,
              picker: () async =>
                  PickedImage(Uint8List.fromList([1, 2, 3]), 't.png', 'png'),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    ));
    await t.tap(find.text('open'));
    await t.pumpAndSettle();
  }

  /// 走完「选图 → 识别 → 结果展示」全流程。结果卡上能看到
  /// 「填入遗传计算器·双基因」+ 「存入错题本」两个按钮。
  Future<void> completeScan(WidgetTester t) async {
    AiSettingsStore.debugConfig = AiConfig.presetMinimax;
    AiChatController.instance.debugScanSender =
        (msgs) async => const AiResult.ok(scanJson);
    ModuleFillBus.register(ModuleFillTarget(
      moduleId: 'cross_dihybrid',
      pageIndex: 2,
      label: '遗传计算器·双基因',
      apply: (p) => p['p1'] == 'AaBb',
    ));
    await openDialog(t);
    // 选图（注入 picker）→ 识别
    await t.tap(find.text('选择题目图片'));
    await t.pumpAndSettle();
    // 验证结果卡渲染：summary + 模块名 + 两按钮
    expect(find.textContaining('豌豆 AaBb 自交 F2 9331 比例'),
        findsWidgets, reason: '识别结果 summary 展示');
    expect(find.text('填入遗传计算器·双基因'), findsOneWidget,
        reason: '主按钮「填入」展示');
    expect(find.text('存入错题本'), findsOneWidget,
        reason: 'P0 #1「存入错题本」按钮展示（与填入并列）');
    expect(find.textContaining('识别失败'), findsNothing,
        reason: 'R3 P1-A1：识别成功不弹失败 SnackBar');
  }

  testWidgets('P0 #1 拍题 → 识别 → 点「存入错题本」→ entry 落 MistakeBook',
      (t) async {
    await completeScan(t);
    // 起始 MistakeBook 空
    expect(MistakeBook.instance.entries, isEmpty,
        reason: '未点加入按钮时错题本应为空');

    // 点「存入错题本」
    await t.tap(find.text('存入错题本'));
    await t.pumpAndSettle();

    // 验证 entry 落 MistakeBook
    final entries = MistakeBook.instance.entries;
    expect(entries.length, 1, reason: '点「存入错题本」后 MistakeBook 增 1 条');
    final entry = entries.first;
    expect(entry.stem, '豌豆 AaBb 自交 F2 9331 比例',
        reason: 'stem = scan.summary');
    expect(entry.subjectArea, '遗传计算器·双基因',
        reason: 'subjectArea = scanModuleLabel(scan.module)');
    expect(entry.errorType, MistakeErrorType.concept,
        reason: 'errorType 默认 concept（OCR 误识最常见）');
    expect(entry.userAnswer, '', reason: 'userAnswer 留空（OCR 没识别对错）');
    expect(entry.correctAnswer, '',
        reason: 'correctAnswer 留空（OCR 没识别对错）');
    expect(entry.reviewStatus, MistakeReviewStatus.unreviewed,
        reason: '复习状态默认未复习');
    expect(entry.id, isNotEmpty, reason: 'entry 分配了 id');

    // SnackBar 「已加入错题本 → [撤销]」出现
    expect(find.text('已加入错题本'), findsOneWidget,
        reason: 'SnackBar 文案');
    expect(find.text('撤销'), findsOneWidget,
        reason: 'v2.12+ R1 final-B P0 #2：SnackBar 含「撤销」action（inline Undo）');

    // flush MistakeBook 写盘 debounce（避免 test 结束 timersPending 失败）
    MistakeBook.instance.debugFlushSave();
  });

  testWidgets('P0 #1「填入」与「存入错题本」两按钮并存（不互斥）', (t) async {
    await completeScan(t);
    // 两按钮同显
    expect(find.text('填入遗传计算器·双基因'), findsOneWidget);
    expect(find.text('存入错题本'), findsOneWidget);
    // 点「存入错题本」不影响「填入」按钮的存在（点前没消失）
    await t.tap(find.text('存入错题本'));
    await t.pumpAndSettle();
    // SnackBar 弹出后 dialog 还在（不影响）
    expect(find.text('填入遗传计算器·双基因'), findsOneWidget,
        reason: '点存入错题本不应关闭拍题 dialog');
    expect(find.text('存入错题本'), findsOneWidget,
        reason: '点存入错题本后按钮仍可点');
    // R5 查重语义：再点一次 = 同识别摘要查重命中——条目不重复新增
    //（原断言「再增 1 条」是去重前的旧行为），反馈「已在错题本」。
    await t.tap(find.text('存入错题本'));
    await t.pumpAndSettle();
    expect(MistakeBook.instance.entries.length, 1,
        reason: '同摘要重复存入被查重，不产生重复条目');
    expect(find.textContaining('已在错题本'), findsOneWidget,
        reason: '查重提示替代「已加入错题本」');
    MistakeBook.instance.debugFlushSave();
  });

  // ═══ v2.12+ R1 final-B P0 #2：拍题结果 inline Undo（点 [撤销] 撤回加入） ═══
  testWidgets(
      'P0 #2 inline Undo：点 [撤销] → entry 移到 trash,不在 entries（用户撤回"加入"动作）',
      (t) async {
    // 学生每日拍题 5 道，每道 30 秒决策——OCR 错的题如果已经入库，
    // 5 秒 Undo 窗口是高频救命操作。Undo 走 `MistakeBook.delete(id)`：
    // 软删除移到 trash（不是真删），5 秒过期后用户可从错题本回收站恢复。
    await completeScan(t);
    expect(MistakeBook.instance.entries, isEmpty,
        reason: '未点加入按钮时错题本应为空');

    // 点「存入错题本」→ entry 落 MistakeBook + SnackBar 弹 [撤销]
    await t.tap(find.text('存入错题本'));
    await t.pumpAndSettle();
    expect(MistakeBook.instance.entries, hasLength(1),
        reason: '点加入后 MistakeBook 增 1 条');
    final addedId = MistakeBook.instance.entries.first.id;
    expect(MistakeBook.instance.trash, isEmpty,
        reason: '刚加入的 entry 不在 trash');
    expect(find.text('撤销'), findsOneWidget,
        reason: 'SnackBar 含 [撤销] action');

    // 点 [撤销]：直接调 SnackBarAction 的 onPressed 回调（不走 tap +
    // hit test）——SnackBar 锚定屏幕底部 + enter 动画未完成时，tap
    // 命中 SnackBar 容器而非 button，hit test 警告会让人误判 Undo
    // 没生效。这里直接调 callback 测「撤销 = delete(id)」语义。
    final action = t.widget<SnackBarAction>(
        find.ancestor(of: find.text('撤销'), matching: find.byType(SnackBarAction)));
    action.onPressed();
    await t.pumpAndSettle();
    expect(MistakeBook.instance.entries, isEmpty,
        reason: '撤销后 entry 不在主列表（撤回"加入"动作）');
    expect(MistakeBook.instance.trash, hasLength(1),
        reason: '撤销 = 软删除，entry 进 trash（不是真删）');
    expect(MistakeBook.instance.trash.first.id, addedId,
        reason: 'trash 里是刚才加的那条（按 id 识别）');

    // 验证后续可从回收站恢复：5 秒过期后用户还能 restoreFromTrash 拿回
    // （这是 v2.12 R1 P0 #5 已做的能力，本测试顺手验一下 inline Undo
    // 不破坏这条链路）
    final restored = MistakeBook.instance.restoreFromTrash(addedId);
    expect(restored, isNotNull);
    expect(MistakeBook.instance.entries, hasLength(1),
        reason: '回收站恢复后 entry 回到主列表');
    expect(MistakeBook.instance.trash, isEmpty);
    MistakeBook.instance.debugFlushSave();
  });

  // ═══ v2.13 R3 P1-A1：识别失败不再静默（弹 SnackBar 提示重试） ═══
  // 背景：sendScan 失败只写聊天 messages，而拍题对话框不渲染聊天——
  // 断网/额度用尽/解析失败时 spinner 消失后零反馈。现在 sendScan 返回
  // 成功与否 + lastScanError，对话框失败时弹「识别失败：$err，请重试」。
  testWidgets('R3 P1-A1 识别失败（断网/额度/解析失败）→ SnackBar「识别失败：…，请重试」',
      (t) async {
    // 注入失败发送器模拟断网/额度用尽（返回带 error 的 AiResult）
    AiSettingsStore.debugConfig = AiConfig.presetMinimax;
    AiChatController.instance.debugScanSender =
        (msgs) async => const AiResult.fail('网络超时');
    await openDialog(t);
    // 选图 → sendScan 走注入的失败发送器 → busy 回落
    await t.tap(find.text('选择题目图片'));
    await t.pumpAndSettle();
    // SnackBar 弹出：识别失败 + 可行动提示 + 请重试（不再静默/不裸露技术串）
    expect(find.textContaining('识别失败'), findsOneWidget,
        reason: 'R3 P1-A1：失败弹 SnackBar（之前 spinner 消失后零反馈）');
    expect(find.textContaining('检查网络'), findsOneWidget,
        reason: 'v2.13 UI 走查：错误人话化为可行动提示（原裸「网络超时」）');
    expect(find.textContaining('重试'), findsOneWidget,
        reason: 'SnackBar 提示重试');
    // 失败不渲染识别结果卡（lastScan 未更新）
    expect(find.text('存入错题本'), findsNothing,
        reason: '失败时 lastScan 未更新，结果卡不出现');
  });

  // ═══ v2.13 R3 P1-A2：拍题加错题也入 AI 自动整理队（与表单入口同款） ═══
  testWidgets('P1-A2 拍题 → 加错题本 → AI 整理入队被调（sender 计数 +1）',
      (t) async {
    // 表单入口（_handleAdd）有 debugEnqueueAiOrganize 入队，拍题入口之前
    // 漏了这 1 行 → 学生高频路径缺「AI 已自动归类」承诺。此测试走拍题
    // 全路径，mock debugOrganizeSender 计数：入队 → 500ms debounce →
    // _runAiOrganize 调 sender，全程走真实队列（同 mistake_book_page_test
    // P0 #3 的验证手法）。
    var organizeCalls = 0;
    MistakeBook.debugOrganizeSender = (entry) async {
      organizeCalls++;
      return MistakeAiAnalysis(
        summary: 'AI 自动归类：${entry.stem}',
        pitfalls: const ['避坑 1'],
      );
    };

    await completeScan(t);

    // 点「存入错题本」→ entry 落 MistakeBook。
    // 注意不能用 pumpAndSettle——它每步推进 100ms，SnackBar 进入动画
    // 累计会越过 500ms debounce 窗口（闸门就测不到了）。用 pump() 只
    // 渲染一帧，时间几乎不推进（同 mistake_book_page_test P0 #3 手法）。
    await t.tap(find.text('存入错题本'));
    await t.pump();
    expect(MistakeBook.instance.entries, hasLength(1),
        reason: '点加入后 MistakeBook 增 1 条');

    // 500ms debounce 窗口内不应已调（验证确实是 debounce 队列，非同步调）
    expect(organizeCalls, 0,
        reason: '500ms debounce 窗口内不应调 organizeSingle');

    // advance past 500ms debounce → AI 整理入队被触发（拍题入口同款）
    await t.pump(const Duration(milliseconds: 600));
    await t.pumpAndSettle();
    expect(organizeCalls, 1,
        reason: '拍题加错题后 AI 整理入队，sender 被调 1 次');

    // AI 结果写回 entry.aiSummary（入队链路完整走通）
    final refreshed =
        MistakeBook.instance.findById(MistakeBook.instance.entries.single.id);
    expect(refreshed?.aiSummary, 'AI 自动归类：豌豆 AaBb 自交 F2 9331 比例',
        reason: 'AI 整理结果写回 entry.aiSummary');
    expect(refreshed?.aiPitfalls, ['避坑 1'],
        reason: 'AI 整理 pitfalls 写回 entry.aiPitfalls');

    // 清场：等 in-flight 队列完成 + SnackBar dismiss + 落盘
    await MistakeBook.instance.debugWaitAiOrganizeDone();
    await t.pumpAndSettle();
    await t.pump(const Duration(seconds: 5));
    await t.pumpAndSettle();
    MistakeBook.debugOrganizeSender = null;
    MistakeBook.instance.debugResetAiOrganize();
    MistakeBook.instance.debugFlushSave();
  });

  // ═══ v2.13 R4-1 P0：老师角色守卫（一票否决修复本体） ═══
  // 背景：拍题对话框在老师模式下也呈现，但 dashboard 老师视图按
  // studentOnly 过滤隐藏错题本——老师写入 = 数据进不可见错题本 +
  // AI 整理照跑耗额度写不可见条目。守卫：老师点「存入错题本」→
  // SnackBar 说明 + 不写入（方案 A，与 supervisor 对齐）。
  testWidgets('R4-1 P0 老师角色点「存入错题本」→ 不写入 + 守卫 SnackBar', (t) async {
    await FirstRunStore.instance.setRole(UserRole.teacher);
    await completeScan(t);
    expect(MistakeBook.instance.entries, isEmpty,
        reason: '老师视角下起始错题本为空');

    await t.tap(find.text('存入错题本'));
    await t.pumpAndSettle();

    expect(MistakeBook.instance.entries, isEmpty,
        reason: '老师点「存入错题本」不写入学生错题本（不可见数据零产生）');
    expect(MistakeBook.instance.trash, isEmpty,
        reason: '也没有软删除痕迹（根本没 add）');
    expect(find.text('老师模式下错题本对学生可见；如需收藏请切学生模式'),
        findsOneWidget, reason: '守卫 SnackBar 文案（提示切学生模式）');
    expect(find.text('已加入错题本'), findsNothing,
        reason: '不弹「已加入错题本」——没写入，也没有 Undo 语义');
  });

  testWidgets('R4-1 P0 学生角色点「存入错题本」→ 正常写入（守卫不误伤）', (t) async {
    await FirstRunStore.instance.setRole(UserRole.student);
    await completeScan(t);

    await t.tap(find.text('存入错题本'));
    await t.pumpAndSettle();

    expect(MistakeBook.instance.entries, hasLength(1),
        reason: '学生角色正常写入（守卫只拦老师）');
    expect(find.text('已加入错题本'), findsOneWidget,
        reason: '学生照常弹「已加入错题本 [撤销]」');
    expect(find.textContaining('老师模式'), findsNothing,
        reason: '学生不弹老师守卫 SnackBar');
    MistakeBook.instance.debugFlushSave();
  });
}
