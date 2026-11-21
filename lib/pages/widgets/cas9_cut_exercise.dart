// cas9_cut_exercise.dart —— 经典 SpCas9 双链切割位置互动练习
//
// 输入与结果共用一份 State，与知识库其他工具遵循同一契约：
//   · showInputs=true：自包含，输入区与结果区一起渲染；
//   · showInputs=false：只渲染结果区，输入由 KnowledgeLab.buildInputs 转发
//     [Cas9CutExerciseState.buildInputs]，放在页面左侧工作台。
// 科学规则集中在 engine/cas9_cut_engine.dart，本组件只负责交互与展示。

import 'package:flutter/material.dart';

import '../../engine/cas9_cut_engine.dart';
import '../../theme.dart';
import 'cross_tool_rail.dart' show FlatSection;

class Cas9CutExercise extends StatefulWidget {
  const Cas9CutExercise({super.key, this.showInputs = true, this.revision});

  final bool showInputs;
  final ValueNotifier<int>? revision;

  @override
  Cas9CutExerciseState createState() => Cas9CutExerciseState();
}

class Cas9CutExerciseState extends State<Cas9CutExercise>
    with AutomaticKeepAliveClientMixin {
  static const String topExample = 'TTTTTACGTACGTACGTACGTACGTTGGTTT';
  static const String bottomExample = 'AAAACCGACGTACGTACGTACGTACGTTT';

  final _sequenceCtrl = TextEditingController();
  SpCas9Analysis? _analysis;
  String? _error;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _bumpRevision();
    });
  }

  @override
  void dispose() {
    _sequenceCtrl.dispose();
    super.dispose();
  }

  void _bumpRevision() => widget.revision?.value++;

  void _applySample(String sequence) {
    _sequenceCtrl.text = sequence;
    _compute();
  }

  /// 按钮、回车、示例和父页刷新共用唯一计算入口。
  void recalc() => _compute();

  void _compute() {
    try {
      final result = analyzeSpCas9Cuts(_sequenceCtrl.text);
      setState(() {
        _analysis = result;
        _error = null;
      });
    } on ArgumentError catch (error) {
      setState(() {
        _analysis = null;
        _error = error.message?.toString() ?? '输入格式错误';
      });
    }
    _bumpRevision();
  }

  /// 左栏副本与本组件自包含形态共用的练习输入区。
  Widget buildInputs(BuildContext context) => FlatSection(
    title: 'SpCas9 切割练习',
    subtitle: '顶链恒按 5′→3′ · 23–120 bp',
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '同时检查上链 NGG 与互补链 NGG（顶链表现为 CCN）；'
          '只接受 A、T、C、G，空白自动忽略。',
          style: AppText.caption.copyWith(color: AppColors.graphite),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 6,
          runSpacing: 4,
          children: [
            ActionChip(
              label: const Text('上链 NGG 示例'),
              onPressed: () => _applySample(topExample),
            ),
            ActionChip(
              label: const Text('互补链 NGG 示例'),
              onPressed: () => _applySample(bottomExample),
            ),
          ],
        ),
        const SizedBox(height: 10),
        TextField(
          key: const Key('cas9-sequence-input'),
          controller: _sequenceCtrl,
          style: AppText.monoSmall.copyWith(fontSize: 14, letterSpacing: 0.8),
          autocorrect: false,
          enableSuggestions: false,
          maxLines: 3,
          minLines: 1,
          decoration: const InputDecoration(
            isDense: true,
            labelText: 'DNA 序列（顶链 5′→3′）',
            hintText: '输入 23–120 bp',
            counterText: '',
          ),
          onChanged: (_) {
            // 输入已变，旧位点不能继续冒充新序列的答案。
            setState(() {
              _analysis = null;
              _error = null;
            });
            _bumpRevision();
          },
          onSubmitted: (_) => _compute(),
        ),
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: _compute,
            icon: const Icon(Icons.content_cut, size: 18),
            label: const Text('判断切割位置'),
            style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
          ),
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final results = _buildResults();
    if (!widget.showInputs) return results;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [buildInputs(context), results],
    );
  }

  Widget _buildResults() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        children: [
          Icon(Icons.content_cut, size: 21, color: AppColors.teal),
          const SizedBox(width: 8),
          Expanded(child: Text('SpCas9 切割位置练习', style: AppText.sectionTitle)),
        ],
      ),
      const SizedBox(height: 6),
      Text(
        '找出 PAM 同链 5′ 侧的 20 nt 原间隔序列，再判断 PAM 上游约 3 bp 的平末端边界。',
        style: AppText.caption,
      ),
      const SizedBox(height: 12),
      if (_error != null)
        _messagePanel(_error!, isError: true)
      else if (_analysis == null)
        _emptyPanel()
      else if (_analysis!.sites.isEmpty)
        _noSitePanel(_analysis!)
      else ...[
        Text(
          '找到 ${_analysis!.sites.length} 个可分析位点 · 双链共 ${_analysis!.pamMotifCount} 个 NGG motif',
          style: AppText.label,
        ),
        const SizedBox(height: 10),
        for (var i = 0; i < _analysis!.sites.length; i++)
          _sitePanel(_analysis!, _analysis!.sites[i], i),
      ],
      const SizedBox(height: 4),
      Text(
        '教学边界：仅处理经典 SpCas9 的 NGG 与理想平末端切割；'
        '不预测编辑效率、脱靶或安全性，也不推广到其他 Cas 蛋白。',
        style: AppText.caption.copyWith(color: AppColors.steel),
      ),
    ],
  );

  Widget _emptyPanel() => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(14),
    decoration: _panelDecoration(),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('先选一个示例，或输入一段 DNA', style: AppText.label),
        const SizedBox(height: 6),
        Text(
          '顶链 NGG 从 PAM 向左取 20 nt；互补链 NGG 在顶链写作 CCN，'
          '从其右侧取 20 nt 后反向互补。两条链的切口位于同一碱基对边界。',
          style: AppText.body,
        ),
      ],
    ),
  );

  Widget _noSitePanel(SpCas9Analysis analysis) {
    final noMotif = analysis.pamMotifCount == 0;
    return _messagePanel(
      noMotif
          ? '两条链都未检测到经典 NGG（顶链 NGG；互补链在顶链表现为 CCN）。'
          : '共发现 ${analysis.pamMotifCount} 个 NGG motif，但没有位点同时具备 '
                'PAM 同链 5′ 侧的完整 20 nt 原间隔序列。请向相应一侧补足序列。',
      isError: false,
      title: noMotif ? '未找到经典 NGG 位点' : '发现 PAM，但原间隔序列不足 20 nt',
    );
  }

  Widget _messagePanel(String message, {required bool isError, String? title}) {
    final tone = isError ? AppColors.lethal : AppColors.sand;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: tone.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppTheme.radiusCard),
        border: Border.all(color: tone.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (title != null) ...[
            Text(title, style: AppText.label.copyWith(color: tone)),
            const SizedBox(height: 6),
          ],
          Text(message, style: AppText.body.copyWith(color: tone)),
        ],
      ),
    );
  }

  Widget _sitePanel(SpCas9Analysis analysis, Cas9CutSite site, int index) {
    final isTop = site.pamStrand == Cas9PamStrand.displayedTop;
    return Container(
      key: Key('cas9-site-panel-$index'),
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: _panelDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '位点 ${index + 1} · ${isTop ? '上链 NGG' : '互补链 NGG（顶链 CCN）'}',
            style: AppText.label.copyWith(color: AppColors.tealDark),
          ),
          const SizedBox(height: 10),
          _valueBlock('PAM（按所在链 5′→3′）', site.pam, monospace: true),
          Text(
            '顶链 motif 位次：第 ${site.pamStart1Based}–${site.pamEnd1Based} 位',
            style: AppText.caption,
          ),
          const SizedBox(height: 10),
          _valueBlock(
            'PAM 同链 5′ 侧原间隔序列（20 nt，5′→3′）',
            site.protospacer,
            monospace: true,
            selectable: true,
          ),
          const SizedBox(height: 10),
          _valueBlock(
            '平末端切割边界',
            '顶链第 ${site.cutLeft1Based} 位与第 ${site.cutRight1Based} 位之间'
                '（两条链同一边界）',
          ),
          const SizedBox(height: 12),
          Text('双链切割示意（↓ 为同一边界）', style: AppText.caption),
          const SizedBox(height: 6),
          SingleChildScrollView(
            key: Key('cas9-strand-scroll-$index'),
            scrollDirection: Axis.horizontal,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '5′-${analysis.topSequence}-3′',
                  style: AppText.monoSmall.copyWith(fontSize: 13, height: 1.4),
                ),
                Text(
                  '${' ' * (site.cutBoundary + 3)}↓',
                  style: AppText.monoSmall.copyWith(
                    fontSize: 13,
                    height: 1.4,
                    color: AppColors.lethal,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  '3′-${analysis.bottomSequence}-5′',
                  style: AppText.monoSmall.copyWith(fontSize: 13, height: 1.4),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _valueBlock(
    String label,
    String value, {
    bool monospace = false,
    bool selectable = false,
  }) {
    final style = monospace
        ? AppText.monoSmall.copyWith(fontSize: 14, color: AppColors.ink)
        : AppText.body;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: AppText.caption),
        const SizedBox(height: 3),
        if (selectable)
          SelectableText(value, style: style)
        else
          Text(value, style: style),
      ],
    );
  }

  BoxDecoration _panelDecoration() => BoxDecoration(
    color: AppColors.surfaceLow,
    borderRadius: BorderRadius.circular(AppTheme.radiusCard),
    border: Border.all(color: AppColors.border),
  );
}
