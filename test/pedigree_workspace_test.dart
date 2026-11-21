// pedigree_workspace_test.dart —— v2.21.0 系谱工作区视觉模块化回归
//
// 只覆盖本轮呈现层改动（空态 ModuleSurface + 三步骤、画布容器薄壳与
// 页面内 8–12px 外边距、全屏外边距为 0）；引擎/坐标/连线状态机与默认
// 双亲一律不动，故这里不对引擎做任何断言，只复用既有装配（MaterialApp
// + 固定视口 + 点「计算」），不复制复杂状态机。
//
// 运行：flutter test test/pedigree_workspace_test.dart
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:biology/guide/guide_keys.dart';
import 'package:biology/pages/genetic_pedigree_page.dart';
import 'package:biology/pages/widgets/pedigree_canvas.dart';
import 'package:biology/pages/widgets/pedigree_canvas_area.dart';
import 'package:biology/state/history_store.dart';
import 'package:biology/ui/module_surface.dart';

Widget _app() => const MaterialApp(home: GeneticPedigreePage());

/// 既有测试同款装配：固定逻辑视口（dpr=1）+ 页面本体。
/// 窄屏（390）/ 宽屏（1400）都走这一条，不另造状态。
Future<void> _pump(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(_app());
  await tester.pump();
}

/// 底部操作条「计算」（GuideKeys.pedigreeCalc）——比 find.text('计算') 精确：
/// 侧栏与底栏各有一颗同文案按钮。
Future<void> _derive(WidgetTester tester) async {
  await tester.tap(find.byKey(GuideKeys.pedigreeCalc));
  await tester.pumpAndSettle();
}

/// 空态原文案（历史测试与 R8 学生走查依赖，逐字不可改）。
const _emptyTitle = '填入双亲基因型，点击「计算」';
const _afterComputeHint =
    '计算后可：点节点看信息 · 开「连线」配对 · '
    '长按节点收线（多条可选） · 右键空白加样本';

ModuleSurface _surfaceOf(WidgetTester tester, Finder areaFinder) =>
    tester.widget<ModuleSurface>(
      find.descendant(of: areaFinder, matching: find.byType(ModuleSurface)),
    );

void main() {
  setUp(() {
    HistoryStore.debugFilePath =
        '${Directory.systemTemp.createTempSync('biology_ws_').path}/history.json';
  });
  tearDown(() => HistoryStore.debugFilePath = null);

  testWidgets('空态：ModuleSurface 薄壳 + 01/02/03 三步骤 + 原文案（390 窄屏）', (
    tester,
  ) async {
    await _pump(tester, const Size(390, 800));
    expect(tester.takeException(), isNull, reason: '390 宽空态零溢出');

    expect(
      find.text(_emptyTitle),
      findsOneWidget,
      reason: '空态标题逐字保留（pedigree_history_test 同断言）',
    );
    expect(find.text(_afterComputeHint), findsOneWidget, reason: '计算后提示全文逐字保留');

    // 薄壳：空态只有一个 ModuleSurface（不层叠卡片）；画布尚未构建。
    final surface = find.byType(ModuleSurface);
    expect(surface, findsOneWidget, reason: '空态是单层薄壳');
    expect(find.byType(PedigreeCanvas), findsNothing, reason: '未计算无画布');

    // 步骤层只作说明：三块步骤标签都在空态薄壳内、各一枚。
    for (final label in ['01 输入', '02 计算', '03 连线']) {
      expect(
        find.descendant(of: surface, matching: find.text(label)),
        findsOneWidget,
        reason: '步骤「$label」在空态内且唯一',
      );
    }

    // 空态不遮底栏：薄壳底缘在「计算」按钮顶缘之上（课堂/手机可达）。
    final surfaceRect = tester.getRect(surface);
    final calcRect = tester.getRect(find.byKey(GuideKeys.pedigreeCalc));
    expect(
      surfaceRect.bottom,
      lessThanOrEqualTo(calcRect.top),
      reason: '空态不覆盖底部操作条',
    );
  });

  testWidgets('空态不劫持 find.text(\'计算\').first：窄屏首个匹配仍是真按钮', (tester) async {
    // 回归：空态若出现与按钮逐字相同的独立 Text('计算')，窄屏树序里它排在
    // 侧栏/底栏之前，`.first` 会点到空态上 —— 点下去毫无反应（本轮实测
    // pedigree_2_1_tools_test 三连红的根因）。步骤标签因此写成「02 计算」。
    await _pump(tester, const Size(390, 800));
    await tester.tap(find.text('计算').first);
    await tester.pumpAndSettle();
    expect(
      find.byType(PedigreeCanvas),
      findsOneWidget,
      reason: '.first 命中的是真实按钮，计算成功',
    );
  });

  testWidgets('空态：1400 宽屏零溢出，内容最大宽约 680（画布本体不受限）', (tester) async {
    await _pump(tester, const Size(1400, 900));
    expect(tester.takeException(), isNull, reason: '1400 宽空态零溢出');
    expect(find.text(_emptyTitle), findsOneWidget);

    final w = tester.getSize(find.byType(ModuleSurface)).width;
    expect(w, closeTo(680, 0.5), reason: '空态内容最大宽 680，不铺满画布区');
    // 空态薄壳窄于可用区 → 窄屏不会因 maxWidth 挤压（Wrap 兜底）。
    expect(w, lessThan(1400));
  });

  testWidgets('窄屏点底栏「计算」→ 空态不被遮挡、可进入画布', (tester) async {
    await _pump(tester, const Size(390, 800));
    await _derive(tester);
    expect(find.byType(PedigreeCanvas), findsOneWidget, reason: '计算后出画布');
    expect(find.text(_emptyTitle), findsNothing, reason: '空态已切换');
    expect(tester.takeException(), isNull, reason: '390 宽计算后零溢出');
  });

  testWidgets('计算后：画布容器为无标题薄壳，10px 外边距，画布与连线动作仍在', (tester) async {
    await _pump(tester, const Size(1400, 900));
    await _derive(tester);
    expect(tester.takeException(), isNull, reason: '1400 宽计算后零溢出');

    final areaFinder = find.byType(PedigreeCanvasArea);
    expect(areaFinder, findsOneWidget, reason: '页面内嵌画布区唯一');
    final area = tester.widget<PedigreeCanvasArea>(areaFinder);
    expect(area.fullscreen, isFalse);

    final surface = _surfaceOf(tester, areaFinder);
    expect(surface.title, isNull, reason: '画布容器不带标题，不占画布高度');
    expect(
      surface.padding,
      EdgeInsets.zero,
      reason: 'padding 为 0，画布本体尺寸不被薄壳改写',
    );
    final margin = surface.margin as EdgeInsets;
    expect(margin.left, inInclusiveRange(8, 12), reason: '页面内左边距 8–12');
    expect(margin.right, inInclusiveRange(8, 12), reason: '页面内右边距 8–12');

    expect(find.byType(PedigreeCanvas), findsOneWidget, reason: '画布本体仍在');
    final canvas = tester.widget<PedigreeCanvas>(find.byType(PedigreeCanvas));
    expect(canvas.nodes, isNotEmpty, reason: '计算产出未被薄壳影响');

    // 连线动作链仍在：底栏 segmented「连线」→ 画布提示切到连线模式。
    expect(find.text('连线'), findsOneWidget, reason: '底栏连线入口仍在');
    await tester.tap(find.text('连线'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('连线模式'),
      findsOneWidget,
      reason: '进入连线模式（提示胶囊文案切换）',
    );

    // 底栏其余动作与主按钮保留（视觉薄壳不动按钮/阈值）。
    for (final label in ['添加家族', '添加样本', '删除整代', '计算下一代', '计算']) {
      expect(find.text(label), findsWidgets, reason: '「$label」入口仍在');
    }
  });

  testWidgets('全屏 Dialog：画布容器外边距为 0（不收缩全屏可点区）', (tester) async {
    // 1000 宽：占位式侧栏（>=900），「全屏」文字入口在侧栏画布区
    // （与 pedigree_ui_test 的全屏用例同一装配）。
    await _pump(tester, const Size(1000, 800));
    await _derive(tester);

    await tester.ensureVisible(find.text('全屏'));
    await tester.pump();
    await tester.tap(find.text('全屏'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull, reason: '全屏双实例共存无异常');

    final areas = tester
        .widgetList<PedigreeCanvasArea>(find.byType(PedigreeCanvasArea))
        .toList();
    expect(areas.length, 2, reason: '内嵌 + 全屏 Dialog 两个画布区');

    final fullscreenArea = areas.firstWhere((a) => a.fullscreen);
    final inlineArea = areas.firstWhere((a) => !a.fullscreen);

    final fsSurface = _surfaceOf(tester, find.byWidget(fullscreenArea));
    expect(fsSurface.margin, EdgeInsets.zero, reason: '全屏外边距必须为 0');
    expect(fsSurface.padding, EdgeInsets.zero);

    final inlineSurface = _surfaceOf(tester, find.byWidget(inlineArea));
    final inlineMargin = inlineSurface.margin as EdgeInsets;
    expect(
      inlineMargin.left,
      inInclusiveRange(8, 12),
      reason: '页面内嵌保持 8–12px 外边距，全屏才归零',
    );

    expect(find.byType(PedigreeCanvas), findsNWidgets(2));
  });
}
