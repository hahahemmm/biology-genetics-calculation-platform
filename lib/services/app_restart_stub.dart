// app_restart_stub.dart —— 桌面 / 安卓端 stub（条件导入，Web 构建时
// 被 app_restart_web.dart 替换）。
//
// 不会被调用：restartApp() 里 kIsWeb 为假时走进程重启分支。

void reloadPage() {}
