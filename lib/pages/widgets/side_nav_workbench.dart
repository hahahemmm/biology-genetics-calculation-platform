// side_nav_workbench.dart —— 信息型页面通用「分区选择条 + 右内容」骨架
//（v2.19.28 建，v2.20.0 收掉宽屏第二列 + 转 Stateful）
//
// UI 统一化专项（用户裁定：全部页面统一为「左侧工作区 + 右结果/内容」的
// 工作台布局，废弃「下面大白板 + 上面突出主体卡片」的 StepCard 堆叠）。
// 本骨架服务于「无计算输入、只有信息分区」的页面（课标 / 关于），
// 与计算型页面的 ToolWorkbench 同款视觉语言：
//
//   · **所有宽度**统一为「顶部横向滚动选择条（pill，选中 tealWash）+
//     右区平铺选中分区内容（无卡片壳，节标题 + 内容）」。窄屏用短标签，
//     宽屏用全称（宽度预算不同，见 _NavPill.fullLabel）。
//   · v2.20.0（用户裁定：双层左导航）：删掉 ≥1200 的 280px 纵向目录列。
//     宽屏时它与 HomeShell 的全局 NavigationRail 并排 = 屏幕左侧两层导航；
//     现在只剩全局 Rail 一层，分区切换全部交给顶部选择条。
//     ToolWorkbench 的左输入面板不受影响（那是「输入」，不是导航）。
//   · v2.20.0（M3.1 评审）：宽屏在横条里**同时给出组名**——只靠一条细
//     竖线表达「概念3 / 概念4 / 参考」太隐晦；窄屏保持短标签 + 竖线不变。
//
// v2.20.0 选中项自动进视口（M3.1 评审）：
//   课标等页会被程序化改 selectedId（e.g. 错题本深链 focusCode ⇒ 左树切到
//   对应关键概念），目标 pill 可能在横条视口外，用户只看到内容变了、找不到
//   选中项。本组件因此**转 Stateful**：每个 pill 挂 GlobalKey，
//   - 首次挂载（父组件初始就选中靠后项）→ postFrame 揭示；
//   - didUpdateWidget 发现 selectedId 变化 → postFrame 揭示；
//   揭示统一走 lib/ui/scroll_reveal.dart（已完整可见时 no-op，不会把
//   手动点到的项再顶到视口起点）。手动点击路径与程序化路径共用同一段逻辑
//   （State 里 onSelect 之后由父组件回灌 selectedId 触发）。
//
// identical 短路纪律：调用方每次 build 新建本骨架实例（本组件消费
// AppColors 主题 token，禁 const 实例化复用——v2.19.20/23 事故根因）。
// 旋转/窗口拖动跨阈值时右区滚动偏移由 PageStorageKey 保住（v2.19.27 F-4）。

import 'package:flutter/material.dart';

import '../../theme.dart';
import '../../ui/scroll_reveal.dart';

/// 左栏一个分组（组头可空串 = 不分组，条目直接平铺）。
class SideNavGroup {
  const SideNavGroup({required this.label, this.icon, required this.entries});

  final String label;
  final IconData? icon;
  final List<SideNavEntry> entries;
}

/// 左栏一个导航条目（id 全局唯一，作为选中态与内容路由键）。
class SideNavEntry {
  const SideNavEntry({
    required this.id,
    required this.label,
    this.shortLabel,
    this.icon,
    this.subtitle,
  });

  final String id;
  final String label;

  /// v2.19.29（M3.1 学生 N-P1-4）：窄态横滚 pill 用的短标签——
  /// 长概念名（整句教学语言）当导航标签读不动且横滑 N 屏才看完。
  /// null 时窄态回退 [label]。
  final String? shortLabel;
  final IconData? icon;

  /// 条目标注（如「7 条」「22 条」），可选。
  final String? subtitle;
}

/// 信息型页面骨架：顶部分区选择条 + 右内容（全宽度同一形态）。
class SideNavWorkbench extends StatefulWidget {
  const SideNavWorkbench({
    super.key,
    required this.groups,
    required this.selectedId,
    required this.onSelect,
    required this.body,
    this.bodyMaxWidth = 980,
  });

  final List<SideNavGroup> groups;

  /// 当前选中条目 id（父组件 State 持有；可被程序化改写）。
  final String selectedId;
  final ValueChanged<String> onSelect;

  /// 当前选中条目的内容区（无卡片壳平铺）。
  final WidgetBuilder body;

  /// 右区内容最大宽度（阅读舒适度；全宽长文本行在投影上易串行）。
  final double bodyMaxWidth;

  @override
  State<SideNavWorkbench> createState() => _SideNavWorkbenchState();
}

class _SideNavWorkbenchState extends State<SideNavWorkbench> {
  /// 每个分区条目一枚 GlobalKey（id → key），用于把选中 pill 揭示进视口。
  final Map<String, GlobalKey> _pillKeys = <String, GlobalKey>{};

  /// 揭示是否已排队——父组件连续改 selectedId 时只跑最后安排的那一次，
  /// 不叠加多次滚动请求（异步去重）。
  bool _revealScheduled = false;

  @override
  void initState() {
    super.initState();
    _syncKeys();
    // 首次挂载兜底：父组件可能一上来就选中靠后的分区（如课标 focusCode）。
    _scheduleReveal();
  }

  @override
  void didUpdateWidget(SideNavWorkbench oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncKeys();
    if (oldWidget.selectedId != widget.selectedId) _scheduleReveal();
  }

  /// 按当前 groups 补齐/清理 pill key（id 集合变化时不留悬空 key）。
  void _syncKeys() {
    final ids = <String>{
      for (final g in widget.groups)
        for (final e in g.entries) e.id,
    };
    _pillKeys.removeWhere((id, _) => !ids.contains(id));
    for (final id in ids) {
      _pillKeys.putIfAbsent(id, () => GlobalKey(debugLabel: 'snw-pill-$id'));
    }
  }

  /// 排一次 postFrame 揭示（同一帧内多次请求合并）。
  void _scheduleReveal() {
    if (_revealScheduled) return;
    _revealScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      _revealScheduled = false;
      if (!mounted) return;
      final ctx = _pillKeys[widget.selectedId]?.currentContext;
      if (ctx == null) return;
      // 300ms 与主内容切分区的观感一致；已完全可见时 helper 直接 no-op。
      await revealInViewport(ctx,
          duration: const Duration(milliseconds: 300));
    });
  }

  @override
  Widget build(BuildContext context) {
    // v2.19.29（M3.1 老师 P2-1）：条高随 textScaler 缩放——课堂模式
    // ×1.75 时 pill 行高约 31.5px，52px 固定条会把文字底部裁掉。
    // 惯例同 pedigree_bottom_bar（62 × textScaler）。
    final barH = 52.0 * MediaQuery.textScalerOf(context).scale(1.0);
    // v2.20.0：宽屏有横向余量 ⇒ pill 用全称 + 组名上条（原宽屏纵向目录里
    // 就是全称，收掉目录后不能把 22 条课标概念名退化成短标签）；
    // 窄屏沿用短标签 + 分组竖线，避免一条概念横滑一屏。
    final wide = MediaQuery.of(context).size.width >= 1200;
    return Column(
      children: [
        SizedBox(
          // ⛔ width: infinity 必须有：SingleChildScrollView 在滚动方向
          // **收缩到内容宽**（ListView 不是），而 Column 默认
          // crossAxisAlignment.center 会把这条收缩后的横条居中——实测
          // 1900 宽独立构造时整条从 x≈10 漂到 x≈626（0.64% golden diff
          // 就是它，不是 reveal 滚动：pixels 始终 0）。
          width: double.infinity,
          height: barH,
          // v2.20.0（M3.1 评审）：改 **SingleChildScrollView + Row**——横向
          // ListView 是惰性的，视口外的 pill 根本不挂载，GlobalKey 拿不到
          // context，程序化选中项就无法被揭示。20 余枚 pill 全量挂载开销
          // 可忽略，换来「任意 id 都能被揭示」的确定性。
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var gi = 0; gi < widget.groups.length; gi++) ...[
                  if (gi > 0)
                    Padding(
                      padding:
                          const EdgeInsets.only(right: 6, top: 10, bottom: 10),
                      child: VerticalDivider(
                        width: 1,
                        color: AppColors.border.withValues(alpha: 0.6),
                      ),
                    ),
                  // 宽屏组名上条：只靠竖线表达「概念3/概念4/参考」太隐晦
                  //（M3.1 评审）。窄屏不加 —— 手机横条每一像素都紧。
                  if (wide && widget.groups[gi].label.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(right: 8, left: 2),
                      child: Center(
                        child: ConstrainedBox(
                          // 组名是"路标"不是"正文"：限宽 + 省略，避免把
                          // 后面的 pill 全推出视口（课标 22 条概念的长句组名
                          // 每个能吃掉 200px）。
                          constraints: const BoxConstraints(maxWidth: 132),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (widget.groups[gi].icon != null) ...[
                                Icon(widget.groups[gi].icon,
                                    size: 14, color: AppColors.steel),
                                const SizedBox(width: 4),
                              ],
                              Flexible(
                                child: Text(widget.groups[gi].label,
                                    maxLines: 1,
                                    softWrap: false,
                                    overflow: TextOverflow.ellipsis,
                                    style: AppText.caption
                                        .copyWith(color: AppColors.steel)),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  for (final e in widget.groups[gi].entries)
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: _NavPill(
                        // key 挂在 pill 上：选中项揭示用（见 _scheduleReveal）。
                        key: _pillKeys[e.id],
                        entry: e,
                        selected: e.id == widget.selectedId,
                        fullLabel: wide,
                        onTap: () => widget.onSelect(e.id),
                      ),
                    ),
                ],
              ],
            ),
          ),
        ),
        Divider(height: 1, color: AppColors.border.withValues(alpha: 0.6)),
        Expanded(child: _buildBody(context)),
      ],
    );
  }

  Widget _buildBody(BuildContext context) {
    return SingleChildScrollView(
      key: PageStorageKey<String>('snw-${widget.selectedId}'),
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: widget.bodyMaxWidth),
          child: widget.body(context),
        ),
      ),
    );
  }
}

/// 顶部分区选择条 pill。
class _NavPill extends StatelessWidget {
  const _NavPill({
    super.key,
    required this.entry,
    required this.selected,
    required this.fullLabel,
    required this.onTap,
  });

  final SideNavEntry entry;
  final bool selected;

  /// true ⇒ 用 [SideNavEntry.label]（宽屏），false ⇒ 优先短标签（窄屏）。
  final bool fullLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? AppColors.tealWash : Colors.transparent,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        // v2.19.29（M3.1 学生 N-P1-3）：pill 是信息页唯一分区切换器——
        // minHeight 44 触屏命中线（原 ~32px：caption 行高 18 + padding
        // 12 + 边框 2，塞在 52px 条内上下各 2px 死区）。
        child: Container(
          constraints: const BoxConstraints(minHeight: 44),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
                color: selected ? AppColors.teal : AppColors.border),
          ),
          child: Text(
            fullLabel ? entry.label : (entry.shortLabel ?? entry.label),
            maxLines: 1,
            softWrap: false,
            overflow: TextOverflow.ellipsis,
            style: AppText.caption.copyWith(
              color: selected ? AppColors.teal : AppColors.graphite,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
            ),
          ),
        ),
      ),
    );
  }
}
