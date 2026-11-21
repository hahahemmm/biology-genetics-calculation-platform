// pedigree_fullscreen_sync_test.dart —— 全屏状态同步与提示层遮挡回归
import 'package:biology/guide/guide_keys.dart';
import 'package:biology/pages/genetic_pedigree_page.dart';
import 'package:biology/pages/widgets/pedigree_canvas.dart';
import 'package:biology/pages/widgets/pedigree_canvas_area.dart';
import 'package:biology/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'golden_fonts.dart';

void main() {
  Future<void> pumpPage(WidgetTester tester) async {
    await loadGoldenFonts();
    assertMaterialIconsLoaded();
    assertMonoLoaded();
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: const MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(1.75)),
          child: GeneticPedigreePage(),
        ),
      ),
    );
    await tester.tap(find.text('计算').first);
    await tester.pumpAndSettle();
    expect(find.byType(PedigreeCanvas), findsOneWidget);
  }

  Future<void> openFullscreen(WidgetTester tester) async {
    await tester.ensureVisible(find.text('全屏').first);
    await tester.pump();
    await tester.tap(find.text('全屏').first);
    await tester.pumpAndSettle();
    expect(find.byType(PedigreeCanvas), findsNWidgets(2));
    expect(tester.takeException(), isNull);
  }

  testWidgets('全屏中添加家族：内嵌与全屏画布实时同步，ESC 后句柄不再残留', (tester) async {
    await pumpPage(tester);
    await openFullscreen(tester);

    // 只点全屏 Dialog 里的「添加家族」，不走页面内嵌按钮。
    final add = find.descendant(
      of: find.byType(Dialog),
      matching: find.text('添加家族'),
    );
    expect(add, findsOneWidget);
    await tester.tap(add);
    await tester.pumpAndSettle();
    final fields = find.descendant(
      of: find.byType(AlertDialog),
      matching: find.byType(TextField),
    );
    expect(fields, findsNWidgets(2));
    await tester.enterText(fields.at(0), 'Bb');
    await tester.enterText(fields.at(1), 'Bb');
    await tester.tap(find.text('添加'));
    await tester.pumpAndSettle();

    // 不退出全屏就同时断言两个真实 widget：旧实现只有内嵌实例更新。
    final canvases = tester
        .widgetList<PedigreeCanvas>(find.byType(PedigreeCanvas))
        .toList();
    expect(canvases, hasLength(2));
    for (final canvas in canvases) {
      expect(canvas.familyLabels, hasLength(2));
      expect(canvas.familyLabels[1], 'B');
      expect(
        canvas.nodes.any((n) => n.familyId == 1 && n.id == 'P1-father'),
        isTrue,
        reason: '家族 B 必须在全屏未退出时就已渲染',
      );
      expect(
        canvas.nodes.any((n) => n.familyId == 1 && n.id == 'P1-mother'),
        isTrue,
      );
    }

    // 同步结果也留一张全屏实图：家族 B 必须已经出现在 Dialog 里。
    await expectLater(
      find.byType(Dialog),
      matchesGoldenFile('goldens/pedigree_fullscreen_family_added.png'),
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byType(PedigreeCanvas), findsOneWidget);
    // 关闭后直接点选画布节点，证明旧 Dialog 的 StateSetter 已清空；
    // 不依赖大字号下可能滚出视口的「计算下一代」按钮。
    final inline = tester.widget<PedigreeCanvas>(find.byType(PedigreeCanvas));
    inline.onNodeTap!(inline.nodes.first);
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('课堂 ×1.75：算出子代后默认提示收起，连线提示不覆盖缩放条/动作面板',
      (tester) async {
    await pumpPage(tester);

    // v3.7：一旦算出基因型节点，默认模式的长串手势提示整条不渲染
    // （用户原话：「点了计算弹出基因型之后，这个提示就给它消失掉」）。
    expect(
      find.byKey(const Key('pedigree-canvas-hint')),
      findsNothing,
      reason: '默认模式有子代 → 提示条连同外框/内边距一起不占位',
    );

    // 操作态提示不能删：进「连线」模式后提示条必须回来。
    await tester.ensureVisible(find.byKey(GuideKeys.pedigreeWireBtn));
    await tester.pump();
    await tester.tap(find.byKey(GuideKeys.pedigreeWireBtn));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('pedigree-canvas-hint')),
      findsOneWidget,
      reason: '连线模式提示是操作态提示，不随「算出子代」收起',
    );

    Rect rectOf(Key key) => tester.getRect(find.byKey(key));
    final inlineHint = rectOf(const Key('pedigree-canvas-hint'));
    final inlineZoom = rectOf(const Key('pedigree-zoom-bar'));
    expect(
      inlineHint.bottom,
      lessThanOrEqualTo(inlineZoom.top),
      reason: '提示必须完整位于缩放条上方，不能遮住缩放/锁/全屏按钮',
    );

    await openFullscreen(tester);
    final area = tester
        .widgetList<PedigreeCanvasArea>(find.byType(PedigreeCanvasArea))
        .singleWhere((a) => a.fullscreen);
    final areaFinder = find.byWidget(area);
    final hint = tester.getRect(
      find.descendant(
        of: areaFinder,
        matching: find.byKey(const Key('pedigree-canvas-hint')),
      ),
    );
    final zoom = tester.getRect(
      find.descendant(
        of: areaFinder,
        matching: find.byKey(const Key('pedigree-zoom-bar')),
      ),
    );
    final actions = tester.getRect(
      find.descendant(
        of: areaFinder,
        matching: find.byKey(const Key('pedigree-floating-actions')),
      ),
    );
    expect(hint.bottom, lessThanOrEqualTo(zoom.top));
    expect(
      hint.right,
      lessThanOrEqualTo(actions.left),
      reason: '提示与全屏右侧「退出全屏/添加家族/添加样本」区域必须分离',
    );

    await expectLater(
      find.byType(Dialog),
      matchesGoldenFile('goldens/pedigree_fullscreen_hint_clear.png'),
    );
  });
}
