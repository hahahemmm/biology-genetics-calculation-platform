// lightwhite_repro_test.dart —— 端到端复现白底白字 bug
//
// 场景：Windows 系统 dark 启动 app → AppColors.sync(dark) → _dark=true
//      → 用户在 app 设置里手动切到浅色模式 → MaterialApp.themeMode=light
//      → ListenableBuilder 重建 → AppColors.sync(light) → _dark=false ✓
//
// 旧 bug 触发条件：app 启动后**仅**系统主题从 dark 切到 light
// （用户没主动切模式，仍是 system 模式）→ onPlatformBrightnessChanged
// 在 system 模式下 notify 修过；但若 mode=light（用户已锁），系统亮度
// 变化时旧代码**不 notify** → ListenableBuilder 不 rebuild → _dark 残留。
//
// 修复：取消 mode 限定，任何模式都 notify。
//
// 本测试用「用户在 system 模式下看 app + 平台亮度变化」模拟该竞态：
import 'package:biology/main.dart';
import 'package:biology/state/theme_controller.dart';
import 'package:biology/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/ready_app.dart';

void main() {
  test('platform 变化 → mode=light 时也必须 notify（防止 _dark 残留）', () {
    final c = ThemeController.instance;
    c.debugSetMode(ThemeMode.light); // 用户已锁浅色
    var notify = 0;
    c.addListener(() => notify++);

    // 模拟系统从 dark 切到 light
    c.onPlatformBrightnessChanged();
    expect(notify, greaterThanOrEqualTo(1),
        reason: '修复前不 notify，ListenableBuilder 不 rebuild，'
            '_dark 残留 → 文字色 token 残留 inkD 米白 → 白底白字');
  });

  test('platform 变化 → mode=dark 时也必须 notify', () {
    final c = ThemeController.instance;
    c.debugSetMode(ThemeMode.dark);
    var notify = 0;
    c.addListener(() => notify++);

    c.onPlatformBrightnessChanged();
    expect(notify, greaterThanOrEqualTo(1),
        reason: '手动 dark 模式同样需要响应平台亮度（虽然逻辑上 _dark 应保持 true）');
  });

  testWidgets('端到端：系统 dark 启动 + 用户切浅色 → _dark=false', (t) async {
    // 模拟系统 dark
    t.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    addTearDown(() => t.platformDispatcher.clearPlatformBrightnessTestValue);

    // 模拟磁盘存 light（已加载完）
    final c = ThemeController.instance;
    c.debugSetMode(ThemeMode.light);

    // v2.2 主题重写：_dark 实时派生自 effectiveBrightness（用户锁 light
    // → 永远 light，与系统亮度无关）。不需要任何 sync 调用。
    expect(AppColors.isDark, isFalse,
        reason: '用户锁定浅色后，token 必须立即反映浅色——不依赖任何 '
            'notify/rebuild/sync 时序');
    expect(AppColors.ink, const Color(0xFF35322C),
        reason: '浅色模式 ink 应是深墨，不是米白');

    // 系统亮度再怎么切也不影响锁定模式
    t.platformDispatcher.platformBrightnessTestValue = Brightness.light;
    c.onPlatformBrightnessChanged();
    await t.pump();
    expect(AppColors.isDark, isFalse);
    expect(AppColors.ink, const Color(0xFF35322C));

    // 跟随系统模式才真正跟随平台亮度
    c.debugSetMode(ThemeMode.system);
    expect(AppColors.isDark, isFalse, reason: 'system + 平台 light → 浅色');
    t.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    expect(AppColors.isDark, isTrue, reason: 'system + 平台 dark → 深色');
    expect(AppColors.ink, const Color(0xFFEAE8E1));

    c.debugSetMode(ThemeMode.light); // 复位
  });

  testWidgets('端到端：dark 首帧后切 light，分子页区块标题必须渲染深墨（const 冻结回归）',
      (t) async {
    // 2026-08-29 最终根因：main.dart 页面列表里 4 个 const 页面实例
    // （课标/分子/进化/倍性）被 canonicalize → Element identical 短路
    // → 主题切换后永不 rebuild → 首帧（system+平台dark）用 inkD 构建的
    //   显式 style 文字永久冻结 = 用户看到的白底白字（且只有这几页中招）。
    // 本用例完整复现该时序：dark 首帧 → 用户锁 light → 导航到分子页 →
    // 断言区块标题的 widget 样式与渲染样式都是浅色墨灰。
    t.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    addTearDown(() => t.platformDispatcher.clearPlatformBrightnessTestValue);
    t.view.physicalSize = const Size(1400, 900);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);

    final c = ThemeController.instance;
    await t.runAsync(() => c.debugEnsureLoaded()); // 真实 I/O，须 runAsync 放行
    c.debugSetMode(ThemeMode.system); // 首帧：system + 平台 dark → ink=inkD
    addTearDown(() => c.debugSetMode(ThemeMode.system));

    await pumpReadyBiologyApp(t);
    // 首帧确认：此时 token 为深色（全部页面已用 inkD 构建）
    expect(AppColors.isDark, isTrue, reason: '首帧 system+平台dark 应为深色');

    // 用户在设置里锁浅色
    c.debugSetMode(ThemeMode.light);
    await t.pumpAndSettle();

    // 导航到分子页（桌面宽屏 Rail 标签）
    final railLabel = find.descendant(
      of: find.byType(NavigationRail),
      matching: find.text('分子'),
    );
    expect(railLabel, findsWidgets, reason: '宽屏应有 Rail 标签「分子」');
    await t.tap(railLabel.first);
    await t.pumpAndSettle();

    // 区块标题：widget 声明样式必须是浅色墨灰
    final title = t.widget<Text>(find.text('DNA 碱基互补计算'));
    expect(title.style?.color, AppColors.inkL,
        reason: 'const 冻结时此处残留 inkD 米白（白底白字）；'
            '修复后页面每帧新建，切浅色后立即拿到 inkL 墨灰');
  });

  testWidgets('端到端：dark 首帧后切 light，9331 页 tab 内容必须渲染深墨（TabBarView children const 冻结回归）',
      (t) async {
    // 2026-08-29 第三轮根因：main.dart 页面列表的 const 修复后，9331 页仍发白——
    // CrossCalculatorPage 的 TabBarView children 列表里 6 个 tab 全是 const 实例，
    // 页面本身 rebuild 时 children identical 短路 → tab 内显式 style 文字永久冻结
    // 首帧 inkD 米白。本用例复现：dark 首帧构建 tab → 锁 light → 断言区块标题。
    t.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    addTearDown(() => t.platformDispatcher.clearPlatformBrightnessTestValue);
    t.view.physicalSize = const Size(1400, 900);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);

    final c = ThemeController.instance;
    await t.runAsync(() => c.debugEnsureLoaded()); // 真实 I/O，须 runAsync 放行
    c.debugSetMode(ThemeMode.system); // 首帧：system + 平台 dark → ink=inkD
    addTearDown(() => c.debugSetMode(ThemeMode.system));

    await pumpReadyBiologyApp(t);
    expect(AppColors.isDark, isTrue, reason: '首帧 system+平台dark 应为深色');

    // 导航到 9331 页（tab 内容在此刻用 inkD 构建）
    final railLabel = find.descendant(
      of: find.byType(NavigationRail),
      matching: find.text('9331'),
    );
    expect(railLabel, findsWidgets, reason: '宽屏应有 Rail 标签「9331」');
    await t.tap(railLabel.first);
    await t.pumpAndSettle();

    // 用户在设置里锁浅色
    c.debugSetMode(ThemeMode.light);
    await t.pumpAndSettle();

    // 区块标题（AppSectionHeader→AppText.sectionTitle，色=ink）必须是浅色墨灰
    final header = t.widget<Text>(find.text('常见 9331 变式速查'));
    expect(header.style?.color, AppColors.inkL,
        reason: 'TabBarView children 为 const 时 identical 短路，tab 内容残留 '
            'inkD 米白（白底白字）；修复后 children 每次新建，切浅色立即拿到 inkL');
  });

  testWidgets('端到端：dark 下从课标页跳 9331（切导航索引），切 light 后目标页必须渲染深墨（_openTool const 冻结回归）',
      (t) async {
    // 2026-08-29 第三轮根因之二：课标页 _openTool 里 8 个工具页全部写成
    // `page = const XxxPage()`，push 进路由后被 canonicalize——路由重建时
    // builder 返回同一 const 实例 → Element identical 短路 → 永不 rebuild，
    // dark 下 push 的页面在切 light 后仍是 inkD 米白。本用例复现完整时序。
    // v2.2 双向跳转修复后：chip 改走 HomeShell 切导航索引（页面内跳转），
    // IndexedStack 页面实例每次 build 新建，本用例继续守护主题刷新链路。
    t.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    addTearDown(() => t.platformDispatcher.clearPlatformBrightnessTestValue);
    // 超高视口：课标列表全量构建，chip 直接可见可点，避免 ListView 懒挂载
    // 滚动链路的脆弱性（scrollUntilVisible 挂载即停 / dragUntilVisible 的
    // ancestor scrollable 匹配在本壳层结构下均不可靠）。
    t.view.physicalSize = const Size(1400, 5200);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);

    final c = ThemeController.instance;
    await t.runAsync(() => c.debugEnsureLoaded());
    c.debugSetMode(ThemeMode.system);
    addTearDown(() => c.debugSetMode(ThemeMode.system));

    await pumpReadyBiologyApp(t);

    // 导航到课标页
    final railLabel = find.descendant(
      of: find.byType(NavigationRail),
      matching: find.text('课标'),
    );
    expect(railLabel, findsWidgets, reason: '宽屏应有 Rail 标签「课标」');
    await t.tap(railLabel.first);
    await t.pumpAndSettle();

    // v2.19.28 左树化：3.3.4 收在关键概念 3.3 下——先点左栏概念。
    await t.tap(find.text('可遗传的变异（突变/重组/染色体变异）'));
    await t.pumpAndSettle();

    // 点击「工具：连锁互换 + 9331 →」chip（3.3.4 条目）
    // v2.19.35（课标深链簇）：该 chip 不再只「切到 9331 默认页签」，而是
    // 数据驱动深链——fill('cross_linkage', {p1,p2,r}) 切导航 + 切到连锁互换
    // 页签 + 真算出结果。本用例的牙齿（主题切换后文字色不冻结）不变：
    // 「亲本型」证明真算出了结果（teal 徽标，只做存在性断言）；
    // 「设定亲本与交换值」是 AppText.sectionTitle（color=AppColors.ink），
    // 承担原来的冻结色断言（与原「常见 9331 变式速查」同族牙齿）。
    final chip = find.textContaining('连锁互换 + 9331');
    expect(chip, findsOneWidget, reason: '超高视口下课标全列表应一次构建');
    await t.tap(chip);
    await t.pumpAndSettle(); // 深链：切导航索引 + 连锁页签 + 真计算（dark 下构建 → inkD）
    expect(find.text('亲本型'), findsWidgets,
        reason: 'chip 应深链到 9331 连锁互换页签并真算出结果（v2.19.35）');
    expect(find.text('设定亲本与交换值'), findsOneWidget,
        reason: '连锁页签专属分区标题（承担冻结色断言的锚点）');

    // 用户在设置里锁浅色（路由页若不 rebuild，文字冻结 inkD）
    c.debugSetMode(ThemeMode.light);
    await t.pumpAndSettle();

    final header = t.widget<Text>(find.text('设定亲本与交换值'));
    expect(header.style?.color, AppColors.inkL,
        reason: '页面实例若被复用（const/闭包缓存），identical 短路 '
            '永不 rebuild，切浅色后残留 inkD 米白；修复后每次新建，立即拿到 inkL');
  });
}
