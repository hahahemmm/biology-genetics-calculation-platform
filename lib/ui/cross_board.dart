// cross_board.dart —— 棋盘板书共享组件 + 全屏放映（v2.6 课堂讲解优化）
//
// 场景：老师大屏讲课时，板书棋盘嵌在 720px 结果卡里只有巴掌大，
// 后排学生看不清基因型。「放映」把板书推成全屏：隐藏一切 UI 杂质，
// 只留 P→配子→F1 棋盘→表型比，格子随屏宽自适应放大，支持双指缩放
// 平移细看（64 格三对基因棋盘尤其需要）。
//
// CrossBoardView 同时服务内联板书视图（fontSize 传 null = 全部 token
// 原尺寸，学生模式像素级不变）与全屏放映（按屏宽自适应放大）。

import 'package:flutter/material.dart';

import '../engine/kaoji_calc.dart';
import '../theme.dart';
import 'presenter.dart';

/// 两配子合成合子基因型：逐位点显性大写在前（AA+Aa+aa 三种均正确）。
String zygoteGenotype(String a, String b) {
  final buf = StringBuffer();
  for (var i = 0; i < a.length && i < b.length; i++) {
    final c1 = a[i], c2 = b[i];
    if (c1.toLowerCase() != c2.toLowerCase()) {
      buf.write(c1);
      buf.write(c2);
      continue; // 异位点字符（理论不发生），原样保留
    }
    final up = c1.toUpperCase(), lo = c1.toLowerCase();
    final dom1 = c1 == up, dom2 = c2 == up;
    if (dom1 && dom2) {
      buf.write(up + up);
    } else if (!dom1 && !dom2) {
      buf.write(lo + lo);
    } else {
      buf.write(up + lo);
    }
  }
  return buf.toString();
}

/// 标准遗传图解板书内容（无外壳）：P → 配子 → F1 棋盘 → 表型比。
/// 默认 [cellWidth]=76、[fontSize]=null（全部用 token 原尺寸）＝内联
/// 板书既有渲染（学生模式像素级不变硬门禁）；全屏放映传放大值。
class CrossBoardView extends StatelessWidget {
  final KaojiCalcResult result;
  final String p1;
  final String p2;
  final double cellWidth;

  /// null = 全部用 token 原尺寸（内联板书默认路径，像素不变）。
  final double? fontSize;

  const CrossBoardView({
    super.key,
    required this.result,
    required this.p1,
    required this.p2,
    this.cellWidth = 76,
    this.fontSize,
  });

  @override
  Widget build(BuildContext context) {
    final r = result;
    final g1 = r.gametesP1;
    final g2 = r.gametesP2;
    final fs = fontSize;

    Widget cell(String s, {bool head = false}) => SizedBox(
          width: cellWidth,
          child: Text(
            s,
            textAlign: TextAlign.center,
            style: (fs == null
                    ? AppText.genotype.copyWith(fontSize: 13)
                    : AppText.genotype.copyWith(fontSize: fs))
                .copyWith(
                    fontWeight: head ? FontWeight.w700 : FontWeight.w500,
                    color: head ? AppColors.teal : AppColors.ink),
          ),
        );

    final pStyle = fs == null
        ? AppText.genotype.copyWith(fontWeight: FontWeight.w700)
        : AppText.genotype
            .copyWith(fontWeight: FontWeight.w700, fontSize: fs + 3);
    final gameteStyle = fs == null
        ? AppText.monoSmall.copyWith(color: AppColors.graphite)
        : AppText.monoSmall
            .copyWith(color: AppColors.graphite, fontSize: fs - 2);
    final ratioStyle = fs == null
        ? AppText.genotype.copyWith(color: AppColors.tealDark)
        : AppText.genotype
            .copyWith(color: AppColors.tealDark, fontSize: fs + 1);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('P：$p1  ×  $p2', style: pStyle),
        const SizedBox(height: 4),
        Text('配子：${g1.join('  ')}（纵）× ${g2.join('  ')}（横）',
            style: gameteStyle),
        const SizedBox(height: 8),
        // F1 棋盘：首行横配子，首列纵配子，格内合子基因型
        Row(children: [
          cell('F1', head: true),
          for (final g in g2) cell(g, head: true)
        ]),
        for (final ga in g1)
          Row(children: [
            cell(ga, head: true),
            for (final gb in g2) cell(zygoteGenotype(ga, gb)),
          ]),
        const SizedBox(height: 8),
        Text('表型比：${r.phenotypeRatio}（${r.phenotypeLabels.join(' : ')}）',
            style: ratioStyle),
      ],
    );
  }
}

/// 板书全屏放映（v2.6 课堂讲解优化；v2.7 迁移到通用放映壳 presenter.dart）：
/// 隐藏一切 UI 杂质，只留遗传图解，格子按屏宽自适应放大；
/// 双指缩放/拖动细看（64 格三对基因棋盘）。点右上关闭/空白/Esc 退出。
Future<void> showCrossBoardPresenter(
  BuildContext context, {
  required KaojiCalcResult result,
  required String p1,
  required String p2,
}) {
  return showWidgetPresenter(
    context,
    // Builder 拿对话框内的 MediaQuery（屏宽决定格子尺寸）
    child: Builder(
      builder: (ctx) {
        final size = MediaQuery.of(ctx).size;
        final cols = result.gametesP2.length + 1; // 含 F1 首列
        // 格子按屏宽自适应：96px 边距后均分，76 起步（不缩小于内联），上限 150
        final cellW = ((size.width - 96) / cols).clamp(76.0, 150.0);
        // 字号上限 26→30（v2.13 UI 走查 P2）：1080p 大屏 ×1.3 下 26px
        // 对后排偏小的反馈——150 格宽配 30px 基因型仍宽裕（约 5 字符）。
        final fs = (13 * cellW / 76).clamp(13.0, 30.0);
        return CrossBoardView(
          result: result,
          p1: p1,
          p2: p2,
          cellWidth: cellW,
          fontSize: fs,
        );
      },
    ),
  );
}
