// present_mode_test.dart —— v2.3 课堂模式（演示模式）
//
// 覆盖：
// 1. 控制器：默认关、debugSetEnabled 触发 notify；
// 2. MaterialApp.builder 注入：开启后 MediaQuery.textScaler ≥1.3、
//    全局触控目标放大（paddedForAccessibility）；关闭时不受影响；
// 3. 设置页「课堂模式」开关联动控制器；
// 4. 激光笔层：课堂模式开启时挂入系谱画布、关闭时移除；
//    指针划过后 0.8s 渐隐轨迹自动清空（定时器自停，不泄漏）。
import 'package:biology/main.dart';
import 'package:biology/pages/settings_page.dart';
import 'package:biology/pages/widgets/laser_pointer_layer.dart';
import 'package:biology/pages/widgets/pedigree_canvas.dart';
import 'package:biology/pages/widgets/spotlight_layer.dart';
import 'package:biology/state/present_mode_controller.dart';
import 'package:biology/state/theme_controller.dart';
import 'package:biology/theme.dart';
import 'package:biology/ui/mode_switcher.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  tearDown(() {
    PresentModeController.instance.debugSetEnabled(false);
    // 激光笔新默认关（2026-08-31 裁定：教鞭场景不常驻）。
    PresentModeController.instance.debugSetLaserEnabled(false);
    PresentModeController.instance.debugSetHighContrast(false);
    PresentModeController.instance.debugSetSpotlightOn(false);
  });

  testWidgets('课堂模式开启：全场字号×1.3；关闭：不受影响', (tester) async {
    // 真实文件 I/O（~/.biology_app/*.json）必须 runAsync 放行——
    // 直接在 FakeAsync 测试体里 await 会挂死（本测试首版实锤）。
    await tester.runAsync(() async {
      await ThemeController.instance.debugEnsureLoaded();
      await PresentModeController.instance.debugEnsureLoaded();
    });

    // 关闭态：默认缩放（system 1.0）。
    PresentModeController.instance.debugSetEnabled(false);
    await tester.pumpWidget(const BiologyApp());
    await tester.pump();
    var ctx = tester.element(find.byType(HomeShell));
    expect(MediaQuery.of(ctx).textScaler.scale(10), 10,
        reason: '关闭时字号不放大');

    // 开启态：×1.3（按钮/芯片随文字等比变大，触控目标随之放大）。
    PresentModeController.instance.debugSetEnabled(true);
    await tester.pump();
    ctx = tester.element(find.byType(HomeShell));
    expect(MediaQuery.of(ctx).textScaler.scale(10), greaterThanOrEqualTo(13),
        reason: '开启后全场字号至少 ×1.3（后排可读）');
  });

  testWidgets('设置页「使用模式」切换器联动控制器（学生/课堂分别做）',
      (tester) async {
    await tester
        .runAsync(() => PresentModeController.instance.debugEnsureLoaded());
    PresentModeController.instance.debugSetEnabled(false);
    await tester.pumpWidget(MaterialApp(
      home: SettingsPage(navCollapsed: false, onNavPressed: () {}),
    ));
    await tester.pump();

    // v2.19.30：设置页回退单列平铺——滚到「使用模式」节再断言
    //（ListView 懒挂载，屏外不在树）。
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('presentModeCard')),
      200,
      scrollable: find
          .descendant(
              of: find.byType(SettingsPage),
              matching: find.byType(Scrollable))
          .first,
    );
    await tester.pump();
    expect(find.byType(ModeSwitcher), findsOneWidget, reason: '模式切换器存在');

    // 学生模式（默认）→ 点「课堂模式」→ 控制器开启。
    await tester.tap(find.text('课堂大屏'));
    await tester.pump();
    expect(PresentModeController.instance.enabled, isTrue,
        reason: '切到课堂模式后控制器开启');

    // 点「学生模式」切回，恢复。
    await tester.tap(find.text('标准'));
    await tester.pump();
    expect(PresentModeController.instance.enabled, isFalse);
  });

  // v2.22.0：高对比是浅色投影档的量具；深色有独立调校的可读色板
  //（AppColors._hc 本来就在 dark 下短路）⇒ 深色里把开关置灰，但**不清偏好**。
  testWidgets('设置页高对比开关：深色置灰并说明仅浅色，切回浅色偏好仍生效',
      (tester) async {
    await tester
        .runAsync(() => PresentModeController.instance.debugEnsureLoaded());
    PresentModeController.instance.debugSetHighContrast(true); // 预置偏好

    Future<void> pumpSettings(ThemeData theme) async {
      await tester.pumpWidget(MaterialApp(
        theme: theme,
        home: SettingsPage(navCollapsed: false, onNavPressed: () {}),
      ));
      // MaterialApp 用 AnimatedTheme 过渡主题（200ms）：只 pump 一帧时
      // Theme.of 还是上一档的插值（dark→light 首帧仍是 dark），必须等动画落定。
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('highContrastSwitch')),
        200,
        scrollable: find
            .descendant(
                of: find.byType(SettingsPage),
                matching: find.byType(Scrollable))
            .first,
      );
      await tester.pumpAndSettle();
    }

    await pumpSettings(AppTheme.dark());
    var tile = tester.widget<SwitchListTile>(
        find.byKey(const ValueKey('highContrastSwitch')));
    expect(tile.onChanged, isNull, reason: '深色下开关必须置灰（拨了也没有反应）');
    expect(find.textContaining('仅浅色模式；深色使用独立高可读色板'),
        findsOneWidget);
    expect(tile.value, isTrue, reason: '置灰 ≠ 清偏好：存储值必须保留');
    expect(PresentModeController.instance.highContrast, isTrue);

    // 切回浅色：同一份偏好照样可用，开关恢复可拨。
    await pumpSettings(AppTheme.light());
    tile = tester.widget<SwitchListTile>(
        find.byKey(const ValueKey('highContrastSwitch')));
    expect(
      Theme.of(tester.element(find.byKey(const ValueKey('highContrastSwitch'))))
          .brightness,
      Brightness.light,
      reason: '开关所在子树必须真的处在浅色主题下',
    );
    expect(tile.onChanged, isNotNull, reason: '浅色行为不变');
    expect(tile.value, isTrue, reason: '切回浅色后原高对比偏好仍生效');
    expect(find.textContaining('纯白底 + 近黑文字'), findsOneWidget);
    PresentModeController.instance.debugSetHighContrast(false);
  });

  testWidgets('激光笔层：课堂模式开启挂入画布、指针轨迹 0.8s 后清空',
      (tester) async {
    PresentModeController.instance.debugSetEnabled(false);
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 600,
          height: 400,
          child: PedigreeCanvas(nodes: [], edges: []),
        ),
      ),
    ));
    await tester.pump();
    expect(find.byType(LaserPointerLayer), findsNothing,
        reason: '关闭时不挂载激光笔层');

    PresentModeController.instance.debugSetEnabled(true);
    // 激光笔默认关：需显式开启才挂层（2026-08-31 裁定）。
    PresentModeController.instance.debugSetLaserEnabled(true);
    await tester.pump();
    expect(find.byType(LaserPointerLayer), findsOneWidget,
        reason: '开启后挂入画布');

    // 指针划过 → 产生轨迹；800ms 后渐隐清空、定时器自停。
    final pointer = TestPointer(1, PointerDeviceKind.mouse);
    pointer.hover(tester.getCenter(find.byType(PedigreeCanvas)));
    await tester.pump();
    pointer.hover(tester.getCenter(find.byType(PedigreeCanvas)) +
        const Offset(40, 30));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 900));
    await tester.pump(const Duration(milliseconds: 100));
    // 无异常即通过（渐隐定时器正常清空并自停）。

    // 激光笔独立开关：课堂模式保持开启，仅关激光笔 → 层移除。
    PresentModeController.instance.debugSetLaserEnabled(false);
    await tester.pump();
    expect(find.byType(LaserPointerLayer), findsNothing,
        reason: '课堂模式内单独关闭激光笔后层移除');
    PresentModeController.instance.debugSetLaserEnabled(true);
    await tester.pump();
    expect(find.byType(LaserPointerLayer), findsOneWidget,
        reason: '重新开启后层恢复');

    // 聚光灯（v2.8 白板教鞭对象化）：默认关 → 开启后亮区默认居中；
    // hover 不再移动亮区（白板"鼠标"是瞬移的，跟随模型不成立——
    // 对齐希沃/ViewSonic：聚光灯是可操作对象，点哪亮哪/按住拖动/边缘调大小）。
    PresentModeController.instance.debugSetSpotlightOn(true);
    await tester.pump();
    final spot = find.byType(SpotlightLayer);
    expect(spot, findsOneWidget, reason: '聚光灯开启后层挂载');
    final spotState = tester.state<SpotlightLayerState>(spot);
    // hover 注入（sendEventToBinding，裸 await 无效——既有踩坑实锤）
    final canvasCenter = tester.getCenter(find.byType(PedigreeCanvas));
    await tester.sendEventToBinding(pointer.hover(canvasCenter + const Offset(80, 60)));
    await tester.pump();
    expect(spotState.debugCenter, isNull, reason: 'v2.8：hover 不再移动亮区');
    // 亮区圆心内按住拖动 → 亮区移动（手指真实轨迹）
    final layerTopLeft = tester.getTopLeft(find.byType(SpotlightLayer));
    final layerSize = tester.getSize(find.byType(SpotlightLayer));
    final c0 = layerTopLeft + layerSize.center(Offset.zero); // 默认居中
    final r0 = layerSize.shortestSide * 0.22;
    await tester.dragFrom(c0, const Offset(60, 40));
    await tester.pump();
    expect(spotState.debugCenter, isNotNull, reason: '圆内拖动后亮区移动');
    // 边缘环带（半径 ±22px 内）拖动 → 调半径
    final rBefore = spotState.debugRadius ?? r0;
    final rimPoint = (spotState.debugCenter ?? Offset.zero) +
        layerTopLeft +
        Offset(rBefore, 0); // 右侧边缘
    await tester.dragFrom(rimPoint, const Offset(30, 0));
    await tester.pump();
    expect(spotState.debugRadius, isNotNull, reason: '边缘拖动后半径被显式设置');
    expect(spotState.debugRadius, greaterThan(rBefore),
        reason: '沿径向外拖 → 半径变大');
    PresentModeController.instance.debugSetSpotlightOn(false);
    await tester.pump();
    // 关闭后层仍在树中但 painter 不压暗（active=false → SizedBox.shrink）。
    expect(tester.widget<SpotlightLayer>(spot).active, isFalse);
  });
}
