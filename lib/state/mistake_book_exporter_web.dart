// mistake_book_exporter_web.dart —— Web 端下载触发。
//
// 用 package:web + dart:js_interop 创建 Blob + URL + 触发 <a> download
// 点击。浏览器会自动把文件保存到默认下载目录。
//
// v2.11 M7 起项目已用 web 1.1.1（package:web + dart:js_interop 替换
// dart:html），所以这里直接 import 'package:web/web.dart' 即可。

// ignore: avoid_web_libraries_in_flutter
import 'dart:convert';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

void webTriggerDownload(String json, String filename) {
  // 把 JSON 字符串转成 JS Uint8Array → Blob → ObjectURL。
  // dart:js_interop 把 Dart List<int> 转 JS Uint8Array：
  //   bytes.toJS 是 List<int>.toJS（web 1.1+ 提供的扩展）。
  final bytes = utf8.encode(json);
  // ignore: invalid_use_of_internal_member
  final jsBytes = bytes.toJS;
  // BlobPart in JS interop is a union; we just pass Uint8Array (works in
  // practice; older js_interop used BufferSource).
  final blob = web.Blob(
    <JSAny>[jsBytes].toJS,
    web.BlobPropertyBag(type: 'application/json'),
  );
  final url = web.URL.createObjectURL(blob);

  // 创建一个 <a> 元素，设置 download 属性 + href，然后 click。
  final anchor = web.HTMLAnchorElement()
    ..href = url
    ..download = filename
    ..style.display = 'none';
  web.document.body!.appendChild(anchor);
  anchor.click();
  // 清理：移除元素 + 释放 ObjectURL。
  anchor.remove();
  web.URL.revokeObjectURL(url);
}

/// v2.12+ R2 P0-B2：PNG 字节 Web 端下载触发。
///
/// 沿用 webTriggerDownload 的 Blob + ObjectURL + <a> download 范式，
/// 但不走 JSON 字符串编码（PNG 已是 Uint8List）。MIME = image/png。
/// 桌面 / 安卓端 stub 走 mistake_book_exporter_stub.dart。
void webTriggerPngDownload(Uint8List bytes, String filename) {
  // ignore: invalid_use_of_internal_member
  final jsBytes = bytes.toJS;
  final blob = web.Blob(
    <JSAny>[jsBytes].toJS,
    web.BlobPropertyBag(type: 'image/png'),
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
