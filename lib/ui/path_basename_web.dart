// path_basename_web.dart —— Web「取路径最后一段」（web 桩）。
//
// 现实触发条件：mistake_book_page.dart 在 web 端走「已触发浏览器下载」
// 分支，saved 是文案不是文件路径，根本不调用本函数。这里 stub 实现
// 返原串即满足条件导入，web 编译通过 + 运行时若意外调用也不抛。

export 'path_basename_stub.dart';

String pathBasename(String path) => path;
