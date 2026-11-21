// knowledge_lab.dart —— 基因工程知识库：精选学习 + 三库实时只读检索
//
// 与 RestrictionLab / PcrLab 共用 showInputs、revision、isPristine、
// buildInputs 契约。内置记录与实时结果始终分区：前者经过教学筛选，后者
// 是数据库当次响应，不把“检索到”包装成“已经教学审核”。

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../data/bio_knowledge_data.dart';
import '../../models/bio_knowledge.dart';
import '../../services/bio_database_service.dart';
import '../../theme.dart';
import '../../ui/tex_formula.dart';
import 'cas9_cut_exercise.dart';
import 'cross_tool_rail.dart' show FlatSection;
import 'dna_ligase_bond_exercise.dart';
import 'pcr_amplification_exercise.dart';
import 'pcr_cycle_exercise.dart';
import 'pcr_efficiency_exercise.dart';
import 'primer_extension_exercise.dart';
import 'taq_heat_exercise.dart';

class KnowledgeLab extends StatefulWidget {
  const KnowledgeLab({
    super.key,
    this.showInputs = true,
    this.revision,
    this.service,
    this.linkLauncher,
  });

  final bool showInputs;
  final ValueNotifier<int>? revision;
  final BioDatabaseClient? service;
  final Future<bool> Function(Uri uri)? linkLauncher;

  @override
  KnowledgeLabState createState() => KnowledgeLabState();
}

class KnowledgeLabState extends State<KnowledgeLab>
    with AutomaticKeepAliveClientMixin {
  static const samples = <String>[
    'EcoRI',
    'Taq',
    'GFP',
    'PCR',
    'CRISPR',
    'PAM',
  ];

  final _queryCtrl = TextEditingController();
  final _cas9Key = GlobalKey<Cas9CutExerciseState>();
  late final BioDatabaseClient _service =
      widget.service ?? BioDatabaseService();
  BioSource? _source;
  BioSearchResponse? _live;
  String? _liveQuery;
  BioSource? _liveSource;
  String? _pendingQuery;
  BioSource? _pendingSource;
  String? _error;
  bool _loading = false;
  int _requestSerial = 0;

  @override
  bool get wantKeepAlive => true;

  bool get isPristine => _queryCtrl.text.trim().isEmpty && _source == null;

  bool get _liveMatchesFilters =>
      _liveQuery == _queryCtrl.text.trim() && _liveSource == _source;

  static String _sourceLabel(BioSource? source) => source?.label ?? '全部来源';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _bumpRevision();
    });
  }

  @override
  void dispose() {
    _requestSerial++;
    _queryCtrl.dispose();
    _service.dispose();
    super.dispose();
  }

  void _bumpRevision() => widget.revision?.value++;

  void _invalidatePending() {
    _requestSerial++;
    _loading = false;
    _pendingQuery = null;
    _pendingSource = null;
  }

  void recalc() {
    if (_queryCtrl.text.trim().isNotEmpty) _search();
    _cas9Key.currentState?.recalc();
  }

  Future<void> _search() async {
    final query = _queryCtrl.text.trim();
    if (query.isEmpty) {
      setState(() => _error = '请输入关键词，或先点一个示例。');
      _bumpRevision();
      return;
    }
    final source = _source;
    final serial = ++_requestSerial;
    setState(() {
      _loading = true;
      _pendingQuery = query;
      _pendingSource = source;
      _error = null;
    });
    _bumpRevision();
    try {
      final result = await _service.search(query, source: source);
      if (!mounted || serial != _requestSerial) return;
      setState(() {
        _live = result;
        _liveQuery = query;
        _liveSource = source;
        _loading = false;
        _pendingQuery = null;
        _pendingSource = null;
      });
    } catch (e) {
      if (!mounted || serial != _requestSerial) return;
      setState(() {
        _loading = false;
        _pendingQuery = null;
        _pendingSource = null;
        _error = e is BioDatabaseException
            ? e.message
            : '实时查询失败，请检查网络后重试。内置精选仍可离线学习。';
      });
    }
    _bumpRevision();
  }

  void _applySample(String sample) {
    setState(() {
      _queryCtrl.text = sample;
      _invalidatePending();
      _error = null;
    });
    _bumpRevision();
  }

  void _setSource(BioSource? source) {
    setState(() {
      _source = source;
      _invalidatePending();
      _error = null;
    });
    _bumpRevision();
  }

  void _clearFilters() {
    setState(() {
      _queryCtrl.clear();
      _source = null;
      _invalidatePending();
      _error = null;
    });
    _bumpRevision();
  }

  Widget buildInputs(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      FlatSection(
        title: '知识检索',
        subtitle: 'UniProt · RCSB PDB · PubMed',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '先在内置精选中筛选；需要探索更多条目时，再实时查询原始数据库。'
              '实时结果不等于教学审核结论。',
              style: AppText.caption.copyWith(color: AppColors.graphite),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                ChoiceChip(
                  label: const Text('全部来源'),
                  selected: _source == null,
                  onSelected: (_) => _setSource(null),
                ),
                for (final source in BioSource.values)
                  ChoiceChip(
                    label: Text(source.label),
                    selected: _source == source,
                    onSelected: (_) => _setSource(source),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                for (final sample in samples)
                  ActionChip(
                    label: Text(sample),
                    onPressed: () => _applySample(sample),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            TextField(
              key: const Key('knowledge-search-input'),
              controller: _queryCtrl,
              autocorrect: false,
              enableSuggestions: false,
              decoration: const InputDecoration(
                isDense: true,
                labelText: '蛋白质、结构或文献关键词',
                hintText: '如 EcoRI、Taq、GFP、PCR',
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: (_) {
                setState(() {
                  _invalidatePending();
                  _error = null;
                });
                _bumpRevision();
              },
              onSubmitted: (_) => _search(),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _loading ? null : _search,
                icon: const Icon(Icons.travel_explore, size: 18),
                label: Text(_loading ? '正在查询…' : '实时查询'),
              ),
            ),
          ],
        ),
      ),
      if (!widget.showInputs)
        _cas9Key.currentState?.buildInputs(context) ?? const SizedBox.shrink(),
    ],
  );

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final builtIn = filterBioKnowledge(query: _queryCtrl.text, source: _source);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.showInputs) buildInputs(context),
        Row(
          children: [
            Icon(Icons.menu_book_outlined, color: AppColors.teal, size: 22),
            const SizedBox(width: 8),
            Expanded(child: Text('遗传与基因工程 · 知识库', style: AppText.sectionTitle)),
          ],
        ),
        const SizedBox(height: 6),
        Text('把课堂概念连接到蛋白质、三维结构与原始研究文献；链接均可选择、复制。', style: AppText.caption),
        const SizedBox(height: 16),
        _formulaPanel(),
        const SizedBox(height: 12),
        DnaLigaseBondExercise(onShowEvidence: () => _applySample('DNA 连接酶')),
        const SizedBox(height: 12),
        TaqHeatExercise(onShowEvidence: () => _applySample('Taq')),
        const SizedBox(height: 12),
        PrimerExtensionExercise(onShowEvidence: () => _applySample('引物末端')),
        const SizedBox(height: 12),
        PcrCycleExercise(onShowEvidence: () => _applySample('PCR 温度循环')),
        const SizedBox(height: 12),
        PcrAmplificationExercise(
          onShowEvidence: () => _applySample('PCR 理论扩增'),
        ),
        const SizedBox(height: 12),
        PcrEfficiencyExercise(onShowEvidence: () => _applySample('PCR 效率对照')),
        const SizedBox(height: 12),
        _pamPanel(),
        const SizedBox(height: 24),
        Cas9CutExercise(
          key: _cas9Key,
          showInputs: widget.showInputs,
          revision: widget.revision,
        ),
        const SizedBox(height: 12),
        if (_error != null) _messageBanner(_error!, isError: true),
        AppSectionHeader('内置精选', trailing: AppChip('${builtIn.length} 条')),
        Text('内置已核验 · 离线可读 · 按当前关键词与来源筛选', style: AppText.caption),
        const SizedBox(height: 6),
        if (builtIn.isEmpty)
          _builtInEmptyState()
        else
          for (final record in builtIn) _recordCard(record, builtIn: true),
        if (_loading && _pendingQuery != null) ...[
          const SizedBox(height: 16),
          Semantics(
            container: true,
            liveRegion: true,
            label: '正在读取原始数据库',
            child: Text(
              '正在查询“$_pendingQuery” · 来源：${_sourceLabel(_pendingSource)}',
              style: AppText.label,
            ),
          ),
          const SizedBox(height: 8),
          _searchSkeleton(),
        ],
        if (_live != null) ...[
          AppSectionHeader(
            _liveMatchesFilters ? '实时查询' : '上次实时结果',
            trailing: AppChip('${_live!.records.length} 条'),
          ),
          Text(
            '关键词“${_liveQuery ?? ''}” · 来源：${_sourceLabel(_liveSource)} · '
            '查询时间：${_formatTime(_live!.queriedAt)} · 数据库当次响应，未逐条教学审核',
            style: AppText.caption,
          ),
          const SizedBox(height: 6),
          if (_live!.failures.isNotEmpty)
            _messageBanner(
              <String>[
                if (_live!.records.isNotEmpty)
                  '部分来源未返回（${_live!.failures.length} 个）；'
                      '已保留 ${_live!.records.length} 条可用结果。',
                ..._live!.failures,
              ].join('\n'),
              isError: _live!.records.isEmpty,
            ),
          if (_live!.records.isEmpty)
            _live!.failures.isEmpty
                ? _noMatchState()
                : Padding(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    child: Text('本次未取回可用记录，请根据上方错误提示重试。', style: AppText.body),
                  )
          else
            for (final record in _live!.records)
              _recordCard(record, builtIn: false),
        ],
        const SizedBox(height: 12),
        Text(
          '学习提示：高中基础 PCR 与 CRISPR/Cas9 基因编辑是不同技术主题；'
          '结构条目还要留意突变体、蛋白片段和复合物等边界。',
          style: AppText.caption,
        ),
      ],
    );
  }

  Widget _builtInEmptyState() => Container(
    key: const ValueKey('knowledge-built-in-empty'),
    width: double.infinity,
    margin: const EdgeInsets.only(top: 12),
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: AppColors.surfaceLow,
      borderRadius: BorderRadius.circular(AppTheme.radiusCard),
      border: Border.all(color: AppColors.border),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.menu_book_outlined, size: 24, color: AppColors.teal),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('内置精选中没有匹配项。', style: AppText.label),
              const SizedBox(height: 4),
              Text('可清空关键词与来源筛选，恢复全部已核验记录。', style: AppText.body),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: _clearFilters,
                  icon: const Icon(Icons.clear_all, size: 18),
                  label: const Text('清空筛选'),
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );

  Widget _noMatchState() => Container(
    key: const ValueKey('knowledge-live-no-match'),
    width: double.infinity,
    margin: const EdgeInsets.only(top: 12),
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: AppColors.surfaceLow,
      borderRadius: BorderRadius.circular(AppTheme.radiusCard),
      border: Border.all(color: AppColors.border),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.search_off, size: 24, color: AppColors.teal),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('本次查询没有匹配记录。', style: AppText.label),
              const SizedBox(height: 4),
              Text('可缩短关键词、更换来源，或填入示例后再查。', style: AppText.body),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () => _applySample('GFP'),
                  icon: const Icon(Icons.lightbulb_outline, size: 18),
                  label: const Text('填入 GFP 示例'),
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );

  Widget _searchSkeleton() => Container(
    key: const ValueKey('knowledge-search-skeleton'),
    width: double.infinity,
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: AppColors.surfaceLow,
      borderRadius: BorderRadius.circular(AppTheme.radiusCard),
      border: Border.all(color: AppColors.border),
    ),
    child: const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SkeletonBar(widthFactor: 0.36),
        SizedBox(height: 12),
        _SkeletonBar(widthFactor: 0.92),
        SizedBox(height: 8),
        _SkeletonBar(widthFactor: 0.78),
        SizedBox(height: 12),
        _SkeletonBar(widthFactor: 0.58),
      ],
    ),
  );

  Widget _formulaPanel() => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: AppColors.tealWash,
      borderRadius: BorderRadius.circular(AppTheme.radiusCard),
      border: Border.all(color: AppColors.border),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('概念公式 · 与既有实验互相对应', style: AppText.label),
        const SizedBox(height: 8),
        Text(
          'PCR 理想扩增（N₀ 为初始目标 DNA 分子份数，n 为循环数；不评估效率损失）',
          style: AppText.caption,
        ),
        const TexFormula(
          tex: r'N=N_0\times2^n',
          fallback: 'N = N₀ × 2ⁿ',
          semanticsLabel: '理论产物份数等于初始模板份数乘 2 的循环数次方',
        ),
        const SizedBox(height: 8),
        Text('线性 DNA 被切开 n 个位点后的片段数', style: AppText.caption),
        const TexFormula(
          tex: r'F=n+1',
          fallback: 'F = n + 1',
          semanticsLabel: '线性 DNA 的片段数等于切点数加一',
        ),
      ],
    ),
  );

  Widget _pamPanel() => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: AppColors.surfaceLow,
      borderRadius: BorderRadius.circular(AppTheme.radiusCard),
      border: Border.all(color: AppColors.border),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.compare_arrows, size: 20, color: AppColors.teal),
            const SizedBox(width: 8),
            Expanded(child: Text('PAM ≠ 引导 RNA 配对区', style: AppText.label)),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          'PAM 是靶 DNA 上原间隔序列邻近的短序列；引导 RNA 的配对区与靶 DNA 互补。'
          '二者位置和作用不同，PAM 不位于引导 RNA 上。',
          style: AppText.body,
        ),
        const SizedBox(height: 10),
        Text('化脓性链球菌 Cas9 的经典 PAM', style: AppText.caption),
        const TexFormula(
          tex: r"5^{\prime}-\mathrm{NGG}-3^{\prime}",
          fallback: '5′-NGG-3′',
          semanticsLabel: '化脓性链球菌 Cas9 的经典 PAM 为 5 撇 NGG 3 撇，N 可为 A、T、C 或 G',
        ),
        const SizedBox(height: 6),
        Text(
          'N 可为 A、T、C 或 G。该序列并非所有 Cas 蛋白通用；'
          '书写时必须带链方向，并结合双链理解。',
          style: AppText.caption,
        ),
        const SizedBox(height: 8),
        ActionChip(
          avatar: const Icon(Icons.menu_book_outlined, size: 17),
          label: const Text('查看 PAM 证据'),
          onPressed: () => _applySample('PAM'),
        ),
      ],
    ),
  );

  Widget _messageBanner(String message, {required bool isError}) {
    final tone = isError ? AppColors.lethal : AppColors.sand;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: tone.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppTheme.radiusInput),
        border: Border.all(color: tone.withValues(alpha: 0.45)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            isError ? Icons.error_outline : Icons.info_outline,
            size: 19,
            color: tone,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(message, style: AppText.body.copyWith(color: tone)),
          ),
        ],
      ),
    );
  }

  Widget _recordCard(BioKnowledgeRecord record, {required bool builtIn}) =>
      Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 6,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  AppChip(record.source.label, icon: Icons.dns_outlined),
                  AppChip(record.id),
                  AppChip(builtIn ? '内置已核验' : '实时结果'),
                ],
              ),
              const SizedBox(height: 10),
              SelectableText(
                record.title,
                style: AppText.label.copyWith(height: 1.45),
              ),
              if (record.subtitle.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(record.subtitle, style: AppText.caption),
              ],
              const SizedBox(height: 8),
              Text(record.summary, style: AppText.body),
              if (record.facts.isNotEmpty) ...[
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    for (final fact in record.facts)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.surfaceLow,
                          borderRadius: BorderRadius.circular(
                            AppTheme.radiusChip,
                          ),
                        ),
                        child: Text(
                          '${fact.label}：${fact.value}',
                          style: AppText.caption,
                        ),
                      ),
                  ],
                ),
              ],
              if (record.caution != null) ...[
                const SizedBox(height: 10),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.sand.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(AppTheme.radiusInput),
                    border: Border.all(
                      color: AppColors.sand.withValues(alpha: 0.35),
                    ),
                  ),
                  child: Text(
                    record.caution!,
                    style: AppText.caption.copyWith(color: AppColors.sand),
                  ),
                ),
              ],
              const SizedBox(height: 10),
              SelectableText(
                record.url,
                maxLines: 3,
                style: AppText.monoSmall.copyWith(
                  fontSize: 11,
                  color: AppColors.tealDark,
                ),
              ),
              Align(
                alignment: Alignment.centerRight,
                child: Wrap(
                  spacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    TextButton.icon(
                      onPressed: () => _copyLink(record),
                      icon: const Icon(Icons.copy_outlined, size: 17),
                      label: const Text('复制链接'),
                    ),
                    TextButton.icon(
                      onPressed: () => _openLink(record),
                      icon: const Icon(Icons.open_in_new, size: 17),
                      label: const Text('打开原始页面'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );

  static Future<bool> _launchExternal(Uri uri) =>
      launchUrl(uri, mode: LaunchMode.externalApplication);

  Future<void> _openLink(BioKnowledgeRecord record) async {
    final uri = Uri.tryParse(record.url);
    var opened = false;
    if (uri != null &&
        (uri.scheme == 'http' || uri.scheme == 'https') &&
        uri.hasAuthority) {
      try {
        opened = await (widget.linkLauncher ?? _launchExternal)(uri);
      } on Object {
        opened = false;
      }
    }
    if (!mounted || opened) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            '无法打开 ${record.source.label} ${record.id} 的原始页面，请复制链接后在浏览器中打开。',
          ),
        ),
      );
  }

  Future<void> _copyLink(BioKnowledgeRecord record) async {
    var copied = true;
    try {
      await Clipboard.setData(ClipboardData(text: record.url));
    } on Object {
      copied = false;
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            copied
                ? '已复制 ${record.source.label} ${record.id} 的链接'
                : '无法复制 ${record.source.label} ${record.id} 的链接，请选中上方链接手动复制。',
          ),
        ),
      );
  }

  static String _formatTime(DateTime time) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${time.year}-${two(time.month)}-${two(time.day)} '
        '${two(time.hour)}:${two(time.minute)}:${two(time.second)}';
  }
}

class _SkeletonBar extends StatelessWidget {
  const _SkeletonBar({required this.widthFactor});

  final double widthFactor;

  @override
  Widget build(BuildContext context) => FractionallySizedBox(
    widthFactor: widthFactor,
    child: Container(
      height: 12,
      decoration: BoxDecoration(
        color: AppColors.border,
        borderRadius: BorderRadius.circular(AppTheme.radiusInput),
      ),
    ),
  );
}
