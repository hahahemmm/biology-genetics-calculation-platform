// dna_ligase_bond_exercise.dart —— DNA 连接酶成键位置辨析
//
// 只处理一个稳定的高中概念：氢键负责碱基互补配对；DNA 连接酶催化
// DNA 骨架缺口处的磷酸二酯键形成。文献证据由 KnowledgeLab 离线筛选。

import 'package:flutter/material.dart';

import '../../theme.dart';
import '../../ui/tex_formula.dart';

enum _BondChoice { hydrogen, phosphodiester }

class DnaLigaseBondExercise extends StatefulWidget {
  const DnaLigaseBondExercise({super.key, this.onShowEvidence});

  final VoidCallback? onShowEvidence;

  @override
  State<DnaLigaseBondExercise> createState() => _DnaLigaseBondExerciseState();
}

class _DnaLigaseBondExerciseState extends State<DnaLigaseBondExercise> {
  _BondChoice? _selected;

  void _choose(_BondChoice choice) => setState(() => _selected = choice);

  @override
  Widget build(BuildContext context) {
    final correct = _selected == _BondChoice.phosphodiester;
    return Container(
      key: const Key('dna-ligase-bond-exercise'),
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
              Icon(Icons.link, size: 21, color: AppColors.teal),
              const SizedBox(width: 8),
              Expanded(child: Text('DNA 连接酶连接哪种化学键？', style: AppText.label)),
            ],
          ),
          const SizedBox(height: 8),
          Text('先判断连接发生在碱基之间还是 DNA 骨架缺口，再选择。两个选项都可以重选。', style: AppText.body),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                key: const Key('dna-ligase-hydrogen-bond'),
                onPressed: () => _choose(_BondChoice.hydrogen),
                icon: Icon(
                  _selected == _BondChoice.hydrogen
                      ? Icons.cancel_outlined
                      : Icons.hub_outlined,
                  size: 18,
                ),
                label: const Text('碱基对之间的氢键'),
              ),
              OutlinedButton.icon(
                key: const Key('dna-ligase-phosphodiester-bond'),
                onPressed: () => _choose(_BondChoice.phosphodiester),
                icon: Icon(
                  correct ? Icons.check_circle_outline : Icons.link,
                  size: 18,
                ),
                label: const Text('DNA 骨架缺口处的磷酸二酯键'),
              ),
            ],
          ),
          if (_selected != null) ...[
            const SizedBox(height: 12),
            Semantics(
              container: true,
              liveRegion: true,
              child: Container(
                key: const Key('dna-ligase-feedback'),
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
                  correct
                      ? '正确。DNA 连接酶催化 DNA 骨架缺口处的 3′-OH 与 5′-磷酸形成磷酸二酯键，封闭缺口；不是连接碱基对之间的氢键。'
                      : '再想一想：氢键负责碱基互补配对，不是连接酶催化的骨架共价连接。请重新选择。',
                  style: AppText.body.copyWith(
                    color: correct ? AppColors.tealDark : AppColors.sand,
                  ),
                ),
              ),
            ),
          ],
          if (correct) ...[
            const SizedBox(height: 12),
            Text('成键位置（概念示意，非完整反应计量）', style: AppText.caption),
            const TexFormula(
              tex: r"3^{\prime}\mathrm{-OH}+5^{\prime}\mathrm{-PO_4}\xrightarrow{\mathrm{DNA\ ligase}}\mathrm{phosphodiester\ bond}",
              fallback: '3′-OH + 5′-磷酸 → 磷酸二酯键',
              semanticsLabel: '三撇羟基与五撇磷酸在 DNA 连接酶作用下形成磷酸二酯键',
            ),
          ],
          if (widget.onShowEvidence != null) ...[
            const SizedBox(height: 8),
            ActionChip(
              avatar: const Icon(Icons.menu_book_outlined, size: 17),
              label: const Text('查看连接酶证据'),
              onPressed: widget.onShowEvidence,
            ),
          ],
        ],
      ),
    );
  }
}
