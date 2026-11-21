// ════════════════════════════════════════════════════════════════════════
//  test/pages/mistake_book_src_params_call_site_test.dart
//  存题调用点的**来源参数**守卫：单基因 / 伴性 / 双基因 / 三对基因四页存进去的亲本，
//  必须是真能填回去的亲本（否则错题本里会多一枚**死按钮**）。
// ════════════════════════════════════════════════════════════════════════
//
//  ## 这一层为什么值得单独立一个文件
//
//  「回来源工具重算」按钮的判据是 `mistakeEntryHasSource`：
//  `srcModule != null && srcParams` 非空。**只要记了就一定会渲染按钮**，
//  按钮点了就走 `ModuleFillBus.fill(moduleId, params)` —— 而
//  `cross_calculator_page.dart` 的 `_applyMonoFill` / `_applySexFill` /
//  `_applyCrossFill` 有自己的校验（那是回程的**事实源**，且不在本簇的
//  文件所有权内）。
//
//  ⇒ 调用侧的判据必须与回程的校验**逐字一致**。一旦漂移，后果不是编译
//  错误、也不是测试变红，而是学生点开一枚「去「单基因」重算」之后收到
//  「那一页现在过不去」——一枚**看得见却点不动**的按钮。本文件就是把
//  「记下来的参数 ⇔ 回程认得的参数」钉成回归。
//
//  ## 两个方向都要断，且两页的「拦」发生在不同层（不是抄同一个测试）
//
//  · 单基因（cross_mono）：本页只校验「长度 == 2」，所以 `1a` **能算出来**
//    ——判据必须落在 `_monoSrcParams` 里（对齐回程的 `^[A-Za-z]{2}$`）。
//  · 伴性（cross_sex_linked）：本页用引擎的 `parseGenotype`，`XAZ`
//    **根本算不出来** ⇒ 屏上不存在「存入错题本」入口 ⇒ 假来源连落库的
//    机会都没有。两条路径守住的是同一个不变量，实现位置不同。
//
//  ## 双基因 / 三对基因（v2.19.37 补齐的最后两处 dormant 调用点）
//
// 这两页与上面两页**同页同源**（同一个 `CrossCalculatorPage`），回程判据
// 也同族（`_applyCrossFill`，只是字符数分档：tab 0 = 4、tab 1 = 6）。
// ⛔ 它们的 tab 是**库私有类**（`_Dihybrid9331Tab` / `_TrihybridTab`），
// 测试拿不到 ⇒ 只能整页起、再点页签名切过去（`pumpPage`）。
// ⛔ 与上面两组相反，视口取**宽屏**（1400×3000）：>=1200 时输入面板注入
// 左栏 rail，同一时刻树上只有**当前页签**的输入框——窄屏下相邻页签各自
// 自渲染一份，`find.widgetWithText(TextField, '亲本 1')` 会撞车。
//
// ## 两页的「假来源」走**两条不同的路**（别抄成同一个测试）
//
// · 双基因（cross_dihybrid）：`_calculate` **只查长度**（4），引擎
//   （`dihybrid9331` → `CrossEngine`）也不校验字符 ⇒ `1aB1` **算得出**、
//   屏上照样有存入按钮 ⇒ 判据必须落在 srcParams 那一层（同单基因组的
//   `1a`）。
// · 三对基因（cross_trihybrid）：`_calculate` 走 `KaojiCalc.crossAuto`，
//   它**自己解析基因型**，`AaBb1C` 直接回 error ⇒ 本页置 `_error`、
//   `_result = null` ⇒ 结果面板（含存入按钮）整块消失（同伴性组的 `XAZ`）。
//
// 两条路径守住的是同一个不变量：回程填不进去的亲本**绝不许**落进错题本。
//
//  ## 视口
//
// 900×1400 @1.0（单基因 / 伴性两组）—— **必须窄于 1200**：这两个 tab 的
// 输入面板（含「杂交」/「计算子代」按钮）在宽屏是由 9331 页的 rail 注入
// 的，单独起 widget 时只有窄态才自渲染。

import 'dart:io';

import 'package:biology/pages/cross_calculator_page.dart';
import 'package:biology/pages/widgets/mono_cross_widget.dart';
import 'package:biology/pages/widgets/sex_linked_tab.dart';
import 'package:biology/state/first_run_store.dart';
import 'package:biology/state/mistake_book.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory tmp;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('mistake_src_params_site');
    MistakeBook.debugFilePath = '${tmp.path}/mistakes.json';
    MistakeBook.debugTrashFilePath = '${tmp.path}/mistakes.trash.json';
    MistakeBook.instance.debugReset();
    FirstRunStore.debugFilePath = '${tmp.path}/first_run.json';
    FirstRunStore.debugWebStorage = null;
    FirstRunStore.debugForceIsWebStorage = false;
    FirstRunStore.instance.debugReset();
  });

  tearDown(() {
    MistakeBook.instance.debugFlushSave();
    MistakeBook.instance.debugResetAiOrganize();
    MistakeBook.instance.debugReset();
    MistakeBook.debugFilePath = null;
    MistakeBook.debugTrashFilePath = null;
    FirstRunStore.debugFilePath = null;
    FirstRunStore.debugWebStorage = null;
    FirstRunStore.debugForceIsWebStorage = false;
    FirstRunStore.instance.debugReset();
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  Future<void> pumpNarrow(WidgetTester tester, Widget page) async {
    tester.view.physicalSize = const Size(900, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(home: page));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  /// 整页起遗传计算器（双基因 / 三对基因两个 tab 是**库私有类**，测试拿不到，
  /// 只能开整页再点页签名切过去）。视口 1400×3000：**宽屏**下输入面板注入
  /// 左栏 rail ⇒ 同一时刻树上只有**当前页签**的输入框（窄屏下相邻页签各挂
  /// 一份，判据锚点会撞车）。
  Future<void> pumpPage(WidgetTester tester, {String tab = '双基因 9331'}) async {
    tester.view.physicalSize = const Size(1400, 3000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const MaterialApp(home: CrossCalculatorPage()));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    if (tab != '双基因 9331') {
      final t = find.text(tab);
      expect(t, findsWidgets, reason: '页签页名「$tab」必须在屏上');
      await tester.tap(t.first);
      await tester.pumpAndSettle();
    }
  }

  /// 点「计算比例」并等结果面板展开（两页的按钮同名）。
  Future<void> tapCalculate(WidgetTester tester) async {
    await tester.tap(find.text('计算比例'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  /// 把某个 label 的亲本输入框改掉（宽屏下该 label 在树上唯一——
  /// `pumpPage` 用宽视口就是为了这条）。
  Future<void> setParent(WidgetTester tester, String label, String value) async {
    final f = find.widgetWithText(TextField, label);
    expect(f, findsOneWidget, reason: '前提：「$label」输入框唯一在场');
    await tester.ensureVisible(f);
    await tester.pump();
    await tester.enterText(f, value);
    await tester.pump();
  }

  /// 收尾：泵过写盘 debounce，不留 pending timer。
  Future<void> settle(WidgetTester tester) async {
    await tester.pump(const Duration(milliseconds: 600));
  }

  /// 点那枚「存入错题本」（结果面板里）。前提已由调用方断过。
  Future<void> tapSave(WidgetTester tester) async {
    await tester.tap(find.text('存入错题本').first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  // ── 单基因（cross_mono）──────────────────────────────────────────────

  testWidgets('单基因：出厂态存题 ⇒ srcModule=cross_mono + 记下 Aa/Aa',
      (tester) async {
    await pumpNarrow(tester, const Scaffold(body: MonoCrossWidget()));

    // 先算出结果（否则「存入错题本」守卫会拦：空答案不入库）。
    await tester.tap(find.text('杂交'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('存入错题本'), findsWidgets,
        reason: '前提：结果面板有那枚存入按钮');

    await tapSave(tester);

    final e = MistakeBook.instance.entries.single;
    expect(e.srcModule, 'cross_mono',
        reason: '单基因页存进来的题必须记下来源页签');
    expect(e.srcParams, isNotNull,
        reason: '出厂态亲本合法 ⇒ 必须记下（否则复习时没按钮）');
    expect(e.srcParams!['p1'], 'Aa', reason: 'p1 = 亲本 1（不许只断非空）');
    expect(e.srcParams!['p2'], 'Aa', reason: 'p2 = 亲本 2');

    await settle(tester);
  });

  testWidgets('单基因：亲本改成回程认不出的格式 ⇒ srcParams=null（不出按钮）',
      (tester) async {
    await pumpNarrow(tester, const Scaffold(body: MonoCrossWidget()));

    // `1a` 长度对、但含数字：回程 `_applyMonoFill` 的 `^[A-Za-z]{2}$`
    // 不收 ⇒ 记下来就是一枚点下去必然失败的死按钮。本页只查长度，
    // 所以这条恰恰是「判据写在 srcParams 里」才有意义的场景。
    final p1 = find.widgetWithText(TextField, '亲本 1');
    await tester.ensureVisible(p1);
    await tester.pump();
    await tester.enterText(p1.first, '1a');
    await tester.pump();

    await tester.tap(find.text('杂交'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('存入错题本'), findsWidgets,
        reason: '前提：`1a` 长度对，本页照样算得出结果（所以这条真的'
            '考验到 srcParams 判据，而不是被「算不出来」挡掉）');

    await tapSave(tester);

    final e = MistakeBook.instance.entries.single;
    expect(e.srcModule, 'cross_mono',
        reason: '来源页仍然要记（它是真的）');
    expect(e.srcParams, isNull,
        reason: '⛔ 回程填不进去的亲本不许记（错题本会因此多一枚死按钮）');

    await settle(tester);
  });

  // ── 伴性遗传（cross_sex_linked）──────────────────────────────────────

  testWidgets('伴性：出厂态存题 ⇒ srcModule=cross_sex_linked + 记下 XAXa/XAY',
      (tester) async {
    await pumpNarrow(tester, const Scaffold(body: SexLinkedTab()));

    await tester.tap(find.text('计算子代'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('存入错题本'), findsWidgets,
        reason: '前提：结果面板有那枚存入按钮');

    await tapSave(tester);

    final e = MistakeBook.instance.entries.single;
    expect(e.srcModule, 'cross_sex_linked');
    expect(e.srcParams, isNotNull);
    expect(e.srcParams!['p1'], 'XAXa',
        reason: 'p1 = 母本（回程落 _femaleCtrl）');
    expect(e.srcParams!['p2'], 'XAY', reason: 'p2 = 父本（回程落 _maleCtrl）');

    await settle(tester);
  });

  testWidgets('伴性：基因型引擎认不出 ⇒ 屏上没有存入入口（假来源无处可落）',
      (tester) async {
    await pumpNarrow(tester, const Scaffold(body: SexLinkedTab()));

    // `XAZ`：X 开头、≥3 字符（能过 `_applySexFilled` 的宽松前置校验），但
    // Z 不是伴性基因的等位基因字母 ⇒ 引擎抛 ArgumentError ⇒ 本页置
    // `_error`、`_result = null` ⇒ 结果面板（含存入按钮）整块消失。
    final female = find.widgetWithText(TextField, '母亲基因型 ♀');
    await tester.ensureVisible(female);
    await tester.pump();
    await tester.enterText(female.first, 'XAZ');
    await tester.pump();
    await tester.tap(find.text('计算子代'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('存入错题本'), findsNothing,
        reason: '算不出结果时不存在存入入口 ⇒ 不可能记下回程填不进去的来源');
    expect(MistakeBook.instance.entries, isEmpty,
        reason: '⛔ 不许凭空多出一条带假来源的错题');

    await settle(tester);
  });
  // ── 双基因 9331（cross_dihybrid）───────────────────────────────────

  testWidgets('双基因：出厂态存题 ⇒ srcModule=cross_dihybrid + 记下 AaBb/AaBb',
      (tester) async {
    await pumpPage(tester);

    // 先算出结果（否则「存入错题本」守卫会拦：空答案不入库）。
    await tapCalculate(tester);
    expect(find.text('存入错题本'), findsOneWidget,
        reason: '前提：结果面板有那枚存入按钮');

    await tapSave(tester);

    final e = MistakeBook.instance.entries.single;
    expect(e.srcModule, 'cross_dihybrid',
        reason: '双基因页存进来的题必须记下来源页签');
    expect(e.srcParams, isNotNull,
        reason: '出厂态亲本合法 ⇒ 必须记下（否则复习时没按钮）');
    expect(e.srcParams!['p1'], 'AaBb', reason: 'p1 = 亲本 1（不许只断非空）');
    expect(e.srcParams!['p2'], 'AaBb', reason: 'p2 = 亲本 2');

    await settle(tester);
  });

  testWidgets('双基因：亲本含数字（本页照样算得出）⇒ srcParams=null（不出按钮）',
      (tester) async {
    await pumpPage(tester);

    // `1aB1` 长度对（4），本页 `_calculate` 只查长度、引擎也不校验字符
    // ⇒ 照样出结果、照样有存入入口；但回程 `_applyCrossFill(0,…)` 的
    // `^[A-Za-z]{4}$` 不收 ⇒ 记下来就是一枚点下去必然失败的死按钮。
    // 这条恰恰是「判据写在 srcParams 里」才有意义的场景。
    await setParent(tester, '亲本 1', '1aB1');

    await tapCalculate(tester);
    expect(find.text('存入错题本'), findsOneWidget,
        reason: '前提：`1aB1` 长度对，本页照样算得出结果（所以这条真的'
            '考验到 srcParams 判据，而不是被「算不出来」挡掉）');

    await tapSave(tester);

    final e = MistakeBook.instance.entries.single;
    expect(e.srcModule, 'cross_dihybrid',
        reason: '来源页仍然要记（它是真的）');
    expect(e.srcParams, isNull,
        reason: '⛔ 回程填不进去的亲本不许记（错题本会因此多一枚死按钮）');

    await settle(tester);
  });

  // ── 三对基因（cross_trihybrid）────────────────────────────────────

  testWidgets('三对基因：出厂态存题 ⇒ srcModule=cross_trihybrid + 记下 AaBbCc/AaBbCc',
      (tester) async {
    // ⛔ 必须真切到页签：默认停在双基因（tab 0），三对基因的 State 还没挂。
    await pumpPage(tester, tab: '三对基因');

    await tapCalculate(tester);
    expect(find.text('存入错题本'), findsOneWidget,
        reason: '前提：结果面板有那枚存入按钮');

    await tapSave(tester);

    final e = MistakeBook.instance.entries.single;
    expect(e.srcModule, 'cross_trihybrid',
        reason: '⛔ 面板 n 基因通用（两页共用），来源页签必须由调用方透传——'
            '透传丢了就会记成双基因，回程停在错误的页签');
    expect(e.srcParams, isNotNull,
        reason: '出厂态亲本合法 ⇒ 必须记下（否则复习时没按钮）');
    expect(e.srcParams!['p1'], 'AaBbCc', reason: 'p1 = 亲本 1（不许只断非空）');
    expect(e.srcParams!['p2'], 'AaBbCc', reason: 'p2 = 亲本 2');

    await settle(tester);
  });

  testWidgets('三对基因：crossAuto 解析不出 ⇒ 屏上没有存入入口（假来源无处可落）',
      (tester) async {
    await pumpPage(tester, tab: '三对基因');

    // `AaBb1C` 长度对（6），但 `KaojiCalc.crossAuto` 的基因型解析器只认
    // 等位基因字母 ⇒ 回 error ⇒ 本页置 `_error`、`_result = null` ⇒
    // 结果面板（含存入按钮）整块消失。⛔ 与双基因那组不同：这一组考的
    // 是「假来源连落库的机会都没有」，不是「判据把它拦在门外」。
    await setParent(tester, '亲本 1', 'AaBb1C');

    await tapCalculate(tester);
    expect(find.text('存入错题本'), findsNothing,
        reason: '算不出结果时不存在存入入口 ⇒ 不可能记下回程填不进去的来源');
    expect(MistakeBook.instance.entries, isEmpty,
        reason: '⛔ 不许凭空多出一条带假来源的错题');

    await settle(tester);
  });
}
