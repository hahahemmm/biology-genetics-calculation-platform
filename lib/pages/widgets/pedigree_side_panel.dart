// pedigree_side_panel.dart —— 系谱页左侧控制面板（2.3 重构阶段 5 抽取）
//
// 从 genetic_pedigree_page.dart 抽出，纯展示组件：所有页面状态
// （双亲控制器 / 语义开关 / 折叠与回交线状态 / 模式态）与动作
// （计算 / 各对话框 / 开关切换）由页面持有并显式注入，本组件不持有状态。
// 行为与抽取前逐行一致（「计算」「连线」「同性交配」「XY 性别」等
// 文案是测试依赖）。

import 'package:flutter/material.dart';

import '../../engine/pedigree_graph.dart';
import '../../guide/guide_keys.dart';
import '../../theme.dart';
import 'pedigree_canvas.dart';
import 'pedigree_chip_tooltips.dart';

/// v3 悬浮工具条按钮：紧凑 pill，颜色按语义分级
///（armed=家族 / teal=样本与计算 / steel=删除整代）。
/// 侧栏「画布动作」区与画布区右上悬浮面板共用（页面侧悬浮面板同调）。
/// v2.19.16（DeepSeek 找茬 🟡4）：删 96×30 写死尺寸 + shrinkWrap——该
/// 面板是**白板全屏讲解时唯一入口**（退出全屏/添加家族/添加样本等），
/// 30px 在白板上有「点不中退不出」的极端风险；交回课堂主题 52px
/// 加肉（宽度交回内容自适应，不再限 96）。
Widget pedigreeBarAction({
  required IconData icon,
  required String label,
  String? tooltip,
  Color? color,
  VoidCallback? onTap,
}) {
  final c = color ?? AppColors.ink;
  return Tooltip(
    message: tooltip ?? label,
    child: TextButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 16, color: onTap == null ? AppColors.steel : c),
      label: Text(label,
          style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: onTap == null ? AppColors.steel : AppColors.ink)),
      style: TextButton.styleFrom(
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    ),
  );
}

/// v3.1 左侧控制面板（VS Code 双栏式）。
/// v2.16 UI 重做：「模式」「画布」两区迁入画布浮动工具条
/// （PedigreeCanvasToolbar）——画布操作长在画布上；本面板只留
/// 亲本 + 语义。所有控件文案与交互不变（'计算'/'同性交配' 等
/// label 是测试依赖）。
class PedigreeSidePanel extends StatelessWidget {
  const PedigreeSidePanel({
    super.key,
    required this.overlay,
    required this.p1Ctrl,
    required this.p2Ctrl,
    required this.computed,
    required this.engineAlive,
    required this.onShowPreset,
    // v2.16：模式区窄屏保留（computed && MediaQuery.sizeOf(context).width < 1200 时渲染）；宽屏迁入
    // 命令栏左侧组。同一状态源，两处同一时刻只显示一处。
    required this.wireModeOn,
    required this.onToggleWireMode,
    required this.selecting,
    required this.focusing,
    required this.pickedCount,
    required this.onEnterSelect,
    required this.onApplyFocus,
    required this.onShowAll,
    // v3.6 智能密线开关（与聚焦「显示全部」是两个动作）。
    required this.allEdgesOn,
    required this.onToggleAllEdges,
    // v2.16：画布动作区（<860 宽时渲染——>=860 由命令栏左侧组承接）。
    required this.onFullscreen,
    required this.onAddFamily,
    required this.onAddSample,
    required this.onDerive,
    required this.onShowFreq,
    required this.onShowLethal,
    required this.allowSameSex,
    required this.onToggleSameSex,
    required this.trackSex,
    required this.onToggleTrackSex,
    required this.showLineage,
    required this.onToggleLineage,
    // v2.19 曲线连线（蜘蛛网手感）开关。
    required this.curveLinesOn,
    required this.onToggleCurveLines,
    required this.showBackcross,
    required this.onToggleBackcross,
    required this.backcrossEdges,
    required this.hiddenBackcrossKeys,
    required this.onToggleBackcrossEdge,
    required this.sexLinkedOn,
    required this.onShowSexLinked,
    required this.allowMissingGene,
    required this.onToggleMissingGene,
    required this.linkageOn,
    required this.onToggleLinkage,
    required this.allowPolyploid,
    required this.onTogglePolyploid,
    required this.linkageSection,
  });

  final bool overlay;
  final TextEditingController p1Ctrl;
  final TextEditingController p2Ctrl;

  /// 已计算（引擎存在）。控制语义区里依赖引擎的开关禁用态。
  final bool computed;

  /// 引擎存在（= computed；禁用态判定与原 `_engine == null` 对齐）。
  final bool engineAlive;

  /// 「预置」按钮（弹窗列全部预置组合）。
  final VoidCallback onShowPreset;

  // ── 模式区（<860 宽渲染；>=860 在命令栏） ──
  final bool wireModeOn;
  final VoidCallback onToggleWireMode;
  final bool selecting;
  final bool focusing;
  final int pickedCount;
  /// v2.19.6 菜单化：选择元素（持续选择）/ 只看所选（应用聚焦）/
  /// 显示全部（恢复全部）。
  final VoidCallback onEnterSelect;
  final VoidCallback onApplyFocus;
  final VoidCallback onShowAll;

  /// v3.6 智能密线开关（true = 全部自动连线原样铺开）。
  final bool allEdgesOn;
  final VoidCallback onToggleAllEdges;

  // ── 画布动作区（同 <1200 条件） ──
  final VoidCallback onFullscreen;
  final VoidCallback onAddFamily;
  final VoidCallback onAddSample;

  // ── 语义区 ──
  final VoidCallback onDerive;
  final VoidCallback onShowFreq;
  final VoidCallback onShowLethal;
  final bool allowSameSex;
  final ValueChanged<bool> onToggleSameSex;
  final bool trackSex;
  final ValueChanged<bool> onToggleTrackSex;
  final bool showLineage;
  final ValueChanged<bool> onToggleLineage;

  /// v2.19 曲线连线开关（true = 曲线蜘蛛网手感；SVG 板书导出固定正交）。
  final bool curveLinesOn;
  final ValueChanged<bool> onToggleCurveLines;
  final bool showBackcross;
  final ValueChanged<bool> onToggleBackcross;

  /// 当前回交边列表（引擎为 null 时页面传空表，按钮禁用）。
  final List<PedigreeEdge> backcrossEdges;
  final Set<String> hiddenBackcrossKeys;
  final ValueChanged<String> onToggleBackcrossEdge;

  final bool sexLinkedOn;
  final VoidCallback onShowSexLinked;
  final bool allowMissingGene;
  final ValueChanged<bool> onToggleMissingGene;
  final bool linkageOn;
  final ValueChanged<bool> onToggleLinkage;
  final bool allowPolyploid;
  final ValueChanged<bool> onTogglePolyploid;

  /// 连锁互换区块（页面侧 _buildLinkageSection 委托产物；仅 linkageOn 时渲染）。
  final Widget linkageSection;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 280,
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border(right: BorderSide(color: AppColors.border)),
        boxShadow: overlay ? AppColors.cardShadow : null,
      ),
      child: LayoutBuilder(
        builder: (ctx, c) => SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          // v3.2 弹性分布：内容不满时拉伸填满面板高（高窗口无上下空白），
          // 超出时（maxHeight 被子内容突破）自动降级滚动。
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: c.maxHeight - 20),
            child: IntrinsicHeight(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
            // ── 亲本 ──
            // v3.7 新手引导锚点：整块亲本基因型输入区（小节标题 + 预置 +
            // 两个基因型框）包一层 Column，key 才有真实 RenderObject 与尺寸。
            Column(
              key: GuideKeys.pedigreeParents,
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _panelSection('亲本'),
                // v2.1 预置按钮：一个按钮同时填 ♂+♀（弹窗列全部预置组合）
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    onPressed: onShowPreset,
                    icon: const Icon(Icons.library_books_outlined, size: 15),
                    label: const Text('预置'),
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.teal,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
                ),
                // 面板内收紧：去掉 helperText 省一行（无测试依赖），
                // label 保留「亲本 ♂/♀」文案。
                Row(
                  children: [
                    _SexIcon(isMale: true, size: 18),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        controller: p1Ctrl,
                        style: AppText.genotype,
                        decoration: const InputDecoration(
                          isDense: true,
                          labelText: '亲本 ♂',
                          hintText: '如 AaBb',
                          contentPadding:
                              EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    _SexIcon(isMale: false, size: 18),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        controller: p2Ctrl,
                        style: AppText.genotype,
                        decoration: const InputDecoration(
                          isDense: true,
                          labelText: '亲本 ♀',
                          hintText: '如 AaBb',
                          contentPadding:
                              EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
            // ── 亲本 → 计算 ──
            // 老师走查：计算按钮原挂在「语义」标题下，和身后一堆渲染开关
            // 对不上；上移到两个基因型框正下方，填完即可点。文案仍是「计算」。
            _panelSection('亲本 → 计算'),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: onDerive,
                icon: const Icon(Icons.account_tree, size: 18),
                label: const Text('计算'),
                style: FilledButton.styleFrom(
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
            ),
            const Spacer(),
            // ── 模式 + 画布动作（v2.16：<1200 宽在此承载；>=1200 提至
            // 命令栏左侧组。同一状态源，两处同一时刻只显示一处） ──
            if (computed && MediaQuery.sizeOf(context).width < 1200) ...[
              _panelSection('模式'),
              Container(
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  color: AppColors.surfaceLow,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.border),
                ),
                // v3.6：模式区各 chip（连线 / 选择元素 / 只看所选 / 显示全部）改
              // Wrap——窄面板（296px）横排三枚溢出 70px（实测），Wrap
              // 自动换行两行可接受。
              child: Wrap(
                spacing: 2,
                runSpacing: 2,
                children: [
                  _wireModeChip(),
                  ..._selectModeChips(),
                ],
              ),
              ),
              const Spacer(),
              _panelSection('画布'),
              Wrap(
                spacing: 2,
                runSpacing: 2,
                children: [
                  pedigreeBarAction(
                    icon: Icons.fullscreen,
                    label: '全屏',
                    tooltip: '全屏',
                    onTap: onFullscreen,
                  ),
                  pedigreeBarAction(
                    icon: Icons.groups_outlined,
                    label: '添加家族',
                    color: AppColors.armed,
                    onTap: engineAlive ? onAddFamily : null,
                  ),
                  pedigreeBarAction(
                    icon: Icons.person_add_alt,
                    label: '添加样本',
                    color: AppColors.teal,
                    onTap: engineAlive ? onAddSample : null,
                  ),
                ],
              ),
            ],
            const Spacer(),
            // ── 语义 ──
            _panelSection('语义'),
            // 计算按钮已上移到亲本区；本段只剩渲染/规则开关。
            // 工具行（动作类）：频率 / 致死。
            Wrap(
              spacing: 8,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                OutlinedButton.icon(
                  onPressed: engineAlive ? onShowFreq : null,
                  icon: const Icon(Icons.bar_chart_outlined, size: 16),
                  label: const Text('计算基因频率'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: engineAlive ? onShowLethal : null,
                  icon: const Icon(Icons.warning_amber_outlined, size: 16),
                  label: const Text('致死'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
              ],
            ),
            // v2.19.3 UI 重排（group-related-elements 邻近性原则）：
            // 原 9 枚 chip 混排一坨被用户批「乱」——按语义分三组，
            // 组内 chip 距 4 / 组距 12 + 11px 微标签，扫读不再逐枚辩认。
            _chipGroupLabel('显示'),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                FilterChip(
                  label: const Text('主干线'),
                  selected: showLineage,
                  onSelected: onToggleLineage,
                ),
                FilterChip(
                  label: const Text('回交线'),
                  selected: showBackcross,
                  onSelected: onToggleBackcross,
                ),
                // v2.19 曲线连线：正交折线 ↔ 蜘蛛网曲线（屏幕-only；
                // SVG 板书导出固定正交——打印/手绘板书 crisp 优先）。
                FilterChip(
                  label: const Text('曲线连线'),
                  tooltip: '配偶线画弧、回交线画 S、主干线全曲化；'
                      '板书导出仍为正交',
                  selected: curveLinesOn,
                  onSelected: onToggleCurveLines,
                ),
                // v3.6 智能密线：默认收起未聚焦的自动连线（手连的线
                // 一条不删）；撑开全部观察到全部关系时打开本开关。
                FilterChip(
                  label: const Text('全部连线'),
                  tooltip: allEdgesOn
                      ? '当前铺满全部自动连线；点一下回到智能密线'
                      : '智能密线：收起未聚焦的自动连线，只留主干与选中相关的线；'
                          '点选元素可逐代追踪',
                  selected: allEdgesOn,
                  onSelected: (_) => onToggleAllEdges(),
                ),
                _backcrossFilterButton(),
              ],
            ),
            const SizedBox(height: 12),
            _chipGroupLabel('交配规则'),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                FilterChip(
                  label: const Text('同性交配'),
                  // v2.19.6 polish（老师 🔴1）：与底栏 O-6 IconButton 共享同一段
                  // 后果导向文案，避免漂移。
                  tooltip: allowSameSex
                      ? sameSexTooltipOn
                      : sameSexTooltipOff,
                  selected: allowSameSex,
                  onSelected: onToggleSameSex,
                ),
                FilterChip(
                  label: const Text('XY 性别'),
                  tooltip: trackSex
                      ? '计算桶标注雌雄比（XX♀/XY♂ = 1:1）'
                      : '默认桶不分性别；同性个体间默认禁连',
                  selected: trackSex,
                  onSelected: onToggleTrackSex,
                ),
                FilterChip(
                  label: const Text('允许基因缺失交配'),
                  tooltip: '开启后不同基因对数（如三对×一对）可连线杂交，'
                      '子代缺失位点以「-」标注（三倍体×二倍体等场景）',
                  selected: allowMissingGene,
                  onSelected: onToggleMissingGene,
                ),
                // v2.1 多倍体开关（引擎 allowPolyploid，_derive 时应用）
                FilterChip(
                  label: const Text('多倍体'),
                  tooltip: '开启后允许单倍体/三倍体/四倍体/五倍体'
                      '（每对位点 1~5 份等位，如 Aaa）',
                  selected: allowPolyploid,
                  onSelected: onTogglePolyploid,
                ),
              ],
            ),
            const SizedBox(height: 12),
            _chipGroupLabel('高级'),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                FilterChip(
                  label: const Text('伴性遗传'),
                  selected: sexLinkedOn,
                  onSelected: (_) => onShowSexLinked(),
                ),
                FilterChip(
                  label: const Text('连锁互换'),
                  selected: linkageOn,
                  onSelected: onToggleLinkage,
                ),
              ],
            ),
            if (linkageOn) ...[
              _panelSection('连锁互换'),
              linkageSection,
            ],
            const Spacer(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// 面板分区标题：1px 分隔线 + 13px 小标题（v3.1 分区节奏，紧凑高度）。
  Widget _panelSection(String title) {
    return Padding(
      padding: const EdgeInsets.only(top: 6, bottom: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Divider(height: 4, thickness: 1),
          Text(title, style: AppText.sectionTitle.copyWith(fontSize: 13)),
        ],
      ),
    );
  }

  /// v2.19.3 chip 组微标签（11px 淡色）——比 13px 分区标题轻一档，
  /// 用于语义区内部的小组分隔（显示/交配规则/高级）。
  Widget _chipGroupLabel(String title) {
    return Padding(
      padding: const EdgeInsets.only(top: 2, bottom: 3),
      child: Text(
        title,
        style: AppText.caption.copyWith(
            color: AppColors.steel,
            fontSize: 11,
            fontWeight: FontWeight.w600),
      ),
    );
  }

  /// 「连线」模式 chip：segmented 段样式——关闭透明底、开启紫光填充。
  Widget _wireModeChip() {
    final on = wireModeOn;
    return FilterChip(
      // v3.7 新手引导高亮目标：<1200 宽「连线」只在这里出现（底栏编辑
      // 组 >=1200 才渲染），两处条件按同一宽度互斥，同一 GlobalKey 不会
      // 同时挂载。
      key: GuideKeys.pedigreeWireBtn,
      avatar: Icon(Icons.cable_outlined,
          size: 16, color: on ? AppColors.onTeal : AppColors.armed),
      label: const Text('连线'),
      selected: on,
      onSelected: (_) => onToggleWireMode(),
      backgroundColor: Colors.transparent,
      selectedColor: AppColors.armed,
      labelStyle: TextStyle(
          color: on ? AppColors.onTeal : AppColors.ink,
          fontWeight: FontWeight.w600),
      side: const BorderSide(color: Colors.transparent),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(7)),
      elevation: 0,
    );
  }

  /// v3.6 「选择元素」+「只看所选（N）」+「显示全部」菜单 chip：
  /// 选择元素可持续加选不被打断；只看所选 = 应用聚焦；
  /// 显示全部 = 只清聚焦（不展开各代）。三枚互不代偿。
  List<Widget> _selectModeChips() {
    final selLabel =
        selecting && pickedCount > 0 ? '选择元素（$pickedCount）' : '选择元素';
    chip(bool selected, IconData icon, String label, VoidCallback onTap,
        String tip) {
      return FilterChip(
        avatar: Icon(icon,
            size: 16, color: selected ? AppColors.onTeal : AppColors.teal),
        label: Text(label),
        tooltip: tip,
        selected: selected,
        onSelected: (_) => onTap(),
        backgroundColor: Colors.transparent,
        selectedColor: AppColors.teal,
        labelStyle: TextStyle(
            color: selected ? AppColors.onTeal : AppColors.ink,
            fontWeight: FontWeight.w600),
        side: const BorderSide(color: Colors.transparent),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(7)),
        elevation: 0,
      );
    }

    return [
      chip(selecting, Icons.touch_app_outlined, selLabel, onEnterSelect,
          '选择元素：进入后可持续加选/取消，不会被中断'),
      if (selecting && pickedCount > 0)
        chip(false, Icons.filter_alt_outlined, '只看所选（$pickedCount）',
            onApplyFocus, '应用聚焦：只显示所选元素'),
      if (focusing)
        chip(true, Icons.visibility_outlined, '显示全部', onShowAll,
            '恢复全部元素可见（各代折叠状态保持不变）'),
    ];
  }

  /// 调色板按钮：弹出当前所有回交边（色块 = 画布线条色），逐条显隐。
  /// v2.19.10：色块 14→24（老师走查 M5：几米外 14px 色块看不见）+
  /// 图标加 Badge 计数（可见/总数，如 3/5——一眼看出几条被关）。
  Widget _backcrossFilterButton() {
    final list = backcrossEdges;
    final visible = list
        .where((e) => !hiddenBackcrossKeys.contains(backcrossEdgeKey(e)))
        .length;
    return PopupMenuButton<String>(
      tooltip: '回交线逐条显隐（当前 $visible/${list.length} 条可见）',
      enabled: list.isNotEmpty,
      icon: Badge(
        isLabelVisible: list.isNotEmpty && visible < list.length,
        // v2.19.13（老师找茬 🟡7）：默认 10sp 几米外读不出——label
        // 提到 13 bold（课堂 textScaler 1.3 → ~17sp），Badge 本体随之
        // 放大到可读。
        label: Text('${list.length - visible}',
            style: const TextStyle(
                fontSize: 13, fontWeight: FontWeight.bold)),
        child: Icon(Icons.palette_outlined,
            size: 24, color: list.isEmpty ? AppColors.steel : AppColors.ink),
      ),
      onSelected: onToggleBackcrossEdge,
      itemBuilder: (ctx) => [
        for (final e in list)
          PopupMenuItem<String>(
            value: backcrossEdgeKey(e),
            child: Row(
              children: [
                Container(
                  // v2.19.12（老师验证 🟢5）：24→28——几米白板上 24px
                  // 色块仍偏小，28px 与侧栏 chip 同档可辨。
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: backcrossEdgeColor(e),
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('${e.fromId} × ${e.toId}',
                      style: AppText.caption, overflow: TextOverflow.ellipsis),
                ),
                if (!hiddenBackcrossKeys.contains(backcrossEdgeKey(e)))
                  Icon(Icons.check, size: 16, color: AppColors.teal),
              ],
            ),
          ),
      ],
    );
  }
}

/// 性别图标（雄性方块 / 雌性圆形），配色走 token。
class _SexIcon extends StatelessWidget {
  final bool isMale;
  final double size;
  const _SexIcon({required this.isMale, required this.size});

  @override
  Widget build(BuildContext context) {
    if (isMale) {
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: AppColors.tealWash,
          border: Border.all(color: AppColors.teal, width: 1.5),
          borderRadius: BorderRadius.circular(2),
        ),
      );
    }
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: AppColors.surface,
        shape: BoxShape.circle,
        border: Border.all(color: AppColors.sand, width: 1.5),
      ),
    );
  }
}
