// shortcut_cheatsheet.dart —— v2.19.54：? 键快捷键速览（找茬创新提案 1）
//
// 学生在任何算题页按 ?（Shift + /）弹出「本页可用快捷键」卡。键表按
// 主导航 index 逐页点名，⛔ 键名一律引用各宿主的静态常量（TabJumpShortcuts
// .keyLabel / SaveMistakeKeyHost.keyLabel / CurriculumFocusShortcuts.keyLabel）
// ——单一真相，改键位只动宿主一处（B 仓「手写重复第二次就该变成单一真相」
// 教训）。
//
// 形态：HardwareKeyboard 宿主（与三族同论证——焦点落在页面子树外时
// CallbackShortcuts 收不到键）。闸：① 仅 Shift+/（Ctrl/Alt/Meta 同按
// 不认领）② 本页非当前路由 ⇒ 让路 ②b 焦点在 EditableText 里 ⇒ 让路
// （敲题干时按 ? 不弹卡，与同族宿主同款判据）③ 无键表的页（首页/设置等）
// 按了也无声让路——不为空表弹「暂无」，那是噪音（本卡只服务算题页）。
//
// 挂载：HomeShell 在 PageActivationScope 之下、IndexedStack 之外包一层
// （读 scope.currentIndex 用 dependOn——build 期注册依赖，切页自动刷新）。

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../ui/page_activation.dart';
import '../../ui/tab_jump_shortcuts.dart';
import '../big_question_cards_page.dart' show CardPracticeKeyHost;
import '../curriculum_page.dart';
import 'card_link_key_host.dart';
import 'save_mistake_key_host.dart';

/// 一条快捷键说明。
typedef CheatRow = ({String keys, String what});

class ShortcutCheatsheet extends StatefulWidget {
  const ShortcutCheatsheet({super.key, required this.child});

  final Widget child;

  /// 逐页键表。键名引用宿主静态常量（唯一真相）；页名注释对齐
  /// appNavDestinations 的 index，改导航顺序时本表必须同步（守卫钉在
  /// test/shortcut_cheatsheet_test.dart 与 test/nav_order_guard_test.dart）。
  /// v2.19.60 起设置/关于固定末位（index 11/12），故其无键表行保持无；
  /// 变异/遗传病提前到 9/10，键位随之迁移。
  static const Map<int, List<CheatRow>> rowsByPage = {
    // 1 遗传图谱计算：本族三键均未挂载（系谱有自己的键位体系，不在本表）。
    // 2 遗传计算器（9331）
    2: [
      (keys: TabJumpShortcuts.keyLabel, what: TabJumpShortcuts.keyDescription),
      (
        keys: SaveMistakeKeyHost.keyLabel,
        what: SaveMistakeKeyHost.keyDescription
      ),
      (
        keys: CurriculumFocusShortcuts.keyLabel,
        what: CurriculumFocusShortcuts.keyDescription
      ),
      (keys: CardLinkKeyHost.keyLabel, what: CardLinkKeyHost.keyDescription),
    ],
    // 4 课标 / 11 设置 / 12 关于 / 3 知识图谱：未挂本族键。
    // 8 大题套路卡（v2.19.60：Alt+L 去练——只有这一枚本族键）
    8: [
      (
        keys: CardPracticeKeyHost.keyLabel,
        what: CardPracticeKeyHost.keyDescription
      ),
    ],
    // 5 分子（⛔ 本页不挂 Alt+K：`CurriculumFocusShortcuts` 仅 9331 /
    // 遗传病两处实例化，表里写一行就是编造对应关系；K = 看套路卡是
    // v2.19.59 新挂的 CardLinkKeyHost，与 Alt+K 不是一枚键）
    5: [
      (keys: TabJumpShortcuts.keyLabel, what: TabJumpShortcuts.keyDescription),
      (
        keys: SaveMistakeKeyHost.keyLabel,
        what: SaveMistakeKeyHost.keyDescription
      ),
      (keys: CardLinkKeyHost.keyLabel, what: CardLinkKeyHost.keyDescription),
    ],
    // 6 进化（⛔ 本页不挂 Alt+K：同分子页，宿主未实例化；K 行同分子）
    6: [
      (keys: TabJumpShortcuts.keyLabel, what: TabJumpShortcuts.keyDescription),
      (
        keys: SaveMistakeKeyHost.keyLabel,
        what: SaveMistakeKeyHost.keyDescription
      ),
      (keys: CardLinkKeyHost.keyLabel, what: CardLinkKeyHost.keyDescription),
    ],
    // 7 染色体倍性（K 行同分子/进化）
    7: [
      (keys: TabJumpShortcuts.keyLabel, what: TabJumpShortcuts.keyDescription),
      (
        keys: SaveMistakeKeyHost.keyLabel,
        what: SaveMistakeKeyHost.keyDescription
      ),
      (keys: CardLinkKeyHost.keyLabel, what: CardLinkKeyHost.keyDescription),
    ],
    // 9 变异（⛔ 本页不挂 Alt+K：两个 moduleId 均多义，宿主不绑——
    // 表里若写一行就是编造对应关系）
    9: [
      (keys: TabJumpShortcuts.keyLabel, what: TabJumpShortcuts.keyDescription),
      (
        keys: SaveMistakeKeyHost.keyLabel,
        what: SaveMistakeKeyHost.keyDescription
      ),
    ],
    // 10 人类遗传病
    10: [
      (keys: TabJumpShortcuts.keyLabel, what: TabJumpShortcuts.keyDescription),
      (
        keys: SaveMistakeKeyHost.keyLabel,
        what: SaveMistakeKeyHost.keyDescription
      ),
      (
        keys: CurriculumFocusShortcuts.keyLabel,
        what: CurriculumFocusShortcuts.keyDescription
      ),
    ],
  };

  @override
  State<ShortcutCheatsheet> createState() => _ShortcutCheatsheetState();
}

class _ShortcutCheatsheetState extends State<ShortcutCheatsheet> {
  bool _open = false;

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

  /// 焦点是否在 EditableText 内（与 save_mistake_key_host.dart /
  /// tab_jump_shortcuts.dart 同款判据）。⛔ 在学生敲题干时按 ? 不弹卡：
  /// 那是输入的一部分，不是要速览。
  bool get _editingText {
    final focus = FocusManager.instance.primaryFocus;
    final ctx = focus?.context;
    // 焦点挂在 EditableText 内部的 Focus widget 上，须祖先查找。
    return ctx != null &&
        ctx.findAncestorWidgetOfExactType<EditableText>() != null;
  }

  bool _onKey(KeyEvent event) {
    if (event is! KeyDownEvent) return false; // 长按连发不重复弹
    if (event.logicalKey != LogicalKeyboardKey.slash) return false;
    final kb = HardwareKeyboard.instance;
    if (!kb.isShiftPressed) return false;
    if (kb.isControlPressed || kb.isAltPressed || kb.isMetaPressed) {
      return false; // 修饰键精确：Ctrl/Alt/Meta + Shift+/ 不认领
    }
    if (ModalRoute.of(context)?.isCurrent != true) return false; // 闸 ②
    if (_editingText) return false; // 闸 ②b：⛔ 正在敲输入不弹卡
    // 事件回调内读取 scope：用 read（getElementForInheritedWidgetOfExactType，
    // 不注册 build 依赖）——maybeOf 是 dependOn 版，在回调里用会给 element
    // 注册无谓依赖（见 page_activation.dart 读法纪律）。
    final scope = PageActivationScope.read(context);
    final rows = scope == null
        ? null
        : ShortcutCheatsheet.rowsByPage[scope.currentIndex];
    if (rows == null || rows.isEmpty) return false; // 无键表页无声让路
    if (_open) return false; // 已在屏：不叠第二个
    _open = true;
    showDialog<void>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('本页快捷键'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final r in rows)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: Theme.of(dialogCtx)
                            .colorScheme
                            .surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(r.keys,
                          style: const TextStyle(
                              fontFamily: 'monospace',
                              fontWeight: FontWeight.w600)),
                    ),
                    const SizedBox(width: 10),
                    Expanded(child: Text(r.what)),
                  ],
                ),
              ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(),
            child: const Text('知道了'),
          ),
        ],
      ),
    ).whenComplete(() {
      if (mounted) _open = false;
    });
    return true;
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
