// png_export.dart —— 板书/画布一键导出 PNG（v2.4，功能 2）
//
// 场景：老师把 9331 棋盘板书 / 系谱图存成图片插进自己的课件。
// 截图部分（RepaintBoundary→toImage）三端通用；写文件部分按平台
// 条件导入（dart.library.io → 桌面/安卓写图片目录；否则桩返回不支持）。
// 无新增依赖（不引 path_provider：桌面写 Pictures，失败时把错误透出）。

import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import 'png_export_stub.dart'
    if (dart.library.io) 'png_export_io.dart';

export 'png_export_stub.dart'
    if (dart.library.io) 'png_export_io.dart';

/// 抓取 boundaryKey 对应渲染树并写 PNG。
/// 返回 (path, error)：成功 path 非空；失败 error 为中文说明。
/// [debugDir] 测试专用：写入目录覆盖（避免测试污染真实图片目录）。
Future<({String? path, String? error})> captureBoundaryPng(
  GlobalKey boundaryKey,
  String prefix, {
  String? debugDir,
}) async {
  try {
    final boundary = boundaryKey.currentContext?.findRenderObject();
    if (boundary is! RenderRepaintBoundary) {
      return (path: null, error: '截图目标未就绪');
    }
    final img = await boundary.toImage(pixelRatio: 2.5);
    final data = await img.toByteData(format: ui.ImageByteFormat.png);
    img.dispose();
    if (data == null) return (path: null, error: '图像编码失败');
    return await writePng(
        data.buffer.asUint8List(), prefix, debugDir: debugDir);
  } catch (e) {
    return (path: null, error: '导出失败：$e');
  }
}
