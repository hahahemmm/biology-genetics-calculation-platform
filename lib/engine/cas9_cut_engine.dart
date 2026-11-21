// cas9_cut_engine.dart —— 经典化脓性链球菌 Cas9（SpCas9）切割位置教学模型
//
// 只处理经典 5′-NGG-3′ PAM：输入顶链恒按 5′→3′ 书写；顶链上的 NGG
// 与底链上的 NGG（顶链表现为 CCN）都要检查。原间隔序列是 PAM 同链
// 5′ 侧紧邻的 20 nt；理想平末端切割位于 PAM 上游 3 bp 的碱基对边界。
// 本模型不预测编辑效率、脱靶或安全性，也不推广到其他 Cas 蛋白。

import 'restriction_engine.dart'
    show complementDna, normalizeDnaSequence, reverseComplementDna;

const int kSpCas9MinSequenceLength = 23;
const int kSpCas9MaxSequenceLength = 120;
const int kSpCas9ProtospacerLength = 20;

/// PAM 实际位于哪条链；序列方向均按该链自身 5′→3′ 解读。
enum Cas9PamStrand { displayedTop, complementaryBottom }

class Cas9CutSite {
  const Cas9CutSite({
    required this.pamStrand,
    required this.pamStart,
    required this.cutBoundary,
    required this.pam,
    required this.protospacer,
  });

  final Cas9PamStrand pamStrand;

  /// PAM 对应的三碱基 motif 在输入顶链上的 0-based 起点。
  /// 顶链 PAM 为 NGG；底链 PAM 对应的顶链 motif 为 CCN。
  final int pamStart;

  /// 输入顶链上的 0-based 碱基对边界：切在 [cutBoundary - 1] 与
  /// [cutBoundary] 两个 0-based 下标之间。底链在同一边界切开，形成平末端。
  final int cutBoundary;

  /// 实际 PAM，按 PAM 所在链的 5′→3′ 书写。
  final String pam;

  /// PAM 同链 5′ 侧的 20 nt 原间隔序列，按同一条链的 5′→3′ 书写。
  final String protospacer;

  int get pamStart1Based => pamStart + 1;
  int get pamEnd1Based => pamStart + 3;

  /// 切口左侧、右侧紧邻碱基在输入顶链上的 1-based 位次。
  int get cutLeft1Based => cutBoundary;
  int get cutRight1Based => cutBoundary + 1;
}

class SpCas9Analysis {
  const SpCas9Analysis({
    required this.topSequence,
    required this.bottomSequence,
    required this.sites,
    required this.pamMotifCount,
  });

  /// 输入顶链（5′→3′）与逐列互补的底链（3′→5′）。
  final String topSequence;
  final String bottomSequence;

  /// 同时具备完整 20 nt 原间隔序列的位点，按顶链 PAM 坐标排序。
  final List<Cas9CutSite> sites;

  /// 两条链发现的全部 NGG motif 数，包括因旁侧不足 20 nt 而未分析的。
  final int pamMotifCount;
}

SpCas9Analysis analyzeSpCas9Cuts(String raw) {
  final top = normalizeDnaSequence(raw);
  if (top.length < kSpCas9MinSequenceLength) {
    throw ArgumentError(
      '完整位点需要 20 nt 原间隔序列与 3 nt PAM，序列至少 $kSpCas9MinSequenceLength bp',
    );
  }
  if (top.length > kSpCas9MaxSequenceLength) {
    throw ArgumentError('序列过长（本教学模型上限 $kSpCas9MaxSequenceLength bp）');
  }

  final sites = <Cas9CutSite>[];
  var motifCount = 0;
  for (var i = 0; i + 3 <= top.length; i++) {
    final motif = top.substring(i, i + 3);

    // 顶链 5′-NGG-3′：PAM 同链 5′ 侧取 20 nt；切口在 PAM 前 3 bp。
    if (motif[1] == 'G' && motif[2] == 'G') {
      motifCount++;
      if (i >= kSpCas9ProtospacerLength) {
        sites.add(
          Cas9CutSite(
            pamStrand: Cas9PamStrand.displayedTop,
            pamStart: i,
            cutBoundary: i - 3,
            pam: motif,
            protospacer: top.substring(i - kSpCas9ProtospacerLength, i),
          ),
        );
      }
    }

    // 底链 5′-NGG-3′ 在顶链上写成 5′-CCN-3′。底链 PAM 的 5′ 侧
    // 对应顶链 CCN 的右侧 20 nt，须反向互补后按底链 5′→3′ 展示。
    if (motif[0] == 'C' && motif[1] == 'C') {
      motifCount++;
      final protospacerEnd = i + 3 + kSpCas9ProtospacerLength;
      if (protospacerEnd <= top.length) {
        sites.add(
          Cas9CutSite(
            pamStrand: Cas9PamStrand.complementaryBottom,
            pamStart: i,
            cutBoundary: i + 6,
            pam: reverseComplementDna(motif),
            protospacer: reverseComplementDna(
              top.substring(i + 3, protospacerEnd),
            ),
          ),
        );
      }
    }
  }

  sites.sort((a, b) {
    final byPosition = a.pamStart.compareTo(b.pamStart);
    return byPosition != 0
        ? byPosition
        : a.pamStrand.index.compareTo(b.pamStrand.index);
  });
  return SpCas9Analysis(
    topSequence: top,
    bottomSequence: complementDna(top),
    sites: List<Cas9CutSite>.unmodifiable(sites),
    pamMotifCount: motifCount,
  );
}
