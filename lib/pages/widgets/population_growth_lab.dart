// population_growth_lab.dart —— 进化页第 6 页签「种群增长」：J 型 / S 型对照
//
// 为什么是一个独立实验组件：J 型（离散代际 N_t = N₀·λᵗ）与 S 型
// （连续 Logistic N_t = K/(1+(K/N₀−1)e^(−r·t))）共用一套输入
// （N₀、λ、K、r、代数），输入与结果必须**同一份 State**，否则「左栏
// 改了 K、右栏还画着旧 K 的曲线」这种自相矛盾的画面必然出现。
//
// 契约与 pcr_lab.dart 完全一致（页面用 GlobalKey 取本 State）：
//   · [PopulationGrowthLabState.buildInputs] —— 左栏（窄屏回落到结果区上方）；
//   · [PopulationGrowthLabState.build] —— 结果区；
//   · [PopulationGrowthLabState.isPristine] —— 父页深链覆盖守卫用；
//   · [PopulationGrowthLabState.recalc] —— 父页「全部计算」按一次重算；
//   · [PopulationGrowthLab.revision] —— 宽屏左栏先于结果区构建，挂载后补一帧。
//
// 科学口径见 lib/engine/population_growth_engine.dart 文件头；屏上另印
// [kPopulationGrowthDisclaimer]（模型边界），⛔ 不许删。
//
// 屏上公式（J/S 通式、绝对速率/相对增长率、J 型新增量）一律经
// [TexFormula] 真排版（flutter_math_fork 的 Math.tex）；⛔ 中文解释不许
// 塞进 TeX \text，全部留在普通 Text 里。

import 'package:flutter/material.dart';

import '../../charts/population_growth_chart.dart';
import '../../engine/population_growth_engine.dart';
import '../../theme.dart';
import '../../ui/tex_formula.dart';
import 'cross_tool_rail.dart' show FlatSection;

/// 屏上一句话的模型边界（⛔ 不许删：这是「不虚构科学」的可见承诺）。
const String kPopulationGrowthDisclaimer =
    '教学简化模型：J 型假设资源空间无限且 λ 固定；S 型只考虑环境容纳量，'
    '不含随机波动、迁移、年龄结构；不用于预测真实种群。';

/// 一个预设（chip）：一键把五个输入都摆好——白板上不用键盘也能出结果。
class PopulationGrowthSample {
  const PopulationGrowthSample({
    required this.label,
    required this.n0,
    required this.lambda,
    required this.k,
    required this.r,
    required this.generations,
  });

  final String label;
  final String n0;
  final String lambda;
  final String k;
  final String r;
  final String generations;
}

/// 种群增长实验（输入 + 结果，共享一份 State）。
class PopulationGrowthLab extends StatefulWidget {
  const PopulationGrowthLab({super.key, this.showInputs = true, this.revision});

  /// true（默认）：输入区 + 结果区一起渲染（单测/窄屏直接泵它）。
  /// false：只渲染结果区——页面里输入区由左栏副本
  /// （[PopulationGrowthLabState.buildInputs]）承担。
  final bool showInputs;

  /// 左栏副本的重建信号（页面持有并负责 dispose，⛔ 本组件不 dispose 它）。
  final ValueNotifier<int>? revision;

  @override
  PopulationGrowthLabState createState() => PopulationGrowthLabState();
}

class PopulationGrowthLabState extends State<PopulationGrowthLab>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  // ── 出厂默认题（具名常量：controller 初值与 isPristine 共用同一批）──
  //
  // 默认例的选取理由：λ=1.5、K=1000、N₀=10、r=0.8、12 代 ⇒ J 型第 12 代
  // ≈1297（刚越过 K），S 型 ≈993（趋近 K）。两条曲线落在同一数量级，
  // 共用一根纵轴时都看得清，恰好演示「J 冲上 K、S 贴住 K」的核心差别。
  static const String kDefaultN0 = '10';
  static const String kDefaultLambda = '1.5';
  static const String kDefaultCarryingCapacity = '1000';
  static const String kDefaultR = '0.8';
  static const String kDefaultGenerations = '12';

  /// 预设 chips：三个都必须给全五个输入（⛔ 半套参数会得到没有意义的对照）。
  static const List<PopulationGrowthSample> samples = <PopulationGrowthSample>[
    PopulationGrowthSample(
      label: '理想 J 型',
      n0: kDefaultN0,
      lambda: kDefaultLambda,
      k: kDefaultCarryingCapacity,
      r: kDefaultR,
      generations: kDefaultGenerations,
    ),
    PopulationGrowthSample(
      label: '资源有限 S 型',
      n0: '20',
      lambda: '1.2',
      k: '1000',
      r: '0.45',
      generations: '20',
    ),
    PopulationGrowthSample(
      label: 'N0 > K 的回落',
      n0: '2000',
      lambda: '1.05',
      k: '1000',
      r: '0.8',
      generations: '12',
    ),
  ];

  final _n0Ctrl = TextEditingController(text: kDefaultN0);
  final _lambdaCtrl = TextEditingController(text: kDefaultLambda);
  final _kCtrl = TextEditingController(text: kDefaultCarryingCapacity);
  final _rCtrl = TextEditingController(text: kDefaultR);
  final _genCtrl = TextEditingController(text: kDefaultGenerations);

  PopulationGrowthComparison? _result;
  String? _error;

  /// 学生一个格子都没动过吗（父页深链覆盖守卫用）。
  /// ⚠️ 判的是「有没有被学生动过」，不是「是不是空」；非空 ≠ dirty。
  bool get isPristine =>
      _n0Ctrl.text == kDefaultN0 &&
      _lambdaCtrl.text == kDefaultLambda &&
      _kCtrl.text == kDefaultCarryingCapacity &&
      _rCtrl.text == kDefaultR &&
      _genCtrl.text == kDefaultGenerations;

  @override
  void initState() {
    super.initState();
    // 出厂默认题先算一遍（与其余页签「出厂即展开默认结果」一致）。
    _result = _resultQuiet(
      n0: _n0Ctrl.text,
      lambda: _lambdaCtrl.text,
      k: _kCtrl.text,
      r: _rCtrl.text,
      generations: _genCtrl.text,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _bumpRevision();
    });
  }

  @override
  void dispose() {
    for (final c in [_n0Ctrl, _lambdaCtrl, _kCtrl, _rCtrl, _genCtrl]) {
      c.dispose();
    }
    super.dispose();
  }

  PopulationGrowthComparison? _resultQuiet({
    required String n0,
    required String lambda,
    required String k,
    required String r,
    required String generations,
  }) {
    try {
      return _buildFrom(
        n0: n0,
        lambda: lambda,
        k: k,
        r: r,
        generations: generations,
      );
    } on ArgumentError {
      return null;
    }
  }

  /// 唯一解析入口：五个输入 → 对照结果；非法输入抛 [ArgumentError]（中文）。
  PopulationGrowthComparison _buildFrom({
    required String n0,
    required String lambda,
    required String k,
    required String r,
    required String generations,
  }) {
    final n0v = double.tryParse(n0.trim());
    final lv = double.tryParse(lambda.trim());
    final kv = double.tryParse(k.trim());
    final rv = double.tryParse(r.trim());
    final gv = int.tryParse(generations.trim());
    if (n0v == null || lv == null || kv == null || rv == null || gv == null) {
      throw ArgumentError('N0、λ、K、r、代数 都必须是数字'
          '（当前：N0=$n0、λ=$lambda、K=$k、r=$r、代数=$generations）');
    }
    return comparePopulationGrowth(
      n0: n0v,
      lambda: lv,
      k: kv,
      r: rv,
      generations: gv,
    );
  }

  /// 通知左栏副本重建（⛔ 页面持有该 ValueNotifier，此处只自增）。
  void _bumpRevision() => widget.revision?.value++;

  /// 按当前输入重算（按钮 / 回车 / chip 共用唯一入口）。
  void _compute() {
    try {
      final result = _buildFrom(
        n0: _n0Ctrl.text,
        lambda: _lambdaCtrl.text,
        k: _kCtrl.text,
        r: _rCtrl.text,
        generations: _genCtrl.text,
      );
      setState(() {
        _result = result;
        _error = null;
      });
    } on ArgumentError catch (e) {
      // ⛔ 出错必须清旧结果：留着上一题的曲线，学生会以为这次也算成了。
      setState(() {
        _result = null;
        _error = e.message?.toString() ?? '输入格式错误';
      });
    }
    _bumpRevision();
  }

  /// 供父页「全部计算」按一次刷新本实验（未挂载时父页取不到 State）。
  void recalc() => _compute();

  void _applySample(PopulationGrowthSample sample) {
    setState(() {
      _n0Ctrl.text = sample.n0;
      _lambdaCtrl.text = sample.lambda;
      _kCtrl.text = sample.k;
      _rCtrl.text = sample.r;
      _genCtrl.text = sample.generations;
    });
    _compute();
  }

  // ─── 输入区（宽屏左栏 / 窄屏结果区上方 / 自包含形态顶部）───

  /// 输入面板：左侧工作台栏调用它（页面用 GlobalKey 取本 State）。
  Widget buildInputs(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FlatSection(
            title: '种群增长的两种模型',
            subtitle: '选择性必修2 · 种群的数量变化',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'J 型：资源空间无限、每代固定乘 λ（离散代际）；'
                  'S 型：资源有限，只考虑环境容纳量 K（连续 Logistic）。'
                  '两条曲线共用同一条时间轴。',
                  style: AppText.caption.copyWith(color: AppColors.graphite),
                ),
                const SizedBox(height: 6),
                const TexFormula(
                  key: Key('tex-j-intro'),
                  tex: r'N_t = N_0\,\lambda^{t}',
                  fallback: 'N_t = N₀·λᵗ',
                  semanticsLabel: 'J 型通项：N 下标 t 等于 N 下标 0 乘 λ 的 t 次方',
                ),
                const SizedBox(height: 4),
                const TexFormula(
                  key: Key('tex-s-intro'),
                  tex: r'N_t = \frac{K}'
                      r'{1 + \left(\frac{K}{N_0} - 1\right) e^{-r \cdot t}}',
                  fallback: 'N_t = K ÷ [1 + (K/N₀ − 1)·e^(−r·t)]',
                  semanticsLabel: 'S 型通项：N 下标 t 等于 K 除以 '
                      '[1 + (K 除 N 下标 0 减 1) 乘 e 的负 r 乘 t 次方]',
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
                _numField(_n0Ctrl, '初始数量 N0', _compute),
                _numField(_lambdaCtrl, '每代增长倍数 λ（0–10）', _compute),
                _numField(_kCtrl, '环境容纳量 K（S 型）', _compute),
                _numField(_rCtrl, '内禀增长率 r（0–5）', _compute),
                _numField(_genCtrl, '代数（1–40）', _compute),
                const SizedBox(height: 4),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _compute,
                    icon: const Icon(Icons.show_chart_outlined, size: 18),
                    label: const Text('计算种群增长',
                        style: TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w600)),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(0, 44),
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      );

  Widget _numField(
          TextEditingController ctrl, String label, VoidCallback onDone) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: TextField(
          controller: ctrl,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
            isDense: true,
            labelText: label,
            counterText: '',
          ),
          onSubmitted: (_) => onDone(),
        ),
      );

  // ─── 结果区 ───

  @override
  Widget build(BuildContext context) {
    super.build(context); // 页签往返时保留学生当前输入与结果。
    final results = _buildResults(context);
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

  Widget _buildResults(BuildContext context) {
    final r = _result;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(kPopulationGrowthDisclaimer,
            style: AppText.caption.copyWith(color: AppColors.steel)),
        const SizedBox(height: 16),
        if (_error != null)
          FlatSection(title: '种群增长结果', child: _errorBanner(_error!))
        else if (r != null) ...[
          _chartSection(r),
          const SizedBox(height: 26),
          _tableSection(r),
          const SizedBox(height: 26),
          _capacitySection(r),
          const SizedBox(height: 26),
          _rateSection(r),
        ],
      ],
    );
  }

  Widget _errorBanner(String message) => Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.lethal.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(AppTheme.radiusInput),
          border: Border.all(color: AppColors.lethal.withValues(alpha: 0.45)),
        ),
        child: Text(message,
            style: AppText.body
                .copyWith(color: AppColors.lethal, fontWeight: FontWeight.w600)),
      );

  Widget _chartSection(PopulationGrowthComparison r) => FlatSection(
        title: 'J 型与 S 型对照曲线',
        subtitle: '共用同一条时间轴与数量轴；两条虚线是 K 与 K/2',
        trailing: AppChip('t = 0…${r.generations}'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            PopulationGrowthChart(
              series: [
                GrowthSeries(
                  label: 'J 型（λ 固定）',
                  values: r.j.population,
                  color: AppColors.teal,
                ),
                GrowthSeries(
                  label: 'S 型（Logistic）',
                  values: r.s.population,
                  color: AppColors.sand,
                ),
              ],
              references: [
                GrowthReference(
                  value: r.s.halfK,
                  label: 'K/2 = ${_f(r.s.halfK)}',
                  color: AppColors.steel,
                ),
                GrowthReference(
                  value: r.s.k,
                  label: 'K = ${_f(r.s.k)}',
                  color: AppColors.graphite,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '本页当前输入：J 型末代 ${_f(r.j.finalPopulation)}，'
              'S 型末代 ${_f(r.s.finalPopulation)}'
              '（K = ${_f(r.s.k)}）。纵轴按两者的最大值自动取上限，'
              '所以纵轴刻度不是 0–1 的频率轴。',
              style: AppText.caption.copyWith(color: AppColors.graphite),
            ),
          ],
        ),
      );

  Widget _tableSection(PopulationGrowthComparison r) => FlatSection(
        title: '逐代数值',
        subtitle: 't = 代数　J = J 型数量 N_t　S = S 型数量 N_t（引擎返回值）',
        trailing: AppChip('${r.generations + 1} 行'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var t = 0; t <= r.generations; t++)
              Padding(
                padding: const EdgeInsets.only(bottom: 3),
                child: Text(
                  't = ${t.toString().padLeft(2)}　'
                  'J = ${_f(r.j.population[t])}　'
                  'S = ${_f(r.s.population[t])}',
                  style: AppText.monoSmall.copyWith(
                      fontSize: 12.5, color: AppColors.ink),
                ),
              ),
          ],
        ),
      );

  Widget _capacitySection(PopulationGrowthComparison r) {
    final s = r.s;
    return FlatSection(
      title: 'K 与 K/2 的含义',
      subtitle: '只对 S 型说；J 型没有 K',
      trailing: AppChip('K = ${_f(s.k)}'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _kv('环境容纳量 K', _kLine(s)),
          _kv('K/2 与最大速率',
              'K/2 = ${_f(s.halfK)}；若曲线经过 K/2，该处绝对增长速率最大，'
                  '等于 r·K/4 = ${_f(s.maxAbsoluteRate)} 个/代。'),
          _kv('本曲线是否经过 K/2', _halfKLine(s)),
          _kv('J 型的「上限」',
              'J 型没有 K（假设资源空间无限）：λ > 1 时数量一直往上冲，'
                  '不存在「越接近上限长得越慢」——这正是 J 型与 S 型的分水岭。'),
        ],
      ),
    );
  }

  /// K 的说明必须随模型状态分句：r=0 不朝 K 变、N₀>K 是回落、N₀=K 保持不变。
  /// ⛔ 一律写「最终趋近的上限」在 r=0 / N₀>K 两种情况下都是假话。
  String _kLine(LogisticResult s) {
    if (s.r == 0) {
      return 'K = ${_f(s.k)}：本页 r = 0，数量恒为 N0 = ${_f(s.n0)}，'
          '不会朝 K 变化；K 只是模型里设定的容纳量。';
    }
    if (s.n0 > s.k) {
      return 'K = ${_f(s.k)}：起点 N0 = ${_f(s.n0)} 已高于 K，'
          '数量会从上方逐渐回落到 K；K 是这个模型最终趋近的平衡水平'
          '（环境容纳量），不是一条「数量上限」。';
    }
    if (s.n0 == s.k) {
      return 'K = ${_f(s.k)}：起点正好等于 K，数量保持 K 不变'
          '（r·K/4 = ${_f(s.maxAbsoluteRate)} 个/代只是理论上限）。';
    }
    return 'K = ${_f(s.k)}：S 型曲线最终趋近的平衡水平（环境容纳量），'
        '只由环境决定；它不是一个「数量上限」。';
  }

  String _halfKLine(LogisticResult s) {
    final maxRate = _f(s.maxAbsoluteRate);
    switch (s.halfKStart) {
      case HalfKStart.below:
        // ⚠️ 采样到的那一代只是「最早 ≥ K/2 的那一格」，不是连续模型的
        // 极值点本身；真正的极值时刻用 halfKTime（可为小数）说。
        final t = s.halfKTime;
        final sampled = s.halfKGeneration;
        if (t == null) {
          // 只可能是 r = 0（数量不变）——⛔ 不许强解包 sampled 崩溃。
          return '当前设置下不会达到：r = 0，所以数量恒为 N0 = ${_f(s.n0)}，'
              '永远停在 K/2 以下。';
        }
        if (sampled == null) {
          return '当前代数范围内还没达到：连续模型在 t = ${_f(t)} 处经过 K/2'
              '（N = ${_f(s.halfK)}），但只算到第 ${s.population.length - 1} 代，'
              '屏上曲线尚未走到那一步。';
        }
        return '经过：连续模型在 t = ${_f(t)} 处经过 K/2（N = ${_f(s.halfK)}），'
            '该处绝对增长速率最大（r·K/4 = $maxRate 个/代）；'
            '屏上采样最早在第 $sampled 代看到 N ≥ K/2'
            '（N = ${_f(s.population[sampled])}）。';
      case HalfKStart.at:
        if (s.r == 0) {
          return '起点 N0 = ${_f(s.n0)} 正好在 K/2；r = 0，所以数量不变，'
              '一直停在这个位置（$maxRate 个/代只是理论上限）。';
        }
        return '起点 N0 = ${_f(s.n0)} 正好在 K/2：一开始就是增长最快的时刻'
            '（r·K/4 = $maxRate 个/代），之后随 N 增大而变慢。';
      case HalfKStart.above:
        // ⚠️ above 含三种走向：N₀ > K（回落）、K/2 < N₀ < K（继续增长）、
        // N₀ = K（保持 K）；r = 0 时一律保持不变。写错就是讲反模型。
        final String trend;
        if (s.r == 0) {
          trend = '数量保持不变（r = 0）';
        } else if (s.n0 > s.k) {
          trend = '数量从上方逐渐回落到 K';
        } else if (s.n0 == s.k) {
          trend = '数量保持 K 不变';
        } else {
          trend = '数量继续增长趋近 K（越接近 K 长得越慢）';
        }
        return '不经过：起点 N0 = ${_f(s.n0)} 已在 K/2 之上，$trend，'
            '之后不会再经过 K/2——所以不能说「以后到 K/2 时增长最快」。'
            'r·K/4 = $maxRate 个/代只是该模型的理论上限。';
    }
  }

  Widget _rateSection(PopulationGrowthComparison r) {
    final s = r.s;
    final n0 = s.population.first;
    final last = s.population.last;
    final inc = r.j.increments;
    return FlatSection(
      title: '绝对增长速率与相对增长率',
      subtitle: '两个量别混：一个按「整群」算，一个按「每个个体」算',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _kvRow(
            '定义（S 型）',
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('绝对增长速率（个/代）', style: _formulaNoteStyle),
                const SizedBox(height: 2),
                const TexFormula(
                  key: Key('tex-rate-absolute'),
                  tex: r'\frac{dN}{dt} = rN\left(1 - \frac{N}{K}\right)',
                  fallback: 'dN/dt = r·N·(1 − N/K)',
                  semanticsLabel:
                      '绝对增长速率：dN/dt 等于 r 乘 N 乘 (1 减 N 除 K)',
                ),
                const SizedBox(height: 8),
                Text('相对增长率（每个个体每代）', style: _formulaNoteStyle),
                const SizedBox(height: 2),
                const TexFormula(
                  key: Key('tex-rate-relative'),
                  tex: r'\frac{1}{N}\,\frac{dN}{dt}'
                      r' = r\left(1 - \frac{N}{K}\right)',
                  fallback: '(1/N)·dN/dt = r·(1 − N/K)',
                  semanticsLabel:
                      '相对增长率：(1 除 N) 乘 dN/dt 等于 r 乘 (1 减 N 除 K)',
                ),
              ],
            ),
          ),
          _kv('起点 N0',
              '绝对 ${_f(s.absoluteRateAt(n0))} 个/代；'
                  '相对 ${_pct(s.relativeRateAt(n0))}（每个个体每代）'),
          _kv('末代 N${r.generations}',
              '绝对 ${_f(s.absoluteRateAt(last))} 个/代；'
                  '相对 ${_pct(s.relativeRateAt(last))}'),
          _kvRow(
            'J 型对照',
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('绝对新增量', style: _formulaNoteStyle),
                const SizedBox(height: 2),
                const TexFormula(
                  key: Key('tex-j-increment'),
                  tex: r'N_{t+1} - N_t = N_t\,(\lambda - 1)',
                  fallback: 'N_{t+1} − N_t = N_t·(λ − 1)',
                  semanticsLabel: 'J 型绝对新增量：N 下标 t+1 减 N 下标 t '
                      '等于 N 下标 t 乘 (λ 减 1)',
                ),
                const SizedBox(height: 4),
                Text(
                  '${_f(inc.first)} → ${_f(inc.last)} 个/代；'
                  '相对增长率恒为 ${_pct(r.j.relativeGrowthRate)}，'
                  '不随数量变化。',
                  style: _kvValueStyle,
                ),
              ],
            ),
          ),
          if (s.isAtEquilibrium)
            _kv('r = 0',
                'S 型不增长：始终为 N0 = ${_f(s.n0)}（不会突然跳到 K）。'),
          _kv('读法', _jTrendLine(r.j)),
        ],
      ),
    );
  }

  String _jTrendLine(JShapedResult j) {
    // ⚠️ 屏上文字⛔ 不许用 ⇒ / ⇔ 这类逻辑箭头：golden 的中文字体（雅黑）里
    // 没有这些码位，会渲染成 .notdef 空心方框（实测 `> 1 ⇒ 增长` 显示为
    // `> 1 □ 增长`）。改用「所以 / 因此」等自然中文因果词。`→` 已实测可显示。
    switch (j.trend) {
      case JShapeTrend.grow:
        return 'λ = ${_f(j.lambda)} > 1，所以增长：每代固定乘 λ，'
            '相对增长率恒为 λ−1 = ${_f(j.relativeGrowthRate)}'
            '（每代 ${_pct(j.relativeGrowthRate)}）。';
      case JShapeTrend.stable:
        return 'λ = 1，所以稳定：相对增长率 λ−1 = 0，数量每代不变。';
      case JShapeTrend.decline:
        return '0 < λ < 1，所以下降：相对增长率 λ−1 = '
            '${_f(j.relativeGrowthRate)}（每代 ${_pct(j.relativeGrowthRate)}）。';
      case JShapeTrend.extinct:
        return 'λ = 0，所以归零：下一代起数量为 0（相对增长率 λ−1 = −1，'
            '每代 −100%）。';
    }
  }

  /// _kv 值文案样式（13px 加粗正文，与标签列的 caption 形成层级）。
  /// ⛔ 不做 static 缓存：AppText/AppColors 都是实时派生的 theme token。
  TextStyle get _kvValueStyle => AppText.body
      .copyWith(fontSize: 13, height: 1.55, fontWeight: FontWeight.w600);

  /// 公式前的小节提示词（「绝对增长速率（个/代）」这类）。
  TextStyle get _formulaNoteStyle => AppText.caption
      .copyWith(color: AppColors.graphite, fontWeight: FontWeight.w600);

  Widget _kv(String label, String value) =>
      _kvRow(label, Text(value, style: _kvValueStyle));

  /// 左标签 + 右内容（[Widget] 版）：公式行用 TexFormula，纯文字行照旧。
  Widget _kvRow(String label, Widget value) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 96,
              child: Text(label, style: AppText.caption),
            ),
            Expanded(child: value),
          ],
        ),
      );

  String _f(double v) => formatPopulationNumber(v);

  String _pct(double v) => '${(v * 100).toStringAsFixed(1)}%';
}
