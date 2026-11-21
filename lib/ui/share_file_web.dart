// share_file_web.dart —— 分享文件（Web 桩）。
//
// Web 端导出走 <a download> 触发浏览器下载，无系统分享面板概念 →
// 返回错误原因（调用方不显示分享按钮）。

Future<String?> shareFile(String path, {String? mimeType}) async =>
    '当前平台不支持分享';