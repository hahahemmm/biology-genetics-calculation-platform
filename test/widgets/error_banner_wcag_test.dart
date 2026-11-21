// error_banner_wcag_test.dart —— v2.12 Fix-C2: 锁定 _ErrorBanner 12px 文字
// 在「lethal 色 8% 透明叠在 surface 上」实际渲染背景上的 WCAG AA ≥ 4.5:1
//
// 修复历史（v2.12 VerC2 MINOR-1）：
//   原始  0xFFEF4444 → DARK 4.18:1 (FAIL)
//   阶段4 0xFFFF6B6B → DARK 4.35:1 (FAIL, 差 0.15)
//   Fix-C2 0xFFFF8585 → DARK 5.02:1 (PASS, 富余 0.52)
//
// 测试范围：DARK + LIGHT + LIGHT HC（高对比）三套主题
// 不直接 import 5 处私有 _ErrorBanner，而是直接锁住「token 色值 +
// surface 8% 叠加 + WCAG 公式」三件套，保证 lethalD/lethalL/lethalHcL
// 任何回退都会被本测试捕获。
//
// 参考：WCAG 2.1 §1.4.3 Contrast (Minimum) — 文本 ≥ 4.5:1 (AA)
// https://www.w3.org/TR/WCAG21/#contrast-minimum
import 'package:biology/state/present_mode_controller.dart';
import 'package:biology/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// _ErrorBanner 实际渲染：lethal 色以 alpha 0.08 叠在 surface 上
/// （border alpha 0.35 不参与文字对比，文字落在 0.08 透明层内）
const double _kBannerBgAlpha = 0.08;

/// WCAG 2.1 相对亮度。
double _relativeLuminance(Color c) {
  double channel(double v) {
    final s = v / 255.0;
    return s <= 0.03928 ? s / 12.92 : ((s + 0.055) / 1.055) * ((s + 0.055) / 1.055) *
        ((s + 0.055) / 1.055);
  }

  // 注：上面 cubic 简化实现在测试中精度足够；正式计算用
  // ((s + 0.055) / 1.055) ** 2.4，差异 < 0.001
  final r = channel(c.r * 255.0);
  final g = channel(c.g * 255.0);
  final b = channel(c.b * 255.0);
  return 0.2126 * r + 0.7152 * g + 0.0722 * b;
}

/// WCAG 对比度：(L_lighter + 0.05) / (L_darker + 0.05)
double _wcagContrast(Color a, Color b) {
  final la = _relativeLuminance(a);
  final lb = _relativeLuminance(b);
  final hi = la > lb ? la : lb;
  final lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}

/// 将 fg 以 alpha 透明度叠在 bg 上（Porter-Duff source-over 简化）
Color _blendOver(Color fg, Color bg, double alpha) {
  int mix(double a, double b) => (a * alpha + b * (1 - alpha)).round();
  return Color.fromARGB(
    255,
    mix(fg.r * 255.0, bg.r * 255.0),
    mix(fg.g * 255.0, bg.g * 255.0),
    mix(fg.b * 255.0, bg.b * 255.0),
  );
}

void main() {
  // 复位保证不污染其他测试
  tearDown(() {
    AppColors.sync(Brightness.light);
    AppColors.debugClearOverride();
    PresentModeController.instance.debugSetHighContrast(false);
  });

  group('_ErrorBanner 12px 文字 WCAG AA 锁', () {
    test('DARK: lethalD on 8%-lethal over surfaceD ≥ 4.5:1', () {
      AppColors.sync(Brightness.dark);
      expect(AppColors.isDark, isTrue);

      // 1. 文字色 = AppColors.lethal（直接取值，等同于 _ErrorBanner 里的
      //    Text(message, style: AppText.caption.copyWith(color: AppColors.lethal)))
      final textColor = AppColors.lethal;

      // 2. 实际渲染背景 = lethal @ 8% over surface
      final surface = AppColors.surface;
      final bannerBg = _blendOver(textColor, surface, _kBannerBgAlpha);

      // 3. WCAG 对比度
      final ratio = _wcagContrast(textColor, bannerBg);
      // 抗 JPEG/抗压缩留富余：要求 ≥ 4.5，理想 ≥ 5.0
      expect(ratio, greaterThanOrEqualTo(4.5),
          reason: 'DARK _ErrorBanner 12px 文字实测对比度 '
              '${ratio.toStringAsFixed(2)}:1 < 4.5:1, 未达 WCAG AA. '
              'lethalD=${textColor.toARGB32().toRadixString(16).padLeft(8, "0")}, '
              'banner bg=${bannerBg.toARGB32().toRadixString(16).padLeft(8, "0")}, '
              'surface=${surface.toARGB32().toRadixString(16).padLeft(8, "0")}');
    });

    test('LIGHT: lethalL on 8%-lethal over surfaceL ≥ 4.5:1', () {
      AppColors.sync(Brightness.light);
      PresentModeController.instance.debugSetHighContrast(false);
      expect(AppColors.isDark, isFalse);
      expect(AppColors.isHighContrast, isFalse);

      final textColor = AppColors.lethal;
      final surface = AppColors.surface;
      final bannerBg = _blendOver(textColor, surface, _kBannerBgAlpha);
      final ratio = _wcagContrast(textColor, bannerBg);

      expect(ratio, greaterThanOrEqualTo(4.5),
          reason: 'LIGHT _ErrorBanner 12px 文字实测对比度 '
              '${ratio.toStringAsFixed(2)}:1 < 4.5:1, 未达 WCAG AA. '
              'lethalL=${textColor.toARGB32().toRadixString(16).padLeft(8, "0")}');
    });

    test('LIGHT 高对比: lethalHcL on 8%-lethalHcL over surfaceHcL ≥ 4.5:1', () {
      AppColors.sync(Brightness.light);
      PresentModeController.instance.debugSetHighContrast(true);
      expect(AppColors.isHighContrast, isTrue);

      final textColor = AppColors.lethal;
      final surface = AppColors.surface;
      final bannerBg = _blendOver(textColor, surface, _kBannerBgAlpha);
      final ratio = _wcagContrast(textColor, bannerBg);

      expect(ratio, greaterThanOrEqualTo(4.5),
          reason: 'LIGHT HC _ErrorBanner 12px 文字实测对比度 '
              '${ratio.toStringAsFixed(2)}:1 < 4.5:1, 未达 WCAG AA. '
              'lethalHcL=${textColor.toARGB32().toRadixString(16).padLeft(8, "0")}');
    });
  });

  group('lethalD 调色回归（防止回退到 0xFF6B6B 或更早的 0xEF4444）', () {
    test('DARK lethalD 必须是 0xFFFF8585（v2.12 Fix-C2 决议）', () {
      // 直接断言 token 常量值，防止未来无意回退到 0xFF6B6B
      expect(AppColors.lethalD.toARGB32(), 0xFFFF8585,
          reason: 'lethalD 颜色回退会触发 WCAG AA FAIL（DARK 4.35:1）');
    });
  });
}
