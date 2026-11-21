// platform_storage_io.dart —— 非 Web 平台存储桩（条件导入，Web 构建时
// 被 platform_storage_web.dart 替换）。保持同步签名，Web 端经
// `if (dart.library.html)` 分支使用 localStorage。
//
// v2.11 M1：从 lib/pages/settings_storage_stub.dart 迁移到 lib/storage/
// 中性层——修复 engine 层跨层 import pages 层的反向依赖
//（lib/state/scan_bank_store.dart:12）。
//
// v2.0：避免引入原生插件（shared_preferences 需要 Windows Developer Mode
// 的 symlink 支持，构建受阻）——改用条件导入 + dart:html localStorage，
// 桌面/安卓维持 File 持久化，Web 端设置与会话历史存浏览器本地。

// platform_storage_io.dart —— 非 Web 平台存储桩（条件导入，Web 构建时
// 被 platform_storage_web.dart 替换）。保持同步签名，Web 端经
// `if (dart.library.html)` 分支使用 localStorage。
//
// v2.11 M1：从 lib/pages/settings_storage_stub.dart 迁移到 lib/storage/
// 中性层——修复 engine 层跨层 import pages 层的反向依赖
//（lib/state/scan_bank_store.dart:12）。
//
// v2.11 M8：加 `userAppDir()` 中性 API——返回应用专属目录路径
//（$USERPROFILE/.biology_app）。调用方（scan_bank_store / history_store）
// 改用此 API 替代直接 `Directory('$home/.biology_app')`。
// 桌面/安卓返真实路径；Web stub 返 null（走 localStorage 不需要路径）。
//
// v2.13 R3 W1（P0 修复）：Android 分支——`USERPROFILE ?? HOME ?? '.'`
// 在 Android 上两个环境变量都不存在 → 回退 '.' → cwd = '/' → EACCES
// → 全盘持久化静默失效。改为经 MethodChannel `biology/app_dir/getFilesDir`
// 取 Context.getFilesDir()（见 app_dir_android.dart + MainActivity.kt），
// 缓存供同步 userAppDir() 读；各 store 的 async load() 先 await
// `ensureAppDirReady()` 保证首次读盘前缓存就绪（桌面/Web no-op）。
//
// v2.0：避免引入原生插件（shared_preferences 需要 Windows Developer Mode
// 的 symlink 支持，构建受阻）——改用条件导入 + dart:html localStorage，
// 桌面/安卓维持 File 持久化，Web 端设置与会话历史存浏览器本地。
import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'app_dir_android.dart';

/// 当前是否为 Web 平台（save 用它区分 localStorage 空值与桌面未实现）。
bool get isWebStorage => false;

String? storageGet(String key) => null;

Future<void> storageSet(String key, String value) async {}

/// v2.13 R3 W1：测试注入——强制模拟 Android 平台分支。
///
/// flutter_test 跑在 VM 上 `Platform.isAndroid` 恒为 false，无法直接
/// 测 MethodChannel 分支；置 true 后 userAppDir() / ensureAppDirReady()
/// 走 Android 路径（配合 appDirChannel 的 mock handler）。
@visibleForTesting
bool? debugForceIsAndroid;

bool get _isAndroid => debugForceIsAndroid ?? Platform.isAndroid;

/// v2.13 R3 W1：等待 Android getFilesDir 缓存就绪（桌面/Web no-op）。
///
/// 各 store（app_state / first_run_store / history_store / mistake_book /
/// scan_bank_store / theme_controller / present_mode_controller）的 async
/// load() 开头调用——保证首次读盘就拿到正确的应用专属目录，而不是
/// fallback 到 '/'（EACCES 静默丢数据）。
Future<void> ensureAppDirReady() async {
  if (_isAndroid) await fetchAndroidFilesDir();
}

/// v2.24：基目录——应用数据根（桌面/安卓）。
///
/// 桌面 home 兜底顺序：USERPROFILE → HOME → '.'。
/// Android：getFilesDir() 缓存未就绪时触发异步预取并返 null（调用方
/// 走相对路径占位；正常时序下 load() 已先 ensureAppDirReady，不会出现）。
/// 不调用 `Directory().createSync`——调用方决定是否真的创建。
String? baseAppDir() {
  if (_isAndroid) {
    final files = cachedAndroidFilesDir();
    if (files != null && files.isNotEmpty) {
      return '$files${Platform.pathSeparator}.biology_app';
    }
    // 缓存未就绪：fire-and-forget 预取，完成即缓存（兜底 save 路径）。
    unawaited(fetchAndroidFilesDir());
    return null;
  }
  final home = Platform.environment['USERPROFILE'] ??
      Platform.environment['HOME'] ??
      '.';
  return '$home${Platform.pathSeparator}.biology_app';
}

/// v2.24：当前档案目录——由 AccountsStore 在启动最开始写入
/// `<基目录>/accounts/<id>`；null = 尚未分档（或 Web 端），退回基目录，
/// 此时 14 个 store 全部落在基目录，行为与引入多档案之前一致。
String? accountDataDir;

/// v2.24：Web 端 localStorage 前缀。io 端没有 localStorage，此变量只为
/// 条件导入编译期同签名存在（真正的分档看 [accountDataDir]）。
String? accountKeyPrefix;

String? userAppDir() => accountDataDir ?? baseAppDir();

/// v2.24：io 端不走 localStorage——账号清单落在 `<基目录>/accounts.json`
/// （见 state/accounts_store.dart）。下面四个接口只为条件导入同签名。
String? storageGetRaw(String key) => null;

Future<void> storageSetRaw(String key, String value) async {}

Future<void> storageRemove(String key) async {}

Future<void> storageRemoveByPrefix(String prefix) async {}

/// v2.24：与 web 版同签名（条件导入编译期要求）；io 端没有 localStorage。
Future<void> storageRemoveLocalKeys() async {}
