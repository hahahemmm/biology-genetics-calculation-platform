// share_file.dart —— 导出文件分享到系统分享面板（v2.13 R4-2 P1-2 配套）。
//
// 场景（Android 主力路径）：
//   - 学生导出错题 JSON → 分享到微信/QQ
//   - 老师导出板书 PNG → 分享到微信群
//
// 背景：Android 零存储权限 + targetSdk 35 scoped storage 下，导出文件
// 只落应用专属目录（getFilesDir，见 mistake_book._resolveDownloadsDir /
// png_export_io.writePng），分享目标（微信/QQ）看不到私有目录 → 必须
// 经 FileProvider 暴露为 content:// URI 再走 Intent.ACTION_SEND。
// 零插件约束：MethodChannel `biology/share_file` → MainActivity.kt
//（与 image_pick / json_pick / app_dir 同模式）。
//
// 沿用 image_pick.dart / json_pick.dart 的条件导入模式：
//   - Android：MethodChannel 拉起系统分享面板
//   - 桌面 / Web：无系统分享面板概念，返回错误原因（调用方隐藏按钮）

import 'share_file_io.dart'
    if (dart.library.html) 'share_file_web.dart' as impl;

/// 把 [path] 文件分享出去（Android 拉起系统分享面板）。
///
/// 返回 null = 已发起分享；非 null = 错误原因（可直接 SnackBar 显示，
/// 如「当前平台不支持分享」/ 文件不存在 / 无分享目标）。
/// 调用方仅在 Android（MistakeBookExporter.isAndroidExport）显示分享按钮。
Future<String?> shareFile(String path, {String? mimeType}) =>
    impl.shareFile(path, mimeType: mimeType);