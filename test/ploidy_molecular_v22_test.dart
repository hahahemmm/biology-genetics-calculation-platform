// ploidy_molecular_v22_test.dart —— v2.2 批次3：新计算模块页面 P0 冒烟
//
// 覆盖：
//   1. PloidyPage：渲染 + 五个计算按钮逐一触发（组数形态法/基因型法/
//      倍性判定/单倍体育种/四倍体配子），结果出现、无异常（P0 崩溃巡检）
//   2. MolecularPage 新区块：单链比值 / 两链 CT 互推 / 标记计算 /
//      有丝分裂标记逐一触发
//   3. 390 窄屏渲染不溢出
// debugConfig 空配置注入：「问 AI」不会碰真实网络。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:biology/services/ai_client.dart';
import 'package:biology/pages/molecular_page.dart';
import 'package:biology/pages/ploidy_page.dart';
import 'package:biology/pages/settings_page.dart' show AiSettingsStore;
import 'package:biology/ui/ai_chat_controller.dart';

void main() {
  setUp(() {
    AiSettingsStore.debugConfig =
        const AiConfig(baseUrl: '', apiKey: '', model: '');
    AiChatController.instance.reset();
  });

  tearDown(() {
    AiSettingsStore.debugConfig = null;
    AiChatController.instance.reset();
  });

  Future<void> tapAndSettle(WidgetTester tester, String label) async {
    await tester.tap(find.text(label).first);
    await tester.pump();
    expect(tester.takeException(), isNull, reason: '点击「$label」不应崩溃');
  }

  /// 长列表页：先把目标按钮滚进视口再点。
  /// 坑：ListView 是 sliver 懒挂载，屏外子节点不在 element 树里；
  /// scrollUntilVisible 必须传「可为空」的 finder（不能 .first，
  /// FirstFinder 在空匹配时会直接抛 Bad state 中断滚动）。
  Future<void> scrollTap(WidgetTester tester, String label) async {
    await tester.scrollUntilVisible(find.text(label), 200,
        scrollable: find.byType(Scrollable).first);
    await tester.pump();
    await tapAndSettle(tester, label);
  }

  /// v2.19.21 工作台化：顶部 TabBar 切 tab（目标 tab 懒构建后才可交互）。
  Future<void> switchTab(WidgetTester tester, String label) async {
    await tester.tap(find.text(label));
    await tester.pumpAndSettle();
  }

  testWidgets('PloidyPage 五模块全流程', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: PloidyPage()));
    await tester.pump();
    expect(find.text('染色体倍性'), findsOneWidget);

    // Tab0 组数判断（默认挂载）
    await scrollTap(tester, '计算组数');
    expect(find.text('2 个'), findsWidgets); // 8÷4=2 组

    await scrollTap(tester, '按基因型判断');
    expect(find.text('3 个'), findsWidgets); // AaaBBb→3 组

    // Tab1 倍性与育性
    await switchTab(tester, '倍性与育性');
    await scrollTap(tester, '判定倍性');
    expect(find.textContaining('三倍体'), findsWidgets); // 3 组受精卵

    // 批次5 扩展：三倍体无子西瓜（四倍体母本默认 → 胚3组/胚乳5组/果皮4组）
    await scrollTap(tester, '推导三倍体果实');
    expect(find.textContaining('胚=3 组'), findsOneWidget);
    expect(find.textContaining('胚乳=5 组'), findsOneWidget);
    expect(find.textContaining('果皮（子房壁）=4 组'), findsOneWidget);

    // Tab2 育种应用
    await switchTab(tester, '育种应用');
    await scrollTap(tester, '列出花粉与加倍结果');
    expect(find.textContaining('AABB'), findsOneWidget);

    await scrollTap(tester, '计算配子比例');
    expect(find.textContaining('1 : 4 : 1'), findsOneWidget);
  });

  testWidgets('MolecularPage 批次3 新区块全流程', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: MolecularPage()));
    await tester.pump();
    expect(find.text('分子遗传'), findsOneWidget);

    // Tab0 碱基组成（默认挂载）
    await scrollTap(tester, '按 (A+G)/(T+C) 算');
    expect(find.text('2.500'), findsOneWidget); // 0.4 → 2.5

    await scrollTap(tester, '计算全分子碱基');
    // 批次4a：结果并入 StepChain 节点，formula 为 'A=45　T=45　…' 单行
    expect(find.textContaining('A=45'), findsOneWidget); // A=T=45
    expect(find.textContaining('碱基总数 140 个'), findsOneWidget);

    // Tab1 复制与标记
    await switchTab(tester, '复制与标记');
    await scrollTap(tester, '计算标记分布');
    expect(find.textContaining('8 个'), findsWidgets); // 2^3=8

    await scrollTap(tester, '第 2 次分裂');
    expect(find.textContaining('0 ~ 20'), findsOneWidget);
  });

  testWidgets('390 窄屏：两页渲染不溢出', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const MaterialApp(home: PloidyPage()));
    await tester.pump();
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -2000));
    await tester.pump();
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const MaterialApp(home: MolecularPage()));
    await tester.pump();
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -3000));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}
