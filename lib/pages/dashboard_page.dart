// dashboard_page.dart —— 图标化首页（v2.2 批次4a）
//
// 通用生物计算器定位页：功能以图标网格呈现（不再是表单平铺），
// 每个卡片 = 大图标 + 名称 + 一句话用途；点击通过 onOpenTool 回调
// 让 HomeShell 切导航索引（单一导航事实源，不自开页面栈）。
//
// v2.12 Wave 2 / Worker B：第 10 张卡片「我的错题」用 Navigator.push
// 模式直接入栈（不在主导航索引里——主导航由其他 worker 负责扩展，
// 错题本是用户私人空间，独立 push 更轻量）。其余 9 张卡片保持
// onOpenTool 模式不变（既有 dashboard_page_test 仍绿）。
//
// v2.12 Wave 3-B：顶部加角色 chip（老师/学生）+ 切换入口；
// 老师角色隐藏「我的错题」入口（错题本是学生私人空间，老师工作流
// 不需要被干扰）。学生看到完整入口。
// v2.13 R5 P0：移除「家长」——产品决策 Biology 不面向家长。
//
// v2.21.0 首页排版重做：旧版是 13 张同权卡片墙——每张卡同样的尺寸、
// 同样的灰字，读完不知道「先点哪个」。新版给出一页**有层级**的版面：
//
//   欢迎 / 状态区（大标题 + 定位语 + 使用模式 / 角色）
//     → 三核心工作区（系谱推断 / 9331 及变式 / 图谱浏览，桌面并列强调）
//     → 分组模块（计算工具 / 学习支持 / 系统与帮助，紧凑双列可扫读）
//
// 纪律：
//   · 入口身份走 _ToolEntry.id（**不按显示名映射**——文案会随迭代改，
//     id 才是身份；分组只认 id）。
//   · 三核心卡只在核心区出现一次，后续分组不重复（同一入口两处出现，
//     点击行为相同但读起来像两个功能）。
//   · 薄壳统一走 ModuleSurface（lib/ui/module_surface.dart）：卡内不再套
//     Card，两层描边会把层级重新压平。
//   · 唯一滚动容器 = 外面这层 SingleChildScrollView（也是新手引导的
//     高亮目标）：所有入口一次性挂载，键盘遍历与「跳到末项」不受视口限制。
//   · 卡片为 InkWell，默认可聚焦，Tab/方向遍历 + Enter 触发（键盘党友好）。
//   · 配色只走 AppColors/AppText token，深浅模式零改动换肤。

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../state/scan_bank_store.dart';
import '../guide/guide_keys.dart';
import '../state/first_run_store.dart';
import '../state/history_store.dart';
import '../state/mistake_book.dart';
import '../storage/platform_storage_io.dart'
    if (dart.library.html) '../storage/platform_storage_web.dart';
import '../theme.dart';
import '../ui/ai_chat_controller.dart';
import '../ui/app_navigation.dart';
import '../ui/assistant_panel.dart';
import '../ui/mode_switcher.dart';
import '../ui/module_fill.dart';
import '../ui/module_surface.dart';
import 'genetic_disease_page.dart';
import 'mistake_book_page.dart';

/// 历史条目是否「可复核」= 可复现（▷）/ 可出 AI 讲题稿。
///
/// v2.19.62（创新提案 #7）：判据抽成顶层函数——入口**渲染处**（渲染与否）
/// 与**按键处**（拼提示词）同调这里，杜绝「渲染时按 A 判、点击时按 B 拼」
/// 的两套判据漂移。
///
/// 判据（哪些字段算「可复核」，逐条列明）：
///   detail 必须能 `jsonDecode` 成一个 **JSON 对象**（Map），且同时带
///     · `m`  —— 引擎模块 id（cross_dihybrid / cross_mono /
///               cross_sex_linked / cross_linkage / cross_method_compare）
///     · `p1` —— 亲本基因型快照（题干主干）
///   两个键（值非 null）。
///
/// 反例 ⇒ 不可复核：
///   · 系谱页条目（detail 是「每代产出逐行」的纯文本，没有结构化参数）
///   · 自由交配条目（detail 空串）
///   · 任何非 JSON / JSON 数组 / JSON 标量的 detail
/// 这类条目**不渲染**「讲题稿」入口——没有参数快照就拼不出确切题干，
/// 渲染出来点了也只能回一句「不支持」，那是屏上撒谎。
bool historyEntryLectureable(HistoryEntry e) {
  try {
    final j = jsonDecode(e.detail);
    return j is Map && j['m'] != null && j['p1'] != null;
  } catch (_) {
    return false;
  }
}

/// 一条可复核历史 → 「AI 讲题稿」提示词；不可复核返回 null。
///
/// ⛔ 提示词正文里**一个星号都不许有**：AI 常把提示词里的排版标记原样
/// 回显，讲稿会被老师直接投影到幕布上（屏上文案卫生的 prompt 侧）。因此
/// 「不要用 markdown 星号」这句要求只能**用中文词说出**「星号」，不能
/// 真的敲一个星号字符当示例。
String? historyLecturePrompt(HistoryEntry e) {
  if (!historyEntryLectureable(e)) return null;
  Map<String, dynamic> snap;
  try {
    snap = (jsonDecode(e.detail) as Map).cast<String, dynamic>();
  } catch (_) {
    return null; // 防御：与 historyEntryLectureable 判据不一致时宁可不发
  }
  final p1 = snap['p1']?.toString() ?? '';
  final p2 = snap['p2']?.toString() ?? '';
  final sb = StringBuffer()
    ..writeln('【当前工具：课堂讲题回放】请写一份讲题稿，我会直接投影给全班看。')
    ..writeln('题目参数：$p1 × $p2')
    ..writeln('我已算出的结果（正确答案）：${e.label}')
    ..writeln('要求：一是先讲清已知条件和要求什么；')
    ..writeln('二是分步骤推导，每一步写清依据（用第一、第二这样的中文序号）；')
    ..writeln('三是指出这道题最容易错在哪里；四是最后给一句好记的口诀。')
    ..writeln(
      '请按「给全班同学讲这道题」的口吻写，句子短一点，'
      '不要用 markdown 星号、井号这类排版标记（符号会被投影原样显示）。',
    );
  return sb.toString();
}

/// 首页功能入口描述。
class _ToolEntry {
  /// 稳定 id（页面身份；改名不动 id）。
  ///
  /// v2.21.0：分组只按 id 索引（`pedigree` / `cross` / …）。此前首页只有
  /// 「显示名」，任何分组/强调都得写 `name == '我的错题'` 这种判据——文案
  /// 一改（v2.19.68 就把老师卡描述改过）判据静默失效。对主导航条目，id
  /// 直接取 `appNavDestinations[].id`；错题本 / 老师工具用本地 id。
  final String id;

  final String name; // 卡片名称
  final String desc; // 一句话用途
  final IconData icon;

  /// HomeShell 导航索引（首页为 0，功能页从 1 起）。customTap 模式下
  /// 走 Navigator.push 不入主导航，故 navIndex 可省——历史上曾遗留
  /// `10` 这种越界值（v2.12 P0-1：当时主导航仅 10 项，index 10 越界
  /// 点卡即崩）；现主导航 13 项，但这类卡仍统一省 navIndex。
  ///
  /// v2.20.0：主导航卡片的 navIndex 不再手写——直接取
  /// `appNavDestinations` 的下标（目录顺序 == 页面索引），首页与
  /// HomeShell 不再各维护一份「名字 ↔ 索引」映射。
  final int? navIndex;

  /// v2.12：可选的「自定义点击行为」（不经过 onOpenTool）。
  /// 错题本走 Navigator.push 模式——主导航列表在别处维护，
  /// 这里不抢占 navIndex。
  final void Function(BuildContext context)? customTap;

  /// v2.12 Wave 3-B：老师角色隐藏标记。true = 只对学生显示，
  /// 老师角色下从入口列表过滤掉（错题本是学生私人学习空间）。
  /// v2.13 R5 P0：移除「家长」分支——产品决策 Biology 不面向家长。
  final bool studentOnly;

  /// v2.12 Wave 3-B P1：老师角色专属标记。true = 只对老师显示，
  /// 学生角色下从入口列表过滤掉（老师工作流工具）。
  /// 与 `studentOnly` 互斥——一张卡最多属于一个角色组。
  /// v2.13 R5 P0：移除「家长」分支。
  final bool teacherOnly;

  const _ToolEntry({
    required this.id,
    required this.name,
    required this.desc,
    required this.icon,
    this.navIndex,
    this.customTap,
    this.studentOnly = false,
    this.teacherOnly = false,
  });
}

/// v2.21.0：首页分区（按 id 归类；顺序 == 视觉顺序）。
///
/// 三张核心卡只在这里出现一次——后续分组不得重复同一 id（同一入口两处
/// 出现，读起来像两个功能）。四个表的并集必须覆盖 [_visibleEntries]
/// 的全集，`build` 里有 assert 兜底（新增导航页时忘记归类会当场炸在
/// debug，而不是让入口在首页静默消失）。
const List<String> _coreEntryIds = <String>['pedigree', 'cross', 'graph'];
const List<String> _computeEntryIds = <String>[
  'molecular',
  'evolution',
  'ploidy',
  'variation',
  'disease',
];
const List<String> _learnEntryIds = <String>[
  'curriculum',
  // v2.22.0：「套路卡」(cards) 从首页撤下独立入口 ⇒ 本表同步去掉，
  // 否则分组表与 _baseEntries 不一致（覆盖 assert 会红）。
  // 套路卡仍可经 9331 结果页按 K、错题本按需打开。
  'mistakes',
  'teacher',
];
const List<String> _systemEntryIds = <String>['settings', 'about'];

/// v2.23 首页层级：主入口 id（核心三卡里的「遗传图谱计算」）。
///
/// 用 Sage 实色（[AppColors.teal]）+ onTeal 高对比把它抬成全页**第一
/// 入口**——学生/老师打开软件第一眼就知道先点哪个。按**稳定 id** 判定
/// （不比显示名，文案会随迭代改）；另两张核心卡保持浅色同族层次，
/// 不制造第二块实色（否则「主」就不再唯一）。
const String _primaryEntryId = 'pedigree';

/// 图标化首页。
///
/// v2.12 Wave 3-B：升级为 StatefulWidget 订阅 FirstRunStore——
/// 角色（老师/学生）变化时立即 rebuild，老师角色过滤掉「我的错题」
/// 入口（错题本是学生私人学习空间，老师工作流不需要被干扰）。
/// v2.13 R5 P0：移除「家长」——产品决策 Biology 不面向家长。
class DashboardPage extends StatefulWidget {
  // v2.12+ R1 P0 #2：构造时不能 const（_baseEntries 闭包捕获 onOpenTool）。
  // ignore: prefer_const_constructors_in_immutables
  DashboardPage({super.key, required this.onOpenTool});

  /// v2.12+ R1 final D P0 #3：测试注入——非空时 _TeacherPage 的
  /// 板书历史走该目录而非 userAppDir() + board_history/。仅影响
  /// _TeacherPage 内的板书文件读写；不修改 userAppDir() 本体
  /// （避免污染 MistakeBook / ScanBankStore 等同走 userAppDir
  /// 的模块）。
  ///
  /// static 字段而非实例字段：_TeacherPage 是 Navigator.push 推
  /// 出来的，外部代码拿不到它的实例，没法通过实例字段注入。
  @visibleForTesting
  static String? debugBoardHistoryDirForTest;

  /// v2.12+ R2 A2 P1-6：测试注入——true 时 `_showBoardInExplorer`
  /// 走 web 守卫分支。flutter_test 跑在 VM 上（kIsWeb 恒 false），
  /// 没法直接模拟 web 平台；真 web 环境由 kIsWeb 生效，本字段
  /// 仅测试用。
  @visibleForTesting
  static bool debugForceIsWeb = false;

  /// 点击卡片 → HomeShell 切换导航索引（保持单一导航事实源）。
  final void Function(int navIndex) onOpenTool;

  /// 全部导航功能入口（首页自身除外）。
  /// v2.12+ R1 P0 #2：从 `static final` 改为「lazy getter 返回实例
  /// 列表」——老师卡片的 customTap 需要把 `onOpenTool(1)` 注入到
  /// _TeacherPage.onOpenPedigree，让老师卡走「切主导航到系谱页」
  /// 而非自己 Navigator.push(GeneticPedigreePage)，避免
  /// dashboard_page ↔ genetic_pedigree_page 反向 import
  /// （R1-D 范围，本 worker 不动）。getter 内部闭包捕获
  /// `this.onOpenTool`（DashBoard 实例），与 widget.onOpenTool(1)
  /// 等价但更安全（不会被静态状态污染）。
  List<_ToolEntry> get _baseEntries => <_ToolEntry>[
    // v2.20.0：主导航卡 = 导航目录（app_navigation.dart）除「首页」
    // 外的全部条目，顺序/名称/描述/图标/索引同源。原实现手工维护
    // 「名字 + navIndex」并与 HomeShell 并行，v2.19.31 加变异/遗传病
    // 时就漏了首页两卡（功能隐身）——现在目录加项，首页自动跟上。
    for (var i = 0; i < appNavDestinations.length; i++)
      if (appNavDestinations[i].id != 'home' &&
          // v2.22.0：首页**不再**给隐藏页独立入口卡（套路卡改由 9331
          // 结果页的 K 快捷键 / 错题本按需打开）。目录条目与 pageIndex
          // 不变——只是首页不显示这一张卡。
          appNavDestinations[i].visibleInNav)
        _ToolEntry(
          // v2.21.0：id 直接取导航目录的稳定 id（分组只认 id）。
          id: appNavDestinations[i].id,
          name: appNavDestinations[i].dashboardTitle,
          desc: appNavDestinations[i].dashboardDesc,
          icon: appNavDestinations[i].icon,
          navIndex: i,
        ),
    // v2.12 Wave 2：错题本 = 用户私人数据空间，AI 主动归类错因 / 提炼
    // 易错点 / 生成总览。customTap 走 Navigator.push（不入主导航）；
    // navIndex 省略——customTap 模式下主导航索引对它无意义（v2.12 P0-1
    // 修正：原 navIndex: 10 越界会让点卡崩）。
    // v2.12 Wave 3-B：错题本 = 学生私人空间，老师角色 hide。
    // 父入口 `studentOnly: true`——按角色过滤；首次启动时角色未定
    // （FirstRunStore._role == null）按"学生"处理，与兜底语义一致。
    _ToolEntry(
      id: 'mistakes',
      name: '我的错题',
      desc: 'AI 主动归类错因 · 提炼易错点 · 总览',
      icon: Icons.book_outlined,
      customTap: (ctx) =>
          Navigator.of(ctx)
              .push(MaterialPageRoute(builder: (_) => MistakeBookPage())),
      studentOnly: true,
    ),
    // v2.12+ R1 P0 #2：老师工具卡实装——把 onOpenTool(1)（切主导航
    // 到系谱页）注入 _TeacherPage.onOpenPedigree，让"去系谱页生成"
    // 按钮复用 dashboard 的导航事实源，避免反向 import
    // genetic_pedigree_page（那是 R1-D 范围）。
    // v2.19.68 P2-5（看官走查：讲题回放可发现性弱）：描述补「讲题
    // 回放」关键词——老师只在卡描述里搜索式扫视，原描述只有
    // 板书/拍题统计，回放功能被漏看。
    _ToolEntry(
      id: 'teacher',
      name: '老师工具',
      desc: '讲题回放 · 板书 SVG 导出 · 拍题统计',
      icon: Icons.school_outlined,
      customTap: (ctx) {
        Navigator.of(ctx).push(
          MaterialPageRoute(
            builder: (_) => _TeacherPage(
              onOpenPedigree: () {
                // 先关掉 _TeacherPage，回到 dashboard，再切主导航
                // 到 navIndex=1（遗传图谱计算 = 系谱页）。
                Navigator.of(ctx).pop();
                onOpenTool(1);
              },
            ),
          ),
        );
      },
      teacherOnly: true,
    ),
  ];

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  @override
  void initState() {
    super.initState();
    FirstRunStore.instance.addListener(_onRoleChanged);
    // v2.13+：错题未复习徽标数据源。存入/标记复习/AI 整理都会
    // notifyListeners → 徽标实时刷新（UX 走查 P0：存入→复习闭环的
    // 引导信号，学生不用自己记「有几道没复习」）。
    MistakeBook.instance.addListener(_onBookChanged);
  }

  @override
  void dispose() {
    FirstRunStore.instance.removeListener(_onRoleChanged);
    MistakeBook.instance.removeListener(_onBookChanged);
    super.dispose();
  }

  void _onRoleChanged() {
    if (mounted) setState(() {});
  }

  void _onBookChanged() {
    if (mounted) setState(() {});
  }

  /// v2.12 Wave 3-B：按角色过滤入口列表。
  /// - 老师：12 张主导航卡（隐藏错题本 + 显老师工具卡）= 13 张
  /// - 学生 / 未定：12 张主导航卡 + 错题本 = 13 张
  /// - 角色未定（首启）：默认学生视图（显错题本 + 隐藏老师工具）
  ///
  /// 老师角色下：
  ///   - studentOnly=true 的卡（错题本）隐藏
  ///   - teacherOnly=true 的卡（老师工具占位）显示
  /// 学生角色下：
  ///   - studentOnly=true 的卡（错题本）显示
  ///   - teacherOnly=true 的卡（老师工具）隐藏
  /// 两种角色均为 13 张卡：3 列网格滚动展示（首屏不必一次铺满）。
  /// v2.19.24：主卡 9→10（加大题套路卡）。
  /// v2.20.0：主卡改由导航目录生成（11 → 12：补上此前漏掉的变异 /
  /// 人类遗传病），每角色总数 13。
  ///
  /// v2.13 R5 P0：移除「家长」分支——产品决策 Biology 不面向家长，
  /// 原"学生 / 家长"等价组合并为单一"学生"路径。
  List<_ToolEntry> _visibleEntries() {
    final role = FirstRunStore.instance.currentRole();
    if (role == UserRole.teacher) {
      return widget._baseEntries
          .where((e) => !e.studentOnly) // 隐藏错题本
          .toList();
    }
    // 学生 / 未定：隐藏老师工具
    return widget._baseEntries.where((e) => !e.teacherOnly).toList();
  }

  /// v2.13 R5 P0：角色切换 dialog。2 选 1，老师 / 学生。
  ///
  /// v2.12 / v2.13 早期版本曾有第 3 选项「家长」——v2.13 R5 硬编码
  /// 移除：产品决策「Biology 不面向家长角色」，与 _showFirstRunRoleDialog
  /// 同步（首启 / 切换两条路径都去掉家长）。用户可随时切到老师（看老师
  /// 工具卡）或回学生（看错题本卡）。
  Future<void> _showRoleSwitchDialog(BuildContext context) async {
    final picked = await showDialog<UserRole>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('切换使用角色'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '选择最贴近你的使用场景，错题本等私人空间按角色显示。',
              style: AppText.body.copyWith(color: AppColors.graphite),
            ),
            const SizedBox(height: 16),
            // v2.13 R5 P0：硬编码 2 张卡（与首启 dialog 对齐）。
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.school_outlined, color: AppColors.teal),
              title: Text(UserRole.teacher.displayName, style: AppText.label),
              subtitle: Text('备课 / 讲题 / 演示模式（无错题本）', style: AppText.caption),
              onTap: () => Navigator.of(ctx).pop(UserRole.teacher),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.person_outline, color: AppColors.teal),
              title: Text(UserRole.student.displayName, style: AppText.label),
              subtitle: Text('刷题 / 错题整理 / 复习（含错题本）', style: AppText.caption),
              onTap: () => Navigator.of(ctx).pop(UserRole.student),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('取消'),
          ),
        ],
      ),
    );
    if (picked != null) {
      await FirstRunStore.instance.setRole(picked);
    }
  }

  @override
  Widget build(BuildContext context) {
    final role = FirstRunStore.instance.currentRole();
    final entries = _visibleEntries();
    // v2.21.0：入口按 id 建索引（**不按显示名映射**——文案会随迭代改，
    // id 才是身份）。角色过滤已在 _visibleEntries 完成，这里只做归类。
    final byId = <String, _ToolEntry>{for (final e in entries) e.id: e};
    final core = _pick(byId, _coreEntryIds);
    final groups = <_ModuleGroup>[
      _ModuleGroup('计算工具', Icons.tune, _pick(byId, _computeEntryIds)),
      _ModuleGroup(
        '学习支持',
        Icons.menu_book_outlined,
        _pick(byId, _learnEntryIds),
      ),
      _ModuleGroup(
        '系统与帮助',
        Icons.settings_outlined,
        _pick(byId, _systemEntryIds),
      ),
    ].where((g) => g.entries.isNotEmpty).toList();
    // 不重不漏兜底：每个入口必须恰好落在一个分区里。新增导航页时忘了
    // 归类（或同一 id 在两处出现），debug 下当场炸；release 下不付代价。
    assert(() {
      final placed = <String>[
        for (final e in core) e.id,
        for (final g in groups)
          for (final e in g.entries) e.id,
      ];
      return placed.length == entries.length &&
          placed.toSet().length == entries.length;
    }(), '首页分区必须覆盖全部入口且不重复（检查 _coreEntryIds 等分组表）');
    // v2.13+：待复习徽标数据源（与 dueEntries 排期对齐——未复习随时
    // 到期/复习中 1 天/已掌握 3 天；v2.13 复习会话前是未复习计数，
    // 语义偏窄：刚「还需复习」的题仍被计为未复习）。老师角色下错题本卡
    // 隐藏，徽标不会被看到；此处不区分角色统一计算，代价可忽略。
    // v2.21.0：徽标按 id 挂（`mistakes`），不再比显示名。
    final dueCount = MistakeBook.instance.dueEntries().length;
    final mistakeBadge = dueCount > 0 ? '$dueCount 道待复习' : null;
    return Scaffold(
      appBar: AppBar(title: const Text('生物遗传计算平台')),
      body: SafeArea(
        // v2.21.0：整页一个滚动容器。旧版「固定头部 + Expanded(GridView)」
        // 把首屏全部高度给了卡片墙，头部只能塞三行等宽灰字——层级无从
        // 谈起。改成一页滚动后，欢迎区可以真的「大」，核心区可以真的
        // 「强调」，分组区可以真的「紧凑」。
        child: LayoutBuilder(
          builder: (context, c) {
            // 桌面（≥900）三核心并列；手机核心卡全宽纵向排列。
            final wide = c.maxWidth >= 900;
            final hPad = wide ? 24.0 : 16.0;
            // v2.23.2（M3.1 投影复核）：全局「问 AI」extended FAB 浮在
            // Scaffold 右下（endFloat，右边距 16）——内容居中铺满时右缘
            // 会滑进 FAB 柱，1280 投影 golden 实测 FAB 左缘压住「Hardy-
            // Weinberg 与选择逐代模拟」末字。
            //
            // 净空按**实际需要**给（不无脑推移整页）：
            //   fabZone = FAB 柱占位（Scaffold 边距 16 + FAB 宽≈ padding
            //   64 + icon 24 + 间距 8 + 「问 AI」标签≈2.6em×14px，随课堂
            //   textScaler 缩放；88+36×scale 含 ~5–9px 安全余量）。
            //   freeRight = 内容居中后右缘到视口右缘的自然距离。
            //   仅当 fabZone > freeRight（1280/1400 一类窄投影档）才把
            //   内容左推补足；1920 自然净空足够 ⇒ 零位移，golden 不动。
            // 窄档（<900，含 390 手机）完全不参与——移动端现状保持。
            final textScaler = MediaQuery.textScalerOf(context);
            final fabZone = 96.0 + 40.0 * textScaler.scale(1.0);
            final avail = c.maxWidth - 2 * hPad;
            final contentW = math.min(1040.0, avail);
            final freeRight = hPad + (avail - contentW) / 2;
            double fabRightPad = 0;
            if (wide && fabZone > freeRight) {
              // 缩到 1040 以内需要的补距 = fabZone - hPad；若补完内容仍
              // 宽于 1040（居中还会分掉一半补距），按居中几何翻倍补齐。
              final shrinkE = fabZone - hPad;
              fabRightPad = (avail - shrinkE <= 1040.0)
                  ? shrinkE
                  : 2 * (fabZone - freeRight);
            }
            // v2.22.0：窄屏（<600，与主导航档位同一断点）分组入口改单列
            // ——双列时每列只有 ~160px，说明被压成省略号（「碱基互补 / 两链…」
            // 「Hardy-Weinber…」），读不出用途。单列后横向 ~330px，
            // 名称与说明可完整折行。核心三卡与宽屏双列一律不动。
            final narrowGroups = c.maxWidth < 600;
            return SingleChildScrollView(
              // 新手引导高亮目标（GuideKeys.dashboardGrid）：引导框的是
              // 「整块入口区」，故挂在滚动容器上而不是某一组。
              key: GuideKeys.dashboardGrid,
              padding: EdgeInsets.fromLTRB(
                hPad,
                wide ? 20 : 12,
                // 右侧含 FAB 净空列（非必要时为 0，见上 fabRightPad）。
                hPad + fabRightPad,
                28,
              ),
              child: Center(
                child: ConstrainedBox(
                  // 阅读宽度上限：1900 宽投影时三核心卡不该一张卡占一屏
                  //（卡片宽度随窗口线性膨胀 = 大屏反而更难读）。
                  constraints: const BoxConstraints(maxWidth: 1040),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // ── 欢迎 / 状态区 ───────────────────────────
                      // 三级层次：大标题 → 定位语 → 状态行（使用模式 +
                      // 角色）。旧版三行同字号灰字平铺，首屏读完仍不知道
                      // 「先点哪个」。
                      Text(
                        '遗传计算工作台',
                        style: AppText.pageTitle.copyWith(
                          fontSize: 27,
                          height: 1.15,
                          letterSpacing: -0.5,
                        ),
                      ),
                      const SizedBox(height: 8),
                      // ⛔ 精确定位语：老测试按这串字断言，勿改字。
                      Text(
                        '输入题目数据，直接算出结果——通用生物计算器',
                        style: AppText.body.copyWith(color: AppColors.graphite),
                      ),
                      const SizedBox(height: 14),
                      // 状态行：使用模式（学生 / 课堂）+ 角色 chip 同排。
                      // 两项都是「当前处于什么状态」，各占一行会把首屏
                      // 高度从核心卡里挤掉。
                      Wrap(
                        spacing: 14,
                        runSpacing: 8,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          // v2.3 使用模式快捷切换（学生/课堂分别做，用户
                          // 裁定）：老师上课前一键切课堂模式（大字号 +
                          // 画布激光笔），学生默认学生模式，用不到也不被
                          // 打扰。
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.switch_account_outlined,
                                size: 18,
                                color: AppColors.steel,
                              ),
                              const SizedBox(width: 8),
                              ModeSwitcher(),
                            ],
                          ),
                          // v2.12 Wave 3-B：角色 chip + 切换入口。点击 chip
                          // 弹 dialog 选 2 选 1 角色。错题本可见性 = 角色
                          // 分流的核心入口。
                          // v2.13 R5 P0：dialog 改 2 选 1（移除家长）。
                          ActionChip(
                            key: const Key('dashboard_role_chip'),
                            avatar: Icon(
                              // v2.13 R5 P0：枚举只有 teacher / student
                              // 两值，简化三元：teacher →
                              // school_outlined，其他（含 null 未选 /
                              // student）→ person_outline。
                              role == UserRole.teacher
                                  ? Icons.school_outlined
                                  : Icons.person_outline,
                              size: 16,
                              color: AppColors.teal,
                            ),
                            label: Text(
                              '当前：${role?.displayName ?? "未选择"}',
                              style: AppText.caption.copyWith(
                                color: AppColors.ink,
                              ),
                            ),
                            onPressed: () => _showRoleSwitchDialog(context),
                            backgroundColor: AppColors.tealWash,
                            side: BorderSide(color: AppColors.border),
                          ),
                        ],
                      ),
                      // R6 双走查 #2：老师模式下「我的错题」静默消失，学生
                      // 选错角色找不到错题本——在状态行下方给一行显式说明
                      // + 指路。
                      if (role == UserRole.teacher)
                        Padding(
                          padding: const EdgeInsets.only(top: 10),
                          child: Text(
                            '老师模式：错题本是学生私人空间，已为你隐藏——'
                            '点上方角色或去「设置」可切回学生。',
                            style: AppText.caption.copyWith(
                              color: AppColors.steel,
                            ),
                          ),
                        ),
                      // ── 三核心工作区 ───────────────────────────
                      // 三张卡承接「90% 的使用频次」，用更大的图标块、
                      // 更重的标题、右侧 chevron 与分组里的紧凑行区分开。
                      const SizedBox(height: 22),
                      // 非 const 实例：本组件在 build 期读 AppColors token，
                      // const 会被 canonicalize → Element identical 短路 →
                      // 换肤后文字色值永久冻结（v2.2 / v2.19.20 事故同款）。
                      _SectionHeading(
                        title: '核心工作区',
                        hint: '系谱推断 · 9331 及变式 · 图谱浏览',
                      ),
                      const SizedBox(height: 12),
                      if (wide)
                        IntrinsicHeight(
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              for (var i = 0; i < core.length; i++) ...[
                                if (i > 0) const SizedBox(width: 14),
                                Expanded(
                                  child: _CoreCard(
                                    entry: core[i],
                                    onOpenTool: widget.onOpenTool,
                                    primary: core[i].id == _primaryEntryId,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        )
                      else
                        // 手机（<900）：核心卡全宽纵向排列——横向两列在
                        // 390 上会把「9331 及变式 / 测交 / 致死等 6 类」
                        // 这类说明压成两行省略号。
                        for (var i = 0; i < core.length; i++) ...[
                          if (i > 0) const SizedBox(height: 12),
                          _CoreCard(
                            entry: core[i],
                            onOpenTool: widget.onOpenTool,
                            primary: core[i].id == _primaryEntryId,
                          ),
                        ],
                      // ── 分组模块 ───────────────────────────────
                      // 组内紧凑双列（图标 + 名称 + 一行说明）：1900 上保持
                      // 同一密度，不随窗口膨胀成 4~5 列；窄屏（<600）改
                      // 单列，说明完整折行（见 narrowGroups 注释）。
                      for (final g in groups)
                        _GroupSection(
                          group: g,
                          onOpenTool: widget.onOpenTool,
                          mistakeBadge: mistakeBadge,
                          singleColumn: narrowGroups,
                        ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// v2.21.0：按 id 从索引里取入口（保持 [ids] 顺序；被角色过滤掉的 id
/// 直接跳过——老师 / 学生两种角色的分区表因此不需要各写一份）。
List<_ToolEntry> _pick(Map<String, _ToolEntry> byId, List<String> ids) =>
    <_ToolEntry>[
      for (final id in ids)
        if (byId[id] != null) byId[id]!,
    ];

/// 一组「非核心」入口（组名 + 组内入口）。
class _ModuleGroup {
  const _ModuleGroup(this.label, this.icon, this.entries);

  final String label;
  final IconData icon;
  final List<_ToolEntry> entries;
}

/// 分区标题：左侧 teal 竖条 + 短标题 + 一句提示（提示超宽省略，不撑破
/// 390 窄屏）。
class _SectionHeading extends StatelessWidget {
  const _SectionHeading({required this.title, required this.hint});

  final String title;
  final String hint;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 3,
          height: 16,
          margin: const EdgeInsets.only(right: 8),
          decoration: BoxDecoration(
            color: AppColors.teal,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        Text(title, style: AppText.sectionTitle.copyWith(fontSize: 16)),
        const SizedBox(width: 10),
        Flexible(
          child: Text(
            hint,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppText.caption.copyWith(color: AppColors.steel),
          ),
        ),
      ],
    );
  }
}

/// 打开一个入口：customTap（Navigator.push）优先，否则切主导航索引。
///
/// 两条卡型（核心 / 紧凑行）共用同一段跳转逻辑，避免「核心卡能点、
/// 分组行点不动」这种两套实现的漂移。
void _openEntry(
  _ToolEntry entry,
  BuildContext context,
  void Function(int navIndex) onOpenTool,
) {
  if (entry.customTap != null) {
    entry.customTap!(context);
  } else {
    // customTap 为 null 时必走 onOpenTool 分支，navIndex 不为 null
    //（构造时强制）。
    onOpenTool(entry.navIndex!);
  }
}

/// 核心工作区卡片（系谱推断 / 9331 及变式 / 图谱浏览）。
///
/// 强调手法（相对分组里的紧凑行）：更大的图标块（44）、更重的标题
/// （15 / w700）、右侧 chevron 指明「点了会去哪」。薄壳走
/// [ModuleSurface]，卡内不再套 Card——两层描边会把层级重新压平。
///
/// v2.23 首页层级：核心三卡里 [entry.id] == `pedigree` 的那张是**全页
/// 主入口**——用 Sage 实色（[AppColors.teal] 满铺）+ onTeal 高对比抬成
/// 「打开第一眼就点这里」的视觉锚点；另两张保持浅色同族层次（tealWash
/// 图标块 + ink 标题）。实色填充由本卡在 build 期求值（**不 const 缓存**，
/// 换肤即时生效），并借 [ModuleSurface] 的 antiAlias 裁剪成同款圆角。
class _CoreCard extends StatelessWidget {
  const _CoreCard({
    required this.entry,
    required this.onOpenTool,
    this.primary = false,
  });

  final _ToolEntry entry;
  final void Function(int navIndex) onOpenTool;

  /// 是否为全页主入口（Sage 实色 + onTeal 高对比）。
  final bool primary;

  @override
  Widget build(BuildContext context) {
    // 主色 / 前景按 primary 在 build 期求值；非 const，换肤即时生效。
    final fg = primary ? AppColors.onTeal : AppColors.ink;
    // v2.23.1：副文字用**不透明** onTeal——原 onTeal@0.82 对 teal 仅
    // 4.11:1（< WCAG AA 4.5）。白（浅色）/ 近黑（深色）对 Sage 实底
    // 反而最高对比，深色模式不退化。
    final descColor = primary ? AppColors.onTeal : AppColors.steel;
    final tileBg = primary
        ? AppColors.onTeal.withValues(alpha: 0.16)
        : AppColors.tealWash;
    final iconColor = primary ? AppColors.onTeal : AppColors.teal;

    return ModuleSurface(
      padding: EdgeInsets.zero,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: () => _openEntry(entry, context, onOpenTool),
          // 主入口：克制的 hover/focus/press 反馈（onTeal 低透明度微光，
          // 深浅模式各自成立；无持续动画，不降低触控目标）。
          hoverColor: primary ? AppColors.onTeal.withValues(alpha: 0.06) : null,
          focusColor: primary ? AppColors.onTeal.withValues(alpha: 0.10) : null,
          splashColor:
              primary ? AppColors.onTeal.withValues(alpha: 0.12) : null,
          highlightColor:
              primary ? Colors.black.withValues(alpha: 0.10) : null,
          // v2.23.1（DeepSeek 像素复核 P0）：实色填充必须走 [Ink] 而不是
          // DecoratedBox——_RenderInkFeatures 先画 ink feature、再画 child
          // （Flutter material.dart），不透明 DecoratedBox child 会把
          // hover / focus / splash 全部盖住（实测 hover 仅边缘 6px、
          // maxΔ2，focus 完全不可见）。Ink 把填充注册成 ink feature：
          // 注册顺序在交互高亮（hover/focus/press 时才注册）之前，因此
          // 填充垫底层、交互色叠画其上，深浅模式皆真正可见。
          // 借 ModuleSurface 的 antiAlias 裁剪收 14px 圆角，几何不变。
          child: Ink(
            decoration: BoxDecoration(
              color: primary ? AppColors.teal : Colors.transparent,
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 12, 16),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: tileBg,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(entry.icon, size: 24, color: iconColor),
                  ),
                  const SizedBox(width: 13),
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // v2.23.2（M3.1 投影复核）：标题行 Row → Wrap。
                        // 课堂 ×1.75 大字号下「遗传图谱计算」（6×28px）
                        // +「主入口」小标在 1280/1920 三列卡宽里塞不进
                        // 一行，原 Row + Flexible(maxLines:1) 把标题压成
                        // 省略号（投影 golden 实测「遗传图…/遗传图谱…」）。
                        // Wrap 放不下时小标自动换到下一行，标题允许 2 行
                        // 完整可读——不缩字号、不隐藏小标、非主卡视觉不变。
                        Wrap(
                          spacing: 8,
                          runSpacing: 4,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Text(
                              entry.name,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: AppText.label.copyWith(
                                fontSize: primary ? 16 : 15,
                                fontWeight: FontWeight.w700,
                                color: fg,
                              ),
                            ),
                            if (primary)
                              // 非 const 调用：_PrimaryTag.build 读 onTeal
                              // 实时 token；若 const 会 canonicalize 成同一
                              // 实例，父级重建时 Element 因 identical 短路、
                              // build 不重跑 → 换肤后小标色冻结。
                              _PrimaryTag(),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          entry.desc,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: AppText.caption.copyWith(color: descColor),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 6),
                  Icon(
                    Icons.chevron_right,
                    size: 18,
                    // v2.23.1：非文字 UI 元素 ≥3:1（AA），不透明 onTeal
                    // 最高对比，与标题/副文字同口径。
                    color: primary ? AppColors.onTeal : AppColors.steel,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 主入口卡上的「主入口」小标（v2.23）：与实色卡同色系、不引入新色相；
/// 仅作扫读提示，不是数据。
///
/// v2.23.1（对比度复核）：原 onTeal@0.18 底 + onTeal 文字对 teal 实底仅
/// 3.61:1（< AA 4.5）。改为**透明底**（露出卡面 teal 实色）+ 不透明
/// onTeal 文字/描边——白/近黑对 Sage 本就是最高对比，深浅模式皆达标。
class _PrimaryTag extends StatelessWidget {
  const _PrimaryTag();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        // 透明底：对比度由「不透明 onTeal 文字 × 卡面实色 teal」保证，
        // 不再叠一层半透明底把对比度摊薄。
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: AppColors.onTeal),
      ),
      child: Text(
        '主入口',
        style: AppText.caption.copyWith(
          color: AppColors.onTeal,
          fontSize: 11,
          height: 1.2,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

/// 分组里的紧凑入口行（图标 + 名称 + 一行说明）。
///
/// v2.21.0 徽标口径：待复习徽标按 **id == 'mistakes'** 挂在这一行里，
/// 顶替说明行（不再是卡右上角的浮层）——紧凑行只有两行文字，浮层会
/// 压住名称末尾。0 道待复习时不渲染，文字层数不变。
class _CompactTile extends StatelessWidget {
  const _CompactTile({
    required this.entry,
    required this.onOpenTool,
    this.badge,
    this.singleColumn = false,
  });

  final _ToolEntry entry;
  final void Function(int navIndex) onOpenTool;
  final String? badge;

  /// v2.22.0：窄屏单列模式——名称与说明**完整折行**，不再一行省略号。
  ///
  /// 双列时每列只有 ~160px，「碱基互补 / 两链互推 / DNA 标记」这类说明
  /// 会被压成「碱基互补 / 两链…」「Hardy-Weinber…」——学生根本读不出
  /// 这个入口是干什么的。窄屏改为单列后横向有 ~330px，说明可完整折行。
  final bool singleColumn;

  @override
  Widget build(BuildContext context) {
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => _openEntry(entry, context, onOpenTool),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          child: Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: AppColors.tealWash,
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Icon(entry.icon, size: 18, color: AppColors.teal),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      entry.name,
                      // 窄屏单列：不限行数（完整折行）；双列：单行省略号。
                      maxLines: singleColumn ? null : 1,
                      overflow: singleColumn
                          ? TextOverflow.clip
                          : TextOverflow.ellipsis,
                      style: AppText.label,
                    ),
                    const SizedBox(height: 2),
                    if (badge != null)
                      Row(
                        children: [
                          Container(
                            width: 6,
                            height: 6,
                            decoration: BoxDecoration(
                              color: AppColors.teal,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 5),
                          Flexible(
                            child: Text(
                              badge!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppText.caption.copyWith(
                                color: AppColors.teal,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      )
                    else
                      Text(
                        entry.desc,
                        // 窄屏单列：说明完整折行可读（不被人为省略号截断）。
                        maxLines: singleColumn ? null : 1,
                        overflow: singleColumn
                            ? TextOverflow.clip
                            : TextOverflow.ellipsis,
                        style: AppText.caption.copyWith(color: AppColors.steel),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 一个分组：ModuleSurface 薄壳（组名做标题）+ 组内紧凑双列。
class _GroupSection extends StatelessWidget {
  const _GroupSection({
    required this.group,
    required this.onOpenTool,
    this.mistakeBadge,
    this.singleColumn = false,
  });

  final _ModuleGroup group;
  final void Function(int navIndex) onOpenTool;
  final String? mistakeBadge;

  /// v2.22.0：窄屏（<600）单列列表；宽屏仍是紧凑双列。
  final bool singleColumn;

  @override
  Widget build(BuildContext context) {
    return ModuleSurface(
      margin: const EdgeInsets.only(top: 18),
      padding: const EdgeInsets.fromLTRB(12, 16, 12, 12),
      title: group.label,
      icon: group.icon,
      child: _CompactGrid(
        singleColumn: singleColumn,
        children: [
          for (final e in group.entries)
            _CompactTile(
              entry: e,
              onOpenTool: onOpenTool,
              // 按 id 挂徽标（不按显示名）。
              badge: e.id == 'mistakes' ? mistakeBadge : null,
              singleColumn: singleColumn,
            ),
        ],
      ),
    );
  }
}

/// 组内紧凑双列。
///
/// 固定两列（不是「随窗口涨列数」）：组内行只有图标 / 名称 / 一行说明，
/// 两列在 1900 是可扫读密度；列数随窗口变会让同一组在大屏上
/// 稀疏成大卡片（层级又被抹平）。非懒加载——所有入口一次性建出来，
/// 键盘遍历与「跳到末项」不受视口限制。
///
/// v2.22.0：窄屏（<600）改**单列**——双列时每列仅 ~160px，说明被压成
/// 省略号（「碱基互补 / 两链…」「Hardy-Weinber…」），学生读不出用途。
class _CompactGrid extends StatelessWidget {
  const _CompactGrid({required this.children, this.singleColumn = false});

  final List<Widget> children;

  /// 窄屏单列（纵向堆叠）还是宽屏双列。
  final bool singleColumn;

  static const double _gap = 12;

  @override
  Widget build(BuildContext context) {
    // v2.22.0：单列 —— 复用同一枚紧凑行（图标 + 名称 + 说明），只把
    // 说明从「一行省略号」放开为完整折行；不引入新的卡片层级。
    if (singleColumn) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) const SizedBox(height: 4),
            children[i],
          ],
        ],
      );
    }
    final rows = <Widget>[];
    for (var i = 0; i < children.length; i += 2) {
      final second = i + 1 < children.length ? children[i + 1] : null;
      if (rows.isNotEmpty) rows.add(const SizedBox(height: 4));
      rows.add(
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: children[i]),
            const SizedBox(width: _gap),
            Expanded(child: second ?? const SizedBox.shrink()),
          ],
        ),
      );
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: rows,
    );
  }
}

/// v2.12+ R1 P0 #2：老师工作流页（实装 2 项 + 1 项 v2.13 占位）。
///
/// 老师选了角色后，dashboard 上有「老师工具」入口跳到这里。
/// v2.12+ R1 之前是 stub（center + 「敬请期待 v2.13」灰卡），老师首启
/// 100% 看到会感觉软件"半成品"。本次实装：
///
///   1. 板书 SVG / PNG 导出历史
///      列出 `~/.biology_app/board_history/` 下已保存的 .svg / .png 文件
///      （按 mtime 倒序，默认前 10 条 + 「查看更多」全量），并提供
///      「去系谱页生成」入口跳到系谱页——
///      系谱页有现成的「复制 SVG」按钮（v2.12 板书 PDF 基础件已就绪，
///      svg_export.dart 实现）。这样 v2.12+ R1 不重复造轮子，板书 SVG
///      导出走系谱页→SVG 链路，老师工具卡只做"历史 + 入口"。
///
///   2. 拍题识别次数
///      累加统计：错题本总条数（学生角色才看得到，老师不显错题本故这
///      里用内置题库条目数 + 全局 MistakeBook 总数） + 内置题库（拍题
///      识别后自动入库的 ScanBankStore）。数据从 ScanBankStore.load()
///      + MistakeBook.instance.entries 读，**只读**——不依赖错题本角色
///      过滤（老师角色下错题本入口隐藏，但实例数据还在）。
///
///   3. 班级共性错
///      v2.13 完整版（聚合多学生错题数据）放占位：按钮 + 「敬请期待
///      v2.13」提示。设计意图保留，不假装有功能（避免半成品感）。
///
/// 持久化：
///   - 板书历史：`<userAppDir>/board_history/*.svg` + `*.png`（File 落盘）
///   - 拍题次数：每次进老师页实时读 ScanBankStore + MistakeBook，**不**
///     单独持久化（避免数据源分歧；统计本身是派生量）。
///   - Web 端：userAppDir() 返 null，板书历史列表为空 + 拍题次数仍
///     可从 localStorage 的 scan_bank_json 读（ScanBankStore.load() 内部
///     走 storageGet，与 IsWebStorage 分支对齐）。
class _TeacherPage extends StatefulWidget {
  const _TeacherPage({required this.onOpenPedigree});

  /// v2.12+ R1 P0 #2：跳到系谱页（v2.12 板书 PDF 入口）的回调。
  ///
  /// 不直接 import genetic_pedigree_page（避免反向依赖：老师工具卡是
  /// dashboard 内部 widget，dashboard 已被 R1-C 跨端 worker 触及，
  /// genetic_pedigree_page 同时被 R1-D 触及——多 worker 并行下，硬
  /// 引用会让编译相互阻塞）。改用回调注入：dashboard 持有
  /// `onOpenTool` 切主导航索引的现成机制，老师卡用同一个 callback
  /// 切到系谱页（navIndex = 1 = 遗传图谱计算）。这条路径不破坏既有
  /// 「dashboard 是导航事实源」的设计原则。
  final void Function() onOpenPedigree;

  @override
  State<_TeacherPage> createState() => _TeacherPageState();
}

class _TeacherPageState extends State<_TeacherPage> {
  /// 当前展示的板书历史（v2.13 R4：`_allBoardHistory` 的前 10 条，
  /// 「查看更多」后全量——见 `_showAllBoards`）。
  List<FileSystemEntity> _boardHistory = const [];

  /// v2.13 R4 P1：全量板书历史（.svg + .png，按 mtime 倒序），
  /// 不随 take(10) 截断——「查看更多」分页的数据源。
  List<FileSystemEntity> _allBoardHistory = const [];
  // v2.13 老师走查金点子：课堂讲题回放——HistoryStore 数据「已写未读」，
  // 按天聚合「今天讲过哪些题」，周一接着上周五讲。
  List<HistoryEntry> _history = const [];

  /// v2.13 R4 P1：是否已展开全量板书历史（默认收起只显示前 10 条）。
  bool _showAllBoards = false;

  /// R7 老师走查 #7：班级共性错时间窗（true=本周，默认——讲课决策
  /// 看近期新错，不被历届累积带偏）。
  bool _classMistakeWeekly = true;

  /// R5 老师走查：回放卡默认前 15 条，「查看全部」展开（课上连讲超过
  /// 15 次时昨天的题就滚出去了——恰是最需要回放的场景）。
  bool _showAllHistory = false;

  int _mistakeCount = 0;
  int _scanBankCount = 0;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
    // v2.13+ 老师走查 P0：回放卡自动刷新——HistoryStore.revision 在
    // 任何写入（系谱页/计算器各 tab）时递增；此前只在 initState 读
    // 一次，计算器算完回到 dashboard（IndexedStack 不重建）看不到新记录。
    HistoryStore.revision.addListener(_onHistoryRevision);
    // R6 老师走查 #4：MistakeBook 懒加载此前只在错题本页触发——讲台机
    // 以老师角色启动、从不开错题本页 → 班级共性错/错题计数恒为 0（不
    // 报错不提示，以为没数据其实是没加载）。这里预载 + 完成后刷新。
    MistakeBook.instance.load().whenComplete(() {
      if (mounted) setState(() {});
    });
  }

  void _onHistoryRevision() {
    if (mounted) _load();
  }

  @override
  void dispose() {
    HistoryStore.revision.removeListener(_onHistoryRevision);
    super.dispose();
  }

  /// 板书历史目录：`<userAppDir>/board_history/`。Web 端返 null → 列表空。
  /// 不复用 _file() helper（那是 MistakeBook / HistoryStore 的私有
  /// 命名）——独立写一个避免越界改其它文件。
  ///
  /// 测试可设 `debugBoardHistoryDir` 覆盖默认路径（用于临时目录隔离）。
  static String? _boardHistoryDir() {
    if (DashboardPage.debugBoardHistoryDirForTest != null) {
      return DashboardPage.debugBoardHistoryDirForTest!;
    }
    final appDir = userAppDir();
    if (appDir == null) return null;
    final sep = Platform.pathSeparator;
    return '$appDir${sep}board_history';
  }

  Future<void> _load() async {
    // 1) 板书历史：列 .svg + .png 文件，按 mtime 倒序，全量存
    //    _allBoardHistory；_boardHistory 默认取前 10 条（「查看更多」
    //    后全量——take(10) 封顶不再让旧板书不可达）。
    final dir = _boardHistoryDir();
    final list = <FileSystemEntity>[];
    if (dir != null) {
      try {
        final d = Directory(dir);
        if (!d.existsSync()) d.createSync(recursive: true);
        final entries = d.listSync().where((e) {
          if (e is! File) return false;
          final p = e.path.toLowerCase();
          // v2.13 R4 P1：SVG + PNG 都归档（老师高频路径是「保存为 PNG 文件」）。
          return p.endsWith('.svg') || p.endsWith('.png');
        }).toList();
        entries.sort((a, b) {
          final am = a.statSync().modified;
          final bm = b.statSync().modified;
          return bm.compareTo(am); // 倒序
        });
        list.addAll(entries);
      } catch (_) {
        // 目录不可读 = 空列表（不抛错，老师页不阻塞）
      }
    }

    // 2) 拍题识别次数：错题本 + 内置题库
    var mistakeCount = 0;
    var scanCount = 0;
    try {
      // R6 老师走查 #4：先确保 MistakeBook 已加载（懒加载此前只在错题
      // 本页触发，讲台机恒显 0）。load 幂等 + FLUTTER_TEST 守卫。
      await MistakeBook.instance.load();
      mistakeCount = MistakeBook.instance.entries.length;
    } catch (_) {
      /* 内存读失败 = 0 */
    }
    try {
      // ScanBankStore 走 load()（持久化路径与 _file() 解析逻辑对齐），
      // 不主动 trigger 加载——读是冷路径，能拿多少算多少。
      final entries = await ScanBankStore.load();
      scanCount = entries.length;
    } catch (_) {
      /* load 失败 = 0（损坏文件 / Web 端无 localStorage）*/
    }

    // 3) 课堂讲题回放：计算历史（HistoryStore 只读，跨页同步无需监听）。
    var history = const <HistoryEntry>[];
    try {
      history = await HistoryStore.load();
    } catch (_) {
      /* 读失败 = 空回放 */
    }

    if (!mounted) return;
    setState(() {
      _allBoardHistory = list;
      _boardHistory = _showAllBoards ? list : list.take(10).toList();
      _mistakeCount = mistakeCount;
      _scanBankCount = scanCount;
      _history = history;
      _loading = false;
    });
  }

  // ---- v2.12+ R1 final D P0 #3：板书历史列表行操作 ----

  /// 重新复制板书 SVG 到剪贴板（复用 v2.12 已有 Clipboard.setData 链路，
  /// 同 genetic_pedigree_page._copySvgText）。读 .svg 文件 → 文本
  /// 走系统剪贴板，粘到富文本 / 微信 / Word 看到的是 `<svg>...</svg>`
  /// 字符串（同 P0 #4「复制 SVG」行为）。
  Future<void> _copyBoardToClipboard(FileSystemEntity f) async {
    try {
      final content = await File(f.path).readAsString();
      await Clipboard.setData(ClipboardData(text: content));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('SVG 文本已复制（粘到富文本编辑器 / 保存为 .svg）')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('复制失败：$e')));
    }
  }

  /// 在系统文件管理器中定位该 SVG 文件。
  ///
  /// 跨端逻辑抽到 `MistakeBookExporter.openInExplorer`（v2.12+ R2 P1 抽），
  /// 供错题本导出 SnackBar [打开下载目录] 和本方法共用。失败时本方法
  /// 弹 SnackBar 提示（dashboard 老师页用，行为与 R1 一致）。
  ///
  /// v2.12+ R2 A2 P1-5：openInExplorer 返回 `String?` 错误原因（含
  /// Process.start 抛错细节），本方法直接显示——修复 R1 引入的
  /// Process.start 漏 await / stdout / stderr 消费问题。
  Future<void> _showBoardInExplorer(FileSystemEntity f) async {
    // v2.12+ R2 A2 P1-6：web 端没有文件管理器概念——放行会进
    // openInExplorer 的 Platform 分支（dart:io web stub 抛
    // UnsupportedError）→ 弹「在文件管理器中显示失败：...」技术
    // 错误。守卫：直接提示改用「重新复制到剪贴板」。
    if (DashboardPage.debugForceIsWeb || kIsWeb) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Web 端请用「重新复制到剪贴板」')));
      return;
    }
    final err = await MistakeBookExporter.openInExplorer(f.path);
    if (err != null) {
      // 跨端无文件管理器概念（Web / Android）或启动文件管理器失败
      //（Process.start 抛错 / 5 秒 timeout → P1-5 防御性 catch）。
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
    }
  }

  /// 永久删除单个板书文件（SVG / PNG）。
  ///
  /// v2.12+ R1 final D P0 #3：板书历史是「只读博物馆 + 重用」模型，
  /// 历史文件可永久删（与 R1 P0 #5 错题本回收站 7 天软删除不同——
  /// 板书 SVG 是从系谱页现场再生成的派生数据，不是用户原创内容，
  /// 永久删更直接，避免「板书回收站」二级界面）。
  ///
  /// v2.13 R4 P1：永久删除加**二次确认 dialog**（原来点按钮直接删——
  /// 老师可能误触「永久删除」图标，OS 真删后不可恢复，只能去系谱页
  /// 重画）。弹「删除板书？」确认框，取消不删，确认才走删除。
  Future<void> _deleteBoardFile(FileSystemEntity f) async {
    final name = f.path.split(Platform.pathSeparator).last;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除板书？'),
        content: Text('「$name」将被永久删除，无法恢复。\n如需重新生成请去系谱页重画。'),
        actions: [
          TextButton(
            key: const Key('board_history_delete_cancel_btn'),
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            key: const Key('board_history_delete_confirm_btn'),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('永久删除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await File(f.path).delete();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('删除失败：$e')));
      return;
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('已永久删除'),
        action: SnackBarAction(
          // 误删兜底：从同目录 mtime 找同名文件恢复——但 SVG 已被
          // OS 真删，无法恢复。这里只触发 reload 让用户视觉上看到
          // 「操作生效」。若用户需要重新生成该板书，去系谱页重画
          // 即可（系谱页有现成「存为板书」入口，R1 P0 #4 实装）。
          label: '知道了',
          onPressed: () {},
        ),
      ),
    );
    // 重新加载列表让行消失
    setState(() => _loading = true);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('老师工具'),
        actions: [
          IconButton(
            tooltip: '刷新统计',
            onPressed: () {
              setState(() => _loading = true);
              _load();
            },
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                children: [
                  _buildBoardHistoryCard(context),
                  const SizedBox(height: 12),
                  // v2.13：第 3 卡「课堂讲题回放」（HistoryStore 按天聚合）。
                  _buildLectureReplayCard(),
                  const SizedBox(height: 12),
                  // v2.13+ 老师走查 P0：推断器入口——人类遗传病页不在主导航
                  //（课标页 chip 深埋），课堂/备课 5+ 步不可达；老师工具页
                  // 给直达卡。
                  _buildInferenceEntryCard(),
                  const SizedBox(height: 12),
                  _buildScanCountCard(),
                  const SizedBox(height: 12),
                  _buildClassMistakePlaceholder(context),
                ],
              ),
      ),
    );
  }

  // ---- 卡片 1：板书 PDF / SVG 导出历史 ----

  Widget _buildBoardHistoryCard(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.draw_outlined, color: AppColors.teal, size: 20),
                const SizedBox(width: 8),
                Text(
                  '板书 PDF / SVG 导出历史',
                  style: AppText.label.copyWith(fontWeight: FontWeight.w700),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              // v2.13 R4 P1：PNG 也归档（老师高频路径），文案不再只提 SVG。
              '系谱页生成的板书（SVG / PNG）自动归档到 ~/.biology_app/board_history/，'
              '点「去系谱页生成」跳过去手动画一遍，导出的板书会在此显示。',
              style: AppText.caption.copyWith(color: AppColors.graphite),
            ),
            const SizedBox(height: 10),
            // 主入口按钮：跳到系谱页（v2.12 已有 SVG 导出能力）。
            // v2.12+ R1 P0 #2：走 widget.onOpenPedigree 回调，不直接
            // 引入 genetic_pedigree_page（避免 R1-C / R1-D 跨 worker
            // 编译阻塞 + 反向依赖）。
            FilledButton.icon(
              onPressed: widget.onOpenPedigree,
              icon: const Icon(Icons.arrow_forward, size: 16),
              label: const Text('去系谱页生成'),
            ),
            const SizedBox(height: 12),
            // 历史列表
            if (_boardHistory.isEmpty)
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.history, size: 32, color: AppColors.steel),
                  const SizedBox(height: 8),
                  Text('暂无历史', style: AppText.sectionTitle),
                  const SizedBox(height: 4),
                  Text(
                    '点上方「去系谱页生成」，生成的板书会自动存进这里。',
                    textAlign: TextAlign.center,
                    style: AppText.caption,
                  ),
                ],
              )
            else ...[
              ..._boardHistory.map((e) => _boardHistoryRow(e)),
              // v2.13 R4 P1：take(10) 保留但加「查看更多」——旧板书不再
              // 封顶不可达。全量展开后可收起。
              if (_allBoardHistory.length > 10)
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    key: const Key('board_history_toggle_more_btn'),
                    onPressed: () => setState(() {
                      _showAllBoards = !_showAllBoards;
                      _boardHistory = _showAllBoards
                          ? _allBoardHistory
                          : _allBoardHistory.take(10).toList();
                    }),
                    icon: Icon(
                      _showAllBoards ? Icons.expand_less : Icons.expand_more,
                      size: 16,
                    ),
                    label: Text(
                      _showAllBoards
                          ? '收起'
                          : '查看更多（共 ${_allBoardHistory.length} 条）',
                      style: AppText.caption,
                    ),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _boardHistoryRow(FileSystemEntity f) {
    final name = f.path.split(Platform.pathSeparator).last;
    // v2.13 R4 P1：SVG / PNG 图标区分（PNG 是位图，不支持「复制文本」
    // ——复制按钮只对 SVG 显示）。
    final isPng = f.path.toLowerCase().endsWith('.png');
    String timeStr;
    try {
      final t = f.statSync().modified;
      timeStr =
          '${t.year.toString().padLeft(4, '0')}-${t.month.toString().padLeft(2, '0')}-${t.day.toString().padLeft(2, '0')} '
          '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      timeStr = '—';
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(
            isPng ? Icons.image_outlined : Icons.description_outlined,
            size: 16,
            color: AppColors.steel,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppText.caption,
            ),
          ),
          Text(
            timeStr,
            style: AppText.caption.copyWith(color: AppColors.steel),
          ),
          // v2.12+ R1 final D P0 #3：板书历史从「只读博物馆」升级
          // 为「可重用库」——三件套：重新复制 / 文件管理器定位 / 永久删除。
          // IconButton 比 TextButton 省横向空间（行内 16dp 按钮密度）。
          // tooltip 写明动作 + 副作用，老师点前能预知。
          // v2.13 R4 P1：复制仅 SVG（PNG 二进制无法复制文本给富文本
          // 编辑器）；PNG 行走「文件管理器定位 / 永久删除」两件套。
          const SizedBox(width: 4),
          if (!isPng)
            // R6 老师走查 #5：去掉局部 32-36px 硬编码——课堂大屏模式下
            // 全局 IconButton 主题提到 48px 触控目标，局部 constraints
            // 会把它压回去（教鞭/触控笔点 32px 很别扭）。
            IconButton(
              key: const Key('board_history_copy_btn'),
              tooltip: '重新复制 SVG 到剪贴板',
              icon: const Icon(Icons.copy_all_outlined),
              onPressed: () => _copyBoardToClipboard(f),
            ),
          IconButton(
            key: const Key('board_history_reveal_btn'),
            tooltip: '在文件管理器中显示',
            icon: const Icon(Icons.folder_open_outlined),
            onPressed: () => _showBoardInExplorer(f),
          ),
          IconButton(
            key: const Key('board_history_delete_btn'),
            tooltip: '永久删除（不可恢复，去系谱页可重画）',
            // delete_forever icon 比 delete_outline 更明确「不可恢复」语义。
            // AppColors.steel 是 getter（非 const），所以 icon 不加 const。
            icon: Icon(Icons.delete_forever_outlined, color: AppColors.steel),
            onPressed: () => _deleteBoardFile(f),
          ),
        ],
      ),
    );
  }

  // ---- v2.13 卡片：课堂讲题回放（老师走查金点子，零架构） ----
  //
  // 数据源 HistoryStore（计算历史，上限 200 条）此前「已写未读」——
  // dashboard 完全不消费它。按 今天/昨天/更早 分组展示 label + 时刻，
  // 老师周一第 4 节能接着上周五的讲题序列续讲。

  Widget _buildLectureReplayCard() {
    // 新→旧取前 15 条（回放是「最近讲了什么」，考古走系谱/计算器页）；
    // R5：超过 15 条给「查看全部」展开，不滚掉昨天的讲题序列。
    final recent = (!_showAllHistory && _history.length > 15)
        ? _history.sublist(_history.length - 15).reversed.toList()
        : _history.reversed.toList();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    String groupOf(int epochMs) {
      final d = DateTime.fromMillisecondsSinceEpoch(epochMs);
      final day = DateTime(d.year, d.month, d.day);
      final diff = today.difference(day).inDays;
      if (diff <= 0) return '今天';
      if (diff == 1) return '昨天';
      // R5：跨年的「9月13日」歧义——非本年补年份。
      if (d.year != now.year) return '${d.year}年${d.month}月${d.day}日';
      return '${d.month}月${d.day}日';
    }

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.history_outlined, color: AppColors.teal, size: 20),
                const SizedBox(width: 8),
                Text(
                  '课堂讲题回放',
                  style: AppText.label.copyWith(fontWeight: FontWeight.w700),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              // R5 老师走查：原文案「计算器/系谱页每次计算自动记录」是
              // 过度承诺——v2.14 起七个 tab 全部落盘（补齐 4 个），文案
              // 写实 + 教 ▷  affordance（带 ▷ 的点按可复现：
              // 双基因/三对/单基因/伴性；方法对比/连锁/自由交配回看题干）。
              '遗传计算器七个 tab 与系谱页的计算都会自动记录——今天讲过'
              '哪些题、讲到哪，这里按时间倒序回放（共 ${_history.length} 次）；'
              '带 ▷ 的可点按复现（双基因/三对/单基因/伴性/方法对比/连锁互换'
              '；自由交配回看题干）。带「讲题稿」的还能让 AI 写一段讲稿，'
              '照稿投影给学生听。',
              style: AppText.caption.copyWith(color: AppColors.graphite),
            ),
            const SizedBox(height: 10),
            if (recent.isEmpty)
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.forum_outlined,
                      size: 32, color: AppColors.steel),
                  const SizedBox(height: 8),
                  Text('暂无讲题记录', style: AppText.sectionTitle),
                  const SizedBox(height: 4),
                  Text(
                    '去计算器或系谱页算几道题就出现在这里',
                    textAlign: TextAlign.center,
                    style: AppText.caption,
                  ),
                ],
              )
            else ...[
              for (var i = 0; i < recent.length; i++) ...[
                // 组头：与上一条不同组时插入。
                if (i == 0 ||
                    groupOf(recent[i].epochMs) !=
                        groupOf(recent[i - 1].epochMs))
                  Padding(
                    padding: const EdgeInsets.only(top: 8, bottom: 4),
                    child: Text(
                      groupOf(recent[i].epochMs),
                      style: AppText.caption.copyWith(
                        color: AppColors.teal,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: InkWell(
                    // v2.19.16（DeepSeek 找茬 🟡5）：触控兜底——原行高
                    // ≈18-22px（caption 12px×1.5 + ▷14px），白板/触屏
                    // 误触上下相邻行会跳到另一道题；ConstrainedBox 抬到
                    // 48px（课堂主题按钮同档）。
                    onTap: historyEntryLectureable(recent[i])
                        ? () => _replayHistory(recent[i])
                        : null,
                    borderRadius: BorderRadius.circular(6),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(minHeight: 48),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            // 时刻 HH:mm
                            '${DateTime.fromMillisecondsSinceEpoch(recent[i].epochMs).hour.toString().padLeft(2, '0')}:'
                            '${DateTime.fromMillisecondsSinceEpoch(recent[i].epochMs).minute.toString().padLeft(2, '0')}',
                            style: AppText.caption.copyWith(
                              color: AppColors.steel,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              recent[i].label,
                              style: AppText.caption.copyWith(
                                color: AppColors.ink,
                              ),
                            ),
                          ),
                          // v2.19.62：可复核条目多一枚「讲题稿」入口——
                          // 与 ▷ 同判据（historyEntryLectureable）。不可复核
                          // 的条目连这个位置都不渲染（不是点了才提示不行）。
                          if (historyEntryLectureable(recent[i]))
                            Icon(
                              Icons.play_circle_outline,
                              size: 14,
                              color: AppColors.teal,
                            ),
                          if (historyEntryLectureable(recent[i]))
                            _lectureNoteButton(recent[i]),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
              // R5：>15 条给展开/收起。
              if (_history.length > 15)
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: () =>
                        setState(() => _showAllHistory = !_showAllHistory),
                    icon: Icon(
                      _showAllHistory ? Icons.unfold_less : Icons.unfold_more,
                      size: 16,
                    ),
                    label: Text(
                      _showAllHistory ? '收起' : '查看全部 ${_history.length} 条',
                    ),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }

  /// 「讲题稿」入口：一条可复核历史 ⇒ 让 AI 写一段可直接投影的讲题稿。
  ///
  /// v2.19.62：「可复核」的判据已抽成顶层 `historyEntryLectureable`
  /// （单一口径，本入口与 ▷ 复现共用，调用点不再有第二份判据）。
  /// ⛔ 只在判据为真时渲染（见该函数注释里逐条列明的字段）。
  Widget _lectureNoteButton(HistoryEntry e) => Tooltip(
    message: 'AI 讲题稿',
    child: TextButton.icon(
      key: ValueKey('history_lecture_note_${e.epochMs}'),
      onPressed: () => _askAiForLectureNote(e),
      style: TextButton.styleFrom(
        foregroundColor: AppColors.teal,
        // 紧凑档：回放行本来就只 48px（触控兜底），按钮不许把行撑高。
        padding: const EdgeInsets.symmetric(horizontal: 6),
        minimumSize: const Size(0, 32),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        visualDensity: VisualDensity.compact,
      ),
      icon: Icon(Icons.menu_book_outlined, size: 15, color: AppColors.teal),
      label: Text(
        '讲题稿',
        style: AppText.caption.copyWith(
          color: AppColors.teal,
          fontWeight: FontWeight.w600,
        ),
      ),
    ),
  );

  /// 点「讲题稿」：把这条历史拼成讲题提示词发进 AI 助手面板。
  ///
  /// ⛔ 首轮不做（明确留白，不是漏做）：讲稿落盘成文件、批量生成整学期
  /// 讲稿、课堂模式自动投影讲稿——本轮只做「一条历史 → 一段提示词 →
  /// 助手面板」，学生/老师自己看讲稿。
  void _askAiForLectureNote(HistoryEntry e) {
    final prompt = historyLecturePrompt(e);
    if (prompt == null) return; // 防御：不可复核的条目本就不渲染入口
    // 当前屏（历史列表页）的截图对「讲这道题」零信息量，不随问题带上
    // ——与错题本追问同款口径（pendingCanvasImage 置空）。
    AiChatController.instance.pendingCanvasImage = null;
    AiChatController.instance.queueSend(prompt);
    showAiAssistant(context);
  }

  /// 点按回放条目 → 切主导航到计算器并回填亲本即算（ModuleFillBus）。
  ///
  /// R5 老师走查 P0：本卡长在 push 出来的 _TeacherPage 上——
  /// ModuleFillBus.fill 只切底层 IndexedStack 索引，不 pop 本页；
  /// 不主动 pop 的话计算器在身后切好、参数填好，老师看着不动的
  /// 屏幕以为坏了。fill 成功后仿 onOpenPedigree 先让本页让位。
  void _replayHistory(HistoryEntry e) {
    try {
      final j = jsonDecode(e.detail);
      if (j is! Map || j['m'] == null) return;
      final ok = ModuleFillBus.fill(j['m'].toString(), {
        'p1': j['p1']?.toString() ?? '',
        'p2': j['p2']?.toString() ?? '',
      });
      if (!ok) {
        if (mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(const SnackBar(content: Text('该条目暂不支持复现')));
        }
        return;
      }
      if (mounted) Navigator.of(context).pop();
    } catch (_) {
      /* 非 JSON detail = 系谱/单基因条目，无复现 */
    }
  }

  // ---- v2.13+ 卡片：系谱推断直达入口（老师走查 P0：原入口 5+ 步） ----

  Widget _buildInferenceEntryCard() {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.account_tree_outlined,
                  color: AppColors.teal,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Text(
                  '系谱推断',
                  style: AppText.label.copyWith(fontWeight: FontWeight.w700),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              '给家族遗传病系谱图，判遗传方式（常显/常隐/伴X/伴Y）——'
              '4 个经典金标准一键载入，依据条文逐步呈现。',
              style: AppText.caption.copyWith(color: AppColors.graphite),
            ),
            const SizedBox(height: 10),
            FilledButton.icon(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => GeneticDiseasePage(focusInference: true),
                ),
              ),
              icon: const Icon(Icons.arrow_forward, size: 16),
              label: const Text('打开系谱推断'),
            ),
          ],
        ),
      ),
    );
  }

  // ---- 卡片 2：拍题识别次数 ----

  Widget _buildScanCountCard() {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.add_photo_alternate_outlined,
                  color: AppColors.teal,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Text(
                  '拍题识别统计',
                  style: AppText.label.copyWith(fontWeight: FontWeight.w700),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: _statBox(
                    label: '内置题库',
                    value: _scanBankCount,
                    hint: 'ScanBankStore\n学生拍题识别后自动入库',
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _statBox(
                    label: '错题本',
                    value: _mistakeCount,
                    // R5 老师走查：公用讲台机上这个数字混着所有登录过的
                    // 学生，没有班级统计含义——标注「本机」防止误读。
                    hint: 'MistakeBook\n本机学生错题（含「加入错题本」）',
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _statBox({
    required String label,
    required int value,
    required String hint,
  }) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: AppColors.tealWash,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: AppText.caption.copyWith(color: AppColors.steel)),
          const SizedBox(height: 2),
          Text(
            '$value',
            style: AppText.pageTitle.copyWith(color: AppColors.teal),
          ),
          const SizedBox(height: 2),
          Text(
            hint,
            // R6 老师走查 #9：原 fontSize 11 降到 caption 以下，课堂
            // 大屏 ×1.3 后投到后排看不清——回到 caption 基线（大屏由
            // textScaler 放大，不再二次压小）。
            style: AppText.caption.copyWith(
              color: AppColors.steel,
              height: 1.3,
            ),
          ),
        ],
      ),
    );
  }

  // ---- 卡片 3：班级共性错（v2.14 R5 实做：本机脱敏聚合视图）----
  //
  // 老师走查 R5 #10/#11：「今天课上集体讲哪道错题」对老师在 app 内原无解
  //（AI 总览活在学生私有错题本里，老师进不去）。产品红线不做家长/班级
  // 数据同步，但本机聚合是诚实且有用的：错因分布 + 高频考点 + 代表题
  // 题干——帮老师决定「集体讲哪一类」。不含任何个人复习状态（脱敏）。

  Widget _buildClassMistakePlaceholder(BuildContext context) {
    // 内存单例直读（dashboard _load 已冷启动过一次；聚合是 build 期纯函数）。
    // R7 老师走查 #7：讲台机混着历届学生累积错题——加「本周/全部」
    // 时间窗，老师决定「今天集体讲哪类」不被历史数据带偏。
    var entries = MistakeBook.instance.entries;
    if (_classMistakeWeekly) {
      final cutoff = DateTime.now().subtract(const Duration(days: 7));
      entries = entries.where((e) => !e.createdAt.isBefore(cutoff)).toList();
    }
    // 空态按筛选口径区分文案。
    final scopeEmpty = _classMistakeWeekly && entries.isEmpty;
    // 错因分布（固定枚举序，零隐藏）。
    final byType = <MistakeErrorType, int>{};
    for (final e in entries) {
      byType[e.errorType] = (byType[e.errorType] ?? 0) + 1;
    }
    // 高频考点 top3。
    final byArea = <String, int>{};
    for (final e in entries) {
      final k = e.subjectArea.isEmpty ? '未标注考点' : e.subjectArea;
      byArea[k] = (byArea[k] ?? 0) + 1;
    }
    final topAreas = byArea.entries.toList()..sort((a, b) => b.value - a.value);
    // 代表题：占比最高错因里最新的一道（createdAt 最大在前——entries
    // 本身倒序，取第一个命中即可）。
    MistakeErrorType? topType;
    var topCount = 0;
    byType.forEach((k, v) {
      if (v > topCount) {
        topType = k;
        topCount = v;
      }
    });
    final rep = topType == null
        ? null
        : entries.cast<MistakeEntry?>().firstWhere(
            (e) => e!.errorType == topType,
            orElse: () => null,
          );

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.groups_outlined, color: AppColors.teal, size: 20),
                const SizedBox(width: 8),
                Text(
                  '班级共性错',
                  style: AppText.label.copyWith(
                    fontWeight: FontWeight.w700,
                    color: AppColors.teal,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              '本机错题的脱敏聚合——错因分布 / 高频考点 / 代表题，'
              '帮你在课上决定「集体讲哪一类」。不含个人复习状态。',
              style: AppText.caption.copyWith(color: AppColors.graphite),
            ),
            const SizedBox(height: 8),
            // R7 老师走查 #7：时间窗筛选（默认本周，讲课决策不被
            // 历届旧数据带偏）。
            Wrap(
              spacing: 8,
              children: [
                ChoiceChip(
                  label: const Text('本周'),
                  selected: _classMistakeWeekly,
                  onSelected: (_) => setState(() => _classMistakeWeekly = true),
                ),
                ChoiceChip(
                  label: const Text('全部'),
                  selected: !_classMistakeWeekly,
                  onSelected: (_) =>
                      setState(() => _classMistakeWeekly = false),
                ),
              ],
            ),
            const SizedBox(height: 10),
            if (entries.isEmpty)
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.error_outline,
                      size: 32, color: AppColors.steel),
                  const SizedBox(height: 8),
                  Text(
                    scopeEmpty ? '本周还没有新错题' : '暂无错题数据',
                    style: AppText.sectionTitle,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    scopeEmpty
                        ? '切「全部」看历届累积。'
                        : '学生开始收录错题后，这里自动聚合同类错误。',
                    textAlign: TextAlign.center,
                    style: AppText.caption,
                  ),
                ],
              )
            else ...[
              for (final t in MistakeErrorType.values)
                if ((byType[t] ?? 0) > 0)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 3),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            t.displayName,
                            style: AppText.caption.copyWith(
                              color: AppColors.ink,
                            ),
                          ),
                        ),
                        Text(
                          '${byType[t]} 道',
                          style: AppText.caption.copyWith(
                            color: AppColors.graphite,
                          ),
                        ),
                      ],
                    ),
                  ),
              if (topAreas.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  '高频考点：${topAreas.take(3).map((a) => '${a.key} ×${a.value}').join('　')}',
                  style: AppText.caption.copyWith(color: AppColors.teal),
                ),
              ],
              if (rep != null) ...[
                const SizedBox(height: 4),
                // R7 老师走查 #6：代表题原是死胡同（42 字截断、无入口；
                // 老师角色又进不了错题本）——整行可点，弹完整题干
                // + 答案的只读对话框，课堂讲完即关。
                InkWell(
                  borderRadius: BorderRadius.circular(6),
                  onTap: () => showDialog<void>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: Text('「${topType!.displayName}」典型题'),
                      content: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SelectableText(rep.stem, style: AppText.body),
                          const SizedBox(height: 10),
                          Text(
                            '正确答案：${rep.correctAnswer.isEmpty ? "（待补充）" : rep.correctAnswer}',
                            style: AppText.caption.copyWith(
                              color: AppColors.teal,
                            ),
                          ),
                          if (rep.aiSummary?.isNotEmpty == true) ...[
                            const SizedBox(height: 6),
                            Text(
                              '错因：${rep.aiSummary}',
                              style: AppText.caption.copyWith(
                                color: AppColors.graphite,
                              ),
                            ),
                          ],
                        ],
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.of(ctx).pop(),
                          child: const Text('关闭'),
                        ),
                      ],
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            '「${topType!.displayName}」典型题：${rep.stem.length > 42 ? '${rep.stem.substring(0, 42)}…' : rep.stem}',
                            style: AppText.caption.copyWith(
                              color: AppColors.steel,
                            ),
                          ),
                        ),
                        Icon(
                          Icons.open_in_full,
                          size: 13,
                          color: AppColors.teal,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}
