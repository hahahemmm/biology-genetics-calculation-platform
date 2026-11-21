// theme.dart —— 设计系统实现（与 docs/ARCHITECTURE.md 的设计约定对应）
//
// 设计约定的文字来源是 docs/ARCHITECTURE.md；本文件只做 Flutter 侧的 token 落地。
// v2（2026-08-26）：Slate 冷调中性 + Jade Teal 提亮 + 深色一等公民。
// v3（2026-08-26 二审）：莫兰迪低饱和高级灰（淡漠裸暖灰中性家族）+
// 灰豆绿 Sage 强调色；token 命名（teal/tealDark/tealWash）保持不变，
// 只换色值——页面侧零改动换肤。功能语义色（含 select/connect token）
// 两模式只调亮度不调色相。
// 规则摘录：
//  - 单一中性家族（Morandi 淡漠裸暖灰系），唯一强调色灰豆绿 Sage
//  - 禁用纯黑；基因型/比例/概率一律等宽字体
//  - 卡片仅用于层级，结果区用 border-top 分隔；阴影带色相
//
// 深色模式：AppColors 持有浅/深两套 token，main.dart 顶层 build 调
// AppColors.sync(实际生效亮度) 完成切换；页面侧继续用 AppColors.xxx
// 零改动换肤。注意两条铁律：
//  1. token 是 getter，不能在 const 构造里使用；
//  2. 含 AppColors/AppText 读取的 widget 子树不得以 const/static 缓存
//     实例（identical 实例会让 Element 跳过 rebuild，切换时旧 token
//     残留 → 深浅混染）。页面列表必须每帧新建（State 不会丢）。

import 'package:flutter/material.dart';

import 'state/present_mode_controller.dart';
import 'state/theme_controller.dart';

/// 设计 Token：颜色。
class AppColors {
  AppColors._();

  // ── 浅色 token（Morandi 淡漠裸暖灰系）────────────────────
  // v2.22.0 视觉减负（用户反馈「偏黄灰、字发虚」）：中性家族从「裸暖灰」
  // 收到「绿中性灰」——色相从黄褐一侧挪回中性，R/G/B 极差由 7 收到 4，
  // 黄褐感消失但仍是莫兰迪低饱和（不是彩色化）。文字/边界各深一档：
  // graphite 5D594F→4E534B（对 surface 7.6:1）、steel 6E695C→61665C
  //（5.5:1）、border DFDAD0→D2D7CD（结构线在白底上终于有形）。
  // **不动**：surfaceL / inkL（近白底与墨灰已是主对比承担者，改它们等于
  // 重做基线）、tealL / tealDarkL / tealWashL（Sage 品牌色）、功能语义色。
  static const canvasL = Color(0xFFF1F2EE); // Canvas 页面背景（绿中性灰）
  static const surfaceL = Color(0xFFFBF9F5); // Surface 卡片/输入（暖近白）
  static const inkL = Color(0xFF35322C); // Ink 主文字（墨灰，非纯黑）
  static const graphiteL = Color(0xFF4E534B); // Graphite 次要标题（v2.22 加深）
  static const steelL = Color(0xFF61665C); // 辅助说明（v2.22 加深 4.8→5.5:1）
  static const borderL = Color(0xFFD2D7CD); // Border 结构线（v2.22 可见化）
  static const tealL = Color(0xFF5C7265); // 灰豆绿 Sage（v6 加深：3.7→5.2:1）
  static const tealDarkL = Color(0xFF4A5A50); // 按压态
  static const tealWashL = Color(0xFFE6EBE2); // 浅底：选中/徽标（淡豆绿灰）
  static const lethalL = Color(0xFFB91C1C); // 致死 / 错误
  static const sandL = Color(0xFF8F5B1E); // 隐性表型标记（v6 灰调化，莫兰迪）
  static const sexUpperL = Color(0xFF1D4ED8); // 伴性大写（X/Y）蓝
  static const sexLowerL = Color(0xFFCA8A04); // 伴性小写（x/y）黄
  static const armedL = Color(0xFF7C3AED); // 连线待命光（v2.19.5 紫罗兰：去橙粉感）
  static const flashL = Color(0xFFD97706); // 连线成功橙光（约 2s 后自行熄灭）
  static const selectL = Color(0xFF9A3412); // 选中光效（v2.19.5 深琥珀陶土：去正红）
  static const connectL = Color(0xFF155E75); // 相连高亮（v2.19.5 深青瓷：去亮蓝）

  /// v2.22.0：surface 低一档（ColorScheme.surfaceContainerLow / switch 轨道 /
  /// slider 未激活轨 / chip 禁用底）。**token 化**前是 4 处硬编码
  /// `0xFFECE8E0`——浅色一改底色，这四处就留在旧黄灰上（局部硬编码破坏
  /// 一致性），故抽成具名 token，改色只改一处。
  static const surfaceLowL = Color(0xFFE8ECE6);
  static const surfaceLowD = Color(0xFF262A25);

  // ── 浅色高对比变体（v2.3.4 课堂模式子开关）─────────────────
  // 投影仪泛白吃对比度：背景纯白、文字近黑、边框/强调色加深。
  // 仅在「课堂模式开 + 高对比开 + 浅色主题」时由 getter 选用。
  static const canvasHcL = Color(0xFFFFFFFF); // 纯白底（投影最大亮度）
  static const surfaceHcL = Color(0xFFFFFFFF);
  static const inkHcL = Color(0xFF17150F); // 近黑暖墨
  static const graphiteHcL = Color(0xFF37342B);
  static const steelHcL = Color(0xFF4F4B41); // 辅助文字也保 WCAG AA+
  static const borderHcL = Color(0xFF8A8578); // 结构线加深两档
  static const tealHcL = Color(0xFF3E5C4B); // 更深更饱和的 Sage
  static const tealDarkHcL = Color(0xFF2C4437);
  static const tealWashHcL = Color(0xFFD8E4DC); // 浅底在白底上仍有形
  static const lethalHcL = Color(0xFF991B1B);
  static const sandHcL = Color(0xFF7C4A12);
  // v2.19.30（R13-2 移植）：HC 家族补全原先缺的三枚——补全前
  // sexUpper/sexLower/armed 在高对比档没有变体，getter 沿用浅色值，
  // sexLower(#CA8A04) 在投影纯白底上只有 2.94:1，是投影场景唯一的
  // 实测**文字**对比度 FAIL（伴性小写 x/y 在系谱画布是真文字）。
  // 三枚都是同色相色阶往深挪一档（blue-600→800 / yellow-600→700 /
  // violet-600→700），主色与墨色零改动；浅/深档原样保留，
  // 新值只在 _hc 分支生效（标准模式与既有 golden 零像素变化）。
  static const sexUpperHcL = Color(0xFF1E40AF); // 蓝加一档：投影白底 8.72:1
  static const sexLowerHcL = Color(0xFFA16207); // 黄加一档：投影白底 4.92:1
  static const armedHcL = Color(0xFF6D28D9); // 紫加一档：投影白底 7.10:1

  // ── 深色 token（Morandi 暖墨灰阶；一等公民独立调校）─────────
  // v2.22.0：深色**不是浅色的反色**，各自按「底层要更沉、层级要更分明」
  // 单独调——canvas 压深一档（23→21 亮度）让 surface 浮起来，border
  // 3F423D→5C6158 让描边在暗底上看得见（对 canvas 2.47:1，对 surface
  // 2.11:1，旧值只有 1.51/1.32），辅助字 steel 9C988D→A4A298 抵掉暗底
  // 上的发虚（对 surface 5.24:1）；inkD / tealD 等主色零改动。
  static const canvasD = Color(0xFF212420); // 暖墨灰（微绿底）
  static const surfaceD = Color(0xFF2C302B);
  static const inkD = Color(0xFFEAE8E1); // 暖米白
  static const graphiteD = Color(0xFFCBCAC0);
  static const steelD = Color(0xFFA4A298);
  static const borderD = Color(0xFF5C6158);
  static const tealD = Color(0xFF9EB8A7); // Sage 暗色提亮
  static const tealDarkD = Color(0xFFBFD4C6); // 按压态（暗色下更亮）
  static const tealWashD = Color(0xFF303A33);
  // v2.12 调色历史:
  //   原始 0xFFEF4444 在 canvasD(0xFF232523) 上仅 4.18:1 不达 AA
  //   v2.12 阶段 4 → 0xFFFF6B6B 在 _ErrorBanner 实际背景
  //     (lethalD * 0.08 + surfaceD * 0.92 = 0x3E3431) 上 4.35:1
  //     仍未达 AA 4.5(差 0.15)
  //   v2.12 Fix-C2 → 0xFFFF8585 在同背景上 5.02:1 过 AA
  //     留 0.52 富余,适配 12px 小字抗 JPEG/抗压缩场景
  // 浅色 (lethalL=0xB91C1C 5.38:1 / lethalHcL=0x991B1B 7.24:1)
  // 已达 AA 不动。tealD 调色决策留 Wave 2 评估,本次只动 lethalD。
  static const lethalD = Color(0xFFFF8585);
  // v2.22.0：深色 sand 太亮黄（0xFFF59E0B 在暖墨灰底上像警示灯，抢节点文字），
  // 单独调成**低饱和沙金** 0xFFD8B97A：对 surfaceD 7.07:1 / canvasD 5.01:1 /
  // tealWashD 6.21:1，仍远超文字 AA 4.5（登记表已同步）。sandL / sandHcL 与
  // 其它语义色零改动——这是深色档的独立调校，不是浅色的反色。
  static const sandD = Color(0xFFD8B97A);
  static const sexUpperD = Color(0xFF60A5FA);
  static const sexLowerD = Color(0xFFFACC15);
  static const armedD = Color(0xFFC4B5FD); // 连线待命光（v2.19.5 亮紫罗兰）
  static const flashD = Color(0xFFFBBF24);
  static const selectD = Color(0xFFFB923C); // 选中光效（v2.19.5 亮琥珀）
  static const connectD = Color(0xFF67E8F9); // 相连高亮（v2.19.5 亮青瓷）

  /// v2.2 主题重写：测试专用亮度 override。widget 测试里
  /// `AppColors.sync(Brightness.dark)` 的语义即「锁定本测试的
  /// token 亮度」；生产代码不再调用（token 实时从
  /// ThemeController.effectiveBrightness 派生）。
  static Brightness? _debugBrightnessOverride;

  /// v2.2 主题重写：**_dark 不再是可残留的全局静态状态**。
  /// 每次取值实时计算：测试 override 优先，否则跟随
  /// ThemeController.effectiveBrightness（用户锁定的模式 + 仅在
  /// 「跟随系统」时读平台亮度）。任何 notify/rebuild 时序问题都
  /// 不再可能导致 token 与界面主题错位（白底白字/黑底黑字灭绝）。
  static bool get _dark {
    final o = _debugBrightnessOverride;
    if (o != null) return o == Brightness.dark;
    return ThemeController.instance.effectiveBrightness == Brightness.dark;
  }

  static bool get isDark => _dark;

  /// 高对比配色（v2.3.4；v2.10 迁移为全局开关）：开 + 浅色时 getter 选用
  /// 高对比变体；深色主题不受理（投影场景是浅色）。
  /// v2.10 功能迁移：原来是「课堂模式开」子开关，但学生模式同样需要
  /// 可读性辅助（近视/远视学生坐在后排看屏幕），故不再要求课堂模式开启。
  /// 与 _dark 一样实时派生——控制器 notify → 顶层 rebuild →
  /// token 重新求值，无残留状态。
  static bool get _hc =>
      !_dark && PresentModeController.instance.highContrast;

  /// 测试/调试可读：当前是否生效高对比变体。
  static bool get isHighContrast => _hc;

  /// 兼容旧调用（测试包壳用）：设置本进程 token 亮度 override；
  /// 传入的亮度决定所有 token getter 返回深/浅哪套色值。
  /// 生产路径请勿调用——token 已实时派生，无需手动同步。
  static void sync(Brightness brightness) =>
      _debugBrightnessOverride = brightness;

  /// 测试专用：清除亮度 override，让 token 回到实时派生
  /// （跟随 ThemeController.effectiveBrightness）。同进程多个
  /// 测试串行时，验证「实时派生」语义的用例必须先调本方法，
  /// 否则会被前面用例的 sync() override 污染。
  @visibleForTesting
  static void debugClearOverride() => _debugBrightnessOverride = null;

  static Color get canvas =>
      _dark ? AppColors.canvasD : (_hc ? AppColors.canvasHcL : AppColors.canvasL);
  static Color get surface => _dark
      ? AppColors.surfaceD
      : (_hc ? AppColors.surfaceHcL : AppColors.surfaceL);
  static Color get ink =>
      _dark ? AppColors.inkD : (_hc ? AppColors.inkHcL : AppColors.inkL);
  static Color get graphite => _dark
      ? AppColors.graphiteD
      : (_hc ? AppColors.graphiteHcL : AppColors.graphiteL);
  static Color get steel =>
      _dark ? AppColors.steelD : (_hc ? AppColors.steelHcL : AppColors.steelL);
  static Color get border =>
      _dark ? AppColors.borderD : (_hc ? AppColors.borderHcL : AppColors.borderL);
  static Color get teal =>
      _dark ? AppColors.tealD : (_hc ? AppColors.tealHcL : AppColors.tealL);
  static Color get tealDark => _dark
      ? AppColors.tealDarkD
      : (_hc ? AppColors.tealDarkHcL : AppColors.tealDarkL);
  static Color get tealWash => _dark
      ? AppColors.tealWashD
      : (_hc ? AppColors.tealWashHcL : AppColors.tealWashL);
  static Color get lethal =>
      _dark ? AppColors.lethalD : (_hc ? AppColors.lethalHcL : AppColors.lethalL);
  static Color get sand =>
      _dark ? AppColors.sandD : (_hc ? AppColors.sandHcL : AppColors.sandL);
  static Color get sexUpper => _dark
      ? AppColors.sexUpperD
      : (_hc ? AppColors.sexUpperHcL : AppColors.sexUpperL);
  static Color get sexLower => _dark
      ? AppColors.sexLowerD
      : (_hc ? AppColors.sexLowerHcL : AppColors.sexLowerL);
  static Color get armed =>
      _dark ? AppColors.armedD : (_hc ? AppColors.armedHcL : AppColors.armedL);
  static Color get flash => _dark ? AppColors.flashD : AppColors.flashL;

  /// 选中光效红 / 相连高亮蓝（功能语义，画布光效用）。
  static Color get select => _dark ? AppColors.selectD : AppColors.selectL;
  static Color get connect => _dark ? AppColors.connectD : AppColors.connectL;

  /// 回交连线调色板：每条跨世代 mating 边按 (fromId^toId) 散列取色，
  /// 逐条异色以便在密集系谱里区分（深浅主题通用的中饱和色）。
  static const backcrossPalette = [
    Color(0xFF8B5CF6), // 紫
    Color(0xFFF97316), // 橙
    Color(0xFFEC4899), // 品红
    Color(0xFF06B6D4), // 青
    Color(0xFF6366F1), // 靛蓝
    Color(0xFF84CC16), // 青柠
    Color(0xFFF43F5E), // 玫红
    Color(0xFFEAB308), // 金黄
  ];

  /// 家族分栏色板（R14）：多家族系谱的分栏底色/描边/横幅取色，
  /// 按家族编号取模。深浅主题通用的中饱和色（底色仅用低透明度）。
  static const familyPalette = [
    Color(0xFF3B82F6), // 蓝
    Color(0xFF10B981), // 绿
    Color(0xFFF59E0B), // 琥珀
    Color(0xFFEC4899), // 品红
    Color(0xFF8B5CF6), // 紫
    Color(0xFF14B8A6), // 青
    Color(0xFFEF4444), // 红
    Color(0xFF84CC16), // 黄绿
  ];

  /// 浅色模式下的 surface 变体（ColorScheme.surfaceContainerLow 用）。
  static Color get surfaceLow =>
      _dark ? AppColors.surfaceLowD : AppColors.surfaceLowL;

  /// 画布悬浮工具条底色：Surface，深色下 92% 不透明（浮于画布上方）。
  static Color get overlayBar =>
      _dark ? const Color(0xEB2D2F2C) : const Color(0xF5FBF9F5);

  /// FilledButton 上的前景色（暗色 Sage 提亮后需配深色字）。
  static Color get onTeal =>
      _dark ? const Color(0xFF16211B) : Colors.white;

  /// 卡片投影：带 Ink 色相的 whisper 阴影；暗色下加深。
  static List<BoxShadow> get cardShadow => [
        BoxShadow(
          color: _dark ? const Color(0x73000000) : const Color(0x0D35322C),
          blurRadius: 12,
          offset: const Offset(0, 4),
        ),
      ];
}

/// 字体栈：中文界面必须显式含中文字体。
///
/// v2.23 钉（勿动顺序）：主 family 名 'PingFang SC' 与 fallback 首项
/// 'Microsoft YaHei' 被 golden 装载器钉死（test/golden_fonts.dart 的
/// kSansFamily / kSansFamilyFallback 字面量 + golden_font_guard C0 断言
/// AppText.caption.fontFamily == kSansFamily、sansFallback.first 逐字一致），
/// 重排成「Windows 字族当主 family」会静默把 golden 中文变方框。
/// Windows 中文优先由 **fallback 首项 'Microsoft YaHei'** 承担（主 family
/// 在 Windows 不存在 ⇒ 逐字回落到雅黑）；'Noto Sans SC' + 'sans-serif'
/// 继续兜住 Linux / Web 等其余平台 = 跨平台回退不减。
class AppFonts {
  AppFonts._();

  /// 正文/标题：拉丁回退到系统中文字体。
  static const sans = 'PingFang SC';
  static const sansFallback = <String>[
    'Microsoft YaHei',
    'Noto Sans SC',
    'sans-serif',
  ];

  /// 等宽：基因型 / 比例 / 概率专用（本应用签名细节）。
  static const mono = 'JetBrains Mono';
  static const monoFallback = <String>['Consolas', 'Menlo', 'monospace'];
}

/// 常用文字样式快捷方式。
///
/// v2.1n 修复：v2.1k/l 曾删掉 color 字段指望 textTheme 接管 onSurface，
/// 但 textTheme.copyWith 用无色样式整体替换了 M3 自带颜色的样式，
/// 导致 textTheme 各 style color 全为 null → DefaultTextStyle 断链 →
/// TextPainter 渲染成白色 → 浅色模式白字白底（所有页面）。
/// 现恢复显式 color（AppColors getter；v2.1k 已修复 _dark 同步链路：
/// main.dart 顶层每帧 sync + 系统亮度监听，getter 取值可信）。
class AppText {
  AppText._();

  // v2.23 中文层级阶梯（用户反馈「层级偏平」）：
  //  - 标题两级收到 20 / 16 的清晰台阶（16 与 dashboard 分区标题
  //    copyWith(fontSize: 16) 的既有取向一致）；正文 14 / 标签 13 /
  //    辅助 12 **原样保留**——正文与辅助文字不得回缩。
  //  - 中文标题用 +0.2px **正**字距 + 显式行高 1.3：原 -0.2 是拉丁向的
  //    收紧，对中文字面是挤压；显式行高让 Windows 微软雅黑 / macOS 苹方
  //    两个字族渲染出同一节奏（字族栈不动，见 AppFonts 钉）。
  static TextStyle get pageTitle => TextStyle(
        fontFamily: AppFonts.sans,
        fontFamilyFallback: AppFonts.sansFallback,
        fontSize: 20,
        fontWeight: FontWeight.w700,
        height: 1.3,
        letterSpacing: 0.2,
        color: AppColors.ink,
      );

  static TextStyle get sectionTitle => TextStyle(
        fontFamily: AppFonts.sans,
        fontFamilyFallback: AppFonts.sansFallback,
        fontSize: 16,
        fontWeight: FontWeight.w700,
        height: 1.3,
        letterSpacing: 0.2,
        color: AppColors.ink,
      );

  static TextStyle get label => TextStyle(
        fontFamily: AppFonts.sans,
        fontFamilyFallback: AppFonts.sansFallback,
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: AppColors.ink,
      );

  static TextStyle get body => TextStyle(
        fontFamily: AppFonts.sans,
        fontFamilyFallback: AppFonts.sansFallback,
        fontSize: 14,
        height: 1.6,
        color: AppColors.ink,
      );

  static TextStyle get caption => TextStyle(
        fontFamily: AppFonts.sans,
        fontFamilyFallback: AppFonts.sansFallback,
        fontSize: 12,
        height: 1.5,
        color: AppColors.steel,
      );

  /// 按钮/跨模块动作共用字型：与正文同族、14px、600 字重。
  /// 颜色由按钮前景解析，避免不同页面各自复制一份略不同的 TextStyle。
  static const action = TextStyle(
    inherit: false,
    fontFamily: AppFonts.sans,
    fontFamilyFallback: AppFonts.sansFallback,
    fontSize: 14,
    fontWeight: FontWeight.w600,
  );

  /// 等宽基因型文本：加字距，像实验记录。
  static TextStyle get genotype => TextStyle(
        fontFamily: AppFonts.mono,
        fontFamilyFallback: AppFonts.monoFallback,
        fontSize: 14,
        letterSpacing: 1.0,
        fontWeight: FontWeight.w600,
        color: AppColors.ink,
      );

  /// 等宽大数字：比例 / 概率。teal 强调色/功能色，
  /// 不能用 onSurface（否则与普通文字同色，失去强调意义）。
  static TextStyle get monoFigure => TextStyle(
        fontFamily: AppFonts.mono,
        fontFamilyFallback: AppFonts.monoFallback,
        fontSize: 22,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.5,
        color: AppColors.teal,
      );

  static TextStyle get monoSmall => TextStyle(
        fontFamily: AppFonts.mono,
        fontFamilyFallback: AppFonts.monoFallback,
        fontSize: 13,
        letterSpacing: 0.5,
        color: AppColors.ink,
      );
}

/// 主题组装：浅色 / 深色共用同一套结构，仅 token 亮度不同。
class AppTheme {
  AppTheme._();

  static const radiusCard = 14.0;
  static const radiusInput = 10.0;
  static const radiusChip = 8.0;

  /// v2.22.0：按钮统一圆角（Filled / Outlined 共用一枚常量）。
  ///
  /// 旧值 28 = 36px 高按钮的**全胶囊**，与本应用层级（卡片 14 / 输入 10 /
  /// chip 8）不是一套形状语言：页面上按钮像药丸、块面像方卡，用户读成
  /// 「形状不统一」。12px 让按钮回到「圆角矩形」，与输入框（10）同族、
  /// 比卡片（14）略紧，仍是同一支尺子。页面内自定义语义按钮（课堂条、
  /// 画布缩放块等）各自显式给 shape，不在此列。
  static const radiusButton = 12.0;

  static ThemeData light() => build(Brightness.light);
  static ThemeData dark() => build(Brightness.dark);

  static ThemeData build([Brightness brightness = Brightness.light]) {
    // v2.1k：所有 colorScheme / scaffold / iconTheme / appBarTheme / 关键
    // 文字 token 一律用 isDark ? _xxxD : _xxxL（私有 const token），不再
    // 读 AppColors.xxx getter（getter 依赖全局 _dark 残留）。AppTheme.build
    // 完全 deterministic：只依赖 brightness 参数，MaterialApp rebuild 时
    // colorScheme 一定正确。
    //
    // 旧的注释"禁止调 AppColors.sync"是指不要在 build 内 sync；本函数现在
    // 根本不再读 _dark，更不依赖 sync 顺序。AppColors.sync 仍由 main.dart
    // 顶层调（兼容旧 widget / 显式 AppColors.xxx 的代码）。
    final isDark = brightness == Brightness.dark;
    // v2.19.30（R13-2 移植）：组件主题结构线原先一律写死
    // `isDark ? borderD : borderL`，绕过了 AppColors.border getter 的
    // _hc 分支——borderHcL(#8A8578, 3.68:1) 这枚专为投影配的 token 从未
    // 到达屏幕（高对比档输入框描边/按钮/chip/卡片描边吃的仍是标准档
    // #DFDAD0）。遵循 v2.1k 契约（build 只依赖 brightness 参数 + 单一
    // 全局量 highContrast），9 处全部换 borderColor；浅/深档取值与改前
    // 逐位相同 → 既有 golden 零位移。
    final hc = !isDark && PresentModeController.instance.highContrast;
    final Color borderColor = isDark
        ? AppColors.borderD
        : (hc ? AppColors.borderHcL : AppColors.borderL);
    // v2.22.0：主色前景由**本 build 的 brightness 参数**决定（深色 = 深墨绿
    // #16211B，浅色 = 白），不再读 AppColors.onTeal —— 那枚 getter 按全局
    // _dark 实时派生，跨亮度构建（首帧 dark → 锁 light、widget 测试先 sync
    // 再 build）时可能与参数不一致。取值与旧行为逐位相同，故像素零位移。
    // AppColors.onTeal 仍保留给页面侧运行时消费（FAB/演示器/系谱条等）。
    final Color onPrimaryColor =
        isDark ? const Color(0xFF16211B) : Colors.white;
    // v2.22.0：输入框填充色抽成局部量——floatingLabelStyle 的背景必须与它
    // 逐位一致，否则标签底色与输入框底色会出现一道色差。
    final Color fieldFill = isDark ? AppColors.surfaceD : AppColors.surfaceL;
    final scheme = ColorScheme.fromSeed(
      seedColor: isDark ? AppColors.tealD : AppColors.tealL,
      brightness: brightness,
    ).copyWith(
      primary: isDark ? AppColors.tealD : AppColors.tealL,
      onPrimary: onPrimaryColor,
      primaryContainer: isDark ? AppColors.tealWashD : AppColors.tealWashL,
      onPrimaryContainer: isDark ? AppColors.tealDarkD : AppColors.tealDarkL,
      // v2.22.0：secondary 曾复用 armed 紫（画布「连线待命光」的语义色）。
      // 那让按钮/分段控件/图表读成「第二强调色」，与「单一 Sage 强调」的
      // 设计铁律打架，也让画布语义色外泄。现归 Sage 家族：
      // 前景 = tealDark（压深档），容器 = tealWash，容器前景 = tealDark。
      // armed 从此只用于画布连线（节点描边/待命光），不再出现在主题里。
      secondary: isDark ? AppColors.tealDarkD : AppColors.tealDarkL,
      onSecondary: onPrimaryColor,
      secondaryContainer: isDark ? AppColors.tealWashD : AppColors.tealWashL,
      onSecondaryContainer: isDark ? AppColors.tealDarkD : AppColors.tealDarkL,
      tertiary: isDark ? AppColors.sandD : AppColors.sandL,
      surface: isDark ? AppColors.surfaceD : AppColors.surfaceL,
      surfaceContainerLow:
          isDark ? AppColors.surfaceLowD : AppColors.surfaceLowL,
      surfaceContainerHighest: isDark ? AppColors.tealWashD : AppColors.tealWashL,
      onSurface: isDark ? AppColors.inkD : AppColors.inkL,
      onSurfaceVariant: isDark ? AppColors.graphiteD : AppColors.graphiteL,
      error: isDark ? AppColors.lethalD : AppColors.lethalL,
      outline: borderColor,
    );

    final base = ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: isDark ? AppColors.canvasD : AppColors.canvasL,
      fontFamily: AppFonts.sans,
      fontFamilyFallback: AppFonts.sansFallback,
    );

    // v2.1n 修复：v2.1k/l 的 textTheme.copyWith 用「无 color」的 AppText
    // 样式整体替换了 M3 自带颜色的样式 → textTheme 各 style color 全为
    // null → DefaultTextStyle 断链 → TextPainter 渲染成白色 → 所有页面
    // 白字白底（golden + 实机双重证据）。现用确定性三元显式补色
    //（isDark 来自 brightness 参数，不依赖 AppColors._dark 全局残留）。
    final textTheme = base.textTheme
        .apply(
          fontFamily: AppFonts.sans,
          fontFamilyFallback: AppFonts.sansFallback,
        )
        .copyWith(
          // v2.23：titleLarge 不再覆写 letterSpacing:-0.2（拉丁向收紧），
          // 跟随 pageTitle 的中文正字距/行高，M3 对话框标题与页标题同节奏。
          titleLarge: AppText.pageTitle.copyWith(fontSize: 18),
          titleMedium: AppText.sectionTitle,
          bodyMedium: AppText.body.copyWith(
              color: isDark ? AppColors.inkD : AppColors.inkL),
          bodyLarge: AppText.body
              .copyWith(fontSize: 15, color: isDark ? AppColors.inkD : AppColors.inkL),
          bodySmall: AppText.caption.copyWith(
              color: isDark ? AppColors.graphiteD : AppColors.graphiteL),
          labelLarge: TextStyle(
            fontFamily: AppFonts.sans,
            fontFamilyFallback: AppFonts.sansFallback,
            fontWeight: FontWeight.w600,
            fontSize: 14,
            color: isDark ? AppColors.inkD : AppColors.inkL,
          ),
        )
        // 兜底：确保 M3 全部样式（含未被 copyWith 覆盖的 Headline/Title
        // 变体）继承正确的 onSurface 色，杜绝任何样式 color=null。
        .apply(
          bodyColor: isDark ? AppColors.inkD : AppColors.inkL,
          displayColor: isDark ? AppColors.inkD : AppColors.inkL,
        );

    return base.copyWith(
      textTheme: textTheme,
      // v6 全局图标双套化：所有未显式配色的 Icon 落到 onSurface
      //（浅色深墨灰 / 深色暖米白），杜绝 Material 默认色漏网。
      iconTheme: IconThemeData(color: isDark ? AppColors.inkD : AppColors.inkL),
      appBarTheme: AppBarTheme(
        toolbarHeight: 64,
        backgroundColor: isDark ? AppColors.canvasD : AppColors.canvasL,
        foregroundColor: isDark ? AppColors.inkD : AppColors.inkL,
        iconTheme: IconThemeData(color: isDark ? AppColors.inkD : AppColors.inkL),
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: AppText.pageTitle.copyWith(fontSize: 20),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) =>
            states.contains(WidgetState.selected)
                ? onPrimaryColor
                : (isDark ? AppColors.steelD : AppColors.steelL)),
        trackColor: WidgetStateProperty.resolveWith((states) =>
            states.contains(WidgetState.selected)
                ? (isDark ? AppColors.tealD : AppColors.tealL)
                : (isDark
                    ? AppColors.surfaceLowD
                    : AppColors.surfaceLowL)),
        trackOutlineColor: WidgetStateProperty.all(
            borderColor),
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: isDark ? AppColors.tealD : AppColors.tealL,
        inactiveTrackColor:
            isDark ? AppColors.surfaceLowD : AppColors.surfaceLowL,
        thumbColor: isDark ? AppColors.tealD : AppColors.tealL,
        overlayColor: isDark ? AppColors.tealWashD : AppColors.tealWashL,
      ),
      progressIndicatorTheme:
          ProgressIndicatorThemeData(color: isDark ? AppColors.tealD : AppColors.tealL),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: isDark ? AppColors.canvasD : AppColors.canvasL,
        indicatorColor: isDark ? AppColors.tealWashD : AppColors.tealWashL,
        selectedIconTheme:
            IconThemeData(color: isDark ? AppColors.tealDarkD : AppColors.tealDarkL),
        unselectedIconTheme:
            IconThemeData(color: isDark ? AppColors.steelD : AppColors.steelL),
        selectedLabelTextStyle: AppText.label.copyWith(
            color: isDark ? AppColors.tealDarkD : AppColors.tealDarkL,
            fontWeight: FontWeight.w700),
        unselectedLabelTextStyle:
            AppText.caption.copyWith(color: isDark ? AppColors.steelD : AppColors.steelL),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: isDark ? AppColors.surfaceD : AppColors.surfaceL,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusCard),
          side: BorderSide(color: borderColor),
        ),
        margin: const EdgeInsets.symmetric(vertical: 6),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: fieldFill,
        labelStyle: AppText.label,
        // v2.22.0：浮动标签停在 1px 描边的位置上，描边从字中间穿过去（「描边
        // 穿字」）。这里给浮动标签一枚**与 fillColor 逐位相同**的背景，行高收到
        // 1.2（≈14.4px 高的底块，正好盖住那截 1px 线）——信息架构不变：
        // 标签照旧浮动、照旧坐在上边框缺口处，只是不再与线互相穿插。
        // 没有用 FloatingLabelBehavior.never 去掉标签（那会丢掉「这个框是什么」
        // 的亲本信息）。像素是否真的干净由主线程逐张 golden 目检，不由单测断言。
        floatingLabelStyle: AppText.label.copyWith(
          fontSize: 12,
          height: 1.2,
          backgroundColor: fieldFill,
          color: isDark ? AppColors.inkD : AppColors.inkL,
        ),
        helperStyle: AppText.caption,
        errorStyle: AppText.caption.copyWith(
            color: isDark ? AppColors.lethalD : AppColors.lethalL),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusInput),
          borderSide: BorderSide(color: borderColor),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusInput),
          borderSide: BorderSide(color: borderColor),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusInput),
          borderSide: BorderSide(
              color: isDark ? AppColors.tealD : AppColors.tealL, width: 1.6),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: ButtonStyle(
          padding: WidgetStateProperty.all(
              const EdgeInsets.symmetric(horizontal: 20, vertical: 13)),
          // v2.22.0：28（全胶囊）→ radiusButton（12 圆角矩形，与输入框同族）
          shape: WidgetStateProperty.all(RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(radiusButton))),
          textStyle: WidgetStateProperty.all(AppText.action),
          // 按压反馈：-1px 位移 + 加深
          overlayColor: WidgetStateProperty.all(
              isDark ? AppColors.tealDarkD : AppColors.tealDarkL),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: ButtonStyle(
          padding: WidgetStateProperty.all(
              const EdgeInsets.symmetric(horizontal: 20, vertical: 13)),
          // v2.22.0：与 FilledButton 同一枚 radiusButton（不再各写 28）
          shape: WidgetStateProperty.all(RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(radiusButton))),
          side: WidgetStateProperty.all(
              BorderSide(color: borderColor)),
          foregroundColor:
              WidgetStateProperty.all(isDark ? AppColors.inkD : AppColors.inkL),
          textStyle: WidgetStateProperty.all(AppText.action),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: isDark ? AppColors.surfaceD : AppColors.surfaceL,
        indicatorColor: isDark ? AppColors.tealWashD : AppColors.tealWashL,
        elevation: 0,
        labelTextStyle: WidgetStateProperty.all(TextStyle(
          fontFamily: AppFonts.sans,
          fontFamilyFallback: AppFonts.sansFallback,
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: isDark ? AppColors.graphiteD : AppColors.graphiteL,
        )),
      ),
      dividerTheme: DividerThemeData(
          color: borderColor, thickness: 1),
      // v2/v3 语义开关统一样式：1px Border 描边 + Surface 底 + 8px 圆角；
      // 选中态 Sage Wash 底 + Sage 字（替掉 FilterChip 默认灰底）。
      chipTheme: base.chipTheme.copyWith(
        backgroundColor: isDark ? AppColors.surfaceD : AppColors.surfaceL,
        selectedColor: isDark ? AppColors.tealWashD : AppColors.tealWashL,
        disabledColor:
            isDark ? AppColors.surfaceLowD : AppColors.surfaceLowL,
        side: BorderSide(color: borderColor),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusChip)),
        labelStyle: AppText.label.copyWith(fontSize: 12),
        secondaryLabelStyle:
            AppText.label.copyWith(fontSize: 12, color: scheme.primary),
        checkmarkColor: scheme.primary,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: isDark ? AppColors.inkD : AppColors.inkL,
        contentTextStyle:
            AppText.body.copyWith(color: isDark ? AppColors.canvasD : AppColors.canvasL),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        behavior: SnackBarBehavior.floating,
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: scheme.primary,
        unselectedLabelColor: isDark ? AppColors.steelD : AppColors.steelL,
        indicatorColor: scheme.primary,
        labelStyle: const TextStyle(
          fontFamily: AppFonts.sans,
          fontFamilyFallback: AppFonts.sansFallback,
          fontWeight: FontWeight.w600,
        ),
      ),
      dropdownMenuTheme: DropdownMenuThemeData(
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: isDark ? AppColors.surfaceD : AppColors.surfaceL,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(radiusInput),
            borderSide:
                BorderSide(color: borderColor),
          ),
        ),
      ),
    );
  }
}

/// 徽标 Chip：Teal Wash 底 + Teal 字（变式名、遗传方式标签）。
/// v2.1k：改用 Theme.of(context).colorScheme —— 不依赖 AppColors._dark
/// 全局残留。MaterialApp rebuild 时 colorScheme 重新算，chip 颜色刷新。
class AppChip extends StatelessWidget {
  final String text;
  final IconData? icon;
  const AppChip(this.text, {super.key, this.icon});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: cs.primaryContainer,
        borderRadius: BorderRadius.circular(AppTheme.radiusChip),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 13, color: cs.primary),
            const SizedBox(width: 4),
          ],
          Text(
            text,
            style: TextStyle(
              fontFamily: AppFonts.sans,
              fontFamilyFallback: AppFonts.sansFallback,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: cs.onPrimaryContainer,
            ),
          ),
        ],
      ),
    );
  }
}

/// 本页工具面板 ☰：只开合页面控制区，不控制全局导航。
/// 无回调（页面独立构造/测试）时返回 null = 命令栏/AppBar 不渲染按钮。
Widget? appNavButton(VoidCallback? onPressed) => onPressed == null
    ? null
    : IconButton(
        tooltip: '工具面板',
        onPressed: onPressed,
        icon: const Icon(Icons.menu),
      );

/// 分区标题 + 顶部结构线（结果区文档流用）。
class AppSectionHeader extends StatelessWidget {
  final String title;
  final Widget? trailing;
  const AppSectionHeader(this.title, {super.key, this.trailing});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Divider(height: 24),
        Row(
          children: [
            Text(title, style: AppText.sectionTitle),
            const Spacer(),
            ?trailing,
          ],
        ),
        const SizedBox(height: 8),
      ],
    );
  }
}