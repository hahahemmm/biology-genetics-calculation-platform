// image_pick_stub.dart —— 图片选择桩（非 IO/HTML 平台兜底，实际不会走到）。
//
// v2.12 跨端完备：抽出 runWithCancelTimeout 纯 dart 工具函数到本文件，
// 让 VM 平台测试可直接 import（image_pick_web.dart 顶部依赖
// package:web，VM 编译会失败；放 stub 里所有平台都能用）。
import 'dart:async';
import 'dart:typed_data';

/// 选中的图片（字节 + 文件名 + 扩展名，扩展名不含点）。
class PickedImage {
  final Uint8List bytes;
  final String name;
  final String extension;
  const PickedImage(this.bytes, this.name, this.extension);
}

/// 弹出系统选图框；用户取消或平台不支持返回 null。
Future<PickedImage?> pickImageFile() async => null;

/// 给 [future] 加一个等待上限。超时返回 [fallback]（不抛 TimeoutException），
/// 调用方可继续走「视为取消」分支——避免选图 Future 永久悬挂阻塞 UI。
///
/// v2.12 背景：Web 端 `<input type="file">.click()` 触发的系统文件选择器
/// 用户取消时，浏览器不发任何回调（无 cancel 事件、无 change 事件），
/// done.future 永久悬挂 → 拍题面板状态机被锁死。Web 端在 pickImageFile
/// 末尾用本函数兜底；其它平台未来若引入异步选图也可直接复用。
///
/// 设计要点：
///   - 不抛 TimeoutException（UI 不希望被异常打挂）；
///   - 超时仅返回 fallback，调用方按 null = 取消处理；
///   - 抽到 stub 让 VM 测试可直接覆盖（不依赖 package:web / dart:io）。
Future<T?> runWithCancelTimeout<T>(
  Future<T> future, {
  Duration timeout = const Duration(seconds: 60),
  T? fallback,
}) async {
  try {
    return await future.timeout(timeout);
  } on TimeoutException {
    // 视为取消：UI 上层把 null = "用户在系统对话框点取消" 兜底。
    return fallback;
  }
}
