// png_export_stub.dart —— 非 IO 平台桩（Web 构建时被使用）；
// 桌面/安卓经 `if (dart.library.io)` 分支换成 png_export_io.dart。

import 'dart:typed_data';

Future<({String? path, String? error})> writePng(Uint8List bytes,
    String prefix,
    {String? debugDir}) async {
  return (path: null, error: '当前平台不支持导出文件');
}
