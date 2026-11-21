// v215_selection_sim_test.dart —— 自然选择模拟选择系数化（v2.13）测试
//
// 守护：
//   引擎（gene_frequency.dart simulateSelection）：
//     1. s=1 完全淘汰 ≡ 旧 cullRecessive:true 语义（q → q/(1+q) 精确值）
//     2. s=0 无选择 → 基因频率恒定
//     3. 教材桦尺蛾参数（s=2/11, q0=0.8）→ 首年 q≈0.7732（S≈22.7%）
//     4. s 越界 / 参数缺失 / 新旧参数冲突 → ArgumentError
//   页面（evolution_page.dart）：
//     5. 预设 chips 填参（教材·桦尺蛾 → 0.8 / 0.18 / 10）
//     6. 开始模拟 → FrequencyCurveChart 渲染 + s 分级解读文案
//   图表（frequency_curve_chart.dart）：
//     7. 空序列不崩；常规序列渲染

import 'package:biology/charts/frequency_curve_chart.dart';
import 'package:biology/engine/gene_frequency.dart';
import 'package:biology/pages/evolution_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('simulateSelection 选择系数化', () {
    test('s=1 完全淘汰：q0=0.5 两代 → 1/3、0.25（与旧 cull 语义一致）', () {
      final r = simulateSelection(
          q0: 0.5, generations: 2, selectionAgainstAa: 1);
      expect(r.selectionS, 1);
      expect(r.qPerGen[1], closeTo(1 / 3, 1e-9));
      expect(r.qPerGen[2], closeTo(0.25, 1e-9));
      // 旧布尔 API 同参同结果（向后兼容）。
      final old = simulateSelection(
          q0: 0.5, generations: 2, cullRecessive: true);
      expect(old.qPerGen[2], r.qPerGen[2]);
    });

    test('s=0 无选择 → q 恒定', () {
      final r = simulateSelection(
          q0: 0.3, generations: 5, selectionAgainstAa: 0);
      expect(r.qPerGen.every((q) => (q - 0.3).abs() < 1e-12), isTrue);
    });

    test('教材桦尺蛾：s=2/11、q0=0.8 → 首年 q≈0.7732（S≈22.7%）', () {
      final r = simulateSelection(
          q0: 0.8, generations: 10, selectionAgainstAa: 2 / 11);
      expect(r.qPerGen[1], closeTo(0.7732, 1e-3));
      expect(r.pPerGen[1], closeTo(0.2268, 1e-3));
      // 选择压方向正确：浅色 a 频率逐代下降。
      expect(r.qPerGen[10] < r.qPerGen[0], isTrue);
    });

    test('s=0.5 中间选择：q0=0.5 首年 = 3/7', () {
      final r = simulateSelection(
          q0: 0.5, generations: 1, selectionAgainstAa: 0.5);
      // (pq + q²(1-s)) / (1 - s·q²) = (0.25+0.125)/(1-0.125) = 3/7
      expect(r.qPerGen[1], closeTo(3 / 7, 1e-9));
    });

    test('s 越界（-0.1 / 1.1）抛 ArgumentError', () {
      expect(
          () => simulateSelection(
              q0: 0.5, generations: 1, selectionAgainstAa: -0.1),
          throwsArgumentError);
      expect(
          () => simulateSelection(
              q0: 0.5, generations: 1, selectionAgainstAa: 1.1),
          throwsArgumentError);
    });

    test('新旧参数同时传且语义冲突 → ArgumentError', () {
      expect(
          () => simulateSelection(
              q0: 0.5,
              generations: 1,
              cullRecessive: true,
              selectionAgainstAa: 0.5),
          throwsArgumentError);
    });

    test('两个强度参数都缺 → ArgumentError', () {
      expect(() => simulateSelection(q0: 0.5, generations: 1),
          throwsArgumentError);
    });

    test('新参数路径下 q0 越界 / 代数 ≤0 → ArgumentError（校验不回退）', () {
      expect(
          () => simulateSelection(
              q0: 0, generations: 3, selectionAgainstAa: 0.5),
          throwsArgumentError);
      expect(
          () => simulateSelection(
              q0: 1, generations: 3, selectionAgainstAa: 0.5),
          throwsArgumentError);
      expect(
          () => simulateSelection(
              q0: 0.5, generations: 0, selectionAgainstAa: 0.5),
          throwsArgumentError);
    });

    test('cullRecessive:false 与 selectionAgainstAa:0 同传（合法兼容组合）', () {
      final r = simulateSelection(
          q0: 0.4,
          generations: 3,
          cullRecessive: false,
          selectionAgainstAa: 0);
      expect(r.selectionS, 0);
      expect(r.qPerGen.every((q) => (q - 0.4).abs() < 1e-12), isTrue);
    });
  });

  group('FrequencyCurveChart', () {
    testWidgets('空序列不崩（绘制空态）', (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
          body: FrequencyCurveChart(series: []),
        ),
      ));
      await tester.pumpAndSettle();
      expect(find.byType(FrequencyCurveChart), findsOneWidget);
    });

    testWidgets('常规序列渲染（图例/刻度走 CustomPainter，不建 widget）',
        (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
          body: FrequencyCurveChart(
            series: [
              FreqSeries(
                  label: 'a 频率',
                  values: [0.8, 0.77, 0.74],
                  color: Colors.brown),
            ],
          ),
        ),
      ));
      await tester.pumpAndSettle();
      // 图表存在且绘制无异常即可——文字在 Canvas 上，find.text 不可见。
      expect(find.byType(FrequencyCurveChart), findsOneWidget);
    });
  });

  testWidgets('进化页：桦尺蛾预设填参 + 开始模拟出图 + 分级解读',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(home: EvolutionPage()));
    await tester.pumpAndSettle();

    // v2.19.21 工作台化：选择模拟在「选择模拟」tab（v2.19.23 其输入
    // 面板宽屏在左栏 / 窄屏回渲染 body 顶部——本测试默认 800 宽为
    // 窄屏，面板随 tab 激活构建）。
    await tester.tap(find.text('选择模拟'));
    await tester.pumpAndSettle();
    expect(find.text('自然选择模拟（逐代基因频率）'), findsOneWidget);
    expect(find.text('选择系数 s（0–1）'), findsOneWidget);

    // 预设 chip 填参（不自动开始）。私有字段跨库不可见（Flutter 无
    // mirrors），参数正确性由下方解读文案行为断言间接守护：
    // 桦尺蛾 s=0.18 → 走「部分选择」分支；无选择 → 走「恒定」分支。
    await tester.tap(find.text('课本·桦尺蛾'));
    await tester.pumpAndSettle();

    // 开始模拟 → 折线图 + 部分选择解读 + 教材对照说明。
    await tester.ensureVisible(find.text('开始模拟'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('开始模拟'));
    await tester.pumpAndSettle();
    expect(find.byType(FrequencyCurveChart), findsOneWidget);
    expect(find.textContaining('部分选择下 a 频率'), findsOneWidget);
    expect(find.textContaining('课本桦尺蛾例题按'), findsOneWidget);

    // 切「无选择」重跑 → 恒等解读。
    await tester.ensureVisible(find.text('无选择'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('无选择'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('开始模拟'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('开始模拟'));
    await tester.pumpAndSettle();
    expect(find.textContaining('基因频率保持不变'), findsOneWidget);
  });
}
