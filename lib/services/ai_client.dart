// ai_client.dart —— OpenAI 兼容 API 客户端（纯 Dart，跨平台：桌面/安卓/Web）
//
//
// 能力：
//   - 读取 baseUrl + apiKey + 模型名（从 AiConfig 传入）
//   - 调用 /chat/completions（OpenAI 兼容格式，含多模态 image_url）
//   - 超时控制、错误信息归一化
//   - 基于 package:http（v2.0：自 dart:io HttpClient 迁移——Web 端无
//     dart:io，统一 http 客户端为 Web 上线铺地基）
//
// 用途：遗传计算中「难题叫 AI」的接入点（简单概率本地算、难题转 AI）。

import 'dart:async';
import 'dart:convert';

import 'package:cryptography/cryptography.dart' show Sha256;
import 'package:flutter/foundation.dart' show kReleaseMode, visibleForTesting;
import 'package:http/http.dart' as http;

/// AI 配置：BaseURL、API Key、模型名 + 通道标识。
///
/// v2.15 双通道（OpenCode 通道已移除，替换为 DeepSeek 官方 API）：
///   - DeepSeek（https://api.deepseek.com，deepseek-flash = V4.1-Flash
///     多模态，支持图片一键发送）——默认通道
///   - MiniMax（https://api.minimaxi.com/v1，MiniMax-M3.1-Flash
///     多模态）——保留通道（存量用户配置不受影响）
/// 通道选择在设置页完成并持久化（ai_config.json 的 provider 字段）。
///
/// 凭据口径：**源码不含任何 API key，仅支持 `--dart-define` 编译期注入**。
/// key 的来源按优先级：
///   1. **用户手填并落盘**（`ai_config.json`，本机 AES-256-GCM 加密，密钥
///      绑定本机特征）——最高优先。
///   2. **build 时 `--dart-define` 注入**（DeepSeek：`AI_API_KEY` /
///      `AI_BASE_URL` / `AI_MODEL`；MiniMax：`MINIMAX_API_KEY`；本地文件
///      `dart_defines.local.json` 已 gitignore）。
/// ⚠️ 风险如实记账：`String.fromEnvironment` 是 const 表达式，注入值会在
/// AOT 编译期**烤进二进制**，可被从安装包中提取——**release 同样能读到**。
/// 所以 `--dart-define` 不是安全存储，只适合开发者自己的本机构建与受控
/// 分发；仓库源码与构建产物里都没有明文可清理。
class AiConfig {
  final String baseUrl; // 默认 https://api.deepseek.com
  final String apiKey;
  final String model; // 默认 deepseek-flash（DeepSeek-V4.1-Flash）
  /// 通道标识：'deepseek'（默认）/ 'minimax'（保留）/ 'custom'。
  final String provider;

  static const String providerDeepSeek = 'deepseek';
  static const String providerMinimax = 'minimax';
  static const String providerCustom = 'custom';

  /// v2.15 存量迁移：旧版 provider 字面值 'opencode'（OpenCode 网关已
  /// 下线）映射到 DeepSeek 通道。
  static const String _legacyProviderOpenCode = 'opencode';

  /// build-time `--dart-define` 注入值（缺省空串）。
  ///
  /// ⚠️ 不是安全存储：`String.fromEnvironment` 是 const 表达式，AOT 编译会
  /// 把这些值**直接烤进二进制**，任何拿到安装包的人都能提取出来（release
  /// 也一样）。优点只有一个——key 不进源码仓库、不随 git 历史扩散。
  /// 正式路径始终是用户在设置页自填的**本机加密配置**；本组注入只服务
  /// 开发与内部受控构建（见仓库根 dart_defines.example.json）。
  static const String _envApiKey =
      String.fromEnvironment('AI_API_KEY', defaultValue: '');
  static const String _envBaseUrl =
      String.fromEnvironment('AI_BASE_URL', defaultValue: '');
  static const String _envModel =
      String.fromEnvironment('AI_MODEL', defaultValue: '');

  /// MiniMax 专用通道（`--dart-define=MINIMAX_API_KEY=...`）。
  /// 与泛用 `AI_API_KEY` 分开：MiniMax 通道的 key 与 DeepSeek 不通用，
  /// 泛用量保持原语义（只喂 DeepSeek 默认通道），互不串味。
  /// 缺省空串：源码不含任何 API key，只有 `--dart-define` 注入才有值。
  static const String _envMinimaxApiKey = String.fromEnvironment(
    'MINIMAX_API_KEY',
    defaultValue: '',
  );

  const AiConfig({
    this.provider = providerDeepSeek,
    // v2.11 H1 修订：保留 baseUrl/model/provider 默认值避免 widget
    // 渲染行为变化（golden screenshot 重录成本高）。仅 apiKey 默认空——
    // 真正泄露的资产是 apiKey，baseUrl/model 是公开信息。
    this.baseUrl = 'https://api.deepseek.com',
    this.apiKey = '',
    this.model = 'deepseek-flash',
  });

  /// v2.11 H1 工厂：组装「启动默认配置」。按优先级：
  ///
  ///   1. 有 `--dart-define` 注入的 MiniMax key → 直接返回 [presetMinimax]。
  ///      **debug 也走这条**：开发时与发布包行为同构，否则看不到实际会
  ///      遇到的通道。
  ///   2. **release**：取 `--dart-define` 的 DeepSeek 注入值
  ///      （`AI_API_KEY` / `AI_BASE_URL` / `AI_MODEL`）。没注入 → apiKey
  ///      空 → isConfigured=false → 设置页引导用户自填。
  ///   3. **debug**：可传 [presetOverride] 覆盖，否则 DeepSeek 预设（空 key）。
  /// 注意：注入值会烤进二进制、可从安装包提取（**release 也能读到**）——
  /// 不是安全存储，只适合开发者本机构建与受控分发。
  ///
  /// 调用方（`AiSettingsStore.load` / 用户手填 config）应优先用本工厂而非
  /// 直接 new AiConfig()，避免 release 误用空 apiKey。
  factory AiConfig.fromEnv({AiConfig? presetOverride}) {
    // 有 MiniMax key 就先把 MiniMax 当启动默认通道——不区分 debug/release：
    // 注入值在两端等价，开发时也应按真实通道跑。
    if (_envMinimaxApiKey.isNotEmpty) return presetMinimax;
    if (kReleaseMode) {
      return AiConfig(
        provider: providerDeepSeek,
        baseUrl: _envBaseUrl.isEmpty
            ? 'https://api.deepseek.com'
            : _envBaseUrl,
        apiKey: _envApiKey,
        model: _envModel.isEmpty ? 'deepseek-flash' : _envModel,
      );
    }
    return presetOverride ?? presetDeepSeek;
  }

  /// MiniMax 通道预设（M3.1 多模态）。
  ///
  /// apiKey 取 `MINIMAX_API_KEY`：只有 `--dart-define` 注入才有值，未注入
  /// 即空串（源码不含任何 key）。注入值是编译期常量、会烤进二进制，
  /// **不是**安全存储；用户在设置页自填的 key 优先。provider / baseUrl /
  /// model 是公开值。
  /// 模型名 = `MiniMax-M3.1-Flash`（官方 2026-10-19 发布：1M 上下文、
  /// 输出上限 524288、`reasoning_effort` 支持 low/medium/high/xhigh/max）。
  /// 旧名 `MiniMax-M3.1-Flash-Preview` 已列入 [retiredMinimaxModels]，
  /// 存量配置读回时自动迁移到本名。
  static const AiConfig presetMinimax = AiConfig(
    provider: providerMinimax,
    baseUrl: 'https://api.minimaxi.com/v1',
    apiKey: _envMinimaxApiKey,
    model: 'MiniMax-M3.1-Flash',
  );

  /// MiniMax 通道锁定的思考等级。
  ///
  /// M3.1 省略该字段时平台默认也是 max；这里显式写死，是为了不随平台
  /// 默认值漂移。产品口径：思考等级不可由用户在设置页调低。
  static const String minimaxReasoningEffort = 'max';

  /// v2.10 泄露到 installers APK 的旧共享 MiniMax key（已在
  /// platform.minimaxi.com 撤销）的 **SHA-256 指纹**（小写 hex）。
  ///
  /// 源码只留指纹、不留原文：存量 `ai_config.json` 里读到这把 key 时
  /// 必须换成 `MINIMAX_API_KEY` 注入值（注入值为空则清空），不能让已
  /// 撤销的凭据继续当运行时配置。比对入口 [isRetiredMinimaxKey]。
  /// 计算方式：`sha256(utf8(key))` 的 hex 串。
  static const String retiredMinimaxKeySha256 =
      '96b1a3d2743661f40d977aa0c020609ac76aed052dda30d38b006cdb31eb0b61';

  /// 测试注入：非空时 [isRetiredMinimaxKey] 改按明文比对——测试只能用
  /// 虚构 key（真实 key 不得写进测试），所以需要这条免哈希的旁路。
  @visibleForTesting
  static String? debugRetiredMinimaxKey;

  /// 测试注入：非空时 [minimaxApiKeyFromEnv] 返回它，用于覆盖
  /// 「env 有值 → 替换」「env 空 → 清空」两条迁移分支。
  @visibleForTesting
  static String? debugMinimaxApiKeyEnv;

  /// 测试专用：清掉上面两个注入 hook。
  @visibleForTesting
  static void debugResetKeyHooks() {
    debugRetiredMinimaxKey = null;
    debugMinimaxApiKeyEnv = null;
  }

  /// `--dart-define=MINIMAX_API_KEY` 的运行期读取入口（测试可注入）。
  static String get minimaxApiKeyFromEnv =>
      debugMinimaxApiKeyEnv ?? _envMinimaxApiKey;

  /// 判定 [key] 是否仍是那把已撤销的旧共享 key。
  ///
  /// 走 SHA-256 指纹比对（`cryptography` 的 [Sha256] 在 VM / Web 都有
  /// 实现，故为异步）。原文不存在于源码，比对失败也不会泄露任何信息。
  static Future<bool> isRetiredMinimaxKey(String key) async {
    if (key.isEmpty) return false;
    final injected = debugRetiredMinimaxKey;
    if (injected != null) return injected == key;
    final digest = await Sha256().hash(utf8.encode(key));
    final hex = digest.bytes
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();
    return hex == retiredMinimaxKeySha256;
  }

  /// v2.19.67：MiniMax 通道已下线的模型名（M3 全系）。存量配置命中
  /// 即迁移到 [presetMinimax]（M3.1-Flash）。
  static const List<String> retiredMinimaxModels = [
    'MiniMax-M3',
    'MiniMax-M3.1', // 该字面值平台不认（2026-10-25 实测 400），仅防手滑
    'MiniMax-M3.1-Flash-Preview', // 预览名已转正为 MiniMax-M3.1-Flash
  ];

  /// DeepSeek 官方 API 预设（v2.15 默认通道）。
  /// 模型 deepseek-flash = DeepSeek-V4.1-Flash：多模态（Vision ✓，
  /// 拍题/截图可一键发图）、1M 上下文、思考/非思考双模式。
  /// apiKey 留空——DeepSeek 无预置 key，用户在设置页自填
  ///（platform.deepseek.com 申请）；isConfigured=false 时设置页引导。
  /// v2.15：替代已移除的 OpenCode 融合网关（其预置 key 随通道一并删除）。
  static const AiConfig presetDeepSeek = AiConfig(
    provider: providerDeepSeek,
    baseUrl: 'https://api.deepseek.com',
    apiKey: '',
    model: 'deepseek-flash',
  );

  /// 按通道标识取预设；custom/未知返回 null（保留用户手填值）。
  /// v2.15 迁移：旧 'opencode' 字面值映射到 DeepSeek 预设。
  static AiConfig? presetOf(String provider) {
    switch (provider) {
      case providerMinimax:
        return presetMinimax;
      case providerDeepSeek:
      case _legacyProviderOpenCode:
        return presetDeepSeek;
      default:
        return null;
    }
  }

  /// v2.11 H3：BaseURL 强校验 https 方案。修复旧实现仅校验
  /// `startsWith('http')`——同时接受明文 http://（API key 裸奔）和
  /// 非 URL 字符串（任何 `http` 开头的乱码都通过）。SSRF 与内网
  /// 拒绝在 [validateBaseUrl] 静态方法中做。
  bool get isConfigured {
    if (apiKey.isEmpty || baseUrl.isEmpty) return false;
    final uri = Uri.tryParse(baseUrl);
    if (uri == null) return false;
    if (uri.scheme != 'https') return false;
    return true;
  }

  /// v2.11 H3：SSRF 校验。设置页 BaseURL 输入框失焦时调，错误时
  /// 显示红色提示 + 阻止保存。返回 null = 通过；非 null = 错误原因。
  static const _blockedHosts = {
    'localhost', '127.0.0.1', '0.0.0.0',
    // ::1（IPv6 loopback）由 RegExp 兜底
  };

  /// 内网/私有 IP 段正则：
  /// - 10.0.0.0/8（10.*）
  /// - 172.16.0.0/12（172.16-31.*）
  /// - 192.168.0.0/16（192.168.*）
  static final RegExp _privateIpRe =
      RegExp(r'^(10\.|172\.(1[6-9]|2[0-9]|3[01])\.|192\.168\.|127\.)');

  static String? validateBaseUrl(String input) {
    final trimmed = input.trim();
    if (trimmed.isEmpty) return 'URL 不能为空';
    final uri = Uri.tryParse(trimmed);
    if (uri == null) return 'URL 格式错误';
    if (uri.scheme != 'https') {
      return '必须使用 https://（明文 HTTP 会泄露 API key + 聊天内容）';
    }
    final host = uri.host.toLowerCase();
    if (host.isEmpty) return 'URL 必须含域名或 IP';
    if (_blockedHosts.contains(host)) return '不允许内网/本机地址';
    if (_privateIpRe.hasMatch(host)) return '不允许内网 IP';
    return null;
  }

  AiConfig copyWith(
      {String? baseUrl, String? apiKey, String? model, String? provider}) {
    return AiConfig(
      baseUrl: baseUrl ?? this.baseUrl,
      apiKey: apiKey ?? this.apiKey,
      model: model ?? this.model,
      provider: provider ?? this.provider,
    );
  }
}

/// 聊天消息。
class AiMessage {
  final String role; // system / user / assistant
  final String content;
  /// v3.5 多模态：图片的 base64（不含 data: 前缀）。非空时
  /// chat() 把 content 序列化为 OpenAI 多模态数组
  /// （[{type:text},{type:image_url,url:data:<mime>;base64,...}]）。
  final String? imagePngBase64;
  /// v2.5 拍题识别：图片 MIME（默认 image/png；相册 JPEG 用 image/jpeg）。
  final String imageMimeType;
  const AiMessage(this.role, this.content,
      {this.imagePngBase64, this.imageMimeType = 'image/png'});
}

/// AI 响应结果。
class AiResult {
  final bool ok;
  final String content; // 成功时的助手回复
  final String? error; // 失败时的错误信息
  final String? reasoning; // R22：思维链（默认折叠展示，可为空）

  const AiResult.ok(this.content, {this.reasoning})
      : ok = true,
        error = null;
  const AiResult.fail(this.error)
      : ok = false,
        content = '',
        reasoning = null;

  @override
  String toString() => ok ? content : 'AI错误: $error';
}

/// v2.24 工具调用循环：单轮请求的内部结果。
///
/// 公开的 [AiResult] 语义保持不变（content / reasoning / ok / error 的名字与
/// 含义不动）；tool_calls 与正文原文只在本文件内流转，不出客户端。
class _PostResult {
  final bool ok;
  final String content;
  final String? error;
  final String? reasoning;

  /// 原样透传的 `message.tool_calls`（非空表示模型要求调工具）。
  final List<dynamic>? toolCalls;

  /// 本轮正文原文（回填 assistant 回合用；纯工具回合可能为空串）。
  final String? rawContent;

  const _PostResult.ok(this.content,
      {this.reasoning, this.toolCalls, this.rawContent})
      : ok = true,
        error = null;
  const _PostResult.fail(this.error)
      : ok = false,
        content = '',
        reasoning = null,
        toolCalls = null,
        rawContent = null;
}

/// 凭据形状识别（**只描述形状，不含任何真实密钥**）。
///
/// 顺序敏感：先处理 URL query，再处理 Authorization 头，最后处理裸 token。
final RegExp _querySecretRe = RegExp(
  r'([?&](?:api[_-]?key|apikey|key|token|access[_-]?token|secret|password)=)([^&\s"#]+)',
  caseSensitive: false,
);
final RegExp _bearerRe = RegExp(
  r'(bearer\s+)([A-Za-z0-9._~+/=-]{8,})',
  caseSensitive: false,
);
final RegExp _bareTokenRe = RegExp(r'sk-[A-Za-z0-9_\-]{8,}');

/// 统一敏感信息脱敏（v2.20.0）。
///
/// 错误文本会进 UI 提示、日志和测试快照；上游（网关 / 代理 / 服务端）
/// 偶尔把 `Authorization` 头、URL query 或 key 片段回显进
/// `error.message` / 响应 body，那等于把凭据抄进聊天记录。凡是经
/// [AiResult] 离开客户端的错误字符串都先过这里：
///   - `…?api_key=<值>` / `?key=` / `?token=` 等 query → 值换成 `***`
///   - `Authorization: Bearer <token>` → `Bearer ***`
///   - `sk-…` 形态的长 token → `sk-***`
///
/// 只抹凭据本身：状态码、原因文本、模型名、错误码都保留（排障不能瞎）。
/// 超长文本截断，避免把整页 HTML 塞进提示条。
String redactSensitive(String input, {int maxLength = 1000}) {
  if (input.isEmpty) return input;
  var s = input.replaceAllMapped(_querySecretRe, (m) => '${m[1]}***');
  s = s.replaceAllMapped(_bearerRe, (m) => '${m[1]}***');
  s = s.replaceAll(_bareTokenRe, 'sk-***');
  if (s.length > maxLength) {
    s = '${s.substring(0, maxLength)}…(已截断，原文 ${input.length} 字符)';
  }
  return s;
}

/// OpenAI 兼容客户端。
class AiClient {
  final AiConfig config;
  final Duration timeout;

  /// 当前活动请求的 http.Client（R22 打断：interrupt 关闭它以中止/忽略
  /// 进行中的请求——Web 端 XHR 无法强制终止，靠标记忽略结果）。
  http.Client? _active;

  /// R22 打断标记：interrupt() 置位后，被终止的请求返回「已打断」。
  bool _interrupted = false;

  /// 测试注入：非空时 [chat] 用它代替真实 http.Client。
  /// 用途 = 离线钉住错误分支（状态码归一化 + 脱敏），绝不联网。
  @visibleForTesting
  static http.Client Function()? debugHttpClientFactory;

  // 默认 120s：拍题/问 AI 涉及图片上传与大段题干，高峰延迟波动大，
  // 30s 会误报「请求超时」；真实遗传题推导约 10~30s，留足余量。
  AiClient(this.config, {this.timeout = const Duration(seconds: 120)});

  /// R22 打断进行中的请求（幂等；无活动请求时仅置标记）。
  void interrupt() {
    _interrupted = true;
    _active?.close();
  }

  /// 发送一轮对话（简单多轮）。
  ///
  /// v2.24：可选工具调用循环。`tools` / `onToolCall` 缺省或为空时完全走
  /// 原来的单轮路径——请求体与解析逐字不变，存量调用方零影响。
  Future<AiResult> chat(
    List<AiMessage> messages, {
    List<Map<String, dynamic>>? tools,
    Future<String> Function(String name, Map<String, dynamic> arguments)?
        onToolCall,
    int maxRounds = 3,
  }) async {
    if (!config.isConfigured) {
      return const AiResult.fail('未配置 API：请先在「设置」页填入 BaseURL 和 API Key。');
    }
    _interrupted = false;
    final client = (debugHttpClientFactory ?? http.Client.new)();
    _active = client;
    try {
      final wire = messages.map(_wireMessage).toList();
      if (tools == null || tools.isEmpty || onToolCall == null) {
        final res = await _post(client, wire, null);
        return res.ok
            ? AiResult.ok(res.content, reasoning: res.reasoning)
            : AiResult.fail(res.error);
      }
      // v2.24 工具循环：模型要工具 → 本地执行 → role=tool 回填 → 再请求。
      final trace = <String>[];
      for (var round = 0; round < maxRounds; round++) {
        final res = await _post(client, wire, tools);
        if (!res.ok) {
          return AiResult.fail(res.error); // 错误/打断原样返回
        }
        final calls = res.toolCalls;
        if (calls == null || calls.isEmpty) {
          // 工具足迹接在思维链之后；没有思维链时不凭空加空行。
          var reasoning = res.reasoning;
          if (trace.isNotEmpty) {
            final head = (reasoning == null || reasoning.isEmpty)
                ? ''
                : '$reasoning\n\n';
            reasoning = '$head【工具调用】\n${trace.join('\n')}';
          }
          return AiResult.ok(res.content, reasoning: reasoning);
        }
        // v2.24 修复：最后一轮不再执行工具。执行了也没机会把结果回给模型，
        // 只会让用户在确认框里点过「继续」的 run_python / run_shell 白跑一次。
        if (round == maxRounds - 1) {
          final planned = <String>[];
          for (final c in calls) {
            final fn = c is Map ? c['function'] : null;
            final n = fn is Map ? (fn['name']?.toString() ?? '') : '';
            if (n.isNotEmpty) planned.add(n);
          }
          return AiResult.fail('工具调用轮次用尽（$maxRounds 轮）：'
              '模型最后一轮仍想调用 ${planned.isEmpty ? '工具' : planned.join('、')}');
        }
        // 回填 assistant 回合：工具回合正文常为空，tool_calls 原样带回。
        wire.add({
          'role': 'assistant',
          'content': res.rawContent ?? '',
          'tool_calls': calls,
        });
        for (var i = 0; i < calls.length; i++) {
          final call = calls[i];
          final fn = call is Map ? call['function'] : null;
          final name = fn is Map ? (fn['name']?.toString() ?? '') : '';
          final rawArgs = fn is Map ? fn['arguments'] : null;
          trace.add('$name(${_summarizeArgs(rawArgs)})');
          String out;
          try {
            out = await onToolCall(name, _parseToolArgs(rawArgs));
          } catch (e) {
            // 工具异常不回传原始异常链（可能带本机路径/凭据），先脱敏。
            out = '工具执行失败：${redactSensitive('$e', maxLength: 200)}';
          }
          if (out.length > 4000) {
            out = '${out.substring(0, 4000)}…(已截断)';
          }
          final id = call is Map ? call['id']?.toString() : null;
          wire.add({
            'role': 'tool',
            'tool_call_id': id ?? 'call_$i', // 缺 id 的网关：序号兜底
            'content': out,
          });
        }
      }
      return AiResult.fail('工具调用轮次用尽（$maxRounds 轮）');
    } finally {
      _active = null;
      client.close();
    }
  }

  /// v2.24：单轮请求——组装 body → post → 解析 200 / 非 200 / 异常。
  ///
  /// 自改前的 [chat] 逐字搬运；工具循环把 assistant / tool 回合追加进
  /// [wire] 后重复调用。client 由 [chat] 持有并统一关闭，所以 [interrupt]
  /// 关掉它以后，下一轮请求会抛异常，落到 catch 的 `_interrupted` 分支
  /// 归一为「已打断」。
  Future<_PostResult> _post(
    http.Client client,
    List<Map<String, dynamic>> wire,
    List<Map<String, dynamic>>? tools,
  ) async {
    try {
      final url = Uri.parse('${_trimSlash(config.baseUrl)}/chat/completions');
      final body = jsonEncode({
        'model': config.model,
        // MiniMax 通道：思考等级锁 max（M3.1 省略该字段默认也是 max，
        // 显式写入只为不随平台默认值漂移）。其它通道不带此字段。
        if (config.provider == AiConfig.providerMinimax)
          'reasoning_effort': AiConfig.minimaxReasoningEffort,
        'messages': wire,
        // v2.24：仅在真带工具时出现；默认路径请求体逐字不变。
        if (tools != null && tools.isNotEmpty) ...{
          'tools': tools,
          'tool_choice': 'auto',
        },
      });
      final res = await client
          .post(
            url,
            headers: {
              'Content-Type': 'application/json; charset=utf-8',
              'Authorization': 'Bearer ${config.apiKey}',
            },
            body: body,
          )
          .timeout(timeout);
      final resBody = res.body;
      if (res.statusCode == 200) {
        final json = jsonDecode(resBody) as Map<String, dynamic>;
        final choices = json['choices'] as List?;
        if (choices == null || choices.isEmpty) {
          return const _PostResult.fail('API 返回空响应');
        }
        final msg = (choices.first as Map<String, dynamic>)['message']
            as Map<String, dynamic>?;
        // 部分模型（如带推理的 mimo）content 可能为 null 或分段数组，做归一化
        final raw = msg?['content'];
        String content;
        if (raw is List) {
          content = raw
              .map((e) =>
                  e is Map ? (e['text']?.toString() ?? '') : e.toString())
              .join();
        } else {
          content = raw?.toString() ?? '';
        }
        // R22：思维链（reasoning）独立提取（可能与 content 同现），
        // 归一化拼接；content 为空时回退用它顶替正文。
        // v2.15：DeepSeek 思考模式把思维链放在 reasoning_content 字段
        // （OpenAI 生态无统一键名）——两级回退都读。
        final rawR = msg?['reasoning'] ?? msg?['reasoning_content'];
        String? reasoning;
        if (rawR is List) {
          final parts = rawR
              .map((e) =>
                  e is Map ? (e['text']?.toString() ?? '') : e.toString())
              .where((s) => s.isNotEmpty)
              .toList();
          if (parts.isNotEmpty) reasoning = parts.join();
        } else if (rawR is String && rawR.isNotEmpty) {
          reasoning = rawR;
        }
        // v2.2：MiniMax-M3/M3.1 等推理模型把 <think>...</think> 内联在
        // content 里——剥离为思维链，正文只留最终回答。
        final sp = splitThink(content);
        if (sp.$2 != null) {
          content = sp.$1;
          reasoning = reasoning == null ? sp.$2 : '$reasoning\n${sp.$2}';
        }
        // v2.24：工具调用回合常常没有正文——先判 tool_calls 再判空。
        final tc = msg?['tool_calls'];
        if (tc is List && tc.isNotEmpty) {
          return _PostResult.ok(content,
              reasoning: reasoning, toolCalls: tc, rawContent: content);
        }
        if (content.isEmpty && reasoning != null) {
          content = reasoning;
          reasoning = null; // 正文即思维链时不再重复折叠展示
        }
        if (content.isEmpty) {
          return const _PostResult.fail('API 返回了空内容');
        }
        return _PostResult.ok(content, reasoning: reasoning);
      } else {
        // 归一化常见错误
        final err = _normalizeError(res.statusCode, resBody);
        return _PostResult.fail(err);
      }
    } catch (e) {
      if (_interrupted) return const _PostResult.fail('已打断');
      // v2.13 UI 走查 P0：网络层异常不许裸露技术字符串（课堂断网时
      // 老师/学生看到「SocketException: Failed host lookup...」会懵）。
      // 按类型名匹配（不 import dart:io，Web 端同样生效）映射成人话。
      // v2.20.0：其余异常文本先脱敏（异常链里可能带 Authorization 头 /
      // 请求 URL 的 query）再截断，避免凭据经错误提示外泄。
      final tech = e.toString();
      if (tech.contains('SocketException') ||
          tech.contains('ClientException') ||
          tech.contains('TimeoutException') ||
          tech.contains('Failed host lookup')) {
        return const _PostResult.fail('网络连接失败，请检查网络后重试');
      }
      return _PostResult.fail(redactSensitive('请求失败：$e'));
    }
  }

  /// 一次性问答（便捷方法）。
  Future<AiResult> ask(String prompt) async {
    return chat([
      const AiMessage('system',
          '你是一个高中生物遗传学解题助手。请准确、简洁地解答遗传学问题，涉及基因型、表型、概率、9331变式时给出清晰推导。用中文回答。'),
      AiMessage('user', prompt),
    ]);
  }

  /// 剥离内联思维链：MiniMax-M3/M3.1 等推理模型把 `<think>...</think>`
  /// 直接放在 content 里（而非独立的 reasoning 字段）。
  /// 返回 (正文, 思维链)；无 think 标签时思维链为 null。
  /// 未闭合的 `<think>`（流式截断）其后内容全部视为思维链。
  static (String, String?) splitThink(String content) {
    if (!content.contains('<think>')) return (content, null);
    final body = StringBuffer();
    final think = StringBuffer();
    var rest = content;
    while (true) {
      final s = rest.indexOf('<think>');
      if (s < 0) {
        body.write(rest);
        break;
      }
      body.write(rest.substring(0, s));
      final e = rest.indexOf('</think>', s + 7);
      if (e < 0) {
        think.write(rest.substring(s + 7));
        break;
      }
      think.write(rest.substring(s + 7, e));
      rest = rest.substring(e + 8);
    }
    final b = body.toString().trim();
    final t = think.toString().trim();
    return (b, t.isEmpty ? null : t);
  }

  /// v2.24：AiMessage → wire 消息（与改前请求体内联 map 逐字同构）。
  static Map<String, dynamic> _wireMessage(AiMessage m) {
    if (m.imagePngBase64 == null) {
      return {'role': m.role, 'content': m.content};
    }
    // v3.5 多模态：图片附在用户消息
    return {
      'role': m.role,
      'content': [
        {'type': 'text', 'text': m.content},
        {
          'type': 'image_url',
          'image_url': {
            'url': 'data:${m.imageMimeType};base64,${m.imagePngBase64}'
          }
        },
      ],
    };
  }

  /// v2.24：工具参数归一——JSON 字符串、直接给的对象、空串、坏 JSON 都能吃。
  static Map<String, dynamic> _parseToolArgs(Object? raw) {
    Object? v = raw;
    if (v is String) {
      if (v.trim().isEmpty) return <String, dynamic>{};
      try {
        v = jsonDecode(v);
      } catch (_) {
        return <String, dynamic>{};
      }
    }
    if (v is! Map) return <String, dynamic>{};
    return {for (final e in v.entries) e.key.toString(): e.value};
  }

  /// v2.24：工具足迹——参数压成单行、截断 80 字（写进思维链展示）。
  static String _summarizeArgs(Object? rawArgs) {
    final s = rawArgs is String
        ? rawArgs
        : (rawArgs == null ? '' : jsonEncode(rawArgs));
    final one = s.replaceAll(RegExp(r'\s+'), ' ').trim();
    return one.length > 80 ? '${one.substring(0, 80)}…' : one;
  }

  String _trimSlash(String s) => s.endsWith('/') ? s.substring(0, s.length - 1) : s;

  /// 错误归一化。v2.20.0：reason 与 body 都先过 [redactSensitive]——
  /// 上游报错文本经常回显请求细节（`Incorrect API key provided: sk-…`、
  /// 带 query 的 URL），直接拼进提示就等于二次泄露；脱敏只抹凭据，
  /// 状态码/原因/错误码保留。
  String _normalizeError(int status, String body) {
    String reason = '';
    try {
      final j = jsonDecode(body);
      if (j is Map && j['error'] is Map) {
        final e = j['error'] as Map;
        reason = e['message']?.toString() ?? reason;
      }
    } catch (_) {}
    reason = redactSensitive(reason, maxLength: 300);
    final safeBody = redactSensitive(body);
    // Cloudflare WAF 拦截（如 error code: 1010）不是 key 问题，单独提示
    if (status == 403 && safeBody.contains('error code: 10')) {
      return '403: 网关防护拦截（Cloudflare），请稍后重试。';
    }
    switch (status) {
      case 401:
        return '401: API Key 无效或已过期。$reason';
      case 403:
        return '403: 无权限（配额不足或模型不可用）。$reason';
      case 404:
        return '404: 接口或模型不存在（检查 BaseURL 是否含 /v1、模型名是否正确）。$reason';
      case 429:
        return '429: 请求过于频繁或额度用尽。$reason';
      default:
        return '$status: $reason${reason.isEmpty ? safeBody : ''}';
    }
  }
}
