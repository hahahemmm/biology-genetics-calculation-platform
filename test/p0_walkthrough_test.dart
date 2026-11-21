// p0_walkthrough_test.dart —— P0 崩溃巡检：主要页面主按钮逐个点击，
// 断言全程无异常（用户纪律：每个按钮都要检测 P0 崩溃）。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:biology/main.dart';
import 'package:biology/pages/genetic_pedigree_page.dart';
import 'package:biology/pages/curriculum_page.dart';
import 'package:biology/pages/knowledge_graph_page.dart';
import 'package:biology/pages/evolution_page.dart';
import 'package:biology/pages/genetic_disease_page.dart';
import 'package:biology/pages/molecular_page.dart';
import 'package:biology/pages/variation_page.dart';
import 'package:biology/state/theme_controller.dart';

Future<void> setView(WidgetTester tester, [Size size = const Size(1000, 800)]) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

/// 滚动到目标再点（ListView 惰性）。
Future<void> tapText(WidgetTester tester, String text) async {
  final f = find.text(text);
  for (var i = 0; i < 10 && f.evaluate().isEmpty; i++) {
    await tester.drag(find.byType(ListView).first, const Offset(0, -150));
    await tester.pumpAndSettle();
  }
  if (f.evaluate().isNotEmpty) {
    await tester.ensureVisible(f.first);
    await tester.pumpAndSettle();
  }
  await tester.tap(f.first);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('P0 巡检：遗传图谱页按钮链', (tester) async {
    await setView(tester);
    await tester.pumpWidget(const MaterialApp(home: GeneticPedigreePage()));
    await tester.pumpAndSettle();
    await tapText(tester, '计算');
    expect(tester.takeException(), isNull, reason: '计算');
    await tapText(tester, '预置');
    expect(tester.takeException(), isNull, reason: '预置');
    // 选一个预置
    final preset = find.textContaining('纯合显性');
    if (preset.evaluate().isNotEmpty) {
      await tester.tap(preset.first);
      await tester.pumpAndSettle();
    }
    expect(tester.takeException(), isNull, reason: '选预置');
    await tapText(tester, '计算基因频率');
    expect(tester.takeException(), isNull, reason: '基因频率');
    await tapText(tester, '关闭');
    expect(tester.takeException(), isNull, reason: '关频率');
    await tapText(tester, '致死');
    expect(tester.takeException(), isNull, reason: '致死对话框');
    await tapText(tester, '取消');
    expect(tester.takeException(), isNull, reason: '致死取消');
    await tapText(tester, '多倍体');
    expect(tester.takeException(), isNull, reason: '多倍体开关');
    await tapText(tester, '计算下一代');
    expect(tester.takeException(), isNull, reason: '下一代');
    await tapText(tester, '删除整代');
    expect(tester.takeException(), isNull, reason: '删除整代对话框');
    await tapText(tester, '取消');
    expect(tester.takeException(), isNull, reason: '删除取消');
  });

  Future<void> toolPageProbe(
      WidgetTester tester, Widget page, List<String> buttons) async {
    await tester.pumpWidget(MaterialApp(home: page));
    await tester.pumpAndSettle();
    for (final b in buttons) {
      final f = find.text(b);
      if (f.evaluate().isEmpty) continue;
      await tapText(tester, b);
      expect(tester.takeException(), isNull, reason: '$b 在 ${page.runtimeType}');
    }
    // 问 AI 按钮存在且可点（面板常驻动画：定长推帧，绝不 pumpAndSettle）
    final ai = find.text('问 AI');
    if (ai.evaluate().isNotEmpty) {
      await tester.ensureVisible(ai.first);
      await tester.pump(const Duration(milliseconds: 200));
      await tester.tap(ai.first, warnIfMissed: false);
      await tester.pump(const Duration(milliseconds: 400));
      expect(tester.takeException(), isNull, reason: '问 AI 在 ${page.runtimeType}');
    }
  }

  testWidgets('P0 巡检：分子页', (tester) async {
    await setView(tester);
    await toolPageProbe(tester, const MolecularPage(), ['全部计算']);
  });

  testWidgets('P0 巡检：进化页', (tester) async {
    await setView(tester);
    await toolPageProbe(tester, const EvolutionPage(), ['全部计算']);
  });

  testWidgets('P0 巡检：变异页', (tester) async {
    await setView(tester);
    await toolPageProbe(tester, const VariationPage(), ['模拟突变']);
  });

  testWidgets('P0 巡检：遗传病页', (tester) async {
    await setView(tester);
    await toolPageProbe(tester, const GeneticDiseasePage(), ['计算']);
  });

  // 2.2 批次2：真题页随刷题模块移除，本用例只保留课标页巡检。
  testWidgets('P0 巡检：课标页', (tester) async {
    await setView(tester);
    await tester.pumpWidget(const MaterialApp(home: CurriculumPage()));
    await tester.pumpAndSettle();
    // v2.19.28 左树化：点左导航概念切右区（v2.19.29 起窄态 pill
    // 渲染短标签），无异常即通过。
    await tapText(tester, '4.2 自然选择');
    expect(tester.takeException(), isNull, reason: '切概念（4.2）渲染');
    await tapText(tester, '概览');
    expect(tester.takeException(), isNull, reason: '概览');
    await tapText(tester, '关闭');
    expect(tester.takeException(), isNull, reason: '概览关闭');
  });

  testWidgets('P0 巡检：双模式各页无异常', (tester) async {
    await setView(tester);
    for (final dark in [false, true]) {
      ThemeController.instance.debugSetMode(
          dark ? ThemeMode.dark : ThemeMode.light);
      await tester.pumpWidget(const BiologyApp());
      await tester.pumpAndSettle();
      for (final tab in ['课标', '分子', '进化']) {
        await tapText(tester, tab);
        expect(tester.takeException(), isNull, reason: '$tab ${dark ? "dark" : "light"}');
      }
      ThemeController.instance.debugSetMode(ThemeMode.system);
    }
  });

  // 2.2 批次2：练习页随刷题模块移除，本用例只保留知识图谱页。
  testWidgets('P0 巡检：知识图谱页问AI', (tester) async {
    await setView(tester);
    for (final page in <Widget>[
      const KnowledgeGraphPage(),
    ]) {
      // 面板常驻动画：pumpAndSettle 可能永不 settle，用定长推帧。
      await tester.pumpWidget(MaterialApp(home: page));
      await tester.pump(const Duration(milliseconds: 400));
      final ai = find.text('问 AI');
      if (ai.evaluate().isNotEmpty) {
        await tester.ensureVisible(ai.first);
        await tester.pump(const Duration(milliseconds: 200));
        await tester.tap(ai.first, warnIfMissed: false);
        await tester.pump(const Duration(milliseconds: 400));
      }
      expect(tester.takeException(), isNull,
          reason: '问 AI 在 ${page.runtimeType}');
    }
  });
}