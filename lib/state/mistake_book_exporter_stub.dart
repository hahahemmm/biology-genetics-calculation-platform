// mistake_book_exporter_stub.dart —— 桌面 / 安卓端 stub（不会触发 Web
// 下载，因为 isWebStorage=false 走 _saveDesktop）。
//
// 条件导入：mistake_book.dart 末尾
//   import 'mistake_book_exporter_stub.dart'
//       if (dart.library.html) 'mistake_book_exporter_web.dart';
// 在非 Web 平台（即 dart:io 可用），调本文件的 _webTriggerDownload，
// 它直接返回 null，调用方把它当成 "Web 触发失败" 处理——但实际不
// 会被走到，因为 MistakeBookExporter.saveToDownloads 内部先看
// isWebStorage 决定走 _saveDesktop 还是 _saveWeb。

import 'dart:typed_data';

void webTriggerDownload(String json, String filename) {
  // 桌面 / 安卓：不实现。理论不会被调用。
  return;
}

/// v2.12+ R2 P0-B2：PNG 字节下载触发 stub（桌面 / 安卓不实现）。
/// 实际不会走到（savePngToDownloads 走 _saveDesktop），保留以满足
/// 条件导入的签名。
void webTriggerPngDownload(Uint8List bytes, String filename) {
  // 桌面 / 安卓：不实现。理论不会被调用。
  return;
}
