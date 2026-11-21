// v210_scan_dialog_test.dart —— v2.10 拍题识别独立入口
//
// 覆盖：对话框打开 → 选图（picker 注入）→ 识别结果展示 → 填入路由；
// 问 AI 面板不再有上传题目按钮（入口分离实锤）；主 FAB 区两个按钮都在。

import 'dart:io';
import 'dart:typed_data';

import 'package:biology/services/ai_client.dart';
import 'package:biology/state/scan_bank_store.dart';
import 'package:biology/main.dart';
import 'package:biology/pages/settings_page.dart';
import 'package:biology/state/first_run_store.dart';
import 'package:biology/state/present_mode_controller.dart';
import 'package:biology/state/theme_controller.dart';
import 'package:biology/ui/ai_chat_controller.dart';
import 'package:biology/ui/assistant_panel.dart';
import 'package:biology/ui/file_drop_bus.dart';
import 'package:biology/ui/image_pick.dart';
import 'package:biology/ui/module_fill.dart';
import 'package:biology/ui/scan_upload_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmp;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('v210_test');
    // 密封化（main_test.dart 同款）：FirstRunStore 注入临时 first_run.json，
    // 防止首启角色弹窗 / 读到本机真实角色态。
    FirstRunStore.debugFilePath = '${tmp.path}/first_run.json';
    FirstRunStore.debugWebStorage = null;
    FirstRunStore.debugForceIsWebStorage = false;
    FirstRunStore.instance.debugReset();
    File(FirstRunStore.debugFilePath!)
        .writeAsStringSync('{"role":"student"}');
    ScanBankStore.debugFilePath = '${tmp.path}/scan_bank.json';
    AiChatStore.debugFilePath = '${tmp.path}/ai_chat_history.json';
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
    // 课堂态复位：debugSetEnabled(false) 防跨用例串态（load 早退后
    // _enabled 残留为上一个用例注入值）。
    PresentModeController.instance.debugSetEnabled(false);
    ModuleFillBus.resetForTest();
    FileDropBus.instance.resetForTest();
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  const scanJson =
      '{"summary":"豌豆杂交","module":"cross_dihybrid","params":{"p1":"AaBb","p2":"AaBb"}}';

  testWidgets('拍题对话框：选图 → 识别 → 结果展示 → 填入跳转', (t) async {
    AiSettingsStore.debugConfig = AiConfig.presetMinimax;
    AiChatController.instance.debugScanSender =
        (msgs) async => const AiResult.ok(scanJson);
    final navLog = <int>[];
    ModuleFillBus.navigator = navLog.add;
    ModuleFillBus.register(ModuleFillTarget(
      moduleId: 'cross_dihybrid',
      pageIndex: 2,
      label: '遗传计算器·双基因',
      apply: (p) => p['p1'] == 'AaBb',
    ));

    t.view.physicalSize = const Size(1400, 900);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);
    await t.pumpWidget(MaterialApp(
      home: Builder(
        builder: (ctx) => Scaffold(
          body: TextButton(
            onPressed: () => showScanUploadDialog(
              ctx,
              picker: () async =>
                  PickedImage(Uint8List.fromList([1, 2, 3]), 't.png', 'png'),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    ));
    await t.tap(find.text('open'));
    await t.pumpAndSettle();
    expect(find.text('拍题识别'), findsOneWidget);

    // 选图（注入 picker）→ 识别
    await t.tap(find.text('选择题目图片'));
    await t.pumpAndSettle();
    // 结果展示
    expect(find.textContaining('豌豆杂交'), findsWidgets);
    expect(find.textContaining('识别为：遗传计算器·双基因'), findsOneWidget);
    expect(find.text('填入遗传计算器·双基因'), findsOneWidget);

    // 填入 → 跳页 + 对话框关闭
    await t.tap(find.text('填入遗传计算器·双基因'));
    await t.pumpAndSettle();
    expect(navLog, [2]);
    expect(find.text('拍题识别'), findsNothing);
  });

  testWidgets('Wave2 拖图入窗：initialImage 开框即识别（不点选图按钮）', (t) async {
    AiSettingsStore.debugConfig = AiConfig.presetMinimax;
    AiChatController.instance.debugScanSender =
        (msgs) async => const AiResult.ok(scanJson);

    await t.pumpWidget(MaterialApp(
      home: Builder(
        builder: (ctx) => Scaffold(
          body: TextButton(
            // picker 传抛异常的假实现：若 initialImage 路径退化为点按钮
            // 选图会闪退——证明本用例走的是拖拽直投链路。
            onPressed: () => showScanUploadDialog(
              ctx,
              picker: () async => throw Exception('should not pick'),
              initialImage: PickedImage(
                  Uint8List.fromList([1, 2, 3]), 'drop.png', 'png'),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    ));
    await t.tap(find.text('open'));
    await t.pumpAndSettle();

    // 没点「选择题目图片」，识别结果直接渲染（按钮已变「再拍一题」）。
    expect(find.text('再拍一题'), findsOneWidget);
    expect(find.textContaining('豌豆杂交'), findsWidgets);
    // 对话框 mounted 期间是 FileDropBus 活跃消费者（HomeShell 兜底
    // 因此不开第二个框）。
    expect(FileDropBus.instance.hasConsumer, isTrue);
  });

  testWidgets('Wave2 拖图入窗：对话框开着时 publish 新图 → 直接识别', (t) async {
    AiSettingsStore.debugConfig = AiConfig.presetMinimax;
    AiChatController.instance.debugScanSender =
        (msgs) async => const AiResult.ok(scanJson);

    await t.pumpWidget(MaterialApp(
      home: Builder(
        builder: (ctx) => Scaffold(
          body: TextButton(
            onPressed: () => showScanUploadDialog(ctx),
            child: const Text('open'),
          ),
        ),
      ),
    ));
    await t.tap(find.text('open'));
    await t.pumpAndSettle();
    expect(find.text('选择题目图片'), findsOneWidget); // 空框等图

    // 模拟原生侧拖图：HomeShell 的 initFileDrop 回调等效动作。
    FileDropBus.instance.publish(PickedImage(
        Uint8List.fromList([1, 2, 3]), 'drop2.png', 'png'));
    await t.pumpAndSettle();

    expect(find.text('再拍一题'), findsOneWidget);
    expect(find.textContaining('豌豆杂交'), findsWidgets);
    expect(FileDropBus.instance.hasConsumer, isTrue);
    // 关框后消费者注销：HomeShell 兜底恢复接管。
    await t.tap(find.text('关闭'));
    await t.pumpAndSettle();
    expect(FileDropBus.instance.hasConsumer, isFalse);
  });

  testWidgets('主 FAB 区：拍题与问 AI 两个入口并存（学生/课堂都呈现）', (t) async {
    t.view.physicalSize = const Size(1400, 900);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);
    // 密封化（main_test.dart 同款）：真实磁盘 I/O（~/.biology_app/
    // present_mode.json 可能 enabled:true——本机用户真开过课堂模式）
    // 先 runAsync 放行 load 完成，再用 debugSetEnabled(false) 覆盖为
    // 标准模式。不覆盖则 FAB tooltip 是课堂版「长按 1 秒解锁」，
    // 下方标准版 tooltip 断言找不到（load 完成后覆盖，initState 的
    // load() 因 _loaded 早退不会回读真实文件冲掉注入值）。
    await t.runAsync(() async {
      await ThemeController.instance.debugEnsureLoaded();
      await PresentModeController.instance.debugEnsureLoaded();
    });
    PresentModeController.instance.debugSetEnabled(false);
    await t.pumpWidget(const BiologyApp());
    await t.pump();
    expect(find.byTooltip('拍题识别（上传题目图片）'), findsOneWidget);
    expect(find.text('问 AI'), findsOneWidget);
    // 点拍题 FAB → 拍题对话框打开
    await t.tap(find.byTooltip('拍题识别（上传题目图片）'));
    await t.pumpAndSettle();
    expect(find.text('拍题识别'), findsOneWidget);
    expect(find.text('选择题目图片'), findsOneWidget);
  });

  testWidgets('问 AI 面板：不再有上传题目按钮（入口分离实锤）', (t) async {
    // 预置画布截图注入，跳过 showAiAssistant 里的 captureAppCanvas await
    //（FakeAsync 下 toImage future 不完成会卡住对话框打开——既有测试同手法）
    AiChatController.instance.pendingCanvasImage = 'Qk1T';
    t.view.physicalSize = const Size(1400, 900);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);
    await t.pumpWidget(MaterialApp(
      home: Builder(
        builder: (ctx) => Scaffold(
          body: TextButton(
            onPressed: () => showAiAssistant(ctx),
            child: const Text('打开AI'),
          ),
        ),
      ),
    ));
    await t.tap(find.text('打开AI'));
    // 面板有常驻呼吸动画（_breath repeat）——pumpAndSettle 永不沉降，
    // 改用定长泵（与既有 ai_assistant_test 同手法）。
    await t.pump();
    await t.pump(const Duration(milliseconds: 400));
    expect(find.text('AI 遗传助手'), findsOneWidget);
    // 旧上传按钮已移除（该 tooltip 不存在）
    expect(find.byTooltip('上传题目图片（AI 识别并填入对应模块）'), findsNothing);
  });
}
