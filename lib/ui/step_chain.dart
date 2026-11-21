// step_chain.dart —— 推导链组件（v2.2 批次4 地基）
//
// 用图标/节点链呈现计算过程（思维链）：题干 → 中间量 → 结果。
// 纵向时间线：序号圆点 + 连接线 + 箭头；每节点含标题/公式(Mono)/说明。
// 纯 Flutter 零依赖（不引 graphview，避免新增包；确定性树状推导链
// 用纵向链最清晰，自由脑图场景再评估 graphview）。
//
// 主题安全：全部走 AppColors/AppText token（深浅色自动适配，
// 不产生白底白字）；无常驻动画（widget 测试可 pumpAndSettle）。

import 'package:flutter/material.dart';

import '../theme.dart';

/// 推导链中的一个节点。
class ChainStep {
  final String title; // 步骤标题（如「已知条件」「互补配对」「结果」）
  final String? formula; // 公式/数值（Mono 渲染，如 'A = T = 45'）
  final String? detail; // 说明文字（思维链解释）
  final IconData icon; // 节点图标（图标化呈现过程）
  const ChainStep({
    required this.title,
    this.formula,
    this.detail,
    this.icon = Icons.adjust,
  });

  /// 常用节点工厂。
  const ChainStep.input(String title, {String? formula, String? detail})
      : this(title: title, formula: formula, detail: detail,
            icon: Icons.input_outlined);
  const ChainStep.compute(String title, {String? formula, String? detail})
      : this(title: title, formula: formula, detail: detail,
            icon: Icons.calculate_outlined);
  const ChainStep.result(String title, {String? formula, String? detail})
      : this(title: title, formula: formula, detail: detail,
            icon: Icons.flag_outlined);
}

/// 推导链（纵向节点时间线）。
class StepChain extends StatelessWidget {
  final List<ChainStep> steps;
  const StepChain({super.key, required this.steps});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < steps.length; i++) ...[
          _StepNode(step: steps[i], index: i, isLast: i == steps.length - 1),
        ],
      ],
    );
  }
}

class _StepNode extends StatelessWidget {
  final ChainStep step;
  final int index;
  final bool isLast;
  _StepNode(
      {required this.step, required this.index, required this.isLast});

  @override
  Widget build(BuildContext context) {
    final isResult = index != 0 && isLast;
    final dotColor = isResult ? AppColors.sand : AppColors.teal;
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 左侧：图标圆点 + 连接线
          SizedBox(
            width: 36,
            child: Column(
              children: [
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: dotColor.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                    border: Border.all(color: dotColor, width: 1.2),
                  ),
                  child: Icon(step.icon, size: 15, color: dotColor),
                ),
                if (!isLast)
                  Expanded(
                    child: Container(
                      width: 1.5,
                      color: AppColors.border,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          // 右侧：节点内容
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: isLast ? 0 : 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 4),
                  Text(step.title,
                      style: AppText.label.copyWith(
                          color: isResult ? AppColors.sand : AppColors.ink,
                          fontWeight: FontWeight.w700)),
                  if (step.formula != null) ...[
                    const SizedBox(height: 3),
                    Text(step.formula!, style: AppText.monoFigure),
                  ],
                  if (step.detail != null) ...[
                    const SizedBox(height: 3),
                    Text(step.detail!, style: AppText.caption),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
