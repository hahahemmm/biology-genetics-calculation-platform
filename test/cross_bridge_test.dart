// cross_bridge_test.dart —— v2.19.15 A 桥（双向「送入」）+ C 回程横幅测试
//
// 覆盖：
//   1. A 桥正向：系谱内嵌杂交面板算完 →「在 9331 完整展开」按钮出现，
//      点击经 ModuleFillBus.fill('cross_dihybrid') 切到 pageIndex=2；
//   2. A 桥反向：9331 双基因结果区 →「在系谱画布展开」按钮出现，
//      点击经 ModuleFillBus.fill('pedigree') 切到 pageIndex=1；
//   3. C 回程横幅：fill 走 navigator 时来源页可被 HomeShell 记录
//      （本层验证 navigator 以目标页码被调；横幅本身由 HomeShell
//      _selectWithReturn 渲染，main_test 层覆盖）。
//
// 设计说明：两侧按钮都不直接 import 对方页面——只经 ModuleFillBus
// 总线（与讲题回放 ▷ / 拍题识别同一事实源），所以本测试手动注册
// 对端 target 模拟「对端页面已挂载」的真实运行态。

import 'dart:io';

import 'package:biology/pages/cross_calculator_page.dart';
import 'package:biology/pages/genetic_pedigree_page.dart';
import 'package:biology/pages/widgets/pedigree_canvas.dart';
import 'package:biology/state/app_state.dart';
import 'package:biology/ui/module_fill.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

late Directory _isolatedDir;
String _isolatedPath() => '${_isolatedDir.path}/cross_panel.json';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    GeneticPedigreePage.debugResetHooks();
    _isolatedDir = Directory.systemTemp.createTempSync('cross_bridge_test_');
    GeneticPedigreePage.debugFilePath = _isolatedPath();
    ModuleFillBus.resetForTest();
    // AppState 是全局单例：不清 context 的话上一个用例上报的
    // 「双亲基因型 / 参考表型比例」会串到下一个用例的 snapshot 断言里。
    AppState.instance.clearContext();
  });

  tearDown(() {
    GeneticPedigreePage.debugFilePath = null;
    GeneticPedigreePage.debugResetHooks();
    ModuleFillBus.resetForTest();
    AppState.instance.clearContext();
    if (_isolatedDir.existsSync()) {
      _isolatedDir.deleteSync(recursive: true);
    }
  });

  group('A 桥正向：系谱内嵌面板 → 9331 完整展开', () {
    testWidgets('算完后按钮出现，点击 fill cross_dihybrid 并切到 pageIndex=2',
        (tester) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      // 对端 target：模拟 9331 页已挂载（真实运行态它 initState 自注册）。
      ModuleFillBus.register(ModuleFillTarget(
        moduleId: 'cross_dihybrid',
        pageIndex: 2,
        label: '遗传计算器·双基因',
        apply: (_) => true,
      ));
      final navigations = <int>[];
      ModuleFillBus.navigator = navigations.add;

      await tester.pumpWidget(const MaterialApp(home: GeneticPedigreePage()));
      await tester.pumpAndSettle();

      // 打开内嵌杂交面板并计算（亲本 1/2 标签在多计算器面板中各出现
      // 多次——first = 9331 块）。
      await tester.tap(find.text('杂交计算'));
      await tester.pumpAndSettle();
      await tester.enterText(
          find.widgetWithText(TextField, '亲本 1').first, 'AaBb');
      await tester.enterText(
          find.widgetWithText(TextField, '亲本 2').first, 'AaBb');
      await tester.tap(find.text('开始计算'));
      await tester.pumpAndSettle();
      expect(find.text('9:3:3:1'), findsOneWidget);

      // 按钮出现且点击后触发 fill。
      final btn = find.text('在 9331 完整展开');
      expect(btn, findsOneWidget);
      // 诊断：先直接调 fill 验证 navigator 链路通。
      expect(ModuleFillBus.targetOf('cross_dihybrid'), isNotNull,
          reason: 'cross_dihybrid target 应已注册');
      ModuleFillBus.fill('cross_dihybrid', {'p1': 'AaBb', 'p2': 'AaBb'});
      expect(navigations, [2], reason: '直接 fill 应立即同步调 navigator');
      navigations.clear();
      // 按钮在结果区末尾（SingleChildScrollView 内）——先滚到可见再点。
      await tester.scrollUntilVisible(btn, 100,
          scrollable: find.byType(Scrollable).last);
      await tester.pumpAndSettle();
      await tester.tap(btn, warnIfMissed: true);
      await tester.pumpAndSettle();
      expect(navigations, [2], reason: '点按钮应切到主导航第 2 页（9331）');
    });

    testWidgets('未算完（结果为空）不显示按钮', (tester) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(const MaterialApp(home: GeneticPedigreePage()));
      await tester.pumpAndSettle();
      await tester.tap(find.text('杂交计算'));
      await tester.pumpAndSettle();

      expect(find.text('尚未计算'), findsOneWidget);
      expect(find.text('在 9331 完整展开'), findsNothing);
    });
  });

  group('A 桥反向：9331 双基因 → 系谱画布展开', () {
    testWidgets('算完后按钮出现，点击 fill pedigree 并切到 pageIndex=1',
        (tester) async {
      tester.view.physicalSize = const Size(1400, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      // 对端 target：模拟系谱页已挂载。
      ModuleFillBus.register(ModuleFillTarget(
        moduleId: 'pedigree',
        pageIndex: 1,
        label: '遗传图谱',
        apply: (_) => true,
      ));
      final navigations = <int>[];
      ModuleFillBus.navigator = navigations.add;

      await tester
          .pumpWidget(const MaterialApp(home: CrossCalculatorPage()));
      await tester.pumpAndSettle();

      // 双基因 tab 默认即第 0 页；填亲本并计算。
      final p1 = find.widgetWithText(TextField, '亲本 1');
      final p2 = find.widgetWithText(TextField, '亲本 2');
      expect(p1, findsOneWidget);
      await tester.enterText(p1, 'AaBb');
      await tester.enterText(p2, 'AaBb');
      // 结果区懒计算——触发「计算比例」。
      final calcBtn = find.text('计算比例');
      expect(calcBtn, findsOneWidget);
      await tester.tap(calcBtn);
      await tester.pumpAndSettle();

      // 按钮出现且点击后触发 fill。
      final btn = find.text('在系谱画布展开');
      expect(btn, findsOneWidget);
      await tester.tap(btn);
      await tester.pumpAndSettle();
      expect(navigations, [1], reason: '应切到主导航第 1 页（系谱）——'
          '专用目标未注册时回退到老的 pedigree 目标');
    });

    testWidgets('专用目标存在时：携带 p1/p2 + ratio + 来源标签', (tester) async {
      tester.view.physicalSize = const Size(1400, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final captured = <Map<String, String>>[];
      ModuleFillBus.register(ModuleFillTarget(
        moduleId: 'pedigree_from_cross',
        pageIndex: 1,
        label: '遗传图谱',
        apply: (p) {
          captured.add(p);
          return true;
        },
      ));
      final navigations = <int>[];
      ModuleFillBus.navigator = navigations.add;

      await tester
          .pumpWidget(const MaterialApp(home: CrossCalculatorPage()));
      await tester.pumpAndSettle();
      await tester.enterText(find.widgetWithText(TextField, '亲本 1'), 'AaBb');
      await tester.enterText(find.widgetWithText(TextField, '亲本 2'), 'AaBb');
      await tester.tap(find.text('计算比例'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('在系谱画布展开'));
      await tester.pumpAndSettle();
      expect(navigations, [1], reason: '专用目标优先，切到系谱页');
      expect(captured, hasLength(1), reason: '切页后由目标页消费参数');
      expect(captured.single['p1'], 'AaBb');
      expect(captured.single['p2'], 'AaBb');
      expect(captured.single['ratio'], '9:3:3:1',
          reason: '表型比随参数一起带走');
      expect(captured.single['sourceLabel'], '9331 杂交计算',
          reason: '来源标签随参数一起带走（页面横幅与上报用）');
    });
  });

  // ── v3.6：9331 → 系谱的两种落点（空态填入 / 已有则追加家族）────
  group('9331 → 系谱：p1/p2 + 参考比例的实际消费', () {
    Future<void> pumpPedigree(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      ModuleFillBus.navigator = (_) {};
      await tester.pumpWidget(const MaterialApp(home: GeneticPedigreePage()));
      await tester.pumpAndSettle();
    }

    Map<String, String> params({String p1 = 'AaBb', String p2 = 'AaBb'}) =>
        <String, String>{
          'p1': p1,
          'p2': p2,
          'ratio': '9:3:3:1',
          'sourceLabel': '9331 杂交计算',
        };

    testWidgets('出厂空态：填入 p1/p2 并计算，参考比例明确标注', (tester) async {
      await pumpPedigree(tester);
      expect(ModuleFillBus.targetOf('pedigree_from_cross'), isNotNull,
          reason: '系谱页注册了专用填参目标');

      ModuleFillBus.fill('pedigree_from_cross', params());
      await tester.pumpAndSettle();

      // 已按 p1/p2 计算（画布出现 + P 代双亲基因型一致）。
      final canvas = tester.widget<PedigreeCanvas>(find.byType(PedigreeCanvas));
      final parents = canvas.nodes.where((n) => n.generation == 0).toList();
      expect(parents.map((n) => n.genotype).toSet(), {'AaBb'},
          reason: '双亲都换成 9331 带来的 AaBb');
      // 参考比例条：写清「参考值，非引擎推算」。
      expect(find.textContaining('参考表型比例 9:3:3:1'), findsOneWidget);
      // 横幅 + toast 都会写明「非引擎推算」。
      expect(find.textContaining('非引擎推算'), findsWidgets);
      // v2.22.0+1：空态内部走的是 _derive（它算成功会清参考字段）——
      // 桥接必须在之后重新设置并上报，比例才能带亲本进 AppState。
      final snap = AppState.instance.buildSnapshot();
      expect(snap, contains('参考表型比例'),
          reason: '空态桥接算完后仍要上报参考比例');
      expect(snap, contains('AaBb × AaBb'),
          reason: '上报的比例必须绑定本次杂交亲本（不能是裸比例）');
    });

    testWidgets('已有学生系谱：追加新家族，不覆盖原图', (tester) async {
      await pumpPedigree(tester);
      // 学生先自己算一张（出厂双亲 AABBCC × aabbcc）。
      await tester.tap(find.text('计算').first);
      await tester.pumpAndSettle();
      var canvas = tester.widget<PedigreeCanvas>(find.byType(PedigreeCanvas));
      final beforeNodes = canvas.nodes.length;
      final beforeGen0 = canvas.nodes.where((n) => n.generation == 0).length;
      expect(beforeGen0, 2, reason: '原图只有一对双亲');

      ModuleFillBus.fill('pedigree_from_cross', params(p1: 'AAbb', p2: 'aaBB'));
      await tester.pumpAndSettle();

      canvas = tester.widget<PedigreeCanvas>(find.byType(PedigreeCanvas));
      final gen0 = canvas.nodes.where((n) => n.generation == 0).toList();
      expect(gen0.length, 4, reason: '新家族追加一对双亲（原双亲保留）');
      expect(gen0.map((n) => n.genotype),
          containsAll(<String>['AABBCC', 'aabbcc', 'AAbb', 'aaBB']),
          reason: '原图双亲不被覆盖');
      expect(canvas.nodes.length, greaterThan(beforeNodes),
          reason: '只增不减：原系谱的节点还在');
      expect(find.textContaining('参考表型比例 9:3:3:1'), findsOneWidget);
    });
  });

  // ── v2.22.0+1 交付前复核：参考比例的**归属**与**失效** ────────────
  //
  // MEDIUM：追加家族后 AppState 的「参考表型比例」不带亲本，而「双亲基因型」
  //   仍按旧主输入上报 ⇒ AI 会把参考比例错挂到旧亲本上。
  // LOW：手动重算（主输入换了）后，旧参考比例仍挂在横幅与 AppState 里。
  group('v2.22.0+1 参考比例：AppState 绑定本次杂交 + 手动重算即失效', () {
    const crossP1 = 'AAbb';
    const crossP2 = 'aaBB';

    Future<void> pumpPedigree(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      ModuleFillBus.navigator = (_) {};
      await tester.pumpWidget(const MaterialApp(home: GeneticPedigreePage()));
      await tester.pumpAndSettle();
    }

    Map<String, String> crossParams() => <String, String>{
          'p1': crossP1,
          'p2': crossP2,
          'ratio': '9:3:3:1',
          'sourceLabel': '9331 杂交计算',
        };

    /// 主输入框（左栏「亲本」）：按当前文本定位，不依赖控件顺序。
    Finder parentField(String text) => find.byWidgetPredicate(
        (w) => w is TextField && w.controller?.text == text);

    String lineOf(String snapshot, String key) => snapshot
        .split('\n')
        .firstWhere((l) => l.startsWith('$key：'), orElse: () => '');

    testWidgets('先算旧系谱再追加 AAbb × aaBB：比例明确绑定 AAbb × aaBB',
        (tester) async {
      await pumpPedigree(tester);
      // 学生先算一张出厂系谱（AABBCC × aabbcc）。
      await tester.tap(find.text('计算').first);
      await tester.pumpAndSettle();

      ModuleFillBus.fill('pedigree_from_cross', crossParams());
      await tester.pumpAndSettle();

      final snap = AppState.instance.buildSnapshot();
      final refLine = lineOf(snap, '参考表型比例');
      expect(refLine, isNotEmpty, reason: '追加家族后必须有参考比例上报');
      expect(refLine, contains('9:3:3:1'));
      expect(refLine, contains('$crossP1 × $crossP2'),
          reason: 'MEDIUM：比例必须写明它属于本次 AAbb × aaBB，'
              '否则 AI 会挂到下面的旧主输入上');
      expect(refLine, contains('9331 杂交计算'), reason: '来源照旧带上');
      expect(refLine, contains('参考值'));
      expect(refLine, contains('非引擎推算'));

      // 旧主输入照旧上报（公开契约不变）：两行并列，AI 可分得清。
      final mainLine = lineOf(snap, '双亲基因型');
      expect(mainLine, contains('AABBCC'));
      expect(mainLine, contains('aabbcc'));
      expect(find.textContaining('参考表型比例 9:3:3:1'), findsOneWidget,
          reason: '横幅仍显示（视图语义未扩大）');
    });

    testWidgets('手动把主输入改成 AABB × aabb 重算：横幅消失、snapshot 清键',
        (tester) async {
      await pumpPedigree(tester);
      await tester.tap(find.text('计算').first);
      await tester.pumpAndSettle();
      ModuleFillBus.fill('pedigree_from_cross', crossParams());
      await tester.pumpAndSettle();
      expect(AppState.instance.buildSnapshot(), contains('参考表型比例'));
      expect(find.textContaining('参考表型比例'), findsOneWidget);

      final p1Field = parentField('AABBCC');
      final p2Field = parentField('aabbcc');
      expect(p1Field, findsOneWidget, reason: '主输入仍是出厂亲本');
      expect(p2Field, findsOneWidget);
      await tester.enterText(p1Field, 'AABB');
      await tester.enterText(p2Field, 'aabb');
      await tester.pumpAndSettle();
      await tester.tap(find.text('计算').first);
      await tester.pumpAndSettle();

      expect(find.textContaining('参考表型比例'), findsNothing,
          reason: 'LOW：手动重算成功后旧参考横幅必须消失');
      final snap = AppState.instance.buildSnapshot();
      expect(snap, isNot(contains('参考表型比例')),
          reason: 'AppState 不得再携带旧参考比例（否则 AI 看到的是上一题）');
      final mainLine = lineOf(snap, '双亲基因型');
      expect(mainLine, contains('AABB'), reason: '主输入已换成新亲本');
      expect(mainLine, contains('aabb'));
    });

    testWidgets('收起参考横幅：视图与 AI 快照同步摘键，系谱保留', (tester) async {
      await pumpPedigree(tester);
      ModuleFillBus.fill('pedigree_from_cross', crossParams());
      await tester.pumpAndSettle();
      expect(find.textContaining('参考表型比例'), findsOneWidget);
      expect(AppState.instance.buildSnapshot(), contains('参考表型比例'));

      await tester.tap(find.byTooltip('收起参考比例'));
      await tester.pumpAndSettle();

      expect(find.textContaining('参考表型比例'), findsNothing);
      expect(AppState.instance.buildSnapshot(),
          isNot(contains('参考表型比例')),
          reason: '收起后问 AI 不应再读到已撤下的旧参考值');
      final canvas = tester.widget<PedigreeCanvas>(find.byType(PedigreeCanvas));
      expect(canvas.nodes, isNotEmpty, reason: '收起参考值不删除任何系谱节点');
    });
  });

  group('9331 ⇄ 系谱：输入区直达 + 原状态返回', () {
    testWidgets('输入区「系谱展开」无需先找结果按钮，携带当前亲本与比例',
        (tester) async {
      tester.view.physicalSize = const Size(1400, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final captured = <Map<String, String>>[];
      ModuleFillBus.register(ModuleFillTarget(
        moduleId: 'pedigree_from_cross',
        pageIndex: 1,
        label: '遗传图谱',
        apply: (p) {
          captured.add(p);
          return true;
        },
      ));
      final navigations = <int>[];
      ModuleFillBus.navigator = navigations.add;
      await tester
          .pumpWidget(const MaterialApp(home: CrossCalculatorPage()));
      await tester.pumpAndSettle();
      await tester.enterText(find.widgetWithText(TextField, '亲本 1'), 'AAbb');
      await tester.enterText(find.widgetWithText(TextField, '亲本 2'), 'aaBB');

      await tester.tap(find.text('系谱展开'));
      await tester.pumpAndSettle();

      expect(navigations, [1]);
      expect(captured, hasLength(1));
      expect(captured.single['p1'], 'AAbb');
      expect(captured.single['p2'], 'aaBB');
      expect(captured.single['ratio'], '1',
          reason: 'AAbb × aaBB 的子代均为双显性表型，比例应为 1');
    });

    testWidgets('系谱参考条「返回 9331」只切页，不重新填参覆盖原题',
        (tester) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final applied = <Map<String, String>>[];
      ModuleFillBus.register(ModuleFillTarget(
        moduleId: 'cross_dihybrid',
        pageIndex: 2,
        label: '遗传计算器·双基因',
        apply: (p) {
          applied.add(p);
          return true;
        },
      ));
      final navigations = <int>[];
      ModuleFillBus.navigator = navigations.add;
      await tester.pumpWidget(const MaterialApp(home: GeneticPedigreePage()));
      await tester.pumpAndSettle();
      ModuleFillBus.fill('pedigree_from_cross', {
        'p1': 'AaBb',
        'p2': 'AaBb',
        'ratio': '9:3:3:1',
        'sourceLabel': '9331 杂交计算',
      });
      await tester.pumpAndSettle();
      navigations.clear();

      await tester.tap(find.text('返回 9331'));
      await tester.pumpAndSettle();

      expect(navigations, [2], reason: '经 HomeShell navigator 切页，不 push');
      expect(applied, isEmpty, reason: '返回不调用 apply，原输入与结果不被覆盖');
    });
  });

  group('v3.6 窄屏布局：结果动作折行、底部让开全局 FAB', () {
    testWidgets('390 宽结果区不溢出（按钮折行 + 底部留白）', (tester) async {
      tester.view.physicalSize = const Size(390, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester
          .pumpWidget(const MaterialApp(home: CrossCalculatorPage()));
      await tester.pumpAndSettle();

      await tester.enterText(find.widgetWithText(TextField, '亲本 1'), 'AaBb');
      await tester.enterText(find.widgetWithText(TextField, '亲本 2'), 'AaBb');
      final calcBtn = find.text('计算比例');
      await tester.scrollUntilVisible(calcBtn, 200,
          scrollable: find.byType(Scrollable).first);
      await tester.tap(calcBtn);
      await tester.pumpAndSettle();

      // 结果动作按钮存在且可滚到可见（Wrap 折行，不横向溢出）。
      final btn = find.text('在系谱画布展开');
      expect(btn, findsOneWidget);
      await tester.scrollUntilVisible(btn, 200,
          scrollable: find.byType(Scrollable).first);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull,
          reason: '窄屏结果区 + 变长按钮不得溢出');
    });
  });
}
