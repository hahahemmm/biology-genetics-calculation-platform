// ai_minimax_migration_test.dart —— MiniMax 通道迁移契约（v2.20.0 修订）
//
// 背景：v2.20.0 把 API key 从源码里彻底删除。`AiConfig.presetMinimax`
// 不再带 key（apiKey 只取 `--dart-define=MINIMAX_API_KEY` 的编译期注入
// 值，缺省空串）；旧共享 key（v2.10 泄露、已在平台撤销）只保留 SHA-256
// 指纹用于识别。
//
// `AiSettingsStore._fromJson` 对 provider=minimax 的存量配置的迁移契约：
//   ① 退役模型名（`retiredMinimaxModels`，**大小写不敏感**；空模型名按
//      「未指定」同样处理）→ 一律更新为 presetMinimax.model；
//      用户有效的 apiKey / baseUrl **原样保留**；
//   ② 命中已撤销的旧共享 key（指纹比对）→ **只**用 MINIMAX_API_KEY 注入值
//      替换 key；注入值为空则**清空**（已撤销的凭据不得继续当运行时配置）；
//   ③ key 本来就为空 + 内置通道存在（minimaxApiKeyFromEnv 非空）→ 补内置
//      key，只在内存生效、**不写盘**；没有内置通道（注入空）→ 保持为空，
//      绝不塞任何共享 key。用户自己填过的 key 一律原样保留。
//   ④ 其余通道（DeepSeek / custom）：key 为空 + 内置通道存在 + baseUrl 仍是
//      该通道预设地址 → 整份回落 presetMinimax；用户自填的第三方 baseUrl
//      不回落（内置 key 不得发到第三方），保持「未配置」。
//
// 覆盖：
//   a) 旧共享 key + MiniMax-M3 + env 空 → key 清空、model 换预设模型名
//   a1) 旧共享 key + env 有值 → key = env 注入值（只换 key）
//   a2) 退役模型名 + 用户自填 key → 仅 model 替换，key/baseUrl 原样
//   b) 空 key（含字段缺失）+ 内置通道 → 补内置 key（不写盘）+ 退役模型更新
//   b1) 无内置通道 → 空 key 保持空（不塞 key）
//   c) 自填 key + 未退役模型 → 原样保留，绝不迁移
//   d) provider=deepseek 且 key 非空 → 完全不受迁移影响
//   d1) provider=deepseek + 空 key + 预设地址 → 整份回落内置通道
//   d2) 用户自填第三方 baseUrl + 空 key → 不回落、不发内置 key
//   d3) 空 key + 无内置通道 → 非 MiniMax 通道行为不变
//   e) Web 分支（localStorage）同样走迁移——两个 load 分支都正确 await
//   f) 指纹识别本身：无注入时虚构 key 一律不命中（不误伤用户 key）
//
// 注入方式同 settings_page_test.dart：debugFilePath 临时文件 hook
//（load → readSecure 明文嗅探原样放行 → _fromJson），机器密钥收进
// 临时目录，不脏写真实 ~/.biology_app。
//
// ⚠️ 本文件只允许出现**虚构** key（fake/xxx），绝不写真实 key；
// 旧共享 key 的正身已不在源码里（只剩指纹），所以用
// `AiConfig.debugRetiredMinimaxKey` 注入一个虚构「旧 key」来驱动分支。

import 'dart:io';

import 'package:biology/services/ai_client.dart';
import 'package:biology/pages/settings_page.dart';
import 'package:biology/services/local_secure_store.dart';
import 'package:flutter_test/flutter_test.dart';

/// 虚构的「已撤销旧共享 key」（测试专用，与真实 key 无关）。
const String kFakeRetiredKey = 'sk-fake-retired-shared-0001';

/// 虚构的「用户自填有效 key」。
const String kFakeUserKey = 'sk-fake-user-own-0002';

/// 虚构的「env 注入值」。
const String kFakeEnvKey = 'sk-fake-env-injected-0003';

void main() {
  late Directory tmp;
  late String filePath;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('ai_minimax_migration_test');
    filePath = '${tmp.path}/ai_config.json';
    LocalSecureStore.debugResetHooks();
    LocalSecureStore.debugMachineKeyPath = '${tmp.path}/.machine.key';
    AiSettingsStore.debugConfig = null;
    AiSettingsStore.debugFilePath = filePath;
    AiSettingsStore.debugWebStorage = null;
    AiSettingsStore.debugForceIsWebStorage = null;
    AiConfig.debugResetKeyHooks();
  });

  tearDown(() {
    AiSettingsStore.debugResetHooks();
    AiSettingsStore.debugConfig = null;
    LocalSecureStore.debugResetHooks();
    AiConfig.debugResetKeyHooks();
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  /// 把存量明文 JSON 落盘后 load——与老用户磁盘现状同构
  ///（v2.19.37 加密改造之前的明文 ai_config.json 形态）。
  Future<AiConfig> loadFromLegacyJson(String json) async {
    File(filePath).writeAsStringSync(json);
    return AiSettingsStore.load();
  }

  group('MiniMax 通道迁移（AiSettingsStore._fromJson）', () {
    test('a) 旧共享 key + MiniMax-M3，env 空 → key 清空、model 换新', () async {
      AiConfig.debugRetiredMinimaxKey = kFakeRetiredKey;
      AiConfig.debugMinimaxApiKeyEnv = ''; // 环境里没有可替换的 key

      final loaded = await loadFromLegacyJson(
        '{"provider":"minimax","baseUrl":"https://api.minimaxi.com/v1",'
        '"apiKey":"$kFakeRetiredKey","model":"MiniMax-M3"}',
      );

      expect(
        loaded.model,
        AiConfig.presetMinimax.model,
        reason: '已下线的 MiniMax-M3 必须被替换为预设模型名',
      );
      expect(
        loaded.apiKey,
        isEmpty,
        reason: '已撤销的旧共享 key 不得继续作为运行时配置；env 为空 → 清空',
      );
      expect(loaded.provider, AiConfig.providerMinimax);
      expect(
        loaded.baseUrl,
        'https://api.minimaxi.com/v1',
        reason: '有效 baseUrl 保留',
      );
      expect(loaded.isConfigured, isFalse, reason: '清空 key 后必须显示为「未配置」，引导用户自填');
    });

    test('a1) 旧共享 key + MINIMAX_API_KEY 有值 → 只换 key，保留其余', () async {
      AiConfig.debugRetiredMinimaxKey = kFakeRetiredKey;
      AiConfig.debugMinimaxApiKeyEnv = kFakeEnvKey;

      final loaded = await loadFromLegacyJson(
        '{"provider":"minimax","baseUrl":"https://api.minimaxi.com/v1",'
        '"apiKey":"$kFakeRetiredKey","model":"MiniMax-M9-Pro"}',
      );

      expect(loaded.apiKey, kFakeEnvKey, reason: '命中旧共享 key → 仅用 env 注入值替换');
      expect(loaded.model, 'MiniMax-M9-Pro', reason: '未退役模型名不该被动（本条只验 key 替换）');
      expect(loaded.baseUrl, 'https://api.minimaxi.com/v1');
      expect(loaded.isConfigured, isTrue);
    });

    test('a2) 退役模型 + 自填 key → 仅替换 model，key/baseUrl 保留', () async {
      // 用户自填的有效 key 绝不能被任何共享/注入 key 静默覆盖。
      AiConfig.debugRetiredMinimaxKey = kFakeRetiredKey;
      AiConfig.debugMinimaxApiKeyEnv = kFakeEnvKey;

      for (final m in AiConfig.retiredMinimaxModels) {
        final loaded = await loadFromLegacyJson(
          '{"provider":"minimax","baseUrl":"https://api.minimaxi.com/v1",'
          '"apiKey":"$kFakeUserKey","model":"$m"}',
        );
        expect(
          loaded.model,
          AiConfig.presetMinimax.model,
          reason: '$m 已下线，模型名必须被替换为预设模型名',
        );
        expect(loaded.apiKey, kFakeUserKey, reason: '用户自填的有效 key 必须原样保留');
        expect(
          loaded.baseUrl,
          'https://api.minimaxi.com/v1',
          reason: '自填 baseUrl 原样保留',
        );
        expect(loaded.provider, AiConfig.providerMinimax);
      }

      // 手滑小写 minimax-m3 也触发替换（大小写不敏感比对）。
      final lower = await loadFromLegacyJson(
        '{"provider":"minimax","baseUrl":"https://api.minimaxi.com/v1",'
        '"apiKey":"$kFakeUserKey","model":"minimax-m3"}',
      );
      expect(
        lower.model,
        AiConfig.presetMinimax.model,
        reason: '小写退役模型名也要命中（toLowerCase 归一比对）',
      );
      expect(lower.apiKey, kFakeUserKey, reason: '小写命中同样只换 model，不动 key');
    });

    test('b) 空 key + 内置通道 → 补内置 key（只在内存），退役模型照样更新', () async {
      // v2.25 口径：内置 key 随包分发后，空 key 必须回落内置通道——否则老师
      // 只要在设置页点过一次保存，就永久停在「未配置」。回落**不写盘**。
      AiConfig.debugMinimaxApiKeyEnv = kFakeEnvKey;
      const legacyJson = '{"provider":"minimax",'
          '"baseUrl":"https://api.minimaxi.com/v1",'
          '"apiKey":"","model":"MiniMax-M3"}';
      var loaded = await loadFromLegacyJson(legacyJson);
      expect(loaded.apiKey, kFakeEnvKey, reason: '空 key → 回落内置 key');
      expect(loaded.isConfigured, isTrue, reason: '回落内置 key 后开箱即可用');
      expect(loaded.model, AiConfig.presetMinimax.model, reason: '退役模型照样更新');
      expect(loaded.baseUrl, 'https://api.minimaxi.com/v1',
          reason: '有效 baseUrl 原样保留');
      expect(File(filePath).readAsStringSync(), legacyJson,
          reason: '回落只在内存生效，不得回写磁盘');

      // apiKey 字段整个缺失 → 同样按空 key 回落。
      loaded = await loadFromLegacyJson(
        '{"provider":"minimax","baseUrl":"https://api.minimaxi.com/v1",'
        '"model":"MiniMax-M3"}',
      );
      expect(loaded.apiKey, kFakeEnvKey);
      expect(loaded.model, AiConfig.presetMinimax.model);

      // 模型字段缺失 → 用预设模型名（等价「未指定」）；自填 key 不动。
      loaded = await loadFromLegacyJson(
        '{"provider":"minimax","baseUrl":"https://api.minimaxi.com/v1",'
        '"apiKey":"$kFakeUserKey"}',
      );
      expect(loaded.model, AiConfig.presetMinimax.model);
      expect(loaded.apiKey, kFakeUserKey);
    });

    test('b1) 没有内置通道（注入空）→ 空 key 保持为空，绝不塞 key', () async {
      AiConfig.debugMinimaxApiKeyEnv = '';
      final loaded = await loadFromLegacyJson(
        '{"provider":"minimax","baseUrl":"https://api.minimaxi.com/v1",'
        '"apiKey":"","model":"MiniMax-M3"}',
      );
      expect(loaded.apiKey, isEmpty, reason: '没有内置 key 就没有可回落的凭据');
      expect(loaded.isConfigured, isFalse);
    });

    test('c) 自填 key + 未退役模型 → 原样保留，不迁移', () async {
      final loaded = await loadFromLegacyJson(
        '{"provider":"minimax","baseUrl":"https://api.minimaxi.com/v1",'
        '"apiKey":"$kFakeUserKey","model":"MiniMax-M9"}',
      );
      expect(loaded.provider, AiConfig.providerMinimax);
      expect(loaded.baseUrl, 'https://api.minimaxi.com/v1');
      expect(loaded.apiKey, kFakeUserKey, reason: '用户手填的有效 key 绝不能被覆盖或清空');
      expect(loaded.model, 'MiniMax-M9', reason: '未退役模型名原样读回');
    });

    test('d) provider=deepseek 且 key 非空 → 完全不受迁移影响', () async {
      AiConfig.debugMinimaxApiKeyEnv = kFakeEnvKey; // 内置通道在场也不得顶替用户 key
      final loaded = await loadFromLegacyJson(
        '{"provider":"deepseek","baseUrl":"https://api.deepseek.com",'
        '"apiKey":"sk-fake-ds-own","model":"deepseek-flash"}',
      );
      expect(loaded.provider, AiConfig.providerDeepSeek);
      expect(loaded.baseUrl, 'https://api.deepseek.com');
      expect(loaded.apiKey, 'sk-fake-ds-own', reason: '用户自填 key 是用户资产');
      expect(loaded.model, 'deepseek-flash');
    });

    test('d1) provider=deepseek + 空 key（预设地址）→ 整份回落内置通道', () async {
      // 老师打开设置页点过一次保存（什么都没填）就是这个形态：
      // 空 key 的配置本来就不可能工作，整份回落才叫「开箱即用」。
      AiConfig.debugMinimaxApiKeyEnv = kFakeEnvKey;
      const emptyKeyJson = '{"provider":"deepseek",'
          '"baseUrl":"https://api.deepseek.com",'
          '"apiKey":"","model":"deepseek-flash"}';
      final loaded = await loadFromLegacyJson(emptyKeyJson);
      expect(loaded.provider, AiConfig.providerMinimax);
      expect(loaded.baseUrl, AiConfig.presetMinimax.baseUrl,
          reason: 'MiniMax key 不能留在 DeepSeek 地址上（打不通），必须整份换');
      expect(loaded.model, AiConfig.presetMinimax.model);
      expect(loaded.apiKey, kFakeEnvKey);
      expect(loaded.isConfigured, isTrue, reason: '内置通道直接可用');
      expect(File(filePath).readAsStringSync(), emptyKeyJson,
          reason: '回落只在内存生效，不写盘');
    });

    test('d2) 用户自填第三方 baseUrl + 空 key → 不回落，保持未配置', () async {
      // 内置 key 是 MiniMax 的凭据：拼到第三方地址上既打不通，也算泄露。
      AiConfig.debugMinimaxApiKeyEnv = kFakeEnvKey;
      final loaded = await loadFromLegacyJson(
        '{"provider":"custom","baseUrl":"https://my-gateway.example.com/v1",'
        '"apiKey":"","model":"gpt-x"}',
      );
      expect(loaded.provider, AiConfig.providerCustom);
      expect(loaded.baseUrl, 'https://my-gateway.example.com/v1',
          reason: '用户填的地址不得被覆盖');
      expect(loaded.apiKey, isEmpty, reason: '内置 key 不得发到第三方地址');
      expect(loaded.isConfigured, isFalse);
    });

    test('d3) 空 key + 没有内置通道 → 非 MiniMax 通道行为不变', () async {
      AiConfig.debugMinimaxApiKeyEnv = '';
      final loaded = await loadFromLegacyJson(
        '{"provider":"deepseek","baseUrl":"https://api.deepseek.com",'
        '"apiKey":"","model":"deepseek-flash"}',
      );
      expect(loaded.provider, AiConfig.providerDeepSeek);
      expect(loaded.apiKey, isEmpty);
      expect(loaded.isConfigured, isFalse, reason: '没有内置 key 才显示「未配置」');
    });

    test('e) Web 分支（localStorage）同样 await 迁移结果', () async {
      // load 的两个分支都必须 await _fromJson：否则迁移后的配置根本
      // 没被返回，且异常会绕过 catch。
      final webStore = <String, String>{
        'ai_config_json':
            '{"provider":"minimax",'
            '"baseUrl":"https://api.minimaxi.com/v1",'
            '"apiKey":"$kFakeRetiredKey","model":"MiniMax-M3"}',
      };
      AiSettingsStore.debugWebStorage = webStore;
      AiSettingsStore.debugForceIsWebStorage = true;
      AiSettingsStore.debugFilePath = null;
      AiConfig.debugRetiredMinimaxKey = kFakeRetiredKey;
      AiConfig.debugMinimaxApiKeyEnv = '';

      final loaded = await AiSettingsStore.load();
      expect(
        loaded.model,
        AiConfig.presetMinimax.model,
        reason: 'web 分支也要拿到迁移后的模型名',
      );
      expect(loaded.apiKey, isEmpty, reason: 'web 分支同样要清掉已撤销的旧共享 key');
    });
  });

  group('旧共享 key 指纹识别（AiConfig.isRetiredMinimaxKey）', () {
    test('无注入时虚构 key 一律不命中（不误伤用户 key）', () async {
      for (final k in [kFakeUserKey, kFakeEnvKey, 'sk-anything-else-9']) {
        expect(
          await AiConfig.isRetiredMinimaxKey(k),
          isFalse,
          reason: '指纹比对不得把普通用户 key 误判成旧共享 key',
        );
      }
      expect(
        await AiConfig.isRetiredMinimaxKey(''),
        isFalse,
        reason: '空 key 直接不命中（免无意义哈希）',
      );
    });

    test('指纹常量是 64 位小写 hex（不含 key 原文）', () {
      final f = AiConfig.retiredMinimaxKeySha256;
      expect(f, matches(RegExp(r'^[0-9a-f]{64}$')), reason: 'SHA-256 hex 指纹形态');
      expect(f.startsWith('sk-'), isFalse, reason: '常量必须是指纹，不能是 key 原文');
    });

    test('注入虚构旧 key 后命中（测试旁路）', () async {
      AiConfig.debugRetiredMinimaxKey = kFakeRetiredKey;
      expect(await AiConfig.isRetiredMinimaxKey(kFakeRetiredKey), isTrue);
      expect(await AiConfig.isRetiredMinimaxKey(kFakeUserKey), isFalse);
    });
  });
}
