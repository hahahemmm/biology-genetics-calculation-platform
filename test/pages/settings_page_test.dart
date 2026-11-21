// settings_page_test.dart —— v2.12 R1 C P0 #7 跨端持久化回归测试
//
// 覆盖：
//   1. AiSettingsStore 桌面 / 安卓 File 路径 round-trip：save 写盘 + load 读回
//   2. AiSettingsStore Web 端 localStorage 路径 round-trip（用
//      debugWebStorage mock）
//   3. AiChatStore 桌面 / 安卓 File 路径 round-trip
//   4. AiChatStore Web 端 localStorage 路径 round-trip
//   5. debugResetHooks 清理
//
// v2.12 R1 C P0 #7 修复：原 `_dir()` 用 `Platform.environment['USERPROFILE']`
// + `Directory(...)` 直接拼路径在 Web 端 build 成功但运行时 File 构造
// 抛 UnimplementedError，被 catch 吞掉。改用 `userAppDir()` 中性 API +
// `isWebStorage` 分支后必须验证：Web 端 localStorage 路径 round-trip
// 链路、JSON 损坏降级、debug hook 接线。
//
// 本机透明加密（`LocalSecureStore` 移植）：桌面 / 安卓分支已切到
// `LocalSecureStore`——磁盘上是 AES-256-GCM envelope，**不再是明文**。
// 本文件相应地把「直接 readAsStringSync 断言含 apiKey」的旧断言换成两条
// 更硬的性质：① 原始字节里搜不到 apiKey 明文（casual disclosure 已消除）；
// ② 经 readSecure 能拿回逐字的明文 JSON。Web 端 localStorage 分支维持
// 明文（拍板：Web 端不加密，见 local_secure_store.dart 文件头），
// 对应断言原样保留。
//
// ⚠️ 本仓 `AiSettingsStore.save` 仍是 `Future<void>`（与改造前一致），
// 因此源仓的 `expect(await save(cfg), isTrue)` 断言不适用——改为断言磁盘
// 事实（envelope 落盘 / 无明文）。save 的失败回报语义属 UI 层改造，未纳入本轮。

import 'dart:async';
import 'dart:io';

import 'package:biology/services/ai_client.dart';
import 'package:biology/pages/settings_page.dart';
import 'package:biology/services/local_secure_store.dart';
import 'package:biology/services/mistake_book_crypto.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AiSettingsStore 跨端持久化（v2.12 R1 C P0 #7）', () {
    late Directory tmp;
    late String filePath;

    setUp(() {
      tmp = Directory.systemTemp.createTempSync('ai_settings_test');
      filePath = '${tmp.path}/ai_config.json';
      // 把「每安装机器密钥」收进临时目录，不脏写真实用户目录
      // （debugResetHooks 会清 hook，故必须先 reset 再设）。
      LocalSecureStore.debugResetHooks();
      LocalSecureStore.debugMachineKeyPath = '${tmp.path}/.machine.key';
      AiSettingsStore.debugConfig = null;
      AiSettingsStore.debugFilePath = filePath;
      AiSettingsStore.debugWebStorage = null;
      AiSettingsStore.debugForceIsWebStorage = null;
    });

    tearDown(() {
      AiSettingsStore.debugResetHooks();
      AiSettingsStore.debugConfig = null;
      LocalSecureStore.debugResetHooks();
      if (tmp.existsSync()) tmp.deleteSync(recursive: true);
    });

    test('桌面 / 安卓 File 路径：save 加密写盘 + load 解密读回', () async {
      // 1. 首次启动：磁盘无文件 → load 走 fromEnv fallback
      expect(File(filePath).existsSync(), isFalse,
          reason: 'setUp 后磁盘应无 ai_config.json');
      final initial = await AiSettingsStore.load();
      // debugFilePath 注入到 filePath → load 走 readSecure，磁盘无
      // 文件 → 抛 LocalSecureUnreadableException → 降级返回 AiConfig.fromEnv()。
      expect(initial, isA<AiConfig>(),
          reason: 'load() 应返回 AiConfig 实例');

      // 2. save 一份 config → 加密落盘到 filePath（路径不变）
      // v2.19.67：model 刻意避开退役名（MiniMax-M3* 命中 AiSettingsStore
      // 的 MiniMax 退役迁移会被整体换成 presetMinimax）——本用例测的是
      // 加密 round-trip 保真，不是迁移（迁移见 ai_minimax_migration_test）。
      final cfg = AiConfig(
        provider: AiConfig.providerMinimax,
        baseUrl: 'https://api.minimaxi.com/v1',
        apiKey: 'test-key-123',
        model: 'my-mm-model',
      );
      await AiSettingsStore.save(cfg);
      expect(File(filePath).existsSync(), isTrue,
          reason: 'save 后磁盘应有 ai_config.json');
      final raw = File(filePath).readAsStringSync();
      // 核心验收：打开文件看不到 key 明文。
      expect(raw, isNot(contains('test-key-123')),
          reason: 'apiKey 不得以明文出现在磁盘字节里');
      expect(raw, isNot(contains('apiKey')),
          reason: '连字段名都不该裸露（整包已被 envelope 包住）');
      expect(MistakeBookCrypto.isEncryptedEnvelope(raw), isTrue,
          reason: '落盘内容应是可识别的 AES-GCM envelope');
      // 明文可经 readSecure 完整取回（字段逐字对齐旧格式）。
      final plain = await LocalSecureStore.readSecure(filePath);
      expect(plain, contains('"provider":"minimax"'));
      expect(plain, contains('"apiKey":"test-key-123"'));

      // 3. 重新 load → 读回（debugFilePath 仍指向 filePath）
      final loaded = await AiSettingsStore.load();
      expect(loaded.provider, AiConfig.providerMinimax,
          reason: 'load 应读出 provider=minimax');
      expect(loaded.apiKey, 'test-key-123',
          reason: 'load 应解密读回 apiKey');
      expect(loaded.model, 'my-mm-model',
          reason: '未退役的存量配置 load 后应逐字保留（不迁移）');
    });

    test('存量兼容：加密改造之前的明文 ai_config.json 仍能 load，并在下次 save 升级',
        () async {
      // 老用户机器上的现状：明文 JSON 落盘（找茬报告实证形态）。
      // model 用未退役名——退役名（MiniMax-M3*）会触发 MiniMax 整体
      // 迁移换 presetMinimax，那就测不到「明文原样保留」本意了。
      File(filePath).writeAsStringSync(
          '{"provider":"minimax","baseUrl":"https://api.minimaxi.com/v1",'
          '"apiKey":"legacy-plain-key","model":"my-mm-model"}');

      final loaded = await AiSettingsStore.load();
      expect(loaded.apiKey, 'legacy-plain-key',
          reason: 'readSecure 对旧明文必须原样放行（向后兼容硬要求）');

      await AiSettingsStore.save(loaded);
      final raw = File(filePath).readAsStringSync();
      expect(MistakeBookCrypto.isEncryptedEnvelope(raw), isTrue,
          reason: '下次 save 自动升级为密文，无需用户导出导入');
      expect(raw, isNot(contains('legacy-plain-key')));
      expect((await AiSettingsStore.load()).apiKey, 'legacy-plain-key');
    });

    test('惰性升级：load() 自身触发明文→密文升级（无需用户再点保存）', () async {
      // 老用户只打开设置页 / 只发一次问（走 load），从不改配置——
      // 只靠「下次 save」升级的话，明文 key 会一直躺在磁盘上。
      // 惰性升级让 load() 后台补一次加密写，消除这个残留窗口。
      // model 用未退役名（避开 MiniMax 退役迁移，保住「原样返回」语义）。
      File(filePath).writeAsStringSync(
          '{"provider":"minimax","baseUrl":"https://api.minimaxi.com/v1",'
          '"apiKey":"lazy-key-1","model":"my-mm-model"}');

      final loaded = await AiSettingsStore.load();
      expect(loaded.apiKey, 'lazy-key-1',
          reason: 'load 必须先照常返回明文配置（升级不影响返回值）');

      // 升级是 fire-and-forget：inline 派生只走 microtask，让出事件循环即完成。
      for (var i = 0;
          i < 100 &&
              !MistakeBookCrypto.isEncryptedEnvelope(
                  File(filePath).readAsStringSync());
          i++) {
        await Future<void>.delayed(Duration.zero);
      }
      final raw = File(filePath).readAsStringSync();
      expect(MistakeBookCrypto.isEncryptedEnvelope(raw), isTrue,
          reason: 'load() 后即使不调 save，磁盘也应被惰性升级为密文');
      expect(raw, isNot(contains('lazy-key-1')),
          reason: '升级后明文 key 不得再裸露');
      expect((await AiSettingsStore.load()).apiKey, 'lazy-key-1',
          reason: '升级后仍能正常读回');
    });

    test('竞态回归：load() 的后台升级不得覆盖随后 save() 写入的新配置',
        () async {
      // v2.15 opencode→DeepSeek 迁移的真实形态（源仓全量测试实测翻车点）：
      //   load() 读到旧明文 ⇒ 后台惰性升级启动（要先跑一次 100k PBKDF2）
      //   ⇒ 同一批里迁移链 save() 写入**不同**的新配置
      //   ⇒ 升级若无 compare-and-swap，就把 load 时刻的过期明文回写，
      //      provider 从 deepseek 被打回 opencode。
      // 这里用 debugGateBeforeAtomicReplace 把「加密窗口」钉成确定时序，
      // 不靠两条写链的偶然先后（那是假绿）。
      File(filePath).writeAsStringSync(
          '{"provider":"opencode","baseUrl":"https://opencode.ai/zen/go/v1",'
          '"apiKey":"race-key-1","model":"mimo-v2.5"}');

      final gate = Completer<void>();
      var parked = false;
      LocalSecureStore.debugGateBeforeAtomicReplace = (p) {
        parked = parked || p == filePath;
        return gate.future;
      };

      final loaded = await AiSettingsStore.load();
      expect(loaded.provider, 'opencode',
          reason: 'load 仍照常返回旧明文配置（升级不挡返回）');
      for (var i = 0; i < 1000 && !parked; i++) {
        await Future<void>.delayed(Duration.zero);
      }
      expect(parked, isTrue, reason: '前置：后台升级停在「密文就绪、尚未替换」窗口');

      // 窗口内：迁移把新配置整体落盘（这是**最后一次**合法写入）
      await AiSettingsStore.save(const AiConfig(
        provider: AiConfig.providerDeepSeek,
        baseUrl: 'https://api.deepseek.com',
        apiKey: 'race-key-1',
        model: 'deepseek-flash',
      ));
      gate.complete(); // 放后台升级继续 ⇒ 它现在必须被 CAS 拦下
      for (var i = 0; i < 5; i++) {
        await Future<void>.delayed(Duration.zero);
      }

      final plain = await LocalSecureStore.readSecure(filePath);
      expect(plain, contains('"provider":"deepseek"'),
          reason: '磁盘最终必须是 save 写入的新配置，过期明文不得回写');
      expect(plain, isNot(contains('opencode')));
      expect((await AiSettingsStore.load()).provider,
          AiConfig.providerDeepSeek);
      expect(
          tmp
              .listSync()
              .whereType<File>()
              .where((f) => f.path.endsWith('.tmp')),
          isEmpty,
          reason: '被 CAS 拦下的升级要删掉半成品');
    });

    test('损坏密文降级：ai_config.json 是解不开的 envelope → 回落 fromEnv，不抛',
        () async {
      // 场景：用户把 A 机的 ai_config.json 拷到 B 机（密钥派生源不同），
      // 或手工改过字节。绝不允许把异常冒到启动链上。
      final foreign = await MistakeBookCrypto.encryptJson(
          '{"provider":"minimax","apiKey":"sk-x"}', 'another-machine');
      File(filePath).writeAsStringSync(foreign);

      final loaded = await AiSettingsStore.load();
      expect(loaded, isA<AiConfig>(),
          reason: '损坏密文 → 降级到 fromEnv，不抛');
      expect(loaded.apiKey, isNot('sk-x'),
          reason: '解不开的 key 不该被读出来');
    });

    // 本仓增量回归：9/25 实爆事故（ai_chat_controller.dart:278 注释）
    // —— 机器 key 轮换导致 ai_config 解密失败，异常若冒出去会把
    // sendScan 打成「尚未配置 AI 接口」分支，v215_r6 等全量测试变红。
    // 本条把「解密失败 → 失败开放回落 fromEnv，绝不抛」钉死。
    test('事故回归：机器 key 轮换后密文解不开 → 回落 fromEnv，绝不抛异常',
        () async {
      // 1. 正常时期：配置加密落盘。
      await AiSettingsStore.save(const AiConfig(
        provider: AiConfig.providerDeepSeek,
        baseUrl: 'https://api.deepseek.com',
        apiKey: 'sk-before-rotation',
        model: 'deepseek-flash',
      ));
      expect(MistakeBookCrypto.isEncryptedEnvelope(
              File(filePath).readAsStringSync()),
          isTrue);

      // 2. 机器 key 被轮换（重装 / 换用户 / 误删 .machine.key）。
      File('${tmp.path}/.machine.key').writeAsStringSync('f' * 32);
      LocalSecureStore.debugResetHooks();
      LocalSecureStore.debugMachineKeyPath = '${tmp.path}/.machine.key';

      // 3. 失败开放：load() 必须返回 fromEnv 兜底，一个异常都不许冒。
      AiConfig? loaded;
      Object? caught;
      try {
        loaded = await AiSettingsStore.load();
      } catch (e) {
        caught = e;
      }
      expect(caught, isNull,
          reason: '解密失败绝不允许冒到调用方（9/25 事故的根因就是异常外泄）');
      expect(loaded, isNotNull);
      expect(loaded, isA<AiConfig>());
      // v2.25：内置 key 随包分发后，fromEnv 回落的是内置 MiniMax 通道，
      // isConfigured 因此为 true——这不再是「未配置」的判据。这里要钉的是
      // 「解不开的旧 key 一个字都没被读出来」。
      expect(loaded!.apiKey, isNot('sk-before-rotation'),
          reason: '解不开的旧 key 不得被读出来冒充「已配置」');
      expect(loaded.apiKey, AiConfig.minimaxApiKeyFromEnv,
          reason: '回落的必须是内置通道，不是那把解不开的旧 key');
    });

    test('Web 端 localStorage 路径：debugWebStorage round-trip', () async {
      // flutter_test 无 window 对象。用 debugWebStorage 注入 mock。
      final webStore = <String, String>{};
      AiSettingsStore.debugWebStorage = webStore;
      AiSettingsStore.debugForceIsWebStorage = true;
      AiSettingsStore.debugFilePath = null;
      AiSettingsStore.debugConfig = null;

      // 1. 首启：web 端 localStorage 空 → load 走 fromEnv fallback
      final initial = await AiSettingsStore.load();
      expect(initial, isA<AiConfig>(),
          reason: 'web 端空 localStorage → load 返回 fromEnv()');

      // 2. save 一份 config → 写 localStorage（mock）
      final cfg = AiConfig(
        provider: AiConfig.providerDeepSeek,
        baseUrl: 'https://api.deepseek.com',
        apiKey: 'web-test-key',
        model: 'deepseek-flash',
      );
      await AiSettingsStore.save(cfg);
      expect(webStore['ai_config_json'], isNotNull,
          reason: 'save 应写到 web storage（mock）');
      expect(webStore['ai_config_json'], contains('"provider":"deepseek"'),
          reason: 'web storage 内容含 provider=deepseek');
      // 注意：web 端拍板**不加密**（理由见 local_secure_store.dart 文件头），
      // 所以 localStorage 里仍是明文 JSON——这条断言是策略的钉，不是疏忽。
      expect(webStore['ai_config_json'], contains('"apiKey":"web-test-key"'),
          reason: 'web 端维持现状（明文），不参与本机加密');

      // 3. 模拟"刷新页面"：清 webStore + debugWebStorage 重新注入 → load
      webStore.clear();
      final reloaded = await AiSettingsStore.load();
      expect(reloaded.apiKey, isNot('web-test-key'),
          reason: '清空 webStore 后 load 走 fromEnv fallback（apiKey 空）');

      // 4. 重新写入 → load 读出
      webStore['ai_config_json'] =
          '{"provider":"minimaxi","baseUrl":"https://x.com","apiKey":"k","model":"M3"}';
      final reloaded2 = await AiSettingsStore.load();
      expect(reloaded2.apiKey, 'k', reason: 'web 路径写后再 load 读出');
    });

    test('JSON 损坏降级：web 端 localStorage 损坏 → 走 fromEnv fallback',
        () async {
      final webStore = <String, String>{
        'ai_config_json': 'not-valid-json{{{',
      };
      AiSettingsStore.debugWebStorage = webStore;
      AiSettingsStore.debugForceIsWebStorage = true;
      AiSettingsStore.debugFilePath = null;
      AiSettingsStore.debugConfig = null;

      // 损坏 JSON → load 走 try/catch → 返回 fromEnv fallback（不抛）
      final loaded = await AiSettingsStore.load();
      expect(loaded, isA<AiConfig>(),
          reason: '损坏 JSON → 降级到 fromEnv，不抛');
    });
  });

  group('AiChatStore 跨端持久化（v2.12 R1 C P0 #7）', () {
    late Directory tmp;
    late String filePath;

    setUp(() {
      tmp = Directory.systemTemp.createTempSync('ai_chat_test');
      filePath = '${tmp.path}/ai_chat_history.json';
      LocalSecureStore.debugResetHooks();
      LocalSecureStore.debugMachineKeyPath = '${tmp.path}/.machine.key';
      AiChatStore.debugFilePath = filePath;
      AiChatStore.debugWebStorage = null;
      AiChatStore.debugForceIsWebStorage = null;
    });

    tearDown(() {
      AiChatStore.debugResetHooks();
      LocalSecureStore.debugResetHooks();
      if (tmp.existsSync()) tmp.deleteSync(recursive: true);
    });

    test('桌面 / 安卓 File 路径：save 加密写盘 + load 解密读回', () async {
      // 1. 首次启动：磁盘无文件 → load 返空列表
      expect(File(filePath).existsSync(), isFalse);
      final initial = await AiChatStore.load();
      expect(initial, isEmpty, reason: '磁盘无文件 → load 返空列表');

      // 2. save 一些消息 → 加密落盘（路径不变）
      final msgs = [
        {'role': 'user', 'text': 'AaBb 自交 F2 比例？'},
        {'role': 'assistant', 'text': '9:3:3:1（独立遗传）'},
      ];
      await AiChatStore.save(msgs);
      expect(File(filePath).existsSync(), isTrue);
      final raw = File(filePath).readAsStringSync();
      // 核心验收：聊天正文（题目描述 / 可能的人名）不得明文落盘。
      expect(raw, isNot(contains('AaBb')),
          reason: '聊天正文不得以明文出现在磁盘字节里');
      expect(raw, isNot(contains('"role":"user"')),
          reason: '结构化的 role/text 也不该裸露');
      expect(MistakeBookCrypto.isEncryptedEnvelope(raw), isTrue,
          reason: '落盘内容应是可识别的 AES-GCM envelope');
      // 明文可经 readSecure 完整取回。
      final plain = await LocalSecureStore.readSecure(filePath);
      expect(plain, contains('"role":"user"'));
      expect(plain, contains('"role":"assistant"'));

      // 3. 重新 load → 解密读回
      final loaded = await AiChatStore.load();
      expect(loaded, hasLength(2));
      expect(loaded[0]['role'], 'user');
      expect(loaded[0]['text'], 'AaBb 自交 F2 比例？');
      expect(loaded[1]['role'], 'assistant');
      expect(loaded[1]['text'], '9:3:3:1（独立遗传）');
    });

    test('存量兼容：加密改造之前的明文 ai_chat_history.json 仍能读回并升级',
        () async {
      File(filePath).writeAsStringSync(
          '[{"role":"user","text":"旧明文提问"},{"role":"assistant","text":"旧回答"}]');
      final loaded = await AiChatStore.load();
      expect(loaded, hasLength(2), reason: '旧明文必须原样可读');
      expect(loaded[0]['text'], '旧明文提问');

      await AiChatStore.save(loaded);
      final raw = File(filePath).readAsStringSync();
      expect(MistakeBookCrypto.isEncryptedEnvelope(raw), isTrue);
      expect(raw, isNot(contains('旧明文提问')));
      expect((await AiChatStore.load()).last['text'], '旧回答');
    });

    test('损坏密文降级：解不开的 envelope → 空历史，不抛', () async {
      final foreign = await MistakeBookCrypto.encryptJson(
          '[{"role":"user","text":"别人的历史"}]', 'another-machine');
      File(filePath).writeAsStringSync(foreign);
      expect(await AiChatStore.load(), isEmpty,
          reason: '损坏密文按空历史继续，不能挡住 App 启动');
    });

    test('Web 端 localStorage 路径：debugWebStorage round-trip', () async {
      final webStore = <String, String>{};
      AiChatStore.debugWebStorage = webStore;
      AiChatStore.debugForceIsWebStorage = true;
      AiChatStore.debugFilePath = null;

      // 1. 首启：web 端 localStorage 空 → load 返空列表
      final initial = await AiChatStore.load();
      expect(initial, isEmpty,
          reason: 'web 端 localStorage 空 → load 返空列表');

      // 2. save → 写 localStorage
      final msgs = [
        {'role': 'user', 'text': 'web hello'},
        {'role': 'assistant', 'text': 'web hi'},
      ];
      await AiChatStore.save(msgs);
      expect(webStore['ai_chat_history_json'], isNotNull);
      expect(webStore['ai_chat_history_json'], contains('"role":"user"'));
      expect(webStore['ai_chat_history_json'], contains('"web hello"'));

      // 3. 重新 load → 从 webStore 读回
      final loaded = await AiChatStore.load();
      expect(loaded, hasLength(2));
      expect(loaded[0]['text'], 'web hello');
      expect(loaded[1]['text'], 'web hi');
    });

    test('clear() 清空历史', () async {
      final webStore = <String, String>{
        'ai_chat_history_json': '[]',
      };
      AiChatStore.debugWebStorage = webStore;
      AiChatStore.debugForceIsWebStorage = true;
      AiChatStore.debugFilePath = null;

      // 先 save 一些消息
      await AiChatStore.save([{'role': 'user', 'text': 'x'}]);
      expect(webStore['ai_chat_history_json'], contains('"x"'));

      // clear
      await AiChatStore.clear();
      expect(webStore['ai_chat_history_json'], '[]',
          reason: 'clear 后 localStorage 存空数组');
    });
  });

  group('debugResetHooks 清理（v2.12 R1 C P0 #7）', () {
    test('AiSettingsStore.debugResetHooks 清三个 hook', () {
      AiSettingsStore.debugFilePath = '/some/path';
      AiSettingsStore.debugWebStorage = <String, String>{};
      AiSettingsStore.debugForceIsWebStorage = true;

      AiSettingsStore.debugResetHooks();
      expect(AiSettingsStore.debugFilePath, isNull);
      expect(AiSettingsStore.debugWebStorage, isNull);
      expect(AiSettingsStore.debugForceIsWebStorage, isNull);
    });

    test('AiChatStore.debugResetHooks 清三个 hook', () {
      AiChatStore.debugFilePath = '/some/path';
      AiChatStore.debugWebStorage = <String, String>{};
      AiChatStore.debugForceIsWebStorage = true;

      AiChatStore.debugResetHooks();
      expect(AiChatStore.debugFilePath, isNull);
      expect(AiChatStore.debugWebStorage, isNull);
      expect(AiChatStore.debugForceIsWebStorage, isNull);
    });
  });
}
