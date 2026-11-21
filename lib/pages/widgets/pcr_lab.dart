// pcr_lab.dart —— 分子页第 5 个页签「基因工程」：PCR 扩增 + 凝胶电泳示意
//
// 为什么是「小而完整」的一个切片：限制酶切讲「切开」，PCR 讲「扩增」，
// 教材上紧随其后的是「电泳看结果」这一条链。本实验只跑这一条链：
//   · 模板只输入顶链 5′→3′（引擎见 `engine/pcr_engine.dart`）；
//   · 一对引物，各必须**唯一**结合（0 处 / 多处 / 方向反 / 重叠都报错）；
//   · 拷贝数按理想 2ⁿ 计；电泳只画**迁移方向**的分档示意；
//   · 结论只用于理解概念，屏上明写「不用于实验设计」（[kPcrDisclaimer]）。
//
// 布局沿用本页工作台语言（ToolWorkbench 的输入 / 结果两栏），与
// `restriction_lab.dart` 同一套契约：
//   · [PcrLabState.buildInputs] —— 左栏（窄屏回落到结果区上方）；
//   · [PcrLabState.build] —— 结果区；
//   `showInputs: true`（默认）两者连成一体，单测/窄屏直接泵它；
//   页面里用 `showInputs: false`，输入区由左栏副本承担（**同一份 State**）。
//
// 状态归属：输入与结果共用 [PcrLabState] 一份真相（⛔ 不各存一份，
// 两真相必分叉）。宽屏左栏先于结果区构建 ⇒ 本 State 挂载后向
// [PcrLab.revision] 补发一次通知，与限制酶切同款做法。

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../engine/pcr_engine.dart';
import '../../theme.dart';
import 'cross_tool_rail.dart' show FlatSection;

/// 屏上一句话的模型边界（⛔ 不许删：这是「不虚构科学」的可见承诺）。
const String kPcrDisclaimer =
    '教学简化模型：只输入模板顶链 5′→3′，两条引物按完全互补、各只结合一处处理；'
    '循环数 n 的理想拷贝数按 2ⁿ 计（0 次 = 1 份）；'
    '不评估 GC 含量、退火温度、非特异扩增与扩增效率，不用于实验设计。';

/// 一个示例（chip）：一键把模板与两条引物都摆好——白板上不用键盘也能出结果。
class PcrSample {
  const PcrSample({
    required this.label,
    required this.template,
    required this.forward,
    required this.reverse,
  });

  final String label;
  final String template;
  final String forward;
  final String reverse;
}

/// PCR 扩增与电泳实验（输入 + 结果，共享一份 State）。
class PcrLab extends StatefulWidget {
  const PcrLab({super.key, this.showInputs = true, this.revision});

  /// true（默认）：输入区 + 结果区一起渲染（自包含；单测/窄屏直接泵它）。
  /// false：只渲染结果区——页面里输入区由左栏副本
  /// （[PcrLabState.buildInputs]）承担。
  final bool showInputs;

  /// 左栏副本的重建信号（页面持有并负责 dispose，⛔ 本组件不 dispose 它）。
  final ValueNotifier<int>? revision;

  @override
  PcrLabState createState() => PcrLabState();
}

class PcrLabState extends State<PcrLab> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  /// 出厂默认题：70 bp 模板，正向引物结合第 4–23 位、反向引物（反向互补）
  /// 结合第 48–67 位 ⇒ 扩增子顶链第 4–67 位 = **64 bp**。
  /// ⚠️ 常量是唯一真相：controller 初值与 [isPristine] 共用同一批常量。
  static const String kDefaultTemplate =
      'GGGATGGCATCGATCGTTAGCATGCCGTTAACCGGTTAGCTAGCTTATTACGGATCCTAGCTAGGCATTA';
  static const String kDefaultForward = 'ATGGCATCGATCGTTAGCAT';
  /// 反向引物按 5′→3′ 写：它的反向互补才是顶链第 48–67 位
  /// （TTACGGATCCTAGCTAGGCA 的反向互补）。
  static const String kDefaultReverse = 'TGCCTAGCTAGGATCCGTAA';
  static const int kDefaultCycles = 25;

  /// 默认题目里反向结合区在顶链上的样子（示例 chip「方向写反」要用）。
  static const String _kDefaultReverseBindingOnTop = 'TTACGGATCCTAGCTAGGCA';

  /// 示例 chips（白板友好：点一下即算，⛔ 不必键盘输入）。
  static const List<PcrSample> samples = <PcrSample>[
    PcrSample(
      label: '示例·标准扩增',
      template: kDefaultTemplate,
      forward: kDefaultForward,
      reverse: kDefaultReverse,
    ),
    PcrSample(
      label: '示例·无产物（引物不匹配）',
      template: 'CCCGGGTTTAACCCGGGTTTAAC',
      forward: kDefaultForward,
      reverse: kDefaultReverse,
    ),
    PcrSample(
      label: '示例·反向引物写反',
      template: kDefaultTemplate,
      forward: kDefaultForward,
      reverse: _kDefaultReverseBindingOnTop,
    ),
  ];

  /// 循环数 chip（0..30 里挑几个常见值；具体数仍可看屏上当前值）。
  static const List<int> kCyclePresets = <int>[0, 1, 5, 15, 20, 25, 30];

  final _templateCtrl = TextEditingController(text: kDefaultTemplate);
  final _forwardCtrl = TextEditingController(text: kDefaultForward);
  final _reverseCtrl = TextEditingController(text: kDefaultReverse);
  int _cycles = kDefaultCycles;
  PcrResult? _result;
  String? _error;

  /// 学生一个格子都没动过吗（父页深链覆盖守卫用）。
  bool get isPristine =>
      _templateCtrl.text == kDefaultTemplate &&
      _forwardCtrl.text == kDefaultForward &&
      _reverseCtrl.text == kDefaultReverse &&
      _cycles == kDefaultCycles;

  @override
  void initState() {
    super.initState();
    // 出厂默认题先算一遍（与其余页签「出厂即展开默认结果」一致）。
    _result = _resultQuiet(
      template: _templateCtrl.text,
      forward: _forwardCtrl.text,
      reverse: _reverseCtrl.text,
      cycles: _cycles,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _bumpRevision();
    });
  }

  @override
  void dispose() {
    _templateCtrl.dispose();
    _forwardCtrl.dispose();
    _reverseCtrl.dispose();
    super.dispose();
  }

  PcrResult? _resultQuiet({
    required String template,
    required String forward,
    required String reverse,
    required int cycles,
  }) {
    try {
      return pcrAmplify(
        template: template,
        forwardPrimer: forward,
        reversePrimer: reverse,
        cycles: cycles,
      );
    } on ArgumentError {
      return null;
    }
  }

  /// 通知左栏副本重建（⛔ 页面持有该 ValueNotifier，此处只自增）。
  void _bumpRevision() => widget.revision?.value++;

  /// 按当前输入重算（按钮 / 回车 / chip / 换循环数共用唯一入口）。
  void _compute() {
    try {
      final r = pcrAmplify(
        template: _templateCtrl.text,
        forwardPrimer: _forwardCtrl.text,
        reversePrimer: _reverseCtrl.text,
        cycles: _cycles,
      );
      setState(() {
        _result = r;
        _error = null;
      });
    } on ArgumentError catch (e) {
      // ⛔ 出错必须清旧结果：留着上一题的扩增子会让学生以为这次也算成了。
      setState(() {
        _result = null;
        _error = e.message?.toString() ?? '输入格式错误';
      });
    }
    _bumpRevision();
  }

  /// 供父页「全部计算」按一次刷新本实验（未挂载时父页取不到 State）。
  void recalc() => _compute();

  void _applySample(PcrSample sample) {
    setState(() {
      _templateCtrl.text = sample.template;
      _forwardCtrl.text = sample.forward;
      _reverseCtrl.text = sample.reverse;
    });
    _compute();
  }

  void _setCycles(int n) {
    if (n == _cycles) return;
    setState(() => _cycles = n);
    _compute();
  }

  // ─── 输入区（宽屏左栏 / 窄屏结果区上方 / 自包含形态的顶部）───

  /// 输入面板：左侧工作台栏调用它（页面用 GlobalKey 取本 State）。
  Widget buildInputs(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FlatSection(
            title: '模板与引物',
            subtitle: '选择性必修3 · 生物技术与工程',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'PCR 用一对引物把模板上的目标区段大量扩增：正向引物与顶链'
                  '某段完全相同；反向引物按 5′→3′ 写出，它的反向互补才是'
                  '顶链上的结合区。扩增子 = 从正向结合区起点到反向结合区终点。',
                  style: AppText.caption.copyWith(color: AppColors.graphite),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    for (final s in samples)
                      ActionChip(
                        label: Text(s.label),
                        onPressed: () => _applySample(s),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                _monoField(
                  _templateCtrl,
                  '模板顶链（5′→3′）',
                  '如 GGGATGGCATCGATCGTTAGCAT',
                ),
                _monoField(
                  _forwardCtrl,
                  '正向引物（5′→3′，与顶链相同）',
                  '如 ATGGCATCGATCGTTAGCAT',
                ),
                _monoField(
                  _reverseCtrl,
                  '反向引物（5′→3′，与结合区反向互补）',
                  '如 TGCCTAGCTAGGATCCGTAA',
                ),
                Text(
                  '引物长度 $kPcrMinPrimerLength–$kPcrMaxPrimerLength nt'
                  '（默认示例 20 nt；这不是真实引物设计工具）',
                  style: AppText.caption.copyWith(color: AppColors.steel),
                ),
                const SizedBox(height: 10),
                _bigButton('开始扩增', _compute),
              ],
            ),
          ),
          FlatSection(
            title: '循环数',
            subtitle: '0–$kPcrMaxCycles 次（0 次 = 不扩增，仍是 1 份模板）',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    for (final n in kCyclePresets)
                      ChoiceChip(
                        label: Text('$n 次'),
                        selected: _cycles == n,
                        onSelected: (_) => _setCycles(n),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  '当前循环数 n = $_cycles',
                  style: AppText.body.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 4),
                Text(
                  '理想拷贝数 = 2ⁿ：每轮把已有产物再当模板，所以是翻倍关系。'
                  '真实 PCR 有平台期与效率损失，这里不做修正。',
                  style: AppText.caption.copyWith(color: AppColors.graphite),
                ),
              ],
            ),
          ),
        ],
      );

  /// 等宽输入框（序列用等宽字体：碱基对位时才看得清）。
  Widget _monoField(
          TextEditingController ctrl, String label, String hint) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: TextField(
          controller: ctrl,
          style: AppText.monoSmall.copyWith(fontSize: 14, letterSpacing: 1),
          autocorrect: false,
          enableSuggestions: false,
          decoration: InputDecoration(
            isDense: true,
            labelText: label,
            hintText: hint,
            hintStyle:
                AppText.monoSmall.copyWith(fontSize: 13, color: AppColors.steel),
            counterText: '',
          ),
          onSubmitted: (_) => _compute(),
        ),
      );

  /// 主按钮：通栏 + 44 高（白板/触屏都够按），措辞即动作。
  Widget _bigButton(String label, VoidCallback onTap) => SizedBox(
        width: double.infinity,
        child: FilledButton.icon(
          onPressed: onTap,
          icon: const Icon(Icons.science_outlined, size: 18),
          label: Text(label,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
          style: FilledButton.styleFrom(
            minimumSize: const Size(0, 44),
            padding: const EdgeInsets.symmetric(horizontal: 14),
          ),
        ),
      );

  // ─── 结果区 ───

  @override
  Widget build(BuildContext context) {
    super.build(context); // 页签往返时保留学生当前模板、引物与循环数。
    final results = _results(context);
    if (!widget.showInputs) return results;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        buildInputs(context),
        Divider(color: AppColors.border.withValues(alpha: 0.6)),
        const SizedBox(height: 20),
        results,
      ],
    );
  }

  Widget _results(BuildContext context) {
    final r = _result;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(kPcrDisclaimer,
            style: AppText.caption.copyWith(color: AppColors.steel)),
        const SizedBox(height: 16),
        if (_error != null)
          FlatSection(title: '扩增结果', child: _errorBanner(_error!))
        else if (r != null) ...[
          _bindingSection(r),
          const SizedBox(height: 26),
          _ampliconSection(r),
          const SizedBox(height: 26),
          _copySection(r),
          const SizedBox(height: 26),
          _gelSection(r),
        ],
      ],
    );
  }

  Widget _bindingSection(PcrResult r) => FlatSection(
        title: '引物结合区（模板顶链）',
        subtitle: '位置统一按 1-based（第 1 个碱基 = 1）',
        trailing: AppChip('模板 ${r.template.length} bp'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _kv('正向引物', '${r.forwardPrimer}（${r.forwardBinding.length} nt）'),
            _kv('正向结合区', '${r.forwardBinding.rangeText}：'
                '${r.forwardBinding.sequence}'),
            const SizedBox(height: 6),
            _kv('反向引物', '${r.reversePrimer}（${r.reverseBinding.length} nt）'),
            _kv('反向结合区', '${r.reverseBinding.rangeText}：'
                '${r.reverseBinding.sequence}'),
            const SizedBox(height: 8),
            Text(
              '反向引物按 5′→3′ 输入，它自己与结合区互为反向互补：'
              '引擎拿它的反向互补去顶链上找位置，所以两行序列看起来不一样是正常的。',
              style: AppText.caption.copyWith(color: AppColors.graphite),
            ),
          ],
        ),
      );

  Widget _ampliconSection(PcrResult r) => FlatSection(
        title: '扩增子（产物顶链）',
        subtitle: '从正向结合区起点到反向结合区终点，含两端引物本身',
        trailing: AppChip('${r.ampliconLength} bp'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _kv('产物区间', r.productRangeText),
            const SizedBox(height: 6),
            Text(
              _grouped(r.amplicon),
              style: AppText.monoSmall.copyWith(
                fontSize: 12.5,
                height: 1.7,
                letterSpacing: 1,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '产物长度核对：${r.productEnd} − ${r.productStart} + 1 = '
              '${r.ampliconLength} bp（与上面序列的碱基数一致）',
              style: AppText.body.copyWith(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: AppColors.teal,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '产物两端各含一段引物（正向 5′ 端、反向互补 3′ 端），'
              '中间是模板原有的区段——这就是引物能把目标区段「框住」的原因。',
              style: AppText.caption.copyWith(color: AppColors.graphite),
            ),
          ],
        ),
      );

  Widget _copySection(PcrResult r) => FlatSection(
        title: '循环数与理想拷贝数',
        subtitle: '2ⁿ 只是拷贝数（理想模型），不是条带亮度或浓度',
        trailing: AppChip('n = ${r.cycles}'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _kv('循环数', '${r.cycles} 次'),
            _kv('理想拷贝数', '2^${r.cycles} = ${r.idealCopies} 份'),
            const SizedBox(height: 6),
            Text(
              r.cycles == 0
                  ? '0 次循环 = 不扩增：产物就是原始模板本身，共 1 份。'
                  : '第 1 轮 2 份、第 2 轮 4 份……每轮翻倍，'
                      '${r.cycles} 轮后是 2^${r.cycles} = ${r.idealCopies} 份（理想值）。',
              style: AppText.caption.copyWith(color: AppColors.graphite),
            ),
            Text(
              '这里只数分子个数，不涉及浓度、荧光强度与条带粗细。',
              style: AppText.caption.copyWith(color: AppColors.graphite),
            ),
          ],
        ),
      );

  Widget _gelSection(PcrResult r) => FlatSection(
        title: '凝胶电泳示意',
        subtitle: '上端是加样孔；短片段迁移更远（更靠下），marker 为对数分档示意',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            PcrGelDiagram(sampleLength: r.ampliconLength),
            const SizedBox(height: 10),
            Text(
              gelInMarkerRange(r.ampliconLength)
                  ? '样品条带（${r.ampliconLength} bp）落在 marker 的 '
                      '${_nearestMarkerText(r.ampliconLength)} 附近——'
                      '只说明大小量级，不做精确长度回归。'
                  : '样品条带（${r.ampliconLength} bp）超出 marker 分档范围'
                      '（${kGelMarkerBps.last}–${kGelMarkerBps.first} bp），'
                      '位置被夹在端点，仅示意迁移方向。',
              style: AppText.caption.copyWith(color: AppColors.graphite),
            ),
            const SizedBox(height: 4),
            Text(
              '条带位置仅示意迁移方向，不用于精确定量；'
              '同一次电泳里等长的片段落在同一高度。',
              style: AppText.caption.copyWith(color: AppColors.steel),
            ),
          ],
        ),
      );

  /// 落在哪一档 marker 附近（对数轴上最近的一档，只作量级提示）。
  String _nearestMarkerText(int bp) {
    var best = kGelMarkerBps.first;
    var bestDelta = double.infinity;
    for (final m in kGelMarkerBps) {
      final d = (math.log(m.toDouble()) - math.log(bp.toDouble())).abs();
      if (d < bestDelta) {
        bestDelta = d;
        best = m;
      }
    }
    return '$best bp';
  }

  /// 序列按 10 个碱基一组断开（等宽字体下可换行，390 宽也不溢出）。
  static String _grouped(String seq, [int group = 10]) {
    final parts = <String>[];
    for (var i = 0; i < seq.length; i += group) {
      parts.add(seq.substring(i, math.min(i + group, seq.length)));
    }
    return parts.join(' ');
  }

  /// 测试钩子：与屏上完全同源的序列分组，防「屏上序列与产物长度对不上」。
  static String debugGroupedSequence(String seq) => _grouped(seq);

  // ─── 通用小件（沿用分子页写法）───

  Widget _kv(String k, String v) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 96,
              child: Text(k,
                  style: AppText.caption.copyWith(color: AppColors.graphite)),
            ),
            Expanded(
              child: Text(v,
                  style: AppText.body.copyWith(fontWeight: FontWeight.w600)),
            ),
          ],
        ),
      );

  Widget _errorBanner(String message) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.lethal.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(AppTheme.radiusInput),
          border: Border.all(color: AppColors.lethal.withValues(alpha: 0.35)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.error_outline_rounded, size: 18, color: AppColors.lethal),
            const SizedBox(width: 10),
            Expanded(
              child: Text(message,
                  style: AppText.caption.copyWith(color: AppColors.lethal)),
            ),
          ],
        ),
      );
}

/// 凝胶示意：左侧 marker 刻度、右侧样品泳道（只画迁移方向，不算浓度）。
///
/// 位置全部来自 [gelPositionFor]（对数分档），⇒ 短片段更靠下、
/// 等长必同高；图高固定 [PcrGelDiagram.kHeight] px，图内不放任何
/// 「亮度 = 拷贝数」的编码。
class PcrGelDiagram extends StatelessWidget {
  const PcrGelDiagram({
    super.key,
    required this.sampleLength,
    this.markerBps = kGelMarkerBps,
  });

  /// 样品片段长度（bp）。
  final int sampleLength;

  /// marker 分档（bp，从大到小）。
  final List<int> markerBps;

  /// 整图高度（含上下留白）。
  static const double kHeight = 236;
  static const double _padV = 16;
  static const double _labelWidth = 62;
  static const double _laneLeft = 106;

  @override
  Widget build(BuildContext context) {
    final inner = kHeight - _padV * 2;
    double yOf(int bp) =>
        _padV + gelPositionFor(bp, markerBps: markerBps) * inner;
    final sampleY = yOf(sampleLength);
    return LayoutBuilder(builder: (context, c) {
      final bandWidth =
          (c.maxWidth - _laneLeft - 12).clamp(60.0, double.infinity);
      // 条带/加样孔共用的横向区间（居中、窄条更像真实凝胶）
      final markWidth = math.min(160.0, bandWidth - 20);
      final markLeft = _laneLeft + (bandWidth - markWidth) / 2;
      return SizedBox(
        height: kHeight,
        child: Stack(
          children: [
            // 胶体
            Positioned(
              left: _laneLeft,
              width: bandWidth,
              top: 0,
              bottom: 0,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: AppColors.surfaceLow,
                  borderRadius: BorderRadius.circular(AppTheme.radiusInput),
                  border: Border.all(color: AppColors.border),
                ),
              ),
            ),
            // marker 刻度：标签右对齐 + 一条短刻度线
            for (final bp in markerBps) ...[
              Positioned(
                left: 0,
                width: _labelWidth,
                top: yOf(bp) - 8,
                child: Text(
                  '$bp bp',
                  textAlign: TextAlign.right,
                  style: AppText.caption.copyWith(
                      fontSize: 10.5, color: AppColors.graphite),
                ),
              ),
              Positioned(
                left: _labelWidth + 4,
                width: 10,
                top: yOf(bp),
                child: Container(
                  height: 1.2,
                  color: AppColors.steel.withValues(alpha: 0.55),
                ),
              ),
            ],
            // 加样孔：一个窄孔居中（⛔ 不画成通栏横条——那读起来像分隔线）
            Positioned(
              left: _laneLeft + (bandWidth - math.min(72.0, bandWidth - 20)) / 2,
              width: math.min(72.0, bandWidth - 20),
              top: 8,
              child: Container(
                height: 7,
                decoration: BoxDecoration(
                  color: AppColors.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            // 样品条带：居中的一条短条（读起来是「条带」而不是分隔线）；
            // 纵向位置只由长度决定 ⇒ 等长必同高、短片段更靠下。
            Positioned(
              left: markLeft,
              width: markWidth,
              top: sampleY - 3.5,
              child: Container(
                height: 7,
                decoration: BoxDecoration(
                  color: AppColors.teal,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Positioned(
              left: markLeft,
              width: markWidth,
              top: sampleY - 24,
              child: Text(
                '样品 $sampleLength bp',
                textAlign: TextAlign.center,
                style: AppText.caption.copyWith(
                    fontSize: 10.5, color: AppColors.teal),
              ),
            ),
          ],
        ),
      );
    });
  }
}
