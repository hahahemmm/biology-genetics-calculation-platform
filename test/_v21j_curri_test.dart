// v2.1k 验收 widget test：
//   ① 3.1.1 description 用 Theme.of(context).colorScheme.onSurface
//      （不依赖 AppColors._dark 全局残留）—— 主修复在 main.dart
//      WidgetsBindingObserver，副修复在 _itemTile 断绝 _dark 影响。
//   ② 工具 chip 浅豆绿底+深绿字+1px teal 边 + softWrap:false + maxLines:1
//   ③ description maxLines:2 防 chip 过长挤压
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:biology/pages/curriculum_page.dart';
import 'package:biology/state/theme_controller.dart';
import 'package:biology/theme.dart';

import 'golden_fonts.dart';

void main() {
  testWidgets('v2.1k 浅色：3.1.1 描述 onSurface 墨灰 + chip 浅绿',
      (tester) async {
    await loadGoldenFonts();
    assertMaterialIconsLoaded();
    assertMonoLoaded();

    AppColors.sync(Brightness.light);
    await tester.binding.setSurfaceSize(const Size(1900, 1200));
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light(),
      home: const CurriculumPage(),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('3.1.1'), findsOneWidget);
    expect(find.textContaining('概述多数生物的基因是DNA分子'),
        findsOneWidget);
    expect(find.textContaining('工具：中心法则页'), findsOneWidget);

    // 关键断言：description 必须用 colorScheme.onSurface
    // 浅色 = 墨灰 0xFF35322C；深色 = 暖米白 0xFFEAE8E1
    final desc = tester.widget<Text>(find.text(
        '概述多数生物的基因是DNA分子的功能片段，有些病毒的基因在RNA分子上'));
    expect(desc.maxLines, 2);
    expect(desc.style?.fontWeight, FontWeight.w500);
    expect(desc.overflow, TextOverflow.ellipsis);
    final cs = AppTheme.light().colorScheme;
    expect(desc.style?.color, cs.onSurface);

    // 工具 chip 文字必须单行
    final chipText = tester.widget<Text>(
        find.text('工具：中心法则页·基因概念卡 →'));
    expect(chipText.maxLines, 1);
    expect(chipText.softWrap, false);
    expect(chipText.overflow, TextOverflow.ellipsis);
    expect(chipText.style?.color, AppColors.tealDark);

    await expectLater(
      find.byType(CurriculumPage),
      matchesGoldenFile('goldens/_v21k_curriculum_light.png'),
    );
  });

  testWidgets('v2.1k 深色：3.1.1 描述 onSurface 暖米白 + chip 亮绿',
      (tester) async {
    await loadGoldenFonts();
    assertMaterialIconsLoaded();
    assertMonoLoaded();

    AppColors.sync(Brightness.dark);
    await tester.binding.setSurfaceSize(const Size(1900, 1200));
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.dark(),
      home: const CurriculumPage(),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('3.1.1'), findsOneWidget);
    expect(find.textContaining('概述多数生物的基因是DNA分子'),
        findsOneWidget);
    expect(find.textContaining('工具：中心法则页'), findsOneWidget);

    final descD = tester.widget<Text>(find.text(
        '概述多数生物的基因是DNA分子的功能片段，有些病毒的基因在RNA分子上'));
    expect(descD.maxLines, 2);
    expect(descD.style?.fontWeight, FontWeight.w500);
    final csD = AppTheme.dark().colorScheme;
    expect(descD.style?.color, csD.onSurface);

    final chipTextD = tester.widget<Text>(
        find.text('工具：中心法则页·基因概念卡 →'));
    expect(chipTextD.maxLines, 1);
    expect(chipTextD.softWrap, false);
    expect(chipTextD.style?.color, AppColors.tealDark);

    await expectLater(
      find.byType(CurriculumPage),
      matchesGoldenFile('goldens/_v21k_curriculum_dark.png'),
    );
  });

  testWidgets('v2.2 主题重写：effectiveBrightness 用户锁定优先，token 实时派生',
      (tester) async {
    // 新语义（v2.2 主题重写）：token 从 effectiveBrightness 实时派生，
    // 不再依赖 notify/rebuild 时序——所以这里直接验证派生结果：
    // ① system 模式跟随平台亮度；② 手动锁 light/dark 时平台亮度切换
    //    不影响有效亮度（用户锁定优先）；③ onPlatformBrightnessChanged
    //    无条件 notify（驱动 rebuild 重绘，语义无害）。
    AppColors.debugClearOverride(); // 防本进程前序用例 sync() override 污染
    addTearDown(() {
      ThemeController.instance.debugSetMode(ThemeMode.system);
      AppColors.debugClearOverride();
    });

    // ① system 模式：跟随平台亮度
    ThemeController.instance.debugSetMode(ThemeMode.system);
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
    expect(ThemeController.instance.effectiveBrightness, Brightness.dark,
        reason: 'system 模式应跟随平台 dark');
    expect(AppColors.isDark, isTrue, reason: 'token 应实时派生为深色');
    expect(AppColors.ink, AppColors.inkD);

    tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
    expect(ThemeController.instance.effectiveBrightness, Brightness.light,
        reason: '平台切 light 后 system 模式应立即跟随');
    expect(AppColors.ink, AppColors.inkL);

    // ② 手动锁 light：平台切 dark 不影响有效亮度（用户锁定优先）
    ThemeController.instance.debugSetMode(ThemeMode.light);
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    expect(ThemeController.instance.effectiveBrightness, Brightness.light,
        reason: '用户锁 light 后不受系统 dark 影响');
    expect(AppColors.ink, AppColors.inkL, reason: 'token 应为浅色墨灰（白底白字灭绝）');

    // ③ onPlatformBrightnessChanged 无条件 notify（驱动 rebuild，无害）
    var notified = false;
    void listener() => notified = true;
    ThemeController.instance.addListener(listener);
    ThemeController.instance.onPlatformBrightnessChanged();
    expect(notified, isTrue, reason: '任何模式都 notify 以驱动 rebuild');
    ThemeController.instance.removeListener(listener);
  });
}
