// assistant_panel_test.dart —— AI 助手面板：思维链默认展开 + 用户偏好
//
// v2.12.0+2 hotfix：思维链（thinking/scratchpad）默认从折叠改为展开。
// 老师 + 学生 persona UX 共识：学生需要看到解题过程、老师需要看到
// AI 推理路径。
//
// 覆盖：
//   1. 默认行为：思维链默认展开（reasoning 内容可见）
//   2. 用户偏好：勾「下次不展开」→ AppState.thinkingChainExpandedDefault
//      变 false + 当前面板立即收起
//   3. 持久化：setter 写盘 → 新 AppState 实例 load() 读回偏好
//   4. AppState 字段契约：默认 true / 重复 setter 幂等

import 'dart:io';

import 'package:biology/state/app_state.dart';
import 'package:biology/ui/ai_chat_controller.dart';
import 'package:biology/ui/assistant_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory tmp;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('assistant_panel_test');
    AppState.debugFilePath = '${tmp.path}/app_state.json';
    AppState.debugWebStorage = null;
    AppState.debugForceIsWebStorage = null;
    AppState.instance.debugResetPrefs();
    // AI 面板会用到的全局 controller 也 reset，避免历史消息污染
    AiChatController.instance.reset();
  });

  tearDown(() {
    AppState.debugFilePath = null;
    AppState.debugWebStorage = null;
    AppState.debugForceIsWebStorage = null;
    AppState.instance.debugResetPrefs();
    AiChatController.instance.reset();
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  // ── 工具：与 ai_assistant_test.dart 同构的 fixture ─────────────

  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  Future<void> openPanel(
    WidgetTester tester, {
    String? reasoning,
  }) async {
    if (reasoning != null) {
      AiChatController.instance.messages.add(AiChatMessage(
        'assistant',
        'AI 输出（不随思维链折叠）',
        reasoning: reasoning,
      ));
      AiChatController.instance.notifyListeners();
    }
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (ctx) => TextButton(
            onPressed: () => showAiAssistant(ctx),
            child: const Text('打开AI'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('打开AI'));
    await settle(tester);
  }

  // ── AppState 字段契约 ──────────────────────────────────────────

  group('AppState 字段契约', () {
    test('默认 thinkingChainExpandedDefault = true', () {
      AppState.instance.debugResetPrefs();
      expect(AppState.instance.thinkingChainExpandedDefault, isTrue,
          reason: 'v2.12.0+2 默认展开（老师 + 学生 persona 共识）');
    });

    test('setter 写内存 + notifyListeners', () async {
      var notified = 0;
      AppState.instance.addListener(() => notified++);
      await AppState.instance.setThinkingChainExpandedDefault(false);
      expect(AppState.instance.thinkingChainExpandedDefault, isFalse);
      expect(notified, 1, reason: 'setter 应触发 1 次 notifyListeners');
      AppState.instance.removeListener(() {});
    });

    test('setter 重复写同值不触发 notifyListeners（幂等）', () async {
      // 已经是 true，再 set true 应静默
      var notified = 0;
      AppState.instance.addListener(() => notified++);
      await AppState.instance.setThinkingChainExpandedDefault(true);
      expect(notified, 0, reason: '值未变不通知');
      await AppState.instance.setThinkingChainExpandedDefault(false);
      expect(notified, 1, reason: 'true→false 通知 1 次');
      await AppState.instance.setThinkingChainExpandedDefault(false);
      expect(notified, 1, reason: 'false→false 不通知');
    });
  });

  // ── 持久化（File + Web localStorage） ──────────────────────────

  group('AppState 持久化', () {
    test('setter 写盘：File 路径可被新实例 load 读回', () async {
      // 写：instance 1 写 false
      await AppState.instance.setThinkingChainExpandedDefault(false);
      // 强制等异步 fire-and-forget 落盘
      await testerRunAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 30));
      });

      // 文件应已生成
      final file = File(AppState.debugFilePath!);
      expect(file.existsSync(), isTrue, reason: 'setter 应落盘');
      final raw = file.readAsStringSync();
      expect(raw, contains('"thinkingChainExpandedDefault":false'),
          reason: '落盘 JSON 含 false');

      // 读：reset 后 load 应读回 false
      AppState.instance.debugResetPrefs();
      expect(AppState.instance.thinkingChainExpandedDefault, isTrue,
          reason: 'reset 后回到默认 true');
      await AppState.instance.load();
      expect(AppState.instance.thinkingChainExpandedDefault, isFalse,
          reason: 'load 读回上次 set 的 false');
    });

    test('Web 路径：mock localStorage round-trip', () async {
      AppState.debugForceIsWebStorage = true;
      AppState.debugWebStorage = <String, String>{};

      await AppState.instance.setThinkingChainExpandedDefault(false);
      // fire-and-forget storageSet 完成
      await testerRunAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 30));
      });
      expect(AppState.debugWebStorage!['app_state_json'],
          contains('"thinkingChainExpandedDefault":false'));

      // 模拟刷新：reset + 重新 load
      AppState.instance.debugResetPrefs();
      expect(AppState.instance.thinkingChainExpandedDefault, isTrue);
      await AppState.instance.load();
      expect(AppState.instance.thinkingChainExpandedDefault, isFalse,
          reason: 'Web 端从 localStorage 读回 false');
    });

    test('损坏 JSON 容错：保持默认 true', () async {
      File(AppState.debugFilePath!).writeAsStringSync('不是JSON{{{');
      await AppState.instance.load();
      expect(AppState.instance.thinkingChainExpandedDefault, isTrue,
          reason: '损坏文件不抛错，保持默认');
    });
  });

  // ── 面板 UI 行为 ──────────────────────────────────────────────

  group('AI 助手面板：思维链默认展开（v2.12.0+2）', () {
    testWidgets('默认思维链展开：reasoning 内容直接可见', (tester) async {
      await openPanel(
        tester,
        reasoning: '1. 判断被测个体基因型\n2. 选隐性纯合子做测交',
      );
      // 思维链标题 + 展开内容都在
      expect(find.text('思维过程'), findsOneWidget);
      expect(find.textContaining('判断被测个体基因型'), findsOneWidget,
          reason: 'v2.12.0+2 默认展开，推理内容直接可见');
      // AI 输出内容始终可见（不随思维链折叠）
      expect(find.text('AI 输出（不随思维链折叠）'), findsOneWidget);
      // 「下次不展开」复选框可见
      expect(find.text('下次不展开'), findsOneWidget);
    });

    testWidgets('勾「下次不展开」→ AppState 偏好 = false + 当前面板立即收起',
        (tester) async {
      await openPanel(
        tester,
        reasoning: '判断被测个体基因型',
      );
      // 起始：reasoning 可见
      expect(find.textContaining('判断被测个体基因型'), findsOneWidget);

      // 勾上「下次不展开」
      await tester.tap(find.text('下次不展开'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      // AppState 偏好应已变 false
      expect(AppState.instance.thinkingChainExpandedDefault, isFalse,
          reason: '勾上应写入 AppState');
      // 当前面板立即收起
      expect(find.textContaining('判断被测个体基因型'), findsNothing,
          reason: '勾上后当前面板立即收起');
      // 思维链标题仍在
      expect(find.text('思维过程'), findsOneWidget);
    });

    testWidgets('「重启」后偏好持久化：File 写盘 → 新实例 load 读回',
        (tester) async {
      // 1) 第一次启动：用户勾上「下次不展开」 → 写盘
      await openPanel(
        tester,
        reasoning: '判断被测个体基因型',
      );
      await tester.tap(find.text('下次不展开'));
      await tester.pump();
      // fire-and-forget 落盘等待
      await tester.pump(const Duration(milliseconds: 50));
      // v2.12.0+2 fix（回归超时）：testWidgets 在 FakeAsync 下
      // Future.delayed 永不完成会死锁——必须用 tester.runAsync
      // 跑真异步，等 fire-and-forget 写盘落定。
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 30));
      });
      expect(File(AppState.debugFilePath!).existsSync(), isTrue,
          reason: '勾选后应已落盘');

      // 2) 模拟"重启"：reset AppState 内存（不清磁盘）
      AppState.instance.debugResetPrefs();
      expect(AppState.instance.thinkingChainExpandedDefault, isTrue,
          reason: 'reset 后默认 true（未 load）');

      // 3) 启动 load → 读回 false
      // v2.12.0+2 fix（回归超时）：load 走真实 File IO，
      // 包进 tester.runAsync 确保 FakeAsync 下正常推进。
      await tester.runAsync(() async {
        await AppState.instance.load();
      });
      expect(AppState.instance.thinkingChainExpandedDefault, isFalse,
          reason: 'load 应从磁盘读回上次保存的 false');

      // 4) 再次打开面板 → 思维链默认收起（reasoning 内容不可见）
      // 关掉旧 fixture，重开新 widget tree 模拟"重启后打开"
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await openPanel(
        tester,
        reasoning: '重启后这条 reasoning 不应展开',
      );
      expect(find.text('重启后这条 reasoning 不应展开'), findsNothing,
          reason: '偏好持久化后思维链默认收起');
    });
  });
}

// ── 工具：让 fire-and-forget 异步落盘有真时钟可跑 ────────────────

/// Flutter widget tester 内的 fire-and-forget `writeAsStringSync`
/// 实际是同步（File IO），但 AppState._persist 的 storageSet 在 Web
/// 路径是 Future。此 helper 让 tester 走真时钟跑一会儿 Future。
Future<void> testerRunAsync(Future<void> Function() cb) async {
  await cb();
}
