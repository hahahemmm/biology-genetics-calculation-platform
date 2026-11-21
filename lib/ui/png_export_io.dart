// png_export_io.dart —— 桌面/安卓 PNG 落盘（dart:io）。
// v2.11 M10：落应用沙盒（~/.biology_app/Pictures/Biology板书），
// 失败回退到公共 Pictures 目录（兼容安卓需公共图库的场景）。
// 无新增依赖（不引 path_provider；直接读 USERPROFILE 环境变量）。
//
// 目录优先级：
// 1. Windows 应用沙盒 = $USERPROFILE/.biology_app/Pictures/Biology板书
//    （与 settings_page 的 ~/.biology_app 同一根，应用专属目录）
// 2. Windows 公共 Pictures（v2.10 行为，向后兼容老用户文件位置）
// 3. Android（v2.13 R4-2 P1-2 EACCES 修复）：
//    公共 Pictures = /storage/emulated/0/Pictures/Biology板书 在
//    targetSdk 35 scoped storage + 零存储权限下必抛 EACCES。改走
//    userAppDir()（= <getFilesDir>/.biology_app，R3 W1 已修好），
//    应用专属目录无需任何权限。

import 'dart:io';
import 'dart:typed_data';

import '../storage/platform_storage_io.dart';

Future<({String? path, String? error})> writePng(Uint8List bytes,
    String prefix,
    {String? debugDir}) async {
  try {
    final ts = DateTime.now()
        .toIso8601String()
        .replaceAll(':', '')
        .replaceAll('-', '')
        .split('.')
        .first;
    final fileName = '${prefix}_$ts.png';
    if (debugDir != null) {
      final d = Directory(debugDir)..createSync(recursive: true);
      final f = File('${d.path}${Platform.pathSeparator}$fileName');
      await f.writeAsBytes(bytes, flush: true);
      return (path: f.path, error: null);
    }
    // v2.13 R4-2（P1-2 EACCES 修复）：Android 导出前先等 getFilesDir()
    // 缓存就绪，保证 userAppDir() 拿到真实应用专属目录。桌面 no-op。
    await ensureAppDirReady();
    final home = Platform.environment['USERPROFILE'] ??
        Platform.environment['HOME'];
    final candidates = <String>[
      // v2.11 M10：Windows 应用沙盒（首选）
      if (!Platform.isAndroid && home != null)
        '$home${Platform.pathSeparator}.biology_app${Platform.pathSeparator}Pictures${Platform.pathSeparator}Biology板书',
      // v2.10 行为：Windows 公共 Pictures（向后兼容老导出文件位置）
      if (Platform.environment.containsKey('USERPROFILE'))
        '${Platform.environment['USERPROFILE']}\\Pictures\\Biology板书',
      // Android（v2.13 R4-2）：应用专属目录（getFilesDir 下，无需权限）
      if (Platform.isAndroid && userAppDir() != null)
        '${userAppDir()}${Platform.pathSeparator}Pictures${Platform.pathSeparator}Biology板书',
    ];
    for (final dir in candidates) {
      try {
        final d = Directory(dir)..createSync(recursive: true);
        final f = File('${d.path}${Platform.pathSeparator}$fileName');
        await f.writeAsBytes(bytes, flush: true);
        return (path: f.path, error: null);
      } catch (_) {
        continue;
      }
    }
    return (path: null, error: '未找到可写的图片目录');
  } catch (e) {
    return (path: null, error: '写文件失败：$e');
  }
}
