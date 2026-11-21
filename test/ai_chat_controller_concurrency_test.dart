// ai_chat_controller_concurrency_test.dart —— v2.11 H5 单例 client 并发守门测试
//
// 修复前：send/refreshSuggestions/sendScan 三处都 `final client = AiClient(config);
// _client = client;` 直接覆盖，旧 client 不被 interrupt → AI 回答中点
// 刷新 = 两条消息都到 messages 列表，顺序错乱。
//
// 修复后：
//   - send() 入口加 busy/refreshing 守门，busy 中再 send → 入 queue
//   - refreshSuggestions() 入口加 busy/refreshing 守门，busy 中再 refresh → 静默忽略
//   - sendScan() 已有守门，sender 闭包内加防御性 interrupt
//
// 验证：
//   1. send 进行中再 send → 第二条入 queue 不丢消息
//   2. send 完成 → _drainQueue 自动从 queue 取下一条 send
//   3. busy 中点 refresh → 静默忽略（refreshing 仍为 false）
//   4. send 启动前 _client 已被覆盖 → 新 client 创建前先 interrupt 旧 client

import 'dart:async';

import 'package:biology/services/ai_client.dart';
import 'package:biology/pages/settings_page.dart' show AiSettingsStore;
import 'package:biology/ui/ai_chat_controller.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('v2.11 H5：AiChatController._client 单例并发守门', () {
    setUp(() {
      AiChatController.instance.reset();
      // 注入测试配置（不读盘，避免污染用户目录）
      AiSettingsStore.debugConfig = const AiConfig(
        baseUrl: 'https://test.example.com/v1',
        apiKey: 'test-key',
        model: 'test-model',
      );
    });

    tearDown(() {
      AiChatController.instance.debugSender = null;
      AiSettingsStore.debugConfig = null;
    });

    testWidgets('send 进行中再 send → 第二条进 queue 不丢消息', (tester) async {
      // 可控的 sender：让 q1 挂起，q2 自动 send 时再决定
      final completers = <Completer<AiResult>>[];
      AiChatController.instance.debugSender = (msgs) {
        final c = Completer<AiResult>();
        completers.add(c);
        return c.future;
      };

      final ctrl = AiChatController.instance;

      // 1. 启动 send('q1')，不 await 让它后台跑
      unawaited(ctrl.send('q1'));
      // 让异步切到 busy
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(ctrl.busy, isTrue, reason: 'send 启动后 busy=true');
      expect(completers, hasLength(1), reason: 'q1 已发起一次 sender');
      expect(ctrl.queue, isEmpty, reason: 'q1 是首发，不入队');

      // 2. 第二条 send：应入 queue
      ctrl.send('q2');
      expect(ctrl.queue, contains('q2'),
          reason: 'busy 中再 send → 第二条进 queue 不丢');
      expect(ctrl.busy, isTrue, reason: 'q1 仍在跑，busy 不变');
      // q2 没发起新 sender（仅入队）
      expect(completers, hasLength(1),
          reason: 'q2 只是入队，未发起新网络请求');

      // 3. 释放 q1 → 完成后 _drainQueue 应自动 send('q2')
      completers[0].complete(const AiResult.ok('a1'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(ctrl.busy, isTrue, reason: 'q2 应自动接上 send，仍 busy');
      expect(completers, hasLength(2), reason: 'q2 已自动 send');
      expect(ctrl.queue, isEmpty, reason: 'q2 已从 queue 取出');

      // 4. 释放 q2，结束
      completers[1].complete(const AiResult.ok('a2'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(ctrl.busy, isFalse, reason: 'q2 完成后 busy=false');
      // 5. 消息顺序：user q1 → assistant a1 → user q2 → assistant a2
      expect(ctrl.messages.map((m) => m.text).toList(),
          ['q1', 'a1', 'q2', 'a2'],
          reason: '消息按 q1/a1/q2/a2 顺序追加，无错位');
    });

    testWidgets('busy 中点 refresh → 静默忽略', (tester) async {
      final completer = Completer<AiResult>();
      AiChatController.instance.debugSender = (msgs) => completer.future;

      final ctrl = AiChatController.instance;
      unawaited(ctrl.send('q1'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(ctrl.busy, isTrue);

      // busy 中 refresh 应静默忽略
      await ctrl.refreshSuggestions();
      expect(ctrl.refreshing, isFalse,
          reason: 'busy 中 refresh → 静默忽略，refreshing 不变');
      expect(ctrl.busy, isTrue, reason: 'q1 仍在跑');

      // 释放 q1 收尾
      completer.complete(const AiResult.ok('a1'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
    });

    testWidgets('refreshing 中再点 refresh → 静默忽略', (tester) async {
      final refreshCompleter = Completer<AiResult>();
      var callCount = 0;
      AiChatController.instance.debugSender = (msgs) {
        callCount++;
        return refreshCompleter.future;
      };

      final ctrl = AiChatController.instance;

      // 启动 refresh
      unawaited(ctrl.refreshSuggestions());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(ctrl.refreshing, isTrue);
      expect(callCount, 1);

      // refreshing 中再 refresh 应静默忽略
      await ctrl.refreshSuggestions();
      expect(callCount, 1,
          reason: 'refreshing 中再 refresh → 不发起新网络请求');

      // 释放收尾
      refreshCompleter.complete(const AiResult.ok('[]'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
    });

    // 注：防御性 _client?.interrupt() 路径（"send 启动覆盖 _client 之前
    // 先 interrupt 旧 client"）需要更深的 mock 设计——debugSender 注入
    // 后完全替换 sender 闭包，闭包内的 _client 赋值也被替换。生产代码中
    // 走默认 sender 时会执行该赋值 + interrupt，正常用户行为已被前 3
    // 个测试覆盖（busy 中再 send/refresh 静默忽略，不丢消息）。
  });
}
