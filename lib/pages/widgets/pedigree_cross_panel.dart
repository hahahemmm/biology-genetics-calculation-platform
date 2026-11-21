// pedigree_cross_panel.dart —— 系谱页右侧杂交计算面板（2.3 重构抽取）
//
// 从 genetic_pedigree_page.dart 抽出，纯展示组件：TextEditingController
// 与结果态由页面持有并传入，本组件不持有状态。
// 行为与抽取前逐行一致（「开始计算」「尚未计算」等文案是测试依赖）。

import 'package:flutter/material.dart';

import '../../engine/kaoji_calc.dart';
import '../../theme.dart';
import '../../ui/step_card.dart';
import 'pedigree_mini_calcs.dart';

class PedigreeCrossPanel extends StatelessWidget {
  const PedigreeCrossPanel({
    super.key,
    required this.overlay,
    required this.p1Ctrl,
    required this.p2Ctrl,
    required this.nextSlot,
    required this.result,
    required this.snapshot,
    required this.onClose,
    required this.onStart,
    this.onOpenInCalculator,
  });

  final bool overlay;
  final TextEditingController p1Ctrl;
  final TextEditingController p2Ctrl;

  /// 「下一个填入：亲本 N」提示。
  final int nextSlot;
  final AutoCrossResult? result;

  /// 「开始计算」时输入的快照（用于过期提示）。
  final String snapshot;
  final VoidCallback onClose;
  final VoidCallback onStart;

  /// v2.19.15 A 桥正向：算完后「在 9331 完整展开」——跳到 9331 页
  /// 双基因 tab 并回填同样 p1/p2（完整棋盘/步骤/方法对比，内嵌面板
  /// 只有表型比）。null = 不显示按钮（独立测试/预览用）。
  final VoidCallback? onOpenInCalculator;

  @override
  Widget build(BuildContext context) {
    final r = result;
    final stale = r != null &&
        r.result != null &&
        snapshot != '${p1Ctrl.text.trim()} × ${p2Ctrl.text.trim()}';
    return Container(
      width: 300,
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border(left: BorderSide(color: AppColors.border)),
        boxShadow: overlay ? AppColors.cardShadow : null,
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.calculate_outlined, size: 18, color: AppColors.teal),
                const SizedBox(width: 8),
                Expanded(child: Text('杂交计算', style: AppText.sectionTitle)),
                IconButton(
                  tooltip: '关闭面板',
                  onPressed: onClose,
                  icon: Icon(Icons.close, size: 18, color: AppColors.steel),
                ),
              ],
            ),
            Text('9331 及 n 对基因通用 · 支持一倍体/二倍体自动识别',
                style: AppText.caption),
            const SizedBox(height: 4),
            Text('点画布元素轮流填入亲本框；只有点「开始计算」才会计算',
                style: AppText.caption.copyWith(color: AppColors.steel)),
            const SizedBox(height: 12),
            TextField(
              controller: p1Ctrl,
              style: AppText.genotype,
              decoration: const InputDecoration(
                labelText: '亲本 1',
                hintText: '如 AaBb',
                isDense: true,
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: p2Ctrl,
              style: AppText.genotype,
              decoration: const InputDecoration(
                labelText: '亲本 2',
                hintText: '如 AaBb',
                isDense: true,
              ),
              onSubmitted: (_) => onStart(),
            ),
            const SizedBox(height: 6),
            Text('下一个填入：亲本 $nextSlot',
                style: AppText.caption.copyWith(color: AppColors.steel)),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: onStart,
                icon: const Icon(Icons.play_arrow_rounded, size: 20),
                label: const Text('开始计算'),
              ),
            ),
            const SizedBox(height: 12),
            if (r == null)
              Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 18),
                  child: Text('尚未计算',
                      style: AppText.caption.copyWith(color: AppColors.steel)),
                ),
              )
            else if (r.error != null)
              _crossBanner(r.error!, AppColors.lethal, Icons.error_outline)
            else if (r.notice != null)
              _crossBanner(r.notice!, AppColors.sand, Icons.warning_amber_rounded)
            else
              _crossResultBody(r, stale),
            // v2.19.19 多计算器竖滚面板：9331 通用块之外追加单基因速算 /
            // 连锁互换速算（用户记忆复原：面板曾是一整层可滚动的多计算器
            // 框架），迷你块与 9331 页同引擎同算法。
            const SizedBox(height: 20),
            Divider(color: AppColors.border.withValues(alpha: 0.6)),
            const SizedBox(height: 16),
            // v2.19.20 禁 const：本面板消费 AppColors token——const 实例
            // canonicalize 后与旧 widget identical，Element.update 短路
            // 永不 rebuild，主题切换时文字色永久冻结（v2.2 白底白字
            // 同型事故复发：identical 短路；main.dart 页面列表注释同款
            // 纪律「消费 AppColors token 故不得 const 实例化」）。
            MonoMiniCalc(),
            const SizedBox(height: 20),
            Divider(color: AppColors.border.withValues(alpha: 0.6)),
            const SizedBox(height: 16),
            LinkageMiniCalc(),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  Widget _crossBanner(String msg, Color color, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppTheme.radiusInput),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 10),
          Expanded(
              child: Text(msg, style: AppText.caption.copyWith(color: color))),
        ],
      ),
    );
  }

  Widget _crossResultBody(AutoCrossResult r, bool stale) {
    final res = r.result!;
    final parts = res.phenotypeRatio.parts;
    final total = parts.fold<int>(0, (a, b) => a + b);
    final ploidyLabel = r.ploidy == 1 ? '一倍体' : '二倍体';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            AppChip(res.variantName, icon: Icons.auto_awesome),
            AppChip('$ploidyLabel · ${r.loci} 对基因'),
          ],
        ),
        const SizedBox(height: 6),
        Text('基于 $snapshot',
            style: AppText.caption.copyWith(color: AppColors.steel)),
        if (stale)
          Text('输入已修改，结果来自上次「开始计算」',
              style: AppText.caption.copyWith(color: AppColors.sand)),
        Divider(height: 20, color: AppColors.border.withValues(alpha: 0.6)),
        Text('表型比例', style: AppText.label),
        const SizedBox(height: 2),
        Text(res.phenotypeRatio.toString(), style: AppText.monoFigure),
        const SizedBox(height: 10),
        for (var i = 0; i < res.phenotypeLabels.length; i++) ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: AppColors.canvas,
              borderRadius: BorderRadius.circular(8),
              border:
                  Border.all(color: AppColors.border.withValues(alpha: 0.5)),
            ),
            child: Row(
              children: [
                Expanded(
                    child: Text('表型 ${res.phenotypeLabels[i]}',
                        style: AppText.body)),
                Text('${parts[i]}/$total',
                    style: AppText.caption.copyWith(color: AppColors.steel)),
                const SizedBox(width: 8),
                RatioPill(text: '${parts[i]}'),
              ],
            ),
          ),
          const SizedBox(height: 6),
        ],
        Divider(height: 20, color: AppColors.border.withValues(alpha: 0.6)),
        Text('P1 配子', style: AppText.caption),
        Text(res.gametesP1.join('  '), style: AppText.monoSmall),
        const SizedBox(height: 4),
        Text('P2 配子', style: AppText.caption),
        Text(res.gametesP2.join('  '), style: AppText.monoSmall),
        const SizedBox(height: 8),
        Text('基因型明细（${res.genotypeLabels.length} 类）', style: AppText.label),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: res.genotypeLabels
              .take(48)
              .map((g) => Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppColors.canvas,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Text(g, style: AppText.monoSmall),
                  ))
              .toList(),
        ),
        if (res.genotypeLabels.length > 48)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text('…仅展示前 48 类',
                style: AppText.caption.copyWith(color: AppColors.steel)),
          ),
        // v2.19.15 A 桥正向：内嵌面板只有表型比/配子/基因型明细；
        // 完整棋盘格、步骤流程、方法对比、连锁互换在 9331 页——
        // 算完一键跳过去并回填同样 p1/p2，回程横幅保证一键跳回。
        if (onOpenInCalculator != null) ...[
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: onOpenInCalculator,
              icon: const Icon(Icons.open_in_new_rounded, size: 18),
              label: const Text('在 9331 完整展开'),
            ),
          ),
        ],
      ],
    );
  }
}
