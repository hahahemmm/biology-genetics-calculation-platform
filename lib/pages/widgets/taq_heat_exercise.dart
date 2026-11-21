// taq_heat_exercise.dart —— Taq DNA 聚合酶耐热性质辨析
//
// 只处理适合高中 PCR 的稳定概念：耐热性使反应能在较高温度进行，
// 不等于温度越高越好、永不失活，也不把高温变性误写成酶切割 DNA。

import 'package:flutter/material.dart';

import '../../theme.dart';
import '../../ui/tex_formula.dart';

enum _TaqChoice { heatStable, hotter, denaturation }

class TaqHeatExercise extends StatefulWidget {
  const TaqHeatExercise({super.key, this.onShowEvidence});

  final VoidCallback? onShowEvidence;

  @override
  State<TaqHeatExercise> createState() => _TaqHeatExerciseState();
}

class _TaqHeatExerciseState extends State<TaqHeatExercise> {
  _TaqChoice? _selected;

  void _choose(_TaqChoice choice) => setState(() => _selected = choice);

  @override
  Widget build(BuildContext context) {
    final correct = _selected == _TaqChoice.heatStable;
    final feedback = switch (_selected) {
      _TaqChoice.heatStable =>
        '正确。Taq DNA 聚合酶的耐热性质使 PCR 能在较高温度进行，并适应反复温度循环；这不等于温度越高越好或永远不会失活。',
      _TaqChoice.hotter => '再想一想：耐热不等于温度越高越好，也不等于永远不会失活。PCR 需要按规程控制各阶段温度。',
      _TaqChoice.denaturation =>
        '再想一想：高温变性与 Taq 的延伸合成是不同事件，不能说 Taq 通过切割 DNA 骨架使双链变性。',
      null => null,
    };
    return Container(
      key: const Key('taq-heat-stable-exercise'),
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
              Icon(Icons.thermostat, size: 21, color: AppColors.teal),
              const SizedBox(width: 8),
              Expanded(
                child: Text('Taq DNA 聚合酶为什么适合 PCR？', style: AppText.label),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text('选择最准确的解释。两个误区都可以点选，再重新选择。', style: AppText.body),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                key: const Key('taq-heat-stable-choice'),
                onPressed: () => _choose(_TaqChoice.heatStable),
                icon: Icon(
                  correct ? Icons.check_circle_outline : Icons.thermostat,
                  size: 18,
                ),
                label: const Text('耐热性质适应较高温度的循环反应'),
              ),
              OutlinedButton.icon(
                key: const Key('taq-hotter-choice'),
                onPressed: () => _choose(_TaqChoice.hotter),
                icon: Icon(
                  _selected == _TaqChoice.hotter
                      ? Icons.cancel_outlined
                      : Icons.local_fire_department_outlined,
                  size: 18,
                ),
                label: const Text('温度越高，Taq 活性一定越强'),
              ),
              OutlinedButton.icon(
                key: const Key('taq-denaturation-choice'),
                onPressed: () => _choose(_TaqChoice.denaturation),
                icon: Icon(
                  _selected == _TaqChoice.denaturation
                      ? Icons.cancel_outlined
                      : Icons.content_cut,
                  size: 18,
                ),
                label: const Text('Taq 切割 DNA 骨架使双链变性'),
              ),
            ],
          ),
          if (feedback != null) ...[
            const SizedBox(height: 12),
            Semantics(
              container: true,
              liveRegion: true,
              child: Container(
                key: const Key('taq-heat-feedback'),
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
            Text('Taq 在延伸阶段合成新 DNA 链的方向', style: AppText.caption),
            const TexFormula(
              tex: r"5^{\prime}\longrightarrow3^{\prime}",
              fallback: '5′ → 3′',
              semanticsLabel: 'Taq DNA 聚合酶在延伸阶段沿五撇到三撇方向合成 DNA',
            ),
          ],
          if (widget.onShowEvidence != null) ...[
            const SizedBox(height: 8),
            ActionChip(
              avatar: const Icon(Icons.menu_book_outlined, size: 17),
              label: const Text('查看 Taq 证据'),
              onPressed: widget.onShowEvidence,
            ),
          ],
        ],
      ),
    );
  }
}
