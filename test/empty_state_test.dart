// 空态不是空白：全模块体验官回归。

import 'package:biology/pages/genetic_disease_page.dart';
import 'package:biology/pages/variation_page.dart';
import 'package:biology/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> pump(WidgetTester tester, Widget page) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(theme: AppTheme.light(), home: page));
    await tester.pumpAndSettle();
  }

  testWidgets('变异默认页给出模拟步骤与结果位置', (tester) async {
    await pump(tester, const VariationPage());
    expect(find.text('等待模拟：结果将在这里展开'), findsOneWidget);
    expect(find.textContaining('选择替换、插入或缺失后点「模拟突变」'), findsOneWidget);
  });

  testWidgets('遗传咨询默认页给出计算步骤与结果位置', (tester) async {
    await pump(tester, const GeneticDiseasePage());
    expect(find.text('等待咨询计算：结果将在这里展开'), findsOneWidget);
    expect(find.textContaining('这里依次展开亲本配子、子代基因型'), findsOneWidget);
  });
}
