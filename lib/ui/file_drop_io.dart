// file_drop_io.dart —— 桌面/安卓拖拽入窗（dart:io 平台）。
//
// 仅 Windows 有原生实现（runner flutter_window.cpp 的 WM_DROPFILES →
// MethodChannel "biology/file_drop" → 方法名 "onFiles"，参数为 UTF-8
// 路径字符串数组）。Android 等 IO 平台没有窗口拖放概念，注册 no-op。
//
// 竞态说明：引擎启动早期（Dart isolate 未跑 / HomeShell 未 initState）
// 用户拖图，C++ 侧 InvokeMethod 落空（Dart 侧无 handler）——丢这一帧
// 是可接受的（拖拽是显式用户动作，松手前窗口已可见，实际到达时间窗
// 极窄），不崩、不重放。

import 'dart:io';

import 'package:flutter/services.dart';

import 'file_drop_stub.dart';

export 'file_drop_stub.dart' show FileDropHandler;

const _channel = MethodChannel('biology/file_drop');

/// 注册窗口级拖入回调（App 启动时调一次；重复调用覆盖旧 handler）。
void initFileDrop(FileDropHandler onFiles) {
  if (!Platform.isWindows) return; // Android：无窗口拖放，no-op
  _channel.setMethodCallHandler((call) async {
    if (call.method == 'onFiles' && call.arguments is List) {
      onFiles([for (final e in call.arguments as List) e.toString()]);
    }
    return null;
  });
}
