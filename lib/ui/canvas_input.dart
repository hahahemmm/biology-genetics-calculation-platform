// canvas_input.dart —— 自绘画布共用的桌面/白板输入约定
//
// Windows 触控屏可能给应用原生触点，也可能由驱动/系统把手势转成
// PointerScrollEvent。统一约定：滚动输入平移，Ctrl/Meta+滚轮才缩放。
// 页面只负责把事件接进来，不各自猜测设备品牌或驱动型号。

import 'package:flutter/services.dart';

/// 当前是否按住画布缩放修饰键。Meta 一并支持桌面平台习惯。
bool get canvasZoomModifierPressed =>
    HardwareKeyboard.instance.isControlPressed ||
    HardwareKeyboard.instance.isMetaPressed;

/// 按屏幕像素平移视口，不受当前画布缩放倍率影响。
///
/// 必须左乘平移矩阵；在当前矩阵后追加 translate 会把位移再乘一次缩放，
/// 例如 80% 缩放下 35px 拖动只移动 28px，白板上表现为「不跟手」。
Matrix4 canvasPanByScreenDelta(Matrix4 current, Offset viewportDelta) =>
    Matrix4.translationValues(viewportDelta.dx, viewportDelta.dy, 0)
      ..multiply(current);

/// 将滚动增量换算成视口平移：向下/向右滚动时，内容向反方向移动。
Matrix4 canvasPanAfterScroll(Matrix4 current, Offset scrollDelta) =>
    canvasPanByScreenDelta(current, -scrollDelta);
