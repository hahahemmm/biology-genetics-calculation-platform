// history_lecture_note_test.dart —— v2.19.62 历史卡「AI 讲题稿」守卫网
//
// ## 这条网守什么
// 「课堂讲题回放」卡（老师工具页，长在 dashboard_page.dart 的 _TeacherPage）
// 里，每条**可复核**的历史条目（引擎计算类、detail 带结构化参数快照）多了
// 一枚「讲题稿」入口：点它 ⇒ AiChatController 队列收到一段讲题提示词
// + 助手面板打开，老师照稿投影。
//
// ## 断言分组
//   L1 可复核条目 ⇒ 「讲题稿」入口在屏；点 ⇒ 队列收到含题干关键词的待发消息
//      （S5/cards_step_selftest 同款「busy 排队 + 定长 pump」手法）
//   L2 不可复核条目（自由交配：detail 空串）⇒ 入口**不渲染**（不是点了才提示）
//   L3 historyEntryLectureable 单测：边界字段逐个钉（判据口径见下）
//   L4 屏上文案卫生：入口 label / tooltip / 卡上文案 零星号零方向词
//
// ## 判据口径（与 dashboard_page.dart 的 historyEntryLectureable 注释同源）
//   可复核 ⇔ detail 能 jsonDecode 成 JSON 对象且同时有非 null 的
//   `m`（引擎模块 id）与 `p1`（亲本基因型快照）。系谱条目（纯文本
//   detail）/ 自由交配（空 detail）/ 非 JSON / JSON 数组 / JSON 标量
//   ⇒ 不可复核。
//
// ## 诚实记账
// ① 入口落在**老师工具页**的「课堂讲题回放」卡（_TeacherPage），不是首页
//    dashboard 网格——本仓库唯一的 HistoryEntry 列表卡就在那里，首页 p00
//    golden 结构上不含历史卡（见汇报）。
// ② 讲稿落盘 / 批量生成 / 课堂模式自动投影讲稿 = 首轮明确不做，故无断言。
// ③ 未做「面板里真的出讲稿正文」的端到端断言：通道为空配置（不碰真实网络，
//    与 pages_ask_ai_test 同口径），只钉到「队列里躺着正确的提示词」这一环。

import 'dart:convert';
import 'dart:io';

import 'package:biology/services/ai_client.dart';
import 'package:biology/pages/dashboard_page.dart';
import 'package:biology/pages/settings_page.dart'
    show AiChatStore, AiSettingsStore;
import 'package:biology/state/first_run_store.dart';
import 'package:biology/state/history_store.dart';
import 'package:biology/state/mistake_book.dart';
import 'package:biology/ui/ai_chat_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// ⛔ 方向词黑名单（与 cards_step_selftest / cards_page_alt_l 同款，一个字不放宽）。
const List<String> _kBannedDirWords = <String>[
  '上面', '下面', '上边', '下边', '左边', '右边', //
  '左侧', '右侧', '上方', '下方', '上一行', '下一行',
];

/// 入口文案（label）+ tooltip——两处都得卫生。
const String _kEntryLabel = '讲题稿';
const String _kEntryTooltip = 'AI 讲题稿';

/// 可复核样例：计算器双基因条目（真机上 cross_calculator_page 的落盘形状）。
HistoryEntry _lectureableEntry({int epochMs = 1700000000000}) => HistoryEntry(
      label: 'AaBb × AaBb · 双基因 9331 · 表型 9:3:3:1',
      epochMs: epochMs,
      detail: jsonEncode(
          <String, dynamic>{'m': 'cross_dihybrid', 'p1': 'AaBb', 'p2': 'AaBb'}),
    );

/// 不可复核样例：自由交配条目（真机上 random_mating_tab 落盘 detail = 空串）。
HistoryEntry _plainEntry({int epochMs = 1700000000001}) => HistoryEntry(
      label: '自由交配（3 个基因型）· F1 基因型比 1:2:1',
      epochMs: epochMs,
      detail: '',
    );

void main() {
  late Directory tmp;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('history_lecture_note');
    HistoryStore.debugFilePath = '${tmp.path}/history.json';
    // 老师工具卡只在老师角色下可见（进卡的前置条件）。
    FirstRunStore.debugFilePath = '${tmp.path}/first_run.json';
    FirstRunStore.debugWebStorage = null;
    FirstRunStore.debugForceIsWebStorage = false;
    FirstRunStore.instance.debugReset();
    // 板书历史目录隔离（_TeacherPage._load 会建目录并 listSync）。
    DashboardPage.debugBoardHistoryDirForTest = '${tmp.path}/board_history';
    // 错题本隔离（_TeacherPage 预载 MistakeBook.instance.load()）。
    MistakeBook.debugFilePath = '${tmp.path}/mistakes.json';
    MistakeBook.debugTrashFilePath = '${tmp.path}/mistakes.trash.json';
    MistakeBook.instance.debugReset();
    // AI 通道隔离：空配置 ⇒ 绝不碰真实网络（同 pages_ask_ai_test）。
    AiChatStore.debugFilePath = '${tmp.path}/ai_chat_history.json';
    AiSettingsStore.debugConfig =
        const AiConfig(baseUrl: '', apiKey: '', model: '');
    AiChatController.instance.reset();
  });

  tearDown(() {
    HistoryStore.debugFilePath = null;
    DashboardPage.debugBoardHistoryDirForTest = null;
    MistakeBook.instance.debugFlushSave();
    MistakeBook.instance.debugReset();
    MistakeBook.debugFilePath = null;
    MistakeBook.debugTrashFilePath = null;
    FirstRunStore.instance.debugReset();
    FirstRunStore.debugFilePath = null;
    FirstRunStore.debugWebStorage = null;
    AiChatStore.debugFilePath = null;
    AiSettingsStore.debugConfig = null;
    AiChatController.instance.reset();
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  /// 首页（老师角色）→ 点「老师工具」→ 老师工具页（含讲题回放卡）。
  Future<void> pumpTeacherPage(WidgetTester tester,
      {Size size = const Size(1200, 1400)}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await FirstRunStore.instance.setRole(UserRole.teacher);
    await tester.pumpWidget(
        MaterialApp(home: DashboardPage(onOpenTool: (_) {})));
    await tester.pumpAndSettle();
    await tester.tap(find.text('老师工具'));
    await tester.pumpAndSettle();
  }

  /// 把某条历史滚进视口（ListView 懒构建）。
  Future<void> scrollTo(WidgetTester tester, String label) async {
    await tester.scrollUntilVisible(find.textContaining(label), 200,
        scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();
  }

  // ══════════════════════════════════════════════════════════════════
  //  L1. 可复核条目 ⇒ 入口在屏；点 ⇒ 队列收到含题干关键词的待发消息
  // ══════════════════════════════════════════════════════════════════
  testWidgets('L1·可复核条目：入口在屏，点后队列收到带题干与结果的讲题提示词',
      (tester) async {
    await HistoryStore.save([_lectureableEntry()]);
    await pumpTeacherPage(tester);
    await scrollTo(tester, 'AaBb × AaBb · 双基因 9331');

    // 入口在屏（前提成立才有意义）。
    expect(find.text(_kEntryLabel), findsOneWidget,
        reason: '可复核条目应渲染「$_kEntryLabel」入口');
    expect(find.byIcon(Icons.menu_book_outlined), findsOneWidget,
        reason: '入口图标应是同族 menu_book_outlined');

    // ⛔ 让 queueSend 走**排队**分支（空闲时会当场 send，队列看不到）：
    // 与 ai_chat_controller_concurrency_test / cards_step_selftest S5 同款。
    final ctrl = AiChatController.instance;
    ctrl.busy = true;

    await tester.tap(find.text(_kEntryLabel));
    // ⛔ 助手面板有常驻呼吸动画（repeat），pumpAndSettle 永不 settle
    // ⇒ 定长 pump（照 cards_step_selftest S5 / pages_ask_ai_test）。
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(ctrl.queue, isNotEmpty, reason: '回答中点「$_kEntryLabel」应入队');
    final queued = ctrl.queue.join('\n');
    expect(queued, contains('AaBb'), reason: '提示词应带题干关键词（亲本基因型快照）');
    expect(queued, contains('双基因 9331'), reason: '提示词应带这道题的标签（含正确结果）');
    expect(queued, contains('讲题稿'), reason: '提示词应点明要的是讲题稿');
    expect(queued, contains('投影'), reason: '提示词应说明是投影给全班看的讲稿');
    expect(queued, contains('易'), reason: '提示词应要求指出易错点');
    expect(queued, contains('口诀'), reason: '提示词应要求给一句口诀');
    // ⛔ prompt 侧卫生：提示词里一个星号都不许有（AI 会原样回显到幕布上）。
    expect(queued.contains('*'), isFalse,
        reason: '⛔ 提示词里出现星号 ⇒ AI 会把它原样回显进讲稿');
    expect(find.text('AI 遗传助手'), findsOneWidget, reason: '助手面板应打开');
    // ⛔ 入口是独立控件，不是整行点击的别名：点「讲题稿」不许同时触发
    // ▷ 回放（回放没注册 fill 目标时会弹「该条目暂不支持复现」）。
    expect(find.text('该条目暂不支持复现'), findsNothing,
        reason: '点「讲题稿」把整行回放也触发了（入口控件没吃掉点击）');

    // 收尾：面板还开着（呼吸动画在跑），关掉再退出。
    ctrl.busy = false;
    ctrl.reset();
  });

  // ══════════════════════════════════════════════════════════════════
  //  L2. 不可复核条目 ⇒ 入口不渲染
  // ══════════════════════════════════════════════════════════════════
  testWidgets('L2·不可复核条目（detail 空串）：条目在屏但入口不渲染',
      (tester) async {
    await HistoryStore.save([_plainEntry()]);
    await pumpTeacherPage(tester);
    await scrollTo(tester, '自由交配（3 个基因型）');

    // 前提：条目本身确实渲染了（否则下面的否定断言是空断言）。
    expect(find.textContaining('自由交配（3 个基因型）'), findsOneWidget,
        reason: '前提：这条历史应在屏');
    expect(find.text('课堂讲题回放'), findsOneWidget, reason: '前提：回放卡在屏');
    // ⛔ 否定：不可复核 ⇒ 一个「讲题稿」入口都不许有。
    expect(find.text(_kEntryLabel), findsNothing,
        reason: '⛔ 没有参数快照的条目不许渲染入口（点了才说不行 = 屏上撒谎）');
    expect(find.byIcon(Icons.menu_book_outlined), findsNothing,
        reason: '入口图标也不许在屏');
    // 成对：该条也不带 ▷ 复现图标（同判据）。
    expect(find.byIcon(Icons.play_circle_outline), findsNothing);
  });

  testWidgets('L2b·混合两条：只有可复核那条长入口（不误伤邻居）',
      (tester) async {
    await HistoryStore.save([_plainEntry(), _lectureableEntry()]);
    await pumpTeacherPage(tester);
    await scrollTo(tester, 'AaBb × AaBb · 双基因 9331');

    expect(find.text(_kEntryLabel), findsOneWidget,
        reason: '两条历史里只有可复核那条有入口（恰好 1 枚）');
    expect(find.byIcon(Icons.play_circle_outline), findsOneWidget,
        reason: '▷ 与讲题稿入口同进同出');
  });

  // ══════════════════════════════════════════════════════════════════
  //  L3. historyEntryLectureable 单测：边界字段逐个钉
  // ══════════════════════════════════════════════════════════════════
  group('L3·historyEntryLectureable 判据（detail 解析 + m/p1 两键）', () {
    HistoryEntry withDetail(String detail) =>
        HistoryEntry(label: 'x', epochMs: 1, detail: detail);

    test('可复核：JSON 对象且 m / p1 都在 ⇒ true', () {
      expect(
          historyEntryLectureable(withDetail(
              jsonEncode({'m': 'cross_dihybrid', 'p1': 'AaBb', 'p2': 'AaBb'}))),
          isTrue);
      // 多余键不影响判据（p2 缺失也算——判据只钉 m / p1）。
      expect(
          historyEntryLectureable(withDetail(jsonEncode({'m': 'cross_mono', 'p1': 'Aa'}))),
          isTrue);
    });

    test('缺 m 或缺 p1 ⇒ false', () {
      expect(
          historyEntryLectureable(
              withDetail(jsonEncode({'p1': 'AaBb', 'p2': 'AaBb'}))),
          isFalse,
          reason: '没有引擎模块 id ⇒ 拼不出「哪个计算器算的」');
      expect(
          historyEntryLectureable(withDetail(jsonEncode({'m': 'cross_dihybrid'}))),
          isFalse,
          reason: '没有亲本快照 ⇒ 拼不出题干');
    });

    test('m / p1 值为 null ⇒ false（键在但空值不算快照）', () {
      expect(
          historyEntryLectureable(
              withDetail(jsonEncode({'m': null, 'p1': 'AaBb'}))),
          isFalse);
      expect(
          historyEntryLectureable(
              withDetail(jsonEncode({'m': 'cross_dihybrid', 'p1': null}))),
          isFalse);
    });

    test('非对象 / 非 JSON / 空串 ⇒ false（系谱纯文本、自由交配空 detail）', () {
      expect(historyEntryLectureable(withDetail('')), isFalse,
          reason: '自由交配条目 detail = 空串（真机口径）');
      expect(
          historyEntryLectureable(withDetail(
              '♂AABBCC × ♀aabbcc · 家族 A\nF1：AaBbCc 全显性')),
          isFalse,
          reason: '系谱条目 detail 是每代产出的纯文本');
      expect(historyEntryLectureable(withDetail('[1,2,3]')), isFalse,
          reason: 'JSON 数组不是参数快照对象');
      expect(historyEntryLectureable(withDetail('"cross_dihybrid"')), isFalse,
          reason: 'JSON 标量不是参数快照对象');
      expect(historyEntryLectureable(withDetail('{"m": cross')), isFalse,
          reason: '非法 JSON 解析失败 ⇒ 不算可复核（不许抛）');
    });
  });

  // ══════════════════════════════════════════════════════════════════
  //  L4. 屏上文案卫生：入口 label / tooltip / 卡上文案 零星号零方向词
  // ══════════════════════════════════════════════════════════════════
  testWidgets('L4·入口文案卫生：零 markdown 星号 / 零方向词', (tester) async {
    await HistoryStore.save([_lectureableEntry()]);
    await pumpTeacherPage(tester);
    await scrollTo(tester, 'AaBb × AaBb · 双基因 9331');

    // 入口自己的文案（label + tooltip）。
    final expected = <String>[_kEntryLabel, _kEntryTooltip];
    for (final s in expected) {
      expect(s.contains('*'), isFalse, reason: '「$s」含 markdown 星号');
      for (final w in _kBannedDirWords) {
        expect(s.contains(w), isFalse, reason: '「$s」含方向词「$w」');
      }
    }
    expect(find.byTooltip(_kEntryTooltip), findsOneWidget,
        reason: '入口 tooltip 应是「$_kEntryTooltip」');

    // 整页没有一枚星号（讲稿会上幕布，屏上文案一个星号都不许有）。
    for (final el in tester.widgetList<Text>(find.byType(Text))) {
      final s = el.data ?? '';
      expect(s.contains('*'), isFalse, reason: '屏上文案「$s」含 markdown 星号');
    }
  });

  // ══════════════════════════════════════════════════════════════════
  //  L5. prompt 侧卫生（纯函数，免泵）：历史讲题提示词的拼装口径
  // ══════════════════════════════════════════════════════════════════
  test('L5·historyLecturePrompt：可复核出提示词 / 不可复核返 null / 零星号', () {
    final p = historyLecturePrompt(_lectureableEntry());
    expect(p, isNotNull, reason: '可复核条目必须能拼出提示词');
    expect(p, contains('AaBb'), reason: '应带亲本快照');
    expect(p, contains('AaBb × AaBb · 双基因 9331 · 表型 9:3:3:1'),
        reason: '应带标签（含正确结果）');
    expect(p, contains('投影'), reason: '应说明是投影给全班看的讲稿');
    expect(p, contains('口诀'), reason: '应要求给一句口诀');
    expect(p!.contains('*'), isFalse,
        reason: '⛔ 提示词正文不许出现星号字符（会被 AI 原样回显）');
    expect(historyLecturePrompt(_plainEntry()), isNull,
        reason: '不可复核 ⇒ 提示词为 null（按键处同判据）');
  });
}
