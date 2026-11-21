// workbench_rail_test.dart —— v2.19.22 工作台左栏刷新回归
//
// 覆盖两类「输入面板卡掉」事故：
//   1. 9331 容器页 _currentSidePanel() 漏 case 6（自由交配实现了
//      CrossTabSidePanel 但容器页 switch 无分支、tab 无 key）——
//      切到自由交配 tab 左栏输入面板永远为空；
//   2. ToolWorkbench 骨架 StatelessWidget 形态下切 tab 只有
//      TabBarView 子树 rebuild，宽屏左栏（rail）是骨架 build 输出的
//      兄弟分支不刷新——左栏停在上一个 tab 的输入面板。

import 'package:biology/pages/cross_calculator_page.dart';
import 'package:biology/pages/molecular_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('9331 宽屏：切到自由交配 tab 左栏注入其输入面板', (tester) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const MaterialApp(home: CrossCalculatorPage()));
    await tester.pumpAndSettle();
    // 首帧后容器页 postFrame setState，双基因输入面板就位。
    expect(find.text('亲本 1'), findsWidgets, reason: 'tab0 左栏应有亲本输入');

    await tester.tap(find.text('自由交配'));
    await tester.pumpAndSettle();
    expect(find.text('设定群体构成'), findsOneWidget,
        reason: 'v2.19.22 修复：自由交配 tab 的 sidePanel 必须注入左栏');
    expect(find.text('亲本 1'), findsNothing,
        reason: '左栏不应残留上一个 tab 的输入面板');

    await tester.tap(find.text('双基因 9331'));
    await tester.pumpAndSettle();
    expect(find.text('亲本 1'), findsWidgets,
        reason: '切回 tab0 左栏恢复亲本输入');
  });

  testWidgets('ToolWorkbench 宽屏：切 tab 后左栏输入面板跟随刷新', (tester) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const MaterialApp(home: MolecularPage()));
    await tester.pumpAndSettle();
    expect(find.text('计算碱基组成'), findsOneWidget,
        reason: 'tab0 碱基组成的计算按钮在左栏');

    await tester.tap(find.text('复制与标记'));
    await tester.pumpAndSettle();
    expect(find.text('计算复制结果'), findsOneWidget,
        reason: 'v2.19.22 修复：切 tab 后左栏必须换成新 tab 的输入面板');
    expect(find.text('计算碱基组成'), findsNothing,
        reason: '左栏不应残留上一个 tab 的计算按钮');
  });
}
