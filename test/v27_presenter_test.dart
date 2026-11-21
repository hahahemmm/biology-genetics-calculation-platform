// v27_presenter_test.dart —— v2.7 通用放映壳
//
// 覆盖：showWidgetPresenter / showImagePresenter 两个入口的打开与关闭；
// 板书放映迁移到通用壳后的回归由既有 v26_board_presenter_test 覆盖。

import 'dart:typed_data';

import 'package:biology/ui/presenter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// 1x1 PNG bytes（image 包编码）
  Uint8List tinyPng() =>
      Uint8List.fromList(img.encodePng(img.Image(width: 1, height: 1)));

  Widget host(WidgetBuilder onOpen) => MaterialApp(
        home: Scaffold(
          body: Builder(builder: onOpen),
        ),
      );

  testWidgets('showWidgetPresenter：打开 → 内容可见 → 关闭退出', (t) async {
    await t.pumpWidget(host((ctx) => TextButton(
          onPressed: () =>
              showWidgetPresenter(ctx, child: const Text('放映内容')),
          child: const Text('open'),
        )));
    await t.tap(find.text('open'));
    await t.pumpAndSettle();
    expect(find.text('放映内容'), findsOneWidget);
    expect(find.byTooltip('退出放映'), findsOneWidget);
    await t.tap(find.byTooltip('退出放映'));
    await t.pumpAndSettle();
    expect(find.text('放映内容'), findsNothing);
  });

  testWidgets('showImagePresenter：位图放映打开与退出', (t) async {
    await t.pumpWidget(host((ctx) => TextButton(
          onPressed: () => showImagePresenter(ctx, pngBytes: tinyPng()),
          child: const Text('open'),
        )));
    await t.tap(find.text('open'));
    await t.pumpAndSettle();
    expect(find.byType(Image), findsOneWidget);
    expect(find.byTooltip('退出放映'), findsOneWidget);
    await t.tap(find.byTooltip('退出放映'));
    await t.pumpAndSettle();
    expect(find.byTooltip('退出放映'), findsNothing);
  });
}
