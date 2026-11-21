// pcr_efficiency_exercise.dart —— PCR 理想扩增与恒定效率假设对照
//
// 固定一份初始模板，对照 N₀×2ⁿ 与 N₀×(1+E)ⁿ。恒定效率只是
// 假设模型：不模拟效率变化、平台期或真实终点产量。

import 'package:flutter/material.dart';

import '../../engine/pcr_engine.dart';
import '../../theme.dart';
import '../../ui/tex_formula.dart';

class PcrEfficiencyExercise extends StatefulWidget {
  const PcrEfficiencyExercise({super.key, this.onShowEvidence});

  final VoidCallback? onShowEvidence;

  @override
  State<PcrEfficiencyExercise> createState() => _PcrEfficiencyExerciseState();
}

class _PcrEfficiencyExerciseState extends State<PcrEfficiencyExercise> {
  static const _efficiencyChoices = <double>[1, 0.9, 0.8, 0.5];
  static const _cycleChoices = <int>[0, 4, 10];

  double _efficiency = 0.9;
  int _cycles = 4;

  @override
  Widget build(BuildContext context) {
    final ideal = pcrIdealProductCount(cycles: _cycles);
    final product = pcrConstantEfficiencyProduct(
      cycles: _cycles,
      efficiency: _efficiency,
    );
    final efficiencyPercent = (_efficiency * 100).round();
    final productText = product.toStringAsFixed(4);
    final ratioText = (product / ideal.toDouble() * 100).toStringAsFixed(2);
    final efficiencyText = _efficiency.toStringAsFixed(2);
    final foldText = (1 + _efficiency).toStringAsFixed(1);

    return Container(
      key: const Key('pcr-efficiency-exercise'),
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surfaceLow,
        borderRadius: BorderRadius.circular(AppTheme.radiusCard),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.compare_arrows, size: 21, color: AppColors.teal),
              const SizedBox(width: 8),
              Expanded(child: Text('PCR 理想扩增与恒定效率对照', style: AppText.label)),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '固定初始模板 N₀ = 1 份。选择每轮恒定效率 E 与循环数 n，比较理想模型 N₀×2ⁿ 与假设模型 N₀×(1+E)ⁿ。',
            style: AppText.body,
          ),
          const SizedBox(height: 8),
          Text(
            '效率口径：100% 表示每轮加倍；90% 表示每轮变为 1.9 倍，而不是只保留原来的 90%。',
            style: AppText.caption,
          ),
          const SizedBox(height: 12),
          Text('每轮效率 E', style: AppText.caption),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              for (final efficiency in _efficiencyChoices)
                ChoiceChip(
                  key: Key(
                    'pcr-efficiency-percent-${(efficiency * 100).round()}',
                  ),
                  label: Text('${(efficiency * 100).round()}%'),
                  selected: _efficiency == efficiency,
                  onSelected: (_) => setState(() => _efficiency = efficiency),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Text('循环数 n', style: AppText.caption),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              for (final cycles in _cycleChoices)
                ChoiceChip(
                  key: Key('pcr-efficiency-cycle-$cycles'),
                  label: Text('$cycles 次'),
                  selected: _cycles == cycles,
                  onSelected: (_) => setState(() => _cycles = cycles),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Semantics(
            container: true,
            liveRegion: true,
            label:
                '每轮效率 $efficiencyPercent%，经过 $_cycles 次循环：理想模型 $ideal 份；恒定效率模型 $productText 份，约为理想的 $ratioText%',
            child: Container(
              key: const Key('pcr-efficiency-result'),
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.tealWash,
                borderRadius: BorderRadius.circular(AppTheme.radiusInput),
                border: Border.all(color: AppColors.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('理想模型：$ideal 份', style: AppText.label),
                  const SizedBox(height: 4),
                  TexFormula(
                    tex: 'N_{\\mathrm{ideal}}=1\\times2^{$_cycles}=$ideal',
                    fallback: 'N_ideal = 1 × 2^$_cycles = $ideal',
                    semanticsLabel: '一份初始模板经过 $_cycles 次理想循环得到 $ideal 份',
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '恒定效率模型：$productText 份（约为理想的 $ratioText%）',
                    style: AppText.label,
                  ),
                  const SizedBox(height: 4),
                  TexFormula(
                    tex:
                        'N_E=1\\times(1+$efficiencyText)^{$_cycles}=$productText',
                    fallback:
                        'N_E = 1 × (1 + $efficiencyText)^$_cycles = $productText',
                    semanticsLabel:
                        '每轮效率 $efficiencyPercent%，经过 $_cycles 次循环得到 $productText 份',
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            '当前每轮效率 $efficiencyPercent%，即每轮变为 $foldText 倍。效率为 0% 或循环为 0 次时，仍保留初始的 1 份模板。',
            style: AppText.body,
          ),
          const SizedBox(height: 8),
          Text(
            '模型边界：本卡没有模拟平台期，也不能用于外推真实终点产量；真实 PCR 的每轮效率会变化。',
            style: AppText.caption,
          ),
          if (widget.onShowEvidence != null) ...[
            const SizedBox(height: 8),
            ActionChip(
              avatar: const Icon(Icons.menu_book_outlined, size: 17),
              label: const Text('查看效率与平台期证据'),
              onPressed: widget.onShowEvidence,
            ),
          ],
        ],
      ),
    );
  }
}
