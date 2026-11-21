// file_drop_web.dart —— Web 端拖拽入窗（no-op）。
//
// 待 HTML5 drop 接入：浏览器端没有本地文件路径概念，拖入的是 File
// 对象（bytes 直读），链路与 Windows 的「路径 → File.readAsBytes」
// 不同——接入时应走 dataTransfer drop 事件 → PickedImage.bytes，再
// publish 到 FileDropBus，消费协议不变。当前 Web 不是第一优先平台，
// 先 no-op 保证编译与协议完整。

import 'file_drop_stub.dart';

export 'file_drop_stub.dart' show FileDropHandler;

/// Web no-op（见文件头注释：待 HTML5 drop 接入）。
void initFileDrop(FileDropHandler onFiles) {}
