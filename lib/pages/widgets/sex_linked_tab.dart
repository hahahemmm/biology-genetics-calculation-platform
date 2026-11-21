// sex_linked_tab.dart —— 伴性遗传 Tab（遗传计算器第 3 页）
//
// 伴 X 遗传：母亲基因型 × 父亲基因型 → 子代按性别拆分的精确概率。
// 教学要点：交叉遗传、半合子雄性由唯一 X 决定表型。
// 视觉遵循 docs/ARCHITECTURE.md 的设计约定：基因型/概率一律等宽字体，结果区用 border-top 分隔。

import 'dart:convert';

import 'package:flutter/material.dart';

import '../../engine/fraction.dart';
import '../../engine/sex_linked_engine.dart';
import '../../state/app_state.dart';
import '../../state/history_store.dart';
import '../../theme.dart';
import '../../ui/png_export.dart';
import '../../ui/step_card.dart';
import '../curriculum_page.dart';
import 'cross_tool_rail.dart';
import 'save_mistake_key_host.dart';
import 'save_to_mistake_book.dart';
import 'sex_linked_punnett_diagram.dart'; // v2.19.40 伴性概念示意图（方格图）

/// 伴性遗传面的**考点常量**（v2.19.59）。
///
/// ⛔ 字面量**只有这一处定义**：既决定「存入错题本」写进 `subjectArea` 的
/// 考点，也决定「K 看这道题的套路卡」的判据（`cross_calculator_page.dart`
/// 的 `_currentTabTopic()` 引用本常量）。
const String kSexLinkedSubjectArea = '伴性遗传';

/// 存进错题本时**记下这道题的亲本**（moduleId = 'cross_sex_linked'，
/// `p1` = 母本 / `p2` = 父本，回填落 `_femaleCtrl` / `_maleCtrl`）。
///
/// ⛔ 口径：用**引擎自己的解析器**当判据（`SexLinkedEngine.parseGenotype`）
/// ——回程走 `cross_calculator_page.dart` 的 `_applySexFill`，它要的就是
/// 「两个都是引擎认得的伴性基因型」。解析不过就不记 ⇒ 错题本里不会出现
/// 一枚点下去必然弹「那一页现在过不去」的**死按钮**（宁可没有）。
Map<String, String>? _sexLinkedSrcParams(String p1, String p2) {
  final a = p1.trim();
  final b = p2.trim();
  try {
    SexLinkedEngine.parseGenotype(a, expectFemale: true);
    SexLinkedEngine.parseGenotype(b, expectFemale: false);
  } on ArgumentError {
    return null;
  }
  return {'p1': a, 'p2': b};
}

class SexLinkedTab extends StatefulWidget {
  const SexLinkedTab({super.key, this.cardHint});

  /// v2.19.59：结果区副标题尾注（「 · 按 K 看这道题的套路卡」）。
  /// ⛔ 由容器页算好传进来（判据与 K 宿主同源），本组件不认识套路卡库；
  /// null = 这一面没有配套卡 ⇒ 原句逐字不变。
  final String? cardHint;

  /// v2.14 R5：fill 先于本 tab 挂载到达时的待填槽（页级 _flushFill 设置，
  /// initState 消费）——TabBarView 懒构建场景的双通道兜底。
  static ({String p1, String p2})? pendingFill;

  @override
  State<SexLinkedTab> createState() => SexLinkedTabState();
}

/// State 公开（v2.14 R5）：遗传计算器页用 GlobalKey 直达 fillFromAi
/// （讲题回放 ▷ 复现链路）。
class SexLinkedTabState extends State<SexLinkedTab>
    with AutomaticKeepAliveClientMixin
    implements CrossTabSidePanel {
  final _engine = SexLinkedEngine();

  /// 出厂默认题（判 `isPristine` 的锚点）。⛔ controller 初始化复用它。
  static const _kDefaultFemale = 'XAXa';
  static const _kDefaultMale = 'XAY';

  final _femaleCtrl = TextEditingController(text: _kDefaultFemale);
  final _maleCtrl = TextEditingController(text: _kDefaultMale);

  /// 这一栏现在**还是出厂状态吗**（没人动过）？
  ///
  /// 供 `ModuleFillTarget.canOverwrite` 用：学生在这一栏敲过题之后，再从
  /// 课标/拍题深链进来，**不该把他那道题无声顶掉**。判据 = 两个输入框都还
  /// 等于出厂默认值。⛔ 不用 initState 快照；⚠️ 不看「有没有算过」——
  /// 出厂态本就不会自动算（initState 只消费 `pendingSex`），拿「有没有结果」
  /// 当判据会把「敲了题还没点计算」错判成 dirty 之外的情形。
  bool get isPristine =>
      _femaleCtrl.text == _kDefaultFemale && _maleCtrl.text == _kDefaultMale;

  SexLinkedResult? _result;
  String? _error;
  // v2.19.56（照 v2.19.53 分子/变异试点）：算出那一刻的母本|父本输入
  // 快照。Ctrl+S 组装 payload 时比对现文——改动过未重算则从题干/答案
  // 剔除（⛔ 不存「题干新输入 + 答案旧结果」的矛盾题）。
  String? _sexSnap;
  // v2.13：数值结果截图边界与导出态（与 mono 样板同模式）。
  final _resultKey = GlobalKey();
  bool _exporting = false;

  @override
  void initState() {
    super.initState();
    final pf = SexLinkedTab.pendingFill;
    if (pf != null) {
      SexLinkedTab.pendingFill = null;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) fillFromAi(pf.p1, pf.p2);
      });
    }
  }

  /// v2.14 R5：拍题识别/讲题回放回填——p1=母本、p2=父本，填完即算。
  void fillFromAi(String p1, String p2) {
    _femaleCtrl.text = p1;
    _maleCtrl.text = p2;
    _compute();
  }

  /// 数值结果存为 PNG（学生发群问老师路径）。
  Future<void> _exportResult() async {
    setState(() => _exporting = true);
    final r = await captureBoundaryPng(_resultKey, '伴性遗传计算');
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
    _femaleCtrl.dispose();
    _maleCtrl.dispose();
    super.dispose();
  }

  void _compute() {
    try {
      final r = _engine.cross(_femaleCtrl.text, _maleCtrl.text);
      setState(() {
        _result = r;
        _error = null;
        // v2.19.56：算出即存母本|父本输入快照（stale 门的基准）。
        _sexSnap = '${_femaleCtrl.text.trim()}|${_maleCtrl.text.trim()}';
      });
      AppState.instance.report('伴性杂交',
          '♀ ${r.femaleParent} × ♂ ${r.maleParent}');
      final daughters = r.phenotypeGivenSex('雌性');
      final sons = r.phenotypeGivenSex('雄性');
      AppState.instance.report(
          '女儿表型', daughters.entries.map((e) => '${e.key} ${e.value}').join('，'));
      AppState.instance.report(
          '儿子表型', sons.entries.map((e) => '${e.key} ${e.value}').join('，'));
      // v2.14 R5 讲题回放补齐：伴性计算落盘（▷ 可复现——detail 带
      // 双亲基因型，回放卡点按跳本 tab 回填即算）。
      HistoryStore.append(HistoryEntry(
        label: '♀${r.femaleParent} × ♂${r.maleParent} · 伴性遗传',
        epochMs: DateTime.now().millisecondsSinceEpoch,
        detail: jsonEncode({
          'm': 'cross_sex_linked',
          'p1': r.femaleParent,
          'p2': r.maleParent,
        }),
      ));
    } on ArgumentError catch (e) {
      setState(() {
        _result = null;
        _error = e.message?.toString() ?? '基因型格式错误';
      });
    }
  }

  void _applyPreset(
      ({String name, String female, String male, String note}) p) {
    _femaleCtrl.text = p.female;
    _maleCtrl.text = p.male;
    _compute();
  }

  // v2.19.56（照 v2.19.53 试点）：本节「新鲜度」门——结果存在且算出那
  // 一刻的母本|父本快照与现文一致才算数；改亲本未重算 ⇒ 节 stale ⇒
  // 整节剔除（题干/答案/srcModule/srcParams 一并走）⇒ 全节 stale 时答案
  // 空串 ⇒ saveToMistakeBook 既有「先算出结果」守卫应答。
  bool get _sexFresh =>
      _result != null &&
      _sexSnap ==
          '${_femaleCtrl.text.trim()}|${_maleCtrl.text.trim()}';

  /// v2.19.57：9331 页级宿主的分派入口——按下 Ctrl+S 那一刻现读现拼
  /// （⛔ 不用 build 期预取：「改了输入未重算」时预取非空会穿过 _sexFresh
  /// 门）。与结果面板那枚按钮同口径。
  SavePayload? savePayload() {
    final fresh = _sexFresh;
    final cur = fresh ? _result : null;
    return SavePayload(
      stem: fresh
          ? '♀${_femaleCtrl.text.trim()} × ♂${_maleCtrl.text.trim()} 伴性遗传，'
              '求子代基因型与表型分布（按性别看条件概率）'
          : '',
      correctAnswer: cur == null
          ? ''
          : '女儿表型：${cur.phenotypeGivenSex('雌性').entries.map((e) => '${e.key} ${e.value}').join('，')}；'
              '儿子表型：${cur.phenotypeGivenSex('雄性').entries.map((e) => '${e.key} ${e.value}').join('，')}',
      subjectArea: kSexLinkedSubjectArea,
      srcModule: fresh ? 'cross_sex_linked' : null,
      srcParams: fresh
          ? _sexLinkedSrcParams(_femaleCtrl.text, _maleCtrl.text)
          : null,
    );
  }

  /// v2.19.18 去主体化：输入面板（无壳，含页首说明）——宽屏注入 rail
  /// 顶部，窄屏自渲染。
  @override
  Widget buildSidePanel(BuildContext context) {
    // v2.19.57 找茬 B1：宿主收编为 9331 容器页一枚页级宿主（按键按
    // _tab.index 分派到本 State 的 savePayload()）——本 widget 不再自挂
    // 宿主（原两枚同键各存一次、回执互相顶掉）。
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const AppChip('伴 X 遗传', icon: Icons.transgender),
            const SizedBox(width: 8),
            Expanded(
              child: Text('Y 染色体上无对应等位基因，雄性为半合子',
                  style: AppText.caption),
            ),
          ],
        ),
        const SizedBox(height: 12),
          Text('设定亲本基因型', style: AppText.sectionTitle),
          const SizedBox(height: 4),
          Text('母亲 ♀ × 父亲 ♂（如 XAXa × XAY）',
              style: AppText.caption.copyWith(color: AppColors.steel)),
          const SizedBox(height: 12),
          _buildInputArea(),
        ],
      );
  }

  /// v2.19.40：伴性遗传概念示意图的数据（返回 null = 这一题上**不给图**）。
  ///
  /// ⛔ **不许硬编码成「总是显示」**。逐条判据 + 每条挡住的是哪一种假话：
  ///
  /// ① `_result == null`（还没算过）⇒ null。
  ///    挡住：「图上四格各自对应一个引擎真算出来的组合」——没算过的时候屏上只有
  ///    「等待计算：结果将在这里展开」一句，那些格子是无源之水。
  /// ② 配子表**现算**：`SexLinkedEngine.femaleGametes` / `maleGametes` 对
  ///    `result.femaleParent` / `result.maleParent`（引擎**标准化后**的串）各调
  ///    一次，⛔ **绝不硬编码 `1/2`、绝不读输入框文本**。
  ///    挡住：① 比例与屏上账目脱钩（引擎给什么就画什么）；② 改了输入不点计算时
  ///    图先一步改口——闸门读的是 `_result` = 屏上正在显示的那笔账。
  /// ③ 父亲必须恰好**两条不同**的染色体、其中一条是光杆 `Y`（引擎
  ///    `sex_linked_engine.dart:130`）；Y 上没有位点 ⇒ 图上不给 Y 画色带；母亲的
  ///    配子至多两种。
  ///    挡住：把 X 与 Y 画成**同一条**、或给 Y 编一个位点、或画出一张讲不了
  ///    「四种组合」的图。这些前提一旦不成立，`fromEngine` 直接抛 ⇒ 这里拿到 null
  ///    ⇒ 屏上没有这张图。**理由写在 `fromEngine` 的每一条抛错里**，不在这里重抄。
  SexLinkedPunnettFigure? get _punnettFigure {
    final r = _result;
    if (r == null) return null; // ①
    return SexLinkedPunnettFigure.maybeFromEngine(
      // ②③
      femaleGametes: SexLinkedEngine.femaleGametes(r.femaleParent),
      maleGametes: SexLinkedEngine.maleGametes(r.maleParent),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    // v2.19.15：页面级 Ctrl+S 宿主——与 9331/单基因 tab 同模式。
    final r = _result;
    // v2.19.40：概念图数据（null = 这一题上不给图）。闸门逐条判据见 [_punnettFigure]。
    final punnett = _punnettFigure;
    final wide = MediaQuery.of(context).size.width >= 1200;
    // v2.19.36 正向「课标 X」可点徽章：结果区标题行 trailing。3.2.4 的
    // `tool` 逐字写着「伴性遗传」⇒ `cross_sex_linked` 唯一反查 3.2.4，
    // code 由 `curriculumReverseBadgeFor` 现算（⛔ 本页不建表、禁 const）。
    // ⛔ 空态不挂；helper 返 null 时回落原来那行亲本文字（逐像素同旧）。
    final badge = r == null
        ? null
        : curriculumReverseBadgeFor(context, 'cross_sex_linked');
    // 原来那行亲本文字：抽成局部量，徽章挂上后它仍是**同一个 widget**，
    // 只从「独占 trailing」变成「Wrap 里的第二件」。
    final parentsText = r == null
        ? null
        : Text(
            '♀ ${r.femaleParent} × ♂ ${r.maleParent}',
            style: AppText.monoSmall.copyWith(color: AppColors.steel),
          );
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
                  title: '子代结果',
                  subtitle: r == null
                      ? '设定亲本后点「计算子代」，这里展开子代明细与按性别的条件概率'
                      : '子代基因型明细 · 按性别看表型（条件概率）'
                          '${widget.cardHint ?? ''}',
                  trailing: badge == null
                      ? parentsText
                      : Wrap(
                          spacing: 10,
                          alignment: WrapAlignment.end,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [badge, parentsText!],
                        ),
                  child: _buildResultBody(),
                ),
              // ── 伴性遗传概念示意图（v2.19.40）────────────────────
              //
              // 位置是 `FlatSection` 的**兄弟**、排在它**之后**，⛔ 三条理由不许挪：
              // ① 它在 `RepaintBoundary(key: _resultKey)`（结果区那个）**之外**
              //    ⇒ 学生点「存为图片」导出的 PNG **不会**把这张概念图卷进去
              //    （`_exportResult` 走 `captureBoundaryPng(_resultKey, …)`，
              //    `png_export.dart` 只对那一个 boundary 调 `toImage()`）。
              // ② 它不是 `FlatSection` 的子节点 ⇒ 位置本身**不**受「算出结果才
              //    展开」那套结构支配；是否上屏只由 [_punnettFigure] 一个闸门说。
              // ③ 本页签**出厂不自动算**（`initState` 只消费 `pendingFill`）⇒
              //    概念图只有点过「计算子代」才存在，未计算态的屏上一个像素都不加。
              //
              // ⛔ **不加任何输入框或按钮**（`test/cross_tab_sweep_test.dart`
              //    那类守卫按位置 / 数量取控件，多一个可点控件就可能取错题）。
              // ⛔ **不硬编码成总是显示**：数据是 [_punnettFigure]，它为 null 时整块
              //    不渲染（每条判据见那里）。
              if (punnett != null) ...[
                const SizedBox(height: 24),
                Text('子代是怎么来的', style: AppText.label),
                const SizedBox(height: 10),
                // 组件内部已是 `SizedBox(width: double.infinity)` + `AspectRatio`
                // （320 / designHeightFor(行数)）⇒ ⛔ 外面不许再套**固定**宽度。
                // 这里只给一个**上限**：本页 `Column` 是 `crossAxisAlignment.stretch`
                // 且外面有 `maxWidth: 1400`，不封顶的话宽屏上 320 的设计稿会被
                // 拉到一千多宽、色带变成海报；封顶后宽屏恒为设计尺寸 1:1，而 360
                // 窄屏照样收缩到可用宽（实测 312），⛔ 不会溢出。
                Align(
                  alignment: Alignment.topCenter,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(
                        maxWidth: SexLinkedPunnettDiagram.designWidth),
                    child: SexLinkedPunnettDiagram(figure: punnett),
                  ),
                ),
              ],
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
          children: [
            Expanded(
              child: TextField(
                controller: _femaleCtrl,
                style: AppText.genotype,
                decoration: const InputDecoration(
                  labelText: '母亲基因型 ♀',
                  hintText: '如 XAXa',
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
                controller: _maleCtrl,
                style: AppText.genotype,
                decoration: const InputDecoration(
                  labelText: '父亲基因型 ♂',
                  hintText: '如 XAY',
                ),
                onSubmitted: (_) => _compute(),
              ),
            ),
          ],
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
        Text('经典案例（红绿色盲模型）', style: AppText.caption),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final p in SexLinkedEngine.presets)
              _PresetChip(preset: p, onTap: () => _applyPreset(p)),
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
                  Icon(Icons.transgender,
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
        // v2.13：整个结果区挂 RepaintBoundary + 「存为图片」——
        // _SexResultTable 与 _ConditionalCard 各自视觉已稳定，
        // 外部不再叠 canvas 底避免「卡中卡」视觉。
        RepaintBoundary(
          key: _resultKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _SexResultTable(result: r),
              const SizedBox(height: 16),
              _ConditionalCard(result: r),
            ],
          ),
        ),
        // R6 学生走查 #8：伴性 tab 补「存入错题本」——7 个 tab 里唯独
        // 它断链，学生做完题想存错题只能手动建。
        Align(
          alignment: Alignment.centerLeft,
          child: SaveToMistakeBookButton(
            stem: '♀${r.femaleParent} × ♂${r.maleParent} 伴性遗传，'
                '求子代基因型与表型分布（按性别看条件概率）',
            correctAnswer: '女儿表型：${r.phenotypeGivenSex('雌性').entries.map((e) => '${e.key} ${e.value}').join('，')}；'
                '儿子表型：${r.phenotypeGivenSex('雄性').entries.map((e) => '${e.key} ${e.value}').join('，')}',
            subjectArea: kSexLinkedSubjectArea,
            // 结果面板用的是算完那一刻的 result（不是 controller 文本）——
            // 两个都取得到值时二者一致；这里用 controller 文本，与本页
            // 两个 Ctrl+S 宿主同源，避免同一道题记下两组亲本。
            srcModule: 'cross_sex_linked',
            srcParams:
                _sexLinkedSrcParams(r.femaleParent, r.maleParent),
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

class _PresetChip extends StatelessWidget {
  final ({String name, String female, String male, String note}) preset;
  final VoidCallback onTap;
  _PresetChip({required this.preset, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: preset.note,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Container(
          // v2.19.18：rail 内容宽仅 248——chip 限宽 + 名称省略号防溢出。
          constraints: const BoxConstraints(maxWidth: 216),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(preset.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.caption.copyWith(color: AppColors.graphite)),
              ),
              const SizedBox(width: 6),
              Text('${preset.female}×${preset.male}',
                  style: AppText.monoSmall
                      .copyWith(fontSize: 11, color: AppColors.teal)),
            ],
          ),
        ),
      ),
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

/// 子代基因型明细表（等宽字体，按概率排序；StepCard 内部，无自身卡片外壳）。
class _SexResultTable extends StatelessWidget {
  final SexLinkedResult result;
  const _SexResultTable({required this.result});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            children: [
              Expanded(flex: 3, child: Text('基因型', style: AppText.caption)),
              Expanded(flex: 2, child: Text('性别', style: AppText.caption)),
              Expanded(flex: 2, child: Text('表型', style: AppText.caption)),
              Expanded(
                flex: 2,
                child: Text('比例',
                    style: AppText.caption, textAlign: TextAlign.right),
              ),
            ],
          ),
        ),
        Divider(height: 1, color: AppColors.border.withValues(alpha: 0.6)),
        for (final o in result.offspring)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 9),
            child: Row(
              children: [
                Expanded(
                    flex: 3,
                    child: Text(o.genotype, style: AppText.genotype)),
                Expanded(
                  flex: 2,
                  child: Text(o.sex, style: AppText.body),
                ),
                Expanded(
                  flex: 2,
                  child: Text(
                    o.phenotype,
                    style: AppText.body.copyWith(
                      color: o.phenotype == '隐性'
                          ? AppColors.lethal
                          : AppColors.tealDark,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Text('${o.probability.toPercent()}',
                          style: AppText.caption
                              .copyWith(color: AppColors.steel)),
                      const SizedBox(width: 8),
                      RatioPill(text: '${o.probability}'),
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

/// 条件概率区：女儿/儿子各自的表型分布（教学核心考点；StepCard 内部）。
class _ConditionalCard extends StatelessWidget {
  final SexLinkedResult result;
  const _ConditionalCard({required this.result});

  @override
  Widget build(BuildContext context) {
    final daughters = result.phenotypeGivenSex('雌性');
    final sons = result.phenotypeGivenSex('雄性');
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
          Text('按性别看表型（条件概率）', style: AppText.sectionTitle),
          const SizedBox(height: 4),
          Text('高考常考：P(患病|性别) ≠ P(患病且性别)',
              style: AppText.caption),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                  child: _sexColumn('女儿 ♀', daughters, Icons.female)),
              const SizedBox(width: 12),
              Expanded(child: _sexColumn('儿子 ♂', sons, Icons.male)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _sexColumn(
      String title, Map<String, Fraction> dist, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: AppColors.teal),
              const SizedBox(width: 6),
              Text(title, style: AppText.label),
            ],
          ),
          const SizedBox(height: 8),
          if (dist.isEmpty)
            Text('无子代', style: AppText.caption)
          else
            for (final e in dist.entries)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  children: [
                    Text(e.key, style: AppText.body),
                    const Spacer(),
                    Text('${e.value}',
                        style: AppText.monoFigure.copyWith(fontSize: 18)),
                  ],
                ),
              ),
        ],
      ),
    );
  }
}
