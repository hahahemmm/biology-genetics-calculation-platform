// ════════════════════════════════════════════════════════════════
//  test/theme/contrast_audit_test.dart
//  v2.19.30 R13-2 移植 —— 可复算的 WCAG 对比度审计（分离工作区精华）
// ════════════════════════════════════════════════════════════════
//
//  【为什么要有这个文件】投影走查把对比度实测出来写进报告，但没有
//  留下任何防护——仓库里没有任何测试会因「谁把某个 token 改浅了」
//  变红。本文件把 WCAG 公式写进测试、遍历三套主题档的 token 组合，
//  任何后续配色改动一旦把对比度改坏，这里直接红。
//
//  三条设计原则（与分离版一致）：
//  1. 公式独立实现，不复用 Color.computeLuminance（复用引擎实现等于
//     让实现给自己打分）；再用规范参考值校验尺子本身。
//  2. 白名单逐条给理由且钉死实测值——数值漂移以「必须复评」失败，
//     杜绝「为了全绿而放宽阈值」。
//  3. 每个 token 的 getter 取值都要对上登记 hex——抓「token 定义对
//     了但接线绕过 getter」（R13-2 实测抓到 9 处 border 绕过）。
//
//  审计范围：标准浅色 / 高对比浅色（投影档）/ 深色 × 3 承载底 ×
//  14 枚 token。刻意排除：flash/select/connect（画布光效临时色，
//  信息由形状与动效承载）；backcrossPalette/familyPalette（固定色板
//  带 alpha 叠底，单值不足判定）。
// ════════════════════════════════════════════════════════════════

import 'dart:math' as math;

import 'package:biology/state/present_mode_controller.dart';
import 'package:biology/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// ────────────────────────────────────────────────────────────────
// 一、WCAG 2.x 公式（本文件独立实现）
// ────────────────────────────────────────────────────────────────

/// sRGB 单通道 8bit → 线性化值。WCAG 2.x 规定的分段函数。
double _linearize(int channel8) {
  final c = channel8 / 255.0;
  return c <= 0.04045
      ? c / 12.92
      : math.pow((c + 0.055) / 1.055, 2.4).toDouble();
}

/// WCAG 2.x 相对亮度 L = 0.2126R + 0.7152G + 0.0722B（RGB 均已线性化）。
double relativeLuminanceOfHex(String hex) {
  final h = hex.replaceFirst('#', '');
  assert(h.length == 6, '必须是 6 位 RRGGBB，实际 "$hex"');
  int ch(int i) => int.parse(h.substring(i * 2, i * 2 + 2), radix: 16);
  return 0.2126 * _linearize(ch(0)) +
      0.7152 * _linearize(ch(1)) +
      0.0722 * _linearize(ch(2));
}

/// WCAG 2.x 对比度 = (L_light + 0.05) / (L_dark + 0.05)，值域 [1, 21]。
double contrastOfHex(String fg, String bg) {
  final a = relativeLuminanceOfHex(fg);
  final b = relativeLuminanceOfHex(bg);
  return (math.max(a, b) + 0.05) / (math.min(a, b) + 0.05);
}

Color _colorOfHex(String hex) =>
    Color(0xFF000000 | int.parse(hex.replaceFirst('#', ''), radix: 16));

// ────────────────────────────────────────────────────────────────
// 二、档位 / 角色 / token 表
// ────────────────────────────────────────────────────────────────

class _Tier {
  final String name;
  final bool dark;
  final bool highContrast;
  const _Tier(this.name, this.dark, this.highContrast);

  @override
  bool operator ==(Object other) =>
      other is _Tier &&
      other.name == name &&
      other.dark == dark &&
      other.highContrast == highContrast;

  @override
  int get hashCode => Object.hash(name, dark, highContrast);
}

const _kStdLight = _Tier('标准浅色', false, false);
const _kHcLight = _Tier('高对比浅色（投影档）', false, true);
const _kDark = _Tier('深色', true, true);
const _kTiers = <_Tier>[_kStdLight, _kHcLight, _kDark];

/// token 的 WCAG 角色。决定套哪条线：文字 4.5:1 / 非文本 3:1。
enum _Role {
  text('文字', 4.5),
  nonText('非文本·图形边界', 3.0);

  const _Role(this.label, this.minRatio);
  final String label;
  final double minRatio;
}

/// 一枚被审计的 token：getter（用于接线断言）+ 三套档位的实测 hex。
class _Token {
  final String name;
  final _Role role;
  final Color Function() read;
  final String stdHex;
  final String hcHex;
  final String darkHex;

  const _Token(this.name, this.role, this.read,
      {required this.stdHex, required this.hcHex, required this.darkHex});

  String hexOf(_Tier tier) => switch (tier) {
        _kStdLight => stdHex,
        _kHcLight => hcHex,
        _ => darkHex,
      };
}

final _kTokens = <_Token>[
  // ── 文字 token（WCAG AA 4.5:1）────────────────────────────
  _Token('ink', _Role.text, () => AppColors.ink,
      stdHex: '#35322C', hcHex: '#17150F', darkHex: '#EAE8E1'),
  _Token('graphite', _Role.text, () => AppColors.graphite,
      stdHex: '#4E534B', hcHex: '#37342B', darkHex: '#CBCAC0'),
  _Token('steel', _Role.text, () => AppColors.steel,
      stdHex: '#61665C', hcHex: '#4F4B41', darkHex: '#A4A298'),
  _Token('teal', _Role.text, () => AppColors.teal,
      stdHex: '#5C7265', hcHex: '#3E5C4B', darkHex: '#9EB8A7'),
  _Token('tealDark', _Role.text, () => AppColors.tealDark,
      stdHex: '#4A5A50', hcHex: '#2C4437', darkHex: '#BFD4C6'),
  _Token('lethal', _Role.text, () => AppColors.lethal,
      stdHex: '#B91C1C', hcHex: '#991B1B', darkHex: '#FF8585'),
  // v2.22.0：深色 sand 从亮黄 0xFFF59E0B 单独调为低饱和沙金 0xFFD8B97A
  //（对 surfaceD 7.07:1 / canvasD 5.01:1 / tealWashD 6.21:1，AA 富余）。
  // sandL / sandHcL 不动——深色是独立调校，不是浅色反色。
  _Token('sand', _Role.text, () => AppColors.sand,
      stdHex: '#8F5B1E', hcHex: '#7C4A12', darkHex: '#D8B97A'),
  _Token('sexUpper', _Role.text, () => AppColors.sexUpper,
      stdHex: '#1D4ED8', hcHex: '#1E40AF', darkHex: '#60A5FA'),
  // R13-2 移植补上的那一枚：投影白底上从 2.94:1 → 4.92:1。
  _Token('sexLower', _Role.text, () => AppColors.sexLower,
      stdHex: '#CA8A04', hcHex: '#A16207', darkHex: '#FACC15'),
  _Token('armed', _Role.text, () => AppColors.armed,
      stdHex: '#7C3AED', hcHex: '#6D28D9', darkHex: '#C4B5FD'),
  // ── 非文本 token（WCAG 1.4.11 3:1）────────────────────────
  _Token('border', _Role.nonText, () => AppColors.border,
      stdHex: '#D2D7CD', hcHex: '#8A8578', darkHex: '#5C6158'),
];

/// 承载底：某枚 token 作为前景时，它实际会被画在什么底色上。
class _Bg {
  final String name;
  final Color Function() read;
  final String stdHex;
  final String hcHex;
  final String darkHex;

  const _Bg(this.name, this.read,
      {required this.stdHex, required this.hcHex, required this.darkHex});

  String hexOf(_Tier tier) => switch (tier) {
        _kStdLight => stdHex,
        _kHcLight => hcHex,
        _ => darkHex,
      };
}

final _kBackgrounds = <_Bg>[
  _Bg('canvas', () => AppColors.canvas,
      stdHex: '#F1F2EE', hcHex: '#FFFFFF', darkHex: '#212420'),
  _Bg('surface', () => AppColors.surface,
      stdHex: '#FBF9F5', hcHex: '#FFFFFF', darkHex: '#2C302B'),
  _Bg('tealWash', () => AppColors.tealWash,
      stdHex: '#E6EBE2', hcHex: '#D8E4DC', darkHex: '#303A33'),
];

// ────────────────────────────────────────────────────────────────
// 三、白名单（豁免项）—— 每条都必须有理由，且实测值被钉死
// ────────────────────────────────────────────────────────────────

class _Exemption {
  final _Tier tier;
  final String fg;
  final String bg;
  final double measured;
  final String reason;

  const _Exemption(this.tier, this.fg, this.bg, this.measured, this.reason);

  String get key => '${tier.name}·$fg on $bg';
}

const _sexLowerStdWhy =
    '登记不修（R13-2 移植）。要把标准浅色的 sexLower 从 2.60:1 提到 4.5:1，'
    '在 #F1F2EE 上唯一的走法是把它压进褐色区，而那些值与 sandL #8F5B1E'
    '（隐性表型标记）两两对比度只有 1.0~1.2:1——两个语义 token 会变成'
    '同一个颜色。实测证明「黄色在近白底上原理上到不了 4.5:1 而不变褐」，'
    '因此标准档不修，由投影专用的高对比档承担'
    '（#A16207 = 4.92:1）。';

const _borderStdWhy =
    '豁免：装饰性发丝线。设计铁律「卡片仅用于层级、用 border-top 分隔」，'
    'border 是刻意压出来的 1px 结构线。把它加深会把整站从莫兰迪极简推向'
    '表格线，属改动设计语言而非修缺陷。投影场景的正确解法是开高对比档'
    '（borderHcL #8A8578 = 3.68:1）。WCAG 1.4.11 只要求「识别控件/状态'
    '所必需的」视觉信息达标；发丝分隔线不承载必须读出的信息。';

const _borderDarkWhy =
    '豁免 + 边界：深色主题不受理投影档（_hc = !_dark && …，深色一律'
    '走深色 token）。装饰理由同标准浅色 border。';

const _borderOnWashWhy =
    '豁免：tealWash 只承载徽标/选中底色，其上的合法文字前景只有 '
    'tealDark（AppChip 走 onPrimaryContainer，Rail selectedLabel 同理），'
    'tealDark 在 tealWash 上三档全部达标。其它 token 落在 tealWash 上'
    '的组合不在真实渲染路径，按不可达配对豁免。';

const _onWashUnreachableWhy =
    '豁免：不可达配对。tealWash 是徽标/选中态底色（AppChip 的 '
    'primaryContainer、NavigationBar/Rail 的 indicatorColor），落在它上'
    '面的文字一律是 tealDark——实测三档全部达标。矩阵穷举产生、真实渲染'
    '不存在的配对；若哪天真画上去，那时再讨论配色，不预先开白名单口子。';

const _borderOnWashHcWhy =
    '豁免（HC 档唯一非文本豁免）：选中态 Chip 边框 #8A8578 落在 '
    'tealWash #D8E4DC 底上 ≈2.81:1。该边框冗余——Chip 可识别性由标签'
    '文字承担（tealDark #2C4437 在 tealWash 上 8.07:1），边框不承载'
    '唯一信息，按 1.4.11 豁免。加深 borderHcL 连带投影 golden 基线，'
    '收益不抵成本，登记不修。';

final _kExemptions = <_Exemption>[
  _Exemption(_kStdLight, 'sexLower', 'canvas', 2.61, _sexLowerStdWhy),
  _Exemption(_kStdLight, 'sexLower', 'surface', 2.79, _sexLowerStdWhy),
  _Exemption(_kStdLight, 'teal', 'tealWash', 4.28, _onWashUnreachableWhy),
  _Exemption(_kStdLight, 'sexLower', 'tealWash', 2.43, _onWashUnreachableWhy),
  _Exemption(_kStdLight, 'border', 'canvas', 1.30, _borderStdWhy),
  _Exemption(_kStdLight, 'border', 'surface', 1.39, _borderStdWhy),
  _Exemption(_kStdLight, 'border', 'tealWash', 1.21, _borderOnWashWhy),
  _Exemption(_kHcLight, 'border', 'tealWash', 2.81, _borderOnWashHcWhy),
  _Exemption(_kHcLight, 'sexLower', 'tealWash', 3.76, _onWashUnreachableWhy),
  _Exemption(_kDark, 'border', 'canvas', 2.47, _borderDarkWhy),
  _Exemption(_kDark, 'border', 'surface', 2.11, _borderDarkWhy),
  _Exemption(_kDark, 'border', 'tealWash', 1.86, _borderDarkWhy),
  // v2.22.0：steelD/tealWash 已达 4.61:1，旧豁免必须删除，不能留僵尸项。
];

// ────────────────────────────────────────────────────────────────

void main() {
  void selectTier(_Tier t) {
    AppColors.sync(t.dark ? Brightness.dark : Brightness.light);
    PresentModeController.instance.debugSetHighContrast(t.highContrast);
    expect(AppColors.isDark, t.dark, reason: '${t.name} 亮度档位未生效');
  }

  setUp(() => selectTier(_kStdLight));
  tearDown(() {
    AppColors.debugClearOverride();
    PresentModeController.instance.debugSetHighContrast(false);
  });

  // ══════════════════════════════════════════════════════════════
  // 一、公式自校验：先证明「这把尺子」是对的
  // ══════════════════════════════════════════════════════════════

  group('一、WCAG 公式自校验', () {
    test('复刻 WCAG 2.x 规范原文给出的参考对比度', () {
      expect(contrastOfHex('#767676', '#FFFFFF'), closeTo(4.54, 0.005),
          reason: 'WCAG 规范原文：#767676 on #FFFFFF = 4.54');
      expect(contrastOfHex('#595959', '#FFFFFF'), closeTo(7.00, 0.005),
          reason: 'WCAG 规范原文：#595959 on #FFFFFF = 7.00');
      expect(contrastOfHex('#777777', '#FFFFFF'), closeTo(4.48, 0.005),
          reason: 'WCAG 规范原文：#777777 on #FFFFFF = 4.48');
      expect(contrastOfHex('#000000', '#FFFFFF'), closeTo(21.0, 1e-9),
          reason: '理论上限：纯黑 on 纯白 = 21:1');
      expect(contrastOfHex('#FFFFFF', '#FFFFFF'), closeTo(1.0, 1e-9),
          reason: '理论下限：同色 = 1:1');
    });

    test('与 Color.computeLuminance 逐色对齐（证明实现无偏）', () {
      for (final tk in _kTokens) {
        for (final t in _kTiers) {
          final hex = tk.hexOf(t);
          expect(relativeLuminanceOfHex(hex),
              closeTo(_colorOfHex(hex).computeLuminance(), 1e-6),
              reason: '${tk.name} ${t.name} $hex：自实现与引擎实现应一致');
        }
      }
    });
  });

  // ══════════════════════════════════════════════════════════════
  // 二、接线断言：getter 实际返回的色值 == 审计表里登记的 hex
  // ══════════════════════════════════════════════════════════════

  group('二、token 接线（getter 取值 == 登记色值）', () {
    for (final t in _kTiers) {
      for (final tk in _kTokens) {
        test('${t.name} · ${tk.name}', () {
          selectTier(t);
          expect(_hexOf(tk.read()), tk.hexOf(t),
              reason: '${tk.name} getter 在「${t.name}」返回的色值与'
                  '登记表不符——要么 token 定义改了没更新审计表，要么'
                  '某处绕过了 getter（R13-2 抓到 9 处 border 绕过）。');
        });
      }
      for (final bg in _kBackgrounds) {
        test('${t.name} · 承载底 ${bg.name}', () {
          selectTier(t);
          expect(_hexOf(bg.read()), bg.hexOf(t),
              reason: '承载底 ${bg.name} 在「${t.name}」与登记表不符');
        });
      }
    }
  });

  // ══════════════════════════════════════════════════════════════
  // 三、对比度矩阵：3 档 × 3 底 × 11 token = 99 组
  // ══════════════════════════════════════════════════════════════

  group('三、对比度矩阵（WCAG 2.x）', () {
    for (final t in _kTiers) {
      for (final tk in _kTokens) {
        for (final bg in _kBackgrounds) {
          test('${t.name} · ${tk.name}(${tk.role.label}) on ${bg.name}',
              () {
            selectTier(t);
            final fgHex = tk.hexOf(t);
            final bgHex = bg.hexOf(t);
            final ratio = contrastOfHex(fgHex, bgHex);
            final need = tk.role.minRatio;

            final exempt = _findExemption(t, tk.name, bg.name);
            if (exempt == null) {
              expect(ratio, greaterThanOrEqualTo(need),
                  reason: '$fgHex on $bgHex = ${ratio.toStringAsFixed(2)}:1，'
                      '低于 ${tk.role.label} 门槛 $need:1。新增豁免必须在'
                      ' _kExemptions 写明理由并钉死实测值。');
              return;
            }

            expect(ratio, closeTo(exempt.measured, 0.005),
                reason: '白名单「${exempt.key}」已漂移：登记 '
                    '${exempt.measured}:1，实测 ${ratio.toStringAsFixed(2)}:1。'
                    '豁免理由不再自动成立，请复评。');
            expect(exempt.reason.trim().length, greaterThanOrEqualTo(20),
                reason: '白名单「${exempt.key}」无效理由（需 ≥20 字）。');
          });
        }
      }
    }

    test('白名单覆盖完整性：不存在「登记了但已达标」的僵尸豁免', () {
      for (final e in _kExemptions) {
        selectTier(e.tier);
        final tk = _kTokens.firstWhere((k) => k.name == e.fg);
        final actual = contrastOfHex(
          tk.hexOf(e.tier),
          _kBackgrounds.firstWhere((b) => b.name == e.bg).hexOf(e.tier),
        );
        expect(actual, lessThan(tk.role.minRatio),
            reason: '白名单「${e.key}」实测 ${actual.toStringAsFixed(2)}:1 '
                '已达标，请从 _kExemptions 删掉。');
      }
    });

    test('投影档豁免只能落在 tealWash 徽标底上', () {
      final hcExemptions =
          _kExemptions.where((e) => e.tier == _kHcLight).toList();
      for (final e in hcExemptions) {
        expect(e.bg, 'tealWash',
            reason: '高对比档豁免「${e.key}」落在 canvas/surface 底上——'
                '投影档纯白底是每屏主体底色，不允许豁免。');
        expect(
            const {_onWashUnreachableWhy, _borderOnWashHcWhy},
            contains(e.reason),
            reason: '投影档豁免「${e.key}」理由须为「不可达配对」或'
                '「装饰冗余边界」。');
      }
    });
  });

  // ══════════════════════════════════════════════════════════════
  // 四、HC 家族完整性 + 投影档文字全达标
  // ══════════════════════════════════════════════════════════════

  group('四、高对比档家族完整性', () {
    test('sexUpper / sexLower / armed 在投影档必须有自己的变体', () {
      for (final tk in _kTokens.where(
          (k) => const {'sexUpper', 'sexLower', 'armed'}.contains(k.name))) {
        expect(tk.hcHex, isNot(tk.stdHex),
            reason: '${tk.name} 高对比变体与浅色档同值——'
                '这正是 R13-2 修复的 HC 家族缺口。');
      }
    });

    test('深色主题不受投影档影响（_hc = !_dark && …）', () {
      selectTier(_kDark);
      final darkValues = {
        for (final tk in _kTokens) tk.name: _hexOf(tk.read()),
      };
      PresentModeController.instance.debugSetHighContrast(false);
      final darkAgain = {
        for (final tk in _kTokens) tk.name: _hexOf(tk.read()),
      };
      expect(darkAgain, equals(darkValues),
          reason: '深色下 highContrast 开或关 token 取值必须一致。');
    });

    test('投影档关键文字全部 ≥ 4.5:1（老师 10 米外能读）', () {
      selectTier(_kHcLight);
      for (final tk in _kTokens.where((k) => k.role == _Role.text)) {
        final r = contrastOfHex(tk.hcHex, _kBackgrounds.first.hexOf(_kHcLight));
        expect(r, greaterThanOrEqualTo(4.5),
            reason: '${tk.name} 在投影白底上只有 ${r.toStringAsFixed(2)}:1');
      }
    });
  });
}

_Exemption? _findExemption(_Tier t, String fg, String bg) {
  for (final e in _kExemptions) {
    if (e.tier.name == t.name && e.fg == fg && e.bg == bg) return e;
  }
  return null;
}

String _hexOf(Color c) {
  String two(double v) =>
      (v * 255).round().clamp(0, 255).toRadixString(16).padLeft(2, '0');
  return '#${two(c.r)}${two(c.g)}${two(c.b)}'.toUpperCase();
}
