// module_link.dart —— v2.21.0 知识图谱节点 → 主导航目的地的纯导览链接
//
// ## 为什么有这个文件
//
// 改前 knowledge_graph_page.dart 自己维护 `_nodeTools`：一张
// `{节点 id: (导航索引, 功能名)}` 的私有表。索引 1/2/5 是**裸数字**，
// 而导航索引的事实源是 lib/ui/app_navigation.dart 的顺序（顺序即索引）。
// 一旦主导航重排（v2.19.60 就重排过一次），这张表会静默指错页——
// 编号没有名字，编译器帮不上忙。
//
// 本文件把「节点 → 功能页」改写成「节点 → 稳定 destinationId + 展示
// label」：索引不再手写，一律由 [appNavDestinations] 顺序派生；
// destinationId 改名不动 id（见 app_navigation.dart 纪律）。
//
// ## 纪律
//
//   · **导览与填题分离**：destinationId 决定去哪一页；可选 moduleId /
//     linkParams 只描述页内页签（如 cross_tab + tab=3），不携带 p1/p2、
//     不覆盖学生原题。解析本身不读写 ModuleFillBus，页面点击时才消费；
//     深链未注册时仍由 `onOpenTool(int)` 回退到主导航。
//   · **未知即 null**：未知节点 id、或 destinationId 在
//     [appNavDestinations] 里找不到 ⇒ [knowledgeGraphLinkForNode] 返
//     null，页面据此不渲染按钮（零像素诚实，不给死按钮）。
//   · **label 与 destination 名分开存**：按钮文案是「给学生看的功能名」
//     （「分子遗传」「遗传图谱」），与导航短名/全名宽度预算不同，不能
//     互相顶替；destinationId 才是身份。
import 'package:flutter/foundation.dart';

import 'app_navigation.dart';

/// 一个「知识点 → 功能页」的纯导览链接。
@immutable
class AppModuleLink {
  const AppModuleLink({
    required this.destinationId,
    required this.label,
    this.moduleId,
    this.linkParams = const <String, String>{},
  });

  /// 目标页身份（app_navigation.dart 的稳定 id，例如 'cross'）。
  final String destinationId;

  /// 按钮展示名（「打开对应功能：<label>」里的 <label>）。
  final String label;

  /// 可选：目标页内的只读导览深链（例如 cross_tab + tab=3）。
  /// 只切页签，不填参、不覆盖学生正在做的题；未注册时回退 navIndex。
  final String? moduleId;

  /// 深链参数；与 moduleId 一起由页面交给 ModuleFillBus。
  final Map<String, String> linkParams;

  /// 目的地条目；未知 destinationId ⇒ null。
  AppNavDestination? get destination => appNavById(destinationId);

  /// 导航索引：**由 [appNavDestinations] 顺序派生**（不手写数字）。
  /// 未知 destinationId ⇒ null（调用方据此隐藏入口）。
  int? get navIndex {
    for (var i = 0; i < appNavDestinations.length; i++) {
      if (appNavDestinations[i].id == destinationId) return i;
    }
    return null;
  }

  /// 目的地存在 ⇒ 可跳转。
  bool get isNavigable => navIndex != null;

  /// 最终展示名：label 为空时回退目的地名（再回退 id），避免空按钮。
  String get displayLabel {
    if (label.trim().isNotEmpty) return label;
    return destination?.name ?? destinationId;
  }

  @override
  bool operator ==(Object other) =>
      other is AppModuleLink &&
      other.destinationId == destinationId &&
      other.label == label &&
      other.moduleId == moduleId &&
      mapEquals(other.linkParams, linkParams);

  @override
  int get hashCode {
    // mapEquals 不看插入顺序，哈希也必须按键排序，保证相等对象同哈希。
    final keys = linkParams.keys.toList()..sort();
    return Object.hash(
      destinationId,
      label,
      moduleId,
      Object.hashAll(keys.map((key) => Object.hash(key, linkParams[key]))),
    );
  }

  @override
  String toString() => 'AppModuleLink($destinationId → $label)';
}

/// 图谱 19 个节点 → 功能页（v2.2 `_nodeTools` 的原样迁移，只换了目标形式）。
///
/// 绝大多数遗传学核心概念落到遗传计算器（9331 及变式 / 测交 / 伴性 /
/// 致死），少数落到遗传图谱（系谱）/ 分子（DNA 本质）：
///   · dna-genes-alleles            → molecular（分子遗传：碱基互补/两链互推）
///   · genotype-phenotype / pedigree-analysis → pedigree（遗传图谱：系谱推断）
///   · 其余 16 个                    → cross（9331 及变式/测交/伴性/致死）
const Map<String, AppModuleLink> _knowledgeGraphLinks = <String, AppModuleLink>{
  'dna-genes-alleles': AppModuleLink(
    destinationId: 'molecular',
    label: '分子遗传',
    moduleId: 'molecular_tab',
    linkParams: {'tab': '0'},
  ),
  'genotype-phenotype': AppModuleLink(destinationId: 'pedigree', label: '遗传图谱'),
  'dominant-recessive': AppModuleLink(
    destinationId: 'cross', label: '遗传计算器', moduleId: 'cross_tab', linkParams: {'tab': '2'}),
  'law-of-segregation': AppModuleLink(
    destinationId: 'cross', label: '遗传计算器', moduleId: 'cross_tab', linkParams: {'tab': '2'}),
  'law-of-independent-assortment': AppModuleLink(
    destinationId: 'cross', label: '遗传计算器', moduleId: 'cross_tab', linkParams: {'tab': '0'}),
  'punnett-square': AppModuleLink(
    destinationId: 'cross', label: '遗传计算器', moduleId: 'cross_tab', linkParams: {'tab': '0'}),
  'gamete-formation': AppModuleLink(
    destinationId: 'cross', label: '遗传计算器', moduleId: 'cross_tab', linkParams: {'tab': '2'}),
  'testcross': AppModuleLink(
    destinationId: 'cross', label: '遗传计算器', moduleId: 'cross_tab', linkParams: {'tab': '2'}),
  'backcross': AppModuleLink(
    destinationId: 'cross', label: '遗传计算器', moduleId: 'cross_tab', linkParams: {'tab': '2'}),
  '9331': AppModuleLink(
    destinationId: 'cross', label: '遗传计算器', moduleId: 'cross_tab', linkParams: {'tab': '0'}),
  '9331-variant-97': AppModuleLink(
    destinationId: 'cross', label: '遗传计算器', moduleId: 'cross_tab', linkParams: {'tab': '0'}),
  '9331-variant-934': AppModuleLink(
    destinationId: 'cross', label: '遗传计算器', moduleId: 'cross_tab', linkParams: {'tab': '0'}),
  '9331-variant-151': AppModuleLink(
    destinationId: 'cross', label: '遗传计算器', moduleId: 'cross_tab', linkParams: {'tab': '0'}),
  '9331-variant-14641': AppModuleLink(
    destinationId: 'cross', label: '遗传计算器', moduleId: 'cross_tab', linkParams: {'tab': '0'}),
  'lethal-gene': AppModuleLink(
    destinationId: 'cross', label: '遗传计算器', moduleId: 'cross_tab', linkParams: {'tab': '2'}),
  'incomplete-dominance': AppModuleLink(
    destinationId: 'cross', label: '遗传计算器', moduleId: 'cross_tab', linkParams: {'tab': '2'}),
  'codominance': AppModuleLink(
    destinationId: 'cross', label: '遗传计算器', moduleId: 'cross_tab', linkParams: {'tab': '2'}),
  'sex-linked': AppModuleLink(
    destinationId: 'cross', label: '遗传计算器', moduleId: 'cross_tab', linkParams: {'tab': '3'}),
  'pedigree-analysis': AppModuleLink(destinationId: 'pedigree', label: '遗传图谱'),
};

/// 节点 id → 功能页链接。
///
/// 未知节点 id（含空串）或目的地不在 [appNavDestinations] 内 ⇒ null。
AppModuleLink? knowledgeGraphLinkForNode(String nodeId) {
  final link = _knowledgeGraphLinks[nodeId];
  if (link == null || !link.isNavigable) return null;
  return link;
}

/// 有功能映射的节点 id 集合（从表派生，不另维护平行清单）。
Set<String> get knowledgeGraphLinkedNodeIds =>
    _knowledgeGraphLinks.keys.toSet();
