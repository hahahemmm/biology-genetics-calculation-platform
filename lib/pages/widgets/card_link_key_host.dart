// card_link_key_host.dart —— v2.19.59 页面级「K 看这道题的套路卡」宿主
// （9331 五个计算面 / 分子 / 进化 / 倍性）
//
// 与 SaveMistakeKeyHost / CurriculumFocusShortcuts / TabJumpShortcuts 同一套
// 论证：CallbackShortcuts 沿焦点链冒泡，焦点落在页面子树之外时收不到键；
// 本宿主走 HardwareKeyboard.addHandler（dispose 摘掉），对不关心的键一律
// 返回 false。
//
// 让路闸（缺一道就会误触发）：
//  ① 非裸 K ⇒ 让路（Ctrl/Alt/Meta 同按都不认领，与 TabJumpShortcuts 口径一致）；
//  ② 本页不是当前路由（被 push 路由 / 对话框盖住）⇒ 让路；
//  ②b 壳内非激活页（IndexedStack 兄弟页）⇒ 让路——⛔ 必须先于一切跳转判断：
//     keep-alive 多页宿主同时存活，非激活页 return true 会把事件从焦点链
//     抽走，饿死激活页内嵌组件自己的快捷键（与 SaveMistakeKeyHost 闸 ②b
//     同一条论证）；
//  ③ 焦点在 EditableText 里 ⇒ 让路——敲到一半的题干里按 K 是输入的一部分；
//  ④ 当前考点没有配套卡（cardId() 返回 null）⇒ 无声让路——⛔ 不许承诺
//     一枚按不动的键：屏上提示与本闸共用同一个判据函数，两处不可能分叉；
//  ⑤ 同一次物理按键的全局互斥：SDK 把同一枚事件实例派发给所有 handler，
//     keep-alive 多宿主（9331 各 tab）时第二枚会把第一枚的跳转再跳一次。
//     已在应答的宿主把事件标记进 Expando，后到宿主见标记即让路。
//
// ⛔ 不渲染任何屏上按钮（键盘优先；按钮会改动全页扫描基线）。屏上提示
// 由各页结果区副标题自带，判据必须与本宿主 cardId() 同一份。

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../ui/page_activation.dart';
import '../../ui/shortcut_nudge.dart';
import '../big_question_cards_page.dart';

/// 页面级「K 看这道题的套路卡」宿主（**零像素**：不渲染任何东西）。
class CardLinkKeyHost extends StatefulWidget {
  const CardLinkKeyHost({
    super.key,
    required this.cardId,
    required this.child,
  });

  /// v2.19.59：键位文案唯一真相（速览表从这里取，⛔ 不许另写一份）。
  static const String keyLabel = 'K';
  static const String keyDescription =
      '跳到这道题的套路卡（当前考点有配套卡才应答；正在敲输入时不跳转）';

  /// 按下 K **那一刻**现取的配套卡 id。⛔ 必须是 ValueGetter：TabBarView
  /// 切页签不让页面 State rebuild，构造参数会滞留已切走的页签的考点。
  /// 返回 null = 当前考点没有配套卡 ⇒ 无声让路（闸 ④）。
  final String? Function() cardId;

  final Widget child;

  @override
  State<CardLinkKeyHost> createState() => _CardLinkKeyHostState();
}

class _CardLinkKeyHostState extends State<CardLinkKeyHost> {
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
    // （与同族宿主同款写法）。
    return ctx != null && ctx.findAncestorWidgetOfExactType<EditableText>() != null;
  }

  /// `HardwareKeyboard.addHandler` 的签名是 `bool Function(KeyEvent)`
  /// ——false = 不认领，事件继续走既有通路。
  bool _onKey(KeyEvent event) {
    if (event is! KeyDownEvent) return false; // 长按连发（KeyRepeatEvent）让路
    if (event.logicalKey != LogicalKeyboardKey.keyK) return false; // 闸 ①
    // 修饰键精确：Ctrl+K / Alt+K / Meta+K 都不认领（Alt+K 是课标聚焦，
    // 归 CurriculumFocusShortcuts 自己答）。
    if (HardwareKeyboard.instance.isControlPressed) return false;
    if (HardwareKeyboard.instance.isAltPressed) return false;
    if (HardwareKeyboard.instance.isMetaPressed) return false;
    // 闸 ②：被别的路由盖住（对话框、push 出来的二级页）⇒ 让路。
    if (ModalRoute.of(context)?.isCurrent != true) return false;
    // 闸 ②b：壳内非激活页让路（必须先于一切跳转判断，论证见文件头）。
    if (!isPageKeyActive(context)) return false;
    if (_editingText) return false; // 闸 ③：敲到一半的题干里按 K 是输入
    // 闸 ④：当前考点没有配套卡 ⇒ 无声让路（与屏上提示同一个判据）。
    final id = widget.cardId();
    if (id == null) return false;
    // 闸 ⑤：同一次物理按键的全局互斥（论证见文件头）。
    if (_consumed[event] == true) return false;
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => BigQuestionCardsPage(initialCardId: id),
    ));
    _consumed[event] = true;
    ShortcutNudge.maybeNotify(context); // 首次成功触发给 ? 速览指引
    return true;
  }

  /// 同键互斥的标记位（见闸 ⑤）。Expando 以事件对象身份为键——同一次
  /// 物理按键派发的是同一枚 KeyEvent 实例，跨宿主共享。
  static final Expando<bool> _consumed = Expando<bool>('cardLinkConsumed');

  @override
  Widget build(BuildContext context) => widget.child;
}
