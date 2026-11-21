// mode_switcher_narrow_test.dart —— v2.20.0 窄窗课堂字号零溢出回归网
//
// 真窗发现：窗口 500×1500 + 课堂模式，首页 ModeSwitcher 那一行出现
// 「RIGHT OVERFLOWED BY 4.1 PIXELS」。根因是系统 150% 缩放：
//   500 物理 ⇒ 逻辑 ≈333；行内实得 333-66 = 267（页边距 40 + 前置图标 18
//   + 间距 8）；课堂档（textScale 1.75）「图标 + 全称」实测 268.8
//   ⇒ 右溢 4.1px（逐像素吻合）。
//
// 修法（只动 lib/ui/mode_switcher.dart）：按「行内可用宽 vs 三档实测固有
// 宽」选最小降级档
//   full       = 图标 + 全称「课堂大屏」（宽窗原样，零像素变化）
//   labelsOnly = 去图标 + 全称（逻辑 267 档正好放下：232.8）
//   compact    = 去图标 + 短标签「课堂」（<300 逻辑宽兜底）
//
// 本文件钉住：
//   W1 @1280 课堂档：仍是 full（图标 + 全称），宽屏外观零变化；
//   W2 @500×1500 physical + dpr 1.5（逻辑 333，真窗缺陷档）课堂档：零溢出；
//   W3 @390×844 课堂档：零溢出，且两种模式仍可切换；
//   W4 @390×844 标准档：零溢出，标签仍可点（行为不变）；
//   W5 三档阈值单元网（含 <300 逻辑宽的 compact 兜底，实泵验证零溢出）。
import 'package:biology/main.dart';
import 'package:biology/state/first_run_store.dart';
import 'package:biology/state/present_mode_controller.dart';
import 'package:biology/state/theme_controller.dart';
import 'package:biology/ui/mode_switcher.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> pumpShell(
  WidgetTester tester,
  Size physicalSize, {
  required bool classroom,
  double dpr = 1.0,
}) async {
  tester.view.physicalSize = physicalSize;
  tester.view.devicePixelRatio = dpr;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.runAsync(() => ThemeController.instance.debugEnsureLoaded());
  await tester
      .runAsync(() => PresentModeController.instance.debugEnsureLoaded());
  PresentModeController.instance.debugSetEnabled(classroom);
  addTearDown(PresentModeController.instance.debugReset);
  await FirstRunStore.instance.setRole(UserRole.student);
  addTearDown(FirstRunStore.instance.debugReset);
  await tester.pumpWidget(const BiologyApp());
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 600));
}

/// 当前 HomeShell 里课堂档的实际字号倍率（不写死 1.3/1.75——课堂倍率会调）。
double textScaleOf(WidgetTester tester) =>
    MediaQuery.textScalerOf(tester.element(find.byType(ModeSwitcher)))
        .scale(1.0);

void main() {
  testWidgets('W1 @1280 课堂档：仍为 full（图标 + 全称），宽屏外观不变',
      (tester) async {
    await pumpShell(tester, const Size(1280, 900), classroom: true);

    expect(find.byType(ModeSwitcher), findsOneWidget);
    expect(find.text('课堂大屏'), findsOneWidget, reason: '宽屏保持全称标签');
    // 选中段的图标会被换成 check，故断言**未选中**段的自定义图标在树。
    expect(
        find.descendant(
          of: find.byType(SegmentedButton<bool>),
          matching: find.byIcon(Icons.school_outlined),
        ),
        findsOneWidget,
        reason: '宽屏保持「图标 + 文字」外观');
    expect(
        ModeSwitcher.densityFor(
            screenWidth: 1280, textScale: textScaleOf(tester)),
        ModeSwitcherDensity.full);
    expect(tester.takeException(), isNull);
  });

  testWidgets('W2 真窗缺陷档 @500×1500 physical + 150% 缩放：零溢出', (tester) async {
    // 逻辑宽 = 500/1.5 ≈ 333：修前正是「RIGHT OVERFLOWED BY 4.1 PIXELS」。
    await pumpShell(tester, const Size(500, 1500),
        classroom: true, dpr: 1.5);

    expect(tester.takeException(), isNull,
        reason: '逻辑≈333 宽课堂档不得溢出（真窗 4.1px 缺陷点）');
    final logicalW = 500 / 1.5;
    expect(
        ModeSwitcher.densityFor(
            screenWidth: logicalW, textScale: textScaleOf(tester)),
        ModeSwitcherDensity.labelsOnly,
        reason: '逻辑≈333 档放不下 full（268.8 > 267），应降为去图标 + 全称');
    expect(find.text('课堂大屏'), findsOneWidget, reason: '文字信息不丢（仍全称）');
    expect(find.text('标准'), findsOneWidget);
  });

  testWidgets('W3 @390×844 课堂档：零溢出，两档模式仍可切换', (tester) async {
    await pumpShell(tester, const Size(390, 844), classroom: true);

    expect(tester.takeException(), isNull, reason: '390 宽课堂档不得溢出');
    expect(find.text('标准'), findsOneWidget);
    expect(find.text('课堂大屏'), findsOneWidget);

    // 行为不变：点「标准」关课堂档，再点回来。
    await tester.ensureVisible(find.text('标准'));
    await tester.tap(find.text('标准'));
    await tester.pumpAndSettle();
    expect(PresentModeController.instance.enabled, isFalse,
        reason: '点「标准」应关闭课堂模式');
    expect(tester.takeException(), isNull);

    // 字号切换会改变首页高度；先把目标滚回视口，再验证真实点击。
    await tester.ensureVisible(find.text('课堂大屏'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('课堂大屏'));
    await tester.pumpAndSettle();
    expect(PresentModeController.instance.enabled, isTrue,
        reason: '点「课堂大屏」应重新开启');
    expect(tester.takeException(), isNull);
  });

  testWidgets('W4 @390×844 标准档：零溢出，切换行为不变', (tester) async {
    await pumpShell(tester, const Size(390, 844), classroom: false);

    expect(find.byType(ModeSwitcher), findsOneWidget);
    expect(tester.takeException(), isNull, reason: '标准档 390 宽不得溢出');

    await tester.tap(find.text('课堂大屏'));
    await tester.pumpAndSettle();
    expect(PresentModeController.instance.enabled, isTrue,
        reason: '点「课堂大屏」应开启课堂模式');
    expect(tester.takeException(), isNull);
  });

  testWidgets('W5 三档阈值 + 超窄窗（<300 逻辑宽）compact 兜底零溢出',
      (tester) async {
    // 阈值网（数字由真实 App 壳实测固有宽推出，见 mode_switcher.dart 注释）。
    expect(ModeSwitcher.densityFor(screenWidth: 1280, textScale: 1.75),
        ModeSwitcherDensity.full);
    expect(ModeSwitcher.densityFor(screenWidth: 500, textScale: 1.75),
        ModeSwitcherDensity.full, reason: '逻辑 500 课堂档仍放得下 full（268.8）');
    expect(ModeSwitcher.densityFor(screenWidth: 390, textScale: 1.75),
        ModeSwitcherDensity.full, reason: '逻辑 390 课堂档也放得下 full');
    expect(ModeSwitcher.densityFor(screenWidth: 333, textScale: 1.75),
        ModeSwitcherDensity.labelsOnly, reason: '实得 267 < 268.8 ⇒ 降档');
    expect(ModeSwitcher.densityFor(screenWidth: 280, textScale: 1.75),
        ModeSwitcherDensity.compact, reason: '实得 214 < 232.8 ⇒ 短标签兜底');
    expect(ModeSwitcher.densityFor(screenWidth: 390, textScale: 1.0),
        ModeSwitcherDensity.full, reason: '标准档 390 不需降级');

    // 回归（v2.20.0 补钉）：小字号档 scale=0.85 + 窄屏仍返回 compact。
    // 旧代码末尾有 `assert(_needCompactWidth(scale) < _needLabelsOnlyWidth(scale))`
    // ——固有宽模型里 compact(156.4+8×0.85=163.2) 反而**大于**
    // labelsOnly(73.2+91.2×0.85+4=154.7)，档位序在小字号档翻转，该 assert
    // 会直接抛（compact 本就是无条件兜底）。删 assert 后此断言必须仍成立。
    expect(ModeSwitcher.densityFor(screenWidth: 200, textScale: 0.85),
        ModeSwitcherDensity.compact,
        reason: 'scale=0.85 窄屏（实得 134 < labelsOnly 154.7）仍走 compact 兜底');
    expect(ModeSwitcher.densityFor(screenWidth: 200, textScale: 0.95),
        ModeSwitcherDensity.compact,
        reason: 'scale=0.95 同一占位关系（139 vs 163.8）也必须是 compact');

    // 超窄窗实泵：compact 档零溢出 + 短标签在树 + 全称退到 tooltip。
    await pumpShell(tester, const Size(280, 800), classroom: true);
    expect(tester.takeException(), isNull, reason: '280 逻辑宽课堂档不得溢出');
    expect(find.text('课堂'), findsOneWidget, reason: 'compact 档用短标签');
    expect(find.text('课堂大屏'), findsNothing);
    final button = tester
        .widget<SegmentedButton<bool>>(find.byType(SegmentedButton<bool>));
    expect(button.segments.last.tooltip, '课堂大屏',
        reason: '全称退到 tooltip（语义不丢）');
    expect(button.segments.first.tooltip, '标准显示');

    // 课堂 → 标准（点未选中段；点已选中段是 no-op，别写错方向）。
    await tester.tap(find.text('标准'));
    await tester.pumpAndSettle();
    expect(PresentModeController.instance.enabled, isFalse,
        reason: 'compact 档切换行为不变');
    expect(tester.takeException(), isNull);
  });
}
