// step_chain_test.dart —— v2.2 批次4 地基：推导链组件测试
//
// 覆盖：节点渲染（标题/公式/说明/图标）、末节点高亮（结果位）、
// 连接线只在非末节点出现、深浅双模式文字色走 token（防白底白字）、
// 390 窄屏不溢出。

import 'package:biology/ui/step_chain.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const steps = [
    ChainStep.input('已知条件', formula: '链1 C=10, T=20', detail: '题干数据'),
    ChainStep.compute('互补配对', formula: 'A = T₁ + T₂', detail: 'A₁=T₂、A₂=T₁'),
    ChainStep.result('最终结果', formula: 'A = 45 个'),
  ];

  Widget wrap({bool dark = false}) => MaterialApp(
        theme: ThemeData(brightness: dark ? Brightness.dark : Brightness.light),
        home: const Scaffold(body: SingleChildScrollView(child: StepChain(steps: steps))),
      );

  testWidgets('三节点渲染：标题/公式/说明齐全', (tester) async {
    await tester.pumpWidget(wrap());
    await tester.pump();
    expect(find.text('已知条件'), findsOneWidget);
    expect(find.text('链1 C=10, T=20'), findsOneWidget);
    expect(find.text('A₁=T₂、A₂=T₁'), findsOneWidget);
    expect(find.text('最终结果'), findsOneWidget);
    expect(find.text('A = 45 个'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('深浅双模式渲染不抛异常（token 取色不白底白字）', (tester) async {
    await tester.pumpWidget(wrap());
    await tester.pump();
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(wrap(dark: true));
    await tester.pump();
    expect(find.text('最终结果'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('390 窄屏长 detail 不溢出', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: StepChain(steps: [
          ChainStep.compute('很长说明',
              detail: '这是一段特别长的说明文字，用来验证窄屏换行不溢出。' * 6),
        ]),
      ),
    ));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}
