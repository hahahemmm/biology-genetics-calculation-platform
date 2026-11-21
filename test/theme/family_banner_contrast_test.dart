// family_banner_contrast_test.dart —— 家族横幅文字色判定钉死
//（v2.19.30 DeepSeek P2-3：_onForBg 纯函数化后 8 色 × 2 模式进测试，
// 杜绝「未来调 palette 色或 banner alpha 后对比度静默破 AA」）。
import 'package:biology/pages/widgets/pedigree_canvas.dart';
import 'package:biology/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

double _luminance(Color c) => c.computeLuminance();

double _contrast(Color fg, Color bg) {
  final a = _luminance(fg);
  final b = _luminance(bg);
  final l = a > b ? a : b;
  final d = a > b ? b : a;
  return (l + 0.05) / (d + 0.05);
}

void main() {
  /// banner 底 = palette 色 alpha 0.80 叠在 canvas 上（painter 实际做法）。
  Color bannerBg(Color palette) {
    const alpha = 0.80;
    final canvas = AppColors.canvas;
    return Color.from(
      alpha: 1.0,
      red: palette.r * alpha + canvas.r * (1 - alpha),
      green: palette.g * alpha + canvas.g * (1 - alpha),
      blue: palette.b * alpha + canvas.b * (1 - alpha),
    );
  }

  for (final dark in [false, true]) {
    group(dark ? '深色' : '浅色', () {
      setUp(() => AppColors.sync(dark ? Brightness.dark : Brightness.light));
      tearDown(AppColors.debugClearOverride);

      for (var i = 0; i < 8; i++) {
        test('家族横幅 第${i + 1}色（${dark ? '深' : '浅'}底）文字对比度 ≥4.5',
            () {
          final palette = AppColors.familyPalette[i];
          final bg = bannerBg(palette);
          final fg = PedigreePainter.onForBgCore(bg, AppColors.canvas);
          expect(
            _contrast(fg, bg),
            greaterThanOrEqualTo(4.5),
            reason: 'palette $palette（#${palette.toARGB32().toRadixString(16)}）'
                ' alpha0.80 叠 ${dark ? '深' : '浅'}色 canvas → 实际底 '
                '#${bg.toARGB32().toRadixString(16)}，文字色 '
                '#${fg.toARGB32().toRadixString(16)} 须达 WCAG AA 4.5:1',
          );
        });
      }
    });
  }

  test('判定只返回两个合法色之一（白 / 深墨 1A1A1A）', () {
    AppColors.sync(Brightness.light);
    for (final palette in AppColors.familyPalette) {
      final bg = bannerBg(palette);
      final fg = PedigreePainter.onForBgCore(bg, AppColors.canvas);
      expect(
        fg == Colors.white || fg == const Color(0xFF1A1A1A),
        isTrue,
        reason: 'palette #$palette 判定出非法文字色 #${fg.toARGB32().toRadixString(16)}',
      );
    }
  });
}
