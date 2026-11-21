// linkage_tab.dart —— 连锁与互换 Tab（遗传计算器第 5 页）
//
// 两对基因位于同一对同源染色体上，减数分裂可发生交叉互换。
// 教学要点：亲本型配子多、重组型配子少，交换值 r = 重组型配子占比。
// 视觉遵循 docs/ARCHITECTURE.md 的设计约定：基因型/比例/概率一律等宽字体，结果区用 border-top 分隔。

import 'dart:convert';

import 'package:flutter/material.dart';

import '../../engine/linkage_engine.dart';
import '../../state/app_state.dart';
import '../../state/history_store.dart';
import '../../theme.dart';
import '../../ui/png_export.dart';
import '../../ui/step_card.dart';
import '../curriculum_page.dart';
import 'cross_tool_rail.dart';
import 'linkage_crossover_diagram.dart';
import 'linkage_widgets.dart';

class LinkageTab extends StatefulWidget {
  const LinkageTab({super.key});

  /// v2.15：fill 先于本 tab 挂载到达时的待填槽（页级 _flushFill 设置，
  /// initState 消费）——讲题回放 ▷ 复现的懒构建兜底。
  static ({String p1, String p2, String r})? pendingFill;

  @override
  State<LinkageTab> createState() => LinkageTabState();
}

/// State 公开（v2.15）：遗传计算器页用 GlobalKey 直达 fillFromAi。
class LinkageTabState extends State<LinkageTab>
    with AutomaticKeepAliveClientMixin
    implements CrossTabSidePanel {
  final _engine = LinkageEngine();

  /// 出厂默认题（判 `isPristine` 的锚点）。⛔ controller 初始化复用它。
  static const _kDefaultP1 = 'AB/ab';
  static const _kDefaultP2 = 'ab/ab';
  static const _kDefaultR = '20%';

  final _p1Ctrl = TextEditingController(text: _kDefaultP1);
  final _p2Ctrl = TextEditingController(text: _kDefaultP2);
  final _rCtrl = TextEditingController(text: _kDefaultR);

  /// 这一栏现在**还是出厂状态吗**（没人动过）？
  ///
  /// 供 `ModuleFillTarget.canOverwrite` 用：学生在这一栏敲过题之后，再从
  /// 课标/拍题深链进来，**不该把他那道题无声顶掉**。判据 = **三样**都还等于
  /// 出厂默认值——`fillFromAi` 写的就是 p1/p2/**r** 三个框，交换值被顶掉
  /// 同样是改了他的题。⛔ 不用 initState 快照。
  bool get isPristine =>
      _p1Ctrl.text == _kDefaultP1 &&
      _p2Ctrl.text == _kDefaultP2 &&
      _rCtrl.text == _kDefaultR;

  LinkageResult? _result;
  String? _error;
  // v2.13：数值结果截图边界与导出态（与 mono 样板同模式）。
  final _resultKey = GlobalKey();
  bool _exporting = false;

  @override
  void initState() {
    super.initState();
    final pf = LinkageTab.pendingFill;
    if (pf != null) {
      LinkageTab.pendingFill = null;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) fillFromAi(pf.p1, pf.p2, pf.r);
      });
    }
  }

  /// v2.15：拍题识别/讲题回放回填——p1/p2 为连锁基因型（AB/ab），
  /// r 为交换值（'20%' 或 '20'，引擎自解析）。
  void fillFromAi(String p1, String p2, String r) {
    _p1Ctrl.text = p1;
    _p2Ctrl.text = p2;
    _rCtrl.text = r;
    _compute();
  }

  /// 数值结果存为 PNG（学生发群问老师路径）。
  Future<void> _exportResult() async {
    setState(() => _exporting = true);
    final r = await captureBoundaryPng(_resultKey, '连锁互换计算');
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
    _rCtrl.dispose();
    super.dispose();
  }

  void _compute() {
    try {
      final r = _engine.cross(_p1Ctrl.text, _p2Ctrl.text, _rCtrl.text);
      setState(() {
        _result = r;
        _error = null;
      });
      AppState.instance.report(
          '连锁杂交', '${r.parent1.label} × ${r.parent2.label}，交换值 ${r.recombination}');
      AppState.instance.report(
          '子代表型比', r.phenotypeRatio.join(' : '));
      // v2.14 R5 讲题回放补齐：连锁互换落盘。v2.15：detail 带结构化
      // 参数——回放卡 ▷ 点按可复现（跳本 tab 回填 + 即算）。
      HistoryStore.append(HistoryEntry(
        label: '${r.parent1.label} × ${r.parent2.label} · 连锁互换 · 交换值 ${r.recombination}',
        epochMs: DateTime.now().millisecondsSinceEpoch,
        detail: jsonEncode({
          'm': 'cross_linkage',
          'p1': r.parent1.label,
          'p2': r.parent2.label,
          // Fraction 不可直接 JSON 序列化；toString 得 'n/d' 形式，
          // parseRecombination 可再解析（'1/5' ∈ 支持格式）。
          'r': r.recombination.toString(),
        }),
      ));
    } on ArgumentError catch (e) {
      setState(() {
        _result = null;
        _error = e.message?.toString() ?? '输入格式错误';
      });
    }
  }

  void _applyPreset(
      ({String name, String p1, String p2, String r, String note}) p) {
    _p1Ctrl.text = p.p1;
    _p2Ctrl.text = p.p2;
    _rCtrl.text = p.r;
    _compute();
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
            const AppChip('连锁互换', icon: Icons.link),
            const SizedBox(width: 8),
            Expanded(
              child: Text('两位点记作 AB/ab，交换值 = 重组型配子占比',
                  style: AppText.caption),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Text('设定亲本与交换值', style: AppText.sectionTitle),
        const SizedBox(height: 4),
        Text('也可从下方经典案例一键载入',
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
                  hintText: '如 AB/ab',
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
                  hintText: '如 ab/ab（测交）',
                ),
                onSubmitted: (_) => _compute(),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        TextField(
          controller: _rCtrl,
          style: AppText.genotype,
          decoration: const InputDecoration(
            labelText: '交换值 r',
            hintText: '0.2 / 20% / 1/5，范围 0–50%',
          ),
          onSubmitted: (_) => _compute(),
        ),
        const SizedBox(height: 14),
        FilledButton.icon(
          onPressed: _compute,
          icon: const Icon(Icons.calculate_outlined),
          label: const Text('计算子代'),
        ),
        // v2.19.23 找茬 P1#2：错误展示移到下方结果区（body 恒渲染）——
        // 宽屏时本面板注入 rail，tab 内部 setState 不重建 rail 副本，
        // 错误放这里会「点了没反应」。
        const SizedBox(height: 14),
        Text('经典案例', style: AppText.caption),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final p in linkagePresets)
              LinkagePresetChip(preset: p, onTap: () => _applyPreset(p)),
          ],
        ),
      ],
    );
  }

  /// v2.19.40 ⛔⛔ 闸门**改成直接给数据**：返回 [CrossoverFigure]（= 这笔
  /// 结果上这张图**画得出来**），返回 null（= 不挂这张图）。
  ///
  /// ### 为什么判据必须从「软件实际算出来的东西」派生
  ///
  /// 图是**数据驱动**的（[CrossoverFigure] 自己从两条亲本单倍型推出
  /// 「哪条参与了交换」），所以宿主**不再**需要替图挡住「顺式还是反式」：
  /// `Ab/aB` 时图上「交换前」两对相同、「交换后」变掉的两行正好是 `AB` 与
  /// `ab`，与顺式讲的是同一件事 ⇒ 旧版那条写死的「必须恰好是 {AB,ab} / {Ab,aB}」
  /// 整条消失，本文件的判据只剩下面五条。
  ///
  /// ⛔ **不许读输入框文本**：改了不点计算时屏上仍是旧结果，图必须跟着屏上
  /// **正在显示**的那笔结果走。
  CrossoverFigure? get _crossoverFigure {
    final res = _result;
    // ① 还没算过：图上每一行都要对应一个**真实算出来的**配子（「1a 交换前
    //    是什么」这类断言在没有结果时是无源之水），且未算态屏上只有
    //    「等待计算：结果将在这里展开」那一句。
    if (res == null) return null;
    // ② `r = 0` 必须**显式**判：那时重组型概率为 0、被
    //    `out.removeWhere(isZero)`（engine:174）删掉了，⛔ 那次交换根本没发生，
    //    画一张讲「参与了交换」的图就是教一件不存在的事。
    //    `Fraction` 的分母恒为正（fraction.dart:26），故 `numerator <= 0`
    //    与「值 ≤ 0」等价（`parseRecombination` 已把负值挡在门外，这里是第二道）。
    if (res.recombination.numerator <= 0) return null;
    // ③ 一次减数分裂里**只有 4 条染色单体**（同源染色体 2 条 × 姐妹染色单体
    //    2 条）⇒ 图上恒为 4 行两块。因此需要 `gametesP1` **恰好 4 个键**：
    //    · 三位点出 6 个键（2 亲本 + 2 区间 × 2，engine:164-172）⇒ 挡。
    //      ⚠️ 那 6 个键是**不同减数分裂里各自可能出现的 6 种配子**
    //      （教学口径「只算一次互换」），**不是同一次减数分裂里的 6 条
    //      染色单体**：第 1 区间与第 2 区间的交换发生在不同的减数分裂里，
    //      各自的「交换前」形态不同 ⇒ 画成上下两块各 6 行就是教一件不存在的
    //      事（一次减数分裂里没有第 3 条同源染色单体）。**这是硬停，不是省事。**
    //    · 键碰撞（`AB/AB`、`ab/ab`、`Ab/ab` 这类两条染色体在某个位点上等位
    //      基因相同，`gametesOf` 的重组键会与亲本键合并）出 2–3 个键 ⇒ 挡。
    final g = res.gametesP1;
    if (g.length != 4) return null;
    // ④ 「头两条是亲本型」这件事本身必须**成立**：`r = 1/2` 时四个值全相等
    //    （自由组合等价），「谁是亲本型」无定义，这张按「哪两条没参与交换」
    //    讲因果的图不该在这种题上出现。⚠️ 只能用 `compareTo`：`Fraction`
    //    只实现了 `Comparable`（fraction.dart:85），**没有 `operator >`**。
    //    且要求**严格**大于——相等即放行不得。
    //    （`gametesOf` 给每种配子的概率是**亲本型各 (1-r)/2、重组型各 r/2**
    //    ⇒ 只要 `r < 1/2`，概率高的那两条就是亲本型。）
    final s = g.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    if (s[0].value.compareTo(s[2].value) <= 0) return null;
    // ⑤ 头两条**就是 `parent1` 的那两条单倍型**。⚠️ 头两条概率相等、排序
    //    后先后不定 ⇒ 必须按**集合**比，不能按下标逐个比（那会随机地一次对
    //    一次错）。⚠️ 用 `contains` 而不是 `==`/`equals`：`Set` 在 Dart 里是
    //    **恒等相等**（不像 List/Map 走内容比较），写成 `top == {...}` 恒
    //    false、图**永远不会**出现（假红的另一种形态）。
    //    `g` 是 Map ⇒ 键互不相同 ⇒ 命中 hap1/hap2 就一定是两条不同的。
    //    这一条顺带把「反式」也放行了：`Ab/aB` 的头两条正是 `Ab`/`aB`。
    final top = s.take(2).map((e) => e.key).toSet();
    final hap = res.parent1;
    if (!top.contains(hap.hap1) || !top.contains(hap.hap2)) return null;
    // ⇒ 数据齐了。图自己会去推导「哪两条参与了交换」。
    return CrossoverFigure(
      hap1: hap.hap1,
      hap2: hap.hap2,
      afterGametes: s.map((e) => e.key).toList(),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final wide = MediaQuery.of(context).size.width >= 1200;
    // v2.19.36 正向「课标 X」可点徽章：结果区标题行 trailing。3.3.4 的
    // `tool` 逐字写着「连锁互换」⇒ `cross_linkage` 唯一反查 3.3.4，code 由
    // `curriculumReverseBadgeFor` 现算（⛔ 本页不建表、禁 const）。
    // ⛔ 空态不挂；helper 返 null 时回落原来那行交换值（逐像素同旧）。
    final badge = _result == null
        ? null
        : curriculumReverseBadgeFor(context, 'cross_linkage');
    final swapText = _result == null
        ? null
        : Text(
            '交换值 ${_result!.recombination}（${_result!.recombination.toPercent()}）',
            style: AppText.monoSmall.copyWith(color: AppColors.steel),
          );
    // v2.19.40：闸门直接给数据（null = 这笔结果上不挂这张图）。
    final crossoverFigure = _crossoverFigure;
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
      children: [
        if (!wide) buildSidePanel(context),
        if (!wide) const SizedBox(height: 28),

        // 第 2 步：结果区（v2.19.18 去壳平铺）
        FlatSection(
          title: '计算结果',
          subtitle: _result == null
              ? '设定亲本与交换值后点「计算子代」，这里展开配子分布与表型比'
              : null,
          trailing: badge == null
              ? swapText
              : Wrap(
                  spacing: 10,
                  alignment: WrapAlignment.end,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [badge, swapText!],
                ),
          // v2.19.23 找茬 P1#2：错误优先展示在结果区（同方法对比 tab）。
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
                    child: Text('等待计算：结果将在这里展开',
                        style: AppText.body.copyWith(color: AppColors.steel)),
                  ),
                )
              : Column(
                  // v2.13：配子分布 + 子代表型 整体挂 RepaintBoundary，
                  // 内部子表/子卡自带的装饰不再叠 canvas 底。
                  children: [
                    RepaintBoundary(
                      key: _resultKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('配子分布', style: AppText.label),
                          const SizedBox(height: 8),
                          LinkageGameteTable(result: _result!),
                          const SizedBox(height: 14),
                          Text('子代表型', style: AppText.label),
                          const SizedBox(height: 8),
                          LinkagePhenotypeCard(result: _result!),
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
        // ── 连锁互换概念示意图（v2.19.40）────────────────────────
        //
        // 位置是 `FlatSection` 的**兄弟**、排在它**之后**，⛔ 三条理由不许挪：
        // ① 它在 `RepaintBoundary(key: _resultKey)`（结果区那个）**之外**
        //    ⇒ 学生点「存为图片」导出的 PNG **不会**把这张概念图卷进去
        //    （`_exportResult` 走 `captureBoundaryPng(_resultKey, ...)`，
        //    `png_export.dart` 只对那一个 boundary 调 `toImage()`）。
        // ② 它不是 `FlatSection` 的子节点 ⇒ 位置本身**不**受「算出结果才展开」
        //    那套结构支配；是否上屏只由 [_crossoverFigure] 一个闸门说。
        // ③ `LinkageTab` 是 9331 容器页的第 6 个页签，而全量扫描基线
        //    （`test/goldens/light_scan_*` / `dark_scan_*`）只停在默认的第 1 个
        //    页签 ⇒ 既有基线不会因这张图变红。
        //
        // ⚠️ 屏上文案三条硬规矩：⛔ 不印 markdown 星号；⛔ 不用方向词
        // （「上面/下面/左侧/右侧」）——「交换前」「交换后」是**点名状态**
        // 所以能用，位置词一律不用；⛔ 不印任何数字/百分比（比例是**算出来**
        // 的东西，由结果区的依据行负责）。
        //
        // 宽度：组件内部已是 `SizedBox(width: double.infinity)` +
        // `AspectRatio(320/367)` ⇒ ⛔ 外面不许再套任何固定宽度。
        if (crossoverFigure != null) ...[
          const SizedBox(height: 24),
          Text('重组型是怎么来的', style: AppText.label),
          const SizedBox(height: 10),
          LinkageCrossoverDiagram(figure: crossoverFigure),
        ],
      ],
    );
  }
}
