// ai_assistant_test.dart —— R17 问AI 面板测试
//
// 覆盖：
//  - parseAiSuggestions：AI 刷新的格式解析（干净 JSON / 代码块 / 夹带文字 /
//    超 3 条截断 / 垃圾输入）
//  - AiChatStore：历史存取回环 / 100 条封顶 / 损坏文件容错
//  - 面板 widget：历史恢复、清空历史、建议栏 3 条 + 双刷新按钮、本地刷新

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:biology/services/ai_client.dart';
import 'package:biology/pages/settings_page.dart'
    show AiChatStore, AiSettingsStore;
import 'package:biology/ui/ai_chat_controller.dart';
import 'package:biology/ui/assistant_panel.dart';

void main() {
  late Directory tmp;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('ai_panel_test');
    AiChatStore.debugFilePath = '${tmp.path}/ai_chat_history.json';
    // 空配置：send / AI 刷新走「未配置」分支，绝不碰真实网络
    AiSettingsStore.debugConfig =
        const AiConfig(baseUrl: '', apiKey: '', model: '');
    AiChatController.instance.reset();
  });

  tearDown(() {
    AiChatStore.debugFilePath = null;
    AiSettingsStore.debugConfig = null;
    AiChatController.instance.reset();
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  group('parseAiSuggestions（AI 刷新格式解析）', () {
    test('干净 JSON 数组', () {
      expect(parseAiSuggestions('["问题一","问题二","问题三"]'),
          ['问题一', '问题二', '问题三']);
    });
    test('代码块包裹 / 夹带解释文字都能解析', () {
      expect(parseAiSuggestions('```json\n["a","b"]\n```'), ['a', 'b']);
      expect(parseAiSuggestions('好的，以下是建议：["x","y"] 希望有帮助'),
          ['x', 'y']);
    });
    test('超过 3 条截断、空条丢弃、超长截到 40 字', () {
      final long = '超' * 50;
      expect(parseAiSuggestions('["1","2","3","4","5"]'), ['1', '2', '3']);
      expect(parseAiSuggestions('["","  ","a"]'), ['a']);
      expect(parseAiSuggestions('["$long"]').single.length, 40);
    });
    test('垃圾输入 / 非数组 / 非字符串元素 → 空列表', () {
      expect(parseAiSuggestions('完全没有数组'), isEmpty);
      expect(parseAiSuggestions('{"a":1}'), isEmpty);
      expect(parseAiSuggestions('[1,2,3]'), ['1', '2', '3']); // 数字转字符串
      expect(parseAiSuggestions('["a", null, "b"]'), ['a', 'b']);
    });
  });

  group('AiChatStore（历史持久化）', () {
    test('存取回环', () async {
      await AiChatStore.save([
        {'role': 'user', 'text': '你好'},
        {'role': 'assistant', 'text': '你好！'},
      ]);
      final loaded = await AiChatStore.load();
      expect(loaded.length, 2);
      expect(loaded[0]['text'], '你好');
      expect(loaded[1]['role'], 'assistant');
    });

    test('超过 100 条只保留最近 100 条', () async {
      await AiChatStore.save([
        for (var i = 0; i < 130; i++) {'role': 'user', 'text': '第$i条'},
      ]);
      final loaded = await AiChatStore.load();
      expect(loaded.length, 100);
      expect(loaded.first['text'], '第30条');
      expect(loaded.last['text'], '第129条');
    });

    test('文件不存在 / 损坏 / 结构不对 → 空列表', () async {
      expect(await AiChatStore.load(), isEmpty);
      File(AiChatStore.debugFilePath!).writeAsStringSync('不是JSON{{{');
      expect(await AiChatStore.load(), isEmpty);
      File(AiChatStore.debugFilePath!).writeAsStringSync('{"a":1}');
      expect(await AiChatStore.load(), isEmpty);
      File(AiChatStore.debugFilePath!)
          .writeAsStringSync('[{"role":"user"},{"role":"user","text":"ok"}]');
      expect((await AiChatStore.load()).single['text'], 'ok', reason: '缺字段条目被丢弃');
    });
  });

  group('问AI 面板（widget）', () {
    // 注意：面板有常驻呼吸动画（repeat），pumpAndSettle 永不 settle，
    // 一律用定长 pump（开/关面板动画 300ms，给 400ms 余量）。
    Future<void> settle(WidgetTester tester) async {
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
    }

    Future<void> openPanel(WidgetTester tester) async {
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

    testWidgets('历史恢复：重开面板消息还在，清空后删除', (tester) async {
      await AiChatStore.save([
        {'role': 'user', 'text': '什么是测交'},
        {'role': 'assistant', 'text': '测交是与隐性纯合子杂交'},
      ]);
      await openPanel(tester);
      expect(find.text('什么是测交'), findsOneWidget);
      expect(find.text('测交是与隐性纯合子杂交'), findsOneWidget);

      // 关闭再开：历史还在
      await tester.tap(find.byTooltip('关闭'));
      await settle(tester);
      await tester.tap(find.text('打开AI'));
      await settle(tester);
      expect(find.text('什么是测交'), findsOneWidget, reason: '历史应持久化');

      // 清空历史（有确认框）
      await tester.tap(find.byTooltip('清空历史'));
      await settle(tester);
      expect(find.text('清空聊天记录？'), findsOneWidget);
      await tester.tap(find.text('清空'));
      await settle(tester);
      expect(find.text('什么是测交'), findsNothing);
      expect(await AiChatStore.load(), isEmpty);
    });

    testWidgets('表格渲染：Markdown 管道表格 → 真 Table（表头 teal 高亮）',
        (tester) async {
      await AiChatStore.save([
        {
          'role': 'assistant',
          'text': '三种交配方式对比：\n'
              '| 交配方式 | 用途 | 后代比例 |\n'
              '|---|---|---|\n'
              '| 自交 | 纯合鉴定 | 3:1 |\n'
              '| 测交 | 基因型鉴定 | 1:1 |',
        },
      ]);
      await openPanel(tester);
      expect(find.byType(Table), findsOneWidget,
          reason: '管道表格渲染成真表格而非竖线原文');
      expect(find.text('交配方式'), findsOneWidget, reason: '表头单元格');
      expect(find.text('基因型鉴定'), findsOneWidget, reason: '正文单元格');
      // 非表格段落仍在。
      expect(find.textContaining('三种交配方式对比'), findsOneWidget);
    });

    testWidgets('建议栏常驻：3 条 + 本地/AI 双刷新按钮', (tester) async {
      await openPanel(tester);
      expect(find.text('猜你想问'), findsOneWidget);
      expect(find.byTooltip('本地刷新（内置题库）'), findsOneWidget);
      expect(find.byTooltip('AI 刷新（按当前页面内容推荐）'), findsOneWidget);
      // 初始 3 条建议全部来自内置题库
      final chips = find.descendant(
          of: find.byType(InkWell), matching: find.byType(Text));
      final texts = tester
          .widgetList<Text>(chips)
          .map((t) => t.data)
          .whereType<String>()
          .where(localQuestionBank.contains)
          .toList();
      expect(texts.length, 3, reason: '建议栏应展示 3 条题库建议');

      // 本地刷新：仍是 3 条、仍全部来自题库
      await tester.tap(find.byTooltip('本地刷新（内置题库）'));
      await tester.pump();
      final after = tester
          .widgetList<Text>(chips)
          .map((t) => t.data)
          .whereType<String>()
          .where(localQuestionBank.contains)
          .toList();
      expect(after.length, 3);
    });

    testWidgets('未配置时点建议问题 → 提示去设置页（不走网络）', (tester) async {
      await openPanel(tester);
      final first = tester
          .widgetList<Text>(find.descendant(
              of: find.byType(InkWell), matching: find.byType(Text)))
          .map((t) => t.data)
          .whereType<String>()
          .firstWhere(localQuestionBank.contains);
      await tester.tap(find.text(first));
      await tester.pump();
      expect(find.textContaining('尚未配置 AI 接口'), findsOneWidget);
    });

    testWidgets('R22 关闭面板不打断请求；重开继续显示；打断按钮中止', (tester) async {
      final c = AiChatController.instance;
      // 模拟进行中的回答（会话是全局的，面板只是视图）
      c.busy = true;
      c.busyLabel = '正在回答…';
      c.messages.add(const AiChatMessage('user', '什么是测交'));
      c.notifyListeners();

      await openPanel(tester);
      expect(find.byTooltip('打断'), findsOneWidget,
          reason: '进行中应显示打断按钮');

      // 关闭面板 → 请求不能因此中断
      await tester.tap(find.byTooltip('关闭'));
      await settle(tester);
      expect(c.busy, isTrue, reason: '关闭面板不应中断 AI 请求');

      // 重开面板 → 仍显示进行中状态 + 打断可用
      await tester.tap(find.text('打开AI'));
      await settle(tester);
      expect(find.byTooltip('打断'), findsOneWidget,
          reason: '重开面板后进行中状态仍在，可打断');

      // 点打断（无活动连接时立即结束忙碌状态）→ 不再 busy
      await tester.tap(find.byTooltip('打断'));
      await tester.pump();
      expect(c.busy, isFalse, reason: '点打断后请求被中止');
    });

    testWidgets('R22 思维链默认展开（v2.12.0+2），输出内容不折叠', (tester) async {
      final c = AiChatController.instance;
      c.messages.add(const AiChatMessage(
          'assistant',
          '测交是与隐形纯合子杂交。',
          reasoning: '1. 判断被测个体基因型\n2. 选隐性纯合子做测交\n3. 看后代比例'));
      c.notifyListeners();
      await openPanel(tester);

      // 输出内容直接可见
      expect(find.text('测交是与隐形纯合子杂交。'), findsOneWidget);
      // 思维链标题可见，且默认展开（明细直接可见）
      expect(find.text('思维过程'), findsOneWidget);
      expect(find.textContaining('判断被测个体基因型'), findsOneWidget,
          reason: 'v2.12.0+2 思维链默认展开');
      // 点标题收起思维链 → 明细隐藏；输出仍在（折叠只影响思考过程）
      await tester.tap(find.text('思维过程'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.textContaining('判断被测个体基因型'), findsNothing,
          reason: '点标题可收起思维链');
      expect(find.text('测交是与隐形纯合子杂交。'), findsOneWidget,
          reason: '收起思维链不应折叠输出内容');
    });

    testWidgets('R23 排队发送：回答中发送变打断、回车样排队按钮入队',
        (tester) async {
      final c = AiChatController.instance;
      c.busy = true;
      c.busyLabel = '正在回答…';
      c.notifyListeners();
      await openPanel(tester);

      // 主按钮=打断；回车样排队按钮出现；无发送箭头
      expect(find.byTooltip('打断'), findsOneWidget,
          reason: '回答中主按钮变打断');
      expect(find.byTooltip('排队发送（AI 完成后自动发送）'), findsOneWidget,
          reason: '回答中新增回车样排队按钮');
      expect(find.byIcon(Icons.arrow_upward), findsNothing,
          reason: '回答中不应再有发送箭头');

      // 排两条：输入框清空、队列上浮
      final field = find.byType(TextField);
      await tester.enterText(field, '第一个问题');
      await tester.tap(find.byTooltip('排队发送（AI 完成后自动发送）'));
      await tester.pump();
      await tester.enterText(field, '第二个问题');
      await tester.tap(find.byTooltip('排队发送（AI 完成后自动发送）'));
      await tester.pump();
      expect(c.queue, ['第一个问题', '第二个问题']);
      expect(find.textContaining('1. 第一个问题'), findsOneWidget,
          reason: '排队消息应上浮一格显示');

      // 请求完成 → 自动逐条发送（未配置分支也 drain）
      c.busy = false;
      await c.send('直接问的');
      await tester.pump();
      expect(c.queue, isEmpty, reason: '完成后队列自动逐条发送');
      expect(
          c.messages.any(
              (m) => m.role == 'user' && m.text == '第一个问题'),
          isTrue,
          reason: '排队第一条应已发送');
      expect(
          c.messages.any(
              (m) => m.role == 'user' && m.text == '第二个问题'),
          isTrue,
          reason: '排队第二条也应已发送');
    });
  });
}
