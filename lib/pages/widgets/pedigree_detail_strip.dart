// pedigree_detail_strip.dart —— 系谱页底部详情面板（2.3 重构抽取）
//
// 从 genetic_pedigree_page.dart（3961 行屎山）抽出，纯展示组件：
// 页面把引擎/选中态/回调传入，本组件不持有任何状态。
// 行为与抽取前逐行一致（按钮文案「导入 9331」「取消连线」「删除」等
// 是测试依赖，不可改）。
//
// R7-P2: _nodeInfo 单函数 250 行超 200 阈值，拆为 4 个子助手函数：
//   _buildHeaderRow（标题行：AppChip + id + 3 按钮）
//   _buildGenotypeBlock（基因型 InkWell 块）
//   _buildInfoItems（信息项列表 → Wrap）
//   _buildContentRow（窄屏/宽屏布局）
//   _buildNodeInfo（拼装主调用，~40 行）

import 'package:flutter/material.dart';

import '../../engine/pedigree_graph.dart';
import '../../engine/phenotype_grouper.dart';
import '../../theme.dart';
import 'pedigree_canvas.dart' show parseTapId;

/// 单基因型的表型标签（如 'A显·B隐' / 'X显'），单样本归组即可。
String phenotypeLabelOf(String genotype) =>
    groupByPhenotype([GenotypeSample(genotype, 1)]).first.label;

/// 一组概率 → 最小整数计数（k = 1..256），凑不出返回 null。
///
/// 上限按分母定：4 对基因自交的分母正好是 256（81:27:…:1，六个 9 / 四个 3），
/// 高中范围到顶。原来只试到 64，导致 4 对基因这种教科书场景直接退回百分比。
/// 再往上不放开：概率多是任意小数，k 越大越容易凑出 643:234:123 这类
/// 毫无意义的"整数比"，还不如百分比诚实。
List<int>? integerCountsOf(List<double> probabilities) {
  for (var k = 1; k <= 256; k++) {
    final vals = [for (final p in probabilities) p * k];
    if (vals.every((v) => (v - v.round()).abs() < 1e-9)) {
      return [for (final v in vals) v.round()];
    }
  }
  return null;
}

/// 每组的配比值：优先最小整数比，凑不出退回百分比（1 位小数）。
List<String> phenotypeRatioValues(List<PhenotypeGroup> groups) {
  final ratio = integerCountsOf([for (final g in groups) g.probability]);
  return [
    for (var i = 0; i < groups.length; i++)
      ratio == null
          ? '${(groups[i].probability * 100).toStringAsFixed(1)}%'
          : '${ratio[i]}',
  ];
}

/// 本代配比文案：'A显·B显 9 : A隐·B隐 1'；组数 > 4 只显示前 3 组 +
/// 「等 N 类」（N = 被省略的组数）。
String phenotypeRatioText(List<PhenotypeGroup> groups) {
  if (groups.isEmpty) return '';
  final values = phenotypeRatioValues(groups);
  final shown = groups.length > 4 ? 3 : groups.length;
  final parts = [
    for (var i = 0; i < shown; i++) '${groups[i].label} ${values[i]}',
  ];
  if (groups.length > 4) parts.add('等 ${groups.length - 3} 类');
  return parts.join(' : ');
}

/// 某一（家族, 世代）的表型分组。
///
/// 致死桶剔除：引擎给存活子代按「存活总和 = 1」归一化，致死桶保留的是
/// 未归一化的原始概率，混算会把比例拉歪（AA .25 / Aa .5 / aa 致死 .25
/// 会凑成 4:8:3 而不是正确的 1:2，理由同 _shareGroupOf）。
List<PhenotypeGroup> phenotypeGroupsOf(
    PedigreeGraphEngine engine, int familyId, int generation) {
  return groupByPhenotype([
    for (final n in engine.nodes)
      if (!n.isExternal &&
          !n.isLethal &&
          n.familyId == familyId &&
          n.generation == generation)
        GenotypeSample(n.genotype, n.probability),
  ]);
}

/// 未选中任何节点时详情条要给的「答案」：最新一代各家族的表型比。
///
/// P0-1：点节点只是看单个基因型的细节，不该是拿到答案的前提。只读引擎
/// 已有节点，不新造状态；还没算出子代（只有 P 代）时返回空表，由调用方
/// 显示兜底文案。
List<(String, List<PhenotypeGroup>)> latestPhenotypeRatios(
    PedigreeGraphEngine engine) {
  final gen = engine.maxGeneration;
  if (gen <= 0) return const [];
  final fams = <int>{
    for (final n in engine.nodes)
      if (!n.isExternal && n.generation == gen) n.familyId,
  };
  final multi = fams.length > 1;
  return [
    for (final f in fams)
      (
        multi ? '${engine.familyLabel(f)} 本代配比' : '本代配比',
        phenotypeGroupsOf(engine, f, gen),
      ),
  ].where((e) => e.$2.isNotEmpty).toList();
}

/// 计算成功的一句话确认（P0-7）：'已算出子代：9 种基因型，表型比 9:3:3:1'。
/// 表型拿不到（只有一种表型 / 凑不出整数比）时只报基因型数。
String deriveSuccessMessage(PedigreeGraphEngine engine) {
  final gen = engine.maxGeneration;
  final nodes = [
    for (final n in engine.nodes)
      if (!n.isExternal && !n.isLethal && n.generation == gen) n,
  ];
  if (nodes.isEmpty) return '已算出系谱';
  final groups = groupByPhenotype([
    for (final n in nodes) GenotypeSample(n.genotype, n.probability),
  ]);
  // 单组没有"比"可读（表型比 1 是噪音）；凑不出整数比也只报基因型数。
  final counts = groups.length > 1
      ? integerCountsOf([for (final g in groups) g.probability])
      : null;
  final kinds = {for (final n in nodes) n.genotype}.length;
  return '已算出子代：$kinds 种基因型'
      '${counts == null ? '' : '，表型比 ${counts.join(':')}'}';
}

/// 单个基因型在某一代里的份数展示（'9/64'；凑不出整数时是 '6.3%'）。
class GenotypeShare {
  const GenotypeShare(this.genotype, this.share);

  final String genotype;
  final String share;
}

/// 一个已展开世代的完整基因型配比。
///
/// 纯数据、不带「当前是哪一代」的单值状态 —— 多世代同时展开时详情条
/// 逐代各一块，由 [genotypeShareGroups] 全部算好后一起渲染。
class GenotypeShareGroup {
  const GenotypeShareGroup({
    required this.label,
    required this.entries,
    required this.total,
    this.lethal = 0,
  });

  final String label;
  final List<GenotypeShare> entries;

  /// 该代总份数（F2 = 64）；概率凑不成整数时为 null，条目退回百分比。
  final int? total;

  /// 被剔除的致死基因型数（>0 时 header 会写明，避免「共 N 个」悄悄少算）。
  final int lethal;

  /// 'F2 · 27 种基因型 · 共 64 个'
  String get header => total == null
      ? '$label · ${entries.length} 种基因型${lethal > 0 ? ' · 致死 $lethal 种已剔除' : ''}'
      : '$label · ${entries.length} 种基因型 · 共 $total 个'
          '${lethal > 0 ? ' · 致死 $lethal 种已剔除' : ''}';
}

/// 已展开世代 → 每代一块完整配比（份数降序，同份数按基因型字母序）。
List<GenotypeShareGroup> genotypeShareGroups(
    PedigreeGraphEngine engine, List<PedigreeNode> expandedNodes) {
  final byKey = <String, List<PedigreeNode>>{};
  for (final n in expandedNodes) {
    byKey.putIfAbsent('${n.familyId}:${n.generation}', () => []).add(n);
  }
  int partOf(String k) => int.tryParse(k.split(':').first) ?? 0;
  int genOf(String k) => int.tryParse(k.split(':').last) ?? 0;
  final keys = byKey.keys.toList()
    ..sort((a, b) => partOf(a) != partOf(b)
        ? partOf(a) - partOf(b)
        : genOf(a) - genOf(b));
  return [for (final k in keys) _shareGroupOf(engine, byKey[k]!)];
}

GenotypeShareGroup _shareGroupOf(
    PedigreeGraphEngine engine, List<PedigreeNode> nodes) {
  // 致死节点必须剔除：引擎给存活子代按「存活总和 = 1」归一化，而致死桶
  // 保留的是未归一化的原始概率（让用户看到「本应 X% 但都死了」）。两者混在
  // 一起既能凑出更大的 k，也会把整组比例拉歪（AA .25/Aa .5/aa 致死 .25 会凑成
  // 4:8:3 而不是正确的 1:2）。剔除后只报存活比例，致死数量在 header 注明。
  final alive = nodes.where((n) => !n.isLethal).toList();
  final lethal = nodes.length - alive.length;
  final pool = alive.isEmpty ? nodes : alive;
  pool.sort((a, b) {
    final p = b.probability.compareTo(a.probability);
    return p != 0 ? p : a.genotype.compareTo(b.genotype);
  });
  var counts = integerCountsOf([for (final n in pool) n.probability]);
  // 全 0 概率（引擎当前不会产出，纯防御）：退回百分比，别显示 "0/0"。
  if (counts != null && counts.every((c) => c == 0)) counts = null;
  final total = counts?.fold<int>(0, (s, c) => s + c);
  final gen = pool.first.generation;
  final genLabel = gen == 0 ? 'P' : 'F$gen';
  return GenotypeShareGroup(
    label: engine.familyIds.length > 1
        ? '$genLabel · ${engine.familyLabel(pool.first.familyId)}'
        : genLabel,
    entries: [
      for (var i = 0; i < pool.length; i++)
        GenotypeShare(
          pool[i].genotype,
          counts == null
              ? '${(pool[i].probability * 100).toStringAsFixed(1)}%'
              : '${counts[i]}/$total',
        ),
    ],
    total: total,
    lethal: lethal,
  );
}

/// 已展开世代的完整基因型配比面板。
///
/// 每代一块：标题行给「多少种 / 共多少份」，条目是紧凑 Wrap
/// （`AaBBCC 8/64`）——27 个基因型也只占 3–4 行，超出详情条高度时由
/// 外层 SingleChildScrollView 滚动。
class _ExpandedSharePanel extends StatelessWidget {
  const _ExpandedSharePanel({required this.groups});

  final List<GenotypeShareGroup> groups;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final g in groups) ...[
          Text(g.header,
              style: AppText.caption
                  .copyWith(color: AppColors.ink, fontWeight: FontWeight.w700)),
          const SizedBox(height: 2),
          Wrap(
            spacing: 12,
            runSpacing: 2,
            children: [
              for (final e in g.entries)
                Text('${e.genotype} ${e.share}', style: AppText.monoSmall),
            ],
          ),
          const SizedBox(height: 6),
        ],
      ],
    );
  }
}

class PedigreeDetailStrip extends StatelessWidget {
  const PedigreeDetailStrip({
    super.key,
    required this.engine,
    required this.selectedId,
    this.expandedNodes = const [],
    required this.connectedLabels,
    required this.editableGenotype,
    required this.onEditGenotype,
    required this.onImportToCross,
    required this.onWireDetach,
    required this.onDeleteSelected,
  });

  final PedigreeGraphEngine engine;
  final String? selectedId;

  /// 当前处于「展开」状态的世代节点（页面按 _expandedKeys 过滤后传入）。
  /// 多世代同时展开 → 详情条逐代一块完整基因型配比。
  final List<PedigreeNode> expandedNodes;

  /// 相连元素的展示标签列表（基因型（世代）♂/♀），由页面计算传入。
  final List<String> Function(String tapId) connectedLabels;
  final bool Function(PedigreeNode node) editableGenotype;
  final void Function(PedigreeNode node) onEditGenotype;
  final void Function(String genotype) onImportToCross;
  final void Function(PedigreeNode node) onWireDetach;
  final VoidCallback onDeleteSelected;

  @override
  Widget build(BuildContext context) {
    PedigreeNode? sel;
    String? halfNote;
    if (selectedId != null) {
      final (baseId, half) = parseTapId(selectedId!);
      for (final n in engine.nodes) {
        if (n.id == baseId) {
          sel = n;
          break;
        }
      }
      // R15 组合桶半边：已懒分裂则显示真实半边节点；未分裂显示父桶
      // 并标注所选性别半边（查看不触发分裂）。
      if (sel != null && half != null) {
        final h = engine.halfNode(sel.id, half);
        if (h != null) sel = h;
        halfNote =
            half == PedigreeNodeKind.male ? '雄性半边 □' : '雌性半边 ○';
      }
    }
    // 已展开世代的完整配比：与选中态解耦（展开不选任何节点也要看得到）
    final shares = genotypeShareGroups(engine, expandedNodes);
    // P0-1：未选中节点也直接给出最新一代表型比——点节点只是看单个基因型
    // 的细节，不该是拿到答案的前提。
    final ratios = latestPhenotypeRatios(engine);
    return Container(
      width: double.infinity,
      // v2.2：宽屏两列布局后内容一屏装下；上限放宽到 156（窄屏内容
      // 稍高），SingleChildScrollView 兜底防极端多相连元素溢出。
      constraints: const BoxConstraints(maxHeight: 156),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.border, width: 1)),
      ),
      padding: const EdgeInsets.all(14),
      child: sel == null
          ? (shares.isEmpty && ratios.isEmpty
              ? Center(
                  child: Text('点击任意节点查看完整信息（基因型 / 概率 / 性别 / 伴性标注）',
                      style: AppText.caption),
                )
              : SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (final r in ratios) ...[
                        _PhenotypeRatioPanel(groups: r.$2, label: r.$1),
                        const SizedBox(height: 4),
                      ],
                      // 兜底：组不出表型（如整代都是致死桶）时不留空白。
                      if (ratios.isEmpty)
                        Text('本代暂无可统计的表型比', style: AppText.caption),
                      if (shares.isNotEmpty) _ExpandedSharePanel(groups: shares),
                    ],
                  )))
          : SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildNodeInfo(context, sel, halfNote: halfNote),
                  if (shares.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    _ExpandedSharePanel(groups: shares),
                  ],
                ],
              ),
            ),
    );
  }

  /// 选中节点信息行主拼装（halfNote：组合桶半边标注，R15）。
  /// 拆为 header / genotype / info grid / content row 4 个子助手。
  Widget _buildNodeInfo(BuildContext context, PedigreeNode n,
      {String? halfNote}) {
    final genLabel = n.generation == 0 ? 'P' : 'F${n.generation}';
    final matingCount = engine.matingCountOf(n.id);
    // 伴性标注：列出有表型标签的伴性位点（X=病 等）
    final cfg = engine.sexLinked;
    final sexNotes = <String>[];
    if (cfg != null && !cfg.isEmpty) {
      for (final s in cfg.annotate(n.genotype)) {
        if (s.isSexLinked && (s.label?.isNotEmpty ?? false)) {
          sexNotes.add('${s.allele}=${s.label}');
        }
      }
    }
    final narrow = MediaQuery.sizeOf(context).width < 600;
    final editable = editableGenotype(n);
    // 表型与本代配比：同 familyId + 同 generation，排除外来样本与致死桶
    // （与未选中时的最新一代摘要同一口径，避免选中/不选中看到两个比例）。
    final phenotype = phenotypeLabelOf(n.genotype);
    final groups = phenotypeGroupsOf(engine, n.familyId, n.generation);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildHeaderRow(
            context, n, genLabel, halfNote, narrow),
        const SizedBox(height: 8),
        _buildContentRow(
          context,
          narrow,
          _buildGenotypeBlock(n, editable),
          _buildInfoItems(n, matingCount, sexNotes, phenotype),
        ),
        const SizedBox(height: 4),
        _PhenotypeRatioPanel(groups: groups),
      ],
    );
  }

  /// 标题行：AppChip(genLabel) + 可选 halfNote + id + 3 个按钮
  /// （导入 9331 / 取消连线 / 删除），narrow/!narrow 分支切换图标 vs 文字。
  Widget _buildHeaderRow(
    BuildContext context,
    PedigreeNode n,
    String genLabel,
    String? halfNote,
    bool narrow,
  ) {
    // P1-B 修复：标题行原 Row 在 1000×800 viewport 下溢出 282 像素
    // （3 个按钮 + chip + 长 id 文本挤一行）；改 Wrap 允许换行。
    // 三个按钮（导入 9331 / 取消连线 / 删除）保留 narrow/!narrow 分支，
    // 测试依赖其 Text 文案，wrap 包裹后仍能 find.text() 找到。
    return Wrap(
      spacing: 6,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        AppChip(genLabel),
        if (halfNote != null) AppChip(halfNote),
        // id 文本限宽 + ellipsis，避免与按钮争夺单行空间
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 220),
          child: Text(n.id,
              style: AppText.sectionTitle,
              overflow: TextOverflow.ellipsis),
        ),
        // v3.5：删除键移到标题行（与 F1 雄性半边 并列）；
        // v2.2：「取消连线」也进标题行（长按收线隐蔽难用，
        // 用户实测反馈）——常开可点，无连线时点击给 toast 引导。
        // 窄屏压缩为图标按钮防溢出。
        if (narrow)
          IconButton(
            tooltip: '导入 9331',
            onPressed: () => onImportToCross(n.genotype),
            icon: Icon(Icons.input_rounded,
                size: 18, color: AppColors.teal),
          )
        else
          OutlinedButton.icon(
            onPressed: () => onImportToCross(n.genotype),
            icon: const Icon(Icons.input_rounded, size: 15),
            label: const Text('导入 9331'),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.teal,
              side: BorderSide(color: AppColors.teal),
              padding: const EdgeInsets.symmetric(horizontal: 10),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),
        if (narrow)
          IconButton(
            tooltip: '取消连线（收回该元素最近一条连线）',
            onPressed: () => onWireDetach(n),
            icon: Icon(Icons.link_off, size: 18, color: AppColors.sand),
          )
        else
          OutlinedButton.icon(
            onPressed: () => onWireDetach(n),
            icon: const Icon(Icons.link_off, size: 15),
            label: const Text('取消连线'),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.sand,
              side: BorderSide(color: AppColors.sand),
              padding: const EdgeInsets.symmetric(horizontal: 10),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),
        if (narrow)
          IconButton(
            tooltip: '删除',
            onPressed: onDeleteSelected,
            icon: Icon(Icons.delete_outline,
                size: 18, color: AppColors.lethal),
          )
        else
          OutlinedButton.icon(
            onPressed: onDeleteSelected,
            icon: const Icon(Icons.delete_outline, size: 15),
            label: const Text('删除'),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.lethal,
              side: BorderSide(color: AppColors.lethal),
              padding: const EdgeInsets.symmetric(horizontal: 10),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),
      ],
    );
  }

  /// 基因型大字显示 + 编辑（铅笔/点击整块，绑定区域大；
  /// 子代只读，外来样本与 P 代双亲可编辑）
  Widget _buildGenotypeBlock(PedigreeNode n, bool editable) {
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: editable ? () => onEditGenotype(n) : null,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: editable ? AppColors.tealWash : AppColors.surfaceLow,
          borderRadius: BorderRadius.circular(10),
          border:
              Border.all(color: editable ? AppColors.teal : AppColors.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // P1-B 修复：内部 Row 在外层 Flexible 压窄时溢出 133 像素。
            // 给 Text 加 Flexible 包裹，基因型过长时 ellipsis 截断，
            // 短基因型（"AaBbCc" 6 字符）不被压缩。致死/锁/只读标
            // 识保持自然宽，可读性优先。
            Flexible(
              child: Text(n.genotype,
                  style: AppText.monoFigure,
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1),
            ),
            // v2.1i：致死子代在基因型后追加「（纯合致死）」红字
            if (n.isLethal) ...[
              const SizedBox(width: 8),
              Text('（纯合致死）',
                  style: AppText.monoFigure.copyWith(
                      fontSize: 14,
                      color: AppColors.lethal,
                      fontWeight: FontWeight.w800)),
            ],
            const SizedBox(width: 12),
            if (editable) ...[
              Icon(Icons.edit_outlined, size: 19, color: AppColors.teal),
              const SizedBox(width: 5),
              // P1-B 修复：editable 分支下"编辑" Text 也需 Flexible 包裹。
              // P-father 节点（editable=true）选中也走这里，没 Flexible
              // 会让内部 Row 在窄 viewport 下溢出 3.5 像素（与"只读"对称
              // 处理——任一标识被压缩都不影响主功能）。
              Flexible(
                child: Text('编辑',
                    style: AppText.caption.copyWith(
                        color: AppColors.teal, fontWeight: FontWeight.w700),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1),
              ),
            ] else ...[
              Icon(Icons.lock_outline, size: 16, color: AppColors.steel),
              const SizedBox(width: 5),
              // P1-B 修复：内部 Row 在窄 viewport 下仍溢出 3.5 像素。
              // "计算产出 · 只读" 也加 Flexible 包裹，让"只读"标
              // 识在容器压窄时 ellipsis 截断（"计算产出"被截后剩
              // "· 只读"仍可识别语义）。
              Flexible(
                child: Text('计算产出 · 只读',
                    style: AppText.caption.copyWith(color: AppColors.steel),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// 信息项网格（概率/性别/世代/家族/连线/相连元素/来源 等）。
  Widget _buildInfoItems(
      PedigreeNode n, int matingCount, List<String> sexNotes,
      String phenotype) {
    final kindLabel = n.kind == PedigreeNodeKind.male
        ? 'X（矩形）'
        : n.kind == PedigreeNodeKind.female
            ? 'Y（圆）'
            : '群体桶';
    final genLabel = n.generation == 0 ? 'P' : 'F${n.generation}';
    final items = <Widget>[
      _infoItem(
          '概率',
          n.isExternal
              ? '外来样本'
              : '${(n.probability * 100).toStringAsFixed(2)}%'),
      _infoItem('表型', phenotype),
      _infoItem('性别', kindLabel),
      _infoItem('世代', genLabel),
      if (engine.familyIds.length > 1)
        _infoItem('家族', engine.familyLabel(n.familyId)),
      if (n.maleFraction != null)
        _infoItem('雌雄比',
            '○X ${(n.maleFraction! * 100).round()}% : ●Y ${(100 - (n.maleFraction! * 100).round())}%'),
      if (sexNotes.isNotEmpty) _infoItem('伴性', sexNotes.join(' · ')),
      if (n.genotype.contains('-'))
        _infoItem('标注', '基因缺失（「-」为缺失位点，单亲遗传）'),
      _infoItem('连线', '$matingCount 条'),
      // R23：与选中元素相连的元素列表（与上方各信息项并列展示）
      if (selectedId != null && connectedLabels(selectedId!).isNotEmpty)
        _infoItem('相连元素', connectedLabels(selectedId!).join('、')),
      _infoItem('来源', n.isExternal ? '外来样本（可右键编辑）' : '计算产出'),
    ];
    return Wrap(spacing: 18, runSpacing: 6, children: items);
  }

  /// 内容行布局：宽屏左右两列（基因型块 + 信息项网格），窄屏上下结构。
  /// 窄屏时无外层 Row 包裹，避免水平溢出。
  Widget _buildContentRow(
    BuildContext context,
    bool narrow,
    Widget genotypeBlock,
    Widget itemGrid,
  ) {
    if (narrow) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          genotypeBlock,
          const SizedBox(height: 6),
          itemGrid,
        ],
      );
    }
    // P1-B 修复：内容行原 Row 在 1000×800 viewport 下溢出 128 像素
    // （长基因型 + 多信息项挤一行）。genotypeBlock 内部子 Row 自然
    // 宽 ~272 像素 < Row 总宽（1000 viewport），原代码靠 Expanded 推
    // itemGrid 填右空白，但外 Row 总宽足够时不溢出（只在基因型极长
    // 时溢出）。此处不变更外 Row 主体，仅保留原 layout。
    // P1-B 修复：内容行原 Row 在窄 viewport（800×800 测）/宽屏
    // 长基因型下溢出（实测溢出 46 像素）。genotypeBlock 加
    // Flexible(fit: loose) + ConstrainedBox(maxWidth: 460) 包裹：
    // 内部 Row 自然宽 ~277 像素（monoFigure 22px + 锁/只读标识）
    // < 460 = 不被压窄；外 Row 总宽不够时分给 genotypeBlock 的
    // 约束到 460 封顶（实测 380/420 仍差 3.5 像素溢出——
    // 内 Row 用 mainAxisSize.min 自然宽有 padding/font metric
    // 微小差，460 留足 buffer 彻底解决）。
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Flexible(
          fit: FlexFit.loose,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: genotypeBlock,
          ),
        ),
        const SizedBox(width: 18),
        // 信息项网格填入右侧空白区（概率/性别/世代/家族/连线…）
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: 2),
            child: itemGrid,
          ),
        ),
      ],
    );
  }

  Widget _infoItem(String label, String value, {bool mono = false}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('$label ', style: AppText.caption),
        Flexible(
          child: Text(value,
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
              style: (mono ? AppText.monoSmall : AppText.caption).copyWith(
                  color: AppColors.ink, fontWeight: FontWeight.w600)),
        ),
      ],
    );
  }
}

/// 本代配比条 + 可展开的每组基因型列表（收起 1 行，Wrap 防溢出）。
class _PhenotypeRatioPanel extends StatefulWidget {
  const _PhenotypeRatioPanel({required this.groups, this.label = '本代配比'});

  final List<PhenotypeGroup> groups;

  /// 行首标签；多家族时详情条按家族各给一份（'家族A 本代配比'）。
  final String label;

  @override
  State<_PhenotypeRatioPanel> createState() => _PhenotypeRatioPanelState();
}

class _PhenotypeRatioPanelState extends State<_PhenotypeRatioPanel> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    if (widget.groups.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 6,
          runSpacing: 2,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(widget.label, style: AppText.caption),
            Text(phenotypeRatioText(widget.groups),
                style: AppText.caption
                    .copyWith(color: AppColors.ink, fontWeight: FontWeight.w600)),
            InkWell(
              borderRadius: BorderRadius.circular(6),
              onTap: () => setState(() => _expanded = !_expanded),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(_expanded ? Icons.expand_less : Icons.expand_more,
                      size: 16, color: AppColors.teal),
                  Text(_expanded ? '收起' : '展开基因型',
                      style: AppText.caption
                          .copyWith(color: AppColors.teal)),
                ],
              ),
            ),
          ],
        ),
        if (_expanded)
          Padding(
            padding: const EdgeInsets.only(top: 2, left: 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var i = 0; i < widget.groups.length; i++)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 2),
                    child: Wrap(
                      spacing: 6,
                      runSpacing: 2,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                            '${widget.groups[i].label} ${phenotypeRatioValues(widget.groups)[i]}',
                            style: AppText.caption.copyWith(
                                color: AppColors.ink,
                                fontWeight: FontWeight.w600)),
                        Text(widget.groups[i].genotypes.join('、'),
                            style: AppText.monoSmall),
                      ],
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}
