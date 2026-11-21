// genetic_disease_page.dart —— 人类遗传病（课标 3.3.6）
//
// 速查分类 + 遗传咨询计算（引擎 lib/engine/genetic_disease_engine.dart）。
// 窄屏友好：滚动卡片 + 常驻结果。

import 'dart:convert';

import 'package:flutter/material.dart';

import '../engine/genetic_disease_engine.dart';
import '../theme.dart';
import '../ui/ai_chat_controller.dart';
import '../ui/assistant_panel.dart';
import '../ui/module_fill.dart';
import '../ui/tab_jump_shortcuts.dart';
import 'curriculum_page.dart';
import 'widgets/calculation_empty_state.dart';
import 'widgets/tool_workbench.dart';
import 'widgets/pedigree_inference_view.dart';
import 'widgets/save_mistake_key_host.dart';

class GeneticDiseasePage extends StatefulWidget {
  const GeneticDiseasePage({
    super.key,
    this.navCollapsed = false,
    this.onNavPressed,
    // v2.13+ 老师走查：快捷条/老师卡 push 本页直达「系谱推断」分区
    // （否则落地页首屏是遗传咨询计算，推断分区要滚 7+ 屏）。
    this.focusInference = false,
    this.sourceLabel,
  });

  /// v2.20.0：HomeShell 的导航面板折叠态（与系谱/9331/图谱页同源）。
  ///
  /// 本页没有「随 ☰ 折叠的本地面板」——布局是 ToolWorkbench（宽屏左
  /// 输入栏 / 窄屏输入回渲染顶部），输入栏不在折叠范围内（用户裁定：
  /// 折叠只收控制类面板，输入栏必须常驻可用）。故本参数当前**不改变
  /// 像素**，只为与同族工作台页（evolution/home/settings 等）保持同一
  /// 构造签名，并由 HomeShell 统一注入——避免「有的页收得到全局状态、
  /// 有的页收不到」再次出现。默认 false ⇒ 独立构造（测试/嵌入）行为不变。
  final bool navCollapsed;

  final VoidCallback? onNavPressed;

  /// true 时首帧后自动滚到「系谱推断」分区。
  final bool focusInference;

  /// v2.19.30（M3.1 老师 P2-3）：push 来源页名（顶部回程细条；null 不渲染）。
  final String? sourceLabel;

  @override
  State<GeneticDiseasePage> createState() => _GeneticDiseasePageState();
}

class _GeneticDiseasePageState extends State<GeneticDiseasePage>
    with TickerProviderStateMixin {
  /// v2.19.28 工作台化：3 个 tab 的 TabController（本 State 持有，
  /// 骨架每 build 新建实例——identical 短路纪律）。
  late final TabController _tab;

  final _fCtrl = TextEditingController(text: 'XAY');
  final _mCtrl = TextEditingController(text: 'XAXa');
  bool _rec = true;

  /// 系谱推断分区的定位 key（focusInference 直达用）。
  final _inferenceKey = GlobalKey();

  /// 推断器视图 key（拍题识别 actions 录入用）。
  final _inferenceViewKey = GlobalKey<PedigreeInferenceViewState>();

  /// v2.14 R5：拍题原图（base64）——拍题识别填参进来时随 ModuleFillBus
  /// 带到，展示在推断分区上方供学生对照核对 AI 识别的成员有无遗漏。
  String? _scanImageB64;

  DiseaseRiskResult? _result;
  String? _error;
  // v2.19.53（找茬 D）：各节**算出那一刻的输入快照**。Ctrl+S 组装 payload
  // 时逐节比对现文——改动过未重算的节从题干/答案剔除（⛔ 不存「题干新
  // 输入 + 答案旧结果」的矛盾题，矛盾数据会喂给错题本 AI 错因归类）。
  // tab0 的输入除两个框还有显隐开关 _rec（直接喂引擎、题干里也渲染它）
  // ⇒ 一并入快照（照倍性/变异「框+开关」先例）：只拨开关不重算同样算 stale。
  String? _riskSnap;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 3, vsync: this);
    if (widget.focusInference) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        // v2.19.28 工作台化：推断器在「系谱推断」tab（index 1）——
        // 先切 tab，骨架 rebuild 后的下一帧再滚动定位。
        if (_tab.index != 1) _tab.animateTo(1);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          final ctx = _inferenceKey.currentContext;
          if (ctx != null) {
            Scrollable.ensureVisible(ctx,
                duration: const Duration(milliseconds: 300));
          }
        });
      });
    }
    // v2.13+：拍题识别录入路由——AI 识别系谱图 → add_member 动作序列 →
    // 本页推断器视图。
    // R5 学生走查 P0（v2.14 修订）：pd_inference / disease_risk 的
    // ModuleFillTarget 注册原来在本页 initState、dispose 注销——而拍题
    // FAB 在 HomeShell 上：页面盖住 FAB 时扫不了，pop 回来即注销，
    // fillScan 永远查不到 target（招牌链路实际走不通）。两 target 已
    // 上移到 HomeShell 常驻注册（main.dart）；本页只保留 push 路由的
    // pending 自愈消费（取走入队的 params/actions）。
    final pendingPd = ModuleFillBus.consumePendingActions('pd_inference');
    if (pendingPd.isNotEmpty) {
      // v2.19.28 工作台化：推断器视图在「系谱推断」tab（index 1），
      // 切过去后视图才挂载。
      _tab.animateTo(1);
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (mounted) {
          // R7 修订：loadFromActions 现在是 Future（覆盖前确认），
          // postFrame 里 await 即可。
          await _inferenceViewKey.currentState?.loadFromActions(pendingPd);
        }
      });
    }
    // v2.14 R5：拍题原图随 fill 带来（系谱识别对照核对用）——控制器里
    // 的原图已被 sendScan 消费，只有 ModuleFillBus 这份备份。仅 push
    // 填参路径会有；普通进入本页取到 null 无副作用。
    _scanImageB64 = ModuleFillBus.takePendingScanImage();
    // v2.12 拍题识别填参路由：AI 识别出人类遗传病风险题 → 设双亲基因型
    // + 显隐模式 + 即算。页面不在主导航：target 走 pushFactory 路由。
    //
    // v2.12 修复 (VerB2 P0)：拍题识别走 fillScan（AI 返回 actions 不带 params）
    // 时，actions 入队 `_pendingActions` 而非 `_pendingFills`，老代码只消费
    // `_pendingFills` → actions 永远不被消费，是死数据。修复：params 缺失时
    // 退一步消费 `_pendingActions`，把 `set_parents` action 转译成 params
    // 再走原有 apply 路径。
    final pending = ModuleFillBus.consumePending('disease_risk');
    Map<String, String>? appliedParams;
    if (pending != null && pending.isNotEmpty) {
      appliedParams = pending;
    } else {
      // 拍题识别走 fillScan（AI 返回 actions 不带 params）时，
      // `_pendingFills` 留下空 map `{}`——`pending != null` 走不进 else；
      // 需 `isNotEmpty` 才认作有效 params，否则继续消费 actions。
      final pendingActions =
          ModuleFillBus.consumePendingActions('disease_risk');
      if (pendingActions.isNotEmpty) {
        final first = pendingActions.first;
        if (first['type'] == 'set_parents') {
          final mode = first['mode']?.trim().toLowerCase();
          appliedParams = {
            'father': first['father']?.trim() ?? '',
            'mother': first['mother']?.trim() ?? '',
            'mode': (mode == 'dom') ? 'dom' : 'rec',
          };
        }
      }
    }
    if (appliedParams != null) {
      // initState 阶段 widget 还未挂载，延迟到首帧后再回填。
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _applyDiseaseRisk(appliedParams!);
      });
    }
    // R5（v2.14）：disease_risk target 已上移到 HomeShell 常驻注册
    // （见 initState 顶部注释），本页不再注册/注销。
  }

  @override
  void dispose() {
    _tab.dispose();
    _fCtrl.dispose();
    _mCtrl.dispose();
    super.dispose();
  }

  void _calc() {
    try {
      final r = mendelianRisk(
        father: _fCtrl.text.trim(),
        mother: _mCtrl.text.trim(),
        mode: _rec ? 'rec' : 'dom',
      );
      setState(() {
        _result = r;
        _error = null;
        // v2.19.53：父框|母框|显隐开关 '|' 拼快照（遗传咨询节）。
        _riskSnap =
            '${_fCtrl.text.trim()}|${_mCtrl.text.trim()}|${_rec ? 'rec' : 'dom'}';
      });
    } on ArgumentError catch (e) {
      setState(() {
        _result = null;
        _error = e.message?.toString() ?? '输入格式错误';
      });
    }
  }

  /// v2.12 拍题识别：设双亲基因型 + 显隐模式 + 即算。
  /// params 字段：
  ///   - father / mother：必填（亲本基因型，如 Aa / XAY / XAXa）
  ///   - mode：可选（rec=隐性/dom=显性，缺省走当前 _rec）
  bool _applyDiseaseRisk(Map<String, String> params) {
    final father = params['father']?.trim();
    final mother = params['mother']?.trim();
    if (father == null || father.isEmpty) return false;
    if (mother == null || mother.isEmpty) return false;
    final mode = params['mode']?.trim().toLowerCase();
    setState(() {
      _fCtrl.text = father;
      _mCtrl.text = mother;
      if (mode == 'rec' || mode == 'dom') {
        _rec = mode == 'rec';
      }
    });
    // setState 之后再 _calc（setState 已把控制器文本写入；_calc 读 .text）
    _calc();
    return true;
  }

  String _pct(double v) => '${(v * 100).toStringAsFixed(1)}%';

  // ─── v2.19.51：Ctrl+S 存入错题本——题干/答案按下那一刻现组装 ───
  //
  // ⛔ 题干只写已算出的输入（controller 现文 + 显隐模式中文标签），屏上
  // 数字一律来自 controller 现文 / 引擎字段，一个都不许自编（B 仓
  // v2.19.173 同款口径）。

  // v2.19.53（找茬 D）：逐节「新鲜度」门——结果存在**且算出那一刻的
  // 输入快照与现文一致**才算数。学生改输入未重算时该节从题干/答案剔除，
  // ⛔ 不存「题干新输入 + 答案旧结果」的矛盾题（矛盾数据会喂给错题本
  // AI 错因归类）。全部节不新鲜 ⇒ 答案空串 ⇒ saveToMistakeBook 既有
  // 「先算出结果」守卫应答。
  bool get _riskFresh =>
      _result != null &&
      _riskSnap ==
          '${_fCtrl.text.trim()}|${_mCtrl.text.trim()}|${_rec ? 'rec' : 'dom'}';

  /// 考点标签（错题本「考点」字段）。本页只有 tab0 遗传咨询有计算器 ⇒
  /// 不三签共用一签；其余两签在 [_mistakePayload] 里已被 null 闸拦掉。
  String get _mistakeSubjectArea => '遗传咨询（单基因遗传病风险）';

  String get _mistakeStem {
    // 遗传咨询：双亲基因型现文 + 显隐模式中文标签。
    if (_tab.index != 0) return '';
    return !_riskFresh
        ? ''
        : '父亲基因型 ${_fCtrl.text.trim()}、母亲基因型 ${_mCtrl.text.trim()}'
            '（${_rec ? '隐性患病' : '显性患病'}），求子代患病风险';
  }

  /// 答案全部取自引擎结果字段（DiseaseRiskResult，见
  /// lib/engine/genetic_disease_engine.dart），⛔ 一个数字都不自编；
  /// 患病/携带者概率用屏上 [_pct] 同款百分比格式。
  String get _mistakeAnswer {
    final r = _riskFresh ? _result : null;
    if (_tab.index != 0 || r == null) return '';
    return '亲本配子 父：${r.fatherGametes.join(' / ')}　母：${r.motherGametes.join(' / ')}；'
        '子代基因型 ${r.offspring.entries.map((e) => '${e.key} ${_pct(e.value)}').join('　')}；'
        '患病概率 ${_pct(r.affectedRate)}'
        '${r.carrierRate > 0 ? '；携带者概率 ${_pct(r.carrierRate)}' : ''}；'
        '${r.note}';
  }

  /// tab1（系谱推断）/ tab2（分类与预防）返回 null（闸④）：
  ///  · tab1 内嵌 PedigreeInferenceView 已是页面级 SaveMistakeKeyHost
  ///    （v2.19.55 起，非 CallbackShortcuts）——本宿主对这一签必须 null
  ///    让路，正确性靠「本宿主 tab!=0 返 null」+ 宿主同键互斥消费闸
  ///    （save_mistake_key_host.dart 闸⑤）共同保证：一次按键只由内嵌视图
  ///    应答一次，⛔ 在这里返回非 null 会把系谱那道题在本页再写一遍。
  ///  · tab2 是纯内容区（分类速查 + 检测与预防），没有计算器 ⇒ 编造
  ///    题干闸：按了必须无声让路。
  /// tab0「未算出结果」照常传空答案，由 saveToMistakeBook 的
  /// 「先算出结果，再存入错题本」守卫应答（与四页蓝本同口径）。
  ///
  /// srcModule 传 'disease_risk'：它是 HomeShell 常驻注册的真 target
  /// （main.dart registerAppLevelModuleTargets）。apply 的 `(_) => false`
  /// 只是 pushFactory 壳在非 push 分支的兜底——fill 的 push 分支
  /// （module_fill.dart）入队 params + push 新实例后**直接 return true，
  /// 不回调 apply**；新实例 initState `consumePending('disease_risk')` →
  /// [_applyDiseaseRisk] 真实回填 _fCtrl/_mCtrl/_rec 并 _calc 重算
  /// （参数键 father/mother/mode，与课标 3.3.6 深链 linkParams 同款）
  /// ⇒ 错题本回程按钮点得回去、参数落得上，不是摆设。
  /// v2.19.53：srcModule/srcParams 受「遗传咨询」节的新鲜度门——stale
  /// （改输入/拨开关未重算）时不传回程，错题本不会出现「参数是新的、
  /// 答案却是旧的」的错回程（照分子页 dogmaSaved / 变异页 mutSaved 先例）。
  SavePayload? _mistakePayload() {
    final i = _tab.index;
    if (i != 0) return null;
    final saved = _riskFresh;
    return SavePayload(
      stem: _mistakeStem,
      correctAnswer: _mistakeAnswer,
      subjectArea: _mistakeSubjectArea,
      srcModule: saved ? 'disease_risk' : null,
      srcParams: saved
          ? {
              'father': _fCtrl.text.trim(),
              'mother': _mCtrl.text.trim(),
              'mode': _rec ? 'rec' : 'dom',
            }
          : null,
    );
  }


  List<WorkbenchTabSpec> _tabs() => [
        WorkbenchTabSpec(
          label: '遗传咨询',
          icon: Icons.calculate_outlined,
          sidePanel: _consultInputs,
          body: _consultBody,
        ),
        WorkbenchTabSpec(
          label: '系谱推断',
          icon: Icons.account_tree_outlined,
          sidePanel: _inferenceSide,
          body: _inferenceBody,
        ),
        WorkbenchTabSpec(
          label: '分类与预防',
          icon: Icons.fact_check_outlined,
          sidePanel: _catalogSide,
          body: _catalogBody,
        ),
      ];

  /// v2.19.35：**页签下标 → `ModuleFillBus` moduleId**，次序与上面那份
  /// `_tabs()` 的页签次序一一对应。
  ///
  /// ⛔ 末位那个**空串**是刻意的：分类与预防那一栏没有可填参 target，填一个
  /// 真的 moduleId 反而会让人以为「有深链可接」。空串让
  /// `curriculumReverseCodeOf` 返回 null ⇒ 宿主**不绑** `Alt+K`。
  /// 同样地，系谱推断（`pd_inference`）没有被任何课标点名 ⇒ 那一栏也不绑。
  static const _tabModuleIds = ['disease_risk', 'pd_inference', ''];

  @override
  Widget build(BuildContext context) {
    // v2.19.28 UI 统一：废弃 4 个 _section 纵向堆叠，接入
    // ToolWorkbench（与分子/进化/倍性同款骨架）——顶部 tab 分工具，
    // 宽屏 ≥1200 左栏输入 / 右区结果，窄屏面板回渲染结果上方。
    final tabs = _tabs();
    return Scaffold(
      appBar: AppBar(
        leading: appNavButton(widget.onNavPressed),
        title: const Text('人类遗传病'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: buildWorkbenchTabBar(_tab, tabs),
        ),
        actions: [
          // v2.1 问 AI：页面上下文随带（与系谱页同链路：queueSend + 侧栏）
          TextButton.icon(
            onPressed: () {
              AiChatController.instance.queueSend('【当前工具：人类遗传病】遗传咨询计算（常染色体/伴 X 显隐）。当前输入：父亲 ${_fCtrl.text} / 母亲 ${_mCtrl.text} / 模式 ${_rec ? '隐性' : '显性'}。');
              showAiAssistant(context);
            },
            icon: Icon(Icons.psychology_outlined,
                size: 18, color: AppColors.teal),
            label: Text('问 AI',
                style: TextStyle(
                    color: AppColors.teal, fontWeight: FontWeight.w600)),
          ),
          const SizedBox(width: 8),
        ],
      ),
      // v2.19.35：`Alt+K` 宿主包住主体（**零像素**：不渲染任何东西）——
      // 从「我此刻这一栏」跳到它考的课标条目；绑哪一条由
      // `curriculumReverseCodeOf` 现算（见 `_tabModuleIds`）。
      // v2.19.49：外层再接 Alt+数字 页签直跳宿主（同零像素族；闸见
      // lib/ui/tab_jump_shortcuts.dart 文件头）。
      // v2.19.51：Ctrl+S 存当前题进错题本（页面级唯一宿主；payload 是
      // 按下那一刻现取的 ValueGetter ⇒ ToolWorkbench 切页签不让本 State
      // rebuild 也没有过期窗，B 仓 v2.19.173 抓的 stale-capture 病由构造
      // 不存在；闸见 save_mistake_key_host.dart 文件头）。
      body: SaveMistakeKeyHost(
        payload: _mistakePayload,
        child: TabJumpShortcuts(
          tab: _tab,
          child: CurriculumFocusShortcuts(
            tab: _tab,
            moduleIdsByTab: _tabModuleIds,
            child: Column(
              children: [
                if (widget.sourceLabel != null)
                  GestureDetector(
                    onTap: () => Navigator.of(context).maybePop(),
                    child: Container(
                      width: double.infinity,
                      padding:
                          const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                      decoration: BoxDecoration(
                        border: Border(
                            bottom: BorderSide(color: AppColors.border)),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.arrow_back,
                              size: 15, color: AppColors.teal),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              '来自${widget.sourceLabel} · 点击返回',
                              style: AppText.caption
                                  .copyWith(color: AppColors.ink),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                Expanded(
                  child: ToolWorkbench(
                    controller: _tab,
                    tabs: tabs,
                    railTitle: '遗传病 · 输入',
                    railIcon: Icons.calculate_outlined,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ─── Tab 1：遗传咨询计算 ───

  Widget _consultInputs(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '输入双亲基因型计算子代患病风险。常染色体用 A/a（如 Aa × aa）；'
          '伴 X 用 XAY / XAXa / XaXa 形式（大写=显性等位基因，小写=隐性——'
          '色盲模型 XaY 即患病）。',
          style: AppText.caption,
        ),
        const SizedBox(height: 8),
        _field(_fCtrl, '父亲基因型（如 Aa / XAY）', _calc),
        _field(_mCtrl, '母亲基因型（如 Aa / XAXa）', _calc),
        // v2.19.53：显隐开关只改输入、不自动重算（照变异页突变类型开关
        // 先例）——开关直接喂引擎且题干里渲染它；若此处自动重算，「只拨
        // 开关不重算」的矛盾形态在 UI 上不可达，新鲜度门对它的开关分量
        // 就形同虚设。要刷新结果，点「计算」或提交输入框。
        // 显隐开关两个芯片：**必须能折行**。
        // v2.22.0 投影修复：本栏是 ToolWorkbench 的固定 280 宽左输入栏
        // （内边距后内容 250），课堂 ×1.75 时「隐性患病 / 显性患病」两枚
        // 芯片各约 134px（选中态还多一枚勾），并排要 276 ⇒ Row 右溢 26px
        // （R13 量测网报 `[遗传病] A RenderFlex overflowed by 26 pixels`）。
        // 改 Wrap 而非缩字号/隐藏芯片：窄栏折成两行仍完整可读，宽栏
        // （窄屏时侧板铺满宽度）依旧一行并排。
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            ChoiceChip(
              label: const Text('隐性患病'),
              selected: _rec,
              onSelected: (v) => setState(() => _rec = v),
            ),
            ChoiceChip(
              label: const Text('显性患病'),
              selected: !_rec,
              onSelected: (v) => setState(() => _rec = !v),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton.icon(
            // v2.19.29（M3.1 学生 N-P1-5）：先收键盘再算——窄态结果
            // 在输入面板下方，键盘不收结果整块落在键盘底下。
            onPressed: () {
              FocusManager.instance.primaryFocus?.unfocus();
              _calc();
            },
            icon: const Icon(Icons.calculate_outlined, size: 18),
            label: const Text('计算',
                style: TextStyle(fontWeight: FontWeight.w600)),
            style: FilledButton.styleFrom(
              minimumSize: const Size(0, 38),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),
        ),
      ],
    );
  }

  Widget _consultBody(BuildContext context) {
    // v2.19.36 正向「课标 X」可点徽章：挂**结果区首行**（本栏用
    // ToolWorkbench，没有 FlatSection 标题行可挂 trailing —— 与备份仓
    // 同款挂法）。3.3.6 的 `tool` 逐字写着「遗传病速查」⇒ `disease_risk`
    // 唯一反查 3.3.6，code 由 `curriculumReverseBadgeFor` 现算
    // （⛔ 本页不建表、禁 const）。
    // ⛔ **只在算出结果后挂**：空态这一栏还没算出「这道题」，一枚可点徽章
    // 等于宣称一道**还不存在**的题考它。空态仅显示下一步操作引导，不挂徽章。
    final badge = _result == null
        ? null
        : curriculumReverseBadgeFor(context, 'disease_risk');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (badge != null) ...[
          badge,
          const SizedBox(height: 8),
        ],
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(_error!,
                style: AppText.caption
                    .copyWith(color: AppColors.lethal)),
          ),
        if (_result != null) ...[
          _kv('亲本配子',
              '父：${_result!.fatherGametes.join(' / ')}　母：${_result!.motherGametes.join(' / ')}'),
          _kv('子代基因型', _result!.offspring.entries
              .map((e) => '${e.key} ${_pct(e.value)}')
              .join('　')),
          _kv('患病概率', _pct(_result!.affectedRate),
              highlight: _result!.affectedRate > 0),
          if (_result!.carrierRate > 0)
            _kv('携带者概率', _pct(_result!.carrierRate)),
          _kv('说明', _result!.note),
        ] else if (_error == null)
          const CalculationEmptyState(
            icon: Icons.health_and_safety_outlined,
            title: '等待咨询计算：结果将在这里展开',
            description: '选择隐性或显性患病，确认双亲基因型后点「计算」。这里依次展开亲本配子、子代基因型、患病概率与携带者概率。',
          ),
      ],
    );
  }

  // ─── Tab 2：系谱推断（课标 3.2.6） ───

  Widget _inferenceSide(BuildContext context) {
    return Text('给系谱图判遗传方式：8 条规则打分 + 人话依据。'
        '逐成员录入，或点「载入经典系谱」一键开始（4 个金标准）。',
        style: AppText.caption);
  }

  Widget _inferenceBody(BuildContext context) {
    // GlobalKey 供 focusInference 直达（key 挂内容根，tab 切换后仍在树）。
    // v2.19.29（M3.1 老师 P1-3）：拍题原图挪到本 tab 顶部——原在「遗传
    // 咨询」tab，识别系谱自动跳本 tab 后学生找不到对照原图，核对链路
    // 事实断掉（v2.14 R5 专为学生走查 P0 加的能力）。
    return KeyedSubtree(
      key: _inferenceKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_scanImageB64 != null) ...[
            Text('拍题原图（核对识别结果）', style: AppText.sectionTitle),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.memory(
                base64Decode(_scanImageB64!),
                fit: BoxFit.contain,
                errorBuilder: (_, _, _) => Text(
                    '原图已不可读（可关掉此卡继续核对成员）',
                    style: AppText.caption
                        .copyWith(color: AppColors.steel)),
              ),
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => setState(() => _scanImageB64 = null),
                icon: const Icon(Icons.close, size: 16),
                label: const Text('核对完成，关闭原图'),
              ),
            ),
            const SizedBox(height: 16),
          ],
          PedigreeInferenceView(key: _inferenceViewKey),
        ],
      ),
    );
  }

  // ─── Tab 3：遗传病分类速查 + 检测与预防 ───

  Widget _catalogSide(BuildContext context) {
    return Text('点击类别查看遗传特点与常见病举例；检测与预防手段对照。',
        style: AppText.caption);
  }

  Widget _catalogBody(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('遗传病分类速查', style: AppText.sectionTitle),
        const SizedBox(height: 8),
        for (final d in diseaseCatalog)
          ExpansionTile(
            dense: true,
            leading: AppChip(d.name),
            title: Text(d.inheritance, style: AppText.caption),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                child: Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final e in d.examples) AppChip(e),
                  ],
                ),
              ),
            ],
          ),
        const SizedBox(height: 18),
        Text('检测与预防', style: AppText.sectionTitle),
        const SizedBox(height: 8),
        for (final (t, d) in const [
          ('遗传咨询', '对家庭病史进行分析，推算再发风险，提供婚育建议'),
          ('产前诊断', '羊水检查、B 超、基因检测等，在胎儿出生前确定是否患遗传病'),
          ('禁止近亲结婚', '近亲携带相同隐性致病基因概率高，显著提高隐性遗传病发病风险'),
        ])
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                    width: 92,
                    child: Text(t, style: AppText.label)),
                Expanded(child: Text(d, style: AppText.body)),
              ],
            ),
          ),
      ],
    );
  }

  Widget _field(TextEditingController ctrl, String label, VoidCallback onDone) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: TextField(
        controller: ctrl,
        decoration: InputDecoration(
            isDense: true, labelText: label, counterText: ''),
        onSubmitted: (_) => onDone(),
      ),
    );
  }

  Widget _kv(String label, String value, {bool highlight = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 92, child: Text(label, style: AppText.caption)),
          Expanded(
            child: Text(value,
                style: (highlight ? AppText.caption : AppText.body).copyWith(
                    color: highlight ? AppColors.teal : AppColors.ink,
                    fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }
}