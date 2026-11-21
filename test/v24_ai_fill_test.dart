// v24_ai_fill_test.dart —— AI 读题填参（v2.4 功能 1）
import 'package:biology/pages/cross_calculator_page.dart';
import 'package:biology/ui/ai_fill_params.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('parseParamsFromReply', () {
    test('纯 JSON / 带前后缀文字 / 无 JSON', () {
      expect(parseParamsFromReply('{"p1":"AaBb","p2":"aabb"}'),
          {'p1': 'AaBb', 'p2': 'aabb'});
      expect(parseParamsFromReply('参数如下：{"p1":"Aa","p2":"Aa"} 完毕'),
          {'p1': 'Aa', 'p2': 'Aa'});
      expect(parseParamsFromReply('没有结构化内容'), isNull);
      expect(parseParamsFromReply('{broken'), isNull);
    });
  });

  testWidgets('9331 页有「读题填参」入口，对话框可开可关', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: CrossCalculatorPage()));
    await tester.pump();
    await tester.tap(find.text('读题填参'));
    await tester.pump();
    expect(find.text('AI 读题填参'), findsOneWidget);
    expect(find.text('提取并填入'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pump();
    expect(find.text('AI 读题填参'), findsNothing);
  });

  testWidgets('假提取器注入：提取参数回灌 onApply 并关对话框', (tester) async {
    var applied = false;
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (ctx) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () => showAiFillParams(
                ctx,
                moduleHint: 'test',
                extractor: (t) async => {'p1': 'AaBb', 'p2': 'aabb'},
                onApply: (params) {
                  applied = true;
                  expect(params['p1'], 'AaBb');
                  expect(params['p2'], 'aabb');
                },
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ));
    await tester.pump();
    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.enterText(find.byType(TextField), '测交题题干');
    await tester.tap(find.text('提取并填入'));
    await tester.pump();
    await tester.pump();
    expect(applied, isTrue, reason: '提取成功回灌 onApply');
    expect(find.text('AI 读题填参'), findsNothing, reason: '成功后对话框关闭');
  });
}
