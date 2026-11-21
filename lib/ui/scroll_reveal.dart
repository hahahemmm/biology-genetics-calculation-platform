// scroll_reveal.dart —— 「把已挂载元素滚进最近可滚动视口」的共享小工具（v2.20.0）
//
// ## 为什么不用 Scrollable.ensureVisible 原样调
//
// · `alignmentPolicy: explicit`（默认）会**无条件**把目标对齐到 alignment：
//   目标本来就完整可见时也会跳一下（把已可见项顶到视口起点）——M3.1 评审
//   实锤 main.dart 旧实现踩的就是这个：连续 keepVisibleAtEnd +
//   keepVisibleAtStart 两次调用，第二次把已经可见的导航项对齐到了起点，
//   而注释还反过来写「已可见时两者都是 no-op」。
// · `keepVisibleAtStart` / `keepVisibleAtEnd` 各自只兜**一个方向**，且
//   语义是「保住视口某一端」，不是「保住整个目标」，连调两次并不等于双侧兜底。
//
// ## 本 helper 的语义（先量后滚，只滚一次）
//
// 用 `RenderAbstractViewport.getOffsetToReveal` 把目标换算成**滚动偏移空间**
// 的位置（因此横滚 / 竖滚 / reverse 轴共用同一套判断，不手算指针坐标差）：
//   · start = 让目标起点贴视口起点所需的 offset
//   · end   = 让目标终点贴视口终点所需的 offset
// 两者都 clamp 到 [minScrollExtent, maxScrollExtent]——否则「目标在视口外
// 但内容还不足以滚动」这种情形会算出负 offset，被误判成「需要滚」。
//
//   · 已完整可见（start ≥ pixels - tol 且 end ≤ pixels + tol）→ **直接返回**，
//     一个像素都不动；
//   · 只在起点外侧（start < pixels）→ 以 alignment 0.0 滚**一次**；
//   · 只在终点外侧（end > pixels）→ 以 alignment 1.0 滚**一次**。
//
// ## 使用约定
//
// · 目标必须在 `Scrollable` 之下（否则 `Scrollable.maybeOf` 为 null ⇒ no-op）。
// · 当前只量最近一层 viewport，但 `Scrollable.ensureVisible` 会继续处理外层
//   scrollable；因此目标不得位于嵌套滚动容器里，否则内层已可见时外层仍可能
//   被对齐。需要那种场景时应显式拆分内外层揭示，而不是直接复用本函数。
// · 调用方负责**排队去重**（通常 postFrame + 一个 bool 哨兵）：本函数返回
//   是否真的滚了，方便「连续请求只执行最后一次」的调用方自己控制。
// · 默认 `duration: Duration.zero`（jump，导航切页用）；需要动画时由调用方
//   传 duration，并在动画期间避免重复发起。

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// 可见性判定容差（亚像素舍入，0.5 逻辑像素）。
const double kScrollRevealTolerance = 0.5;

/// 把 [context] 对应元素滚进最近的可滚动视口——**已完整可见时是 no-op**。
///
/// 返回 true 表示确实发起了滚动（含动画启动），false 表示无需滚动或
/// 目标不在可滚动容器内 / 尚未完成布局。
Future<bool> revealInViewport(
  BuildContext context, {
  Duration duration = Duration.zero,
  Curve curve = Curves.easeOutCubic,
  double tolerance = kScrollRevealTolerance,
}) async {
  // 挂载检查放在最前：调用方常从 postFrame / 异步回调进来，
  // 元素可能已经随页面销毁（context.findRenderObject 会断言）。
  if (!context.mounted) return false;
  final renderObject = context.findRenderObject();
  if (renderObject is! RenderBox || !renderObject.attached) return false;

  final scrollable = Scrollable.maybeOf(context);
  final viewport = RenderAbstractViewport.maybeOf(renderObject);
  if (scrollable == null || viewport == null) return false;

  final position = scrollable.position;
  // 首帧 / 布局未完成时拿不到内容尺寸，先放过（postFrame 的下一帧自然会再来）。
  if (!position.hasPixels || !position.hasContentDimensions) return false;

  final axis = position.axis;
  final start = viewport
      .getOffsetToReveal(renderObject, 0.0, axis: axis)
      .offset
      .clamp(position.minScrollExtent, position.maxScrollExtent);
  final end = viewport
      .getOffsetToReveal(renderObject, 1.0, axis: axis)
      .offset
      .clamp(position.minScrollExtent, position.maxScrollExtent);
  final pixels = position.pixels;

  final startsBefore = start < pixels - tolerance;
  final endsAfter = end > pixels + tolerance;
  if (!startsBefore && !endsAfter) return false; // 已完整可见：no-op

  await Scrollable.ensureVisible(
    context,
    // 方向决定对齐边：从起点外侧来就贴起点，从终点外侧来就贴终点。
    // 两侧都超（目标比视口还长）时贴起点，至少让开头可读。
    alignment: startsBefore ? 0.0 : 1.0,
    duration: duration,
    curve: curve,
  );
  return true;
}
