// app_restart.dart —— 切换档案 / 恢复备份后重启应用。
//
// v2.24：账号档案与备份恢复都改的是「进程启动时读的那份数据」，
// 而十几个 store 都是单例 + 内存缓存（各自的 _loaded / early-return
// 语义互不相同）。热切换等于逐个人工写 reset，任何一处漏写就是
// 「A 的错题出现在 B 的界面里」这类数据串档事故。
//
// 所以统一走「重启进程」：Windows 直接以当前可执行文件重新拉起，
// 再 exit(0)；Android 没有可靠的自重启通道（exit 后不保证会被系统
// 拉起），返回 needManual 让 UI 提示用户手动重开；Web 没有进程，
// 整页刷新等价于重启（单例缓存随页面一起清掉），见条件导入的
// app_restart_web.dart——SystemNavigator.pop() 在浏览器里是空操作。

import 'dart:io';

import 'package:flutter/foundation.dart';

import 'app_restart_stub.dart'
    if (dart.library.html) 'app_restart_web.dart' as page_reload;

/// 重启结果。
enum RestartOutcome {
  relaunched, // 已重新拉起（当前进程即将退出 / 页面即将重载）
  needManual, // 需要用户手动重启
  failed, // 重启失败（调用方应提示手动重启）
}

/// 重启应用。
///
/// 调用方拿到 RestartOutcome.relaunched 后不要再做任何 UI 操作——
/// 进程马上退出，Web 上页面马上重载。
Future<RestartOutcome> restartApp() async {
  if (kIsWeb) {
    page_reload.reloadPage();
    return RestartOutcome.relaunched;
  }
  if (!Platform.isWindows) {
    // Android / Linux / macOS：没有免插件的自重启通道。
    return RestartOutcome.needManual;
  }
  try {
    await Process.start(
      Platform.resolvedExecutable,
      const <String>[],
      mode: ProcessStartMode.detached,
    );
    // 留一拍让新进程完成加载再退，避免 Windows 上文件锁竞争。
    await Future<void>.delayed(const Duration(milliseconds: 300));
    exit(0);
  } catch (e) {
    debugPrint('[biology] restartApp failed: $e');
    return RestartOutcome.failed;
  }
}
