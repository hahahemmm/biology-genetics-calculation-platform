// startup_mode_test.dart —— 启动模式改造：真实 BiologyApp 离线验收
//
// 用户裁定（2026-10-30 修订）：**课堂模式 enabled 是持久化的模式记忆**——
// 首次启动（无配置文件 / 字段缺失）一律进「标准」普通小字号；之后每次冷
// 启动恢复上次退出时的模式（上次是课堂大屏就仍进课堂大屏）。Windows 侧
// 默认普通窗口（原生已是 SW_SHOWNORMAL + fullscreen_=false，C++ 不改），
// F11 也只在当次主动按下时切。
//
// 本文件是端到端验收（不是控制器单测）：
//   A1 夹具 = 真实存量形态 `{"enabled":true,"laser":true,"hc":true}`
//      + 临时 FirstRunStore（学生角色）+ 500×1500 physical / dpr 1.5
//      （逻辑宽 ≈333，正是 ModeSwitcher 真窗缺陷档）**真冷启动**：
//        · enabled=true（模式记忆：上次是课堂大屏 → 仍进课堂大屏）
//        · laser / hc 偏好照常恢复（证明配置真的被读到，不是"没 load
//          所以碰巧同值"）
//        · MediaQuery textScaler = PresentModeController.textScale（×1.75）
//        · 零 exception / 零 overflow，模式切换器在
//   A2 无 present_mode.json（首次安装）→ enabled=false、textScaler=1.0、
//      模式切换器可见；当次点「课堂大屏」→ enabled=true、
//      textScaler=1.75、仍零异常（"当次主动开启才生效"的正向面）
//
// ⚠️ 隔离纪律：所有配置文件都指向 systemTemp 下的临时目录（present_mode /
// first_run / theme_mode 三件），绝不读写 `~/.biology_app`；ai_config 走
// AiSettingsStore.debugConfig 内存注入。tearDown 完整复位静态钩子 + 删临时
// 目录。真实冷启动的 load 由 BiologyApp / HomeShell.initState 触发（不预
// 加载），load 内部只做同步 File 读，故可在 widget 测试的 fake-async 里
// 完成；⚠️ 若改成在测试体里 `await` 加载，必须包 `tester.runAsync`。
import 'dart:io';

import 'package:biology/services/ai_client.dart';
import 'package:biology/main.dart';
import 'package:biology/pages/settings_page.dart' show AiSettingsStore;
import 'package:biology/state/first_run_store.dart';
import 'package:biology/state/present_mode_controller.dart';
import 'package:biology/state/theme_controller.dart';
import 'package:biology/ui/mode_switcher.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmp;
  late String presentPath;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('startup_mode');
    presentPath = '${tmp.path}/present_mode.json';
    // present_mode.json 是否存在由各用例自己决定（A1 写存量配置 = 上次退出
    // 停在课堂大屏；A2 不写 = 首次安装）。三件配置都指向 systemTemp。
    PresentModeController.debugFilePath = presentPath;
    PresentModeController.debugWebStorage = null;
    PresentModeController.debugForceIsWebStorage = null;
    PresentModeController.instance.debugReset();

    // 学生角色（避开首启角色 dialog；nudge=true 避开一次性快捷键提示）。
    final firstRunPath = '${tmp.path}/first_run.json';
    File(firstRunPath).writeAsStringSync('{"role":"student","nudge":true}');
    FirstRunStore.debugFilePath = firstRunPath;
    FirstRunStore.debugWebStorage = null;
    FirstRunStore.debugForceIsWebStorage = false;
    FirstRunStore.instance.debugReset();

    // 主题配置也隔离：读不到文件 ⇒ ThemeMode.system，不碰真机主题偏好。
    ThemeController.debugFilePath = '${tmp.path}/theme_mode.json';
    ThemeController.instance.debugReset();

    // 已配置 AI：避免「进入课堂大屏 → 一次性 AI Key SnackBar」留下 4s
    // 定时器（v21968_present_ai_key_hint_test 的既有坑）。
    AiSettingsStore.debugConfig = const AiConfig(
      provider: AiConfig.providerMinimax,
      baseUrl: 'https://api.minimaxi.com/v1',
      apiKey: 'sk-fake-configured-0001',
      model: 'MiniMax-M3.1-Flash-Preview',
    );
  });

  tearDown(() {
    PresentModeController.debugFilePath = null;
    PresentModeController.debugWebStorage = null;
    PresentModeController.debugForceIsWebStorage = null;
    PresentModeController.instance.debugReset();

    FirstRunStore.debugFilePath = null;
    FirstRunStore.debugWebStorage = null;
    FirstRunStore.debugForceIsWebStorage = null;
    FirstRunStore.instance.debugReset();

    ThemeController.debugFilePath = null;
    ThemeController.instance.debugReset();

    AiSettingsStore.debugConfig = null;

    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  /// 当前 HomeShell 里实际应用的字号倍率（不写死 1.3/1.75）。
  double textScaleOf(WidgetTester tester) =>
      MediaQuery.textScalerOf(tester.element(find.byType(ModeSwitcher)))
          .scale(1.0);

  testWidgets('存量课堂大屏配置 → 冷启动恢复课堂大屏', (tester) async {
    // A1 夹具：上次退出停在课堂大屏 + 激光笔 + 高对比。
    File(presentPath).writeAsStringSync(
        '{"enabled":true,"laser":true,"hc":true}');

    // 真窗缺陷档：500×1500 physical + 150% 缩放 ⇒ 逻辑宽 ≈333。
    tester.view.physicalSize = const Size(500, 1500);
    tester.view.devicePixelRatio = 1.5;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    // ── 冷启动：不预加载，让 BiologyApp / HomeShell.initState 自己 load ──
    await tester.pumpWidget(const BiologyApp());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));

    // ① 配置确实被读到：laser / hc 偏好恢复（否则 enabled=true 可能只是
    //    "默认值碰巧"的假绿）。
    expect(PresentModeController.instance.laserEnabled, isTrue,
        reason: 'laser 是偏好，冷启动照常恢复（证明配置文件真的被读到了）');
    expect(PresentModeController.instance.highContrast, isTrue,
        reason: 'hc 是配色偏好，冷启动照常恢复');

    // ② 核心：模式记忆——上次是课堂大屏，冷启动仍进课堂大屏。
    expect(PresentModeController.instance.enabled, isTrue,
        reason: 'enabled 持久化记忆：上次退出在课堂大屏 → 冷启动恢复课堂大屏');

    // ③ 课堂大屏字号倍率。
    expect(textScaleOf(tester), PresentModeController.textScale,
        reason: '课堂大屏字号倍率 = PresentModeController.textScale（不写死）');

    // ④ 模式切换器仍在，且零 exception / 零 overflow（逻辑宽 ≈333 档）。
    expect(find.byType(ModeSwitcher), findsOneWidget,
        reason: '模式切换器仍在（用户可随时切回标准）');
    expect(tester.takeException(), isNull,
        reason: '冷启动恢复课堂大屏不得抛异常 / 布局溢出');
  });

  testWidgets('无配置文件冷启动即标准模式；当次点课堂大屏才放大字号',
      (tester) async {
    // A2 夹具：首次安装——present_mode.json 不存在（setUp 只指路径，不写）。
    expect(File(presentPath).existsSync(), isFalse,
        reason: '首次安装夹具：磁盘无 present_mode.json');

    tester.view.physicalSize = const Size(500, 1500);
    tester.view.devicePixelRatio = 1.5;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const BiologyApp());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));

    // ① 核心：首次安装 → 标准模式。
    expect(PresentModeController.instance.enabled, isFalse,
        reason: '首次启动（无 present_mode.json）= 标准模式');
    expect(textScaleOf(tester), 1.0,
        reason: '标准模式字号倍率必须是 1.0（普通小字号）');
    expect(find.byType(ModeSwitcher), findsOneWidget,
        reason: '冷启动后用户仍能当次主动开课堂大屏');
    expect(tester.takeException(), isNull,
        reason: '冷启动不得抛异常 / 布局溢出');

    // ── 当次主动开启：点「课堂大屏」→ 立即生效 ──
    expect(find.text('课堂大屏'), findsOneWidget,
        reason: '标准档 333 逻辑宽下仍展示全称标签，可点');
    await tester.tap(find.text('课堂大屏'));
    // 定长泵跨过 MaterialApp 重建与 200ms 样式动画，避免把中间帧当最终态；
    // 兼容旧测试的跳帧纪律，不把动画过程中的瞬态当作产品异常。
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));

    expect(PresentModeController.instance.enabled, isTrue,
        reason: '当次主动开启课堂大屏必须生效');
    expect(textScaleOf(tester), PresentModeController.textScale,
        reason: '课堂大屏字号倍率 = PresentModeController.textScale（不写死）');
    expect(tester.takeException(), isNull,
        reason: '课堂档在 333 逻辑宽下也不得溢出 / 抛异常');
  });
}
