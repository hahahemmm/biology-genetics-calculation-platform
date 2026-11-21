// shortcut_nudge.dart —— v2.19.54：快捷键指引一次性提示
//
// 三族页面键宿主（Alt+数字 / Ctrl+S / Alt+K）全是零像素、多数页连对应
// 按钮都没有（找茬创新提案 1 的缺口证据）——功能存在但不可发现。
// 学生**第一次**成功触发其中任何一键后，弹一次 SnackBar 告知「按 ?
// 查看本页快捷键」；此后再不弹（FirstRunStore.shortcutNudgeShown 持久化，
// ⛔ 每次启动重弹会比不弹更烦）。
//
// 调用点：各宿主成功触发（return true 前）调 [ShortcutNudge.maybeNotify]。
// 让路路径（return false）⛔ 不调——没触发成功就没有「原来有快捷键」的
// 事实，此时弹指引是噪音。

import 'package:flutter/material.dart';

import '../state/first_run_store.dart';

abstract final class ShortcutNudge {
  /// 首次成功触发后弹一次性指引。重复调用 / 已弹过 = 静默 no-op。
  static void maybeNotify(BuildContext context) {
    if (FirstRunStore.instance.shortcutNudgeShown) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;
    // 先落盘再弹：弹完即标，下次（含下次启动）不再烦。
    FirstRunStore.instance.markShortcutNudgeShown();
    messenger.showSnackBar(
      const SnackBar(
        content: Text('按 ?（Shift + /）查看本页可用的快捷键'),
        duration: Duration(seconds: 4),
      ),
    );
  }
}
