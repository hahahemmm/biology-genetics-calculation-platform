// app_navigator_key.dart —— 全局 Navigator 句柄。
//
// v2.24：AI 工具执行前的「确认执行」对话框需要在没有 BuildContext 的
// 调用链里弹出（AiClient → AiToolHost → 确认）。给 MaterialApp 挂一个
// 全局 navigatorKey，任何位置都能拿到当前 Navigator 上下文。
//
// 只在 main.dart 的 MaterialApp.navigatorKey 上使用一次，别的地方只读。

import 'package:flutter/widgets.dart';

/// 应用根 Navigator 的 GlobalKey。
///
/// 未挂到 MaterialApp 之前 currentContext 为 null——调用方必须判空，
/// 拿不到上下文时按「用户未确认」处理，不能默认放行（危险命令宁可拒绝）。
final GlobalKey<NavigatorState> appNavigatorKey =
    GlobalKey<NavigatorState>(debugLabel: 'appNavigator');
