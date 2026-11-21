// global_canvas_shot_test.dart —— 2.2 批次5：全局问 AI 自动附截图
//
// 覆盖：
//   1) 页面自身未注入截图时，showAiAssistant 自动截全局 appCanvas
//      （IndexedStack 内容区）注入 pendingCanvasImage，随问题发给
//      多模态模型（M3/mimo）；
//   2) 页面已自行注入截图（如系谱页 ROI 高清截图）时，不覆盖；
//   3) 截图失败（无渲染对象）时静默降级，不阻断面板打开。
// 注意：AiChatController 是全局单例 —— setUp/tearDown 一律 reset。

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:biology/services/ai_client.dart';
import 'package:biology/pages/molecular_page.dart';
import 'package:biology/pages/settings_page.dart'
    show AiChatStore, AiSettingsStore;
import 'package:biology/ui/ai_chat_controller.dart';
import 'package:biology/ui/assistant_panel.dart';

void main() {
  late Directory tmp;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('global_canvas_shot_test');
    AiChatStore.debugFilePath = '${tmp.path}/ai_chat_history.json';
    AiSettingsStore.debugConfig =
        const AiConfig(baseUrl: '', apiKey: '', model: '');
    AiChatController.instance.reset();
  });

  tearDown(() {
    AiChatStore.debugFilePath = null;
    AiSettingsStore.debugConfig = null;
    AiChatController.instance.reset();
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

  testWidgets('showAiAssistant 自动截取全局画布注入 pendingCanvasImage', (t) async {
    await t.pumpWidget(wrap(RepaintBoundary(
      key: appCanvasKey,
      child: MolecularPage(),
    )));
    await t.pump();
    expect(AiChatController.instance.pendingCanvasImage, isNull);

    // 注意：不能 await——showAiAssistant 的 Future 直到面板关闭才完成。
    // ignore: unawaited_futures
    showAiAssistant(t.element(find.byType(MolecularPage)));
    // toImage 是真实 engine 异步调用，FakeAsync 的 pump 无法推进它，
    // 必须 runAsync 放行（同 page_scan_test 的 rootBundle 放行手法）。
    await t.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    await t.pump();
    await t.pump(const Duration(milliseconds: 400));

    final shot = AiChatController.instance.pendingCanvasImage;
    expect(shot, isNotNull, reason: '打开面板时应自动截全局画布');
    expect(shot!.length, greaterThan(1000), reason: 'PNG base64 应有实际内容');

    // 清理弹出的面板；未发送的截图不得留到下一页复用。
    Navigator.of(t.element(find.byType(MolecularPage))).pop();
    await t.pump();
    expect(AiChatController.instance.pendingCanvasImage, isNull);
  });

  testWidgets('页面已注入截图时不覆盖（系谱页 ROI 截图优先）', (t) async {
    await t.pumpWidget(wrap(RepaintBoundary(
      key: appCanvasKey,
      child: MolecularPage(),
    )));
    await t.pump();
    AiChatController.instance.pendingCanvasImage = 'PRESET_ROI_SHOT';

    // ignore: unawaited_futures
    showAiAssistant(t.element(find.byType(MolecularPage)));
    await t.pump();
    await t.pump(const Duration(milliseconds: 400));

    expect(AiChatController.instance.pendingCanvasImage, 'PRESET_ROI_SHOT',
        reason: '页面自注入截图优先，不被全局截图覆盖');

    Navigator.of(t.element(find.byType(MolecularPage))).pop();
    await t.pump();
    expect(AiChatController.instance.pendingCanvasImage, isNull,
        reason: '即使未发送，局部截图也只在本次面板生命周期内有效');
  });
}
