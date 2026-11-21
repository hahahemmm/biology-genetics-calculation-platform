// image_pick.dart —— 拍题识别的图片选择入口（v2.5 功能 1）
//
// 不用 file_picker 等原生插件：Windows 插件构建需要开发者模式 symlink
// 支持，项目零插件约束（见 settings_storage_stub.dart 注释）因此保持。
// 分平台实现：
//   - Windows：dart:io Process 调 PowerShell WinForms OpenFileDialog
//   - Android：MethodChannel(biology/image_pick) → MainActivity
//     ACTION_OPEN_DOCUMENT 读字节
//   - Web：dart:html FileUploadInputElement
//   - 其余平台返回 null（面板提示不支持）。

export 'image_pick_stub.dart'
    if (dart.library.io) 'image_pick_io.dart'
    if (dart.library.html) 'image_pick_web.dart';
