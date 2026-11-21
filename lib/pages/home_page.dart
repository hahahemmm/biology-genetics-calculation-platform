// home_page.dart —— 关于页（v2.19.28 UI 统一：左分组导航 + 右内容工作台）
//
// v2.19.28：废弃「居中窄条 + StepCard 堆叠」的 PPT 式卡片布局（用户裁定
// 全部页面统一为「左侧工作区 + 右内容」工作台形态），改 SideNavWorkbench：
// 左栏分组导航（软件 / 技术），右区平铺选中分区内容，
// 与计算页 ToolWorkbench 同款视觉语言。identical 短路纪律：骨架每 build
// 新建实例。

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_version.dart';
import '../engine/syllabus_loader.dart';
import '../theme.dart';
import 'widgets/side_nav_workbench.dart';

/// 关于页：软件简介、功能清单、考纲覆盖度与数据来源说明。
class HomePage extends StatefulWidget {
  const HomePage({super.key, this.navCollapsed = false, this.onNavPressed});

  /// v3.3 侧栏折叠联动（HomeShell 注入）；独立构造时不渲染 ☰。
  final bool navCollapsed;
  final VoidCallback? onNavPressed;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  /// v2.19.28 UI 统一：左导航当前选中分区 id（SideNavWorkbench）。
  String _selId = 'overview';

  /// 左栏导航分组（纯数据，const 安全）。
  static const _groupSoftware = SideNavGroup(
    label: '软件',
    entries: [
      SideNavEntry(
          id: 'overview', label: '本软件概览', icon: Icons.info_outline),
      SideNavEntry(id: 'features', label: '核心功能', icon: Icons.apps_outlined),
      SideNavEntry(
          id: 'coverage', label: '考纲覆盖', icon: Icons.fact_check_outlined),
    ],
  );

  static const _groupTech = SideNavGroup(
    label: '技术',
    entries: [
      SideNavEntry(
          id: 'arch', label: '技术架构', icon: Icons.account_tree_outlined),
      SideNavEntry(id: 'sources', label: '数据来源', icon: Icons.storage_outlined),
    ],
  );

  static const List<SideNavGroup> _navGroups = [_groupSoftware, _groupTech];

  /// v2.19.29（M3.1 老师 P2-5）：future 提成字段——build 里新建
  /// future 每次切分区重跑（先闪 3 条骨架占位 + 一次多余 IO）。
  late final Future<SyllabusCoverage> _syllabusFuture = _loadSyllabus();

  Future<SyllabusCoverage> _loadSyllabus() async {
    try {
      final raw =
          await rootBundle.loadString('data/syllabus_gaokao.json');
      return parseSyllabusCoverage(raw);
    } on FlutterError {
      return const SyllabusCoverage(name: '', items: [], coveredBy: {});
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: appNavButton(widget.onNavPressed),
        title: const Text('关于'),
      ),
      body: SideNavWorkbench(
        groups: _navGroups,
        selectedId: _selId,
        onSelect: (id) => setState(() => _selId = id),
        // v2.20.0（M3.1 评审）：railTitle / railIcon 已无渲染用途，参数删除
        // ——宽屏组名改由 SideNavWorkbench 从 groups[].label 直接上条。
        // v2.19.29（M3.1 老师 D3）：信息页右区宽统一 980（原 900，
        // 与设置 980 不一致，翻页内容栏宽度跳）。
        bodyMaxWidth: 980,
        body: (context) {
          switch (_selId) {
            case 'features':
              return _panelFeatures(context);
            case 'coverage':
              return _panelCoverage(context);
            case 'arch':
              return _panelArch(context);
            case 'sources':
              return _panelSources(context);
            case 'overview':
            default:
              return _panelOverview(context);
          }
        },
      ),
    );
  }

  // ─── 右区分区面板（无卡片壳平铺） ───

  /// 本软件概览：头部 + AI 助手说明 + 数据来源。
  Widget _panelOverview(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.biotech_outlined, size: 44, color: AppColors.teal),
        const SizedBox(height: 14),
        Text('生物遗传计算平台', style: AppText.pageTitle),
        const SizedBox(height: 6),
        Text(
          '把遗传计算的每一步摊开来给你看——错在哪一步，一眼可见。',
          style: AppText.body.copyWith(color: AppColors.graphite),
        ),
        const SizedBox(height: 8),
        // v2.19.67 P2 #7：版本号单源——改引 lib/app_version.dart 常量，
        // 升版只改那一处（原此处硬编码字面量，易与其它展示位失配）。
        Text(appVersionLabel, style: AppText.caption),
        const SizedBox(height: 28),
        Text('AI 遗传助手', style: AppText.sectionTitle),
        const SizedBox(height: 8),
        Text(
          '工具页点顶部「问 AI」，首页/设置/关于点右下角即可唤起助手。'
          '它会自动读取你当前所在的页面、'
          '已输入的基因型和刚算出的结果，不用你复述。'
          '默认接入 DeepSeek（deepseek-flash 多模态，拍题/截图一键发图），'
          'MiniMax 通道保留，可在「设置」中切换。',
          style: AppText.body,
        ),
        const SizedBox(height: 28),
        Text('数据来源', style: AppText.sectionTitle),
        const SizedBox(height: 8),
        Text(
          '考纲条目以《普通高中生物学课程标准（2017年版2020年修订）》官方编号'
          '为骨架，经假期教学可信资料库（课程标准覆盖矩阵、高考考纲整理）核对；'
          '考点数据逐条标注来源，全部见 data/ 目录。',
          style: AppText.body,
        ),
      ],
    );
  }

  /// 核心功能清单。
  Widget _panelFeatures(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('核心功能', style: AppText.sectionTitle),
        const SizedBox(height: 16),
        for (final f in _features) _featureRow(f.$1, f.$2),
      ],
    );
  }

  /// 考纲覆盖度。
  Widget _panelCoverage(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('考纲覆盖', style: AppText.sectionTitle),
        const SizedBox(height: 8),
        Text(
          '以《课程标准（2017年版2020年修订）》官方条目编号为骨架，'
          '对照本软件功能逐条自评（覆盖=功能可支撑该条目的练习与推导，'
          '不构成教研意义上的完整覆盖）：',
          style: AppText.caption,
        ),
        const SizedBox(height: 12),
        FutureBuilder<SyllabusCoverage>(
          future: _syllabusFuture,
          builder: (context, snap) {
            if (snap.connectionState != ConnectionState.done) {
              // 静态骨架，不做无限动画
              return Column(
                children: [
                  for (var i = 0; i < 3; i++)
                    Container(
                      height: 44,
                      margin: const EdgeInsets.only(bottom: 8),
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(10),
                        border:
                            Border.all(color: AppColors.border),
                      ),
                    ),
                ],
              );
            }
            final cov = snap.data ??
                const SyllabusCoverage(
                    name: '', items: [], coveredBy: {});
            if (cov.items.isEmpty) {
              return Text('考纲数据未加载（请确认 asset 已打包）。',
                  style: AppText.caption);
            }
            return _CoverageSection(coverage: cov);
          },
        ),
      ],
    );
  }

  /// 技术架构。
  Widget _panelArch(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('技术架构', style: AppText.sectionTitle),
        const SizedBox(height: 16),
        for (final f in _arch) _featureRow(f.$1, f.$2),
      ],
    );
  }

  /// 数据来源（独立条目，右区单独成页）。
  Widget _panelSources(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('数据来源', style: AppText.sectionTitle),
        const SizedBox(height: 8),
        Text(
          '考纲条目以《普通高中生物学课程标准（2017年版2020年修订）》官方编号'
          '为骨架，经假期教学可信资料库（课程标准覆盖矩阵、高考考纲整理）核对；'
          '考点数据逐条标注来源，全部见 data/ 目录。',
          style: AppText.body,
        ),
      ],
    );
  }

  static const _features = [
    ('遗传图谱计算', '双亲多对基因型 → 逐代系谱树，各代表型概率精确展示'),
    ('双基因 9331 计算器', '配子、F2 基因型/表型比例，含 9:7、9:3:4、15:1 等全套变式'),
    ('单基因杂交', '分离定律、测交、回交、不完全显性/共显性/致死修饰模型'),
    ('伴性遗传', '伴 X 交叉遗传，按性别拆分的条件概率（女儿/儿子分开看）'),
    ('分解法 vs 配子法', '同一题两种解法并排跑，直观看到为什么要「拆开算」'),
    ('知识图谱 + 考点速查', '19 个知识点网状拓扑 + 26 条考点应试口径'),
    ('精确分数引擎', '概率全程分数运算（借鉴开源社区共识做法），多代传递零误差'),
  ];

  static const _arch = [
    ('领域引擎', '纯 Dart（lib/engine），与平台无关，Windows/安卓/iOS/Web 通用'),
    ('UI 层', 'Flutter 一套代码跑全端，设计约定见 docs/ARCHITECTURE.md'),
    ('数据层', '结构化 JSON（data/），含考纲、考点汇总'),
  ];

  Widget _featureRow(String title, String desc) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: AppText.label),
          if (desc.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(desc, style: AppText.body),
          ],
        ],
      ),
    );
  }
}

/// 考纲覆盖度区：考情速览 + 总览条 + 按模块分组的逐条列表。
class _CoverageSection extends StatelessWidget {
  final SyllabusCoverage coverage;
  const _CoverageSection({required this.coverage});

  @override
  Widget build(BuildContext context) {
    final total = coverage.items.length;
    final covered = coverage.coveredCount;
    final partial = coverage.partialCount;
    final pct = total == 0 ? 0.0 : covered / total;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 考情速览
        if (!coverage.exam.isEmpty) ...[
          _ExamCard(exam: coverage.exam),
          const SizedBox(height: 12),
        ],
        // 总览
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.tealWash,
            borderRadius: BorderRadius.circular(AppTheme.radiusCard),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text('$covered / $total',
                      style: AppText.monoFigure),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '条课标条目已覆盖'
                      '${partial > 0 ? '（另有 $partial 条部分覆盖）' : ''}',
                      style: AppText.label,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: pct,
                  minHeight: 6,
                  backgroundColor: AppColors.surface,
                  valueColor:
                      AlwaysStoppedAnimation(AppColors.teal),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        // 按模块分组
        for (final entry in coverage.byModule.entries) ...[
          const SizedBox(height: 6),
          Text(entry.key, style: AppText.label),
          const SizedBox(height: 6),
          for (final item in entry.value)
            _SyllabusTile(
              item: item,
              coveredBy: coverage.coveredBy[item.id],
              partial: coverage.partialIds.contains(item.id),
            ),
        ],
      ],
    );
  }
}

/// 考情速览卡：辽宁新高考生物试卷结构与遗传权重。
class _ExamCard extends StatelessWidget {
  final ExamInfo exam;
  const _ExamCard({required this.exam});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.fact_check_outlined,
                    size: 18, color: AppColors.teal),
                const SizedBox(width: 6),
                Expanded(child: Text(exam.title, style: AppText.label)),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 16,
              runSpacing: 8,
              children: [
                _examStat('时长', exam.duration),
                _examStat('满分', exam.totalScore),
                _examStat('卷型', exam.paperType),
              ],
            ),
            const SizedBox(height: 8),
            Text(exam.structure, style: AppText.body),
            const SizedBox(height: 4),
            Text(exam.geneticsWeight,
                style: AppText.body.copyWith(color: AppColors.teal)),
            if (exam.note.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(exam.note, style: AppText.caption),
            ],
          ],
        ),
      ),
    );
  }

  Widget _examStat(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: AppText.caption),
        Text(value, style: AppText.monoSmall),
      ],
    );
  }
}

class _SyllabusTile extends StatelessWidget {
  final SyllabusItem item;
  final String? coveredBy;
  final bool partial;
  const _SyllabusTile({
    required this.item,
    this.coveredBy,
    this.partial = false,
  });

  @override
  Widget build(BuildContext context) {
    final covered = coveredBy != null;
    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      clipBehavior: Clip.antiAlias,
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 12),
          childrenPadding:
              const EdgeInsets.fromLTRB(12, 0, 12, 12),
          iconColor: AppColors.teal,
          collapsedIconColor: AppColors.steel,
          leading: Icon(
            covered
                ? Icons.check_circle
                : partial
                    ? Icons.adjust
                    : Icons.radio_button_unchecked,
            size: 18,
            color: covered
                ? AppColors.teal
                : partial
                    ? AppColors.sand
                    : AppColors.steel,
          ),
          title: Row(
            children: [
              if (item.code.isNotEmpty) ...[
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppColors.tealWash,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: AppColors.teal),
                  ),
                  child: Text(item.code,
                      style: AppText.monoSmall
                          .copyWith(color: AppColors.teal, fontSize: 11)),
                ),
                const SizedBox(width: 8),
              ],
              Expanded(child: Text(item.kaodian, style: AppText.body)),
            ],
          ),
          subtitle: Text(item.level, style: AppText.caption),
          children: [
            if (item.note.isNotEmpty)
              Align(
                alignment: Alignment.centerLeft,
                child: Text(item.note, style: AppText.body),
              ),
            if (covered) ...[
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final cap in coveredBy!.split('、'))
                      AppChip(cap, icon: Icons.check),
                  ],
                ),
              ),
            ] else if (partial) ...[
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text('部分覆盖',
                        style:
                            AppText.caption.copyWith(color: AppColors.sand)),
                    if (item.coveredByList != null)
                      for (final cap in item.coveredByList!)
                        AppChip(cap, icon: Icons.adjust),
                  ],
                ),
              ),
            ] else ...[
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: Text('尚未覆盖 · 已在路线图中',
                    style:
                        AppText.caption.copyWith(color: AppColors.sand)),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
