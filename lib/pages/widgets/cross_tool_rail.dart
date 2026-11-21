// cross_tool_rail.dart —— 9331 页宽屏常驻左侧工具侧栏（v2.19.16 工作台化）
//
// 动机：系谱页是「VS Code 双栏式」专业工作台（左侧密集工具面板 +
// 中央大画布），而 9331 页是「居中 720px 窄条 + 大白板」，两页布局
// 语言割裂（用户原话：系谱像 Audition，9331 像 PPT）。本组件把
// ☰ 工具抽屉的内容（经典预设 + 计算历史）常驻化为左侧栏，与系谱页
// PedigreeSidePanel 同款视觉语言（分区小标题 + 紧凑控件组）。
//
// 布局规则（与系谱页 overlay 判定同阈值）：
//   >=1200 逻辑宽 → Row[rail 280px, Expanded(TabBarView)] 常驻
//   <1200 → 不传 rail，Scaffold 抽屉承接（窄屏空间让给内容）
//
// 纯展示组件：历史数据与预设回调全部由容器页注入，本组件不持有状态。

import 'package:flutter/material.dart';

import '../../theme.dart';

/// 一条计算历史（与容器页 _history 的元素同构）。
typedef CrossHistoryEntry = ({
  int tab,
  String p1,
  String p2,
  String ratio
});

/// 经典预设项：展示名 + 目标 tab + 亲本组合。
typedef CrossPreset = (String, int, String, String);

/// v2.19.17 tab 侧栏注入协议：宽屏（>=1200）时容器页从当前 tab 的
/// State 取「输入面板」塞进 rail 顶部——输入控件与预设/历史同栏，
/// 中间内容区只剩纯结果呈现（系谱页「左功能右画布」同款信息架构）。
/// tab 未挂载（TabBarView 懒构建）时容器页取不到，槽位显示占位。
abstract class CrossTabSidePanel {
  /// 输入面板（无卡片壳，直接铺 rail 背景色）。
  Widget buildSidePanel(BuildContext context);
}

/// v2.19.18 平铺分区（去主体化的 StepCard 替代，跨 tab 公共）：标题行
/// + 内容直接铺页面背景，无悬浮卡片壳/阴影/圆角底——「背景融入主体」
/// 的关键件。分区之间只用间距与标题层级区分（系谱页侧栏同款架构）。
class FlatSection extends StatelessWidget {
  const FlatSection({
    super.key,
    required this.title,
    required this.child,
    this.subtitle,
    this.trailing,
  });

  final String title;
  final String? subtitle;
  final Widget? trailing;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 30),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: AppText.sectionTitle),
                    if (subtitle != null) ...[
                      const SizedBox(height: 3),
                      Text(subtitle!,
                          style: AppText.caption
                              .copyWith(color: AppColors.steel)),
                    ],
                  ],
                ),
              ),
              if (trailing != null) trailing!,
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

class CrossToolRail extends StatelessWidget {
  const CrossToolRail({
    super.key,
    required this.history,
    required this.onPreset,
    required this.onReplay,
    this.top,
  });

  /// 本次会话计算历史（新→旧，≤20 条）。
  final List<CrossHistoryEntry> history;

  /// 点预设：关侧栏语义无关，直接切 tab + 回填即算。
  final void Function(int tab, String p1, String p2) onPreset;

  /// 点历史条目：与预设同通道（恢复该组合再算一次）。
  final void Function(int tab, String p1, String p2) onReplay;

  /// v2.19.17：当前 tab 注入的输入面板（rail 顶部，预设/历史之上）。
  /// null = tab 未挂载或该 tab 无独立输入面板。
  final Widget? top;

  /// v2.14 预设清单（与抽屉版严格一致——测试依赖这些文案）。
  static const presets = <CrossPreset>[
    ('双基因 · 杂合自交 9:3:3:1', 0, 'AaBb', 'AaBb'),
    ('双基因 · 测交 1:1:1:1', 0, 'AaBb', 'aabb'),
    ('双基因 · 一对杂合 × 纯合', 0, 'AABb', 'AaBb'),
    ('三对基因 · 三杂合自交 27:9:…:1', 1, 'AaBbCc', 'AaBbCc'),
    ('三对基因 · 测交 1:1:…:1', 1, 'AaBbCc', 'aabbcc'),
    ('三对基因 · 两对杂合 AaBbCC', 1, 'AaBbCC', 'AaBbCc'),
  ];

  @override
  Widget build(BuildContext context) {
    // Material 在最外层：ListTile 的 ink splash 画在最近的 Material
    // 祖先上——外层若用带背景色的 Container/DecoratedBox 会挡住
    // splash（Flutter 断言）；Material + shape 边框二合一。
    return Material(
      color: AppColors.surface,
      shape: Border(right: BorderSide(color: AppColors.border)),
      child: SizedBox(
        width: 280,
        child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(Icons.handyman_outlined, size: 18, color: AppColors.teal),
              const SizedBox(width: 8),
              Text('计算工具', style: AppText.sectionTitle),
            ]),
            // v2.19.17：tab 注入的输入面板（双基因=亲本输入+计算按钮）。
            if (top != null) ...[
              const SizedBox(height: 14),
              top!,
            ],
            const SizedBox(height: 14),
            Text('经典预设（点按直接开算）', style: AppText.label),
            const SizedBox(height: 8),
            for (final p in presets)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: () => onPreset(p.$2, p.$3, p.$4),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(p.$1,
                          style: AppText.body.copyWith(fontSize: 13)),
                    ),
                  ),
                ),
              ),
            const SizedBox(height: 14),
            Text('计算历史（本次会话）', style: AppText.label),
            const SizedBox(height: 4),
            if (history.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.history_outlined,
                        size: 28, color: AppColors.steel),
                    const SizedBox(height: 8),
                    Text('暂无历史', style: AppText.sectionTitle),
                    const SizedBox(height: 4),
                    Text(
                      '点「计算比例」后自动记录',
                      textAlign: TextAlign.center,
                      style: AppText.body.copyWith(color: AppColors.steel),
                    ),
                  ],
                ),
              )
            else
              for (final h in history)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text('${h.p1} × ${h.p2}',
                      style: AppText.genotype.copyWith(fontSize: 13)),
                  subtitle: Text(
                      '${h.tab == 1 ? '三对基因' : '双基因'} · 表型比 ${h.ratio}',
                      style: AppText.caption.copyWith(color: AppColors.steel)),
                  trailing: Icon(Icons.replay_outlined,
                      size: 16, color: AppColors.teal),
                  onTap: () => onReplay(h.tab, h.p1, h.p2),
                ),
          ],
        ),
        ),
      ),
    );
  }
}
