// app_navigation.dart —— 主导航目录（唯一事实源，v2.20.0 导航治理切片）
//
// ## 为什么有这个文件
//
// 改前 HomeShell 把同一份「13 页主导航」拆成五张并行常量表
// （_pageNames / _navLabels / _navDescs / _navIcons / _navIconsSelected），
// 首页 DashboardPage 又自己维护一套「卡片名 + navIndex」——三处并行，
// 改一项必漏两项（v2.19.60 的「变异/遗传病提前、设置/关于后置」就是靠
// 人工逐表对齐，且首页漏掉了变异/遗传病两张卡）。
//
// 本文件把「稳定 id / 全名 / 短名 / 描述 / 普通图标 / 选中图标」收敛到
// 一个 const 目录：HomeShell 的 Rail、移动底导、「全部」面板、数字键、
// 回程横幅，以及首页功能卡，全部按本表读——顺序即导航索引。
//
// ## 纪律
//
//   · **顺序即页面索引**：下标 == HomeShell 的页面索引，也是数字键
//     （digit1..digit0 → 0..9）、guide_controller.dart 的 pageIndex、
//     shortcut_cheatsheet.dart 的 rowsByPage 的公共参照。增删/重排必须
//     先想清楚这些消费者。
//   · **纯 UI 目录**：不 import 任何页面、不依赖状态、不引入路由库。
//     页面构建仍由 HomeShell 的 switch(id) 决定（不引 go_router）。
//   · **id 稳定**：id 是页面身份（不是名字），改名不动 id；名字/短名/
//     描述/图标可以随文案迭代自由改。
//
// ## 字段用途
//
//   id         页面身份（HomeShell 构建分支 + 选中态判断）
//   name       全名（「全部」面板 / 回程横幅 / AppState 页名）
//   shortName  Rail 与移动底导的短标签（单行、不折行）
//   desc       一句用途（「全部」面板副标题）
//   icon       未选中图标；selectedIcon 选中图标
//   cardTitle  首页功能卡标题（null ⇒ 回退 name）
//   cardDesc   首页功能卡描述（null ⇒ 回退 desc）
//   visibleInNav 是否在主导航入口层显示（默认 true；v2.22.0 起套路卡为
//              false ⇒ 只减入口，不删条目/索引/能力）
//
// 说明：cardTitle/cardDesc 存在不是为了「两套文案」，而是因为首页卡片
// 与导航标签的**宽度预算不同**（导航栏 10px 单行，卡片 2 行 132px）——
// 两份文案放在同一行条目里，改一处看得见另一处，不再跨文件漂移。

import 'package:flutter/material.dart';

/// 一个主导航目的地（顺序即页面索引，见文件头「纪律」）。
@immutable
class AppNavDestination {
  const AppNavDestination({
    required this.id,
    required this.name,
    required this.shortName,
    required this.desc,
    required this.icon,
    required this.selectedIcon,
    this.hasInlineAi = false,
    this.visibleInNav = true,
    this.cardTitle,
    this.cardDesc,
  });

  /// 稳定 id（页面身份；改名不动 id）。
  final String id;

  /// 全名（导航面板 / 回程横幅 / AppState 页名）。
  final String name;

  /// 短名（Rail / 移动底导标签，单行不折行）。
  final String shortName;

  /// 一句用途说明（「全部」面板副标题）。
  final String desc;

  /// 未选中图标。
  final IconData icon;

  /// 选中图标。
  final IconData selectedIcon;

  /// 页内是否另有带本页上下文的 AI 讲解动作。
  ///
  /// 仅作入口元数据；v2.22.0 起所有页面始终保留右下角全局「问 AI」，
  /// 本字段绝不能再用于隐藏全局 FAB。页内动作可预填本页问题，全局
  /// 入口则保持跨页面一致的使用习惯。
  final bool hasInlineAi;

  /// 是否在**主导航入口层**显示（Rail / 移动底导 /「全部功能」面板 /
  /// 首页 Dashboard）。
  ///
  /// v2.22.0「只减入口、不删能力」：默认 true；个别页面（如大题套路卡
  /// id='cards'）改为 false ⇒ 它从主导航与首页撤下，但**页面本身、目录
  /// 条目、pageIndex、深链、快捷键、ModuleFillBus 跳转全部保留**——
  /// 套路卡改由「9331 结果页按 K」与「错题本按需打开」触达。
  ///
  /// ⚠ 本字段**只影响显示层**：目录顺序（== pageIndex）不变，不得据此
  ///   删除或重排条目。可见索引 ↔ pageIndex 的映射见
  ///   [appNavVisiblePageIndexes] / [appNavVisibleIndexOf]。
  final bool visibleInNav;

  /// 首页功能卡标题（null ⇒ 用 [name]）。
  final String? cardTitle;

  /// 首页功能卡描述（null ⇒ 用 [desc]）。
  final String? cardDesc;

  /// 首页卡片最终标题。
  String get dashboardTitle => cardTitle ?? name;

  /// 首页卡片最终描述。
  String get dashboardDesc => cardDesc ?? desc;
}

/// 主导航 13 页（顺序 == 页面索引）。
///
/// v2.19.60 顺序：首页 → 8 个计算/资料页 → 变异 / 人类遗传病 →
/// 设置 / 关于（用户要求设置与关于固定末位）。
const List<AppNavDestination> appNavDestinations = <AppNavDestination>[
  AppNavDestination(
    id: 'home',
    name: '首页',
    shortName: '首页',
    desc: '功能入口总览与使用引导',
    icon: Icons.home_outlined,
    selectedIcon: Icons.home,
  ),
  AppNavDestination(
    id: 'pedigree',
    name: '遗传图谱计算',
    shortName: '遗传图谱',
    desc: '系谱推断 · 亲子代风险概率',
    icon: Icons.family_restroom_outlined,
    selectedIcon: Icons.family_restroom,
    hasInlineAi: true, // 命令栏「日志 / 历史 / 杂交计算 / 问 AI」
  ),
  AppNavDestination(
    id: 'cross',
    name: '遗传计算器',
    shortName: '9331',
    desc: '9331 及变式 / 测交 / 致死等 7 个 tab',
    icon: Icons.calculate_outlined,
    selectedIcon: Icons.calculate,
    hasInlineAi: true, // AppBar「问 AI」
    // 卡片描述保持 meter 更友好的「6 类」措辞（卡片宽 2 行，导航栏 1 行）。
    cardDesc: '9331 及变式 / 测交 / 致死等 6 类',
  ),
  AppNavDestination(
    id: 'graph',
    name: '知识图谱',
    shortName: '图谱',
    desc: '遗传概念关系全景浏览',
    icon: Icons.hub_outlined,
    selectedIcon: Icons.hub,
    hasInlineAi: true, // AppBar「问 AI」
  ),
  AppNavDestination(
    id: 'curriculum',
    name: '课标',
    shortName: '课标',
    desc: '22 条课标内容要求对照',
    icon: Icons.menu_book_outlined,
    selectedIcon: Icons.menu_book,
    hasInlineAi: true, // AppBar「问 AI」（真窗发现：与全局 FAB 撞车）
    cardTitle: '课标体系',
  ),
  AppNavDestination(
    id: 'molecular',
    name: '分子',
    shortName: '分子',
    desc: '碱基互补 / 两链互推 / DNA 标记',
    icon: Icons.science_outlined,
    selectedIcon: Icons.science,
    hasInlineAi: true, // AppBar「问 AI」
    cardTitle: '分子遗传',
  ),
  AppNavDestination(
    id: 'evolution',
    name: '进化',
    shortName: '进化',
    desc: 'Hardy-Weinberg 与选择逐代模拟',
    icon: Icons.trending_up,
    selectedIcon: Icons.trending_up,
    hasInlineAi: true, // AppBar「问 AI」
    cardTitle: '进化·基因频率',
  ),
  AppNavDestination(
    id: 'ploidy',
    name: '染色体倍性',
    shortName: '倍性',
    desc: '组数判断 / 倍性判定 / 单倍体育种',
    icon: Icons.bubble_chart_outlined,
    selectedIcon: Icons.bubble_chart,
    hasInlineAi: true, // AppBar「问 AI」
  ),
  AppNavDestination(
    id: 'cards',
    name: '大题套路卡',
    shortName: '套路卡',
    desc: '遗传大题答题套路 · 14 张速背卡',
    icon: Icons.style_outlined,
    selectedIcon: Icons.style,
    hasInlineAi: true, // AppBar「问 AI」
    cardDesc: '识别信号 → 套路步骤 → 一句话背下来',
    // v2.22.0：从主导航 / 首页撤下独立入口（内容融入 9331 结果页的 K
    // 快捷键与错题本的按需打开）。**条目本身保留**——pageIndex 8、
    // ModuleFillBus / 深链 / Alt+L 快捷键 / 页面保活全部照旧。
    visibleInNav: false,
  ),
  AppNavDestination(
    id: 'variation',
    name: '变异',
    shortName: '变异',
    desc: '基因突变 / 染色体组数 / 结构变异 / 育种',
    icon: Icons.change_circle_outlined,
    selectedIcon: Icons.change_circle,
    hasInlineAi: true, // AppBar「问 AI」
  ),
  AppNavDestination(
    id: 'disease',
    name: '人类遗传病',
    shortName: '遗传病',
    desc: '遗传咨询 / 系谱推断 / 分类与预防',
    icon: Icons.healing_outlined,
    selectedIcon: Icons.healing,
    hasInlineAi: true, // AppBar「问 AI」
  ),
  AppNavDestination(
    id: 'settings',
    name: '设置',
    shortName: '设置',
    desc: '主题模式与 AI 接口通道',
    icon: Icons.settings_outlined,
    selectedIcon: Icons.settings,
  ),
  AppNavDestination(
    id: 'about',
    name: '关于',
    shortName: '关于',
    desc: '版本信息与使用说明',
    icon: Icons.school_outlined,
    selectedIcon: Icons.school,
  ),
];

/// 全名表（顺序 == 页面索引）。
List<String> get appNavNames => <String>[
  for (final d in appNavDestinations) d.name,
];

/// 短名表（Rail / 底导标签顺序）。
List<String> get appNavShortNames => <String>[
  for (final d in appNavDestinations) d.shortName,
];

/// 按稳定 id 取目的地；未知 id 返回 null。
AppNavDestination? appNavById(String id) {
  for (final d in appNavDestinations) {
    if (d.id == id) return d;
  }
  return null;
}

// ── v2.22.0 可见索引 ↔ pageIndex 映射 ─────────────────────────────
//
// 「只减入口、不删能力」的两套下标空间：
//   · **pageIndex**：目录顺序（== 页面索引 / 数字键 / guide pageIndex /
//     ModuleFillBus / 深链目标）。**永不因可见性变化而改变。**
//   · **可见索引**：主导航条（Rail / 底导 /「全部」面板）里那一排的
//     下标 —— 隐藏页不在其中 ⇒ 与 pageIndex 存在错位。
//
// 调用方纪律：
//   · 显示层遍历用 [appNavVisiblePageIndexes]（拿 pageIndex 去取条目）；
//   · 显示层回调（onDestinationSelected）把**可见索引**换回 pageIndex；
//   · 选中态用 [appNavVisibleIndexOf]（隐藏页 ⇒ -1 ⇒ 不高亮任何项，
//     绝不越界、不错位高亮）。

/// 可见目的地（过滤 [AppNavDestination.visibleInNav] 为 false 的条目）。
///
/// ⚠ 本表顺序 = **可见索引**顺序，不是 pageIndex 顺序。
final List<AppNavDestination> appNavVisibleDestinations = <AppNavDestination>[
  for (final d in appNavDestinations)
    if (d.visibleInNav) d,
];

/// [appNavVisibleDestinations] 每项对应的 pageIndex（与 appNavDestinations
/// 同一索引空间）。
final List<int> appNavVisiblePageIndexes = <int>[
  for (var i = 0; i < appNavDestinations.length; i++)
    if (appNavDestinations[i].visibleInNav) i,
];

/// pageIndex → 可见索引；该页不在主导航条上（隐藏页）⇒ -1。
int appNavVisibleIndexOf(int pageIndex) =>
    appNavVisiblePageIndexes.indexOf(pageIndex);
