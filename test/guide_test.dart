// guide_test.dart —— v2.2 新手引导验收
//
// 机制：设置页「开始引导」→ HomeShell 插 GuideOverlay（顶层 Overlay，
// 半透明罩+挖孔高亮）→ 步骤推进伴随页面切换 → 完成/跳过自动关闭。
// 一次性语义：不自动弹出；每次手动开启走一遍；完成后再想看需再点。

import 'package:biology/guide/guide_controller.dart';
import 'package:biology/main.dart';
import 'package:biology/guide/guide_keys.dart';
import 'package:biology/pages/settings_page.dart';
import 'package:biology/state/theme_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/ready_app.dart';

void main() {
  Future<void> pumpApp(WidgetTester t) async {
    t.view.physicalSize = const Size(1400, 900);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    final c = ThemeController.instance;
    await t.runAsync(() => c.debugEnsureLoaded());
    c.debugSetMode(ThemeMode.light);
    addTearDown(() => c.debugSetMode(ThemeMode.system));
    await pumpReadyBiologyApp(t);
  }

  /// v2.20.0：点 Rail 的「设置」——**先滚动再点**。
  ///
  /// Rail 有 13 项，1400×900 下总高超出可视区（「设置」/「关于」在屏外，
  /// 命中点 y > 屏高），直接 tap 会打空：设置页根本没建出来，后续
  /// scrollUntilVisible('开始引导') 立刻 Bad state: No element（不是
  /// 「找不到按钮」，是整页没打开）。生产语义本来就是用户先把 rail 滚到
  /// 目标项再点，所以这里在同一条 rail 的 Scrollable 里 scrollUntilVisible
  /// 后 tap——不放大视口、不删用例、也不依赖 HomeShell 的自动跳转。
  Future<void> tapRailSettings(WidgetTester t) async {
    final settings = find.descendant(
      of: find.byType(NavigationRail),
      matching: find.text('设置'),
    );
    await t.scrollUntilVisible(
      settings.first,
      80,
      scrollable: find
          .descendant(
              of: find.byType(NavigationRail),
              matching: find.byType(Scrollable))
          .first,
    );
    await t.pumpAndSettle();
    await t.tap(settings.first);
    await t.pumpAndSettle();
  }

  Future<void> startGuide(WidgetTester t) async {
    // 导航到设置页点「开始引导」（rail 先滚到「设置」，见 helper 注释）。
    await tapRailSettings(t);
    // v2.19.30：设置页回退单列平铺——「开始引导」在滚动流里，
    // scrollUntilVisible 直达（v2.19.28 分区化的 pill 切换已废止）。
    // v2.3 课堂模式卡加入后「开始引导」可能落到屏外（ListView 懒挂载），
    // 先滚到可见再点；设置页有多个 Scrollable，必须显式指定。
    // v2.19.27：限定 SettingsPage 子树——NavigationRail 开 scrollable
    // 后 rail 自带 Scrollable 抢走了全局 .first 的命中（开始引导滚
    // 进 rail 视口永远失败）。
    await t.scrollUntilVisible(
      find.text('开始引导'),
      200,
      scrollable: find
          .descendant(
              of: find.byType(SettingsPage),
              matching: find.byType(Scrollable))
          .first,
    );
    await t.pumpAndSettle();
    await t.tap(find.text('开始引导'));
    await t.pumpAndSettle();
  }

  testWidgets('引导开启→欢迎步出现→自动切回首页', (t) async {
    await pumpApp(t);
    await startGuide(t);
    expect(find.text('欢迎使用生物遗传计算平台'), findsOneWidget,
        reason: '引导第 1 步应为欢迎卡');
    expect(find.textContaining('1 / '), findsOneWidget, reason: '步骤计数器存在');
    expect(t.widget<IndexedStack>(find.byType(IndexedStack)).index, 0,
        reason: '欢迎步应切回首页');
  });

  testWidgets('步骤推进：下一步逐页切换，最后「完成」自动关闭', (t) async {
    await pumpApp(t);
    await startGuide(t);

    // 关键步骤抽查：导航栏步 → 遗传图谱步 → 9331 步
    await t.tap(find.text('下一步'));
    await t.pumpAndSettle();
    expect(find.text('导航栏'), findsOneWidget);

    // 连点两步到遗传图谱（步骤 4，索引 1）
    await t.tap(find.text('下一步')); // 首页功能地图
    await t.pumpAndSettle();
    await t.tap(find.text('下一步')); // 遗传图谱
    await t.pumpAndSettle();
    expect(find.text('遗传图谱 · 填亲本'), findsOneWidget,
        reason: '图谱第 1 步应为亲本输入区说明');
    expect(t.widget<IndexedStack>(find.byType(IndexedStack)).index, 1,
        reason: '遗传图谱步应切到导航索引 1');

    // 一路点到最后一步（完成步文案「引导完成」），再点「完成」关闭。
    // v2.19.26（老用户 ⑧）：循环上界改由 stepsFor 实际步数驱动——
    // 步数增减时测试自动跟随，不再依赖 12 这个会过期的常数
    // （14 步引导只剩 2 步余量，下轮加步会先在这里报警）。
    final totalSteps = GuideController.instance.stepsFor(wide: true).length;
    // v2.19.30（DeepSeek P1-1 测试守护）：挖孔存在性断言——设置步
    // 气泡出现时，settingsAi 的 Element 必须在树且 RenderBox 纵坐标
    // 在视口内（ensureVisible + cacheExtent 生效的证明）。此前只断
    // 文案不断挖孔，「整屏黑罩无高亮」型回归全绿漏网。
    var settingsStepSeen = false;
    for (var i = 0;
        i < totalSteps && find.text('引导完成').evaluate().isEmpty;
        i++) {
      await t.tap(find.text('下一步'));
      await t.pumpAndSettle();
      if (find.textContaining('配置 AI 接口通道').evaluate().isNotEmpty) {
        settingsStepSeen = true;
        final ctx = GuideKeys.settingsAi.currentContext;
        expect(ctx, isNotNull,
            reason: '设置步挖孔目标 settingsAi 不在树（Element 被'
                ' ListView 缓存回收）——ensureVisible/cacheExtent 失效');
        final box = ctx!.findRenderObject();
        expect(box, isA<RenderBox>());
        final topLeft = (box as RenderBox).localToGlobal(Offset.zero);
        expect(topLeft.dy, greaterThan(0.0),
            reason: 'settingsAi 纵坐标 ${topLeft.dy} 在屏外上方——'
                '挖孔丢失（整屏黑罩无高亮）');
        expect(topLeft.dy, lessThan(900.0),
            reason: 'settingsAi 纵坐标 ${topLeft.dy} 在屏外下方——'
                'ensureVisible 未把目标滚进视口');
      }
    }
    expect(settingsStepSeen, isTrue, reason: '推进循环应经过设置步');
    // 总步数断言：步骤再增减时此处直接红（防静默漂移）。
    // v2.22.0：套路卡从主导航撤下独立入口 ⇒ 撤销「套路卡」那一步，
    // 改在 9331 步交代「结果页按 K / 错题本按需打开」的真实可达路径。
    expect(totalSteps, 19,
        reason: 'v3.8 引导 = 欢迎/导航/首页 + 图谱×5（亲本/结果/连线/手势/多代）'
            ' + 9331/课标/分子/进化/倍性/变异/遗传病/设置/问AI/完成');
    expect(find.text('引导完成'), findsOneWidget, reason: '应到达完成步');
    await t.tap(find.text('完成'));
    await t.pumpAndSettle();
    expect(find.text('引导完成'), findsNothing, reason: '完成后 overlay 自动关闭');
    expect(GuideController.instance.active, isFalse);
  });

  testWidgets('跳过立即关闭；一次性语义：可手动再次开启', (t) async {
    await pumpApp(t);
    await startGuide(t);
    expect(find.text('欢迎使用生物遗传计算平台'), findsOneWidget);

    await t.tap(find.text('跳过'));
    await t.pumpAndSettle();
    expect(find.text('欢迎使用生物遗传计算平台'), findsNothing,
        reason: '跳过应立即关闭 overlay');
    expect(GuideController.instance.active, isFalse);

    // 一次性：不会自动重播；但回设置页手动再点可再来一遍
    await t.pumpAndSettle();
    expect(find.text('欢迎使用生物遗传计算平台'), findsNothing,
        reason: '完成后不得自动重播');
    // v2.20.0：手动再开启同样先滚 rail 到「设置」再点（13 项 rail 在
    // 900 高窗口下末几项在屏外，直接 tap 会打空）。
    await tapRailSettings(t);
    await t.tap(find.text('开始引导'));
    await t.pumpAndSettle();
    expect(find.text('欢迎使用生物遗传计算平台'), findsOneWidget,
        reason: '手动再次开启应重新走一遍');
    await t.tap(find.text('跳过')); // 收尾不污染环境
    await t.pumpAndSettle();
  });

  testWidgets('上一步回退：步骤与页面同步回退', (t) async {
    await pumpApp(t);
    await startGuide(t);
    await t.tap(find.text('下一步')); // → 导航栏
    await t.pumpAndSettle();
    await t.tap(find.text('下一步')); // → 首页功能地图
    await t.pumpAndSettle();
    expect(find.text('首页 · 功能地图'), findsOneWidget);

    await t.tap(find.text('上一步'));
    await t.pumpAndSettle();
    expect(find.text('导航栏'), findsOneWidget, reason: '上一步应回退到导航栏步');
  });
}
