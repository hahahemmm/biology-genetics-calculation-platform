// edge_style_test.dart —— v2.19 连线样式（正交 ↔ 曲线蜘蛛网）测试
//
// 覆盖：
//   1. 默认正交：painter/canvas 收到 PdEdgeStyle.orthogonal
//   2. 侧栏「曲线连线」chip 切换 → curve 透传到画家，且无异常
//   3. 曲线模式渲染冒烟 golden（目测样张——也给用户定手感）

import 'package:biology/engine/pedigree_graph.dart';
import 'package:biology/pages/genetic_pedigree_page.dart';
import 'package:biology/pages/widgets/pedigree_canvas.dart';
import 'package:biology/pages/widgets/pedigree_side_panel.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'golden_fonts.dart';

Widget _app() => const MaterialApp(home: GeneticPedigreePage());

Future<void> _pump(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1000, 800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(_app());
}

Future<void> _derive(WidgetTester tester) async {
  await tester.tap(find.text('计算').first);
  await tester.pumpAndSettle();
  expect(find.byType(PedigreeCanvas), findsOneWidget);
}

PedigreeCanvas _canvas(WidgetTester tester) =>
    tester.widget<PedigreeCanvas>(find.byType(PedigreeCanvas));

/// mating 边的规范化键：忽略端点顺序与组合桶半边后缀（'桶id::male'）。
String _matingKey(String a, String b) {
  final x = a.split('::').first;
  final y = b.split('::').first;
  return x.compareTo(y) <= 0 ? '$x|$y' : '$y|$x';
}

Set<String> _matingKeys(PedigreeCanvas c) => c.edges
    .where((e) => e.kind == PedigreeEdgeKind.mating)
    .map((e) => _matingKey(e.fromId, e.toId))
    .toSet();

/// 点侧栏「连线」chip，并断言模式真的切到 wire。
///
/// 不能用 find.text('连线')：目标是带 avatar 的 FilterChip
/// （pedigree_side_panel.dart:495），框架 _RenderChip.hitTest
/// （chip.dart:1907）会把命中重定向到 label 子件中心，tap 文本因此报
/// "would not hit test" 假警（指针实际仍落到 chip 上）。
Future<void> _tapWireChip(WidgetTester tester) async {
  final chip = find.widgetWithText(FilterChip, '连线');
  expect(chip, findsOneWidget, reason: '侧栏模式区应有「连线」chip');
  await tester.ensureVisible(chip);
  await tester.pumpAndSettle();
  await tester.tap(chip);
  await tester.pumpAndSettle();
  expect(
    tester.widget<PedigreeSidePanel>(find.byType(PedigreeSidePanel)).wireModeOn,
    isTrue,
    reason: '点「连线」后侧栏应进入连线模式（wireModeOn）',
  );
}

/// 右键画布空白 → 添加样本（genderChip：'♂ 雄'/'♀ 雌'/混合默认）。
Future<void> _addExternal(WidgetTester tester, String genderChip,
    {String genotype = 'Aabbcc', String? generation}) async {
  final topLeft = tester.getTopLeft(find.byType(PedigreeCanvas));
  await tester.tapAt(topLeft + const Offset(14, 14),
      buttons: kSecondaryMouseButton);
  await tester.pumpAndSettle();
  await tester.tap(find.text('添加样本').last);
  await tester.pumpAndSettle();
  if (genderChip.isNotEmpty) {
    await tester.tap(find.text(genderChip));
    await tester.pump();
  }
  final field = find.descendant(
      of: find.byType(AlertDialog), matching: find.byType(TextField));
  await tester.enterText(field, genotype);
  if (generation != null) {
    await tester.tap(find.byType(DropdownButtonFormField<int>).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text(generation).last);
    await tester.pumpAndSettle();
  }
  await tester.tap(find.text('添加'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('默认正交 + chip 切换为曲线并透传画家', (tester) async {
    await _pump(tester);
    await _derive(tester);
    expect(_canvas(tester).edgeStyle, PdEdgeStyle.orthogonal,
        reason: '默认正交折线');

    // 侧栏语义区开「曲线连线」。
    await tester.scrollUntilVisible(find.text('曲线连线'), 200,
        scrollable: find.byType(Scrollable).first);
    await tester.tap(find.text('曲线连线'));
    await tester.pumpAndSettle();

    expect(_canvas(tester).edgeStyle, PdEdgeStyle.curve,
        reason: 'chip 切换后曲线样式透传到画布');
    expect(tester.takeException(), isNull);
  });

  testWidgets('切回正交', (tester) async {
    await _pump(tester);
    await _derive(tester);
    await tester.scrollUntilVisible(find.text('曲线连线'), 200,
        scrollable: find.byType(Scrollable).first);
    await tester.tap(find.text('曲线连线'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('曲线连线'));
    await tester.pumpAndSettle();
    expect(_canvas(tester).edgeStyle, PdEdgeStyle.orthogonal);
  });

  testWidgets('v2.19.2 底栏「曲线」chip（>=1200 白板可达入口）',
      (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(_app());
    await tester.tap(find.text('计算').first);
    await tester.pumpAndSettle();
    expect(find.text('曲线'), findsOneWidget,
        reason: '>=1200 底栏模式 segmented 含曲线 chip');

    await tester.tap(find.text('曲线'));
    await tester.pumpAndSettle();
    expect(_canvas(tester).edgeStyle, PdEdgeStyle.curve,
        reason: '底栏 chip 切换生效');
  });

  testWidgets('v2.19.4 曲线样式持久化 round-trip（重进页面恢复曲线）',
      (tester) async {
    // 注入内存 web storage，让持久化路径在 flutter test 下也启用
    //（不碰真实盘）；tearDown 用页面自带的 debugResetHooks 清干净。
    final store = <String, String>{};
    GeneticPedigreePage.debugWebStorage = store;
    GeneticPedigreePage.debugForceIsWebStorage = true;
    addTearDown(GeneticPedigreePage.debugResetHooks);

    await _pump(tester);
    await _derive(tester);
    await tester.scrollUntilVisible(find.text('曲线连线'), 200,
        scrollable: find.byType(Scrollable).first);
    await tester.tap(find.text('曲线连线'));
    await tester.pumpAndSettle();

    expect(store['pedigree_edge_style'], contains('curve'),
        reason: '切曲线应立即落盘');

    // 模拟「退出再进」：整个换掉 widget 树，新实例 initState 重跑
    // _loadEdgeStyle，应把样式恢复回曲线。
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    await tester.pumpWidget(_app());
    await _derive(tester);

    expect(_canvas(tester).edgeStyle, PdEdgeStyle.curve,
        reason: '重进页面后从持久化存储恢复曲线样式');
  });

  testWidgets('曲线模式渲染冒烟（golden 样张：配偶曲线 + 回交 S 曲线）',
      (tester) async {
    await loadGoldenFonts();
    assertMaterialIconsLoaded();
    assertMonoLoaded();

    await _pump(tester);
    await _derive(tester);
    // 加外来雄性样本并开连线模式与 P♀ 跨代连线 → 回交 S 曲线入镜。
    final topLeft = tester.getTopLeft(find.byType(PedigreeCanvas));
    await tester.tapAt(topLeft + const Offset(14, 14),
        buttons: kSecondaryMouseButton);
    await tester.pumpAndSettle();
    await tester.tap(find.text('添加样本').last);
    await tester.pumpAndSettle();
    final field = find.descendant(
        of: find.byType(AlertDialog), matching: find.byType(TextField));
    await tester.enterText(field, 'Aabbcc');
    await tester.tap(find.text('♂ 雄'));
    await tester.pump();
    // 目标世代选 F1 → 与 P♀ 跨代 = 回交边（S 曲线入镜）。
    await tester.tap(find.byType(DropdownButtonFormField<int>).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('F1').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('添加'));
    await tester.pumpAndSettle();

    // 连线模式：P♀ × 外来样本（跨代 → 回交边）。
    await tester.scrollUntilVisible(find.text('连线'), 200,
        scrollable: find.byType(Scrollable).first);
    await _tapWireChip(tester);
    var c = _canvas(tester);
    final pFemale = c.nodes.firstWhere(
        (n) => n.generation == 0 && n.kind == PedigreeNodeKind.female);
    final ext = c.nodes.firstWhere((n) => n.isExternal);
    // 默认 P♂×P♀ 本来就有一条 mating 边——只查 any 会假阳性；
    // 改为比较点击前后的 mating 边集合，并要求新增边端点正是这对。
    final beforeMating = _matingKeys(_canvas(tester));
    c.onNodeTap!(pFemale);
    c.onNodeTap!(ext);
    await tester.pumpAndSettle();
    final addedMating = _matingKeys(_canvas(tester)).difference(beforeMating);
    expect(addedMating, isNotEmpty, reason: 'P♀ × 外来样本应新增 mating 边');
    expect(addedMating, contains(_matingKey(pFemale.id, ext.id)),
        reason: '新增 mating 边端点应是 P♀ 与外来样本（不限顺序）');

    // 连线成功会有约 2 秒橙光双闪——等它自行熄灭再截 goldens，
    // 基线只审曲线样式与锚点，不把闪光录进样张（也会遮住曲线）。
    await tester.pump(const Duration(milliseconds: 2200));
    await tester.pump();
    expect(_canvas(tester).flashIds, isEmpty,
        reason: '截图前橙光必须已消退');

    // 曲线模式。
    await tester.scrollUntilVisible(find.text('曲线连线'), 200,
        scrollable: find.byType(Scrollable).first);
    await tester.tap(find.text('曲线连线'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    await expectLater(
      find.byType(PedigreeCanvas),
      matchesGoldenFile('goldens/edge_curve_style.png'),
    );
  });

  testWidgets('v2.19.7 XY 关时连组合桶→开 XY 端点重算落半边', (tester) async {
    await loadGoldenFonts();
    assertMaterialIconsLoaded();
    assertMonoLoaded();

    await _pump(tester);
    await _derive(tester);
    // 先关 XY（用户场景：XY 关闭期间连线，端点合法落大框…
    await tester.scrollUntilVisible(find.text('XY 性别'), 200,
        scrollable: find.byType(Scrollable).first);
    await tester.tap(find.text('XY 性别'));
    await tester.pumpAndSettle();

    // 两个外来混合桶（XY 关时渲染为单框）。
    await _addExternal(tester, '', genotype: 'Aabbcc');
    await tester.pump(const Duration(seconds: 5));
    await _addExternal(tester, '', genotype: 'aaBbcc');
    await tester.pump(const Duration(seconds: 5));
    await tester.pump();

    // 连线模式：桶A × 桶B → mating(group, group)，fromSex/toSex=null。
    await tester.scrollUntilVisible(find.text('连线'), 200,
        scrollable: find.byType(Scrollable).first);
    // v2.19.14：滚动动画可能未结束（侧栏 chip 变高后可滚），settle
    // 后再 tap——否则 hitTest 撞滚动静默期的 IgnorePointer。
    await tester.pumpAndSettle();
    await _tapWireChip(tester);
    var c = _canvas(tester);
    final groups = c.nodes.where((n) => n.isExternal).toList();
    expect(groups.length, 2, reason: '两个外来混合桶');
    c.onNodeTap!(groups[0]);
    await tester.pump();
    _canvas(tester).onNodeTap!(groups[1]);
    await tester.pump();
    final matings = _canvas(tester)
        .edges
        .where((e) => e.kind == PedigreeEdgeKind.mating)
        .toList();
    expect(matings.length, 2,
        reason: '混合桶互交引擎拆两条配对边（雄A×雌B / 雌A×雄B）');
    // 性别记录可能部分为 null（XY 关时 sexOf(group) 无明确性别）——
    // 渲染层对 null 端按另一端异性推断落半边，两条路径 golden 目检。

    // 同前：等约 2 秒橙光熄灭，golden 只审锚点/曲线，不录闪光。
    await tester.pump(const Duration(milliseconds: 2200));
    await tester.pump();
    expect(_canvas(tester).flashIds, isEmpty,
        reason: '截图前橙光必须已消退');

    // …再开 XY：连线逻辑必须随开关重算——端点按异性推断落回半边
    // glyph（不残留大框锚点）、边不丢、不炸。
    await tester.scrollUntilVisible(find.text('XY 性别'), 200,
        scrollable: find.byType(Scrollable).first);
    await tester.tap(find.text('XY 性别'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull, reason: '开 XY 后半边端点重算');
    expect(
        _canvas(tester)
            .edges
            .any((e) => e.kind == PedigreeEdgeKind.mating),
        isTrue,
        reason: '开关切换不丢 mating 边');

    // 曲线模式渲染（golden 目检：配偶线端点应各落桶内半边 glyph）。
    await tester.scrollUntilVisible(find.text('曲线连线'), 200,
        scrollable: find.byType(Scrollable).first);
    await tester.tap(find.text('曲线连线'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    await expectLater(
      find.byType(PedigreeCanvas),
      matchesGoldenFile('goldens/mating_group_half_anchor.png'),
    );
  });
}
