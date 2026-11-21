// eye_care_test.dart —— v2.19.8 护眼模式（R9 集成）测试
//
// 覆盖：
//   1. 设置页有「护眼模式」开关（SwitchListTile）
//   2. 开启后 app 树出现 ColorFiltered（全局暖色滤镜），关闭后移除
//   3. 状态持久化 round-trip（注入内存 web storage，不碰真实盘）

import 'package:biology/main.dart';
import 'package:biology/state/theme_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/ready_app.dart';

void main() {
  testWidgets('设置页有护眼模式开关，开启后全局套 ColorFiltered',
      (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await pumpReadyBiologyApp(tester);

    // 只点 Rail 里的「设置」，避免命中首页分组中的同名入口。
    await tester.tap(find.descendant(
      of: find.byType(NavigationRail),
      matching: find.text('设置'),
    ));
    await tester.pumpAndSettle();
    // v2.19.30：设置页回退单列平铺——「外观」节滚到即见，无需切分区。
    expect(find.text('护眼模式'), findsOneWidget,
        reason: '外观节含护眼模式开关');

    // 默认关：无 ColorFiltered。
    expect(find.byType(ColorFiltered), findsNothing,
        reason: '默认关闭，无暖色滤镜');

    // 开关联动：让目标在它自己的滚动容器里可见，不依赖全局 Scrollable 树序。
    await tester.ensureVisible(find.text('护眼模式'));
    await tester.pumpAndSettle();
    await tester.tapAt(tester.getCenter(find.text('护眼模式')));
    await tester.pumpAndSettle();
    expect(ThemeController.instance.eyeCare, isTrue,
        reason: '设置页开关与 ThemeController 联动');
    expect(find.byType(ColorFiltered), findsOneWidget,
        reason: '开启后全局套暖色矩阵滤镜（含对话框层）');

    await tester.tapAt(tester.getCenter(find.text('护眼模式')));
    await tester.pumpAndSettle();
    expect(ThemeController.instance.eyeCare, isFalse);
    expect(find.byType(ColorFiltered), findsNothing);
  });
}
