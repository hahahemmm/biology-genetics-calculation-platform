// pcr_amplification_exercise.dart —— PCR 循环数与理论扩增产物
//
// 只计算理想关系 N = N₀ × 2ⁿ；与 PcrResult 共用 pcrIdealProductCount，
// 不把理想份数包装成真实产量、浓度、荧光或条带亮度。

import 'package:flutter/material.dart';

import '../../engine/pcr_engine.dart';
import '../../theme.dart';
import '../../ui/tex_formula.dart';

class PcrAmplificationExercise extends StatefulWidget {
  const PcrAmplificationExercise({super.key, this.onShowEvidence});

  final VoidCallback? onShowEvidence;

  @override
  State<PcrAmplificationExercise> createState() =>
      _PcrAmplificationExerciseState();
}

class _PcrAmplificationExerciseState extends State<PcrAmplificationExercise> {
  static const _initialChoices = <int>[1, 3, 10];
  static const _cycleChoices = <int>[0, 1, 4, 5, 10, 20, 30];

  int _initialTemplates = 1;
  int _cycles = 0;

  @override
  Widget build(BuildContext context) {
    final product = pcrIdealProductCount(
      initialTemplates: _initialTemplates,
      cycles: _cycles,
    );
    final fold = BigInt.two.pow(_cycles);
    return Container(
      key: const Key('pcr-amplification-exercise'),
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
              Icon(Icons.functions, size: 21, color: AppColors.teal),
              const SizedBox(width: 8),
              Expanded(child: Text('PCR 循环数如何影响理论产物？', style: AppText.label)),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '选择初始模板份数 N₀ 与循环数 n。假设每个目标 DNA 分子每轮都加倍，观察理想指数关系。',
            style: AppText.body,
          ),
          const SizedBox(height: 12),
          Text('初始模板份数 N₀', style: AppText.caption),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              for (final initial in _initialChoices)
                ChoiceChip(
                  key: Key('pcr-amplification-initial-$initial'),
                  label: Text('$initial 份'),
                  selected: _initialTemplates == initial,
                  onSelected: (_) =>
                      setState(() => _initialTemplates = initial),
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
                  key: Key('pcr-amplification-cycle-$cycles'),
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
            child: Container(
              key: const Key('pcr-amplification-result'),
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
                  Text('理想产物：$product 份目标 DNA 分子', style: AppText.label),
                  const SizedBox(height: 8),
                  TexFormula(
                    tex: 'N=$_initialTemplates\\times2^{$_cycles}=$product',
                    fallback: 'N = $_initialTemplates × 2^$_cycles = $product',
                    semanticsLabel:
                        '$_initialTemplates 份初始模板经过 $_cycles 次理想 PCR 循环得到 $product 份目标 DNA 分子',
                  ),
                  const SizedBox(height: 6),
                  Text('相对初始模板放大 $fold 倍。', style: AppText.caption),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            _cycles == 0
                ? '0 次循环尚未扩增，所以产物份数仍为初始的 $_initialTemplates 份。'
                : '辨误区：不是 $_initialTemplates × $_cycles = '
                      '${_initialTemplates * _cycles}。循环数在指数上，表示连续乘 $_cycles 次 2，而不是把循环数当作乘数。',
            style: AppText.body,
          ),
          const SizedBox(height: 8),
          Text(
            '模型边界：理想份数不等于真实 PCR 的产量、浓度、荧光强度或凝胶条带亮度；真实 PCR 存在效率损失与平台期。',
            style: AppText.caption,
          ),
          if (widget.onShowEvidence != null) ...[
            const SizedBox(height: 8),
            ActionChip(
              avatar: const Icon(Icons.menu_book_outlined, size: 17),
              label: const Text('查看理论扩增证据'),
              onPressed: widget.onShowEvidence,
            ),
          ],
        ],
      ),
    );
  }
}
