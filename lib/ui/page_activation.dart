// page_activation.dart —— v2.19.52：页面级键宿主的「激活页」闸基建
//
// 背景（找茬 P1，2026-10-09 取证）：HomeShell 用 IndexedStack + Visibility
// (maintainState) 常驻全部 10 页 ⇒ 每页注册的 HardwareKeyboard handler
// **同时存活**；而宿主原有的「闸②ModalRoute.isCurrent」对壳内非激活页
// 恒 true（10 页同属一条壳路由）⇒ 按一次 Ctrl+S 五页全部写库、Alt+数字
// 六页全部切页签、且任一宿主 return true 会把事件从焦点链抽走（SDK 语义：
// 所有 handler 都收事件，返回值只做 OR 汇总，handled=true ⇒ 焦点系统收不到）
// —— 遗传病 tab1 内嵌视图既有的 CallbackShortcuts Ctrl+S 被这样饿死过。
//
// 结构：HomeShell 在 IndexedStack 外放 [PageActivationScope]（携带当前
// 激活 index），每个子页外包 [PageActivationMarker]（携带自己的 index）。
// 宿主在键事件里用 [isPageKeyActive] 判定：
//   - 两个标记都在 ⇒ 激活 = scope.currentIndex == marker.pageIndex
//   - 都缺 ⇒ 页面是独立路由（push 形态 / 单页测试 home: 泵）⇒ 视为激活
//     （push 路由自有 ModalRoute.isCurrent 闸把关，见各宿主闸②）
//   - 只有一个 ⇒ 接线不完整 ⇒ 按激活处理（⛔ 不静默杀功能），debug 打印
//
// ⛔ 读法纪律：宿主在**键事件回调**里调用 [isPageKeyActive]，不是 build
// ⇒ 内部一律用 getElementForInheritedWidgetOfExactType（不注册依赖），
// ⛔ 不许用 dependOnInheritedWidgetOfExactType（非 build 期调用会抛）。

import 'package:flutter/widgets.dart';

/// 壳层标记：当前激活的导航 index（HomeShell 的 _index）。
class PageActivationScope extends InheritedWidget {
  const PageActivationScope({
    super.key,
    required this.currentIndex,
    required super.child,
  });

  final int currentIndex;

  /// 事件回调内安全读取（不注册 build 依赖）。
  static PageActivationScope? read(BuildContext context) {
    final el = context
        .getElementForInheritedWidgetOfExactType<PageActivationScope>();
    final w = el?.widget;
    return w is PageActivationScope ? w : null;
  }

  /// build 期读取（注册依赖，scope.currentIndex 变化时自动 rebuild）。
  /// ⛔ 只许在 build 里用；键事件回调里用 [read]。
  static PageActivationScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<PageActivationScope>();

  @override
  bool updateShouldNotify(PageActivationScope oldWidget) =>
      oldWidget.currentIndex != currentIndex;
}

/// 子页标记：本页自己的导航 index（IndexedStack children 的逐个包裹）。
class PageActivationMarker extends InheritedWidget {
  const PageActivationMarker({
    super.key,
    required this.pageIndex,
    required super.child,
  });

  final int pageIndex;

  /// 事件回调内安全读取（不注册 build 依赖）。
  static PageActivationMarker? read(BuildContext context) {
    final el = context
        .getElementForInheritedWidgetOfExactType<PageActivationMarker>();
    final w = el?.widget;
    return w is PageActivationMarker ? w : null;
  }

  @override
  bool updateShouldNotify(PageActivationMarker oldWidget) =>
      oldWidget.pageIndex != pageIndex;
}

/// 页面级键宿主的激活判定。语义见文件头：
/// 双标记按 index 相等判激活；双缺（独立路由/测试）视为激活；
/// 单缺（接线不完整）按激活处理并 debug 打印。
bool isPageKeyActive(BuildContext context) {
  final scope = PageActivationScope.read(context);
  final marker = PageActivationMarker.read(context);
  if (scope == null && marker == null) return true;
  if (scope == null || marker == null) {
    assert(() {
      debugPrint('[page_activation] 接线不完整：scope=${scope == null ? '缺' : '有'} '
          'marker=${marker == null ? '缺' : '有'}，按激活处理');
      return true;
    }());
    return true;
  }
  return scope.currentIndex == marker.pageIndex;
}
