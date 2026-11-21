// method_compare_tab.dart —— 分解法 vs 配子法 对比 Tab（遗传计算器第 4 页）
//
// 教学核心：同一组亲本并排跑两种解法，结果必然一致，
// 但配子法格子数随位点指数爆炸（4^n），分解法只需 n 步单位点计算。
// 让学生直观理解「为什么多对基因要拆开算」。
//
// 2.2 UI 重做：步骤流程卡结构（①设定亲本 → ②两法并排结果）。

import 'dart:convert';

import 'package:flutter/material.dart';

import '../../engine/method_compare.dart';
import '../../state/app_state.dart';
import '../../state/history_store.dart';
import '../../theme.dart';
import '../../ui/png_export.dart';
import '../../ui/step_card.dart';
import 'cross_tool_rail.dart';

class MethodCompareTab extends StatefulWidget {
  const MethodCompareTab({super.key});

  /// v2.15：fill 先于本 tab 挂载到达时的待填槽（页级 _flushFill 设置，
  /// initState 消费）——讲题回放 ▷ 复现的懒构建兜底。
  static ({String p1, String p2})? pendingFill;

  @override
  State<MethodCompareTab> createState() => MethodCompareTabState();
}

/// State 公开（v2.15）：遗传计算器页用 GlobalKey 直达 fillFromAi。
class MethodCompareTabState extends State<MethodCompareTab>
    with AutomaticKeepAliveClientMixin
    implements CrossTabSidePanel {
  /// 出厂默认题（判 `isPristine` 的锚点）。⛔ controller 初始化复用它。
  static const _kDefaultP1 = 'AaBb';
  static const _kDefaultP2 = 'AaBb';

  final _p1Ctrl = TextEditingController(text: _kDefaultP1);
  final _p2Ctrl = TextEditingController(text: _kDefaultP2);

  /// 这一栏现在**还是出厂状态吗**（没人动过）？
  ///
  /// 供 `ModuleFillTarget.canOverwrite` 用：学生在这一栏敲过题之后，再从
  /// 课标/拍题深链进来，**不该把他那道题无声顶掉**。判据 = 两个亲本输入框
  /// 都还等于出厂默认值——本页签只有这两个输入框，且 `fillFromAi` 恰好就写
  /// 它们。⛔ 不用 initState 快照。
  bool get isPristine =>
      _p1Ctrl.text == _kDefaultP1 && _p2Ctrl.text == _kDefaultP2;

  MethodComparison? _result;
  String? _error;
  // v2.13：数值结果截图边界与导出态（与 mono 样板同模式）。
  final _resultKey = GlobalKey();
  bool _exporting = false;

  @override
  void initState() {
    super.initState();
    final pf = MethodCompareTab.pendingFill;
    if (pf != null) {
      MethodCompareTab.pendingFill = null;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) fillFromAi(pf.p1, pf.p2);
      });
    }
  }

  /// v2.15：拍题识别/讲题回放回填——填亲本 + 跑两种算法对比。
  void fillFromAi(String p1, String p2) {
    _p1Ctrl.text = p1;
    _p2Ctrl.text = p2;
    _compute();
  }

  /// 数值结果存为 PNG（学生发群问老师路径）。
  Future<void> _exportResult() async {
    setState(() => _exporting = true);
    final r = await captureBoundaryPng(_resultKey, '方法对比');
    if (!mounted) return;
    setState(() => _exporting = false);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(r.path != null ? '已保存：${r.path}' : r.error ?? '导出失败'),
      duration: const Duration(seconds: 4),
    ));
  }

  @override
  bool get wantKeepAlive => true;

  @override
  void dispose() {
    _p1Ctrl.dispose();
    _p2Ctrl.dispose();
    super.dispose();
  }

  void _compute() {
    try {
      final r = compareMethods(_p1Ctrl.text, _p2Ctrl.text);
      setState(() {
        _result = r;
        _error = null;
      });
      AppState.instance.report('方法对比', '${r.p1} × ${r.p2}');
      AppState.instance.report('配子法', '${r.cellCount} 格方阵');
      AppState.instance.report('分解法', '${r.decomposeSteps} 步单位点');
      AppState.instance.report('表型比', r.integerRatio.join(':'));
      // v2.14 R5 讲题回放补齐：方法对比落盘。v2.15：detail 带结构化
      // 参数——回放卡 ▷ 点按可复现（跳本 tab 回填 + 即算）。
      HistoryStore.append(HistoryEntry(
        label: '${r.p1} × ${r.p2} · 方法对比 · 表型 ${r.integerRatio.join(':')}',
        epochMs: DateTime.now().millisecondsSinceEpoch,
        detail: jsonEncode({'m': 'cross_method_compare', 'p1': r.p1, 'p2': r.p2}),
      ));
    } on ArgumentError catch (e) {
      setState(() {
        _result = null;
        _error = e.message?.toString() ?? '输入格式错误';
      });
    }
  }

  /// v2.19.18 去主体化：输入面板（无壳，含说明行）——宽屏注入 rail
  /// 顶部，窄屏自渲染。
  @override
  Widget buildSidePanel(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const AppChip('方法论对比', icon: Icons.compare_outlined),
            const SizedBox(width: 8),
            Expanded(
              child: Text('同一道题，两种算法，结果必然一致',
                  style: AppText.caption),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Text('设定亲本基因型', style: AppText.sectionTitle),
        const SizedBox(height: 4),
        Text('两对及以上基因（如 AaBb），同一组亲本用两种算法解',
            style: AppText.caption.copyWith(color: AppColors.steel)),
        const SizedBox(height: 12),
        _buildInputArea(),
      ],
    );
  }

  /// v2.19.18：第 1 步输入区（原 StepCard 1 child，去壳抽出共用）。
  Widget _buildInputArea() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _p1Ctrl,
                style: AppText.genotype,
                decoration: const InputDecoration(
                  labelText: '亲本 1',
                  hintText: '如 AaBb',
                ),
                onSubmitted: (_) => _compute(),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Icon(Icons.close, size: 18, color: AppColors.steel),
            ),
            Expanded(
              child: TextField(
                controller: _p2Ctrl,
                style: AppText.genotype,
                decoration: const InputDecoration(
                  labelText: '亲本 2',
                  hintText: '如 AaBb',
                ),
                onSubmitted: (_) => _compute(),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        FilledButton.icon(
          onPressed: _compute,
          icon: const Icon(Icons.play_arrow),
          label: const Text('开始对比'),
        ),
        // v2.19.23 找茬 P1#2：错误不再放这里（宽屏时本面板注入 rail，
        // tab 内部 setState 不重建 rail 副本 → 错误永不显示）。错误
        // 展示统一移到下方结果区（body 恒渲染）。
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final wide = MediaQuery.of(context).size.width >= 1200;
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
      children: [
        if (!wide) buildSidePanel(context),
        if (!wide) const SizedBox(height: 28),

        // 第 2 步：两法并排结果（v2.19.18 去壳平铺）
        FlatSection(
          title: '两种方法并排跑',
          subtitle: _result == null
              ? '设定亲本后点「开始对比」，这里并排展示两种解法'
              : null,
          trailing: _result == null
              ? null
              : Text('${_result!.lociCount} 对位点', style: AppText.caption),
          // v2.19.23 找茬 P1#2：错误优先展示在结果区——宽屏左栏面板
          // 不随 tab 内部 setState 重建，错误放输入区会「点了没反应」。
          child: _error != null
              ? Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(_error!,
                      style: AppText.caption.copyWith(color: AppColors.lethal)),
                )
              : _result == null
              ? Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Center(
                    child: Text('等待对比：结果将在这里展开',
                        style: AppText.body.copyWith(color: AppColors.steel)),
                  ),
                )
              : Column(
                  // v2.13：两法并排 + 一致性横幅 整体挂 RepaintBoundary，
                  // 内部子面板 _SubPanel/横幅已自带装饰，不再叠 canvas 底。
                  children: [
                    RepaintBoundary(
                      key: _resultKey,
                      child: Column(
                        children: [
                          LayoutBuilder(
                            builder: (ctx, c) {
                              final wide = c.maxWidth >= 640;
                              final left = _GameteMethodPanel(result: _result!);
                              final right =
                                  _DecomposeMethodPanel(result: _result!);
                              if (wide) {
                                return Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Expanded(child: left),
                                    const SizedBox(width: 12),
                                    Expanded(child: right),
                                  ],
                                );
                              }
                              return Column(children: [left, right]);
                            },
                          ),
                          const SizedBox(height: 12),
                          _AgreementBanner(result: _result!),
                        ],
                      ),
                    ),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton.icon(
                        onPressed: _exporting ? null : _exportResult,
                        icon: const Icon(Icons.image_outlined, size: 18),
                        label: Text(_exporting ? '导出中…' : '存为图片'),
                      ),
                    ),
                  ],
                ),
        ),
      ],
    );
  }
}

/// 结果卡内子区通用外壳（canvas 底 + 细边，避免卡中卡）。
class _SubPanel extends StatelessWidget {
  const _SubPanel({required this.title, required this.badge, required this.subtitle, required this.child});

  final String title;
  final String badge;
  final String subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: AppColors.canvas,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border.withValues(alpha: 0.6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(title, style: AppText.label),
              const Spacer(),
              AppChip(badge),
            ],
          ),
          const SizedBox(height: 4),
          Text(subtitle, style: AppText.caption),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

/// 配子法（Punnett 方阵）子区。
class _GameteMethodPanel extends StatelessWidget {
  final MethodComparison result;
  const _GameteMethodPanel({required this.result});

  @override
  Widget build(BuildContext context) {
    final showGrid = result.cellCount <= 16; // 2 对位点内才展开方阵
    return _SubPanel(
      title: '配子法',
      badge: '${result.cellCount} 格',
      subtitle: '列出全部配子，两两组合填方阵',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('亲本 1 配子', style: AppText.caption),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final g in result.gametesP1) _gameteChip(g),
            ],
          ),
          const SizedBox(height: 10),
          Text('亲本 2 配子', style: AppText.caption),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final g in result.gametesP2) _gameteChip(g),
            ],
          ),
          const SizedBox(height: 12),
          if (showGrid)
            _PunnettGrid(result: result)
          else
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.border),
              ),
              child: Text(
                '${result.gametesP1.length} × ${result.gametesP2.length} = '
                '${result.cellCount} 个格子（位点增多后表格爆炸，此处仅计数）',
                style: AppText.caption,
              ),
            ),
        ],
      ),
    );
  }

  Widget _gameteChip(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.tealWash,
        borderRadius: BorderRadius.circular(7),
      ),
      child: Text(label, style: AppText.monoSmall.copyWith(fontSize: 12)),
    );
  }
}

class _PunnettGrid extends StatelessWidget {
  final MethodComparison result;
  const _PunnettGrid({required this.result});

  @override
  Widget build(BuildContext context) {
    final g1 = result.gametesP1;
    final g2 = result.gametesP2;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Table(
        defaultColumnWidth: const IntrinsicColumnWidth(),
        border: TableBorder.all(color: AppColors.border, width: 0.8),
        children: [
          // 表头行：亲本2 配子
          TableRow(
            decoration: BoxDecoration(color: AppColors.tealWash),
            children: [
              _cell(''),
              for (final b in g2) _cell(b, header: true),
            ],
          ),
          for (var i = 0; i < g1.length; i++)
            TableRow(
              children: [
                _cell(g1[i], header: true),
                for (var j = 0; j < g2.length; j++)
                  _cell(result.punnett[i][j]),
              ],
            ),
        ],
      ),
    );
  }

  Widget _cell(String text, {bool header = false}) {
    return Container(
      color: header ? AppColors.tealWash : null,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      alignment: Alignment.center,
      child: Text(
        text,
        style: AppText.monoSmall.copyWith(
          fontSize: 11,
          fontWeight: header ? FontWeight.w700 : FontWeight.w400,
          color: header ? AppColors.tealDark : AppColors.ink,
        ),
      ),
    );
  }
}

/// 分解法（逐位点拆分再相乘）子区。
class _DecomposeMethodPanel extends StatelessWidget {
  final MethodComparison result;
  const _DecomposeMethodPanel({required this.result});

  @override
  Widget build(BuildContext context) {
    return _SubPanel(
      title: '分解法',
      badge: '${result.decomposeSteps} 步',
      subtitle: '每对基因单独算分离比，再逐位点相乘',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < result.loci.length; i++) ...[
            if (i > 0)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Icon(Icons.close, size: 14, color: AppColors.sand),
              ),
            _LocusRow(breakdown: result.loci[i]),
          ],
          Divider(height: 24, color: AppColors.border.withValues(alpha: 0.6)),
          Row(
            children: [
              Icon(Icons.south, size: 16, color: AppColors.teal),
              const SizedBox(width: 6),
              Text('各位点相乘合并', style: AppText.label),
            ],
          ),
          const SizedBox(height: 8),
          for (final e in result.phenotypeDist.entries)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                children: [
                  Expanded(child: Text(e.key, style: AppText.body)),
                  RatioPill(text: '${e.value}'),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _LocusRow extends StatelessWidget {
  final LocusBreakdown breakdown;
  const _LocusRow({required this.breakdown});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(breakdown.crossLabel, style: AppText.genotype),
          const SizedBox(height: 6),
          Row(
            children: [
              Text('表型比', style: AppText.caption),
              const SizedBox(width: 8),
              Text(
                breakdown.integerRatio.join(':'),
                style: AppText.monoFigure.copyWith(fontSize: 17),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 底部一致性横幅：两法殊途同归 + 效率对比。
class _AgreementBanner extends StatelessWidget {
  final MethodComparison result;
  const _AgreementBanner({required this.result});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: AppColors.tealWash,
        borderRadius: BorderRadius.circular(AppTheme.radiusCard),
        border: Border.all(color: AppColors.border),
      ),
      padding: const EdgeInsets.all(18),
      child: Column(
        children: [
          Text('两法结果一致', style: AppText.label),
          const SizedBox(height: 6),
          Text(
            result.integerRatio.join(' : '),
            style: AppText.monoFigure.copyWith(fontSize: 28),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 10),
          Text(
            '配子法填了 ${result.cellCount} 格，分解法只算 '
            '${result.decomposeSteps} 步——位点越多，分解法优势越大',
            style: AppText.caption,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
