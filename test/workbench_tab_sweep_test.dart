// workbench_tab_sweep_test.dart —— v2.19.23 宽屏逐 tab 遍历零溢出巡检
//
// 动机：找茬报告 P2#3（倍性 SegmentedButton 窄栏换行/分子横排字段标签
// 裁切）之所以逃过 961 全绿，是因为 golden 宽屏只截默认 tab、窄屏用例
// 不触发宽屏分支——非默认 tab 的 rail 布局零覆盖。本测试把三页全部
// tab 在宽屏（1600）逐个切一遍，断言零渲染溢出 + 各 tab 左栏注入成功。

import 'package:biology/pages/evolution_page.dart';
import 'package:biology/pages/molecular_page.dart';
import 'package:biology/pages/ploidy_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> sweep(WidgetTester tester, Widget page, List<String> tabs,
      List<String> railMarkers) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(MaterialApp(home: page));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull, reason: '首帧无溢出');

    for (var i = 0; i < tabs.length; i++) {
      await tester.tap(find.text(tabs[i]));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull,
          reason: 'tab「${tabs[i]}」激活帧无溢出');
      expect(find.textContaining(railMarkers[i]), findsWidgets,
          reason: 'tab「${tabs[i]}」应注入含「${railMarkers[i]}」的输入面板');
    }
  }

  testWidgets('分子页：4 tab 宽屏遍历零溢出 + 左栏跟随', (tester) async {
    await sweep(
      tester,
      const MolecularPage(),
      ['碱基组成', '复制与标记', '基因表达', '配子种类'],
      ['计算碱基组成', '计算标记分布', '推出各链', '计算配子种类'],
    );
  });

  testWidgets('进化页：6 tab 宽屏遍历零溢出 + 左栏跟随', (tester) async {
    await sweep(
      tester,
      const EvolutionPage(),
      ['进化树', '基因频率', '遗传平衡', '选择模拟', '进化理论', '种群增长'],
      ['时间轴自上而下', '计算基因频率', '预测下一代', '开始模拟', '知识速览', '计算种群增长'],
    );
  });

  testWidgets('倍性页：3 tab 宽屏遍历零溢出 + 左栏跟随', (tester) async {
    await sweep(
      tester,
      const PloidyPage(),
      ['组数判断', '倍性与育性', '育种应用'],
      ['计算组数', '判定倍性', '计算配子比例'],
    );
  });
}
