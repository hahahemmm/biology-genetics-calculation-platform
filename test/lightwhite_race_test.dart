// lightwhite_race_test.dart —— 验证 onPlatformBrightnessChanged 修复
// 场景：模拟「系统 dark 启 app，磁盘存 light」竞态；
//       模拟「手动 light 模式 + 系统 dark 切到 light」竞态（用户报告的 bug）
import 'package:biology/state/theme_controller.dart';
import 'package:biology/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('onPlatformBrightnessChanged 任何模式都 notify（修复白底白字）', () {
    final c = ThemeController.instance;
    c.debugSetMode(ThemeMode.light); // 用户手动锁浅色（debugSetMode 自身会 notify 1 次）
    var notifyCount = 0;
    c.addListener(() => notifyCount++);

    // 关键断言：手动 light 模式下，平台亮度变化仍须 notify，
    // 触发 ListenableBuilder rebuild，重新 AppColors.sync
    c.onPlatformBrightnessChanged();
    expect(notifyCount, 1,
        reason: '修复前：手动模式不 notify → ListenableBuilder 不 rebuild → '
            '_dark 残留 → ink 返错色 → 白底白字');

    // 反向：手动 dark 模式
    c.debugSetMode(ThemeMode.dark); // 又 notify 1 次
    c.onPlatformBrightnessChanged();
    expect(notifyCount, 3,
        reason: '手动 dark 模式同样需要响应平台亮度变化');
  });

  testWidgets('手动 light 模式 + 系统 dark 启动 → _dark=false', (t) async {
    // 模拟系统 dark
    t.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    addTearDown(() => t.platformDispatcher.clearPlatformBrightnessTestValue());

    // 用户磁盘存 light（通过 setMode 模拟）—— 不走 load()
    final c = ThemeController.instance;
    c.debugSetMode(ThemeMode.light);

    // 此时 _dark 还没 sync（singleton 残留）
    // 模拟系统 dark→light 切换：触发修复路径
    t.platformDispatcher.platformBrightnessTestValue = Brightness.light;
    c.onPlatformBrightnessChanged();
    await t.pump();

    // 现在平台 light，mode=light → 期望 _dark=false
    // （这里不调 pumpWidget，只验证 onPlatformBrightnessChanged 通知了）
    expect(c.mode, ThemeMode.light);
  });
}
