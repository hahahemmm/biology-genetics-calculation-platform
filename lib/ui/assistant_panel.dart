// assistant_panel.dart —— 全局 AI 助手侧栏（R22：会话全局化）
//
// 设计依据 docs/ARCHITECTURE.md 的设计约定 + R22 反馈：
//  - 右侧滑入面板（宽 380px），弹簧曲线入场
//  - 会话由 AiChatController 全局持有：关闭面板不打断请求，重开面板
//    继续看到进行中状态与完整结果；只有「打断」按钮能中止
//  - 顶部「上下文 chip」显性展示 AI 当前看到的系统状态
//  - 回复中基因型/比例用等宽字体渲染；assistant 消息附带的思维链
//    （reasoning）v2.12.0+2 hotfix 后**默认展开**（v2.12 老师 + 学生
//    persona UX 共识：学生需要看到解题过程、老师需要看到 AI 推理路径），
//    用户可在标题右侧勾选「下次不展开」关掉，偏好持久化到 AppState。
//    AI 输出内容始终直接展开。

import 'package:flutter/material.dart';

import '../state/scan_bank_store.dart';
import '../state/app_state.dart';
import '../theme.dart';
import 'ai_chat_controller.dart';
import 'module_fill.dart';
import 'scan_upload_dialog.dart';

/// 打开全局 AI 助手侧栏。任何页面均可调用。
Future<void> showAiAssistant(BuildContext context) async {
  // 页面自行注入的局部高清截图（如系谱 ROI）优先；否则截当前内容区。
  final controller = AiChatController.instance;
  controller.pendingCanvasImage ??= await captureAppCanvas();
  if (!context.mounted) {
    controller.pendingCanvasImage = null;
    return;
  }
  try {
    await showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: '关闭 AI 助手',
      barrierColor: Colors.black.withValues(alpha: 0.28),
      transitionDuration: const Duration(milliseconds: 300),
      // 严禁 const：面板文字用 AppColors 显式 style，const 实例会被 canonicalize
      // 导致主题切换后永不 rebuild，深色 token 文字在浅色模式下变成白底白字。
      pageBuilder: (ctx, anim, secondary) => _AssistantPanel(),
      transitionBuilder: (ctx, anim, secondary, child) {
        final curved =
            CurvedAnimation(parent: anim, curve: Curves.easeOutCubic);
        return Align(
          alignment: Alignment.centerRight,
          child: SlideTransition(
            position: Tween(begin: const Offset(1, 0), end: Offset.zero)
                .animate(curved),
            child: child,
          ),
        );
      },
    );
  } finally {
    // 截图只服务于本次打开：已发送时 send() 已清空；未发送也不能
    // 留到另一页复用。下次打开会重新截当前页，避免图文串页。
    controller.pendingCanvasImage = null;
  }
}

class _AssistantPanel extends StatefulWidget {
  const _AssistantPanel();

  @override
  State<_AssistantPanel> createState() => _AssistantPanelState();
}

class _AssistantPanelState extends State<_AssistantPanel>
    with SingleTickerProviderStateMixin {
  final _inputCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  bool _contextExpanded = false;

  AiChatController get _ctrl => AiChatController.instance;

  late final AnimationController _breath = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2400),
  )..repeat(reverse: true);

  @override
  void initState() {
    super.initState();
    _ctrl.loadHistory();
    // 初始建议（本地题库抽 3 条；AI 刷新会覆盖）
    if (_ctrl.suggestions.isEmpty) _ctrl.localRefresh();
    _ctrl.addListener(_onCtrlChanged);
  }

  @override
  void dispose() {
    // R22：面板销毁 ≠ 打断请求——只摘监听，请求继续在全局会话跑
    _ctrl.removeListener(_onCtrlChanged);
    _inputCtrl.dispose();
    _scrollCtrl.dispose();
    _breath.dispose();
    super.dispose();
  }

  void _onCtrlChanged() {
    if (mounted) setState(() {});
    _scrollToEnd();
  }

  bool get _busy => _ctrl.busy || _ctrl.refreshing;

  void _send() {
    final q = _inputCtrl.text.trim();
    if (q.isEmpty || _busy) return;
    _inputCtrl.clear();
    _ctrl.send(q);
  }

  /// v2.13 学生走查 P2：空态示例问题直达——学生不知道「能问什么」，
  /// 点示例 chip 即发问。
  void _ask(String q) {
    if (_busy) return;
    _inputCtrl.text = q;
    _send();
  }

  Future<void> _clearHistory() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('清空聊天记录？'),
        content: const Text('将删除本机保存的全部 AI 对话历史，不可恢复。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('清空'),
          ),
        ],
      ),
    );
    if (ok == true && mounted) {
      // v2.19.57：clearHistory 现在 await 落盘——失败（磁盘/加密异常）
      // 要弹条让用户知道「清空没存住」，不能静默吞。
      try {
        await _ctrl.clearHistory();
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('清空失败：历史未能持久化（$e）')),
          );
        }
      }
    }
  }

  void _localRefresh() => _ctrl.localRefresh();

  void _aiRefresh() {
    if (_ctrl.refreshing) return;
    _ctrl.refreshSuggestions();
  }

  /// 内置题库：识别成功的题目自动入库，这里查看/回填/删除。
  Future<void> _showBank() async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => _ScanBankDialog(parentContext: context),
    );
  }

  void _fillFromScan(ScanResult scan) {
    final ok = ModuleFillBus.fillScan(scan.module, scan.params, scan.actions);
    if (ok) {
      Navigator.of(context).pop(); // 关上 AI 面板，露出目标页
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('该题型暂不支持自动填参，已为你总结题干')));
    }
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(_scrollCtrl.position.maxScrollExtent,
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final width = mq.size.width < 420 ? mq.size.width : 380.0;
    final state = AppState.instance;
    final msgs = _ctrl.messages;

    return Material(
      color: AppColors.surface,
      elevation: 0,
      child: Container(
        width: width,
        height: mq.size.height,
        decoration: BoxDecoration(
          border: Border(left: BorderSide(color: AppColors.border)),
        ),
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ===== 头部：标题 + 呼吸光点 =====
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 8, 10),
                child: Row(
                  children: [
                    FadeTransition(
                      opacity: Tween(begin: 0.6, end: 1.0).animate(_breath),
                      child: Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: AppColors.teal,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text('AI 遗传助手', style: AppText.sectionTitle),
                    const Spacer(),
                    IconButton(
                      tooltip: '内置题库（拍题识别自动入库）',
                      icon: const Icon(Icons.inventory_2_outlined, size: 20),
                      onPressed: _showBank,
                    ),
                    IconButton(
                      tooltip: '清空历史',
                      icon: const Icon(Icons.delete_outline, size: 20),
                      onPressed: msgs.isEmpty ? null : _clearHistory,
                    ),
                    IconButton(
                      tooltip: '关闭',
                      icon: const Icon(Icons.close, size: 20),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              // ===== 上下文 chip（AI 看到了什么） =====
              InkWell(
                onTap: () =>
                    setState(() => _contextExpanded = !_contextExpanded),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  child: Row(
                    children: [
                      Icon(Icons.visibility_outlined,
                          size: 15, color: AppColors.steel),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          state.hasContext
                              ? 'AI 可见：${state.currentPage}'
                              : 'AI 可见：${state.currentPage}（暂无计算上下文）',
                          style: AppText.caption,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Icon(
                        _contextExpanded
                            ? Icons.expand_less
                            : Icons.expand_more,
                        size: 16,
                        color: AppColors.steel,
                      ),
                    ],
                  ),
                ),
              ),
              if (_contextExpanded)
                Container(
                  margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.tealWash,
                    borderRadius: BorderRadius.circular(AppTheme.radiusChip),
                  ),
                  child: Text(
                    state.buildSnapshot(),
                    style: AppText.monoSmall.copyWith(fontSize: 11),
                  ),
                ),
              const Divider(height: 1),
              // ===== 消息流（R23：排队条并入弹性区，避免底部溢出） =====
              Expanded(
                child: msgs.isEmpty && _ctrl.queue.isEmpty
                    ? _EmptyHint(onAsk: _ask)
                    : Column(
                        children: [
                          Expanded(
                            child: msgs.isEmpty
                                ? const SizedBox.shrink()
                                : ListView.builder(
                                    controller: _scrollCtrl,
                                    padding: const EdgeInsets.all(14),
                                    itemCount: msgs.length,
                                    itemBuilder: (ctx, i) =>
                                        _MsgBubble(msg: msgs[i]),
                                  ),
                          ),
                          // 排队消息上浮一格（不占用常驻输入框）
                          if (_ctrl.queue.isNotEmpty)
                            Container(
                              padding:
                                  const EdgeInsets.fromLTRB(14, 8, 14, 4),
                              decoration: BoxDecoration(
                                border: Border(
                                    top: BorderSide(
                                        color: AppColors.border)),
                                color: AppColors.tealWash
                                    .withValues(alpha: 0.4),
                              ),
                              child: Column(
                                crossAxisAlignment:
                                    CrossAxisAlignment.start,
                                children: [
                                  for (var i = 0;
                                      i < _ctrl.queue.length;
                                      i++)
                                    Padding(
                                      padding:
                                          const EdgeInsets.only(bottom: 4),
                                      child: Row(
                                        children: [
                                          Icon(
                                              Icons.schedule_send_outlined,
                                              size: 13,
                                              color: AppColors.steel),
                                          const SizedBox(width: 6),
                                          Expanded(
                                            child: Text(
                                              '${i + 1}. ${_ctrl.queue[i]}',
                                              style: AppText.caption,
                                              maxLines: 1,
                                              overflow:
                                                  TextOverflow.ellipsis,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                ],
                              ),
                            ),
                        ],
                      ),
              ),
              if (_busy)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                  child: Row(
                    children: [
                      // v2.19.23 找茬 §4.9：去外层 const（隐式 const 冻结盲区）。
                      Expanded(child: _ThinkingSkeleton()),
                      const SizedBox(width: 8),
                      Text(_ctrl.busyLabel,
                          style: AppText.caption
                              .copyWith(color: AppColors.steel)),
                    ],
                  ),
                ),
              // ===== 拍题识别结果卡（v2.5：有结果时浮在建议条上方） =====
              if (_ctrl.lastScan != null) _buildScanCard(_ctrl.lastScan!),
              // ===== 建议问题（本地刷新 / AI 刷新，常驻） =====
              _buildSuggestionBar(),
              const Divider(height: 1),
              // ===== 输入区（R23：发送→打断切换 + 回车样排队按钮） =====
              // v2.19.26 手机 P1-1 修复：自绘 dialog 不吃键盘 inset
              //（只有 AlertDialog 一族自动处理），软键盘弹出时输入行
              // 与发送键被整个压住。viewInsets 底部抬升 + 回车键改为
              // 发送（原 multiline 默认换行，手机端唯一发送路径被盖）。
              Padding(
                padding: EdgeInsets.only(
                    bottom: MediaQuery.viewInsetsOf(context).bottom),
                child: Padding(
                padding:
                    const EdgeInsets.fromLTRB(12, 10, 12, 12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _inputCtrl,
                        minLines: 1,
                        maxLines: 4,
                        style: AppText.body,
                        // 手机软键盘回车 = 发送（桌面多行换行不受影响：
                        // 桌面按 Enter 走同一 onSubmitted，Shift+Enter
                        // 换行仍可用）。
                        textInputAction: TextInputAction.send,
                        decoration: const InputDecoration(
                          hintText: '问 AI，它看得到你当前的计算…',
                          isDense: true,
                        ),
                        onSubmitted: (_) => _send(),
                      ),
                    ),
                    // R23 主按钮：空闲=发送；回答/刷新中自动变为「打断」
                    //（用户反馈：发送箭头在请求进行时应变成终止箭头）
                    if (_busy)
                      IconButton(
                        tooltip: '打断',
                        icon: Icon(Icons.stop_circle_outlined,
                            size: 24, color: AppColors.armed),
                        onPressed: _ctrl.interrupt,
                      )
                    else
                      IconButton.filled(
                        onPressed: _send,
                        icon: const Icon(Icons.arrow_upward, size: 18),
                        style: IconButton.styleFrom(
                          backgroundColor: AppColors.teal,
                          // v2.12 单一事实源: 浅色 white / 暗色墨绿,
                          // 与 ColorScheme.onPrimary 对齐
                          foregroundColor: AppColors.onTeal,
                        ),
                      ),
                    // R23 排队按钮（回车样）：AI 回答期间继续写、可不断
                    // 排队；完成后自动逐条发送（空闲时不显示）
                    if (_busy)
                      IconButton(
                        tooltip: '排队发送（AI 完成后自动发送）',
                        icon: Icon(Icons.keyboard_return_outlined,
                            size: 20,
                            color: AppColors.teal),
                        onPressed: () {
                          final q = _inputCtrl.text.trim();
                          if (q.isEmpty) return;
                          _inputCtrl.clear();
                          _ctrl.queueSend(q);
                        },
                      ),
                  ],
                ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// v2.5 拍题识别结果卡：总结 + 模块路由按钮（可填参/可执行动作时）。
  Widget _buildScanCard(ScanResult scan) {
    final target = ModuleFillBus.targetOf(scan.module);
    // v2.9：可填参（params 非空）或可执行动作（actions 非空且目标支持动作路由）
    final fillable = target != null &&
        (scan.params.isNotEmpty ||
            (scan.actions.isNotEmpty && target.applyActions != null));
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 6, 12, 4),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.tealWash.withValues(alpha: 0.5),
        border: Border.all(color: AppColors.teal.withValues(alpha: 0.4)),
        borderRadius: BorderRadius.circular(AppTheme.radiusChip),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.document_scanner_outlined,
                  size: 15, color: AppColors.teal),
              const SizedBox(width: 6),
              Expanded(
                child: Text('识别结果 · ${scanModuleLabel(scan.module)}',
                    style: AppText.caption.copyWith(color: AppColors.teal)),
              ),
              // v2.19.26（手机 P2-4）：✕ 原触控面 16×16 手机点不中——
              // 视觉保持 16，命中区扩到 40×40（行高居中）。
              InkWell(
                onTap: _ctrl.dismissScan,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                      minWidth: 40, minHeight: 40),
                  child: Icon(Icons.close,
                      size: 16, color: AppColors.steel),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(scan.summary,
              style: AppText.body.copyWith(fontSize: 13),
              maxLines: 3,
              overflow: TextOverflow.ellipsis),
          // v2.9：动作清单（创建家族/添加样本/计算下一代）
          if (scan.actions.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  for (final a in scan.actions)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: AppColors.sand.withValues(alpha: 0.25),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(scanActionLabel(a),
                          style: AppText.caption
                              .copyWith(color: AppColors.graphite)),
                    ),
                ],
              ),
            ),
          const SizedBox(height: 8),
          Row(
            children: [
              if (fillable)
                FilledButton.icon(
                  onPressed: () => _fillFromScan(scan),
                  icon: const Icon(Icons.input_outlined, size: 16),
                  label: Text('填入${target.label}'),
                  style: FilledButton.styleFrom(
                      visualDensity: VisualDensity.compact),
                )
              else
                Expanded(
                  child: Text('该题型仅总结，暂不支持自动填参',
                      style:
                          AppText.caption.copyWith(color: AppColors.steel)),
                ),
              const Spacer(),
              Text('已存入题库',
                  style: AppText.caption.copyWith(color: AppColors.steel)),
            ],
          ),
        ],
      ),
    );
  }

  /// 建议问题条（R17/R22：常驻；本地题库随机抽 / AI 按当前页面生成）。
  Widget _buildSuggestionBar() {
    return Container(
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('猜你想问', style: AppText.caption),
              const Spacer(),
              IconButton(
                tooltip: '本地刷新（内置题库）',
                icon: const Icon(Icons.refresh, size: 18),
                onPressed: _ctrl.refreshing ? null : _localRefresh,
              ),
              IconButton(
                tooltip: 'AI 刷新（按当前页面内容推荐）',
                icon: _ctrl.refreshing
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.auto_awesome, size: 18),
                onPressed: _ctrl.refreshing ? null : _aiRefresh,
              ),
            ],
          ),
          for (final q in _ctrl.suggestions)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: InkWell(
                borderRadius: BorderRadius.circular(AppTheme.radiusChip),
                onTap: () {
                  _inputCtrl.text = q;
                  _send();
                },
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    border: Border.all(color: AppColors.border),
                    borderRadius:
                        BorderRadius.circular(AppTheme.radiusChip),
                  ),
                  child:
                      Text(q, style: AppText.body.copyWith(fontSize: 13)),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// 空状态：构图化引导（建议问题已移到常驻建议栏）。
class _EmptyHint extends StatelessWidget {
  const _EmptyHint({required this.onAsk});

  /// 点示例问题 → 直接发问。
  final void Function(String) onAsk;

  /// v2.13：空态示例问题——「能问什么」模板，降低第一次发问门槛。
  static const _examples = [
    'AaBb × AaBb 为什么得到 9:3:3:1？',
    '测交和自交怎么选？',
    '伴性遗传「交叉遗传」是什么意思？',
  ];

  @override
  Widget build(BuildContext context) {
    // SingleChildScrollView：空态内容（图标+说明+3 示例 chip）在矮视口/
    // 课堂 ×1.3 下可能超出可用高度，滚得动就不 overflow。
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 12),
          Icon(Icons.psychology_outlined,
              size: 40, color: AppColors.teal),
          const SizedBox(height: 12),
          Text('我能看到你屏幕上的遗传计算，直接问。', style: AppText.body),
          const SizedBox(height: 4),
          Text('也可以点击下方「猜你想问」，或用两个刷新按钮换一批。',
              style: AppText.caption),
          const SizedBox(height: 12),
          for (final q in _examples)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: ActionChip(
                avatar: const Icon(Icons.chat_bubble_outline, size: 14),
                label: Text(q, style: AppText.caption),
                onPressed: () => onAsk(q),
              ),
            ),
        ],
      ),
    );
  }
}

/// 消息气泡：assistant 消息的思维链（R22）默认折叠展示，
/// **AI 输出内容始终直接展开**（不随思维链折叠）。
///
/// v2.12.0+2 hotfix：思维链改为默认**展开**（v2.12 老师 + 学生
/// persona UX 共识——学生需要看到解题过程、老师需要看到 AI 推理路径）。
/// 用户可在标题右侧勾选「下次不展开」关掉，偏好持久化到 AppState。
class _MsgBubble extends StatelessWidget {
  final AiChatMessage msg;
  const _MsgBubble({required this.msg});

  @override
  Widget build(BuildContext context) {
    final isUser = msg.role == 'user';
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        constraints: const BoxConstraints(maxWidth: 300),
        decoration: BoxDecoration(
          color: isUser ? AppColors.tealWash : AppColors.canvas,
          border: isUser ? null : Border.all(color: AppColors.border),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // R22 思维链：默认折叠；只折叠思考过程，正文不折叠
            if (!isUser &&
                msg.reasoning != null &&
                msg.reasoning!.isNotEmpty)
              _ReasoningBlock(reasoning: msg.reasoning!),
            // v2.13 学生走查 P0：基因型（AaBb / XBXb）与比例（9:3:3:1）
            // 等宽 + teal 高亮——AI 回「9:3:3:1 表型分布」不再糊成连续字符。
            // v2.13+：Markdown 管道表格渲染成真表格（原竖线原文难读）。
            _AiMessageBody(text: msg.text, base: AppText.body.copyWith(fontSize: 13)),
          ],
        ),
      ),
    );
  }
}

/// AI 回复正文：管道表格块渲染成真表格，其余段落走富文本高亮。
class _AiMessageBody extends StatelessWidget {
  const _AiMessageBody({required this.text, required this.base});

  final String text;
  final TextStyle base;

  @override
  Widget build(BuildContext context) {
    final blocks = _splitBlocks(text);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final b in blocks)
          if (b.table != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: _MdTable(rows: b.table!),
            )
          else if ((b.text ?? '').trim().isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: SelectableText.rich(_richAiText(b.text!, base)),
            ),
      ],
    );
  }

  /// 按「连续 | 开头行 = 表格块」切分文本块。
  static List<({String? text, List<List<String>>? table})> _splitBlocks(
      String text) {
    final out = <({String? text, List<List<String>>? table})>[];
    final lines = text.split('\n');
    var i = 0;
    final buf = StringBuffer();
    void flush() {
      if (buf.isNotEmpty) {
        // trim：writeln 累积的首尾换行会让 find.text 精确匹配失配
        // （回归测试实测），内部换行保留。
        out.add((text: buf.toString().trim(), table: null));
        buf.clear();
      }
    }

    while (i < lines.length) {
      if (lines[i].trimLeft().startsWith('|')) {
        final tbl = <List<String>>[];
        while (i < lines.length &&
            lines[i].trimLeft().startsWith('|')) {
          final cells = lines[i]
              .trim()
              .replaceAll(RegExp(r'^\|'), '')
              .replaceAll(RegExp(r'\|$'), '')
              .split('|')
              .map((c) => c.trim())
              .toList();
          // 跳过分隔行 |---|---|。
          final isSep =
              cells.every((c) => RegExp(r'^:?-{2,}:?$').hasMatch(c));
          if (!isSep) tbl.add(cells);
          i++;
        }
        if (tbl.isNotEmpty) {
          flush();
          out.add((text: null, table: tbl));
        }
      } else {
        buf.writeln(lines[i]);
        i++;
      }
    }
    flush();
    return out;
  }
}

/// Markdown 表格的紧凑渲染（Table + 全边框，caption 字号）。
class _MdTable extends StatelessWidget {
  const _MdTable({required this.rows});
  final List<List<String>> rows;

  @override
  Widget build(BuildContext context) {
    final cols = rows.map((r) => r.length).fold<int>(0, (a, b) => a > b ? a : b);
    return Table(
      border: TableBorder.all(
          color: AppColors.border, width: 0.8, borderRadius: BorderRadius.circular(4)),
      defaultVerticalAlignment: TableCellVerticalAlignment.middle,
      children: [
        for (var ri = 0; ri < rows.length; ri++)
          TableRow(
            decoration: ri == 0
                ? BoxDecoration(color: AppColors.tealWash)
                : null,
            children: [
              for (var ci = 0; ci < cols; ci++)
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                  child: Text(
                    ci < rows[ri].length ? rows[ri][ci] : '',
                    style: AppText.caption.copyWith(
                      color: ri == 0 ? AppColors.teal : AppColors.ink,
                      fontWeight:
                          ri == 0 ? FontWeight.w700 : FontWeight.w400,
                    ),
                  ),
                ),
            ],
          ),
      ],
    );
  }
}

/// AI 回复富文本：比例（9:3:3:1 / 27:9:…:1）与基因型（AaBb / XBXb /
/// AABbcc）用等宽 + teal 加亮渲染，其余保持正文字体。
///
/// 启发式（AI 回答以中文为主，英文只可能是基因型/术语）：
/// - 比例：`\d+(:\d+)+`——纯数字+冒号序列。
/// - 基因型：`[A-Z][A-Za-z]{1,7}`——大写开头、2~8 位、必含小写
///   （排除 DNA/RNA 这类全大写缩写术语，它们不该被高亮）。
TextSpan _richAiText(String text, TextStyle base) {
  final pattern = RegExp(r'(\d+(?::\d+)+)|\b([A-Z][A-Za-z]{1,7})\b');
  final spans = <TextSpan>[];
  var index = 0;
  for (final m in pattern.allMatches(text)) {
    if (m.start > index) {
      spans.add(TextSpan(text: text.substring(index, m.start), style: base));
    }
    final isRatio = m.group(1) != null;
    final token = m.group(0)!;
    final isGenotype = !isRatio && token.contains(RegExp(r'[a-z]'));
    if (isRatio || isGenotype) {
      spans.add(TextSpan(
        text: token,
        style: base.copyWith(
          fontFamily: AppText.monoSmall.fontFamily,
          fontFamilyFallback: AppText.monoSmall.fontFamilyFallback,
          color: AppColors.teal,
          fontWeight: FontWeight.w700,
        ),
      ));
    } else {
      spans.add(TextSpan(text: token, style: base));
    }
    index = m.end;
  }
  if (index < text.length) {
    spans.add(TextSpan(text: text.substring(index), style: base));
  }
  return TextSpan(children: spans, style: base);
}

/// R22 思维链折叠块：默认折叠（ListTile 在有色容器里会触发断言，
/// 因此自绘 InkWell + 条件展开），展开/收起只影响思考过程本身。
///
/// v2.12.0+2 hotfix：默认状态从 `AppState.thinkingChainExpandedDefault`
/// 读取（默认 true）。用户勾选标题右侧「下次不展开」复选框后，
/// 写入 AppState 并立即收起当前展开的思维链。
class _ReasoningBlock extends StatefulWidget {
  final String reasoning;
  const _ReasoningBlock({required this.reasoning});

  @override
  State<_ReasoningBlock> createState() => _ReasoningBlockState();
}

class _ReasoningBlockState extends State<_ReasoningBlock> {
  /// 当前展开状态。初始值取自 AppState.thinkingChainExpandedDefault。
  /// 后续跟 AppState 双向联动：用户勾「下次不展开」→ AppState 持久化
  /// + 本地立即收起。
  late bool _open;
  late VoidCallback _appStateListener;

  @override
  void initState() {
    super.initState();
    _open = AppState.instance.thinkingChainExpandedDefault;
    _appStateListener = () {
      if (!mounted) return;
      // 偏好从 true→false 时立即收起（用户已勾「下次不展开」）。
      // 偏好从 false→true 时不强制展开——尊重用户当下手动操作。
      if (!AppState.instance.thinkingChainExpandedDefault) {
        setState(() => _open = false);
      }
    };
    AppState.instance.addListener(_appStateListener);
  }

  @override
  void dispose() {
    AppState.instance.removeListener(_appStateListener);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final defaultExpanded = AppState.instance.thinkingChainExpandedDefault;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: () => setState(() => _open = !_open),
          borderRadius: BorderRadius.circular(6),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.psychology_alt_outlined,
                    size: 13, color: AppColors.steel),
                const SizedBox(width: 4),
                Text('思维过程',
                    style: AppText.caption
                        .copyWith(color: AppColors.steel)),
                const SizedBox(width: 2),
                Icon(_open ? Icons.expand_less : Icons.expand_more,
                    size: 14, color: AppColors.steel),
                const SizedBox(width: 8),
                // v2.12.0+2 hotfix：用户偏好——勾上后下次默认收起
                // （AppState 持久化，复选框本身始终反映当前默认）。
                GestureDetector(
                  onTap: () {
                    // 切换时立刻 setState 避免点击穿透到 InkWell
                    final next = !defaultExpanded;
                    AppState.instance
                        .setThinkingChainExpandedDefault(next);
                  },
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 14,
                        height: 14,
                        child: Checkbox(
                          value: !defaultExpanded,
                          // 视觉上 uncheck = 默认展开，check = 下次不展开
                          // value 反向：勾上 = 下次不展开 = defaultExpanded=false
                          materialTapTargetSize:
                              MaterialTapTargetSize.shrinkWrap,
                          onChanged: (v) {
                            AppState.instance
                                .setThinkingChainExpandedDefault(!(v ?? false));
                          },
                        ),
                      ),
                      const SizedBox(width: 3),
                      Text('下次不展开',
                          style: AppText.caption
                              .copyWith(color: AppColors.steel, fontSize: 10)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        if (_open)
          Align(
            alignment: Alignment.centerLeft,
            child: SelectableText(
              widget.reasoning,
              style: AppText.monoSmall.copyWith(
                  fontSize: 11, color: AppColors.steel),
            ),
          ),
        const SizedBox(height: 2),
      ],
    );
  }
}

/// 思考中骨架（禁止裸转圈）。
class _ThinkingSkeleton extends StatefulWidget {
  const _ThinkingSkeleton();

  @override
  State<_ThinkingSkeleton> createState() => _ThinkingSkeletonState();
}

class _ThinkingSkeletonState extends State<_ThinkingSkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1100))
    ..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: Tween(begin: 0.35, end: 0.9).animate(_c),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _bar(220),
          const SizedBox(height: 6),
          _bar(160),
        ],
      ),
    );
  }

  Widget _bar(double w) => Container(
        width: w,
        height: 10,
        decoration: BoxDecoration(
          color: AppColors.border,
          borderRadius: BorderRadius.circular(5),
        ),
      );
}

/// v2.5 内置题库对话框：拍题识别自动入库的题目列表，
/// 点条目回填对应模块（不可填参的题型仅查看总结），可逐条删/清空。
class _ScanBankDialog extends StatefulWidget {
  /// 面板自己的 context：回填成功后连面板一起关掉露出目标页。
  final BuildContext parentContext;
  const _ScanBankDialog({required this.parentContext});

  @override
  State<_ScanBankDialog> createState() => _ScanBankDialogState();
}

class _ScanBankDialogState extends State<_ScanBankDialog> {
  List<ScanEntry>? _entries;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final list = await ScanBankStore.load();
    if (mounted) setState(() => _entries = list);
  }

  String _fmtTs(int ts) {
    if (ts <= 0) return '';
    final d = DateTime.fromMillisecondsSinceEpoch(ts);
    return '${d.month}/${d.day} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  }

  void _fill(ScanEntry e) {
    final target = ModuleFillBus.targetOf(e.module);
    final hasActions = e.actions.isNotEmpty && target?.applyActions != null;
    if ((e.params.isEmpty && !hasActions) || target == null) {
      ScaffoldMessenger.of(widget.parentContext).showSnackBar(
          const SnackBar(content: Text('该题仅支持查看总结，对应模块不支持自动填参')));
      return;
    }
    ModuleFillBus.fillScan(e.module, e.params, e.actions);
    Navigator.of(context).pop(); // 关题库对话框
    Navigator.of(widget.parentContext).pop(); // 关 AI 面板
  }

  Future<void> _clearAll() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('清空内置题库？'),
        content: const Text('将删除全部拍题识别入库的题目，不可恢复。'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('清空')),
        ],
      ),
    );
    if (ok == true) {
      await ScanBankStore.clear();
      await _reload();
    }
  }

  @override
  Widget build(BuildContext context) {
    final entries = _entries;
    return AlertDialog(
      title: Row(
        children: [
          Icon(Icons.inventory_2_outlined, size: 20, color: AppColors.teal),
          const SizedBox(width: 8),
          const Expanded(child: Text('内置题库')),
          if (entries != null && entries.isNotEmpty)
            TextButton(onPressed: _clearAll, child: const Text('清空')),
        ],
      ),
      content: SizedBox(
        width: 440,
        height: 380,
        child: entries == null
            ? const Center(child: CircularProgressIndicator())
            : entries.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.photo_library_outlined,
                            size: 48, color: AppColors.steel),
                        const SizedBox(height: 12),
                        Text('还没有入库的题目', style: AppText.sectionTitle),
                        const SizedBox(height: 6),
                        Text(
                          '点输入框旁的图片按钮上传题目照片，识别成功后会自动存到这里。',
                          textAlign: TextAlign.center,
                          style: AppText.caption
                              .copyWith(color: AppColors.steel),
                        ),
                      ],
                    ),
                  )
                : ListView.separated(
                    itemCount: entries.length,
                    separatorBuilder: (_, i) =>
                        Divider(height: 1, color: AppColors.border),
                    itemBuilder: (ctx, i) {
                      final e = entries[i];
                      return ListTile(
                        dense: true,
                        contentPadding:
                            const EdgeInsets.symmetric(horizontal: 4),
                        title: Text(e.summary,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: AppText.body.copyWith(fontSize: 13)),
                        subtitle: Text(
                            '${scanModuleLabel(e.module)} · ${_fmtTs(e.ts)}',
                            style: AppText.caption
                                .copyWith(color: AppColors.steel)),
                        trailing: IconButton(
                          tooltip: '删除',
                          icon: const Icon(Icons.delete_outline, size: 18),
                          onPressed: () async {
                            await ScanBankStore.removeAt(i);
                            await _reload();
                          },
                        ),
                        onTap: () => _fill(e),
                      );
                    },
                  ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('关闭')),
      ],
    );
  }
}