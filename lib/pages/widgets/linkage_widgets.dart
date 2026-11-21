// linkage_widgets.dart —— 连锁互换公共展示组件
//
// 由 linkage_tab.dart 抽取（Task 1：抽取公共连锁互换组件），供 LinkageTab 与
// 后续图谱页复用。纯 UI 展示，引擎逻辑全部在 lib/engine/linkage_engine.dart。
// 视觉遵循 docs/ARCHITECTURE.md 的设计约定：基因型/比例/概率一律等宽字体，结果区用 border-top 分隔。

import 'package:flutter/material.dart';

import '../../engine/fraction.dart';
import '../../engine/linkage_engine.dart';
import '../../theme.dart';

/// 经典连锁案例（教学高频）。
const linkagePresets = <({String name, String p1, String p2, String r, String note})>[
  (
    name: '完全连锁测交',
    p1: 'AB/ab',
    p2: 'ab/ab',
    r: '0',
    note: '不发生互换：只产 AB、ab 两种配子，测交后代 1:1',
  ),
  (
    name: 'r=20% 测交',
    p1: 'AB/ab',
    p2: 'ab/ab',
    r: '1/5',
    note: '亲本型多、重组型少：后代 4:4:1:1',
  ),
  (
    name: '相斥相 r=20%',
    p1: 'Ab/aB',
    p2: 'ab/ab',
    r: '20%',
    note: '相引相换到另一条染色体上，亲本型变成 Ab、aB',
  ),
  (
    name: 'r=50%（等价自由组合）',
    p1: 'AB/ab',
    p2: 'ab/ab',
    r: '1/2',
    note: '四种配子各占 1/4，与非同源染色体上的自由组合无法区分',
  ),
  (
    name: '自交 r=20%',
    p1: 'AB/ab',
    p2: 'AB/ab',
    r: '1/5',
    note: '双杂合自交：表型比不再是 9:3:3:1',
  ),
];

class LinkagePresetChip extends StatelessWidget {
  final ({String name, String p1, String p2, String r, String note}) preset;
  final VoidCallback onTap;
  LinkagePresetChip(
      {super.key, required this.preset, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: preset.note,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Container(
          // v2.19.18：rail 内容宽仅 248——chip 限宽 + 名称省略号防溢出。
          constraints: const BoxConstraints(maxWidth: 216),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(preset.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.caption.copyWith(color: AppColors.graphite)),
              ),
              const SizedBox(width: 6),
              Text('${preset.p1}×${preset.p2}',
                  style: AppText.monoSmall
                      .copyWith(fontSize: 11, color: AppColors.teal)),
            ],
          ),
        ),
      ),
    );
  }
}

/// 双亲配子分布表（亲本型 / 重组型标注）。
class LinkageGameteTable extends StatelessWidget {
  final LinkageResult result;
  const LinkageGameteTable({super.key, required this.result});

  @override
  Widget build(BuildContext context) {
    return Container(
      // v2.2 UI 推广：Card → canvas 底子区外壳（嵌进 StepCard 不双卡，
      // 系谱页侧栏内同样成立）
      decoration: BoxDecoration(
        color: AppColors.canvas,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border.withValues(alpha: 0.6)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          children: [
            _gameteBlock(
                '亲本 1（${result.parent1.label}）', result.parent1, result.gametesP1),
            const Divider(height: 1),
            _gameteBlock(
                '亲本 2（${result.parent2.label}）', result.parent2, result.gametesP2),
          ],
        ),
      ),
    );
  }

  Widget _gameteBlock(
      String title, LinkedParent parent, Map<String, Fraction> gametes) {
    final entries = gametes.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: AppText.label),
          const SizedBox(height: 6),
          for (final e in entries)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                children: [
                  // 宽度自适应：系谱页侧栏（约 248px）与计算器整页共用，
                  // 基因型占剩余弹性空间，尾部分数过窄时 scaleDown 收缩，
                  // 任何宽度都不截断（2.2 课堂重构修「连锁互换 UI 显示不全」）。
                  Expanded(
                    child: Text(e.key,
                        style: AppText.genotype,
                        overflow: TextOverflow.ellipsis),
                  ),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: (e.key == parent.hap1 || e.key == parent.hap2)
                          ? AppColors.tealWash
                          : AppColors.surface,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: (e.key == parent.hap1 || e.key == parent.hap2)
                            ? AppColors.teal
                            : AppColors.sand,
                      ),
                    ),
                    child: Text(
                      (e.key == parent.hap1 || e.key == parent.hap2)
                          ? '亲本型'
                          : '重组型',
                      style: AppText.monoSmall.copyWith(
                        fontSize: 11,
                        color: (e.key == parent.hap1 || e.key == parent.hap2)
                            ? AppColors.teal
                            : AppColors.sand,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerRight,
                      child: Text('${e.value}（${e.value.toPercent()}）',
                          style: AppText.monoSmall),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// 子代表型分布卡（整数比 + 实测交换值核对）。
class LinkagePhenotypeCard extends StatelessWidget {
  final LinkageResult result;
  const LinkagePhenotypeCard({super.key, required this.result});

  @override
  Widget build(BuildContext context) {
    final entries = result.phenotypes.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final ratio = result.phenotypeRatio;
    return Container(
      decoration: BoxDecoration(
        color: AppColors.tealWash,
        borderRadius: BorderRadius.circular(AppTheme.radiusCard),
        border: Border.all(color: AppColors.border),
      ),
      padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('表型整数比', style: AppText.sectionTitle),
            const SizedBox(height: 6),
            Text(
              ratio.join(' : '),
              style: AppText.monoFigure.copyWith(fontSize: 22),
            ),
            const SizedBox(height: 10),
            for (var i = 0; i < entries.length; i++)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  children: [
                    // 同配子行：宽度自适应，窄面板不截断。
                    Expanded(
                      child: Text(entries[i].key,
                          style: AppText.body,
                          overflow: TextOverflow.ellipsis),
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerRight,
                        child: Text(
                          '${entries[i].value}（${entries[i].value.toPercent()}）',
                          style: AppText.monoSmall,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 8),
            const Divider(height: 1),
            const SizedBox(height: 8),
            Text(
              '实测交换值 ${result.observedRecombination}（${result.observedRecombination.toPercent()}）'
              '＝输入 ${result.recombination}，互为印证',
              style: AppText.caption,
            ),
          ],
        ),
      );
  }
}