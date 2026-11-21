import 'dart:convert';

import 'package:flutter/material.dart';

import '../../engine/cross_engine.dart';
import '../../engine/utils.dart';
import '../../state/app_state.dart';
import '../../state/history_store.dart';
import '../../theme.dart';
import '../../ui/assistant_panel.dart';
import '../../ui/png_export.dart';
import '../../ui/step_card.dart';
import '../curriculum_page.dart';
import 'cross_tool_rail.dart';
import 'save_mistake_key_host.dart';
import 'save_to_mistake_book.dart';

/// 单基因杂交面的**考点常量**（v2.19.59）。
///
/// ⛔ 字面量**只有这一处定义**：既决定「存入错题本」写进 `subjectArea` 的
/// 考点，也决定「K 看这道题的套路卡」的判据（`cross_calculator_page.dart`
/// 的 `_currentTabTopic()` 引用本常量，K 宿主与屏上尾注共用同一判据）。
/// 两处各写一份字面量迟早分叉（B 仓 v2.19.249 教训）。
const String kMonoCrossSubjectArea = '分离定律';

/// 单基因杂交 + 测交/回交 + 修饰模型计算器。
/// 复用 CrossEngine：分离定律（Aa×Aa→3:1）、不完全显性、共显性、致死、
/// 测交（×隐性纯合）、回交（×亲本）。
class MonoCrossWidget extends StatefulWidget {
  const MonoCrossWidget({super.key, this.cardHint});

  /// v2.19.59：结果区副标题尾注（「 · 按 K 看这道题的套路卡」）。
  /// ⛔ 由容器页算好传进来（判据与 K 宿主同源），本组件不认识套路卡库；
  /// null = 这一面没有配套卡 ⇒ 原句逐字不变。
  final String? cardHint;

  /// v2.14 R5：fill 先于本 tab 挂载到达时的待填槽（页级 _flushFill 设置，
  /// initState 消费）——TabBarView 懒构建场景的双通道兜底。
  static ({String p1, String p2})? pendingFill;

  @override
  State<MonoCrossWidget> createState() => MonoCrossWidgetState();
}

/// 存进错题本时**记下这道题的亲本**（moduleId = 'cross_mono'）。
///
/// ⛔ 口径：只有**回程一定写得进去**的亲本才记。回程走
/// `cross_calculator_page.dart` 的 `_applyMonoFill`，它的判据是
/// `^[A-Za-z]{2}$`（两个亲本各 2 个字母）——本函数的判据必须与它
/// **逐字一致**，否则会记下一组 `fill` 会拒收的参数 ⇒ 错题本里出现一枚
/// 点下去必然弹「那一页现在过不去」的**死按钮**，比不记更糟。
/// ⛔ 因此这里比本页 `_calculate` 的「长度 == 2」更严：长度对但含非字母
/// （如 `1a`）本页算得出、回程填不进 ⇒ 不记。
Map<String, String>? _monoSrcParams(String p1, String p2) {
  final a = p1.trim();
  final b = p2.trim();
  final re = RegExp(r'^[A-Za-z]{2}$');
  if (!re.hasMatch(a) || !re.hasMatch(b)) return null;
  return {'p1': a, 'p2': b};
}

/// State 公开（v2.14 R5）：遗传计算器页用 GlobalKey 直达 fillFromAi
/// （讲题回放 ▷ 复现链路）。
class MonoCrossWidgetState extends State<MonoCrossWidget>
    with AutomaticKeepAliveClientMixin
    implements CrossTabSidePanel {
  @override
  bool get wantKeepAlive => true;

  /// 出厂默认题（判 `isPristine` 的锚点）。⛔ controller 初始化复用它，
  /// 不另写一份字面量——两份常量迟早分叉，那时守卫就成了摆设。
  static const _kDefaultP1 = 'Aa';
  static const _kDefaultP2 = 'Aa';

  final _p1Ctrl = TextEditingController(text: _kDefaultP1);
  final _p2Ctrl = TextEditingController(text: _kDefaultP2);
  final _domCtrl = TextEditingController(text: 'A');
  final _recCtrl = TextEditingController(text: 'a');
  Modification _mod = Modification.completeDominance;

  /// 这一栏现在**还是出厂状态吗**（没人动过）？
  ///
  /// 供 `ModuleFillTarget.canOverwrite` 用：学生自己在这一栏敲了题之后，
  /// 再从课标/拍题深链进来，**不该把他那道题无声顶掉**。
  ///
  /// 判据 = 两个亲本输入框都还等于出厂默认值。⛔ **不用 initState 快照**：
  /// keep-alive 存活的 State 与重建过的 State 会各拿一份快照，守卫就成了
  /// 薛定谔的。⚠️ 只比 `fillFromAi` 会写的这两框——本页签的显隐性字母
  /// （`_domCtrl`/`_recCtrl`）是**另外一套工具**，深链不写它们，不该由它们
  /// 拦下深链。
  bool get isPristine =>
      _p1Ctrl.text == _kDefaultP1 && _p2Ctrl.text == _kDefaultP2;

  final _engine = CrossEngine();
  CrossResult? _result;
  String? _error;
  // v2.19.56（照 v2.19.53 变异页「框+开关」先例）：算出那一刻的
  // 亲本|遗传模式 快照——_mod 是非文本开关、直接喂引擎，一并入快照；
  // Ctrl+S 组装 payload 时比对现文，改动过未重算则从题干/答案剔除
  // （⛔ 不存「题干新输入 + 答案旧结果」的矛盾题）。
  String? _monoSnap;
  String _lastMode = '杂交';
  // v2.13：数值结果截图边界与导出态。
  final _resultKey = GlobalKey();
  bool _exporting = false;

  @override
  void initState() {
    super.initState();
    final pf = MonoCrossWidget.pendingFill;
    if (pf != null) {
      MonoCrossWidget.pendingFill = null;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) fillFromAi(pf.p1, pf.p2);
      });
    }
  }

  /// v2.14 R5：拍题识别/讲题回放回填——填亲本 + 跑杂交。
  void fillFromAi(String p1, String p2) {
    _p1Ctrl.text = p1;
    _p2Ctrl.text = p2;
    _calculate(_mod);
  }

  /// 数值结果存为 PNG（学生发群问老师路径）。
  Future<void> _exportResult() async {
    setState(() => _exporting = true);
    final r = await captureBoundaryPng(_resultKey, '单基因计算');
    if (!mounted) return;
    setState(() => _exporting = false);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(r.path != null ? '已保存：${r.path}' : r.error ?? '导出失败'),
      duration: const Duration(seconds: 4),
    ));
  }

  static const _modNames = {
    Modification.completeDominance: '完全显性',
    Modification.incompleteDominance: '不完全显性',
    Modification.codominance: '共显性',
    Modification.lethalDominant: '致死（显性纯合 AA 致死）',
    Modification.lethalRecessive: '致死（隐性纯合 aa 致死）',
  };

  @override
  void dispose() {
    _p1Ctrl.dispose();
    _p2Ctrl.dispose();
    _domCtrl.dispose();
    _recCtrl.dispose();
    super.dispose();
  }

  void _calculate(Modification mod) {
    final p1 = _p1Ctrl.text.trim();
    final p2 = _p2Ctrl.text.trim();
    final dom = _domCtrl.text.trim();
    final rec = _recCtrl.text.trim();
    if (p1.length != 2 || p2.length != 2) {
      setState(() {
        _error = '单基因杂交请输入 2 字符基因型（如 Aa / aa / AA）。';
        _result = null;
      });
      return;
    }
    _lastMode = '杂交';
    setState(() {
      _mod = mod;
      _error = null;
      _result = _engine.singleGeneCross(
        p1,
        p2,
        dominant: dom,
        recessive: rec,
        modification: mod,
        dominantPhenotype: '显性($dom)',
        recessivePhenotype: '隐性($rec)',
      );
      // v2.19.56：亲本|遗传模式 '|' 拼快照（照变异页「框+开关」先例）。
      // v2.19.57 找茬 F2：dom/rec 字母**直接喂引擎**（singleGeneCross 的
      // dominant/recessive 参）⇒ 必须入快照——曾漏掉：改字母不重算时
      // 门比对全中照常入库，回程重算却按新字母出另一道题的答案。
      _monoSnap = '${_p1Ctrl.text.trim()}|${_p2Ctrl.text.trim()}|'
          '${_domCtrl.text.trim()}|${_recCtrl.text.trim()}|$_mod';
    });
    _report(p1, p2);
  }

  void _testcross() {
    final p1 = _p1Ctrl.text.trim();
    final dom = _domCtrl.text.trim();
    final rec = _recCtrl.text.trim();
    if (p1.length != 2) {
      setState(() {
        _error = '测交需先输入 F1 基因型（如 Aa）。';
        _result = null;
      });
      return;
    }
    _lastMode = '测交';
    setState(() {
      _error = null;
      _mod = Modification.completeDominance;
      _result = _engine.testcross(
        p1,
        dominant: dom,
        recessive: rec,
        dominantPhenotype: '显性($dom)',
        recessivePhenotype: '隐性($rec)',
      );
      // v2.19.57 找茬 F3：测交引擎只消费 p1（testcross 不读 p2）⇒ 快照
      // 不含 p2——否则改「亲本 2」不重算会被误拦（安全方向的过度剔除，
      // 但学生困惑）。dom/rec 照 F2 入快照。
      _monoSnap =
          '${_p1Ctrl.text.trim()}|${_domCtrl.text.trim()}|${_recCtrl.text.trim()}';
    });
    _report(p1, '$rec$rec');
  }

  void _report(String p1, String p2) {
    final r = _result;
    if (r == null) return;
    final counts = r.phenotypeRatios.map((e) => e.count).toList();
    final g = counts.fold<int>(0, (a, b) => a == 0 ? b : gcd(a, b));
    final ratioStr =
        g > 1 ? counts.map((c) => c ~/ g).join(':') : counts.join(':');
    // v2.13+ 老师走查 P0：单基因计算同步落盘讲题回放（与 9331/三对
    // recordHistory 同款链路；mono 是独立 widget 够不到页级 hook，
    // 直接写 HistoryStore）。v2.14 R5：detail 带结构化参数——回放卡
    // ▷ 点按可复现（跳计算器单基因 tab + 回填 + 即算）。
    HistoryStore.append(HistoryEntry(
      label: '$p1 × $p2 · 单基因$_lastMode · 表型 $ratioStr',
      epochMs: DateTime.now().millisecondsSinceEpoch,
      detail: jsonEncode({
        'm': 'cross_mono',
        'p1': p1,
        'p2': p2,
        'mode': _lastMode,
      }),
    ));
    final state = AppState.instance;
    state.report('交配方式', _lastMode);
    state.report('遗传模式', _modNames[_mod]!);
    state.report('双亲基因型', '$p1 × $p2');
    state.report('P1 配子', r.gametesP1.join('、'));
    state.report('P2 配子', r.gametesP2.join('、'));
    state.report('表型比', ratioStr);
    state.report(
        '基因型明细',
        r.genotypeRatios.map((e) => '${e.genotype}:${e.count}').join('  '));
  }

  // v2.19.56（照 v2.19.53 试点）：本节「新鲜度」门——结果存在且算出那
  // 一刻的输入快照与现拼一致才算数；改亲本**或只拨遗传模式**未重算 ⇒
  // 节 stale ⇒ 整节剔除（题干/答案/srcModule/srcParams 一并走）⇒ 全节
  // stale 时答案空串 ⇒ saveToMistakeBook 既有「先算出结果」守卫应答。
  // v2.19.57 找茬 F2/F3：公式与写点逐字同口径，且按 _lastMode 分两式——
  // 杂交吃 p1|p2|dom|rec|mod；测交引擎不吃 p2 ⇒ 快照式不含 p2。
  bool get _monoFresh {
    if (_result == null) return false;
    final snap = _lastMode == '测交'
        ? '${_p1Ctrl.text.trim()}|${_domCtrl.text.trim()}|${_recCtrl.text.trim()}'
        : '${_p1Ctrl.text.trim()}|${_p2Ctrl.text.trim()}|'
            '${_domCtrl.text.trim()}|${_recCtrl.text.trim()}|$_mod';
    return _monoSnap == snap;
  }

  /// v2.19.18 去主体化：输入面板（无壳）——宽屏注入 rail 顶部，窄屏
  /// 自渲染（同双基因 tab 模式）。
  @override
  Widget buildSidePanel(BuildContext context) {
    // v2.19.57 找茬 B1：宿主收编为 9331 容器页一枚页级宿主（按键按
    // _tab.index 分派到本 State 的 savePayload()）——本 widget 不再自挂
    // 宿主（原窄屏两枚同键各存一次、回执互相顶掉）。
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('设定亲本与遗传模式', style: AppText.sectionTitle),
        const SizedBox(height: 4),
        Text('一对等位基因（如 Aa / aa / AA），支持测交与修饰模型',
            style: AppText.caption.copyWith(color: AppColors.steel)),
        const SizedBox(height: 12),
        _buildInputArea(),
      ],
    );
  }

  /// v2.19.57 找茬 F4：存题/面板的**引擎真实**第二亲本——测交引擎内部拿
  /// '$rec$rec' 当另一方（⛔ 不读「亲本 2」框），存进错题本的题干与
  /// srcParams 必须记这笔真实账：回程 `fillFromAi → _calculate` 是杂交
  /// 重算，p2 记错框就会复现出另一道题。两个入口（按钮/页级 Ctrl+S）
  /// 同走本口径。
  String get _saveP2 => _lastMode == '测交'
      ? '${_recCtrl.text.trim()}${_recCtrl.text.trim()}'
      : _p2Ctrl.text.trim();

  /// v2.19.57：9331 页级宿主的分派入口——按下 Ctrl+S 那一刻现读现拼
  /// （⛔ 不用 build 期预取：「改了输入未重算」时预取非空会穿过 _monoFresh
  /// 门）。与结果面板那枚按钮同口径（同源 _result/_monoFresh/_saveP2）。
  SavePayload? savePayload() {
    final fresh = _monoFresh;
    final r = fresh ? _result : null;
    final counts = r?.phenotypeRatios.map((e) => e.count).toList();
    final g = counts == null || counts.isEmpty
        ? 0
        : counts.fold<int>(0, (a, b) => a == 0 ? b : gcd(a, b));
    final ratioStr = counts == null
        ? ''
        : (g > 1 ? counts.map((c) => c ~/ g).join(':') : counts.join(':'));
    final genRatio = r == null
        ? ''
        : r.genotypeRatios.map((e) => '${e.genotype}:${e.count}').join('  ');
    final saveP2 = _saveP2;
    return SavePayload(
      stem: fresh
          ? '${_p1Ctrl.text.trim()} × $saveP2 杂交，后代表型比和基因型比分别是？'
          : '',
      correctAnswer: r == null ? '' : '表型比 $ratioStr；基因型 $genRatio',
      subjectArea: kMonoCrossSubjectArea,
      srcModule: fresh ? 'cross_mono' : null,
      srcParams: fresh ? _monoSrcParams(_p1Ctrl.text, saveP2) : null,
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // AutomaticKeepAliveClientMixin 要求
    final r = _result;
    final wide = MediaQuery.of(context).size.width >= 1200;
    // v2.19.36 正向「课标 X」可点徽章：结果区标题行 trailing。code 由
    // `curriculumReverseBadgeFor` 从 `cross_mono` 唯一命中反查（3.2.3 的
    // 「分离」那半边）⛔ 本页不建表；⛔ 空态不挂（那一栏还没算出题）；helper
    // 返 null（多义/未被点名）时回落原来那枚 AppChip —— 逐像素同旧。
    final badge =
        r == null ? null : curriculumReverseBadgeFor(context, 'cross_mono');
    final modChip =
        r == null ? null : AppChip(_modNames[_mod]!, icon: Icons.auto_awesome);
    // v2.19.57 找茬 B1：宿主收编为容器页一枚页级宿主（见 buildSidePanel
    // 头注）——本 build 不再自挂宿主。
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
                FlatSection(
                  title: '计算结果',
                  subtitle: r == null
                      ? '设定亲本后点「计算比例」，这里展开配子与基因型/表型比例'
                      : '配子 · 表型/基因型比例${widget.cardHint ?? ''}',
                  trailing: badge == null
                      ? modChip
                      : Wrap(
                          spacing: 10,
                          alignment: WrapAlignment.end,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [badge, modChip!],
                        ),
                  child: _buildResultBody(),
                ),
              ],
            ),
          ),
        ),
    );
  }

  Widget _buildInputArea() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: TextField(
                controller: _p1Ctrl,
                style: AppText.genotype,
                decoration: const InputDecoration(labelText: '亲本 1'),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 16, left: 8, right: 8),
              child: Icon(Icons.close, size: 18, color: AppColors.steel),
            ),
            Expanded(
              child: TextField(
                controller: _p2Ctrl,
                style: AppText.genotype,
                decoration: const InputDecoration(labelText: '亲本 2'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _domCtrl,
                style: AppText.genotype,
                decoration: const InputDecoration(labelText: '显性等位基因'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                controller: _recCtrl,
                style: AppText.genotype,
                decoration: const InputDecoration(labelText: '隐性等位基因'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        // v2.19.18：isExpanded——rail 窄内容宽下选中文字省略号防溢出。
        DropdownButtonFormField<Modification>(
          initialValue: _mod,
          isExpanded: true,
          decoration: const InputDecoration(labelText: '遗传模式'),
          items: _modNames.entries
              .map((e) => DropdownMenuItem(value: e.key, child: Text(e.value)))
              .toList(),
          onChanged: (m) {
            if (m != null) _calculate(m);
          },
        ),
        const SizedBox(height: 10),
        // v2.8 高考高频预设 chips（白板免键盘：教鞭点一下直接开算）
        Wrap(spacing: 8, runSpacing: 4, children: [
          for (final p in const [
            ('杂合自交 3:1', 'Aa', 'Aa', Modification.completeDominance),
            ('测交 1:1', 'Aa', 'aa', Modification.completeDominance),
            ('纯合杂交 F1 全显性', 'AA', 'aa', Modification.completeDominance),
            ('显性纯合致死 2:1', 'Aa', 'Aa', Modification.lethalDominant),
            ('不完全显性 1:2:1', 'Aa', 'Aa', Modification.incompleteDominance),
          ])
            ActionChip(
              label: Text(p.$1),
              onPressed: () {
                _p1Ctrl.text = p.$2;
                _p2Ctrl.text = p.$3;
                _calculate(p.$4);
              },
            ),
        ]),
        const SizedBox(height: 16),
        // v2.19.18：Wrap——同双基因，兼容 rail 窄内容宽。
        Wrap(
          spacing: 12,
          runSpacing: 8,
          children: [
            FilledButton.icon(
              onPressed: () => _calculate(_mod),
              icon: const Icon(Icons.calculate_outlined),
              label: const Text('杂交'),
            ),
            OutlinedButton.icon(
              onPressed: _testcross,
              icon: const Icon(Icons.fitness_center),
              label: const Text('测交(×隐性纯合)'),
            ),
            OutlinedButton.icon(
              onPressed: () => showAiAssistant(context),
              icon: const Icon(Icons.psychology_outlined),
              label: const Text('AI 解析'),
            ),
          ],
        ),
      ],
    );
  }

  /// v2.19.18 结果区内容体（无 StepCard 壳）。
  Widget _buildResultBody() {
    final r = _result;
    if (r == null) {
      return _error != null
          ? _ErrorBanner(message: _error!)
          : Padding(
              padding: const EdgeInsets.symmetric(vertical: 18),
              child: Column(
                children: [
                  Icon(Icons.calculate_outlined,
                      size: 32,
                      color: AppColors.steel.withValues(alpha: 0.45)),
                  const SizedBox(height: 10),
                  Text('等待计算：结果将在这里展开',
                      style: AppText.body.copyWith(color: AppColors.steel)),
                ],
              ),
            );
    }
    // v2.13 学生走查：数值结果挂 RepaintBoundary + 「存为图片」——
    // 「截图发群问老师」此前单基因 tab 完全无法导出。
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        RepaintBoundary(
          key: _resultKey,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.canvas,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.border),
            ),
            child: _MonoResultPanel(
                result: r,
                // v2.19.57 找茬 F4：面板存题口径用引擎真实的第二亲本
                // （测交 = rec+rec），与页级 Ctrl+S 的 savePayload 同链。
                p1: _p1Ctrl.text.trim(),
                p2: _saveP2),
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

/// 单基因计算结果内容（StepCard 内部，无自身卡片外壳）。
class _MonoResultPanel extends StatelessWidget {
  final CrossResult result;
  final String p1;
  final String p2;
  // p1/p2 评审改 required（v2.13）：旧默认值 'Aa' 会让未来漏传的挂载点
  // 静默写错题干进错题本——编译期报错优于脏数据。
  const _MonoResultPanel({required this.result, required this.p1, required this.p2});

  @override
  Widget build(BuildContext context) {
    final counts = result.phenotypeRatios.map((e) => e.count).toList();
    final g = counts.fold<int>(0, (a, b) => a == 0 ? b : gcd(a, b));
    final ratioStr =
        g > 1 ? counts.map((c) => c ~/ g).join(':') : counts.join(':');
    final genRatio = result.genotypeRatios
        .map((e) => '${e.genotype}:${e.count}')
        .join('  ');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // v2.13：算完一键收藏进错题本（与 9331/三对面板同款入口）。
        Align(
          alignment: Alignment.centerRight,
          child: SaveToMistakeBookButton(
            stem: '$p1 × $p2 杂交，后代表型比和基因型比分别是？',
            correctAnswer: '表型比 $ratioStr；基因型 $genRatio',
            subjectArea: kMonoCrossSubjectArea,
            srcModule: 'cross_mono',
            // 本 widget 拿不到 controller，用它构造时传入的 p1/p2（与题干
            // 同一个来源 ⇒ 记下的亲本与屏上题干逐字一致）。
            srcParams: _monoSrcParams(p1, p2),
          ),
        ),
        _kv('P1 配子', result.gametesP1.join('  ')),
        _kv('P2 配子', result.gametesP2.join('  ')),
        Divider(height: 24, color: AppColors.border.withValues(alpha: 0.6)),
        Text('表型数量比', style: AppText.label),
        const SizedBox(height: 2),
        Text(ratioStr, style: AppText.monoFigure),
        const SizedBox(height: 12),
        for (final e in result.phenotypeRatios) ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: AppColors.canvas,
              borderRadius: BorderRadius.circular(10),
              border:
                  Border.all(color: AppColors.border.withValues(alpha: 0.5)),
            ),
            child: Row(
              children: [
                Expanded(child: Text(e.phenotype, style: AppText.body)),
                Text('${e.count} 份',
                    style: AppText.caption.copyWith(color: AppColors.steel)),
                const SizedBox(width: 10),
                RatioPill(text: '${e.count}'),
              ],
            ),
          ),
          const SizedBox(height: 8),
        ],
        Divider(height: 24, color: AppColors.border.withValues(alpha: 0.6)),
        _kv('基因型比例', genRatio),
      ],
    );
  }

  Widget _kv(String k, String v) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(width: 110, child: Text(k, style: AppText.caption)),
            Expanded(child: Text(v, style: AppText.monoSmall)),
          ],
        ),
      );
}
