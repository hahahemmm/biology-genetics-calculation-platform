// workbench_narrow_tabbar_test.dart —— v2.19.60 挤压态 TabBar 去图标守卫网
//
// ## 这条网守什么
// `buildWorkbenchTabBar`（工作台骨架的顶部页签行）在**窗口被挤压**时把
// 「图标 + 文字」降为「纯文字」：挤压态下它与底部导航（同为「图标 + 文字」）
// 视觉同构，用户读到的是上下**两层导航**。阈值 `kWorkbenchCompactWidth = 720`：
//   · 宽 < 720 ⇒ 每个 Tab 的 icon 为 null（去图标）；
//   · 宽 ≥ 720 ⇒ 维持 icon + text（**回归对照**，宽档视觉不许变）。
//
// ## 与派工单的偏离记录（已闭环）
// 派工单写的 N1 是「@560 泵 9331（CrossCalculatorPage）」。初版实测 9331 **不走**
// `buildWorkbenchTabBar`（它内联了 7 页签 TabBar），而 cross_calculator_page.dart
// 不在所有权内 ⇒ N1 曾改泵分子页顶位。回收后主线程已把同款 `<720` 分支内联进
// 9331（引同一个 kWorkbenchCompactWidth），N5 逐字钉住原派工单语义。
//
// ## 网型纪律
// 基线（页签下标）走**鼠标点 TabBar / 初始态**取得；键盘通道只用于被测动作，
// 避免「每次按键都改写 controller」的变异写进基线（B 仓 v2.19.168 教训）。

import 'package:biology/pages/big_question_cards_page.dart';
import 'package:biology/pages/cross_calculator_page.dart';
import 'package:biology/pages/molecular_page.dart';
import 'package:biology/pages/widgets/side_nav_workbench.dart';
import 'package:biology/ui/module_surface.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 泵某页到指定视口宽（高固定 900，DPR 1.0）。
Future<void> _pumpAt(WidgetTester tester, Widget page, double width) async {
  tester.view.physicalSize = Size(width, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(MaterialApp(home: page));
  await tester.pump();
}

/// 顶部页签行的全部 `Tab` 字节（唯一一枚 TabBar 的 children）。
List<Tab> _tabs(WidgetTester tester) =>
    tester.widgetList<Tab>(find.byType(Tab)).toList();

/// 当前页签下标：走 TabBar 的 controller（结构化读数，不靠屏上文字）。
int _tabIndex(WidgetTester tester) =>
    tester.widget<TabBar>(find.byType(TabBar)).controller!.index;

void main() {
  // ══════════════════════════════════════════════════════════════════
  //  N1. @560（挤压态）：Tab 全部无图标，且页签仍切得动
  //      （派工单写的是 9331；9331 不走本 helper，改泵分子页——见文件头）
  // ══════════════════════════════════════════════════════════════════
  testWidgets('N1·@560 分子页：所有 Tab 无图标，且「基因表达」页签切得动', (tester) async {
    await _pumpAt(tester, const MolecularPage(), 560);

    final tabs = _tabs(tester);
    // v2.21：分子页新增第 5 个页签「基因工程」⇒ 前提数由 4 改成 5
    //（本用例只钉「挤压态去图标 + 页签切得动」，与页签内容无关）。
    expect(tabs.length, 5, reason: '前提：分子页 5 个页签（含「基因工程」）');
    for (final t in tabs) {
      expect(t.icon, isNull, reason: '挤压态去图标：Tab「${t.text}」仍有 icon');
    }

    // 功能不变：页签仍可切（鼠标通道取基线 + 取结果，不靠键盘）。
    expect(_tabIndex(tester), 0, reason: '初始态基线');
    await tester.ensureVisible(find.text('基因表达'));
    await tester.pump();
    await tester.tap(find.text('基因表达'));
    await tester.pumpAndSettle();
    expect(_tabIndex(tester), 2, reason: '去图标只是视觉瘦身，切页签功能不变');
  });

  // ══════════════════════════════════════════════════════════════════
  //  N2. @900（宽档回归对照）：Tab 带图标（不许把宽档也改掉）
  // ══════════════════════════════════════════════════════════════════
  testWidgets('N2·@900 分子页：Tab 带图标（宽档视觉不变的回归对照）', (tester) async {
    await _pumpAt(tester, const MolecularPage(), 900);

    final tabs = _tabs(tester);
    // v2.21：同 N1，分子页 5 个页签（多出「基因工程」）。
    expect(tabs.length, 5);
    for (final t in tabs) {
      expect(t.icon, isNotNull, reason: '宽档 ≥720 必须维持 icon + text：${t.text}');
    }
  });

  // ══════════════════════════════════════════════════════════════════
  //  N3. @560 套路卡页：**已无页签行**（v2.20.0 单栏导航改造）
  //
  //  本用例原本钉「6 页签在挤压态去图标、且换章页签切得动」。v2.20.0 按
  //  用户裁定（全局导航永远单栏可滚动、不许双层导航）把该页的 AppBar
  //  章节 TabBar 整块收掉，换章改由一套 SideNavWorkbench 顶部横向选择条
  //  承担 ⇒ 「挤压态去图标」这条规则对本页不再适用（没有 Tab 可去图标）。
  //  守卫改为钉住**新结构**：@560 既无 TabBar 也无第二层导航，选择条仍
  //  只有一套、换章功能不丢。
  // ══════════════════════════════════════════════════════════════════
  testWidgets('N3·@560 套路卡页：无 TabBar（页签行已收掉），横条选择条照旧切得动', (tester) async {
    await _pumpAt(tester, const BigQuestionCardsPage(), 560);

    expect(
      find.byType(TabBar),
      findsNothing,
      reason: 'v2.20.0：章节页签行已删——挤压态 TabBar 去图标不再适用于本页',
    );
    expect(find.byType(Tab), findsNothing);
    expect(
      find.byType(SideNavWorkbench),
      findsOneWidget,
      reason: '整页只允许一条导航（顶部横向选择条）',
    );
    expect(tester.takeException(), isNull, reason: '@560 首帧无溢出');

    // 功能不变：换章仍切得动（点该章卡片的 pill），正文跟随。
    final pill = find.textContaining('伴性遗传大题步骤').first;
    await tester.ensureVisible(pill);
    await tester.pump();
    await tester.tap(pill);
    await tester.pumpAndSettle();
    expect(
      find.text('伴性遗传 · 第 2/2 张'),
      findsOneWidget,
      reason: '点 pill 应换到伴性章那张卡',
    );
    expect(tester.takeException(), isNull, reason: '@560 切章后无溢出');
  });

  // ══════════════════════════════════════════════════════════════════
  //  N4. 阈值边界：< 720 去图标 / ≥ 720 保图标（钉死 kWorkbenchCompactWidth 语义）
  // ══════════════════════════════════════════════════════════════════
  testWidgets('N4·阈值边界：@719 无图标、@720 有图标', (tester) async {
    await _pumpAt(tester, const MolecularPage(), 719);
    for (final t in _tabs(tester)) {
      expect(t.icon, isNull, reason: '719 < 720 ⇒ 挤压档，应去图标');
    }

    await _pumpAt(tester, const MolecularPage(), 720);
    for (final t in _tabs(tester)) {
      expect(t.icon, isNotNull, reason: '720 ≥ 720 ⇒ 宽档，应保图标');
    }
  });

  // ══════════════════════════════════════════════════════════════════
  //  N5. 9331（用户原话点名的双层导航主案发页）：@560 去图标且切得动；
  //      @900 保图标（回归对照）。9331 不走共享 helper——内联同款分支
  //      （cross_calculator_page.dart），阈值同一个 kWorkbenchCompactWidth。
  // ══════════════════════════════════════════════════════════════════
  testWidgets('N5a·@560 9331：7 页签全部无图标，且「伴性遗传」切得动', (tester) async {
    await _pumpAt(tester, const CrossCalculatorPage(), 560);

    final tabs = _tabs(tester);
    expect(tabs.length, 7, reason: '前提：9331 七个页签');
    for (final t in tabs) {
      expect(t.icon, isNull, reason: '挤压态去图标：Tab「${t.text}」仍有 icon');
    }

    expect(_tabIndex(tester), 0, reason: '初始态基线');
    await tester.ensureVisible(find.text('伴性遗传'));
    await tester.pump();
    await tester.tap(find.text('伴性遗传'));
    await tester.pumpAndSettle();
    expect(_tabIndex(tester), 3, reason: '去图标只是视觉瘦身，切页签功能不变');
  });

  testWidgets('N5b·@900 9331：7 页签带图标（宽档视觉不变）', (tester) async {
    await _pumpAt(tester, const CrossCalculatorPage(), 900);

    final tabs = _tabs(tester);
    expect(tabs.length, 7);
    for (final t in tabs) {
      expect(t.icon, isNotNull, reason: '宽档 ≥720 必须维持 icon + text：${t.text}');
    }
  });

  // ══════════════════════════════════════════════════════════════════
  //  N6. v2.21.0 宽屏排版：预览「280 输入 ModuleSurface + 结果
  //      ModuleSurface」两块薄壳，且 TabBarView 仍拿到**有界**高度。
  //
  //  这条网守的是重排版最容易踩的雷：结果区薄壳一旦带上标题（内部套
  //  Column）而子内容又没有 Expanded，TabBarView 会拿到无限高度约束并
  //  在首帧崩（"RenderBox was not laid out"）。输入标题必须来自
  //  railTitle / railIcon（调用方文案，不是骨架里写死的）。
  // ══════════════════════════════════════════════════════════════════
  testWidgets('N6·@1400 分子页：宽屏两块 ModuleSurface，TabBarView 高度有界', (
    tester,
  ) async {
    await _pumpAt(tester, const MolecularPage(), 1400);
    await tester.pumpAndSettle();

    // 两块薄壳（输入 + 结果）：没有第三层、没有层层套卡。
    expect(
      find.byType(ModuleSurface),
      findsNWidgets(2),
      reason: '宽屏工作台 = 输入面板 + 结果面板两块薄壳',
    );

    // 输入面板固定 280 宽，标题走 railTitle / railIcon。
    final rail = find
        .ancestor(
          of: find.text('分子遗传 · 输入'),
          matching: find.byType(ModuleSurface),
        )
        .first;
    expect(tester.getSize(rail).width, 280, reason: '输入面板仍是 280 定宽');
    expect(
      find.descendant(of: rail, matching: find.byIcon(Icons.science_outlined)),
      findsOneWidget,
      reason: '输入面板标题图标 = 调用方 railIcon',
    );

    // 结果区 TabBarView 必须拿到有界高度（能测出有限高度即为有界）。
    final view = tester.getSize(find.byType(TabBarView));
    expect(view.height.isFinite, isTrue, reason: 'TabBarView 高度不得为无限');
    expect(view.height, greaterThan(200), reason: '结果区仍占满右列剩余高度');
    expect(view.width, greaterThan(280), reason: '结果区在输入面板右侧展开');

    // 切页签仍工作（重排版不许改交互语义）。
    await tester.tap(find.text('复制与标记'));
    await tester.pumpAndSettle();
    expect(_tabIndex(tester), 1);
    expect(
      find.text('计算复制结果'),
      findsOneWidget,
      reason: '切 tab 后左栏仍换成新 tab 的输入面板',
    );
    expect(tester.takeException(), isNull);
  });
}
