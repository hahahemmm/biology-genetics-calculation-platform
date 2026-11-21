// image_pick_web.dart —— Web 端图片选择（package:web 文件输入框）。
//
// v2.11 M7：dart:html → package:web + dart:js_interop 迁移。
// 旧实现用 dart:html 的 Stream API（`input.onChange.listen((_) {...})`），
// 新实现用 package:web 的 setter API 赋 JS function callback
// （`input.onchange = ((web.Event _) {...}).toJS`）。
// package:web 1.1.1 的事件回调是 EventHandler / OnErrorEventHandlerNonNull
// = JSFunction，Dart lambda 需 .toJS 包装。
// 异步读取：reader.readAsArrayBuffer(blob) 后 reader.result 是 JSAny?，
// FileReader.readAsArrayBuffer 完成后 result 必为 JSArrayBuffer，toDart 转 ByteBuffer。
//
// v2.12 跨端完备：用户取消时 input.click 触发的系统文件对话框不发任何回调，
// change 不触发 → done.future 永久悬挂。用 image_pick_stub.runWithCancelTimeout
// 60s 兜底，到时 done.future 强制完成 null（不抛 TimeoutException），面板无
// 状态污染。timeout 抽到 stub 是为了让 VM 平台测试不依赖 package:web。
import 'dart:async';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

import 'image_pick_stub.dart';

export 'image_pick_stub.dart' show PickedImage;

/// 选图对话框等待上限：60 秒后用户仍未选择（大多场景是对话框被关掉
/// 但 change 没触发），超时强制视为取消。
const Duration _pickTimeout = Duration(seconds: 60);

Future<PickedImage?> pickImageFile() async {
  final input = web.HTMLInputElement()
    ..type = 'file'
    ..accept = 'image/*';
  final done = Completer<PickedImage?>();
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
      final name = file.name;
      final dot = name.lastIndexOf('.');
      if (!done.isCompleted) {
        done.complete(PickedImage(buf.asUint8List(), name,
            dot >= 0 ? name.substring(dot + 1).toLowerCase() : 'png'));
      }
    }).toJS;
    reader.onerror = ((web.ProgressEvent _) {
      if (!done.isCompleted) done.complete(null);
    }).toJS;
    reader.readAsArrayBuffer(file);
  }).toJS;
  // 用户在系统对话框取消：Web 无 cancel 回调，靠 stub.runWithCancelTimeout
  // 兜底——超过 60s 强制返回 null，不抛异常。
  input.click();
  return runWithCancelTimeout<PickedImage?>(
    done.future,
    timeout: _pickTimeout,
    fallback: null,
  );
}

