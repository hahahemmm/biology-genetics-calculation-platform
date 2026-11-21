// ploidy_page.dart —— 染色体倍性计算页（v2.2 批次3）
//
// 覆盖：染色体组数判断（形态法/基因型法）、单倍体/二倍体/多倍体判定
// （发育来源优先）、单倍体育种、同源四倍体配子比例、三倍体无子西瓜。
// 引擎：lib/engine/ploidy_engine.dart。
//
// v2.19.21 工作台化（用户裁定：9331 布局语言推广到全计算器页）：
// 顶部 tab 导航（组数判断 / 倍性与育性 / 育种应用），宽屏 ≥1200
// 左侧常驻输入面板（ToolWorkbench 骨架，280px），窄屏输入面板
// 回渲染在结果区上方。

import 'package:flutter/material.dart';

import '../data/big_question_cards.dart' show findCardIdForTopic;
import '../engine/ploidy_engine.dart';
// 这张自绘概念图不吃 MediaQuery.textScaler，课堂大屏的字号倍率要在
// **宿主这一行**显式递给它（标准档 1.0 = 逐像素零变化）。
import '../state/present_mode_controller.dart';
import '../theme.dart';
import '../ui/ai_chat_controller.dart';
import '../guide/guide_keys.dart';
import '../ui/assistant_panel.dart';
import '../ui/module_fill.dart';
import '../ui/step_card.dart' show RatioPill;
import '../ui/step_chain.dart';
import '../ui/tab_jump_shortcuts.dart';
import 'widgets/card_link_key_host.dart';
import 'widgets/cross_tool_rail.dart' show FlatSection;
import 'widgets/save_mistake_key_host.dart';
import 'widgets/tetraploid_gamete_diagram.dart';
import 'widgets/tool_workbench.dart';

class PloidyPage extends StatefulWidget {
  const PloidyPage({super.key, this.onNavPressed});

  final VoidCallback? onNavPressed;

  @override
  State<PloidyPage> createState() => _PloidyPageState();
}

class _PloidyPageState extends State<PloidyPage>
    with TickerProviderStateMixin {
  // ── v2.19.32：出厂默认值（具名常量）────────────────────────────
  //
  // ⚠️ **常量是唯一真相**：controller 初始化与 `isPristine` 共用同一批常量
  // （本项目被「影子常量」坑过——重复定义 `_tabNames` 被 `dart analyze` 抓到）。
  static const _kDefaultTotal = '8'; // 染色体总条数
  static const _kDefaultForms = '4'; // 形态种数
  static const _kDefaultGeno = 'AaaBBb'; // 基因型
  static const _kDefaultSets = '3'; // 组数（判倍性）
  static const _kDefaultBreed = 'AaBb'; // 育种亲本
  // v2.4 N3：杂交育种流程（亲本→分离世代→连续自交纯合年限）
  static const _kDefaultHybridP = 'AaBb'; // 杂合亲本
  static const _kDefaultHybridT = 'AAbb'; // 目标纯合
  static const _kDefaultTetra = 'AAaa'; // 四倍体基因型
  static const _kDefaultTriX = '11'; // 基本染色体数 x
  // 两处开关态也提为常量：`PloidyOrigin` / 三倍体「母本四倍体」是**答案的
  // 字段**——学生挑好了「合子发育 / 母本四倍体」，深链却让页面按出厂那套
  // 重算，学生的选择就被静默丢掉了。宁可一起拦。
  static const _kDefaultOrigin = PloidyOrigin.zygote;
  static const _kDefaultTriMother4 = true;

  final _totalCtrl = TextEditingController(text: _kDefaultTotal);
  final _formsCtrl = TextEditingController(text: _kDefaultForms);
  final _genoCtrl = TextEditingController(text: _kDefaultGeno);
  final _setsCtrl = TextEditingController(text: _kDefaultSets);
  final _breedCtrl = TextEditingController(text: _kDefaultBreed);
  // v2.4 N3：杂交育种流程（亲本→分离世代→连续自交纯合年限）
  final _hybridPCtrl = TextEditingController(text: _kDefaultHybridP);
  final _hybridTCtrl = TextEditingController(text: _kDefaultHybridT);
  final _tetraCtrl = TextEditingController(text: _kDefaultTetra);
  final _triXCtrl = TextEditingController(text: _kDefaultTriX);
  PloidyOrigin _origin = _kDefaultOrigin;
  bool _triMother4 = _kDefaultTriMother4; // 三倍体专题：母本是否四倍体

  SetsByMorphology? _morphResult;
  String? _morphError;
  // v2.19.53（找茬 D）：各节**算出那一刻的输入快照**。Ctrl+S 组装 payload
  // 时逐节比对现文——改动过未重算的节从题干/答案剔除（⛔ 不存「题干新
  // 输入 + 答案旧结果」的矛盾题，矛盾数据会喂给错题本 AI 错因归类）。
  // 快照写在各按钮回调 body 算成功后的 setState 里（⛔ 不改 _run 签名——
  // 每节输入组成不同：单框 / 双框 '|' 拼接 / 框 + 开关，_run 只是通用
  // 错误壳，快照采集是各节自己的事，与分子/进化两页同款落点）。
  String? _morphSnap;
  SetsByGenotype? _genoResult;
  String? _genoError;
  String? _genoSnap;
  PloidyJudgment? _judgeResult;
  String? _judgeError;
  /// v2.19.53：判定节的输入除组数框还有「发育来源」开关（直接喂引擎、
  /// 题干里也渲染它）⇒ 一并入快照；只拨开关不重算同样算 stale。
  String? _judgeSnap;
  HaploidBreedingResult? _breedResult;
  String? _breedError;
  String? _breedSnap;
  HybridBreedingResult? _hybridResult;
  String? _hybridError;
  String? _hybridSnap;
  TetraploidGametes? _tetraResult;
  String? _tetraError;
  String? _tetraSnap;
  TriploidSeedlessResult? _triResult;
  String? _triError;
  /// v2.19.53：三倍体节的输入除 x 框还有「母本四倍体」开关（喂引擎、
  /// 题干里渲染）⇒ 一并入快照。
  String? _triSnap;

  /// v2.19.21 工作台 tab（骨架外部持有 controller，避免 identical 短路）。
  late final TabController _tab;

  /// v2.19.32：这一页现在**还是出厂状态吗**（学生一处都没动过）？
  ///
  /// 供 `ModuleFillTarget.canOverwrite` 用：学生自己在倍性页敲了题之后，
  /// 再从「考纲覆盖」/「大题套路卡」点深链，**不该把他那道题无声顶掉**。
  ///
  /// 判据 = **整页 3 个页签**的全部 9 个输入框 **加两处开关态**
  /// （`PloidyOrigin` 发育来源 / 三倍体「母本四倍体」）都还等于出厂常量。
  ///
  /// ⚠️ 为什么开关态也算 dirty：这两处是**答案的字段**——学生挑好了
  /// 「合子发育 / 母本四倍体」，深链却让页面按出厂那套重算，学生的选择
  /// 就被静默丢掉了。宁可一起拦。
  bool get isPristine =>
      _totalCtrl.text == _kDefaultTotal &&
      _formsCtrl.text == _kDefaultForms &&
      _genoCtrl.text == _kDefaultGeno &&
      _setsCtrl.text == _kDefaultSets &&
      _breedCtrl.text == _kDefaultBreed &&
      _hybridPCtrl.text == _kDefaultHybridP &&
      _hybridTCtrl.text == _kDefaultHybridT &&
      _tetraCtrl.text == _kDefaultTetra &&
      _triXCtrl.text == _kDefaultTriX &&
      _origin == _kDefaultOrigin &&
      _triMother4 == _kDefaultTriMother4;

  /// v2.19.32：`apply` 拒收本次参数时的**用户可见**反馈。
  ///
  /// 文案直接用总线给的 `reason`（`kModuleFillSkippedDirty`）；⛔ 不用
  /// 「你现在看到的是默认题」去解释「我们主动决定不写」，那是**假话**。
  /// ⚠️ 文案不含 markdown 星号，也不用「上面/下面」方向词。
  void _onApplyFailed(String moduleId, String reason) {
    debugPrint('[ploidy] 深链未写入：module=$moduleId reason=$reason');
    if (!mounted) return;
    // 页面上下文拿不到 ScaffoldMessenger 时（极端挂载时序）退回 appCanvasKey。
    final ctx = ScaffoldMessenger.maybeOf(context) != null
        ? context
        : appCanvasKey.currentContext;
    final messenger = ctx == null ? null : ScaffoldMessenger.maybeOf(ctx);
    if (messenger == null) return;
    // 先换掉再 show：不 hide 的话连发只有第一条能看见。
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(reason),
        duration: const Duration(seconds: 9),
      ));
  }

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 3, vsync: this);
    // v2.19.25：套路卡深链——按 tab 参数直达（0 组数判断 /
    // 1 倍性与育性 / 2 育种应用）。
    ModuleFillBus.register(
      ModuleFillTarget(
        moduleId: 'ploidy',
        pageIndex: 7,
        label: '染色体倍性',
        apply: (params) {
          if (!mounted) return false;
          final tab = int.tryParse(params['tab']?.trim() ?? '');
          if (tab == null || tab < 0 || tab >= 3) return false;
          _tab.animateTo(tab);
          return true;
        },
        // v2.19.32：倍性页里已经有学生自己敲的题 ⇒ 深链**不覆盖**。
        canOverwrite: () => isPristine,
        onApplyFailed: _onApplyFailed,
      ),
    );
  }

  @override
  void dispose() {
    ModuleFillBus.unregister('ploidy');
    _tab.dispose();
    for (final c in [
      _totalCtrl, _formsCtrl, _genoCtrl, _setsCtrl, _breedCtrl, _tetraCtrl,
      _hybridPCtrl, _hybridTCtrl,
      _triXCtrl,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  int _parse(TextEditingController c, String name) {
    final v = int.tryParse(c.text.trim());
    if (v == null) throw ArgumentError('$name 应为整数');
    return v;
  }

  void _run(String who, void Function() body, void Function(String) onErr) {
    try {
      body();
    } on ArgumentError catch (e) {
      setState(() => onErr(e.message?.toString() ?? '输入格式错误'));
    }
  }

  // ─── v2.19.51：Ctrl+S 存入错题本——题干/答案按下那一刻现组装 ───
  //
  // ⛔ 一个页签里多个计算器时，题干只写**已算出结果的那几节**的输入
  // （屏上那一节的输入框），不把整页 9 个输入框全塞进去——那样题干
  // 会变成与当前这道题无关的噪音（B 仓 v2.19.173 同款口径）。
  // ⛔ 屏上数字一律来自 controller 现文 / 引擎字段，一个都不许自编。

  // v2.19.53（找茬 D）：逐节「新鲜度」门——结果存在**且算出那一刻的
  // 输入快照与现文一致**才算数。学生改输入未重算时该节从题干/答案剔除，
  // ⛔ 不存「题干新输入 + 答案旧结果」的矛盾题（矛盾数据会喂给错题本
  // AI 错因归类）。全部节不新鲜 ⇒ 答案空串 ⇒ saveToMistakeBook 既有
  // 「先算出结果」守卫应答。
  bool get _morphFresh =>
      _morphResult != null &&
      _morphSnap ==
          '${_totalCtrl.text.trim()}|${_formsCtrl.text.trim()}';
  bool get _genoFresh =>
      _genoResult != null && _genoSnap == _genoCtrl.text.trim();
  bool get _judgeFresh =>
      _judgeResult != null &&
      _judgeSnap == '${_setsCtrl.text.trim()}|${_origin.name}';
  bool get _triFresh =>
      _triResult != null &&
      _triSnap == '${_triXCtrl.text.trim()}|$_triMother4';
  bool get _breedFresh =>
      _breedResult != null && _breedSnap == _breedCtrl.text.trim();
  bool get _hybridFresh =>
      _hybridResult != null &&
      _hybridSnap ==
          '${_hybridPCtrl.text.trim()}|${_hybridTCtrl.text.trim()}';
  bool get _tetraFresh =>
      _tetraResult != null && _tetraSnap == _tetraCtrl.text.trim();

  /// 当前页签的考点标签（错题本筛选字段）。⛔ 三签三条课标，不共用一签。
  String get _mistakeSubjectArea {
    const areas = [
      '染色体组数判断（形态法与基因型法）',
      '倍性判定与育性（三倍体无子西瓜）',
      '育种应用（单倍体育种·杂交育种·四倍体配子）',
    ];
    final i = _tab.index;
    return i >= 0 && i < areas.length ? areas[i] : areas.first;
  }

  /// v2.19.59：**当前考点有没有配套套路卡**——全页唯一判据。
  ///
  /// 屏上提示句与 [CardLinkKeyHost] 的 `cardId` 回调都调这一个 getter
  /// （同一个 `findCardIdForTopic(_mistakeSubjectArea)` 调用链）⇒ 两处
  /// 不可能分叉：显示提示时按 K 必跳、不显示时按 K 必无声让路。
  /// ⛔ 不许按 `_tab.index` 另行推导考点（B 仓 v2.19.251 教训：倍性页 3
  /// 页签 7 个子计算器，按页签推导的默认页签全落空）——考点就是 save 用
  /// 的那一份 `_mistakeSubjectArea`。
  String? get _linkedCardId => findCardIdForTopic(_mistakeSubjectArea);

  /// v2.19.59：结果区副标题位的屏上提示句（键位文案从宿主取，唯一真相；
  /// ⛔ 无 markdown 星号、无方向词）。
  static const String _kCardLinkHint =
      '按 ${CardLinkKeyHost.keyLabel} 看这道题的套路卡';

  String get _mistakeStem {
    switch (_tab.index) {
      case 0:
        return <String>[
          if (_morphFresh)
            '染色体总条数 ${_totalCtrl.text.trim()}、形态种数 ${_formsCtrl.text.trim()}，'
                '求染色体组数（形态法）',
          if (_genoFresh)
            '基因型 ${_genoCtrl.text.trim()}，求染色体组数（基因型法）',
        ].join('；');
      case 1:
        return <String>[
          if (_judgeFresh)
            '染色体组数 ${_setsCtrl.text.trim()}、'
                '${_origin == PloidyOrigin.gamete ? '配子发育' : '受精卵发育'}，'
                '判定倍性与育性',
          if (_triFresh)
            '基本染色体数 x=${_triXCtrl.text.trim()}、'
                '${_triMother4 ? '4n 母本 × 2n 父本' : '2n 母本 × 4n 父本'}，'
                '推导三倍体无子果实',
        ].join('；');
      case 2:
        return <String>[
          if (_breedFresh)
            '亲本基因型 ${_breedCtrl.text.trim()}，'
                '求单倍体育种的花粉与加倍结果',
          if (_hybridFresh)
            '杂合亲本 ${_hybridPCtrl.text.trim()} 自交、'
                '目标纯合 ${_hybridTCtrl.text.trim()}，推算杂交育种流程',
          if (_tetraFresh)
            '同源四倍体基因型 ${_tetraCtrl.text.trim()}，求配子比例',
        ].join('；');
      default:
        return '';
    }
  }

  /// 答案全部取自引擎结果字段（SetsByMorphology / SetsByGenotype /
  /// PloidyJudgment / TriploidSeedlessResult / HaploidBreedingResult /
  /// HybridBreedingResult / TetraploidGametes，字段定义见
  /// lib/engine/ploidy_engine.dart），⛔ 一个数字都不自编。
  String get _mistakeAnswer {
    final parts = <String>[];
    switch (_tab.index) {
      case 0:
        final m = _morphFresh ? _morphResult : null;
        if (m != null) {
          parts.add('组数 ${m.sets} 个，每组含 ${m.perSet} 条');
        }
        final g = _genoFresh ? _genoResult : null;
        if (g != null) {
          parts.add('各字母次数 ${g.letterCounts.entries.map((e) => '${e.key}×${e.value}').join('　')}，'
              '组数 ${g.sets} 个');
        }
      case 1:
        final j = _judgeFresh ? _judgeResult : null;
        if (j != null) {
          parts.add('${j.name}（${j.fertile ? '可育' : '不育'}）：${j.reason}');
        }
        final tri = _triFresh ? _triResult : null;
        if (tri != null) {
          parts.add('胚 ${tri.embryoSets} 组（${tri.embryoChromosomes} 条），'
              '胚乳 ${tri.endospermSets} 组，果皮 ${tri.fruitSets} 组；${tri.sterility}');
        }
      case 2:
        final b = _breedFresh ? _breedResult : null;
        if (b != null) {
          parts.add('花粉 ${b.gametes.join('、')}，加倍后 ${b.doubled.join('、')}，'
              '纯合子比例 ${(b.pureRatio * 100).toStringAsFixed(0)}%');
        }
        final h = _hybridFresh ? _hybridResult : null;
        if (h != null) {
          parts.add('分离世代基因型 ${h.genotypeKinds} 种；目标表型 '
              '${h.targetPhenotypeCount}/${h.segregatingTotal}，其中纯合 '
              '${h.targetPureCount}/${h.segregatingTotal}；'
              '${h.pureAtSelection ? '目标全隐性：选出即纯合' : '连续自交 ${h.selfingGenerations} 代纯合率 ${(h.pureRateAfterN * 100).toStringAsFixed(1)}%'}'
              '，约 ${h.estimatedYears} 年');
        }
        final t = _tetraFresh ? _tetraResult : null;
        if (t != null) {
          parts.add('配子 ${t.ratioText}');
        }
      default:
        break;
    }
    return parts.join('；');
  }

  /// 本页 3 个页签全部有计算器 ⇒ 永不返回 null；「未算出结果」照常传
  /// 空答案，由 saveToMistakeBook 的「先算出结果，再存入错题本」守卫应答。
  ///
  /// srcModule **一律不传**：本页 ModuleFillBus 唯一注册的 target 是
  /// moduleId 'ploidy'（见 initState），它的 apply 只解析 `tab` 参数做
  /// `_tab.animateTo(tab)` 切页签——⛔ 没有任何分支回填 _setsCtrl /
  /// _triXCtrl / _breedCtrl 等计算器输入。存进去的节没有任何一个能被该
  /// target 真实回填 ⇒ 传了错题本会出现一枚点下去必落回出厂题的回程按钮。
  SavePayload? _mistakePayload() {
    final i = _tab.index;
    if (i < 0 || i > 2) return null;
    return SavePayload(
      stem: _mistakeStem,
      correctAnswer: _mistakeAnswer,
      subjectArea: _mistakeSubjectArea,
    );
  }

  // ─── 工作台 tab 定义 ───

  List<WorkbenchTabSpec> _tabs() => [
        WorkbenchTabSpec(
          label: '组数判断',
          icon: Icons.grid_4x4_outlined,
          sidePanel: _setsInputs,
          body: _setsBody,
        ),
        WorkbenchTabSpec(
          label: '倍性与育性',
          icon: Icons.fact_check_outlined,
          sidePanel: _judgeInputs,
          body: _judgeBody,
        ),
        WorkbenchTabSpec(
          label: '育种应用',
          icon: Icons.agriculture_outlined,
          sidePanel: _breedingInputs,
          body: _breedingBody,
        ),
      ];

  @override
  Widget build(BuildContext context) {
    // v2.19.21 工作台化：顶部 tab + 宽屏左栏输入 / 右区结果。
    // v2.19.22：骨架 StatefulWidget（监听 TabController 刷新左栏），
    // 每次 build 新建实例；TabBar 由 buildWorkbenchTabBar 组装。
    final tabs = _tabs();
    return Scaffold(
      appBar: AppBar(
        leading: appNavButton(widget.onNavPressed),
        title: const Text('染色体倍性'),
        // v2.19.23 找茬 P1#1：引导锚点挂 TabBar（tab 无关，永在树），
        // 与分子/进化三页统一。
        bottom: PreferredSize(
          key: GuideKeys.ploidyFirst,
          preferredSize: const Size.fromHeight(48),
          child: buildWorkbenchTabBar(_tab, tabs),
        ),
        actions: [
          TextButton.icon(
            onPressed: () {
              AiChatController.instance.queueSend(
                  '【当前工具：染色体倍性计算】染色体组数判断 / 倍性判定 / 单倍体育种 / 四倍体配子。'
                  '当前输入：总条数=${_totalCtrl.text}、形态种数=${_formsCtrl.text}、'
                  '基因型=${_genoCtrl.text}、组数=${_setsCtrl.text}、'
                  '育种亲本=${_breedCtrl.text}、四倍体=${_tetraCtrl.text}。');
              showAiAssistant(context);
            },
            icon: Icon(Icons.psychology_outlined, size: 18, color: AppColors.teal),
            label: Text('问 AI',
                style: TextStyle(
                    color: AppColors.teal, fontWeight: FontWeight.w600)),
          ),
          const SizedBox(width: 8),
        ],
      ),
      // v2.19.49：Alt+数字 页签直跳宿主（零像素，只切页签不碰题面；
      // 让路闸见 lib/ui/tab_jump_shortcuts.dart 文件头）。
      // v2.19.51：Ctrl+S 存当前题进错题本（页面级唯一宿主；payload 是
      // 按下那一刻现取的 ValueGetter ⇒ ToolWorkbench 切页签不让本 State
      // rebuild 也没有过期窗，B 仓 v2.19.173 抓的 stale-capture 病由构造
      // 不存在；闸见 save_mistake_key_host.dart 文件头）。
      body: SaveMistakeKeyHost(
        payload: _mistakePayload,
        child: CardLinkKeyHost(
          // v2.19.59：K 看这道题的套路卡（页面级唯一宿主；只切页签不让本
          // State rebuild ⇒ cardId 必须是按下那一刻现取的 ValueGetter，
          // 闸见 card_link_key_host.dart 文件头）。
          cardId: () => _linkedCardId,
          child: TabJumpShortcuts(
            tab: _tab,
            child: ToolWorkbench(
              controller: _tab,
              tabs: tabs,
              railTitle: '倍性 · 输入',
              railIcon: Icons.grid_4x4_outlined,
            ),
          ),
        ),
      ),
    );
  }

  // ─── Tab 0：组数判断（输入 + 结果）───

  Widget _setsInputs(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FlatSection(
            title: '染色体组数判断 · 形态法',
            subtitle: '常考',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('同一形态的染色体有几条 = 几个染色体组；'
                    '组数 = 总条数 ÷ 形态种数（如果蝇 8÷4=2 组）。',
                    style: AppText.caption.copyWith(color: AppColors.graphite)),
                const SizedBox(height: 8),
                // v2.4 N7：经典预设 chips（白板打字痛点）
                Wrap(spacing: 8, runSpacing: 4, children: [
                  for (final p in const [('果蝇 8÷4', '8', '4'), ('人 46÷23', '46', '23')])
                    ActionChip(
                      label: Text(p.$1),
                      onPressed: () {
                        _totalCtrl.text = p.$2;
                        _formsCtrl.text = p.$3;
                      },
                    ),
                ]),
                const SizedBox(height: 4),
                _field(_totalCtrl, '染色体总条数'),
                _field(_formsCtrl, '形态种数'),
                _calcBtn('计算组数', () => _run('m', () {
                      final r = setsByMorphology(
                          totalChromosomes: _parse(_totalCtrl, '总条数'),
                          distinctForms: _parse(_formsCtrl, '形态种数'));
                      setState(() {
                        _morphResult = r;
                        _morphError = null;
                        // v2.19.53：两输入 '|' 拼快照（形态法节）。
                        _morphSnap =
                            '${_totalCtrl.text.trim()}|${_formsCtrl.text.trim()}';
                      });
                    }, (m) {
                      _morphResult = null;
                      _morphError = m;
                    })),
              ],
            ),
          ),
          FlatSection(
            title: '染色体组数判断 · 基因型法',
            subtitle: '常考',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('控制同一性状的基因（同一字母不分大小写）出现几次 = 几个组。'
                    '如 Aa→2 组，AaaBBb→3 组，AAaaBBbb→4 组。',
                    style: AppText.caption.copyWith(color: AppColors.graphite)),
                const SizedBox(height: 8),
                // v2.4 N7：经典预设 chips（白板打字痛点）
                Wrap(spacing: 8, runSpacing: 4, children: [
                  for (final g in const ['AaaBBb', 'AAaaBBbb', 'Aa'])
                    ActionChip(
                      label: Text(g),
                      onPressed: () => _genoCtrl.text = g,
                    ),
                ]),
                const SizedBox(height: 4),
                _field(_genoCtrl, '基因型（如 AaaBBb）'),
                _calcBtn('按基因型判断', () => _run('g', () {
                      final r = setsByGenotype(_genoCtrl.text.trim());
                      setState(() {
                        _genoResult = r;
                        _genoError = null;
                        _genoSnap = _genoCtrl.text.trim();
                      });
                    }, (m) {
                      _genoResult = null;
                      _genoError = m;
                    })),
              ],
            ),
          ),
        ],
      );

  Widget _setsBody(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _resultSection(
            title: '形态法 · 结果',
            badge: '常考',
            ready: _morphResult != null,
            error: _morphError,
            results: _morphResult == null
                ? null
                : [
                    _kv('染色体组数', '${_morphResult!.sets} 个'),
                    _kv('每组含染色体', '${_morphResult!.perSet} 条'),
                  ],
          ),
          _resultSection(
            title: '基因型法 · 结果',
            badge: '常考',
            ready: _genoResult != null,
            error: _genoError,
            results: _genoResult == null
                ? null
                : [
                    _kv('各字母次数',
                        _genoResult!.letterCounts.entries
                            .map((e) => '${e.key}×${e.value}')
                            .join('　')),
                    _kv('染色体组数', '${_genoResult!.sets} 个'),
                  ],
          ),
        ],
      );

  // ─── Tab 1：倍性与育性（输入 + 结果）───

  Widget _judgeInputs(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FlatSection(
            title: '倍性判定（先看发育来源）',
            subtitle: '易错',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('由配子直接发育 → 一律是单倍体（与组数无关）；'
                    '由受精卵发育 → 按组数称二倍体/三倍体/多倍体。'
                    '奇数染色体组联会紊乱 → 不育（三倍体无子西瓜）。',
                    style: AppText.caption.copyWith(color: AppColors.graphite)),
                const SizedBox(height: 8),
                _field(_setsCtrl, '染色体组数'),
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: SegmentedButton<PloidyOrigin>(
                    segments: const [
                      ButtonSegment(
                          value: PloidyOrigin.zygote, label: Text('受精卵发育')),
                      ButtonSegment(
                          value: PloidyOrigin.gamete, label: Text('配子发育')),
                    ],
                    selected: {_origin},
                    onSelectionChanged: (s) =>
                        setState(() => _origin = s.first),
                  ),
                ),
                _calcBtn('判定倍性', () => _run('j', () {
                      final r = judgePloidy(
                          sets: _parse(_setsCtrl, '组数'), origin: _origin);
                      setState(() {
                        _judgeResult = r;
                        _judgeError = null;
                        // v2.19.53：组数框 + 发育来源开关一并入快照。
                        _judgeSnap =
                            '${_setsCtrl.text.trim()}|${_origin.name}';
                      });
                    }, (m) {
                      _judgeResult = null;
                      _judgeError = m;
                    })),
              ],
            ),
          ),
          FlatSection(
            title: '三倍体无子西瓜',
            subtitle: '常考',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('二倍体×四倍体 → 三倍体种子；三倍体联会紊乱不育 → 无子；'
                    '果皮组数 = 母本倍数（易错）。',
                    style: AppText.caption.copyWith(color: AppColors.graphite)),
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  // v2.19.23 找茬 P2#3：段标签改短——宽屏 rail 内容宽仅
                  // 248px，原 11 字段标签（~170px 固有宽）被 SegmentedButton
                  // 均分到 124px/段后换行成两行。生物学通用记法 4n/2n。
                  child: SegmentedButton<bool>(
                    segments: const [
                      ButtonSegment(value: true, label: Text('4n 母本 × 2n 父本')),
                      ButtonSegment(value: false, label: Text('2n 母本 × 4n 父本')),
                    ],
                    selected: {_triMother4},
                    onSelectionChanged: (s) =>
                        setState(() => _triMother4 = s.first),
                  ),
                ),
                _field(_triXCtrl, '基本染色体数 x（西瓜=11，即 2n=22）'),
                _calcBtn('推导三倍体果实', () => _run('tri', () {
                      final r = triploidSeedless(
                        x: _parse(_triXCtrl, '基本染色体数'),
                        motherPloidy: _triMother4 ? 4 : 2,
                        fatherPloidy: _triMother4 ? 2 : 4,
                      );
                      setState(() {
                        _triResult = r;
                        _triError = null;
                        // v2.19.53：x 框 + 母本四倍体开关一并入快照。
                        _triSnap = '${_triXCtrl.text.trim()}|$_triMother4';
                      });
                    }, (m) {
                      _triResult = null;
                      _triError = m;
                    })),
              ],
            ),
          ),
        ],
      );

  Widget _judgeBody(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _resultSection(
            title: '倍性判定 · 结果',
            badge: '易错',
            ready: _judgeResult != null,
            error: _judgeError,
            results: _judgeResult == null
                ? null
                : [
                    // v2.2 批次4a：推导链呈现（题干→判定规则→结果）。
                    StepChain(steps: [
                      ChainStep.input('题干数据',
                          formula: '染色体组数=${_setsCtrl.text}；'
                              '${_origin == PloidyOrigin.gamete ? "配子发育" : "受精卵发育"}'),
                      const ChainStep.compute('判定规则',
                          detail: '配子发育→一律单倍体（与组数无关）；'
                              '受精卵发育→按组数称二/三/多倍体，奇数组不育'),
                      ChainStep.result('判定结果',
                          formula:
                              '${_judgeResult!.name}（${_judgeResult!.fertile ? "可育" : "不育"}）',
                          detail: _judgeResult!.reason),
                    ]),
                  ],
          ),
          _resultSection(
            title: '三倍体无子西瓜 · 结果',
            badge: '常考',
            ready: _triResult != null,
            error: _triError,
            results: _triResult == null
                ? null
                : [
                    StepChain(steps: [
                      ChainStep.input('亲本',
                          formula: '母本 ${_triResult!.motherPloidy}n × '
                              '父本 ${_triResult!.fatherPloidy}n',
                          detail: 'x=${_triResult!.x}，'
                              '母本配子 ${_triResult!.motherPloidy ~/ 2} 组，'
                              '父本精细胞 ${_triResult!.fatherPloidy ~/ 2} 组'),
                      ChainStep.compute('受精成双受精',
                          formula: '胚=${_triResult!.embryoSets} 组；'
                              '胚乳=${_triResult!.endospermSets} 组',
                          detail: '胚=卵+精=${_triResult!.embryoSets} 组'
                              '（${_triResult!.embryoChromosomes} 条）；'
                              '胚乳=2极核+精=${_triResult!.endospermSets} 组'),
                      ChainStep.result('果实与育性',
                          formula: '果皮（子房壁）=${_triResult!.fruitSets} 组'
                              '——由母本体细胞决定',
                          detail: '${_triResult!.sterility}；'
                              '${_triResult!.pollenRole}'),
                    ]),
                  ],
          ),
        ],
      );

  // ─── Tab 2：育种应用（输入 + 结果）───

  Widget _breedingInputs(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FlatSection(
            title: '单倍体育种',
            subtitle: '常考',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('杂合亲本 → 花药离体培养得单倍体 → 秋水仙素加倍 → '
                    '后代 100% 纯合，明显缩短育种年限。',
                    style: AppText.caption.copyWith(color: AppColors.graphite)),
                const SizedBox(height: 8),
                _field(_breedCtrl, '亲本基因型（如 AaBb，≤3 对基因）'),
                _calcBtn('列出花粉与加倍结果', () => _run('b', () {
                      final r = haploidBreeding(_breedCtrl.text.trim());
                      setState(() {
                        _breedResult = r;
                        _breedError = null;
                        _breedSnap = _breedCtrl.text.trim();
                      });
                    }, (m) {
                      _breedResult = null;
                      _breedError = m;
                    })),
              ],
            ),
          ),
          FlatSection(
            title: '杂交育种流程',
            subtitle: '常考',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('杂合亲本自交得分离世代 → 选目标表型 → 目标含显性性状时'
                    '须连续自交逐代纯化（目标全隐性则选出即纯合）。',
                    style: AppText.caption.copyWith(color: AppColors.graphite)),
                const SizedBox(height: 8),
                _field(_hybridPCtrl, '杂合亲本（如 AaBb，≤2 对基因）'),
                _field(_hybridTCtrl, '目标纯合基因型（如 aaBB / aabb）'),
                _calcBtn('推算育种流程', () => _run('h', () {
                      final r = hybridBreeding(
                          _hybridPCtrl.text.trim(), _hybridTCtrl.text.trim());
                      setState(() {
                        _hybridResult = r;
                        _hybridError = null;
                        // v2.19.53：两输入 '|' 拼快照（杂交育种节）。
                        _hybridSnap =
                            '${_hybridPCtrl.text.trim()}|${_hybridTCtrl.text.trim()}';
                      });
                    }, (m) {
                      _hybridResult = null;
                      _hybridError = m;
                    })),
              ],
            ),
          ),
          FlatSection(
            title: '同源四倍体配子比例',
            subtitle: '常考',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('4 条同源染色体随机 2 条进配子（C(4,2)=6 种等概率）。'
                    '经典：AAaa → AA:Aa:aa = 1:4:1。',
                    style: AppText.caption.copyWith(color: AppColors.graphite)),
                const SizedBox(height: 8),
                _field(_tetraCtrl, '四倍体基因型（如 AAaa / AAAa / Aaaa）'),
                _calcBtn('计算配子比例', () => _run('t', () {
                      final r = tetraploidGametes(_tetraCtrl.text.trim());
                      setState(() {
                        _tetraResult = r;
                        _tetraError = null;
                        _tetraSnap = _tetraCtrl.text.trim();
                      });
                    }, (m) {
                      _tetraResult = null;
                      _tetraError = m;
                    })),
              ],
            ),
          ),
        ],
      );

  Widget _breedingBody(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _resultSection(
            title: '单倍体育种 · 结果',
            badge: '常考',
            ready: _breedResult != null,
            error: _breedError,
            results: _breedResult == null
                ? null
                : [
                    _kv('花粉（单倍体）', _breedResult!.gametes.join('、')),
                    _kv('加倍后纯合', _breedResult!.doubled.join('、')),
                    _kv('纯合子比例', '100%'),
                  ],
          ),
          _resultSection(
            title: '杂交育种流程 · 结果',
            badge: '常考',
            ready: _hybridResult != null,
            error: _hybridError,
            results: _hybridResult == null
                ? null
                : [
                    StepChain(steps: [
                      ChainStep.input('亲本与目标',
                          formula:
                              'P ${_hybridResult!.parentGenotype} → 目标 ${_hybridResult!.targetGenotype}'),
                      ChainStep.compute('分离世代（自交一代）',
                          formula:
                              '基因型 ${_hybridResult!.genotypeKinds} 种；目标表型 '
                                  '${_hybridResult!.targetPhenotypeCount}/${_hybridResult!.segregatingTotal}，'
                                  '其中纯合 ${_hybridResult!.targetPureCount}/${_hybridResult!.segregatingTotal}'),
                      ChainStep.result('纯化与年限',
                          formula: _hybridResult!.pureAtSelection
                              ? '目标全隐性：选出即纯合（约 ${_hybridResult!.estimatedYears} 年）'
                              : '连续自交 ${_hybridResult!.selfingGenerations} 代纯合率 '
                                  '${(_hybridResult!.pureRateAfterN * 100).toStringAsFixed(1)}%，'
                                  '约 ${_hybridResult!.estimatedYears} 年',
                          detail: _hybridResult!.notes.join('\n')),
                    ]),
                  ],
          ),
          _resultSection(
            title: '同源四倍体配子比例 · 结果',
            badge: '常考',
            ready: _tetraResult != null,
            error: _tetraError,
            results: _tetraResult == null
                ? null
                : [
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Row(children: [
                        Text('配子比例', style: AppText.caption),
                        const SizedBox(width: 8),
                        RatioPill(text: _tetraResult!.ratioText),
                      ]),
                    ),
                    // 同源四倍体配子示意图（纯代码绘制，非位图）：挂在「配子
                    // 比例」那枚 RatioPill 的**兄弟位置**——pill 印比例，图回答
                    // 「这个数是怎么来的」。⛔ 不可画时组件**自身**收缩成
                    // SizedBox.shrink（不留标题 / 图例 / 空框 / 占位），与遗传
                    // 咨询那张方格图同款纪律，所以这里不必包任何条件。课堂档
                    // 字号倍率显式下传（见上面 present_mode_controller 注释）。
                    TetraploidGameteDiagram(
                        result: _tetraResult,
                        textScale: PresentModeController.instance.enabled
                            ? PresentModeController.textScale
                            : 1.0),
                  ],
          ),
        ],
      );

  // ─── 展示 helper ───

  /// 结果分区：FlatSection 平铺（替代 v2.19.20 前的 _section
  /// StepCard 输入+结果合体）。未计算 → 单行占位；错误 → lethal 文本。
  Widget _resultSection({
    required String title,
    String? badge,
    required bool ready,
    String? error,
    List<Widget>? results,
  }) {
    return FlatSection(
      title: title,
      // v2.19.59：算出结果 且 当前考点有配套卡 ⇒ 副标题位出 K 提示句；
      // 无结果 / 无卡（_linkedCardId 为 null）⇒ 整句不渲染。判据与宿主
      // cardId() 共用 _linkedCardId（同一个 findCardIdForTopic 调用链）。
      subtitle: ready && _linkedCardId != null ? _kCardLinkHint : null,
      trailing: badge == null ? null : AppChip(badge),
      child: error != null
          ? _err(error)
          : (ready
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: results!,
                )
              : _waitingPlaceholder()),
    );
  }

  Widget _waitingPlaceholder() => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.calculate_outlined,
                size: 18, color: AppColors.steel.withValues(alpha: 0.45)),
            const SizedBox(width: 8),
            Text('等待计算：结果将在这里展开',
                style: AppText.caption),
          ],
        ),
      );

  Widget _field(TextEditingController ctrl, String label) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: TextField(
        controller: ctrl,
        decoration:
            const InputDecoration(isDense: true, counterText: '')
                .copyWith(labelText: label),
      ),
    );
  }

  Widget _calcBtn(String label, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Align(
        alignment: Alignment.centerLeft,
        child: FilledButton.icon(
          onPressed: onTap,
          icon: const Icon(Icons.calculate_outlined, size: 18),
          label: Text(label),
          style: FilledButton.styleFrom(
            minimumSize: const Size(0, 38),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            padding:
                const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          ),
        ),
      ),
    );
  }

  Widget _err(String msg) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(msg,
            style: AppText.caption.copyWith(color: AppColors.lethal)),
      );

  Widget _kv(String label, String value) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(width: 110, child: Text(label, style: AppText.caption)),
            Expanded(
              child: Text(value,
                  style: AppText.body.copyWith(
                      color: AppColors.ink, fontWeight: FontWeight.w600)),
            ),
          ],
        ),
      );
}
