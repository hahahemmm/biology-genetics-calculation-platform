// path_basename_io.dart —— 桌面/安卓「取路径最后一段」（dart:io 平台）。
//
// 桌面（Windows / macOS / Linux）：saved 是真实文件路径，Windows 用 \
// 分隔、POSIX 用 / 分隔。统一用 Platform.pathSeparator 切尾，避免硬编码。
// Android：导出分支会走「已保存到应用目录」独立文案，不调本函数；
//   但条件导入仍把本文件编入 APK，所以实现保留。
//
// 之所以不直接用 `path` pub 包：避免为单一 split 调用新增依赖。

import 'dart:io';

export 'path_basename_stub.dart';

/// 把 [path] 切到最后一段。Windows / POSIX 都用 Platform.pathSeparator。
String pathBasename(String path) => path.split(Platform.pathSeparator).last;
