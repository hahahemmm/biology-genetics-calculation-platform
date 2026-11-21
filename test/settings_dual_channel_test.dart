// settings_dual_channel_test.dart —— 设置页双通道切换 P0 冒烟（v2.15 DeepSeek 化）
//
// 覆盖：
//   1. 三通道芯片渲染（DeepSeek 默认 / MiniMax 保留 / 自定义）
//   2. 点 DeepSeek 芯片 → BaseURL/模型自动回填预设（key 留空待用户填）
//   3. 点 MiniMax 芯片 → 回填 MiniMax 预设（M3.1-Flash；key 栏留空，
//      源码不含任何 key，只能由用户自填或 --dart-define 注入）
//   4. 390 窄屏（安卓小屏）渲染不溢出、无异常
// 空配置（debugConfig）注入，绝不碰真实网络与真实配置文件。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:biology/services/ai_client.dart';
import 'package:biology/pages/settings_page.dart';

void main() {
  setUp(() {
    // 空配置：页面加载走 debugConfig，不读真实 ~/.biology_app/ai_config.json
    AiSettingsStore.debugConfig =
        const AiConfig(baseUrl: '', apiKey: '', model: '');
  });

  tearDown(() {
    AiSettingsStore.debugConfig = null;
  });

  Future<void> pumpSettings(WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: SettingsPage()));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    // v2.19.30：设置页回退单列平铺——AI 节首屏直接可见，无需切分区。
  }

  testWidgets('三通道芯片渲染', (tester) async {
    await pumpSettings(tester);
    expect(find.text('DeepSeek（默认）'), findsOneWidget);
    expect(find.text('MiniMax'), findsOneWidget);
    expect(find.text('自定义'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  /// 按顺序取三个输入框（BaseURL / Key / 模型）的当前文本。
  /// 不用 widgetWithText：预设值与 hint 相同会双命中。
  List<String> fieldTexts(WidgetTester tester) => [
        for (var i = 0; i < 3; i++)
          tester.widget<TextField>(find.byType(TextField).at(i)).controller!.text,
      ];

  testWidgets('切 DeepSeek 芯片自动回填预设（key 留空待填）', (tester) async {
    await pumpSettings(tester);
    await tester.tap(find.text('DeepSeek（默认）'));
    await tester.pump();
    final t = fieldTexts(tester);
    expect(t[0], 'https://api.deepseek.com');
    expect(t[1], '', reason: 'DeepSeek 无预置 key，等用户自填');
    expect(t[2], 'deepseek-flash');
  });

  testWidgets('切 MiniMax 芯片自动回填 M3.1-Flash 预设（key 留空待填）', (tester) async {
    await pumpSettings(tester);
    await tester.tap(find.text('DeepSeek（默认）'));
    await tester.pump();
    await tester.tap(find.text('MiniMax'));
    await tester.pump();
    final t = fieldTexts(tester);
    expect(t[0], 'https://api.minimaxi.com/v1');
    // 开源版口径：源码不含 key，未注入 --dart-define 时 key 栏留空。
    expect(t[1], AiConfig.minimaxApiKeyFromEnv,
        reason: '回填值只来自编译期注入入口，未注入即空');
    // 预设模型名 = M3.1-Flash（M3 已下线，Preview 已转正）。
    expect(t[2], 'MiniMax-M3.1-Flash');
    // 提示语必须与真实行为一致：没有 key 就明确要求自填。
    expect(find.textContaining('请填入自己的 API Key'), findsOneWidget);
    expect(find.textContaining('Key 已就绪'), findsNothing);
    expect(find.text('当前使用内置通道，无需填写 Key'), findsNothing,
        reason: '开源版没有内置 key，不得再宣称免填');
  });

  testWidgets('未注入内置 key：MiniMax 通道填了自备 key 也不给「恢复内置配置」',
      (tester) async {
    // 开源构建没有 --dart-define 注入值。回归：此时横幅曾谎称「内置通道」，
    // 而点「恢复内置配置」会用空值覆盖用户自填的 key（清成空串）。
    AiConfig.debugResetKeyHooks();
    await pumpSettings(tester);
    await tester.tap(find.text('MiniMax'));
    await tester.pump();
    await tester.enterText(find.byType(TextField).at(1), 'sk-user-own-key');
    // 再点一次芯片触发 setState：输入框变化本身不会重建整页。
    await tester.tap(find.text('MiniMax'));
    await tester.pump();
    expect(fieldTexts(tester)[1], 'sk-user-own-key', reason: '自备 key 不得被清掉');
    expect(find.text('恢复内置配置'), findsNothing,
        reason: '没有注入值就没有可恢复的内置配置');
    expect(find.text('当前使用内置通道，无需填写 Key'), findsNothing);
  });

  testWidgets('390 窄屏渲染不溢出', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await pumpSettings(tester);
    // 滚动到底部确认全部内容可布局（溢出会在 pump 时抛异常）
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -600));
    await tester.pump();
    expect(find.text('保存配置'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
