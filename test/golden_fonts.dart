// golden_fonts.dart —— golden 截图统一的字体装载（R10-5）
//
// 【为什么需要这个文件】
// `flutter test` 里没显式装载的字体 family 会落到引擎的测试字体上，
// 所有字形渲染成同一个空心方框（.notdef）。R10-5 之前，仓库里 8 个 golden
// harness 只装载了两个**文字**字体（PingFang SC / Microsoft YaHei，从
// C:\Windows\Fonts\msyh.ttc），**从未装载 MaterialIcons**。
// 后果：全部 golden 里 `Icon(...)` 都是同一个空框 —— 文字正常、图标全废。
// 这意味着任何 icon 改动（例如 R10-4a 把 school_outlined 拆成
// tune_outlined / cast_outlined / info_outline）对 golden 完全不可见，
// 「golden 没红」不构成「icon 换对了」的证据。本文件把图标字体补上。
//
// 【family 名为什么是 'MaterialIcons'】
// 照抄 Flutter SDK：`flutter/packages/flutter/lib/src/material/icons.dart`
// 里每个 `Icons.xxx` 都是 `IconData(0x…, fontFamily: 'MaterialIcons')`
// （本仓 pubspec.yaml 未声明任何自定义字体，也无 fontPackage，
//  所以就是裸 family 名，不带 package 前缀）。写错一个字符 =
//  FontLoader 成功但一个 glyph 都命中不到，icon 仍是空框 ——
//  静默失效，所以下面 [assertMaterialIconsLoaded] 会自检。
//
// 【为什么找不到字体要抛异常而不是跳过】
// 跳过 = 回到「icon 静默变空框、回归网失效」的老坑，而且更难发现。
// 换机器 / 换 SDK 时立刻炸出来，比录出一批假 golden 便宜得多。
//
// 【R11-3：中文方框盲区】
// R10-5 只修了 icon（`cjk: false`），有 5 个 harness
// （ui_screenshot / edge_style / family_bus_render / combo_bucket_render /
// _v21j_curri）历史上**一个文字字体都没装**，它们录的 14 张 golden 里
// 中文全是空心方框。危险之处在于：布局是按方框的宽度算的，所以这类
// golden 对"中文文本布局"零敏感 —— 换文案 / 加大字号 / 改 padding 全都
// 检不出来，是**假绿**。R11-3 把 `cjk` 的默认值从 false 翻成 true：
// 新写 harness 忘了传参会重新制造同一个盲区，而"多装一个字体"的代价
// 只是慢几十毫秒。字体来源同时从写死的 `C:\Windows\Fonts\msyh.ttc`
// 改成 [resolveCjkFont]（环境变量 → 平台系统字体目录 → 抛错列出全部试过路径）。
//
// 【R12-1：等宽（mono）字体盲区 —— 本项目最严重的一条】
// R10-5 补了 icon，R11-3 补了中文，**但没有补等宽字体**。而等宽字体
// 在这个应用里承载的是**最核心的内容**：基因型（`AaBb` / `AA` / `ab`）、
// 配子、交换值 `0.5`、分离比与缩放百分比。theme.dart 把它们全挂在
// `AppFonts.mono`（3 个 text style：genotype / monoFigure / monoSmall，
// 外加 ui/step_card.dart 的 RatioPill 1 处）上，而 harness 从没装载过
// 这个 family —— 于是**全部 golden 里的基因型都是空心方框**。
// 对遗传计算器来说「基因型是方框」比「中文标签是方框」更致命：
// 那是页面的主内容本身，而且遗传计算正确性（金标准表 9331）全靠它。
//
// 【R12-1 实测结论：必须注册成 'JetBrains Mono'，注册成 'Consolas' 无效】
// theme.dart 声明的是 `fontFamily: 'JetBrains Mono'` +
// `fontFamilyFallback: ['Consolas', 'Menlo', 'monospace']`，直觉上
// 「注册成 Consolas，让 fallback 兜住」就够了。**实测是错的**：
//   - 探针 A（只把 consola.ttf 注册成 'Consolas'，primary 仍写
//     'JetBrains Mono'）：渲染 'AaBb' 的像素与「family 从没被装载」的
//     对照组**逐字节相同**（都是 232B 的 .notdef 方框）→ fallback 没有兜住。
//   - 探针 B（注册成 'JetBrains Mono'）：1526B vs 对照 232B，**字形是真字**。
// 原因：flutter_tester 的字体集合里没有的 family 不是"交给 fallback 列表
// 继续找"，而是直接落回引擎测试字体（FlutterTest，全方框）。
// 所以 [loadGoldenFonts] 里的**载荷是 `kMonoFamily` 那个名字**；
// 顺带也注册 'Consolas' 兜住「将来某个 widget 直接写死 Consolas」的情况，
// 但那只是防御性冗余，真正生效的是第一个。
//
// 为防 family 名与 theme 声明漂移，kMonoFamily **不写字符串字面量**，
// 直接取 [AppFonts.mono]；[assertMonoLoaded] 再从 `AppText.genotype`
// 反向校验一次。
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:biology/theme.dart' show AppFonts, AppText;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderRepaintBoundary;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart' show WidgetTester, find;

/// Material Icons 在 Flutter 内部注册的 family 名（逐字照抄 SDK，见文件头）。
const String kMaterialIconsFamily = 'MaterialIcons';

/// 换机器 / CI 时用环境变量显式指定字体文件：
/// `BIOLOGY_MATERIAL_ICONS_FONT=<materialicons-regular.otf 的绝对路径>`
const String kMaterialIconsFontEnv = 'BIOLOGY_MATERIAL_ICONS_FONT';

/// 字体文件在 Flutter SDK 里的相对路径（各平台一致）。
const String _kSdkRelativePath = 'bin/cache/artifacts/material_fonts';

/// SDK 里字体文件名大小写在各平台不一致：
/// Windows/Linux 上是全小写 `materialicons-regular.otf`，
/// macOS 上是 `MaterialIcons-Regular.otf`。所以按小写比对。
const String _kFontFileName = 'materialicons-regular.otf';

/// 中文界面用的两个 family 名（AppFonts.sans / .sansFallback，见 lib/theme.dart
/// 225-227 行；主题把整站文字都挂在这两个 family 上，所以**只要把它们装载上**，
/// 全应用的中文就都从方框变真字，无需改任何 widget）。
const String kSansFamily = 'PingFang SC';
const String kSansFamilyFallback = 'Microsoft YaHei';

/// 换机器 / CI 时用环境变量显式指定中文字体文件：
/// `BIOLOGY_CJK_FONT=<msyh.ttc / PingFang.ttc / NotoSansCJK-Regular.ttc 的绝对路径>`
///
/// 【为什么需要它】R10-5 之前这里写死 `C:\Windows\Fonts\msyh.ttc`。写死的后果是
/// 换机 / 换平台（macOS 开发者、Linux CI）直接 `File.readAsBytesSync` 抛
/// FileSystemException，报错跟"字体没装"毫无关系，排查成本高；更糟的是有人
/// 为了跑通测试随手改成本机某个字体文件，golden 就静默换了一套字形基线。
/// 现在改成"环境变量 → 平台系统字体目录（按优先级找候选文件名）→ 抛错并列出
/// 试过的全部路径"，与 [kMaterialIconsFontEnv] 同一套形状。
const String kCjkFontEnv = 'BIOLOGY_CJK_FONT';

/// 中文字体候选文件名，**按优先级**。只写文件名不写绝对路径：盘符 / 装法各机
/// 不同，绝对路径会立刻失效（见 [kCjkFontEnv]）。
const List<String> _kCjkFontNames = <String>[
  'msyh.ttc', // 微软雅黑：Windows 自带，本仓自 R10-5 起的既有基线
  'msyhl.ttc', // 微软雅黑 Light：雅黑本体缺失时的同族次选（字形基本一致）
  'PingFang.ttc', // 苹方：macOS 自带
  'NotoSansCJK-Regular.ttc', // Noto Sans CJK：Linux 常见
  'SourceHanSansSC-Regular.otf', // 思源黑体：手工装的开源可选项
  'simsun.ttc', // 宋体：极老 Windows 的兜底，字宽与雅黑不同
];

/// 中文字体太小 = 拿错文件（例如误指了 MaterialIcons 那种 1.6MB 字体）。
/// 真正覆盖常用汉字的 CJK 字体最小也在 MB 级（雅黑 19.7MB / 苹方 ~20MB）。
/// 这条是**静默失效的护栏**：装上一个不含汉字的字体不会报错，只会又变回方框。
const int _kCjkFontMinBytes = 2 * 1024 * 1024;

/// 等宽字体在 Flutter 里的 family 名。**取自主题本身**（[AppFonts.mono]）
/// 而不是再抄一遍字符串 —— 这个名字写错就是静默失效（FontLoader 成功、
/// glyph 一个不命中、golden 里全是方框），抄一遍必然会漂。
const String kMonoFamily = AppFonts.mono;

/// 主题里 mono 的 fallback 列表（[AppFonts.monoFallback]）的第一项，
/// 也就是**实测可用的那支系统字体**在 Flutter 里的裸 family 名。
/// 之所以也注册它：万一将来有 widget 直接写 `fontFamily: 'Consolas'`，
/// 不注册就又是方框。见文件头「R12-1 实测结论」。
const String kMonoFallbackFamily = 'Consolas';

/// 换机器 / CI 时用环境变量显式指定等宽字体文件：
/// `BIOLOGY_GOLDEN_MONO_FONT=<JetBrainsMono-Regular.ttf / consola.ttf / … 的绝对路径>`
///
/// 【为什么需要它】与 [kCjkFontEnv] 同构：写死路径换机即挂，而"随手改成本机
/// 某个字体"会让 golden 静默换掉等宽字形基线（真机上是 JetBrains Mono，
/// 录出来变成 Courier New，字宽全变）。
const String kMonoFontEnv = 'BIOLOGY_GOLDEN_MONO_FONT';

/// 等宽字体候选文件名，**按优先级**。只写文件名不写绝对路径（同 [kCjkFontEnv]）。
/// 排序理由：先试真机真正会命中的一支 —— 主题的 fallback 首选项 Consolas
/// 在 Windows 上是系统自带、且与 JetBrains Mono 一样是等宽，录出的字宽
/// 基线最有代表性；再退到同为系统自带的 Courier New / Lucida Console；
/// 最后才是"手工装了 JetBrains Mono 本体"的场合（此时反而说明机器有真字体）。
const List<String> _kMonoFontNames = <String>[
  'consola.ttf', // Consolas：Windows 自带，且是 AppFonts.monoFallback 首项
  'cour.ttf', // Courier New：Windows 自带，等宽兜底
  'lucon.ttf', // Lucida Console：Windows 自带，等宽兜底
  'JetBrainsMono-Regular.ttf', // 真机若装了 JetBrains Mono 本体，优先用真字体
  'JetBrainsMono-VariableFont_wght.ttf',
  'Menlo.ttc', // Menlo：macOS 自带（fallback 第 2 项）
  'DejaVuSansMono.ttf', // DejaVu Sans Mono：Linux 常见
  'NotoSansMono-Regular.ttf', // Noto Sans Mono：Linux 常见
];

/// 等宽字体文件的下限（字节）。纯拉丁等宽字体天然比 CJK 小一个量级
/// （实测 Consolas 453KB / Courier New 817KB / Lucida Console 111KB），
/// 低于 50KB 基本是指错了文件（例如某个符号子集或图标字体）。
/// 注意这条**不能**照抄 CJK 的 MB 级下限 —— 那个值会把三个系统等宽字体
/// 全部误杀。
const int _kMonoFontMinBytes = 50 * 1024;

/// 解析出 MaterialIcons 字体文件；找不到就抛 [StateError] 并列出试过的路径。
File resolveMaterialIconsFont() {
  final tried = <String>[];

  final override = Platform.environment[kMaterialIconsFontEnv];
  if (override != null && override.isNotEmpty) {
    final f = File(override);
    if (f.existsSync()) return f;
    throw StateError(
      '$kMaterialIconsFontEnv 指向的文件不存在：$override\n'
      '要么修正该环境变量，要么清掉它让代码自己从 Flutter SDK 里找。',
    );
  }

  for (final root in _flutterRootCandidates()) {
    tried.add('$_kSdkRelativePath/$_kFontFileName  (SDK root: $root)');
    final hit = _findFontInSdkRoot(root);
    if (hit != null) return hit;
  }

  throw StateError(
    '找不到 MaterialIcons 字体文件，golden 里的 icon 会全部退化成空心方框。\n'
    '已尝试：\n  ${tried.join('\n  ')}\n'
    '修法（任选其一）：\n'
    '  1) 设 $kMaterialIconsFontEnv=<字体绝对路径>\n'
    '  2) 设 FLUTTER_ROOT=<flutter sdk 根目录>\n'
    '  3) 先跑一次 flutter precache 把 material_fonts artifact 拉下来。',
  );
}

/// 在一个 Flutter SDK 根目录下找字体文件；找到返回，找不到返回 null。
File? _findFontInSdkRoot(String sdkRoot) {
  final dir = Directory('$sdkRoot/$_kSdkRelativePath');
  if (!dir.existsSync()) return null;
  final wanted = _kFontFileName.toLowerCase();
  for (final entity in dir.listSync()) {
    if (entity is File && entity.path.toLowerCase().endsWith(wanted)) {
      return entity;
    }
  }
  return null;
}

/// 猜 Flutter SDK 根目录的顺序（都不含任何本机硬编码盘符）：
///  1. `FLUTTER_ROOT` 环境变量；
///  2. 从 `Platform.resolvedExecutable` 向上回溯 —— `flutter test` 下它是
///     `<root>/bin/cache/artifacts/engine/<platform>/flutter_tester.exe`，
///     往上最多 8 层逐层试 `bin/cache/artifacts/material_fonts`。
///     这样换 SDK 位置 / 换平台都不用改代码。
List<String> _flutterRootCandidates() {
  final out = <String>[];
  final envRoot = Platform.environment['FLUTTER_ROOT'];
  if (envRoot != null && envRoot.isNotEmpty) out.add(envRoot);

  var dir = File(Platform.resolvedExecutable).parent.path;
  for (var i = 0; i < 8; i++) {
    out.add(dir);
    final parent = Directory(dir).parent.path;
    if (parent == dir) break;
    dir = parent;
  }
  return out;
}

ByteData _readFont(String path) {
  final bytes = File(path).readAsBytesSync();
  return ByteData.view(bytes.buffer, bytes.offsetInBytes, bytes.lengthInBytes);
}

/// 解析出中文字体文件；找不到 / 拿到明显不对的文件就抛 [StateError]。
///
/// 顺序与 [resolveMaterialIconsFont] 同构：
///   1. 环境变量 [kCjkFontEnv]（显式指定，不存在则直接抛，不静默回落）；
///   2. 运行时推导出的平台系统字体目录里按 [_kCjkFontNames] 优先级找；
///   3. 全都落空 → 抛错并把试过的每一个路径都列出来 + 三条修法。
///
/// 【为什么第 2 步要逐层回溯目录】Linux 的 Noto 通常在
/// `/usr/share/fonts/opentype/noto/` 下面（Debian/Fedora 布局不一致），
/// 只看根目录会漏。所以限定深度的小 BFS（[_kCjkSearchMaxDepth] 层）足够，
/// 又不会像整盘 find 那样在大目录上卡住。
File resolveCjkFont() {
  final tried = <String>[];

  final override = Platform.environment[kCjkFontEnv];
  if (override != null && override.isNotEmpty) {
    final f = File(override);
    if (!f.existsSync()) {
      throw StateError(
        '$kCjkFontEnv 指向的文件不存在：$override\n'
        '要么修正该环境变量，要么清掉它让代码自己在系统字体目录里找。',
      );
    }
    _assertPlausibleCjkFont(f);
    return f;
  }

  for (final dir in _systemFontDirCandidates()) {
    for (final name in _kCjkFontNames) {
      final hit = _findFontByName(dir, name);
      if (hit == null) continue;
      tried.add('$dir/**/$name  → 命中 ${hit.path}');
      try {
        _assertPlausibleCjkFont(hit);
        return hit;
      } on StateError catch (e) {
        // 找到了同名但明显不对的文件（例如被同名的小图标字体占位）：
        // 记下来继续往下找，而不是立刻炸——最终错误里会带上这条线索。
        tried.add('  ↳ 跳过：$e');
      }
    }
  }

  throw StateError(
    '找不到中文字体文件，golden 里的所有中文都会退化成空心方框'
    '（回归网对"中文文本布局"完全失效）。\n'
    '已尝试：\n  ${tried.isEmpty ? '(系统字体目录一个都没打开成功)' : tried.join('\n  ')}\n'
    '修法（任选其一）：\n'
    '  1) 设 $kCjkFontEnv=<中文字体绝对路径>（推荐，可复现）\n'
    '  2) 装一个常见中文字体（Windows 自带微软雅黑；macOS 自带苹方；\n'
    '     Linux 装 fonts-noto-cjk）后重跑\n'
    '  3) 确认 %WINDIR% / \$HOME 环境变量在当前 shell 里可见（见错误里的目录列表）。',
  );
}

/// 中文字体至少得 [_kCjkFontMinBytes] 大；太小说明指错了文件。
void _assertPlausibleCjkFont(File f) {
  final len = f.lengthSync();
  if (len < _kCjkFontMinBytes) {
    throw StateError(
      '中文字体文件可疑地小：${f.path}（$len 字节 < $_kCjkFontMinBytes）。\n'
      '覆盖常用汉字的 CJK 字体至少几 MB（微软雅黑 19.7MB / 苹方 ~20MB）。\n'
      '这个大小更像是图标字体或西文字体——装上去也会渲染成方框。',
    );
  }
}

/// 解析出等宽（mono）字体文件；找不到 / 拿到明显不对的文件就抛 [StateError]。
///
/// 顺序与 [resolveCjkFont] / [resolveMaterialIconsFont] 同构：
///   1. 环境变量 [kMonoFontEnv]（显式指定，不存在则直接抛，不静默回落）；
///   2. 运行时推导出的平台系统字体目录里按 [_kMonoFontNames] 优先级找；
///   3. 全都落空 → 抛错并把试过的每一个路径都列出来 + 三条修法。
///
/// 【为什么绝不能静默跳过】R12-1 之前 harness 根本没这一段，于是全部 golden
/// 的基因型（`AaBb`）都是方框，测试照样全绿 —— 这正是本项目踩过的最深的一个坑。
/// 找不到就炸，比录出一批"基因型是方框"的假 golden 便宜得多。
///
/// 【候选里 Consolas 排第一】因为主题 [AppFonts.monoFallback] 的首项就是
/// Consolas，真机上没装 JetBrains Mono 时**实际渲染的就是 Consolas**；
/// 用它录出来的字宽基线才与真机一致。
File resolveMonoFont() {
  final tried = <String>[];

  final override = Platform.environment[kMonoFontEnv];
  if (override != null && override.isNotEmpty) {
    final f = File(override);
    if (!f.existsSync()) {
      throw StateError(
        '$kMonoFontEnv 指向的文件不存在：$override\n'
        '要么修正该环境变量，要么清掉它让代码自己在系统字体目录里找。',
      );
    }
    _assertPlausibleMonoFont(f);
    return f;
  }

  for (final dir in _systemFontDirCandidates()) {
    for (final name in _kMonoFontNames) {
      final hit = _findFontByName(dir, name);
      if (hit == null) continue;
      tried.add('$dir/**/$name  → 命中 ${hit.path}');
      try {
        _assertPlausibleMonoFont(hit);
        return hit;
      } on StateError catch (e) {
        // 同名但明显不对的文件：记下来继续往下找，最终错误里会带上这条线索。
        tried.add('  ↳ 跳过：$e');
      }
    }
  }

  throw StateError(
    '找不到等宽（mono）字体文件，golden 里的**基因型 / 配子 / 比例数字 '
    '会全部退化成空心方框**（例如本应显示 AaBb 的位置显示成 □□□□）——\n'
    '这是遗传计算器最核心的内容，等于 golden 对基因型完全失明。\n'
    '已尝试：\n  ${tried.isEmpty ? '(系统字体目录一个都没打开成功)' : tried.join('\n  ')}\n'
    '修法（任选其一）：\n'
    '  1) 设 $kMonoFontEnv=<等宽字体绝对路径>（推荐，可复现）\n'
    '  2) Windows 上装/启用 Consolas（控制面板→字体，文件通常是 consola.ttf）；\n'
    '     macOS 自带 Menlo；Linux 装 fonts-dejavu-core\n'
    '  3) 确认 %WINDIR% / \$HOME 环境变量在当前 shell 里可见（见错误里的目录列表）。',
  );
}

/// 等宽字体至少得 [_kMonoFontMinBytes] 大；太小说明指错了文件。
///
/// 下限刻意比 [_kCjkFontMinBytes] 小两个数量级：等宽字体是纯拉丁，
/// 系统自带的 Lucida Console 只有 111KB，照抄 CJK 的 MB 级下限会误杀。
void _assertPlausibleMonoFont(File f) {
  final len = f.lengthSync();
  if (len < _kMonoFontMinBytes) {
    throw StateError(
      '等宽字体文件可疑地小：${f.path}（$len 字节 < $_kMonoFontMinBytes）。\n'
      '系统等宽字体实测大小：Lucida Console 111KB / Consolas 453KB / '
      'Courier New 817KB。\n'
      '小于 50KB 更像是某个符号子集或图标字体——装上去基因型还是会变方框。',
    );
  }
}

/// 各平台常见的系统字体目录。全部由**运行时环境**推导（%WINDIR% / $HOME /
/// Platform.operatingSystem），只有 macOS 的固定系统路径是硬编码的常量。
List<String> _systemFontDirCandidates() {
  final out = <String>[];
  void add(String p) {
    if (p.isEmpty) return;
    final norm = p.replaceAll('\\', '/');
    if (!out.contains(norm)) out.add(norm);
  }

  switch (Platform.operatingSystem) {
    case 'windows':
      // 盘符可能不在 C:（装到 D: 的机器 / 定制镜像），所以先读环境变量。
      final windir = Platform.environment['WINDIR'] ??
          Platform.environment['SystemRoot'] ??
          r'C:\Windows';
      add('$windir\\Fonts');
      add('$windir\\Fonts\\local'); // 免安装字体（右键装）落这里
    case 'macos':
      add('/System/Library/Fonts');
      add('/Library/Fonts');
      add('${Platform.environment['HOME'] ?? ''}/Library/Fonts');
    default: // linux / fuchsia
      add('/usr/share/fonts');
      add('/usr/local/share/fonts');
      add('${Platform.environment['HOME'] ?? ''}/.fonts');
      add('${Platform.environment['HOME'] ?? ''}/.local/share/fonts');
  }
  return out;
}

/// 系统字体目录搜索的最大回溯层数（见 [resolveCjkFont] 的说明）。
const int _kCjkSearchMaxDepth = 3;

/// 在目录树里按文件名找字体（大小写不敏感），限定深度；找到返回，找不到 null。
File? _findFontByName(String root, String fileName) {
  final rootDir = Directory(root);
  if (!rootDir.existsSync()) return null;
  final wanted = fileName.toLowerCase();
  var frontier = <Directory>[rootDir];
  for (var depth = 0; depth < _kCjkSearchMaxDepth; depth++) {
    final next = <Directory>[];
    for (final dir in frontier) {
      List<FileSystemEntity> children;
      try {
        children = dir.listSync(followLinks: false);
      } on FileSystemException {
        continue; // 无权限的目录（少见但存在）直接跳过
      }
      for (final entity in children) {
        if (entity is File) {
          if (entity.path.toLowerCase().endsWith(wanted)) return entity;
        } else if (entity is Directory) {
          next.add(entity);
        }
      }
    }
    if (next.isEmpty) return null;
    frontier = next;
  }
  return null;
}

// ─── KaTeX 数学字体（flutter_math_fork 公式渲染）──────────────────────────
//
// 【为什么测试里必须手动装】flutter_math_fork 把 12 个 KaTeX 子族声明在
// **它自己的** pubspec.yaml 里。生产打包（flutter build / flutter run）会沿
// 依赖图把这些包字体纳入 FontManifest.json，family 注册成
// `packages/flutter_math_fork/KaTeX_*`（见 fork 的
// `src/render/symbols/make_symbol.dart:140`），真机渲染正常。但
// `flutter test` 的 flutter_tester **不自动注册** app / 包的 FontManifest
//（它把字体回退沙箱到 artifact 缓存目录，见 flutter_tools
// `src/test/font_config_manager.dart`；测试器启动器也不读 FontManifest.json）
// —— 不手动 FontLoader 就会落回引擎测试字体，公式每个字形都是 .notdef
// 空心方框。这与 MaterialIcons / 等宽字体当年的坑**完全同形**（见文件头
// R10-5 / R12-1）：`Math.ast` 解析成功 ≠ 字形渲染成功，AST 全绿也拦不住
// "整屏公式变方框"。
//
// 【family 名必须带 `packages/flutter_math_fork/` 前缀】renderer 用的是
// `'packages/flutter_math_fork/KaTeX_${子族}'` 这个**已带前缀**的裸字符串
//（不是 `fontFamily: 'KaTeX_Main', package: 'flutter_math_fork'`）。所以
// FontLoader 也必须注册成同一个带前缀的名字，差一个字符就是静默失效
//（FontLoader 成功、字形一个不命中、公式仍全是方框）——
// [assertKatexGlyphsLoaded] 用像素比对来兜这个静默坑。

/// flutter_math_fork 渲染公式时使用的 family 前缀（make_symbol.dart:140）。
const String kKatexFamilyPrefix = 'packages/flutter_math_fork/KaTeX_';

/// flutter_math_fork 声明的 12 个 KaTeX 子族（与其 pubspec.yaml 逐一对应）。
/// 渲染路径里 FontOptions.fontFamily ∈ {Main,Math,AMS,Size1..4,Caligraphic,
/// Fraktur,SansSerif,Script,Typewriter}，再经 make_symbol 拼上 [kKatexFamilyPrefix]。
const List<String> kKatexSubfamilies = <String>[
  'Main',
  'Math',
  'AMS',
  'Size1',
  'Size2',
  'Size3',
  'Size4',
  'Caligraphic',
  'Fraktur',
  'SansSerif',
  'Script',
  'Typewriter',
];

/// 换机器 / CI 时用环境变量显式指定 katex 字体目录：
/// `BIOLOGY_KATEX_FONTS_DIR=<flutter_math_fork .../lib/katex_fonts/fonts 的绝对路径>`
const String kKatexFontEnv = 'BIOLOGY_KATEX_FONTS_DIR';

/// 探测用的「必定未注册」family：用它渲染出的一定是引擎测试字体的 .notdef。
/// 与真实 KaTeX family 逐字节比对 —— 相同即说明 KaTeX family 也没命中字形。
const String _kNotdefControlFamily = '__katex_notdef_control_probe__';

/// 解析 flutter_math_fork 包内的 `lib/katex_fonts/fonts` 目录。
///
/// 顺序与 [resolveCjkFont] / [resolveMonoFont] 同构，但来源不是系统字体目录，
/// 而是 **package 解析结果**：
///   1. 环境变量 [kKatexFontEnv]（显式指定，不存在则抛，不静默回落）；
///   2. 读 `.dart_tool/package_config.json` 里 flutter_math_fork 的
///      `rootUri`（与构建用的是**同一份**解析，换缓存路径 / 换机都稳），
///      拼上 `lib/katex_fonts/fonts`；
///   3. 全都落空 → 抛错并列出线索。
Directory resolveKatexFontsDir() {
  final override = Platform.environment[kKatexFontEnv];
  if (override != null && override.isNotEmpty) {
    final d = Directory(override);
    if (!d.existsSync()) {
      throw StateError('$kKatexFontEnv 指向的目录不存在：$override\n'
          '要么修正该环境变量，要么清掉它让代码自己从 package_config 解析。');
    }
    return d;
  }

  final pcFile = File('.dart_tool/package_config.json');
  if (!pcFile.existsSync()) {
    throw StateError(
        '找不到 .dart_tool/package_config.json（cwd=${Directory.current.path}），'
        '无法定位 flutter_math_fork 的 katex 字体。\n'
        '修法：设 $kKatexFontEnv=<katex_fonts/fonts 绝对路径>，或先 flutter pub get。');
  }

  final dynamic pc = jsonDecode(pcFile.readAsStringSync());
  final List<dynamic> packages = pc['packages'] as List<dynamic>;
  dynamic entry;
  for (final dynamic p in packages) {
    if (p['name'] == 'flutter_math_fork') {
      entry = p;
      break;
    }
  }
  if (entry == null) {
    throw StateError('package_config.json 里没有 flutter_math_fork'
        '（依赖没解析？先 flutter pub get）。\n'
        '修法：设 $kKatexFontEnv=<katex_fonts/fonts 绝对路径>。');
  }

  // rootUri 相对 package_config.json 所在目录（.dart_tool）解析；
  // 若是绝对 file:// URI 则直接生效。两种写法都兼容。
  // ⚠️ Dart 的 `base.resolveUri(ref)` = 以 base 为基准解析 reference ref。
  // 写反（`ref.resolveUri(base)`）会把 base 自己解析出来，得到 .dart_tool。
  final String baseDir = Directory('.dart_tool').absolute.path.replaceAll('\\', '/');
  final Uri base = Uri.parse('file:///$baseDir/');
  final Uri root = base.resolveUri(Uri.parse(entry['rootUri'] as String));
  final Directory fonts = Directory('${root.toFilePath()}/lib/katex_fonts/fonts');
  if (!fonts.existsSync()) {
    throw StateError('katex 字体目录不存在：${fonts.path}\n'
        'flutter_math_fork 的 pubspec 声明了 lib/katex_fonts/fonts 下的 12 个子族，'
        '目录缺失 = 公式会渲染成 .notdef 方框。\n'
        '修法：设 $kKatexFontEnv=<正确的 katex_fonts/fonts 路径>，或 flutter pub get 重拉包。');
  }
  return fonts;
}

/// 装载 flutter_math_fork 的 12 个 KaTeX 子族（每个子族挂上它在
/// `katex_fonts/fonts` 下的所有 .ttf —— Regular/Italic/Bold 由引擎按字体
/// 内部元数据自动挑选，无需在此标注字重/字形）。
Future<void> _loadKatexFonts() async {
  final Directory dir = resolveKatexFontsDir();
  final List<File> files =
      dir.listSync().whereType<File>().toList(growable: false);
  for (final String sub in kKatexSubfamilies) {
    final String family = '$kKatexFamilyPrefix$sub';
    final List<File> matching = files.where((File f) {
      final String base = f.uri.pathSegments.last.toLowerCase();
      return base.startsWith('katex_${sub.toLowerCase()}-') &&
          base.endsWith('.ttf');
    }).toList();
    if (matching.isEmpty) {
      throw StateError('KaTeX 子族 $sub：在 ${dir.path} 下找不到任何 '
          'KaTeX_$sub-*.ttf —— 公式里用到该子族的字形会是 .notdef 方框。');
    }
    final FontLoader loader = FontLoader(family);
    for (final File f in matching) {
      loader.addFont(Future<ByteData>.value(_readFont(f.path)));
    }
    await loader.load();
  }
}

/// KaTeX 公式字形自检（**像素证据**，非 AST）：确认 [kKatexFamilyPrefix]Main /
/// Math 真的渲染出字形、而不是 .notdef 方框。
///
/// 原理：把探测字符分别用「KaTeX family」和一个**必定未注册**的对照 family
///（[_kNotdefControlFamily]）渲染到 RepaintBoundary 并抓 RGBA 原始像素——
/// 若两者逐字节相同，说明 KaTeX family 也落到了引擎测试字体（= .notdef 方框），
/// 即 FontLoader 缺失 / family 名写错。这是字形级证据：`Math.ast` 再正确也
/// 拦不住"整屏公式变方框"，只有像素比对能兜住这个静默坑。
///
/// 必须在 [loadGoldenFonts] 之后调用。
Future<void> assertKatexGlyphsLoaded(WidgetTester tester) async {
  // Main（数字/运算符/直立体）与 Math（斜体变量）覆盖公式绝大多数字形；
  // 12 个子族一起装载，任一为 .notdef 即代表整个 katex FontLoader 缺失。
  const List<(String, String)> probes = <(String, String)>[
    ('Main', 'N'),
    ('Main', '0'),
    ('Math', 'x'),
  ];
  for (final (String sub, String ch) in probes) {
    final String family = '$kKatexFamilyPrefix$sub';
    final Uint8List real = await _captureGlyph(tester, family, ch);
    final Uint8List control = await _captureGlyph(tester, _kNotdefControlFamily, ch);
    if (_bytesEqual(real, control)) {
      throw StateError(
          'KaTeX 字形自检失败：family=$family 渲染 “$ch” 的像素与「未注册对照」'
          '逐字节相同 ⇒ 该 family 仍是 .notdef 方框（公式会显示为空心框）。\n'
          '根因通常是二者之一：\n'
          '  1) loadGoldenFonts 没装载 katex（katex 参数被传 false，或装载块被删）；\n'
          '  2) family 名没带 packages/flutter_math_fork/ 前缀（写错即静默失效）。\n'
          '修法：确保 loadGoldenFonts() 走 _loadKatexFonts()，且 '
          'kKatexFamilyPrefix 与 fork 的 make_symbol.dart:140 逐字一致。');
    }
  }
}

/// 把单个字符渲染进 RepaintBoundary，抓回 RGBA 原始字节。
Future<Uint8List> _captureGlyph(
    WidgetTester tester, String family, String ch) async {
  const Key k = Key('_katexGlyphProbeBoundary');
  await tester.pumpWidget(
    Directionality(
      textDirection: TextDirection.ltr,
      child: RepaintBoundary(
        key: k,
        child: SizedBox(
          width: 72,
          height: 72,
          child: DecoratedBox(
            decoration: const BoxDecoration(color: Color(0xFFFFFFFF)),
            child: Center(
              child: Text(
                ch,
                textDirection: TextDirection.ltr,
                style: TextStyle(
                  fontFamily: family,
                  fontSize: 56,
                  color: const Color(0xFF000000),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  final RenderRepaintBoundary boundary =
      tester.renderObject<RenderRepaintBoundary>(find.byKey(k));
  late final Uint8List bytes;
  await tester.runAsync(() async {
    final ui.Image img = await boundary.toImage(pixelRatio: 1.0);
    final ByteData? data =
        await img.toByteData(format: ui.ImageByteFormat.rawRgba);
    bytes = data!.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
    img.dispose();
  });
  return bytes;
}

bool _bytesEqual(Uint8List a, Uint8List b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// 装载 golden 需要的字体。
///
/// [cjk] 为 true 时额外装载中文文字字体（full-scan / 交互截图 / 课标 等 harness
/// 一直这么做）；为 false 时只装图标字体。
///
/// R11-3 的变化：曾经有 5 个 harness（ui_screenshot / edge_style /
/// family_bus_render / combo_bucket_render / _v21j_curri）传 `cjk: false`，
/// 于是它们录下的 14 张 golden 里中文全是方框，而**布局几何按方框宽度算**——
/// 换文案 / 加大字号 / 改 padding 都检不出来（假绿）。现在这 5 个也传
/// `cjk: true`，全仓 14 个 golden harness 一律有真字形。
///
/// 图标 / 中文字体找不到时都抛 [StateError]（见文件头「为什么找不到要抛异常」）。
///
/// R12-1 的变化：新增 [mono]（默认 **true**）。理由与 R11-3 把 `cjk`
/// 默认值翻成 true 完全一样 —— 等宽字体承载的是基因型这个核心内容，
/// 新写 harness 忘了传参会**重新制造同一个盲区**，"多装一个字体"的代价
/// 只是慢几十毫秒。
Future<void> loadGoldenFonts(
    {bool cjk = true, bool mono = true, bool katex = true}) async {
  final icons = resolveMaterialIconsFont();
  final data = _readFont(icons.path);
  await (FontLoader(kMaterialIconsFamily)..addFont(Future.value(data))).load();

  if (cjk) {
    final cjkData = _readFont(resolveCjkFont().path);
    // 同一个字体文件挂两个 family 名：主题里 sans = 'PingFang SC'、
    // sansFallback = 'Microsoft YaHei'（lib/theme.dart 225-227），两个都要装，
    // 否则落到 fallback 的那一支仍然是方框。
    await (FontLoader(kSansFamily)..addFont(Future.value(cjkData))).load();
    await (FontLoader(kSansFamilyFallback)..addFont(Future.value(cjkData))).load();
  }

  if (mono) {
    final monoData = _readFont(resolveMonoFont().path);
    // 【R12-1】**载荷是 kMonoFamily 那个名字**。注册成 'Consolas' 是不行的：
    // 实测（文件头「R12-1 实测结论」）primary family 未注册时引擎不会去
    // 查 fontFamilyFallback，直接落回 FlutterTest 方框字体。
    // 这里顺带也注册 'Consolas'，只是防御性冗余（万一将来有 widget 直接
    // 写死 Consolas），不是生效路径。
    await (FontLoader(kMonoFamily)..addFont(Future.value(monoData))).load();
    await (FontLoader(kMonoFallbackFamily)..addFont(Future.value(monoData))).load();
  }

  if (katex) {
    // 【公式字体】默认 true，与 cjk / mono 同理：新写 harness 忘传参不能重新
    // 制造"公式全 .notdef 方框"的盲区（见文件头 KaTeX 段）。装载失败会抛
    // StateError，不静默跳过。
    await _loadKatexFonts();
  }
}

/// 自检：装完之后确认 `Icons.*` 用的确实是上面那个 family 名。
///
/// 意义在于 family 名写错是**静默**失效（FontLoader 成功、glyph 一个不命中），
/// 没有这行自检就只能靠肉眼看 PNG 才发现「icon 还是空框」。
void assertMaterialIconsLoaded() {
  if (Icons.history.fontFamily != kMaterialIconsFamily) {
    throw StateError(
      'Icons.history.fontFamily = ${Icons.history.fontFamily}，'
      '与 kMaterialIconsFamily($kMaterialIconsFamily) 不一致 —— '
      '图标字体会被装到一个没人用的 family 上，golden 里 icon 全是空框。',
    );
  }
}

/// 自检（R12-1）：确认 `AppText.genotype` 声明的 family 名就是我们装载的那个。
///
/// [kMonoFamily] 本身已经是 `AppFonts.mono`（编译期就绑死），所以这条自检
/// 守的是**另一半**：`AppText.genotype` 这个 text style 有没有改成别的字体
/// （例如某次「顺手优化字体」把基因型改回 sans）。那种改动同样静默 ——
/// golden 全绿，只是基因型不再是等宽、宽度也不再对齐。
///
/// 注意 `AppText.genotype` 是 **getter**，每次读都新建 TextStyle（`theme.dart`
/// 的铁律：含 token 的样式不得缓存成 static final，否则深浅色切换会残留旧值）。
/// 这里读的 `fontFamily` 是 const 字符串，不受深浅色影响，读一次即可。
void assertMonoLoaded() {
  final declared = AppText.genotype.fontFamily;
  if (declared != kMonoFamily) {
    throw StateError(
      'AppText.genotype.fontFamily = $declared，'
      '与 kMonoFamily($kMonoFamily) 不一致 —— 等宽字体会被装到一个没人用的 '
      'family 上，golden 里的基因型（AaBb/AA/ab）会全部是空心方框。',
    );
  }
}

