// primer_extension_exercise.dart —— PCR 引物末端与新链延伸方向辨析
//
// 只讲稳定概念：延伸发生在引物的 3′ 端，新链按 5′→3′ 合成。
// 不把合成方向误写成所有酶促反应的方向，也不混淆新链与模板链。

import 'package:flutter/material.dart';

import '../../theme.dart';
import '../../ui/tex_formula.dart';

enum _PrimerChoice { threeOh, fiveEnd, middle }

class PrimerExtensionExercise extends StatefulWidget {
  const PrimerExtensionExercise({super.key, this.onShowEvidence});

  final VoidCallback? onShowEvidence;

  @override
  State<PrimerExtensionExercise> createState() =>
      _PrimerExtensionExerciseState();
}

class _PrimerExtensionExerciseState extends State<PrimerExtensionExercise> {
  _PrimerChoice? _selected;

  void _choose(_PrimerChoice choice) => setState(() => _selected = choice);

  @override
  Widget build(BuildContext context) {
    final correct = _selected == _PrimerChoice.threeOh;
    final feedback = switch (_selected) {
      _PrimerChoice.threeOh => '正确。引物为延伸提供起点，新的脱氧核苷酸接到游离 3′-OH 端，所以新链按 5′→3′ 方向延伸；与之配对的模板链按 3′→5′ 方向被读取。',
      _PrimerChoice.fiveEnd => '再想一想：延伸发生在引物的 3′ 端，不是 5′-磷酸端；新链的合成方向应按新链自身书写。',
      _PrimerChoice.middle =>
        '再想一想：脱氧核苷酸不是从引物中部随机接入，而是在已有引物的 3′ 末端继续延伸，方向并非不重要。',
      null => null,
    };
    return Container(
      key: const Key('primer-extension-exercise'),
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
              Icon(Icons.more_horiz, size: 21, color: AppColors.teal),
              const SizedBox(width: 8),
              Expanded(
                child: Text('PCR 引物为什么需要游离 3′-OH？', style: AppText.label),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text('选择对延伸末端与新链方向最准确的描述。', style: AppText.body),
          const SizedBox(height: 12),
          _choiceButton(
            key: const Key('primer-three-oh-choice'),
            icon: correct ? Icons.check_circle_outline : Icons.arrow_forward,
            label: '从引物的 3′-OH 端延伸，新链按 5′→3′ 合成',
            onPressed: () => _choose(_PrimerChoice.threeOh),
          ),
          const SizedBox(height: 8),
          _choiceButton(
            key: const Key('primer-five-end-choice'),
            icon: _selected == _PrimerChoice.fiveEnd
                ? Icons.cancel_outlined
                : Icons.arrow_back,
            label: '从引物的 5′-磷酸端延伸，新链按 3′→5′ 合成',
            onPressed: () => _choose(_PrimerChoice.fiveEnd),
          ),
          const SizedBox(height: 8),
          _choiceButton(
            key: const Key('primer-middle-choice'),
            icon: _selected == _PrimerChoice.middle
                ? Icons.cancel_outlined
                : Icons.join_inner,
            label: '从引物中部接入新碱基，延伸方向不重要',
            onPressed: () => _choose(_PrimerChoice.middle),
          ),
          if (feedback != null) ...[
            const SizedBox(height: 12),
            Semantics(
              container: true,
              liveRegion: true,
              child: Container(
                key: const Key('primer-extension-feedback'),
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
            Text('引物方向与延伸端（概念示意，非完整反应计量）', style: AppText.caption),
            const TexFormula(
              tex: r"\mathrm{Primer}\!:\;5^{\prime}\longrightarrow3^{\prime}-\mathrm{OH}",
              fallback: '引物：5′ → 3′-OH',
              semanticsLabel: '新脱氧核苷酸接到引物三撇羟基端，新链沿五撇到三撇方向延伸',
            ),
            const SizedBox(height: 6),
            Text('注意：5′→3′ 是此处新链的延伸方向，不是所有酶促反应的方向。', style: AppText.caption),
          ],
          if (widget.onShowEvidence != null) ...[
            const SizedBox(height: 8),
            ActionChip(
              avatar: const Icon(Icons.menu_book_outlined, size: 17),
              label: const Text('查看引物证据'),
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
