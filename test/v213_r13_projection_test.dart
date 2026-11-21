// v213_r13_projection_test.dart —— 投影 / 课堂放映场景专项（R13 移植版）
//
// 【来源】分离工作区（AI 全自主线程）R13-1 批次精华移植：原仓库
// R1~R12 全部围绕「手机窄屏 + 桌面宽屏」，投影档位从未被专项走查；
// 本文件把「课堂大屏两档分辨率 × 全部导航页」钉成 golden + 量测回归网。
//
// 【取样方式：泵真实 BiologyApp，不复刻 builder】课堂模式的一切都
// 发生在 MaterialApp.builder 注入的 MediaQuery.textScaler + 按钮主题上；
// 复刻 builder 只对副本负责，main.dart 真值漂了照样全绿（假绿族）。
//
// 【确定性】用户数据注入隔离：FirstRunStore（临时文件，老师 persona）、
// ThemeController（debugSetMode light）、AiSettingsStore（debugConfig）、
// MistakeBook（debugFilePath）。
//
// 运行：flutter test --update-goldens test/v213_r13_projection_test.dart
// 产物：test/goldens/proj_*.png
import 'dart:io';

import 'package:biology/services/ai_client.dart';
import 'package:biology/main.dart';
import 'package:biology/pages/genetic_pedigree_page.dart';
import 'package:biology/pages/settings_page.dart' show AiSettingsStore;
import 'package:biology/state/app_state.dart';
import 'package:biology/state/first_run_store.dart';
import 'package:biology/state/mistake_book.dart';
import 'package:biology/state/present_mode_controller.dart';
import 'package:biology/state/theme_controller.dart';
import 'package:biology/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
// v2.22.0：套路卡改用数字键 9 直达 pageIndex 8（LogicalKeyboardKey 在
// services 里，material 不导出）。
import 'package:flutter/services.dart';
import 'golden_fonts.dart';
import 'package:flutter_test/flutter_test.dart';

/// 投影两档分辨率：1920×1080 = 教室主流投影/交互大屏原生分辨率；
/// 1280×720 = 老投影仪 / 部分希沃一体机信号上限。两档都必须过。
const Map<String, Size> kProjectedSizes = <String, Size>{
  '1920': Size(1920, 1080),
  '1280': Size(1280, 720),
};

void main() {
  late Directory tmp;
  late String firstRunFile;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('biology_r13_projection');
    final sep = Platform.pathSeparator;
    firstRunFile = '${tmp.path}${sep}first_run.json';
    // 老师 persona + 非首启：不弹角色 dialog，dashboard 走老师分支
    //（错题本隐藏、老师工具卡在场），与课堂演示真实画面一致。
    File(firstRunFile).writeAsStringSync('{"role":"teacher"}');
    FirstRunStore.debugFilePath = firstRunFile;
    FirstRunStore.debugWebStorage = null;
    FirstRunStore.debugForceIsWebStorage = false;
    FirstRunStore.instance.debugReset();
    // 2026-10-29：主题档 / 课堂 hc / AppState 偏好也必须落在本用例临时目录。
    // 原来 startProjected 的 debugEnsureLoaded 走默认路径，会读开发机真实
    // `~/.biology_app/{theme_mode,present_mode}.json`（真实 hc=true ⇒ 高对比
    // 配色；真实教师机 laser 残留 ⇒ 快捷条状态漂移），golden 随日常使用漂。
    ThemeController.debugFilePath = '${tmp.path}${sep}theme.json';
    PresentModeController.debugFilePath = '${tmp.path}${sep}present.json';
    AppState.debugFilePath = '${tmp.path}${sep}app_state.json';
    ThemeController.instance.debugReset();
    PresentModeController.instance.debugReset();
    AppState.instance.debugResetPrefs();
    MistakeBook.debugFilePath = '${tmp.path}${sep}m.json';
    MistakeBook.debugTrashFilePath =
        '${tmp.path}${sep}m.trash.json';
    MistakeBook.instance.debugReset();
  });

  tearDown(() {
    PresentModeController.instance.debugReset();
    ThemeController.instance.debugSetMode(ThemeMode.system);
    ThemeController.instance.debugReset();
    FirstRunStore.debugFilePath = null;
    FirstRunStore.debugWebStorage = null;
    FirstRunStore.debugForceIsWebStorage = null;
    FirstRunStore.instance.debugReset();
    MistakeBook.debugFilePath = null;
    MistakeBook.debugTrashFilePath = null;
    MistakeBook.instance.debugReset();
    ThemeController.debugFilePath = null;
    PresentModeController.debugFilePath = null;
    AppState.debugFilePath = null;
    AppState.instance.debugResetPrefs();
    AiSettingsStore.debugConfig = null;
    AppColors.sync(Brightness.light);
    // best-effort：Windows 上临时文件可能仍被句柄占着，清理失败不该判红。
    try {
      if (tmp.existsSync()) tmp.deleteSync(recursive: true);
    } catch (_) {}
  });

  void setView(WidgetTester tester, Size size) {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  /// v2.19.31（golden_fonts 移植）：统一 harness 全装（icon+CJK+mono），
  /// 与 full_scan 同款渲染。
  Future<void> loadCjkFonts() async {
    await loadGoldenFonts();
    assertMaterialIconsLoaded();
    assertMonoLoaded();
  }

  /// 以「课堂大屏 + 浅色 + 指定分辨率」启动真实 App。
  Future<void> startProjected(WidgetTester tester, Size size,
      {bool highContrast = false}) async {
    setView(tester, size);
    await loadCjkFonts();
    // load() 是真实文件 I/O，必须 runAsync 放行，否则 FakeAsync 里
    // await 挂死。先落地再 debugSet，才不会被 load() 完成后的 notify
    // 覆盖回磁盘值。
    await tester.runAsync(() async {
      await ThemeController.instance.debugEnsureLoaded();
      await PresentModeController.instance.debugEnsureLoaded();
    });
    ThemeController.instance.debugSetMode(ThemeMode.light);
    AiSettingsStore.debugConfig = AiConfig.presetMinimax;
    PresentModeController.instance.debugSetHighContrast(highContrast);
    PresentModeController.instance.debugSetEnabled(true);
    await tester.pumpWidget(const BiologyApp());
    await tester.pumpAndSettle();
  }

  // ═══════════════════════════════════════════════════════════════
  // 一、投影 golden（课堂大屏像素级证据）
  // ═══════════════════════════════════════════════════════════════

  for (final entry in kProjectedSizes.entries) {
    testWidgets('投影 ${entry.key} 首页（课堂大屏）', (tester) async {
      await startProjected(tester, entry.value);
      await expectLater(
        find.byType(HomeShell),
        matchesGoldenFile('goldens/proj_${entry.key}_p00_首页.png'),
      );
    });
  }

  testWidgets('投影 1920 首页（课堂大屏 + 高对比配色）', (tester) async {
    // 高对比是投影专用档（投影仪泛白吃对比度）——必须有像素基线，
    // 否则「高对比开关有没有真的变白底近黑字」永远靠肉眼。
    await startProjected(tester, const Size(1920, 1080), highContrast: true);
    await expectLater(
      find.byType(HomeShell),
      matchesGoldenFile('goldens/proj_1920_p00_首页_高对比.png'),
    );
  });

  testWidgets('投影 1920 · 9331（课堂大屏 · 计算后基因型）', (tester) async {
    // 老师上课最高频一屏：杂交组合分离比。基因型是等宽字体承载，
    // 这张是「基因型在投影尺寸下是不是够大」的像素证据。
    await startProjected(tester, const Size(1920, 1080));
    await tester.tap(find.text('9331'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('计算比例'));
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(HomeShell),
      matchesGoldenFile('goldens/proj_1920_p02_9331.png'),
    );
  });

  testWidgets('投影 1920 · 遗传图谱（课堂大屏 · 计算后）', (tester) async {
    // 系谱页是唯一有侧栏控制面板 + 底栏按钮的页面 = 触控目标最密的
    // 课堂表面。量测网里「侧栏按钮 ≥44px」就在这屏取样。
    await startProjected(tester, const Size(1920, 1080));
    await tester.tap(find.text('遗传图谱'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('计算').first);
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(HomeShell),
      matchesGoldenFile('goldens/proj_1920_p01_遗传图谱.png'),
    );
  });

  // ═══════════════════════════════════════════════════════════════
  // 二、量测断言（把投影门槛钉成回归网）
  // ═══════════════════════════════════════════════════════════════

  testWidgets('R13 量测：课堂大屏正文有效字号 ≥ 24px（10 米外可读线）',
      (tester) async {
    await startProjected(tester, const Size(1920, 1080));
    // 正文 14pt（AppText.body）× PresentModeController.textScale 必须
    // ≥ 24px（present_mode_controller 写着的投影门槛；R13 移植前 ×1.3
    // 只给出 18.2px、缺口 24%，改 ×1.75 → 24.5px）。
    final effective = MediaQuery.of(tester.element(find.byType(HomeShell)))
        .textScaler
        .scale(AppText.body.fontSize!);
    expect(effective, greaterThanOrEqualTo(24.0),
        reason: '课堂大屏正文有效字号应 ≥24px'
            '（实测 ${effective.toStringAsFixed(1)}px）');

    // 真实页面抽样：至少一处正文字号真的落在这个值上——只断言
    // MediaQuery 常量的话，builder 忘了注入也会照样绿。
    final bodyPx = <double>[];
    for (final el in find.byType(Text).evaluate()) {
      final r = el.renderObject;
      if (r is! RenderParagraph) continue;
      final fs = r.text.style?.fontSize;
      if (fs == null || fs != AppText.body.fontSize) continue;
      bodyPx.add(r.textScaler.scale(fs));
    }
    expect(bodyPx, isNotEmpty, reason: '首页应有正文字号可抽样');
    for (final px in bodyPx) {
      expect(px, greaterThanOrEqualTo(24.0));
    }
  });

  testWidgets('R13 量测：系谱侧栏按钮在课堂大屏下 ≥ 44px 触控目标',
      (tester) async {
    await startProjected(tester, const Size(1920, 1080));
    await tester.tap(find.text('遗传图谱'));
    await tester.pumpAndSettle();

    // 按类型遍历侧栏全部按钮（主线程侧栏按钮集与分离线程不同——
    // 按标签逐个点名会在面板重排后失效，按类型遍历覆盖「所有」）。
    final buttons = find.descendant(
      of: find.byType(GeneticPedigreePage),
      matching: find.byWidgetPredicate((w) =>
          w is FilledButton || w is OutlinedButton || w is TextButton),
    );
    expect(buttons, findsWidgets, reason: '系谱页应能定位到按钮集');
    for (final el in buttons.evaluate()) {
      final r = el.renderObject;
      if (r is! RenderBox || !r.hasSize) continue;
      expect(
        r.size.width, greaterThanOrEqualTo(44.0),
        reason: '按钮宽 ${r.size.width.toStringAsFixed(0)} < 44px',
      );
      expect(
        r.size.height, greaterThanOrEqualTo(44.0),
        reason: '按钮高 ${r.size.height.toStringAsFixed(0)} < 44px'
            '（教鞭/手指点不准）',
      );
    }
  });

  for (final entry in kProjectedSizes.entries) {
    testWidgets('R13 量测：投影 ${entry.key} 课堂大屏零溢出（×1.75 后）',
        (tester) async {
      // ×1.75 放大必然挤压布局——把「全部导航页在两档投影分辨率下
      // 零 RenderFlex overflow」钉成回归网：谁再动课堂倍率或某页布局，
      // 第一时间炸在这里。
      final failures = <String>[];
      var pageLabel = '启动';
      final prevOnError = FlutterError.onError;
      FlutterError.onError = (d) {
        final s = d.exceptionAsString();
        if (s.contains('overflowed') || s.contains('OVERFLOW')) {
          failures.add('[$pageLabel] ${s.split('\n').first}');
        } else {
          prevOnError?.call(d);
        }
      };
      addTearDown(() => FlutterError.onError = prevOnError);

      await startProjected(tester, entry.value);

      // 壳层内容子树里的 Focus 节点（main.dart：Shortcuts ▸ Actions ▸
      // Focus(autofocus: true) ▸ content）——数字键送达 Shortcuts 的前提：
      // 键只沿**主焦点的祖先链**冒泡，点完 Rail 后焦点已不在壳层内容子树
      // 里（可能停在 Rail 或页面输入框上），必须显式交回。
      //
      // 节点取法：Focus.of(内容里的 element) —— 最近的祖先 Focus 就是壳层
      // 那颗（Focus 未显式传 focusNode 时节点由 State 持有，widget 上是
      // null，外部拿不到，只能走祖先查询）。
      final shellFocusNode = Focus.of(tester.element(find.byType(IndexedStack)));

      // visited 记账：走完一遍就能证明「13 页全都到过」（而不是只走到
      // 12 页还在假绿）。
      final visited = <int>[];
      int currentIndex() =>
          tester.widget<IndexedStack>(find.byType(IndexedStack)).index ?? -1;

      // 逐个导航页过一遍（首页已在 startProjected 渲染）——**13 页一个不漏**。
      // 1280×720 下课堂模式 rail 项被抬高，末几项在首屏外——rail 已
      // scrollable（v2.19.27 F 组），ensureVisible + tap 有效；
      // 不 ensureVisible 直接 tap 会打空，那一页根本没被走查（假绿）。
      //
      // v2.22.0：套路卡（pageIndex 8）已从主导航撤下独立入口，Rail 上
      // 没有「套路卡」标签 ⇒ 该位置改用**数字键 9 直达**（深链保留）；
      // 其余 12 页仍按 Rail 可见标签原顺序点击，**不依赖任何隐藏标签**。
      Future<void> walk(String nav) async {
        pageLabel = nav;
        // 限定在 Rail 子树内找标签：页面正文里可能也有同名文字
        // （如套路卡正文提到「变异」），不限定会点错地方。
        final f = find
            .descendant(
              of: find.byType(NavigationRail),
              matching: find.text(nav),
            )
            .first;
        await tester.ensureVisible(f);
        await tester.pumpAndSettle();
        await tester.tap(f);
        await tester.pumpAndSettle();
        // rootBundle 异步数据（课标/图谱/教材）放行，否则录到空壳
        await tester.runAsync(() async {
          await Future<void>.delayed(const Duration(milliseconds: 200));
        });
        await tester.pumpAndSettle();
        visited.add(currentIndex());
      }

      // pageIndex 1..7（套路卡之前）：按 Rail 可见标签原顺序点。
      for (final nav in <String>[
        '遗传图谱', '9331', '图谱', '课标', '分子', '进化', '倍性',
      ]) {
        await walk(nav);
      }

      // pageIndex 8 = 套路卡：主导航已无该标签 ⇒ 数字键 9 直达。
      shellFocusNode.requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.digit9);
      // ⚠ 套路卡页有持续动画 ⇒ pumpAndSettle 可能永不落定（10 分钟超时），
      //   故这一页用**有界** pump；其余页仍走 walk() 的 pumpAndSettle。
      await tester.pump(const Duration(milliseconds: 600));
      visited.add(currentIndex());
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 200));
      });
      await tester.pump(const Duration(milliseconds: 200));

      // pageIndex 9..12：继续按 Rail 可见标签原顺序点。
      for (final nav in <String>['变异', '遗传病', '设置', '关于']) {
        await walk(nav);
      }

      // 先把 FlutterError.onError 还原，再做断言——断言失败若被上面的
      // 收集器转发给 prevOnError，框架会报成「onError 未还原」的假象。
      FlutterError.onError = prevOnError;

      expect(
        visited,
        <int>[1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12],
        reason: '投影 ${entry.key}：13 页（含隐藏的套路卡）必须全都走到',
      );
      expect(failures, isEmpty,
          reason: '投影 ${entry.key} 课堂大屏溢出页：\n${failures.join('\n')}');
    });
  }
}
