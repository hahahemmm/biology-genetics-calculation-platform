// ════════════════════════════════════════════════════════════════
//  test/ui/golden_font_guard_test.dart
//  把「字体到底有没有生效」从**人眼看图**变成**机器判定**
// ════════════════════════════════════════════════════════════════
//
//  ## 这个文件存在的理由
//
//  本仓同一个病复发过四轮，每轮外衣不同、**病根是同一个**：
//  `flutter test` 的 golden 里文字整片变成空心方框（.notdef / tofu），
//  而 `flutter test` **照样全绿**。四轮分别漏掉的是：
//
//  · R10-5  MaterialIcons —— 8 个 harness 只装载了两个**文字**字体，
//           从没装载图标字体，于是全部 golden 里 `Icon(...)` 都是同一个
//           空框。危险之处：R10-4a 把 school_outlined 拆成
//           tune_outlined / cast_outlined / info_outline 对 golden
//           **完全不可见** ——「golden 没红」不构成「icon 换对了」的证据。
//  · R11-3  中文 —— 有 5 个 harness（ui_screenshot / edge_style /
//           family_bus_render / combo_bucket_render / _v21j_curri）历史上
//           一个文字字体都没装，录下的 14 张 golden 里中文全是方框。危险之处：
//           布局是**按方框的宽度**算的，所以这类 golden 对「中文文本布局」
//           零敏感 —— 换文案 / 加大字号 / 改 padding 全都检不出来，是**假绿**。
//           修法是把 `cjk` 默认值翻成 true。
//  · R12-1  等宽（mono）—— **本项目最严重的一条**。基因型（`AaBb` / `AA` /
//           `ab`）、配子、交换值 `0.5`、分离比全挂在 `AppFonts.mono` 上，
//           而 harness 从没装载过这个 family ⇒ **全部 golden 里的基因型
//           都是空心方框**。对遗传计算器来说「基因型是方框」比「中文标签
//           是方框」更致命：那是页面的主内容本身，遗传计算正确性
//           （金标准表 9331）全靠它。
//  · 第四轮  长在 `CustomPainter` 的 `TextPainter` 里 —— 那里**没有
//           BuildContext**、拿不到 `DefaultTextStyle`，一个不声明
//           `fontFamily` 的 `TextStyle` 不会「继承主题字体」，而是直接
//           落回 flutter_tester 的引擎测试字体 FlutterTest。
//
//  为什么四轮都没被回归网抓住：**每轮都是人眼看 PNG 才发现的**，
//  而看图恰恰是回归网最不擅长的动作 —— 它只在「你恰好打开 PNG 看过」时
//  生效。所以本文件的任务就是把这一步机械化。
//
//  ## 本仓的一条实测结论（A / B 组反复用到）
//
//  完整推导见 `test/golden_fonts.dart` 文件头「R12-1 实测结论」，这里只留
//  判据直接依赖的那一句：**`fontFamilyFallback` 不兜底**。
//  flutter_tester 的字体集合里没有的 family 不是「交给 fallback 列表继续
//  找」，而是直接落回引擎测试字体。实测把 consola.ttf 注册成 'Consolas'、
//  primary 仍写 'JetBrains Mono'（也就是 kMonoFamily）⇒ 渲染 'AaBb' 的
//  像素与「family 从没被装载」的对照组**逐字节相同**（都是方框）；
//  注册成 'JetBrains Mono' 才是 1526B vs 对照 232B 的真字形。
//  ⇒ `loadGoldenFonts` 的**载荷是 kMonoFamily 那个名字**（= AppFonts.mono）。
//
//  ## 判据为什么必须能在**运行时**判定
//
//  ⛔ 我**放弃**了「用源码正则扫 `lib/` 全仓、检查每处 `TextStyle` 都声明了
//    `fontFamily`」这条判据，两个原因：
//    ① 它是**粗筛**：正则分不清「painter 里的裸 TextStyle（确实有坑）」与
//       「有意不声明的装饰性文本」，必然误报；误报过的守卫会被调低阈值，
//       最后形同虚设。
//    ② 它是**文本判据**：文件路径、缩进、换行符、一次无害重构都能让它变红，
//       而它对**真正的失效原因**（family 名写错、FontLoader 一个 glyph
//       都没命中）反而一个字都测不出来 —— 那正是前四轮全部静默的地方。
//  ⇒ 取而代之的是**像素判据**：把「声明了家族」与「声明了一个确定不存在的
//    家族」两次真实渲染的像素拿来比。**逐字节相同 = 声明的家族没生效 =
//    正在录方框**，与眼睛无关，可校准、可复现。
//
//  ## 三组断言各守什么
//
//  · A 探针自校准 —— 探针自己也必须被测过（未校准的工具只能当粗筛）。
//    A1 真家族必须让像素变；A2 错家族必须让探针判「没生效」（否则恒真）。
//    A2 同时是「不声明 / 写错 family 就落回测试字体」的**活证据**。
//    A3 把 A1 复制到中文家族上 —— C 组绑的正是中文图例，探针在**两个**
//    家族上都校准过才算数。
//  · B 三个家族（图标 / 中文 / 等宽）都必须**经由无 BuildContext 的那条
//    TextPainter 路径**真的生效 —— 前三轮的病都在 widget 树上，而第四轮
//    长在树上没有的路径上，只测 widget 树等于没测。
//  · C 真正守产品：`FrequencyCurveChartPainter` **实际用来画图例的那个
//    TextStyle**（`AppText.caption.copyWith(...)`，见
//    `lib/charts/frequency_curve_chart.dart`）声明了本仓装载的家族
//    （style 是现算的，不是读源码 ⇒ 运行时判定），**并且**把 `paint()`
//    真正画一遍、diff 出图例文字的真实像素，断言两个中文标签的位图
//    **两两不同**。⇒ painter 哪天退回成不声明 family 的裸 `TextStyle`，
//    两个标签会渲染成同一个方框 ⇒ 位图逐位相同 ⇒ C 组**必红**。
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:biology/charts/frequency_curve_chart.dart';
import 'package:biology/theme.dart' show AppColors, AppFonts, AppText;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../golden_fonts.dart';

/// 一个**确定不存在**的 family 名。
///
/// 它当「静默失效」的对照：flutter_tester 里没被 FontLoader 注册过的 family
/// 不会去查 `fontFamilyFallback`（见文件头「本仓的一条实测结论」），而是
/// 直接落回引擎测试字体 FlutterTest，每个字形都画成同一个空心方块 ⇒
/// **同样内容必然逐字节相同**。
const String _kNoSuchFamily = '__no_such_family__';

/// 探针统一使用的**固定**画布尺寸。
///
/// ⛔ 绝不能按 `TextPainter.width` 自适应画布：真字形与方框字体的推进宽度
///    不同，自适应会让两次渲染的画布大小不同 ⇒ `ByteData` 长度不同 ⇒
///    「像素不同」仅因长度不等就恒成立，探针当场变成永真。
const int _kCanvasW = 260;
const int _kCanvasH = 56;
const double _kProbeInset = 12;
const double _kProbeFontSize = 28;

/// 探针统一使用的字色（两个渲染必须同色，否则「像素不同」毫无意义）。
const Color _kProbeInk = Color(0xFF000000);

/// C 组画布尺寸。**只要够放下两条图例**即可，判据不依赖任何私有几何常量
/// （见 [_chart] 注释里「为什么不需要知道图例画在哪」的推导）。
const int _kChartW = 320;
const int _kChartH = 180;

/// C 组图例的四个探针标签。
///
/// 全部是**单字 CJK**，且两两不同：
///   · 单字 ⇒ 每个标签只占一个汉字宽，diff 出来的包围盒互不重叠，
///     于是「谁是谁」不需要任何私有常量就能判定；
///   · 同为 CJK 单字 ⇒ 在真 CJK 字体里推进宽度相同，改标签不会把后面的
///     图例挤走（C2 的第一条前提会当场验这件事）。
const List<String> _kLegendLabels = <String>['甲', '乙', '丙', '丁'];

// ── 探针 ────────────────────────────────────────────────────────

/// 在**无 BuildContext** 的处境下渲染一段文本并取回 rawRgba 像素。
///
/// ⚠️ 刻意**不**走 `Widget` 树 / `DefaultTextStyle`：`CustomPainter` 里的
///    `TextPainter` 拿不到它们（这正是第四轮的病灶），探针必须复刻**那一条**
///    路径，否则测的是一个产品里根本不存在的处境。
///
/// 只返回像素、不返回 `TextPainter.width`：**本文件只比较字节，不断言布局**。
/// 字体没生效时布局会变（方框宽度 ≠ 真字宽度），断言布局等于把「字体对了
/// 当成布局对」绑在一起，那会让这条守卫在布局调整时误报。
Future<ByteData> _rasterize(String text, TextStyle style) async {
  final recorder = ui.PictureRecorder();
  final tp = TextPainter(
    text: TextSpan(text: text, style: style),
    textDirection: TextDirection.ltr,
  )..layout();
  tp.paint(ui.Canvas(recorder), const Offset(_kProbeInset, _kProbeInset));
  final img = await recorder.endRecording().toImage(_kCanvasW, _kCanvasH);
  try {
    return (await img.toByteData(format: ui.ImageByteFormat.rawRgba))!;
  } finally {
    img.dispose();
  }
}

/// 两个渲染结果是否**逐字节相同**（长度也要一致）。
bool _samePixels(ByteData a, ByteData b) {
  if (a.lengthInBytes != b.lengthInBytes) return false;
  for (var i = 0; i < a.lengthInBytes; i++) {
    if (a.getUint8(i) != b.getUint8(i)) return false;
  }
  return true;
}

/// [declared] 里声明的那个 family **是否真的生效了**。
///
/// 判据：声明了它的渲染，与「声明 [_kNoSuchFamily]」的对照渲染**逐字节不同**
/// ⇒ 字形是真字；逐字节相同 ⇒ 落回了方框 ⇒ 没生效。
Future<bool> _takesEffect(String text, TextStyle declared) async {
  final real = await _rasterize(text, declared);
  final tofu = await _rasterize(
    text,
    TextStyle(
      fontFamily: _kNoSuchFamily,
      fontSize: declared.fontSize,
      fontWeight: declared.fontWeight,
      color: declared.color,
    ),
  );
  return !_samePixels(real, tofu);
}

/// 缓冲区里是否有任何非零字节（把「画了东西」与「全空」分开）。
bool _hasInk(ByteData px) {
  for (var i = 0; i < px.lengthInBytes; i++) {
    if (px.getUint8(i) != 0) return true;
  }
  return false;
}

// ── C 组：真实组件的像素 ────────────────────────────────────────

/// 一块**半开**像素窗口 [x0, x1) × [y0, y1)。
class _Box {
  const _Box(this.x0, this.y0, this.x1, this.y1);

  /// 全画布（[x0, y0) 为原点）。
  static const _Box full = _Box(0, 0, _kChartW, _kChartH);

  final int x0;
  final int y0;
  final int x1;
  final int y1;

  int get w => x1 - x0;
  int get h => y1 - y0;

  /// 什么像素都没圈到（⇒ 两次渲染在这个区域**完全一样**）。
  bool get isEmpty => w <= 0 || h <= 0;

  @override
  String toString() => '[$x0,$y0)×[$x1,$y1)';
}

/// [a] 与 [b] 不同的像素所构成的**最小**包围盒；完全相同则返回空盒。
///
/// 用于**定位**（而不是分类）：把某个字符串换掉，diff 出来的就是那串文字
/// 的全部像素。定位用 diff 而不是「按颜色分类」，是因为分类要靠
/// 「到 token 色最近者」这种近似判据（抗锯齿边缘像素会漂），而 diff 是
/// 精确的 —— 颜色相近的 token 不会影响它一个字。
_Box _diffBox(ByteData a, ByteData b, {_Box scope = _Box.full}) {
  var x0 = 1 << 30, y0 = 1 << 30, x1 = -1, y1 = -1;
  for (var i = 0; i < a.lengthInBytes; i++) {
    if (a.getUint8(i) == b.getUint8(i)) continue;
    final p = i ~/ 4;
    final x = p % _kChartW;
    final y = p ~/ _kChartW;
    if (x < scope.x0 || x >= scope.x1 || y < scope.y0 || y >= scope.y1) {
      continue;
    }
    if (x < x0) x0 = x;
    if (x > x1) x1 = x;
    if (y < y0) y0 = y;
    if (y > y1) y1 = y;
  }
  if (x1 < 0) return _Box(0, 0, 0, 0);
  return _Box(x0, y0, x1 + 1, y1 + 1);
}

/// 在 [win] 这块**固定**窗口内取 [a] 与 [b] 的差异位图（1 = 该像素不同）。
///
/// ⚠️ 窗口必须是**两个标签共用**的同一块：窗口尺寸不同的话，
///    「两两不同」会因为长度不等而恒成立，判据当场变成永真。
List<int> _diffMask(ByteData a, ByteData b, _Box win) {
  final out = List<int>.filled(win.w * win.h, 0);
  for (var y = win.y0; y < win.y1; y++) {
    for (var x = win.x0; x < win.x1; x++) {
      final o = (y * _kChartW + x) * 4;
      if (a.getUint8(o) != b.getUint8(o) ||
          a.getUint8(o + 1) != b.getUint8(o + 1) ||
          a.getUint8(o + 2) != b.getUint8(o + 2) ||
          a.getUint8(o + 3) != b.getUint8(o + 3)) {
        out[(y - win.y0) * win.w + (x - win.x0)] = 1;
      }
    }
  }
  return out;
}

/// 按**同样那串**取值造一个图，标签由参数给定。
///
/// 【为什么不依赖任何私有几何常量】图例的 x 由 `_marginL`（私有）起算，
/// 但本文件**从不去读图例画在哪** —— 定位改用「换掉一个标签、diff 出它
/// 的像素」。之所以成立，依赖下面两条可当场验证的性质：
///   ① 两条序列的 [FreqSeries.values] **逐位相同** ⇒ 折线、端点、坐标轴
///      刻度在两次渲染里像素完全一致，只有图例文字会动；
///   ② 改的是**单字 CJK** ⇒ 真 CJK 字体里推进宽度相同，图例 B 的落点
///      不会因为 A 的宽度变化而移动。
/// 两条都由 C2 的前提断言现场检验（diff 包围盒非空 + 两个包围盒在 x 上
/// 互不重叠），任一条不成立就地炸出可读的原因，而不是给出假绿。
FrequencyCurveChartPainter _chart(String labelA, String labelB) =>
    FrequencyCurveChartPainter(
      series: <FreqSeries>[
        // 颜色是构造器实参，照 `FrequencyCurveChart.build` 的传法来，不自造。
        FreqSeries(
          label: labelA,
          values: <double>[0.10, 0.35, 0.62, 0.78],
          color: AppColors.teal,
        ),
        FreqSeries(
          label: labelB,
          values: <double>[0.10, 0.35, 0.62, 0.78],
          color: AppColors.steel,
        ),
      ],
      inkColor: AppColors.ink,
      graphiteColor: AppColors.graphite,
      borderColor: AppColors.border,
      xLabel: '代',
    );

/// 把 [FrequencyCurveChartPainter] 真实画一遍并取回 rawRgba 像素。
Future<ByteData> _shootChart(String labelA, String labelB) async {
  final size = Size(_kChartW.toDouble(), _kChartH.toDouble());
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  // 先铺底色：真实 widget 里 CustomPaint 之下是 Scaffold 的 canvas 底色。
  // 铺成不透明后「画了东西」与「全空」才分得开（C2 靠这个定位图例）。
  canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height), Paint()..color = AppColors.canvas);
  _chart(labelA, labelB).paint(canvas, size);
  final img = await recorder.endRecording().toImage(_kChartW, _kChartH);
  try {
    return (await img.toByteData(format: ui.ImageByteFormat.rawRgba))!;
  } finally {
    img.dispose();
  }
}

/// 图例文字**实际**使用的那个 TextStyle。
///
/// ⛔ 复制 `frequency_curve_chart.dart` 里图例那一处 `TextSpan` 的实参，
///    一个字都没改也不多写 —— 这就是「C 组守的是产品真正在用的样式」。
///    `AppText.caption` 是 getter（每次读都新建 TextStyle），所以这里
///    不能 const，**每次调用重新读**才对。
TextStyle _legendTextStyle() => AppText.caption.copyWith(
      color: AppColors.ink,
      fontSize: 10,
      fontWeight: FontWeight.w600,
    );

String _inkCount(List<int> m) => '${m.where((v) => v == 1).length}/${m.length}';

/// 断言 [masks] 两两不同；撞上时给出可读的原因。
void _expectPairwiseDistinct(List<String> labels, List<List<int>> masks) {
  for (var i = 0; i < labels.length; i++) {
    // ⛔ 前提先行：差异位图全空时「两两相同」是**恒真**的（空 == 空），
    //    必须先把「取到了东西」变成必红，否则整组会静默通过。
    expect(masks[i].where((v) => v == 1).length, greaterThan(0),
        reason: '「${labels[i]}」的差异位图是**全空**的 —— 换掉这个标签后'
            '产品渲染一个像素都没变。两种可能，都必须在这里炸出来：'
            '(a) painter 根本没画这串文字；'
            '(b) painter 画的是 .notdef 方框，'
            '**换成任何一个字都渲染成同一个方框**，像素自然不变。'
            '(b) 正是第四轮的病灶。');
    for (var j = i + 1; j < labels.length; j++) {
      expect(masks[i], isNot(equals(masks[j])),
          reason: '「${labels[i]}」与「${labels[j]}」的文字位图**逐位相同**'
              '（墨迹 ${_inkCount(masks[i])} vs ${_inkCount(masks[j])}）。'
              '真字体的这两组内容必然各不相同；逐位相同只有一个解释：'
              '它们渲染的是**同一个 .notdef 方框** —— painter 的 TextPainter '
              '没有真正生效的 fontFamily，正在把方框录进基线。而这类基线'
              '布局是按方框宽度算的，对文本内容零敏感，是**彻底的假绿**。');
    }
  }
}

void main() {
  group('A 探针自校准（未校准的工具只能当粗筛）', () {
    testWidgets('A1 声明了真家族 ⇒ 像素必须变（否则探针恒假）', (t) async {
      await loadGoldenFonts();
      final ok = (await t.runAsync(() => _takesEffect(
            'AaBb1a',
            TextStyle(
              // ⛔ 家族名**不写字面量**：照 `test/golden_fonts.dart:120` 的做法，
              //    名字写错就是静默失效（FontLoader 成功、一个 glyph 不命中）。
              fontFamily: kMonoFamily,
              fontFamilyFallback: AppFonts.monoFallback,
              fontSize: _kProbeFontSize,
              color: _kProbeInk,
            ),
          )))!;
      expect(ok, isTrue,
          reason: '声明了 kMonoFamily 之后，\'AaBb1a\' 的渲染与「家族名确定'
              '不存在」的对照组逐字节相同 ⇒ 等宽字体没生效。'
              '这一条不绿说明**探针本身坏了**，A2 / A3 / B / C 的结论全部不可信。');
    });

    testWidgets('A2 家族名写错 ⇒ 探针必须判「没生效」（否则探针恒真）', (t) async {
      await loadGoldenFonts();
      final ok = (await t.runAsync(() => _takesEffect(
            'AaBb1a',
            TextStyle(
              fontFamily: _kNoSuchFamily,
              fontSize: _kProbeFontSize,
              color: _kProbeInk,
            ),
          )))!;
      expect(ok, isFalse,
          reason: '探针对一个**确定不存在**的家族也报「生效」⇒ 探针恒真，'
              '它什么都没测。这就是「不声明 / 写错 family 会落回 '
              'flutter_tester 的引擎测试字体 FlutterTest、字形全是方框」的'
              '**活证据**：声明与否渲染完全一样，恰恰因为**根本没取到字体**。');
    });

    testWidgets('A3 中文字家族同样要让像素变（C 组要靠它）', (t) async {
      await loadGoldenFonts();
      final ok = (await t.runAsync(() => _takesEffect(
            '基因型',
            TextStyle(
              fontFamily: AppFonts.sans,
              fontFamilyFallback: AppFonts.sansFallback,
              fontSize: _kProbeFontSize,
              color: _kProbeInk,
            ),
          )))!;
      expect(ok, isTrue,
          reason: '中文家族在探针上就没生效 ⇒ C 组（中文图例）的像素判据'
              '在原理上就不可能通过，先在这里把「探针 vs 家族」的配对问题'
              '与产品问题分开。');
    });
  });

  group('B 三个家族都必须真的生效（走无 BuildContext 的 TextPainter 路径）', () {
    testWidgets('B1 mono —— 基因型那一支（R12-1）', (t) async {
      await loadGoldenFonts();
      // 复用既有自检，不重写。
      assertMonoLoaded();
      expect(AppText.genotype.fontFamily, kMonoFamily);
      final ok = (await t.runAsync(() => _takesEffect(
            'AaBb1a',
            TextStyle(
              fontFamily: kMonoFamily,
              fontFamilyFallback: AppFonts.monoFallback,
              fontSize: _kProbeFontSize,
              color: _kProbeInk,
            ),
          )))!;
      expect(ok, isTrue,
          reason: '等宽家族在**无 BuildContext** 的 TextPainter 上没生效 —— '
              '凡是长在 CustomPainter 里的基因型（AaBb / AA / ab）都会是方框。');
    });

    testWidgets('B2 sans / 中文（R11-3）', (t) async {
      await loadGoldenFonts();
      final ok = (await t.runAsync(() => _takesEffect(
            '基因型',
            TextStyle(
              fontFamily: AppFonts.sans,
              fontFamilyFallback: AppFonts.sansFallback,
              fontSize: _kProbeFontSize,
              color: _kProbeInk,
            ),
          )))!;
      expect(ok, isTrue,
          reason: '中文字体在**无 BuildContext** 的 TextPainter 上没生效 —— '
              '凡是没有继承 DefaultTextStyle 的中文都会是方框。');
    });

    testWidgets('B3 MaterialIcons（R10-5）', (t) async {
      await loadGoldenFonts();
      // 复用既有自检，不重写。
      assertMaterialIconsLoaded();
      final glyph = String.fromCharCode(Icons.history.codePoint);
      final ok = (await t.runAsync(() => _takesEffect(
            glyph,
            TextStyle(
              fontFamily: kMaterialIconsFamily,
              fontSize: _kProbeFontSize,
              color: _kProbeInk,
            ),
          )))!;
      expect(ok, isTrue,
          reason: '图标字体在**无 BuildContext** 的 TextPainter 上没生效 —— '
              '凡是代码绘制（而非 Icon widget）的图标都会是方框。');
    });

    test('B4 三个字体文件都能解析（换机器时的第一道闸）', () {
      // resolve* 内部已对 CJK / mono 做了体积下限校验（太小 ⇒ 抛错），
      // 这里只补「文件确实在」与阈值复核，不重复定义判定逻辑。
      final icons = resolveMaterialIconsFont();
      final cjk = resolveCjkFont();
      final mono = resolveMonoFont();
      for (final f in <File>[icons, cjk, mono]) {
        expect(f.existsSync(), isTrue, reason: '字体文件应存在：${f.path}');
      }
      expect(icons.lengthSync(), greaterThan(0), reason: '图标字体文件是空的');
      expect(cjk.lengthSync(), greaterThanOrEqualTo(2 * 1024 * 1024),
          reason: '中文字体至少 MB 级：${cjk.path}');
      expect(mono.lengthSync(), greaterThanOrEqualTo(50 * 1024),
          reason: '等宽字体至少 50KB：${mono.path}');
    });
  });

  group('C 产品守卫：frequency_curve_chart 的图例文字不是方框', () {
    setUp(() => AppColors.sync(Brightness.light));

    test('C0 图例样式声明的家族与 golden_fonts 装载的逐字一致', () {
      // 图例文字的底子是 AppText.caption，所以「主题里 caption 挂的家族」
      // 就是这个 painter 的中文命运。名字对不上就是静默失效
      // （FontLoader 成功、glyph 一个不命中），只能靠这一行炸出来。
      expect(AppText.caption.fontFamily, kSansFamily,
          reason: 'AppText.caption.fontFamily 与 kSansFamily 不一致 —— '
              '中文字体会被装到一个没人用的 family 上，'
              'frequency_curve_chart 的中文图例全是方框。');
      expect(AppFonts.sansFallback, isNotEmpty);
      expect(AppFonts.sansFallback.first, kSansFamilyFallback,
          reason: '主题的 sans fallback 首项必须就是 golden_fonts 装载的'
              '那个 fallback 名，否则落到 fallback 的那一支仍是方框。');
    });

    testWidgets('C1 图例那个 TextStyle 声明了家族，且在无 BuildContext 上取得到字形',
        (t) async {
      await loadGoldenFonts();
      // 光「声明了」不够 ⇒ 还要证明这个家族在 painter 那种
      // 无 BuildContext 的 TextPainter 上**真的取到了字形**。
      final style = _legendTextStyle();
      expect(style.fontFamily, AppFonts.sans,
          reason: 'copyWith 之后 fontFamily 必须还在（copyWith 只覆盖给定的 '
              '字段）；若哪天有人给图例换底子又没带家族，这里会红。');
      final ok = (await t.runAsync(
          () => _takesEffect(_kLegendLabels.first, style)))!;
      expect(ok, isTrue,
          reason: '图例样式声明了 AppFonts.sans，但它在无 BuildContext 的 '
              'TextPainter 上**取不到字形** ⇒ 图例中文仍是方框。');
    });

    testWidgets('C2 真实画一遍：两个中文图例标签的文字位图两两不同', (t) async {
      await loadGoldenFonts();
      // 只换标签、其余全部逐位不变，于是 diff 出来的就是「这串文字」本身。
      final base = (await t.runAsync(() => _shootChart(
            _kLegendLabels[0], _kLegendLabels[1],
          )))!;
      final swapA = (await t.runAsync(() => _shootChart(
            _kLegendLabels[3], _kLegendLabels[1],
          )))!;
      final swapB = (await t.runAsync(() => _shootChart(
            _kLegendLabels[0], _kLegendLabels[2],
          )))!;

      final boxA = _diffBox(base, swapA);
      final boxB = _diffBox(base, swapB);

      // 前提 ①：换标签必须真的改了像素。
      expect(boxA.isEmpty, isFalse,
          reason: '换掉第一个图例标签后产品渲染**一个像素都没变**（'
              '${_kLegendLabels[0]} vs ${_kLegendLabels[3]}）—— 要么这串文字'
              '没被画出来，要么画出来的是同一个 .notdef 方框。');
      expect(boxB.isEmpty, isFalse,
          reason: '换掉第二个图例标签后产品渲染**一个像素都没变**'
              '（${_kLegendLabels[1]} vs ${_kLegendLabels[2]}）。');
      // 前提 ②：两个标签的像素必须在 x 上互不重叠，否则「哪个 diff 属于
      // 谁」就没法判定，pairwise-distinct 也就失去意义。
      expect(boxA.x1 <= boxB.x0 || boxB.x1 <= boxA.x0, isTrue,
          reason: '两个图例标签的差异包围盒在 x 上重叠了：'
              'A=$boxA（${_kLegendLabels[0]}）B=$boxB（${_kLegendLabels[1]}）。'
              '说明改一个标签把另一个也挤动了 —— 标签宽度不再相同，'
              'C2 的定位前提失效，判据不作数。');

      // 共用同一块窗口取样：窗口尺寸必须一致，否则「两两不同」会因长度
      // 不等而恒成立（见 _diffMask 的警告）。
      final win = _Box(
        boxA.x0 < boxB.x0 ? boxA.x0 : boxB.x0,
        boxA.y0 < boxB.y0 ? boxA.y0 : boxB.y0,
        boxA.x1 > boxB.x1 ? boxA.x1 : boxB.x1,
        boxA.y1 > boxB.y1 ? boxA.y1 : boxB.y1,
      );
      _expectPairwiseDistinct(
        <String>['${_kLegendLabels[0]}（第一个图例）', '${_kLegendLabels[1]}（第二个图例）'],
        <List<int>>[_diffMask(base, swapA, win), _diffMask(base, swapB, win)],
      );
    });

    testWidgets('C3 前提的活证据：这四个字一旦落回测试字体就必然逐位相同',
        (t) async {
      await loadGoldenFonts();
      // C2 判别力的前提是「真字形两两不同、方框全都一样」。这里把后半句
      // 当场演示：同一组中文在一个不存在的 family 下渲染必然逐字节相同
      // ⇒ painter 哪天丢掉 fontFamily，C2 就必红。
      final tofu = (await t.runAsync(() async => <ByteData>[
            for (final s in _kLegendLabels)
              await _rasterize(
                s,
                TextStyle(
                  fontFamily: _kNoSuchFamily,
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: _kProbeInk,
                ),
              ),
          ]))!;
      for (var i = 0; i < tofu.length; i++) {
        // ⛔ 先钉住「确实画了东西」。否则 4 张全空缓冲区也是两两相同，
        //    这条会**空转通过**，而它要证明的恰恰是「方框真的存在且全都一样」。
        expect(_hasInk(tofu[i]), isTrue,
            reason: '「${_kLegendLabels[i]}」在不存在的 family 下渲染出一张'
                '**全空**缓冲区 ⇒ 连方框都没画出来，前提无从谈起。');
        for (var j = i + 1; j < tofu.length; j++) {
          expect(_samePixels(tofu[i], tofu[j]), isTrue,
              reason: '「${_kLegendLabels[i]}」与「${_kLegendLabels[j]}」在一个'
                  '不存在的 family 下渲染**不同** ⇒ 「方框全都一样」这个前提'
                  '不成立，C2 就失去了判别力。');
        }
      }

      // 另一半：真家族下这四个字必须两两不同。少了这一半，上面的「全都
      // 一样」也可能只是因为「什么都没画出来」。
      final real = (await t.runAsync(() async => <ByteData>[
            for (final s in _kLegendLabels)
              await _rasterize(s, _legendTextStyle()),
          ]))!;
      for (var i = 0; i < real.length; i++) {
        for (var j = i + 1; j < real.length; j++) {
          expect(_samePixels(real[i], real[j]), isFalse,
              reason: '「${_kLegendLabels[i]}」与「${_kLegendLabels[j]}」在'
                  '**真家族**下渲染逐字节相同 ⇒ 这个家族对中文没取到字形。');
        }
      }
    });
  });
}
