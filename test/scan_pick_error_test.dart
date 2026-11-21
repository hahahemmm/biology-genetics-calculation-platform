// scan_pick_error_test.dart —— 拍题对话框异常路径守护（v2.11 M6）
//
// 守护 _pick() 的 3 个分支：
// 1. 选图抛异常（平台插件不可用）→ SnackBar 提示 + dialog 不闪退
// 2. 选图返 null（用户取消）→ 不 attachScanImage（保持现状）
// 3. 选图正常 → attachScanImage + sendScan 触发（保持现状）
import 'dart:typed_data';

import 'package:biology/services/ai_client.dart';
import 'package:biology/ui/ai_chat_controller.dart';
import 'package:biology/ui/image_pick.dart';
import 'package:biology/ui/module_fill.dart';
import 'package:biology/ui/scan_upload_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(() {
    AiChatController.instance.reset();
    ModuleFillBus.resetForTest();
  });

  tearDown(() {
    AiChatController.instance.debugScanSender = null;
    AiChatController.instance.reset();
    ModuleFillBus.resetForTest();
  });

  Future<void> pumpDialog(WidgetTester tester,
      {Future<PickedImage?> Function()? picker}) async {
    final builderKey = GlobalKey();
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          key: builderKey,
          builder: (ctx) => Center(
            child: ElevatedButton(
              onPressed: () => showScanUploadDialog(ctx, picker: picker),
              child: const Text('OPEN'),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('OPEN'));
    await tester.pumpAndSettle();
  }

  testWidgets('M6: 选图抛异常 → SnackBar 提示 + dialog 不闪退',
      (tester) async {
    await pumpDialog(tester, picker: () async {
      throw Exception('platform image picker not available');
    });

    // dialog 仍可见
    expect(find.text('拍题识别'), findsOneWidget);
    // 触发选图
    await tester.tap(find.text('选择题目图片'));
    await tester.pumpAndSettle();

    // dialog 仍可见（"拍题识别"标题在）+ SnackBar 显示
    expect(find.text('拍题识别'), findsOneWidget);
    expect(find.byType(SnackBar), findsOneWidget);
    expect(find.textContaining('选图失败'), findsOneWidget);
  });

  testWidgets('M6: 选图返 null（用户取消）→ 不 attachScanImage',
      (tester) async {
    await pumpDialog(tester, picker: () async => null);
    expect(find.text('拍题识别'), findsOneWidget);

    await tester.tap(find.text('选择题目图片'));
    await tester.pumpAndSettle();

    // 用户取消：dialog 应仍在（让用户重试），不应触发 sendScan
    expect(AiChatController.instance.busy, isFalse);
    expect(AiChatController.instance.lastScan, isNull);
    expect(find.text('拍题识别'), findsOneWidget);
  });

  testWidgets('M6: 选图正常 → 触发 sendScan + 按钮变 "再拍一题"',
      (tester) async {
    // 注入合法 PickedImage + debugScanSender 防止真实网络
    AiChatController.instance.debugScanSender = (req) async {
      return const AiResult.ok(
          '{"summary":"测试总结","module":"other","params":{},"actions":[]}');
    };

    await pumpDialog(tester, picker: () async {
      return PickedImage(
          Uint8List.fromList([1, 2, 3]), 'test.png', 'png');
    });

    expect(find.text('拍题识别'), findsOneWidget);

    await tester.tap(find.text('选择题目图片'));
    await tester.pumpAndSettle();

    // 识别完成 → 按钮文案变 "再拍一题"
    expect(find.text('再拍一题'), findsOneWidget);
  });
}
