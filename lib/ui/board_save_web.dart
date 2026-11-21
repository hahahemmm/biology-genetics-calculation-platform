// board_save_web.dart —— Web 端板书 SVG 下载（package:web + dart:js_interop）。
//
// v2.12+ R2 P0-A1：「存为板书」Web 路径。MistakeBookExporter 同款
// 套路（createObjectURL + <a download> + revokeObjectURL），但
// MIME 改 image/svg+xml + 文件名 .svg。
//
// 桌面/安卓编译路径不会调到本方法（_saveAsBoard 内部 kIsWeb 分流），
// 所以 dart:js_interop 不会污染桌面构建。

// ignore: avoid_web_libraries_in_flutter
import 'dart:convert';
// ignore: avoid_web_libraries_in_flutter
import 'dart:js_interop';

// ignore: avoid_web_libraries_in_flutter
import 'package:web/web.dart' as web;

void stubBoardDownload(String svg, String filename) {
  final bytes = utf8.encode(svg);
  // ignore: invalid_use_of_internal_member
  final jsBytes = bytes.toJS;
  final blob = web.Blob(
    <JSAny>[jsBytes].toJS,
    web.BlobPropertyBag(type: 'image/svg+xml'),
  );
  final url = web.URL.createObjectURL(blob);
  final anchor = web.HTMLAnchorElement()
    ..href = url
    ..download = filename
    ..style.display = 'none';
  web.document.body!.appendChild(anchor);
  anchor.click();
  anchor.remove();
  web.URL.revokeObjectURL(url);
}
