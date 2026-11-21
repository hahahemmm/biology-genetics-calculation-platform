// whiteboard_touch_test.dart —— v2.3.4 课堂模式白板触控增强
//
// 场景：希沃/鸿合几平米白板，老师用胳膊/教鞭点，指针瞬移。
// 覆盖：
// 1. 课堂模式开启 → IconButton/按钮最小触控目标全局放大（52/48px 档）；
//    关闭时不放大。
// 2. 图谱页：课堂模式右下角出现触控缩放条（放大/缩小/适配全图），
//    点放大实际增大 InteractiveViewer 缩放；关闭模式缩放条消失。
import 'package:biology/main.dart';
import 'package:biology/pages/knowledge_graph_page.dart';
import 'package:biology/state/present_mode_controller.dart';
import 'package:biology/state/theme_controller.dart';
import 'package:biology/theme.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  tearDown(() {
    PresentModeController.instance.debugSetEnabled(false);
    PresentModeController.instance.debugSetHighContrast(false);
    AppColors.debugClearOverride();
  });

  Future<void> ensureLoaded(WidgetTester tester) async {
    await tester.runAsync(() async {
      await ThemeController.instance.debugEnsureLoaded();
      await PresentModeController.instance.debugEnsureLoaded();
    });
  }

  testWidgets('课堂模式：全局触控目标放大（IconButton≥52，FilledButton≥52 高）',
      (tester) async {
    await ensureLoaded(tester);

    PresentModeController.instance.debugSetEnabled(false);
    await tester.pumpWidget(const BiologyApp());
    await tester.pump();
    var ctx = tester.element(find.byType(HomeShell));
    expect(Theme.of(ctx).iconButtonTheme.style?.minimumSize?.resolve({}),
        isNot(equals(const Size(52, 52))),
        reason: '学生模式不强制 52px 触控目标');

    PresentModeController.instance.debugSetEnabled(true);
    await tester.pump();
    // 主题覆盖在 MaterialApp.builder：验证主题档位
    ctx = tester.element(find.byType(HomeShell));
    final iconTheme = Theme.of(ctx).iconButtonTheme;
    expect(iconTheme.style?.minimumSize?.resolve({}), const Size(52, 52),
        reason: '课堂模式 IconButton 触控目标 52×52（教鞭/胳膊可点）');
    expect(
        Theme.of(ctx).filledButtonTheme.style?.minimumSize?.resolve({}),
        const Size(64, 52),
        reason: '课堂模式 FilledButton 最小 64×52');
  });

  testWidgets('图谱页：课堂模式显示触控缩放条，点放大实际放大；关闭隐藏',
      (tester) async {
    await ensureLoaded(tester);
    PresentModeController.instance.debugSetEnabled(false);
    await tester.pumpWidget(const MaterialApp(home: KnowledgeGraphPage()));
    await tester.pump();
    expect(find.byTooltip('放大'), findsNothing, reason: '学生模式无缩放条');

    PresentModeController.instance.debugSetEnabled(true);
    await tester.pump();
    expect(find.byTooltip('放大'), findsOneWidget);
    expect(find.byTooltip('缩小'), findsOneWidget);
    expect(find.byTooltip('适配全图'), findsOneWidget);

    double scale() => tester
        .widget<InteractiveViewer>(find.byType(InteractiveViewer))
        .transformationController!
        .value
        .getMaxScaleOnAxis();
    final before = scale();
    await tester.tap(find.byTooltip('放大'));
    await tester.pump();
    expect(scale(), greaterThan(before), reason: '点放大后缩放增大');

    // 连续缩小后点「适配全图」：进入显式全图总览。
    // 默认阅读尺度（本例 0.8）与全图适配（通常更小）是两种语义，
    // 不能再要求它回到默认阅读缩放。
    for (var i = 0; i < 12; i++) {
      await tester.tap(find.byTooltip('缩小'));
      await tester.pump();
    }
    expect(scale(), lessThan(before));
    await tester.tap(find.byTooltip('适配全图'));
    await tester.pump();
    expect(scale(), lessThan(before),
        reason: '显式全图应比默认阅读视图更远，才能装下外围节点');
    expect(scale(), greaterThanOrEqualTo(0.2),
        reason: '全图总览仍不得越过画布最小缩放');
  });

  testWidgets('图谱兼容白板滚动映射：普通滚动平移，Ctrl+滚轮才缩放',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(home: KnowledgeGraphPage()));
    await tester.pumpAndSettle();
    final state = tester.state(find.byType(KnowledgeGraphPage)) as dynamic;
    final before = (state.debugViewTransform as Matrix4).clone();
    final center = tester.getCenter(find.byType(InteractiveViewer));

    await tester.sendEventToBinding(PointerScrollEvent(
        position: center, scrollDelta: const Offset(35, 90)));
    await tester.pump();
    final panned = state.debugViewTransform as Matrix4;
    expect(panned.getMaxScaleOnAxis(), before.getMaxScaleOnAxis(),
        reason: '白板/鼠标滚动不得意外缩放图谱');
    expect(panned.getTranslation().x - before.getTranslation().x,
        closeTo(-35, 0.001));
    expect(panned.getTranslation().y - before.getTranslation().y,
        closeTo(-90, 0.001));

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    try {
      await tester.sendEventToBinding(PointerScrollEvent(
          position: center, scrollDelta: const Offset(0, -120)));
      await tester.pump();
    } finally {
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    }
    expect((state.debugViewTransform as Matrix4).getMaxScaleOnAxis(),
        greaterThan(before.getMaxScaleOnAxis()),
        reason: '桌面用户仍可用 Ctrl+滚轮放大');
  });

  test('高对比配色 token：浅色+hc 开 → 高对比变体；深色不受理（v2.10 全局化）',
      () {
    AppColors.sync(Brightness.light); // 测试壳锁定浅色
    final pm = PresentModeController.instance;
    expect(AppColors.ink, AppColors.inkL, reason: '默认普通浅色 token');

    // v2.10：高对比从「课堂子开关」迁移为全局显示开关——学生模式也生效
    pm.debugSetHighContrast(true);
    expect(AppColors.ink, AppColors.inkHcL, reason: '学生模式（课堂关）+ hc → 近黑文字');
    expect(AppColors.canvas, AppColors.canvasHcL, reason: '纯白底');
    expect(AppColors.border, AppColors.borderHcL, reason: '边框加深');
    expect(AppColors.teal, AppColors.tealHcL, reason: 'teal 加深');
    expect(AppColors.isHighContrast, isTrue);

    AppColors.sync(Brightness.dark);
    expect(AppColors.ink, AppColors.inkD, reason: '深色主题不受理高对比');

    AppColors.sync(Brightness.light);
    pm.debugSetHighContrast(false);
    expect(AppColors.ink, AppColors.inkL, reason: '关 hc 回到普通浅色');
  });
}
