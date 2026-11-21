// file_drop.dart —— Windows 拖图入窗的条件导入门面（Wave2 拖拽上传）
//
// 用户诉求（2026-10）：「Windows 上传图片不支持拖拽上传，把拖拽上传
// 也做一下」。产品决策：拖图入窗 = 打开拍题识别对话框并自动开始识别
//（v2.10 入口分离后拍题是唯一收图入口；「问 AI」面板不接收图片）。
//
// 零插件（与 image_pick.dart 同约束）：原生侧走 runner 自研
// MethodChannel "biology/file_drop"（windows/runner/flutter_window.cpp
// 的 WM_DROPFILES → DragQueryFileW → UTF-8 路径数组），不用桌面拖拽
// 插件。分平台实现：
//   - Windows：file_drop_io.dart 注册通道 handler，收到 onFiles 回调
//     （仅 Windows；Android 等 IO 平台 no-op——安卓没有窗口拖放概念）；
//   - Web：file_drop_web.dart no-op（待 HTML5 drop 接入，见文件注释）；
//   - 其余平台：file_drop_stub.dart no-op。
//
// 门面本身不声明任何符号（与 image_pick.dart 一致）：FileDropHandler /
// initFileDrop 由条件实现各自声明（io/web 从 stub re-export typedef）。

export 'file_drop_stub.dart'
    if (dart.library.io) 'file_drop_io.dart'
    if (dart.library.html) 'file_drop_web.dart';
