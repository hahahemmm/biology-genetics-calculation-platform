// tool_workbench.dart —— 计算器页通用工作台骨架（v2.19.21 / v2.19.22 修刷新）
//
// 9331 页 v2.19.16-18 的工作台布局语言（AppBar bottom TabBar +
// 宽屏 ≥1200 左侧常驻输入面板 / 窄屏面板回渲染内容顶部），推广到
// 分子 / 进化 / 倍性等多计算器页——三页共用一套骨架，不再各写一遍
// 宽/窄分支。与 9331 的区别：本骨架不内置「经典预设/历史」区
// （CrossToolRail 是 9331 专用），左栏内容完全由当前 tab 注入。
//
// v2.19.22 修复：骨架改为 StatefulWidget + 监听 TabController——
// 原 StatelessWidget 形态下切 tab 只有 TabBarView 子树 rebuild，
// 宽屏左栏（rail 的 sidePanel 槽）是骨架 build 输出的兄弟分支，
// 不随 tab 切换刷新，表现为「输入面板卡在上一个 tab / 卡丢」。
// 注意 identical 短路纪律：调用方每次 build 必须新建本骨架实例
// （TabController 仍由调用方 State 持有；骨架实例复用会触发
// Element identical 短路导致骨架自身颜色冻结，v2.19.20 事故）。
//
// 用法（调用方页面持有 TabController，骨架每 build 新建实例）：
//
//   late final TabController _tab;   // State 字段，initState 创建
//   @override
//   Widget build(BuildContext context) {
//     final tabs = _tabs();
//     return Scaffold(
//       appBar: AppBar(..., bottom: buildWorkbenchTabBar(_tab, tabs)),
//       body: ToolWorkbench(controller: _tab, tabs: tabs, ...),
//     );
//   }

import 'package:flutter/material.dart';

import '../../theme.dart';
import '../../ui/module_surface.dart';

/// 一个工作台 tab：顶部导航标签 + 输入面板（sidePanel）+ 结果区（body）。
class WorkbenchTabSpec {
  const WorkbenchTabSpec({
    required this.label,
    this.icon,
    required this.sidePanel,
    required this.body,
  });

  final String label;
  final IconData? icon;

  /// 输入面板（无卡片壳）。宽屏注入左栏；窄屏渲染在 body 顶部。
  final WidgetBuilder sidePanel;

  /// 结果区（FlatSection 平铺）。
  final WidgetBuilder body;
}

/// 通用工作台骨架（StatefulWidget 监听 TabController，切 tab 时
/// 宽屏左栏跟随刷新）。调用方持有 [TabController] 并在 build 中
/// 新建本骨架实例；TabBar 用顶层函数 [buildWorkbenchTabBar] 组装
/// 进 AppBar.bottom（StatefulWidget 无法直接暴露 State 的方法）。
class ToolWorkbench extends StatefulWidget {
  const ToolWorkbench({
    super.key,
    required this.controller,
    required this.tabs,
    this.railTitle = '计算输入',
    this.railIcon = Icons.tune,
    // v2.19.30（afc744d 修订注释）：可选 body 滚动控制器——调用方
    // 切卡时 jumpTo(0) 回到卡首。**安全前提**：TabBarView 切页动画期
    // 相邻 tab 的 pane 会同时挂载（多 ScrollPosition 共用一 controller
    // 会撞断言）——本骨架已防御：controller 只挂到当前 index 的 pane
    //（见 build 内 children 循环）。v2.19.26 旧注释「同一时刻只挂载
    // 一个」对 TabBarView 不成立，勿恢复共享写法。
    this.scrollController,
  });

  final TabController controller;
  final List<WorkbenchTabSpec> tabs;

  /// 宽屏左栏分区标题（默认「计算输入」）。
  final String railTitle;
  final IconData railIcon;
  final ScrollController? scrollController;

  @override
  State<ToolWorkbench> createState() => _ToolWorkbenchState();
}

/// 组装 AppBar.bottom 的 TabBar（调用方在 build 里：
/// `AppBar(..., bottom: buildWorkbenchTabBar(_tab, tabs))`；
/// body 侧直接 `ToolWorkbench(controller: _tab, tabs: tabs, ...)`）。
/// tab 数 ≥5 时 isScrollable，防窄屏标签被淡出裁切（找茬 P3#8）。
///
/// v2.19.60 挤压态瘦身（用户定级：窗口被挤到手机档时「双层导航」观感）：
/// 窗口宽 < [kWorkbenchCompactWidth] 时把页签从「图标 + 文字」降为「纯文字」。
/// 理由——挤压态下本 TabBar 的「图标 + 文字」与底部导航（同为「图标 + 文字」）
/// **视觉同构**，眼睛读到的是上下两层导航；去掉图标后本行与底导明显分层，
/// 功能完全不变（同一个 controller、同样可滚动、同样能切页签）。≥ 阈值维持
/// 现状 icon + text（宽档视觉不变，基线零变化）。
///
/// 实现说明：本函数是顶层函数、六个调用页一律以 `(controller, tabs)` 两参调用，
/// 故**不新增 context 参数**（否则六页都要改）——改为返回一个自读 MediaQuery 的
/// [_WorkbenchTabBar]（build 期取 context ⇒ 窗口跨阈值时自动重建）。
PreferredSizeWidget buildWorkbenchTabBar(
        TabController controller, List<WorkbenchTabSpec> tabs) =>
    _WorkbenchTabBar(controller: controller, tabs: tabs);

/// 挤压态阈值（见 [buildWorkbenchTabBar] 注释）：窗口宽 < 此值 ⇒ 页签去图标。
/// 抽成公开常量：守卫与本函数共用一份真相，不许各写一个数字。
const double kWorkbenchCompactWidth = 720;

/// [buildWorkbenchTabBar] 的返回体。存在的唯一理由：需要 build 期的 `context`
/// 去读 `MediaQuery`（顶层函数签名不便新增 context 参数）。
class _WorkbenchTabBar extends StatelessWidget implements PreferredSizeWidget {
  const _WorkbenchTabBar({required this.controller, required this.tabs});

  final TabController controller;
  final List<WorkbenchTabSpec> tabs;

  /// 调用页一律把本组件外包 `PreferredSize(Size.fromHeight(48))`，故本值只作
  /// 兜底：取「图标 + 文字」档的高（Tab 72 + 指示条 2 = 74，与既有 TabBar 在
  /// 宽档的 `preferredSize` 逐值一致）⇒ 即便某处直接把它当 `bottom:` 用，
  /// 也与改动前同高，不产生回归。
  @override
  Size get preferredSize => const Size.fromHeight(74);

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.of(context).size.width < kWorkbenchCompactWidth;
    return TabBar(
      controller: controller,
      isScrollable: tabs.length >= 5,
      tabAlignment: tabs.length >= 5 ? TabAlignment.start : null,
      tabs: [
        for (final t in tabs)
          // 挤压态去图标（理由见 [buildWorkbenchTabBar] 注释）。
          if (compact)
            Tab(text: t.label)
          else
            Tab(
              icon: t.icon == null ? null : Icon(t.icon, size: 20),
              text: t.label,
            ),
      ],
    );
  }
}

class _ToolWorkbenchState extends State<ToolWorkbench> {
  @override
  void initState() {
    super.initState();
    _lastIndex = widget.controller.index;
    widget.controller.addListener(_onTabChanged);
  }

  @override
  void didUpdateWidget(ToolWorkbench oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onTabChanged);
      widget.controller.addListener(_onTabChanged);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onTabChanged);
    super.dispose();
  }

  /// v2.19.23：按 index 变化即刻 rebuild（不等动画落定）。
  /// v2.19.22 的 `!indexIsChanging` 守卫恰好丢掉动画开始时 index 已变的
  /// 那次通知——300ms 动画期内左栏仍是旧 tab 面板且可点击/可输入（找茬
  /// 报告 P2#2）。改为 index 差分：无每帧开销，也无错配窗口。
  int _lastIndex = -1;

  void _onTabChanged() {
    if (!mounted) return;
    if (widget.controller.index != _lastIndex) {
      setState(() => _lastIndex = widget.controller.index);
    }
  }

  @override
  Widget build(BuildContext context) => buildBody(context);

  Widget buildBody(BuildContext context) {
    if (widget.tabs.isEmpty) return const SizedBox.shrink();
    final wide = MediaQuery.of(context).size.width >= 1200;
    // 严禁 const children：tab 内容文字消费 AppColors 显式 style，
    // const 实例 canonicalize → Element identical 短路永不 rebuild，
    // 主题切换后首帧色值永久冻结（v2.2 白底白字 / v2.19.20 浅色字
    // 事故同款根因）。
    final tabView = TabBarView(
      controller: widget.controller,
      children: [
        // v2.19.30（M3.1 老师 P2-6 防御）：共享 scrollController 只挂到
        // 当前 tab 的 pane——TabBarView 切页动画期间相邻 tab 的 pane
        // 会同时挂载（多 ScrollPosition 共用一 controller），任何
        // jumpTo 都撞 'attached to multiple scroll views' 断言。
        // 原注释「宽/窄同一时刻只挂载一个」对 TabBarView 不成立。
        for (var i = 0; i < widget.tabs.length; i++)
          _TabPane(
            spec: widget.tabs[i],
            wide: wide,
            controller:
                i == widget.controller.index ? widget.scrollController : null,
          ),
      ],
    );
    if (!wide) return tabView;
    final index = widget.controller.index.clamp(0, widget.tabs.length - 1);
    final current = widget.tabs[index];
    // v2.21.0：280px 输入 + 自适应结果两块薄壳；不额外嵌套标题列，
    // 因而 TabBarView 仍直接获得 Row 提供的有界高度。
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 280,
            child: ModuleSurface(
              title: widget.railTitle,
              icon: widget.railIcon,
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
              fillRemaining: true,
              child: SingleChildScrollView(
                padding: const EdgeInsets.only(top: 2, bottom: 8),
                // 按 tab 上 Key，避免输入 controller 与滚动位置串页。
                child: KeyedSubtree(
                  key: ValueKey('rail-panel-$index'),
                  child: current.sidePanel(context),
                ),
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: ModuleSurface(
              padding: EdgeInsets.zero,
              child: tabView,
            ),
          ),
        ],
      ),
    );
  }
}

/// tab 内容载体：宽屏只渲染 body（输入在左栏）；窄屏 sidePanel
/// 回渲染在 body 顶部（空间让给内容，与 v2.19.18 六个 9331 tab
/// 的窄屏模式同语义）。
class _TabPane extends StatelessWidget {
  const _TabPane(
      {required this.spec, required this.wide, this.controller});

  final WorkbenchTabSpec spec;
  final bool wide;
  final ScrollController? controller;

  @override
  Widget build(BuildContext context) {
    // v2.19.26（平板 F-4）：PageStorageKey 保住跨宽窄切换（旋转/窗口
    // 拖动跨 1200）时的 body 滚动偏移——原实现宽窄分支返回不同类型
    // 子树，切换即整树重建、滚动归零。
    final storageKey = PageStorageKey<String>('wb-${spec.label}');
    if (wide) {
      return SingleChildScrollView(
        key: storageKey,
        controller: controller,
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1400),
            child: spec.body(context),
          ),
        ),
      );
    }
    return SingleChildScrollView(
      key: storageKey,
      controller: controller,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          spec.sidePanel(context),
          const SizedBox(height: 20),
          Divider(color: AppColors.border.withValues(alpha: 0.6)),
          const SizedBox(height: 20),
          spec.body(context),
        ],
      ),
    );
  }
}
