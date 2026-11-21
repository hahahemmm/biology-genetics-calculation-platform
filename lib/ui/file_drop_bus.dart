// file_drop_bus.dart —— 拖图入窗事件总线（Wave2 拖拽上传）
//
// 链路：Windows runner WM_DROPFILES → MethodChannel("biology/file_drop")
// → file_drop_io.initFileDrop 回调 → HomeShell 把路径列表经
// [takeImage] 过滤成 PickedImage → publish 到本总线 → 消费者处理。
//
// ── 消费协议（两端接线必须按此顺序，避免双开/丢图）──
//   1. HomeShell 订阅 stream 做「兜底开对话框」；
//   2. 拍题对话框（scan_upload_dialog）mounted 期间 claim()，
//      自己订阅 stream 消费新拖的图（直接 _send 进识别流程）；
//      dispose 时 release() + cancel 订阅；
//   3. HomeShell 收到事件后 `await Future.delayed(Duration.zero)` 再查
//      [hasConsumer]——无人认领才 showScanUploadDialog(initialImage: img)。
//      让出一拍的原因：对话框与 HomeShell 同为 stream 订阅者，对话框
//      在场时它自己消费，HomeShell 不重复开框；对话框不在场时事件已
//      被广播（broadcast 不回放），所以靠 initialImage 参数把图带进
//      新开的对话框。
//   4. 边界：对话框识别中（busy/refreshing）收到新图 → 该帧不排队
//      （连拍场景由用户点「再拍一题」串行），丢帧时对话框弹
//      SnackBar「识别中，请稍后再拖」提示（v2.19.67 P2 #4——
//      拖拽是显式动作，零反馈 = 用户以为拖丢了）。
//
// dart:io 说明：takeImage 只在 IO 平台被调用（file_drop_io 的回调
// 仅 Windows 注册；web/stub 永不触发）。本文件被 main.dart 无条件
// import，dart:io 在 dart2js 下可编译（dashboard_page.dart 同先例，
// 实际分支 web 不会执行）。

import 'dart:async';
import 'dart:io';

import 'image_pick.dart' show PickedImage;

/// 拖入图片事件总线（App 内单例）。
class FileDropBus {
  FileDropBus._();

  static final FileDropBus instance = FileDropBus._();

  StreamController<PickedImage> _controller =
      StreamController<PickedImage>.broadcast();

  /// 拖入图片事件流（broadcast：HomeShell 兜底 + 拍题对话框同时订阅）。
  Stream<PickedImage> get stream => _controller.stream;

  int _consumers = 0;

  /// 活跃消费者登记（拍题对话框 initState 调；重复 claim 计数累加）。
  void claim() => _consumers++;

  /// 消费者注销（对话框 dispose 调；钳到 0 防多 release 打穿）。
  void release() {
    if (_consumers > 0) _consumers--;
  }

  /// 是否有活跃消费者（HomeShell 兜底开框前查；true = 有人自己消化）。
  bool get hasConsumer => _consumers > 0;

  /// 广播一张拖入的图片（HomeShell 的 initFileDrop 回调里调用）。
  void publish(PickedImage img) => _controller.add(img);

  /// 测试用：清消费者计数、关旧流换新流（订阅者全部失效，等同重启）。
  void resetForTest() {
    _consumers = 0;
    if (!_controller.isClosed) unawaited(_controller.close());
    _controller = StreamController<PickedImage>.broadcast();
  }

  /// 从拖入路径列表取第一个图片文件并读成 [PickedImage]。
  ///
  /// 按扩展名 .png/.jpg/.jpeg/.webp/.bmp/.gif（大小写不敏感）过滤，
  /// 取**第一个**命中项（多图连拖不排队，只认头图）；name 取路径
  /// basename（\ 与 / 都切，Windows 主场）；extension 统一小写。
  /// 全不是图片、文件读不了（拖入后被删/被占用）→ null，调用方走
  /// 「非图片」SnackBar 分支。
  ///
  /// v2.19.67 P2 #5：改 `Future`（原 existsSync/readAsBytesSync 在
  /// UI isolate 同步读盘，大图拖入会卡帧）。单候选读失败 try/catch
  /// 跳下一候选（语义与原版一致）。
  static Future<PickedImage?> takeImage(List<String> paths) async {
    const exts = {'png', 'jpg', 'jpeg', 'webp', 'bmp', 'gif'};
    for (final p in paths) {
      final dot = p.lastIndexOf('.');
      if (dot < 0) continue;
      final ext = p.substring(dot + 1).toLowerCase();
      if (!exts.contains(ext)) continue;
      try {
        final f = File(p);
        if (!await f.exists()) continue;
        final bytes = await f.readAsBytes();
        final name = p.split(RegExp(r'[\\/]')).last;
        return PickedImage(bytes, name, ext);
      } catch (_) {
        // 读失败（权限/占用/刚被删）按「取不到」处理，继续看下一个候选。
        continue;
      }
    }
    return null;
  }
}
