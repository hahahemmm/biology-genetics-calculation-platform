// window_channel.dart —— v2.19.68 Windows 无边框全屏切换（F11，零 plugin）
//
// 老师投影刚需：上课时把窗口切成无边框全屏（盖住任务栏/标题栏），再按
// 还原。走 MethodChannel "biology/window" → windows/runner/flutter_window
// 的 ToggleFullscreen（保存 WINDOWPLACEMENT → 切边框样式 → SetWindowPos
// 铺满主屏；还原走 SetWindowPlacement）。零 plugin：通道在 runner 原生
// 侧实现，不新增任何 pubspec 依赖。
//
// 平台语义：仅 Windows 注册/应答；Android / iOS / Web 上 toggleFullscreen()
// 直接 no-op 返回 false（不发通道消息）。旧 runner（未实现该 method）时
// MissingPluginException / NotImplementedException 吞掉返回 false——
// 全屏切换是锦上添花，绝不因它报错打断课堂。

import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb, visibleForTesting;
import 'package:flutter/services.dart';

/// Windows 窗口控制通道（无边框全屏切换）。
class WindowChannel {
  WindowChannel._();

  static const MethodChannel _channel = MethodChannel('biology/window');

  /// 测试注入：非空时 [toggleFullscreen] 直接返回该结果，不触通道
  ///（widget 测试验证 F11 快捷键接线用）。
  @visibleForTesting
  static Future<bool> Function()? debugToggle;

  /// 当前平台是否具备无边框全屏能力（仅 Windows 桌面）。
  static bool get supported => !kIsWeb && Platform.isWindows;

  /// 切换无边框全屏。返回 true = 本次调用后处于全屏，false = 已还原
  /// 或平台不支持/通道未实现（no-op）。
  static Future<bool> toggleFullscreen() async {
    final override = debugToggle;
    if (override != null) return override();
    if (!supported) return false;
    try {
      final r = await _channel.invokeMethod<bool>('toggleFullscreen');
      return r ?? false;
    } on MissingPluginException {
      // 旧 runner 未注册通道：静默降级。
      return false;
    } on PlatformException {
      // 原生侧异常（如窗口句柄失效）：静默降级，不打断课堂。
      return false;
    }
  }
}
