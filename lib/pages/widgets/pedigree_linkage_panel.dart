// pedigree_linkage_panel.dart —— 系谱页连锁互换结果区块（2.3 重构抽取）
//
// 从 genetic_pedigree_page.dart 抽出，纯展示组件：控制器与结果态由页面
// 持有并传入。行为与抽取前逐行一致（「计算子代」「配子分布」等文案
// 是测试依赖）。

import 'package:flutter/material.dart';

import '../../engine/linkage_engine.dart';
import '../../theme.dart';
import 'linkage_widgets.dart';

class PedigreeLinkagePanel extends StatelessWidget {
  const PedigreeLinkagePanel({
    super.key,
    required this.p1Ctrl,
    required this.p2Ctrl,
    required this.rCtrl,
    required this.result,
    required this.error,
    required this.onCompute,
  });

  final TextEditingController p1Ctrl;
  final TextEditingController p2Ctrl;
  final TextEditingController rCtrl;
  final LinkageResult? result;
  final String? error;

  /// 「计算子代」/ 回车 / 案例速选后触发（页面负责引擎计算+setState）。
  final VoidCallback onCompute;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          Expanded(
            child: TextField(
              controller: p1Ctrl,
              style: AppText.genotype,
              decoration: const InputDecoration(
                  isDense: true, labelText: '亲本 1', hintText: 'AB/ab'),
              onSubmitted: (_) => onCompute(),
            ),
          ),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 8),
            child: Icon(Icons.close, size: 16, color: AppColors.steel),
          ),
          Expanded(
            child: TextField(
              controller: p2Ctrl,
              style: AppText.genotype,
              decoration: const InputDecoration(
                  isDense: true, labelText: '亲本 2', hintText: 'ab/ab（测交）'),
              onSubmitted: (_) => onCompute(),
            ),
          ),
        ]),
        const SizedBox(height: 6),
        TextField(
          controller: rCtrl,
          style: AppText.genotype,
          decoration: const InputDecoration(
              isDense: true,
              labelText: '交换值 r',
              hintText: '0.2 / 20% / 1/5，范围 0–50%'),
          onSubmitted: (_) => onCompute(),
        ),
        const SizedBox(height: 6),
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton.icon(
            onPressed: onCompute,
            icon: const Icon(Icons.calculate_outlined, size: 16),
            label: const Text('计算子代'),
            style: FilledButton.styleFrom(
                minimumSize: const Size(0, 34),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap),
          ),
        ),
        if (error != null) ...[
          const SizedBox(height: 6),
          Text(error!,
              style: AppText.caption.copyWith(color: AppColors.lethal)),
        ],
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final p in linkagePresets)
              // 面板 248px 内容宽放不下最长案例名（真实/Ahem 字体均溢出），
              // 逐芯片 scaleDown 收缩（内部 Row 无 flex，可安全缩放）。
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: LinkagePresetChip(
                  preset: p,
                  onTap: () {
                    p1Ctrl.text = p.p1;
                    p2Ctrl.text = p.p2;
                    rCtrl.text = p.r;
                    onCompute();
                  },
                ),
              ),
          ],
        ),
        if (result != null) ...[
          const SizedBox(height: 10),
          // 结果区块：LinkageGameteTable / LinkagePhenotypeCard 已改为宽度
          // 自适应（Expanded + FittedBox scaleDown），面板自然宽直接渲染，
          // 不再用 340px 定宽 + 水平滚动（那会把分数/交换值截到可视区外，
          // 用户报「连锁互换后 UI 显示不全」）。
          AppSectionHeader(
            '配子分布',
            trailing: Flexible(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerRight,
                child: Text(
                  '交换值 ${result!.recombination}'
                  '（${result!.recombination.toPercent()}）',
                  style: AppText.monoSmall.copyWith(color: AppColors.steel),
                ),
              ),
            ),
          ),
          LinkageGameteTable(result: result!),
          const SizedBox(height: 8),
          AppSectionHeader('子代表型'),
          LinkagePhenotypeCard(result: result!),
        ],
      ],
    );
  }
}
