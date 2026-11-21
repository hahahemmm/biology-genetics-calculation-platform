// app_restart_web.dart —— Web 端「重启」= 整页刷新（package:web）。
//
// 为什么存在：浏览器里没有可重启的进程，SystemNavigator.pop() 是空操作。
// 不刷新的话，切换账号 / 恢复备份之后页面继续跑着旧档案的单例缓存，
// 下一次保存就把旧数据写进新档案目录。
//
// 桌面 / 安卓构建不编译本文件（app_restart.dart 用条件导入分流）。

import 'package:web/web.dart' as web;

void reloadPage() {
  web.window.location.reload();
}
