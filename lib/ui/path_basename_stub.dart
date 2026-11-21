// path_basename_stub.dart —— 跨端「取路径最后一段」中性格（v2.13 R5 P1A 配套）。
//
// 唯一调用：mistake_book_page.dart SnackBar 提示「错题本已导出：xxx」。
// 桌面（Windows / macOS / Linux）：saved 是文件路径，要按 / 或 \ 切尾。
// Android：saved 是应用专属目录文件路径——但导出分支会走
//   「已保存到应用目录（可导出/分享）」独立文案，不走到本函数，
//   所以 Android 也视为可走 stub（仅防 web 兜底用）。
// Web：saved 是「已触发浏览器下载」前缀的提示文案——根本不是文件路径，
//   走不到本函数。stub 直接返原串，web 编译通过即可。

/// 把 [path] 切到最后一段。桌面按 / 或 \，其他平台（含 Web）返原串。
String pathBasename(String path) => path;
