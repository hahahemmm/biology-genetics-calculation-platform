// v28_whiteboard_test.dart —— v2.8 白板教鞭适配批次
//
// 覆盖：
//   1. 单基因 tab 高考高频预设 chips（白板免键盘，点一下直接开算）
//   2. 放映内嵌聚光灯（讲课核心闭环：全屏呈现 → 点哪亮哪聚焦）
// 聚光灯对象化（点按/拖动/边缘调大小/hover 不跟随）的回归在
// present_mode_test.dart 已更新覆盖。

import 'package:biology/pages/cross_calculator_page.dart';
import 'package:biology/pages/settings_page.dart';
import 'package:biology/services/ai_client.dart';
import 'package:biology/pages/widgets/spotlight_layer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    AiSettingsStore.debugConfig = AiConfig.presetMinimax;
  });
  tearDown(() {
    AiSettingsStore.debugConfig = null;
  });

  testWidgets('单基因 tab 预设：显性纯合致死 → 2:1', (t) async {
    t.view.physicalSize = const Size(1600, 5000);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);
    await t.pumpWidget(const MaterialApp(home: CrossCalculatorPage()));
    await t.pump();
    // 切到单基因 tab
    await t.tap(find.text('单基因杂交'));
    await t.pumpAndSettle();
    // 预设 chip 一键开算
    await t.tap(find.text('显性纯合致死 2:1'));
    await t.pumpAndSettle();
    expect(find.textContaining('2:1', findRichText: true), findsWidgets);
  });

  testWidgets('单基因 tab 预设：测交 1:1 与不完全显性 1:2:1', (t) async {
    t.view.physicalSize = const Size(1600, 5000);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);
    await t.pumpWidget(const MaterialApp(home: CrossCalculatorPage()));
    await t.pump();
    await t.tap(find.text('单基因杂交'));
    await t.pumpAndSettle();
    await t.tap(find.text('不完全显性 1:2:1'));
    await t.pumpAndSettle();
    expect(find.textContaining('1:2:1', findRichText: true), findsWidgets);
  });

  testWidgets('放映内嵌聚光灯：开 → 拖动亮区 → 关', (t) async {
    t.view.physicalSize = const Size(1920, 1080);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);
    await t.pumpWidget(const MaterialApp(home: CrossCalculatorPage()));
    await t.pump();
    // 计算 + 板书 + 放映
    await t.tap(find.text('杂合自交 9331'));
    await t.pumpAndSettle();
    await t.tap(find.text('板书'));
    await t.pumpAndSettle();
    await t.tap(find.text('放映'));
    await t.pumpAndSettle();
    // 聚光灯按钮存在，开启后 SpotlightLayer 激活
    expect(find.byTooltip('聚光灯：点哪亮哪，拖边缘调大小'), findsOneWidget);
    await t.tap(find.byTooltip('聚光灯：点哪亮哪，拖边缘调大小'));
    await t.pumpAndSettle();
    final spot = find.byType(SpotlightLayer);
    expect(testerWidgetActive(t, spot), isTrue);
    // 亮区圆心内按住拖动 → 亮区移动（手指真实轨迹）
    final st = t.state<SpotlightLayerState>(spot);
    final layerC = t.getCenter(spot);
    await t.dragFrom(layerC, const Offset(100, 60));
    await t.pump();
    expect(st.debugCenter, isNotNull, reason: '放映内亮区可拖动');
    // 关闭聚光灯
    await t.tap(find.byTooltip('关闭聚光灯'));
    await t.pumpAndSettle();
    expect(testerWidgetActive(t, spot), isFalse);
  });
}

bool testerWidgetActive(WidgetTester t, Finder spot) =>
    t.widget<SpotlightLayer>(spot).active;
