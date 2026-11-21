// curriculum_page.dart —— 课标体系（必修2《遗传与进化》内容要求树）
//
// 数据：lib/data/curriculum_2020.dart（22 条次位概念，课标原文逐字）。
// 呈现：大概念 → 重要概念 → 次位概念树；每条含编号/原文/高考热度★/
// 关联工具 chip。窄屏友好（ExpansionTile + ListView 滚动）。

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/curriculum_2020.dart';
import '../guide/guide_keys.dart';
import '../theme.dart';
import '../ui/ai_chat_controller.dart';
import '../ui/assistant_panel.dart';
import '../ui/module_fill.dart';
import '../ui/page_activation.dart';
import '../ui/shortcut_nudge.dart';
import 'widgets/side_nav_workbench.dart';
import 'cross_calculator_page.dart';
import 'evolution_page.dart';
import 'genetic_disease_page.dart';
import 'genetic_pedigree_page.dart';
import 'knowledge_graph_page.dart';
import 'molecular_page.dart';
import 'variation_page.dart';

/// 一条「课标 code ↔ 工具 moduleId」的**反向**锚点。
///
/// 反向徽章运行时**只**需要 [code]（跳本页 + 高亮那一条）；`moduleId`
/// 是给守卫用的，也是 [curriculumReverseCodeOf] 的输入。
typedef CurriculumReverseAnchor = ({
  /// 课标条目 `code`（必须真实存在于 `curriculum_2020.dart`）。
  String code,

  /// 屏上徽章原文，口径 = 「课标 X」。
  String badgeLabel,

  /// 该课标条目点名到的工具，已在 `ModuleFillBus` 注册的 `moduleId`。
  String moduleId,
});

/// 反向锚点表：**只登记能唯一反查的** moduleId ↔ code 对。
///
/// ## 依据：本仓 `curriculum_2020.dart` 每条目自带的 `tool` 字段
///
/// 本仓的正向桥就是那条 `tool` 文本 + [_openTool] 的路由分支
/// （本仓**没有**逐枚 chip 的 moduleId 桥，所以粒度只到页签/页面）。
/// 每一条都按「该条目的 `tool` 自己点名了这个页签**且**全仓只有这一条
/// 点名它」登记——也就是**课标自己说了**，不是看着像：
///
///  · 3.2.3「阐明有性生殖中基因的**分离**和**自由组合**……并可由此
///    **预测**子代的遗传性状」——9331 的三个「预测」页签都在算这两条定律：
///    `cross_mono`（3:1）是「分离」那半边，`cross_dihybrid`（9:3:3:1）/
///    `cross_trihybrid`（27:…:1）是「自由组合」那半边。三枚徽章文案逐字
///    相同，登记次序 = 9331 页签次序（双基因 tab0 / 单基因 tab2 /
///    三对基因 tab1），这样这份次序本身就是一份可核对的映射。
///  · 3.2.4「概述性染色体上的基因传递和性别相关联」——`tool` 逐字写着
///    「伴性遗传」⇒ `cross_sex_linked`（唯一）。
///  · 3.3.4「……染色体所发生的自由组合和**交叉互换**，会导致……基因
///    重构」——`tool` 逐字写着「连锁互换」⇒ `cross_linkage`（唯一）。
///  · 3.3.6「举例说明人类遗传病是可以**检测和预防**的」——`tool` 逐字
///    写着「遗传病速查」⇒ 该页风险计算页签 `disease_risk`（唯一）。
///
/// ## ⛔ 刻意**不**登记的那些（依「宁可不给，也不给错」口径）
///
/// 一枚 moduleId 对**多条**课标的，反查方向必然多义 ⇒ 不登记，
/// [curriculumReverseCodeOf] 自然返回 null：
///  · `molecular`——分子页被 3.1.1 / 3.1.2 / 3.1.3 / 3.1.4 / 3.2.1
///    五条点名（`_openTool` 里「DNA计算器/复制计算器/转录翻译/配子种类」
///    全部落到 nav 5），而错题本**不记页签**⇒「分子页第 0 个页签」和
///    「第 3 个页签」在错题本里长得一模一样。
///  · `evolution`——进化页被 4.1.1 / 4.1.2 / 4.2.1 / 4.2.2 / 4.2.3 /
///    4.2.4 / 4.2.5 七条点名。
///  · `cross_chromosomal_struct`——变异页被 3.3.1 / 3.3.2 / 3.3.3 /
///    3.3.5 四条点名（「变异页·…」四条）。
///  · `pedigree`——3.2.2 的 `tool` 写「遗传图谱」、3.2.3 的 `tool` 写
///    「遗传图谱/9331」，两条都点名遗传图谱页 ⇒ 一枚 moduleId 分不清
///    学生做的是哪一条。
///  · `pd_inference`——它的目标页是遗传病页的系谱推断页签，而 3.2.2 /
///    3.2.3 的「遗传图谱」指向的是**遗传图谱页**，不是同一个页面 ⇒ 本仓
///    没有任何一条课标点名它。
///  · `ploidy` / `cross_method_compare` / `cross_random_mating`——本仓
///    没有任何一条课标的 `tool` 点名它们（3.2.1「减数分裂配子种类计算」
///    经 `_openTool` 落到分子页，不是倍性页）。
const List<CurriculumReverseAnchor> curriculumReverseAnchors =
    <CurriculumReverseAnchor>[
  (code: '3.2.3', badgeLabel: '课标 3.2.3', moduleId: 'cross_dihybrid'),
  (code: '3.2.3', badgeLabel: '课标 3.2.3', moduleId: 'cross_mono'),
  (code: '3.2.3', badgeLabel: '课标 3.2.3', moduleId: 'cross_trihybrid'),
  (code: '3.2.4', badgeLabel: '课标 3.2.4', moduleId: 'cross_sex_linked'),
  (code: '3.3.4', badgeLabel: '课标 3.3.4', moduleId: 'cross_linkage'),
  (code: '3.3.6', badgeLabel: '课标 3.3.6', moduleId: 'disease_risk'),
];

/// code → 反向锚点；表里没有就是 null（调用方据此不给徽章）。
///
/// ⚠️ **一个 code 可能有多个锚点**（3.2.3 = 双基因 / 单基因 / 三对基因
/// 三个 `moduleId`），本函数返回**第一个**。这不产生歧义：同一 code 的
/// 三枚锚点 `badgeLabel` 与 `code` 逐字相同，而 [curriculumReverseBadge]
/// 运行时**只**用这两样（跳本页 + 高亮那一条）⇒ 拿哪一枚都一样。
/// ⛔ 但**不要**拿它当 moduleId 的反查口（那是
/// [curriculumReverseCodeOf]）。
CurriculumReverseAnchor? reverseAnchorOf(String code) {
  for (final a in curriculumReverseAnchors) {
    if (a.code == code) return a;
  }
  return null;
}

/// moduleId → 课标 code。**唯一命中才返回**。
///
/// 供「错题本里按来源反查课标」用。
///
/// ## ⛔ 为什么多命中一律返回 null
///
/// 反查的输入只有 `moduleId`——`srcModule` **不记页签**。据此替学生/老师
/// 挑一条就是**凭空编造**对应关系，而这类编造在屏上**完全看不出来**（徽章
/// 照样可点、照样跳得过去，只是落到了另一条正文上）。这与「一枚徽章印两个
/// code ⇒ 不挂」是同一口径：**宁可不给，也不给错**。
///
/// ⚠️ 本仓表里每个 moduleId 都只登记一次（多义的压根没登记，见表头注释），
/// 所以「第二条命中 ⇒ 返 null」这一支目前是**守卫**而不是活路径：它是给
/// 日后有人往表里补一行同 moduleId 时兜底的，不许因为「现在走不到」就删。
String? curriculumReverseCodeOf(String moduleId) {
  String? hit;
  for (final a in curriculumReverseAnchors) {
    if (a.moduleId != moduleId) continue;
    if (hit != null) return null; // 第二条命中 ⇒ 多义，返回 null
    hit = a.code;
  }
  return hit;
}

/// 工具页/错题本里的「课标 X」徽章（**可点**）：点一下 push 一份带
/// `focusCode` 的课标页，左树自动切到该条目所属的关键概念，那一条被
/// 描边 + 标「正在查看」。
///
/// ## 为什么走 push 而不是切主导航
///
/// 主导航里那份 `CurriculumPage` 由 `main.dart` 的 `IndexedStack` 构造，
/// **不接 `focusCode`**；而 `main.dart` 不在本簇的文件所有权内 ⇒ 只能按
/// 项目既有做法（`_openTool` 的 push 回退分支）推一份新实例。
/// ⛔ 严禁 `const`：`const` 实例被 canonicalize，Element `identical` 短路
/// ⇒ `focusCode` 永远传不进去（同 9331 页记的深色 token 冻结事故）。
///
/// ## 视觉：⛔ 零像素变化
///
/// 改造前那枚 `AppChip` 长什么样，现在就还长什么样——加图标或加边框会
/// 顶红既有扫描基线。可点性靠三条**不占像素**的线索：指针变手形
/// （`MouseRegion`）、悬停/长按出 `Tooltip`、点下去有水波。
Widget curriculumReverseBadge(
    BuildContext context, CurriculumReverseAnchor a) {
  return MouseRegion(
    cursor: SystemMouseCursors.click,
    child: Tooltip(
      // 点名对象，不用「上面/下面」这类方向词。
      message: '查看课标 ${a.code} 的内容要求条目',
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: BorderRadius.circular(AppTheme.radiusChip),
          // ⛔ 不加 const：const 实例 identical 短路会冻住 focusCode。
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => CurriculumPage(focusCode: a.code),
            ),
          ),
          child: AppChip(a.badgeLabel),
        ),
      ),
    ),
  );
}

/// 工具页结果区/输入区**分区标题行**用的「课标 X」可点徽章（**null 安全**）。
///
/// 供各工具页 import 使用；⛔ 各页**不许自建表**、也不许自己写死 code。
///
/// ## 判定链（逐字复用既有函数，不新写第二套反查）
///
/// ```
/// code   = curriculumReverseCodeOf(moduleId)   // 唯一命中才返回
/// code == null ⇒ 返回 null（调用方不渲染任何东西）
/// anchor = reverseAnchorOf(code)              // 只用来拿徽章/跳转目标
/// anchor == null ⇒ 返回 null（守卫：表与反查不同步时不挂）
/// ```
///
/// ## 返 null 的两种情形（调用方据此「不给」）
///
///  · **多义** moduleId：`molecular`（3.1.1~3.1.4 + 3.2.1 五条）、
///    `gene_mutation`（3.3.1/3.3.2）、`cross_chromosomal_struct`（四条）、
///    `pedigree`（3.2.2/3.2.3）——挑一条就是替学生编造，而屏上**完全
///    看不出差别**（徽章照样可点、照样跳得过去，只是落到了另一条正文上）；
///  · **没被任何课标点名**：`ploidy` / `cross_method_compare` /
///    `cross_random_mating` / `pd_inference`。
///
/// 口径与反向消费侧（错题本徽章）、[CurriculumFocusShortcuts] 逐字同源。
///
/// ⛔ 严禁 `const`：与本函数上方那条同款红线（const 实例被 canonicalize，
/// Element `identical` 短路 ⇒ `focusCode` 传不进去）。
Widget? curriculumReverseBadgeFor(
    BuildContext context, String moduleId) {
  final code = curriculumReverseCodeOf(moduleId);
  if (code == null) return null; // 多义 / 未被点名 ⇒ 宁可不给
  final anchor = reverseAnchorOf(code);
  if (anchor == null) return null; // 守卫：表与反查不同步 ⇒ 不挂
  return curriculumReverseBadge(context, anchor);
}

/// 一条**解析后**的正向深链：moduleId + 参数。
///
/// ⛔ 两个字段都是**非空**类型 ⇒ 「有 id 没参」在类型上就造不出来
/// （成对律与 `curriculum_2020.dart` 的 `linkModuleId`/`linkParams` 同款）。
typedef CurriculumToolLink = ({String moduleId, Map<String, String> params});

/// 这一枚 chip 该走哪条深链——**纯函数**（守卫可直接调）。
///
/// ## 优先级（与备份仓 B 同款三级回落）
///  ① `chipLinks![chipIndex]`（非 null 且参数合格）——那一枚自己的深链；
///  ② 条目级 `linkModuleId` + `linkParams`（chipLinks 缺项 / 越界 /
///     元素为 null 都回落这里）；
///  ③ 都没有 ⇒ 返回 null，调用方回落**原导航逻辑**（一行未动）。
///
/// ## ⛔ 成对律在**解析层**再兜一道
/// 挂了 moduleId 却给不出「非空、逐键非空串」的 params ⇒ 当作**没有**深链
/// （返回 null），绝不产生「无参数深链」——本仓每个 target 的 `apply` 对
/// 缺参一律 `return false` ⇒ 学生只会看到「目标页未消费本次参数」。
///
/// ## 本仓的 chipIndex 口径
/// v2.19.36 起，一条目按 `tool` 的 `/` 分段渲染**若干枚** chip（见
/// [curriculumToolSegments] 与 `_itemTile`）⇒ 调用方传**这一枚的分段下标**。
/// 本仓 22 条里只有 3.2.3（`遗传图谱/9331`）有两段 ⇒ `chipLinks` 的
/// 第 1 段**已生效**（`cross_dihybrid` + 示范题），第 0 段为 `null`
/// ⇒ 那一枚**故意不带**深链、回落原导航（守卫 CG3）。
CurriculumToolLink? resolveCurriculumLink(
    CurriculumItem item, int chipIndex) {
  final chips = item.chipLinks;
  if (chips != null && chipIndex >= 0 && chipIndex < chips.length) {
    final c = chips[chipIndex];
    if (c != null) {
      final p = c.params;
      final ok = p.isNotEmpty &&
          p.entries
              .every((e) => e.key.trim().isNotEmpty && e.value.trim().isNotEmpty);
      if (ok) return (moduleId: c.moduleId, params: Map.of(p));
    }
  }
  final mid = item.linkModuleId?.trim();
  if (mid == null || mid.isEmpty) return null;
  final lp = item.linkParams;
  if (lp == null || lp.isEmpty) return null; // ⛔ 空参数深链比不深链更糟
  if (!lp.entries.every((e) => e.value.trim().isNotEmpty)) return null;
  return (moduleId: mid, params: Map.of(lp));
}

/// 一条目 `tool` 文本里的**每一枚**工具入口（trim 后、剔空段）。
///
/// ## 病灶（v2.19.36 修）
/// `CurriculumItem.tool` 是一整串文本，而**改造前**一条目只渲染**一枚** chip
/// ⇒ 「标了两个工具名」的条目**只落一个**：3.2.3「阐明有性生殖中基因的分离和
/// 自由组合……并可由此**预测**子代的遗传性状」的 `tool: '遗传图谱/9331'`，
/// `遗传图谱` 分支排在 `9331` 之前 ⇒ 那个真正用来「预测」的 9331 计算器
/// **永远拿不到**。本函数把一条目拆成若干枚，各带各的名字与各自的
/// 深链下标（[resolveCurriculumLink] 的 `chipIndex` 与本列表**下标对齐**）。
///
/// ## ⛔ 只按 `/` 与全角 `／` 拆，**绝不按 `+` 拆**（数据推出来的，不是偏好）
/// 本仓 22 条里 `/` **只出现 1 次**（3.2.3），而同表 3.2.2 单写 `遗传图谱`
/// ⇒ `/` 在这份数据里的语义确定是「**还有**」。而 `+` 出现 2 处且语义
/// **相反**：
///  · 3.3.4「连锁互换 + 9331」= **一个**目的地（9331 里的连锁互换**页签**），
///    靠 `linkModuleId` 深链直达；拆开会把深链打断，且
///    `lightwhite_repro_test` / `curriculum_jump_test` 都断言
///    `find.textContaining('连锁互换 + 9331')` ⇒ 直接假红；
///  · 3.3.6「遗传病速查 + 图谱概率」里的 `+` 同样不拆（见数据层注释）。
///
/// ## 兼容性：单枚条目逐像素同旧
/// 没有分隔符时也给出**一段**（整串），所以 22 条里 21 条的渲染结果与拆分
/// 前**逐像素相同**（CG10 钉的就是这份逐字文本）。
List<String> curriculumToolSegments(String tool) {
  final segs = tool
      .split(RegExp(r'[/／]'))
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      .toList();
  // 整串都是空段（脏数据）时兜回原串，否则整条目的 chip 会凭空消失。
  return segs.isEmpty ? <String>[tool] : segs;
}

/// 工具页 → 课标的 `Alt+K` 宿主（**零像素变化**：不渲染任何东西）。
///
/// 语义：从「我此刻这一栏」跳到它考的课标条目并高亮那一条
/// （`CurriculumPage(focusCode:)`——与 [curriculumReverseBadge] 同一机制）。
///
/// ## 数据真源 = 既有反向表，⛔ 不新造表
/// code 一律由 [curriculumReverseCodeOf] 从 `moduleIdsByTab[tab.index]` 反查；
/// 反查返 null（多义 moduleId，如 `molecular`/`gene_mutation`；或压根没被
/// 任何课标点名，如 `ploidy`）⇒ **不认领**这一键（宁可不给，也不给错）。
///
/// ## 为什么用「页面生命周期内的原始键盘处理器」而不是 `CallbackShortcuts`
/// `CallbackShortcuts`（同项目 `SaveToMistakeBookShortcuts` 那一族）靠**焦点链
/// 冒泡**：事件从 `primaryFocus` 往上走，而页面级宿主只是**路由焦点域的子节点**
/// ⇒ 学生刚点完按钮、`primaryFocus` 落回路由 scope 时，事件**根本到不了**页面里
/// 的宿主（实测：同一份测试里 `CallbackShortcuts` 版两条 Alt+K 用例全红）。
/// 那等于「快捷键看着存在、实际按了没反应」——本仓明令禁止的形态。
/// ⇒ 本宿主在 `initState` 挂 `HardwareKeyboard.addHandler`（`dispose` 摘掉）。
/// Flutter 的键事件系统对 `RawKeyboard` 监听器 / `HardwareKeyboard` 处理器 /
/// `keyMessageHandler` 是「**所有目的地都收**，返回值只决定要不要截断传播」
/// （`services/hardware_keyboard.dart` 的 `KeyEventManager` 文档原文）⇒
/// 本处理器对不关心的键一律返回 `KeyEventResult.ignored`，**不改变任何既有行为**。
///
/// ## 四道让路闸（缺一道就会误触发）
///  ① 非 `Alt+K` ⇒ 让路（裸 `K` 不触发）；
///  ② 本页不是**当前**路由（被别的路由/对话框盖住）⇒ 让路；
///  ③ 焦点在 `EditableText` 里（学生正在敲基因型）⇒ 让路；
///  ④ code 为 null（多义 / 没被任何课标点名）⇒ 让路。
class CurriculumFocusShortcuts extends StatefulWidget {
  const CurriculumFocusShortcuts({
    super.key,
    required this.tab,
    required this.moduleIdsByTab,
    required this.child,
  });

  /// v2.19.54：键位文案唯一真相（速览表从这里取，⛔ 不许另写一份）。
  static const String keyLabel = 'Alt + K';
  static const String keyDescription =
      '跳到本栏对应的课标条目（多义/未被课标点名的栏不绑）';

  /// 工具页的 `TabController`：code 按**按下那一刻**的 `index` 现算
  /// ⇒ 不存在「build 时算一次、切页签后仍跳旧那一栏」的过期绑定。
  final TabController tab;

  /// 页签下标 → `ModuleFillBus` 的 moduleId。**次序必须与页签一一对应**
  /// （与同文件那批 `ModuleFillBus.register` 的次序同源，见各页注释）。
  /// ⛔ 这**不是**一张新表：它只回答「这一栏是哪个 moduleId」，code 一律来自
  /// [curriculumReverseCodeOf]。
  final List<String> moduleIdsByTab;

  final Widget child;

  @override
  State<CurriculumFocusShortcuts> createState() =>
      _CurriculumFocusShortcutsState();
}

class _CurriculumFocusShortcutsState extends State<CurriculumFocusShortcuts> {
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

  /// 此刻这一栏**唯一**对应的课标 code；null = 不认领。
  String? get _code {
    final i = widget.tab.index;
    if (i < 0 || i >= widget.moduleIdsByTab.length) return null;
    final moduleId = widget.moduleIdsByTab[i];
    if (moduleId.isEmpty) return null; // 刻意留空 = 那一栏没有 target
    return curriculumReverseCodeOf(moduleId);
  }

  bool get _editingText {
    final focus = FocusManager.instance.primaryFocus;
    final ctx = focus?.context;
    // 焦点挂在 EditableText 内部的 Focus widget 上，须祖先查找
    // （同 `genetic_pedigree_page.dart` 的裸键守卫同款写法）。
    return ctx != null && ctx.findAncestorWidgetOfExactType<EditableText>() != null;
  }

  /// `HardwareKeyboard.addHandler` 的签名是 `bool Function(KeyEvent)`（不是
  /// 焦点链那一族的 `KeyEventResult`）——false = 不认领，事件继续走既有通路。
  bool _onKey(KeyEvent event) {
    if (event is! KeyDownEvent) return false; // 长按连发不重复 push
    if (event.logicalKey != LogicalKeyboardKey.keyK) return false;
    if (!HardwareKeyboard.instance.isAltPressed) return false;
    // v2.19.52（找茬 P3 修饰键精确）：Alt+Ctrl+K / Alt+Meta+K 不认领——
    // 与另两族宿主（TabJump 查 Ctrl/Meta、SaveHost 查 Alt）口径对齐。
    if (HardwareKeyboard.instance.isControlPressed) return false;
    if (HardwareKeyboard.instance.isMetaPressed) return false;
    // 被别的路由盖住（对话框、push 出来的二级页）⇒ 让路。
    if (ModalRoute.of(context)?.isCurrent != true) return false;
    // v2.19.52（找茬 P1）：壳内非激活页（9331 与遗传病同壳常驻）⇒ 让路。
    if (!isPageKeyActive(context)) return false;
    if (_editingText) return false; // ⛔ 正在敲基因型
    final code = _code;
    if (code == null) return false; // 多义 / 未被点名
    // ⛔ 不用 const：const 实例被 canonicalize，Element identical 短路
    // ⇒ focusCode 永远传不进去（同本文件 badge 的注释）。
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => CurriculumPage(focusCode: code),
      ),
    );
    ShortcutNudge.maybeNotify(context); // v2.19.54：首次成功触发给 ? 速览指引
    return true;
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class CurriculumPage extends StatefulWidget {
  const CurriculumPage({
    super.key,
    this.onNavPressed,
    this.onOpenTool,
    this.focusCode,
  });

  final VoidCallback? onNavPressed;

  /// v2.2 双向跳转：工具 chip 经 HomeShell 回调切导航索引（页面内跳转，
  /// 不 push 新路由）。null（独立构造/测试）时回退应用内路由 push。
  final void Function(int navIndex)? onOpenTool;

  /// 打开时要把左树切到哪条课标条目（如 '3.2.3'），并给那一条描边 +
  /// 标「正在查看」。null = 不预选、不高亮（主导航那一份与全部既有
  /// 入口都是 null ⇒ **零像素变化**）。
  final String? focusCode;

  @override
  State<CurriculumPage> createState() => _CurriculumPageState();
}

class _CurriculumPageState extends State<CurriculumPage> {
  static const _bigIdeas = [
    ('概念3', '遗传信息控制生物性状，并代代相传'),
    ('概念4', '生物的多样性和适应性是进化的结果'),
  ];

  /// v2.19.28 UI 统一：左树导航选中条目 id（'概念|关键概念'）。
  String? _selId;

  /// v2.19.34 错题本闭环：当前被高亮的课标 code（= `widget.focusCode`）。
  /// null = 不高亮任何一条（全部既有入口都是 null ⇒ 零像素变化）。
  String? _focusCode;

  @override
  void initState() {
    super.initState();
    final code = widget.focusCode;
    if (code == null || code.isEmpty) return;
    _focusCode = code;
    // 左树自动切到那条所属的关键概念。⛔ 认不出来（code 不在数据里）就
    // **不动**左树、不高亮——宁可不给，也不指一条错的正文。
    for (final i in curriculum2020) {
      if (i.code != code) continue;
      _selId = '${i.bigIdea}|${i.keyConcept}';
      return;
    }
  }

  String get _effectiveSelId {
    if (_selId != null) return _selId!;
    final items = curriculum2020;
    final firstIdea = _bigIdeas.first.$1;
    final firstKey = _keyConceptsOf(items, firstIdea).first;
    return '$firstIdea|$firstKey';
  }

  List<SideNavGroup> _navGroups() {
    final items = curriculum2020;
    return [
      for (final (idea, name) in _bigIdeas)
        SideNavGroup(
          label: name,
          entries: [
            for (final key in _keyConceptsOf(items, idea))
              SideNavEntry(
                id: '$idea|$key',
                label: _keyConceptName(key),
                // v2.19.29（M3.1 学生 N-P1-4）：窄态 pill 短标签
                //（长全称留在右区节标题）。
                shortLabel: _keyConceptShort(key),
                subtitle:
                    '${items.where((i) => i.bigIdea == idea && i.keyConcept == key).length} 条',
              ),
          ],
        ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final items = curriculum2020;
    final hotCount = items.where((i) => i.heat >= 1).length;
    final sel = _effectiveSelId;
    return Scaffold(
      appBar: AppBar(
        leading: appNavButton(widget.onNavPressed),
        title: const Text('课标 · 遗传与进化'),
        actions: [
          TextButton.icon(
            onPressed: () => _showSummary(context),
            icon: const Icon(Icons.analytics_outlined, size: 18),
            label: const Text('概览'),
          ),
          // v2.1 问 AI：页面上下文随带（与系谱页同链路：queueSend + 侧栏）
          TextButton.icon(
            onPressed: () {
              AiChatController.instance.queueSend('【当前工具：课标体系】必修2 内容要求 22 条浏览。');
              showAiAssistant(context);
            },
            icon: Icon(Icons.psychology_outlined,
                size: 18, color: AppColors.teal),
            label: Text('问 AI',
                style: TextStyle(
                    color: AppColors.teal, fontWeight: FontWeight.w600)),
          ),
          const SizedBox(width: 8),
        ],
      ),
      // v2.19.28 UI 统一：废弃「居中窄条 + 大概念 StepCard 堆叠 +
      // ExpansionTile 逐级展开」，改左树导航（大概念组 → 关键概念
      // 条目）+ 右区平铺选中概念的次位概念条目——与全 app 工作台
      // 语言一致。
      body: SideNavWorkbench(
        groups: _navGroups(),
        selectedId: sel,
        onSelect: (id) => setState(() => _selId = id),
        // v2.20.0（M3.1 评审）：railTitle / railIcon 已无渲染用途，参数删除
        // ——宽屏组名改由 SideNavWorkbench 从 groups[].label 直接上条。
        bodyMaxWidth: 1100,
        body: (context) {
          final bar = sel.indexOf('|');
          final idea = sel.substring(0, bar);
          final key = sel.substring(bar + 1);
          final subs = items
              .where((i) => i.bigIdea == idea && i.keyConcept == key)
              .toList();
          final ideaName =
              _bigIdeas.firstWhere((t) => t.$1 == idea, orElse: () => ('', '')).$2;
          return Column(
            // 新手引导高亮目标（原挂首张大概念卡，现挂右区内容根，
            // 任何选中态都在树，挖孔不丢）。
            key: GuideKeys.curriculumChip,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 投影可读性：说明文字 steel→graphite 加深一档（既有 token）。
              Text(
                '《普通高中生物学课程标准（2017年版2020年修订）》必修2'
                '《遗传与进化》内容要求：${items.length} 条次位概念，'
                '高考核心考点 $hotCount 条（★）。'
                '点击条目下方的「工具」chip 可直接进入对应计算页。',
                style: AppText.caption.copyWith(color: AppColors.graphite),
              ),
              const SizedBox(height: 16),
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Expanded(
                    child: Text(_keyConceptName(key),
                        style: AppText.sectionTitle),
                  ),
                  Text('$ideaName · ${subs.length} 条',
                      style: AppText.caption
                          .copyWith(color: AppColors.steel)),
                ],
              ),
              const SizedBox(height: 10),
              for (final s in subs) _itemTile(context, s),
            ],
          );
        },
      ),
    );
  }

  List<String> _keyConceptsOf(List<CurriculumItem> items, String idea) {
    final seen = <String>{};
    final out = <String>[];
    for (final i in items) {
      if (i.bigIdea == idea && seen.add(i.keyConcept)) out.add(i.keyConcept);
    }
    return out;
  }

  String _keyConceptName(String key) {
    // ⚠ 字符存储位置备忘（2026-08-28 验收反馈后建，2026-08-28 补 v2.1k 根因） ─
    // 本函数返回 5 个关键概念标题，是课标树第 2 层的标题源。
    // 其中 3.1「遗传信息主要编码在 DNA 分子上」是用户高频复述段：
    //   - 3.1.1 描述"概述多数生物的基因是DNA分子的功能片段..."
    //     在 lib/data/curriculum_2020.dart **L58**（text 字段，原备忘误写 L44）。
    //   - 验收时务必双模式读图验证：3.1.1 行 description 在浅色
    //     模式必须是墨灰 0xFF35322C / 深色模式是暖米白 0xFFEAE8E1
    //     完整可见（v2.1i 之前曾因 chip 挤压被裁成白字白底）。
    //   - v2.1k 真正根因：AppColors._dark 是全局静态字段，若 ListenableBuilder
    //     不 rebuild（系统从白天切到晚上，ThemeController 不 notify），
    //     _dark 残留浅色，AppColors.ink 拿到 _inkD 暖米白 = 与 surface 暖近白
    //     几乎同色 = 白字白底。修复见 main.dart _BiologyAppState mixin
    //     WidgetsBindingObserver（系统亮度变化时强制 notify）。
    // ───────────────────────────────────────────────────────────
    switch (key) {
      case '3.1':
        return '遗传信息主要编码在 DNA 分子上';
      case '3.2':
        return '有性生殖中基因的分离和重组';
      case '3.3':
        return '可遗传的变异（突变/重组/染色体变异）';
      case '4.1':
        return '现存物种来自共同祖先';
      case '4.2':
        return '适应是自然选择的结果';
      default:
        return key;
    }
  }

  /// v2.19.29（M3.1 学生 N-P1-4）：窄态 pill 短标签（编号 + 词组）。
  String _keyConceptShort(String key) {
    switch (key) {
      case '3.1':
        return '3.1 DNA 编码';
      case '3.2':
        return '3.2 分离重组';
      case '3.3':
        return '3.3 可遗传变异';
      case '4.1':
        return '4.1 共同祖先';
      case '4.2':
        return '4.2 自然选择';
      default:
        return key;
    }
  }

  Widget _itemTile(BuildContext context, CurriculumItem item) {
    // v2.1k：description/编号 chip/工具 chip 全部改用
    // Theme.of(context).colorScheme —— 不依赖 AppColors._dark 全局
    // 静态状态。即使 _dark 残留（系统亮度切换未通知 ListenableBuilder），
    // MaterialApp rebuild 时 colorScheme 会重新计算 → Text widget 拿
    // 到的是当前 MaterialApp 的 scheme onSurface（浅/深正确）。
    // 这是双保险：主修复在 main.dart（监听 platformBrightness 主动
    // notify），副修复在 _itemTile（断绝 _dark 残留影响）。
    final cs = Theme.of(context).colorScheme;
    // v2.19.34 错题本闭环：被 focusCode 点名的那一条描边 + 标「正在查看」。
    // ⛔ `_focusCode == null` 时**一个字都不加**（主导航那份与全部既有
    // 入口都是 null）⇒ 本轮对既有屏零像素变化。
    final focused = _focusCode != null && item.code == _focusCode;
    final tile = ListTile(
      contentPadding: const EdgeInsets.only(left: 4, right: 12, bottom: 2),
      leading: Container(
        width: 46,
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
        // 双值 token：浅色=豆绿浅底+豆绿深字；深色=暖灰底+暖米字。
        //（读图验收：勿用近黑底白字，莫兰迪化。）
        decoration: BoxDecoration(
          color: AppColors.tealWash,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.teal),
        ),
        child: Text(
          item.code,
          textAlign: TextAlign.center,
          style: AppText.monoSmall.copyWith(
            fontSize: 11,
            color: AppColors.tealDark,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      title: Padding(
        padding: const EdgeInsets.only(bottom: 4),
        // v2.1k：用 colorScheme.onSurface（不依赖 _dark）——浅色
        // 模式 = 墨灰 0xFF35322C / 深色模式 = 暖米白 0xFFEAE8E1，
        // 自动跟随 MaterialApp.theme 切换。
        // maxLines=2 防 chip 过长挤压 ListTile.title 高度导致描述被裁。
        child: Text(
          item.text,
          style: AppText.body.copyWith(
              color: cs.onSurface, fontWeight: FontWeight.w500),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Wrap(
          spacing: 6,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            // v2.19.34 错题本闭环：被 focusCode 点名的那一条，语言线索
            // 写明「正在查看」（点名对象，禁方向词、禁 markdown 星号）。
            // 只在 focused 时渲染 ⇒ 全页至多一枚。
            if (focused)
              Padding(
                padding: const EdgeInsets.only(right: 2),
                child: Text('正在查看',
                    style: AppText.caption.copyWith(
                        color: AppColors.tealDark,
                        fontSize: 12,
                        fontWeight: FontWeight.w700)),
              ),
            // v2.3.2（AI 评审二轮）：★ 不定宽会把「工具」chip 挤得
            // 参差不齐——定宽 34 让所有 chip 形成整齐左对齐扫视线。
            SizedBox(
              width: 34,
              child: Text('★' * item.heat,
                  style: TextStyle(
                      color: AppColors.sand,
                      fontSize: 12,
                      fontWeight: FontWeight.w700)),
            ),
            if (item.tool != null)
              // v2.1j 浅豆绿底+深绿字+1px teal 边：替代 v2.1i 实心底
              // （与 surface 色差太小，浅底+深字保留下），并强制单行+省略号
              // ——3.1.1「工具：中心法则页·基因概念卡」13 字若换行会撑高
              // subtitle 区把 description 压成不可见。
              //
              // v2.19.36 **逐枚**：一枚 chip 对 `tool` 里的**一个**工具入口
              // （`/` 拆段，规则与理由见 `curriculumToolSegments`），每枚
              // 带自己的名字 + 自己的深链下标 + 自己那段文本的导航回落。
              // ⛔ 逐枚直接作为**外层这个 Wrap 的兄弟**渲染（不另套一层
              // Wrap）——单枚条目（22 条里 21 条）的渲染结果与拆分前
              // **逐像素相同**，而逐枚间距就是本 Wrap 既有的 `spacing: 6`
              // （落在 4–6px 区间内），故其余零变化。
              for (final (chipIndex, seg)
                  in curriculumToolSegments(item.tool!).indexed)
                InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: () =>
                      _openTool(item, chipIndex: chipIndex, chipText: seg),
                  // v2.19.16（DeepSeek 找茬 🟡5）：触控兜底——原竖向
                  // padding 3 + 12px 字 ≈24px 高，触屏点不中；constrain 到
                  // 48px（课堂主题按钮同档）。
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: 48),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: AppColors.tealWash,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: AppColors.teal, width: 1),
                      ),
                      child: Text(
                        '工具：$seg →',
                        style: AppText.caption.copyWith(
                            color: AppColors.tealDark, // 双 token：浅=深绿/深=亮绿
                            fontSize: 12,
                            fontWeight: FontWeight.w700),
                        softWrap: false,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                ),
          ],
        ),
      ),
      isThreeLine: false,
    );
    if (!focused) return tile;
    return Container(
      // 守卫钉的 key：被高亮的必须正是 focusCode 指着的那**一条**，
      // 不是落在同一分区里的另一条正文上。
      key: ValueKey('curriculum-item-${item.code}'),
      decoration: BoxDecoration(
        color: AppColors.tealWash,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.teal, width: 1.5),
      ),
      child: tile,
    );
  }

  /// v2.2 双向跳转修复：工具 chip 直达对应页。
  /// 主导航内的页（遗传图谱 1 / 9331 计算器 2 / 图谱 3 / 分子 5 / 进化 6）
  /// 经 [onOpenTool] 回调让 HomeShell 切导航索引——页面内跳转，Rail 常驻，
  /// 点 Rail「课标」即可跳回（双向），且不会叠路由栈。
  /// 索引事实源：lib/ui/app_navigation.dart（顺序即页面索引）。
  /// 主导航外的页面维持应用内路由 push（MaterialPageRoute 自带返回键，可回）。
  /// 严禁缓存/复用页面实例（含 const）：路由 builder 若返回同一 widget 实例，
  /// Element updateWidget 时 identical 短路永不 rebuild——首帧深色 token 文字
  /// 永久冻结，浅色模式下白底白字（9331 页事故根因）。必须存工厂闭包，
  /// 让路由每次 build 都拿到全新实例。
  ///
  /// v2.19.35：**先走数据（正向深链），再走下面那段字符串匹配**，而字符串
  /// 匹配本身**一行未动**（无深链的条目与本轮之前逐字同路）。
  /// v2.19.36 **逐枚 chip**：签名加命名参且**默认 0** ⇒ 既有调用点零改动。
  ///  · [chipIndex] = 这一枚在 `curriculumToolSegments` 里的下标（喂给
  ///    [resolveCurriculumLink] 取**这一枚自己**的深链）；
  ///  · [chipText] = 这一枚自己的名字（喂给下面那段字符串匹配的**回落**）。
  ///
  /// ⛔ 回落必须按**该枚自己的文本**匹配，不能拿整串 `tool` 匹配——否则
  /// 「遗传图谱/9331」第 1 枚（9331）会被第 0 枚（遗传图谱）的分支劫持，
  /// 那正是逐枚化要修的病灶。
  void _openTool(CurriculumItem item, {int chipIndex = 0, String? chipText}) {
    if (!mounted) return;
    final tool = chipText ?? item.tool!;
    // ① 数据驱动的深链：条目级 `linkModuleId` + `linkParams`，或该枚 chip 自己的
    // `chipLinks[i]`（见 [resolveCurriculumLink] 的三级回落）。
    final link = resolveCurriculumLink(item, chipIndex);
    // v2.19.35：课标深链带 sourceLabel —— push 型目标的回程横幅
    // 写「来自课标」而非写死的「拍题识别」（总线 consumePushSourceLabel）。
    if (link != null &&
        ModuleFillBus.fill(link.moduleId, link.params,
            sourceLabel: '课标')) {
      // 从错题本 / 「课标 X」徽章 push 进来的实例没有 onOpenTool：fill 只切
      // 底层 IndexedStack，而本页路由还盖在上面 ⇒ 按钮看着能点、点了零反应。
      // 修法同 `big_question_cards_page._openLink`（三找茬代理交叉 P1）：
      // fill 成功后弹回根路由，被切到的目标页才真的出现在眼前。
      // v2.19.37（独立验证者 P0 修复）：⛔ 只对**切导航索引型**深链弹回。
      // push 型目标（disease_risk——全表唯一）自己浮在路由栈最上层；
      // popUntil 会把刚 push 的页与本页一起弹掉（学生看到闪回首页、
      // 深链完全失效），且被弹的页从未构建 ⇒ sourceLabel/params 留成
      // 幽灵（下次拍题横幅说「来自课标」——v2.19.35 要消灭的假话复活）。
      final target = ModuleFillBus.targetOf(link.moduleId);
      if (target != null &&
          target.pushFactory == null &&
          widget.onOpenTool == null &&
          Navigator.of(context, rootNavigator: true).canPop()) {
        Navigator.of(context, rootNavigator: true)
            .popUntil((route) => route.isFirst);
      }
      return;
    }
    // ② 回落：原导航逻辑（main.dart _navLabels 顺序，13 页）：
    // v2.19.60 重排后：0首页 1遗传图谱 2·9331 3图谱 4课标 5分子 6进化 7倍性
    // 8套路卡 9变异 10遗传病 11设置 12关于（设置/关于固定末位）。
    final int? navIndex;
    final Widget Function()? pushFactory; // 主导航外页面的回退路由工厂
    if (tool.contains('DNA复制计算器') ||
        tool.contains('DNA计算器') ||
        tool.contains('转录翻译') ||
        tool.contains('配子种类')) {
      navIndex = 5; // 分子
      pushFactory = MolecularPage.new;
    } else if (tool.contains('基因频率') ||
        tool.contains('进化页') ||
        tool.contains('共同特征') ||
        tool.contains('理论脉络') ||
        tool.contains('物种形成') ||
        tool.contains('证据速览')) {
      navIndex = 6; // 进化
      pushFactory = EvolutionPage.new;
    } else if (tool.contains('变异')) {
      navIndex = null; // 变异页不在主导航
      // v2.19.30（M3.1 老师 P2-3）：闭包带 sourceLabel（回程横幅），
      // 构造函数 tear-off 无法带参。**禁 const**（本页注释明文：
      // const 实例 identical 短路 → 主题 token 冻结，v2.19.20 事故
      // 同族）。
      pushFactory = () => VariationPage(sourceLabel: '课标');
    } else if (tool.contains('遗传病') || tool.contains('疾病')) {
      navIndex = null; // 遗传病速查不在主导航
      pushFactory = () => GeneticDiseasePage(sourceLabel: '课标');
    } else if (tool.contains('遗传图谱')) {
      navIndex = 1;
      pushFactory = GeneticPedigreePage.new;
    } else if (tool.contains('9331') ||
        tool.contains('连锁互换') ||
        tool.contains('伴性') ||
        tool.contains('练习')) {
      // 2.2 批次2：刷题模块已移除，练习类条目改指遗传计算器。
      navIndex = 2;
      pushFactory = CrossCalculatorPage.new;
    } else if (tool.contains('知识图谱') || tool.contains('图谱')) {
      navIndex = 3;
      pushFactory = KnowledgeGraphPage.new;
    } else {
      navIndex = null;
      pushFactory = null; // 概念卡类条目（课标体系页原文即承载）
    }
    // 优先页面内跳转（双向）；回调缺失或主导航外页面回退 push。
    if (navIndex != null && widget.onOpenTool != null) {
      widget.onOpenTool!(navIndex);
      return;
    }
    final f = pushFactory;
    if (f != null) {
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => f()));
    }
  }

  void _showSummary(BuildContext context) {
    final items = curriculum2020;
    final byIdea = <String, Map<String, List<String>>>{};
    for (final i in items) {
      byIdea.putIfAbsent(i.bigIdea, () => {});
      byIdea[i.bigIdea]!.putIfAbsent(i.keyConcept, () => []);
      byIdea[i.bigIdea]![i.keyConcept]!.add(i.code);
    }
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('课标覆盖概览'),
        content: SizedBox(
          width: 420,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('共 ${items.length} 条内容要求（次位概念）。', style: AppText.body),
                const SizedBox(height: 8),
                for (final e in byIdea.entries) ...[
                  Text(e.key, style: AppText.sectionTitle),
                  for (final k in e.value.entries)
                    Padding(
                      padding: const EdgeInsets.only(left: 12, top: 2),
                      child: Text('${k.key}：${k.value.join('、')}',
                          style: AppText.caption),
                    ),
                  const SizedBox(height: 6),
                ],
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }
}
