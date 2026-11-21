// restriction_lab.dart —— 分子页第 5 个页签「基因工程」：限制酶切实验
//
// 为什么是「小而完整」的一个切片：教育部 2020 课标把**限制性内切核酸酶**
// 列为 DNA 重组的基本工具，教材上紧跟的就是「识别序列 → 切点 → 片段 →
// 黏性末端」这一条链。本实验只跑这一条链，⛔ 不扩成生信工作台：
//   · 一次一种酶（EcoRI / BamHI / HindIII，引擎见 restriction_engine.dart）；
//   · 只算线性 DNA：切 n 刀得 n+1 段；
//   · 结论只用于理解概念，屏上明写「不用于实验设计」（[kRestrictionDisclaimer]）。
//
// 布局沿用本页工作台语言（ToolWorkbench 的输入 / 结果两栏）：
//   · [RestrictionLabState.buildInputs] —— 左栏（窄屏时回落到结果区上方）：
//     酶选择 + 序列 + 示例 chip + 计算按钮；
//   · [RestrictionLabState.build] —— 结果区：识别位点与切点、序列标尺、
//     片段、双链切点示意。
//   `showInputs: true`（默认）把两者连成一体，单测/窄屏直接泵它；
//   页面里用 `showInputs: false`，输入区由左栏副本承担（**同一份 State**）。
//
// 状态归属：输入与结果共用 [RestrictionLabState] 一份真相，⛔ 不各存一份
// （两真相必分叉：屏上片段按旧酶算、按新酶标）。
// ⚠️ 宽屏左栏是**先于** TabBarView 里的本组件构建的（TabBarView 懒挂载），
// 首帧拿不到本 State ⇒ 本 State 挂载后向 [RestrictionLab.revision] 补发一次
// 通知，左栏副本据此把占位换成真正的输入面板（与 9331 页 panelRevision
// 同一套做法，见 cross_calculator_page.dart 的 v2.19.23 P0#1 注释）。

import 'package:flutter/material.dart';

import '../../engine/restriction_engine.dart';
import '../../theme.dart';
import 'cross_tool_rail.dart' show FlatSection;

/// 屏上一句话的模型边界（⛔ 不许删：这是「不虚构科学」的可见承诺）。
const String kRestrictionDisclaimer =
    '教学简化模型：只扫顶链 5′→3′、按线性 DNA 计（切 n 刀得 n+1 段）、'
    '一次一种酶；结论用于理解概念，不用于实验设计。';

/// 一个示例（chip）：一键把酶与序列都摆好——白板上不用键盘也能出结果。
class RestrictionSample {
  const RestrictionSample({
    required this.label,
    required this.sequence,
    required this.enzyme,
  });

  final String label;
  final String sequence;
  final RestrictionEnzyme enzyme;
}

/// 限制酶切实验（输入 + 结果，共享一份 State）。
class RestrictionLab extends StatefulWidget {
  const RestrictionLab({super.key, this.showInputs = true, this.revision});

  /// true（默认）：输入区 + 结果区一起渲染（自包含；单测/窄屏直接泵它）。
  /// false：只渲染结果区——页面里输入区由左栏副本
  /// （[RestrictionLabState.buildInputs]）承担。
  final bool showInputs;

  /// 左栏副本的重建信号（页面持有并负责 dispose，⛔ 本组件不 dispose 它）。
  final ValueNotifier<int>? revision;

  @override
  RestrictionLabState createState() => RestrictionLabState();
}

class RestrictionLabState extends State<RestrictionLab>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  /// 出厂默认题：EcoRI 在该序列上有 2 个位点 ⇒ 切成 3 段（3 + 9 + 7 = 19 bp）。
  /// ⚠️ 常量是唯一真相：controller 初值与 [isPristine] 共用同一批常量
  /// （本项目被「影子常量」坑过：两个真相一定会分叉）。
  static const String kDefaultSequence = 'GCGAATTCCGGGAATTCAA';
  static const RestrictionEnzyme kDefaultEnzyme = kEcoRI;

  /// 示例 chips（白板友好：点一下即算，⛔ 不必键盘输入）。
  static const List<RestrictionSample> samples = <RestrictionSample>[
    RestrictionSample(
        label: '示例·EcoRI 单位点',
        sequence: 'GGGAATTCGG',
        enzyme: kEcoRI),
    RestrictionSample(
        label: '示例·BamHI 单位点',
        sequence: 'TAGGATCCCT',
        enzyme: kBamHI),
    RestrictionSample(
        label: '示例·HindIII 单位点',
        sequence: 'CCCAAGCTTGGG',
        enzyme: kHindIII),
    RestrictionSample(
        label: '示例·EcoRI 双位点',
        sequence: kDefaultSequence,
        enzyme: kEcoRI),
    RestrictionSample(
        label: '示例·无位点', sequence: 'CCCGGGCCCGGG', enzyme: kEcoRI),
  ];

  final _seqCtrl = TextEditingController(text: kDefaultSequence);
  RestrictionEnzyme _enzyme = kDefaultEnzyme;
  RestrictionDigest? _digest;
  String? _error;

  /// 学生一个格子都没动过吗（父页深链覆盖守卫用）：序列与酶都还是出厂值。
  bool get isPristine =>
      _seqCtrl.text == kDefaultSequence && _enzyme == kDefaultEnzyme;

  @override
  void initState() {
    super.initState();
    // 出厂默认题先算一遍（与其余页签「出厂即展开默认结果」一致）。
    _digest = _digestQuiet(_seqCtrl.text, _enzyme);
    // 宽屏左栏先于本面板构建 ⇒ 挂载后补发一次通知，左栏副本才拿到输入面板。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _bumpRevision();
    });
  }

  @override
  void dispose() {
    _seqCtrl.dispose();
    super.dispose();
  }

  RestrictionDigest? _digestQuiet(String sequence, RestrictionEnzyme enzyme) {
    try {
      return restrictionDigest(sequence: sequence, enzyme: enzyme);
    } on ArgumentError {
      return null;
    }
  }

  /// 通知左栏副本重建（⛔ 页面持有该 ValueNotifier，此处只自增）。
  void _bumpRevision() => widget.revision?.value++;

  /// 按当前输入重算（按钮 / 回车 / 切酶 / 示例 chip 共用唯一入口）。
  void _compute() {
    try {
      final d = restrictionDigest(sequence: _seqCtrl.text, enzyme: _enzyme);
      setState(() {
        _digest = d;
        _error = null;
      });
    } on ArgumentError catch (e) {
      setState(() {
        _digest = null;
        _error = e.message?.toString() ?? '输入格式错误';
      });
    }
    _bumpRevision();
  }

  /// 供父页「全部计算」按一次刷新本实验（未挂载时父页取不到 State，
  /// 自然不会调到它）。
  void recalc() => _compute();

  void _pickEnzyme(RestrictionEnzyme enzyme) {
    if (enzyme.name == _enzyme.name) return;
    setState(() => _enzyme = enzyme);
    _compute();
  }

  void _applySample(RestrictionSample sample) {
    setState(() {
      _seqCtrl.text = sample.sequence;
      _enzyme = sample.enzyme;
    });
    _compute();
  }

  // ─── 输入区（宽屏左栏 / 窄屏结果区上方 / 自包含形态的顶部）───

  /// 输入面板：左侧工作台栏调用它（页面用 GlobalKey 取本 State）。
  Widget buildInputs(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FlatSection(
            title: '限制酶',
            subtitle: '选择性必修3 · 生物技术与工程',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '限制性内切核酸酶是 DNA 重组的基本工具：识别特定序列，'
                  '在切点把双链切成片段。三种酶的识别序列都是 6 bp 回文序列'
                  '（两链读出来一样），所以只看顶链就能定位位点。',
                  style: AppText.caption.copyWith(color: AppColors.graphite),
                ),
                const SizedBox(height: 8),
                for (final e in kRestrictionEnzymes) ...[
                  _enzymeTile(e),
                  const SizedBox(height: 6),
                ],
              ],
            ),
          ),
          FlatSection(
            title: 'DNA 序列（顶链 5′→3′）',
            subtitle: '只认 A、T、C、G；空格与换行自动忽略',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
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
                TextField(
                  controller: _seqCtrl,
                  style: AppText.monoSmall
                      .copyWith(fontSize: 14, letterSpacing: 1),
                  autocorrect: false,
                  enableSuggestions: false,
                  decoration: const InputDecoration(
                    isDense: true,
                    labelText: '序列（如 GCGAATTCCGGGAATTCAA）',
                    counterText: '',
                  ),
                  onSubmitted: (_) => _compute(),
                ),
                const SizedBox(height: 10),
                _bigButton('计算切点与片段', _compute),
              ],
            ),
          ),
        ],
      );

  /// 酶选项：整块可点（白板远距离也好按），选中态用同色系深一档，不整页换色。
  Widget _enzymeTile(RestrictionEnzyme enzyme) {
    final selected = enzyme.name == _enzyme.name;
    final border = selected ? AppColors.teal : AppColors.border;
    return Material(
      color: selected ? AppColors.tealWash : AppColors.surface,
      borderRadius: BorderRadius.circular(AppTheme.radiusInput),
      child: InkWell(
        onTap: () => _pickEnzyme(enzyme),
        borderRadius: BorderRadius.circular(AppTheme.radiusInput),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppTheme.radiusInput),
            border: Border.all(color: border, width: selected ? 1.6 : 1),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    enzyme.name,
                    style: AppText.monoSmall
                        .copyWith(fontSize: 14, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(width: 6),
                  if (selected)
                    Icon(Icons.check_circle,
                        size: 14, color: AppColors.teal),
                ],
              ),
              const SizedBox(height: 2),
              Text(
                '${enzyme.recognition} · ${enzyme.cutNotation}',
                style:
                    AppText.monoSmall.copyWith(fontSize: 12, letterSpacing: 0.5),
              ),
              const SizedBox(height: 2),
              Text(
                '黏性末端 5′-${enzyme.overhang}（位点 ${enzyme.siteLength} bp）',
                style: AppText.caption.copyWith(color: AppColors.graphite),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 主按钮：通栏 + 44 高（白板/触屏都够按），措辞即动作。
  Widget _bigButton(String label, VoidCallback onTap) => SizedBox(
        width: double.infinity,
        child: FilledButton.icon(
          onPressed: onTap,
          icon: const Icon(Icons.content_cut, size: 18),
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
    super.build(context); // TabBarView 往返时保留学生当前酶、序列与结果。
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
    final d = _digest;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(kRestrictionDisclaimer,
            style: AppText.caption.copyWith(color: AppColors.steel)),
        const SizedBox(height: 16),
        if (_error != null)
          FlatSection(
            title: '识别位点与切点',
            child: _errorBanner(_error!),
          )
        else if (d != null) ...[
          _siteSection(d),
          const SizedBox(height: 26),
          _rulerSection(d),
          const SizedBox(height: 26),
          _fragmentSection(d),
          const SizedBox(height: 26),
          _sketchSection(d),
        ],
      ],
    );
  }

  Widget _siteSection(RestrictionDigest d) => FlatSection(
        title: '识别位点与切点',
        subtitle: '位置统一按 1-based（第 1 个碱基 = 1）',
        trailing: AppChip(d.enzyme.name),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _kv('识别序列',
                '${d.enzyme.recognition}（${d.enzyme.siteLength} bp，回文）'),
            _kv('顶链切口', d.enzyme.cutNotation),
            _kv('黏性末端', d.enzyme.overhangText),
            const SizedBox(height: 6),
            if (!d.hasSite)
              Text('没有位点：本序列不含 ${d.enzyme.recognition}。',
                  style: AppText.caption.copyWith(color: AppColors.graphite))
            else
              for (var i = 0; i < d.sites.length; i++)
                _kv('位点 ${i + 1}',
                    '${d.sites[i].rangeText}；${d.sites[i].cutText}'
                    '（${d.sites[i].notation}）'),
            const SizedBox(height: 8),
            Text(d.summary,
                style: AppText.caption.copyWith(color: AppColors.graphite)),
          ],
        ),
      );

  /// 序列标尺：每 10 位右对齐标号；序列与标记逐列等宽对齐。
  Widget _rulerSection(RestrictionDigest d) => FlatSection(
        title: '序列标尺',
        subtitle: '每 10 位右对齐标号；[ ] 为识别位点，| 标在切口左侧碱基下',
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final line in _rulerLines(d))
                Text(
                  line,
                  style: AppText.monoSmall.copyWith(fontSize: 13, height: 1.35),
                ),
            ],
          ),
        ),
      );

  /// 四行标尺文本：里程碑编号 / 序列 / 位点括号 / 切口。
  /// 里程碑 10、20…的完整数字**右对齐**在该碱基列，避免把 11 错放到第 1 列。
  List<String> _rulerLines(RestrictionDigest d) {
    final seq = d.sequence;
    final len = seq.length;
    final indices = List<String>.filled(len, ' ');
    for (var milestone = 10; milestone <= len; milestone += 10) {
      final label = '$milestone';
      final start = milestone - label.length;
      for (var j = 0; j < label.length; j++) {
        indices[start + j] = label[j];
      }
    }
    // 位点括号与切口分两行：三酶都在位点首碱基后切，同行会互相覆盖。
    final siteMarks = List<String>.filled(len, ' ');
    final cutMarks = List<String>.filled(len, ' ');
    for (final s in d.sites) {
      siteMarks[s.start - 1] = '[';
      siteMarks[s.end - 1] = ']';
      cutMarks[s.cutAfter - 1] = '|';
    }
    return <String>[indices.join(), seq, siteMarks.join(), cutMarks.join()];
  }

  /// 测试钩子：与屏上完全同源的标尺行，防编号/切点凭截图误判。
  List<String> debugRulerLines(RestrictionDigest digest) => _rulerLines(digest);

  Widget _fragmentSection(RestrictionDigest d) => FlatSection(
        title: '切出的片段',
        subtitle: '线性 DNA：切 n 刀得 n+1 段（环状质粒切 n 刀得 n 段，本模型不涉及）',
        trailing: AppChip('${d.fragmentCount} 段'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final f in d.fragments) _fragmentRow(f),
            const SizedBox(height: 6),
            Text(
              '长度核算：${d.lengthsText} = ${d.fragmentLengthSum} bp'
              '（原序列 ${d.sequenceLength} bp）',
              style: AppText.body.copyWith(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: AppColors.teal,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '注意：识别序列长度 ${d.enzyme.siteLength} bp 不是片段数：'
              '片段数只由位点数决定。',
              style: AppText.caption.copyWith(color: AppColors.graphite),
            ),
            Text(
              '长度口径：按顶链原序列位置计；黏性末端是切后的局部单链形态，'
              '不另增或删减原序列碱基。',
              style: AppText.caption.copyWith(color: AppColors.graphite),
            ),
          ],
        ),
      );

  Widget _fragmentRow(RestrictionFragment f) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                SizedBox(
                  width: 66,
                  child: Text('片段 ${f.index}',
                      style: AppText.caption
                          .copyWith(color: AppColors.graphite)),
                ),
                Text('${f.length} bp',
                    style: AppText.monoSmall
                        .copyWith(fontSize: 15, fontWeight: FontWeight.w700)),
                const SizedBox(width: 10),
                Expanded(
                    child: Text(f.rangeText, style: AppText.caption)),
              ],
            ),
            Padding(
              padding: const EdgeInsets.only(left: 66, top: 2),
              child: Text(f.endsText,
                  style: AppText.caption.copyWith(color: AppColors.graphite)),
            ),
          ],
        ),
      );

  Widget _sketchSection(RestrictionDigest d) => FlatSection(
        title: '双链切点示意',
        subtitle: '上行顶链 5′→3′、下行底链 3′→5′；↓↑ 是两条链上的切口',
        child: d.hasSite
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (var i = 0; i < d.sites.length; i++) ...[
                    Text('位点 ${i + 1}：${d.sites[i].rangeText}',
                        style:
                            AppText.caption.copyWith(color: AppColors.graphite)),
                    const SizedBox(height: 2),
                    Text(
                      d.sites[i].doubleStrandSketch,
                      style: AppText.monoSmall
                          .copyWith(fontSize: 14, height: 1.6, letterSpacing: 1),
                    ),
                    const SizedBox(height: 12),
                  ],
                  Text(
                    '两条链的切口错开 ${d.enzyme.overhangLength} 个碱基：'
                    '错开的这 ${d.enzyme.overhangLength} 个碱基在切口处成为单链突出'
                    '（黏性末端 5′-${d.enzyme.overhang}），片段其余部分仍是双链。'
                    '同一种酶切出的两个末端能按碱基互补配对，DNA 连接酶才接得上。',
                    style: AppText.caption.copyWith(color: AppColors.graphite),
                  ),
                ],
              )
            : Text(
                '没有位点，因此没有切口，双链保持完整（两条链都是原序列）。',
                style: AppText.caption.copyWith(color: AppColors.graphite),
              ),
      );

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
