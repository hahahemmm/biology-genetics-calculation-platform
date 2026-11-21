// ai_config_env_test.dart —— v2.11 H1 AI key 资产化测试
//
// 验证 AiConfig.fromEnv 工厂 + const 预置的 debug/release 行为分流。
//
// 修复前：const AiConfig() 默认值把内部 key 烤进 AOT，
// installers/biology_v2.3.1_android.apk 已携带出厂。
//
// 修复后：
//   - const AiConfig() 默认值为空（不烤 key）
//   - AiConfig.fromEnv() 工厂：
//     * release + 有 --dart-define：取注入值
//     * release + 无 --dart-define：取空值（isConfigured=false）
//     * debug：fallback 到 const 预置
//   - 用户手填 ai_config.json 优先（AiSettingsStore.load）

import 'package:biology/services/ai_client.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('v2.11 H1：AiConfig.fromEnv 工厂 + const 预置', () {
    test('const AiConfig() 默认值：apiKey 为空（避免烤进 AOT），baseUrl/model 保留', () {
      // v2.11 H1 修订：仅 apiKey 默认空（关键资产），baseUrl/model/provider
      // 保留默认值避免 widget 行为变化（golden screenshot 重录成本高）
      const c = AiConfig();
      expect(c.apiKey, isEmpty,
          reason: 'apiKey 是关键资产，const 默认必须空，走 fromEnv 注入');
      expect(c.baseUrl, 'https://api.deepseek.com',
          reason: 'baseUrl 公开信息，保留默认值避免 widget 渲染变化');
      expect(c.model, 'deepseek-flash');
      expect(c.provider, AiConfig.providerDeepSeek,
          reason: 'v2.15 起默认通道 = DeepSeek');
      expect(c.isConfigured, isFalse,
          reason: '空 apiKey → isConfigured=false（即使 baseUrl/model 有值）');
    });

    test('const AiConfig(provider: providerCustom) 可显式构造', () {
      const c = AiConfig(
        provider: AiConfig.providerCustom,
        baseUrl: 'https://api.example.com/v1',
        apiKey: 'sk-user-supplied',
        model: 'user-model',
      );
      expect(c.provider, AiConfig.providerCustom);
      expect(c.apiKey, 'sk-user-supplied');
      expect(c.isConfigured, isTrue);
    });

    test('presetMinimax 源码不含 key，未注入即空', () {
      // 开源版口径：源码不含任何 API key，apiKey 只能由
      // `--dart-define=MINIMAX_API_KEY` 注入（flutter test 未注入 define）。
      expect(AiConfig.presetMinimax.provider, AiConfig.providerMinimax);
      expect(AiConfig.presetMinimax.baseUrl, 'https://api.minimaxi.com/v1');
      expect(AiConfig.presetMinimax.model, 'MiniMax-M3.1-Flash');
      expect(AiConfig.presetMinimax.apiKey, AiConfig.minimaxApiKeyFromEnv);
      expect(AiConfig.presetMinimax.apiKey, isEmpty,
          reason: '源码不得携带 key，未注入即空');
      expect(AiConfig.presetMinimax.isConfigured, isFalse);
    });

    test('presetDeepSeek 无预置 key（用户设置页自填）', () {
      expect(AiConfig.presetDeepSeek.provider, AiConfig.providerDeepSeek);
      expect(AiConfig.presetDeepSeek.apiKey, isEmpty,
          reason: 'DeepSeek 官方 API 无预置 key，用户自填');
      expect(AiConfig.presetDeepSeek.isConfigured, isFalse);
      expect(AiConfig.presetDeepSeek.model, 'deepseek-flash');
      expect(AiConfig.presetDeepSeek.baseUrl, 'https://api.deepseek.com');
    });

    test('fromEnv() 工厂返回 AiConfig 实例', () {
      final c = AiConfig.fromEnv();
      // 真实值取决于 build mode + dart-define，无法在 test 断言。
      // 重点：返回非 null 类型正确的实例。
      expect(c, isA<AiConfig>());
    });

    test('fromEnv(presetOverride: ...) 接受 debug 模式 override', () {
      const override = AiConfig(
        baseUrl: 'https://test.example.com/v1',
        apiKey: 'test-key',
        model: 'test-model',
      );
      final c = AiConfig.fromEnv(presetOverride: override);
      // 有 --dart-define 注入的 MiniMax key 时第一档优先：override 只在
      // 「无 MiniMax key」的 debug 构建才生效（kReleaseMode 是编译期常量）。
      expect(c, isA<AiConfig>());
      if (AiConfig.minimaxApiKeyFromEnv.isNotEmpty) {
        expect(c.provider, AiConfig.providerMinimax,
            reason: '有内置 key ⇒ fromEnv 恒定返回 MiniMax 预设');
      }
    });

    test('fromEnv 在 test 环境无注入 key ⇒ 回落 DeepSeek 预设', () {
      // 开源版口径：源码不含 key，test 环境（不带 --dart-define）拿不到
      // MiniMax key ⇒ debug 分支返回 DeepSeek 预设，等待用户自填。
      final c = AiConfig.fromEnv();
      expect(c.apiKey, AiConfig.minimaxApiKeyFromEnv);
      expect(c.apiKey, isEmpty, reason: '未注入 ⇒ 空 key');
      expect(c.provider, AiConfig.providerDeepSeek,
          reason: '无 MiniMax key ⇒ 走 DeepSeek 默认通道');
      expect(c.isConfigured, isFalse, reason: '空 key ⇒ 未配置，设置页引导');
    });
  });
}
