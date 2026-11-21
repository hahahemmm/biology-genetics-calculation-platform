// pages_ask_ai_test.dart —— 2.1 第二批：5 个工具页「问 AI」入口冒烟
//
// 覆盖：每页 AppBar「问 AI」按钮存在；点击后 queueSend 携带页面上下文
//   入队（消息带【当前工具：…】前缀）+ showAiAssistant 打开助手面板。
//   空配置（debugConfig）下 send 走「未配置」分支：面板给出配置提示、
//   绝不碰真实网络。
// 注意：AiChatController 是全局单例 —— setUp/tearDown 一律 reset，
//   历史存储注入临时路径，避免污染用户真实聊天历史。

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:biology/services/ai_client.dart';
import 'package:biology/pages/big_question_cards_page.dart';
import 'package:biology/pages/curriculum_page.dart';
import 'package:biology/pages/evolution_page.dart';
import 'package:biology/pages/genetic_disease_page.dart';
import 'package:biology/pages/molecular_page.dart';
import 'package:biology/pages/variation_page.dart';
import 'package:biology/pages/settings_page.dart'
    show AiChatStore, AiSettingsStore;
import 'package:biology/ui/ai_chat_controller.dart';

void main() {
  late Directory tmp;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('pages_ask_ai_test');
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

  // 面板有常驻呼吸动画（repeat），pumpAndSettle 永不 settle：
  // 一律定长 pump。400ms 覆盖开合动画（300ms）+ 200ms 跑完消息区
  // 滚到底动画，末尾再补一帧——长上下文（如套路卡的多行卡内容）
  // 会把回复顶出初始视口，最后那帧才懒挂载进树。
  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump();
  }

  /// 统一入口：pump 页面 → 断言「问 AI」按钮 → 点击 → 面板打开 +
  /// 上下文已入队（无网络）。
  Future<void> expectAskAi(
      WidgetTester tester, Widget page, String toolName) async {
    await tester.pumpWidget(MaterialApp(home: page));
    await tester.pumpAndSettle();
    expect(find.text('问 AI'), findsOneWidget,
        reason: '$toolName AppBar 应有「问 AI」按钮');
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('问 AI'));
    await settle(tester);

    // 面板打开（标题在对话框树中）。
    expect(find.text('AI 遗传助手'), findsOneWidget,
        reason: '$toolName 点击后助手面板打开');
    // 未配置分支：assistant 侧给出配置提示。注：此处断言 controller 消息
    // 而非气泡 Text——长上下文（套路卡多行卡内容）会把回复顶出初始
    // 视口，懒挂载 + 滚动画画使气泡 text 的泵帧数依赖内容长度，
    // 消息级断言等价且确定（气泡渲染本身由 ai_assistant_test 覆盖）。
    final c = AiChatController.instance;
    final queued =
        c.messages.where((m) => m.role == 'user').map((m) => m.text);
    expect(queued.any((t) => t.contains('【当前工具：$toolName】')), isTrue,
        reason: '$toolName 上下文应随 queueSend 入队');
    expect(
        c.messages
            .where((m) => m.role == 'assistant')
            .any((m) => m.text.contains('尚未配置 AI 接口')),
        isTrue,
        reason: '$toolName 空配置分支应给出配置提示');
    expect(tester.takeException(), isNull);
  }

  testWidgets('分子页问 AI：按钮 + 面板 + 上下文入队', (tester) async {
    await expectAskAi(tester, const MolecularPage(), '分子遗传计算');
  });

  testWidgets('进化页问 AI：按钮 + 面板 + 上下文入队', (tester) async {
    await expectAskAi(tester, const EvolutionPage(), '进化 · 基因频率');
  });

  testWidgets('变异页问 AI：按钮 + 面板 + 上下文入队', (tester) async {
    await expectAskAi(tester, const VariationPage(), '变异');
  });

  testWidgets('人类遗传病页问 AI：按钮 + 面板 + 上下文入队', (tester) async {
    await expectAskAi(tester, const GeneticDiseasePage(), '人类遗传病');
  });

  testWidgets('课标体系页问 AI：按钮 + 面板 + 上下文入队', (tester) async {
    await expectAskAi(tester, const CurriculumPage(), '课标体系');
  });

  // v2.19.25：大题套路卡页（主导航 index 8）的问 AI 链路。
  testWidgets('套路卡页问 AI：按钮 + 面板 + 上下文入队', (tester) async {
    await expectAskAi(tester, const BigQuestionCardsPage(), '大题套路卡');
  });
}