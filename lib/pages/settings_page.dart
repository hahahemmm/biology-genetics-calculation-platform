import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show kReleaseMode;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;

import '../storage/platform_storage_io.dart'
    if (dart.library.html) '../storage/platform_storage_web.dart';

import '../services/ai_client.dart';
import '../guide/guide_controller.dart';
import '../guide/guide_keys.dart';
import '../services/local_secure_store.dart';
import '../state/first_run_store.dart';
import '../state/present_mode_controller.dart';
import '../state/theme_controller.dart';
import '../theme.dart';
import '../ui/mode_switcher.dart';
// v2.24：多档案与整机打包/恢复、AI 工具开关两节（独立 widget，避免本文件继续膨胀）
import 'widgets/account_data_section.dart';
import 'widgets/ai_tools_section.dart';


/// 设置页：配置 OpenAI 兼容 API（BaseURL + API Key + 模型名）。
/// 难度大的遗传题将调用此 AI；简单概率本地计算。
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key, this.navCollapsed = false, this.onNavPressed});

  /// v3.3 侧栏折叠联动（HomeShell 注入）；独立构造时不渲染 ☰。
  final bool navCollapsed;
  final VoidCallback? onNavPressed;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

/// 本地配置存储（桌面/安卓 File；Web localStorage——条件导入）。
///
/// v2.12 R1 C P0 #7 修复：原 `_dir()` 用 `Platform.environment['USERPROFILE']`
/// + `Directory(...)` 直接拼路径在 Web 端 build 成功但运行时 File 构造
/// 抛 UnimplementedError，被 catch 吞掉 → 桌面/安卓分支代码即便走
/// try-catch 也潜在隐患。改用 `userAppDir()` 中性 API（platform_storage
/// 条件导入：桌面/安卓返真实路径，Web 返 null），Web 端走 localStorage
/// 不会调到 `_dir()`。同时加 `debugFilePath` / `debugWebStorage` /
/// `debugForceIsWebStorage` 三个测试 hook（同 FirstRunStore / AppState
/// / ThemeController / PresentModeController 范式），让 flutter_test 无
/// window 对象时也能验证 web round-trip 链路。
class AiSettingsStore {
  /// 测试注入：非空时 load() 直接返回该配置，不读盘（防测试走真实网络）。
  static AiConfig? debugConfig;

  /// 测试注入：非空时 load / save 走该文件而非用户目录。
  @visibleForTesting
  static String? debugFilePath;

  /// 测试注入：mock Web 端 localStorage。flutter_test 无 window 对象
  /// （`package:web` 的 `localStorage` 不可用），此 hook 让
  /// `test/settings_page_test.dart` 能验证 web 端 round-trip
  /// 链路（save 写 localStorage → load 读回 → config 一致）。
  @visibleForTesting
  static Map<String, String>? debugWebStorage;

  /// 测试注入：mock `isWebStorage` 标志。非空时强制走 web / desktop 路径。
  /// 配合 `debugWebStorage` 模拟"用户在浏览器中"的完整链路。
  @visibleForTesting
  static bool? debugForceIsWebStorage;

  /// 当前是否走 web 存储路径（test hook 优先于真实 isWebStorage）。
  static bool get _isWebStorage => debugForceIsWebStorage ?? isWebStorage;

  /// localStorage key。Web 端 load / save 走 storageGet / storageSet。
  static const String _webKey = 'ai_config_json';

  /// 桌面 / 安卓路径：`<userAppDir>/ai_config.json`。
  /// 注入的 debugFilePath 优先（同 FirstRunStore / AppState 等）。
  /// Web 端走 storageGet / storageSet，不会调到此处。
  static String _file() {
    if (debugFilePath != null) return debugFilePath!;
    final appDir = userAppDir();
    if (appDir == null) return 'ai_config.json'; // Web 兜底占位（实际不会走）
    final dir = Directory(appDir);
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return '${dir.path}/ai_config.json';
  }

  /// 存量配置迁移：无 provider 字段时按 baseUrl 推断通道。
  /// v2.15：旧 OpenCode 网关地址/标识统一识别为 DeepSeek 通道
  ///（网关已下线，provider 字面值 'opencode' 在 _fromJson 落到
  /// presetOf 迁移）。
  static String _detectProvider(Map<String, dynamic> j) {
    final p = j['provider']?.toString();
    if (p != null && p.isNotEmpty) return p;
    final b = j['baseUrl']?.toString() ?? '';
    if (b.contains('minimaxi')) return AiConfig.providerMinimax;
    if (b.contains('deepseek')) return AiConfig.providerDeepSeek;
    return AiConfig.providerCustom;
  }

  /// 存量配置迁移（v2.20.0 修订）。
  ///
  /// MiniMax 通道三条规则（**互不误伤**，async 因为旧 key 走 SHA-256 比对）：
  ///   ① 退役模型名（`retiredMinimaxModels`，**大小写不敏感**；空模型名
  ///      同样按「未指定」处理）→ 一律更新为 presetMinimax.model；
  ///      用户有效的 apiKey / baseUrl **原样保留**（自填 key 是用户资产）。
  ///   ② 命中已撤销的旧共享 key（[AiConfig.isRetiredMinimaxKey]）→ **只**
  ///      用 `MINIMAX_API_KEY`（`--dart-define`）注入值替换；注入值为空则
  ///      清空 key（已撤销的凭据不得继续当运行时配置）。
  ///   ③ 内置通道存在（[AiConfig.minimaxApiKeyFromEnv] 非空）且 key 为空
  ///      → 补上内置 key，**只在内存生效、不写盘**。
  /// 用户自己填过的 key 一律原样保留、绝不覆盖（以上三条都不得覆盖它）。
  /// 其余通道（DeepSeek / custom）：key 为空 + 内置通道存在 + baseUrl 仍是
  /// 该通道预设地址（没被改成第三方）→ 整份回落 [AiConfig.presetMinimax]。
  /// 为什么整份换而不是只塞 key：MiniMax key 留在 DeepSeek 地址上打不通，
  /// 发到用户自填的第三方地址则是把内置凭据泄露出去。用户改过 baseUrl 的
  /// 配置保持「未配置」等他自己填 key——不覆盖任何已填字段。
  static Future<AiConfig> _fromJson(Map<String, dynamic> j) async {
    final provider = _detectProvider(j);
    final model = j['model']?.toString() ?? '';
    final storedKey = j['apiKey']?.toString() ?? '';
    final storedBaseUrl = j['baseUrl']?.toString() ?? '';

    if (provider == AiConfig.providerMinimax) {
      final modelRetired =
          model.isEmpty ||
          AiConfig.retiredMinimaxModels.any(
            (m) => m.toLowerCase() == model.toLowerCase(),
          );
      var key = storedKey;
      if (await AiConfig.isRetiredMinimaxKey(key)) {
        key = AiConfig.minimaxApiKeyFromEnv;
      }
      // 空 key → 补内置 key：老师开箱即可用；只在内存生效，不写盘。
      if (key.isEmpty) key = AiConfig.minimaxApiKeyFromEnv;
      return AiConfig(
        provider: provider,
        baseUrl: storedBaseUrl.isEmpty
            ? AiConfig.presetMinimax.baseUrl
            : storedBaseUrl,
        apiKey: key,
        model: modelRetired ? AiConfig.presetMinimax.model : model,
      );
    }
    // 空 key + 内置通道存在 → 整份回落，别把内置 key 拼到别的通道上。
    final presetBaseUrl = AiConfig.presetOf(provider)?.baseUrl;
    final customBaseUrl =
        storedBaseUrl.isNotEmpty && storedBaseUrl != presetBaseUrl;
    if (storedKey.isEmpty &&
        !customBaseUrl &&
        AiConfig.minimaxApiKeyFromEnv.isNotEmpty) {
      // 与 _restoreBuiltin 同一取 key 口径（dart-define 注入可覆盖内置值）。
      return AiConfig.presetMinimax
          .copyWith(apiKey: AiConfig.minimaxApiKeyFromEnv);
    }
    return AiConfig(
      provider: provider,
      baseUrl: storedBaseUrl,
      apiKey: storedKey,
      model: model.isNotEmpty
          ? model
          : (AiConfig.presetOf(provider)?.model ?? 'deepseek-flash'),
    );
  }

  /// v2.0 Web 化：Web 端 localStorage（settings_storage_web），
  /// 桌面/安卓维持 File（兼容 ~/.biology_app/ai_config.json 存量配置）。
  ///
  /// v2.11 H1：用户手填配置优先（_fromJson 解析 ai_config.json），
  /// 无配置时 fallback 到 [AiConfig.fromEnv] 工厂——有 `--dart-define` 注入
  /// 的 MiniMax key 时一律回 MiniMax 通道（debug/release 同构）；没有注入时
  /// release 走注入值、debug 回落 DeepSeek 预设（空 key）。
  /// 源码不含任何 key，凭据只能由用户手填或编译期注入。
  ///
  /// v2.12 R1 C P0 #7 修复：load / save 走 `_isWebStorage` 分支 + debug
  /// hook（debugWebStorage / debugForceIsWebStorage），与 save 对称。
  ///
  /// 本机透明加密：桌面/安卓分支改走 `LocalSecureStore`——
  /// `ai_config.json` 路径不变，但内容变成 AES-256-GCM envelope（密钥绑定
  /// 本机特征），「打开文件即见明文 key」不再成立。存量明文由
  /// `readSecure` 嗅探后原样返回（下次 save 自动升级为密文），解不开 /
  /// 文件缺失时按既有语义回落 [AiConfig.fromEnv]，不影响启动。
  static Future<AiConfig> load() async {
    if (debugConfig != null) return debugConfig!;
    try {
      // v2.20.0：_fromJson 因旧 key 指纹比对而异步——两个分支都必须
      // await（`return await` 而不是 `return future`）：否则解析异常会
      // 绕过本方法的 catch，9/25「解密失败异常外泄」的事故形态会复活。
      if (_isWebStorage) {
        final webRaw = _storageGet(_webKey);
        if (webRaw == null) return AiConfig.fromEnv();
        return await _fromJson(jsonDecode(webRaw) as Map<String, dynamic>);
      }
      // readSecure：envelope → 解密；加密改造之前的旧明文 JSON → 原样返回。
      final raw = await LocalSecureStore.readSecure(_file());
      final cfg = await _fromJson(jsonDecode(raw) as Map<String, dynamic>);
      // 惰性升级：若磁盘上仍是旧明文，后台补一次加密写，下次进入读到的就是
      // 密文。故意不 await（fire-and-forget）——helper 内部判重（已密文 /
      // 透传模式则跳过）并吞掉所有异常，绝不影响本次返回。
      // 竞态护栏：把 load 读到的**原始字节** raw 作为 expectedRaw 传进去做
      // compare-and-swap。加密要等一次 PBKDF2，这期间同 isolate 的别的写者
      // （典型：v2.15 opencode→DeepSeek 迁移的那次 save）可能已经写过同一
      // 文件；没有这个 CAS，后台升级就会拿 load 时刻的过期明文把新配置覆盖回去。
      unawaited(LocalSecureStore.upgradeIfLegacyPlaintext(_file(), raw,
          expectedRaw: raw));
      return cfg;
    } on LocalSecureStoreException catch (e) {
      // 损坏密文（多为跨机器拷贝 ai_config.json / 机器 key 轮换）→ 降级为
      // env/预置配置。**绝不让异常冒到启动链**（本仓 9/25 实爆事故：解密失败
      // 外泄把 sendScan 打成「未配置」分支，见 ai_chat_controller.dart 的注释）。
      debugPrint('AiSettingsStore.load: ai_config 不可用，回落 fromEnv（${e.message}）');
      return AiConfig.fromEnv();
    } catch (_) {
      return AiConfig.fromEnv();
    }
  }

  static Future<void> save(AiConfig config) async {
    // v2.11 M4 安全注释（v2.19.37 兑现修订）：apiKey 原先**明文**写入
    // `~/.biology_app/ai_config.json`——同一台机器的其他账户/恶意软件
    // 读到此文件即获 key（v2.19.30 老用户走查 P2-2 点名）。该欠账已于
    // v2.19.37 兑现：`writeSecure` 用机器派生密钥做 AES-256-GCM 后写入
    // 同一个 `ai_config.json`（路径不变，envelope 内嵌）。
    // 威胁模型（详见 lib/services/local_secure_store.dart 文件头）：防的是
    // 「讲台机上别人用记事本打开文件直接看到 key」，**不防**取证级攻击
    // （三个派生源 hostname / USERNAME / `.machine.key` 都在本机）。
    // 共享讲台的处置建议不变：课后清除 key——因为同一台机器上运行本 App 的
    // 人仍能在设置页取回它。Web 端维持 localStorage 明文（拍板，见
    // local_secure_store.dart 的「web 端策略」）。
    final json = jsonEncode({
      'provider': config.provider,
      'baseUrl': config.baseUrl,
      'apiKey': config.apiKey,
      'model': config.model,
    });
    try {
      if (_isWebStorage) {
        // WEB-PASSTHROUGH：浏览器端维持 localStorage 明文。
        await _storageSet(_webKey, json);
        return;
      }
      // 测试未注入 debugFilePath 时不写真实 ai_config.json（返回语义不变）。
      if (!debugSkipUserDirWrite('ai_config.json',
          hasIsolatedPath: debugFilePath != null)) {
        await LocalSecureStore.writeSecure(_file(), json);
      }
    } catch (e) {
      // 写盘/加密失败不影响对话本身；**不**降级写明文（那正是本轮要消除的资产）。
      debugPrint('AiSettingsStore.save: 配置未能持久化（$e）');
    }
  }

  /// 测试专用：清静态 hook（debugFilePath / debugWebStorage / debugForceIsWebStorage）。
  /// **不**触碰磁盘 / localStorage。
  @visibleForTesting
  static void debugResetHooks() {
    debugFilePath = null;
    debugWebStorage = null;
    debugForceIsWebStorage = null;
  }

  /// Web 端 storage 读。test 用 debugWebStorage 注入；生产用 platform_storage。
  static String? _storageGet(String key) {
    if (debugWebStorage != null) return debugWebStorage![key];
    return storageGet(key);
  }

  /// Web 端 storage 写。test 用 debugWebStorage 注入；生产用 platform_storage。
  static Future<void> _storageSet(String key, String value) async {
    if (debugWebStorage != null) {
      debugWebStorage![key] = value;
      return;
    }
    await storageSet(key, value);
  }
}

/// AI 聊天历史存储（R17）：与 ai_config.json 同目录的
/// ai_chat_history.json，格式 [{"role":"user","text":"..."}…]。
/// 关闭助手面板不丢历史，重启 App 也保留；最多保留最近 100 条。
///
/// v2.12 R1 C P0 #7 修复：和 AiSettingsStore 同构——加 debugWebStorage
/// / debugForceIsWebStorage 两个测试 hook（debugFilePath 已存在），让
/// flutter_test 无 window 对象时也能验证 web round-trip 链路。
class AiChatStore {
  /// 测试注入：非空时读写该路径而非用户目录。
  static String? debugFilePath;

  /// 测试注入：mock Web 端 localStorage。flutter_test 无 window 对象。
  @visibleForTesting
  static Map<String, String>? debugWebStorage;

  /// 测试注入：mock `isWebStorage` 标志。
  @visibleForTesting
  static bool? debugForceIsWebStorage;

  /// 当前是否走 web 存储路径（test hook 优先于真实 isWebStorage）。
  static bool get _isWebStorage => debugForceIsWebStorage ?? isWebStorage;

  /// localStorage key。Web 端 load / save 走 storageGet / storageSet。
  static const String _webKey = 'ai_chat_history_json';

  static const int maxMessages = 100;

  static String _file() {
    if (debugFilePath != null) return debugFilePath!;
    final appDir = userAppDir();
    if (appDir == null) return 'ai_chat_history.json'; // Web 兜底占位
    final dir = Directory(appDir);
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return '${dir.path}/ai_chat_history.json';
  }

  /// 读取历史；文件不存在或损坏时返回空列表。Web 端走 localStorage。
  ///
  /// 本机透明加密：桌面/安卓分支经 `LocalSecureStore.readSecure`——
  /// `ai_chat_history.json` 路径不变，内容是 AES-256-GCM envelope 时自动
  /// 解密，是加密改造之前的旧明文时原样解析（下次 save 顺带升级为密文）。
  /// 解不开（跨机器拷贝 / 字节损坏）→ 空列表 + 日志，不影响启动与对话。
  static Future<List<Map<String, String>>> load() async {
    try {
      if (_isWebStorage) {
        final webRaw = _storageGet(_webKey);
        if (webRaw == null) return const [];
        final j = jsonDecode(webRaw);
        if (j is! List) return const [];
        return [
          for (final e in j)
            if (e is Map && e['role'] != null && e['text'] != null)
              {'role': e['role'].toString(), 'text': e['text'].toString()},
        ];
      }
      final j = jsonDecode(await LocalSecureStore.readSecure(_file()));
      if (j is! List) return const [];
      return [
        for (final e in j)
          if (e is Map && e['role'] != null && e['text'] != null)
            {'role': e['role'].toString(), 'text': e['text'].toString()},
      ];
    } on LocalSecureStoreException catch (e) {
      debugPrint('AiChatStore.load: 历史不可用，按空历史继续（${e.message}）');
      return const [];
    } catch (_) {
      return const [];
    }
  }

  /// 保存历史（超出 [maxMessages] 时只留最近的部分）。
  ///
  /// 本机透明加密：桌面/安卓走 `LocalSecureStore.writeSecure` 加密落盘——
  /// 聊天正文含题目图片描述与可能的师生/家长姓名，不再明文躺在
  /// `~/.biology_app/ai_chat_history.json` 里。
  ///
  /// v2.19.57 抛错契约：写盘/加密失败**必须**以异常结束（先 debugPrint
  /// 留痕再 rethrow），绝不在本方法内吞掉。生产唯一调用方
  /// `AiChatController._writeSnapshot` 负责记账（lastPersistError）并让
  /// await 的 clearHistory 拿到异常；这里若吞错，串行队列会把失败当
  /// 成功，清空按钮的失败回执永远到不了 UI。
  static Future<void> save(List<Map<String, String>> msgs) async {
    final trimmed = msgs.length > maxMessages
        ? msgs.sublist(msgs.length - maxMessages)
        : msgs;
    try {
      if (_isWebStorage) {
        // WEB-PASSTHROUGH：浏览器端维持 localStorage 明文（理由见
        // local_secure_store.dart 的「web 端策略」）。
        await _storageSet(_webKey, jsonEncode(trimmed));
        return;
      }
      // 测试未注入 debugFilePath 时不写真实 ai_chat_history.json。
      if (!debugSkipUserDirWrite('ai_chat_history.json',
          hasIsolatedPath: debugFilePath != null)) {
        await LocalSecureStore.writeSecure(_file(), jsonEncode(trimmed));
      }
    } catch (e) {
      // 留痕后原样抛出——对话流程不因此被本轮失败拖垮的担保在调用方
      // （_persistLogged 吞 + 记账；clearHistory 抛给面板弹条）。
      debugPrint('AiChatStore.save: 历史未能持久化（$e）');
      rethrow;
    }
  }

  static Future<void> clear() async => save(const []);

  /// 测试专用：清静态 hook。
  @visibleForTesting
  static void debugResetHooks() {
    debugFilePath = null;
    debugWebStorage = null;
    debugForceIsWebStorage = null;
  }

  /// Web 端 storage 读。test 用 debugWebStorage 注入；生产用 platform_storage。
  static String? _storageGet(String key) {
    if (debugWebStorage != null) return debugWebStorage![key];
    return storageGet(key);
  }

  /// Web 端 storage 写。test 用 debugWebStorage 注入；生产用 platform_storage。
  static Future<void> _storageSet(String key, String value) async {
    if (debugWebStorage != null) {
      debugWebStorage![key] = value;
      return;
    }
    await storageSet(key, value);
  }
}

class _SettingsPageState extends State<SettingsPage> {
  late TextEditingController _baseController;
  late TextEditingController _keyController;
  late TextEditingController _modelController;
  String _provider = AiConfig.providerDeepSeek;


  String? _status;
  bool _testing = false;

  /// 内置通道是否就绪：构建期确实注入了内置 key
  /// （`--dart-define=MINIMAX_API_KEY`，开源构建为空）+ MiniMax 通道 + 已有 key。
  /// 无注入时一律不就绪——否则横幅会谎称「无需填写 Key」，
  /// 「恢复内置配置」还会用空值清掉用户自填的 key。
  bool get _builtinChannelReady =>
      AiConfig.minimaxApiKeyFromEnv.isNotEmpty &&
      _provider == AiConfig.providerMinimax &&
      _keyController.text.trim().isNotEmpty;

  /// v2.11 H3：BaseURL 校验错误（SSRF / 非法 scheme / 格式错）。
  /// 保存前实时校验，错误时阻止保存 + TextField 红色提示。
  String? _baseError;

  /// v2.11 H3：实时校验 BaseURL，错误写入 [_baseError]。
  /// 输入变化 / 切换通道 / 加载配置 都应触发。
  void _validateBaseUrl() {
    // 预置通道的 URL 已知合法，跳过校验
    if (_provider != AiConfig.providerCustom) {
      setState(() => _baseError = null);
      return;
    }
    final err = AiConfig.validateBaseUrl(_baseController.text);
    setState(() => _baseError = err);
  }

  @override
  void initState() {
    super.initState();
    // 立即创建（异步加载期间 build 可用）；加载完成后再填充文本
    _baseController = TextEditingController();
    _keyController = TextEditingController();
    _modelController = TextEditingController();
    _loadConfig();
  }

  Future<void> _loadConfig() async {
    var cfg = await AiSettingsStore.load();
    // v2.15 存量迁移：旧 OpenCode 通道配置（网关已下线）整体切到
    // DeepSeek 预设——provider/baseUrl/model 全换，保留用户手填的
    // key（大概率已失效，留在输入框供其替换时参考），并顺手落盘。
    if (cfg.provider == 'opencode') {
      cfg = AiConfig.presetDeepSeek.copyWith(apiKey: cfg.apiKey);
      await AiSettingsStore.save(cfg);
    }
    if (!mounted) return;
    setState(() {
      _provider = cfg.provider;
      _baseController.text = cfg.baseUrl;
      _keyController.text = cfg.apiKey;
      _modelController.text = cfg.model;
    });
    // R7 老师走查 #8：首进设置页不点芯片也要看到 key 申请引导——
    // 新装机默认 DeepSeek 但 key 为空，此时主动给引导文案。
    if (cfg.apiKey.isEmpty) {
      setState(() => _status = cfg.provider == AiConfig.providerDeepSeek
          ? 'DeepSeek 通道已就绪——到 platform.deepseek.com 免费申请 '
              'API Key，填入下方保存即可使用。'
          : '当前通道尚未填入 API Key，填入后点击保存生效。');
    }
  }

  @override
  void dispose() {
    _baseController.dispose();
    _keyController.dispose();
    _modelController.dispose();
    super.dispose();
  }

  AiConfig get _currentConfig => AiConfig(
        provider: _provider,
        baseUrl: _baseController.text.trim(),
        apiKey: _keyController.text.trim(),
        model: _modelController.text.trim().isEmpty
            ? (AiConfig.presetOf(_provider)?.model ?? 'deepseek-flash')
            : _modelController.text.trim(),
      );

  /// 切换通道：预设通道自动回填 BaseURL/模型；自定义保留手填值。
  ///
  /// 预设 key 口径：[AiConfig.presetMinimax].apiKey 只有
  /// `--dart-define=MINIMAX_API_KEY` 注入才有值，缺省空串。因此：
  ///   - DeepSeek：预设 key 恒空（用户自填）；
  ///   - MiniMax：release 模式不回填（不把注入值写进用户落盘配置），
  ///     debug 模式回填注入值方便调试；输入框已有 key 时不动它。
  /// baseUrl/model 无条件回填预设（幂等，点已选中芯片 = 重载预设）。
  void _selectProvider(String p) {
    setState(() {
      _provider = p;
      final preset = AiConfig.presetOf(p);
      if (preset != null) {
        _baseController.text = preset.baseUrl;
        // v2.19.16（DeepSeek 找茬 🟡6 折中）：key 栏仅「预设非空」或
        // 「当前为空」时回填——同通道重选不再清空用户已贴的 key。
        final presetKey = (kReleaseMode || p == AiConfig.providerDeepSeek)
            ? ''
            : preset.apiKey;
        // 内置 key 只对 MiniMax 有效：切到没有预设 key 的通道时清掉它，
        // 免得把共享凭据发给别家（用户自己填的 key 不动）。
        final builtinKey = AiConfig.minimaxApiKeyFromEnv;
        final keyIsBuiltin =
            builtinKey.isNotEmpty && _keyController.text.trim() == builtinKey;
        if (presetKey.isNotEmpty ||
            _keyController.text.isEmpty ||
            keyIsBuiltin) {
          _keyController.text = presetKey;
        }
        _modelController.text = preset.model;
        // v2.11 H3：预设通道的 URL 已知合法，清空错误
        _baseError = null;
        // R6 老师走查 #3/#14：面向用户的单套措辞——不出现「release/
        // debug 模式」黑话，DeepSeek 明确给 key 申请路径。
        // v2.20.0：MiniMax 不再内置 key，措辞必须与真实行为一致。
        _status = p == AiConfig.providerMinimax
            ? (_keyController.text.trim().isEmpty
                ? '已填入 MiniMax 通道（多模态可看图）。请填入自己的 API Key'
                    '（platform.minimaxi.com 申请）后点击保存生效。'
                : '已填入 MiniMax 通道（Key 已就绪，可直接使用；也可在 Key'
                    ' 栏换成自己的 Key）。')
            : '已填入 DeepSeek 通道（deepseek-flash 多模态，拍题/截图可'
                '直接发图）。在下方 API Key 栏填入你的 DeepSeek Key 后'
                '点击保存生效（key 在 platform.deepseek.com 免费申请）。';
      } else {
        // 切到 custom：等用户输入后实时校验
        _baseError = AiConfig.validateBaseUrl(_baseController.text);
      }
    });
  }

  Future<void> _save() async {
    // v2.11 H3：保存前校验 BaseURL，错误则不保存 + 阻止。
    _validateBaseUrl();
    if (_baseError != null) {
      setState(() => _status = 'BaseURL 校验失败：$_baseError');
      return;
    }
    // v2.11 H3：custom 通道额外弹确认对话框——你将向用户手填的 URL
    // 发送 API key 和聊天内容，是 SSRF 风险最高的路径。
    if (_provider == AiConfig.providerCustom) {
      final ok = await _confirmCustomProvider();
      if (!ok) return;
    }
    await AiSettingsStore.save(_currentConfig);
    if (!mounted) return;
    setState(() => _status = '已保存配置。');
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('配置已保存')));
  }

  /// v2.11 H3：custom 通道保存前弹确认——用户将向 `<url>` 发送 API key +
  /// 聊天内容，确认走不可信 URL 的风险。
  Future<bool> _confirmCustomProvider() async {
    final url = _baseController.text.trim();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('确认使用自定义通道'),
        content: Text(
          '你将向以下 URL 发送 API Key 和所有聊天内容（包括题目图片）：\n\n'
          '$url\n\n'
          '请确认：\n'
          '· 该 URL 是你信任的服务（OpenAI 兼容协议）\n'
          '· URL 已通过 https:// 加密 + 非内网地址校验\n'
          '· 你了解向不可信服务发送 API Key 的风险',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('我已确认风险'),
          ),
        ],
      ),
    );
    return confirmed == true;
  }

  /// 一键回到「开箱即用」状态：通道 / 地址 / 模型 / 内置 key 全部重置并
  /// 落盘。老师在设置页改坏配置后不必再去找 key。
  Future<void> _restoreBuiltin() async {
    // 开源构建没有注入值：空 key 覆盖会抹掉用户自填的 key，直接拒绝。
    if (AiConfig.minimaxApiKeyFromEnv.isEmpty) {
      setState(() => _status = '当前构建未注入内置通道，请填写自己的 API Key。');
      return;
    }
    final cfg = AiConfig.presetMinimax
        .copyWith(apiKey: AiConfig.minimaxApiKeyFromEnv);
    await AiSettingsStore.save(cfg);
    if (!mounted) return;
    setState(() {
      _provider = cfg.provider;
      _baseController.text = cfg.baseUrl;
      _keyController.text = cfg.apiKey;
      _modelController.text = cfg.model;
      _baseError = null;
      _status = '已恢复内置配置：MiniMax 通道（${cfg.model}）。';
    });
  }

  Future<void> _test() async {
    // v2.11 H3：测试连接前也校验。
    _validateBaseUrl();
    if (_baseError != null) {
      setState(() => _status = 'BaseURL 校验失败：$_baseError');
      return;
    }
    final cfg = _currentConfig;
    setState(() {
      _testing = true;
      _status = '正在测试连接...';
    });
    final client = AiClient(cfg);
    final result = await client.ask('请只回复两个字：正常');
    setState(() {
      _testing = false;
      _status = result.ok
          ? '连接成功：${result.content}'
          : '连接失败：${result.error}';
    });
  }

  @override
  Widget build(BuildContext context) {
    // v2.19.30 用户裁定：设置页去分类化——左分类右内容骨架对设置页
    // 是「为了分类而分类」，徒增操作门槛（初衷是简化，不是为操作而
    // 操作）。回退单列平铺：7 节纵向排列，节标题 + 内容，滚动即达。
    // 保留 v2.19.29 全部修复：三输入框回车即存、锚点 key 常显
    //（单列无面板切换，引导 P0 自然根治，_syncGuidePanel 补丁删除）。
    return Scaffold(
      appBar: AppBar(
        leading: appNavButton(widget.onNavPressed),
        title: const Text('设置'),
      ),
      body: ListView(
        // v2.19.30（DeepSeek P1-1）：滚动缓存提到 2000——AI 节在
        // y≈1400，默认 250 的缓存会在用户滚到「开始引导」后销毁
        // AI 节 Element → 引导设置步 settingsAi.currentContext == null
        // → ensureVisible 早退、挖孔丢失（整屏黑罩无高亮）。
        scrollCacheExtent: const ScrollCacheExtent.pixels(2000),
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
        children: [
          // v2.19.30（DeepSeek 检查 P2）：ConstrainedBox 在 ListView 紧
          // 约束下撑满视口、Column 贴左——Align 居中，与全 app body
          // 语言（side_nav_workbench Align(topCenter)）一致。
          Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 860),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                _panelRole(context),
                const SizedBox(height: 30),
                Divider(color: AppColors.border.withValues(alpha: 0.6)),
                const SizedBox(height: 22),
                const AccountDataSection(),
                const SizedBox(height: 30),
                Divider(color: AppColors.border.withValues(alpha: 0.6)),
                const SizedBox(height: 22),
                _panelAi(context),
                const SizedBox(height: 30),
                Divider(color: AppColors.border.withValues(alpha: 0.6)),
                const SizedBox(height: 22),
                const AiToolsSection(),
                const SizedBox(height: 30),
                Divider(color: AppColors.border.withValues(alpha: 0.6)),
                const SizedBox(height: 22),
                _panelAppearance(context),
                const SizedBox(height: 30),
                Divider(color: AppColors.border.withValues(alpha: 0.6)),
                const SizedBox(height: 22),
                _panelPresent(context),
                const SizedBox(height: 30),
                Divider(color: AppColors.border.withValues(alpha: 0.6)),
                const SizedBox(height: 22),
                _panelGuide(context),
                const SizedBox(height: 30),
                Divider(color: AppColors.border.withValues(alpha: 0.6)),
                const SizedBox(height: 22),
                _panelShortcuts(context),
                const SizedBox(height: 30),
                Divider(color: AppColors.border.withValues(alpha: 0.6)),
                const SizedBox(height: 22),
                _panelPrivacy(context),
              ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ─── 分区面板（v2.19.28 沿用至今；单列平铺后节标题即分区标） ───

  Widget _sectionHeader(BuildContext context, String title, String? desc) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: AppText.sectionTitle),
        if (desc != null) ...[
          const SizedBox(height: 6),
          Text(desc, style: theme.textTheme.bodySmall),
        ],
        const SizedBox(height: 14),
      ],
    );
  }

  /// 使用角色（R6 双走查 #2：与首页角色 chip 同一 FirstRunStore，
  /// dashboard 已有 listener 实时生效）。
  Widget _panelRole(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeader(
            context,
            '使用角色',
            '决定首页显示哪些功能：学生 = 完整学习功能（含错题本）；'
                '老师 = 课堂大屏工具（错题本入口隐藏，它是学生私人空间）。'
                '上课前还需在下方「使用模式」切到课堂大屏才会放大字号。'),
        Wrap(
          spacing: 8,
          children: [
            ChoiceChip(
              label: const Text('学生'),
              selected:
                  FirstRunStore.instance.currentRole() != UserRole.teacher,
              onSelected: (_) async {
                await FirstRunStore.instance.setRole(UserRole.student);
                if (!context.mounted) return;
                setState(() {});
                // R7 学生走查：切换无反馈，学生不确定生效没。
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                    content: Text('已切换为学生角色，首页功能即时更新')));
              },
            ),
            ChoiceChip(
              label: const Text('老师'),
              selected:
                  FirstRunStore.instance.currentRole() == UserRole.teacher,
              onSelected: (_) async {
                await FirstRunStore.instance.setRole(UserRole.teacher);
                if (!context.mounted) return;
                setState(() {});
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                    content: Text('已切换为老师角色，首页功能即时更新')));
              },
            ),
          ],
        ),
      ],
    );
  }

  /// OpenAI 兼容 AI 接口（新手引导高亮目标 GuideKeys.settingsAi）。
  Widget _panelAi(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      key: GuideKeys.settingsAi,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeader(
            context,
            'OpenAI 兼容 AI 接口',
            '难题（如复杂遗传推演）交给 AI 计算；简单概率/计算本地计算。'),
        // 内置通道：构建期注入了 key 才显示（开源构建一律不显示），且需
        // MiniMax 通道 + 已有 key（输入框即配置的回显）。
        if (_builtinChannelReady) ...[
          Row(
            children: [
              Icon(Icons.verified_user_outlined,
                  size: 18, color: theme.colorScheme.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text('当前使用内置通道，无需填写 Key',
                    style: theme.textTheme.bodyMedium),
              ),
              // 只在构建期注入了内置 key 时才给这个按钮：
              // 开源构建没有可恢复的东西，点了只会清空用户自填的 key。
              if (AiConfig.minimaxApiKeyFromEnv.isNotEmpty)
                TextButton(
                  onPressed: _restoreBuiltin,
                  child: const Text('恢复内置配置'),
                ),
            ],
          ),
          const SizedBox(height: 10),
        ],
        // v2.15 双通道切换：DeepSeek（默认，deepseek-flash 多模态）/
        // MiniMax（保留通道）/ 自定义。
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            ChoiceChip(
              label: const Text('DeepSeek（默认）'),
              selected: _provider == AiConfig.providerDeepSeek,
              onSelected: (_) => _selectProvider(AiConfig.providerDeepSeek),
            ),
            ChoiceChip(
              label: const Text('MiniMax'),
              selected: _provider == AiConfig.providerMinimax,
              onSelected: (_) => _selectProvider(AiConfig.providerMinimax),
            ),
            ChoiceChip(
              label: const Text('自定义'),
              selected: _provider == AiConfig.providerCustom,
              onSelected: (_) => _selectProvider(AiConfig.providerCustom),
            ),
          ],
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _baseController,
          onChanged: (_) => _validateBaseUrl(),
          // v2.19.29（M3.1 学生 N-P2-4）：回车直接保存——键盘升起时
          // 「保存配置」按钮常被顶出屏。
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _save(),
          decoration: InputDecoration(
            labelText: 'Base URL',
            hintText: 'https://api.deepseek.com',
            helperText: 'OpenAI 兼容接口地址（预置 DeepSeek / MiniMax 双通道）',
            // v2.11 H3：实时显示校验错误
            errorText: _baseError,
            errorMaxLines: 2,
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _keyController,
          obscureText: true,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _save(),
          decoration: const InputDecoration(
            labelText: 'API Key',
            // R7 老师走查 #10 / v2.20.0：讲台机共用场景的诚实提示——
            // 磁盘上是密文，但同一台机器上**运行本应用的人**照样能在
            // 设置页看到它，所以「加密」不等于「别人看不到」。
            helperText: '填入你的 API Key（本机加密存储；但共用电脑的其他'
                '使用者仍可能通过本应用读到它，课后建议清除）',
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _modelController,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _save(),
          decoration: InputDecoration(
            labelText: '模型名',
            hintText: 'deepseek-flash',
            // 模型名从预设取，避免改名后说明文字与输入框自相矛盾。
            helperText:
                'DeepSeek 通道：deepseek-flash（V4.1-Flash 多模态，可看图）；'
                'MiniMax 通道：${AiConfig.presetMinimax.model}',
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            FilledButton.icon(
              onPressed: _save,
              icon: const Icon(Icons.save),
              label: const Text('保存配置'),
            ),
            const SizedBox(width: 12),
            OutlinedButton.icon(
              onPressed: _testing ? null : _test,
              icon: _testing
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.wifi_tethering),
              label: const Text('测试连接'),
            ),
          ],
        ),
        if (_status != null) ...[
          const SizedBox(height: 12),
          Text(_status!, style: theme.textTheme.bodyMedium),
        ],
      ],
    );
  }

  /// 外观：浅色 / 深色 / 跟随系统 + 护眼模式。
  Widget _panelAppearance(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeader(
            context, '外观', '浅色 / 深色模式，立即生效并记忆到本机。'),
        ListenableBuilder(
          listenable: ThemeController.instance,
          builder: (context, _) => SegmentedButton<ThemeMode>(
            segments: const [
              ButtonSegment(
                value: ThemeMode.light,
                icon: Icon(Icons.light_mode_outlined),
                label: Text('浅色'),
              ),
              ButtonSegment(
                value: ThemeMode.dark,
                icon: Icon(Icons.dark_mode_outlined),
                label: Text('深色'),
              ),
              ButtonSegment(
                value: ThemeMode.system,
                icon: Icon(Icons.settings_suggest_outlined),
                label: Text('跟随系统'),
              ),
            ],
            selected: {ThemeController.instance.mode},
            onSelectionChanged: (sel) =>
                ThemeController.instance.setMode(sel.first),
          ),
        ),
        // v2.19.8 R9：护眼模式 = 全局暖色矩阵滤镜，叠加在浅/深主题之上。
        const SizedBox(height: 8),
        ListenableBuilder(
          listenable: ThemeController.instance,
          builder: (context, _) => SwitchListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            title: const Text('护眼模式'),
            subtitle: Text('全局叠加暖色调（降蓝光、背景偏暖），深浅主题均生效'),
            value: ThemeController.instance.eyeCare,
            onChanged: (v) => ThemeController.instance.setEyeCare(v),
          ),
        ),
      ],
    );
  }

  /// 使用模式：标准 / 课堂大屏 + 课堂子开关（ValueKey 为
  /// present_mode_test 锚点，勿删）。
  Widget _panelPresent(BuildContext context) {
    return Column(
      key: const ValueKey('presentModeCard'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeader(context, '使用模式', null),
        Text(
          '标准：日常学习/刷题布局（默认）。拍题识别、板书放映、'
          '工具抽屉、AI 读题填参等学习功能均可使用。\n'
          '课堂大屏：教师在教室大屏/电子白板讲课时使用——'
          '全场字号与触控按钮放大（教鞭/胳膊可点），'
          '右下角常驻课堂快捷条（聚光灯/高对比/激光笔/退出课堂），'
          '可收起成小把手；'
          '系谱画布聚光灯为对象式（点哪亮哪、按住拖动、拖边缘调大小）。\n'
          'F11 全屏切换（Windows）：投影上课时按 F11 进入无边框全屏，'
          '再按一次还原。',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 12),
        ModeSwitcher(),
        const SizedBox(height: 8),
        ListenableBuilder(
          listenable: PresentModeController.instance,
          builder: (context, _) {
            final present = PresentModeController.instance.enabled;
            // v2.22.0：高对比是**浅色投影档**的放大量具（纯白底 + 近黑字），
            // 深色主题已有独立调校的高可读色板（AppColors._hc 本来就在
            // dark 下短路，不看这个开关）。深色里继续让用户拨它 = 拨了没反
            // 应，故置灰；**不改存储值**，切回浅色后原偏好照样生效。
            final dark = Theme.of(context).brightness == Brightness.dark;
            return Column(
              children: [
                // 高对比配色（投影泛白吃对比度 / 学生视力辅助）。
                SwitchListTile(
                  key: const ValueKey('highContrastSwitch'),
                  contentPadding: EdgeInsets.zero,
                  secondary: const Icon(Icons.contrast),
                  title: const Text('高对比配色'),
                  subtitle: Text(dark
                      ? '仅浅色模式；深色使用独立高可读色板'
                          '（本设置保留，切回浅色自动生效）'
                      : '纯白底 + 近黑文字 + 加深边框；投影泛白或学生视力辅助均可用'),
                  value: PresentModeController.instance.highContrast,
                  onChanged: dark
                      ? null
                      : (v) =>
                          PresentModeController.instance.setHighContrast(v),
                ),
                // 激光笔独立开关（默认关）。
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  secondary: const Icon(Icons.gps_fixed),
                  title: const Text('画布激光笔'),
                  subtitle: Text(present
                      ? '遗传图谱画布跟随手指/指针显示红色光点（默认关）'
                      : '切到课堂大屏后可用'),
                  value: PresentModeController.instance.laserEnabled,
                  onChanged: present
                      ? (v) =>
                          PresentModeController.instance.setLaserEnabled(v)
                      : null,
                ),
              ],
            );
          },
        ),
      ],
    );
  }

  /// 新手引导：一次性引导的再入口。
  Widget _panelGuide(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeader(
            context,
            '新手引导',
            '一步步介绍每个板块和按键的用法（约 1 分钟）。'
                '引导为一次性：完成或跳过后自动关闭；'
                '想再看一遍，回到这里再次点击即可。'),
        FilledButton.icon(
          onPressed: () => GuideController.instance.start(),
          icon: const Icon(Icons.play_circle_outline, size: 18),
          label: const Text('开始引导'),
        ),
      ],
    );
  }

  /// 键盘快捷键总览（v2.19.16 起 10+ 快捷键的集中一览）。
  Widget _panelShortcuts(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeader(context, '键盘快捷键', null),
        Text(
          '系谱页：E 复制 SVG 文本 · Ctrl+Shift+E 导出菜单 · Ctrl+Shift+V 出板书 PNG\n'
          '计算器各页：Ctrl+S 存入错题本（焦点在输入框时也可）\n'
          '复习会话：1 显示答案/掌握了 · 2 还需复习 · 3 问 AI 讲解 · Esc 退出\n'
          '全局：数字 1-9/0 切页面 · Ctrl+A 问 AI · 输入框内打字不受快捷键干扰',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      ],
    );
  }

  /// 隐私说明。
  Widget _panelPrivacy(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeader(context, '隐私说明', null),
        Text(
          '· API Key 仅保存在本机配置文件中\n'
          '· 仅在你点击「问 AI」或测试连接时发送到你所填的 BaseURL\n'
          '· 本地概率计算、遗传计算不消耗 API',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      ],
    );
  }
}
