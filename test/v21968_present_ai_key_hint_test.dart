// v21968_present_ai_key_hint_test.dart —— v2.19.68 进入课堂大屏 AI Key 自检提醒
//
// 覆盖（P2-6 修复回归网）：
//   1. 未配置 AI（apiKey 空）→ 进入课堂大屏弹一次性 SnackBar 指路设置页；
//   2. 已配置 AI（apiKey 非空）→ 静默，零提示；
//   3. 课堂内其它 notify（聚光灯/激光笔开关）不重复触发；
//   4. 退出再进（仍未配置）→ 再次提醒（一次性 = 每次进入一条）。
//
// 配置经 AiSettingsStore.debugConfig 注入（不碰真实磁盘配置；
// v213_r13_projection_test 同款手法）。

import 'dart:io';

import 'package:biology/services/ai_client.dart';
import 'package:biology/main.dart';
import 'package:biology/pages/settings_page.dart' show AiSettingsStore;
import 'package:biology/state/first_run_store.dart';
import 'package:biology/state/present_mode_controller.dart';
import 'package:biology/state/theme_controller.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory tmp;
  late String filePath;

  const kHint = '上课前建议先在设置页配置 AI（拍题/讲题稿需要）';

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('v21968_ai_key_hint');
    filePath = '${tmp.path}/first_run.json';
    FirstRunStore.debugFilePath = filePath;
    FirstRunStore.debugWebStorage = null;
    FirstRunStore.debugForceIsWebStorage = false;
    FirstRunStore.instance.debugReset();
    File(filePath).writeAsStringSync('{"role":"teacher"}');
  });

  tearDown(() {
    FirstRunStore.debugFilePath = null;
    FirstRunStore.debugWebStorage = null;
    FirstRunStore.debugForceIsWebStorage = null;
    FirstRunStore.instance.debugReset();
    PresentModeController.instance.debugSetEnabled(false);
    PresentModeController.instance.debugSetSpotlightOn(false);
    PresentModeController.instance.debugSetLaserEnabled(false);
    AiSettingsStore.debugConfig = null;
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  Future<void> pumpShell(WidgetTester tester) async {
    await tester.runAsync(() async {
      await ThemeController.instance.debugEnsureLoaded();
      await PresentModeController.instance.debugEnsureLoaded();
    });
    PresentModeController.instance.debugSetEnabled(false);
    await tester.pumpWidget(const BiologyApp());
    await tester.pumpAndSettle();
  }

  /// 课堂开关后的泵帧纪律：**跳帧**而非 pumpAndSettle——课堂切换会让
  /// MaterialApp 重建（含 settings 页 13 页常驻的按钮样式动画），动画
  /// 中间帧（t≈0.5）会撞框架级 `TextStyle.lerp inherit 不一致` 断言
  /// （live 切换本就存在的产物；present_mode_test 用单帧 pump 同理
  /// 避开）。pump(300ms) 一步跨过 200ms 样式动画，不经过中间帧。
  Future<void> togglePresent(WidgetTester tester, bool on) async {
    PresentModeController.instance.debugSetEnabled(on);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));
  }

  testWidgets('未配置 AI：进入课堂大屏弹一次性指路 SnackBar', (tester) async {
    AiSettingsStore.debugConfig =
        const AiConfig(provider: AiConfig.providerDeepSeek, apiKey: '');
    await pumpShell(tester);
    expect(find.text(kHint), findsNothing, reason: '进入前不提前弹');

    await togglePresent(tester, true);
    expect(find.text(kHint), findsOneWidget,
        reason: '进入课堂大屏且 AI 未配置 → 一次性 SnackBar');
  });

  testWidgets('已配置 AI（apiKey 非空）：静默跳过', (tester) async {
    // v2.20.0：源码不再内置 key，AiConfig.presetMinimax 的 apiKey 为空
    // （只接 --dart-define=MINIMAX_API_KEY），不能再拿它当「已配置」夹具。
    // 这里改用一个明确带虚构 key 的夹具——本用例只验「存在 key ⇒ 静默」。
    AiSettingsStore.debugConfig = const AiConfig(
      provider: AiConfig.providerMinimax,
      baseUrl: 'https://api.minimaxi.com/v1',
      apiKey: 'sk-fake-configured-0001',
      model: 'MiniMax-M3.1-Flash-Preview',
    );
    await pumpShell(tester);
    await togglePresent(tester, true);
    expect(find.text(kHint), findsNothing,
        reason: '已配置 key → 静默（不做联网测试，只查存在性）');
  });

  testWidgets('课堂内其它 notify（聚光灯/激光笔）不重复触发；退出再进才再提醒',
      (tester) async {
    AiSettingsStore.debugConfig =
        const AiConfig(provider: AiConfig.providerDeepSeek, apiKey: '');
    await pumpShell(tester);

    await togglePresent(tester, true);
    expect(find.text(kHint), findsOneWidget);

    // 课堂内开关聚光灯/激光笔：controller notify 多次，但不是"进入"跳变
    // → 不再弹。跳帧把首条 SnackBar（4s 时长 + 进出场动画）推到消失
    // 之后（两帧：一帧走完时长 Timer，一帧走完退出动画）。
    PresentModeController.instance.debugSetSpotlightOn(true);
    PresentModeController.instance.debugSetSpotlightOn(false);
    PresentModeController.instance.debugSetLaserEnabled(true);
    PresentModeController.instance.debugSetLaserEnabled(false);
    await tester.pump(const Duration(seconds: 5));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text(kHint), findsNothing,
        reason: '提示一次性：4s 后消失且不因其它 notify 复活');

    // 退出再进（仍未配置）：再次提醒。
    await togglePresent(tester, false);
    await togglePresent(tester, true);
    expect(find.text(kHint), findsOneWidget,
        reason: '重新进入课堂大屏 → 再次自检（仍未配置则再提醒一次）');
  });
}
