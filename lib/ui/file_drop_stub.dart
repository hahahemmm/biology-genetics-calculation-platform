// file_drop_stub.dart —— 拖拽入窗桩（非 IO/HTML 平台 + 测试兜底）。
//
// typedef 放在 stub（与 image_pick_stub.dart 的 PickedImage 同理）：
// io/web 实现从这里 `show FileDropHandler` re-export，保证全平台拿到
// 同一声明；纯 Dart 单测（VM 平台）也可直接 import 本文件覆盖。

/// 原生侧拖入文件回调：参数为 UTF-8 文件路径列表（Windows runner
/// WM_DROPFILES 转发；一次拖入多文件 = 一个列表）。
typedef FileDropHandler = void Function(List<String> paths);

/// 注册窗口级拖入回调（App 启动时调一次）。桩平台 no-op。
void initFileDrop(FileDropHandler onFiles) {}
