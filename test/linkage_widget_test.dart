// test/linkage_widget_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:biology/engine/linkage_engine.dart';
import 'package:biology/pages/widgets/linkage_widgets.dart';

void main() {
  testWidgets('公共连锁组件可渲染（配子表 + 表型卡）', (tester) async {
    final r = LinkageEngine().cross('AB/ab', 'ab/ab', '1/5');
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: Column(children: [
            LinkageGameteTable(result: r),
            LinkagePhenotypeCard(result: r),
          ]),
        ),
      ),
    ));
    expect(find.text('亲本 1（AB/ab）'), findsOneWidget);
    expect(find.text('表型整数比'), findsOneWidget);
    expect(find.text('4 : 4 : 1 : 1'), findsOneWidget);
    expect(linkagePresets.length, 5, reason: '经典案例数不变');
  });
}