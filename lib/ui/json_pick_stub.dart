// json_pick_stub.dart —— 选 .json 文件的桩（非 IO/HTML 平台兜底）。
//
// v2.12+ R1 final D P0 #5：错题本导入除「粘贴 JSON 文本」外加
// 「从文件选 .json」入口。沿用 image_pick.dart 的条件导入模式：
//   - 桌面（Windows PowerShell WinForms OpenFileDialog）
//   - Android（MethodChannel 走系统文档选择器）
//   - Web（<input type="file" accept=".json"> 通过 package:web）
//   - 其余平台返回 null（与 image_pick 兜底语义一致）
//
// 抽到 stub 的类供 VM 测试直接 import 验证 PickedJson 数据契约，
// 不依赖 package:web / dart:io。
class PickedJson {
  final String content; // 文件全文（utf-8 decoded）
  final String name; // 文件名
  const PickedJson(this.content, this.name);
}

/// 弹出系统选 .json 文件对话框；用户取消或平台不支持返回 null。
///
/// 返回 null 的两种语义（与 image_pick 一致）：
///   1. 用户主动取消（系统对话框的 Cancel / Web 端不选文件）
///   2. 平台不支持（Linux/macOS 当前 stub 走 Windows-only 分支）
///
/// 调用方按 null = "视为取消" 处理，UI 不弹错误 SnackBar。
Future<PickedJson?> pickJsonFile() async => null;
