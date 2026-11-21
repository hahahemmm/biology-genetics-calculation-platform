// theme_toggle_test.dart —— 运行时深浅切换的整帧一致性回归测试。
//
// 背景：用户反馈「浅色模式下输入面板炭黑块 + 白字」的混染症状，仅在
// 运行时从深色切到浅色后出现（冷启动浅色正常）。本测试用真实
// BiologyApp 根 widget 复现切换路径，逐帧断言 token 与 ThemeData
// 不混染。
// v2（2026-08-26）：断言改为对 AppColors token 取值（不再硬编码色值，
// 皮肤重做时测试不脆断）；AppBar 已随 v2 命令栏移除，改验 Scaffold
// 背景色。
import 'package:biology/main.dart';
import 'package:biology/state/theme_controller.dart';
import 'package:biology/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/ready_app.dart';

void main() {
  testWidgets('运行时 dark→light→dark 切换：整帧 token 一致，无混染', (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await pumpReadyBiologyApp(tester);
    // 2.2 批次4a：启动页=首页（无输入框），先切到遗传图谱页再断言。
    await tester.tap(find.text('遗传图谱').first);
    await tester.pumpAndSettle();

    TextField firstField() =>
        tester.widget<TextField>(find.byType(TextField).first);

    // v2.1l：AppText 不再自带 color（color: null → textTheme 接管，
    // 走 colorScheme.onSurface）。断言 TextField 实际生效的文字色：
    // style 显式色优先，否则取当前 theme 的 onSurface。
    Color effectiveFieldColor() {
      final c = firstField().style?.color;
      if (c != null) return c;
      final ctx = tester.element(find.byType(TextField).first);
      return Theme.of(ctx).colorScheme.onSurface;
    }

    Color scaffoldBgOf() {
      // Scaffold.backgroundColor 页面未显式设置，实际生效值在 Theme 上
      final ctx = tester.element(find.byType(Scaffold).first);
      return Theme.of(ctx).scaffoldBackgroundColor;
    }

    // ── 切到深色 ────────────────────────────────────────
    ThemeController.instance.debugSetMode(ThemeMode.dark);
    await tester.pumpAndSettle();
    expect(AppColors.isDark, isTrue, reason: 'token 应为深色');
    expect(effectiveFieldColor(), AppColors.ink,
        reason: '深色模式输入框文字应为 inkD（近白）');
    expect(scaffoldBgOf(), AppColors.canvas,
        reason: '深色模式 Scaffold 应为 canvasD');
    expect(AppColors.canvas, isNot(AppColors.surface),
        reason: '深色 canvas 与 surface 应分层');

    // ── 切到浅色（用户混染症状的操作路径） ─────────────────
    ThemeController.instance.debugSetMode(ThemeMode.light);
    await tester.pumpAndSettle();
    expect(AppColors.isDark, isFalse, reason: 'token 应为浅色');
    expect(AppColors.surface, const Color(0xFFFBF9F5), // v3 莫兰迪 surfaceL
        reason: '浅色 surface 应为 v3 暖近白');
    expect(effectiveFieldColor(), AppColors.ink,
        reason: '浅色模式输入框文字应为 inkL（混染时此处为白）');
    expect(scaffoldBgOf(), AppColors.canvas,
        reason: '浅色模式 Scaffold 应为 canvasL');

    // 输入面板容器色必须是浅色 surface（混染时为深色 surfaceD）。
    // v2 容器走 BoxDecoration，取色要兼容 color 与 decoration 两处。
    final darkSurfaceNow = const Color(0xFF2D2F2C); // v3 surfaceD
    Color? colorOf(Container c) =>
        c.color ?? (c.decoration is BoxDecoration
            ? (c.decoration! as BoxDecoration).color
            : null);
    final ctlPanel = tester
        .widgetList<Container>(find.byType(Container))
        .map(colorOf)
        .whereType<Color>()
        .toSet();
    expect(ctlPanel.contains(darkSurfaceNow), isFalse,
        reason: '浅色模式下任何容器不得使用深色 surfaceD');
    expect(ctlPanel.contains(AppColors.surface), isTrue,
        reason: '浅色模式输入面板应为 surfaceL');

    // ── 再切回深色，确认对称一致 ─────────────────────────
    ThemeController.instance.debugSetMode(ThemeMode.dark);
    await tester.pumpAndSettle();
    expect(effectiveFieldColor(), AppColors.ink);
    expect(scaffoldBgOf(), AppColors.canvas);

    ThemeController.instance.debugSetMode(ThemeMode.system);
  });
}
