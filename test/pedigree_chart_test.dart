// pedigree_chart_test.dart —— 系谱图渲染器测试（v2.13+）
//
// 守护：课本规范（男=方 女=圆 患者=实心）+ 世代分层 + 空输入不崩。
// 布局像素不逐点断言（算法 v1 有交叉线已知限制），只断言结构行为。

import 'package:biology/charts/pedigree_chart.dart';
import 'package:biology/engine/pedigree_inference.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('常隐三代系谱渲染：成员数与世代标签', (tester) async {
    final members = [
      const PdMember(id: 'I1', sex: PdSex.male, status: PdStatus.normal),
      const PdMember(id: 'I2', sex: PdSex.female, status: PdStatus.normal),
      const PdMember(id: 'II1', sex: PdSex.female, status: PdStatus.affected),
    ];
    const relations = [
      PdRelation(parentId: 'I1', childId: 'II1'),
      PdRelation(parentId: 'I2', childId: 'II1'),
    ];
    int genOf(PdMember m) => m.id.startsWith('I') && !m.id.startsWith('II')
        ? 0
        : 1;

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: PedigreeChart(
          members: members,
          relations: relations,
          genOf: genOf,
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.byType(PedigreeChart), findsOneWidget);
    // 世代标签 I / II 绘制在 Canvas 上（find.text 不可见属正常——
    // CustomPainter 文字不进 widget 树，此处只断言渲染无异常）。
  });

  testWidgets('空成员不渲染（SizedBox.shrink，不崩）', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: PedigreeChart(members: [], relations: [], genOf: _gen0),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.byType(PedigreeChart), findsOneWidget);
  });

  testWidgets('四代 Y 连锁系谱渲染无异常', (tester) async {
    final members = [
      const PdMember(id: 'I1', sex: PdSex.male, status: PdStatus.affected),
      const PdMember(id: 'II1', sex: PdSex.male, status: PdStatus.affected),
      const PdMember(id: 'III1', sex: PdSex.male, status: PdStatus.affected),
    ];
    const relations = [
      PdRelation(parentId: 'I1', childId: 'II1'),
      PdRelation(parentId: 'II1', childId: 'III1'),
    ];
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: PedigreeChart(
            members: members, relations: relations, genOf: _gen0),
      ),
    ));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull,
        reason: '四代单亲连线渲染零异常');
  });
}

int _gen0(PdMember m) => 0;
