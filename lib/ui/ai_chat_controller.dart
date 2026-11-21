// ai_chat_controller.dart —— R22 全局 AI 会话控制器
//
// 需求背景：AI 问答/刷新本来住在面板 State 里，关闭面板（叉号）会
// 让请求结果无处落地、看起来「被打断」。本控制器把会话提到全局单例：
//   - 面板只是它的视图；关闭面板请求照跑，完成照常入库；
//   - 只有手动点「打断」才会中止当前请求（AiClient.interrupt）；
//   - 思维链（reasoning）随消息保存，面板默认折叠展示。

import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import '../services/ai_client.dart';
import '../state/scan_bank_store.dart';
import '../pages/settings_page.dart' show AiChatStore, AiSettingsStore;
import '../state/app_state.dart';
// v2.24：AI 工具调用（本地遗传引擎 / 联网搜索 / 本机 Python 与命令行）
import '../services/ai_tools.dart';
import '../state/ai_tool_settings.dart';
import 'tool_confirm.dart';

/// v2.2 全局画布截图：main.dart 的 RepaintBoundary 挂这个 key，
/// 任何页面打开问 AI 时若页面自身未注入截图，则自动截取当前
/// 内容区（IndexedStack）随问题发给多模态模型（M3/mimo）。
final GlobalKey appCanvasKey = GlobalKey(debugLabel: 'appCanvas');

/// 截取当前页面内容区为 PNG base64；失败返回 null（静默降级为纯文本问答）。
Future<String?> captureAppCanvas({double pixelRatio = 1.5}) async {
  try {
    final ctx = appCanvasKey.currentContext;
    if (ctx == null) return null;
    final boundary = ctx.findRenderObject() as RenderRepaintBoundary?;
    if (boundary == null || boundary.debugNeedsPaint) return null;
    final img = await boundary.toImage(pixelRatio: pixelRatio);
    final data = await img.toByteData(format: ui.ImageByteFormat.png);
    img.dispose();
    if (data == null) return null;
    return base64Encode(data.buffer.asUint8List());
  } catch (_) {
    return null;
  }
}

/// 一条聊天消息（user / assistant），可携带思维链。
class AiChatMessage {
  final String role; // 'user' / 'assistant'
  final String text;
  final String? reasoning; // R22 思维链（assistant 消息可带）
  const AiChatMessage(this.role, this.text, {this.reasoning});
}

/// 全局 AI 会话（单例，跨面板存活）。
class AiChatController extends ChangeNotifier {
  AiChatController._();
  static final AiChatController instance = AiChatController._();

  /// 历史消息（user/assistant；与 AiChatStore 持久化互通）。
  final List<AiChatMessage> messages = [];

  /// 是否正在回答（问答请求进行中）。
  bool busy = false;

  /// 是否正在 AI 刷新建议问题。
  bool refreshing = false;

  /// 当前进行中的任务描述（骨架屏/打断按钮提示）。
  String busyLabel = '';

  /// R23 排队中的问题：AI 回答/刷新期间用户继续输入可入队，
  /// 每完成一条自动发送下一条（输入框保持可写，队列条上浮显示）。
  final List<String> queue = [];

  /// 当前建议问题（本地题库 + AI 刷新写入）。
  List<String> suggestions = [];

  /// 活动客户端：打断按钮通过它中止请求。
  AiClient? _client;

  /// v2.11 H5：测试用——读当前活动 client 句柄。验证 _client?.interrupt()
  /// 守门行为：send/refresh 入口在覆盖前会先调 _client?.interrupt()，
  /// send 完成后 finally 块置 null。
  @visibleForTesting
  AiClient? get debugClient => _client;

  /// v3.5 多模态：页面打开问 AI 时注入的当前画布截图（PNG base64，
  /// 已按内容包围盒裁剪）。send() 取用一次即清空。
  String? pendingCanvasImage;

  /// v2.5 拍题识别：待识别的题目图片（base64 + MIME + 文件名）。
  /// 面板选图后填入，sendScan() 取用一次即清空。
  String? pendingScanImage;
  String? pendingScanMime;
  String? pendingScanName;

  /// v2.5 拍题识别：最近一次识别结果（面板结果卡用；新识别覆盖）。
  ScanResult? lastScan;

  /// v2.13 R3 P1-A1：最近一次识别失败原因（识别成功 / 新一次识别开始时
  /// 清空）。拍题对话框不渲染聊天——失败只写 messages 等于静默，对话框
  /// 靠 sendScan() 返回值 + 本字段弹「识别失败：$lastScanError，请重试」。
  String? lastScanError;

  /// 测试注入：非空时 sendScan 走该发送器而非真实网络。
  Future<AiResult> Function(List<AiMessage> messages)? debugScanSender;

  /// v2.11 H5：测试注入——非空时 send / refreshSuggestions 走该发送器
  /// 而非真实网络（与 debugScanSender 同构）。让并发守门测试可以
  /// 注入可阻塞的 Future 控制时序。
  Future<AiResult> Function(List<AiMessage> messages)? debugSender;

  /// 面板选图后挂入待识别图片。
  void attachScanImage(String base64, String mime, String name) {
    pendingScanImage = base64;
    pendingScanMime = mime;
    pendingScanName = name;
    notifyListeners();
  }

  /// 移除待识别图片（未发送前）。
  void clearScanImage() {
    pendingScanImage = null;
    pendingScanMime = null;
    pendingScanName = null;
    notifyListeners();
  }

  /// 加载持久化历史（打开面板前调用一次）。
  Future<void> loadHistory() async {
    if (messages.isNotEmpty) return;
    final saved = await AiChatStore.load();
    messages.addAll([
      for (final m in saved)
        AiChatMessage(m['role']!, m['text']!,
            reasoning: m['reasoning']?.isNotEmpty ?? false
                ? m['reasoning']
                : null),
    ]);
    notifyListeners();
  }

  /// 清空历史（带确认交互在 UI 层；这里只负责状态）。
  ///
  /// v2.19.57：返回 Future 并 await 落盘。加密改造后写盘是异步的
  /// （KDF 在子 isolate），旧 fire-and-forget 在「清空后立刻退 app」
  /// 时可能永远没落盘；且旧 clear 与 send 的写是两条独立异步链，
  /// 交错时「先排队的旧快照」可能后落盘，把已清空的历史复活。
  /// 现在所有写都排 [_persistQueue] 串行执行，清空 = 排一条空快照，
  /// 顺序与内容都由队列保证。顺序刻意为「清内存 → notify → 落盘」：
  /// 空态立刻出现，不等 KDF/磁盘。
  Future<void> clearHistory() async {
    messages.clear();
    notifyListeners();
    await _persist(); // 落盘完成才算这次清空真的做完（失败外抛给调用方）
  }

  // ───────── v2.19.57 落盘串行队列 ─────────
  //
  // 背景：local_secure_store.dart 头部如实记账的遗留弱化——本仓聊天历史
  // 写盘是 fire-and-forget，进程被杀的那一瞬可能丢掉本次写入；且
  // clearHistory 走 AiChatStore.clear()、send 走 save()，两条独立异步链
  // 交错时旧快照可能后落盘（历史复活）。本批修法（与源仓 R9-F 同思路）：
  //   ① 所有写排 [_persistQueue]，同 isolate 串行，一次只跑一个 job；
  //   ② 每次写的内容在**入队时刻**快照定死 ⇒ 入队序 = 状态序，
  //      执行序 = 入队序 ⇒ 后写必然覆盖前写，最后一次写必然等于最新状态；
  //   ③ UI 顺序保持「改内存 → notifyListeners() → 落盘」——写盘要等
  //      KDF（冷路径 ~770ms 发生在子 isolate），气泡不能被它卡住；
  //   ④ 写失败可观测：记 [lastPersistError] + debugPrint + notify；
  //      要确认写成功的调用方（clearHistory）拿到的 Future 以异常结束。
  //
  // 为什么是队列而不是「存在字段上的尾巴 Future」：尾巴 Future 有
  // **区域亲和性**——`.then` 的回调被排进该 Future 创建时那个 zone 的
  // 微任务队列。单例尾巴在 setUp（真实区域）里首次成型后，testWidgets 的
  // FakeAsync 区域里 `.then` 永远不被驱动 ⇒ 落盘卡死。队列的驱动点
  // [_drainPersistQueue] 每次由**调用方区域**同步发起，无悬挂回调。

  /// 落盘 FIFO 队列：所有写按入队序串行执行，后写必然覆盖前写。
  final List<_PersistJob> _persistQueue = [];

  /// 队列是否正在排空（同时只会有一条写链在跑）。
  bool _persistDraining = false;

  /// [debugWaitPersistIdle] 的等待者；队列空时统一 complete。
  final List<Completer<void>> _idleWaiters = [];

  /// 最近一次落盘失败原因（null = 无失败记录）。
  ///
  /// 这是「不 await 的调用链」（send/sendScan 的绝大多数调用点）唯一
  /// 的失败出口：写失败时这里非空 + debugPrint + 一次 notifyListeners。
  String? lastPersistError;

  /// 累计**成功**落盘次数（测试/日志用；生产不读）。
  @visibleForTesting
  int get debugPersistWrites => _persistWrites;

  int _persistWrites = 0;

  /// 测试注入：非空时 [_writeSnapshot] 走它而非真实 AiChatStore.save。
  ///
  /// 用途是把「写盘」排成确定时序（挂起/抛错/记录调用顺序）。不加这个
  /// 接缝，落盘先后只能靠 PBKDF2 让出几次碰运气 ⇒ 时序断言只能在
  /// 「碰巧谁赢」上绿，是假绿。生产恒 null。
  @visibleForTesting
  static Future<void> Function(List<Map<String, String>> msgs)?
      debugPersistSink;

  /// 测试专用：清静态注入（与其他 store 的 debugResetHooks 同构）。
  @visibleForTesting
  static void debugResetHooks() => debugPersistSink = null;

  /// 测试专用：落盘队列是否已排空（同步判定，无区域亲和性问题）。
  ///
  /// tearDown/用例内部用它做「等写盘跑完」的收敛判据——比 await 一个
  /// 可能在已销毁 FakeAsync 区域里完成的 Future 可靠。
  @visibleForTesting
  bool get debugPersistIdle => !_persistDraining && _persistQueue.isEmpty;

  /// 测试专用：等当前排队的落盘全部跑完（队列归零）。
  ///
  /// **只能在用例体内调用**（返回的 Future 在调用方区域完成，需要该区域
  /// 继续驱动微任务）。用例体外请用 [debugPersistIdle] 同步判定。
  @visibleForTesting
  Future<void> debugWaitPersistIdle() {
    if (debugPersistIdle) return Future<void>.value();
    final waiter = Completer<void>();
    _idleWaiters.add(waiter);
    return waiter.future;
  }

  /// 测试专用：强制丢弃排队的落盘（用例被中断时的自愈阀，生产不调）。
  ///
  /// 只用于 setUp 清理上一个用例的残留；残留 job 以「正常完成」收口，
  /// 避免留下无人处理的异步错误去污染下一个用例。
  @visibleForTesting
  void debugResetPersistQueue() {
    if (_persistQueue.isEmpty && !_persistDraining) return;
    // ignore: avoid_print
    print('v2.19.57 警告：setUp 发现残留落盘队列 ${_persistQueue.length} 项，'
        '已丢弃（上一个用例没收口）');
    for (final job in _persistQueue) {
      if (!job.done.isCompleted) job.done.complete();
    }
    _persistQueue.clear();
    _persistDraining = false;
    _notifyPersistIdle();
  }

  /// 按**调用时刻**的内存状态生成待写快照。
  List<Map<String, String>> _snapshotMessages() => [
        for (final m in messages)
          {
            'role': m.role,
            'text': m.text,
            if (m.reasoning != null) 'reasoning': m.reasoning!,
          },
      ];

  /// 把当前状态落盘：入队即快照，实现在 [_persistQueue] 上**串行**执行。
  ///
  /// 返回的 Future 代表「本次快照已落盘完成」；写失败以异常结束（同时
  /// 记 [lastPersistError]）。本方法**不** notifyListeners——UI 反馈在
  /// 状态变更处立刻给。排队点由调用方区域同步发起（见
  /// [_drainPersistQueue] 的区域说明），队列空时第一次写的**调用**本身
  /// 也是同步发生的。
  Future<void> _persist() {
    final job = _PersistJob(_snapshotMessages()); // 入队时刻定死内容，防后被覆
    _persistQueue.add(job);
    if (!_persistDraining) unawaited(_drainPersistQueue());
    return job.done.future;
  }

  /// 串行排空落盘队列。**同 isolate 写序保证**：一次只跑一个 job。
  ///
  /// 区域要点：本方法是 async，但**调用点**在 [_persist]（同步进入、直到
  /// 第一次 await），因此微任务回调绑在发起写的调用方区域；FakeAsync
  /// 用例里 tester.pump() 就能推进——不存在「跨用例区域的悬挂尾巴」。
  Future<void> _drainPersistQueue() async {
    _persistDraining = true;
    try {
      while (_persistQueue.isNotEmpty) {
        final job = _persistQueue.removeAt(0);
        try {
          await _writeSnapshot(job.snapshot);
          if (!job.done.isCompleted) job.done.complete();
        } catch (e, s) {
          if (!job.done.isCompleted) job.done.completeError(e, s);
        }
        _notifyPersistIdle();
      }
    } finally {
      _persistDraining = false;
      _notifyPersistIdle();
    }
  }

  /// 队列空时唤醒所有 [debugWaitPersistIdle] 等待者。
  void _notifyPersistIdle() {
    if (_persistDraining || _persistQueue.isNotEmpty) return;
    if (_idleWaiters.isEmpty) return;
    final waiters = List<Completer<void>>.of(_idleWaiters);
    _idleWaiters.clear();
    for (final waiter in waiters) {
      if (!waiter.isCompleted) waiter.complete();
    }
  }

  /// 落盘并**不外抛**（失败已在 [lastPersistError] 记账）。
  ///
  /// 为什么这里不外抛：send/sendScan 的调用点绝大多数不 await（面板
  /// _send()、queueSend、_drainQueue 都是 fire-and-forget），异常会变成
  /// 未处理异步错误。真正需要「确认写成功」的 clearHistory 自己
  /// await [_persist]。
  Future<void> _persistLogged() => _persist().catchError((_) {});

  Future<void> _writeSnapshot(List<Map<String, String>> snapshot) async {
    final sink = debugPersistSink ?? AiChatStore.save;
    try {
      await sink(snapshot);
      _persistWrites++;
      lastPersistError = null;
    } catch (e) {
      lastPersistError = '历史未能持久化（$e）';
      debugPrint('AiChatController._persist: $lastPersistError');
      notifyListeners(); // 让订阅了 lastPersistError 的 UI 有机会响应
      rethrow;
    }
  }

  /// R23 排队发送：空闲 = 立即发送；回答/刷新中 = 进入队列
  /// （完成后自动逐条发送；输入框立即清空可继续写）。
  void queueSend(String text) {
    final q = text.trim();
    if (q.isEmpty) return;
    if (busy || refreshing) {
      queue.add(q);
      notifyListeners();
    } else {
      send(q);
    }
  }

  /// 发送一问（不走面板生命周期：面板关闭也照常完成）。
  Future<void> send(String question) async {
    // v2.11 H5：守门——AI 回答/刷新中再点「问 AI」自动入队而非覆盖
    // _client。修复旧 _client 不被 interrupt 导致消息错位（AI 回答中
    // 点刷新 = 两条消息都到 messages 列表，顺序错乱）。
    if (busy || refreshing) {
      final q = question.trim();
      if (q.isNotEmpty) {
        queue.add(q);
        notifyListeners();
      }
      return;
    }
    final config = await AiSettingsStore.load();
    // v2.19.16：同 sendScan——注入 debugSender 时跳过真实配置要求。
    if (debugSender == null && !config.isConfigured) {
      // 未配置也如实记录用户消息（问题不丢失），再附配置提示
      messages.add(AiChatMessage('user', question));
      messages.add(const AiChatMessage(
          'assistant', '尚未配置 AI 接口。请到「设置」页确认 BaseURL 与 API Key（默认 DeepSeek 通道，需填入你的 DeepSeek key）。'));
      // v2.19.57：先 notify 让两条气泡立刻出现，再 await 落盘——
      // 返回的 Future 仍代表落盘完成（不退回 fire-and-forget）。
      notifyListeners();
      await _persistLogged();
      _drainQueue(); // 排队消息也能逐条落盘提示
      return;
    }
    messages.add(AiChatMessage('user', question));
    busy = true;
    busyLabel = '正在回答…';
    // v2.19.57：用户气泡 + 「正在回答…」立刻上浮，不等 KDF/磁盘。
    notifyListeners();
    await _persistLogged();

    // v2.11 H5：覆盖前先 interrupt 旧 client（防御性，正常情况 _client
    // 已被 sendScan 入口守门或 send 上一轮完成清空，理论上为 null）。
    _client?.interrupt();
    // v2.24：挂上可用工具。没有任何可用工具时（用户全关 / 通道不支持）
    // 退回纯对话，请求体与改造前逐字一致。
    final sender = debugSender ??
        (List<AiMessage> msgs) async {
          final client = AiClient(config);
          _client = client;
          final settings = await AiToolSettingsStore.load();
          final host = AiToolHost(
            config: config,
            settings: settings,
            confirm: confirmToolExecution,
          );
          final tools = await host.schemas();
          if (tools.isEmpty) return client.chat(msgs);
          return client.chat(msgs, tools: tools, onToolCall: host.call);
        };
    final snapshot = AppState.instance.buildSnapshot();
    // 多轮历史只带最近 20 条，避免长会话撑爆 prompt。
    // v2.19.57 顺手修一处 RangeError：落盘串行化后「用户在请求途中点
    // 清空」是可达时序（clearHistory 现在清内存立刻生效、落盘排队）——
    // messages 被清空后 messages.length - 1 = -1，take(-1) 直接抛
    // RangeError，send 的调用点不 await ⇒ 未处理异步异常 + 本轮回答丢失。
    // 空历史是合法输入（system + 本次问题照发），用 max(0, …) 夹住。
    final history = messages.length > 21
        ? messages.sublist(messages.length - 21, messages.length - 1)
        : messages.take(max(0, messages.length - 1)).toList();
    final res = await sender([
      AiMessage('system',
          '你是高中生物遗传学解题助手，内嵌在「生物遗传计算平台」软件中。'
          '你能直接看到用户当前的软件状态（页面、输入、计算结果），'
          '回答时优先结合该状态，不要让用户重复已输入的信息。'
          '涉及基因型、表型比例、概率时用简洁的中文推导，基因型用原文大写字母。'
          '若附带画布截图，请结合图上的系谱结构（节点、半边、连线、高亮）作答。\n\n'
          // v2.24：工具调用指引——比例类问题必须走本地引擎，别心算。
          '你可以调用工具：本地遗传引擎（涉及具体基因型、比例、概率时必须先用它核算，'
          '不要心算）、联网搜索与网页抓取、本机 Python、本机命令行。'
          '需要学科术语的通行表述或最新资料时再联网搜索。涉及本机代码执行时软件会自动弹确认框，'
          '不必在回答里询问用户是否允许。\n\n'
          '$snapshot'),
      ...history.map((m) => AiMessage(m.role, m.text)),
      AiMessage('user', question, imagePngBase64: pendingCanvasImage),
    ]);
    pendingCanvasImage = null; // 一次性：本次问答已携带
    busy = false;
    _client = null;
    if (res.ok) {
      messages.add(AiChatMessage(
          'assistant', withToolFooter(res.content, res.reasoning),
          reasoning: res.reasoning));
    } else if (res.error == '已打断') {
      messages.add(const AiChatMessage('assistant', '（已打断）'));
    } else {
      messages.add(AiChatMessage('assistant', res.error ?? '请求失败'));
    }
    // v2.19.57：回答/失败/打断的结果先上浮，再等落盘（Future 完成 = 已落盘）。
    notifyListeners();
    await _persistLogged();
    // R23：完成/失败/被打断后，自动发送下一条排队消息
    _drainQueue();
  }

  void _drainQueue() {
    if (queue.isEmpty) return;
    final next = queue.removeAt(0);
    notifyListeners();
    send(next);
  }

  /// v2.5 拍题识别：把 pendingScanImage 发给多模态模型，
  /// 要求返回严格 JSON（summary/module/params），成功后自动存入
  /// 内置题库（ScanBankStore）并把结果暴露在 lastScan 供面板
  /// 渲染「填入对应模块」结果卡。
  ///
  /// v2.13 R3 P1-A1：改为返回 bool——true = 识别成功（解析 + 入库）；
  /// false = 失败，原因写 lastScanError 供拍题对话框弹 SnackBar。
  /// 「已打断」也返回 false 但不写 lastScanError（用户主动行为不算失败）。
  Future<bool> sendScan() async {
    final img = pendingScanImage;
    if (img == null || busy || refreshing) return false;
    final name = pendingScanName ?? '题目图片';
    final mime = pendingScanMime ?? 'image/png';
    pendingScanImage = null;
    pendingScanMime = null;
    pendingScanName = null;

    // v2.13 R3 P1-A1：新一次识别开始，清空上次失败原因（不残留误报）。
    lastScanError = null;
    // R6 学生走查：新一次识别同时清掉旧结果卡——否则识别失败时旧卡
    // 仍挂在拍题弹窗里，正好挡住失败提示，学生会把上一题的答案当成
    // 新题结果（信任级缺陷）。
    lastScan = null;

    messages.add(AiChatMessage('user', '【题目图片】$name'));
    final config = await AiSettingsStore.load();
    // v2.19.16：注入测试通道时跳过真实配置要求——原检查在
    // debugScanSender 之前，机器 key 轮换（ai_config 解密失败）会把
    // 测试打成「未配置」分支（9/25 实爆：M6/v215_r6 全量红）。
    // debugScanSender 生产恒 null，行为不变。
    if (debugScanSender == null && !config.isConfigured) {
      lastScanError = '尚未配置 AI 接口';
      messages.add(const AiChatMessage(
          'assistant', '尚未配置 AI 接口。请到「设置」页确认 BaseURL 与 API Key。'));
      // v2.19.57：先 notify（对话框/面板立刻看到提示），再等落盘。
      notifyListeners();
      await _persistLogged();
      return false;
    }
    busy = true;
    busyLabel = '正在识别题目…';
    // v2.19.57：「正在识别题目…」骨架屏立刻出现，不等 KDF/磁盘。
    notifyListeners();
    await _persistLogged();

    AiClient? client;
    final sender = debugScanSender ??
        (List<AiMessage> msgs) {
          // v2.11 H5：防御性 interrupt——sendScan 入口已有 busy/refreshing
          // 守门（line 223），但 debugScanSender 注入非默认实现时可能跳过
          // 该守门；这里再守一遍。
          _client?.interrupt();
          client = AiClient(config);
          _client = client;
          return client!.chat(msgs);
        };
    final res = await sender([
      const AiMessage('system',
          '你是高中生物题目识别助手。用户会给你一张题目图片（可能是遗传杂交题、'
          '系谱图、DNA/中心法则题、基因频率题、细胞分裂图或实验数据图）。'),
      AiMessage('user',
          '识别这张图片里的生物题，只输出一个 JSON 对象，不要输出任何其他文字、'
          '不要代码块标记：\n'
          '{"summary":"题干要点+考点总结，不超过200字",'
          '"module":"模块标识",'
          '"params":{...}}\n'
          'module 取值：\n'
          '- cross_dihybrid：两对基因自由组合/9331 类，params={"p1":"AaBb","p2":"AaBb"}（亲本基因型，4字符）\n'
          '- cross_trihybrid：三对基因自由组合类，params={"p1":"AaBbCc","p2":"AaBbCc"}（6字符）\n'
          '- cross_mono：一对基因杂交类，params={"p1":"Aa","p2":"Aa"}（2字符）\n'
          '- molecular：DNA/中心法则类，params={"template":"模板链序列如ATCG"}\n'
          '- evolution：基因频率/哈迪温伯格类，params={"p":"0.8","q":"0.2"}\n'
          '- pedigree：系谱图/家族杂交题——用 actions 数组执行标准动作（见下），params 给空对象\n'
          '- cross_chromosomal_struct：染色体结构变异类（缺失/重复/倒位/易位），'
          '用 actions 数组高亮对应条目（见下），params 给空对象\n'
          '- disease_risk：人类遗传病风险类（伴 X/常染色体显隐），'
          '用 actions 数组设双亲基因型与显隐模式（见下），params 给空对象\n'
          '- pd_inference：给出家族系谱图、要求判断遗传方式的题——'
          '用 actions 数组逐个录入系谱成员（见下），params 给空对象\n'
          '- other：以上都不是（params 给空对象）\n'
          '【pd_inference 专用 actions 数组】（module=pd_inference 时使用，按世代顺序执行）：\n'
          '{"type":"add_member","id":"I1","sex":"male","status":"normal","father":"","mother":""}'
          '=录入一名成员（sex: male/female；status: normal/affected；father/mother 填'
          '已录入成员的 id，无则空字符串）；全部成员录完后系统自行推断遗传方式。\n'
          '【pedigree 专用 actions 数组】（module=pedigree 时使用，按顺序执行）：\n'
          '{"type":"create_family","father":"AaBb","mother":"AaBb"}=创建家族（父×母基因型）；'
          '{"type":"add_external","generation":1,"kind":"male","genotype":"Aa"}=添加样本（kind 为 male/female，generation 默认 1）；'
          '{"type":"next_generation"}=计算下一代。\n'
          '【cross_chromosomal_struct 专用 actions 数组】（module=cross_chromosomal_struct 时使用，按顺序执行）：\n'
          '{"type":"highlight_variant","variant":"缺失"}=高亮「缺失」条目（variant 取值：缺失/重复/倒位/易位）。\n'
          '【disease_risk 专用 actions 数组】（module=disease_risk 时使用，按顺序执行）：\n'
          '{"type":"set_parents","father":"XAY","mother":"XAXa","mode":"rec"}=设双亲基因型与模式'
          '（mode: rec=隐性/dom=显性；常染色体用 Aa/aa，伴 X 用 XAY/XAXa 等形式）。\n'
          '无法确定的参数填空字符串；基因型保持题目原文大小写。',
          imagePngBase64: img, imageMimeType: mime),
    ]);
    busy = false;
    _client = null;
    // v2.13 R3 P1-A1：ok = 本次识别成功（解析出结果并入库）。失败分支
    // 写 lastScanError 给拍题对话框弹 SnackBar——之前失败只进聊天
    // messages，而对话框不渲染聊天，断网/额度/解析失败对用户静默。
    var ok = false;
    if (res.ok) {
      final scan = parseScanReply(res.content);
      if (scan != null) {
        lastScan = scan;
        lastScanError = null;
        messages.add(AiChatMessage(
            'assistant', '${scan.summary}\n\n→ 识别为：${scanModuleLabel(scan.module)}',
            reasoning: res.reasoning));
        // 自动存入内置题库（下次同题免拍）；await 保证顺序确定（测试可断言）
        await ScanBankStore.add(ScanEntry(
          summary: scan.summary,
          module: scan.module,
          params: scan.params,
          actions: scan.actions,
          ts: DateTime.now().millisecondsSinceEpoch,
        ));
        ok = true;
      } else {
        // 模型没按 JSON 回：原文兜底展示，不入库
        lastScanError = '识别结果解析失败';
        messages.add(AiChatMessage('assistant', res.content,
            reasoning: res.reasoning));
      }
    } else if (res.error == '已打断') {
      // 打断是用户主动行为，不算失败：不写 lastScanError（对话框不弹条）
      messages.add(const AiChatMessage('assistant', '（已打断）'));
    } else {
      lastScanError = res.error ?? '识别失败';
      messages.add(AiChatMessage('assistant', res.error ?? '识别失败'));
    }
    // v2.19.57：结果卡/失败提示立刻上浮，然后才等落盘；
    // 返回的 Future 仍代表「本轮识别结果已写盘」——调用方 await 到底不变。
    notifyListeners();
    await _persistLogged();
    return ok;
  }

  /// AI 刷新：按当前页面状态生成 3 条建议问题（打断按钮同样可中止）。
  Future<void> refreshSuggestions() async {
    // v2.11 H5：守门——AI 回答/刷新中再点刷新 = 静默忽略（与 send 不同：
    // send 入队不丢消息；刷新重复只会浪费 token，无业务价值）。
    if (busy || refreshing) return;
    final config = await AiSettingsStore.load();
    if (!config.isConfigured) return;
    refreshing = true;
    busyLabel = 'AI 刷新中…';
    notifyListeners();

    // v2.11 H5：防御性 interrupt。
    _client?.interrupt();
    final sender = debugSender ??
        (List<AiMessage> msgs) {
          final client = AiClient(config);
          _client = client;
          return client.chat(msgs);
        };
    final snapshot = AppState.instance.buildSnapshot();
    final res = await sender([
      AiMessage('system',
          '你是高中生物遗传学解题助手，内嵌在「生物遗传计算平台」软件中。'
          '你能直接看到用户当前的软件状态：\n\n$snapshot'),
      const AiMessage('user',
          '基于我当前的软件状态，列出 3 个我此刻最适合问你的问题。'
          '严格要求：只输出一个 JSON 数组，格式 ["问题1","问题2","问题3"]，'
          '不要输出任何其他文字、不要加代码块标记；每条不超过 25 字。'),
    ]);
    refreshing = false;
    _client = null;
    if (res.ok) {
      final parsed = parseAiSuggestions(res.content);
      if (parsed.isNotEmpty) suggestions = parsed;
    }
    // 失败/已打断：保留旧建议
    notifyListeners();
  }

  /// 手动打断当前请求（幂等）。
  void interrupt() {
    _client?.interrupt();
    if (_client == null) {
      // 无活动连接（请求尚未建立/测试模拟态）：立即结束忙碌状态
      busy = false;
      refreshing = false;
      notifyListeners();
    }
  }

  /// 关闭拍题识别结果卡（v2.5）。
  void dismissScan() {
    lastScan = null;
    notifyListeners();
  }

  /// 本地刷新：内置题库随机抽 3 条建议（不消耗 AI）。
  void localRefresh() {
    final bank = List<String>.of(localQuestionBank)..shuffle(Random());
    suggestions = bank.take(3).toList();
    notifyListeners();
  }

  /// 测试用：清空内存状态（不动磁盘历史文件）。
  @visibleForTesting
  void reset() {
    messages.clear();
    suggestions = const [];
    queue.clear();
    busy = false;
    refreshing = false;
    lastScan = null;
    pendingCanvasImage = null;
    pendingScanImage = null;
    pendingScanMime = null;
    pendingScanName = null;
    _client = null;
    notifyListeners();
  }
}

/// 本地建议题库（R17/R22）：「本地刷新」从这里随机抽 3 条。
const localQuestionBank = [
  '我现在算的对不对？帮我检查一遍推导',
  '什么时候能用分解法，什么时候必须用配子法？',
  '把当前结果出成一道变式题考我',
  '9:3:3:1 的变式都有哪些？分别怎么识别？',
  '回交和自交在遗传计算里有什么区别？',
  '伴性遗传为什么常常交叉遗传？',
  '怎么用测交验证一个个体的基因型？',
  '自由组合定律的适用条件是什么？',
  '杂合子连续自交 n 代，后代杂合率怎么算？',
  '表型比例 1:1:1:1 说明双亲是什么基因型？',
  '连锁互换题里的交换值怎么算？',
  '为什么 F2 代会出现性状分离？',
  '概率计算里加法法则和乘法法则怎么选？',
  '帮我总结当前图谱里各代的比例规律',
  '让 F1 与隐性纯合子回交，后代比例是多少？',
];

/// 解析「AI 刷新」返回的建议问题（严格 JSON 数组，宽容解析）。
/// 失败/格式不对返回空列表（调用方保留旧建议）。
List<String> parseAiSuggestions(String raw) {
  final l = raw.indexOf('[');
  final r = raw.lastIndexOf(']');
  if (l < 0 || r <= l) return const [];
  try {
    final j = jsonDecode(raw.substring(l, r + 1));
    if (j is! List) return const [];
    final out = <String>[];
    for (final e in j) {
      final s = e?.toString().trim() ?? '';
      if (s.isEmpty) continue;
      out.add(s.length > 40 ? s.substring(0, 40) : s);
      if (out.length >= 3) break;
    }
    return out;
  } catch (_) {
    return const [];
  }
}

/// 从思维链的「【工具调用】」段取本轮用过的工具名（去重、保序、最多 5 个）。
///
/// 为什么解析文本而不改 AiClient：AiResult 被多处消费，为一个 UI 脚注
/// 扩返回结构不划算；足迹行形如 punnett_cross({...})，逐行取函数名即可。
List<String> toolNamesOf(String? reasoning) {
  if (reasoning == null || reasoning.isEmpty) return const [];
  final at = reasoning.indexOf('【工具调用】');
  if (at < 0) return const [];
  final re = RegExp(r'^(\w+)\(');
  final out = <String>[];
  for (final raw in reasoning.substring(at).split('\n')) {
    final name = re.firstMatch(raw.trim())?.group(1);
    if (name == null || out.contains(name)) continue;
    out.add(name);
    if (out.length >= 5) break; // 脚注只做信任提示，列满 5 个已足够
  }
  return out;
}

/// 回答正文末尾的「用了哪些工具」脚注。
///
/// 为什么：足迹只躺在 reasoning 里，思维链一收起，学生就分不清 3:1 是
/// 软件算的还是模型心算的。没有工具调用时**逐字返回原文**，不改动
/// 既有 golden 与断言。
String withToolFooter(String content, String? reasoning) {
  final names = toolNamesOf(reasoning);
  if (names.isEmpty) return content;
  return '$content\n\n（本条回答使用了工具：${names.join('、')}）';
}

/// v2.5 拍题识别结果；v2.9 扩展动作序列（AI 不只填参，还能让软件
/// 执行「创建家族/添加样本/计算下一代」等标准动作）。
class ScanResult {
  final String summary; // 题干要点+考点总结
  final String module; // 模块标识（见 scanModuleLabel）
  final Map<String, String> params; // 提取的填参参数（可为空）
  /// 标准动作序列（v2.9）：按序执行，每个动作 {"type":"...", ...}，
  /// 键值均为字符串。系谱页动作见 ModuleFillBus 的 pedigree 目标。
  final List<Map<String, String>> actions;
  const ScanResult({
    required this.summary,
    required this.module,
    required this.params,
    this.actions = const [],
  });
}

/// 模块标识 → 中文名（结果卡与题库列表展示用）。
String scanModuleLabel(String module) {
  switch (module) {
    case 'cross_dihybrid':
      return '遗传计算器·双基因';
    case 'cross_trihybrid':
      return '遗传计算器·三对基因';
    case 'cross_mono':
      return '遗传计算器·单基因';
    case 'molecular':
      return '分子页·中心法则';
    case 'evolution':
      return '进化页·基因频率';
    case 'pedigree':
      return '遗传图谱（可创建家族/元素）';
    case 'cross_chromosomal_struct':
      return '变异页·染色体结构变异';
    case 'disease_risk':
      return '遗传病页·风险计算';
    case 'pd_inference':
      return '系谱推断（判遗传方式）';
    default:
      return '其他题型（仅总结）';
  }
}

/// 宽容解析拍题识别回复：提取首个 JSON 对象，summary 缺失视为失败。
Map<String, String> _stringMap(dynamic j) {
  final out = <String, String>{};
  if (j is Map) {
    for (final e in j.entries) {
      final v = '${e.value}'.trim();
      if (v.isNotEmpty) out['${e.key}'] = v;
    }
  }
  return out;
}

ScanResult? parseScanReply(String raw) {
  final start = raw.indexOf('{');
  final end = raw.lastIndexOf('}');
  if (start < 0 || end <= start) return null;
  try {
    final j = jsonDecode(raw.substring(start, end + 1));
    if (j is! Map) return null;
    final summary = j['summary']?.toString().trim() ?? '';
    if (summary.isEmpty) return null;
    final module = j['module']?.toString().trim() ?? 'other';
    return ScanResult(
      summary: summary,
      module: module.isEmpty ? 'other' : module,
      params: _stringMap(j['params']),
      actions: _actionList(j['actions']),
    );
  } catch (_) {
    return null;
  }
}

/// 宽容解析 actions 数组：只保留含 "type" 键的对象，键值全字符串化。
List<Map<String, String>> _actionList(dynamic j) {
  if (j is! List) return const [];
  final out = <Map<String, String>>[];
  for (final e in j) {
    if (e is! Map) continue;
    final m = <String, String>{};
    for (final kv in e.entries) {
      final v = '${kv.value}'.trim();
      if (v.isNotEmpty) m['${kv.key}'] = v;
    }
    if ((m['type'] ?? '').isNotEmpty) out.add(m);
  }
  return out;
}

/// 一次落盘请求：[_persist] 入队时刻的**快照** + 它的完成句柄。
///
/// 快照存在 job 里而不是在写的时候回读 `messages`——这是「最后一次写必然
/// 等于最新状态」的另一个必要条件：入队序 = 状态序，执行序 = 入队序。
class _PersistJob {
  _PersistJob(this.snapshot);

  final List<Map<String, String>> snapshot;
  final Completer<void> done = Completer<void>();
}