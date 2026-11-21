// big_question_cards_page.dart —— 大题套路卡页（v2.19.24 建立 / v2.19.25 修订）
//
// 评论调研落地页：识别信号 → 套路步骤 → 易错提醒 → 一句话背下来 →
// 关联计算器深链（ModuleFillBus 直达目标页 tab + 经典例题开算）。
//
// v2.19.25 找茬甄别落盘（老师/学生/老用户三视角交叉确认的真问题）：
// - 口诀块置顶（背诵位序，学生 P2-3）+ SelectionArea（可复制，P2-4）。
// - 顶部搜索框：按题干关键词跨章反查卡（signals 现成键，学生 P1-2）。
// - 「已背熟」标记持久化 + 目录 ✓（学生 P1-1 半幅；另半幅=错题本回链，
//   见 mistake_book_page.dart）。
// - 卡底「上一张 / 下一张」（课堂翻卡动线，老师 P2-5 的部分解）。
// - 跳转改 ModuleFillBus 深链：名不副实的「去 xx tab」落地真 tab
//   （老师 P2-4 / 学生 P2-1 / 老用户 P2-3 三报告交叉）。
// - 问 AI 带上卡内容（takeaway+易错，学生 P1-4 空头支票修复）。
// - 章内单卡时副标题不显示「第 1/1 张」；目录触控加高（老师 P2-6）。
//
// v2.20.0（用户裁定：全局导航永远单栏可滚动，不许双层导航）：
// 旧布局是「AppBar 下叠一层章节 TabBar」+「宽屏 ≥1200 左 280px『本章卡片』
// 目录」，宽屏下与 HomeShell 的全局 NavigationRail 并排 ⇒ 屏幕左侧两层导航。
// 现在整页只剩**一套** [SideNavWorkbench] 顶部横向选择条（groups = 6 个章节，
// entries = 该章卡片），右区仍是当前卡正文：AppBar 不再叠章节 TabBar，
// 宽屏不再有第二列。⛔ 本页不是计算页，不走 ToolWorkbench（那是「输入面板」）。
// · 选中项 id = '$chapter:$index'，onSelect 同时改写章与卡 ⇒ 跨章点选一步直达，
//   每章 `_selected[chapter]` 记忆照旧（切走再回来还是那张卡）。
// · 选择条里没有 subtitle 位（不改 SideNavWorkbench）⇒ 已背标记改用条目
//   文本前缀 `✓ ` 表达；`_hideMastered`「只看未背」过滤直接作用于 entries
//   （若把当前卡滤掉，右区正文保持当前卡 —— 与旧右区语义一致）。
// · 正文滚动交给骨架自带的 PageStorageKey（selectedId 变化即换 key ⇒ 新卡
//   从卡首读）；选卡/翻卡另有 [_scrollBodyToTop] 的 postFrame ensureVisible
//   兜底（⛔ 不在 build 里跳滚动）。旧 `_scrollCtrl` / 每章 GlobalKey 都已删除，
//   现在只有一张正文 ⇒ 一个锚点 GlobalKey，不会出现 Duplicate GlobalKey。
// identical 短路纪律：骨架每 build 新建实例，不 const 复用。
//
// v2.19.60：给屏上那枚「去练」按钮配上键盘入口 `Alt + L`（页面级宿主
// [CardPracticeKeyHost]，仿 CardLinkKeyHost 形态）——与点按钮走**同一条**
// `_openLink`。认领判据抽成 [_hasPracticeLink]，按钮处 / 键处 / 屏上提示处
// 三处同调，⛔ 不是 `linkModuleId != null`（见 [_hasPracticeLink] 注释）。
//
// v2.19.61（创新提案 #6 v1）：套路步骤「遮着背」自测态——把套路卡从
// 「读」变成「自己先想」。点标题行那枚「遮着背」后，每条步骤变成一块
// 灰遮罩（文字不显示，只印「第 N 步 · 点我揭示」），点哪条揭示哪条；
// 揭示区尾部两枚动作：把这步存进错题本（连卡名 + 步号拼题干，步骤全文
// 进答案）、问 AI 讲这步（带前后步骤上下文）。
//
// ⛔ v1 明确不做（v2 方向，不是遗漏）：
//  ① 自测进度**不落盘**（不开 store schema——本页 State 内 `_revealed`，
//     退出页面即忘；v2 若要「上周卡在第几步」的复习动线再迁
//     BigQuestionCardsStore 并写迁移测试）；
//  ② **不与** `Alt + L` 去练 / `CardPracticeKeyHost` 合并（那条链路
//     的判据 [_hasPracticeLink] 一个字都不动——自测态是纯展示态切换，
//     去练按钮在自测态下照旧可点、`Alt + L` 照旧认领）；
//  ③ **不做**步骤乱序抽考（打乱顺序 = 另一套「哪步在前」的判据，
//     与「套路步骤有序」这一数据契约直接冲突，须先定清语义）。
// 视觉不变量：默认（背卡）态**一个像素都不变**——遮罩行 / 两个小按钮 /
// 尾部两枚动作全部只在自测态挂载；标题行那枚开关本身做成**不超过标题
// 文字行高**的紧凑按钮（见 [_selfTestToggle]），否则标题行变高会把整页
// 内容下移，p10 golden 的差异就不再局限在标题行那一条带。

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/big_question_cards.dart';
import '../state/big_question_cards_store.dart';
import '../state/first_run_store.dart';
import '../state/mistake_book.dart';
import '../theme.dart';
import '../ui/ai_chat_controller.dart';
import '../ui/assistant_panel.dart';
import '../ui/module_fill.dart';
import '../ui/page_activation.dart';
import '../ui/shortcut_nudge.dart';
import '../ui/step_chain.dart';
import 'widgets/cross_tool_rail.dart' show FlatSection;
import 'widgets/side_nav_workbench.dart';

/// v2.19.61：套路卡的「考点」文案——错题本按 `subjectArea` 反查回链
/// （`linkedCardIdOf` → `findCardIdForTopic`），所以这里**不能**写卡 id
/// （`findCardIdForTopic('xipu-koujue')` 返 null），要写 `kCardTopicKeywords`
/// 里这张卡的**领起关键词**：它经 [findCardIdForTopic] 反查恰好回到卡 id，
/// 学生在错题本里点「看套路卡」就能回到刚卡住的那张卡。
/// 表里查不到时兜底写卡 id（回链失效但条目仍带得住出处）。
String subjectAreaForBigQuestionCard(BigQuestionCard card) {
  final keywords = kCardTopicKeywords[card.id];
  if (keywords != null && keywords.isNotEmpty) return keywords.first;
  return card.id;
}

/// v2.19.61：「这一步卡住了」的题干。
/// 例：`套路卡「显隐性判断三步」第 2 步没记住：能自交就自交`。
/// ⛔ 步骤全文只进 correctAnswer；题干只带**领起短语**（[stepLeadOf]）。
String stuckStepStem(BigQuestionCard card, int index) =>
    '套路卡「${card.title}」第 ${index + 1} 步没记住：'
    '${stepLeadOf(card.steps[index])}';

/// v2.19.61：步骤的「领起短语」——到第一个分句边界（：，。；及半角）为止，
/// 最长 20 字（截断补省略号）。学生一看就想起是哪一步，又不至于把答案
/// 全印在题干上（错题本列表直接展开题干）。
String stepLeadOf(String step) {
  final t = step.trim();
  if (t.isEmpty) return '';
  var cut = t.length;
  for (final p in const ['：', '，', '。', '；', ':', ',', ';']) {
    final k = t.indexOf(p);
    if (k > 0 && k < cut) cut = k;
  }
  final lead = t.substring(0, cut);
  return lead.length <= 20 ? lead : '${lead.substring(0, 20)}…';
}

class BigQuestionCardsPage extends StatefulWidget {
  const BigQuestionCardsPage({
    super.key,
    this.onOpenTool,
    this.initialCardId,
  });

  /// 关联工具跳转（HomeShell 注入 → _selectWithReturn，自动带回程横幅）。
  final void Function(int navIndex)? onOpenTool;

  /// v2.19.25：错题本「看套路卡」回链——初始定位到指定卡。
  final String? initialCardId;

  @override
  State<BigQuestionCardsPage> createState() => _BigQuestionCardsPageState();
}

class _BigQuestionCardsPageState extends State<BigQuestionCardsPage> {
  /// v2.20.0：当前章（取代 TabController —— 页签行已经收掉，见文件头）。
  /// 唯一的选择态真相是 `'$_chapter:${_selected[_chapter]}'`。
  int _chapter = 0;

  /// 每章当前选中的卡（State 持有 → 跨章来回不丢选择）。
  final List<int> _selected =
      List<int>.filled(bigQuestionChapters.length, 0);

  /// v2.19.25：跨章反查关键词（学生 P1-2——signals 是现成反查键）。
  final _searchCtrl = TextEditingController();
  String _query = '';

  /// v2.19.26（学生 P2-2）：已背总览旁的「只看未背」过滤。
  /// v2.20.0：过滤作用在顶部选择条的 entries 上（见 [_navEntriesOf]）。
  bool _hideMastered = false;

  /// v2.20.0：正文锚点（选卡 / 翻卡 / 搜索直达后把正文拉回卡首）。
  /// 同一时刻只有一张正文挂在树上 ⇒ 一个 GlobalKey 就够，不存在重复键
  ///（旧版按章建 key 是给 TabBarView 动画期相邻两 pane 用的，已无必要）。
  final _bodyAnchor = GlobalKey(debugLabel: 'cards-body-anchor');

  /// v2.19.61：套路步骤「遮着背」自测态开关。页面级（跨章 / 翻卡都保留
  /// 自测态——学生背卡动线上「一路遮着背下去」是常态），默认 false ⇒
  /// 与 v2.19.60 的渲染逐像素一致。
  bool _selfTest = false;

  /// v2.19.61：每张卡**已揭示**的步骤下标集合（card.id → {下标}）。
  /// ⛔ 挂在两张卡之间会串味（A 卡揭了第 2 步，翻到 B 卡不该已经露着），
  /// 所以按卡 id 分桶，而不是存一个全局 Set。
  final Map<String, Set<int>> _revealed = <String, Set<int>>{};

  /// v2.19.61：每张卡**最近揭示**的那一步（card.id → 下标）——尾部两枚
  /// 动作（存进错题本 / 问 AI）说的都是「刚才卡住的那一步」，就是它。
  /// 「重新遮」时一并清掉（没有已揭示的步骤 ⇒ 两枚动作不渲染）。
  final Map<String, int> _revealedLast = <String, int>{};

  static const _icons = <String, IconData>{
    'filter_1': Icons.filter_1,
    'filter_2': Icons.filter_2,
    'filter_3': Icons.filter_3,
    'filter_4': Icons.filter_4,
    'filter_5': Icons.filter_5,
    'filter_6': Icons.filter_6,
  };

  @override
  void initState() {
    super.initState();
    // 错题本回链：初始定位指定卡（章 + 卡双索引）。
    final initId = widget.initialCardId;
    if (initId != null) {
      final pos = findCardIndexById(initId);
      if (pos != null) {
        _selected[pos.$1] = pos.$2;
        _chapter = pos.$1;
      }
    }
    BigQuestionCardsStore.load();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  /// 选卡统一入口（目录 pill / 搜索直达 / 上一张下一张共用）：章与卡一起
  /// 落定 + 滚回卡首。⛔ 滚动一定在 postFrame 里做，build 期间不动滚动。
  void _selectCard(int chapter, int index) {
    setState(() {
      _chapter = chapter;
      _selected[chapter] = index;
    });
    _scrollBodyToTop();
  }

  /// v2.20.0 选择条回调：条目 id = '$chapter:$index' ⇒ 一次点选跨章直达，
  /// 章与卡同时改写（这就是宽屏「第二列目录」被收掉后唯一的换章动线）。
  void _onNavSelect(String id) {
    final sep = id.indexOf(':');
    if (sep <= 0) return;
    final chapter = int.tryParse(id.substring(0, sep));
    final index = int.tryParse(id.substring(sep + 1));
    if (chapter == null || index == null) return;
    if (chapter < 0 || chapter >= bigQuestionChapters.length) return;
    _selectCard(chapter, index);
  }

  /// 把正文拉回卡首（口诀置顶位）。正文滚动由骨架的 PageStorageKey 承载，
  /// 这里只做「偏移不是 0」的兜底。目标是让新卡从口诀所在的卡首开始读，
  /// 所以显式 alignment=0；不要换成 revealInViewport 的「已可见即 no-op」
  /// 语义——那只适合揭示选中导航，不适合强制回正文首。
  void _scrollBodyToTop() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final ctx = _bodyAnchor.currentContext;
      if (ctx == null) return;
      Scrollable.ensureVisible(ctx,
          alignment: 0, duration: const Duration(milliseconds: 250));
    });
  }

  /// v2.20.0：顶部选择条的 6 个章节分组 —— entries = 该章卡片
  /// （id = '$chapter:$index'，全局唯一；选中态与内容路由共用）。
  ///
  /// 已背标记走**文本前缀**（骨架没有 subtitle 位）：`✓ 卡名`。
  /// 「只看未背」过滤直接作用在 entries 上；某章被滤空就不出这一组
  ///（留一个空组名 + 分隔线在横条里是纯噪音）。当前卡若被滤掉，右区正文
  /// 仍保持它（与旧右区语义一致），只是横条里没有高亮项。
  List<SideNavGroup> _groups() {
    final groups = <SideNavGroup>[];
    for (var c = 0; c < bigQuestionChapters.length; c++) {
      final entries = _navEntriesOf(c);
      if (entries.isEmpty) continue; // 被「只看未背」滤空的章不出空组名
      groups.add(SideNavGroup(
        label: bigQuestionChapters[c].title,
        icon: _icons[bigQuestionChapters[c].iconName],
        entries: entries,
      ));
    }
    return groups;
  }

  List<SideNavEntry> _navEntriesOf(int chapter) {
    final cards = bigQuestionChapters[chapter].cards;
    return [
      for (var i = 0; i < cards.length; i++)
        if (!_hideMastered || !BigQuestionCardsStore.isMastered(cards[i].id))
          SideNavEntry(
            id: '$chapter:$i',
            // 卡片全称本来就是 3–10 字，窄屏 pill 直接用全称（不另造缩写，
            // 少一个「两套叫法」的分歧点）；将来真出现长卡名再补 shortLabel。
            label: _entryLabel(cards[i]),
          ),
    ];
  }

  String _entryLabel(BigQuestionCard card) =>
      BigQuestionCardsStore.isMastered(card.id)
          ? '✓ ${card.title}'
          : card.title;

  /// v2.19.60：此刻屏上那张卡（当前章 × 当前选中位）。页级键 `Alt + L` 的
  /// 两个回调都从它现取——切章 / 翻卡后不滞留旧卡（与 `CardLinkKeyHost` 的
  /// ValueGetter 论证同款）。索引一律 clamp，防越界。
  BigQuestionCard _visibleCard() {
    final ci = _chapter.clamp(0, bigQuestionChapters.length - 1);
    final chapter = bigQuestionChapters[ci];
    final idx = _selected[ci].clamp(0, chapter.cards.length - 1);
    return chapter.cards[idx];
  }

  /// v2.19.60：屏上那枚「去练」按钮**此刻真的存在** ⇔ 页级键 `Alt + L` 认领。
  ///
  /// ⛔ 判据必须与屏上按钮**逐字同源**（不许写第二份）：按钮的渲染条件是
  /// `card.linkLabel != null && card.linkNavIndex != null`（见 `_cardDetail` 里
  /// 那枚 `OutlinedButton.icon`），⛔ **不是** `card.linkModuleId != null`——
  /// 后者只是 `_openLink` 体内的**第一条**深链分支，两者**不是同一个判据**。
  /// 出厂 14 张卡三个字段恰好都非空（实测）⇒ 两种写法今天**行为完全相同**，
  /// 但那只是巧合，不是契约。
  ///
  /// ⛔ 写成 `linkModuleId != null` 就是「屏上撒谎」的另一副面孔：将来多一张
  /// 只有 `linkModuleId` 而没有 `linkLabel` 的卡，键会认领、屏上却没有按钮
  /// （按下去看不见任何东西）；反过来多一张只有 `linkLabel`/`linkNavIndex`
  /// 的卡，按钮在、键却哑了。⇒ 抽成**一个**方法，按钮处 / 键处 / 屏上提示处
  /// 三处同调它。
  bool _hasPracticeLink(BigQuestionCard card) =>
      card.linkLabel != null && card.linkNavIndex != null;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('大题套路卡'),
        // v2.20.0：⛔ 不再叠章节 TabBar（bottom 整块删掉）—— 那正是与
        // HomeShell 全局 Rail 叠成双层导航的那一层；换章交给正文上方的
        // 唯一一条选择条（SideNavWorkbench）。
        actions: [
          TextButton.icon(
            onPressed: () {
              // v2.19.25 学生 P1-4 / v2.19.26 老师 P3-12 补识别信号：
              // prompt 带全卡核心（口诀 + 信号 + 易错），否则 AI 只能猜。
              final chapter = bigQuestionChapters[_chapter];
              final card = _visibleCard();
              AiChatController.instance.queueSend(
                  '【当前工具：大题套路卡】${chapter.title}·${card.title}\n'
                  '一句话背下来：${card.takeaway}\n'
                  '识别信号：${card.signals.join('；')}\n'
                  '易错提醒：${card.pitfalls.join('；')}\n'
                  '请围绕这张卡的识别信号和易错点给我出 1 道同类大题。');
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
      // v2.19.60：页面级 `Alt + L` = 去练宿主（零像素，见 [CardPracticeKeyHost]）。
      // 两个回调都在**按下那一刻**现取屏上那张卡（切章 / 翻卡后不滞留旧卡）。
      body: CardPracticeKeyHost(
        hasPracticeLink: () => _hasPracticeLink(_visibleCard()),
        onOpen: () => _openLink(_visibleCard()),
        // v2.20.0：整套导航只剩这一条（骨架自带横向滚动 + 选中项揭示）。
        // ⛔ 外层 ListenableBuilder 是必要的：已背 ✓ 前缀与「只看未背」过滤
        // 都写在 entries 上，标完已背必须让横条重建（旧版是给目录包了一层）。
        child: ListenableBuilder(
          listenable: BigQuestionCardsStore.mastered,
          builder: (context, _) => SideNavWorkbench(
            groups: _groups(),
            selectedId: '$_chapter:${_selected[_chapter]}',
            onSelect: _onNavSelect,
            body: _content,
          ),
        ),
      ),
    );
  }

  // ─── 右区正文顶部：搜索 + 已背总览 ───

  Widget _masteryStrip() => ListenableBuilder(
        listenable: BigQuestionCardsStore.mastered,
        builder: (context, _) {
          final total =
              bigQuestionChapters.fold<int>(0, (n, c) => n + c.cards.length);
          final done = BigQuestionCardsStore.mastered.value.length;
          final allDone = done >= total;
          return Row(children: [
            Icon(Icons.check_circle_outline,
                size: 14,
                color: allDone ? AppColors.teal : AppColors.steel),
            const SizedBox(width: 6),
            Expanded(
              child: Text('已背 $done/$total',
                  style: AppText.caption.copyWith(
                      color: allDone ? AppColors.teal : AppColors.steel)),
            ),
            // v2.19.26（手机 P2-4 / 平板 F-7）：裸 GestureDetector 包 12px
            // 文字命中区 ≈50×18 触屏偏小——改 InkWell + 纵向 padding，
            // 命中区 ≥40 高，视觉不变。
            InkWell(
              onTap: () => setState(() => _hideMastered = !_hideMastered),
              borderRadius: BorderRadius.circular(4),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                child: Text(
                  _hideMastered ? '显示全部' : '只看未背',
                  style: AppText.caption.copyWith(
                      color: AppColors.teal,
                      fontWeight: FontWeight.w600,
                      decoration: TextDecoration.underline,
                      decorationColor: AppColors.teal),
                ),
              ),
            ),
          ]);
        },
      );

  /// v2.20.0：右区正文 = 搜索框 + 已背总览（+ 搜索命中列表）+ 当前卡。
  /// 原「左栏」的三件事（搜索 / 已背总览 / 目录）一件都没丢：搜索与总览挪到
  /// 正文顶部，目录交给顶部选择条（一进页就看得见，不用先切列）。
  Widget _content(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _searchBox(),
          const SizedBox(height: 8),
          _masteryStrip(),
          if (_query.isNotEmpty) ...[
            const SizedBox(height: 10),
            ..._searchResults(),
          ],
          const SizedBox(height: 10),
          // 正文锚点：选卡 / 翻卡 / 搜索直达后 [_scrollBodyToTop] 定位到这里。
          KeyedSubtree(
            key: _bodyAnchor,
            child: _cardDetail(context, _chapter),
          ),
        ],
      );

  /// 跨章反查（学生 P1-2 / 老师 P2-4，v2.19.26 扩召回）：标题 / 识别
  /// 信号 / 口诀 / 套路步骤 / 易错提醒全部入索引（原只索引前三类，
  /// 「半保留」等步骤术语 0 命中）。
  Widget _searchBox() => TextField(
        controller: _searchCtrl,
        onChanged: (v) => setState(() => _query = v.trim()),
        decoration: InputDecoration(
          isDense: true,
          hintText: '按题干关键词找卡：色盲 / 9331 / 15N…',
          hintStyle: AppText.caption,
          prefixIcon: Icon(Icons.search, size: 16, color: AppColors.steel),
          suffixIcon: _query.isEmpty
              ? null
              : IconButton(
                  icon: Icon(Icons.close, size: 16, color: AppColors.steel),
                  onPressed: () {
                    _searchCtrl.clear();
                    setState(() => _query = '');
                  },
                ),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        ),
      );

  List<Widget> _searchResults() {
    final q = _query.toLowerCase();
    final hits = <({int ch, int idx, BigQuestionCard card})>[];
    for (var c = 0; c < bigQuestionChapters.length; c++) {
      final cards = bigQuestionChapters[c].cards;
      for (var i = 0; i < cards.length; i++) {
        final card = cards[i];
        final hay = '${card.title} ${card.signals.join(' ')} '
                '${card.takeaway} ${card.steps.join(' ')} '
                '${card.pitfalls.join(' ')}'
            .toLowerCase();
        if (hay.contains(q)) hits.add((ch: c, idx: i, card: card));
      }
    }
    if (hits.isEmpty) {
      return [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Text('没有命中的卡，换个关键词试试',
              style: AppText.caption.copyWith(color: AppColors.steel)),
        ),
      ];
    }
    return [
      for (final h in hits)
        _TocItem(
          // v2.20.0：命中项挂稳定 key——选择条里也有同名正文（pill 用卡名），
          // 自动化与调试都按 key 定位，不靠「第几个同名文本」这种脆判据。
          key: ValueKey('cardHit:${h.card.id}'),
          index: h.idx,
          card: h.card,
          leading: Text(bigQuestionChapters[h.ch].title,
              style: AppText.caption.copyWith(color: AppColors.teal)),
          onTap: () {
            // 点选即直达：先切卡（章 + 卡一起），再清搜索词。
            _selectCard(h.ch, h.idx);
            setState(() {
              _query = '';
              _searchCtrl.clear();
            });
          },
        ),
    ];
  }

  // ─── 右区：卡内容 ───

  Widget _cardDetail(BuildContext context, int chapterIndex) {
    final chapter = bigQuestionChapters[chapterIndex];
    final idx = _selected[chapterIndex].clamp(0, chapter.cards.length - 1);
    final card = chapter.cards[idx];
    // 正文锚点由外层 [_content] 的 KeyedSubtree 挂 `_bodyAnchor`（唯一一个）。
    return SelectionArea(
      child: FlatSection(
        title: card.title,
        // v2.19.25：章内只有 1 张卡时不显示「第 1/1 张」（观感找茬落盘）。
        subtitle: chapter.cards.length > 1
            ? '${chapter.title} · 第 ${idx + 1}/${chapter.cards.length} 张'
            : chapter.title,
        trailing: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: AppColors.tealWash,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppColors.border),
          ),
          child: Text(card.tag, style: AppText.caption),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // v2.19.25 学生 P2-3：口诀置顶——「考前 5 分钟扫一遍」最先看到。
            _takeawayBox(card),
            const SizedBox(height: 18),
            _block(
              title: '识别信号',
              icon: Icons.radar_outlined,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final s in card.signals) _bullet(s),
                ],
              ),
            ),
            _block(
              title: '套路步骤',
              icon: Icons.account_tree_outlined,
              // v2.19.61：标题行那枚「遮着背」开关（默认态也在，学生得
              // 先看得见它才谈得上用）。⛔ 高度不超过标题文字行，否则
              // 整页内容下移（见 [_selfTestToggle] 注释与 S4 等高判据）。
              trailing: _selfTestToggle(),
              child: _selfTest
                  ? _selfTestSteps(card, chapter.title)
                  : StepChain(
                      steps: [
                        for (var i = 0; i < card.steps.length; i++)
                          // 末步用 result 样式——套路的最后一步就是落笔结论
                          // （老用户 P3-5：全部 compute 会被 StepChain 自动套
                          // 末步 result 样式，语义反而拧着，不如显式）。
                          i == card.steps.length - 1
                              ? ChainStep.result('第 ${i + 1} 步',
                                  detail: card.steps[i])
                              : ChainStep.compute('第 ${i + 1} 步',
                                  detail: card.steps[i]),
                      ],
                    ),
            ),
            _block(
              title: '易错提醒',
              icon: Icons.error_outline,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final p in card.pitfalls) _bullet(p, warn: true),
                ],
              ),
            ),
            // 背诵标记 + 关联工具 + 章内翻卡（v2.19.25）。
            // Wrap 而非 Row+Spacer：390 窄屏下三个按钮装一行会
            // RenderFlex 右溢出 158px（实测），Wrap 自动换行。
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                _masterButton(card),
                // v2.19.60：按钮与页级键 `Alt + L` 共用**同一个**判据
                // （_hasPracticeLink）⇒「有按钮 ⇔ 键认领 ⇔ 屏上有提示」三处
                // 永远同宽，不存在「键认领了屏上却没按钮」那种分裂。
                if (_hasPracticeLink(card)) ...[
                  OutlinedButton.icon(
                    onPressed: () => _openLink(card),
                    icon: Icon(Icons.open_in_new,
                        size: 16, color: AppColors.teal),
                    label: Text(card.linkLabel!,
                        style: TextStyle(color: AppColors.teal)),
                  ),
                  // v2.19.60：屏上提示。⛔ 只在按钮存在时渲染（与认领条件
                  // 同一个判据）——按钮不在，这一行字也一并消失。文案零
                  // markdown 星号、零方向词（读屏软件也读得懂）。
                  Text('按 Alt+L 去练',
                      style: AppText.caption.copyWith(
                          color: AppColors.steel)),
                ],
                if (chapter.cards.length > 1) ...[
                  _pageBtn('上一张', Icons.chevron_left, () =>
                      _selectCard(chapterIndex,
                          (idx - 1 + chapter.cards.length) %
                              chapter.cards.length)),
                  _pageBtn('下一张', Icons.chevron_right, () =>
                      _selectCard(chapterIndex,
                          (idx + 1) % chapter.cards.length)),
                ],
              ],
            ),
          ],
          ),
        ),
      );
  }

  /// 一句话背下来（置顶块）。
  Widget _takeawayBox(BigQuestionCard card) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.tealWash,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.lightbulb_outline, size: 18, color: AppColors.teal),
            const SizedBox(width: 8),
            Expanded(
              child: Text.rich(
                TextSpan(children: [
                  TextSpan(
                      text: '一句话背下来：',
                      style:
                          AppText.body.copyWith(color: AppColors.graphite)),
                  TextSpan(text: card.takeaway),
                ]),
                style: AppText.body.copyWith(color: AppColors.ink),
              ),
            ),
          ],
        ),
      );

  // ─── v2.19.61：套路步骤「遮着背」自测态 ───

  /// 标题行那枚开关。⛔⛔ 尺寸纪律：本按钮的**布局高度必须 ≤ 标题文字行**
  /// （`AppText.label` = 13px/默认行高）——标题 Row 的高度取子项最大值，
  /// 一旦这枚按钮更高，套路步骤标题行就变高，**整张卡（乃至整页）的内容
  /// 统统下移**，p10 golden 的差异从「标题行那一条带」扩成「从标题行到页
  /// 底」，`cards_step_selftest_test` S4 的等高判据会红。⇒ `minimumSize:
  /// Size.zero` + 纵向 padding 0 + `shrinkWrap` + `VisualDensity.compact`
  /// + 文案行高 1.0（12px），实测比标题行矮一档；牺牲的是触控高度（宽度
  /// 仍有 ~70px），本页的主要动线在下方几条大遮罩行上，它是次级开关。
  Widget _selfTestToggle() => TextButton.icon(
        onPressed: _toggleSelfTest,
        style: TextButton.styleFrom(
          minimumSize: Size.zero,
          padding: const EdgeInsets.symmetric(horizontal: 6),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          visualDensity: VisualDensity.compact,
          foregroundColor: AppColors.teal,
        ),
        icon: Icon(
          _selfTest ? Icons.visibility_outlined : Icons.visibility_off_outlined,
          size: 13,
          color: AppColors.teal,
        ),
        label: Text(
          _selfTest ? '展开恢复' : '遮着背',
          style: AppText.caption.copyWith(
              color: AppColors.teal,
              fontWeight: FontWeight.w600,
              height: 1.0),
        ),
      );

  void _toggleSelfTest() => setState(() {
        _selfTest = !_selfTest;
        // 收起自测态 = 回到背卡态：揭示记录一并清掉，下次进来还是**全新
        // 一张卡**（否则「遮着背」第二次打开时上一轮的答案还露着，自测
        // 就成了复读）。
        if (!_selfTest) {
          _revealed.clear();
          _revealedLast.clear();
        }
      });

  void _revealStep(String cardId, int index) => setState(() {
        (_revealed[cardId] ??= <int>{}).add(index);
        // ⛔ 覆盖而非「保留第一条」：尾部两枚动作说的是**最后**揭示的那步
        //（学生每点一条就是又背到一条，卡住的地方随之往后走）。
        _revealedLast[cardId] = index;
      });

  void _revealAllSteps(String cardId, int count) => setState(() {
        _revealed[cardId] = {for (var i = 0; i < count; i++) i};
        _revealedLast[cardId] = count - 1;
      });

  void _remaskSteps(String cardId) => setState(() {
        _revealed[cardId] = <int>{};
        _revealedLast.remove(cardId);
      });

  /// 自测态的步骤区：遮罩行 / 已揭示行交替 + 区尾按钮。
  Widget _selfTestSteps(BigQuestionCard card, String chapterTitle) {
    final revealed = _revealed[card.id] ?? const <int>{};
    final last = _revealedLast[card.id];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < card.steps.length; i++) ...[
          if (i > 0) const SizedBox(height: 8),
          revealed.contains(i)
              ? _revealedStepRow(card, i, highlighted: last == i)
              : _maskedStepRow(card, i),
        ],
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            _smallBtn('全部揭示', Icons.done_all, () {
              _revealAllSteps(card.id, card.steps.length);
            }),
            _smallBtn('重新遮', Icons.visibility_off_outlined, () {
              _remaskSteps(card.id);
            }),
          ],
        ),
        // ⛔ 尾部两枚动作只在「已经有一步被揭示」时渲染：一步都没揭示时
        // 「这一步」无所指，渲染出来就是两枚按了没意义的按钮。
        if (revealed.isNotEmpty) ...[
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _smallBtn('这步卡住了，存进错题本', Icons.bookmark_add_outlined,
                  () => _saveStuckStep(card, last!)),
              _smallBtn('问 AI 讲这步', Icons.psychology_outlined,
                  () => _askAiAboutStep(card, chapterTitle, last!)),
            ],
          ),
        ],
      ],
    );
  }

  /// 小号文字按钮（自测态内的四枚动作共用）：与标题行开关同一套紧凑口径，
  /// ⛔ 不引主题级 OutlinedButton（52px 触控标准会把自测区撑得很散）。
  Widget _smallBtn(String label, IconData icon, VoidCallback onTap) =>
      TextButton.icon(
        onPressed: onTap,
        style: TextButton.styleFrom(
          foregroundColor: AppColors.teal,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          visualDensity: VisualDensity.compact,
        ),
        icon: Icon(icon, size: 15, color: AppColors.teal),
        label: Text(label,
            style: AppText.caption.copyWith(
                color: AppColors.teal, fontWeight: FontWeight.w600)),
      );

  /// 遮罩行：文字**不显示**，只印「第 N 步 · 点我揭示」。整行可点。
  /// 底色用 surfaceLow + 边框，形状与已揭示行同宽同圆角（揭示那一下
  /// 只在这条上长高，不会横向跳）。
  Widget _maskedStepRow(BigQuestionCard card, int i) => Material(
        color: AppColors.surfaceLow,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () => _revealStep(card.id, i),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.border),
            ),
            child: Row(
              children: [
                Icon(Icons.visibility_off_outlined,
                    size: 14, color: AppColors.steel),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('第 ${i + 1} 步 · 点我揭示',
                      style: AppText.body.copyWith(color: AppColors.steel)),
                ),
              ],
            ),
          ),
        ),
      );

  /// 已揭示行：真文 + teal 左边条（「已揭示」的恒定标记）；**最近**揭示的
  /// 那一条再叠一层 tealWash —— 这就是「高亮一次」。⛔ 不用动画/计时器：
  /// 高亮态由 State 唯一决定，golden 与窄屏断言都确定（跑完就自动淡出那种
  /// 一闪而过的高亮既难断言，学生也可能刚好没看见）。
  Widget _revealedStepRow(BigQuestionCard card, int i,
          {required bool highlighted}) =>
      Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(9, 8, 12, 8),
        decoration: BoxDecoration(
          color: highlighted ? AppColors.tealWash : Colors.transparent,
          // ⛔ 只给 left 一条边、且**不给 borderRadius**——Flutter 的
          // BoxDecoration 不允许「非均匀 border + 圆角」同时出现（断言）。
          border: Border(left: BorderSide(color: AppColors.teal, width: 3)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('第 ${i + 1} 步',
                style: AppText.label.copyWith(color: AppColors.teal)),
            const SizedBox(height: 2),
            Text(card.steps[i], style: AppText.body),
          ],
        ),
      );

  /// 「这一步卡住了」→ 错题本。
  ///
  /// 题干 = `套路卡「卡名」第 N 步没记住：<步骤领起短语>`；步骤**全文**
  /// 只进 correctAnswer（⛔ 题干里带上答案，复习时等于白送）；考点用
  /// [subjectAreaForBigQuestionCard]（错题本「看套路卡」回链靠它反查）；
  /// 错因用 concept（自测卡住 = 这一步的做法没进脑子，不是算错数）。
  void _saveStuckStep(BigQuestionCard card, int i) {
    final messenger = ScaffoldMessenger.of(context);
    final stem = stuckStepStem(card, i);
    // 老师角色守卫：错题本是学生私人空间（与 saveToMistakeBook 同一口径，
    // 全仓「存错题」入口一个不少）。
    if (FirstRunStore.instance.currentRole() == UserRole.teacher) {
      messenger.clearSnackBars();
      messenger.showSnackBar(const SnackBar(
          content:
              Text('错题本是学生功能，老师模式下不可写入；如需收藏请先切换使用角色')));
      return;
    }
    final r = MistakeBook.instance.addOrFind(
      stem: stem,
      // 自测没有「作答」这件事 ⇒ 空串（不是占位串，见 saveToMistakeBook
      // 的 userAnswer 纪律）。
      userAnswer: '',
      correctAnswer: card.steps[i],
      errorType: MistakeErrorType.concept,
      subjectArea: subjectAreaForBigQuestionCard(card),
    );
    messenger.clearSnackBars();
    if (!r.isNew) {
      // 同卡同步查重（题干逐字相同 ⇒ addOrFind 命中旧条目）：⛔ 不重复
      // 入库、不重复入队 AI 整理，回执与「已加入」区分开。
      messenger.showSnackBar(
          const SnackBar(content: Text('这步已在错题本里')));
      return;
    }
    // 与拍题/表单/计算器入口同款：入队 AI 自动整理（fire-and-forget）。
    MistakeBook.instance.debugEnqueueAiOrganize(r.entry.id);
    messenger.showSnackBar(SnackBar(
        content: Text('已加入错题本：套路卡「${card.title}」第 ${i + 1} 步')));
  }

  /// 「问 AI 讲这步」：卡名 + 这一步全文 + 前后步骤上下文。
  void _askAiAboutStep(BigQuestionCard card, String chapterTitle, int i) {
    final prev = i > 0 ? card.steps[i - 1] : null;
    final next = i < card.steps.length - 1 ? card.steps[i + 1] : null;
    AiChatController.instance.queueSend(
        '【当前工具：大题套路卡】$chapterTitle·${card.title}\n'
        '我背到第 ${i + 1} 步卡住了，这一步是：${card.steps[i]}\n'
        '${prev == null ? '' : '它的前一步：$prev\n'}'
        '${next == null ? '' : '它的后一步：$next\n'}'
        '请把这一步讲透：题目里出现什么信号时该用它、为什么必须这么做、'
        '最容易错在哪。');
    showAiAssistant(context);
  }

  /// 已背熟标记（学生 P1-1）：目录同步 ✓，持久化到本地。
  Widget _masterButton(BigQuestionCard card) => ListenableBuilder(
        listenable: BigQuestionCardsStore.mastered,
        builder: (context, _) {
          final done = BigQuestionCardsStore.isMastered(card.id);
          return TextButton.icon(
            onPressed: () => BigQuestionCardsStore.toggle(card.id),
            icon: Icon(
              done ? Icons.check_circle : Icons.check_circle_outline,
              size: 16,
              color: done ? AppColors.teal : AppColors.steel,
            ),
            label: Text(done ? '已背熟' : '标为已背熟',
                style: TextStyle(
                    color: done ? AppColors.teal : AppColors.steel)),
          );
        },
      );

  Widget _pageBtn(String label, IconData icon, VoidCallback onTap) =>
      // v2.19.26（老师 P2-2）：删除 minimumSize 36 覆盖——课堂主题
      // outlinedButtonTheme 的 52px 触控标准被 widget 级样式顶掉，
      // 与同页「已背熟/关联工具」不一致（ pedigree_bottom_bar 同型
      // 事故修复先例）。交回主题接管。
      OutlinedButton.icon(
        onPressed: onTap,
        icon: Icon(icon, size: 16, color: AppColors.graphite),
        label: Text(label, style: TextStyle(color: AppColors.graphite)),
      );

  /// v2.19.26：深链优先（ModuleFillBus 直达 tab + 例题开算），未注册或
  /// 失败时回退主导航索引跳转（测试环境无 target 走此分支）。
  /// 三找茬代理交叉 P1：从错题本 push 进来的实例（onOpenTool==null）
  /// fill 只切底层 IndexedStack——被本页路由盖住，按钮看着能点、
  /// 点了零反应。修：fill 成功后弹出本页路由回到底层（popUntil
  /// 根路由），让被切到的目标页真正出现在眼前。
  void _openLink(BigQuestionCard card) {
    final mid = card.linkModuleId;
    if (mid != null &&
        ModuleFillBus.fill(mid, card.linkParams ?? const {})) {
      if (widget.onOpenTool == null &&
          Navigator.of(context, rootNavigator: true).canPop()) {
        Navigator.of(context, rootNavigator: true)
            .popUntil((route) => route.isFirst);
      }
      return;
    }
    final onOpenTool = widget.onOpenTool;
    final nav = card.linkNavIndex;
    if (onOpenTool != null && nav != null) onOpenTool(nav);
  }

  Widget _block(
          {required String title,
          required IconData icon,
          required Widget child,
          // v2.19.61：标题行右侧附加控件（自测开关）。null = 逐像素同旧版。
          Widget? trailing}) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ⛔ key 只给测试量高度用（S4 的「标题行没被开关撑高」判据），
            // 不加任何视觉/布局。
            Row(
              key: ValueKey('blockTitle:$title'),
              children: [
                Icon(icon, size: 15, color: AppColors.steel),
                const SizedBox(width: 6),
                Text(title, style: AppText.label),
                if (trailing != null) ...[
                  const SizedBox(width: 8),
                  trailing,
                ],
              ],
            ),
            const SizedBox(height: 8),
            child,
          ],
        ),
      );

  Widget _bullet(String text, {bool warn = false}) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 7),
              child: Container(
                width: 5,
                height: 5,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: warn ? AppColors.lethal : AppColors.teal,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(child: Text(text, style: AppText.body)),
          ],
        ),
      );
}

/// v2.19.60：页面级「`Alt + L` 去练」宿主（套路卡页）。
///
/// 与 `CardLinkKeyHost` / `SaveMistakeKeyHost` / `TabJumpShortcuts` 同一套
/// 论证：`CallbackShortcuts` 沿焦点链冒泡，焦点落在页面子树之外（Rail / FAB /
/// 刚点过的按钮）时收不到键；本宿主走 `HardwareKeyboard.addHandler`
/// （dispose 摘掉），对不关心的键一律返回 false。
///
/// 键位核对（本轮实测）：本仓页级 `Alt` 键已占 **K（看套路卡）/ 数字 1–9
/// （页签直跳）**；`L` 空着（「练」的拼音首字母）⇒ 选 `Alt + L`。裸 `L` 是
/// 放映层课堂聚光灯（`presenter.dart` 自己的局部表），不受影响。
///
/// 让路闸（缺一道就会误触发）：
///  ① 非裸 `Alt + L` ⇒ 让路（裸 `L` / `Ctrl+L` / `Meta+L` 同按都不认领，
///     与同族宿主的修饰键口径一致）；
///  ② 本页不是当前路由（被 push 路由 / 对话框盖住）⇒ 让路；
///  ②b 壳内非激活页（IndexedStack 兄弟页）⇒ 让路——先于一切跳转判断，
///     keep-alive 多页宿主同时存活，非激活页 `return true` 会把事件从焦点链
///     抽走（与 `SaveMistakeKeyHost` 闸 ②b 同一条论证）；
///  ③ 焦点在 `EditableText` 里 ⇒ 让路——敲到一半的搜索词里按 L 是输入的一部分；
///  ④ 当前卡没有配套练习入口（[hasPracticeLink] 返回 false）⇒ 无声让路——
///     ⛔ 不许承诺一枚按不动的键：屏上提示与按钮与本闸共用同一个判据。
class CardPracticeKeyHost extends StatefulWidget {
  const CardPracticeKeyHost({
    super.key,
    required this.hasPracticeLink,
    required this.onOpen,
    required this.child,
  });

  /// 键位文案的唯一真相（速览表从这里取，⛔ 不许另写一份）。
  static const String keyLabel = 'Alt + L';
  static const String keyDescription =
      '去当前这张套路卡的练习入口（当前卡有「去练」按钮才应答；正在敲输入时不跳转）';

  /// 按下那一刻现取的判据：当前卡**屏上真有**那枚「去练」按钮 ⇔ 认领。
  /// ⛔ 必须是 ValueGetter：切章 / 翻卡不让本宿主 State rebuild，构造参数
  /// 会滞留旧卡（与 `CardLinkKeyHost.cardId` 同款论证）。
  final bool Function() hasPracticeLink;

  /// 与屏上那枚按钮 `onPressed` 用的**同一个** `_openLink`（⛔ 不重写第二份）。
  final VoidCallback onOpen;

  final Widget child;

  @override
  State<CardPracticeKeyHost> createState() => _CardPracticeKeyHostState();
}

class _CardPracticeKeyHostState extends State<CardPracticeKeyHost> {
  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_onKey);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKey);
    super.dispose();
  }

  bool get _editingText {
    final focus = FocusManager.instance.primaryFocus;
    final ctx = focus?.context;
    // 焦点挂在 EditableText 内部的 Focus widget 上，须祖先查找
    // （与同族宿主同款写法）。
    return ctx != null &&
        ctx.findAncestorWidgetOfExactType<EditableText>() != null;
  }

  /// `HardwareKeyboard.addHandler` 的签名是 `bool Function(KeyEvent)`
  /// ——false = 不认领，事件继续走既有通路。
  bool _onKey(KeyEvent event) {
    if (event is! KeyDownEvent) return false; // 长按连发（KeyRepeatEvent）让路
    if (event.logicalKey != LogicalKeyboardKey.keyL) return false; // 闸 ①：非本键
    if (!HardwareKeyboard.instance.isAltPressed) return false; // 裸 L 不认领
    if (HardwareKeyboard.instance.isControlPressed) return false; // Ctrl+L 不认领
    if (HardwareKeyboard.instance.isMetaPressed) return false; // Meta+L 不认领
    // 闸 ②：被别的路由盖住（对话框、push 出来的二级页）⇒ 让路。
    if (ModalRoute.of(context)?.isCurrent != true) return false;
    // 闸 ②b：壳内非激活页让路（论证见类注释）。
    if (!isPageKeyActive(context)) return false;
    if (_editingText) return false; // 闸 ③：敲到一半的搜索词里按 L 是输入
    // 闸 ④：当前卡没有练习入口 ⇒ 无声让路（与屏上提示/按钮同一个判据）。
    if (!widget.hasPracticeLink()) return false;
    widget.onOpen(); // 与屏上「去练」按钮完全同一条 _openLink
    ShortcutNudge.maybeNotify(context); // 首次成功触发给 ? 速览指引
    return true;
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// 搜索命中项：序号 + 卡名（+ 前导章标签 + 已背熟 ✓）。
/// v2.19.25：触控加高（课堂模式误触分析，老师 P2-6）。
/// v2.20.0：左侧纵向目录已收掉，本组件只剩「搜索命中列表」一个调用方
/// ⇒ 选中态随之删除（横条里的选中态由骨架的 pill 自己表达，不在这里重复）。
class _TocItem extends StatelessWidget {
  const _TocItem({
    super.key,
    required this.index,
    required this.card,
    required this.onTap,
    this.leading,
  });

  final int index;
  final BigQuestionCard card;
  final VoidCallback onTap;
  final Widget? leading;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onTap,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.border),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${index + 1}',
                    style: AppText.monoFigure.copyWith(fontSize: 14)),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        card.title,
                        style: AppText.label.copyWith(
                          color: AppColors.graphite,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (leading != null) ...[
                        const SizedBox(height: 2),
                        leading!,
                      ],
                    ],
                  ),
                ),
                // v2.19.25：已背熟 ✓（学生 P1-1）。
                ListenableBuilder(
                  listenable: BigQuestionCardsStore.mastered,
                  builder: (context, _) =>
                      BigQuestionCardsStore.isMastered(card.id)
                          ? Padding(
                              padding: const EdgeInsets.only(left: 4),
                              child: Icon(Icons.check_circle,
                                  size: 15, color: AppColors.teal),
                            )
                          : const SizedBox.shrink(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
