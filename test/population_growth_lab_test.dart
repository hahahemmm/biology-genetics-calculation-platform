// population_growth_lab_test.dart —— 进化页第 6 页签「种群增长」守卫网
//
// 网型：① 自包含形态逐条钉住「默认例免键盘即有结果」；
// ② 三个预设 chip 各自摆全五个输入；③ 错误必须看得见且清旧结果；
// ④ r=0 / N₀>K 两个模型边界的解释必须讲对（不许写成「回落」或「上限」）；
// ⑤ isPristine 覆盖全部五个输入；⑥ 页面接线：6 页签、旧索引不变、
//    深链 tab=4/5/6、往返保活、「全部计算」重算、390 零溢出；
// ⑦ 教学公式必须是真 TeX 排版（Math 组件），源码式纯文本退场。
import 'package:biology/pages/evolution_page.dart';
import 'package:biology/pages/widgets/population_growth_lab.dart';
import 'package:biology/theme.dart';
import 'package:biology/ui/module_fill.dart';
import 'package:biology/ui/tex_formula.dart';
import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _pumpLab(
  WidgetTester tester, {
  GlobalKey<PopulationGrowthLabState>? hostKey,
  bool showInputs = true,
  Size size = const Size(1100, 3200),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: SingleChildScrollView(
        child: PopulationGrowthLab(key: hostKey, showInputs: showInputs),
      ),
    ),
  ));
  await tester.pumpAndSettle();
}

int _tabIndex(WidgetTester tester) =>
    tester.widget<TabBar>(find.byType(TabBar)).controller!.index;

Future<void> _pumpPage(
  WidgetTester tester, {
  Size size = const Size(1600, 1200),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(const MaterialApp(home: EvolutionPage()));
  await tester.pumpAndSettle();
}

Finder _tab(String label) => find.descendant(
    of: find.byType(TabBar), matching: find.text(label));

Future<void> _openGrowth(WidgetTester tester) async {
  await tester.ensureVisible(_tab('种群增长'));
  await tester.pumpAndSettle();
  await tester.tap(_tab('种群增长'));
  await tester.pumpAndSettle();
}

void main() {
  group('自包含形态：默认例免键盘即有结果', () {
    testWidgets('J 型 1297.46 / S 型 993.34，K 与 K/2 都在屏上', (tester) async {
      await _pumpLab(tester);

      expect(find.textContaining('J 型与 S 型对照曲线'), findsOneWidget);
      expect(find.textContaining('教学简化模型'), findsOneWidget,
          reason: '模型边界必须印在屏上');
      expect(find.textContaining('不用于预测真实种群'), findsOneWidget);
      expect(find.textContaining('J 型末代 1297.46'), findsOneWidget);
      expect(find.textContaining('S 型末代 993.34'), findsOneWidget);
      // 逐代表格：末代一行（同一行里两个数）
      expect(find.textContaining('J = 1297.46'), findsOneWidget);
      expect(find.textContaining('S = 993.34'), findsOneWidget);
      // K 与 K/2 的解释
      expect(find.textContaining('K/2 = 500'), findsWidgets);
      expect(find.textContaining('r·K/4 = 200 个/代'), findsWidgets);
      expect(find.textContaining('屏上采样最早在第 6 代看到 N ≥ K/2'),
          findsOneWidget);
      // 绝对速率 vs 相对增长率（数值行照旧走纯文本）
      expect(find.textContaining('绝对 7.92 个/代'), findsOneWidget);
      expect(find.textContaining('相对 79.2%'), findsOneWidget);
      expect(find.textContaining('λ−1 = 0.5'), findsWidgets);
      expect(tester.takeException(), isNull);
    });

    testWidgets('图表本体在屏上（不是频率轴那张 0..1 图）', (tester) async {
      await _pumpLab(tester);
      expect(find.textContaining('纵轴刻度不是 0–1 的频率轴'), findsOneWidget);
      expect(find.byType(CustomPaint), findsWidgets);
    });
  });

  group('教学公式：真 TeX 排版（非源码式纯文本）', () {
    testWidgets('J/S 通式与速率区共 5 条公式全部渲染成 Math 组件', (tester) async {
      await _pumpLab(tester);

      // 组件层：输入区 J/S 通式 2 条 + 速率区绝对/相对 2 条 + J 型对照 1 条
      expect(find.byType(TexFormula), findsNWidgets(5));
      // 渲染层：每条都是 flutter_math_fork 的 Math（真排版），无一解析失败
      expect(find.byType(Math), findsNWidgets(5));
      for (final m in tester.widgetList<Math>(find.byType(Math))) {
        expect(m.parseError, isNull,
            reason: '教学公式必须解析成功（失败会回落纯文本）');
        expect(m.ast, isNotNull);
      }
      // 结构抽查：TeX 里必须是真分式 / 真上下标 / 希腊字母
      expect(
        find.byWidgetPredicate(
            (w) => w is TexFormula && w.tex.contains(r'N_0\,\lambda^{t}')),
        findsOneWidget,
        reason: 'J 型通项必须是 N_t = N₀·λ^t 的真排版',
      );
      expect(
        find.byWidgetPredicate(
            (w) => w is TexFormula && w.tex.contains(r'\frac{K}{')),
        findsOneWidget,
        reason: 'S 型通项必须用真分式',
      );
      expect(
        find.byWidgetPredicate(
            (w) => w is TexFormula && w.tex.contains(r'\frac{dN}{dt}')),
        findsNWidgets(2),
        reason: '绝对 dN/dt 与相对 (1/N)·dN/dt 两条都必须是真分式',
      );
      expect(
        find.byWidgetPredicate(
            (w) => w is TexFormula && w.tex.contains(r'N_{t+1}')),
        findsOneWidget,
        reason: 'J 型对照的 N_{t+1}−N_t = N_t(λ−1) 必须是真排版',
      );
      // 源码式纯文本必须退场
      expect(find.textContaining('dN/dt = r·N·(1−N/K)'), findsNothing);
      expect(find.textContaining('N_t = K/(1+'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('390 窄屏：长分式只做局部横向滚动，整页零溢出', (tester) async {
      await _pumpLab(tester, size: const Size(390, 3600));

      expect(find.byType(TexFormula), findsNWidgets(5));
      expect(
        find.byWidgetPredicate((w) =>
            w is SingleChildScrollView &&
            w.scrollDirection == Axis.horizontal),
        findsWidgets,
        reason: '窄屏必须有公式专属的局部横向滚动容器',
      );
      expect(find.byType(FittedBox), findsNothing,
          reason: '⛔ 不允许缩放保命（缩到看不清）');
      expect(tester.takeException(), isNull, reason: '⛔ 公式不得把整页撑溢出');
    });

    testWidgets('深色主题：公式颜色跟随 inkD，零异常', (tester) async {
      AppColors.sync(Brightness.dark);
      addTearDown(() => AppColors.debugClearOverride());

      await _pumpLab(tester);

      expect(find.byType(TexFormula), findsNWidgets(5));
      for (final m in tester.widgetList<Math>(find.byType(Math))) {
        expect(m.textStyle?.color, AppColors.inkD,
            reason: '深色下公式必须用 inkD（深底浅字）');
      }
      expect(tester.takeException(), isNull);
    });
  });

  group('自然中文因果句：屏上⛔ 不留 ⇒（golden 缺字形会渲染成方框）', () {
    // 【为什么守这个】⇒（U+21D2）在 golden 的中文字体（微软雅黑）里没有字形，
    // 会渲染成 .notdef 空心方框——实测速率区「读法」显示成 `> 1 □ 增长`。
    // 只断言 Math.ast / 组件类型拦不住它，必须钉住「屏上可见 Text 不含 ⇒」。
    testWidgets('默认例（grow）：含「> 1，所以增长：」且全树无 ⇒', (tester) async {
      await _pumpLab(tester);

      expect(find.textContaining('> 1，所以增长：'), findsOneWidget,
          reason: '默认 λ=1.5 走 grow 分支，必须是自然中文因果句');
      expect(find.textContaining('⇒'), findsNothing,
          reason: '⛔ ⇒ 缺字形（.notdef 方框），不许留给学生');
    });

    testWidgets('stable / decline / extinct 三个分支也无 ⇒，且用自然中文', (tester) async {
      await _pumpLab(tester);

      Future<void> setLambda(String v, String phrase) async {
        await tester.enterText(
            find.widgetWithText(TextField, '每代增长倍数 λ（0–10）'), v);
        await tester.tap(find.text('计算种群增长'));
        await tester.pumpAndSettle();
        expect(find.textContaining(phrase), findsOneWidget,
            reason: 'λ=$v 分支必须是自然中文因果句');
        expect(find.textContaining('⇒'), findsNothing,
            reason: 'λ=$v 分支仍出现 ⇒（golden 会渲染成方框）');
      }

      await setLambda('1', 'λ = 1，所以稳定：');
      await setLambda('0.8', '0 < λ < 1，所以下降：');
      await setLambda('0', 'λ = 0，所以归零：');
    });

    testWidgets('r=0 的两条 K/2 说明也无 ⇒，且用自然中文', (tester) async {
      await _pumpLab(tester);

      // r=0 且 N₀<K/2：走「不会达到」分支
      await tester.enterText(
          find.widgetWithText(TextField, '内禀增长率 r（0–5）'), '0');
      await tester.tap(find.text('计算种群增长'));
      await tester.pumpAndSettle();
      expect(find.textContaining('r = 0，所以数量恒为'), findsOneWidget);
      expect(find.textContaining('⇒'), findsNothing);

      // N₀=K/2 且 r=0：走「起点正好在 K/2」分支
      await tester.enterText(
          find.widgetWithText(TextField, '初始数量 N0'), '500');
      await tester.tap(find.text('计算种群增长'));
      await tester.pumpAndSettle();
      expect(find.textContaining('r = 0，所以数量不变'), findsOneWidget);
      expect(find.textContaining('⇒'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });

  group('预设 chips（每个都摆全五个输入）', () {
    testWidgets('「资源有限 S 型」：20 代、J 766.75、S 993.99', (tester) async {
      await _pumpLab(tester);

      await tester.tap(find.text('资源有限 S 型'));
      await tester.pumpAndSettle();

      expect(find.textContaining('J 型末代 766.75'), findsOneWidget);
      expect(find.textContaining('S 型末代 993.99'), findsOneWidget);
      expect(find.textContaining('t = 20'), findsWidgets);
      expect(tester.takeException(), isNull);
    });

    testWidgets('「N0 > K 的回落」：说明按回落讲，且不再声称经过 K/2',
        (tester) async {
      await _pumpLab(tester);

      await tester.tap(find.text('N0 > K 的回落'));
      await tester.pumpAndSettle();

      expect(find.textContaining('不经过：起点 N0 = 2000 已在 K/2 之上'),
          findsOneWidget);
      expect(find.textContaining('从上方逐渐回落到 K'), findsWidgets);
      expect(find.textContaining('不会再经过 K/2'), findsOneWidget);
      expect(find.textContaining('经过：连续模型'), findsNothing,
          reason: '⛔ 起点在 K/2 之上后不许编造「以后经过 K/2」');
      // K 不得被说成「数量上限」
      expect(find.textContaining('只由环境决定；它不是一个「数量上限」'),
          findsNothing,
          reason: '该句只属于 N₀<K 的分支');
      expect(find.textContaining('不是一条「数量上限」'), findsOneWidget);
    });

    testWidgets('「理想 J 型」＝出厂默认题（点回来仍是出厂状态）',
        (tester) async {
      final key = GlobalKey<PopulationGrowthLabState>();
      await _pumpLab(tester, hostKey: key);

      await tester.tap(find.text('资源有限 S 型'));
      await tester.pumpAndSettle();
      expect(key.currentState!.isPristine, isFalse);

      await tester.tap(find.text('理想 J 型'));
      await tester.pumpAndSettle();
      expect(key.currentState!.isPristine, isTrue,
          reason: '把默认题摆回来 = 出厂状态');
      expect(find.textContaining('J 型末代 1297.46'), findsOneWidget);
    });
  });

  group('模型边界：r=0（不崩、解释正确）', () {
    testWidgets('r=0 且 N₀<K/2：写明「永远停在 K/2 以下」，不崩', (tester) async {
      await _pumpLab(tester);

      await tester.enterText(
          find.widgetWithText(TextField, '内禀增长率 r（0–5）'), '0');
      await tester.tap(find.text('计算种群增长'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull,
          reason: '⛔ 旧实现会在这里 gen! 强制解包崩溃');
      expect(find.textContaining('当前设置下不会达到'), findsOneWidget);
      expect(find.textContaining('永远停在 K/2 以下'), findsOneWidget);
      expect(find.textContaining('不会朝 K 变化'), findsOneWidget);
      expect(find.textContaining('S 型不增长'), findsOneWidget);
      expect(find.textContaining('经过：连续模型'), findsNothing);
      // 两条曲线的 S 值全程等于 N₀（表里每一行都一样）
      expect(find.textContaining('S = 10'), findsWidgets);
    });

    testWidgets('代数不足以走到 K/2：写「当前代数范围内还没达到」', (tester) async {
      await _pumpLab(tester);

      await tester.enterText(find.widgetWithText(TextField, '代数（1–40）'), '2');
      await tester.tap(find.text('计算种群增长'));
      await tester.pumpAndSettle();

      expect(find.textContaining('当前代数范围内还没达到'), findsOneWidget);
      expect(find.textContaining('t = 5.74'), findsOneWidget,
          reason: '精确时刻 t* = ln(99)/0.8 ≈ 5.74，与采样代无关');
      expect(tester.takeException(), isNull);
    });
  });

  group('输入错误必须看得见，且清掉旧结果', () {
    testWidgets('非数字：中文错误 + 旧曲线消失', (tester) async {
      await _pumpLab(tester);

      await tester.enterText(
          find.widgetWithText(TextField, '初始数量 N0'), 'abc');
      await tester.tap(find.text('计算种群增长'));
      await tester.pumpAndSettle();

      expect(find.textContaining('都必须是数字'), findsOneWidget);
      expect(find.textContaining('J 型与 S 型对照曲线'), findsNothing);
      expect(find.textContaining('逐代数值'), findsNothing);
    });

    testWidgets('K ≤ 0：点名 K 必须大于 0', (tester) async {
      await _pumpLab(tester);

      await tester.enterText(
          find.widgetWithText(TextField, '环境容纳量 K（S 型）'), '-100');
      await tester.tap(find.text('计算种群增长'));
      await tester.pumpAndSettle();

      expect(find.textContaining('环境容纳量 K 必须大于 0'), findsOneWidget);
      expect(find.textContaining('逐代数值'), findsNothing);
    });

    testWidgets('代数 41：点名 1–40 范围', (tester) async {
      await _pumpLab(tester);

      await tester.enterText(find.widgetWithText(TextField, '代数（1–40）'), '41');
      await tester.tap(find.text('计算种群增长'));
      await tester.pumpAndSettle();

      expect(find.textContaining('代数必须在 1–40 之间'), findsOneWidget);
    });

    testWidgets('改回合法值：错误消失、结果回来', (tester) async {
      await _pumpLab(tester);

      await tester.enterText(
          find.widgetWithText(TextField, '初始数量 N0'), 'abc');
      await tester.tap(find.text('计算种群增长'));
      await tester.pumpAndSettle();
      expect(find.textContaining('都必须是数字'), findsOneWidget);

      await tester.enterText(
          find.widgetWithText(TextField, '初始数量 N0'), '10');
      await tester.tap(find.text('计算种群增长'));
      await tester.pumpAndSettle();

      expect(find.textContaining('都必须是数字'), findsNothing);
      expect(find.textContaining('J 型末代 1297.46'), findsOneWidget);
    });
  });

  group('isPristine（父页脏页守卫的判据）', () {
    testWidgets('出厂 true；任一输入改动即 false；改回 true', (tester) async {
      final key = GlobalKey<PopulationGrowthLabState>();
      await _pumpLab(tester, hostKey: key);

      expect(key.currentState!.isPristine, isTrue);

      await tester.enterText(
          find.widgetWithText(TextField, '每代增长倍数 λ（0–10）'), '2');
      await tester.pumpAndSettle();
      expect(key.currentState!.isPristine, isFalse);

      await tester.enterText(
          find.widgetWithText(TextField, '每代增长倍数 λ（0–10）'), '1.5');
      await tester.pumpAndSettle();
      expect(key.currentState!.isPristine, isTrue);
    });
  });

  group('showInputs=false（页面里的用法）', () {
    testWidgets('只出结果，输入区不重复渲染', (tester) async {
      await _pumpLab(tester, showInputs: false);

      expect(find.text('计算种群增长'), findsNothing);
      expect(find.text('初始数量 N0'), findsNothing);
      expect(find.textContaining('J 型末代 1297.46'), findsOneWidget);
      expect(find.textContaining('J 型与 S 型对照曲线'), findsOneWidget);
    });
  });

  group('窄屏（390）', () {
    testWidgets('自包含形态 390 宽零溢出（含图表与逐代表格）', (tester) async {
      await _pumpLab(tester, size: const Size(390, 3600));

      expect(tester.takeException(), isNull);
      expect(find.textContaining('J 型与 S 型对照曲线'), findsOneWidget);
      expect(find.textContaining('J = 1297.46'), findsOneWidget);
    });
  });

  group('进化页接线（第 6 页签）', () {
    testWidgets('6 个页签都在；旧 5 个索引不变（tab4 仍是进化理论）',
        (tester) async {
      await _pumpPage(tester);
      addTearDown(ModuleFillBus.resetForTest);

      for (final label in ['进化树', '基因频率', '遗传平衡', '选择模拟', '进化理论', '种群增长']) {
        expect(_tab(label), findsOneWidget, reason: '页签「$label」必须还在');
      }
      expect(_tabIndex(tester), 0);

      await tester.tap(_tab('进化理论'));
      await tester.pumpAndSettle();
      expect(_tabIndex(tester), 4, reason: '旧 tab4 仍落「进化理论」');
      expect(find.textContaining('共同祖先的证据'), findsWidgets,
          reason: 'tab4 仍是进化理论知识区');

      await _openGrowth(tester);
      expect(_tabIndex(tester), 5);
      expect(find.text('计算种群增长'), findsOneWidget,
          reason: '宽屏左栏注入本实验的输入面板');
      expect(find.textContaining('J 型末代 1297.46'), findsOneWidget,
          reason: '右栏出结果（免键盘）');
      expect(tester.takeException(), isNull);
    });

    testWidgets('深链：tab=4 仍进化理论、tab=5 落种群增长、tab=6 仍拒',
        (tester) async {
      await _pumpPage(tester);
      addTearDown(ModuleFillBus.resetForTest);

      ModuleFillBus.fill('evolution', const {'tab': '4'});
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      expect(_tabIndex(tester), 4);

      ModuleFillBus.fill('evolution', const {'tab': '5'});
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      expect(_tabIndex(tester), 5);

      ModuleFillBus.fill('evolution', const {'tab': '6'});
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      expect(_tabIndex(tester), 5, reason: '越界深链必须仍被拒（原地不动）');
    });

    testWidgets('往返保活：改 K 后算一次，切走再回来输入与结果都在',
        (tester) async {
      await _pumpPage(tester);
      addTearDown(ModuleFillBus.resetForTest);
      await _openGrowth(tester);

      final kField = find.widgetWithText(TextField, '环境容纳量 K（S 型）');
      await tester.ensureVisible(kField);
      await tester.enterText(kField, '500');
      await tester.pumpAndSettle();
      final calc = find.text('计算种群增长');
      await tester.ensureVisible(calc);
      await tester.tap(calc);
      await tester.pumpAndSettle();
      expect(find.textContaining('K = 500'), findsWidgets);

      await tester.tap(_tab('基因频率'));
      await tester.pumpAndSettle();
      await _openGrowth(tester);

      expect(
        tester
            .widget<TextField>(find.widgetWithText(TextField, '环境容纳量 K（S 型）'))
            .controller!
            .text,
        '500',
        reason: '页签往返不得重置输入',
      );
      expect(find.textContaining('K = 500'), findsWidgets,
          reason: '结果也不得被重置回默认题');
    });

    testWidgets('「全部计算」重算新实验，且不丢当前输入', (tester) async {
      await _pumpPage(tester);
      addTearDown(ModuleFillBus.resetForTest);
      await _openGrowth(tester);

      final n0Field = find.widgetWithText(TextField, '初始数量 N0');
      await tester.ensureVisible(n0Field);
      await tester.enterText(n0Field, '20');
      await tester.pumpAndSettle();

      await tester.tap(find.text('全部计算'));
      await tester.pumpAndSettle();

      expect(find.textContaining('J 型末代 2594.93'), findsOneWidget,
          reason: '20×1.5¹² = 2594.93（按当前输入重算，不是回到默认题）');
      expect(
        tester
            .widget<TextField>(find.widgetWithText(TextField, '初始数量 N0'))
            .controller!
            .text,
        '20',
        reason: '重算 ≠ 重置',
      );
    });

    testWidgets('390 窄屏：页签可达，结果零溢出', (tester) async {
      await _pumpPage(tester, size: const Size(390, 844));
      addTearDown(ModuleFillBus.resetForTest);

      await _openGrowth(tester);
      expect(_tabIndex(tester), 5);
      expect(find.text('计算种群增长'), findsOneWidget,
          reason: '窄屏输入面板回落在结果区上方，必须可触达');
      expect(find.textContaining('J 型末代 1297.46'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
