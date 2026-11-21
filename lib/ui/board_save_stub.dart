// board_save_stub.dart —— 桌面/安卓端 stub（条件导入，Web 构建时
// 被 board_save_web.dart 替换）。
//
// v2.12+ R2 P0-A1：「存为板书」Web 路径。桌面/安卓走真 File 写盘
// （_saveAsBoard 内部 dart:io），Web 端无文件系统——调本文件的
// stubBoardDownload 是个 no-op（实际不被调用，因为 _saveAsBoard
// 内部 kIsWeb 分流到 web 端实现，stubBoardDownload 不在桌面
// 编译路径上被调用）。
//
// 设计：与 MistakeBookExporter 的 webTriggerDownload / stub 同款
// 套路，保持条件导入范式统一。
void stubBoardDownload(String svg, String filename) {
  // 桌面/安卓：不实现。理论不会被调用。
  return;
}
