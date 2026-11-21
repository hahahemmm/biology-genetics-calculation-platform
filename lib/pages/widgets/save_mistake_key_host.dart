// save_mistake_key_host.dart —— v2.19.51 页面级「Ctrl+S 存进错题本」宿主
// （分子 / 进化 / 倍性 / 变异 / 遗传病 五个算题页）
//
// 为什么新写一个宿主、不复用 SaveToMistakeBookShortcuts（CallbackShortcuts
// 形态）：与 CurriculumFocusShortcuts / TabJumpShortcuts 同一套论证——
// CallbackShortcuts 沿焦点链冒泡，焦点落在页面子树之外（push 返回后的
// Navigator Scope）时根本收不到键 ⇒ 「快捷键看着存在、按了没反应」。
// 本宿主走 HardwareKeyboard.addHandler（dispose 摘掉），对不关心的键一律
// 返回 false。
//
// 让路闸（缺一道就会误触发）：
//  ① 非 Ctrl+S ⇒ 让路（裸 S / Alt+Ctrl+S 都不认领）；
//  ② 本页不是当前路由（被 push 路由 / 对话框盖住）⇒ 让路；
//  ③ 焦点在 EditableText 里 ⇒ 让路——⛔ 敲到一半的题干不存：存了比不存更糟，
//     学生看到半串基因型进错题本会以为软件坏了。失焦后同一枚键必存，
//     守卫须成对钉住「持焦让路 / 失焦必存」两态；
//  ④ payload 为 null ⇒ 让路——**只有**「当前页签根本没有计算器」才允许返回
//     null（给没有计算器的页签配题干是编造数据，按了必须无声让路）。
//     「有计算器但还没算出结果」⛔ 不许返回 null——照常传（answer 为空串），
//     由 saveToMistakeBook 既有的「先算出结果，再存入错题本」SnackBar
//     守卫应答（与 9331 页级快捷键同一条 UX，不另写一套提示）。
//
// 为什么 payload 是**按下那一刻**才调的 ValueGetter（B 仓 v2.19.173 worker
// 抓到真 bug 的根治）：ToolWorkbench 的 TabBarView 切页签**不让页面 State
// rebuild**——把题干当构造参数收的宿主，切到 tab1 未算就按 Ctrl+S 会把
// **已切走的 tab0 那道题**写进错题本。ValueGetter 在按键瞬间现读 State 与
// tab.index，过期窗由构造不存在。
//
// ⛔ 不渲染任何屏上按钮（B 仓同款裁定：键盘优先 + 按钮会实打实改动全页
// 扫描基线）；老师角色守卫由 saveToMistakeBook 内继承（SnackBar 说明、不写入）。

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../ui/page_activation.dart';
import '../../ui/shortcut_nudge.dart';
import 'save_to_mistake_book.dart';

/// Ctrl+S 一键存题的一次性载荷（按下那一刻现组装，见文件头）。
class SavePayload {
  const SavePayload({
    required this.stem,
    required this.correctAnswer,
    required this.subjectArea,
    this.userAnswer = '',
    this.srcModule,
    this.srcParams,
  });

  /// 题干（调用方从当前输入自动拼装，如 'AaBb × AaBb 杂交，F₂ 表型比？'）。
  final String stem;

  /// 正确答案（比例/结论文本）。
  final String correctAnswer;

  /// 考点/模块标签（错题本「考点」字段）。
  final String subjectArea;

  /// 学生的作答；空 = 收藏语义。⛔ 只收学生真写下的东西，屏上占位串不是作答。
  final String userAnswer;

  /// 来源 moduleId：⛔ 只传 ModuleFillBus **真 target**（apply 不是 (_) => false
  /// 的 pushFactory 壳）的 id，否则错题本会出现一枚点下去必然被拒的回程按钮。
  /// 该页签没有可回填深链时**必须**留空。
  final String? srcModule;

  /// 存进来那一刻的参数（`{'p1':…, 'p2':…}`），供回程重算回填。
  final Map<String, String>? srcParams;
}

/// 页面级 Ctrl+S 宿主（**零像素**：不渲染任何东西）。
class SaveMistakeKeyHost extends StatefulWidget {
  const SaveMistakeKeyHost({
    super.key,
    required this.payload,
    required this.child,
  });

  /// v2.19.54：键位文案唯一真相（速览表从这里取，⛔ 不许另写一份）。
  static const String keyLabel = 'Ctrl + S';
  static const String keyDescription =
      '把当前页签的题存入错题本（正在敲输入时不存；未算出结果会提示先计算）';

  /// 按下 Ctrl+S **那一刻**现取的载荷。返回 null 只允许一种情况：当前
  /// 页签**没有计算器**（编造题干闸）；「未算出结果」照常传空答案、由
  /// saveToMistakeBook 的既有 SnackBar 守卫应答。
  final SavePayload? Function() payload;

  final Widget child;

  @override
  State<SaveMistakeKeyHost> createState() => _SaveMistakeKeyHostState();
}

class _SaveMistakeKeyHostState extends State<SaveMistakeKeyHost> {
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
    if (event.logicalKey != LogicalKeyboardKey.keyS) return false; // 闸 ①
    if (!HardwareKeyboard.instance.isControlPressed) return false;
    // Alt+Ctrl+S / Ctrl+Meta+S 都不认领（与 TabJumpShortcuts 修饰键口径一致）。
    if (HardwareKeyboard.instance.isAltPressed) return false;
    if (HardwareKeyboard.instance.isMetaPressed) return false;
    // 闸 ②：被别的路由盖住（对话框、push 出来的二级页）⇒ 让路。
    if (ModalRoute.of(context)?.isCurrent != true) return false;
    // 闸 ②b（v2.19.52 找茬 P1）：壳内非激活页让路——⛔ 这条必须先于一切
    // 写库判断：五页 handler 同时存活时，非激活页 return true 会把事件
    // 从焦点链抽走（SDK：handler 返回值 OR 汇总，true ⇒ 焦点系统收不到），
    // 饿死激活页内嵌组件自己的快捷键。非激活页必须 return false 让路。
    if (!isPageKeyActive(context)) return false;
    if (_editingText) return false; // 闸 ③：⛔ 敲到一半的题干不存
    final p = widget.payload();
    if (p == null) return false; // 闸 ④：当前页签没有计算器 ⇒ 无声让路
    // 闸 ⑤（v2.19.57 找茬 B1）：同一次按键的全局互斥——SDK 会把同一
    // 枚事件对象派发给**所有** handler（返回值只 OR 汇总），CallbackShortcuts
    // 时代「内层消费、外层收不到」的语义不复存在。同页多宿主（如 9331
    // 各 tab 输入面板 + 结果区各一枚）时，第二枚会把第一枚的「已加入
    // 错题本（含撤销）」回执顶成「已在错题本里」。已在应答的宿主把事件
    // 标记进 Expando，后到宿主见标记即让路——一次按键最多一次应答。
    if (_consumed[event] == true) return false;
    saveToMistakeBook(
      context,
      stem: p.stem,
      correctAnswer: p.correctAnswer,
      subjectArea: p.subjectArea,
      userAnswer: p.userAnswer,
      srcModule: p.srcModule,
      srcParams: p.srcParams,
    );
    _consumed[event] = true;
    ShortcutNudge.maybeNotify(context); // v2.19.54：首次成功触发给 ? 速览指引
    return true;
  }

  /// 同键互斥的标记位（见闸 ⑤）。Expando 以事件对象身份为键——同一次
  /// 物理按键派发的是同一枚 KeyEvent 实例，跨宿主共享。
  static final Expando<bool> _consumed = Expando<bool>('saveMistakeConsumed');

  @override
  Widget build(BuildContext context) => widget.child;
}
