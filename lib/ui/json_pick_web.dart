// json_pick_web.dart —— Web 端 .json 文件选择（package:web 文件输入框）。
//
// v2.12+ R1 final D P0 #5：错题本导入对话框加「从文件选 .json」入口。
// Web 端实现：HTMLInputElement type=file accept=.json → FileReader 读全文。
// 沿用 image_pick_web.dart 的同款 pattern：done Completer + 60s timeout
// 兜底 + result 转 Dart String。
//
// 为什么不复用 image_pick_web 的 PickedImage 链路：JSON 是文本，强行
// 包成 bytes 再 utf8.decode 是冗余。PickedJson 直接用 String content
// 更直接。
import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

import 'image_pick_stub.dart' show runWithCancelTimeout;
import 'json_pick_stub.dart';

export 'json_pick_stub.dart' show PickedJson;

/// 选 .json 文件等待上限：60 秒后用户仍未选择（大多场景是对话框被关掉
/// 但 change 没触发），超时强制视为取消。
const Duration _pickTimeout = Duration(seconds: 60);

Future<PickedJson?> pickJsonFile() async {
  final input = web.HTMLInputElement()
    ..type = 'file'
    ..accept = '.json,application/json';
  final done = Completer<PickedJson?>();
  input.onchange = ((web.Event _) {
    final files = input.files;
    if (files == null || files.length == 0) {
      if (!done.isCompleted) done.complete(null);
      return;
    }
    final file = files.item(0);
    if (file == null) {
      if (!done.isCompleted) done.complete(null);
      return;
    }
    final reader = web.FileReader();
    // 注意：reader.onerror 触发时 onloadend 也会随后触发；靠
    // `if (!done.isCompleted)` 守卫避免 double-complete。
    reader.onloadend = ((web.ProgressEvent _) {
      final result = reader.result;
      if (result == null) {
        if (!done.isCompleted) done.complete(null);
        return;
      }
      if (!result.isA<JSArrayBuffer>()) {
        if (!done.isCompleted) done.complete(null);
        return;
      }
      final buf = (result as JSArrayBuffer).toDart;
      final content = utf8.decode(buf.asUint8List());
      final name = file.name;
      if (!done.isCompleted) {
        done.complete(PickedJson(content, name));
      }
    }).toJS;
    reader.onerror = ((web.ProgressEvent _) {
      if (!done.isCompleted) done.complete(null);
    }).toJS;
    reader.readAsArrayBuffer(file);
  }).toJS;
  // 用户在系统对话框取消：Web 无 cancel 回调，靠 60s timeout 兜底——
  // 超过 60s 强制返回 null，不抛异常。复用 image_pick_stub.runWithCancelTimeout
  // （该函数纯 dart 写，专门为跨端 Web/VM 场景设计）。
  input.click();
  return runWithCancelTimeout<PickedJson?>(
    done.future,
    timeout: _pickTimeout,
    fallback: null,
  );
}
