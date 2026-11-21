// cross_tab_sweep_test.dart —— v2.19.23 9331 七 tab 宽屏巡检 + 自由交配
// 面板重建回归（找茬 P0#1）。
//
// 动机：找茬报告 P3#7——9331 非默认 tab 的宽屏 rail 面板零专项覆盖；
// P0#1——自由交配增删行/预设只 setState tab 内部，宽屏 rail 副本停旧
// 快照（显示旧行、输入写进已 dispose 的 controller）。本测试：
//   ① 7 个 tab 宽屏逐个切：零渲染溢出 + 左栏注入各 tab 输入面板；
//   ② 自由交配点预设 → 断言 rail 面板重建（出现预设的新行）。

import 'package:biology/pages/cross_calculator_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('9331：7 tab 宽屏遍历零溢出 + 左栏注入', (tester) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const MaterialApp(home: CrossCalculatorPage()));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull, reason: '首帧无溢出');

    const tabs = [
      '双基因 9331',
      '三对基因',
      '单基因杂交',
      '伴性遗传',
      '方法对比',
      '连锁互换',
      '自由交配',
    ];
    const markers = [
      '两对等位基因共 4 个字符', // 双基因 sidePanel caption
      '三对等位基因共 6 个字符', // 三对 sidePanel caption
      '设定亲本与遗传模式', // 单基因 sidePanel 标题
      'Y 染色体上无对应等位基因', // 伴性 sidePanel 说明
      '开始对比', // 方法对比计算按钮（宽屏仅 rail 有）
      '计算子代', // 连锁计算按钮
      '设定群体构成', // 自由交配 sidePanel
    ];

    for (var i = 0; i < tabs.length; i++) {
      await tester.tap(find.text(tabs[i]));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull,
          reason: 'tab「${tabs[i]}」激活帧无溢出');
      expect(find.textContaining(markers[i]), findsWidgets,
          reason: 'tab「${tabs[i]}」左栏应注入其输入面板');
    }
  });

  testWidgets('自由交配：点预设后宽屏左栏面板必须重建（P0#1 回归）',
      (tester) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const MaterialApp(home: CrossCalculatorPage()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('自由交配'));
    await tester.pumpAndSettle();
    // 初始仅 Aa/1 一行。
    expect(find.text('1/3'), findsNothing, reason: '初始无 1/3 行');

    // 点预设：面板结构变化（dispose 旧行 + 换新行 + panelRevision++）。
    await tester.tap(find.text('1/3 AA + 2/3 Aa'));
    await tester.pumpAndSettle();

    // v2.19.23 修复：ValueListenableBuilder 让 rail 随 panelRevision 重建。
    // 修复前 rail 停在旧快照（Aa/1），此处必然失败。
    expect(find.text('1/3'), findsWidgets,
        reason: '预设后左栏 rail 必须出现 1/3 行（面板已重建）');
    expect(find.text('2/3'), findsWidgets, reason: '预设第二行 2/3');
    expect(tester.takeException(), isNull);
  });
}
