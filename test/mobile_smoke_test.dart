// mobile_smoke_test.dart —— 2.0 批次5：安卓窄屏(390×844) 冒烟防溢出
//
// 5 个新页在手机视口（390×844, DPR 1.0）下：
//   ① pump + pumpAndSettle 后断言无异常（RenderFlex overflow / 崩溃）；
//   ② 进入默认计算流程（tap 默认操作按钮）后再断言无异常。
// 390 宽下每页 body 均为垂直 ListView；按钮若在视口外先 _reveal 再 tap。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:biology/main.dart';
import 'package:biology/pages/big_question_cards_page.dart';
import 'package:biology/pages/cross_calculator_page.dart';
import 'package:biology/pages/curriculum_page.dart';
import 'package:biology/pages/dashboard_page.dart';
import 'package:biology/pages/evolution_page.dart';
import 'package:biology/pages/genetic_disease_page.dart';
import 'package:biology/pages/genetic_pedigree_page.dart';
import 'package:biology/pages/home_page.dart';
import 'package:biology/pages/knowledge_graph_page.dart';
import 'package:biology/pages/molecular_page.dart';
import 'package:biology/pages/ploidy_page.dart';
import 'package:biology/pages/settings_page.dart';
import 'package:biology/pages/variation_page.dart';
import 'package:biology/pages/widgets/pedigree_canvas.dart';
import 'package:biology/state/first_run_store.dart';
import 'package:biology/state/theme_controller.dart';
import 'package:biology/theme.dart';

/// ListView 惰性构建：先滚到树中，再 ensureVisible 拉进视口（缓存区
/// 内的元素树中存在但不可点）。返回后目标保证 hit-testable。
Future<void> _reveal(WidgetTester tester, Finder finder) async {
  for (var i = 0; i < 14 && finder.evaluate().isEmpty; i++) {
    await tester.drag(find.byType(ListView).first, const Offset(0, -160));
    await tester.pumpAndSettle();
  }
  if (finder.evaluate().isNotEmpty) {
    await tester.ensureVisible(finder.first);
    await tester.pumpAndSettle();
  }
  expect(finder, findsWidgets, reason: '滚动后目标应可见');
}

/// 固定手机视口，test 结束后复位（不污染后续用例）。
void _phoneViewport(WidgetTester tester) {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  testWidgets('CurriculumPage 窄屏：首帧无溢出，切概念无溢出（v2.19.28 工作台）',
      (tester) async {
    _phoneViewport(tester);
    await tester.pumpWidget(const MaterialApp(home: CurriculumPage()));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull, reason: '首帧无 RenderFlex overflow');

    // v2.19.28：左树导航窄态 = 顶部横滚 pill（原「概念4 展开」链路
    // 随 StepCard 堆叠移除而废止）；v2.19.29 起 pill 渲染短标签——
    // 切到 3.2 概念验证右区渲染无溢出。
    await _reveal(tester, find.text('3.2 分离重组'));
    await tester.tap(find.text('3.2 分离重组'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull, reason: '切概念后无溢出');
  });

  testWidgets('MolecularPage 窄屏：首帧无溢出，全部计算无崩溃', (tester) async {
    _phoneViewport(tester);
    await tester.pumpWidget(const MaterialApp(home: MolecularPage()));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull,
        reason: '首帧无 RenderFlex overflow（AppBar 含「全部计算」action）');

    await _reveal(tester, find.text('全部计算'));
    await tester.tap(find.text('全部计算'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull, reason: '全部计算后无崩溃/溢出');
  });

  testWidgets('EvolutionPage 窄屏：首帧无溢出，全部计算无崩溃', (tester) async {
    _phoneViewport(tester);
    await tester.pumpWidget(const MaterialApp(home: EvolutionPage()));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull,
        reason: '首帧无 RenderFlex overflow（AppBar 含「全部计算」action）');

    await _reveal(tester, find.text('全部计算'));
    await tester.tap(find.text('全部计算'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull, reason: '全部计算后无崩溃/溢出');
  });

  testWidgets('VariationPage 窄屏：首帧无溢出，模拟突变无崩溃', (tester) async {
    _phoneViewport(tester);
    await tester.pumpWidget(const MaterialApp(home: VariationPage()));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull, reason: '首帧无 RenderFlex overflow');

    await _reveal(tester, find.text('模拟突变'));
    await tester.tap(find.text('模拟突变'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull, reason: '模拟突变后无崩溃/溢出');
  });

  testWidgets('GeneticDiseasePage 窄屏：首帧无溢出，计算无崩溃', (tester) async {
    _phoneViewport(tester);
    await tester.pumpWidget(const MaterialApp(home: GeneticDiseasePage()));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull, reason: '首帧无 RenderFlex overflow');

    await _reveal(tester, find.text('计算'));
    await tester.tap(find.text('计算'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull, reason: '计算后无崩溃/溢出');
  });

  // 2.2 批次2：真题页/系谱演练页已随刷题模块移除，原「2.1 补」用例删除。

  // ── v2.19.26 手机 9:16 竖屏全页巡检 ──
  //
  // 方向策略：手机锁竖屏（main.dart _applyOrientationPolicy），390×844
  // 即设计基准视口。这里把主导航 11 页在真机视口全部泵一遍收溢出；
  // 重页（系谱画布/9331）用定长 pump（防常驻动画卡 pumpAndSettle）。
  // 图谱/课标有 rootBundle 真实异步 I/O，runAsync 放行数据就绪。

  Future<void> _pumpPhone(WidgetTester tester, Widget page) async {
    _phoneViewport(tester);
    await tester.pumpWidget(MaterialApp(home: page));
    await tester.pump();
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 400));
    });
    await tester.pump();
    expect(tester.takeException(), isNull, reason: '390×844 首帧无溢出');
  }

  testWidgets('DashboardPage 手机竖屏无溢出', (tester) async {
    await _pumpPhone(tester, DashboardPage(onOpenTool: (_) {}));
  });

  testWidgets('GeneticPedigreePage 手机竖屏无溢出', (tester) async {
    await _pumpPhone(
        tester,
        GeneticPedigreePage(
            navCollapsed: false, onNavPressed: () {}));
  });

  testWidgets('CrossCalculatorPage 手机竖屏无溢出', (tester) async {
    await _pumpPhone(
        tester,
        CrossCalculatorPage(
            navCollapsed: false, onNavPressed: () {}));
  });

  testWidgets('KnowledgeGraphPage 手机竖屏无溢出', (tester) async {
    await _pumpPhone(
        tester,
        KnowledgeGraphPage(
            navCollapsed: false,
            onNavPressed: () {},
            onOpenTool: (_) {}));
  });

  testWidgets('PloidyPage 手机竖屏无溢出', (tester) async {
    await _pumpPhone(tester, const PloidyPage());
  });

  testWidgets('BigQuestionCardsPage 手机竖屏无溢出', (tester) async {
    await _pumpPhone(tester, const BigQuestionCardsPage());
  });

  testWidgets('SettingsPage 手机竖屏无溢出', (tester) async {
    await _pumpPhone(
        tester, SettingsPage(navCollapsed: false, onNavPressed: () {}));
  });

  testWidgets('HomePage(关于) 手机竖屏无溢出', (tester) async {
    await _pumpPhone(
        tester, HomePage(navCollapsed: false, onNavPressed: () {}));
  });

  // 手机壳整体验：BiologyApp @ 390×844 —— 11 项底导可点、切页无溢出。
  testWidgets('手机壳 390×844：底导切页无溢出', (tester) async {
    _phoneViewport(tester);
    await tester.runAsync(() => ThemeController.instance.debugEnsureLoaded());
    await FirstRunStore.instance.setRole(UserRole.student);
    addTearDown(FirstRunStore.instance.debugReset);

    await tester.pumpWidget(const BiologyApp());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    expect(tester.takeException(), isNull, reason: '手机壳首帧无溢出');

    // 底导点「课标」（11 项横滑可达，先滚进视口）。
    final target = find.text('课标');
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await tester.pump();
    await tester.ensureVisible(target.last);
    await tester.pump();
    await tester.tap(target.last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(tester.takeException(), isNull, reason: '底导切课后无溢出');
    final stack = tester.widget<IndexedStack>(find.byType(IndexedStack));
    expect(stack.index, 4, reason: '课标 = 主导航 index 4');
  });

  // ── v2.19.26 平板 3:4 双视口巡检（调研落地：横屏默认 / 竖屏亦可）──

  Map<String, Widget> _navPages() => {
        '00_首页': DashboardPage(onOpenTool: (_) {}),
        '01_遗传图谱':
            GeneticPedigreePage(navCollapsed: false, onNavPressed: () {}),
        '02_9331':
            CrossCalculatorPage(navCollapsed: false, onNavPressed: () {}),
        '03_图谱': KnowledgeGraphPage(
            navCollapsed: false, onNavPressed: () {}, onOpenTool: (_) {}),
        '04_课标': const CurriculumPage(),
        '05_分子': const MolecularPage(),
        '06_进化': const EvolutionPage(),
        '07_倍性': const PloidyPage(),
        '08_套路卡': const BigQuestionCardsPage(),
        // v2.19.60 导航重排：变异/遗传病提前到 9/10，设置/关于落到 11/12。
        '09_变异': VariationPage(onNavPressed: () {}),
        '10_遗传病': GeneticDiseasePage(onNavPressed: () {}),
        '11_设置': SettingsPage(navCollapsed: false, onNavPressed: () {}),
        '12_关于': HomePage(navCollapsed: false, onNavPressed: () {}),
      };

  Future<void> _sweepViewport(
      WidgetTester tester, Size size, String tag) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    for (final entry in _navPages().entries) {
      await tester.pumpWidget(MaterialApp(home: entry.value));
      await tester.pump();
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 400));
      });
      await tester.pump();
      expect(tester.takeException(), isNull,
          reason: '$tag ${entry.key} 首帧无溢出');
    }
  }

  testWidgets('平板 3:4 竖屏 800×1280：全页零溢出', (tester) async {
    await _sweepViewport(tester, const Size(800, 1280), '平板竖屏');
  });

  testWidgets('平板 3:4 横屏 1280×800：全页零溢出', (tester) async {
    await _sweepViewport(tester, const Size(1280, 800), '平板横屏');
  });

  // 平板壳整体验：1280 宽命中 NavigationRail（v2.19.26 阈值 600）。
  testWidgets('平板壳 1280×800：Rail 导航出现且无溢出', (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.runAsync(() => ThemeController.instance.debugEnsureLoaded());
    await FirstRunStore.instance.setRole(UserRole.student);
    addTearDown(FirstRunStore.instance.debugReset);

    await tester.pumpWidget(const BiologyApp());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.byType(NavigationRail), findsOneWidget,
        reason: '1280 宽 ≥ 600 阈值应出现 Rail（平板横屏默认形态）');
    expect(tester.takeException(), isNull, reason: '平板壳首帧无溢出');
  });

  // ── v2.19.27 体验官定谳用例 ──
  //
  // 手机 P2-3/P3-4：画布缩放条（估算 384 > 380）与 9331 结果区工具行
  // 只在「计算后」渲染——首帧巡检从未覆盖。这里在 390×844 真机视口
  // 走完「切页 → 计算」全链路收溢出（体验官报告点名的测试盲区）。

  Future<void> _pumpPhoneShell(WidgetTester tester) async {
    _phoneViewport(tester);
    await tester.runAsync(() => ThemeController.instance.debugEnsureLoaded());
    await FirstRunStore.instance.setRole(UserRole.student);
    addTearDown(FirstRunStore.instance.debugReset);
    await tester.pumpWidget(const BiologyApp());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
  }

  /// 底导横滑后点目标项（11 项横滚，先 ensureVisible）。
  Future<void> _tapBottomNav(WidgetTester tester, String label) async {
    final f = find.text(label).last;
    await tester.ensureVisible(f);
    await tester.pump();
    await tester.tap(f);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  testWidgets('手机壳 390：系谱页计算后画布（缩放条/提示）无溢出 [P2-3 定谳]',
      (tester) async {
    await _pumpPhoneShell(tester);
    await _tapBottomNav(tester, '遗传图谱');
    expect(tester.takeException(), isNull, reason: '切系谱页无溢出');

    // 默认双亲已预填（AaBb 预设），点计算生成画布。
    await tester.tap(find.text('计算').first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.byType(PedigreeCanvas), findsOneWidget,
        reason: '计算后画布应挂载');
    expect(tester.takeException(), isNull,
        reason: '390 宽已计算画布（缩放条/详情条/提示胶囊）零溢出');
  });

  testWidgets('手机壳 390：9331 计算后结果区工具行无溢出 [P3-4 定谳]',
      (tester) async {
    await _pumpPhoneShell(tester);
    await _tapBottomNav(tester, '9331');
    expect(tester.takeException(), isNull, reason: '切 9331 页无溢出');

    // 双基因 tab 默认 AaBb×AaBb 预设，点「计算比例」出结果区。
    final calc = find.text('计算比例').first;
    await tester.ensureVisible(calc);
    await tester.pump();
    await tester.tap(calc);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    expect(tester.takeException(), isNull,
        reason: '390 宽计算后结果区（数值/板书工具行）零溢出');
  });

  // 平板 F-8：课堂 ×1.3 双形态巡检（原课堂扫描只有 1400×900 单尺寸，
  // 且不含课堂主题触控放大）。
  testWidgets('平板课堂 ×1.3 双形态（800×1280 / 1280×800）全页零溢出',
      (tester) async {
    final errors = <FlutterErrorDetails>[];
    final prev = FlutterError.onError;
    FlutterError.onError = (d) {
      if (d.exceptionAsString().contains('overflowed')) {
        errors.add(d);
      } else {
        prev?.call(d);
      }
    };
    addTearDown(() => FlutterError.onError = prev);

    for (final size in const [Size(800, 1280), Size(1280, 800)]) {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      for (final entry in _navPages().entries) {
        await tester.pumpWidget(MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(1.3)),
          child: MaterialApp(theme: AppTheme.light(), home: entry.value),
        ));
        await tester.pump();
        await tester.runAsync(() async {
          await Future<void>.delayed(const Duration(milliseconds: 400));
        });
        await tester.pump();
        expect(tester.takeException(), isNull,
            reason: '课堂×1.3 ${size.width > size.height ? "横" : "竖"} ${entry.key} 无溢出');
      }
    }
    FlutterError.onError = prev;
    expect(errors, isEmpty,
        reason: '平板课堂双形态零溢出：\n'
            '${errors.map((e) => e.exceptionAsString()).join('\n')}');
  });
}
