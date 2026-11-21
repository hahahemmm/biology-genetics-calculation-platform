// v214_backlog_test.dart —— v2.14 backlog 项回归测试
//
// 覆盖（2026-09-18「把能做的优化都做了」批次）：
//   1. 班级共性错：老师页本机脱敏聚合（错因分布/高频考点/代表题）
//   2. 讲题回放补齐：cross_mono / cross_sex_linked 注册 + fill 直达
//   3. 拍题原图：stage → 遗传病页消费展示（take 语义）
//   4. AI 总览 prompt：含「今日到期」行动信号

import 'dart:io';

import 'package:biology/main.dart' as app_main;
import 'package:biology/pages/cross_calculator_page.dart';
import 'package:biology/pages/dashboard_page.dart';
import 'package:biology/pages/genetic_disease_page.dart';
import 'package:biology/state/first_run_store.dart';
import 'package:biology/state/mistake_book.dart';
import 'package:biology/ui/mistake_book_ai.dart';
import 'package:biology/ui/module_fill.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('班级共性错（老师页本机脱敏聚合）', () {
    late Directory tmp;

    setUp(() async {
      tmp = Directory.systemTemp.createTempSync('v214_bl_test');
      MistakeBook.debugFilePath = '${tmp.path}/m.json';
      MistakeBook.debugTrashFilePath = '${tmp.path}/m.trash.json';
      MistakeBook.instance.debugReset();
      FirstRunStore.debugFilePath = '${tmp.path}/fr.json';
      FirstRunStore.debugWebStorage = null;
      FirstRunStore.debugForceIsWebStorage = false;
      FirstRunStore.instance.debugReset();
      await FirstRunStore.instance.setRole(UserRole.teacher);
      addTearDown(() => MistakeBook.instance.debugFlushSave());
    });

    tearDown(() {
      MistakeBook.debugFilePath = null;
      MistakeBook.debugTrashFilePath = null;
      MistakeBook.instance.debugReset();
      FirstRunStore.debugFilePath = null;
      FirstRunStore.instance.debugReset();
      if (tmp.existsSync()) tmp.deleteSync(recursive: true);
    });

    testWidgets('错因分布 + 高频考点 + 代表题', (tester) async {
      MistakeBook.instance.add(
          stem: '9331 变式：AaBb 自交，求 aabb 占比',
          userAnswer: '1/4',
          correctAnswer: '1/16',
          errorType: MistakeErrorType.calculation,
          subjectArea: '自由组合定律');
      MistakeBook.instance.add(
          stem: '概念：等位基因的定义',
          userAnswer: '相同基因',
          correctAnswer: '控制相对性状的基因',
          errorType: MistakeErrorType.concept,
          subjectArea: '遗传因子的发现');
      MistakeBook.instance.add(
          stem: '概念：显性性状判断',
          userAnswer: 'F1 未表现的性状',
          correctAnswer: 'F1 表现的性状',
          errorType: MistakeErrorType.concept,
          subjectArea: '遗传因子的发现');
      MistakeBook.instance.debugFlushSave();

      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
          MaterialApp(home: DashboardPage(onOpenTool: (_) {})));
      await tester.pumpAndSettle();
      await tester.tap(find.text('老师工具'));
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(find.text('班级共性错'), 250,
          scrollable: find.byType(Scrollable).first);
      // 错因分布 = displayName 与计数两个 widget 并排呈现。
      expect(find.text('概念错'), findsOneWidget, reason: '错因分布按枚举序呈现');
      expect(find.text('计算错'), findsOneWidget);
      expect(find.text('2 道'), findsOneWidget, reason: '概念错计数');
      expect(find.text('1 道'), findsOneWidget, reason: '计算错计数');
      expect(find.textContaining('高频考点：'), findsOneWidget);
      expect(find.textContaining('遗传因子的发现 ×2'), findsOneWidget,
          reason: '高频考点 top3 带计数');
      expect(find.textContaining('典型题：'), findsOneWidget,
          reason: '占比最高错因的代表题题干');
    });

    testWidgets('空数据空态（默认本周口径）', (tester) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
          MaterialApp(home: DashboardPage(onOpenTool: (_) {})));
      await tester.pumpAndSettle();
      await tester.tap(find.text('老师工具'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text('班级共性错'), 250,
          scrollable: find.byType(Scrollable).first);
      // R7 #7：默认「本周」口径——空书时给切换指路。
      expect(find.textContaining('本周还没有新错题'), findsOneWidget);
      // 切「全部」→ 通用空态（chip 在视口下缘，先滚入）。
      await tester.ensureVisible(find.text('全部'));
      await tester.pump();
      await tester.tap(find.text('全部'));
      await tester.pumpAndSettle();
      expect(find.textContaining('暂无错题数据'), findsOneWidget);
    });
  });

  group('讲题回放补齐（cross_mono / cross_sex_linked）', () {
    setUp(() {
      ModuleFillBus.resetForTest();
      // App 级常驻目标（本组不依赖，registerAppLevelModuleTargets 里
      // 不含计算器 tab 目标——那些跟计算器页 initState 走）。
    });

    tearDown(() => ModuleFillBus.resetForTest());

    testWidgets('注册形态 + fill 直达单基因 tab 回填即算', (tester) async {
      tester.view.physicalSize = const Size(1600, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(const MaterialApp(
          home: CrossCalculatorPage()));
      await tester.pumpAndSettle();

      final mono = ModuleFillBus.targetOf('cross_mono');
      expect(mono, isNotNull, reason: '计算器页 initState 注册');
      expect(mono!.label, '遗传计算器·单基因');
      final sex = ModuleFillBus.targetOf('cross_sex_linked');
      expect(sex, isNotNull);
      expect(sex!.label, '遗传计算器·伴性遗传');

      // fill → 切 tab + 回填 + 即算（3:1 出现在单基因结果区）。
      ModuleFillBus.navigator = (_) {};
      expect(ModuleFillBus.fill('cross_mono', {'p1': 'Aa', 'p2': 'Aa'}),
          isTrue);
      await tester.pumpAndSettle();
      expect(find.textContaining('3:1'), findsWidgets,
          reason: 'Aa×Aa 完全显性 → 3:1');
    });

    testWidgets('伴性 fill：XAXa × XAY → 女儿/儿子表型区呈现', (tester) async {
      tester.view.physicalSize = const Size(1600, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(const MaterialApp(
          home: CrossCalculatorPage()));
      await tester.pumpAndSettle();

      ModuleFillBus.navigator = (_) {};
      expect(
          ModuleFillBus.fill(
              'cross_sex_linked', {'p1': 'XAXa', 'p2': 'XAY'}),
          isTrue);
      await tester.pumpAndSettle();
      // 结果卡 trailing 呈现双亲基因型；空态「等待计算」退场。
      expect(find.textContaining('♀ XAXa × ♂ XAY'), findsOneWidget,
          reason: '伴性计算完成，结果卡呈现');
      expect(find.text('等待计算：结果将在这里展开'), findsNothing);
    });
  });

  group('拍题原图随 fill 展示（核对识别结果）', () {
    // 1×1 透明 PNG 的 base64（解码/渲染冒烟足够）。
    const pngB64 =
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==';

    test('stage → take 一次性语义', () {
      ModuleFillBus.resetForTest();
      ModuleFillBus.stageScanImage(pngB64);
      expect(ModuleFillBus.takePendingScanImage(), pngB64);
      expect(ModuleFillBus.takePendingScanImage(), isNull,
          reason: '取走后清空（防串图）');
      ModuleFillBus.resetForTest();
    });

    testWidgets('遗传病页 initState 消费 → 原图卡展示 → 关闭',
        (tester) async {
      ModuleFillBus.resetForTest();
      app_main.registerAppLevelModuleTargets();
      ModuleFillBus.stageScanImage(pngB64);
      await tester.pumpWidget(
          const MaterialApp(home: GeneticDiseasePage()));
      await tester.pumpAndSettle();

      // v2.19.29（M3.1 老师 P1-3）：原图挪到「系谱推断」tab 顶部——
      // 识别系谱自动跳该 tab，原图须与成员同屏可对照。
      await tester.tap(find.text('系谱推断'));
      await tester.pumpAndSettle();
      expect(find.textContaining('拍题原图（核对识别结果）'), findsOneWidget);
      expect(ModuleFillBus.takePendingScanImage(), isNull,
          reason: 'initState 已消费');

      // 关闭按钮 → 原图卡消失。
      await tester.scrollUntilVisible(
          find.text('核对完成，关闭原图'), 200,
          scrollable: find.byType(Scrollable).first);
      await tester.tap(find.text('核对完成，关闭原图'));
      await tester.pumpAndSettle();
      expect(find.textContaining('拍题原图'), findsNothing);
      ModuleFillBus.resetForTest();
    });
  });

  group('AI 总览 prompt（今日到期行动信号）', () {
    late Directory tmp;

    setUp(() {
      tmp = Directory.systemTemp.createTempSync('v214_ai_test');
      MistakeBook.debugFilePath = '${tmp.path}/m.json';
      MistakeBook.debugTrashFilePath = '${tmp.path}/m.trash.json';
      MistakeBook.instance.debugReset();
      addTearDown(() => MistakeBook.instance.debugFlushSave());
    });

    tearDown(() {
      MistakeBook.debugFilePath = null;
      MistakeBook.debugTrashFilePath = null;
      MistakeBook.instance.debugReset();
      if (tmp.existsSync()) tmp.deleteSync(recursive: true);
    });

    test('buildOverviewPrompt 含「今日到期 N 道」', () {
      MistakeBook.instance.add(
          stem: '题干A',
          userAnswer: 'x',
          correctAnswer: 'y',
          errorType: MistakeErrorType.concept,
          subjectArea: 'T');
      final p = MistakeBookAi.buildOverviewPrompt(MistakeBook.instance.entries);
      expect(p, contains('今日到期 1 道'),
          reason: '新错题未复习 = 立即到期，prompt 带行动信号');
      expect(p, contains('已掌握 0 / 复习中 0 / 未复习 1'));
    });
  });
}
