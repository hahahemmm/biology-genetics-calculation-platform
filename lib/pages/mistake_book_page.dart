// mistake_book_page.dart —— 错题本页（v2.12 Wave 2 / Worker B）
//
// 用户的「私人数据空间」—— 录入错题、AI 主动归类错因 / 提炼易错点 / 生成
// 总览、标记复习状态。本页**不**内置任何真题/题库内容（用户口述 2026-09-05
// 沉淀的设计原则）。
//
// UI 结构：
//   - 顶部 AppBar：标题 + 3 个按钮（添加 / AI 整理全部 / AI 总结）
//   - 列表：每条错题 = Card，含题目摘要 / 答案对照 / 错误类型 chip /
//           复习状态 chip / AI 整理结果 / AI 整理单条按钮 / 长按菜单（编辑 / 删除）
//   - 空状态：友好提示「点 + 添加你的第一条错题」
//
// AI 行为：
//   - 单条 AI 整理：调 `MistakeBookAi.analyzeSingle`，结果写入 aiSummary / aiPitfalls
//   - 批量 AI 整理：调 `analyzeAll`，遍历写入
//   - AI 总结：调 `buildOverview`，结果写入每条的 aiOverview + 顶部显示
//
// v2.12 Wave 3-B P1-3：
//   - initState 调 AppState.setPage('我的错题')，dispose 清，让 AI 助手
//     看到当前在错题本页（之前是 dashboard 模式，AI 拿不到错题本上下文）
//   - 删除操作加 Undo SnackBar（5 秒可撤销）——「点错了 / 一时冲动」场景
//     友好回退。撤销走 MistakeBook.add 直接重插（id 不重用，避免历史
//     引用错误）。
// v2.12.0+2 hotfix：
//   - 撤销 Undo 改用 add() 返回的 entry 拿新 id，删掉之前
//     firstWhere(5 字段全等) + orElse: entries.first 的 fragile 匹配。
//     旧写法依赖「_sortDesc 后 firstWhere 拿 0 位 = 刚 add 的」假设，
//     orElse 兜底会拿别的 entry 写 AI 结果（改字场景尤其踩坑）。
//     见 _handleDelete 内注释 + _persona_student_ux_report.md P0 #4。
//
// v2.12+ R1 P0 #3：产品宣传"AI 主动整理"——v2.12 之前是手动按按钮
// 触发（卡片底部"AI 整理"按钮 + AppBar"AI 整理全部"），本节改成
// "加错题后自动入队后台跑"：
//   - add 完调 MistakeBook.debugEnqueueAiOrganize 主动入队
//   - 500ms debounce 后台批量调 MistakeBookAi.analyzeSingle
//   - 5 秒后弹"AI 已自动归类错因 → [展开]" SnackBar
//   - 卡片底部"AI 整理中…"hint（结果到位后消失）
//
// v2.13+ R7-P2 P0：错题本新增「导出自练卷」（PopupMenu 第 3 项）——
// RedFox 真实用户洞察"错题如果不回到笔尖就只是看过"，周末打印/
// 抄写自测 = 错题本最高频闭环。零插件方案：UTF-8 纯文本 .md
// 导出到下载目录，题目区 stem + 留白「我的上次答案：______」（不
// 暴露 userAnswer，逼学生遮住答案页重写），卷尾答案/错因/考点/AI
// 提示。文件名 `自练卷_<yyyyMMdd_HHmm>.md`。

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb, visibleForTesting;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/big_question_cards.dart' show findCardIdForTopic;
import '../state/mono_variant.dart';
import 'big_question_cards_page.dart';
import 'curriculum_page.dart';
import '../services/mistake_book_crypto.dart';
import '../state/app_state.dart';
import '../state/mistake_book.dart';
import '../state/mistake_book_exporter_stub.dart'
    if (dart.library.html) '../state/mistake_book_exporter_web.dart' as webimpl;
import '../storage/platform_storage_io.dart'
    if (dart.library.html) '../storage/platform_storage_web.dart';
import '../theme.dart';
import '../ui/assistant_panel.dart';
import '../ui/ai_chat_controller.dart';
import '../ui/image_pick.dart';
import '../ui/json_pick.dart';
import '../ui/mistake_book_ai.dart';
import '../ui/module_fill.dart';
import '../ui/path_basename.dart';
import '../ui/share_file.dart';
import 'widgets/cause_radar.dart';

/// 错题本页面。
///
/// 顶导 / FAB 不显示（错题本是用户私人空间，不需要全局画布/AI 助手）。
/// 用 Navigator.push 从首页入口进入（不在主导航索引里，避免与 10 个
/// 主导航项抢位置）。
class MistakeBookPage extends StatefulWidget {
  const MistakeBookPage({super.key});

  /// 测试注入口：替换系统选图对话框（widget 测试不弹真实窗口、不碰文件
  /// 系统）。非 null 时表单的「拍照上传」走它而非 [pickImageFile]。
  @visibleForTesting
  static Future<PickedImage?> Function()? debugPicker;

  @override
  State<MistakeBookPage> createState() => _MistakeBookPageState();
}

class _MistakeBookPageState extends State<MistakeBookPage> {
  bool _aiBatchBusy = false;
  bool _aiOverviewBusy = false;

  /// v2.12+ R1 P0 #3：正在后台跑 AI 整理的 entry id 集合。
  /// 渲染时给对应 entry 加「AI 整理中…」hint（去 product 化，
  /// 不再让用户以为要点按钮才整理）。
  final Set<String> _aiOrganizingIds = <String>{};

  /// v2.12+ R1 P0 #3：弹"AI 已自动归类错因" SnackBar 用的 timer。
  ///
  /// v2.12+ R2 A2 P1-2：现在有两种 timer 共用本 map：
  ///   1. 5 秒首查 timer（add 后 5 秒检查一次）
  ///   2. 2 秒复查 timer（首查时 AI 还在跑 → AI 完成前每 2 秒复查一次，
  ///      上限 30 次 ≈ 60 秒）
  /// 在 dispose 时 cancel——否则 widget tester 报「pending timer」红。
  /// `Map<entryId, Timer>`：每条 entry 独立计时，删 entry 时也清掉对应 timer。
  final Map<String, Timer> _aiOrganizeSnackTimers = <String, Timer>{};

  // ─── v2.13 R3 P1-B4：搜索 / 筛选 / 排序状态（P1：100+ 条零入口） ───
  /// 搜索框 controller（AppBar bottom 搜索栏）。dispose 释放。
  final TextEditingController _searchController = TextEditingController();

  /// 当前搜索词（onChanged 实时更新，build 时给 query() 用）。
  String _searchQuery = '';

  /// v2.13 R5 P1A：搜索 200ms debounce。100+ 条错题每键 onChanged
  /// 即触发 `MistakeBook.instance.query` 全量扫（题/考点/错因/答案
  /// 四字段 .contains 串行）——快速连打会卡顿。
  /// 改为：onChanged 不直接 setState，只 cancel + 重启 timer；200ms
  /// 后用户停止敲键才落 setState 让 build 重算。dispose 时 cancel。
  Timer? _searchDebounce;

  /// 当前错因筛选；null = 全部。FilterChip 再点同类型 = 取消筛选。
  MistakeErrorType? _filterType;

  /// v2.13 R4 P1：仅看未复习（reviewedAt == null）筛选开关。FilterChip
  /// 点选 = 开，再点 = 关。与错因筛选可叠加（搜索词 ∩ 类型 ∩ 未复习）。
  bool _filterUnreviewed = false;

  /// v2.19.66：仅看本人（[MistakeEntry.sourceTag] 为空）筛选开关。合并进来
  /// 的同学题被筛掉，只留老师 / 本人自己的题。与其它筛选可叠加。
  bool _filterOwnOnly = false;

  /// 当前排序方式（默认最近添加 = 现有 createdAt 倒序）。
  MistakeSortMode _sortMode = MistakeSortMode.createdAt;
  // v2.13 学生走查：列表/按考点分组视图切换——考前「哪章错最多」
  // 一眼定位（subjectArea 已是结构化章节名）。
  bool _groupByKaodian = false;

  // ─── v2.13 R4-4：「查看归类」定位（Opt3B P1 假按钮修复） ───
  /// 每条 entry 一个 GlobalKey（ListView 卡片外层），
  /// `_revealAiResult` 用 Scrollable.ensureVisible 滚到该题。
  final Map<String, GlobalKey> _cardKeys = <String, GlobalKey>{};

  /// 「查看归类」后短暂高亮的 entry id（2 秒后自动清除）。
  String? _highlightEntryId;
  Timer? _highlightTimer;

  GlobalKey _keyFor(String id) => _cardKeys.putIfAbsent(id, () => GlobalKey());

  @override
  void initState() {
    super.initState();
    // 内存 / 磁盘加载（首次进入错题本时执行；后续幂等）。
    MistakeBook.instance.load().then((_) {
      if (mounted) setState(() {});
    });
    MistakeBook.instance.addListener(_onBookChanged);
    // v2.12 Wave 3-B P1-3：通知 AI 助手当前在错题本页。clear context
    // 让助手提示无算题上下文（错题本无计算结果，纯数据空间）。
    AppState.instance.setPage('我的错题');
  }

  @override
  void dispose() {
    MistakeBook.instance.removeListener(_onBookChanged);
    // v2.12 Wave 3-B P1-3：dispose 时恢复首页上下文（清空 = 助手看到
    // 的是 navigator pop 前的"当前页"，但 navigator.push 栈是同帧的，
    // home dashboard 不会主动重 set；这里用空 setPage('首页') 强制
    // 助手回到 home 视图，避免长时间残留"我的错题"标签）。
    AppState.instance.setPage('首页');
    // v2.12+ R1 P0 #3：cancel 所有 pending 的 5 秒 SnackBar timer。
    // 不 cancel 会让 widget tester 报「pending timer」红，且
    // 用户在 5 秒内退出页面后会再弹一次 SnackBar（mounted 检查能挡
    // 住回调，但 timer 本身留着是泄漏）。
    for (final t in _aiOrganizeSnackTimers.values) {
      t.cancel();
    }
    _aiOrganizeSnackTimers.clear();
    // v2.13 R3 P1-B4：释放搜索框 controller（不释放会在 widget tester
    // dispose 时报 leak 红）。
    _searchController.dispose();
    // v2.13 R5 P1A：cancel 搜索 debounce timer（同 highlightTimer 范式，
    // 防止 widget tester 报 pending timer 红）。
    _searchDebounce?.cancel();
    _searchDebounce = null;
    // v2.13 R4-4：释放「查看归类」高亮 timer（不 cancel 会 pending）。
    _highlightTimer?.cancel();
    _highlightTimer = null;
    super.dispose();
  }

  void _onBookChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final entries = MistakeBook.instance.entries;
    // v2.13 R3 P1-B4：100+ 条错题的「找得到」入口。真空书（0 条）不走
    // query（保持原「还没有错题」空态 + 不渲染搜索栏）。
    final visible = entries.isEmpty
        ? entries
        : MistakeBook.instance.query(
            search: _searchQuery,
            type: _filterType,
            sort: _sortMode,
            unreviewedOnly: _filterUnreviewed,
            ownOnly: _filterOwnOnly,
          );
    return Scaffold(
      appBar: AppBar(
        title: const Text('我的错题本'),
        // v2.13 R3 P1-B4：搜索框 + 排序下拉 + 错因筛选 chips（AppBar
        // bottom，始终可见不随列表滚动；真空书不显示）。
        bottom: entries.isEmpty
            ? null
            : PreferredSize(
                // v2.13 R4 P1：新增「仅看未复习」chip 后 chips 行可能在
                // 窄屏换行成 2 行 → 高度 100 会 overflow。放宽到 130。
                preferredSize: const Size.fromHeight(130),
                child: _buildFilterBar(),
              ),
        actions: [
          // v2.13+ 学生走查 P0：「更多」5 项菜单过载，导出自练卷沉底
          // 看不见——提为 AppBar 直达入口（打印图标，高频周未动作）。
          IconButton(
            tooltip: '导出自练卷（打印重做）',
            onPressed: _handleExportSelfPractice,
            icon: const Icon(Icons.print_outlined),
          ),
          IconButton(
            tooltip: 'AI 整理全部（对每条调 AI 归类错因）',
            onPressed: _aiBatchBusy ? null : _handleAiBatch,
            icon: const Icon(Icons.auto_awesome_outlined),
          ),
          IconButton(
            tooltip: 'AI 总结（基于所有错题生成总览）',
            onPressed: _aiOverviewBusy ? null : _handleAiOverview,
            icon: const Icon(Icons.summarize_outlined),
          ),
          IconButton(
            tooltip: '添加错题',
            onPressed: _handleAdd,
            icon: const Icon(Icons.add),
          ),
          // v2.12 R1 P0 #5+#6：PopupMenuButton 入口放 3 项（回收站 / 导出 / 导入）。
          // 单个 PopupMenu 收 3 项比 3 个 IconButton 省 80% 空间
          // （AppBar 在中等宽屏已接近 overflow 边界）。
          PopupMenuButton<_MistakeOverflowAction>(
            tooltip: '更多',
            onSelected: (a) {
              switch (a) {
                case _MistakeOverflowAction.trash:
                  _handleOpenTrash();
                case _MistakeOverflowAction.export:
                  _handleExport();
                case _MistakeOverflowAction.exportSelfPractice:
                  _handleExportSelfPractice();
                case _MistakeOverflowAction.importJson:
                  _handleImport();
                case _MistakeOverflowAction.classMergeImport:
                  _handleMergeImport();
                case _MistakeOverflowAction.exportEncrypted:
                  _handleExportEncrypted();
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(
                value: _MistakeOverflowAction.trash,
                child: ListTile(
                  leading: Icon(Icons.delete_outline),
                  title: Text('回收站'),
                ),
              ),
              // v2.13 R6-P1：导出/导入项加 subtitle 提示默认脱敏 / 未加密
              // 状态；R8-P1 新增「加密导出（推荐）」+ 加密导入自动嗅探
              // ——R6-P1 的「明文 + 默认脱敏」仍保留作为次选。
              PopupMenuItem(
                value: _MistakeOverflowAction.export,
                child: ListTile(
                  leading: Icon(Icons.file_download_outlined),
                  // v2.13+：标题点明「明文」——与「加密导出（推荐）」对照，
                  // 学生不再误以为两个导出等价（persona 走查 P1）。
                  title: Text('导出 JSON（明文）'),
                  subtitle: Text('默认脱敏（人名→某某，学号→×××）',
                      style: TextStyle(fontSize: 11)),
                ),
              ),
              // v2.13 R8-P1：新增「加密导出（推荐）」项——AES-256-GCM +
              // PBKDF2 100k 端到端加密 + 默认浅脱敏。落地后下载目录里
              // 拿到的是密文 envelope，无口令不可读。
              PopupMenuItem(
                value: _MistakeOverflowAction.exportEncrypted,
                child: ListTile(
                  leading: Icon(Icons.lock_outline),
                  title: Text('加密导出（推荐）'),
                  subtitle: Text('AES-256-GCM 端到端加密 + PBKDF2 100k',
                      style: TextStyle(fontSize: 11)),
                ),
              ),
              PopupMenuItem(
                value: _MistakeOverflowAction.importJson,
                child: ListTile(
                  leading: Icon(Icons.file_upload_outlined),
                  title: Text('导入 JSON'),
                  // v2.19.66：与「合并同学错题包」在**文案上**明确区分——
                  // 这一项是备份恢复（覆盖）路径，别和合并混。
                  subtitle: Text('恢复备份（覆盖）·明文/加密自动识别',
                      style: TextStyle(fontSize: 11)),
                ),
              ),
              // v2.19.66：班级错题「合并导入」入口——与上面的「恢复备份
              // （覆盖）」并列。按 题干+答案 去重后**只追加**，每条打「来自
              // 同学」来源标，本人 / 老师自己的题一条都不动。
              PopupMenuItem(
                value: _MistakeOverflowAction.classMergeImport,
                child: ListTile(
                  leading: Icon(Icons.group_add_outlined),
                  title: Text('合并同学错题包'),
                  subtitle: Text('只追加不覆盖·重复题自动跳过',
                      style: TextStyle(fontSize: 11)),
                ),
              ),
              // v2.13+ R7-P2 P0：自练卷导出（RedFox 真实用户洞察「错题
              // 如果不回到笔尖就只是看过」）。零插件纯文本 .md，题目区
              // 留白（不暴露 userAnswer）逼学生重写，卷尾给正确答案+错因+
              // 考点+AI 提示——周末打印/抄写自测闭环。
              PopupMenuItem(
                value: _MistakeOverflowAction.exportSelfPractice,
                child: ListTile(
                  leading: Icon(Icons.assignment_outlined),
                  title: Text('导出自练卷'),
                  subtitle: Text('周末打印/抄写——题目留白重做 + 卷尾答案错因',
                      style: TextStyle(fontSize: 11)),
                ),
              ),
            ],
          ),
        ],
      ),
      body: SafeArea(
        // v2.13+：今日待复习横幅（零插件间隔复习的提醒入口）+
        // 原内容。横幅只在有到期错题时出现。
        child: Column(
          children: [
            if (entries.isNotEmpty &&
                MistakeBook.instance.dueEntries().isNotEmpty)
              _buildDueBanner(MistakeBook.instance.dueEntries().length),
            // v2.19.61：错因分布雷达卡（列表顶部、待复习横幅下方）。
            // ⛔ 空错题本（entries 为空）一个像素都不渲染。卡高必须紧凑——
            // 列表可视区被它压掉一截，卡越高，列表里能被「看见」的题越少。
            if (entries.isNotEmpty) _buildCauseRadarCard(entries),
            Expanded(
              child: _aiBatchBusy || _aiOverviewBusy
                  ? _BusyOverlay()
                  : entries.isEmpty
                      ? _EmptyState()
                      : visible.isEmpty
                          // v2.13 R3 P1-B4：搜索/筛选后无结果 → 空结果态 +
                          // [清除筛选] 一键恢复（真空书走 _EmptyState，不混淆）。
                          ? _NoResultState(onClear: _clearFilters)
                          : _groupByKaodian
                              ? _buildGrouped(visible)
                              : ListView.builder(
                                  padding: const EdgeInsets.fromLTRB(
                                      16, 12, 16, 24),
                                  itemCount: visible.length,
                                  itemBuilder: (_, i) =>
                                      _cardFor(visible[i]),
                                ),
            ),
          ],
        ),
      ),
    );
  }

  /// 今日待复习横幅：到期数量 + [开始复习]（进入遮罩自测会话）。
  Widget _buildDueBanner(int n) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 10, 16, 0),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.tealWash,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.teal.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          Icon(Icons.event_repeat_outlined, size: 18, color: AppColors.teal),
          const SizedBox(width: 8),
          Expanded(
            child: Text('今日待复习 $n 道（遮住答案自测，防遗忘曲线）',
                style: AppText.caption.copyWith(color: AppColors.teal)),
          ),
          FilledButton.tonal(
            onPressed: () => _startReviewSession(),
            style: FilledButton.styleFrom(
              minimumSize: const Size(0, 32),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: const Text('开始复习'),
          ),
        ],
      ),
    );
  }

  /// v2.19.61：错因分布卡——列表顶部可折叠小卡（默认展开）。
  ///
  /// 数据 = 只聚合**已有**的 errorType 字段（不接 AI）：聚合口径见
  /// [mistakeCauseCounts]（lib/state/mistake_book.dart）。数据源是页面
  /// build 传入的 `MistakeBook.instance.entries`（**不含回收站**）；页面
  /// 已订阅 MistakeBook（[_onBookChanged] → setState）⇒ 列表 rebuild 时
  /// 本卡随之刷新。
  ///
  /// ⛔ 高度是硬约束：本卡占列表可视区一截，卡越高，列表里能「看见」的
  /// 题越少（ListView 懒构建 + 只有落在绘制区内的题才可被检索）。故版面
  /// 一律紧凑，图体也只给 [kCauseRadarCardChartSize] 而非组件默认的 220。
  ///
  /// ⛔ 空错题本不调用本方法（调用点在 build 里 `entries.isNotEmpty` 之后）。
  Widget _buildCauseRadarCard(List<MistakeEntry> entries) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
      child: Card(
        // 外边距由上面的 Padding 统一给（Card 默认 4px margin 会白占高度，
        // 本卡的高度预算以像素计）。
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        child: _CauseRadarCard(
          // 自评视图数据（errorType 五轴）。
          counts: mistakeCauseCounts(entries),
          // AI 判视图数据（causeKey 六轴，null → unclassified 桶）。
          causeKeyCounts: mistakeCauseKeyCounts(entries),
          // 全库是否至少有一条被 AI 判过——决定 AI 视图画图还是诚实空态。
          hasAiCauseKey: hasAnyAiCauseKey(entries),
        ),
      ),
    );
  }

  /// 打开自测会话（全屏对话框，逐题遮罩自测）。
  Future<void> _startReviewSession() async {
    final due = MistakeBook.instance.dueEntries();
    if (due.isEmpty) return;
    // v2.19.13（学生找茬 🟡7）：非自然完成的退出（Esc/退出按钮）
    // 返回当前题号，对话框关闭后 toast 告知进度已保存 + 从哪继续——
    // 原行为无任何反馈，用户不知道进度丢没丢。
    final exitedAt = await showDialog<int>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _ReviewSession(entries: due),
    );
    // 会话结束后状态已变（reviewedAt 刷新）→ 横幅数量/列表徽标重建。
    if (!mounted) return;
    setState(() {});
    if (exitedAt != null && exitedAt < due.length) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content:
            Text('已退出复习：进度已保存，下次从第 ${exitedAt + 1} 道继续'),
        duration: const Duration(seconds: 3),
      ));
    }
  }

  // ─── v2.13 R3 P1-B4：搜索 / 筛选 / 排序 UI ──────────────────────

  /// 单个错题卡（列表与分组视图共用）。
  Widget _cardFor(MistakeEntry e) {
    return _MistakeCard(
      // v2.13 R4-4：「查看归类」定位用 GlobalKey。
      key: _keyFor(e.id),
      entry: e,
      highlight: _highlightEntryId == e.id,
      onTap: () => _handleEdit(e),
      onAiTap: _aiBatchBusy ? null : () => _handleAiSingle(e),
      // v2.12+ R1 P0 #3：后台 AI 整理中标记。
      aiOrganizing: _aiOrganizingIds.contains(e.id),
      // v2.13 R3 P1-B4：错误类型 chip 可点筛选。
      errorTypeFilter: _filterType,
      onErrorTypeTap: () => setState(() {
        _filterType = _filterType == e.errorType ? null : e.errorType;
      }),
    );
  }

  /// v2.13 学生走查：按考点分组视图——组 = subjectArea（空归「未标注
  /// 考点」），组内沿用当前排序；组间按题数倒序（错最多的章节在前）。
  /// R5 学生走查：组头补「待复习 N」小标——考前能看出哪章错最多，
  /// 也能看出哪章还有题没复习完。
  Widget _buildGrouped(List<MistakeEntry> visible) {
    final groups = <String, List<MistakeEntry>>{};
    for (final e in visible) {
      final k = e.subjectArea.isEmpty ? '未标注考点' : e.subjectArea;
      groups.putIfAbsent(k, () => []).add(e);
    }
    final keys = groups.keys.toList()
      ..sort((a, b) => groups[b]!.length - groups[a]!.length);
    final dueIds = MistakeBook.instance.dueEntries().map((e) => e.id).toSet();
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      itemCount: keys.length,
      itemBuilder: (_, gi) {
        final k = keys[gi];
        final list = groups[k]!;
        final dueCount = list.where((e) => dueIds.contains(e.id)).length;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(2, 10, 2, 6),
              child: Row(
                children: [
                  Icon(Icons.bookmark_outline,
                      size: 14, color: AppColors.teal),
                  const SizedBox(width: 6),
                  Text(k, style: AppText.label),
                  const SizedBox(width: 8),
                  Text('${list.length} 道',
                      style: AppText.caption
                          .copyWith(color: AppColors.steel)),
                  if (dueCount > 0) ...[
                    const SizedBox(width: 6),
                    Text('· 待复习 $dueCount',
                        style: AppText.caption
                            .copyWith(color: AppColors.teal)),
                  ],
                ],
              ),
            ),
            for (final e in list) _cardFor(e),
          ],
        );
      },
    );
  }

  /// AppBar bottom 过滤栏：搜索框 + 排序下拉（第一行），
  /// 错因类型 FilterChip 行（第二行，单选可取消）。
  ///
  /// 布局：搜索框占满剩余宽度；排序用 PopupMenuButton（同文件
  /// _ReviewStatusChip 同款模式），当前排序方式显示在按钮上；
  /// chips 行 Align 到左，窄屏自动 Wrap 换行。
  Widget _buildFilterBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 10),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  key: const Key('mistake_search_field'),
                  controller: _searchController,
                  onChanged: (v) {
                    // v2.13 R5 P1A：200ms debounce，避免连打键盘
                    // 每键全量 MistakeBook.query 卡顿。取消上一个
                    // timer + 重启新 timer；只有用户停手 200ms 才
                    // 落 setState。
                    _searchDebounce?.cancel();
                    _searchDebounce = Timer(
                        const Duration(milliseconds: 200), () {
                      if (mounted) setState(() => _searchQuery = v);
                    });
                  },
                  decoration: InputDecoration(
                    // v2.13 R4 P1：搜索覆盖题目/考点/错因/答案（多字段），
                    // placeholder 文案同步改，避免用户以为只能搜题目摘要。
                    hintText: '搜索题目/考点/错因',
                    prefixIcon: const Icon(Icons.search, size: 20),
                    suffixIcon: _searchQuery.isEmpty
                        ? null
                        : IconButton(
                            tooltip: '清除搜索',
                            icon: const Icon(Icons.clear, size: 18),
                            onPressed: () {
                              _searchController.clear();
                              setState(() => _searchQuery = '');
                            },
                          ),
                    isDense: true,
                    filled: true,
                    fillColor: AppColors.surface,
                    contentPadding:
                        const EdgeInsets.symmetric(vertical: 8),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              PopupMenuButton<MistakeSortMode>(
                key: const Key('mistake_sort_menu'),
                tooltip: '排序方式',
                initialValue: _sortMode,
                onSelected: (m) => setState(() => _sortMode = m),
                itemBuilder: (_) => [
                  for (final m in MistakeSortMode.values)
                    PopupMenuItem(
                      value: m,
                      child: Row(
                        children: [
                          if (m == _sortMode)
                            Icon(Icons.check, size: 16,
                                color: AppColors.teal)
                          else
                            const SizedBox(width: 16),
                          const SizedBox(width: 8),
                          Text(m.displayName),
                        ],
                      ),
                    ),
                ],
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.sort, size: 18, color: AppColors.teal),
                      const SizedBox(width: 6),
                      Text(_sortMode.displayName, style: AppText.label),
                    ],
                  ),
                ),
              ),
              // v2.13 学生走查：列表 / 按考点分组视图切换。
              IconButton(
                tooltip: _groupByKaodian ? '切回列表视图' : '按考点分组查看',
                onPressed: () =>
                    setState(() => _groupByKaodian = !_groupByKaodian),
                icon: Icon(
                  _groupByKaodian
                      ? Icons.category
                      : Icons.category_outlined,
                  size: 20,
                ),
                color: _groupByKaodian ? AppColors.teal : null,
              ),
            ],
          ),
          const SizedBox(height: 6),
          Align(
            alignment: Alignment.centerLeft,
            child: Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                // v2.13 R4 P1：仅看未复习筛选（reviewedAt == null）。
                FilterChip(
                  key: const Key('mistake_unreviewed_filter'),
                  label: Text('仅看未复习', style: AppText.caption),
                  selected: _filterUnreviewed,
                  showCheckmark: false,
                  onSelected: (_) => setState(() {
                    _filterUnreviewed = !_filterUnreviewed;
                  }),
                ),
                const SizedBox(width: 4),
                // v2.19.66：仅看本人——筛掉合并进来的同学题，只留 sourceTag
                // 为空（本人 / 老师自己）的条目。
                FilterChip(
                  key: const Key('mistake_own_only_filter'),
                  label: Text('仅看本人', style: AppText.caption),
                  selected: _filterOwnOnly,
                  showCheckmark: false,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  onSelected: (_) => setState(() {
                    _filterOwnOnly = !_filterOwnOnly;
                  }),
                ),
                const SizedBox(width: 4),
                for (final t in MistakeErrorType.values)
                  FilterChip(
                    key: Key('mistake_type_filter_${t.name}'),
                    label: Text(t.displayName, style: AppText.caption),
                    selected: _filterType == t,
                    showCheckmark: false,
                    materialTapTargetSize:
                        MaterialTapTargetSize.shrinkWrap,
                    onSelected: (_) => setState(() {
                      _filterType = _filterType == t ? null : t;
                    }),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// v2.13 R3 P1-B4 + R4 P1：清空搜索词 + 错因筛选 + 「仅看未复习」
  /// （空结果态 [清除筛选] 按钮触发）。排序方式保留用户选择。
  void _clearFilters() {
    _searchController.clear();
    setState(() {
      _searchQuery = '';
      _filterType = null;
      _filterUnreviewed = false;
      _filterOwnOnly = false;
    });
  }

  // ---- 用户操作 ----

  Future<void> _handleAdd() async {
    final result = await showDialog<_MistakeFormResult>(
      context: context,
      builder: (_) => _MistakeFormDialog(),
    );
    if (result == null) return;
    final added = MistakeBook.instance.add(
      stem: result.stem,
      userAnswer: result.userAnswer,
      correctAnswer: result.correctAnswer,
      errorType: result.errorType,
      subjectArea: result.subjectArea,
    );
    if (!mounted) return;
    // v2.12+ R1 P0 #3：产品宣传"AI 主动整理"——v2.12 之前是手动按
    // 按钮触发，add 后**自动入队**后台跑。500ms debounce 后调
    // MistakeBookAi.analyzeSingle，结果写回 aiSummary + aiPitfalls。
    _aiOrganizingIds.add(added.id);
    MistakeBook.instance.debugEnqueueAiOrganize(added.id);
    // 5 秒后弹"AI 已自动归类错因 → [展开]" SnackBar（和"已添加错题"
    // SnackBar 错开，避免视觉冲突）。[展开] action 跳到错题本列表
    // 对应 entry（已经是首屏，无需 push）。
    //
    // 用 Timer（非 Future.delayed）存到 state：在 dispose 时 cancel，
    // 否则 widget tester 报「pending timer」红 + 用户退出页面后 timer
    // 仍会触发回调（mounted 检查能挡 callback，但 timer 本身留着是泄漏）。
    _aiOrganizeSnackTimers[added.id] = Timer(const Duration(seconds: 5), () {
      _aiOrganizeSnackTimers.remove(added.id);
      if (!mounted) return;
      // v2.12+ R2 A2 P1-2：只有 AI 实际跑完（aiSummary 已写入）才显示；
      // AI 还在跑（aiSummary 仍空）时不弹，改为每 2 秒复查一次（上限
      // 30 次 ≈ 60 秒），AI 完成后再弹。如果用户在 5 秒内退出了页面
      // 就跳过（mounted 检查 + dispose 已 cancel timer）。
      final entry = MistakeBook.instance.findById(added.id);
      if (entry == null) return;
      if (entry.aiSummary == null || entry.aiSummary!.isEmpty) {
        _scheduleAiOrganizedSnackRecheck(added.id);
        return;
      }
      _aiOrganizingIds.remove(added.id);
      _showAiOrganizedSnack(added.id);
    });
    _showSnack('已添加错题');
  }

  /// v2.12+ R2 A2 P1-2：AI 完成前的 SnackBar 条件复查。
  ///
  /// 5 秒首查时 AI 可能还在跑（aiSummary 未写入）——此时**不弹**，
  /// 每 2 秒复查一次直到 aiSummary 写入或达到上限（30 次 ≈ 60 秒），
  /// 避免"AI 没跑完也弹"的名实不符（R1 残留 bug）。
  ///
  /// v2.13 R3 P1-B2：复查链到顶（约 60 秒）aiSummary 仍空 = 后台 AI
  /// 整理失败/超时。之前只悄悄终止链，`_aiOrganizingIds` 里的 id 不会
  /// remove → 卡片「AI 整理中…」hint 永久残留。现在到顶时 remove id
  /// + 弹「AI 整理失败，可手动重试」。注意失败路径必须包 setState：
  /// 它没有 applyAiAnalysis 的 notifyListeners 触发 rebuild，只 remove
  /// id 画面不会刷新。
  ///
  /// 复用 `_aiOrganizeSnackTimers` 存放：dispose / 删 entry 时统一
  /// cancel，不会留下孤儿 timer。
  void _scheduleAiOrganizedSnackRecheck(String entryId, {int attempt = 0}) {
    if (!mounted) return;
    _aiOrganizeSnackTimers[entryId] = Timer(const Duration(seconds: 2), () {
      _aiOrganizeSnackTimers.remove(entryId);
      if (!mounted) return;
      final entry = MistakeBook.instance.findById(entryId);
      if (entry == null) return;
      if (entry.aiSummary == null || entry.aiSummary!.isEmpty) {
        if (attempt < 29) {
          _scheduleAiOrganizedSnackRecheck(entryId, attempt: attempt + 1);
          return;
        }
        // v2.13 R3 P1-B2：60 秒复查链终止 = 失败/超时 → 清理 spinner +
        // 弹失败提示（用户可手动点卡片 AI 整理按钮重试）。
        setState(() => _aiOrganizingIds.remove(entryId));
        // v2.13 R4-4：AI 失败提示 2s → 5s。
        _showSnack('AI 整理失败，可手动重试',
            duration: const Duration(seconds: 5));
        return;
      }
      _aiOrganizingIds.remove(entryId);
      _showAiOrganizedSnack(entryId);
    });
  }

  /// v2.12+ R1 P0 #3：「AI 已自动归类错因 → [查看归类]」SnackBar。
  ///
  /// v2.13 R4-4（Opt3B P1）：旧 [展开] action 只调 `setState(() {})`
  /// 刷帧 = no-op 假按钮。卡片 AI 结果块无独立展开 UI（结果恒定渲染在
  /// 卡片底部），因此 action 改为「[查看归类]」→ 定位到该题卡片并短暂
  /// 高亮 AI 结果块——用户点下去真的"看到归类结果"。
  void _showAiOrganizedSnack(String entryId) {
    final messenger = ScaffoldMessenger.of(context);
    messenger.clearSnackBars();
    messenger.showSnackBar(
      SnackBar(
        content: const Text('AI 已自动归类错因'),
        duration: const Duration(seconds: 4),
        persist: false,
        action: SnackBarAction(
          label: '查看归类',
          onPressed: () => _revealAiResult(entryId),
        ),
      ),
    );
  }

  /// v2.13 R4-4：「查看归类」= 滚动列表定位到该 entry 卡片 + 2 秒高亮。
  ///
  /// 若当前搜索 / 错因筛选 / 「仅看未复习」把该题过滤掉了，先清筛选
  /// 恢复全量再定位（保证"看得到"）。排序方式保留用户选择。
  void _revealAiResult(String entryId) {
    // 与 build 的可见集合完全一致（含 R4 P1 的「仅看未复习」开关）——
    // 只有 build 认为不可见时才值得清筛选恢复全量。
    final visible = MistakeBook.instance.query(
      search: _searchQuery,
      type: _filterType,
      sort: _sortMode,
      unreviewedOnly: _filterUnreviewed,
      ownOnly: _filterOwnOnly,
    );
    if (!visible.any((e) => e.id == entryId)) {
      _clearFilters();
    }
    final ctx = _cardKeys[entryId]?.currentContext;
    if (ctx != null) {
      Scrollable.ensureVisible(
        ctx,
        duration: const Duration(milliseconds: 300),
        alignment: 0.1,
      );
    }
    setState(() => _highlightEntryId = entryId);
    _highlightTimer?.cancel();
    _highlightTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _highlightEntryId = null);
    });
  }

  Future<void> _handleEdit(MistakeEntry entry) async {
    final result = await showDialog<_MistakeFormResult>(
      context: context,
      builder: (_) => _MistakeFormDialog(initial: entry),
    );
    if (result == null) return;
    MistakeBook.instance.update(entry.id, (e) => e.copyWith(
          stem: result.stem,
          userAnswer: result.userAnswer,
          correctAnswer: result.correctAnswer,
          errorType: result.errorType,
          subjectArea: result.subjectArea,
        ));
    if (!mounted) return;
    _showSnack('已更新');
  }

  Future<void> _handleDelete(MistakeEntry entry) async {
    // v2.12 Round 1 P0 #5：删除 = 软删除 = 移入回收站。
    //
    // 5 秒 Undo SnackBar 行为保留——点 Undo 调 restoreFromTrash，
    // entry 从 _trash 回到 _entries（新 id + 完整字段恢复）。
    //
    // SnackBar 文案从「已删除」改为「已移入回收站」——明确告知
    // 用户「删除」≠「彻底消失」，可以打开回收站找回。
    //
    // 5 秒 Undo 过期后仍可恢复：从 AppBar 右上角 PopupMenu → 回收站
    // 进入 _MistakeTrashDialog，可看 7 天内删除的条目，
    // 「恢复」调 restoreFromTrash，「永久删除」调 permanentlyDelete。
    final id = entry.id;
    MistakeBook.instance.delete(id);
    // v2.12+ R1 P0 #3：删 entry 时清掉对应后台 AI 整理 timer
    // （5 秒 SnackBar timer + organizing 集合），避免对已删 entry
    // 继续弹 SnackBar / 显示 hint。
    _aiOrganizingIds.remove(id);
    _aiOrganizeSnackTimers.remove(id)?.cancel();
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger.clearSnackBars();
    messenger.showSnackBar(
      SnackBar(
        content: const Text('已移入回收站'),
        duration: const Duration(seconds: 5),
        // v2.12 Wave 3-B P1 修复：SnackBar 配 action 时默认 persist=true
        // → 永远不会自动 dismiss，5 秒 Undo 窗口失效。
        // v2.12 R1 P0 #5：现在 entry 在 _trash 不是真删，Undo
        // 仍能恢复；persist:false 让 SnackBar 5 秒后自动 dismiss。
        persist: false,
        action: SnackBarAction(
          label: '撤销',
          onPressed: () {
            // v2.12 R1 P0 #5：直接调 restoreFromTrash——一行搞定，
            // 替代 v2.12.0+2 hotfix 的"手动 add + applyAiAnalysis +
            // applyAiOverview + markStatus"链路。后者要重写 4 个
            // API 重建 entry 字段；前者是 MistakeBook 内部已封装好
            // 的"恢复"原语（新 id + 保留 AI 字段 + 复习状态），
            // 一处真相源。
            //
            // 注：5 秒 Undo 过期后这条 id 仍在 _trash 里（直到 7 天后
            // 被 purgeExpiredTrash 清理），用户仍可从 AppBar 回收站
            // 入口找回——这就是 P0 #5 的核心改进。
            MistakeBook.instance.restoreFromTrash(id);
          },
        ),
      ),
    );
  }

  Future<void> _handleAiSingle(MistakeEntry entry) async {
    _showSnack('AI 整理中…');
    final result = await MistakeBookAi.analyzeSingle(entry);
    if (!mounted) return;
    if (result == null) {
      // v2.13 R4-4：AI 失败提示 2s → 5s（读得完失败原因再消失）。
      _showSnack('AI 整理失败（未配置 AI / 网络错误 / 解析失败）',
          duration: const Duration(seconds: 5));
      return;
    }
    MistakeBook.instance.applyAiAnalysis(
      entry.id,
      summary: result.summary,
      pitfalls: result.pitfalls,
    );
    _showSnack('已写入 AI 整理结果');
  }

  Future<void> _handleAiBatch() async {
    final entries = MistakeBook.instance.entries
        .where((e) => e.aiSummary == null || e.aiSummary!.isEmpty)
        .toList();
    if (entries.isEmpty) {
      _showSnack('所有错题已整理过，无需重复');
      return;
    }
    setState(() => _aiBatchBusy = true);
    // v2.13 R3 P1-B3：organizeBatch 返回带失败原因的结果，按成功数
    // 分支显示——全失败不再弹「批量整理完成：0 / N」假成功
    // （未配置 AI / 网络失败时旧代码 100% 触发）。
    //
    // v2.13 R4-4：try/finally 保险——MistakeBookAi 内部全 catch 了
    // 异常，但防御性保证任何意外抛错时 _aiBatchBusy 都能复位，
    // 不会让「AI 整理全部」按钮永久灰死。
    try {
      final outcome = await MistakeBook.instance.organizeBatch(entries);
      if (!mounted) return;
      final success = outcome.successCount;
      if (outcome.allFailed) {
        final reason = outcome.failureReason;
        _showSnack(
          reason == null || reason.isEmpty
              ? '批量整理失败（0/${outcome.total}），请稍后重试'
              : '批量整理失败（0/${outcome.total}），请稍后重试\n失败原因：$reason',
          duration: const Duration(seconds: 5),
        );
      } else if (outcome.partialSuccess) {
        _showSnack(
            '部分成功（$success/${outcome.total}），失败 ${outcome.total - success} 条可重试');
      } else {
        _showSnack('批量整理完成：$success / ${outcome.total}');
      }
    } finally {
      if (mounted) setState(() => _aiBatchBusy = false);
    }
  }

  Future<void> _handleAiOverview() async {
    final entries = MistakeBook.instance.entries;
    if (entries.isEmpty) {
      _showSnack('还没有错题，无法总结');
      return;
    }
    setState(() => _aiOverviewBusy = true);
    final result = await MistakeBookAi.buildOverview(entries);
    if (!mounted) return;
    if (result == null) {
      setState(() => _aiOverviewBusy = false);
      // v2.13 R4-4：AI 失败提示 2s → 5s。
      _showSnack('AI 总结失败', duration: const Duration(seconds: 5));
      return;
    }
    // 写回每条的 aiOverview
    for (final e in entries) {
      MistakeBook.instance.applyAiOverview(e.id, result.text);
    }
    setState(() => _aiOverviewBusy = false);
    if (!mounted) return;
    // 弹出总览卡
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('AI 总览'),
        content: SingleChildScrollView(
          child: Text(result.text, style: AppText.body),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  /// 普通提示 SnackBar，默认 2s。
  /// v2.13 R4-4：AI 整理失败等含失败原因的提示传 5s——2s 太短，
  /// 用户读不完「失败原因」就消失了。
  void _showSnack(String msg, {Duration? duration}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        duration: duration ?? const Duration(seconds: 2),
      ),
    );
  }

  /// v2.12 R1 P0 #5：打开回收站对话框。
  Future<void> _handleOpenTrash() async {
    // 进入时清理一次 7 天前的过期条目（load() 不清是为了不阻塞启动）。
    MistakeBook.instance.purgeExpiredTrash();
    await showDialog<void>(
      context: context,
      builder: (_) => _MistakeTrashDialog(),
    );
  }

  /// v2.12 R1 P0 #6：导出 JSON。
  ///
  /// v2.12+ R2 P1：导出成功 SnackBar 加 [打开下载目录] action，直接
  /// 定位到刚生成的 .json 文件（复用 R1 final-D P0 #3 的
  /// `_showBoardInExplorer` 同款 Process.start explorer.exe /select 模式，
  /// 抽到 MistakeBookExporter.openInExplorer 公开静态方法供本页和
  /// dashboard 共用）。
  ///
  /// v2.13 R4-2（P1-2 EACCES 修复）：Android 导出文件只落应用专属目录
  /// （getFilesDir），用户看不到公共 Downloads → SnackBar 文案诚实告知
  /// 「已保存到应用目录」+ [分享] action（走 biology/share_file channel
  /// 拉起系统分享面板，学生 → 微信/QQ）。
  ///
  /// 行为：
  ///   - 桌面 / macOS / Linux：SnackBar [打开下载目录] → explorer.exe
  ///     /select 高亮该 .json 文件（同板书历史）
  ///   - Android（v2.13 R4-2）：SnackBar [分享] → 系统分享面板
  ///     （分享目标可读 content:// URI，经 FileProvider 授权）
  ///   - Web：_saveWeb 已触发浏览器下载，无文件管理器概念，action 隐藏
  ///   - 错误：SnackBar 提示错误路径（不静默吞错）
  Future<void> _handleExport() async {
    // v2.13 R4-4：导出前弹确认 dialog，提供「脱敏导出」选项（浅脱敏：
    // 人名→某某、学号→×××）。导出 JSON 是明文包，落到下载/公共目录
    // 后其他 app 可读——勾选脱敏可显著降低隐私暴露面。
    final desensitize = await showDialog<bool>(
      context: context,
      builder: (_) => _ExportDialog(),
    );
    if (!mounted || desensitize == null) return;
    final json = MistakeBook.instance.exportJson(desensitize: desensitize);
    final saved = await MistakeBookExporter.saveToDownloads(
      json,
      'biology_mistake_${DateTime.now().millisecondsSinceEpoch}',
    );
    if (!mounted) return;
    if (saved == null) {
      _showSnack('导出失败');
      return;
    }
    // 错误路径：写盘失败 / 未找到目录
    if (saved.startsWith('导出失败') || saved == '未找到可写目录') {
      _showSnack(saved);
      return;
    }
    // 成功路径：
    //   - 桌面 / macOS / Linux：saved 是文件路径 → [打开下载目录] action
    //   - Android（v2.13 R4-2）：saved 是应用专属目录里的文件路径 →
    //     [分享] action（见方法 doc）
    //   - Web：saved 是「已触发浏览器下载」 → action 隐藏
    final isFilePath = !saved.startsWith('已触发');
    final isAndroid = MistakeBookExporter.isAndroidExport;
    // v2.13 R7-P1 闭环 R6-2nd MINOR：导出成功 SnackBar 文字根据 desensitize
    // 补明确标注，避免用户选过 dialog 后忘记当时选了什么。
    //   desensitize=true  → 末尾加"（已脱敏）"
    //   desensitize=false → amber 背景 + 末尾加"（明文未脱敏，请确认分享对象可信）"
    final baseText = isFilePath
        ? (isAndroid
            ? '已保存到应用目录（可导出/分享）'
            : '错题本已导出：${pathBasename(saved)}')
        : saved;
    final suffix = desensitize
        ? '（已脱敏）'
        : '（明文未脱敏，请确认分享对象可信）';
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(
      SnackBar(
        backgroundColor: desensitize ? null : Colors.amber.shade100,
        content: Text('$baseText$suffix'),
        duration: const Duration(seconds: 4),
        action: isFilePath
            ? SnackBarAction(
                label: isAndroid ? '分享' : '打开下载目录',
                onPressed: isAndroid
                    ? () => _shareExportedFile(saved)
                    : () async {
                        // v2.13 R4 P1：消费 openInExplorer 返回值，失败弹
                        // SnackBar（此前忽略返回值 = 死 action，失败静默）。
                        final err =
                            await MistakeBookExporter.openInExplorer(saved);
                        if (err != null && mounted) _showSnack(err);
                      },
              )
            : null,
      ),
    );
  }

  /// v2.13 R4-2：Android 分享已导出的错题 JSON（学生 → 微信/QQ）。
  /// 走 biology/share_file channel（MainActivity Intent.ACTION_SEND +
  /// FileProvider content:// URI）。失败 SnackBar 透出错误原因。
  Future<void> _shareExportedFile(String path) async {
    final err = await shareFile(path, mimeType: 'application/json');
    if (!mounted) return;
    if (err != null) _showSnack(err);
  }

  /// v2.12 R1 P0 #6：导入 JSON（弹 dialog 让用户粘贴内容）。
  ///
  /// v2.12+ R1 final-B P0 #4：`MistakeBook.importJson` 会对坏 JSON /
  /// schemaVersion 不匹配 / entries 不是 array 抛 `FormatException`，
  /// 之前没 try/catch → 错误冒泡到 Flutter 框架让整个 app 闪退。
  /// 现在加 try/catch（FormatException + 兜底 Exception），失败弹
  /// SnackBar 提示 + 详细错误，不让 app crash。
  ///
  /// v2.13 R6-P1：导入成功弹「明文导入 + 请确认来源可信」引导 SnackBar
  /// ——这是 P1 隐私根因中「照片/截图/板书 SVG 不脱敏」一项在 import
  /// 链路的最小缓解。
  ///
  /// v2.13 R8-P1：自动嗅探加密 envelope——用户粘 / 选的是加密包
  /// （`MistakeBookCrypto.isEncryptedEnvelope`）→ 弹 `_DecryptImportDialog`
  /// 让用户输口令，调 `importJson(json, passphrase: pwd)` 走解密路径；
  /// 失败弹 SnackBar 透出 FormatException 原因（错口令 / 文件损坏）。
  /// 明文路径保留 R6-P1 「明文 / 来源可信」引导。
  Future<void> _handleImport() async {
    final json = await showDialog<String>(
      context: context,
      builder: (_) => MistakeImportDialog(),
    );
    if (json == null || json.isEmpty || !mounted) return;

    // v2.13 R8-P1：先嗅探 envelope。加密包必须输口令才能 import。
    final isEncrypted = MistakeBookCrypto.isEncryptedEnvelope(json);
    String? passphrase;
    if (isEncrypted) {
      passphrase = await showDialog<String>(
        context: context,
        builder: (_) => _DecryptImportDialog(),
      );
      if (passphrase == null) {
        // 用户取消口令 dialog
        if (!mounted) return;
        _showSnack('已取消');
        return;
      }
    }

    final int added;
    try {
      added = await MistakeBook.instance.importJson(
        json,
        passphrase: passphrase,
      );
    } on FormatException catch (e) {
      if (!mounted) return;
      // v2.13 R8-P1：失败路径分流——
      //   加密包导入失败（错口令 / GCM tag 校验失败 / 文件损坏）：
      //     crypto 层 FormatException.message 形如「口令错误或密文被篡改
      //     （解密失败）」—— 直接透出，用户能直接定位问题
      //   明文包导入失败（坏 JSON / schemaVersion 不匹配）：
      //     保留 R6-P1 「文件格式错误（...）」文案，P0 #4 测试期望
      //     textContaining('导入失败：文件格式错误') 命中
      final reason = isEncrypted
          ? e.message
          : '文件格式错误（${e.message}）';
      _showSnack('导入失败：$reason');
      return;
    } on Exception catch (e) {
      // 兜底：未识别的解析错误也不让 app crash。
      if (!mounted) return;
      _showSnack('导入失败：$e');
      return;
    }
    if (!mounted) return;
    // v2.13 R8-P1：分流 SnackBar——
    //   加密包导入成功 → 「已加密 → 校验通过」（强化「端到端加密落地」）
    //   明文包导入成功 → 保留 R6-P1 「明文 JSON / 请确认来源可信」引导
    if (isEncrypted) {
      _showSnack(
        '已导入 $added 条新错题（加密 → 校验通过）',
        duration: const Duration(seconds: 5),
      );
    } else {
      _showSnack(
        '已导入 $added 条新错题（文件为明文 JSON，请确认来源可信）',
        duration: const Duration(seconds: 5),
      );
    }
  }

  /// v2.19.66：班级错题「合并导入」——老师收同学的错题包，按 题干+答案
  /// 去重后**只追加**，每条打「来自同学」来源标；本人 / 老师自己的题一条
  /// 都不动（[MistakeBook.classMergeImport] 的 [classIncomingToAdd] 口径）。
  ///
  /// 与 [_handleImport]（恢复备份 · 覆盖式）并列存在，**共用**同一个
  /// [MistakeImportDialog]（粘贴 / 从文件选）+ [_DecryptImportDialog]
  /// 解密嗅探——两条路径只差最后一步：这里走 classMergeImport。
  ///
  /// 回执：`并入 N 道（M 道与现有重复已跳过）`。
  Future<void> _handleMergeImport() async {
    final json = await showDialog<String>(
      context: context,
      builder: (_) => MistakeImportDialog(),
    );
    if (json == null || json.isEmpty || !mounted) return;

    // 加密包（同学用「加密导出」给的那种）→ 先要口令。
    final isEncrypted = MistakeBookCrypto.isEncryptedEnvelope(json);
    String? passphrase;
    if (isEncrypted) {
      passphrase = await showDialog<String>(
        context: context,
        builder: (_) => _DecryptImportDialog(),
      );
      if (passphrase == null) {
        if (!mounted) return;
        _showSnack('已取消');
        return;
      }
    }

    final ({int added, int skipped}) result;
    try {
      result = await MistakeBook.instance.classMergeImport(
        json,
        passphrase: passphrase,
      );
    } on FormatException catch (e) {
      if (!mounted) return;
      final reason = isEncrypted ? e.message : '文件格式错误（${e.message}）';
      _showSnack('合并失败：$reason');
      return;
    } on Exception catch (e) {
      if (!mounted) return;
      _showSnack('合并失败：$e');
      return;
    }
    if (!mounted) return;
    _showSnack(
      '并入 ${result.added} 道（${result.skipped} 道与现有重复已跳过）',
      duration: const Duration(seconds: 5),
    );
  }

  /// v2.13 R8-P1：加密导出 envelope 流程。
  ///
  /// 流程：
  ///   1. 弹 `_EncryptExportDialog` 让用户输入 + 确认口令（≥6 位）
  ///   2. 用户确认 → 调
  ///      `MistakeBook.instance.exportEncryptedJson(passphrase: pwd,
  ///       desensitize: true)` 拿到 envelope（**默认 desensitize=true**——
  ///      加密 + 浅脱敏双重保护；UI 不暴露 checkbox 简化体验）
  ///   3. 走 `MistakeBookExporter.saveToDownloads` 落盘
  ///   4. 成功 SnackBar 「错题本已加密导出：xxx（已加密 + 已脱敏）」
  ///      ——加密 + 脱敏双重保护，无需 amber 警告背景
  ///
  /// 取消 / 弱口令（<6 位）→ SnackBar 提示「已取消」/「口令至少 6 位」。
  /// 错误路径：FormatException（导出失败）走 try/catch 弹 SnackBar。
  Future<void> _handleExportEncrypted() async {
    final passphrase = await showDialog<String>(
      context: context,
      builder: (_) => _EncryptExportDialog(),
    );
    if (!mounted) return;
    if (passphrase == null) {
      _showSnack('已取消');
      return;
    }
    // dialog 内已做 ≥6 位校验，passphrase 不会走到这里 < 6。
    try {
      final envelope = await MistakeBook.instance.exportEncryptedJson(
        passphrase: passphrase,
        desensitize: true,
      );
      if (!mounted) return;
      final saved = await MistakeBookExporter.saveToDownloads(
        envelope,
        'biology_mistake_enc_${DateTime.now().millisecondsSinceEpoch}',
      );
      if (!mounted) return;
      if (saved == null) {
        _showSnack('导出失败');
        return;
      }
      if (saved.startsWith('导出失败') || saved == '未找到可写目录') {
        _showSnack(saved);
        return;
      }
      // 成功路径：SnackBar 不加 amber 背景（加密 + 脱敏双重保护，不需
      // 明文风险警示）；Android 走应用专属目录，文件名前缀 _enc_ 标识
      // 这是加密导出产物，落地后即使被其他 app 读也只能拿到 envelope。
      final isFilePath = !saved.startsWith('已触发');
      final isAndroid = MistakeBookExporter.isAndroidExport;
      final baseText = isFilePath
          ? (isAndroid
              ? '已保存到应用目录（加密 envelope，可分享）'
              : '错题本已加密导出：${pathBasename(saved)}')
          : saved;
      _showSnack(
        '$baseText（已加密 + 已脱敏）',
        duration: const Duration(seconds: 5),
      );
    } on FormatException catch (e) {
      if (!mounted) return;
      _showSnack('加密导出失败：${e.message}');
    } on Exception catch (e) {
      if (!mounted) return;
      _showSnack('加密导出失败：$e');
    }
  }

  /// v2.13+ R7-P2 P0：导出自练卷（RedFox 真实用户洞察「错题如果不
  /// 回到笔尖就只是看过」）。
  ///
  /// 零插件方案：生成 UTF-8 纯文本 .md 文件落到下载目录——
  ///   - 题目区：每条只输出 stem + 留白「我的上次答案：______」
  ///     （**不**输出 userAnswer——逼学生遮住答案页重写，回到笔尖）
  ///   - 答案与错因区（卷尾）：正确答案 + 错因 displayName + 考点
  ///     + AI 提示首行（无 AI 整理结果时跳过 AI 提示片段）
  ///
  /// 文件名 `自练卷_<yyyyMMdd_HHmm>.md`（学生周末打印方便归档）。
  /// 跨端：
  ///   - 桌面：写 ~/Downloads/，SnackBar [打开下载目录]
  ///   - Android：写应用专属目录（无公共 Downloads 权限），
  ///     SnackBar [分享] 走 shareFile → 微信/QQ/打印
  ///   - Web：浏览器下载（MIME 暂记 application/json 但后缀 .md
  ///     主流 Markdown 渲染器按文件名关联）
  ///
  /// 错误路径：空错题本 / 写盘失败 / 未找到目录 → SnackBar 提示，
  /// 不抛异常破坏主流程。
  Future<void> _handleExportSelfPractice() async {
    // v2.13+ 学生走查 P1：导出选项对话框——50 题一次导出 = 打印噩梦。
    // 范围（全部/仅待复习）+ 分组（单文件 / 按错因 / 按考点 多份）。
    final opt = await showDialog<({bool dueOnly, int groupBy})>(
      context: context,
      builder: (ctx) => _SelfPracticeOptionsDialog(),
    );
    if (opt == null || !mounted) return;

    var entries = MistakeBook.instance.entries;
    if (entries.isEmpty) {
      _showSnack('错题本是空的，先添加再导出自练卷');
      return;
    }
    if (opt.dueOnly) {
      entries = MistakeBook.instance.dueEntries();
      if (entries.isEmpty) {
        _showSnack('没有待复习的错题——都复习过了');
        return;
      }
    }

    // 分组：0=单文件；1=按错因；2=按考点。
    final ts = _formatTimestampForFilename(DateTime.now());
    final groups = <String, List<MistakeEntry>>{};
    if (opt.groupBy == 0) {
      groups[''] = entries.toList();
    } else {
      for (final e in entries) {
        final k = opt.groupBy == 1
            ? e.errorType.displayName
            : (e.subjectArea.isEmpty ? '未标注考点' : e.subjectArea);
        groups.putIfAbsent(k, () => []).add(e);
      }
    }

    var okCount = 0;
    var failMsg = '';
    String? lastSavedPath; // 成功后 SnackBar 的 打开目录/分享 action 目标
    for (final g in groups.entries) {
      final md = _buildSelfPracticeMarkdown(g.value, DateTime.now());
      final baseName = g.key.isEmpty ? '自练卷_$ts' : '自练卷_${g.key}_$ts';
      String? saved;
      try {
        saved = await _saveSelfPracticeToDownloads(md, baseName);
      } catch (e) {
        saved = '导出失败：$e';
      }
      if (saved == null ||
          saved.startsWith('导出失败') ||
          saved == '未找到可写目录') {
        failMsg = saved ?? '导出失败';
        break;
      }
      lastSavedPath = saved;
      okCount++;
    }
    if (!mounted) return;
    if (okCount == 0) {
      _showSnack(failMsg.isEmpty ? '导出失败' : failMsg);
      return;
    }
    final groupLabel = opt.groupBy == 1 ? '错因' : '考点';
    var content = '已导出 $okCount 个自练卷文件'
        '${groups.length > 1 ? "（按$groupLabel分组，共 ${entries.length} 题）" : '（共 ${entries.length} 题）'}';
    // 部分失败明细（分组多文件时某一组写盘失败不静默）。
    if (failMsg.isNotEmpty && okCount < groups.length) {
      content = '$content；有 1 组失败：$failMsg';
    }
    final isFilePath =
        lastSavedPath != null && !lastSavedPath.startsWith('已触发');
    final isAndroid = MistakeBookExporter.isAndroidExport;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(content),
        duration: const Duration(seconds: 4),
        action: isFilePath
            ? SnackBarAction(
                label: isAndroid ? '分享' : '打开下载目录',
                onPressed: isAndroid
                    ? () => _shareExportedFile(lastSavedPath!)
                    : () async {
                        final err = await MistakeBookExporter.openInExplorer(
                            lastSavedPath!);
                        if (err != null && mounted) _showSnack(err);
                      },
              )
            : null,
      ),
    );
  }

  /// 生成自练卷 Markdown 文本。
  ///
  /// 格式（严格按任务规格，UTF-8 纯文本）：
  ///   ```
  ///   # 生物错题自练卷（YYYY-MM-DD）
  ///   共 N 题。先遮住答案页独立完成，再对答案。
  ///
  ///   ## 题目
  ///   1. <stem>
  ///      我的上次答案：______
  ///
  ///   2. <stem>
  ///      我的上次答案：______
  ///
  ///   ## 答案与错因（做完再看）
  ///   1. 正确答案：<correctAnswer>　错因：<errorType.displayName>[　考点：<subjectArea>][　AI 提示：<aiSummary 首行>]
  ///   ...
  ///   ```
  ///
  /// 关键约束：
  ///   - **不**把 userAnswer 写入任何区（题目区留「______」逼学生重写）
  ///   - correctAnswer 只能在卷尾区出现（题目区绝不暴露）
  ///   - 「考点：」「AI 提示：」段只在数据非空时输出
  ///   - AI 提示取 aiSummary 首行（多行就只取第一行，避免答案区膨胀）
  String _buildSelfPracticeMarkdown(
      List<MistakeEntry> entries, DateTime now) {
    final buf = StringBuffer();
    final dateStr =
        '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    buf.writeln('# 生物错题自练卷（$dateStr）');
    buf.writeln('共 ${entries.length} 题。先遮住答案页独立完成，再对答案。');
    buf.writeln();
    buf.writeln('## 题目');
    for (var i = 0; i < entries.length; i++) {
      final e = entries[i];
      buf.writeln('${i + 1}. ${e.stem}');
      // v2.13+ 学生走查 P0：留白从 1 行扩到 4 行（长答案/图解抄写
      // 空间不足），hint 明示写不下怎么办。
      buf.writeln('   我的上次答案（写不下用背面）：');
      for (var line = 0; line < 4; line++) {
        buf.writeln('   ________');
      }
      buf.writeln();
    }
    buf.writeln('## 答案与错因（做完再看）');
    for (var i = 0; i < entries.length; i++) {
      final e = entries[i];
      buf.write('${i + 1}. 正确答案：${e.correctAnswer}　错因：${e.errorType.displayName}');
      if (e.subjectArea.trim().isNotEmpty) {
        buf.write('　考点：${e.subjectArea}');
      }
      final aiFirst = _firstLine(e.aiSummary);
      if (aiFirst != null && aiFirst.isNotEmpty) {
        buf.write('　AI 提示：$aiFirst');
      }
      buf.writeln();
      buf.writeln();
    }
    return buf.toString();
  }

  /// 取 [s] 首行（按 \n 切），trim 后非空才返回；空 / null / 空白都返 null。
  String? _firstLine(String? s) {
    if (s == null) return null;
    final t = s.trim();
    if (t.isEmpty) return null;
    final nl = t.indexOf('\n');
    return nl < 0 ? t : t.substring(0, nl).trimRight();
  }

  /// 文件名时间戳：yyyyMMdd_HHmm（无冒号，Windows 文件名安全）。
  String _formatTimestampForFilename(DateTime now) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${now.year}${two(now.month)}${two(now.day)}_'
        '${two(now.hour)}${two(now.minute)}';
  }

  /// 跨端保存自练卷 .md：复用 MistakeBookExporter 路径解析约定
  ///（debugDownloadsDir → Android userAppDir → 桌面 ~/Downloads），
  /// 但写出后缀 = .md（Exposer 的 saveToDownloads 硬编码 .json）。
  ///
  /// 返回语义与 MistakeBookExporter.saveToDownloads 对齐：
  ///   - 桌面 / Android：用户可见的文件路径
  ///   - Web：标记 '已触发浏览器下载'
  ///   - 错误：'导出失败：xxx' / '未找到可写目录'
  ///
  /// 为什么不直接用 MistakeBookExporter：它的 saveToDownloads 内部
  /// 写 `${baseName}.json`，改签名 / 拆方法都越界（任务只允许改
  /// mistake_book_page.dart）。这里重写一份走同套目录解析约定即可。
  Future<String?> _saveSelfPracticeToDownloads(
      String md, String baseName) async {
    if (kIsWeb) {
      try {
        webimpl.webTriggerDownload(md, '$baseName.md');
        return '已触发浏览器下载';
      } catch (e) {
        return '导出失败：$e';
      }
    }
    // 桌面 / Android：等 getFilesDir 缓存就绪（同 saveToDownloads）。
    await ensureAppDirReady();
    try {
      final dir = _resolveSelfPracticeDir();
      if (dir == null) return '未找到可写目录';
      final f = File('${dir.path}${Platform.pathSeparator}$baseName.md');
      await f.writeAsString(md, flush: true);
      return f.path;
    } catch (e) {
      return '导出失败：$e';
    }
  }

  /// 解析自练卷导出目录：与 MistakeBookExporter._resolveDownloadsDir
  /// 同款三档——debugDownloadsDir（测试注入）> Android userAppDir
  /// （应用专属，无公共 Downloads 权限）> 桌面 ~/Downloads。
  static Directory? _resolveSelfPracticeDir() {
    if (MistakeBookExporter.debugDownloadsDir != null) {
      return Directory(MistakeBookExporter.debugDownloadsDir!)
        ..createSync(recursive: true);
    }
    if (MistakeBookExporter.isAndroidExport) {
      final appDir = userAppDir();
      if (appDir == null) return null;
      return Directory(appDir)..createSync(recursive: true);
    }
    final home = kIsWeb
        ? null
        : (Platform.environment['USERPROFILE'] ?? Platform.environment['HOME']);
    if (home == null) return null;
    return Directory('$home${Platform.pathSeparator}Downloads')
      ..createSync(recursive: true);
  }
}

// ============================================================================
// 子组件
// ============================================================================

/// v2.19.61：错因分布卡本体（**可折叠，默认展开**）。
///
/// 自绘紧凑头部（标题 + 视图切换 + 最高频错因文案 + 折叠图标），**不用**
/// ExpansionTile——它的 ListTile 头部至少 ~48px 起步，本卡的高度预算
/// 放不下（见 [_MistakeBookPageState._buildCauseRadarCard] 的高度说明）。
///
/// 数据即 [counts]（自评）/ [causeKeyCounts]（AI 判），不做二次聚合；文案
/// 由 [mistakeCauseSummary] / [mistakeCauseKeySummary] 生成。
///
/// v2.19.62：卡头加「自评 | AI 判」双视图切换。默认**自评**视图 ⇒ 既有
/// 视觉零变化。AI 视图在 [hasAiCauseKey] 为 false 时渲染诚实空态、不画图。
class _CauseRadarCard extends StatefulWidget {
  const _CauseRadarCard({
    required this.counts,
    required this.causeKeyCounts,
    required this.hasAiCauseKey,
  });

  /// 自评视图数据（errorType 五轴）。
  final Map<MistakeErrorType, int> counts;

  /// AI 判视图数据（causeKey 六轴）。
  final Map<MistakeCauseKey, int> causeKeyCounts;

  /// 全库是否至少有一条 causeKey 非空（AI 视图有无可画的数据）。
  final bool hasAiCauseKey;

  @override
  State<_CauseRadarCard> createState() => _CauseRadarCardState();
}

class _CauseRadarCardState extends State<_CauseRadarCard> {
  /// 默认展开。
  bool _expanded = true;

  /// 视图：false = 自评（默认，零变化）；true = AI 判。
  bool _aiView = false;

  @override
  Widget build(BuildContext context) {
    // ⛔ 横排是**高度预算**逼出来的：卡高必须压到 ~150px 以下（否则列表
    // 可视区被压掉、末尾几道题在屏外，既有页面测试会找不到题）。竖排
    // 时「标题行 + 图」叠起来要 ~38px 头部 + 图高；横排把标题/文案移到
    // 图左边，头部 38px 就省下来了 ⇒ 同样的卡高能把图开到 [size] 这么大。
    // v2.19.62 的视图切换 chips 塞进标题行——标题行之上的图高（136px）
    // 远大于文字列（~104px），故加 chips **不**抬高卡高。
    return InkWell(
      onTap: () => setState(() => _expanded = !_expanded),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 6, 10, 6),
        child: Row(
          children: [
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ⛔ Wrap 而非 Row：360 窄屏下内容宽只有 ~162px，「标题 +
                  // 两个 chip + 折叠图标」一行放不下会 RenderFlex 溢流
                  // （与本仓徽章行同款收口——折行而不是挤爆）。宽屏仍单行。
                  Wrap(
                    spacing: 6,
                    runSpacing: 2,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      // height: 1.2 = 紧凑标题（本卡高度预算以「像素」计）。
                      Text('错因分布',
                          style: AppText.sectionTitle.copyWith(height: 1.2)),
                      _viewChip('自评', !_aiView, () {
                        if (_aiView) setState(() => _aiView = false);
                      }),
                      _viewChip('AI 判', _aiView, () {
                        if (!_aiView) setState(() => _aiView = true);
                      }),
                      Icon(
                        _expanded ? Icons.expand_less : Icons.expand_more,
                        size: 18,
                        color: AppColors.steel,
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _aiView
                        ? mistakeCauseKeySummary(widget.causeKeyCounts)
                        : mistakeCauseSummary(widget.counts),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.caption,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            if (_expanded) _chartOrEmpty(),
          ],
        ),
      ),
    );
  }

  /// 图区（宽 = [kCauseRadarCardChartSize]，与图体同宽以免切换时跳动）。
  Widget _chartOrEmpty() {
    if (!_aiView) {
      // ⛔ 不得 const（消费 AppColors token，const 会冻结主题色，
      // 主题切换时颜色不刷新）。
      return CauseRadarChart(
        counts: widget.counts,
        size: kCauseRadarCardChartSize,
      );
    }
    if (widget.hasAiCauseKey) {
      return CauseKeyRadarChart(
        counts: widget.causeKeyCounts,
        size: kCauseRadarCardChartSize,
      );
    }
    // 诚实空态：全库没有一条被 AI 判过 ⇒ 不画图，只说明口径 + 出路。
    return SizedBox(
      width: kCauseRadarCardChartSize,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.auto_awesome_outlined, size: 28, color: AppColors.steel),
          const SizedBox(height: 4),
          Text('还没有 AI 判过的错因',
              textAlign: TextAlign.center, style: AppText.label),
          const SizedBox(height: 2),
          Text('点卡片上的 AI 整理试试',
              textAlign: TextAlign.center,
              style: AppText.caption.copyWith(color: AppColors.steel)),
        ],
      ),
    );
  }

  /// 紧凑视图切换 chip（自绘，~22px 高——本卡高度预算以像素计）。
  Widget _viewChip(String label, bool selected, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: selected ? AppColors.tealWash : null,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: selected ? AppColors.teal : AppColors.border,
          ),
        ),
        child: Text(
          label,
          style: AppText.caption.copyWith(
            color: selected ? AppColors.teal : AppColors.steel,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  _EmptyState();
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.menu_book_outlined,
                size: 64, color: AppColors.steel),
            const SizedBox(height: 16),
            Text('还没有错题', style: AppText.sectionTitle),
            const SizedBox(height: 8),
            Text(
              // v2.13 学生走查 P1：空态给具体路径，不只「点 +」。
              '点右上角 + 手动添加；\n'
              '更省事：回首页点右下角「拍题」拍照识别，\n'
              '或算完题点「存入错题本」一键收录。\n'
              'AI 会帮你归类错因、提炼易错点、总结薄弱点。',
              textAlign: TextAlign.center,
              style: AppText.body.copyWith(color: AppColors.steel),
            ),
          ],
        ),
      ),
    );
  }
}

/// v2.13 R3 P1-B4：错题本有内容但搜索/错因筛选后无匹配 → 空结果态。
/// 与 _EmptyState（真空书）区分：这里的重点是给用户一条出路——
/// [清除筛选] 一键恢复，而不是让用户以为错题被删了。
class _NoResultState extends StatelessWidget {
  final VoidCallback onClear;
  const _NoResultState({required this.onClear});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.search_off, size: 56, color: AppColors.steel),
            const SizedBox(height: 12),
            Text('没有符合条件的错题', style: AppText.sectionTitle),
            const SizedBox(height: 6),
            Text(
              '换个关键词，或清除筛选看全部错题。',
              style: AppText.caption.copyWith(color: AppColors.steel),
            ),
            const SizedBox(height: 14),
            FilledButton.tonalIcon(
              key: const Key('mistake_clear_filter_btn'),
              onPressed: onClear,
              icon: const Icon(Icons.filter_alt_off_outlined, size: 18),
              label: const Text('清除筛选'),
            ),
          ],
        ),
      ),
    );
  }
}

class _BusyOverlay extends StatelessWidget {
  _BusyOverlay();
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 16),
          // v2.13 学生走查 P1：动作化措辞——学生不知道「AI 整理」是干什么。
        Text('正在帮你归类错因、提炼易错点…',
            style: AppText.body.copyWith(color: AppColors.steel)),
        ],
      ),
    );
  }
}

/// v2.12 R1 P0 #5+#6：AppBar PopupMenu 三项。
///
/// v2.13 R8-P1：第 4 项 `exportEncrypted`——AES-256-GCM 端到端加密导出。
/// 菜单顺序刻意把「加密导出（推荐）」放在「导出 JSON」下方，让用户在
/// 默认场景下先看到加密选项；导入侧的加密检测改为自动嗅探，不加新菜单
/// 项（避免菜单项过多）。
///
/// v2.13+ R7-P2 P0：新增 `exportSelfPractice`（导出自练卷）—— RedFox
/// 真实用户洞察「错题如果不回到笔尖就只是看过」。放在菜单末位，刻意
/// 跟数据类导出（JSON/加密）区分开（一个走打印/抄写，一个走备份迁移）。
enum _MistakeOverflowAction {
  trash,
  export,
  exportEncrypted,
  importJson,
  // v2.19.66：班级错题合并导入（与 importJson 覆盖式恢复并列）。
  classMergeImport,
  exportSelfPractice,
}

/// v2.12 R1 P0 #5：错题本回收站对话框。
///
/// 列出 7 天内删除的条目（按 deletedAt 倒序），每条带：
///   - 删除时间（相对描述，如 "3 小时前" / "2 天前"）
///   - 恢复按钮（调 MistakeBook.restoreFromTrash）
///   - 永久删除按钮（调 MistakeBook.permanentlyDelete，lethal 描边）
///
/// 空状态："回收站空空如也～" 友好提示。
class _MistakeTrashDialog extends StatefulWidget {
  _MistakeTrashDialog();
  @override
  State<_MistakeTrashDialog> createState() => _MistakeTrashDialogState();
}

class _MistakeTrashDialogState extends State<_MistakeTrashDialog> {
  @override
  void initState() {
    super.initState();
    MistakeBook.instance.addListener(_onChanged);
  }

  @override
  void dispose() {
    MistakeBook.instance.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final trash = MistakeBook.instance.trash;
    return AlertDialog(
      title: Row(
        children: [
          const Icon(Icons.delete_outline),
          const SizedBox(width: 8),
          const Text('回收站'),
          const Spacer(),
          Text('${trash.length} 条 · 7 天后自动清理',
              style: AppText.caption),
        ],
      ),
      content: SizedBox(
        width: double.maxFinite,
        height: 400,
        child: trash.isEmpty
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.inbox_outlined,
                          size: 64, color: AppColors.steel),
                      const SizedBox(height: 12),
                      Text('回收站空空如也～', style: AppText.sectionTitle),
                      const SizedBox(height: 6),
                      Text('已删除的错题会在这里保留 7 天',
                          style: AppText.caption,
                          textAlign: TextAlign.center),
                    ],
                  ),
                ),
              )
            : ListView.separated(
                shrinkWrap: true,
                itemCount: trash.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (_, i) => _TrashItemTile(
                  entry: trash[i],
                  onRestore: () {
                    final r = MistakeBook.instance
                        .restoreFromTrash(trash[i].id);
                    if (r != null && mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('已恢复：${trash[i].entry.stem}'),
                          duration: const Duration(seconds: 2),
                        ),
                      );
                    }
                  },
                  onPermanentlyDelete: () =>
                      MistakeBook.instance
                          .permanentlyDelete(trash[i].id),
                ),
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('关闭'),
        ),
      ],
    );
  }
}

class _TrashItemTile extends StatelessWidget {
  final MistakeTrashEntry entry;
  final VoidCallback onRestore;
  final VoidCallback onPermanentlyDelete;
  const _TrashItemTile({
    required this.entry,
    required this.onRestore,
    required this.onPermanentlyDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            entry.entry.stem,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: AppText.body,
          ),
          const SizedBox(height: 4),
          Text(_relativeTime(entry.deletedAt),
              style: AppText.caption.copyWith(color: AppColors.steel)),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton.icon(
                onPressed: onPermanentlyDelete,
                icon: const Icon(Icons.delete_forever_outlined, size: 16),
                label: const Text('永久删除'),
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.lethal,
                ),
              ),
              const SizedBox(width: 8),
              FilledButton.tonalIcon(
                onPressed: onRestore,
                icon: const Icon(Icons.restore, size: 16),
                label: const Text('恢复'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static String _relativeTime(DateTime t) {
    final now = DateTime.now();
    final diff = now.difference(t);
    if (diff.inDays >= 1) return '${diff.inDays} 天前删除';
    if (diff.inHours >= 1) return '${diff.inHours} 小时前删除';
    if (diff.inMinutes >= 1) return '${diff.inMinutes} 分钟前删除';
    return '刚刚删除';
  }
}

/// v2.12 R1 P0 #6：导入 JSON 对话框。
///
/// 用户从「更多」菜单 → 「导入 JSON」触发。弹 dialog 让用户：
///   1. 粘贴 JSON 文本（原有路径，保留作兜底——粘贴板里已有 JSON
///      内容的用户仍能一键导入，不强制走文件选择器）
///   2. v2.12+ R1 final D P0 #5 新增：从 .json 文件选（更直观，
///      Web 端用户从下载目录拿 JSON 不用再"打开→复制→粘贴"四步）
///
/// 提交后调 MistakeBook.importJson。
///
/// 错误处理：空内容 / JSON 损坏 / schemaVersion 不匹配 → 弹 SnackBar
/// 提示「导入失败：xxx」，不抛异常破坏主流程。
///
/// 公开（不 _ 前缀）的原因：P0 #5 测试需要 mock jsonPicker——showDialog
/// 的 builder 在 _handleImport 内部，测试无法直接传 picker 给 builder。
/// 改公开后测试可以 `showDialog(builder: (_) => MistakeImportDialog(jsonPicker: ...))`。
/// 命名不 _ 前缀与 lib/pages/mistake_book_page.dart 内其它 _ 子组件
/// 不一致是有意取舍：保留 _ 前缀的话 P0 #5 测试要改走静态 hook
/// （如 MistakeImportDialog.debugPicker），设计更重；公开更轻。
/// v2.13 R4-4：导出确认对话框——「脱敏导出」checkbox（默认不勾选）。
///
/// v2.13 R6-P1：默认翻转为「勾选 = 脱敏」（与 MistakeBook.exportJson
/// 默认 desensitize=true 对齐）——只有当用户主动取消勾选时才导明文
/// JSON。这是 P1 隐私根因中「默认 desensitize=false 无强引导」一项的
/// 最小可行修复：AES-GCM 端到端加密属重工程，推到 R7 路线图；本轮先
/// 用「默认脱敏 + 显式明文二选一」覆盖大部分误用场景。
///
/// 返回 bool?：null = 取消；false = 普通导出（明文）；true = 脱敏导出。
class _ExportDialog extends StatefulWidget {
  _ExportDialog();

  @override
  State<_ExportDialog> createState() => _ExportDialogState();
}

class _ExportDialogState extends State<_ExportDialog> {
  // v2.13 R6-P1：默认勾选（= 脱敏）。用户主动取消勾选才导明文。
  bool _desensitize = true;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('导出错题 JSON'),
      content: SizedBox(
        width: 440,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '导出的 JSON 含你的错题内容与答案，属于个人数据。'
              '文件会保存到下载目录 / 公共存储，请勿公开分享。',
              style: AppText.caption,
            ),
            const SizedBox(height: 4),
            Text(
              '浅脱敏只做 token 级替换（人名→某某、学号→×××），'
              '不做全文理解，依赖正则规则。',
              style: AppText.caption.copyWith(color: AppColors.steel),
            ),
            const SizedBox(height: 8),
            CheckboxListTile(
              key: const Key('mistake_export_desensitize_check'),
              value: _desensitize,
              onChanged: (v) => setState(() => _desensitize = v ?? true),
              title: const Text('脱敏导出（推荐）'),
              subtitle: const Text('人名→某某，学号→×××；默认勾选'),
              controlAffinity: ListTileControlAffinity.leading,
              contentPadding: EdgeInsets.zero,
              dense: true,
            ),
            // v2.13 R6-P1：取消勾选时的明文导出风险提示——只有
            // 用户主动取消勾选才显示，避免视觉噪音。
            if (!_desensitize) ...[
              const SizedBox(height: 4),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.sand.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  children: [
                    Icon(Icons.warning_amber_outlined,
                        size: 16, color: AppColors.sand),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        '明文导出：文件含原始人名 / 学号，落到下载目录后其他 app 可读，'
                        '请仅在自己信任的设备上使用。',
                        style: AppText.caption.copyWith(color: AppColors.sand),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          key: const Key('mistake_export_confirm_btn'),
          onPressed: () => Navigator.of(context).pop(_desensitize),
          child: const Text('导出'),
        ),
      ],
    );
  }
}

/// 导入错题 JSON 的对话框（粘贴 / 从文件选两条路径）。
class MistakeImportDialog extends StatefulWidget {
  /// v2.12+ R1 final D P0 #5：测试注入的 json picker（覆盖默认
  /// lib/ui/json_pick.dart 的 pickJsonFile）。生产代码不传，走
  /// 默认条件导入；测试 mock 一个 `Future<PickedJson?>` 让 dialog
  /// 不依赖平台对话框。
  // ignore: unused_element_parameter
  const MistakeImportDialog({super.key, this.jsonPicker});

  final Future<PickedJson?> Function()? jsonPicker;

  @override
  State<MistakeImportDialog> createState() => _MistakeImportDialogState();
}

class _MistakeImportDialogState extends State<MistakeImportDialog> {
  final _controller = TextEditingController();
  bool _picking = false; // v2.12+ R1 final D P0 #5：选文件时禁用按钮

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final raw = _controller.text.trim();
    if (raw.isEmpty) {
      Navigator.of(context).pop(null);
      return;
    }
    Navigator.of(context).pop(raw);
  }

  /// v2.12+ R1 final D P0 #5：点「从文件选 .json」→ 调 json picker
  /// 拿 PickedJson → 直接 pop 全文。选失败（用户取消 / 平台不支持）
  /// 不弹错，dialog 保持打开（用户可改走粘贴路径）。
  Future<void> _pickFromFile() async {
    if (_picking) return;
    setState(() => _picking = true);
    try {
      final picker = widget.jsonPicker ?? pickJsonFile;
      final picked = await picker();
      if (!mounted) return;
      if (picked == null) {
        // 用户取消 / 平台不支持——保持 dialog 打开，让用户改走粘贴
        return;
      }
      Navigator.of(context).pop(picked.content);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('选文件失败：$e')),
      );
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('导入错题 JSON'),
      content: SizedBox(
        width: 480,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '粘贴之前导出的 JSON 内容，或从 .json 文件直接选。'
              '已存在的错题会被跳过，新增的会追加到当前列表。',
              style: AppText.caption,
            ),
            const SizedBox(height: 4),
            // v2.19.66：防误点覆盖——把本对话框（恢复备份）与「合并同学
            // 错题包」入口在文案上明确区分。合并走菜单里的另一项。
            Text(
              '本入口用于「恢复备份」。只想合并同学的错题包，请改用菜单里的'
              '「合并同学错题包」（按题干+答案去重、只追加、不覆盖本人题）。',
              style: AppText.caption.copyWith(color: AppColors.steel),
            ),
            const SizedBox(height: 12),
            // v2.12+ R1 final D P0 #5：「从文件选 .json」入口——outlined
            // 风格表次要操作（主操作仍是粘贴 + 「导入」），与拍题对话框
            // 里的「选择题目图片」按钮风格对齐。
            OutlinedButton.icon(
              key: const Key('mistake_import_pick_file_btn'),
              onPressed: _picking ? null : _pickFromFile,
              icon: _picking
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.file_open_outlined, size: 18),
              label: const Text('从文件选 .json'),
              style: OutlinedButton.styleFrom(
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _controller,
              maxLines: 8,
              minLines: 4,
              decoration: const InputDecoration(
                hintText: '{"schemaVersion": 1, "entries": [...], ...}',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(null),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: _picking ? null : _submit,
          child: const Text('导入'),
        ),
      ],
    );
  }
}

/// v2.13 R8-P1：加密导出对话框——双输入口令 + 确认 + ≥6 位校验。
///
/// 返回值：用户确认 → 返回 passphrase 字符串；取消 → 返回 null；
/// 弱口令（<6 位）→ 「确认」按钮置灰不可点。
///
/// 设计：故意不暴露「脱敏 / 不脱敏」选项——加密场景默认走脱敏
///（加密 + 浅脱敏双重保护），简化用户决策。强场景下「明文导出」
/// 仍走旧路径（脱敏 exportJson dialog）。
class _EncryptExportDialog extends StatefulWidget {
  _EncryptExportDialog();

  @override
  State<_EncryptExportDialog> createState() => _EncryptExportDialogState();
}

class _EncryptExportDialogState extends State<_EncryptExportDialog> {
  final _passController = TextEditingController();
  final _confirmController = TextEditingController();
  bool _obscure = true;

  @override
  void dispose() {
    _passController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  /// 校验：两个输入都不空 + 长度 ≥ 6 + 两次输入一致。
  bool get _isValid {
    final p = _passController.text;
    final c = _confirmController.text;
    return p.isNotEmpty && p.length >= 6 && p == c;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.lock_outline),
          SizedBox(width: 8),
          Text('加密导出'),
        ],
      ),
      content: SizedBox(
        width: 440,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '文件会用 AES-256-GCM 端到端加密 + PBKDF2 × 100k 派生 key，'
              '无口令不可读。导出后默认还做了浅脱敏（人名→某某、学号→×××）。',
              style: AppText.caption,
            ),
            const SizedBox(height: 12),
            TextField(
              key: const Key('mistake_encrypt_pwd_field'),
              controller: _passController,
              obscureText: _obscure,
              decoration: InputDecoration(
                labelText: '口令（至少 6 位）',
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  icon: Icon(_obscure ? Icons.visibility : Icons.visibility_off),
                  onPressed: () => setState(() => _obscure = !_obscure),
                ),
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 8),
            TextField(
              key: const Key('mistake_encrypt_pwd_confirm_field'),
              controller: _confirmController,
              obscureText: _obscure,
              decoration: const InputDecoration(
                labelText: '再次输入口令',
                border: OutlineInputBorder(),
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 6),
            if (_passController.text.isNotEmpty &&
                _passController.text.length < 6)
              Text('口令至少 6 位', style: AppText.caption.copyWith(color: Colors.red))
            else if (_confirmController.text.isNotEmpty &&
                _passController.text != _confirmController.text)
              Text('两次输入不一致', style: AppText.caption.copyWith(color: Colors.red))
            else
              Text('请牢记口令——无口令无法恢复',
                  style: AppText.caption.copyWith(color: AppColors.steel)),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          key: const Key('mistake_encrypt_confirm_btn'),
          onPressed: _isValid
              ? () => Navigator.of(context).pop(_passController.text)
              : null,
          child: const Text('加密导出'),
        ),
      ],
    );
  }
}

/// v2.13 R8-P1：解密导入对话框——单输入口令。
///
/// 返回值：用户确认 → 返回 passphrase 字符串；取消 → 返回 null。
/// 错误处理：错口令 / 文件损坏由 `importJson` 抛 FormatException
/// 在 `_handleImport` 顶层 try/catch 捕获弹 SnackBar。
class _DecryptImportDialog extends StatefulWidget {
  _DecryptImportDialog();

  @override
  State<_DecryptImportDialog> createState() => _DecryptImportDialogState();
}

class _DecryptImportDialogState extends State<_DecryptImportDialog> {
  final _passController = TextEditingController();
  bool _obscure = true;

  @override
  void dispose() {
    _passController.dispose();
    super.dispose();
  }

  bool get _isValid => _passController.text.isNotEmpty;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.lock_open),
          SizedBox(width: 8),
          Text('输入加密口令'),
        ],
      ),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '检测到这是加密导出的错题本（envelope 格式）。'
              '请输入导出时设置的口令解密。',
              style: AppText.caption,
            ),
            const SizedBox(height: 12),
            TextField(
              key: const Key('mistake_decrypt_pwd_field'),
              controller: _passController,
              obscureText: _obscure,
              autofocus: true,
              decoration: InputDecoration(
                labelText: '口令',
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  icon: Icon(_obscure ? Icons.visibility : Icons.visibility_off),
                  onPressed: () => setState(() => _obscure = !_obscure),
                ),
              ),
              onChanged: (_) => setState(() {}),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          key: const Key('mistake_decrypt_confirm_btn'),
          onPressed: _isValid
              ? () => Navigator.of(context).pop(_passController.text)
              : null,
          child: const Text('解密导入'),
        ),
      ],
    );
  }
}

/// v2.12+ R1 P0 #3：单条 entry 卡片底部的「AI 整理中…」轻量提示。
/// 与 _BusyOverlay 区分：_BusyOverlay 是全页 busy 蒙层（手动按「AI
/// 整理全部」时全屏 spinner），本 widget 是「自动后台整理中」时
/// 卡片底部一行小提示——不抢用户视线，但能让用户感知"AI 在动"。
///
/// 设计权衡：用静态 `auto_awesome` icon 而非 CircularProgressIndicator
/// 的无限循环动画——后者会让 widget tester 的 `pumpAndSettle` 永不
/// 沉降（连续帧动画），破坏既有的"添加 → 列表立刻看到"测试。
/// 静态 icon + 文字"AI 整理中…"已足够传达"正在后台跑"。
class _AiOrganizingHint extends StatelessWidget {
  const _AiOrganizingHint();
  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(Icons.auto_awesome, size: 12, color: AppColors.teal),
        const SizedBox(width: 6),
        // v2.13 学生走查 P1：动作化措辞（学生不知道「AI 整理」干什么）。
        Text('正在归类错因、提炼易错点…',
            style: AppText.caption.copyWith(color: AppColors.teal)),
      ],
    );
  }
}


class _MistakeCard extends StatelessWidget {
  final MistakeEntry entry;
  final VoidCallback onTap;
  final VoidCallback? onAiTap;

  /// v2.12+ R1 P0 #3：true = 卡片在后台 AI 整理中，显示「AI 整理中…」hint。
  /// 由父 _MistakeBookPageState 通过 _aiOrganizingIds 集合判定后传入。
  final bool aiOrganizing;

  /// v2.13 R3 P1-B4：当前生效的错因筛选（决定卡片错误类型 chip 的
  /// selected 态）；null = 未筛选。
  final MistakeErrorType? errorTypeFilter;

  /// v2.13 R3 P1-B4：点卡片错误类型 chip → 按该类型筛选（父层再点
  /// 同类型会取消，保持与顶部 FilterChip 一致的单选语义）。
  final VoidCallback? onErrorTypeTap;

  /// v2.13 R4-4：「查看归类」定位后 2 秒高亮（tealWash 底色渐入渐出）。
  final bool highlight;

  const _MistakeCard({
    super.key,
    required this.entry,
    required this.onTap,
    this.onAiTap,
    this.aiOrganizing = false,
    this.errorTypeFilter,
    this.onErrorTypeTap,
    this.highlight = false,
  });

  @override
  Widget build(BuildContext context) {
    // v2.13 R4-4：高亮 = AnimatedContainer 底色（tealWash）动画过渡。
    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      decoration: BoxDecoration(
        color: highlight ? AppColors.tealWash : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          onLongPress: () => _showMenu(context),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildHeader(),
                const SizedBox(height: 8),
                _buildStem(),
                const SizedBox(height: 8),
                _buildAnswers(),
                const SizedBox(height: 8),
                _buildChips(),
                // v2.12+ R1 P0 #3：后台 AI 整理中 → 显示 hint。
                // 放在 chips 之后、AI 整理结果之前——有结果时不显示
                // hint，结果到位自动覆盖。
                if (aiOrganizing &&
                    (entry.aiSummary == null || entry.aiSummary!.isEmpty))
                  // v2.19.23 找茬 §4.8：外层 const 使 child 隐式 const →
                  // identical 短路冻结（lint 盲区）。去外层 const。
                  Padding(
                    padding: const EdgeInsets.only(top: 6, bottom: 2),
                    child: _AiOrganizingHint(),
                  ),
                if (entry.aiSummary != null && entry.aiSummary!.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  _buildAiResult(),
                ],
                if (entry.aiOverview != null &&
                    entry.aiOverview!.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  _buildOverview(),
                ],
                const SizedBox(height: 8),
                // v2.19.34 错题本闭环：「回来源工具重算」+「考哪条课标」
                // 两枚都在**同一行**（两件事都属于「接下来做什么」：想重做
                // 就点重算，想看考纲就点徽章）。无来源时这一整行不存在。
                if (mistakeEntryHasSource(entry)) ..._refillRow(context),
                _buildActions(context),
              ],
            ),
          ),
        ),
      ),
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      children: [
        Icon(Icons.bookmark_outline, size: 16, color: AppColors.teal),
        const SizedBox(width: 6),
        Text(
          entry.subjectArea.isEmpty ? '未关联考点' : entry.subjectArea,
          style: AppText.label.copyWith(color: AppColors.teal),
        ),
        const Spacer(),
        Text(
          _formatTime(entry.createdAt),
          style: AppText.caption.copyWith(color: AppColors.steel),
        ),
      ],
    );
  }

  Widget _buildStem() {
    final tag = entry.sourceTag;
    final hasTag = tag != null && tag.trim().isNotEmpty;
    final stemText = Text(
      entry.stem,
      maxLines: 3,
      overflow: TextOverflow.ellipsis,
      style: AppText.body,
    );
    if (!hasTag) return stemText;
    // v2.19.66：来源标——合并进来的同学题在题干行尾打小 caption。颜色用
    // steel（中性）**不用红**：这不是错误提示，只是「归谁的」。
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(child: stemText),
        const SizedBox(width: 8),
        Text(
          tag.trim(),
          style: AppText.caption.copyWith(color: AppColors.steel),
        ),
      ],
    );
  }

  Widget _buildAnswers() {
    // v2.12+ R2 A2 P1-3：答案空缺 → 橙色边框 + 「待补充」文字，
    // 让"这题还缺答案、等着补"一眼可见（旧版只有灰色「（未填）」
    // 太不明显，学生容易漏补）。
    final missingUserAnswer = entry.userAnswer.isEmpty;
    final missingCorrectAnswer = entry.correctAnswer.isEmpty;
    final hasMissing = missingUserAnswer || missingCorrectAnswer;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: hasMissing ? Colors.orange : AppColors.border,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('错答：',
                  style:
                      AppText.caption.copyWith(color: AppColors.lethal)),
              Expanded(
                child: Text(
                  missingUserAnswer ? '待补充' : entry.userAnswer,
                  style: AppText.body.copyWith(
                    color: missingUserAnswer
                        ? Colors.orange
                        : AppColors.lethal,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Text('正答：',
                  style: AppText.caption.copyWith(color: AppColors.teal)),
              Expanded(
                child: Text(
                  missingCorrectAnswer ? '待补充' : entry.correctAnswer,
                  style: AppText.body.copyWith(
                    color: missingCorrectAnswer
                        ? Colors.orange
                        : AppColors.teal,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildChips() {
    return Wrap(
      spacing: 8,
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        // v2.13 R3 P1-B4：错误类型 chip 变 FilterChip（可点筛选）。
        _ErrorTypeChip(
          type: entry.errorType,
          selected: errorTypeFilter == entry.errorType,
          onTap: onErrorTypeTap,
        ),
        _ReviewStatusChip(
          status: entry.reviewStatus,
          onChanged: (s) {
            MistakeBook.instance.markStatus(entry.id, s);
          },
        ),
      ],
    );
  }

  Widget _buildAiResult() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.tealWash,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.auto_awesome, size: 14, color: AppColors.teal),
              const SizedBox(width: 6),
              Text('AI 整理', style: AppText.caption.copyWith(color: AppColors.teal)),
            ],
          ),
          const SizedBox(height: 4),
          Text(entry.aiSummary!, style: AppText.body),
          if (entry.aiPitfalls.isNotEmpty) ...[
            const SizedBox(height: 6),
            for (final p in entry.aiPitfalls)
              Padding(
                padding: const EdgeInsets.only(left: 6, top: 2),
                child: Text('• $p',
                    style: AppText.caption
                        .copyWith(color: AppColors.graphite)),
              ),
          ],
        ],
      ),
    );
  }

  Widget _buildOverview() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.summarize, size: 14, color: AppColors.steel),
              const SizedBox(width: 6),
              Text('AI 总览块',
                  style:
                      AppText.caption.copyWith(color: AppColors.steel)),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            entry.aiOverview!,
            maxLines: 4,
            overflow: TextOverflow.ellipsis,
            style: AppText.caption.copyWith(color: AppColors.graphite),
          ),
        ],
      ),
    );
  }

  // v2.19.25 学生 P1-1（半幅）：错题 → 套路卡回链。考点自由文本经
  // 关键词映射到卡 id（lib/data/big_question_cards.dart），命中才显示。
  // v2.19.58 抽出共用：判据搬到文件顶层 [linkedCardIdOf]（复习会话揭示区
  // 与收口屏「还需复习」也要判同一条），这里只留一行转发。
  String? get _linkedCardId => linkedCardIdOf(entry);

  /// 这道题考哪条课标的**可点**徽章：跳课标页并高亮那一条。判不出来
  /// （返回 null）时**一个像素都不加**。
  ///
  /// ## 判据链（三步，任一步空就到此为止）
  ///
  ///  1. `srcModule` 为空（老条目）⇒ null，**不给徽章**。
  ///  2. `curriculumReverseCodeOf(srcModule)`——**唯一命中才返回**，多义
  ///     时它自己返 null ⇒ 这里不给徽章。
  ///  3. `reverseAnchorOf(code)` 拿到徽章本体，`curriculumReverseBadge`
  ///     渲染。同一 code 多枚锚点时**取第一枚就够**（拿的是那一枚都一样）：
  ///     跳的是课标页并高亮那条**条目**，与落到哪一枚锚点无关。
  ///
  /// ## ⛔ 为什么第 2 步多义就宁可不给
  ///
  /// 错题本**不记页签**——`molecular` 一枚 moduleId 对**五条** code
  /// （3.1.1 / 3.1.2 / 3.1.3 / 3.1.4 / 3.2.1），而「分子页第 0 个页签」和
  /// 「第 3 个页签」在错题本里长得一模一样。据此替学生挑一条（哪怕挑最热的
  /// 3.2.1）就是**凭空编造**对应关系，而且编出来的东西**屏上完全看不出来**：
  /// 徽章照样可点、照样跳得过去，只是落到了另一条正文上。与「一枚徽章印两个
  /// code ⇒ 不挂」是同一口径：**宁可不给，也不给错**。
  ///
  /// ## ⛔ 为什么是「接」而不是「新造」
  ///
  /// `curriculumReverseBadge` 是 `curriculum_page.dart` 里那一份（同一个
  /// 「可点 + Tooltip + 水波 + 跳课标页并高亮」的机制，零像素变化）。换一套
  /// 写法就会有两套跳转，两套以后必然分叉。故本方法**只负责判据**，像素全部
  /// 来自那份现成的。
  Widget? _curriculumReverseBadge(BuildContext context) {
    final moduleId = entry.srcModule;
    if (moduleId == null) return null;
    final code = curriculumReverseCodeOf(moduleId);
    if (code == null) return null;
    final anchor = reverseAnchorOf(code);
    // ⛔ 这一支实际不可达（`code` 本身就取自锚点表，表里的 code 一定在表里），
    // 写成 null 而不是 `!`：多义反查被改成「取第一条」的那天，最坏结果是
    // 「徽章悄悄不显示了」，而不是整张卡片卡在 TypeError 上打不开。
    if (anchor == null) return null;
    return curriculumReverseBadge(context, anchor);
  }

  /// 「回来源工具重算」那一行（按钮 + 可选的课标徽章）。无来源时返回空表
  /// ⇒ 调用方一个像素都不加。
  ///
  /// ⛔ 这一行**必须换 `Wrap`**：实测重算按钮渲染宽约 290px，而 360 宽下
  /// 卡片可用宽 332px ⇒ 再加一枚约 90px 的徽章必然溢出。`Wrap` 允许窄屏折行，
  /// 宽屏下两者仍并排（`Wrap` 不加 `direction` 时就是横排）。
  /// ⛔ **绝不许**把徽章塞进 [_buildActions]——那是 4 枚按钮的主操作行，
  /// 窄屏刚折行收口过，再加会重新挤爆。
  List<Widget> _refillRow(BuildContext context) {
    // 徽章判不出来（老条目 / `molecular` 多义 / 未注册 moduleId）时是 null
    // ⇒ 这一行只剩重算按钮，与本轮之前逐像素一致。
    final badge = _curriculumReverseBadge(context);
    return [
      Wrap(
        // `Wrap` 的对齐默认是 `start`，与复习会话那枚 `Align(centerLeft)`
        // 在这一行只放得下一个子控件时视觉一致；显式写出来是为了万一这行
        // 折成两行，第二行不会飘到中间去。
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 8,
        runSpacing: 4,
        children: [
          OutlinedButton.icon(
            key: kListRefillButtonKey,
            onPressed: () => goRecomputeInMistakeSource(context, entry),
            icon: const Icon(Icons.calculate_outlined, size: 16),
            // ⚠️ 这里写 `entry.srcModule ?? ''` 而不是 `!`：渲染这一行与
            // srcModule 非空是两个事实，上面的 [mistakeEntryHasSource] 已把
            // 后者钉住；万一那条被改松，代价也只是「老条目多个按钮」，而不是
            // `!` 抛 TypeError 把整棵卡片打崩。
            //
            // ⚠️ 文案与复习会话那枚**同口径但不同字**：都点名目标页（禁方向
            // 词、禁 markdown 星号），但列表这枚少了「这道题」三个字。原因：
            // 复习会话是盖在列表之上的对话框，被盖住的列表卡片仍在树里（非
            // offstage）⇒ 两处若逐字相同，任何按这句话 `tap` 的守卫会命中两枚。
            label: Text('去「${mistakeSourceToolName(entry.srcModule ?? '')}」重算'),
          ),
          if (badge != null) badge,
        ],
      ),
      const SizedBox(height: 8),
    ];
  }

  Widget _buildActions(BuildContext context) {
    // v2.19.26（学生 P2-4 / 老师 P2-3 / 老用户 ②）：动作行改 Wrap——
    // 390 窄屏下「AI 整理 + 重新作答 + 看套路卡 + 更多」四项同现
    // 约超 15-45px，会裁掉最右「更多」（编辑/删除入口）。与套路卡
    // 页三按钮行同型事故的同款修法。
    return Wrap(
      spacing: 4,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        TextButton.icon(
          onPressed: onAiTap,
          icon: const Icon(Icons.auto_awesome_outlined, size: 16),
          label: Text(entry.aiSummary == null ? 'AI 整理' : '重新整理'),
          style: TextButton.styleFrom(
            foregroundColor: AppColors.teal,
            minimumSize: const Size(0, 36),
            padding: const EdgeInsets.symmetric(horizontal: 8),
          ),
        ),
        // v2.13 学生走查 P0：「重新作答」提到主操作行（RedFox 洞察「回到
        // 笔尖」是错题本 90% 价值，之前藏二级菜单 = 自我阉割）。只对
        // 已有答案的条目显示（无答案时「重新作答」= 编辑，语义重复）。
        if (entry.userAnswer.isNotEmpty)
          TextButton.icon(
            onPressed: () {
              MistakeBook.instance.update(
                  entry.id,
                  (cur) => cur.copyWith(
                      userAnswer: '',
                      reviewStatus: MistakeReviewStatus.reviewing));
              onTap();
            },
            icon: const Icon(Icons.edit_note_outlined, size: 16),
            label: const Text('重新作答'),
            style: TextButton.styleFrom(
              foregroundColor: AppColors.graphite,
              minimumSize: const Size(0, 36),
              padding: const EdgeInsets.symmetric(horizontal: 8),
            ),
          ),
        if (_linkedCardId != null)
          TextButton.icon(
            onPressed: () {
              Navigator.of(context).push(MaterialPageRoute<void>(
                builder: (_) =>
                    BigQuestionCardsPage(initialCardId: _linkedCardId),
              ));
            },
            icon: const Icon(Icons.style_outlined, size: 16),
            label: const Text('看套路卡'),
            style: TextButton.styleFrom(
              foregroundColor: AppColors.teal,
              minimumSize: const Size(0, 36),
              padding: const EdgeInsets.symmetric(horizontal: 8),
            ),
          ),
        TextButton(
          onPressed: () => _showMenu(context),
          child: const Text('更多'),
        ),
      ],
    );
  }

  void _showMenu(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('编辑'),
              onTap: () {
                Navigator.of(ctx).pop();
                onTap();
              },
            ),
            // v2.13 RedFox 真实用户洞察：「错题如果不回到笔尖，就只是
            // 看过」——潇洒错题本实证"重练/重做"是坚持闭环的关键。
            // 一键清空我的答案 + 复习态归零 + 打开编辑表单自测。
            ListTile(
              leading: const Icon(Icons.edit_note_outlined),
              title: const Text('重新作答（自测）'),
              subtitle: const Text('清空「我的答案」并打开编辑——遮住正确答案回笔尖重写一遍'),
              onTap: () {
                Navigator.of(ctx).pop();
                MistakeBook.instance.update(
                    entry.id,
                    (cur) => cur.copyWith(
                        userAnswer: '',
                        reviewStatus: MistakeReviewStatus.reviewing));
                onTap();
              },
            ),
            // v2.13 学生走查：追问路径——存错题→看 AI 整理→追问此前
            // 要切走全局侧栏；现在一键带上下文（题目+双答案+归类）发问。
            ListTile(
              leading: const Icon(Icons.psychology_outlined),
              title: const Text('问 AI（关于此题）'),
              subtitle: const Text('AI 已带上题目与答案上下文，直接追问'),
              onTap: () {
                Navigator.of(ctx).pop();
                // v2.13+ 学生走查 P1：queueSend 前先清一次性画布截图，
                // 否则 AI 看到的是上一道题的截图（pendingCanvasImage
                // 一次性消费，A→B 连点时对不上）。
                AiChatController.instance.pendingCanvasImage = null;
                final sb = StringBuffer()
                  ..writeln('【错题追问】请围绕这道错题给我讲解：')
                  ..writeln('题目：${entry.stem}')
                  ..writeln('我的答案：${entry.userAnswer.isEmpty ? "（未作答）" : entry.userAnswer}')
                  ..writeln('正确答案：${entry.correctAnswer}');
                if (entry.aiSummary != null && entry.aiSummary!.isNotEmpty) {
                  sb.writeln('AI 已归类错因：${entry.aiSummary}');
                }
                AiChatController.instance.queueSend(sb.toString());
                showAiAssistant(context);
              },
            ),
            ListTile(
              leading: Icon(Icons.delete_outline, color: AppColors.lethal),
              title: Text('删除', style: TextStyle(color: AppColors.lethal)),
              onTap: () {
                Navigator.of(ctx).pop();
                final state = context.findAncestorStateOfType<_MistakeBookPageState>();
                state?._handleDelete(entry);
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  String _formatTime(DateTime t) {
    final now = DateTime.now();
    final diff = now.difference(t);
    if (diff.inDays >= 1) return '${diff.inDays} 天前';
    if (diff.inHours >= 1) return '${diff.inHours} 小时前';
    if (diff.inMinutes >= 1) return '${diff.inMinutes} 分钟前';
    return '刚刚';
  }
}

class _ErrorTypeChip extends StatelessWidget {
  final MistakeErrorType type;

  /// v2.13 R3 P1-B4：selected = 该类型正是当前筛选（顶部 FilterChip
  /// 选中态一致，让用户在卡片上也看到"正在看哪类"）。
  final bool selected;

  /// v2.13 R3 P1-B4：点击回调（父层传入筛选切换）。
  final VoidCallback? onTap;

  const _ErrorTypeChip({
    required this.type,
    this.selected = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return FilterChip(
      label: Text(type.displayName, style: AppText.caption),
      selected: selected,
      showCheckmark: false,
      onSelected: onTap == null ? null : (_) => onTap!(),
      backgroundColor: AppColors.surface,
      selectedColor: AppColors.tealWash,
      side: BorderSide(
          color: selected ? AppColors.teal : AppColors.border),
      labelStyle: AppText.caption.copyWith(
          color: selected ? AppColors.teal : null),
    );
  }
}

class _ReviewStatusChip extends StatelessWidget {
  final MistakeReviewStatus status;
  final ValueChanged<MistakeReviewStatus> onChanged;
  const _ReviewStatusChip({required this.status, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<MistakeReviewStatus>(
      tooltip: '点击切换复习状态',
      onSelected: onChanged,
      itemBuilder: (_) => [
        for (final s in MistakeReviewStatus.values)
          PopupMenuItem(
            value: s,
            child: Row(
              children: [
                if (s == status)
                  Icon(Icons.check, size: 16, color: AppColors.teal)
                else
                  const SizedBox(width: 16),
                const SizedBox(width: 8),
                Text(s.displayName),
              ],
            ),
          ),
      ],
      child: Chip(
        label: Text(status.displayName, style: AppText.caption),
        avatar: Icon(
          status == MistakeReviewStatus.mastered
              ? Icons.check_circle_outline
              : status == MistakeReviewStatus.reviewing
                  ? Icons.refresh
                  : Icons.radio_button_unchecked,
          size: 14,
          color: status == MistakeReviewStatus.mastered
              ? AppColors.teal
              : AppColors.steel,
        ),
        backgroundColor: status == MistakeReviewStatus.mastered
            ? AppColors.tealWash
            : AppColors.surface,
        side: BorderSide(color: AppColors.border),
      ),
    );
  }
}

// ============================================================================
// 表单对话框（添加 / 编辑共用）
// ============================================================================

class _MistakeFormResult {
  final String stem;
  final String userAnswer;
  final String correctAnswer;
  final MistakeErrorType errorType;
  final String subjectArea;
  const _MistakeFormResult({
    required this.stem,
    required this.userAnswer,
    required this.correctAnswer,
    required this.errorType,
    required this.subjectArea,
  });
}

class _MistakeFormDialog extends StatefulWidget {
  final MistakeEntry? initial;
  const _MistakeFormDialog({this.initial});
  @override
  State<_MistakeFormDialog> createState() => _MistakeFormDialogState();
}

class _MistakeFormDialogState extends State<_MistakeFormDialog> {
  late final TextEditingController _stem;
  late final TextEditingController _userAnswer;
  late final TextEditingController _correctAnswer;
  late final TextEditingController _subjectArea;
  late MistakeErrorType _errorType;
  String? _stemError;

  /// 拍照识别进行中（按钮 loading 且禁用，防重复点击）。
  bool _recognizing = false;

  @override
  void initState() {
    super.initState();
    final e = widget.initial;
    _stem = TextEditingController(text: e?.stem ?? '');
    _userAnswer = TextEditingController(text: e?.userAnswer ?? '');
    _correctAnswer = TextEditingController(text: e?.correctAnswer ?? '');
    _subjectArea = TextEditingController(text: e?.subjectArea ?? '');
    _errorType = e?.errorType ?? MistakeErrorType.concept;
  }

  @override
  void dispose() {
    _stem.dispose();
    _userAnswer.dispose();
    _correctAnswer.dispose();
    _subjectArea.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.initial == null ? '添加错题' : '编辑错题'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 拍照上传：选图 → AI 识别 → 回填四字段（用户核对后手动保存）。
            OutlinedButton.icon(
              onPressed: _recognizing ? null : _pickAndRecognize,
              icon: _recognizing
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.camera_alt_outlined),
              label: Text(_recognizing ? '识别中…' : '拍照上传'),
            ),
            const SizedBox(height: 6),
            Text('识别结果请核对后再保存', style: AppText.label),
            const SizedBox(height: 12),
            TextField(
              controller: _stem,
              decoration: InputDecoration(
                labelText: '题目摘要 *',
                hintText: '如 "9331 变式：AaBb 自交 F2 比例"',
                errorText: _stemError,
              ),
              maxLines: 3,
              minLines: 2,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _userAnswer,
              decoration: const InputDecoration(
                labelText: '错误答案',
                hintText: '如 "9:3:4"',
              ),
              maxLines: 1,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _correctAnswer,
              decoration: const InputDecoration(
                labelText: '正确答案',
                hintText: '如 "9:3:3:1"',
              ),
              maxLines: 1,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _subjectArea,
              decoration: const InputDecoration(
                labelText: '关联考点',
                hintText: '如 "9331 变式 / 系谱推断"（可选）',
              ),
              maxLines: 1,
            ),
            const SizedBox(height: 14),
            Text('错误类型', style: AppText.label),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final t in MistakeErrorType.values)
                  ChoiceChip(
                    label: Text(t.displayName),
                    selected: _errorType == t,
                    onSelected: (_) => setState(() => _errorType = t),
                  ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: _submit,
          child: Text(widget.initial == null ? '添加' : '保存'),
        ),
      ],
    );
  }

  /// 拍照上传：选图 → AI 识别 → 回填四字段。
  ///
  /// - 用户取消选图：静默返回，不报错。
  /// - 识别不出的字段（空字符串）保留用户已有输入，不覆盖。
  /// - 不自动提交：回填后由用户核对，点「添加/保存」走 [_submit]。
  Future<void> _pickAndRecognize() async {
    setState(() => _recognizing = true);
    try {
      final img = await (MistakeBookPage.debugPicker ?? pickImageFile)();
      if (img == null) return; // 用户取消：静默返回
      final (analysis, error) = await MistakeBookAi.analyzePhoto(img);
      if (!mounted) return;
      if (analysis == null) {
        _showSnack(error ?? '识别失败，请重试',
            duration: const Duration(seconds: 5));
        return;
      }
      setState(() {
        // 空字段 = AI 识别不出 ⇒ 保留用户已有输入，不覆盖。
        if (analysis.stem.isNotEmpty) _stem.text = analysis.stem;
        if (analysis.userAnswer.isNotEmpty) {
          _userAnswer.text = analysis.userAnswer;
        }
        if (analysis.correctAnswer.isNotEmpty) {
          _correctAnswer.text = analysis.correctAnswer;
        }
        if (analysis.subjectArea.isNotEmpty) {
          _subjectArea.text = analysis.subjectArea;
        }
      });
      _showSnack('已回填识别结果，请核对后再保存',
          duration: const Duration(seconds: 5));
    } catch (e) {
      // 兜底：任何意外都不抛未捕获异常，保住用户已填内容。
      _showSnack('识别失败：$e', duration: const Duration(seconds: 5));
    } finally {
      if (mounted) setState(() => _recognizing = false);
    }
  }

  /// 与页面 `_showSnack` 同款（对话框 State 够不着页面 State，就近一份）。
  void _showSnack(String msg, {Duration? duration}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        duration: duration ?? const Duration(seconds: 2),
      ),
    );
  }

  void _submit() {
    final stem = _stem.text.trim();
    if (stem.isEmpty) {
      setState(() => _stemError = '题目摘要是必填的');
      return;
    }
    Navigator.of(context).pop(_MistakeFormResult(
      stem: stem,
      userAnswer: _userAnswer.text.trim(),
      correctAnswer: _correctAnswer.text.trim(),
      errorType: _errorType,
      subjectArea: _subjectArea.text.trim(),
    ));
  }
}
// ─── v2.13+：今日复习自测会话 ─────────────────────────────────────
//
// 零插件间隔复习的作答面：逐题展示题干（答案遮罩），学生先回忆再对答，
// 自评「掌握了/还需复习」→ markStatus 落库（reviewedAt 刷新，
// dueEntries 的 1/3 天排期自动生效）。RedFox 洞察「节奏感 + 遮盖自测
// 是错题本最被低估的体验」的落地。

/// 逐题遮罩自测会话（全屏对话框）。
/// 复习会话里那枚「回来源工具重算」按钮的 key。
const Key kReviewRefillButtonKey = Key('mistake_review_refill_btn');

/// 错题本**列表卡片**上那枚同名按钮的 key。
///
/// ⛔ 必须与 [kReviewRefillButtonKey] 是**两个** key，不是同一个：复习
/// 会话是盖在列表之上的全屏对话框，底下的列表卡片仍留在树里（非
/// offstage）⇒ 共用一个 key 会让既有守卫的 `findsOneWidget` 当场变红，
/// 任何按它 `tap` 的守卫也会同时命中两枚。
const Key kListRefillButtonKey = Key('mistake_list_refill_btn');

/// 目标页**已注册**时的人话名字兜底表（未注册 / 已注销时查它）。
/// 目标已注册时一律用 `target.label`（单一事实源），本表不参与。
const Map<String, String> _kModuleNameFallback = {
  'cross_mono': '遗传计算器·单基因',
  'cross_dihybrid': '遗传计算器·双基因',
};

/// 这道题**记不记得**是从哪个工具存进来的？两个条件缺一不可。
///
/// ⛔ 老条目（来源字段上线之前写盘的）两个字段都是 null ⇒ 不渲染按钮。
/// 给它们渲染一枚「点下去必然 fill 返 false」的按钮，比没有按钮更糟：
/// 学生会以为是软件坏了。
///
/// **为什么是文件级顶层函数**（而不是 `_ReviewSessionState` 的私有方法）：
/// 「回来源工具重算」这一个动作有**两个**入口 —— 复习会话内的那枚
/// （`_ReviewSessionState`）与错题本**列表卡片**上那枚（`_MistakeCard`，
/// 两 widget 相距约 600 行）。私有方法两边都够不着：要么把 State 拆出来
/// （改面太大），要么在 `_MistakeCard` 里**重抄一遍**——那就是「覆盖了
/// 一半的守卫比没有更危险」的同一个坑：日后只改一处，两处悄悄分叉，没
/// 有守卫会发现。**只有一份实现**才有单一真相。
bool mistakeEntryHasSource(MistakeEntry e) =>
    e.srcModule != null && (e.srcParams?.isNotEmpty ?? false);

/// 这道题**有没有配套的套路卡**？考点自由文本经关键词映射到卡 id
/// （lib/data/big_question_cards.dart 的 `findCardIdForTopic`），命中才有。
/// 考点空 / 命不中关键词都返回 null ⇒ 调用方一个像素都不加。
///
/// **为什么是文件级顶层函数**（与 [mistakeEntryHasSource] 同一个理由）：
/// 「看套路卡」这一个跳转有**三个**入口 —— 错题本**列表卡片**
/// （`_MistakeCard`）、复习会话的揭示区、以及收口屏「还需复习」逐条。
/// 私有的 `_linkedCardId` getter 只有 `_MistakeCard` 够得着，另两处就得
/// 把这套条件**重抄一遍** —— 正是「改了一处、另一处悄悄分叉」的同一个
/// 坑。**只有一份判据**才有单一真相。
///
/// v2.19.25 起 `_MistakeCard._linkedCardId` 就是这套逻辑；v2.19.58 抽到
/// 这里共用，卡片那枚 getter 改为一行转发。
String? linkedCardIdOf(MistakeEntry entry) => entry.subjectArea.isEmpty
    ? null
    : findCardIdForTopic(entry.subjectArea);

/// 「那一页」的人话名字：目标已注册用它的 label，否则查兜底表。
String mistakeSourceToolName(String moduleId) =>
    ModuleFillBus.targetOf(moduleId)?.label ??
    _kModuleNameFallback[moduleId] ??
    moduleId;

/// 带着这道题回它的来源工具重算。
///
/// 解决的卡点：退避阶梯（3→7→14→30→60→120 天）到期时，学生原先**只有题干**——
/// 必须自己切回 9331、凭记忆把亲本重敲一遍才能重做。退避最该服务的
/// 「防遗忘」那一刻，恰好卡在最该动手重算的一步。
/// 而**发现该复习发生在列表、重算却只在复习会话里**，「发现」与「动手」
/// 中间断了一跳 ⇒ 本函数现在两个入口共用（复习会话 + 列表卡片）。
///
/// ⚠️ `fill` 的 `true` 有**两种**含义（已跳转 / 已投递），而 `apply` 是
/// post-frame 异步的、返回值在 `fill` 内部就被消费掉了 ⇒ 调用方**不可能**
/// 从返回值知道参数到底写没写进去。三种结局各说各的：
///   ① 真写进去了 → 本条给成功回执。
///   ② 被 `canOverwrite` 挡下（目标页里已有学生自己的题）→ 目标页的
///      `onApplyFailed` 会弹 SnackBar（13 个 target 全接上了）⇒
///      **本条一个字都不说**，否则就是双重提示。
///   ③ `fill` 返 false（模块没注册 / 跳不过去）→ **本条必须自己说一句**。
///      ⛔ 静默是明确禁止的。
///
/// ⚠️ [context] 由调用方传入，两个入口各有各的 context（复习会话的 State
/// context / 列表卡片的 context）。两者都在 MaterialApp 之下 ⇒
/// `ScaffoldMessenger.of` 取到的都是**同一个** MaterialApp 根 messenger
/// （它建在 Navigator **之上**）⇒ 结局 ①退栈之后回执仍然有人接。
void goRecomputeInMistakeSource(BuildContext context, MistakeEntry e) {
  final moduleId = e.srcModule;
  final params = e.srcParams;
  if (moduleId == null || params == null || params.isEmpty) return;
  final name = mistakeSourceToolName(moduleId);
  // MaterialApp 自己在 Navigator **之上**建了一个 ScaffoldMessenger，
  // 这里的弹窗取到的就是它 ⇒ 退栈之后回执仍然有人接。
  final messenger = ScaffoldMessenger.of(context);
  // 结局 ②的预判：读一次目标页的「我现在空不空」。
  // 与 `fill` 内部那次查询读的是同一个 canOverwrite、同一组 controller，
  // 切页不改它们 ⇒ 两次结论一致（如 cross_mono 的判据是两个亲本框的出厂态）。
  final target = ModuleFillBus.targetOf(moduleId);
  final can = target?.canOverwrite;
  final willSkipWrite = can != null && !can();
  // v2.19.37（独立验证者 P0 修复）：push 型目标（disease_risk /
  // pd_inference / cross_chromosomal_struct）**先退错题本层、再 fill**
  // ——push 出的目标页浮在根路由上自然可见，退栈与 push 不互相弹掉。
  // 若沿用「fill 后 popUntil(isFirst)」，刚 push 的页与错题本被一起弹回
  // 首页：深链失效 + sourceLabel/params 幽灵（见 curriculum_page 同款修复）。
  final isPushType = target?.pushFactory != null;
  if (isPushType) {
    Navigator.of(context).popUntil((r) => r.isFirst);
  }
  final ok = ModuleFillBus.fill(moduleId, Map<String, String>.from(params));
  if (!ok) {
    // 结局 ③：留在当前页不动路由，学生还能接着看/做这一题。
    // （push 型在此已退栈——fill 返 false 只在目标未注册时发生，
    // 退错了栈但不丢数据；名单见 srcModule 写入侧。）
    messenger.clearSnackBars();
    messenger.showSnackBar(SnackBar(
      content: Text('这道题记的是从「$name」来的，但那一页现在过不去，'
          '请手动切过去（本题已记在错题本里，不会丢）'),
      duration: const Duration(seconds: 5),
    ));
    return;
  }
  if (willSkipWrite) return; // 结局 ②：目标页自己会说，本条不重复。
  // 结局 ①：把人带回能看到目标页的地方。`fill` 只切 HomeShell 的
  // IndexedStack 索引，错题本是它上面 push 出来的一层路由，不退掉的
  // 话学生点了仍盯在错题本上，看起来就是「点了没反应」。已答过的题
  // reviewedAt 早已写盘，进度不丢。
  // ⚠️ 从列表卡片点进来时，退掉的是**错题本那一页**——同样是必需的：
  // 来源工具在 HomeShell 的 IndexedStack 上，不退这一层就看不到切换。
  // ⚠️ `popUntil` 返回 void（**不**是 Future），不能 await；退栈动画与下面
  // 这条回执并行，回执挂在 MaterialApp 根 messenger 上，动画期间就可见。
  // v2.19.37：push 型已在 fill 之前退过栈，这里只退 pageIndex 型。
  if (!isPushType) {
    Navigator.of(context).popUntil((r) => r.isFirst);
  }
  final p1 = params['p1'] ?? '';
  final p2 = params['p2'] ?? '';
  final detail = (p1.isNotEmpty && p2.isNotEmpty) ? '，亲本 $p1 × $p2 已填好' : '';
  messenger.clearSnackBars();
  messenger.showSnackBar(SnackBar(
    content: Text('已退出本轮复习（进度已保存）并切到「$name」$detail'),
    duration: const Duration(seconds: 5),
  ));
}

class _ReviewSession extends StatefulWidget {
  final List<MistakeEntry> entries;
  const _ReviewSession({required this.entries});

  @override
  State<_ReviewSession> createState() => _ReviewSessionState();
}

class _ReviewSessionState extends State<_ReviewSession> {
  var _index = 0;
  var _revealed = false;
  var _mastered = 0;
  var _stillLearning = 0;

  /// 收口屏「再练这 X 道」用的自有可变题库：开局从 [widget.entries] 拷一份，
  /// 学生点「再练」时被换成「还需复习」的那几道。`_cur` / done 判定 /
  /// `_answer` 越界检查**一律读它**，不再直接引用 `widget.entries`。
  late List<MistakeEntry> _entries = List.of(widget.entries);

  /// 本轮判「还需复习」的那几道（`_answer(true)` 不记）。收口屏据此逐条
  /// 列出，并把它们交给「再练这 X 道」。
  final List<MistakeEntry> _missed = [];

  MistakeEntry get _cur => _entries[_index];

  /// 这道题**记不记得**是从哪个工具存进来的？
  ///
  /// ⚠️ 一行转发，实现在文件顶层 [mistakeEntryHasSource]：列表卡片那边
  /// （`_MistakeCard`，约 600 行之外）也要判同一条规矩，两处各判一遍必然
  /// 分叉。**这里不许再写一遍条件。**
  bool _hasSource(MistakeEntry e) => mistakeEntryHasSource(e);

  /// 「那一页」的人话名字。一行转发，实现见 [mistakeSourceToolName]。
  String _sourceToolName(String moduleId) => mistakeSourceToolName(moduleId);

  /// 「去那一页重算」按钮 + 它下方的间距。
  ///
  /// ⚠️ 这里写 `e.srcModule ?? ''` 而不是 `!`：渲染这一行与 srcModule 非空
  /// 是**两个**事实，调用方已用 [_hasSource] 把后者钉住。但一旦那个条件
  /// 被后人改松（比如写成恒真），代价不该是**整屏白**（`!` 抛 TypeError →
  /// 整棵子树构建失败），而该是「老条目多一个按钮」——后者正正好好被守卫
  /// 第 4 条当场抓住，信号干净得多。
  List<Widget> _refillRow(MistakeEntry e) {
    final name = _sourceToolName(e.srcModule ?? '');
    return [
      Align(
        alignment: Alignment.centerLeft,
        child: OutlinedButton.icon(
          key: kReviewRefillButtonKey,
          onPressed: () => _goRecomputeInSource(e),
          icon: const Icon(Icons.calculate_outlined, size: 16),
          // 纪律 K：点名对象，不许「上面/下面」方向词，不许 markdown 星号。
          label: Text('去「$name」重算这道题'),
        ),
      ),
      const SizedBox(height: 12),
    ];
  }

  /// 带着这道题回它的来源工具重算。
  ///
  /// ⚠️ 一行转发，三种结局的实现全在顶层 [goRecomputeInMistakeSource]
  /// （连文案都搬过去了）。⛔ **这里一行实现都不许留**——列表卡片入口
  /// 与本入口共用那一份，留一份「复习侧专属」的副本就等于又埋了一个
  /// 「改了一处、另一处悄悄分叉」的雷。
  void _goRecomputeInSource(MistakeEntry e) =>
      goRecomputeInMistakeSource(context, e);

  /// v2.13+：复习会话内「问 AI 讲解此题」——带题目/双答案/AI 归类
  /// 上下文直发问（与错题卡更多菜单同款），AI 侧栏覆盖在会话上方
  /// （关闭后回会话继续）。
  void _askAiAboutCurrent() {
    final sb = StringBuffer()
      ..writeln('【错题追问·复习中】请围绕这道错题给我讲解：')
      ..writeln('题目：${_cur.stem}')
      // R5 老师+学生双走查：考点 + 易错点——AI 才能讲出「这题归在
      // 哪章」「这类题最容易错在哪」的针对性内容。
      ..writeln('考点：${_cur.subjectArea.isEmpty ? "（未标注）" : _cur.subjectArea}')
      ..writeln('我的答案：${_cur.userAnswer.isEmpty ? "（未作答）" : _cur.userAnswer}')
      ..writeln('正确答案：${_cur.correctAnswer}');
    if (_cur.aiSummary != null && _cur.aiSummary!.isNotEmpty) {
      sb.writeln('AI 已归类错因：${_cur.aiSummary}');
    }
    if (_cur.aiPitfalls.isNotEmpty) {
      sb.writeln('易错点：${_cur.aiPitfalls.join('；')}');
    }
    AiChatController.instance.pendingCanvasImage = null;
    AiChatController.instance.queueSend(sb.toString());
    showAiAssistant(context);
  }

  /// v2.19.65（创新提案 #2 首刀）：把当前 mono 错题的**变式**存进错题本。
  ///
  /// 一次点击只做**一件事**：入库 + 回执。变式由 [monoVariantOf] 确定性推出、
  /// 答案由引擎当场算（⛔ 不经 AI），存进去后走**既有**复习闭环——它和手存的
  /// 题一样进今晚待复习（⛔ 不自建队列 / 不另开复习面）。
  ///
  /// ⛔ 不 `queueSend`「把这道变式包装成文字应用题」：那是**第二件**事，会打断
  /// 学生「练一道」的轻量动作。AI 包装题面是 **v2 方向**，留给学生在 AI 面板
  /// 里自己问（本刀只把**可复习的题**递到他手里）。
  ///
  /// ⛔ 点击**不许静默**：两次出口（新存 / 已在）都给 SnackBar 回执。
  void _addVariantOfCurrent() {
    final v = monoVariantOf(_cur);
    // 按钮本就不渲染（渲染条件同此判据）；这里再兜一次，防后人把渲染条件改松
    // 后点出一枚「什么都不做」的键。
    if (v == null) return;
    final messenger = ScaffoldMessenger.of(context);
    final book = MistakeBook.instance;
    // 查重：`add` 本身**不去重**（去重在 `findSame` / `addOrFind`）⇒ 先按
    // 「题干 + 答案」查一遍，命中就只回执、不再存第二条（同题连点两次、或这
    // 道变式前几天已存过，都不会在库里留两份）。
    if (book.findSame(v.stem, v.answer) != null) {
      messenger.clearSnackBars();
      messenger.showSnackBar(const SnackBar(
        content: Text('这道变式已在错题本里'),
        duration: Duration(seconds: 3),
      ));
      return;
    }
    book.add(
      stem: v.stem,
      // 变式不是学生做错的题、没有「他当时写的」⇒ 空串（揭示区按「未作答」渲染，
      // 与手加表单允许答案为空的口径一致）。
      userAnswer: '',
      correctAnswer: v.answer,
      // 学生的错因是「比例算错」型 ⇒ 计算错（与 mono 面存题的错因同类）。
      errorType: MistakeErrorType.calculation,
      subjectArea: _cur.subjectArea,
      // 来源 + 参数照 mono 存题口径：只用 p1 / p2 两字母基因型（同
      // `mono_cross_widget.dart` 的 `_monoSrcParams`）⇒ 复习时能一键回计算器
      // 重算这道变式。
      srcModule: kMonoVariantSrcModule,
      srcParams: {'p1': v.parent1, 'p2': v.parent2},
    );
    messenger.clearSnackBars();
    messenger.showSnackBar(const SnackBar(
      content: Text('变式已加入错题本，今晚复习见'),
      duration: Duration(seconds: 3),
    ));
  }

  void _answer(bool mastered) {
    MistakeBook.instance.markStatus(
      _cur.id,
      mastered
          ? MistakeReviewStatus.mastered
          : MistakeReviewStatus.reviewing,
    );
    // v2.13+ 学生走查 P0：「还需复习」= 今晚还想再试——reviewedAt 置空
    // （dueEntries 规则：reviewing + reviewedAt 空 → 立即到期），
    // 否则被锁到明天（markStatus 默认写 now）。
    // R5 修订：此前 copyWith(reviewedAt: null) 被 ?? 吞掉是死代码，
    // copyWith 加了显式 clearReviewedAt 开关后才真正生效。
    if (!mastered) {
      MistakeBook.instance
          .update(_cur.id, (cur) => cur.copyWith(clearReviewedAt: true));
    }
    if (mastered) {
      _mastered++;
    } else {
      _stillLearning++;
      // v2.19.58：判「还需复习」的题留档，收口屏逐条列出 + 「再练这 X 道」。
      _missed.add(_cur);
    }
    if (_index + 1 >= _entries.length) {
      setState(() => _index++);
      return;
    }
    setState(() {
      _index++;
      _revealed = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final done = _index >= _entries.length;
    return CallbackShortcuts(
      bindings: {
        // v2.19.11 学生走查 #12：复习中 Esc = 退出（此前 barrier 锁死
        // 只能点「退出」或 Alt+F4）。已答题目的 reviewedAt 已即时写盘，
        // 中途退出进度不丢。
        const SingleActivator(LogicalKeyboardKey.escape): () =>
            // 返回当前题号（done 时 _index = length，打开方据此判断
            // 是否弹「进度已保存」提示）。
            Navigator.of(context).maybePop(_index),
        // v2.19.13 学生找茬轮 P2：数字键免鼠标——1 = 显示答案 / 已
        // 揭示时 = 掌握了；2 = 还需复习；3 = 问 AI。复习对话框打开时
        // 焦点在其内，不与 HomeShell 的 Ctrl+数字页导航冲突（那要 Ctrl）。
        const SingleActivator(LogicalKeyboardKey.digit1): () {
          if (_index >= _entries.length) return;
          if (!_revealed) {
            setState(() => _revealed = true);
          } else {
            _answer(true);
          }
        },
        const SingleActivator(LogicalKeyboardKey.digit2): () {
          if (_index >= _entries.length) return;
          if (_revealed) _answer(false);
        },
        const SingleActivator(LogicalKeyboardKey.digit3): () {
          if (_index >= _entries.length) return;
          if (_revealed) _askAiAboutCurrent();
        },
        // v2.19.58：K = 看这道题的套路卡。判据与揭示区那枚按钮**同一个**
        // [linkedCardIdOf]、跳转同一条路径。未揭示 / 没有配套卡时什么都不做
        // （越界守卫与其它数字键同款）。
        const SingleActivator(LogicalKeyboardKey.keyK): () {
          if (_index >= _entries.length) return;
          if (!_revealed) return;
          final id = linkedCardIdOf(_cur);
          if (id == null) return;
          Navigator.of(context).push(MaterialPageRoute<void>(
            builder: (_) => BigQuestionCardsPage(initialCardId: id),
          ));
        },
      },
      child: Focus(
        autofocus: true,
        child: Dialog.fullscreen(
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: done ? _doneView() : _questionView(),
            ),
          ),
        ),
      ),
    );
  }

  Widget _questionView() {
    final total = _entries.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('第 ${_index + 1} / $total 道',
                style: AppText.label.copyWith(color: AppColors.teal)),
            const Spacer(),
            TextButton.icon(
              // v2.19.13：同 Esc——返回题号供打开方弹进度提示。
              onPressed: () => Navigator.of(context).pop(_index),
              icon: const Icon(Icons.close, size: 16),
              label: const Text('退出'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Expanded(
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_cur.stem, style: AppText.body),
                const SizedBox(height: 16),
                // 只在**有来源**时渲染。⛔ 位置放在「遮罩提示」之前——学生正要
                // 「先遮住答案在纸上算」，这一步就该把亲本递到手边，而不是等他
                // 点开答案才发现要换页。
                if (_hasSource(_cur)) ..._refillRow(_cur),
                if (!_revealed) ...[
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceLow,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Text('先遮住答案，在纸上写出你的解答…\n'
                        '写好点下方「显示答案」对照'),
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: () => setState(() => _revealed = true),
                    icon: const Icon(Icons.visibility_outlined, size: 18),
                    label: const Text('显示答案（1）'),
                  ),
                ] else ...[
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.tealWash,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                          color: AppColors.teal.withValues(alpha: 0.4)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('正确答案',
                            style: AppText.caption
                                .copyWith(color: AppColors.teal)),
                        const SizedBox(height: 4),
                        Text(_cur.correctAnswer.isEmpty
                            // R5 学生走查：手加表单允许答案为空——揭示区
                            // 一片空白学生以为软件坏了；与卡片层「待补充」
                            // 口径一致。
                            ? '（待补充——退出后在错题卡片上补全答案）'
                            : _cur.correctAnswer, style: AppText.body),
                        // v2.13+ 学生走查 P1：当时作答对比（答错想回忆
                        // 自己错在哪时找不到对照）。
                        const SizedBox(height: 6),
                        Text(
                          '你当时写：${_cur.userAnswer.isEmpty ? "（未作答）" : _cur.userAnswer}',
                          style: AppText.caption
                              .copyWith(color: AppColors.steel),
                        ),
                        if (_cur.aiSummary != null &&
                            _cur.aiSummary!.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Text('错因：${_cur.aiSummary}',
                              style: AppText.caption
                                  .copyWith(color: AppColors.graphite)),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  // v2.13+ 学生走查 P0：「再看看」回退——手滑/想再想想
                  // 不致于一锤定音写库过题。
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: () => setState(() => _revealed = false),
                      icon: const Icon(Icons.undo, size: 16),
                      label: const Text('再看看（不记结果）'),
                    ),
                  ),
                  // v2.13+：复习中遇到仍不懂的题 → 带上下文直接问 AI
                  // （与错题卡「问 AI（关于此题）」同款链路，不中断复习流）。
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: _askAiAboutCurrent,
                      icon: const Icon(Icons.psychology_outlined, size: 16),
                      label: const Text('问 AI 讲解此题（3）'),
                    ),
                  ),
                  // v2.19.58：这道题若有配套套路卡，揭示后在此直达那张卡。
                  // 判据与列表卡片同源（[linkedCardIdOf]），命中才渲染；
                  // 文案点名对象（禁方向词、禁 markdown 星号）。
                  if (linkedCardIdOf(_cur) != null)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed: () {
                          final id = linkedCardIdOf(_cur);
                          if (id == null) return;
                          Navigator.of(context).push(MaterialPageRoute<void>(
                            builder: (_) =>
                                BigQuestionCardsPage(initialCardId: id),
                          ));
                        },
                        icon: const Icon(Icons.style_outlined, size: 16),
                        label: const Text('看这道题的套路卡（K）'),
                      ),
                    ),
                  // v2.19.65：mono 错题揭示后给一枚「练道变式」——点一下把这
                  // 道题的变式存进错题本（答案引擎当场算），今晚复习自动带上。
                  // 判据 [monoVariantOf]：非 cross_mono / 参数非法 ⇒ 不渲染（一格
                  // 像素都不加）。文案点名对象（禁方向词、禁 markdown 星号）。
                  if (monoVariantOf(_cur) != null)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed: _addVariantOfCurrent,
                        icon: const Icon(Icons.auto_awesome_outlined, size: 16),
                        label: const Text('练道变式'),
                      ),
                    ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: () => _answer(true),
                          icon: const Icon(Icons.check_circle_outline,
                              size: 18),
                          label: const Text('掌握了（1）'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => _answer(false),
                          icon: const Icon(Icons.refresh, size: 18),
                          label: const Text('还需复习（2）'),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// 收口屏「还需复习」里的一行：题干（最多两行）+ 有配套卡时一枚
  /// 「看套路卡」。判据与列表卡片、揭示区**同源**（[linkedCardIdOf]），
  /// 没有卡的题只印题干、不给按钮。
  Widget _missedRow(MistakeEntry e) {
    final id = linkedCardIdOf(e);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(
              e.stem,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: AppText.body,
            ),
          ),
        ),
        if (id != null)
          TextButton(
            onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
              builder: (_) => BigQuestionCardsPage(initialCardId: id),
            )),
            child: const Text('看套路卡'),
          ),
      ],
    );
  }

  Widget _doneView() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Icon(Icons.task_alt, size: 48, color: AppColors.teal),
        const SizedBox(height: 12),
        Text('本轮复习完成', style: AppText.sectionTitle),
        const SizedBox(height: 8),
        // R5 修订：与真实排期口径一致——「还需复习」= reviewedAt 置空
        // = 今晚仍到期（原写「明天会再次出现」与代码自相矛盾）；
        // 「已掌握」按 masteredStreak 退避 3→7→14→30→60→120 天。
        Text('掌握 $_mastered 道 · 还需复习 $_stillLearning 道\n'
            '「还需复习」的题今晚仍留在待复习里，随时可再来一轮；\n'
            '「已掌握」的题复习间隔会逐步拉长（3→7→14→30→60→120 天）'),
        // v2.19.58：把判「还需复习」的那几道**逐条列出来**——原来收口屏
        // 只说「N 道」，学生想知道错在哪几道还得退回列表自己找。有配套
        // 卡的行顺带一枚「看套路卡」；全部掌握（_missed 空）时这一段
        // **一个像素都不加**，原收口屏逐像素不变。
        if (_missed.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text('这几道还需复习',
              style: AppText.label.copyWith(color: AppColors.graphite)),
          const SizedBox(height: 8),
          // 最多占屏高 40%：收口屏本身不滚动，题多时让这一段自己滚，
          // 不把「完成」按钮顶出屏外。
          ConstrainedBox(
            constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.4),
            child: ListView(
              shrinkWrap: true,
              children: [
                for (var i = 0; i < _missed.length; i++) ...[
                  if (i > 0) const Divider(height: 1),
                  _missedRow(_missed[i]),
                ],
              ],
            ),
          ),
          const SizedBox(height: 12),
          // 创新：不必退回列表重开一轮——直接拿刚才那几道再练一遍。
          OutlinedButton.icon(
            onPressed: () {
              if (_missed.isEmpty) return;
              setState(() {
                _entries = List.of(_missed);
                _missed.clear();
                _mastered = 0;
                _stillLearning = 0;
                _index = 0;
                _revealed = false;
              });
            },
            icon: const Icon(Icons.replay, size: 18),
            label: Text('再练这 ${_missed.length} 道'),
          ),
        ],
        const SizedBox(height: 16),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('完成'),
        ),
      ],
    );
  }
}

// ─── v2.13+：自练卷导出选项对话框 ────────────────────────────────
/// 范围（全部 / 仅待复习）+ 分组（单文件 / 按错因 / 按考点多份）。
/// 学生走查 P1：50 题一次导出 = 打印噩梦，导出前给选项。
class _SelfPracticeOptionsDialog extends StatefulWidget {
  const _SelfPracticeOptionsDialog();

  @override
  State<_SelfPracticeOptionsDialog> createState() =>
      _SelfPracticeOptionsDialogState();
}

class _SelfPracticeOptionsDialogState
    extends State<_SelfPracticeOptionsDialog> {
  bool _dueOnly = false;
  int _groupBy = 0; // 0 单文件 / 1 按错因 / 2 按考点

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('导出自练卷'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('范围', style: AppText.label),
          const SizedBox(height: 4),
          Wrap(spacing: 8, children: [
            ChoiceChip(
              label: const Text('全部错题'),
              selected: !_dueOnly,
              onSelected: (_) => setState(() => _dueOnly = false),
            ),
            ChoiceChip(
              label: const Text('仅待复习'),
              selected: _dueOnly,
              onSelected: (_) => setState(() => _dueOnly = true),
            ),
          ]),
          const SizedBox(height: 10),
          Text('分组', style: AppText.label),
          const SizedBox(height: 4),
          Wrap(spacing: 8, runSpacing: 4, children: [
            for (final (i, label)
                in const [(0, '单一文件'), (1, '按错因分组'), (2, '按考点分组')])
              ChoiceChip(
                label: Text(label),
                selected: _groupBy == i,
                onSelected: (_) => setState(() => _groupBy = i),
              ),
          ]),
          const SizedBox(height: 8),
          Text('分组模式每个分组导出一个文件（如「自练卷_概念错_…md」），打印更友好。',
              style: AppText.caption.copyWith(color: AppColors.steel)),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context)
              .pop((dueOnly: _dueOnly, groupBy: _groupBy)),
          child: const Text('导出'),
        ),
      ],
    );
  }
}
