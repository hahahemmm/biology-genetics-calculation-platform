// dark_full_scan_test.dart —— 2.2 批次5：导航页深色模式全量截图
//
// 浅色巡检（page_scan_test）的镜像：逐页单泵（AppTheme.dark() 包壳 +
// AppColors.sync(dark)），录 golden 供像素级亮度验证黑底黑字。
//
// 为什么不泵整个 BiologyApp 逐页切导航：ThemeController.load() 是真实
// 文件 I/O，其完成后的 notify 会在数帧后把 debugSetMode(dark) 覆盖回
// 磁盘值（本机磁盘存 light → 巡检中途翻浅色，批次5 实锤且翻页点随机）。
// 逐页单泵完全绕开 ThemeController，确定性深色。
// 运行：flutter test --update-goldens test/dark_full_scan_test.dart
// 产物：test/goldens/dark_scan_pXX_<label>.png
import 'dart:io';

import 'package:biology/services/ai_client.dart';
import 'package:biology/pages/big_question_cards_page.dart';
import 'package:biology/pages/genetic_disease_page.dart';
import 'package:biology/pages/variation_page.dart';
import 'package:biology/pages/cross_calculator_page.dart';
import 'package:biology/pages/curriculum_page.dart';
import 'package:biology/pages/dashboard_page.dart';
import 'package:biology/pages/evolution_page.dart';
import 'package:biology/pages/genetic_pedigree_page.dart';
import 'package:biology/pages/home_page.dart';
import 'package:biology/pages/knowledge_graph_page.dart';
import 'package:biology/pages/molecular_page.dart';
import 'package:biology/pages/ploidy_page.dart';
import 'package:biology/pages/settings_page.dart';
import 'package:biology/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'golden_fonts.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  tearDown(() {
    AppColors.sync(Brightness.light); // 复位，防污染其他测试
  });

  testWidgets('导航页深色模式截图（真实字体，逐页单泵）', (tester) async {
    // v2.19.31（golden_fonts 移植）：同 light_full_scan。
    await loadGoldenFonts();
    assertMaterialIconsLoaded();
    assertMonoLoaded();

    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    AppColors.sync(Brightness.dark);

    // 设置页 golden 隔离：同 light_full_scan，锁死 AI 配置防本机配置漂移。
    AiSettingsStore.debugConfig = AiConfig.presetMinimax;
    addTearDown(() => AiSettingsStore.debugConfig = null);

    final pages = <String, Widget>{
      '00_首页': DashboardPage(onOpenTool: (_) {}),
      '01_遗传图谱': GeneticPedigreePage(
          navCollapsed: false, onNavPressed: () {}),
      '02_9331': CrossCalculatorPage(
          navCollapsed: false, onNavPressed: () {}),
      '03_图谱': KnowledgeGraphPage(
          navCollapsed: false, onNavPressed: () {}),
      '04_课标': const CurriculumPage(),
      '05_分子': const MolecularPage(),
      '06_进化': const EvolutionPage(),
      '07_倍性': const PloidyPage(),
      '08_设置': SettingsPage(navCollapsed: false, onNavPressed: () {}),
      '09_关于': HomePage(navCollapsed: false, onNavPressed: () {}),
      // v2.19.24：大题套路卡（主导航 index 8；扫描编号续尾，不动既有命名）
      '10_大题套路卡': const BigQuestionCardsPage(),
      // v2.19.31 导航扩项（扫描编号续尾）。
      '11_变异': VariationPage(),
      '12_遗传病': GeneticDiseasePage(),
    };

    for (final entry in pages.entries) {
      await tester.pumpWidget(
          MaterialApp(theme: AppTheme.dark(), home: entry.value));
      await tester.pump();
      // 课标/图谱等页有 rootBundle 真实异步 I/O，放行让数据就绪
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 400));
      });
      await tester.pump();
      // v2.19.30：设置页 _loadConfig 的 await 在首帧后填充输入框，
      // label 浮动动画被上一行 pump 抓拍中间态（叠影）；批次时序下
      // 帧位置抖动 → golden 假回归。多 pump 一帧等动画落定。
      if (entry.value is SettingsPage) {
        await tester.pump(const Duration(milliseconds: 300));
      }
      await expectLater(find.byType(entry.value.runtimeType),
          matchesGoldenFile('goldens/dark_scan_p${entry.key}.png'));
    }
  });
}
