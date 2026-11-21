// file_drop_shell_test.dart —— Wave2 拖图入窗壳层链路补测（v2.19.67
// 代码评审「看官C 遗漏清单」取三项）。
//
// 与 file_drop_bus_test.dart（纯 Dart 单元）/ v210_scan_dialog_test.dart
// （对话框本体）互补，本文件盯 HomeShell 壳层的接线：
//   1. 兜底路径：无消费者时 publish → HomeShell 替拍题对话框开框
//      并自动识别（initialImage 链路 + _dropDialogOpening 哨兵不误伤）；
//   2. 非图片拖入：经真实 MethodChannel("biology/file_drop") 投递
//      onFiles（与 Windows runner 转发同构）→ SnackBar「拖入的不是图片」；
//   3. 识别中拖图：对话框 busy 期间 publish → SnackBar「识别中，请稍后
//      再拖」且不重复发送（v2.19.67 P2 #4 守卫）。
//
// 注入手法与 main_test.dart / v210_scan_dialog_test.dart 同款：
// FirstRunStore/ThemeController/PresentModeController debug 路径 +
// ensureLoaded；ScanBankStore/AiChatStore/AiSettingsStore debug 注入
// 防真实网络/磁盘；debugScanSender 决定识别结果。busy 态直接置
// AiChatController.instance.busy（public 字段，v2.19.67 P2 #4 裁定
// 无需 @visibleForTest 重构即可测）。

import 'dart:io';

import 'package:biology/services/ai_client.dart';
import 'package:biology/state/scan_bank_store.dart';
import 'package:biology/main.dart';
import 'package:biology/pages/settings_page.dart';
import 'package:biology/state/first_run_store.dart';
import 'package:biology/state/present_mode_controller.dart';
import 'package:biology/state/theme_controller.dart';
import 'package:biology/ui/ai_chat_controller.dart';
import 'package:biology/ui/file_drop_bus.dart';
import 'package:biology/ui/image_pick.dart';
import 'package:biology/ui/module_fill.dart';
import 'package:biology/ui/scan_upload_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const scanJson =
      '{"summary":"豌豆杂交","module":"other","params":{},"actions":[]}';

  late Directory tmp;
  late String firstRunPath;

  /// main_test.dart 同款：真实磁盘 IO 的 store 加载走 runAsync 放行。
  Future<void> ensureLoaded(WidgetTester tester) async {
    await tester.runAsync(() async {
      await ThemeController.instance.debugEnsureLoaded();
      await PresentModeController.instance.debugEnsureLoaded();
    });
  }

  /// main_test.dart 同款：写 first_run.json 避免首启角色弹窗。
  Future<void> setRole(WidgetTester tester, UserRole r) async {
    File(firstRunPath).writeAsStringSync('{"role":"${r.name}"}');
    FirstRunStore.instance.debugReset();
    await tester.runAsync(() => FirstRunStore.instance.load());
  }

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('file_drop_shell_test');
    firstRunPath = '${tmp.path}/first_run.json';
    FirstRunStore.debugFilePath = firstRunPath;
    FirstRunStore.debugWebStorage = null;
    FirstRunStore.debugForceIsWebStorage = false;
    FirstRunStore.instance.debugReset();
    if (!File(firstRunPath).existsSync()) {
      File(firstRunPath).writeAsStringSync('{"role":"student"}');
    }
    ScanBankStore.debugFilePath = '${tmp.path}/scan_bank.json';
    AiChatStore.debugFilePath = '${tmp.path}/ai_chat_history.json';
    AiSettingsStore.debugConfig = AiConfig.presetMinimax;
    AiChatController.instance.reset();
    ModuleFillBus.resetForTest();
    FileDropBus.instance.resetForTest();
  });

  tearDown(() {
    AiChatController.instance.debugScanSender = null;
    AiChatController.instance.reset();
    AiSettingsStore.debugConfig = null;
    ScanBankStore.debugFilePath = null;
    AiChatStore.debugFilePath = null;
    FirstRunStore.debugFilePath = null;
    FirstRunStore.debugWebStorage = null;
    FirstRunStore.debugForceIsWebStorage = null;
    FirstRunStore.instance.debugReset();
    PresentModeController.instance.debugSetEnabled(false);
    ModuleFillBus.resetForTest();
    FileDropBus.instance.resetForTest();
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  /// 模拟 Windows runner 的 WM_DROPFILES 转发：按原生侧同构方式经
  /// MethodChannel("biology/file_drop") 向框架投递 onFiles 消息
  /// （HomeShell initState 里 initFileDrop 注册的 handler 消费）。
  Future<void> dropFilesFromPlatform(WidgetTester tester,
      List<String> paths) async {
    final data =
        const StandardMethodCodec().encodeMethodCall(MethodCall('onFiles', paths));
    await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
        'biology/file_drop', data, (_) {});
  }

  testWidgets('1) 兜底路径：无对话框时 publish → HomeShell 开拍题框并自动识别',
      (tester) async {
    await ensureLoaded(tester);
    await setRole(tester, UserRole.student);
    AiChatController.instance.debugScanSender =
        (msgs) async => const AiResult.ok(scanJson);

    await tester.pumpWidget(const BiologyApp());
    await tester.pumpAndSettle();
    expect(find.text('拍题识别'), findsNothing, reason: '前置：无拍题对话框');

    // 模拟原生侧拖图入窗后的总线广播（HomeShell 兜底订阅消费）。
    FileDropBus.instance.publish(PickedImage(
        Uint8List.fromList([1, 2, 3]), 'drop.png', 'png'));
    await tester.pumpAndSettle();

    // 兜底开框成功：拍题对话框在场 + 已 claim（不再重复开）。
    expect(find.text('拍题识别'), findsOneWidget,
        reason: '无消费者时 HomeShell 兜底替它开框');
    expect(FileDropBus.instance.hasConsumer, isTrue,
        reason: '对话框在场期间是 FileDropBus 活跃消费者');
    // initialImage 链路：开框即识别，按钮已从「选择题目图片」变「再拍一题」。
    expect(find.text('再拍一题'), findsOneWidget,
        reason: '兜底开框带 initialImage，自动开始识别');
  });

  testWidgets('2) 非图片拖入 → SnackBar「拖入的不是图片」提示', (tester) async {
    await ensureLoaded(tester);
    await setRole(tester, UserRole.student);

    await tester.pumpWidget(const BiologyApp());
    await tester.pumpAndSettle();

    // 经真实通道投递 txt 路径（与 runner WM_DROPFILES 转发同构）。
    await dropFilesFromPlatform(tester, ['C:\\temp\\note.txt']);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.textContaining('拖入的不是图片'), findsOneWidget,
        reason: '全非图片时给 SnackBar 人话提示（拖拽无反馈 = 以为拖丢了）');
    // 未广播任何图 → 不触发兜底开框。
    expect(find.text('拍题识别'), findsNothing);
  });

  testWidgets('3) 识别中（busy）拖图 → SnackBar「识别中」+ 不重复发送',
      (tester) async {
    var sent = 0;
    AiChatController.instance.debugScanSender = (msgs) async {
      sent++;
      return const AiResult.ok(scanJson);
    };

    // 独立 pump 对话框（v210 同款手法；无需整棵 BiologyApp）。
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (ctx) => Scaffold(
          body: TextButton(
            onPressed: () => showScanUploadDialog(ctx),
            child: const Text('open'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('拍题识别'), findsOneWidget);
    expect(FileDropBus.instance.hasConsumer, isTrue);

    // 直接置 busy（public 字段）：模拟识别进行中。
    AiChatController.instance.busy = true;
    await tester.pump(); // rebuild 出 spinner（无限动画，不可 pumpAndSettle）

    FileDropBus.instance.publish(PickedImage(
        Uint8List.fromList([9]), 'busy-drop.png', 'png'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // 丢帧有反馈：SnackBar 提示识别中（v2.19.67 P2 #4）。
    expect(find.text('识别中，请稍后再拖'), findsOneWidget,
        reason: 'busy 分支丢帧必须给 SnackBar 反馈，不能静默吞图');
    // 丢帧不重发：识别请求计数为 0（busy 期间新图不得排队进 _send）。
    expect(sent, 0, reason: 'busy 期间拖图不触发第二次识别请求');

    // 收尾：复位 busy，避免 tearDown reset 前的 spinner 动画悬挂。
    AiChatController.instance.busy = false;
    await tester.pump();
  });
}
