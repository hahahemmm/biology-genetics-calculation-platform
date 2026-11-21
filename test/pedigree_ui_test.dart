// pedigree_ui_test.dart —— 计算页 UI 层 widget 测试（T-B3）
//
// 覆盖：R5 计算出 F1 / R6 再计算一代 / R3 右键空白添加样本 / R4 非法连线提示。

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:biology/engine/pedigree_graph.dart';
import 'package:biology/pages/genetic_pedigree_page.dart';
import 'package:biology/pages/widgets/pedigree_canvas.dart';
import 'package:biology/pages/widgets/pedigree_side_panel.dart';
import 'package:biology/theme.dart';

Widget _app() => const MaterialApp(home: GeneticPedigreePage());

/// v3.1：左控制面板使页面内容更高，测试视口从默认 800×600 提到
/// 800×800，保证面板底部「画布」动作按钮在可视区内可点。
Future<void> pumpHome(WidgetTester tester) async {
  // v2.19.27：系谱面板占位/覆盖阈值 720→900——800 宽由占位式变为
  // 覆盖式（平板竖屏语义），这两个测试按占位式布局断言，视口升到 1000。
  tester.view.physicalSize = const Size(1000, 800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(_app());
}



PedigreeCanvas _canvas(WidgetTester tester) =>
    tester.widget<PedigreeCanvas>(find.byType(PedigreeCanvas));

int _maxGen(PedigreeCanvas c) =>
    c.nodes.fold(0, (m, n) => n.generation > m ? n.generation : m);


/// v2.19.10：侧栏 chip 去 shrinkWrap 后体积变大，部分滚出窄视口——
/// tap 前先滚到可见再 ensureVisible，防 hitTest miss。
Future<void> _tapChip(WidgetTester tester, String label) async {
  await tester.scrollUntilVisible(find.text(label), 150,
      scrollable: find.byType(Scrollable).first);
  await tester.ensureVisible(find.text(label));
  await tester.pump();
  await tester.tap(find.text(label));
}

Future<void> _derive(WidgetTester tester) async {
  // v3：页面有两颗「计算」（语义开关行最左 + 底部操作条），任点一颗即可
  await tester.tap(find.text('计算').first);
  await tester.pumpAndSettle();
  expect(find.byType(PedigreeCanvas), findsOneWidget);
}

/// 切换侧栏「连线」FilterChip，并硬断言目标模式确实生效。
///
/// 不能只 tap find.text('连线')：带 avatar 的 FilterChip 会把文本中心的
/// 命中重定向到 label 子件，Flutter 因此报 "would not hit test" 假警。
/// 直接点整个 chip 既不消音，也能证明点击与状态切换都真的发生。
Future<void> _tapWireMode(WidgetTester tester, bool turnOn) async {
  final chip = find.widgetWithText(FilterChip, '连线');
  expect(chip, findsOneWidget, reason: '侧栏应有唯一「连线」FilterChip');
  await tester.tap(chip);
  await tester.pumpAndSettle();
  expect(
    tester.widget<PedigreeSidePanel>(find.byType(PedigreeSidePanel)).wireModeOn,
    turnOn,
    reason: '点击后 wireModeOn 必须变为 $turnOn',
  );
}

/// R15：连线不再是常驻——先点「连线」chip 进入连线模式（chip 发光）。
Future<void> _enableWire(WidgetTester tester) => _tapWireMode(tester, true);

/// 退出连线模式；同时验证没有停留在 wire 状态。
Future<void> _disableWire(WidgetTester tester) => _tapWireMode(tester, false);

void main() {
  testWidgets('「计算」后出现 F1 节点（R5）', (tester) async {
    await pumpHome(tester);
    await _derive(tester);
    final c = _canvas(tester);
    expect(c.nodes.any((n) => n.generation == 1), isTrue,
        reason: '计算后应展开 F1');
    // P 代双亲：一雄一雌
    expect(c.nodes.any((n) => n.generation == 0 && n.kind == PedigreeNodeKind.male),
        isTrue);
    expect(
        c.nodes.any(
            (n) => n.generation == 0 && n.kind == PedigreeNodeKind.female),
        isTrue);
  });

  testWidgets('「再计算一代」增加一世代（R6）', (tester) async {
    await pumpHome(tester);
    await _derive(tester);
    final before = _maxGen(_canvas(tester));
    await tester.tap(find.text('计算下一代'));
    await tester.pumpAndSettle();
    expect(_maxGen(_canvas(tester)), before + 1);
  });

  testWidgets('右键空白弹出「添加样本」并可添加（R3）', (tester) async {    await pumpHome(tester);
    await _derive(tester);
    final before = _canvas(tester).nodes.length;

    // 画布左上角空白处右键（避开节点与覆盖层按钮）
    final finder = find.byType(PedigreeCanvas);
    final topLeft = tester.getTopLeft(finder);
    await tester.tapAt(topLeft + const Offset(14, 14),
        buttons: kSecondaryMouseButton);
    await tester.pumpAndSettle();
    expect(find.text('添加样本'), findsNWidgets(2)); // 常驻按钮 + 右键菜单项

    await tester.tap(find.text('添加样本').last);
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);

    final field = find.descendant(
        of: find.byType(AlertDialog), matching: find.byType(TextField));
    await tester.enterText(field, 'AaBbCc');
    await tester.tap(find.text('添加'));
    await tester.pumpAndSettle();

    final after = _canvas(tester).nodes;
    expect(after.length, before + 1, reason: '应新增一个外来样本节点');
    expect(after.any((n) => n.isExternal && n.genotype == 'AaBbCc'), isTrue);
  });

  testWidgets('v2.18 多连线选择性收回：长按 → 底缘选择器 → 只摘选中的那条',
      (tester) async {
    await pumpHome(tester);
    await _derive(tester);

    // 两个外来雌性样本（与 P♂ 异性可连）。第二次右键换空白位——
    // 第一个样本就出生在左上空白处，原坐标会命中它弹出节点菜单。
    final blankSpots = [const Offset(14, 14), const Offset(14, 480)];
    var spotIdx = 0;
    for (final g in ['AaBbCc', 'Aabbcc']) {
      final topLeft = tester.getTopLeft(find.byType(PedigreeCanvas));
      await tester.tapAt(topLeft + blankSpots[spotIdx++],
          buttons: kSecondaryMouseButton);
      await tester.pumpAndSettle();
      await tester.tap(find.text('添加样本').last);
      await tester.pumpAndSettle();
      final field = find.descendant(
          of: find.byType(AlertDialog), matching: find.byType(TextField));
      await tester.enterText(field, g);
      await tester.tap(find.text('♀ 雌'));
      await tester.pump();
      await tester.tap(find.text('添加'));
      await tester.pumpAndSettle();
    }

    PedigreeNode node(bool Function(PedigreeNode) test) => _canvas(tester)
        .nodes
        .firstWhere(test);

    final pMale = node((n) =>
        n.generation == 0 && n.kind == PedigreeNodeKind.male);
    final ext1 = node((n) => n.isExternal && n.genotype == 'AaBbCc');
    final ext2 = node((n) => n.isExternal && n.genotype == 'Aabbcc');

    bool touches(PedigreeEdge e, String id) =>
        e.fromId == id || e.toId == id;

    // P♂ 初始与 P♀ 相连；再连两个外来样本 → 共 3 条。
    await _enableWire(tester);
    var c = _canvas(tester);
    c.onNodeTap!(pMale);
    c.onNodeTap!(ext1);
    await tester.pump();
    c = _canvas(tester);
    c.onNodeTap!(pMale);
    c.onNodeTap!(ext2);
    await tester.pump();
    c = _canvas(tester);
    expect(
        c.edges
            .where((e) =>
                e.kind == PedigreeEdgeKind.mating && touches(e, pMale.id))
            .length,
        3,
        reason: 'P♂ 应挂 3 条 mating 边（P♀ + 两个外来样本）');

    // 长按 P♂ → 底缘选择器（多条连线不再一刀切）。
    _canvas(tester).onWireDetach!(pMale);
    await tester.pumpAndSettle();
    expect(find.textContaining('收回哪一条'), findsOneWidget,
        reason: '多条连线弹选择性收回选择器');

    // 只摘与 ext1（AaBbCc）的那条。
    await tester.tap(find.textContaining('与 AaBbCc').first);
    await tester.pumpAndSettle();

    final remaining = _canvas(tester)
        .edges
        .where((e) => e.kind == PedigreeEdgeKind.mating && touches(e, pMale.id))
        .toList();
    expect(remaining.length, 2, reason: '只摘一条，剩两条');
    expect(remaining.any((e) => touches(e, ext1.id)), isFalse,
        reason: '被选中的那条已摘');
    expect(remaining.any((e) => touches(e, ext2.id)), isTrue,
        reason: '其余保留');
  });

  testWidgets('v2.18 单连线长按直接收回（不弹选择器）', (tester) async {
    await pumpHome(tester);
    await _derive(tester);
    // P♂ 仅与 P♀ 相连（初始态）。
    final pMale = _canvas(tester)
        .nodes
        .firstWhere((n) => n.generation == 0 && n.kind == PedigreeNodeKind.male);
    _canvas(tester).onWireDetach!(pMale);
    await tester.pumpAndSettle();
    expect(find.textContaining('收回哪一条'), findsNothing,
        reason: '单条连线保持爽快直删，不弹选择器');
    final remaining = _canvas(tester)
        .edges
        .where((e) =>
            e.kind == PedigreeEdgeKind.mating &&
            (e.fromId == pMale.id || e.toId == pMale.id))
        .length;
    expect(remaining, 0, reason: '唯一一条已被收回');
  });

  testWidgets('v2.18 全屏 Dialog：双画布共存不炸 + ESC 可退（P0 回归）',
      (tester) async {
    await pumpHome(tester);
    await _derive(tester);
    expect(find.byType(PedigreeCanvas), findsOneWidget,
        reason: '内嵌画布在树');

    // 点开全屏（<1200 宽时入口在侧栏画布区）。
    await tester.ensureVisible(find.text('全屏'));
    await tester.pump();
    await tester.tap(find.text('全屏'));
    await tester.pumpAndSettle();

    // P0 根因 = 内嵌与全屏共用同一 GlobalKey → duplicate key 炸树变灰。
    // 修复后：两个画布实例共存且都正常构建。
    expect(find.byType(PedigreeCanvas), findsNWidgets(2),
        reason: '内嵌 + 全屏 Dialog 两实例共存');
    expect(tester.takeException(), isNull, reason: '无 duplicate GlobalKey');

    // ESC 退出全屏（CallbackShortcuts 已绑定）。
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byType(PedigreeCanvas), findsOneWidget,
        reason: 'ESC 退出全屏，回到单实例');
  });

  testWidgets('点选-点选连线：待命紫光 → 非法配对有 SnackBar 提示', (tester) async {
    await pumpHome(tester);
    await _derive(tester);
    await _enableWire(tester);
    var c = _canvas(tester);
    final father = c.nodes.firstWhere((n) => n.id == 'P-father');

    // 点 P-father → 待命（armedId 挂上）
    c.onNodeTap!(father);
    await tester.pump();
    expect(_canvas(tester).armedId, 'P-father', reason: '点选后应进入待命');

    // 再点自己 → 解除待命，不产生边、不报错
    c = _canvas(tester);
    c.onNodeTap!(father);
    await tester.pump();
    expect(_canvas(tester).armedId, isNull, reason: '再点自己应解除待命');

    // 添加外来雄性样本，P♂ × EXT♂（同性，默认禁连）→ 提示「同性交配」
    // （v2.19.5 性别互斥前置拦截，文案从引擎「无法连线」改为明确告知）
    final finder = find.byType(PedigreeCanvas);
    final topLeft = tester.getTopLeft(finder);
    await tester.tapAt(topLeft + const Offset(14, 14),
        buttons: kSecondaryMouseButton);
    await tester.pumpAndSettle();
    await tester.tap(find.text('添加样本').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('♂ 雄')); // R17 起默认是混合，本测试要雄性
    await tester.pump();
    final field = find.descendant(
        of: find.byType(AlertDialog), matching: find.byType(TextField));
    await tester.enterText(field, 'AaBbCc');
    await tester.tap(find.text('添加'));
    await tester.pumpAndSettle();
    // 冲掉「已添加样本」Snackbar（占 4s 栏位，后续 toast 会排队）
    await tester.pump(const Duration(seconds: 5));
    await tester.pump();

    c = _canvas(tester);
    final extMale = c.nodes.firstWhere((n) => n.isExternal);
    final edgesBefore = c.edges.length;
    c.onNodeTap!(father); // 待命
    await tester.pump();
    c = _canvas(tester);
    c.onNodeTap!(extMale); // 尝试连线 → 非法
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // v2.19.6 polish（学生走查 #3）后 toast 骨架为「同性交配 · {开/关}
    // · {后果}」——snackbar 文本统一包含「同性交配」与「关」。
    // 注意：chip / tooltip / 按钮也可能含「同性交配」字样，故断言
    // 限定在 SnackBar descendant 里精确匹配（chip 多年都没出现过这种
    // 状态字面冲突，这是 fragment 内查看语义对错用的容忍度）。
    final inSnack = find.descendant(
        of: find.byType(SnackBar), matching: find.textContaining('同性交配'));
    expect(inSnack, findsOneWidget,
        reason: '应弹同性交配 toast（_toast 走 ScaffoldMessenger）');
    expect(inSnack.evaluate().single.widget, isA<Text>(),
        reason: 'SnackBar 内应只有一条同性交配提示文本');
    final txt = (inSnack.evaluate().single.widget as Text).data!;
    expect(txt, contains('关'), reason: 'toast 应明确同性交配当前是「关」');
    expect(_canvas(tester).edges.length, edgesBefore, reason: '非法连线不应产生新边');
    expect(_canvas(tester).armedId, 'P-father', reason: '失败后保持待命，可另选目标');
  });

  testWidgets('v2.19.5 性别互斥：待命雄性时其他雄性 dim、雌性亮起', (tester) async {
    await pumpHome(tester);
    await _derive(tester);
    await _enableWire(tester);

    // 添加外来雄性样本（画布上有 P♂ P♀ 之外的多余雄性）。
    final finder = find.byType(PedigreeCanvas);
    final topLeft = tester.getTopLeft(finder);
    await tester.tapAt(topLeft + const Offset(14, 14),
        buttons: kSecondaryMouseButton);
    await tester.pumpAndSettle();
    await tester.tap(find.text('添加样本').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('♂ 雄'));
    await tester.pump();
    final field = find.descendant(
        of: find.byType(AlertDialog), matching: find.byType(TextField));
    await tester.enterText(field, 'AaBbCc');
    await tester.tap(find.text('添加'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 5));
    await tester.pump();

    var c = _canvas(tester);
    final father = c.nodes.firstWhere((n) => n.id == 'P-father');
    final mother = c.nodes.firstWhere((n) => n.id == 'P-mother');
    final extMale = c.nodes.firstWhere((n) => n.isExternal);

    // 未待命 → 无 dim。
    expect(c.dimIds, isEmpty, reason: '待命未定点：全部亮起');

    // 点 P♂ 待命 → 其他雄性（外来样本）dim；P♀ 与起点自身不 dim。
    c.onNodeTap!(father);
    await tester.pump();
    c = _canvas(tester);
    expect(c.armedId, 'P-father');
    expect(c.dimIds.contains(extMale.id), isTrue,
        reason: '同性（外来雄性）应变暗');
    expect(c.dimIds.contains(mother.id), isFalse,
        reason: '异性（P♀）保持亮起');
    expect(c.dimIds.contains(father.id), isFalse,
        reason: '待命起点自身保持亮起');

    // 解除待命（再点自己）→ 改点 P♀ 待命 → 画布无其他雌性，dim 空；
    // 雄性（P♂/外来）是可连接目标，保持亮起。
    c = _canvas(tester);
    c.onNodeTap!(father);
    await tester.pump();
    expect(_canvas(tester).armedId, isNull, reason: '再点自己解除待命');

    c = _canvas(tester);
    c.onNodeTap!(mother);
    await tester.pump();
    c = _canvas(tester);
    expect(c.armedId, 'P-mother');
    expect(c.dimIds, isEmpty, reason: '雌性待命：无其他雌性，dim 为空');
    expect(c.dimIds.contains(father.id), isFalse,
        reason: '雄性是可连接目标，不 dim');
  });

  testWidgets('回交（跨代点选连线）被允许：双节点闪橙光 + 提示', (tester) async {
    await pumpHome(tester);
    await _derive(tester);
    await _enableWire(tester);
    var c = _canvas(tester);
    final male = c.nodes.firstWhere((n) => n.kind == PedigreeNodeKind.male);
    final group = c.nodes.firstWhere((n) => n.kind == PedigreeNodeKind.group);

    // P♂（待命） × F1 group：跨代回交 → 合法
    final edgesBefore = c.edges.length;
    c.onNodeTap!(male);
    await tester.pump();
    c = _canvas(tester);
    c.onNodeTap!(group);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.textContaining('已建立回交连线'), findsOneWidget);
    c = _canvas(tester);
    expect(c.edges.length, edgesBefore + 1, reason: '回交应产生新 mating 边');
    expect(c.armedId, isNull, reason: '连线成功后待命清除');
    expect(c.flashIds, containsAll([male.id, group.id]),
        reason: '连线成功双节点闪橙光');
    // 2026-10-27：wire 只由 armed/flash 承担反馈，不夹带普通选中/相连光。
    expect(c.selectedId, isNull, reason: 'wire 不传普通选中光');
    expect(c.connectedIds, isEmpty, reason: 'wire 不传相连柔光');

    // 橙光约 2 秒后自行熄灭（旧 1 秒手感已改长）
    await tester.pump(const Duration(milliseconds: 1100));
    expect(_canvas(tester).flashIds, isNotEmpty, reason: '1.1 秒时仍在闪');
    await tester.pump(const Duration(milliseconds: 1100));
    expect(_canvas(tester).flashIds, isEmpty, reason: '约 2 秒后完全消退');
  });

  // ── wire 视觉反馈隔离（2026-10-27 用户裁定，恢复旧紫/橙手感）────────
  //
  // 用户实际截图：连线/选择反馈退化成「一堆相同的绿色勾」，看不出
  // A→B。根因 = wire 分支同时写 selected/connected，成功闪光后 B 的
  // 普通高亮常驻，且 select 的绿勾会跟着模式切换残留。本组硬断言：
  // wire 只认 armed(紫) / flash(橙)，二者按时自行熄灭，不跨轮、不跨模式。
  group('wire 视觉反馈隔离', () {
    testWidgets('A 紫待命 → AB 橙闪 → 约 2 秒一起熄灭；全程不传 selected/connected',
        (tester) async {
      await pumpHome(tester);
      await _derive(tester);
      await _enableWire(tester);

      var c = _canvas(tester);
      final a = c.nodes.firstWhere((n) => n.id == 'P-father');
      final b = c.nodes.firstWhere((n) => n.kind == PedigreeNodeKind.group);
      expect(c.selectedId, isNull, reason: '进入 wire 无普通选中光');
      expect(c.connectedIds, isEmpty, reason: '进入 wire 无相连柔光');
      expect(c.pickedIds, isEmpty, reason: 'wire 无选择绿勾');

      // 点 A → A 紫色待命（画布 armedId 走 AppColors.armed 紫罗兰）
      c.onNodeTap!(a);
      await tester.pump();
      c = _canvas(tester);
      expect(c.armedId, a.id, reason: 'A 进入待命，画布据此上紫光');
      expect(c.flashIds, isEmpty, reason: '待命阶段不闪橙');
      expect(c.selectedId, isNull, reason: '待命不夹带普通选中光');
      expect(c.connectedIds, isEmpty, reason: '待命不夹带相连柔光');

      // 语义 token 必须是用户要的旧「紫待命 / 橙双闪」，不得换浅绿。
      expect(AppColors.armedL, const Color(0xFF7C3AED),
          reason: '待命光 token = 紫罗兰');
      expect(AppColors.flashL, const Color(0xFFD97706),
          reason: '闪光 token = 琥珀橙');

      // 再点合法 B → AB 橙色双闪，armed 立刻清空
      c.onNodeTap!(b);
      await tester.pump();
      c = _canvas(tester);
      expect(c.flashIds, equals({a.id, b.id}), reason: 'A/B 同时闪橙');
      expect(c.armedId, isNull, reason: '闪光开始即结束待命');
      expect(c.selectedId, isNull, reason: '闪光不夹带普通选中光');
      expect(c.connectedIds, isEmpty, reason: '闪光不夹带相连柔光');

      // 1.1 秒仍在闪（证明不是旧的 1 秒手感）
      await tester.pump(const Duration(milliseconds: 1100));
      expect(_canvas(tester).flashIds, equals({a.id, b.id}),
          reason: '1.1 秒时仍应可见（约 2 秒才消退）');

      // 约 2 秒后一起熄灭，且不留下任何常驻光
      await tester.pump(const Duration(milliseconds: 1100));
      c = _canvas(tester);
      expect(c.flashIds, isEmpty, reason: '约 2 秒后双闪完全消退');
      expect(c.armedId, isNull);
      expect(c.selectedId, isNull, reason: '闪光后不得留下普通选中光');
      expect(c.connectedIds, isEmpty, reason: '闪光后不得留下相连柔光');
      expect(c.pickedIds, isEmpty, reason: 'wire 全程无绿勾');
    });

    testWidgets('连续第二轮：新一轮待命/闪光不残留上一轮节点', (tester) async {
      await pumpHome(tester);
      await _derive(tester);
      await _enableWire(tester);

      var c = _canvas(tester);
      final father = c.nodes.firstWhere((n) => n.id == 'P-father');
      final mother = c.nodes.firstWhere((n) => n.id == 'P-mother');
      final group = c.nodes.firstWhere((n) => n.kind == PedigreeNodeKind.group);

      // 第一轮：P♂ × F1 group（回交）
      c.onNodeTap!(father);
      await tester.pump();
      c = _canvas(tester);
      c.onNodeTap!(group);
      await tester.pump();
      expect(_canvas(tester).flashIds, equals({father.id, group.id}));

      // 橙光窗口内立刻开始第二轮：上一轮必须当场收掉，不得同屏叠加
      await tester.pump(const Duration(milliseconds: 300));
      c = _canvas(tester);
      c.onNodeTap!(mother);
      await tester.pump();
      c = _canvas(tester);
      expect(c.armedId, mother.id, reason: '新一轮重新待命');
      expect(c.flashIds, isEmpty, reason: '新一轮待命立即收掉上一轮闪光');
      expect(c.selectedId, isNull);

      c.onNodeTap!(group);
      await tester.pump();
      c = _canvas(tester);
      expect(c.flashIds, equals({mother.id, group.id}),
          reason: '第二轮只闪本轮两端');
      expect(c.flashIds.contains(father.id), isFalse,
          reason: '上一轮的 P♂ 不得跟进闪光');
      expect(c.armedId, isNull);

      await tester.pump(const Duration(milliseconds: 2100));
      c = _canvas(tester);
      expect(c.flashIds, isEmpty, reason: '第二轮同样自行消退');
      expect(c.armedId, isNull);
      expect(c.selectedId, isNull);
      expect(c.connectedIds, isEmpty);
    });

    testWidgets('选择绿勾不混入 wire；进出 wire 清掉浏览态选中/相连光',
        (tester) async {
      await pumpHome(tester);
      await _derive(tester);

      // 浏览态选中 → 普通选中光 + 相连柔光（这两层属于浏览态）
      var c = _canvas(tester);
      final father = c.nodes.firstWhere((n) => n.id == 'P-father');
      final mother = c.nodes.firstWhere((n) => n.id == 'P-mother');
      c.onNodeTap!(father);
      await tester.pump();
      c = _canvas(tester);
      expect(c.selectedId, father.id);
      expect(c.connectedIds, isNotEmpty);

      // 进入 wire → 浏览态两层光都不得跨模式带进来
      await _enableWire(tester);
      c = _canvas(tester);
      expect(c.selectedId, isNull, reason: '进入 wire 清掉普通选中光');
      expect(c.connectedIds, isEmpty, reason: '进入 wire 清掉相连柔光');
      expect(c.armedId, isNull);
      expect(c.flashIds, isEmpty);

      // 选择模式：勾两个节点 → 绿勾（pickedIds）生效
      await tester.tap(find.text('选择元素'));
      await tester.pumpAndSettle();
      c = _canvas(tester);
      expect(c.pickedIds, isEmpty);
      c.onNodeTap!(father);
      await tester.pump();
      _canvas(tester).onNodeTap!(mother);
      await tester.pump();
      expect(_canvas(tester).pickedIds.length, 2, reason: '选择模式绿勾生效');

      // 再进 wire → 绿勾不得显示，wire 从「无待命」重新开始
      await _enableWire(tester);
      c = _canvas(tester);
      expect(c.pickedIds, isEmpty, reason: 'wire 不显示选择绿勾');
      expect(c.armedId, isNull, reason: '进入 wire 无待命');
      expect(c.selectedId, isNull);
      expect(c.connectedIds, isEmpty);

      // wire 内点节点 → 只有紫色待命，绿勾仍然不出现
      c.onNodeTap!(father);
      await tester.pump();
      c = _canvas(tester);
      expect(c.armedId, father.id);
      expect(c.pickedIds, isEmpty, reason: '选择草稿不在 wire 里显示');

      // 退出 wire → 浏览；旧选中光不复活，选择草稿不静默丢失
      await _disableWire(tester);
      await tester.pumpAndSettle();
      c = _canvas(tester);
      expect(c.pickedIds, isEmpty, reason: '浏览态不显示绿勾');
      expect(c.selectedId, isNull, reason: '退出 wire 不复活旧选中光');
      expect(c.armedId, isNull);
      expect(
        tester
            .widget<PedigreeSidePanel>(find.byType(PedigreeSidePanel))
            .pickedCount,
        2,
        reason: '选择草稿保留（谨慎处理已有选择，不静默清空）',
      );
    });

    testWidgets('选择雄半边 → wire 点雌半边：solo 不压紫光，合法配对双闪正确',
        (tester) async {
      await pumpHome(tester);
      await _derive(tester);

      // 选择模式基线：勾组合桶雄半边 → solo 只圈雄（原语义）
      await tester.tap(find.text('选择元素'));
      await tester.pumpAndSettle();
      var c = _canvas(tester);
      final bucket = c.nodes.firstWhere(
          (n) => n.kind == PedigreeNodeKind.group && n.generation == 1);
      c.onNodeHalfTap!(bucket, PedigreeNodeKind.male);
      await tester.pump();
      c = _canvas(tester);
      expect(c.pickedIds, contains('${bucket.id}::male'));
      expect(c.soloHalfIds[bucket.id], PedigreeNodeKind.male,
          reason: 'select 的 solo 语义不变：勾雄半边只圈雄');

      // 进 wire：绿勾与 solo 都不得进画布（solo 是第 4 条视觉通道）
      await _enableWire(tester);
      c = _canvas(tester);
      expect(c.pickedIds, isEmpty, reason: 'wire 不显示绿勾');
      expect(c.soloHalfIds, isEmpty,
          reason: 'wire 不传 solo，否则非 solo 半边会被压掉光晕');

      // 点该桶雌半边 → 待命必须精确落在雌半边，且紫光不受 solo 压制
      c.onNodeHalfTap!(bucket, PedigreeNodeKind.female);
      await tester.pump();
      c = _canvas(tester);
      expect(c.armedId, '${bucket.id}::female', reason: '待命精确到雌半边');
      expect(c.soloHalfIds, isEmpty, reason: 'solo 不得压掉待命紫光');
      expect(c.pickedIds, isEmpty);
      expect(c.selectedId, isNull);
      expect(c.connectedIds, isEmpty);

      // 继续到合法配对：P♂ × 该桶雌半边（回交）→ 两端橙闪
      final father = c.nodes.firstWhere((n) => n.id == 'P-father');
      c.onNodeTap!(father);
      await tester.pump();
      c = _canvas(tester);
      expect(c.flashIds, equals({'${bucket.id}::female', father.id}),
          reason: '橙闪两端 = 雌半边 + P♂');
      expect(c.armedId, isNull);
      expect(c.soloHalfIds, isEmpty, reason: '橙闪同样不被 solo 压');
      expect(c.pickedIds, isEmpty);
      expect(c.selectedId, isNull);
      expect(c.connectedIds, isEmpty);

      await tester.pump(const Duration(milliseconds: 2100));
      expect(_canvas(tester).flashIds, isEmpty, reason: '橙光约 2 秒自行消退');
    });

    testWidgets('收线立即熄灭橙光：单条收回与全部收回都不留「刚连上」',
        (tester) async {
      await pumpHome(tester);
      await _derive(tester);
      await _enableWire(tester);

      var c = _canvas(tester);
      final father = c.nodes.firstWhere((n) => n.id == 'P-father');
      final group =
          c.nodes.firstWhere((n) => n.kind == PedigreeNodeKind.group);

      // ① 单条收回：F1 group 只有这一条 mating → 长按直接摘（_detachEdge）
      c.onNodeTap!(father);
      await tester.pump();
      c = _canvas(tester);
      c.onNodeTap!(group);
      await tester.pump();
      c = _canvas(tester);
      expect(c.flashIds, equals({father.id, group.id}));
      final nodesBefore = c.nodes.length;
      final matingBefore =
          c.edges.where((e) => e.kind == PedigreeEdgeKind.mating).length;

      c.onWireDetach!(group);
      await tester.pump();
      c = _canvas(tester);
      expect(c.flashIds, isEmpty, reason: '线已不存在 → 橙光当场熄灭');
      expect(c.edges.where((e) => e.kind == PedigreeEdgeKind.mating).length,
          matingBefore - 1,
          reason: '只摘这一条');
      expect(c.nodes.length, nodesBefore, reason: '收线不改节点结构');

      // ② 全部收回：重新连上后 P♂ 挂 P♀ + F1 两条 → 选择器「全部收回」
      c.onNodeTap!(father);
      await tester.pump();
      c = _canvas(tester);
      c.onNodeTap!(group);
      await tester.pump();
      c = _canvas(tester);
      expect(c.flashIds, equals({father.id, group.id}),
          reason: '第二轮先连上并闪光');

      c.onWireDetach!(father);
      await tester.pumpAndSettle();
      expect(find.textContaining('收回哪一条'), findsOneWidget);
      expect(_canvas(tester).flashIds, isNotEmpty,
          reason: '选择器打开期间橙光仍在（证明之后确为收线所清）');

      await tester.tap(find.text('全部收回（2 条）'));
      await tester.pumpAndSettle();
      c = _canvas(tester);
      expect(c.flashIds, isEmpty, reason: '全部收回后橙光立即清空');
      expect(c.edges.where((e) => e.kind == PedigreeEdgeKind.mating).length, 0,
          reason: 'P♂ 的两条 mating 全部收回');
      expect(find.textContaining('已收回全部连线'), findsOneWidget);
      expect(c.nodes.length, nodesBefore, reason: '全部收回也不改节点结构');
    });
  });

  testWidgets('右键外来样本弹出「编辑样本」，编辑后基因型更新并重算', (tester) async {
    await pumpHome(tester);
    await _derive(tester);

    // 先右键空白添加一个外来样本 AaBb
    final finder = find.byType(PedigreeCanvas);
    final topLeft = tester.getTopLeft(finder);
    await tester.tapAt(topLeft + const Offset(14, 14),
        buttons: kSecondaryMouseButton);
    await tester.pumpAndSettle();
    await tester.tap(find.text('添加样本').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('♂ 雄')); // R17 起默认是混合，本测试要雄性
    await tester.pump();
    final field = find.descendant(
        of: find.byType(AlertDialog), matching: find.byType(TextField));
    await tester.enterText(field, 'AaBbCc');
    await tester.tap(find.text('添加'));
    await tester.pumpAndSettle();

    // 右键该外来样本 → 菜单含 编辑样本/删除样本
    var c = _canvas(tester);
    final ext = c.nodes.firstWhere((n) => n.isExternal);
    c.onNodeSecondaryTap!(ext, Offset.zero);
    await tester.pumpAndSettle();
    expect(find.text('编辑样本'), findsOneWidget);
    expect(find.text('删除样本'), findsOneWidget);

    // 编辑：AaBbCc → AABbCc，保存并重算
    await tester.tap(find.text('编辑样本'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    final editField = find.descendant(
        of: find.byType(AlertDialog), matching: find.byType(TextField));
    await tester.enterText(editField, 'AABbCc');
    await tester.tap(find.text('保存并重算'));
    await tester.pumpAndSettle();

    c = _canvas(tester);
    final edited = c.nodes.firstWhere((n) => n.id == ext.id);
    expect(edited.genotype, 'AABbCc', reason: '编辑后基因型应更新');
  });

  testWidgets('世代折叠：默认只显示最高概率桶，点芯片展开/收起', (tester) async {
    await pumpHome(tester);
    await _derive(tester);
    // F1 AaBbCc 自交 → F2 有 27 个桶
    await tester.tap(find.text('计算下一代'));
    await tester.pumpAndSettle();

    var c = _canvas(tester);
    final f2Visible = c.nodes.where((n) => n.generation == 2).length;
    expect(f2Visible, 1, reason: '折叠态 F2 只显示最高概率桶');
    expect(c.hiddenCounts['0:2'], 26, reason: '隐藏 26 个低概率桶');
    expect(c.collapsedKeys.contains('0:2'), isTrue);

    // 展开
    c.onToggleGen!('0:2');
    await tester.pumpAndSettle();
    c = _canvas(tester);
    expect(c.nodes.where((n) => n.generation == 2).length, 27);
    expect(c.collapsedKeys.contains('0:2'), isFalse);

    // 展开即出完整配比：不选中任何节点也要在详情条看到（多世代场景
    // 由 phenotype_detail_strip_test 的分块用例承接）
    expect(find.text('F2 · 27 种基因型 · 共 64 个'), findsOneWidget,
        reason: '展开的世代要有完整基因型配比（共 64 个）');
    expect(find.text('AaBbCc 8/64'), findsOneWidget,
        reason: '每个基因型给出份数与总份数');

    // 摊开后每个桶都得看得见亲代连线（只有一条主干 = 大片桶"没有亲代"）
    final f2Ids =
        c.nodes.where((n) => n.generation == 2).map((n) => n.id).toSet();
    expect(
        f2Ids.difference(c.edges
            .where((e) => e.kind == PedigreeEdgeKind.lineage)
            .map((e) => e.toId)
            .toSet()),
        isEmpty,
        reason: '展开的世代不抽稀');

    // 收起
    c.onToggleGen!('0:2');
    await tester.pumpAndSettle();
    expect(_canvas(tester).nodes.where((n) => n.generation == 2).length, 1);
  });

  testWidgets('长按收线：收回最近一条 mating 边', (tester) async {
    await pumpHome(tester);
    await _derive(tester);
    var c = _canvas(tester);
    final father = c.nodes.firstWhere((n) => n.id == 'P-father');
    expect(c.edges.where((e) => e.kind == PedigreeEdgeKind.mating).length, 1,
        reason: '创始 P♂×P♀ 边存在');

    c.onWireDetach!(father); // 长按 = 收回最近一条
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    c = _canvas(tester);
    expect(c.edges.where((e) => e.kind == PedigreeEdgeKind.mating).length, 0,
        reason: '收回后创始边消失');
    expect(find.textContaining('已收回'), findsOneWidget);

    // 冲掉「已收回」Snackbar 后再试
    await tester.pump(const Duration(seconds: 5));
    await tester.pump();

    // 无边再长按 → 提示
    c.onWireDetach!(father);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.textContaining('没有可收回的连线'), findsOneWidget);
  });

  testWidgets('收回后重新点选连线：P-mother × F1 group（回交）', (tester) async {
    await pumpHome(tester);
    await _derive(tester);
    await _enableWire(tester);
    var c = _canvas(tester);
    final father = c.nodes.firstWhere((n) => n.id == 'P-father');
    final mother = c.nodes.firstWhere((n) => n.id == 'P-mother');
    final group = c.nodes.firstWhere((n) => n.kind == PedigreeNodeKind.group);

    c.onWireDetach!(father); // 收回 P♂×P♀
    await tester.pump();
    c = _canvas(tester);
    expect(c.edges.where((e) => e.kind == PedigreeEdgeKind.mating).length, 0);

    c.onNodeTap!(mother); // 待命 P-mother
    await tester.pump();
    c = _canvas(tester);
    c.onNodeTap!(group); // 连线 P-mother × F1 group
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    final matings = _canvas(tester)
        .edges
        .where((e) => e.kind == PedigreeEdgeKind.mating)
        .toList();
    expect(matings.length, 1);
    expect(
        matings.single.fromId == 'P-mother' || matings.single.toId == 'P-mother',
        isTrue,
        reason: '新边应挂在 P-mother 上');
    await tester.pump(const Duration(seconds: 2)); // 冲掉橙光 Timer（2s）
  });

  testWidgets('同性交配开关与 XY 性别开关', (tester) async {
    await pumpHome(tester);
    await _derive(tester);

    // 开启同性交配
    await _tapChip(tester, '同性交配');
    await tester.pumpAndSettle();

    // R16：XY 性别常驻——默认常亮，无需手动开启
    var c = _canvas(tester);
    expect(c.sexSplitView, isTrue, reason: 'XY 默认开启 → 组合桶渲染');
    var f1 = c.nodes.where((n) => n.generation == 1);
    expect(f1.every((n) => n.maleFraction == 0.5), isTrue,
        reason: 'XY 常驻：桶默认带雌雄比存证');

    // 手动点 chip 才能关闭
    await _tapChip(tester, 'XY 性别');
    await tester.pumpAndSettle();
    c = _canvas(tester);
    expect(c.sexSplitView, isFalse, reason: '手动取消后关闭组合桶渲染');
    f1 = c.nodes.where((n) => n.generation == 1);
    expect(f1.every((n) => n.maleFraction == null), isTrue,
        reason: '关闭后重算的桶不带雌雄比');
  });

  testWidgets('触屏/触控板路径：低缩放下单指拖动仍按屏幕像素跟手',
      (tester) async {
    await pumpHome(tester);
    await _derive(tester);
    final c = _canvas(tester);
    expect(c.nodes.any((n) => n.kind == PedigreeNodeKind.group), isTrue);

    // 先把画布缩到非 1.0，防止「平移被缩放二次缩小」在基线中漏检。
    final finder = find.byType(PedigreeCanvas);
    final center = tester.getCenter(finder);
    final state = tester.state<PedigreeCanvasState>(finder);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    try {
      await tester.sendEventToBinding(PointerScrollEvent(
          position: center, scrollDelta: const Offset(0, 120)));
      await tester.pump();
    } finally {
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    }
    expect(state.debugTransform.getMaxScaleOnAxis(), lessThan(1.0));
    final before = state.debugTransform.getTranslation();

    // 用 TestGesture 模拟触摸按下-拖动-抬起（kind=touch）。80 屏幕 px
    // 必须对应 80 屏幕 px 视口位移，而不是 80×当前缩放。
    final gesture = await tester.startGesture(center,
        kind: PointerDeviceKind.touch);
    await tester.pump();
    await gesture.moveBy(const Offset(80, 0));
    await tester.pump(const Duration(milliseconds: 100));
    await gesture.up();
    await tester.pumpAndSettle();
    final after = state.debugTransform.getTranslation();
    expect(after.x - before.x, closeTo(80, 0.001));
    expect(after.y - before.y, closeTo(0, 0.001));
  });

  testWidgets('滚动=二维平移；Ctrl+滚轮/双指捏合=缩放', (tester) async {
    await pumpHome(tester);
    await _derive(tester);
    final state =
        tester.state<PedigreeCanvasState>(find.byType(PedigreeCanvas));
    double scaleOf() => state.debugTransform.getMaxScaleOnAxis();
    final before = scaleOf();
    final beforePan = state.debugTransform.getTranslation();

    // 白板驱动可能只注入滚动事件：普通滚动必须移动视口而非突然缩放。
    final finder = find.byType(PedigreeCanvas);
    final center = tester.getCenter(finder);
    await tester.sendEventToBinding(PointerScrollEvent(
        position: center, scrollDelta: const Offset(40, 120)));
    await tester.pump();
    final afterPan = state.debugTransform.getTranslation();
    expect(scaleOf(), before, reason: '普通滚动不得改变缩放');
    expect(afterPan.x - beforePan.x, closeTo(-40, 0.001));
    expect(afterPan.y - beforePan.y, closeTo(-120, 0.001),
        reason: '纵向滚动应转成同距离的画布平移');

    // 物理鼠标仍可用 Ctrl+滚轮精确缩放。
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    try {
      await tester.sendEventToBinding(PointerScrollEvent(
          position: center, scrollDelta: const Offset(0, -120)));
      await tester.pump();
    } finally {
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    }
    expect(scaleOf(), greaterThan(before), reason: 'Ctrl+滚轮向上应放大');

    // 原生双指捏合张开 = 放大（触控板/触屏 PointerPanZoom 等价路径）。
    // 起点选在画布左上角空白区，避开底部提示文字与节点。
    final blank = tester.getTopLeft(finder) + const Offset(80, 30);
    final g1 = await tester.startGesture(blank + const Offset(-30, 0),
        kind: PointerDeviceKind.touch);
    final g2 = await tester.startGesture(blank + const Offset(30, 0),
        kind: PointerDeviceKind.touch);
    await tester.pump();
    final beforePinch = scaleOf();
    await g1.moveBy(const Offset(-60, 0));
    await g2.moveBy(const Offset(60, 0));
    await tester.pump();
    expect(scaleOf(), greaterThan(beforePinch), reason: '双指张开应放大');
    await g1.up();
    await g2.up();
    await tester.pumpAndSettle();
  });

  testWidgets('R16 缩放控件：＋/－按钮与滑块缩放（手机端替代滚轮）',
      (tester) async {
    await pumpHome(tester);
    await _derive(tester);
    final state =
        tester.state<PedigreeCanvasState>(find.byType(PedigreeCanvas));
    double scaleOf() => state.debugTransform.getMaxScaleOnAxis();
    final before = scaleOf();

    // ＋ 放大（tooltip 定位，避开世代徽标里的同名图标）
    await tester.tap(find.byTooltip('放大'));
    await tester.pump();
    final zoomedIn = scaleOf();
    expect(zoomedIn, greaterThan(before), reason: '＋ 应放大');

    // － 缩小两次 → 低于放大后的值
    await tester.tap(find.byTooltip('缩小'));
    await tester.pump();
    await tester.tap(find.byTooltip('缩小'));
    await tester.pump();
    expect(scaleOf(), lessThan(zoomedIn), reason: '－ 应缩小');

    // 滑块向右拖 → 放大
    await tester.drag(find.byType(Slider), const Offset(100, 0));
    await tester.pump();
    expect(scaleOf(), greaterThan(before), reason: '滑块拖动应直接缩放');
  });

  testWidgets('常驻「添加样本」按钮打开对话框（移动端无右键）', (tester) async {
    await pumpHome(tester);
    await _derive(tester);
    await tester.tap(find.text('添加样本').last);
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.text('目标世代'), findsOneWidget);
    // 关掉
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
  });

  testWidgets('回交线调色板菜单：逐条显隐', (tester) async {
    await pumpHome(tester);
    await _derive(tester);
    await _enableWire(tester);
    var c = _canvas(tester);
    final father = c.nodes.firstWhere((n) => n.id == 'P-father');
    final group = c.nodes.firstWhere((n) => n.kind == PedigreeNodeKind.group);
    // 建一条回交边（点选-点选）
    c.onNodeTap!(father);
    await tester.pump();
    _canvas(tester).onNodeTap!(group);
    await tester.pump();
    await tester.pump(const Duration(seconds: 2)); // 冲掉橙光 Timer（2s）

    // 打开调色板菜单 → 列出该回交边
    await tester.tap(find.byIcon(Icons.palette_outlined));
    await tester.pumpAndSettle();
    expect(find.textContaining('P-father ×'), findsOneWidget);

    // 点菜单项 → 该边进入隐藏集合
    await tester.tap(find.textContaining('P-father ×'));
    await tester.pumpAndSettle();
    c = _canvas(tester);
    expect(c.hiddenBackcrossKeys.length, 1,
        reason: '菜单切换后该回交边应被隐藏');
    // 再开菜单切回
    await tester.tap(find.byIcon(Icons.palette_outlined));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('P-father ×'));
    await tester.pumpAndSettle();
    expect(_canvas(tester).hiddenBackcrossKeys, isEmpty);
  });


  testWidgets('「添加家族」按钮弹出对话框并创建第二家族（R14）', (tester) async {
    await pumpHome(tester);
    await _derive(tester);

    // 常驻按钮存在
    expect(find.text('添加家族'), findsOneWidget);
    await tester.tap(find.text('添加家族'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);

    // 两个基因型输入框（父本/母本）
    final fields = find.descendant(
        of: find.byType(AlertDialog), matching: find.byType(TextField));
    expect(fields, findsNWidgets(2));
    await tester.enterText(fields.at(0), 'Bb');
    await tester.enterText(fields.at(1), 'Bb');
    await tester.tap(find.text('添加'));
    await tester.pumpAndSettle();

    final c = _canvas(tester);
    // 第二家族双亲落位，familyLabels 两家族
    expect(c.nodes.any((n) => n.familyId == 1 && n.id == 'P1-father'), isTrue);
    expect(c.nodes.any((n) => n.familyId == 1 && n.id == 'P1-mother'), isTrue);
    expect(c.familyLabels.length, 2);
    expect(c.familyLabels[0], 'A');
    expect(c.familyLabels[1], 'B');
  });

  // 通过 UI 对话框添加第二家族（Bb×Bb）
  Future<void> addSecondFamily(WidgetTester tester) async {
    await tester.tap(find.text('添加家族'));
    await tester.pumpAndSettle();
    final fields = find.descendant(
        of: find.byType(AlertDialog), matching: find.byType(TextField));
    await tester.enterText(fields.at(0), 'Bb');
    await tester.enterText(fields.at(1), 'Bb');
    await tester.tap(find.text('添加'));
    await tester.pumpAndSettle();
  }

  testWidgets('多家族后「添加样本」出现所属家族下拉（R14）', (tester) async {
    await pumpHome(tester);
    await _derive(tester);
    // 单家族时无家族下拉
    await tester.tap(find.text('添加样本'));
    await tester.pumpAndSettle();
    expect(find.text('所属家族'), findsNothing);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();

    // 加第二家族后再开：出现所属家族下拉
    await addSecondFamily(tester);
    await tester.tap(find.text('添加样本'));
    await tester.pumpAndSettle();
    expect(find.text('所属家族'), findsOneWidget);
    expect(find.text('家族 A'), findsWidgets);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
  });

  testWidgets('多家族计算下一代：两家族各自推进一代（R14）', (tester) async {
    await pumpHome(tester);
    await _derive(tester); // 家族 A 到 F1
    await addSecondFamily(tester);
    await tester.tap(find.text('计算下一代'));
    await tester.pumpAndSettle();
    final c = _canvas(tester);
    // 家族 A：F1→F2；家族 B：P→F1（各自推进一代）
    expect(c.nodes.any((n) => n.familyId == 0 && n.generation == 2), isTrue);
    expect(c.nodes.any((n) => n.familyId == 1 && n.generation == 1), isTrue);
  });

  // ── R15 三态交互：浏览/连线/选择元素 + 组合桶半边 ────────────
  testWidgets('R15 默认浏览模式：点节点只选中，不进入连线待命', (tester) async {
    await pumpHome(tester);
    await _derive(tester);
    var c = _canvas(tester);
    final father = c.nodes.firstWhere((n) => n.id == 'P-father');
    c.onNodeTap!(father);
    await tester.pump();
    c = _canvas(tester);
    expect(c.armedId, isNull, reason: '浏览模式点节点不待命');
    expect(c.selectedId, 'P-father', reason: '浏览模式点节点=选中看信息');
  });

  testWidgets('R15 连线开关：开启后才能点选连线，关闭清空待命', (tester) async {
    await pumpHome(tester);
    await _derive(tester);
    var c = _canvas(tester);
    final father = c.nodes.firstWhere((n) => n.id == 'P-father');

    await _enableWire(tester);
    c = _canvas(tester);
    c.onNodeTap!(father);
    await tester.pump();
    expect(_canvas(tester).armedId, 'P-father', reason: '连线模式点选待命');

    // 关闭连线 → 待命清空，回到浏览
    await _disableWire(tester);
    await tester.pumpAndSettle();
    c = _canvas(tester);
    expect(c.armedId, isNull, reason: '关闭连线开关后待命清空');

    // 浏览模式再点不待命
    c.onNodeTap!(father);
    await tester.pump();
    expect(_canvas(tester).armedId, isNull);
  });

  testWidgets('R15 组合桶：XY 性别开启后半边点选 + 懒分裂连线（雄□×雌○）',
      (tester) async {
    await pumpHome(tester);
    await _derive(tester);
    // R16：XY 常驻默认开启，无需手动打开
    var c = _canvas(tester);
    expect(c.sexSplitView, isTrue, reason: 'XY 常驻：默认组合桶渲染');
    expect(c.nodes.any((n) => n.id.startsWith('SPLIT#')), isFalse,
        reason: '懒分裂：未连线前没有 SPLIT 节点');

    await _enableWire(tester);
    c = _canvas(tester);
    final bucket = c.nodes.firstWhere(
        (n) => n.kind == PedigreeNodeKind.group && n.generation == 1);
    // 点桶的雄半边 → 待命（合成 id）
    c.onNodeHalfTap!(bucket, PedigreeNodeKind.male);
    await tester.pump();
    c = _canvas(tester);
    expect(c.armedId, '${bucket.id}::male', reason: '半边待命用合成 id');
    // 2026-10-27 用户裁定：wire 的视觉只由 armed(紫)/flash(橙) 承担，
    // 普通选中光不传画布（否则紫光下永久压一层琥珀，闪光后也不退）。
    expect(c.selectedId, isNull, reason: 'wire 不传普通选中光');

    // 再点雌半边 → 懒分裂 + 连线成功
    c.onNodeHalfTap!(bucket, PedigreeNodeKind.female);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.textContaining('已连线'), findsOneWidget);
    c = _canvas(tester);
    expect(c.nodes.any((n) => n.id.startsWith('SPLIT#')), isFalse,
        reason: 'SPLIT 半桶不在画布占位（由组合桶内 glyph 代表）');
    final matings = c.edges
        .where((e) => e.kind == PedigreeEdgeKind.mating)
        .toList();
    expect(matings.length, 2, reason: '创始边 + 半边连线');
    expect(
        matings.any((e) =>
            e.fromId.startsWith('SPLIT#') || e.toId.startsWith('SPLIT#')),
        isTrue,
        reason: '连线端点是懒分裂出的 SPLIT 半边');
    await tester.pump(const Duration(seconds: 2)); // 冲掉橙光 Timer（2s）
  });

  testWidgets('R15 选择元素：勾选→确定折叠未选中→显示全部恢复（只作用被选世代）',
      (tester) async {
    await pumpHome(tester);
    await _derive(tester);
    // 扩到 F3，验证「选择折叠只作用被选世代，其余世代照常」
    await tester.tap(find.text('计算下一代'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('计算下一代'));
    await tester.pumpAndSettle();
    // 展开 F2 让多桶可见
    var c = _canvas(tester);
    c.onToggleGen!('0:2');
    await tester.pumpAndSettle();
    c = _canvas(tester);
    final f2 = c.nodes.where((n) => n.generation == 2).toList();
    expect(f2.length, 27);

    // 进入选择模式（v2.19.6 菜单化：持续选择，chip 不再变「确定」）
    await tester.tap(find.text('选择元素'));
    await tester.pumpAndSettle();
    expect(find.textContaining('选择元素'), findsWidgets,
        reason: '选择模式常驻「选择元素」菜单项（计数版标签）');

    // 勾选两个 F2 桶
    c = _canvas(tester);
    c.onNodeTap!(f2[0]);
    await tester.pump();
    _canvas(tester).onNodeTap!(f2[1]);
    await tester.pump();
    c = _canvas(tester);
    expect(c.pickedIds, containsAll([f2[0].id, f2[1].id]));
    expect(find.text('选择元素（2）'), findsOneWidget,
        reason: '选择中标签带计数，且不打断选择');

    // v2.19.6：选择中再点「选择元素」= 保持（不打断），可继续加选
    await tester.tap(find.text('选择元素（2）'));
    await tester.pumpAndSettle();
    expect(_canvas(tester).pickedIds.length, 2,
        reason: '再点选择元素不清空、不聚焦，持续可选');
    _canvas(tester).onNodeTap!(f2[2]);
    await tester.pump();
    expect(_canvas(tester).pickedIds.length, 3,
        reason: '中途可加选，不必从头再来');

    // v3.6 语义拆分：选择中只出现「只看所选（N）」（= 应用聚焦）；
    // 此时不该有「显示全部」（选择空集也不会有「显示全部」把东西藏起来）。
    expect(find.text('只看所选（3）'), findsWidgets,
        reason: '有勾选时出现「只看所选（N）」应用聚焦');
    expect(find.text('显示全部'), findsNothing,
        reason: '未聚焦时没有「显示全部」——恢复动作只在聚焦态出现');

    // 只看所选 → 应用聚焦：只有 F2（被选世代）折叠为选择集，其余世代照常
    await tester.tap(find.text('只看所选（3）').first);
    await tester.pumpAndSettle();
    c = _canvas(tester);
    expect(c.nodes.where((n) => n.generation == 2).length, 3,
        reason: '被选世代 F2 只显示选中的 3 桶');
    expect(c.nodes.where((n) => n.generation == 0).length, 2,
        reason: 'P 代双亲照常呈现');
    expect(c.nodes.where((n) => n.generation == 1).length, 1,
        reason: 'F1 按原折叠规则照常呈现（1 桶）');
    expect(c.nodes.where((n) => n.generation == 3).length, 1,
        reason: 'F3 按原折叠规则照常呈现（最高概率桶）');
    expect(c.hiddenCounts.length, 1, reason: '聚焦代 F2 不出芯片');
    expect(c.hiddenCounts['0:3'], 26, reason: '未选世代 F3 折叠芯片照常');

    // 显示全部 → 恢复（之前展开的 F2 仍展开）
    await tester.tap(find.text('显示全部'));
    await tester.pumpAndSettle();
    c = _canvas(tester);
    expect(c.nodes.where((n) => n.generation == 2).length, 27,
        reason: '恢复后回到展开态');
    expect(c.nodes.any((n) => n.generation == 0), isTrue);
    expect(find.text('显示全部'), findsNothing,
        reason: '恢复后「显示全部」收起（它只在聚焦态出现）');
  });

  testWidgets('v3.6 显示全部只清聚焦、不强制展开各代', (tester) async {
    await pumpHome(tester);
    await _derive(tester);
    await tester.tap(find.text('计算下一代'));
    await tester.pumpAndSettle();

    // F2 未展开（默认折叠为 1 桶，隐藏 26 个）。
    var c = _canvas(tester);
    expect(c.nodes.where((n) => n.generation == 2).length, 1,
        reason: 'F2 默认折叠');
    expect(c.hiddenCounts['0:2'], 26);
    final f2 = c.nodes.where((n) => n.generation == 2).toList();

    await tester.tap(find.text('选择元素'));
    await tester.pumpAndSettle();
    _canvas(tester).onNodeTap!(f2.first);
    await tester.pump();
    expect(find.text('只看所选（1）'), findsWidgets);
    await tester.tap(find.text('只看所选（1）').first);
    await tester.pumpAndSettle();
    expect(find.text('显示全部'), findsWidgets, reason: '聚焦态出现「显示全部」');

    await tester.tap(find.text('显示全部').first);
    await tester.pumpAndSettle();
    c = _canvas(tester);
    expect(c.nodes.where((n) => n.generation == 2).length, 1,
        reason: '只清聚焦：F2 仍是折叠态，不被强行展开');
    expect(c.hiddenCounts['0:2'], 26,
        reason: '折叠芯片照常（26 个隐藏），说明各代折叠状态没被改动');
  });

  testWidgets('v3.6 智能密线：展开的世代直接画全，不再只留一条主干', (tester) async {
    await pumpHome(tester);
    await _derive(tester);
    await tester.tap(find.text('计算下一代'));
    await tester.pumpAndSettle();

    // 展开 F2（27 个桶）→ 每个桶都要连到亲代。抽稀只服务于折叠态：
    // 折叠时该代只剩一个代表桶，多画的线本来就没有落点。
    var c = _canvas(tester);
    c.onToggleGen!('0:2');
    await tester.pumpAndSettle();
    c = _canvas(tester);
    expect(c.nodes.where((n) => n.generation == 2).length, 27);
    final f2Ids =
        c.nodes.where((n) => n.generation == 2).map((n) => n.id).toSet();
    expect(
        f2Ids.difference(c.edges
            .where((e) => e.kind == PedigreeEdgeKind.lineage)
            .map((e) => e.toId)
            .toSet()),
        isEmpty,
        reason: '展开的世代每个桶都要看得见亲代');

    // 「全部连线」开关此时无增量：展开态本就一条不剩地画了。
    final expandedCount = c.edges.length;
    await _tapChip(tester, '全部连线');
    await tester.pumpAndSettle();
    expect(_canvas(tester).edges.length, expandedCount);
    await _tapChip(tester, '全部连线');
    await tester.pumpAndSettle();
    expect(_canvas(tester).edges.length, expandedCount);

    // 选中某个 F2 桶 → 它的相关边（连到上一代）必须显示。
    c = _canvas(tester);
    final target = c.nodes.where((n) => n.generation == 2).toList()[2];
    c.onNodeTap!(target);
    await tester.pump();
    c = _canvas(tester);
    final related = c.edges.where((e) =>
        e.kind == PedigreeEdgeKind.lineage &&
        (e.toId == target.id || e.fromId == target.id));
    expect(related, isNotEmpty,
        reason: '选中元素的自动边被恢复（可逐代追踪）');
  });

  testWidgets('R15 右键桶不再分裂（常驻组合桶，提示点选半边）', (tester) async {
    await pumpHome(tester);
    await _derive(tester);
    await _tapChip(tester, 'XY 性别');
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 5)); // 冲掉开关 toast
    await tester.pump();
    var c = _canvas(tester);
    final bucket =
        c.nodes.firstWhere((n) => n.kind == PedigreeNodeKind.group);
    c.onNodeSecondaryTap!(bucket, Offset.zero);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.textContaining('点选半边'), findsOneWidget);
    expect(_canvas(tester).nodes.any((n) => n.id.startsWith('SPLIT#')),
        isFalse,
        reason: '右键不再产生分裂节点');
  });

  // ── R16 操作日志：多步记录 + 任意步回退 + 第 0 步封顶 ────────
  testWidgets('R16 日志：记录每步操作，可回退到任意步，第 0 步封顶',
      (tester) async {
    await pumpHome(tester);
    await _derive(tester); // #0 初始计算（含 F1）
    await tester.tap(find.text('计算下一代')); // #1 → F2
    await tester.pumpAndSettle();
    await tester.tap(find.text('计算下一代')); // #2 → F3
    await tester.pumpAndSettle();
    var c = _canvas(tester);
    expect(c.nodes.any((n) => n.generation == 3), isTrue);
    expect(find.text('日志（2）'), findsOneWidget,
        reason: '2 步操作（不含第 0 步初始态）');

    // 打开日志面板：最新在上，当前状态无回退按钮
    await tester.tap(find.text('日志（2）'));
    await tester.pumpAndSettle();
    expect(find.text('操作日志'), findsOneWidget);
    expect(find.text('初始计算：AABBCC × aabbcc'), findsOneWidget);
    expect(find.text('计算下一代 → F3'), findsOneWidget);
    expect(find.text('当前状态'), findsOneWidget);
    expect(find.text('回退到此处'), findsNWidgets(2),
        reason: '#1 与 #0 可回退，当前态 #2 不可');

    // 回退到 #1（F2 态）：F3 消失，其后历史丢弃
    await tester.tap(find.text('回退到此处').first);
    await tester.pumpAndSettle();
    c = _canvas(tester);
    expect(c.nodes.any((n) => n.generation == 3), isFalse,
        reason: '回退到 #1 后 F3 不存在');
    expect(c.nodes.any((n) => n.generation == 2), isTrue);
    expect(find.text('日志（1）'), findsOneWidget);

    // 回退到 #0（最开始）：只剩初始 P+F1
    await tester.tap(find.text('日志（1）'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('回退到此处').first);
    await tester.pumpAndSettle();
    c = _canvas(tester);
    expect(c.nodes.any((n) => n.generation == 2), isFalse,
        reason: '回退到第 0 步后 F2 也不存在');
    expect(c.nodes.any((n) => n.generation == 1), isTrue);
    expect(find.text('日志（0）'), findsOneWidget);

    // 第 0 步封顶：面板里再无「回退到此处」（不会退到 -1）
    await tester.tap(find.text('日志（0）'));
    await tester.pumpAndSettle();
    expect(find.text('回退到此处'), findsNothing,
        reason: '第 0 步已是当前状态且到顶，无可再退');
    await tester.tap(find.text('关闭'));
    await tester.pumpAndSettle();
  });

  testWidgets('v2.19.6 选择元素/显示全部入日志且可回退（恢复选择集）',
      (tester) async {
    await pumpHome(tester);
    await _derive(tester); // #0 初始计算
    await tester.tap(find.text('计算下一代')); // #1 → F2
    await tester.pumpAndSettle();

    // 展开 F2，选 2 桶 → 只看所选（应用聚焦）→ 应产生 2 条日志
    var c = _canvas(tester);
    c.onToggleGen!('0:2');
    await tester.pumpAndSettle();
    await tester.tap(find.text('选择元素'));
    await tester.pumpAndSettle();
    c = _canvas(tester);
    final f2 = c.nodes.where((n) => n.generation == 2).toList();
    c.onNodeTap!(f2[0]);
    await tester.pump();
    _canvas(tester).onNodeTap!(f2[1]);
    await tester.pump();
    await tester.tap(find.text('只看所选（2）').first); // 应用聚焦
    await tester.pumpAndSettle();
    expect(find.text('日志（3）'), findsOneWidget,
        reason: '#1 计算下一代、#2 选择元素、#3 聚焦（选择中点选不入日志）；'
            '按钮计数不含第 0 步');

    // 聚焦态：F2 只剩 2 桶。
    c = _canvas(tester);
    expect(c.nodes.where((n) => n.generation == 2).length, 2);

    // 再点显示全部 → 恢复（#4）。
    await tester.tap(find.text('显示全部'));
    await tester.pumpAndSettle();
    c = _canvas(tester);
    expect(c.nodes.where((n) => n.generation == 2).length, 27,
        reason: '恢复全部显示');
    expect(find.text('日志（4）'), findsOneWidget);

    // 回退一步（#4 显示全部 → #3 聚焦态）：日志面板「回退到此处」。
    await tester.tap(find.text('日志（4）'));
    await tester.pumpAndSettle();
    expect(find.text('聚焦：所选 2 个'), findsOneWidget,
        reason: '选择元素/聚焦/显示全部均已入日志');
    await tester.tap(find.text('回退到此处').first);
    await tester.pumpAndSettle();
    c = _canvas(tester);
    expect(c.nodes.where((n) => n.generation == 2).length, 2,
        reason: '回退到「聚焦：所选 2 个」步骤，视图态随日志恢复');
    expect(find.text('日志（3）'), findsOneWidget);
  });

  testWidgets('R16b 撤销回退：回退后「撤销上一步回退」恢复（Ctrl+Shift+Z 语义）',
      (tester) async {
    await pumpHome(tester);
    await _derive(tester); // #0 初始计算（含 F1）
    await tester.tap(find.text('计算下一代')); // #1 → F2
    await tester.pumpAndSettle();
    var c = _canvas(tester);
    expect(c.nodes.any((n) => n.generation == 2), isTrue);
    expect(find.text('日志（1）'), findsOneWidget, reason: '命令栏常驻日志入口');

    // 回退到 #0 → F2 消失（误回退场景）
    await tester.tap(find.text('日志（1）'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('回退到此处').first);
    await tester.pumpAndSettle();
    c = _canvas(tester);
    expect(c.nodes.any((n) => n.generation == 2), isFalse,
        reason: '回退后 F2 消失');
    expect(find.text('日志（0）'), findsOneWidget);

    // 日志面板出现「撤销上一步回退」→ 点它恢复 F2
    await tester.tap(find.text('日志（0）'));
    await tester.pumpAndSettle();
    expect(find.text('撤销上一步回退'), findsOneWidget,
        reason: '有回退历史时可撤销回退');
    await tester.tap(find.text('撤销上一步回退'));
    await tester.pumpAndSettle();
    c = _canvas(tester);
    expect(c.nodes.any((n) => n.generation == 2), isTrue,
        reason: '撤销回退后 F2 恢复');
    expect(find.text('日志（1）'), findsOneWidget, reason: '日志段恢复');

    // 再回退 → 撤销 → 恢复，且新操作会清空撤销栈（Windows 语义）
    await tester.tap(find.text('日志（1）'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('回退到此处').first);
    await tester.pumpAndSettle();
    expect(find.text('日志（0）'), findsOneWidget);
    await tester.tap(find.text('计算下一代')); // 新操作（重新展开 F2）
    await tester.pumpAndSettle();
    await tester.tap(find.text('日志（1）'));
    await tester.pumpAndSettle();
    // 新操作发生后撤销栈已清空 → 按钮禁用/不可点
    final redoBtn = tester.widget<TextButton>(find.widgetWithText(
        TextButton, '撤销上一步回退'));
    expect(redoBtn.onPressed, isNull,
        reason: '新操作后撤销回退历史作废，按钮禁用');
    await tester.tap(find.text('关闭'));
    await tester.pumpAndSettle();
  });

  testWidgets('R17 添加样本：默认选中「混合」，直接添加出混合桶', (tester) async {
    await pumpHome(tester);
    await _derive(tester);
    await tester.tap(find.text('添加样本').last);
    await tester.pumpAndSettle();

    // 三个性别选项都在，且默认选中「混合 ♂♀」
    expect(find.text('混合 ♂♀'), findsOneWidget);
    expect(find.text('♂ 雄'), findsOneWidget);
    expect(find.text('♀ 雌'), findsOneWidget);
    final mixedChip = tester.widget<ChoiceChip>(find.ancestor(
        of: find.text('混合 ♂♀'), matching: find.byType(ChoiceChip)));
    expect(mixedChip.selected, isTrue, reason: '性别应默认选中混合型');

    // 不改任何选项直接添加（默认混合）→ 出现外来 group 桶
    final field = find.descendant(
        of: find.byType(AlertDialog), matching: find.byType(TextField));
    await tester.enterText(field, 'AaBbCc');
    await tester.tap(find.text('添加'));
    await tester.pumpAndSettle();
    final nodes = _canvas(tester).nodes;
    expect(
        nodes.any((n) =>
            n.isExternal &&
            n.kind == PedigreeNodeKind.group &&
            n.genotype == 'AaBbCc'),
        isTrue,
        reason: '默认混合应添加出外来混合桶（大矩形含雄□雌○）');
  });

  testWidgets('R18 允许基因缺失交配：默认关，开启后可添加单对外来样本并算出缺失桶',
      (tester) async {
    await pumpHome(tester);
    await _derive(tester); // 双亲 2 对（AaBb 可见于输入框默认? 用 AaBb）

    // chip 存在且默认关
    final chipFinder = find.ancestor(
        of: find.text('允许基因缺失交配'),
        matching: find.byType(FilterChip));
    expect(chipFinder, findsOneWidget);
    expect(tester.widget<FilterChip>(chipFinder).selected, isFalse,
        reason: '「允许基因缺失交配」默认关闭');

    // 开 chip（v2.19.10：chip 去 shrinkWrap 变大，先滚到可见）
    await _tapChip(tester, '允许基因缺失交配');
    await tester.pump();
    expect(tester.widget<FilterChip>(chipFinder).selected, isTrue);

    // 添加单对外来样本（默认混合），到最新代
    await tester.tap(find.text('添加样本').last);
    await tester.pumpAndSettle();
    final field = find.descendant(
        of: find.byType(AlertDialog), matching: find.byType(TextField));
    await tester.enterText(field, 'aa');
    await tester.tap(find.text('添加'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 5)); // 冲掉 SnackBar
    await tester.pump();
    expect(
        _canvas(tester).nodes.any(
            (n) => n.isExternal && n.genotype == 'aa' && n.familyId == 0),
        isTrue,
        reason: '开启基因缺失交配后单对外来样本可加入');

    // 计算下一代 → F2 含缺失位点「-」的桶（如 AaB-C-…）；
    // F2 默认折叠只显示最高概率桶，先展开整代再看
    await tester.tap(find.text('计算下一代'));
    await tester.pumpAndSettle();
    var c = _canvas(tester);
    if (c.collapsedKeys.contains('0:2')) {
      c.onToggleGen!('0:2');
      await tester.pumpAndSettle();
      c = _canvas(tester);
    }
    expect(c.nodes.any((n) => n.genotype.contains('-')),
        isTrue,
        reason: '基因缺失交配的子代应补「-」形成缺失桶');
  });

  testWidgets('R18 画布锁：锁定后滚轮缩放失效，可按住家族横幅整体拖动', (tester) async {
    // 用更宽 viewport：默认 800×800 下画布实际 220 宽（800 - 280
    // 左面板 - 300 cross panel），缩放条 314.5 像素宽超出画布视口
    // → 锁定 IconButton 中心 (541, 87) 实际在画布 RenderBox 外，
    // hit test 进入 Listener 路径不被 IconButton.onPressed 消费。
    // 1200×800 让画布有 920 宽，缩放条完整在画布内。
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(_app());
    await _derive(tester);
    // 多家族才有横幅可拖
    final state =
        tester.state<PedigreeCanvasState>(find.byType(PedigreeCanvas));
    double scaleOf() => state.debugTransform.getMaxScaleOnAxis();
    final before = scaleOf();

    // 解锁时 Ctrl+滚轮缩放生效
    final canvasF = find.byType(PedigreeCanvas);
    final canvasCenter = tester.getCenter(canvasF);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    try {
      await tester.sendEventToBinding(PointerScrollEvent(
          position: canvasCenter, scrollDelta: const Offset(0, 120)));
      await tester.pump();
    } finally {
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    }
    expect(scaleOf(), lessThan(before), reason: '未锁定时 Ctrl+滚轮可缩放');

    // 锁定
    // 用 lock_open Icon 而非 byTooltip 定位：Tooltip 是 Overlay 渲染，
    // RenderBox center (541, 87) 落在画布 Listener 的 opaque hit test
    // 区域内，tester.tap 报 hit test 警告且未触发 onPressed。
    await tester.tap(find.byIcon(Icons.lock_open));
    await tester.pump();
    expect(state.debugTransform.getMaxScaleOnAxis(),
        lessThan(before)); // 先确认滚轮已生效过
    final lockedScale = state.debugTransform.getMaxScaleOnAxis();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    try {
      await tester.sendEventToBinding(PointerScrollEvent(
          position: tester.getCenter(canvasF),
          scrollDelta: const Offset(0, -120)));
      await tester.pump();
    } finally {
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    }
    expect(state.debugTransform.getMaxScaleOnAxis(), lockedScale,
        reason: '锁定后 Ctrl+滚轮缩放应失效');

    // 解锁回非锁定（便于拖动测试在锁定态进行：保持锁定，横幅拖动）
    // （上述滚轮验证已在锁定下保持锁定态；直接拖动家族A横幅）
    final labelRect = state.debugFamilyLabelRects[0];
    if (labelRect == null) {
      // 单家族也可能画横幅（familyLabels 空则不画）；此处保证多家族
      await pumpHome(tester);
      await _derive(tester);
      // 再找一次
      final st2 =
          tester.state<PedigreeCanvasState>(find.byType(PedigreeCanvas));
      final r2 = st2.debugFamilyLabelRects[0];
      expect(r2, isNotNull);
    } else {
      final screen = tester.getTopLeft(canvasF) +
          MatrixUtils.transformPoint(
              state.debugTransform, labelRect.center + const Offset(0, 14));
      await tester.dragFrom(screen, const Offset(50, 40));
      await tester.pump();
      final off = tester
          .widget<PedigreeCanvas>(canvasF)
          .familyOffsets[0];
      expect(off, isNotNull, reason: '锁定后拖动横幅应产生家族偏移');
      expect(off!.dx, greaterThan(0), reason: '家族应向右移动');
      expect(off.dy, greaterThan(0), reason: '家族应向下移动');
      // 只动了家族A：家族B偏移为空
      expect(
          tester.widget<PedigreeCanvas>(canvasF).familyOffsets[1], isNull,
          reason: '拖动家族A不应影响家族B');
    }
  });

  testWidgets('R19 信息面板有「删除」：初始双亲被拦并提示', (tester) async {
    await pumpHome(tester);
    await _derive(tester);
    final c = _canvas(tester);
    final father = c.nodes.firstWhere((n) => n.id == 'P-father');
    c.onNodeTap!(father);
    await tester.pump();
    expect(find.text('删除'), findsOneWidget, reason: '选中元素后信息面板底部应有删除按钮');
    await tester.ensureVisible(find.text('删除'));
    await tester.pump();
    await tester.tap(find.text('删除'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.textContaining('不可删除'), findsOneWidget,
        reason: '初始双亲不可删除');
  });

  testWidgets('R19 删除计算桶：删除后立即重算，该代清空（黑名单不再生）',
      (tester) async {
    await pumpHome(tester);
    await _derive(tester);
    final c0 = _canvas(tester);
    final f1 = c0.nodes.firstWhere((n) => n.generation == 1);
    c0.onNodeTap!(f1);
    await tester.pump();
    await tester.ensureVisible(find.text('删除'));
    await tester.pump();
    await tester.tap(find.text('删除'));
    await tester.pumpAndSettle();
    final c = _canvas(tester);
    expect(c.nodes.any((n) => n.id == f1.id), isFalse,
        reason: '计算桶应被删除并立即重算');
    expect(c.nodes.any((n) => n.generation == 1), isFalse,
        reason: '该桶是 F1 唯一桶，删除后该代清空（黑名单生效不再生）');
  });

  testWidgets('R20 删除 F1 后点「计算」能重新生成（删除标记一次性）',
      (tester) async {
    await pumpHome(tester);
    await _derive(tester);
    final c0 = _canvas(tester);
    final f1 = c0.nodes.firstWhere((n) => n.generation == 1);
    c0.onNodeTap!(f1);
    await tester.pump();
    await tester.ensureVisible(find.text('删除'));
    await tester.pump();
    await tester.tap(find.text('删除'));
    await tester.pumpAndSettle();

    var c = _canvas(tester);
    expect(c.nodes.any((n) => n.generation == 1), isFalse,
        reason: '删除后 F1 代为空');

    // 再次点击「计算」→ F1 重新计算出来（R20 修复点）
    await tester.tap(find.text('计算').first);
    await tester.pumpAndSettle();
    c = _canvas(tester);
    expect(c.nodes.any((n) => n.generation == 1), isTrue,
        reason: '删除后点击计算应重新生成 F1');
  });

  testWidgets('R20 删除整代后点「计算」重新展开 F1（前沿回退也能再算）',
      (tester) async {
    await pumpHome(tester);
    await _derive(tester);
    // 删除整代：全部家族 × F1
    await tester.tap(find.text('删除整代'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(DropdownButtonFormField<int>).last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('F1 及以后').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除'));
    await tester.pumpAndSettle();
    var c = _canvas(tester);
    expect(c.nodes.any((n) => n.generation == 1), isFalse,
        reason: '删除整代后 F1 清空');

    // 点「计算」→ F1 重新展开（_derive 在 maxGeneration==0 时补一代）
    await tester.tap(find.text('计算').first);
    await tester.pumpAndSettle();
    c = _canvas(tester);
    expect(c.nodes.any((n) => n.generation == 1), isTrue,
        reason: '删除整代后点计算应重新生成 F1');
  });

  testWidgets('R21 折叠态点代表桶=删整代集合；展开态=只删单桶', (tester) async {
    await pumpHome(tester);
    await _derive(tester);
    await tester.tap(find.text('计算下一代')); // F2 27 桶 → 默认折叠
    await tester.pumpAndSettle();
    var c = _canvas(tester);
    expect(c.collapsedKeys.contains('0:2'), isTrue, reason: 'F2 应处于收起态');

    // 收起态：点代表桶 → 删除整代集合（全部基因型）
    final rep = c.nodes.firstWhere((n) => n.generation == 2);
    c.onNodeTap!(rep);
    await tester.pump();
    await tester.ensureVisible(find.text('删除'));
    await tester.pump();
    await tester.tap(find.text('删除'));
    await tester.pumpAndSettle();
    // R8：收起态删除现弹确认（学生走查 #4），确认后才真删。
    await tester.tap(find.text('删除').last);
    await tester.pumpAndSettle();
    c = _canvas(tester);
    expect(c.nodes.any((n) => n.generation == 2), isFalse,
        reason: '收起态删除应清空整代集合（含隐藏的 26 个）');
    expect(c.nodes.any((n) => n.generation == 1), isTrue,
        reason: 'F1 不受影响');
    await tester.pump(const Duration(seconds: 5)); // 冲掉删除 toast
    await tester.pump();

    // 重新展开 F2
    await tester.tap(find.text('计算下一代'));
    await tester.pumpAndSettle();
    c = _canvas(tester);
    c.onToggleGen!('0:2'); // 展开 F2
    await tester.pumpAndSettle();
    c = _canvas(tester);
    final countBefore = c.nodes.where((n) => n.generation == 2).length;
    expect(countBefore, greaterThan(1), reason: '展开后 F2 全部桶可见');

    // 展开态：点某个桶 → 只删这一个
    final one = c.nodes.firstWhere((n) => n.generation == 2);
    c.onNodeTap!(one);
    await tester.pump();
    await tester.ensureVisible(find.text('删除'));
    await tester.pump();
    await tester.tap(find.text('删除'));
    await tester.pumpAndSettle();
    c = _canvas(tester);
    expect(c.nodes.any((n) => n.generation == 2 && n.genotype == one.genotype),
        isFalse,
        reason: '展开态删除只删点中的那一个基因型');
    expect(c.nodes.where((n) => n.generation == 2).length, countBefore - 1,
        reason: '其余桶保留');
  });

  testWidgets('R21 家族移动记录日志（起点→终点）；回退恢复位置', (tester) async {
    // 用更宽 viewport：800×800 下画布 220 宽、缩放条溢出画布，
    // 锁定按钮 hit test 失败。1200×800 让缩放条完整在画布内。
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(_app());
    await _derive(tester);
    await tester.tap(find.text('计算下一代'));
    await tester.pumpAndSettle();

    // 锁定 → 拖动家族 A 横幅
    await tester.tap(find.byIcon(Icons.lock_open));
    await tester.pump();
    final state =
        tester.state<PedigreeCanvasState>(find.byType(PedigreeCanvas));
    final labelRect = state.debugFamilyLabelRects[0]!;
    // v3.1 画布变窄后横幅中心恰落进左上缩放条悬浮面板（命中被抢），
    // 拖动起点取横幅中心偏下 14px（世界坐标，仍在横幅矩形内）。
    final screen = tester.getTopLeft(find.byType(PedigreeCanvas)) +
        MatrixUtils.transformPoint(
            state.debugTransform, labelRect.center + const Offset(0, 14));
    await tester.dragFrom(screen, const Offset(60, 30));
    await tester.pump();
    final off = tester
        .widget<PedigreeCanvas>(find.byType(PedigreeCanvas))
        .familyOffsets[0];
    expect(off, isNotNull, reason: '横幅拖动应产生家族偏移');

    // 日志新增「移动家族 A：起点 → 终点」
    await tester.tap(find.textContaining('日志（'));
    await tester.pumpAndSettle();
    expect(find.textContaining('移动家族 A'), findsOneWidget,
        reason: '移动家族应写入日志（按下→抬起 = 一条，含起点终点）');
    expect(find.textContaining('起点'), findsNothing,
        reason: '日志直接记录坐标式：起点→终点');

    // 回退到最早（第 0 步初始计算）→ 家族位置恢复
    await tester.tap(find.text('回退到此处').last);
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<PedigreeCanvas>(find.byType(PedigreeCanvas))
            .familyOffsets,
        isEmpty,
        reason: '回退应恢复家族手动位置');
  });

  testWidgets('R19 删除整代对话框：按家族删代，另一家族不动；全家族删代', (tester) async {
    await pumpHome(tester);
    await _derive(tester); // 家族A F1（AaBbCc 100%）
    await tester.tap(find.text('计算下一代')); // 家族A F2 + （加第二家族前只有 A）
    await tester.pumpAndSettle();
    await addSecondFamily(tester); // 家族B（Bb×Bb），P 代

    // 家族B 也要有 F1：再计算下一代（家族A F3 + 家族B F1）
    await tester.tap(find.text('计算下一代'));
    await tester.pumpAndSettle();
    // v3.2：删除整代移入底部操作条，SnackBar 浮动层会短暂遮挡——
    // 冲掉上一操作留下的 toast（含退出动画）再点。
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();

    // 打开删除整代对话框
    await tester.tap(find.text('删除整代'));
    await tester.pumpAndSettle();
    expect(find.text('全部家族'), findsOneWidget);
    expect(find.text('全部代数'), findsOneWidget);

    // 家族选择：家族 A（展开下拉后菜单含 家族 A / 家族 B）
    await tester.tap(find.byType(DropdownButtonFormField<int>).first);
    await tester.pumpAndSettle();
    expect(find.text('家族 B'), findsOneWidget, reason: '多家族下拉应列出全部家族');
    await tester.tap(find.text('家族 A').last);
    await tester.pumpAndSettle();
    // 世代选择：F1
    await tester.tap(find.byType(DropdownButtonFormField<int>).last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('F1 及以后').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除'));
    await tester.pumpAndSettle();

    var c = _canvas(tester);
    expect(c.nodes.any((n) => n.familyId == 0 && n.generation == 1), isFalse,
        reason: '家族A 的 F1 已删');
    expect(c.nodes.any((n) => n.familyId == 0 && n.generation > 1), isFalse,
        reason: '家族A 的 F1 后代一并删除');
    expect(c.nodes.any((n) => n.familyId == 1 && n.generation == 1), isTrue,
        reason: '家族B 的 F1 不受影响');
    expect(c.nodes.any((n) => n.familyId == 0 && n.generation == 0), isTrue,
        reason: '家族A 的创始双亲保留');
    await tester.pump(const Duration(seconds: 5)); // 冲掉 toast（含退出动画）
    await tester.pumpAndSettle();

    // 全部家族 × F1 → 家族B 的 F1 也被删
    await tester.tap(find.text('删除整代'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(DropdownButtonFormField<int>).last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('F1 及以后').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除'));
    await tester.pumpAndSettle();
    c = _canvas(tester);
    expect(c.nodes.any((n) => n.familyId == 1 && n.generation == 1), isFalse,
        reason: '全部家族删除后家族B 的 F1 也消失');
    expect(c.nodes.any((n) => n.generation == 0), isTrue,
        reason: '创始双亲保留（P 代禁删）');
  });

  testWidgets('R23 选中元素：相连元素高亮（connectedIds）+ 信息面板并列展示',
      (tester) async {
    await pumpHome(tester);
    await _derive(tester);
    var c = _canvas(tester);
    final father = c.nodes.firstWhere((n) => n.id == 'P-father');
    c.onNodeTap!(father);
    await tester.pump();
    c = _canvas(tester);
    // P-father 与 P-mother、F1（发育线）相连 → connectedIds（Map）应有
    expect(c.connectedIds['P-mother']?.isNotEmpty ?? false, isTrue,
        reason: '与选中节点相连的元素应进入柔光集合');
    expect(
        c.connectedIds.keys.any((id) =>
            c.nodes.any((n) => n.id == id && n.generation == 1)),
        isTrue,
        reason: 'F1 后代桶也算相连（lineage 边）');
    // 信息面板「相连元素」行并列展示
    await tester.ensureVisible(find.textContaining('相连元素'));
    await tester.pump();
    expect(find.textContaining('相连元素'), findsOneWidget,
        reason: '信息面板应列出与选中元素相连的元素');
  });

  testWidgets('R23 手动连线（半边 mating）也进相连高亮', (tester) async {
    await pumpHome(tester);
    await _derive(tester);
    // 添加 3 对外来混合桶
    await tester.tap(find.text('添加样本').last);
    await tester.pumpAndSettle();
    final field = find.descendant(
        of: find.byType(AlertDialog), matching: find.byType(TextField));
    await tester.enterText(field, 'AaBbCc');
    await tester.tap(find.text('添加'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 5)); // 冲掉 toast
    await tester.pump();

    // 连线模式：P-father × 外来桶的雌半边（半边 mating，懒分裂）
    await _enableWire(tester);
    var c = _canvas(tester);
    final father = c.nodes.firstWhere((n) => n.id == 'P-father');
    final ext = c.nodes.firstWhere((n) => n.isExternal);
    c.onNodeTap!(father); // 待命
    await tester.pump();
    c = _canvas(tester);
    c.onNodeHalfTap!(ext, PedigreeNodeKind.female);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    c = _canvas(tester);
    expect(
        c.edges.where((e) => e.kind == PedigreeEdgeKind.mating).length, 2,
        reason: '半边手动连线应成功（创始边 + 新 mating 边）');

    // 退出连线模式后再点选：相连柔光属于浏览态反馈，wire 内不叠加。
    await _disableWire(tester);
    await tester.pumpAndSettle();
    c = _canvas(tester);
    c.onNodeTap!(ext);
    await tester.pump();
    c = _canvas(tester);
    expect(c.connectedIds['P-father']?.isNotEmpty ?? false, isTrue,
        reason: '半边 mating 的另一端（父桶归一）应进入相连高亮');
    // R25：粒度到性别——连线挂在雌半边，则与 P-father 相连的是雄侧
    expect(
        c.connectedIds['P-father']?.contains(PedigreeNodeKind.male) ?? false,
        isTrue,
        reason: '与雌半边相连的另一端应标注为雄（只亮雄半边）');
  });

  testWidgets('R31 灯效绑定：A雄×B雌 连线，选中A雄 → B只亮雌', (tester) async {
    await pumpHome(tester);
    await _derive(tester);
    // 加第二家族（同 3 对）
    await tester.tap(find.text('添加家族'));
    await tester.pumpAndSettle();
    final fields = find.descendant(
        of: find.byType(AlertDialog), matching: find.byType(TextField));
    await tester.enterText(fields.at(0), 'AABBCC');
    await tester.enterText(fields.at(1), 'aabbcc');
    await tester.tap(find.text('添加'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('计算下一代'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 5));
    await tester.pump();

    // 连线：A桶雄半边 × B桶雌半边
    await _enableWire(tester);
    var c = _canvas(tester);
    final aBucket = c.nodes.firstWhere((n) => n.familyId == 0 && n.generation == 1);
    final bBucket = c.nodes.firstWhere((n) => n.familyId == 1 && n.generation == 1);
    c.onNodeHalfTap!(aBucket, PedigreeNodeKind.male);
    await tester.pump();
    c = _canvas(tester);
    c.onNodeHalfTap!(bBucket, PedigreeNodeKind.female);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // 退出连线模式：相连柔光是浏览态反馈，wire 内不叠加（2026-10-27）。
    await _disableWire(tester);
    await tester.pumpAndSettle();
    // 选中 A 桶雄半边 → B 桶应只亮 {female}
    c = _canvas(tester);
    c.onNodeTap!(aBucket);
    await tester.pump();
    c = _canvas(tester);
    final conn = c.connectedIds[bBucket.id];
    expect(conn, isNotNull, reason: 'B 桶应在相连集合');
    expect(conn!.contains(PedigreeNodeKind.female), isTrue,
        reason: 'A 雄应连 B 雌');
    expect(conn.contains(PedigreeNodeKind.male), isFalse,
        reason: 'A 雄不应亮 B 雄（用户反馈的 bug）');
    expect(c.connectedIds.containsKey(aBucket.id), isFalse,
        reason: '选中桶自身不出现在相连集合');
  });

  testWidgets('R31 整桶边性别消歧：XY关连整桶，开XY后选A雄→B只亮雌', (tester) async {
    await pumpHome(tester);
    await _derive(tester);
    // 关 XY（整桶线用整桶身份连）
    await _tapChip(tester, 'XY 性别');
    await tester.pump();
    // 加第二家族
    await tester.tap(find.text('添加家族'));
    await tester.pumpAndSettle();
    final fields = find.descendant(
        of: find.byType(AlertDialog), matching: find.byType(TextField));
    await tester.enterText(fields.at(0), 'AABBCC');
    await tester.enterText(fields.at(1), 'aabbcc');
    await tester.tap(find.text('添加'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('计算下一代'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 5));
    await tester.pump();

    // XY 关时点整桶连线（A-F1 × B-F1）
    await _enableWire(tester);
    var c = _canvas(tester);
    final aBucket = c.nodes.firstWhere((n) => n.familyId == 0 && n.generation == 1);
    final bBucket = c.nodes.firstWhere((n) => n.familyId == 1 && n.generation == 1);
    c.onNodeTap!(aBucket);
    await tester.pump();
    c = _canvas(tester);
    c.onNodeTap!(bBucket);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    c = _canvas(tester);
    expect(
        c.edges.any((e) =>
            e.kind == PedigreeEdgeKind.mating &&
            ((e.fromId == aBucket.id && e.toId == bBucket.id) ||
                (e.fromId == bBucket.id && e.toId == aBucket.id))),
        isTrue,
        reason: '整桶边已建');

    // 开 XY → 选中 A 雄 → B 应只亮 {female}
    await _tapChip(tester, 'XY 性别');
    await tester.pump();
    // 退出连线模式
    await _disableWire(tester);
    await tester.pumpAndSettle();
    c = _canvas(tester);
    c.onNodeHalfTap!(aBucket, PedigreeNodeKind.male);
    await tester.pump();
    c = _canvas(tester);
    expect(c.connectedIds[bBucket.id]?.contains(PedigreeNodeKind.female) ?? false,
        isTrue, reason: 'A 雄 → B 应亮雌（异性消歧）');
    expect(c.connectedIds[bBucket.id]?.contains(PedigreeNodeKind.male) ?? true,
        isFalse, reason: 'B 男不能亮（用户反馈的双亮 bug）');
  });

  testWidgets('R32 同性交配灯效：A雄×B雄 连线，选A雄 → B只亮雄；计算后仍亮雄',
      (tester) async {
    await pumpHome(tester);
    await _derive(tester);
    // 开启同性交配
    await _tapChip(tester, '同性交配');
    await tester.pump();
    await tester.pump(const Duration(seconds: 5)); // 冲掉 toast
    // 加第二家族（同 3 对）
    await tester.tap(find.text('添加家族'));
    await tester.pumpAndSettle();
    final fields = find.descendant(
        of: find.byType(AlertDialog), matching: find.byType(TextField));
    await tester.enterText(fields.at(0), 'AABBCC');
    await tester.enterText(fields.at(1), 'aabbcc');
    await tester.tap(find.text('添加'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('计算下一代'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 5));
    await tester.pump();

    // 连线：A桶雄半边 × B桶雄半边（同性交配）
    await _enableWire(tester);
    var c = _canvas(tester);
    final aBucket =
        c.nodes.firstWhere((n) => n.familyId == 0 && n.generation == 1);
    final bBucket =
        c.nodes.firstWhere((n) => n.familyId == 1 && n.generation == 1);
    c.onNodeHalfTap!(aBucket, PedigreeNodeKind.male);
    await tester.pump();
    c = _canvas(tester);
    c.onNodeHalfTap!(bBucket, PedigreeNodeKind.male);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // 退出连线模式后再点选（wire 只显示 armed/flash，不叠加选中光）。
    await _disableWire(tester);
    await tester.pumpAndSettle();
    // 选中 A 桶雄半边 → B 桶应只亮 {male}（用户反馈：强制异性的 bug）
    c = _canvas(tester);
    c.onNodeHalfTap!(aBucket, PedigreeNodeKind.male);
    await tester.pump();
    c = _canvas(tester);
    var conn = c.connectedIds[bBucket.id];
    expect(conn, isNotNull, reason: 'B 桶应在相连集合');
    expect(conn!.contains(PedigreeNodeKind.male), isTrue,
        reason: '同性交配：A 雄 × B 雄 → B 应亮雄');
    expect(conn.contains(PedigreeNodeKind.female), isFalse,
        reason: 'B 雌不能亮（R31 强制异性规则误伤同性边的 bug）');

    // 用户路径：连线后点「计算」→ recomputeFrom(0)，半边端点降级回整桶，
    // 但 R32 边性别标注保留 → 灯效仍精确（选 A 雄 → B 亮雄）。
    await tester.tap(find.text('计算下一代'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 5));
    await tester.pump();
    c = _canvas(tester);
    final a2 = c.nodes.firstWhere((n) => n.familyId == 0 && n.generation == 1);
    final b2 = c.nodes.firstWhere((n) => n.familyId == 1 && n.generation == 1);
    c.onNodeHalfTap!(a2, PedigreeNodeKind.male);
    await tester.pump();
    c = _canvas(tester);
    conn = c.connectedIds[b2.id];
    expect(conn, isNotNull, reason: '重算后 B 桶仍在相连集合');
    expect(conn!.contains(PedigreeNodeKind.male), isTrue,
        reason: '重算降级后靠边标注仍亮雄半边');
    expect(conn.contains(PedigreeNodeKind.female), isFalse,
        reason: '重算后不得退回「强制异性」');
  });

  testWidgets('R33→v2.2 参与端判定：边 A雄×B雌，点B雄(非参与端) → A 不亮；点B雌(参与端) → A亮雄',
      (tester) async {
    // 语义演进：2026-08-26 反馈"点 B雄 却亮 A雄"→ R33 一律异性兜底；
    // 2026-08-29 用户更精确裁定："只有一对正方形和圆形有联系，另一对
    // 并没有联系"——非参与端不应产生任何高亮。R33 异性兜底正是
    // "点 A○(非参与端)却让 B□ 亮"的根因，故改为参与端判定：
    // 我点的半边不在该 mating 边的标注端上 → 该边与我无关，跳过。
    await pumpHome(tester);
    await _derive(tester);
    await tester.tap(find.text('添加家族'));
    await tester.pumpAndSettle();
    final fields = find.descendant(
        of: find.byType(AlertDialog), matching: find.byType(TextField));
    await tester.enterText(fields.at(0), 'AABBCC');
    await tester.enterText(fields.at(1), 'aabbcc');
    await tester.tap(find.text('添加'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('计算下一代'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 5));
    await tester.pump();

    // 连线：A桶雄半边 × B桶雌半边（边本身是合法异性边）
    await _enableWire(tester);
    var c = _canvas(tester);
    final aBucket =
        c.nodes.firstWhere((n) => n.familyId == 0 && n.generation == 1);
    final bBucket =
        c.nodes.firstWhere((n) => n.familyId == 1 && n.generation == 1);
    c.onNodeHalfTap!(aBucket, PedigreeNodeKind.male);
    await tester.pump();
    c = _canvas(tester);
    c.onNodeHalfTap!(bBucket, PedigreeNodeKind.female);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // 退出连线模式。点 B 桶雄半边（非该边参与端）→ A 桶不得亮
    await tester.tap(find.widgetWithText(FilterChip, '连线'));
    await tester.pumpAndSettle();
    c = _canvas(tester);
    final b2 = c.nodes.firstWhere((n) => n.familyId == 1 && n.generation == 1);
    c.onNodeHalfTap!(b2, PedigreeNodeKind.male);
    await tester.pump();
    c = _canvas(tester);
    final a2 = c.nodes.firstWhere((n) => n.familyId == 0 && n.generation == 1);
    expect(c.connectedIds[a2.id], isNull,
        reason: 'v2.2：点 B雄（非参与端）时 A 桶不应有任何高亮——'
            '边是 A雄×B雌，与 B雄 无关（2026-08-29 用户裁定）');

    // 对照：点 B 桶雌半边（参与端）→ A 亮雄（该边的真实参与侧）
    c.onNodeHalfTap!(b2, PedigreeNodeKind.female);
    await tester.pump();
    c = _canvas(tester);
    final conn = c.connectedIds[a2.id];
    expect(conn, isNotNull, reason: '点参与端 B雌 时 A 桶应亮');
    expect(conn!.contains(PedigreeNodeKind.male), isTrue,
        reason: 'A 侧亮雄（该边 A 端参与性别为雄）');
    expect(conn.contains(PedigreeNodeKind.female), isFalse,
        reason: 'A 雌不得亮（A 端参与侧是雄）');
  });

  testWidgets('R33 重算降级后仍异性绑定：A雌×B雄 → 计算下一代 → 点B雄 → A亮雌',
      (tester) async {
    await pumpHome(tester);
    await _derive(tester);
    await tester.tap(find.text('添加家族'));
    await tester.pumpAndSettle();
    final fields = find.descendant(
        of: find.byType(AlertDialog), matching: find.byType(TextField));
    await tester.enterText(fields.at(0), 'AABBCC');
    await tester.enterText(fields.at(1), 'aabbcc');
    await tester.tap(find.text('添加'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('计算下一代'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 5));
    await tester.pump();

    // 连线：A桶雌半边 × B桶雄半边
    await _enableWire(tester);
    var c = _canvas(tester);
    final aBucket =
        c.nodes.firstWhere((n) => n.familyId == 0 && n.generation == 1);
    final bBucket =
        c.nodes.firstWhere((n) => n.familyId == 1 && n.generation == 1);
    c.onNodeHalfTap!(aBucket, PedigreeNodeKind.female);
    await tester.pump();
    c = _canvas(tester);
    c.onNodeHalfTap!(bBucket, PedigreeNodeKind.male);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await _disableWire(tester);
    await tester.pumpAndSettle();

    // 点「计算下一代」→ recomputeFrom：半边端点销毁重映射成整桶边
    // （标注保留但端点已降级），再点 B 雄 → A 仍应亮雌。
    await tester.tap(find.text('计算下一代'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 5));
    await tester.pump();
    c = _canvas(tester);
    final b2 = c.nodes.firstWhere((n) => n.familyId == 1 && n.generation == 1);
    c.onNodeHalfTap!(b2, PedigreeNodeKind.male);
    await tester.pump();
    c = _canvas(tester);
    final a2 = c.nodes.firstWhere((n) => n.familyId == 0 && n.generation == 1);
    final conn = c.connectedIds[a2.id];
    expect(conn, isNotNull, reason: '重算后 A 桶应在相连集合');
    expect(conn!.contains(PedigreeNodeKind.female), isTrue,
        reason: '重算降级后点 B 雄 → A 亮雌');
    expect(conn.contains(PedigreeNodeKind.male), isFalse,
        reason: '重算后 A 雄不得亮');
  });

  testWidgets('R29 灯效绑定：选中A桶雌半边 → 相连B桶只亮雄半边', (tester) async {
    await pumpHome(tester);
    await _derive(tester);
    // 加第二家族
    await tester.tap(find.text('添加家族'));
    await tester.pumpAndSettle();
    final fields = find.descendant(
        of: find.byType(AlertDialog), matching: find.byType(TextField));
    await tester.enterText(fields.at(0), 'AABBCC');
    await tester.enterText(fields.at(1), 'aabbcc');
    await tester.tap(find.text('添加'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('计算下一代'));
    await tester.pumpAndSettle();

    // 连线：A桶雌半边 × B桶雄半边（手动半边连线）
    await _enableWire(tester);
    var c = _canvas(tester);
    final aBucket = c.nodes.firstWhere((n) => n.familyId == 0 && n.generation == 1);
    final bBucket = c.nodes.firstWhere((n) => n.familyId == 1 && n.generation == 1);
    c.onNodeHalfTap!(aBucket, PedigreeNodeKind.female);
    await tester.pump();
    c = _canvas(tester);
    c.onNodeHalfTap!(bBucket, PedigreeNodeKind.male);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // 确认半边边已建立
    c = _canvas(tester);
    expect(
        c.edges.any((e) =>
            e.kind == PedigreeEdgeKind.mating &&
            e.fromId.startsWith('SPLIT#') &&
            e.toId.startsWith('SPLIT#')),
        isTrue,
        reason: 'A雌×B雄 半边连线应成功');
    // 退出连线模式后再点选：相连柔光只在浏览态显示。
    await _disableWire(tester);
    await tester.pumpAndSettle();
    c = _canvas(tester);
    c.onNodeTap!(aBucket);
    await tester.pump();
    c = _canvas(tester);
    final conn = c.connectedIds[bBucket.id];
    expect(conn, isNotNull, reason: 'B 桶应在相连集合');
    expect(conn!.contains(PedigreeNodeKind.male), isTrue,
        reason: 'A 雌应连 B 雄');
    expect(conn.contains(PedigreeNodeKind.female), isFalse,
        reason: 'A 雌不应亮 B 雌（同性交配未开）');
    // R30：选中桶不得自指相连（SPLIT 半边回指父桶被跳过）——
    // 否则组合桶整桶泛蓝（用户"只点一个元素却整个大矩形亮"根因）
    expect(c.connectedIds.containsKey(aBucket.id), isFalse,
        reason: '选中桶自身不应出现在相连集合');
  });

  testWidgets('R24 选择模式：XY 开=半边圈选绑定雄/雌；XY 关=整桶绑定',
      (tester) async {
    await pumpHome(tester);
    await _derive(tester);
    await tester.tap(find.text('计算下一代'));
    await tester.pumpAndSettle();

    // 展开 F2 才有多个可选桶；直接用 F1（单桶）验证绑定粒度
    var c = _canvas(tester);
    final f1 = c.nodes.firstWhere((n) => n.generation == 1);
    // 选择模式：勾选雄半边
    await tester.tap(find.text('选择元素'));
    await tester.pumpAndSettle();
    c = _canvas(tester);
    expect(c.pickedIds, isEmpty);
    c.onNodeHalfTap!(f1, PedigreeNodeKind.male); // 勾选雄性半边
    await tester.pump();
    c = _canvas(tester);
    expect(c.pickedIds.contains('${f1.id}::male'), isTrue);
    // XY 默认开 → soloHalfIds 绑定到雄半边（不是整桶）
    expect(c.soloHalfIds[f1.id], PedigreeNodeKind.male,
        reason: 'XY 开启时勾选雄半边应绑定到雄，而非整桶');
    // 再勾雌半边 → 两半都选 = 整桶（solo 移除）
    c.onNodeHalfTap!(f1, PedigreeNodeKind.female);
    await tester.pump();
    c = _canvas(tester);
    expect(c.soloHalfIds.containsKey(f1.id), isFalse,
        reason: '两个半边都勾选 = 整桶绑定');

    // 关闭 XY 性别 → 勾选半边也按整桶绑定（solo 失效）
    await _tapChip(tester, 'XY 性别');
    await tester.pump();
    c = _canvas(tester);
    c.onNodeHalfTap!(f1, PedigreeNodeKind.male); // 仍在选择模式再勾
    await tester.pump();
    c = _canvas(tester);
    expect(c.soloHalfIds, isEmpty,
        reason: 'XY 关闭时维持整桶绑定（solo 不生效）');
  });

  testWidgets('连锁互换开关：打开出默认 4:4:1:1，改 r=0 → 1:1，关闭隐藏',
      (tester) async {
    await pumpHome(tester);
    await _derive(tester);
    expect(find.text('连锁互换'), findsOneWidget, reason: '语义区开关存在');
    // v2.19.3 面板分组后语义区变高，「连锁互换」（高级组）在视口
    // 下缘——先滚入再点。
    await tester.ensureVisible(find.text('连锁互换'));
    await tester.pump();
    await tester.tap(find.text('连锁互换'));
    await tester.pumpAndSettle();
    expect(find.text('配子分布'), findsOneWidget, reason: '开启后展示结果区');
    expect(find.text('4 : 4 : 1 : 1'), findsOneWidget,
        reason: '默认案例 AB/ab×ab/ab r=20% → 4:4:1:1');

    // 改交换值为 0 → 完全连锁测交 1:1
    await tester.enterText(
        find.widgetWithText(TextField, '交换值 r'), '0');
    // 开关开启后面板内容变长，「计算子代」可能滚到面板可视区外
    //（被底部操作条占位截断，非 SnackBar），先滚到可见再点。
    await tester.ensureVisible(find.text('计算子代'));
    await tester.tap(find.text('计算子代'));
    await tester.pumpAndSettle();
    expect(find.text('1 : 1'), findsOneWidget, reason: 'r=0 → 1:1');

    // 关闭开关 → 区块消失，谱系画布不受影响
    // （区块标题与 chip 同名，用 .first 定位 chip —— chip 先于区块渲染）
    await tester.ensureVisible(find.text('连锁互换').first);
    await tester.tap(find.text('连锁互换').first);
    await tester.pumpAndSettle();
    expect(find.text('配子分布'), findsNothing);
    expect(find.byType(PedigreeCanvas), findsOneWidget);
  });

  testWidgets('v2.19.17 触控板双指平移：PointerPanZoom 序列驱动画布平移（找茬 ⚪9）',
      (tester) async {
    await pumpHome(tester);
    await _derive(tester);
    final state = tester.state<PedigreeCanvasState>(
        find.byType(PedigreeCanvas));
    final before = state.contentTransform.clone();
    final center = tester.getCenter(find.byType(PedigreeCanvas));

    // Precision Touchpad 双指拖动 = PointerPanZoom 序列（pan, scale=1）。
    final device = TestPointer();
    tester.binding.handlePointerEvent(PointerPanZoomStartEvent(
      device: device.device,
      position: center,
    ));
    tester.binding.handlePointerEvent(PointerPanZoomUpdateEvent(
      device: device.device,
      position: center,
      pan: const Offset(40, 24),
    ));
    await tester.pump();
    tester.binding.handlePointerEvent(
        PointerPanZoomEndEvent(device: device.device));
    await tester.pump();

    final after = state.contentTransform;
    // 平移生效：transform 平移分量变化（不卡死在原值）。
    expect(after.getTranslation() != before.getTranslation(), isTrue,
        reason: '双指平移后画布 transform 平移分量应变化');
  });
}
