// _tmp_present_scan_test.dart —— 2.3 课堂模式 ×1.3 字号溢出巡检（临时工具）
//
// 课堂模式（MaterialApp.builder 注入 textScaler 1.3）下，任何写死宽度/
// 不换行的布局都会 RenderFlex 溢出。widget 测试里溢出即抛异常——
// 本测试逐页泵入 ×1.3 缩放环境，炸哪页修哪页。不录 golden。
// 跑法：flutter test test/_tmp_present_scan_test.dart
import 'package:biology/pages/big_question_cards_page.dart';
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
import 'package:flutter_test/flutter_test.dart';
import 'dart:io';

void main() {
  testWidgets('课堂模式 ×1.3 字号下 11 页零溢出', (tester) async {
    // 真实字体（msyh）：Ahem 方块字宽度失真，溢出判定必须真实字体。
    final bytes = File(r'C:\Windows\Fonts\msyh.ttc').readAsBytesSync();
    final data = ByteData.view(bytes.buffer);
    final loader = FontLoader('PingFang SC')..addFont(Future.value(data));
    final loader2 = FontLoader('Microsoft YaHei')..addFont(Future.value(data));
    await loader.load();
    await loader2.load();

    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final pages = <String, Widget>{
      '00_首页': DashboardPage(onOpenTool: (_) {}),
      '01_遗传图谱': GeneticPedigreePage(navCollapsed: false, onNavPressed: () {}),
      '02_9331': CrossCalculatorPage(navCollapsed: false, onNavPressed: () {}),
      '03_图谱': KnowledgeGraphPage(navCollapsed: false, onNavPressed: () {}),
      '04_课标': const CurriculumPage(),
      '05_分子': const MolecularPage(),
      '06_进化': const EvolutionPage(),
      '07_倍性': const PloidyPage(),
      // v2.19.26 修正标签错位（老用户 ⑩）：主导航 8=套路卡 / 9=设置 /
      // 10=关于——原标签 08=设置/09=关于/10=套路卡与 live_scan 修订
      // 互相打架，按标签定位会拍错页。
      '08_大题套路卡': const BigQuestionCardsPage(),
      '09_设置': SettingsPage(navCollapsed: false, onNavPressed: () {}),
      '10_关于': HomePage(navCollapsed: false, onNavPressed: () {}),
    };

    final failures = <String>[];
    for (final entry in pages.entries) {
      final prevOnError = FlutterError.onError;
      final pageErrors = <FlutterErrorDetails>[];
      FlutterError.onError = (d) {
        // 只收集溢出类布局错误，其他原样上抛
        if (d.exceptionAsString().contains('overflowed')) {
          pageErrors.add(d);
        } else {
          prevOnError?.call(d);
        }
      };
      await tester.pumpWidget(MediaQuery(
        data: const MediaQueryData(
            textScaler: TextScaler.linear(1.3)),
        child: MaterialApp(theme: AppTheme.light(), home: entry.value),
      ));
      await tester.pump();
      // 课标/图谱等页有 rootBundle 真实异步 I/O，放行让数据就绪
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 400));
      });
      await tester.pump();
      FlutterError.onError = prevOnError;
      if (pageErrors.isNotEmpty) {
        failures.add('${entry.key}: ${pageErrors.length} 处溢出');
      }
    }
    expect(failures, isEmpty,
        reason: '课堂模式 ×1.3 溢出页：\n${failures.join('\n')}');
  });
}
