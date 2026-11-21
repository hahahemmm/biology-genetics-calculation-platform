// population_growth_visual_test.dart —— 进化页「种群增长」视觉基线
//
// 只产出本切片的新基线（population_growth_*.png）：桌面浅色 / 桌面深色 /
// 390 手机（含图表）。⛔ 不改任何既有 golden（进化页旧 5 tab 的基线一律不动）。
// 真实 AppTheme.light/dark + 中文/等宽字体；新增或更新后必须逐张目检，
// 不得整批接受。
import 'package:biology/charts/population_growth_chart.dart';
import 'package:biology/pages/evolution_page.dart';
import 'package:biology/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'golden_fonts.dart';

void main() {
  Future<void> boot(
    WidgetTester tester,
    Size size, {
    bool dark = false,
  }) async {
    await loadGoldenFonts();
    assertMaterialIconsLoaded();
    assertMonoLoaded();
    // KaTeX 公式字形守卫（像素级）：5 条教学公式必须渲染真字形、不是 .notdef
    // 方框。放在 golden 拍摄前 —— AST 断言拦不住"整屏公式变方框"，见
    // golden_fonts.dart 的 assertKatexGlyphsLoaded。
    await assertKatexGlyphsLoaded(tester);
    AppColors.sync(dark ? Brightness.dark : Brightness.light);
    addTearDown(() => AppColors.sync(Brightness.light));
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: dark ? AppTheme.dark() : AppTheme.light(),
        home: const EvolutionPage(),
      ),
    );
    await tester.pumpAndSettle();
    final growthTab = find.descendant(
        of: find.byType(TabBar), matching: find.text('种群增长'));
    await tester.ensureVisible(growthTab);
    await tester.tap(growthTab);
    await tester.pumpAndSettle();
    expect(find.textContaining('J 型与 S 型对照曲线'), findsOneWidget,
        reason: '默认例必须已经算出结果（否则拍的是空屏）');
    expect(find.textContaining('J 型末代 1297.46'), findsOneWidget);
  }

  testWidgets('桌面浅色：种群增长（J/S 对照 + 逐代表格）', (tester) async {
    await boot(tester, const Size(1440, 1000));
    expect(tester.takeException(), isNull);
    await expectLater(
      find.byType(EvolutionPage),
      matchesGoldenFile('goldens/population_growth_desktop.png'),
    );
  });

  testWidgets('桌面深色：种群增长保持对比', (tester) async {
    await boot(tester, const Size(1440, 1000), dark: true);
    expect(tester.takeException(), isNull);
    await expectLater(
      find.byType(EvolutionPage),
      matchesGoldenFile('goldens/population_growth_dark.png'),
    );
  });

  testWidgets('手机 390：种群增长含图表，零溢出', (tester) async {
    await boot(tester, const Size(390, 844));
    expect(tester.takeException(), isNull);
    await expectLater(
      find.byType(EvolutionPage),
      matchesGoldenFile('goldens/population_growth_mobile.png'),
    );
  });

  testWidgets('手机 390：滚到图表，J/S 曲线 + K/K2 + x 轴单位真实可见',
      (tester) async {
    await boot(tester, const Size(390, 844));
    final chart = find.byType(PopulationGrowthChart);
    expect(chart, findsOneWidget);
    await tester.ensureVisible(chart);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    // 图表必须真的进了可视区（不是只露出标题）：整块落在 390×844 内。
    final rect = tester.getRect(chart);
    expect(rect.top, greaterThanOrEqualTo(-1));
    expect(rect.bottom, lessThanOrEqualTo(844 + 1),
        reason: '图表本体必须完整可见（标题露出不算图表验收）');
    expect(rect.width, lessThanOrEqualTo(390 + 1), reason: '390 宽不得横溢出');

    await expectLater(
      find.byType(EvolutionPage),
      matchesGoldenFile('goldens/population_growth_mobile_chart.png'),
    );
  });

  // ── 速率区（_rateSection）视觉守卫 ──────────────────────────────────────
  //
  // 为什么单独几张图：_rateSection 在折叠线以下，既有的 4 张 population
  // golden 只覆盖到 J/S 通式，**绝对/相对速率与 J 增量三条公式从未进过图**。
  // 这里滚动到速率区、先断言三条公式都真的在可视区（不是只截区块标题），
  // 再拍 golden。三张基线：浅色桌面 / 手机（含横向滚动边界）/ 深色桌面
  //（KaTeX 公式深底浅字的对比必须单独回归）。⛔ 新增/修改公式后必须逐张目检。
  testWidgets('桌面浅色：速率区（绝对/相对/J 增量公式真实可见，非只截标题）',
      (tester) async {
    await boot(tester, const Size(1440, 1000));
    await _revealAndAssertRateFormulas(tester, viewportHeight: 1000);
    await expectLater(
      find.byType(EvolutionPage),
      matchesGoldenFile('goldens/population_growth_rates_desktop.png'),
    );
  });

  testWidgets('手机 390：速率区公式 + 横向滚动边界可见', (tester) async {
    await boot(tester, const Size(390, 844));
    await _revealAndAssertRateFormulas(tester, viewportHeight: 844);

    // 让「公式只在本行内横向滚动」这件事在图里可见：把绝对速率公式的横向
    // 滚动拖开一小段，公式左右都被容器边缘裁切 ⇒ 滚动边界一目了然，也证明
    // 它不是被整体缩放塞进 390。
    await tester.drag(find.byKey(_kRateAbs), const Offset(-72, 0));
    await tester.pumpAndSettle();
    _assertInView(tester, _kRateAbs, viewportHeight: 844);
    _assertInView(tester, _kRateRel, viewportHeight: 844);
    _assertInView(tester, _kRateInc, viewportHeight: 844);
    expect(tester.takeException(), isNull);
    await expectLater(
      find.byType(EvolutionPage),
      matchesGoldenFile('goldens/population_growth_rates_mobile.png'),
    );
  });

  // 【覆盖缺口】速率区此前只有浅色（desktop）与手机（mobile）基线，没有深色。
  // KaTeX 公式的颜色走 AppColors.ink（深色下 = inkD 暖米白），深底浅字的对比
  // 必须有一张独立基线才能回归——浅色基线检不出「深色公式仍是深字（看不见）」。
  testWidgets('桌面深色：速率区（绝对/相对/J 增量公式在深底浅字下真实可见）',
      (tester) async {
    await boot(tester, const Size(1440, 1000), dark: true);
    await _revealAndAssertRateFormulas(tester, viewportHeight: 1000);
    expect(tester.takeException(), isNull);
    await expectLater(
      find.byType(EvolutionPage),
      matchesGoldenFile('goldens/population_growth_rates_dark.png'),
    );
  });
}

/// 速率区三条公式（population_growth_lab.dart 里 TexFormula 的 key）。
const Key _kRateAbs = Key('tex-rate-absolute');
const Key _kRateRel = Key('tex-rate-relative');
const Key _kRateInc = Key('tex-j-increment');

/// 把速率区滚进可视区，并断言三条公式都完整落在 [viewportHeight] 内。
///
/// [ensureVisible] 会级联滚动所有祖先滚动容器；abs/rel 相邻、inc 在其下两行
/// 文本之后，整段 span 远小于视口高度，故先 abs 再 inc 各滚一次即可让三者
/// 同时在视口内。
Future<void> _revealAndAssertRateFormulas(WidgetTester tester,
    {required double viewportHeight}) async {
  await tester.ensureVisible(find.byKey(_kRateAbs));
  await tester.pumpAndSettle();
  await tester.ensureVisible(find.byKey(_kRateInc));
  await tester.pumpAndSettle();

  _assertInView(tester, _kRateAbs, viewportHeight: viewportHeight);
  _assertInView(tester, _kRateRel, viewportHeight: viewportHeight);
  _assertInView(tester, _kRateInc, viewportHeight: viewportHeight);
  expect(tester.takeException(), isNull);
}

/// 断言单条公式完整落在纵向视口内（顶部 ≥0、底部 ≤视口高、宽度 >0）。
void _assertInView(WidgetTester tester, Key key,
    {required double viewportHeight}) {
  final f = find.byKey(key);
  expect(f, findsOneWidget, reason: '公式 $key 必须在树里');
  final rect = tester.getRect(f);
  expect(rect.top, greaterThanOrEqualTo(-1),
      reason: '公式 $key 顶部须在视口内（只截区块标题不算）');
  expect(rect.bottom, lessThanOrEqualTo(viewportHeight + 1),
      reason: '公式 $key 底部须在视口内（只截区块标题不算）');
  expect(rect.width, greaterThan(0), reason: '公式 $key 必须有实际宽度');
}
