// pedigree_touch_test.dart —— 系谱画布「教室大触控屏」加固验收
//
// 场景：老师把系谱画布投到 1920×1080 的大触控屏，单指/双指都要可靠。
// 覆盖：
// 1. 真实 TestPointer(touch) 双指捏合：确实缩放；不误触发节点点按
//    （页面配对由 onNodeTap 驱动 ⇒ 静默即不会发起配对）；捏合结束后
//    单指点选仍可用（手势竞技场复位），且组合桶走半边通道。
// 2. 缩小到 0.2 后普通点选命中区 ≥48 屏幕 px（普通节点与组合桶都测），
//    且不是无限贪婪（±27px 外仍判空白）；密集区仍由最近圆心决胜。
// 3. 低缩放冲突裁决：节点只是外扩命中时芯片优先（芯片扩区能展开），
//    但点在节点实际 body 内仍节点优先（芯片扩区不得偷节点身体）。
// 4. 精确长按 / 右键都不随点击容错扩大：偏离节点 20 屏幕 px 仍走空白菜单，
//    节点本体上的长按仍收线、右键仍节点菜单。
// 5. 双指轻点（按下即抬、无位移）不得误报点选/配对/空白点击。
// 6. 鼠标 / 触控笔点选不回归。
//
// 说明：这是 widget 级验证，不等于真实触控硬件验收（多点抖动、
// 手掌误触等仍需上机确认）。

import 'package:biology/engine/pedigree_graph.dart';
import 'package:biology/pages/widgets/pedigree_canvas.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// 记录画布上报的全部交互，用于「静默/触发」断言。
class _Probe {
  final List<String> nodeTaps = [];
  final List<String> halfTaps = [];
  final List<String> detached = [];
  final List<String> genToggles = [];
  final List<String> secondaryNodeTaps = [];
  int blankTaps = 0;
  int blankLongPresses = 0;
  int secondaryBlankTaps = 0;

  void clear() {
    nodeTaps.clear();
    halfTaps.clear();
    detached.clear();
    genToggles.clear();
    secondaryNodeTaps.clear();
    blankTaps = 0;
    blankLongPresses = 0;
    secondaryBlankTaps = 0;
  }
}

PedigreeNode _node(String id, PedigreeNodeKind kind, int generation) =>
    PedigreeNode(
      id: id,
      kind: kind,
      genotype: 'Aa',
      generation: generation,
      probability: 1.0,
      isExternal: false,
    );

/// 1920×1080 逻辑视口下挂载画布（覆盖教室大屏尺寸）。
Future<_Probe> _pumpCanvas(
  WidgetTester tester, {
  required List<PedigreeNode> nodes,
  List<PedigreeEdge> edges = const [],
  bool sexSplitView = false,
  Set<String> collapsedKeys = const {},
  Map<String, int> hiddenCounts = const {},
}) async {
  tester.view.physicalSize = const Size(1920, 1080);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final probe = _Probe();
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: PedigreeCanvas(
        nodes: nodes,
        edges: edges,
        sexSplitView: sexSplitView,
        collapsedKeys: collapsedKeys,
        hiddenCounts: hiddenCounts,
        onNodeTap: (n) => probe.nodeTaps.add(n.id),
        onNodeHalfTap: (g, sex) => probe.halfTaps.add(halfTapId(g.id, sex)),
        onBlankTap: () => probe.blankTaps++,
        onWireDetach: (n) => probe.detached.add(n.id),
        onBlankLongPress: (gen, pos) => probe.blankLongPresses++,
        onToggleGen: (k) => probe.genToggles.add(k),
        onNodeSecondaryTap: (n, pos) => probe.secondaryNodeTaps.add(n.id),
        onBlankSecondaryTap: (gen, pos) => probe.secondaryBlankTaps++,
      ),
    ),
  ));
  await tester.pump();
  return probe;
}

PedigreePainter _painter(WidgetTester tester) {
  final finder = find.byWidgetPredicate(
      (w) => w is CustomPaint && w.painter is PedigreePainter);
  expect(finder, findsOneWidget, reason: '画布应只有一个 PedigreePainter');
  return tester.widget<CustomPaint>(finder).painter! as PedigreePainter;
}

Matrix4 _transform(WidgetTester tester) => tester
    .state<PedigreeCanvasState>(find.byType(PedigreeCanvas))
    .contentTransform;

double _scaleOf(WidgetTester tester) =>
    _transform(tester).getMaxScaleOnAxis();

/// 世界坐标（painter.rects）→ 画布局部坐标 → 全局屏幕坐标。
Offset _sceneToGlobal(WidgetTester tester, Offset scene) =>
    tester.getTopLeft(find.byType(PedigreeCanvas)) +
    MatrixUtils.transformPoint(_transform(tester), scene);

Offset _nodeCenter(WidgetTester tester, String id) {
  final rect = _painter(tester).rects[id];
  expect(rect, isNotNull, reason: '节点 $id 应已布局');
  return _sceneToGlobal(tester, rect!.center);
}

/// 真实的按压-抬起（默认 touch 左键），避免 tap 语义里隐含的 mouse kind。
Future<void> _tap(WidgetTester tester, Offset at,
    {PointerDeviceKind kind = PointerDeviceKind.touch,
    int pointer = 21,
    int buttons = kPrimaryButton}) async {
  final g = await tester.startGesture(at,
      kind: kind, pointer: pointer, buttons: buttons);
  await tester.pump(const Duration(milliseconds: 30));
  await g.up();
  await tester.pump();
}

/// Ctrl+滚轮缩到画布下限（0.2）：两次大格滚动足够触底。
Future<void> _zoomToMinimum(WidgetTester tester) async {
  final anchor = tester.getCenter(find.byType(PedigreeCanvas));
  await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  try {
    for (var i = 0; i < 4; i++) {
      await tester.sendEventToBinding(PointerScrollEvent(
          position: anchor, scrollDelta: const Offset(0, 1000)));
      await tester.pump();
    }
  } finally {
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  }
}

void main() {
  testWidgets('大屏双指捏合：真实触点缩放、不误触发点选/配对；随后单指点选恢复',
      (tester) async {
    final probe = await _pumpCanvas(
      tester,
      nodes: [
        _node('P-father', PedigreeNodeKind.male, 0),
        _node('P-mother', PedigreeNodeKind.female, 0),
        _node('F1#0', PedigreeNodeKind.group, 1),
        _node('F1#1', PedigreeNodeKind.group, 1),
      ],
      // XY 组合桶渲染：组合桶的点选走半边通道，能真正验证
      // 「捏合不误报名半边」而不是对着恒空的通道断言。
      sexSplitView: true,
      edges: const [
        PedigreeEdge('P-father', 'P-mother', PedigreeEdgeKind.mating),
        PedigreeEdge('P-father', 'F1#0', PedigreeEdgeKind.lineage),
        PedigreeEdge('P-mother', 'F1#0', PedigreeEdgeKind.lineage),
      ],
    );

    // 有意让两根手指都落在组合桶 F1#0 身体上：捏合若被误判成点按，
    // 会立刻产生 nodeTap/配对请求。
    final focal = _nodeCenter(tester, 'F1#0');
    final before = _scaleOf(tester);

    final g1 = await tester.startGesture(focal + const Offset(-40, 0),
        kind: PointerDeviceKind.touch, pointer: 11);
    final g2 = await tester.startGesture(focal + const Offset(40, 0),
        kind: PointerDeviceKind.touch, pointer: 12);
    await tester.pump();
    await g1.moveBy(const Offset(-120, 0));
    await g2.moveBy(const Offset(120, 0));
    await tester.pump();

    final after = _scaleOf(tester);
    expect(after, greaterThan(before * 1.2), reason: '双指张开应实际放大');
    expect(probe.nodeTaps, isEmpty, reason: '捏合不得误触发节点点按（页面据此配对）');
    expect(probe.halfTaps, isEmpty, reason: '组合桶半边点选同样不得被误触发');
    expect(probe.blankTaps, 0, reason: '捏合不得被当成空白点击（会清选中）');

    await g1.up();
    await g2.up();
    await tester.pumpAndSettle();

    // 捏合结束后：单指点选仍可用，且只上报一次。
    // 组合桶左半边 = 雄性通道（halfTapId 合成 id）。
    final bucketRect = _painter(tester).rects['F1#0']!;
    await _tap(
        tester,
        _sceneToGlobal(
            tester, bucketRect.center - const Offset(12, 0)));
    expect(probe.halfTaps, ['F1#0::male'],
        reason: '双指结束后单指点半边应恢复正常，且走 half 通道');
    expect(probe.nodeTaps, isEmpty, reason: '半边命中不应再走整节点通道');
    expect(probe.blankTaps, 0);

    // 普通（非组合桶）节点在同一 sexSplitView 下仍走 nodeTap 通道。
    probe.clear();
    await _tap(tester, _nodeCenter(tester, 'P-father'));
    expect(probe.nodeTaps, ['P-father'], reason: '普通节点不受半边拆分影响');
    expect(probe.halfTaps, isEmpty);
  });

  testWidgets('双指轻点（按下即抬、无位移）不得误报点选/配对/空白点击',
      (tester) async {
    final probe = await _pumpCanvas(
      tester,
      nodes: [
        _node('P-father', PedigreeNodeKind.male, 0),
        _node('P-mother', PedigreeNodeKind.female, 0),
        _node('F1#0', PedigreeNodeKind.group, 1),
        _node('F1#1', PedigreeNodeKind.group, 1),
      ],
      sexSplitView: true,
    );

    // 两指同时搭在同一个组合桶上，不做任何位移就抬起——教室大屏上
    // 很常见的「顺手两指碰一下」。这不该被当成点选/配对/空白。
    final focal = _nodeCenter(tester, 'F1#0');
    final g1 = await tester.startGesture(focal + const Offset(-30, 0),
        kind: PointerDeviceKind.touch, pointer: 41);
    final g2 = await tester.startGesture(focal + const Offset(30, 0),
        kind: PointerDeviceKind.touch, pointer: 42);
    await tester.pump(const Duration(milliseconds: 40));
    await g1.up();
    await g2.up();
    await tester.pumpAndSettle();

    expect(probe.nodeTaps, isEmpty, reason: '双指轻点不得点选节点（会发起配对）');
    expect(probe.halfTaps, isEmpty, reason: '双指轻点不得报半边点选');
    expect(probe.blankTaps, 0, reason: '双指轻点不得当空白点击清选中');

    // 双指抬手后单指点选必须恢复（多指抑制不能粘住）。
    await _tap(tester, _nodeCenter(tester, 'P-father'));
    expect(probe.nodeTaps, ['P-father'], reason: '双指结束后单指点选应恢复');
  });

  testWidgets('双指轻点反序抬手（次指先抬）同样不得误报点选/配对',
      (tester) async {
    final probe = await _pumpCanvas(
      tester,
      nodes: [
        _node('P-father', PedigreeNodeKind.male, 0),
        _node('P-mother', PedigreeNodeKind.female, 0),
        _node('F1#0', PedigreeNodeKind.group, 1),
        _node('F1#1', PedigreeNodeKind.group, 1),
      ],
      sexSplitView: true,
    );

    // 反序抬手：次指（g2）先抬、主指（g1）后抬。
    // Flutter 派发顺序 = hit-test path 里的 RenderPointerListener 先收到
    // up，GestureBinding 最后才 pointerRouter.route(up) → 主指的 onTapUp
    // 在「计数已归零」之后执行；若标志在归零时就清，这里会误报点选。
    final focal = _nodeCenter(tester, 'F1#0');
    var g1 = await tester.startGesture(focal + const Offset(-30, 0),
        kind: PointerDeviceKind.touch, pointer: 51);
    var g2 = await tester.startGesture(focal + const Offset(30, 0),
        kind: PointerDeviceKind.touch, pointer: 52);
    await tester.pump(const Duration(milliseconds: 40));
    await g2.up(); // 次指先抬
    await g1.up(); // 主指后抬
    await tester.pumpAndSettle();

    expect(probe.halfTaps, isEmpty, reason: '反序抬手同样不得报半边点选');
    expect(probe.nodeTaps, isEmpty, reason: '反序抬手同样不得点选节点');
    expect(probe.blankTaps, 0, reason: '反序抬手不得当空白点击');

    // 整节点通道同理：两指都落在父亲身体上。
    probe.clear();
    final father = _nodeCenter(tester, 'P-father');
    g1 = await tester.startGesture(father + const Offset(-20, 0),
        kind: PointerDeviceKind.touch, pointer: 53);
    g2 = await tester.startGesture(father + const Offset(20, 0),
        kind: PointerDeviceKind.touch, pointer: 54);
    await tester.pump(const Duration(milliseconds: 40));
    await g2.up();
    await g1.up();
    await tester.pumpAndSettle();
    expect(probe.nodeTaps, isEmpty, reason: '反序双指轻点不得走 nodeTap 通道');
    expect(probe.blankTaps, 0);

    // 反序双指结束后单指点选仍恢复。
    await _tap(tester, _nodeCenter(tester, 'P-father'));
    expect(probe.nodeTaps, ['P-father'], reason: '反序双指结束后单指应恢复');
  });

  testWidgets('双指静止 700ms：不触发收线/空白菜单，也不误点选',
      (tester) async {
    final probe = await _pumpCanvas(
      tester,
      nodes: [
        _node('P-father', PedigreeNodeKind.male, 0),
        _node('F1#0', PedigreeNodeKind.group, 1),
      ],
    );

    // 两指静置超过长按 500ms：教室里「手搭在屏上说话」很常见，
    // 不能凭空收回连线或弹快捷菜单。
    final focal = _nodeCenter(tester, 'F1#0');
    final g1 = await tester.startGesture(focal + const Offset(-24, 0),
        kind: PointerDeviceKind.touch, pointer: 61);
    final g2 = await tester.startGesture(focal + const Offset(24, 0),
        kind: PointerDeviceKind.touch, pointer: 62);
    await tester.pump(const Duration(milliseconds: 700));
    expect(probe.detached, isEmpty, reason: '双指静止不得收回该节点连线');
    expect(probe.blankLongPresses, 0, reason: '双指静止不得弹空白快捷菜单');
    expect(probe.nodeTaps, isEmpty, reason: '双指静止不得点选节点');
    expect(probe.blankTaps, 0);

    await g2.up();
    await g1.up();
    await tester.pumpAndSettle();
    expect(probe.detached, isEmpty, reason: '抬手时也不得补报收线');
    expect(probe.blankLongPresses, 0);
    expect(probe.nodeTaps, isEmpty);

    // 单指长按 / 点选仍按原语义。
    var g = await tester.startGesture(_nodeCenter(tester, 'F1#0'),
        kind: PointerDeviceKind.touch, pointer: 63);
    await tester.pump(const Duration(milliseconds: 700));
    await g.up();
    await tester.pump();
    expect(probe.detached, ['F1#0'], reason: '单指长按仍 = 收回最近一条连线');

    probe.clear();
    await _tap(tester, _nodeCenter(tester, 'F1#0'));
    expect(probe.nodeTaps, ['F1#0'], reason: '单指点选仍正常');
  });

  testWidgets('缩到 0.2：普通节点点选命中区补到 48 屏幕 px（且不无限贪婪）',
      (tester) async {
    final probe = await _pumpCanvas(
      tester,
      nodes: [
        _node('P-father', PedigreeNodeKind.male, 0),
        _node('F1#0', PedigreeNodeKind.group, 1),
      ],
    );

    await _zoomToMinimum(tester);
    expect(_scaleOf(tester), moreOrLessEquals(0.2, epsilon: 1e-6),
        reason: '画布应已缩到下限 0.2');
    // 此时普通节点身体只剩 64*0.2 = 12.8 屏幕 px。
    final center = _nodeCenter(tester, 'P-father');

    // ±23 屏幕 px（身体外 16.2px）仍应命中：命中区 ≥48 屏幕 px。
    await _tap(tester, center + const Offset(0, -23));
    expect(probe.nodeTaps, ['P-father'],
        reason: '0.2 缩放下 23px 偏移仍命中节点（命中区约 48px）');
    probe.clear();
    await _tap(tester, center + const Offset(23, 0));
    expect(probe.nodeTaps, ['P-father'], reason: '水平方向同样 ≥48px');
    expect(probe.blankTaps, 0);

    // ±27 屏幕 px 已越界：不该无限膨胀去偷空白。
    probe.clear();
    await _tap(tester, center + const Offset(27, 0));
    expect(probe.nodeTaps, isEmpty, reason: '27px 偏移在 48px 命中区之外');
    expect(probe.blankTaps, 1, reason: '越界应判空白');

    // 组合桶（128×60，短边更矮）同样补到 48px。
    probe.clear();
    final groupCenter = _nodeCenter(tester, 'F1#0');
    await _tap(tester, groupCenter + const Offset(0, 23));
    expect(probe.nodeTaps, ['F1#0'],
        reason: '组合桶短边 60*0.2=12px，命中区同样补到 48px');
  });

  testWidgets('0.2 缩放：节点外扩命中不吞世代芯片，但节点身体仍优先',
      (tester) async {
    final probe = await _pumpCanvas(
      tester,
      nodes: [
        _node('P-father', PedigreeNodeKind.male, 0),
        _node('P-mother', PedigreeNodeKind.female, 0),
        _node('F1#0', PedigreeNodeKind.group, 1),
        _node('F1#1', PedigreeNodeKind.group, 1),
      ],
      // 折叠第 1 代 → 栏右缘出现「+N」芯片（chipKeys 需要 collapsed 或选中）。
      collapsedKeys: const {'0:1'},
      hiddenCounts: const {'0:1': 3},
    );
    await _zoomToMinimum(tester);

    final chip = _painter(tester).genChipRects['0:1'];
    expect(chip, isNotNull, reason: '折叠后应有世代芯片');
    final groupRect = _painter(tester).rects['F1#1']!;

    // ① 点在芯片左缘再往左 20 世界 px（= 芯片扩区，节点仅外扩命中）：
    //    节点右缘距芯片左缘只有 44 世界 px，此处 0.2 缩放下早已进入
    //    48px 点选区，但点在节点身体之外 → 应展开芯片而不是点节点。
    await _tap(tester,
        _sceneToGlobal(tester, Offset(chip!.left - 20, chip.center.dy)));
    expect(probe.genToggles, ['0:1'],
        reason: '低缩放：节点只是外扩命中时，芯片扩区应能展开');
    expect(probe.nodeTaps, isEmpty, reason: '不得把芯片扩区判成点节点');

    // ② 芯片本体中心：既有「芯片命中 ≥48 屏幕 px」语义不破。
    probe.clear();
    await _tap(tester, _sceneToGlobal(tester, chip.center));
    expect(probe.genToggles, ['0:1'], reason: '芯片本体点击仍展开');
    expect(probe.nodeTaps, isEmpty);

    // ③ 点在节点实际 body 内（同时也在芯片扩区里）：仍节点优先——
    //    守住 v2.19.15「芯片扩区不得偷节点身体」的旧修复。
    probe.clear();
    await _tap(
        tester,
        _sceneToGlobal(
            tester, Offset(chip.left - 56, groupRect.center.dy)));
    expect(probe.nodeTaps, ['F1#1'],
        reason: '点落在节点可视 body 内时，芯片扩区不得抢走');
    expect(probe.genToggles, isEmpty, reason: '身体内点击不应触发芯片展开');
  });

  testWidgets('密集重叠区仍由最近圆心决胜（不按遍历顺序抢）', (tester) async {
    final probe = await _pumpCanvas(
      tester,
      nodes: [
        _node('P-father', PedigreeNodeKind.male, 0),
        _node('P-mother', PedigreeNodeKind.female, 0),
      ],
    );
    await _zoomToMinimum(tester);

    // 0.2 缩放下两节点圆心只隔 18.4 屏幕 px，两边 48px 命中区大量重叠。
    final father = _nodeCenter(tester, 'P-father');
    final mother = _nodeCenter(tester, 'P-mother');
    final gap = mother.dx - father.dx;
    expect(gap, greaterThan(10), reason: '两节点应可分辨，便于验证取近');

    // 偏向父亲一侧（圆心右 4px）：虽落在两者命中区内，应判父亲。
    await _tap(tester, Offset(father.dx + 4, father.dy));
    expect(probe.nodeTaps, ['P-father'],
        reason: '重叠区里最近的是父亲，不得被后遍历到的节点抢走');

    // 偏向母亲一侧（父亲圆心右 14px，已在母亲圆心附近）：应判母亲。
    probe.clear();
    await _tap(tester, Offset(father.dx + 14, father.dy));
    expect(probe.nodeTaps, ['P-mother'],
        reason: '最近圆心决胜：靠近母亲就应点亮母亲');
    expect(probe.blankTaps, 0, reason: '重叠区内不应漏判成空白');
  });

  testWidgets('精确长按不被扩大：偏离节点 20px 仍走空白菜单，节点本体仍收线',
      (tester) async {
    final probe = await _pumpCanvas(
      tester,
      nodes: [
        _node('P-father', PedigreeNodeKind.male, 0),
        _node('F1#0', PedigreeNodeKind.group, 1),
      ],
    );
    await _zoomToMinimum(tester);

    final groupCenter = _nodeCenter(tester, 'F1#0');
    var g = await tester.startGesture(groupCenter + const Offset(0, 20),
        kind: PointerDeviceKind.touch, pointer: 31);
    await tester.pump(const Duration(milliseconds: 700));
    await g.up();
    await tester.pump();

    expect(probe.detached, isEmpty, reason: '长按仍是精确命中，不随点击容错扩大');
    expect(probe.blankLongPresses, 1, reason: '偏离节点的长按应弹空白快捷菜单');

    // 节点本体上的长按仍收线（既有语义不变）。
    probe.clear();
    g = await tester.startGesture(groupCenter,
        kind: PointerDeviceKind.touch, pointer: 32);
    await tester.pump(const Duration(milliseconds: 700));
    await g.up();
    await tester.pump();
    expect(probe.detached, ['F1#0'], reason: '节点本体长按仍 = 收回最近一条连线');
    expect(probe.blankLongPresses, 0);
  });

  testWidgets('精确右键：偏离节点 20px 走空白菜单，节点本体仍节点菜单',
      (tester) async {
    final probe = await _pumpCanvas(
      tester,
      nodes: [
        _node('P-father', PedigreeNodeKind.male, 0),
        _node('F1#0', PedigreeNodeKind.group, 1),
      ],
    );
    await _zoomToMinimum(tester);

    final groupCenter = _nodeCenter(tester, 'F1#0');
    // 偏离节点 20 屏幕 px（仍在 48px 点选命中区内）→ 空白右键菜单，
    // 否则 0.2 缩放下「空白处加样本/家族」的入口会被 48px 扩区堵死。
    await _tap(tester, groupCenter + const Offset(0, 20),
        kind: PointerDeviceKind.mouse, buttons: kSecondaryMouseButton);
    expect(probe.secondaryNodeTaps, isEmpty,
        reason: '右键是已定位手势，不随 48px 点选扩区');
    expect(probe.secondaryBlankTaps, 1, reason: '偏离节点的右键应走空白菜单');

    // 节点本体右键仍是节点菜单（既有语义不变）。
    probe.clear();
    await _tap(tester, groupCenter,
        kind: PointerDeviceKind.mouse, buttons: kSecondaryMouseButton);
    expect(probe.secondaryNodeTaps, ['F1#0'], reason: '节点本体右键 = 节点菜单');
    expect(probe.secondaryBlankTaps, 0);
  });

  testWidgets('鼠标 / 触控笔点选不回归', (tester) async {
    final probe = await _pumpCanvas(
      tester,
      nodes: [
        _node('P-father', PedigreeNodeKind.male, 0),
        _node('P-mother', PedigreeNodeKind.female, 0),
      ],
    );

    final center = _nodeCenter(tester, 'P-father');
    await _tap(tester, center, kind: PointerDeviceKind.mouse);
    expect(probe.nodeTaps, ['P-father'], reason: '鼠标点选仍命中');

    probe.clear();
    await _tap(tester, _nodeCenter(tester, 'P-mother'),
        kind: PointerDeviceKind.stylus);
    expect(probe.nodeTaps, ['P-mother'], reason: '触控笔（stylus）点选仍命中');

    // 空白区鼠标左键仍是空白点击（不因 48px 补足把整屏都算节点）。
    probe.clear();
    await _tap(tester, tester.getBottomRight(find.byType(PedigreeCanvas)) -
            const Offset(60, 100),
        kind: PointerDeviceKind.mouse);
    expect(probe.nodeTaps, isEmpty);
    expect(probe.blankTaps, 1, reason: '远离节点的空白点击仍上报空白');
  });

  testWidgets('已展开的世代仍有收起芯片，点它能把该代收回去', (tester) async {
    final probe = await _pumpCanvas(
      tester,
      nodes: [
        _node('P-father', PedigreeNodeKind.male, 0),
        _node('P-mother', PedigreeNodeKind.female, 0),
        _node('F1#0', PedigreeNodeKind.group, 1),
        _node('F1#1', PedigreeNodeKind.group, 1),
      ],
      // 该代已展开（不在 collapsedKeys），但仍有隐藏计数 → 必须保留收起入口。
      collapsedKeys: const {},
      hiddenCounts: const {'0:1': 1},
    );

    final chip = _painter(tester).genChipRects['0:1'];
    expect(chip, isNotNull, reason: '展开态必须仍有收起入口');

    await _tap(tester, _sceneToGlobal(tester, chip!.center));
    expect(probe.genToggles, ['0:1'], reason: '点收起芯片应回传同一组键');
    expect(probe.nodeTaps, isEmpty);
    expect(tester.takeException(), isNull);
  });
}
