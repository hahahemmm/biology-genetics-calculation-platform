// path_basename.dart —— 跨端「取路径最后一段」条件导入门面。
//
// 唯一调用：mistake_book_page.dart SnackBar 提示「错题本已导出：xxx」。
// 沿用 image_pick.dart / json_pick.dart 的条件导入模式：
//   - 桌面 / Android：path_basename_io.dart（用 Platform.pathSeparator）
//   - Web：path_basename_web.dart（返原串，实际不会调用）
//
// 历史背景：v2.13 R5 P1A 配套——mistake_book_page.dart 是项目内
// 唯一未走条件导入却 `import 'dart:io'` 直接调 Platform.* 的页面
// 文件（其他 16 个 IO 调用点全部走 `if (dart.library.html)` 切到
// *_web.dart）。C verifier 确认 web build 仍绿（实际分支不会执行
// `Platform.pathSeparator`，导出成功提示走「已触发浏览器下载」独立
// 文案），但形式违规需统一。

export 'path_basename_io.dart'
    if (dart.library.html) 'path_basename_web.dart';
