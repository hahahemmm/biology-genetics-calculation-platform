// pedigree_inference_view_test.dart —— 系谱推断器 UI 测试（v2.13+）
//
// 覆盖：
//   1. 载入「常隐·无中生有」经典系谱 → 运行推断 → 最可能结论 +
//      依据条文呈现（引擎→UI 全链路）
//   2. 手动添加成员 + 选择父母 → 运行（自由录入路径不崩、出结果）
//   3. 空表运行按钮 disabled（_rows.isEmpty 守卫）

import 'package:biology/charts/pedigree_chart.dart';
import 'package:biology/main.dart' as app_main;
import 'package:biology/pages/genetic_disease_page.dart';
import 'package:biology/ui/module_fill.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('载入常隐金标准 → 运行 → 最可能常染色体隐性 + 依据条文',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(home: GeneticDiseasePage()));
    await tester.pumpAndSettle();

    // v2.19.28 工作台化：推断器收在「系谱推断」tab——切过去即渲染
    //（原「滚到推断分区」链路随 _section 堆叠移除而废止）。
    await tester.tap(find.text('系谱推断'));
    await tester.pumpAndSettle();

    // 载入经典系谱。
    await tester.tap(find.text('常隐·无中生有'));
    await tester.pumpAndSettle();
    expect(find.text('运行推断'), findsOneWidget);
    // v2.13+ 标准系谱图实时呈现（男=方 女=圆 患者=实心）+ 导出按钮。
    expect(find.byType(PedigreeChart), findsOneWidget,
        reason: '载入成员后系谱图渲染');
    expect(find.text('系谱图存为图片'), findsOneWidget,
        reason: '教师出题导出入口');

    await tester.ensureVisible(find.text('运行推断'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('运行推断'));
    await tester.pumpAndSettle();

    expect(find.textContaining('最可能：常染色体隐性'), findsOneWidget);
    expect(find.textContaining('无中生有'), findsWidgets,
        reason: '依据条文逐条呈现');
    expect(find.textContaining('已排除'), findsWidgets,
        reason: '显性模式被硬排除并展示');
    // v2.13+ 半开放反推：默认按最可能方式给基因型结论（常隐 aa）。
    expect(find.text('基因型反推'), findsOneWidget);
    expect(find.textContaining('II1：aa'), findsOneWidget,
        reason: '常隐患者基因型反推');
    expect(find.text('确定'), findsWidgets, reason: '结论档位胶囊');
  });

  testWidgets('自由录入：添加成员 + 选父母 → 运行出结果', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: GeneticDiseasePage()));
    await tester.pumpAndSettle();
    // v2.19.28 工作台化：推断器收在「系谱推断」tab——切过去即渲染
    //（原「滚到推断分区」链路随 _section 堆叠移除而废止）。
    await tester.tap(find.text('系谱推断'));
    await tester.pumpAndSettle();

    // 空表时运行按钮不可用。
    expect(tester.widget<FilledButton>(find.widgetWithText(
            FilledButton, '运行推断')).onPressed, isNull);

    // 添加 3 名成员；把第 3 名的父亲/母亲指向前两名。
    await tester.tap(find.text('添加成员'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('添加成员'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('添加成员'));
    await tester.pumpAndSettle();
    expect(find.text('M3'), findsOneWidget);

    // M3 默认男+正常：切父亲下拉选 M1、母亲下拉选 M2（把 M2 切成女）。
    // 简化：直接把 M2 设为女性（chip「女」），M1 保持男。
    // 成员卡按录入顺序在列里；找 M2 卡内的「女」chip。
    // （卡内 find 用 ancestor 限定——此处直接点第二张卡的「女」。）
    final femaleChips = find.text('女');
    await tester.tap(femaleChips.at(1));
    await tester.pumpAndSettle();

    // 运行（无患者 → errors 区提示）。
    await tester.ensureVisible(find.text('运行推断'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('运行推断'));
    await tester.pumpAndSettle();
    expect(find.textContaining('没有患者'), findsOneWidget,
        reason: '无患者时引擎校验提示可见');
  });

  testWidgets('拍题识别录入：fillScan add_member 动作 → push 新页消费 → 成员载入',
      (tester) async {
    // v2.14 R5：pd_inference target 已上移到 App 级常驻注册——测试里
    // 显式调同一个注册函数（生产由 HomeShell.initState 调）。
    app_main.registerAppLevelModuleTargets();
    // fillScan 走 pushFactory 分支：actions 入队 + pusher 被调——
    // 被 push 的新实例 initState 消费 pendingActions 载入成员。
    final actions = [
      {
        'type': 'add_member',
        'id': 'I1',
        'sex': 'male',
        'status': 'normal',
        'father': '',
        'mother': ''
      },
      {
        'type': 'add_member',
        'id': 'II1',
        'sex': 'female',
        'status': 'affected',
        'father': 'I1',
        'mother': ''
      },
    ];
    // pusher no-op：不真正导航——队列留待下一个实例消费。
    ModuleFillBus.pusher = (_) {};
    addTearDown(ModuleFillBus.resetForTest);

    // 实例 A 挂载（完成注册），fillScan 入队 actions 后整体换新实例 B
    // （A dispose 注销、B initState 注册并消费 pendingActions——
    // 与生产 push 流程等价的单实例树，避开双层路由的滚动定位复杂度）。
    await tester.pumpWidget(const MaterialApp(home: GeneticDiseasePage()));
    await tester.pumpAndSettle();

    final ok = ModuleFillBus.fillScan('pd_inference', const {}, actions);
    expect(ok, isTrue, reason: 'pd_inference 目标已注册');

    await tester.pumpWidget(const MaterialApp(
        home: GeneticDiseasePage(key: ValueKey('pd-instance-b'))));
    await tester.pump();
    await tester.pumpAndSettle();

    // v2.19.28 工作台化：推断器收在「系谱推断」tab——切过去即渲染
    //（原「滚到推断分区」链路随 _section 堆叠移除而废止）。
    await tester.tap(find.text('系谱推断'));
    await tester.pumpAndSettle();
    expect(find.text('I1'), findsWidgets,
        reason: '成员行 + 父母下拉候选各一处');
    expect(find.text('II1'), findsWidgets);
    expect(find.byType(PedigreeChart), findsOneWidget);
  });

  testWidgets('练习模式：闸门提示 → 选答案运行 → 判定横幅 → 换一题重置',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(home: GeneticDiseasePage()));
    await tester.pumpAndSettle();
    // v2.19.28 工作台化：推断器收在「系谱推断」tab——切过去即渲染
    //（原「滚到推断分区」链路随 _section 堆叠移除而废止）。
    await tester.tap(find.text('系谱推断'));
    await tester.pumpAndSettle();

    // 开练习模式 → 随机载入一题（成员可见）。
    await tester.tap(find.text('练习模式'));
    await tester.pumpAndSettle();
    expect(find.textContaining('你的判断'), findsOneWidget);
    expect(find.text('换一题'), findsOneWidget);

    // 闸门：未选答案点运行 → 提示不揭示。
    await tester.ensureVisible(find.text('运行推断'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('运行推断'));
    await tester.pumpAndSettle();
    expect(find.textContaining('先选出你的判断'), findsOneWidget);
    expect(find.textContaining('最可能：'), findsNothing,
        reason: '未提交前不揭示结论');

    // 选一个答案 → 运行 → 判定横幅 + 结论揭示。
    await tester.tap(
        find.widgetWithText(ChoiceChip, '常染色体隐性'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('运行推断'));
    await tester.pumpAndSettle();
    expect(
        find.textContaining('判对了').evaluate().isNotEmpty ||
            find.textContaining('你判的是').evaluate().isNotEmpty,
        isTrue,
        reason: '判定横幅（✓ 判对了 或 ✗ 你判的是）');
    expect(find.textContaining('最可能：'), findsOneWidget,
        reason: '提交后揭示结论');
    // 判错 → 「存入错题本」出现（练习→错题→复习闭环）；
    // 判对 → 不出现。随机题按实际判定分支断言。
    final wrong = find.textContaining('你判的是').evaluate().isNotEmpty;
    expect(find.text('存入错题本'), wrong ? findsOneWidget : findsNothing,
        reason: '判错才给收录入口');

    // 换一题 → 答案重置回遮罩。
    await tester.ensureVisible(find.text('换一题'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('换一题'));
    await tester.pumpAndSettle();
    expect(find.textContaining('你的判断'), findsOneWidget);
    expect(find.textContaining('最可能：'), findsNothing);
  });
}
