// json_pick.dart —— 错题本导入「从文件选 .json」入口（v2.12+ R1 final D P0 #5）。
//
// 沿用 image_pick.dart 的条件导入模式：
//   - Windows：dart:io Process 调 PowerShell WinForms OpenFileDialog（Filter=*.json）
//   - Android：MethodChannel(biology/json_pick) → MainActivity
//   - Web：HTMLInputElement type=file accept=.json
//   - 其余平台返回 null（错题本导入对话框显示「当前平台不支持」提示）。
//
// 数据契约：PickedJson { content: String, name: String }
//   - content：文件全文（utf-8 decoded），可直接给 MistakeBook.importJson
//   - name：文件名（含 .json 后缀），用于 SnackBar 提示「已导入 xxx.json」

export 'json_pick_stub.dart'
    if (dart.library.io) 'json_pick_io.dart'
    if (dart.library.html) 'json_pick_web.dart';
