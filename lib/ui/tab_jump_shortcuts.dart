// tab_jump_shortcuts.dart —— v2.19.49：Alt+数字 页签直跳宿主（六个多页签页）
//
// 为什么是这个形态（而不是 CallbackShortcuts / App 级集中注册表）：
// 与 curriculum_page.dart 的 CurriculumFocusShortcuts 同一套论证——键事件
// 从 primaryFocus 沿焦点链冒泡，页面级宿主只是路由焦点域的子节点，焦点
// 落在 Rail / FAB / 刚点过的按钮上时事件根本到不了页面里的 CallbackShortcuts
// （Alt+K 那一轮实测两条用例全红）。⇒ 本宿主在 initState 挂
// HardwareKeyboard.addHandler（dispose 摘掉），对不关心的键一律返回 false，
// 不改变任何既有行为。
// ⛔ App 级集中注册表（备份仓 B 的 active_shortcut_handlers，~120KB）本仓
// 明确不造——六个页每页一个本宿主即够，cross_calculator_page.dart 里同款
// 口径（「后续轮次」评估后仍不值：为六个零像素宿主引入全局派发层）。
//
// 语义：**只切页签**。⛔ 不写任何 controller、不触发深链填参（带题是
// ModuleFillBus 另一套语义）。按过之后本页输入内容、已算结果、当前页签
// 之外的滚动位置逐项不动（守卫网逐项钉住）。
//
// 让路闸（缺一道就会误触发）：
//  ① 非 Alt+主键盘数字(1..9) ⇒ 让路。裸数字不触发——错题本复习对话框的
//     裸 1/2/3 自评键与本键并存，靠修饰键区分；numpad 不认领（与 B 仓
//     SingleActivator(digitN) 键表同源）。
//  ② Ctrl / Meta 同按 ⇒ 让路。裸数字（无修饰键）是 HomeShell 的页面
//     导航键（main.dart SingleActivator(digitN)），修饰键精确才不互抢；
//     Ctrl+Alt+数字无人认领、原样让路。
//  ③ 本页不是当前路由（被 push 路由 / 对话框盖住）⇒ 让路。
//  ④ 焦点在 EditableText 里（学生正在敲基因型 / 数字）⇒ 让路。
//  ⑤ 目标页签越界（页只有 3 个页签却按了 Alt+4）⇒ 让路——键原样放行，
//     不写数据、不弹看不见的回执。
// 长按连发：只认 KeyDownEvent（KeyRepeatEvent 直接让路）。

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'page_activation.dart';
import 'shortcut_nudge.dart';

/// `Alt+1`–`Alt+9` → 页签下标 0–8 直跳（**零像素**：不渲染任何东西）。
///
/// 目标页签在**按下那一刻**现算（digit − 1），不存在「build 时算一次、
/// 切页签后仍跳旧那一栏」的过期绑定。越界（≥ [TabController.length]）
/// 按让路处理，见文件头闸 ⑤。
class TabJumpShortcuts extends StatefulWidget {
  const TabJumpShortcuts({
    super.key,
    required this.tab,
    required this.child,
  });

  /// v2.19.54：键位文案的唯一真相（快捷键速览表 [ShortcutCheatsheet]
  /// 从这里取，⛔ 速览表不许另写一份键名——B 仓「同一类手写重复第二次
  /// 出现时就该变成单一真相」的教训）。
  static const String keyLabel = 'Alt + 1 … 9';
  static const String keyDescription = '直达第几个页签（超出本页页签数不响应）';

  /// 本页的 TabController。宽窄两档（ToolWorkbench）共用同一个 controller
  /// ⇒ 切页签机制与屏宽无关。
  final TabController tab;

  final Widget child;

  @override
  State<TabJumpShortcuts> createState() => _TabJumpShortcutsState();
}

class _TabJumpShortcutsState extends State<TabJumpShortcuts> {
  /// 主键盘 digit1..digit9 → 目标下标。⛔ 不能 const：LogicalKeyboardKey
  /// 重写了 ==（const map 的键不允许非原始相等），故为 `static final`。
  static final _digits = <LogicalKeyboardKey, int>{
    LogicalKeyboardKey.digit1: 0,
    LogicalKeyboardKey.digit2: 1,
    LogicalKeyboardKey.digit3: 2,
    LogicalKeyboardKey.digit4: 3,
    LogicalKeyboardKey.digit5: 4,
    LogicalKeyboardKey.digit6: 5,
    LogicalKeyboardKey.digit7: 6,
    LogicalKeyboardKey.digit8: 7,
    LogicalKeyboardKey.digit9: 8,
  };

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_onKey);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKey);
    super.dispose();
  }

  bool get _editingText {
    final focus = FocusManager.instance.primaryFocus;
    final ctx = focus?.context;
    // 焦点挂在 EditableText 内部的 Focus widget 上，须祖先查找
    // （与 curriculum_page.dart 的宿主同款写法）。
    return ctx != null && ctx.findAncestorWidgetOfExactType<EditableText>() != null;
  }

  /// `HardwareKeyboard.addHandler` 的签名是 `bool Function(KeyEvent)`
  /// ——false = 不认领，事件继续走既有通路。
  bool _onKey(KeyEvent event) {
    if (event is! KeyDownEvent) return false; // 长按连发（KeyRepeatEvent）让路
    final target = _digits[event.logicalKey];
    if (target == null) return false; // 闸 ①：非本键
    if (!HardwareKeyboard.instance.isAltPressed) return false;
    if (HardwareKeyboard.instance.isControlPressed) return false; // 闸 ②
    if (HardwareKeyboard.instance.isMetaPressed) return false; // 闸 ②
    // 闸 ③：被别的路由盖住（对话框、push 出来的二级页）⇒ 让路。
    if (ModalRoute.of(context)?.isCurrent != true) return false;
    // 闸 ③b（v2.19.52 找茬 P1）：壳内非激活页（IndexedStack 兄弟页的
    // handler 同时存活）⇒ 让路。独立路由/单页测试无标记 ⇒ 视为激活
    // （路由闸已把关）。
    if (!isPageKeyActive(context)) return false;
    if (_editingText) return false; // 闸 ④：⛔ 正在敲输入
    if (target >= widget.tab.length) return false; // 闸 ⑤：越界让路
    widget.tab.animateTo(target);
    ShortcutNudge.maybeNotify(context); // v2.19.54：首次成功触发给 ? 速览指引
    return true;
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
