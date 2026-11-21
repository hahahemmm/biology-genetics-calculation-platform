// step_card.dart —— 2.2 UI 重做公共组件：步骤流程卡三件套
//
// 来源：9331 页样板（f070761）验收通过后提炼，供全部页面推广使用。
//
// 设计意图：
//   StepCard  —— 序号圆点 + 标题/副标题 + 内容区，页面由若干步骤卡纵向排列；
//   FlowArrow —— 卡片间的流向箭头（竖线+下箭头），营造思维导图式操作动线；
//   RatioPill —— 沙色胶囊徽标，突出遗传比例数字。
//
// ⚠️ 红线：本文件组件直接消费 AppColors/AppText 静态 token，
// 严禁 const 实例化（widget 实例复用触发 Element identical 短路，
// 主题切换后颜色永久冻结——白底白字事故根因，见 b8b78c2/cdb4ebc）。

import 'package:flutter/material.dart';

import '../theme.dart';

/// 步骤卡片：左侧序号圆点 + 标题/副标题（+ 可选尾部徽标）+ 内容区。
class StepCard extends StatelessWidget {
  const StepCard({
    super.key,
    required this.step,
    required this.title,
    this.subtitle,
    this.trailing,
    this.dimmed = false,
    required this.child,
  });

  /// 序号（圆点内数字）；传 0 表示不显示序号的纯分区卡。
  final int step;
  final String title;
  final String? subtitle;
  final Widget? trailing;

  /// 未激活态（如结果尚未产生）：序号点降级为钢灰色。
  final bool dimmed;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final dotColor = dimmed ? AppColors.steel : AppColors.teal;
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppTheme.radiusCard),
        border: Border.all(color: AppColors.border.withValues(alpha: 0.6)),
        boxShadow: AppColors.cardShadow,
      ),
      child: Material(
        // ListTile/InkWell 类子孩子的墨水效果画在最近 Material 祖先上；
        // 卡片装饰底会挡住它们——透明 Material 只提供画布不改颜色。
        type: MaterialType.transparency,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 15, 18, 0),
            child: Row(
              children: [
                if (step > 0) ...[
                  Container(
                    width: 26,
                    height: 26,
                    alignment: Alignment.center,
                    decoration:
                        BoxDecoration(color: dotColor, shape: BoxShape.circle),
                    child: Text(
                      '$step',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                        height: 1.1,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                ],
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
                if (trailing != null) ...[
                  const SizedBox(width: 8),
                  trailing!,
                ],
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 11, 18, 0),
            child: Divider(
                height: 1, color: AppColors.border.withValues(alpha: 0.5)),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 13, 18, 17),
            child: child,
          ),
        ],
        ),
      ),
    );
  }
}

/// 步骤卡之间的流向箭头：竖线 + 下箭头，营造思维导图式流程感。
class FlowArrow extends StatelessWidget {
  const FlowArrow({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Column(
        children: [
          Container(width: 2, height: 9, color: AppColors.border),
          Icon(Icons.keyboard_arrow_down_rounded,
              size: 22, color: AppColors.teal),
        ],
      ),
    );
  }
}

/// 比例胶囊徽标：沙色底，突出遗传比例数字。
class RatioPill extends StatelessWidget {
  const RatioPill({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.sand.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppColors.sand.withValues(alpha: 0.45)),
      ),
      child: Text(
        text,
        style: AppText.caption.copyWith(
          color: AppColors.sand,
          fontWeight: FontWeight.w700,
          fontFamily: AppFonts.mono,
          fontFamilyFallback: AppFonts.monoFallback,
        ),
      ),
    );
  }
}
