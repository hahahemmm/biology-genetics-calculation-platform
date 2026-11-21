// pcr_cycle_exercise.dart —— 经典 PCR 变性、退火、延伸顺序辨析
//
// 只讲稳定的三步顺序，不把某组温度或时间写成所有 PCR 的通用规程。

import 'package:flutter/material.dart';

import '../../theme.dart';
import '../../ui/tex_formula.dart';

enum _PcrCycleChoice { correct, annealFirst, extensionFirst }

class PcrCycleExercise extends StatefulWidget {
  const PcrCycleExercise({super.key, this.onShowEvidence});

  final VoidCallback? onShowEvidence;

  @override
  State<PcrCycleExercise> createState() => _PcrCycleExerciseState();
}

class _PcrCycleExerciseState extends State<PcrCycleExercise> {
  _PcrCycleChoice? _selected;

  void _choose(_PcrCycleChoice choice) => setState(() => _selected = choice);

  @override
  Widget build(BuildContext context) {
    final correct = _selected == _PcrCycleChoice.correct;
    final feedback = switch (_selected) {
      _PcrCycleChoice.correct =>
        '正确。经典 PCR 按变性→退火→延伸反复循环：双链分开后，引物与互补序列配对，耐热 DNA 聚合酶再延伸引物、合成新链。',
      _PcrCycleChoice.annealFirst =>
        '再想一想：经典 PCR 先使双链 DNA 变性分开，再降温让引物退火，不能跳过双链分离直接开始退火。',
      _PcrCycleChoice.extensionFirst =>
        '再想一想：延伸发生在引物完成退火之后，不能在一个新循环开始时跳过变性和退火。',
      null => null,
    };
    return Container(
      key: const Key('pcr-cycle-exercise'),
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
              Icon(Icons.loop, size: 21, color: AppColors.teal),
              const SizedBox(width: 8),
              Expanded(child: Text('PCR 温度循环的三步顺序是什么？', style: AppText.label)),
            ],
          ),
          const SizedBox(height: 8),
          Text('选择经典 PCR 一个循环中三步反应的正确顺序。', style: AppText.body),
          const SizedBox(height: 12),
          _choiceButton(
            key: const Key('pcr-cycle-correct-choice'),
            icon: correct ? Icons.check_circle_outline : Icons.loop,
            label: '变性 → 退火 → 延伸',
            onPressed: () => _choose(_PcrCycleChoice.correct),
          ),
          const SizedBox(height: 8),
          _choiceButton(
            key: const Key('pcr-cycle-anneal-first-choice'),
            icon: _selected == _PcrCycleChoice.annealFirst
                ? Icons.cancel_outlined
                : Icons.vertical_align_bottom,
            label: '退火 → 变性 → 延伸',
            onPressed: () => _choose(_PcrCycleChoice.annealFirst),
          ),
          const SizedBox(height: 8),
          _choiceButton(
            key: const Key('pcr-cycle-extension-first-choice'),
            icon: _selected == _PcrCycleChoice.extensionFirst
                ? Icons.cancel_outlined
                : Icons.fast_forward,
            label: '延伸 → 退火 → 变性',
            onPressed: () => _choose(_PcrCycleChoice.extensionFirst),
          ),
          if (feedback != null) ...[
            const SizedBox(height: 12),
            Semantics(
              container: true,
              liveRegion: true,
              child: Container(
                key: const Key('pcr-cycle-feedback'),
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: (correct ? AppColors.teal : AppColors.sand).withValues(
                    alpha: 0.08,
                  ),
                  borderRadius: BorderRadius.circular(AppTheme.radiusInput),
                  border: Border.all(
                    color: (correct ? AppColors.teal : AppColors.sand)
                        .withValues(alpha: 0.4),
                  ),
                ),
                child: Text(
                  feedback,
                  style: AppText.body.copyWith(
                    color: correct ? AppColors.tealDark : AppColors.sand,
                  ),
                ),
              ),
            ),
          ],
          if (correct) ...[
            const SizedBox(height: 12),
            Text('经典 PCR 三步顺序', style: AppText.caption),
            const TexFormula(
              tex: r'\mathrm{Denaturation}\;\longrightarrow\;\mathrm{Annealing}\;\longrightarrow\;\mathrm{Extension}',
              fallback: '变性 → 退火 → 延伸',
              semanticsLabel: '经典 PCR 三步依次为变性、退火、延伸，并反复循环',
            ),
            const SizedBox(height: 6),
            Text(
              '具体温度和时间应依据酶、引物、模板与实验规程设置，不是所有 PCR 通用一组固定数值。',
              style: AppText.caption,
            ),
          ],
          if (widget.onShowEvidence != null) ...[
            const SizedBox(height: 8),
            ActionChip(
              avatar: const Icon(Icons.menu_book_outlined, size: 17),
              label: const Text('查看 PCR 循环证据'),
              onPressed: widget.onShowEvidence,
            ),
          ],
        ],
      ),
    );
  }

  Widget _choiceButton({
    required Key key,
    required IconData icon,
    required String label,
    required VoidCallback onPressed,
  }) => SizedBox(
    width: double.infinity,
    child: OutlinedButton(
      key: key,
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18),
          const SizedBox(width: 8),
          Expanded(child: Text(label)),
        ],
      ),
    ),
  );
}
