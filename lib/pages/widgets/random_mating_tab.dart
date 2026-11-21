// random_mating_tab.dart —— 自由交配 Tab（遗传计算器第 6 页）
//
// 群体自由交配：输入群体基因型构成（如 1/3 AA + 2/3 Aa），
// 配子库法（Hardy-Weinberg）与枚举法同时展开，逐代推演。
// 教学要点：
//   - 自由交配 ≠ 自交：平衡群体杂合子不逐代减半
//   - 致死选择必须「统一淘汰」，逐组合归一化是经典错误
// 视觉遵循 docs/ARCHITECTURE.md 的设计约定：基因型/比例/概率一律等宽字体，结果区用 border-top 分隔。

import 'package:flutter/material.dart';

import '../../engine/fraction.dart';
import '../../engine/genetics_env.dart';
import '../../engine/random_mating_engine.dart';
import '../../state/app_state.dart';
import '../../state/history_store.dart';
import '../../theme.dart';
import '../../ui/png_export.dart';
import '../../ui/step_card.dart';
import 'cross_tool_rail.dart';
import '../../charts/frequency_curve_chart.dart'; // v2.19.41 逐代频率折线图（组件沿用进化页）

/// 一行群体输入：基因型 + 频率（支持 1/3、33.3%、0.333、整数份数 2）。
class _PopRow {
  final TextEditingController gen;
  final TextEditingController freq;
  _PopRow(String g, String f)
      : gen = TextEditingController(text: g),
        freq = TextEditingController(text: f);
  void dispose() {
    gen.dispose();
    freq.dispose();
  }
}

class RandomMatingTab extends StatefulWidget {
  const RandomMatingTab({super.key, this.cardHint});

  /// v2.19.59：结果区副标题尾注（「 · 按 K 看这道题的套路卡」）。
  /// ⛔ 由容器页算好传进来（判据与 K 宿主同源），本组件不认识套路卡库；
  /// null = 这一面没有配套卡 ⇒ 原句逐字不变。
  final String? cardHint;

  @override
  State<RandomMatingTab> createState() => RandomMatingTabState();
}

class RandomMatingTabState extends State<RandomMatingTab>
    with AutomaticKeepAliveClientMixin
    implements CrossTabSidePanel {
  /// v2.19.39：跨页深链的**待填槽**（静态，随 tab 存活跨实例）。
  ///
  /// `TabBarView` 懒构建：深链触发时当前多半停在别的页签，本 tab 尚未挂载
  /// ⇒ 容器页（`cross_calculator_page.dart` 的 `_flushFill(6)`）拿不到
  /// State，参数落在这里，由本 State 的 [initState] 消费——与其余 6 个
  /// 页签的 `pendingFill`（`MonoCrossWidget.pendingFill` /
  /// `MethodCompareTab.pendingFill` / …）同一套双通道兜底。
  /// ⛔ 消费后立刻置 null（幽灵参数会被下一个挂载的实例无声吃掉）；
  /// 测试也必须在 setUp/tearDown 清（跨用例污染）。
  static Map<String, String>? pendingRm;

  /// v2.19.39：出厂默认行（[isPristine] 的判据锚点）。⛔ `_rows` 的初始行
  /// **复用**它，不另抄一份字面量（影子分叉 ⇒ 闸永远说「不是出厂」）。
  static const _kDefaultGen = 'Aa';
  static const _kDefaultFreq = '1';

  final List<_PopRow> _rows = [_PopRow(_kDefaultGen, _kDefaultFreq)];
  String _lethal = '无'; // 无 / 隐性纯合致死 / 显性纯合致死
  int _generations = 1;

  /// 这一栏现在**还是出厂状态吗**（没人动过）？
  ///
  /// 供 `ModuleFillTarget.canOverwrite` 用（注册点 `cross_random_mating`
  /// 在 `cross_calculator_page.dart`）：学生在自由交配里敲过题之后，再从
  /// 课标/拍题深链进来，**不该把他那道题无声顶掉**（与 mono/伴性/方法对比/
  /// 连锁四页签同款规矩）。判据 = 行数与那一行都还等于出厂默认。⛔ **不用
  /// initState 快照**：keep-alive 存活的 State 与重建过的 State 会各拿一份。
  ///
  /// ⚠️ 只比 `_rows`：本轮深链口径**只有 `rows` 一个键**（[applyFillParams]
  /// 也只写 `_rows`），致死/代数下拉不在载荷里 ⇒ 学生改了下拉框不构成
  /// 「他自己那道题被顶掉」，不该因此把深链拦在门外。
  bool get isPristine =>
      _rows.length == 1 &&
      _rows[0].gen.text == _kDefaultGen &&
      _rows[0].freq.text == _kDefaultFreq;

  /// v2.19.23 找茬 P0#1：面板结构修订号。宽屏时输入面板注入容器左栏
  /// rail，rail 副本是容器构建时的快照——增删行/预设替换只 setState
  /// tab 内部，rail 不重建：显示旧行、输入写进已 dispose 的 controller。
  /// 结构变化时自增本通知器，容器以 ValueListenableBuilder 监听重建。
  final ValueNotifier<int> panelRevision = ValueNotifier<int>(0);

  @override
  void initState() {
    super.initState();
    // v2.19.39：消费容器页投来的待填槽（懒构建兜底通道，与其余 6 个页签
    // 同一套）。放在 initState 尾部：_rows / _lethal / _generations 均已就位，
    // 写入后由 `_applyPreset` 直接算出结果（兄弟页签 flush 后「即算」）。
    final pf = pendingRm;
    if (pf != null) {
      pendingRm = null;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) applyFillParams(pf);
      });
    }
  }

  @override
  void dispose() {
    panelRevision.dispose();
    for (final r in _rows) {
      r.dispose();
    }
    super.dispose();
  }

  List<RandomMatingResult>? _results;
  String? _error;
  // v2.13：数值结果截图边界与导出态（与 mono 样板同模式）。
  final _resultKey = GlobalKey();
  bool _exporting = false;

  /// 数值结果存为 PNG（学生发群问老师路径）。
  Future<void> _exportResult() async {
    setState(() => _exporting = true);
    final r = await captureBoundaryPng(_resultKey, '自由交配计算');
    if (!mounted) return;
    setState(() => _exporting = false);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(r.path != null ? '已保存：${r.path}' : r.error ?? '导出失败'),
      duration: const Duration(seconds: 4),
    ));
  }

  static const _lethalOptions = ['无', '隐性纯合致死', '显性纯合致死'];

  @override
  bool get wantKeepAlive => true;


  /// 解析频率：'1/3' / '33.3%' / '0.333' / '2'（整数份数）。
  static Fraction _parseFreq(String raw) {
    final s = raw.trim();
    if (s.isEmpty) throw ArgumentError('频率不能为空');
    if (s.endsWith('%')) {
      final v = double.tryParse(s.substring(0, s.length - 1));
      if (v == null) throw ArgumentError('频率格式错误：$raw');
      return Fraction.approx(v / 100);
    }
    if (s.contains('/')) {
      final parts = s.split('/');
      final n = int.tryParse(parts[0]);
      final d = parts.length > 1 ? int.tryParse(parts[1]) : null;
      if (n == null || d == null || d == 0) {
        throw ArgumentError('频率格式错误：$raw');
      }
      return Fraction(n, d);
    }
    final asInt = int.tryParse(s);
    if (asInt != null) return Fraction.of(asInt);
    final v = double.tryParse(s);
    if (v == null) throw ArgumentError('频率格式错误：$raw');
    return Fraction.approx(v);
  }

  GeneticsEnv _buildEnv(String firstGenotype) {
    final env = GeneticsEnv();
    if (_lethal == '无' || firstGenotype.isEmpty) return env;
    final dom = firstGenotype[0].toUpperCase();
    env.addLethalRule(_lethal == '隐性纯合致死'
        ? GeneticsEnv.lethalOnRecessiveHomozygous(dom)
        : GeneticsEnv.lethalOnDominantHomozygous(dom));
    return env;
  }

  void _compute() {
    try {
      final pop = <String, Fraction>{};
      var nonEmpty = 0;
      for (final row in _rows) {
        final g = row.gen.text.trim();
        if (g.isEmpty) continue;
        nonEmpty++;
        pop[g] = _parseFreq(row.freq.text);
      }
      if (nonEmpty == 0) {
        throw ArgumentError('请至少填写一行基因型');
      }
      final engine = RandomMatingEngine(env: _buildEnv(pop.keys.first));
      final results = engine.generations(pop, _generations);
      setState(() {
        _results = results;
        _error = null;
      });
      final first = results.first;
      AppState.instance.report(
          '自由交配',
          first.population.entries
              .map((e) => '${e.key}=${e.value}')
              .join('，'));
      AppState.instance.report(
          '子代基因型比', first.genotypeRatio.join(' : '));
      if (_lethal != '无') AppState.instance.report('选择压力', _lethal);
      // v2.14 R5 讲题回放补齐：自由交配落盘（label 回看）。
      HistoryStore.append(HistoryEntry(
        label: '自由交配（${first.population.length} 个基因型）· F1 基因型比 '
            '${first.genotypeRatio.join(':')}',
        epochMs: DateTime.now().millisecondsSinceEpoch,
        detail: '',
      ));
    } on ArgumentError catch (e) {
      setState(() {
        _results = null;
        _error = e.message?.toString() ?? '输入格式错误';
      });
    }
  }

  void _applyPreset(
      ({String name, List<(String, String)> rows, String lethal, int gens}) p) {
    for (final r in _rows) {
      r.dispose();
    }
    _rows
      ..clear()
      ..addAll(p.rows.map((e) => _PopRow(e.$1, e.$2)));
    panelRevision.value++; // v2.19.23 找茬 P0#1：驱动宽屏 rail 面板重建
    setState(() {
      _lethal = p.lethal;
      _generations = p.gens;
    });
    _compute();
  }

  /// v2.19.39：群体基因型行走串（`Aa=1;aa=1`）的解析——`;` 分段、`=` 分键。
  ///
  /// **本文件唯一的格式口径**：容器页 `_applyRandomMatingFill` 的准入闸与
  /// 本 State 的回填共用它（公开成 static 就是为了给闸复用；两处各解析一遍
  /// 日后必然漂移——闸放行而回填拒收，学生对着出厂题照抄）。
  ///
  /// 频率**只验非空**（`1/3` / `33.3%` / 整数份数 `2` 都合法），数值合法性交
  /// 引擎严判——与其余 6 个页签「引擎再严判」同一口径。
  ///
  /// 返回 null = 拒收（由调用方出口提示，不静默开算一份出厂题）：分段数 0 /
  /// 缺 `=` / 键值任一为空 / 基因型不过 `/^[A-Za-z]{2,8}$/`（`Aa`…`AaBb` 都
  /// 在内——本页签接受多基因型群体）。
  static List<(String, String)>? parseRowsParam(String raw) {
    final rows = <(String, String)>[];
    for (final seg in raw.split(';')) {
      final kv = seg.split('=');
      if (kv.length != 2) return null;
      final gen = kv[0].trim();
      final freq = kv[1].trim();
      if (gen.isEmpty || freq.isEmpty) return null;
      if (!_reGenotype.hasMatch(gen)) return null;
      rows.add((gen, freq));
    }
    if (rows.isEmpty) return null;
    return rows;
  }

  static final RegExp _reGenotype = RegExp(r'^[A-Za-z]{2,8}$');

  /// v2.19.39：拍题识别 / 课标深链的回填入口（`cross_random_mating` 的
  /// apply 最终落在这里）。
  ///
  /// 载荷只有 `rows`（`Aa=1;aa=1`）一个键 ⇒ 重建群体构成后**不动**致死/代数
  /// 两个下拉（学生自己设的选择压力不该被深链顺手重置），这也是
  /// [isPristine] 只比 `_rows` 的原因。返回是否真的消费了参数。
  bool applyFillParams(Map<String, String> params) {
    // ⛔ 不给默认值：空 params（深链没解析出群体构成）必须**拒收**，不能默默
    // 按出厂题开算一份与调用方意图无关的结果。
    final rows = parseRowsParam(params['rows'] ?? '');
    if (rows == null) return false;
    _applyPreset((
      name: '深链回填',
      rows: rows,
      lethal: _lethal, // ⛔ 本轮口径不含这两项 ⇒ 原样传回自己，不重置
      gens: _generations,
    ));
    return true;
  }

  void _addRow() {
    _rows.add(_PopRow('', '1'));
    panelRevision.value++;
    setState(() {});
  }

  void _removeRow(int i) {
    if (_rows.length <= 1) return;
    _rows.removeAt(i).dispose();
    panelRevision.value++;
    setState(() {});
  }

  /// v2.19.18 去主体化：输入面板（无壳，含页首说明）——宽屏注入 rail
  /// 顶部，窄屏自渲染。
  @override
  Widget buildSidePanel(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const AppChip('自由交配', icon: Icons.groups_outlined),
            const SizedBox(width: 8),
            Expanded(
              child: Text('群体随机结合：配子库法一步出结果，枚举法逐对展开',
                  style: AppText.caption),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Text('设定群体构成', style: AppText.sectionTitle),
        const SizedBox(height: 4),
        Text('基因型 + 频率（1/3、33.3%、整数份数 2），可加多行',
            style: AppText.caption.copyWith(color: AppColors.steel)),
        const SizedBox(height: 12),
        _buildInputArea(),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final wide = MediaQuery.of(context).size.width >= 1200;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
      // v2.19.18 去主体化：平铺铺满，内容直铺背景。
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1400),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (!wide) buildSidePanel(context),
              if (!wide) const SizedBox(height: 28),
              _buildResultSection(),
            ],
          ),
        ),
      ),
    );
  }

  /// v2.19.18 结果区（FlatSection 平铺，无 StepCard 壳）。
  Widget _buildResultSection() {
    final results = _results;
    return FlatSection(
      title: '子代结果',
      subtitle: results == null
          ? '设定群体后点「计算子代」，这里展开配子库、交配组合与逐代结果'
          : '配子库 · 交配组合明细 · 逐代推演${widget.cardHint ?? ''}',
      child: _buildResultBody(),
    );
  }

  /// v2.19.18 结果区内容体（无 StepCard 壳）。
  Widget _buildResultBody() {
    final results = _results;
    if (results == null) {
      return _error != null
          ? _ErrorBanner(message: _error!)
          : Padding(
              padding: const EdgeInsets.symmetric(vertical: 18),
              child: Column(
                children: [
                  Icon(Icons.groups_outlined,
                      size: 32,
                      color: AppColors.steel.withValues(alpha: 0.45)),
                  const SizedBox(height: 10),
                  Text('等待计算：结果将在这里展开',
                      style: AppText.body.copyWith(color: AppColors.steel)),
                ],
              ),
            );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // v2.13：整个结果区（配子库 + 交配组合 + 逐代 + 趋势）整体挂
        // RepaintBoundary，子卡自带装饰，不再叠 canvas 底避免「卡中卡」。
        RepaintBoundary(
          key: _resultKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _sectionLabel('群体配子库',
                  trailing: '配子随机结合 → Hardy-Weinberg'),
              const SizedBox(height: 8),
              _GametePoolCard(result: results.first),
              Divider(height: 28, color: AppColors.border.withValues(alpha: 0.6)),
              _sectionLabel('交配组合明细（枚举法）'),
              const SizedBox(height: 8),
              _MatingsCard(result: results.first),
              for (var g = 0; g < results.length; g++) ...[
                Divider(height: 28, color: AppColors.border.withValues(alpha: 0.6)),
                _sectionLabel(
                    results.length == 1 ? '子代结果' : '第 ${g + 1} 代子代'),
                const SizedBox(height: 8),
                _OffspringCard(result: results[g]),
              ],
              if (results.length > 1) ...[
                Divider(height: 28, color: AppColors.border.withValues(alpha: 0.6)),
                _TrendCard(results: results),
              ],
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
    );
  }

  Widget _buildInputArea() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('群体基因型构成', style: AppText.label),
        const SizedBox(height: 8),
        for (var i = 0; i < _rows.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              children: [
                Expanded(
                  flex: 3,
                  child: TextField(
                    controller: _rows[i].gen,
                    style: AppText.genotype,
                    decoration: const InputDecoration(
                      labelText: '基因型',
                      hintText: '如 Aa',
                    ),
                    onSubmitted: (_) => _compute(),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: TextField(
                    controller: _rows[i].freq,
                    style: AppText.genotype,
                    decoration: const InputDecoration(
                      labelText: '频率 / 份数',
                      hintText: '1/3、33.3%、2',
                    ),
                    onSubmitted: (_) => _compute(),
                  ),
                ),
                IconButton(
                  onPressed: _rows.length > 1 ? () => _removeRow(i) : null,
                  icon: const Icon(Icons.remove_circle_outline, size: 20),
                  tooltip: '删除本行',
                ),
              ],
            ),
          ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: _addRow,
            icon: const Icon(Icons.add, size: 18),
            label: const Text('添加基因型'),
          ),
        ),
        const SizedBox(height: 4),
        // v2.19.22：两个 Dropdown 改竖排（各全宽一行）——宽屏 rail
        // 内容宽仅 248px，横排两个 Expanded DropdownButtonFormField
        // 内部选中行在 ~90px 约束里溢出 6.9px。
        DropdownButtonFormField<String>(
          initialValue: _lethal,
          decoration: const InputDecoration(labelText: '致死 / 选择'),
          items: [
            for (final o in _lethalOptions)
              DropdownMenuItem(value: o, child: Text(o)),
          ],
          onChanged: (v) => setState(() => _lethal = v ?? '无'),
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<int>(
          initialValue: _generations,
          decoration: const InputDecoration(labelText: '逐代推演代数'),
          items: [
            for (var g = 1; g <= 5; g++)
              DropdownMenuItem(value: g, child: Text('$g 代')),
          ],
          onChanged: (v) => setState(() => _generations = v ?? 1),
        ),
        const SizedBox(height: 16),
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton.icon(
            onPressed: _compute,
            icon: const Icon(Icons.calculate_outlined),
            label: const Text('计算子代'),
          ),
        ),
        const SizedBox(height: 14),
        Text('经典案例', style: AppText.caption),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final p in _presets)
              _PresetChip(preset: p, onTap: () => _applyPreset(p)),
          ],
        ),
      ],
    );
  }

  Widget _sectionLabel(String title, {String? trailing}) {
    return Row(
      children: [
        Text(title, style: AppText.sectionTitle),
        if (trailing != null) ...[
          const SizedBox(width: 10),
          Expanded(
            child: Text(trailing,
                style: AppText.caption.copyWith(color: AppColors.steel)),
          ),
        ],
      ],
    );
  }
}

/// 错误横幅：lethal 色圆角 container + icon（与 9331 样板一致）。
class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.lethal.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppTheme.radiusInput),
        border: Border.all(color: AppColors.lethal.withValues(alpha: 0.35)),
      ),
      child: Row(
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
}

/// 经典自由交配案例（教学高频）。
const _presets =
    <({String name, List<(String, String)> rows, String lethal, int gens})>[
  (
    name: 'F1 杂合群体',
    rows: [('Aa', '1')],
    lethal: '无',
    gens: 1,
  ),
  (
    name: '1/3 AA + 2/3 Aa',
    rows: [('AA', '1/3'), ('Aa', '2/3')],
    lethal: '无',
    gens: 1,
  ),
  (
    name: 'F2 群体自由交配',
    rows: [('AA', '1'), ('Aa', '2'), ('aa', '1')],
    lethal: '无',
    gens: 1,
  ),
  (
    name: '平衡推演 3 代',
    rows: [('AA', '1/3'), ('Aa', '2/3')],
    lethal: '无',
    gens: 3,
  ),
  (
    name: 'aa 致死逐代淘汰',
    rows: [('Aa', '1')],
    lethal: '隐性纯合致死',
    gens: 3,
  ),
  (
    name: 'AaBb 群体',
    rows: [('AaBb', '1')],
    lethal: '无',
    gens: 1,
  ),
];

class _PresetChip extends StatelessWidget {
  final ({String name, List<(String, String)> rows, String lethal, int gens})
      preset;
  final VoidCallback onTap;
  _PresetChip({required this.preset, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: preset.rows.map((e) => '${e.$2} ${e.$1}').join(' + ') +
          (preset.lethal == '无' ? '' : '，${preset.lethal}') +
          (preset.gens > 1 ? '，${preset.gens} 代' : ''),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: AppColors.border),
          ),
          child: Text(preset.name,
              style: AppText.caption.copyWith(color: AppColors.graphite)),
        ),
      ),
    );
  }
}

/// 群体配子库内容（StepCard 内部，无自身卡片外壳）。
class _GametePoolCard extends StatelessWidget {
  final RandomMatingResult result;
  const _GametePoolCard({required this.result});

  @override
  Widget build(BuildContext context) {
    final entries = result.gametePool.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Σ(基因型频率 × 各基因型配子)', style: AppText.label),
        const SizedBox(height: 8),
        Wrap(
          spacing: 10,
          runSpacing: 8,
          children: [
            for (final e in entries)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: AppColors.tealWash,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.teal),
                ),
                child: Text(
                  '${e.key}  ${e.value}（${e.value.toPercent()}）',
                  style:
                      AppText.monoSmall.copyWith(color: AppColors.teal),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

/// 交配组合明细（无序对 + 概率 + 子代展开；致死组合标注存活率）。
/// StepCard 内部，无自身卡片外壳。
class _MatingsCard extends StatelessWidget {
  final RandomMatingResult result;
  const _MatingsCard({required this.result});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (var i = 0; i < result.matings.length; i++) ...[
          if (i > 0)
            Divider(height: 1, color: AppColors.border.withValues(alpha: 0.6)),
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: Row(
              children: [
                Expanded(
                  child: Text(result.matings[i].label,
                      style: AppText.genotype.copyWith(fontSize: 13)),
                ),
                Text(
                  'P = ${result.matings[i].probability}'
                  '（${result.matings[i].probability.toPercent()}）',
                  style: AppText.monoSmall,
                ),
              ],
            ),
            subtitle: result.matings[i].survivalRate != Fraction.one
                ? Text(
                    '子代存活率 ${result.matings[i].survivalRate}'
                    '——合并时该组合贡献按存活率缩水',
                    style: AppText.caption.copyWith(color: AppColors.lethal),
                  )
                : null,
            children: [
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Column(
                  children: [
                    for (final e in result.matings[i].offspring.entries)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Row(
                          children: [
                            SizedBox(
                              width: 90,
                              child: Text(e.key,
                                  style: AppText.genotype
                                      .copyWith(fontSize: 13)),
                            ),
                            const Spacer(),
                            Text('${e.value}（${e.value.toPercent()}）',
                                style: AppText.monoSmall),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

/// 子代结果内容：基因型表 + 表型整数比（StepCard 内部 teal 区块）。
class _OffspringCard extends StatelessWidget {
  final RandomMatingResult result;
  const _OffspringCard({required this.result});

  @override
  Widget build(BuildContext context) {
    final genEntries = result.offspringGenotypes.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final phenoEntries = result.offspringPhenotypes.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.tealWash,
        borderRadius: BorderRadius.circular(AppTheme.radiusCard),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('基因型整数比', style: AppText.sectionTitle),
          const SizedBox(height: 4),
          Text(result.genotypeRatio.join(' : '),
              style: AppText.monoFigure.copyWith(fontSize: 22)),
          const SizedBox(height: 8),
          for (final e in genEntries)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                children: [
                  SizedBox(
                    width: 90,
                    child: Text(e.key,
                        style: AppText.genotype.copyWith(fontSize: 13)),
                  ),
                  const Spacer(),
                  Text(e.value.toPercent(),
                      style:
                          AppText.caption.copyWith(color: AppColors.steel)),
                  const SizedBox(width: 8),
                  RatioPill(text: '${e.value}'),
                ],
              ),
            ),
          const SizedBox(height: 8),
          Divider(height: 1, color: AppColors.border.withValues(alpha: 0.6)),
          const SizedBox(height: 8),
          Text('表型整数比', style: AppText.sectionTitle),
          const SizedBox(height: 4),
          Text(result.phenotypeRatio.join(' : '),
              style: AppText.monoFigure.copyWith(fontSize: 22)),
          const SizedBox(height: 8),
          for (final e in phenoEntries)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                children: [
                  Text(e.key, style: AppText.body),
                  const Spacer(),
                  Text(e.value.toPercent(),
                      style:
                          AppText.caption.copyWith(color: AppColors.steel)),
                  const SizedBox(width: 8),
                  RatioPill(text: '${e.value}'),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// 逐代趋势卡：单等位基因频率在各代配子库中的变化。
/// 逐代趋势卡里折线图的**判据与取色**（公开，好让守卫测试直接断这两条纪律）。
///
/// ⛔ 本卡**不新建**图表组件：曲线用的是进化页「自然选择模拟」那张既有的
/// [FrequencyCurveChart]（`evolution_page.dart:583` 起，v2.13 就在用）。
/// 本卡只是把 9331「自由交配」tab 6 的结果区从纯文字扫读补一张趋势图——
/// 组件形状照抄那处（多条 [FreqSeries] + `AppColors.*` 颜色）。
class RandomMatingTrend {
  const RandomMatingTrend._();

  /// 曲线上最多几条线（= 一次渲染允许的配子种数上限）。
  ///
  /// ## 为什么是 4（阈值按「图例一行放得下」定，不是按「好看」定）
  ///
  /// [FrequencyCurveChart] 的可调尺寸**只有高度**（`height`），宽度由父级给
  /// 且**无权改**（`width: double.infinity`）；更要命的是**图例单行不换行**
  /// （`frequency_curve_chart.dart` 里 `legendX += 14 + tp.width + 14`，只增、
  /// 不回绕），画不下就**越过右缘被裁掉**。于是本卡阈值只能按「图例一行放得下」
  /// 来定——加高不管用，只能改**画不画**。
  ///
  /// 取 4 的理由：单一位点 2 条、两位点 4 条，是自由交配真正会遇到的两种，
  /// 都放得下；三位点起 8 条 ⇒ 图例一行放不下 ⇒ 必被裁 ⇒ 裁掉图例与静默
  /// 截断同一宗罪（学生照着抄会拿到错数，页面上没有任何说明）。
  static const int maxCurves = 4;

  /// **画不了曲线时屏上要写的那句说明**；画得了返回 `null`（`null` ⇔ 画）。
  ///
  /// ⛔ 两条「不画」的路都**必须明写原因**：一条是配子种数超 [maxCurves]
  /// （画不下），一条是只算了 1 代（一个点画不出趋势）。屏上什么都不说，
  /// 读者就默认「这里没有第 5 种配子」或「这里就是一条平的」，那比不给更坏。
  static String? skipNotice({
    required int alleleCount,
    required int generationCount,
  }) {
    if (alleleCount > maxCurves) {
      return '有 $alleleCount 种配子，超过折线图 $maxCurves 条的分辨上限，'
          '这里不画曲线（只画前几条会让人照着抄到错数）；'
          '全部 $alleleCount 种配子各自列出逐代频率。';
    }
    if (generationCount < 2) {
      return '只算了 $generationCount 代，一个点画不出趋势（折线至少要 2 代）；'
          '各配子各自列出逐代频率。';
    }
    return null;
  }

  /// 折线调色板：**按字母序**固定分配的四个色位。
  ///
  /// ⚠️ 必须是 **getter**，不许写成 `static final List<Color>`：
  /// `AppColors.*` 是 **getter 不是 const 字段**（`theme.dart` 按浅/浅Hc/深/
  /// 深Hc 四档**实时求值**），冻进 final list 就等于把颜色钉死在**首次读取的
  /// 那一档**，之后切深色/夜间高对比不会跟着变。
  ///
  /// 选**四个不同色相族**（绿≈150° / 蓝≈220° / 褐琥珀≈30° / 紫≈265°），
  /// 任意相邻最近的一对（蓝↔紫）也差 ≈45°，投影偏色不会把它们拉到一起。
  ///
  /// ⛔ [AppColors.lethal] **不许**进这支调色板：本仓红 = **致死**语义，
  /// 拿它当第 5 种曲线颜色等于凭空宣布「这条线是致死的」。
  /// ⛔ 也不收 [AppColors.sexLower]：它与 [AppColors.sand] 两档都分不开
  /// （浅色 #CA8A04 vs #8F5B1E、深色 #FACC15 vs #F59E0B），收进来等于两条重合。
  static List<Color> get palette => <Color>[
        AppColors.teal,
        AppColors.sexUpper,
        AppColors.sand,
        AppColors.armed,
      ];

  /// 某个配子的线色：**只看它在字母序里的名次**。
  ///
  /// ⛔ 绝不按遍历顺序取色：`alleles` 是各代 `gametePool` 的 key 并集（`Set`），
  /// 迭代顺序不保证稳定 ⇒ 学生重算一次看到颜色换了，会以为曲线变了。调用方传进来的
  /// `alleles` 是否已排序都不影响结果（这里再排一次，幂等）。
  static Color colorOfAllele(String allele, Iterable<String> allAlleles) {
    final sorted = allAlleles.toList()..sort();
    final i = sorted.indexOf(allele);
    assert(i >= 0 && i < palette.length,
        '配子「$allele」不在配子表里，或超出 [maxCurves] 色位：$sorted');
    return palette[i];
  }
}

class _TrendCard extends StatelessWidget {
  final List<RandomMatingResult> results;
  const _TrendCard({required this.results});

  @override
  Widget build(BuildContext context) {
    // 收集所有出现过的等位基因（按配子库并集）
    final alleles = <String>{};
    for (final r in results) {
      alleles.addAll(r.gametePool.keys);
    }
    if (alleles.isEmpty) return const SizedBox.shrink();
    // v2.19.41：曲线与文字链**都按字母序**走。曲线那边是取色的前提（同一配子
    // 两次渲染必须同色，见 [RandomMatingTrend.colorOfAllele]）；文字链跟着改是
    // 为让**图例顺序与下面各行顺序一致**。文字链内容一字未动。
    final sorted = alleles.toList()..sort();
    // 画不画曲线的判据集中在一处；不画时屏上**明写原因**（⛔ 静默截断）。
    final notice = RandomMatingTrend.skipNotice(
      alleleCount: sorted.length,
      generationCount: results.length,
    );
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('逐代配子频率趋势', style: AppText.sectionTitle),
            const SizedBox(height: 8),
            if (notice != null) ...[
              // ⛔ 宁可写清楚「为什么没有曲线」，也不给一条缺图例的意大利面。
              Text(notice,
                  style: AppText.caption.copyWith(color: AppColors.steel)),
              const SizedBox(height: 8),
            ] else ...[
              // 逐代频率折线图：组件与形状都**沿用**进化页自然选择模拟那张
              // FrequencyCurveChart，数据就是下面文字链算的**同一串** gametePool 频率。
              //
              // `Fraction.toDouble()` 是 `n / d` 的 IEEE 双精度除法，精度远在
              // 像素之下，**不改动任何屏上显示的数值**：精确值（分数形式）仍由
              // 下面保留的文字链承担，曲线只是趋势图。
              //
              // 图例文字只写配子名（如 `AB`）、不写「频率」二字：图例是单行
              // 不换行的一排，省下的宽度正是 [RandomMatingTrend.maxCurves] = 4
              // 能成立的前提；纵轴本来就是 0%/50%/100%，卡片标题也写着「配子频率」。
              FrequencyCurveChart(
                series: [
                  for (final a in sorted)
                    FreqSeries(
                      label: a,
                      values: [
                        for (final r in results)
                          (r.gametePool[a] ?? Fraction.zero).toDouble(),
                      ],
                      color: RandomMatingTrend.colorOfAllele(a, sorted),
                    ),
                ],
              ),
              const SizedBox(height: 8),
            ],
            // v2.19.41 创新·读图脚手架：数据驱动的一句「怎么读」，不硬编码结论。
            // ⛔ 只从 sorted 的逐代频率推导（单调降 / 趋平 / 达过平衡），
            //    不读输入框、不假设题型；推导不出就不给（宁可不给也不给错）。
            // 读图提示（数据驱动，空串则不渲染这一块）
            ..._readingHintBlock(sorted, results),
            for (final a in sorted)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  children: [
                    SizedBox(
                      width: 56,
                      child: Text(a, style: AppText.genotype),
                    ),
                    Expanded(
                      child: Text(
                        results
                            .map((r) =>
                                (r.gametePool[a] ?? Fraction.zero).toString())
                            .join('  →  '),
                        style: AppText.monoSmall,
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 6),
            Text(
              '无选择时一代即达平衡并保持稳定；有致死时隐性基因被逐代淘汰。',
              style: AppText.caption,
            ),
          ],
        ),
      ),
    );
  }

  /// 读图脚手架：从逐代频率**推导**一句「怎么读」。
  ///
  /// ⛔ 数据驱动、不硬编码结论：只认 [alleles] 在逐代 [results] 里的频率形状
  /// （单调性 / 是否趋平 / 是否某代达过平衡），推导不出特征就返回空串（整块不渲染）。
  /// 理由：这是教学 app，学生读不懂的图只是装饰；但「宁可不给也不给错」，
  /// 没有可辨识特征时绝不硬塞一句套话。
  static List<Widget> _readingHintBlock(
      List<String> alleles, List<RandomMatingResult> results) {
    double f(String a, int g) => (results[g].gametePool[a] ?? Fraction.zero).toDouble();
    final clues = <String>[];
    for (final a in alleles) {
      final seq = [for (var g = 0; g < results.length; g++) f(a, g)];
      if (seq.length < 2) continue;
      // 单调性（允许多代间的非增 / 非减）
      var nonIncreasing = true, nonDecreasing = true;
      for (var i = 1; i < seq.length; i++) {
        if (seq[i] > seq[i - 1] + 1e-9) nonIncreasing = false;
        if (seq[i] < seq[i - 1] - 1e-9) nonDecreasing = false;
      }
      if (nonIncreasing && seq.last < seq.first - 1e-9) {
        clues.add('「$a」逐代下降');
      } else if (nonDecreasing && seq.last > seq.first + 1e-9) {
        clues.add('「$a」逐代上升');
      }
      // 是否早已达平衡（某代起频率基本不动）：首尾差距极小且中段无大跳
      var flat = true;
      for (var i = 1; i < seq.length; i++) {
        if ((seq[i] - seq[i - 1]).abs() > 0.02) flat = false;
      }
      if (flat) clues.add('「$a」各代基本不变');
    }
    if (clues.isEmpty) return const <Widget>[];
    return <Widget>[
      const SizedBox(height: 6),
      Text(
        '怎么读：${clues.join('；')}。',
        style: AppText.caption.copyWith(color: AppColors.steel),
      ),
    ];
  }
}
