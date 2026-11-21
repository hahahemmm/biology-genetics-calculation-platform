// graph_reading_first_test.dart —— v2.22.0 知识图谱「阅读优先 / 全图总览」
//
// 需求（视觉减负第 1、2 项）：
//   1) **默认初始视图以阅读优先**：19 节点分层世界约 2170×960，桌面
//      1400×900 里全图适配只有 ≈0.63 ⇒ 12px 节点标题压到 7.5px（
//      v221_graph_focus.png 的「蚂蚁字」）。默认因此取
//      `max(全图适配, 0.8)` = 0.8（节点字 9.6px），外围靠拖动看。
//   2) **显式全图**仍是真全图：图例「全图」/ 课堂缩放条「适配全图」
//      置 _overview 后不设阅读下限，可压到 _minScale(0.2)，且世界必须
//      真的全部落在视口内。
//   两个语义必须各自成立（本文件 A1/A2/A3 三条分别钉住）。
//   3) **课堂缩放条不再压在右下 FAB 列上**：原 bottom:16 正压拍题 FAB；
//      现值 = 200（FAB 列 122 + 快捷条 134+54）− 图例 34 = 166，本文件
//      B1 用真实布局矩形证明缩放条底缘离页面底边 ≥ 200。
//
// 只断言本页自己的行为，不碰 golden、不碰其它 worker 的文件。

import 'package:biology/pages/knowledge_graph_page.dart';
import 'package:biology/state/present_mode_controller.dart';
import 'package:biology/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(() {
    AppColors.sync(Brightness.light);
    PresentModeController.instance.debugSetEnabled(false);
  });

  tearDown(() {
    AppColors.debugClearOverride();
    PresentModeController.instance.debugSetEnabled(false);
    PresentModeController.instance.debugSetHighContrast(false);
  });

  Future<dynamic> pumpGraph(WidgetTester t, Size size) async {
    t.view.physicalSize = size;
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    await t.pumpWidget(
      MaterialApp(theme: AppTheme.light(), home: const KnowledgeGraphPage()),
    );
    await t.pumpAndSettle();
    return t.state(find.byType(KnowledgeGraphPage));
  }

  /// 画布视口（InteractiveViewer 的实测尺寸；ModuleSurface 只差 1px 描边）。
  Size viewportOf(WidgetTester t) => t.getSize(find.byType(InteractiveViewer));

  group('A · 默认阅读优先 vs 显式全图', () {
    testWidgets('A1：桌面 1400×900 默认取 0.8 阅读下限，不装下全世界', (t) async {
      final state = await pumpGraph(t, const Size(1400, 900));

      final world = state.debugWorldSize as Size;
      final vp = viewportOf(t);
      final fitted = (vp.width / world.width) < (vp.height / world.height)
          ? vp.width / world.width
          : vp.height / world.height;

      expect(state.debugOverviewMode, isFalse, reason: '默认必须是阅读视图语义');
      expect(
        state.debugViewScale as double,
        closeTo(0.8, 1e-6),
        reason: '全图适配 ${fitted.toStringAsFixed(3)} < 0.8 时必须抬到阅读下限',
      );
      expect(fitted, lessThan(0.8), reason: '本例就该触发下限（否则本测试无效）');
      expect(
        world.width * (state.debugViewScale as double),
        greaterThan(vp.width),
        reason: '阅读视图刻意裁掉外围——这正是它与「全图」的区别',
      );
      // 12px 节点标题在 0.8 下的实际字号：9.6px（旧 0.63 ⇒ 7.5px）。
      expect(12 * (state.debugViewScale as double), greaterThan(9.0));
    });

    testWidgets('A2：显式全图 ⇒ 真装下全部节点，尺度落回全图适配', (t) async {
      final state = await pumpGraph(t, const Size(1400, 900));
      final world = state.debugWorldSize as Size;
      final vp = viewportOf(t);
      final reading = state.debugViewScale as double;

      state.debugFitOverview();
      await t.pumpAndSettle();

      final overview = state.debugViewScale as double;
      expect(state.debugOverviewMode, isTrue, reason: '显式全图是独立语义');
      expect(overview, lessThan(reading), reason: '全图必须比阅读视图更远');
      expect(overview, greaterThanOrEqualTo(0.2), reason: '不越 minScale');
      expect(world.width * overview, lessThanOrEqualTo(vp.width + 2),
          reason: '全图状态下世界宽度必须真的装进视口');
      expect(world.height * overview, lessThanOrEqualTo(vp.height + 2),
          reason: '全图状态下世界高度必须真的装进视口');
    });

    testWidgets('A3：视口够大时阅读下限不生效（不无故放大）', (t) async {
      final state = await pumpGraph(t, const Size(1800, 1600));
      final world = state.debugWorldSize as Size;
      final vp = viewportOf(t);
      final fitted = (vp.width / world.width) < (vp.height / world.height)
          ? vp.width / world.width
          : vp.height / world.height;

      expect(fitted, greaterThan(0.8), reason: '本例全图适配本就够大');
      expect(
        state.debugViewScale as double,
        closeTo(fitted.clamp(0.2, 1.0), 0.01),
        reason: '下限只是「不低于」，不是「一律放大到」'
            '（容忍 ModuleSurface 1px 描边造成的视口差）',
      );
    });

    testWidgets('A4：图例「全图」是标准模式下的显式入口', (t) async {
      final state = await pumpGraph(t, const Size(1400, 900));
      final reading = state.debugViewScale as double;

      await t.tap(find.text('全图'));
      await t.pumpAndSettle();

      expect(state.debugOverviewMode, isTrue);
      expect(state.debugViewScale as double, lessThan(reading));
    });
  });

  group('B · 课堂缩放条让位右下 FAB 列', () {
    testWidgets('B1：bottom 不再是 16，缩放条底缘离页面底边 ≥ 200', (t) async {
      PresentModeController.instance.debugSetEnabled(true);
      final state = await pumpGraph(t, const Size(1400, 900));
      expect(state.debugViewScale as double, greaterThan(0));

      // 缩放条「放大」键 → 最近的 Positioned（本页 Stack 里的那一个）。
      final positioned = t.widget<Positioned>(
        find
            .ancestor(
              of: find.byTooltip('放大'),
              matching: find.byType(Positioned),
            )
            .first,
      );
      expect(positioned.right, 16);
      expect(positioned.bottom, isNot(16), reason: '旧值直接压在拍题 FAB 上');
      // 166 = (16 底距 + 拍题 40 + 间距 10 + 问AI 56 + 12 + 快捷条 54 + 12)
      //       − 图例 34
      expect(positioned.bottom, 166);

      final bar = t.getRect(find.byTooltip('放大'));
      final screenH = t.view.physicalSize.height / t.view.devicePixelRatio;
      expect(
        bar.bottom,
        lessThanOrEqualTo(screenH - 200),
        reason: 'FAB 列顶 122 + 课堂快捷条 134..188，缩放条必须整体在其上方',
      );
      // 上方仍留在画布内（没有被顶出视口顶部）
      expect(bar.top, greaterThan(0));
    });
  });
}
