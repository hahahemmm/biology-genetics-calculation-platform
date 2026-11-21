// theme_typography_test.dart —— v2.23 中文文字层级契约
//
// 背景（用户反馈「中文层级偏平」）：共享 AppText 阶梯从 20/15/14/13/12
// 收到 20/16/14/13/12 的清晰台阶，中文标题改用正字距 + 显式行高。
// 本文件钉四件事（与 theme_v221_palette_test 的颜色/按钮契约、
// golden_font_guard 的家族装载契约互补，不重复它们的断言）：
//
//   T1 标题阶梯：pageTitle 20 / sectionTitle 16，w700 + 行高 1.3 +
//      中文正字距（不得回到拉丁向负字距，那会挤中文字面）。
//   T2 正文与辅助文字不得回缩：body 14 / label 13 / caption 12，
//      行高 body 1.6 / caption 1.5 原样保留——v213_r13 投影门槛
//      （body.fontSize × textScale 1.75 ≥ 24px）与 WCAG 门槛都挂在这。
//   T3 等宽与动作字型不漂：genotype / monoFigure / monoSmall 仍挂
//      AppFonts.mono（数字/基因型等宽是签名细节）；AppText.action 仍是
//      const 同实例 14/w600（theme_v221 钉 same()，这里钉它不被改成 getter）。
//   T4 字体栈方向：Windows 中文由 fallback 首项 'Microsoft YaHei' 承担、
//      跨平台回退不减。主 family 'PingFang SC' 与 fallback 首项被
//      golden 装载器字面量钉死（test/golden_fonts.dart kSansFamily /
//      kSansFamilyFallback），重排家族顺序会把 golden 中文静默变方框。

import 'package:biology/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('T1 标题阶梯（20 / 16，正字距 + 行高）', () {
    test('pageTitle 20 / sectionTitle 16，w700 + height 1.3', () {
      expect(AppText.pageTitle.fontSize, 20);
      expect(AppText.pageTitle.fontWeight, FontWeight.w700);
      expect(AppText.pageTitle.height, 1.3);
      expect(AppText.sectionTitle.fontSize, 16);
      expect(AppText.sectionTitle.fontWeight, FontWeight.w700);
      expect(AppText.sectionTitle.height, 1.3);
    });

    test('标题字距为正（负字距是拉丁向收紧，挤中文字面）', () {
      expect(AppText.pageTitle.letterSpacing, 0.2);
      expect(AppText.sectionTitle.letterSpacing, 0.2);
    });

    test('阶梯不平铺：20 > 16 > 14 > 13 > 12', () {
      final sizes = [
        AppText.pageTitle.fontSize!,
        AppText.sectionTitle.fontSize!,
        AppText.body.fontSize!,
        AppText.label.fontSize!,
        AppText.caption.fontSize!,
      ];
      for (var i = 1; i < sizes.length; i++) {
        expect(sizes[i], lessThan(sizes[i - 1]),
            reason: '层级必须单调递减（实测 $sizes），否则读起来是平铺');
      }
    });
  });

  group('T2 正文 / 辅助文字不得回缩', () {
    test('body 14 / label 13 / caption 12 与行高原样保留', () {
      expect(AppText.body.fontSize, 14);
      expect(AppText.body.height, 1.6);
      expect(AppText.label.fontSize, 13);
      expect(AppText.caption.fontSize, 12);
      expect(AppText.caption.height, 1.5);
    });

    test('正文/辅助仍走共享 sans 字族栈', () {
      for (final s in [
        AppText.pageTitle,
        AppText.sectionTitle,
        AppText.label,
        AppText.body,
        AppText.caption,
      ]) {
        expect(s.fontFamily, AppFonts.sans);
        expect(s.fontFamilyFallback, AppFonts.sansFallback);
      }
    });
  });

  group('T3 等宽与动作字型不漂', () {
    test('genotype / monoFigure / monoSmall 仍等宽（数字/基因型签名细节）', () {
      for (final s in [
        AppText.genotype,
        AppText.monoFigure,
        AppText.monoSmall,
      ]) {
        expect(s.fontFamily, AppFonts.mono);
        expect(s.fontFamilyFallback, AppFonts.monoFallback);
      }
    });

    test('AppText.action 仍是 const 同实例（14 / w600，颜色由按钮前景解析）', () {
      expect(identical(AppText.action, AppText.action), isTrue,
          reason: 'action 是 const 字段而非 getter——改成 getter 会破 '
              'theme_v221 的 same() 同源契约');
      expect(AppText.action.fontFamily, AppFonts.sans);
      expect(AppText.action.fontSize, 14);
      expect(AppText.action.fontWeight, FontWeight.w600);
      expect(AppText.action.color, isNull,
          reason: '颜色由按钮前景解析，样式里不带色（v2.1n 白字事故教训）');
    });
  });

  group('T4 字体栈：Windows 中文优先 + 跨平台回退', () {
    test('fallback 首项 Microsoft YaHei（Windows 中文优先）', () {
      expect(AppFonts.sansFallback.first, 'Microsoft YaHei');
    });

    test('跨平台回退不减：Noto Sans SC + 通用 sans-serif 兜底', () {
      expect(AppFonts.sansFallback, contains('Noto Sans SC'));
      expect(AppFonts.sansFallback.last, 'sans-serif');
      expect(AppFonts.monoFallback, isNotEmpty,
          reason: 'mono 也要留系统等宽兜底（Consolas/Menlo/monospace）');
    });
  });
}
