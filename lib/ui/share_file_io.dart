// share_file_io.dart —— 分享文件（dart:io 平台）。
//
// Android：MethodChannel `biology/share_file` → MainActivity.kt 调
// Intent.ACTION_SEND（FileProvider content:// URI +
// FLAG_GRANT_READ_URI_PERMISSION，targetSdk 35 下 Uri.fromFile 会抛
// FileUriExposedException）。
// 其余 IO 平台（Windows/macOS/Linux）无系统分享面板 → 返回错误原因。

import 'dart:io';

import 'package:flutter/services.dart';

const _channel = MethodChannel('biology/share_file');

Future<String?> shareFile(String path, {String? mimeType}) async {
  if (!Platform.isAndroid) return '当前平台不支持分享';
  try {
    await _channel.invokeMethod<void>(
      'shareFile',
      {'path': path, 'mimeType': mimeType ?? '*/*'},
    );
    return null; // 分享面板已拉起（用户可能取消，无法感知）
  } on PlatformException catch (e) {
    return '分享失败：${e.message ?? e.code}';
  } catch (e) {
    return '分享失败：$e';
  }
}