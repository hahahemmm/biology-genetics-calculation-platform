// graph_label_readability_test.dart —— 知识图谱非焦点标题可读性
//
// 选中一个节点后，非一跳节点仍要保留，但旧实现把 dimNodeWeight=0.45
// 同时乘到背景、描边和标题上：浅色普通节点文字对比只有 2.48:1，
// 形成「节点还在、名字却读不出」的假保留。现在卡片仍按 0.45 降权，
// 标题独立按 0.72 降权；本文件用真实 token 与 Canvas 叠色顺序逐档复算。
import 'dart:math' as math;

import 'package:biology/pages/knowledge_graph_page.dart';
import 'package:biology/state/present_mode_controller.dart';
import 'package:biology/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 与 Painter 的绘制顺序一致：foreground 以 alpha 覆盖到 background。
Color _over(Color foreground, Color background, double alpha) {
  int channel(double fg, double bg) =>
      (fg * 255 * alpha + bg * 255 * (1 - alpha)).round();
  return Color.fromARGB(
    255,
    channel(foreground.r, background.r),
    channel(foreground.g, background.g),
    channel(foreground.b, background.b),
  );
}

double _linear(int value) {
  final c = value / 255.0;
  return c <= 0.04045
      ? c / 12.92
      : math.pow((c + 0.055) / 1.055, 2.4).toDouble();
}

double _luminance(Color color) =>
    0.2126 * _linear((color.r * 255).round()) +
    0.7152 * _linear((color.g * 255).round()) +
    0.0722 * _linear((color.b * 255).round());

double _contrast(Color a, Color b) {
  final la = _luminance(a);
  final lb = _luminance(b);
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

void main() {
  tearDown(() {
    AppColors.sync(Brightness.light);
    AppColors.debugClearOverride();
    PresentModeController.instance.debugSetHighContrast(false);
  });

  test('卡片与标题权重分离：卡片 0.45，非焦点标题 0.72，焦点不变', () {
    expect(KnowledgeGraphPainter.dimNodeWeight, 0.45);
    expect(KnowledgeGraphPainter.dimNodeLabelWeight, 0.72);
    expect(KnowledgeGraphPainter.nodeLabelWeight(0.45), 0.72);
    expect(KnowledgeGraphPainter.nodeLabelWeight(1.0), 1.0,
        reason: '焦点/搜索/薄弱点标题不得被额外降权');
  });

  for (final tier in <(String, Brightness, bool)>[
    ('标准浅色', Brightness.light, false),
    ('高对比浅色', Brightness.light, true),
    ('深色', Brightness.dark, false),
  ]) {
    test('${tier.$1}：普通/基础概念非焦点标题均达 WCAG AA 4.5:1', () {
      AppColors.sync(tier.$2);
      PresentModeController.instance.debugSetHighContrast(tier.$3);

      final canvas = AppColors.canvas;
      final normalBg = _over(
        AppColors.surface,
        canvas,
        KnowledgeGraphPainter.dimNodeWeight,
      );
      final rootBg = _over(
        AppColors.sand,
        canvas,
        0.10 * KnowledgeGraphPainter.dimNodeWeight,
      );
      for (final (kind, bg) in [('普通', normalBg), ('基础概念', rootBg)]) {
        final label = _over(
          AppColors.ink,
          bg,
          KnowledgeGraphPainter.dimNodeLabelWeight,
        );
        final ratio = _contrast(label, bg);
        expect(
          ratio,
          greaterThanOrEqualTo(4.5),
          reason: '${tier.$1} / $kind节点：${ratio.toStringAsFixed(2)}:1；'
              '标题必须独立降权，不能跟卡片一起压到 0.45',
        );
      }
    });
  }

  test('旧做法反证：标题若继续跟卡片用 0.45，标准浅色不达 AA', () {
    AppColors.sync(Brightness.light);
    PresentModeController.instance.debugSetHighContrast(false);
    final bg = _over(
      AppColors.surface,
      AppColors.canvas,
      KnowledgeGraphPainter.dimNodeWeight,
    );
    final oldLabel = _over(
      AppColors.ink,
      bg,
      KnowledgeGraphPainter.dimNodeWeight,
    );
    expect(_contrast(oldLabel, bg), lessThan(4.5),
        reason: '证明新回归确实能抓住旧缺陷，而不是恒绿公式');
  });
}
