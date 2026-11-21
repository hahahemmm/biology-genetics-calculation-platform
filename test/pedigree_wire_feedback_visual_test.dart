// pedigree_wire_feedback_visual_test.dart —— 大屏连线反馈三连图
//
// 只看状态变量不足以发现「橙色双闪后普通选中光仍常驻」这类问题。
// 本组在 1920×1080 逻辑视口记录 A 待命、AB 双闪、自动熄灭三个时刻，
// 供逐张目检；真实指针与多点触控由 pedigree_touch_test.dart 覆盖。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:biology/engine/pedigree_graph.dart';
import 'package:biology/pages/genetic_pedigree_page.dart';
import 'package:biology/pages/widgets/pedigree_canvas.dart';
import 'package:biology/pages/widgets/pedigree_side_panel.dart';
import 'package:biology/theme.dart';

import 'golden_fonts.dart';

void main() {
  const boundaryKey = Key('wire-feedback-visual');

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
        home: const RepaintBoundary(
          key: boundaryKey,
          child: GeneticPedigreePage(),
        ),
      ),
    );
    await tester.tap(find.text('计算').first);
    await tester.pumpAndSettle();
    final chip = find.widgetWithText(FilterChip, '连线');
    expect(chip, findsAtLeastNWidgets(1));
    await tester.tap(chip.first);
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<PedigreeSidePanel>(find.byType(PedigreeSidePanel))
          .wireModeOn,
      isTrue,
    );
  }

  PedigreeCanvas canvas(WidgetTester tester) =>
      tester.widget<PedigreeCanvas>(find.byType(PedigreeCanvas));

  testWidgets('大屏连线：A 紫色待命 → AB 橙色双闪 → 一起熄灭', (tester) async {
    await pumpPage(tester);
    var c = canvas(tester);
    final a = c.nodes.firstWhere((n) => n.id == 'P-father');
    final b = c.nodes.firstWhere(
      (n) => n.kind == PedigreeNodeKind.group && n.generation == 1,
    );

    c.onNodeTap!(a);
    await tester.pump();
    expect(canvas(tester).armedId, a.id);
    await expectLater(
      find.byKey(boundaryKey),
      matchesGoldenFile('goldens/wire_feedback_01_armed.png'),
    );

    c = canvas(tester);
    c.onNodeTap!(b);
    // 不用 pumpAndSettle：它会等完闪光 Timer，截不到双闪瞬间。
    await tester.pump(const Duration(milliseconds: 250));
    expect(canvas(tester).flashIds, containsAll([a.id, b.id]));
    await expectLater(
      find.byKey(boundaryKey),
      matchesGoldenFile('goldens/wire_feedback_02_flash.png'),
    );

    await tester.pump(const Duration(milliseconds: 2400));
    expect(canvas(tester).flashIds, isEmpty);
    expect(canvas(tester).armedId, isNull);
    await expectLater(
      find.byKey(boundaryKey),
      matchesGoldenFile('goldens/wire_feedback_03_cleared.png'),
    );
  });
}
