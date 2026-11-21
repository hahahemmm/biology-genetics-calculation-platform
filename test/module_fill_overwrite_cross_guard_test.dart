// ════════════════════════════════════════════════════════════════════════
//  test/module_fill_overwrite_cross_guard_test.dart
//  遗传计算器（9331）7 个 ModuleFillTarget 的防覆盖闸 + 拒收提示守卫。
// ════════════════════════════════════════════════════════════════════════
//
//  ## 病灶
//
//  `ModuleFillTarget.canOverwrite`（`lib/ui/module_fill.dart`）：目标页回答
//  「我那儿现在是不是空着」。返回 false ⇒ `fill`/`fillScan` **仍然切页**
//  （学生的导航意图要满足）但**跳过 apply**，并用 `kModuleFillSkippedDirty`
//  调 `onApplyFailed`。⛔ 两者为 null 时**完全不设防**——直接 `apply(params)`，
//  学生已敲的题被无声顶掉，且零提示。
//
//  A 仓这 7 个注册点（`lib/pages/cross_calculator_page.dart:158-224`）此前
//  既没有 `canOverwrite` 也没有 `onApplyFailed`：拍题识别链路走的正是
//  `fillScan`，学生会看着自己敲的 p1/p2 被静默顶掉。
//
//  ## ⛔ 断言为什么落在 controller 实际值 / 渲染产物上
//
//  1. `fill()` 被拒绝时**恒返回 true** ⇒ 断言「返回 true」**不能**证明参数写
//     进去了。所以正向一律断言 `TextField.controller!.text`（State 真正持有的
//     同一个 controller 实例，apply 直接写 `.text`）。
//  2. 纪律 17：「树上有 widget」≠「屏上画出了东西」。反向一律**两条**：controller
//     的 `.text` 没变 **且** 屏上出现那句提示；再补一条接线检查
//     （`canOverwrite()` 翻 false），证明挂的是活控制器而不是 nil。
//
//  ## 判据锚点（按输入框 label 文字，不按 controller 身份）
//
//  宽屏（>=1200）时 7 个页签都只在自己 body 里 `if (!wide) buildSidePanel`，
//  输入面板唯一一份挂在左栏 rail ⇒ 每个 label 在树上**唯一**（`findsOneWidget`
//  是前提硬断言，产品改文案先红、不会静默 0 命中）。
//
//  ## 复现三要素
//
//  · 复现路径：主导航「遗传计算器」页（pageIndex 2）→ 点页签名切到目标页签 →
//    （反向用例）`enterText` 手敲，再 `ModuleFillBus.fill`。
//  · 判据锚点：输入框 label（`亲本 1` / `母亲基因型 ♀` / `交换值 r` …）
//    + 提示文案**整句**（直接用总线常量 `kModuleFillSkippedDirty`）。
//  · 实测数字：出厂值逐字见各 `_kFactory` 注释；手敲值见 `_cases`。
// ════════════════════════════════════════════════════════════════════════

import 'package:biology/pages/cross_calculator_page.dart';
import 'package:biology/pages/widgets/linkage_tab.dart';
import 'package:biology/pages/widgets/method_compare_tab.dart';
import 'package:biology/pages/widgets/mono_cross_widget.dart';
import 'package:biology/pages/widgets/random_mating_tab.dart';
import 'package:biology/pages/widgets/sex_linked_tab.dart';
import 'package:biology/ui/module_fill.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 开一页 9331。视口 1400×3000：宽屏（>=1200）下 7 个页签的输入面板都注入
/// 左栏 rail，窄屏则自渲染在 body 里——两种形态都能拿到输入框，但宽屏下
/// 「当前页签的输入框」在树上唯一，判据锚点不会撞车。
///
/// [size] 只给自由交配那一组用（见那里的说明）。
Future<void> _pumpPage(WidgetTester t,
    {Size size = const Size(1400, 3000)}) async {
  t.view.physicalSize = size;
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
  await t.pumpWidget(const MaterialApp(home: CrossCalculatorPage()));
  await t.pump();
  await t.pump(const Duration(milliseconds: 600));
}

/// 点页签名把目标页签切到前台（挂上它的 State）。默认页签是「双基因 9331」。
Future<void> _gotoTab(WidgetTester t, String tabName) async {
  if (tabName != '双基因 9331') {
    final tab = find.text(tabName);
    expect(tab, findsWidgets, reason: '页签页名「$tabName」必须在屏上');
    await t.tap(tab.first);
    await t.pumpAndSettle();
  }
}

/// 目标页签的 `canOverwrite()`（缺守卫 ⇒ 前提就红，不静默放行）。
bool _canOverwrite(String moduleId) {
  final t = ModuleFillBus.targetOf(moduleId);
  expect(t, isNotNull, reason: 'moduleId「$moduleId」必须已注册');
  final can = t!.canOverwrite;
  expect(can, isNotNull,
      reason: 'moduleId「$moduleId」必须挂 canOverwrite（深链不覆盖学生敲的题）');
  return can!();
}

/// 某个 label 输入框的 controller 实际值（`findsOneWidget` 是前提硬断言）。
String _ctrlText(WidgetTester t, String label) {
  final f = find.widgetWithText(TextField, label);
  expect(f, findsOneWidget, reason: '前提：「$label」输入框在场上（唯一）');
  return t.widget<TextField>(f).controller!.text;
}

/// `fill` 之后等「总线 apply」+「容器页真正写 controller」两级 postFrame。
///
/// ⛔ **第 2 帧没人排时 `pump` 会空转**：测试绑定只在 `hasScheduledFrame` 时真
/// 跑一帧。而容器页把写入推到第 2 帧（`_flushFill`），它前面的
/// `animateTo` 落在**已激活**的页签上时不产生动画 ⇒ 也就没人排帧 ⇒ 只
/// `pump` 两次的话，参数永远写不进输入框（红输出会说「实际值还是出厂值」，
/// 与「守卫没生效」长得一模一样）。这里显式补排后几帧——**测试侧**的排帧
/// 补丁，不是产品行为。
///
/// ⛔ 不用 `pumpAndSettle`：反向用例里输入框已被 `enterText` 聚焦，光标在
/// 闪 ⇒ 每 500ms 排一帧，`pumpAndSettle` 会一直等下去。
Future<void> _pumpFill(WidgetTester t) async {
  await t.pump(); // 第 1 帧：总线的 postFrame 调 apply
  for (var i = 0; i < 3; i++) {
    // 第 2 帧：_flushFill 真写 controller；再往后：目标页签挂上后左栏 rail
    // 的输入面板重建（容器页要等一帧才拿得到新页签的 State）。
    TestWidgetsFlutterBinding.instance.scheduleFrame();
    await t.pump(const Duration(milliseconds: 600));
  }
}

/// 一个 target 的完整用例参数。
/// 出厂值（逐字对齐各 State 的 `_kDefault*`）：
///   双基因 AaBb/AaBb · 三对基因 AaBbCc/AaBbCc · 单基因 Aa/Aa
///   伴性 XAXa/XAY · 方法对比 AaBb/AaBb · 连锁 AB/ab · ab/ab · 20%
///   自由交配 Aa/1
typedef _Case = ({
  String id, // moduleId
  String tab, // 页签名
  Map<String, String> fill, // 深链载荷（须能过该 target 的 apply 校验）
  String typedLabel, // 反向用例手敲用的输入框 label
  String typed, // 手敲内容（与出厂值不同，且不会过 apply 校验也无所谓）
  String p1Label, // 正向断言的输入框 label
  String p2Label,
  String expectP1, // 出厂态 fill 后期望的 controller 值
  String expectP2,
  String? rLabel, // 连锁互换的第三参（其余 target 为 null）
  String? expectR,
});

const List<_Case> _cases = [
  (
    id: 'cross_dihybrid',
    tab: '双基因 9331',
    fill: {'p1': 'CcDd', 'p2': 'ccDD'},
    typedLabel: '亲本 1',
    typed: 'EeFf',
    p1Label: '亲本 1',
    p2Label: '亲本 2',
    expectP1: 'CcDd',
    expectP2: 'ccDD',
    rLabel: null,
    expectR: null,
  ),
  (
    id: 'cross_trihybrid',
    tab: '三对基因',
    fill: {'p1': 'AaBBcc', 'p2': 'aaBBCC'},
    typedLabel: '亲本 1',
    typed: 'aaBBCC',
    p1Label: '亲本 1',
    p2Label: '亲本 2',
    expectP1: 'AaBBcc',
    expectP2: 'aaBBCC',
    rLabel: null,
    expectR: null,
  ),
  (
    id: 'cross_mono',
    tab: '单基因杂交',
    fill: {'p1': 'AA', 'p2': 'aa'},
    typedLabel: '亲本 1',
    typed: 'Bb',
    p1Label: '亲本 1',
    p2Label: '亲本 2',
    expectP1: 'AA',
    expectP2: 'aa',
    rLabel: null,
    expectR: null,
  ),
  (
    id: 'cross_sex_linked',
    tab: '伴性遗传',
    fill: {'p1': 'XAXA', 'p2': 'XaY'},
    typedLabel: '母亲基因型 ♀',
    typed: 'XaXa',
    p1Label: '母亲基因型 ♀',
    p2Label: '父亲基因型 ♂',
    expectP1: 'XAXA',
    expectP2: 'XaY',
    rLabel: null,
    expectR: null,
  ),
  (
    id: 'cross_method_compare',
    tab: '方法对比',
    fill: {'p1': 'CcDd', 'p2': 'ccDD'},
    typedLabel: '亲本 1',
    typed: 'EeFf',
    p1Label: '亲本 1',
    p2Label: '亲本 2',
    expectP1: 'CcDd',
    expectP2: 'ccDD',
    rLabel: null,
    expectR: null,
  ),
  (
    id: 'cross_linkage',
    tab: '连锁互换',
    fill: {'p1': 'Ab/aB', 'p2': 'Ab/ab', 'r': '35%'},
    typedLabel: '亲本 1',
    typed: 'Ab/AB',
    p1Label: '亲本 1',
    p2Label: '亲本 2',
    expectP1: 'Ab/aB',
    expectP2: 'Ab/ab',
    rLabel: '交换值 r',
    expectR: '35%',
  ),
];

void main() {
  setUp(() {
    // 必须在 pumpWidget 之前清：容器页在 initState 里注册 7 个 target。
    ModuleFillBus.resetForTest();
    // 假导航器：页面是被直接 pump 的（HomeShell 不在场），只需「切页这一步
    // 发生过」——守卫正是在 navigator?.call **之后**才问的。
    ModuleFillBus.navigator = (_) {};

    // ⛔ 跨用例污染必须清：mono/伴性/方法对比/连锁四个页签的待填槽是
    // **静态**字段（`pendingFill`）。上一个用例的树在收尾帧里被销毁后，
    // 容器页的 `_flushFill` 若那时才跑到，会把待填槽写进这个静态字段
    // （`currentState` 已 null ⇒ 走「留给 tab initState 消费」那条分支）。
    // 下一个用例的页签一挂载就把它吃掉、`isPristine` 立刻翻 false ——
    // 于是「开局应放行」这条前提断言会红，红得跟守卫本身毫无关系。
    MonoCrossWidget.pendingFill = null;
    SexLinkedTab.pendingFill = null;
    MethodCompareTab.pendingFill = null;
    LinkageTab.pendingFill = null;
    // v2.19.39：自由交配的待填槽同样是**静态**字段（`pendingRm`），同一个
    // 坑：上一个用例的树在收尾帧才销毁时，容器页的 `_flushFill(6)` 会把参数
    // 写进它（`currentState` 已 null ⇒ 走「留给 tab initState 消费」那条分支）。
    RandomMatingTabState.pendingRm = null;
  });
  tearDown(() {
    ModuleFillBus.resetForTest();
    MonoCrossWidget.pendingFill = null;
    SexLinkedTab.pendingFill = null;
    MethodCompareTab.pendingFill = null;
    LinkageTab.pendingFill = null;
    RandomMatingTabState.pendingRm = null;
  });

  for (final c in _cases) {
    group(c.id, () {
      // ── ① 出厂态：参数真写进输入框 ──
      testWidgets('出厂状态下 fill 真把参数写进输入框', (t) async {
        await _pumpPage(t);
        await _gotoTab(t, c.tab);
        expect(_canOverwrite(c.id), isTrue,
            reason: '${c.id} 出厂（没人动过）⇒ 允许深链写入');

        expect(ModuleFillBus.fill(c.id, c.fill), isTrue,
            reason: '已注册 ⇒ fill 返 true');
        await _pumpFill(t);

        // 正向判据：controller 实际值。
        expect(_ctrlText(t, c.p1Label), c.expectP1,
            reason: '正向：${c.p1Label} 必须被深链参数写进去');
        expect(_ctrlText(t, c.p2Label), c.expectP2,
            reason: '正向：${c.p2Label} 必须被深链参数写进去');
        if (c.rLabel != null) {
          expect(_ctrlText(t, c.rLabel!), c.expectR,
              reason: '正向：${c.rLabel}（连锁互换第三参）必须被写进去');
        }
        expect(find.text(kModuleFillSkippedDirty), findsNothing,
            reason: '出厂态写入成功，不该出拒收提示');
      });

      // ── ② 手敲后：不覆盖 + 提示出现 ──
      testWidgets('学生敲了题后 fill 不覆盖 + 屏上出提示', (t) async {
        await _pumpPage(t);
        await _gotoTab(t, c.tab);
        // 前提：手敲之前守卫放行（此时的 true 只可能是「出厂」）。
        expect(_canOverwrite(c.id), isTrue, reason: '${c.id} 开局应放行');

        final field = find.widgetWithText(TextField, c.typedLabel);
        expect(field, findsOneWidget,
            reason: '前提：「${c.typedLabel}」输入框在场上（唯一）');
        await t.enterText(field, c.typed);
        await t.pump();

        // 闸拦下时 fill 仍返 true：导航意图要满足，只是没写入。
        expect(ModuleFillBus.fill(c.id, c.fill), isTrue,
            reason: '被闸拦下也返 true（已切页，只是没写入）');
        await _pumpFill(t);

        // 反向判据第一条：数据没变。
        expect(_ctrlText(t, c.typedLabel), c.typed,
            reason: '反向：学生敲的「${c.typed}」一个字都不能被顶掉');
        // 反向判据第二条：屏上出现提示（否则学生只看到「点了没反应」）。
        expect(find.text(kModuleFillSkippedDirty), findsOneWidget,
            reason: '闸拦下必须让用户看见「没写入」');
        // 接线检查：守卫读的是活控制器，不是常闭的 true。
        expect(_canOverwrite(c.id), isFalse,
            reason: '${c.id} 学生 enterText 敲了题 ⇒ 整页签 dirty');
      });
    });
  }

  // ── cross_random_mating：v2.19.39 补上回填通道后的两条（真闸 + 真写入）──
  //
  // ⛔ 这一组用 **1100 宽的窄视口**（<1200 工作台阈值，7 个页签名仍点得到）：
  // 宽屏下面板挂左栏 rail，而 rail 要等容器页**再重建一帧**才认新挂载的
  // 页签（`_currentSidePanel()` 读的是 rail 构建那一刻的 `currentState`）——
  // 真机上是 HomeShell 的 `setState` 顺带补的那一帧，独立 pump 的测试没人
  // 替它补，于是「面板在不在」成了测帧数而不是测行为。窄屏下面板由页签
  // **自己**渲染，与页签同帧出现 ⇒ 判据重新落在「深链切没切过去」上。
  group('cross_random_mating（rows 深链回填）', () {
    const narrow = Size(1100, 2400);

    testWidgets('出厂状态下 fill 真把 rows 写成群体构成并即算', (t) async {
      await _pumpPage(t, size: narrow);
      // 前提：开局停在「双基因 9331」，自由交配的输入框不在屏上。
      expect(find.widgetWithText(TextField, '基因型'), findsNothing,
          reason: '前提：开局停在 tab 0，自由交配页签还没构建');
      expect(_canOverwrite('cross_random_mating'), isTrue,
          reason: '出厂 ⇒ 放行');

      expect(
          ModuleFillBus.fill(
              'cross_random_mating', const {'rows': 'Aa=1;aa=1'}),
          isTrue,
          reason: '已注册 ⇒ fill 返 true');
      await _pumpFill(t);

      // 正向判据落在 controller 实际值上（`Aa=1;aa=1` ⇒ 两行，出厂只有一行）。
      final gens =
          t.widgetList<TextField>(find.widgetWithText(TextField, '基因型'));
      expect(gens, hasLength(2), reason: '正向：行数必须从 1 变成 2');
      expect(gens.map((w) => w.controller!.text).toList(), ['Aa', 'aa']);
      final freqs = t
          .widgetList<TextField>(find.widgetWithText(TextField, '频率 / 份数'));
      expect(freqs.map((w) => w.controller!.text).toList(), ['1', '1'],
          reason: '正向：频率也必须被写进去');
      // 「即算」判据：结果区只在算完时才有这几个小节（等待态是那句
      // 「等待计算：结果将在这里展开」）。
      expect(find.text('等待计算：结果将在这里展开'), findsNothing,
          reason: '正向：回填后应直接算出结果，而不是停在等待态');
      expect(find.text('群体配子库'), findsOneWidget,
          reason: '正向：算完才有配子库小节');
      expect(find.text(kModuleFillSkippedDirty), findsNothing,
          reason: '出厂态写入成功，不该出拒收提示');
    });

    testWidgets('学生改过自由交配的行后 fill 不覆盖 + 屏上出提示', (t) async {
      await _pumpPage(t, size: narrow);
      await _gotoTab(t, '自由交配');
      expect(_canOverwrite('cross_random_mating'), isTrue,
          reason: '开局应放行（此时的 true 只可能是「出厂」）');
      final field = find.widgetWithText(TextField, '基因型');
      expect(field, findsOneWidget, reason: '前提：出厂只有一行');
      await t.enterText(field, 'BB');
      await t.pump();
      expect(_canOverwrite('cross_random_mating'), isFalse,
          reason: '接线检查：手敲之后闸必须翻 false（⛔ 不是恒放行占位）');

      expect(
          ModuleFillBus.fill(
              'cross_random_mating', const {'rows': 'Aa=1;aa=1'}),
          isTrue,
          reason: '闸拦下也返 true（已切页，只是没写入）');
      await _pumpFill(t);

      expect(_ctrlText(t, '基因型'), 'BB',
          reason: '反向：学生敲的 BB 还在，且没多出行');
      expect(find.widgetWithText(TextField, '基因型'), findsOneWidget,
          reason: '反向：被拦下 ⇒ 没被写成两行');
      expect(find.text(kModuleFillSkippedDirty), findsOneWidget,
          reason: '闸拦下必须让用户看见「没写入」');
    });

    // 通道②（worker 遗留 #3 补常驻）：容器页 flush 时 tab 未挂载 ⇒ 参数落
    // 静态槽 pendingRm，tab 挂载时 initState 消费。一次性验证件验过本路径，
    // 这里钉成长期守卫——静态槽残留 = 幽灵数据，回归即红。
    testWidgets('通道②：pendingRm 先于 tab 挂载到达 ⇒ initState 消费并清零',
        (t) async {
      await _pumpPage(t, size: narrow);
      // 与生产线程同源分支（`_flushFill(6)` 的 currentState==null 兜底）。
      RandomMatingTabState.pendingRm = const {'rows': 'AA=1;Aa=2'};
      await _gotoTab(t, '自由交配');
      await t.pumpAndSettle();

      final rowTexts = t
          .widgetList<TextField>(find.byType(TextField))
          .map((w) => w.controller?.text ?? '')
          .toList();
      expect(rowTexts, containsAll(<String>['AA', 'Aa']),
          reason: 'initState 消费静态槽 ⇒ 两行基因型真被写成 AA / Aa');
      expect(RandomMatingTabState.pendingRm, isNull,
          reason: '消费后必须清零——残留即幽灵，回归即红');
      expect(find.text('群体配子库'), findsOneWidget,
          reason: '消费后触发即算（结果区小节出现）');
    });
  });
}
