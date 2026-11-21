// theme_v221_palette_test.dart —— v2.22.0 视觉减负的 token / 形状契约
//
// 需求（视觉减负第 3、4 项）：
//   3) Filled / OutlinedButton 统一 12px 圆角（共享常量 radiusButton），
//      不再是 28px 全胶囊；页面内自定义语义按钮不受影响（不在此断言）。
//   4) 浅色「去黄褐」+ 边界/辅助字更实；深色**独立**调校（不是反色）。
//      铁律不变：AppColors / AppText 命名不变、莫兰迪低饱和 Sage 不变、
//      课堂浅色高对比分支与功能语义色不变、AppTheme.build 只由
//      brightness + 高对比控制器决定。
//
// 注意：本文件钉的是「新值 + 可达门槛」，与 test/theme/contrast_audit_test.dart
// 的登记表是两回事。首轮调色（canvas/graphite/steel/border/surfaceD…）已由
// 主线程同步进审计登记表；本轮 v2.22.0 的两处改动各自同步：
//   · 深色 sandD 0xFFF59E0B → 0xFFD8B97A（登记表 + 本文件三/四组）；
//   · onPrimary / secondary 家族改成按 bright 参数派生（本文件五组）。
// 断言仍只覆盖「取值 + 对比门槛」，不宣称像素级修复。

import 'dart:math' as math;

import 'package:biology/state/present_mode_controller.dart';
import 'package:biology/state/theme_controller.dart';
import 'package:biology/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// ── WCAG 2.x 相对亮度 / 对比度（与 contrast_audit_test 同公式）──
double _lin(double c) {
  final v = c / 255.0;
  return v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4) as double;
}

double _lum(Color c) =>
    0.2126 * _lin(c.r * 255) + 0.7152 * _lin(c.g * 255) + 0.0722 * _lin(c.b * 255);

double _contrast(Color fg, Color bg) {
  final a = _lum(fg), b = _lum(bg);
  final hi = math.max(a, b), lo = math.min(a, b);
  return (hi + 0.05) / (lo + 0.05);
}

int _r(Color c) => (c.r * 255).round();
int _g(Color c) => (c.g * 255).round();
int _bl(Color c) => (c.b * 255).round();

String _hex(Color c) =>
    '#${_r(c).toRadixString(16).padLeft(2, '0')}'
    '${_g(c).toRadixString(16).padLeft(2, '0')}'
    '${_bl(c).toRadixString(16).padLeft(2, '0')}'.toUpperCase();

void main() {
  tearDown(() {
    AppColors.debugClearOverride();
    PresentModeController.instance.debugSetHighContrast(false);
  });

  group('一 · 按钮形状统一（12px 圆角，共享常量）', () {
    test('radiusButton = 12，且两套按钮主题都吃这一枚常量', () {
      expect(AppTheme.radiusButton, 12.0);

      for (final theme in [AppTheme.light(), AppTheme.dark()]) {
        for (final style in [
          theme.filledButtonTheme.style,
          theme.outlinedButtonTheme.style,
        ]) {
          final shape = style?.shape?.resolve(const <WidgetState>{});
          expect(shape, isA<RoundedRectangleBorder>());
          final radius = (shape as RoundedRectangleBorder).borderRadius;
          expect(radius, BorderRadius.circular(AppTheme.radiusButton),
              reason: '按钮必须回到圆角矩形（旧值 28 = 全胶囊）');
        }
      }
    });

    testWidgets('FilledButton 渲染圆角确为 12（不是 28）', (t) async {
      await t.pumpWidget(MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: Center(
            child: FilledButton(onPressed: () {}, child: const Text('保存')),
          ),
        ),
      ));
      await t.pumpAndSettle();
      final material = t.widget<Material>(
        find
            .descendant(
              of: find.byType(FilledButton),
              matching: find.byType(Material),
            )
            .first,
      );
      final shape = material.shape;
      expect(shape, isA<RoundedRectangleBorder>());
      expect((shape as RoundedRectangleBorder).borderRadius,
          BorderRadius.circular(12));
    });
  });

  group('二 · 浅色去黄褐 + 可读性', () {
    test('中性家族不再是「裸暖灰」：B 通道不显著低于 R、G ≥ R', () {
      for (final c in [
        AppColors.canvasL,
        AppColors.graphiteL,
        AppColors.steelL,
        AppColors.borderL,
        AppColors.surfaceLowL,
      ]) {
        expect(_r(c) - _bl(c), lessThanOrEqualTo(6),
            reason: '${_hex(c)} 红蓝差过大 ⇒ 回到黄褐一侧');
        expect(_g(c), greaterThanOrEqualTo(_r(c)),
            reason: '${_hex(c)} 绿通道不及红 ⇒ 偏黄而非绿中性');
      }
    });

    test('浅色文字 token 对 surface 达 WCAG AA 4.5:1', () {
      final bg = AppColors.surfaceL;
      for (final c in [
        AppColors.inkL,
        AppColors.graphiteL,
        AppColors.steelL,
        AppColors.tealL,
      ]) {
        expect(_contrast(c, bg), greaterThanOrEqualTo(4.5),
            reason: '${_hex(c)} on ${_hex(bg)} = '
                '${_contrast(c, bg).toStringAsFixed(2)}:1');
      }
      // v2.22 的「辅助字更实」：steel 从 4.8 提到 5.4 以上
      expect(_contrast(AppColors.steelL, bg), greaterThan(5.4));
    });

    test('结构线可见化，但仍属「发丝线」档（不越 3:1 变成表格线）', () {
      // 旧值（改前实测）：border on canvas 1.23 / on surface 1.32
      for (final entry in {
        AppColors.canvasL: 1.23,
        AppColors.surfaceL: 1.32,
      }.entries) {
        final ratio = _contrast(AppColors.borderL, entry.key);
        expect(ratio, greaterThan(entry.value + 0.03),
            reason: 'border on ${_hex(entry.key)} 应比旧值 '
                '${entry.value.toStringAsFixed(2)} 更实');
        expect(ratio, lessThan(3.0), reason: '不得把设计语言推成表格线');
      }
    });
  });

  group('三 · 深色独立调校（不是浅色反色）', () {
    test('层级：canvas 更沉、surface 更亮，border 在暗底上看得见', () {
      expect(_lum(AppColors.canvasD), lessThan(_lum(AppColors.surfaceD)));
      expect(_contrast(AppColors.borderD, AppColors.canvasD), greaterThan(1.4));
      expect(_contrast(AppColors.borderD, AppColors.surfaceD), greaterThan(2.0));
    });

    test('深色文字 token 对 surfaceD 达 4.5:1', () {
      for (final c in [
        AppColors.inkD,
        AppColors.graphiteD,
        AppColors.steelD,
        AppColors.tealWashD, // 仅作反向对照，下面单独判
      ].take(3)) {
        expect(_contrast(c, AppColors.surfaceD), greaterThanOrEqualTo(4.5),
            reason: '${_hex(c)} on ${_hex(AppColors.surfaceD)}');
      }
    });

    test('深色不受理投影高对比档（_hc 仍只对浅色生效）', () {
      AppColors.sync(Brightness.dark);
      PresentModeController.instance.debugSetHighContrast(true);
      expect(AppColors.isHighContrast, isFalse);
      expect(AppColors.canvas, AppColors.canvasD);
      expect(AppColors.ink, AppColors.inkD);
    });
  });

  group('四 · 命名与主题组装契约不变', () {
    test('ThemeData.brightness 与入参逐位一致（防 Theme.of 读错档）', () {
      expect(AppTheme.light().brightness, Brightness.light);
      expect(AppTheme.dark().brightness, Brightness.dark);
      expect(AppTheme.light().colorScheme.brightness, Brightness.light);
      expect(AppTheme.dark().colorScheme.brightness, Brightness.dark);
    });

    testWidgets('MaterialApp 主题过渡落定后子树必须读到浅色', (t) async {
      // MaterialApp 走 AnimatedTheme：先深后浅时首帧 Theme.of 仍是插值，
      // 断言前必须 pumpAndSettle（设置页的 HC 置灰判断依赖这一点）。
      await t.pumpWidget(MaterialApp(
        theme: AppTheme.dark(),
        home: const Scaffold(body: Text('probe')),
      ));
      await t.pumpAndSettle();
      await t.pumpWidget(MaterialApp(
        theme: AppTheme.light(),
        home: const Scaffold(body: Text('probe')),
      ));
      await t.pumpAndSettle();
      final ctx = t.element(find.text('probe'));
      expect(MediaQuery.platformBrightnessOf(ctx), Brightness.light);
      expect(Theme.of(ctx).brightness, Brightness.light);
    });

    test('surfaceLow 已 token 化，ColorScheme 直接引用同一枚值', () {
      for (final t in [AppTheme.light(), AppTheme.dark()]) {
        final dark = t.brightness == Brightness.dark;
        expect(
          t.colorScheme.surfaceContainerLow,
          dark ? AppColors.surfaceLowD : AppColors.surfaceLowL,
          reason: '局部硬编码旧 ECE8E0 会让 surface 档位与主题漂移',
        );
      }
    });

    test('AppTheme.build 仍然只由 brightness 决定（同一入参 ⇒ 同一主题）', () {
      final a = AppTheme.light();
      final b = AppTheme.light();
      expect(a.scaffoldBackgroundColor, b.scaffoldBackgroundColor);
      expect(a.colorScheme.primary, b.colorScheme.primary);
      expect(a.scaffoldBackgroundColor, AppColors.canvasL);
      // 全局亮度残留不得污染 build 结果
      AppColors.sync(Brightness.dark);
      expect(AppTheme.light().scaffoldBackgroundColor, AppColors.canvasL);
      expect(ThemeController.instance, isNotNull);
    });
  });

  group('动作字型同源', () {
    test('Filled / Outlined 共用 AppText.action，不再各维护一份字体样式', () {
      expect(AppText.action.fontFamily, AppFonts.sans);
      expect(AppText.action.fontSize, 14);
      expect(AppText.action.fontWeight, FontWeight.w600);
      for (final theme in [AppTheme.light(), AppTheme.dark()]) {
        expect(
          theme.filledButtonTheme.style?.textStyle
              ?.resolve(const <WidgetState>{}),
          same(AppText.action),
        );
        expect(
          theme.outlinedButtonTheme.style?.textStyle
              ?.resolve(const <WidgetState>{}),
          same(AppText.action),
        );
      }
    });
  });

  group('五 · v2.22.0：主色前景 / secondary 家族 / 深色 sand', () {
    test('onPrimary 由本 build 的 brightness 决定，不读 AppColors.onTeal', () {
      expect(AppTheme.light().colorScheme.onPrimary, Colors.white);
      expect(AppTheme.dark().colorScheme.onPrimary, const Color(0xFF16211B));
      // 全局 _dark 残留（含跨亮度构建时序）不得把浅色主题读成深色前景
      AppColors.sync(Brightness.dark);
      expect(AppTheme.light().colorScheme.onPrimary, Colors.white,
          reason: '浅色 build 读到深色前景 ⇒ 主按钮字与底色同深，读不出');
      AppColors.sync(Brightness.light);
      expect(AppTheme.dark().colorScheme.onPrimary, const Color(0xFF16211B));
    });

    test('secondary 不再复用 armed 紫：归 Sage 家族且对比达标', () {
      for (final t in [AppTheme.light(), AppTheme.dark()]) {
        final dark = t.brightness == Brightness.dark;
        final cs = t.colorScheme;
        expect(cs.secondary, dark ? AppColors.tealDarkD : AppColors.tealDarkL,
            reason: 'secondary 应是 tealDark 档（Sage 家族）');
        expect(cs.secondary, isNot(dark ? AppColors.armedD : AppColors.armedL),
            reason: 'armed 是画布连线语义色，不得外泄成第二强调色');
        expect(cs.secondaryContainer, isNot(AppColors.armedD));
        expect(cs.secondaryContainer,
            dark ? AppColors.tealWashD : AppColors.tealWashL);
        expect(cs.onSecondaryContainer,
            dark ? AppColors.tealDarkD : AppColors.tealDarkL);
        expect(_contrast(cs.onSecondary, cs.secondary), greaterThanOrEqualTo(4.5),
            reason: 'onSecondary on secondary = '
                '${_contrast(cs.onSecondary, cs.secondary).toStringAsFixed(2)}:1');
        expect(_contrast(cs.onSecondaryContainer, cs.secondaryContainer),
            greaterThanOrEqualTo(4.5));
      }
      // armed 仍原样可用（画布连线语义未被削弱）
      expect(AppColors.armedL, const Color(0xFF7C3AED));
      expect(AppColors.armedD, const Color(0xFFC4B5FD));
    });

    test('深色 sandD 是低饱和沙金，三块承载底均达 AA', () {
      expect(AppColors.sandD, const Color(0xFFD8B97A));
      expect(AppColors.sandD, isNot(const Color(0xFFF59E0B)),
          reason: '旧值亮黄在暖墨灰底上像警示灯');
      // 低饱和判据：蓝通道明显抬起来（沙金而非纯黄）
      expect(_bl(AppColors.sandD), greaterThan(100));
      for (final bg in [
        AppColors.surfaceD,
        AppColors.canvasD,
        AppColors.tealWashD,
      ]) {
        expect(_contrast(AppColors.sandD, bg), greaterThanOrEqualTo(4.5),
            reason: '${_hex(AppColors.sandD)} on ${_hex(bg)}');
      }
      // 浅色 / 投影档 sand 零改动
      expect(AppColors.sandL, const Color(0xFF8F5B1E));
      expect(AppColors.sandHcL, const Color(0xFF7C4A12));
    });

    test('输入框保留浮动标签，且浮动标签底色与填充色逐位一致', () {
      for (final t in [AppTheme.light(), AppTheme.dark()]) {
        final dark = t.brightness == Brightness.dark;
        final deco = t.inputDecorationTheme;
        expect(deco.filled, isTrue);
        expect(deco.floatingLabelBehavior, isNot(FloatingLabelBehavior.never),
            reason: '禁用浮动标签会丢掉「这个框是什么」的亲本信息');
        final floating = deco.floatingLabelStyle;
        expect(floating, isNotNull);
        expect(floating!.backgroundColor, deco.fillColor,
            reason: '底色不一致 ⇒ 标签处出现一道色差，且描边仍穿字');
        expect(deco.fillColor,
            dark ? AppColors.surfaceD : AppColors.surfaceL);
      }
    });
  });
}
