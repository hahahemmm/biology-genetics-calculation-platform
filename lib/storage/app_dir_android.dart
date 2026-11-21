// app_dir_android.dart —— Android 应用专属目录提供者（v2.13 R3 W1 P0 修复）
//
// 背景（P0：Android 全盘持久化失效 = 静默数据丢失）：
//   platform_storage_io.userAppDir() 的 home 兜底链
//   `USERPROFILE ?? HOME ?? '.'` 在 Android 上两个环境变量都不存在
//   → 回退 '.' → cwd = '/' → createSync / writeAsStringSync 全部 EACCES
//   → 错题本 / 回收站 / AI 配置 / 角色 / 主题全部不落盘，每次启动全空，
//   且所有 store 的 `catch (_)` 把异常吞掉 → 用户零提示 = 静默丢数据。
//
// 修法：MethodChannel `biology/app_dir` + `getFilesDir`（MainActivity 从
// Context.getFilesDir() 取 `/data/data/<pkg>/files`）——零插件约束，
// 与 image_pick / json_pick 同模式（MainActivity.kt 注册原生 handler，
// Dart 侧 invokeMethod 直取）。
//
// 时序约束：userAppDir() 是同步 API（调用方 _file() 都是同步路径），
// 而 MethodChannel 本质异步。解法：
//   1. 各 store 的 async load() 开头先 `await ensureAppDirReady()`
//      （platform_storage_io.dart 导出；桌面/Web no-op）——保证首次
//      读盘前缓存已就绪；
//   2. userAppDir() 读缓存；缓存未就绪时触发 fire-and-forget 预取
//      （兜底 save 路径，正常时序下不会走到）。

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// 与 MainActivity.kt 注册的 channel 同名。
const MethodChannel appDirChannel = MethodChannel('biology/app_dir');

/// 已缓存的 getFilesDir() 结果（null = 尚未获取到）。
String? _cachedFilesDir;

/// 同步读缓存（userAppDir() 用）。null = 还没拿到。
String? cachedAndroidFilesDir() => _cachedFilesDir;

/// 获取 getFilesDir() 并缓存。幂等；失败 debugPrint 可见（不抛）。
///
/// 返回 `/data/data/<pkg>/files` 或 `/data/user/0/<pkg>/files`
/// （Android 10+ user 分区路径），由 Context.getFilesDir() 决定。
Future<String?> fetchAndroidFilesDir() async {
  if (_cachedFilesDir != null) return _cachedFilesDir;
  try {
    final v = await appDirChannel.invokeMethod<String>('getFilesDir');
    if (v == null || v.isEmpty) {
      debugPrint('[biology] app_dir getFilesDir 返回空，持久化仍不可用');
      return null;
    }
    _cachedFilesDir = v;
    debugPrint('[biology] app_dir getFilesDir = $v');
  } catch (e) {
    debugPrint('[biology] app_dir getFilesDir 失败：$e');
  }
  return _cachedFilesDir;
}