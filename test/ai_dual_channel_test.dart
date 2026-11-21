// ai_dual_channel_test.dart —— v2.15：AI 双通道（DeepSeek 默认 / MiniMax 保留）
//
// 覆盖：
//   1. AiConfig 预设：默认通道 = DeepSeek（deepseek-flash 多模态）；
//      presetMinimax 保留（M3.1-Flash，注入构建内置共享 key）。
//   2. 存量迁移：旧 'opencode'  provider 字面值 → DeepSeek 预设。
//   3. provider 标识与 copyWith 保持。
//   4. AiClient.splitThink：推理模型把 <think>...</think> 内联在
//      content 里——剥离为 (正文, 思维链)，含未闭合/多段/无标签分支。
import 'package:biology/services/ai_client.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AiConfig 双通道预设', () {
    test('默认通道为 DeepSeek（deepseek-flash 多模态）', () {
      // v2.11 H1 修订：const AiConfig() 默认 apiKey 为空（避免烤进 AOT），
      // baseUrl/model/provider 保留默认值以避免 widget 渲染变化。
      const c = AiConfig.presetDeepSeek;
      expect(c.provider, AiConfig.providerDeepSeek);
      expect(c.baseUrl, 'https://api.deepseek.com');
      expect(c.model, 'deepseek-flash');
      expect(c.apiKey, isEmpty,
          reason: 'DeepSeek 无预置 key，用户设置页自填');
    });

    test('v2.11 H1：const AiConfig() 默认 apiKey 为空（关键资产）', () {
      // 仅 apiKey 默认空——baseUrl/model/provider 保留避免 widget 行为变化
      const c = AiConfig();
      expect(c.apiKey, isEmpty,
          reason: 'apiKey 是关键资产，const 默认必须空');
      expect(c.provider, AiConfig.providerDeepSeek,
          reason: 'v2.15 起默认通道 = DeepSeek');
      expect(c.baseUrl, 'https://api.deepseek.com');
      expect(c.model, 'deepseek-flash');
      expect(c.isConfigured, isFalse,
          reason: '空 apiKey → isConfigured=false');
    });

    test('MiniMax 预设保留（M3.1-Flash，key 仅由 dart-define 注入）', () {
      const c = AiConfig.presetMinimax;
      expect(c.provider, AiConfig.providerMinimax);
      expect(c.baseUrl, 'https://api.minimaxi.com/v1');
      expect(c.model, 'MiniMax-M3.1-Flash',
          reason: '官方现名 MiniMax-M3.1-Flash（2026-10-19），Preview 已转正');
      // 开源版口径：apiKey 只来自 MINIMAX_API_KEY 注入，源码不含 key。
      expect(c.apiKey, AiConfig.minimaxApiKeyFromEnv,
          reason: '预设 key 恒等于运行期读取入口（dart-define 注入值）');
      expect(c.apiKey, isEmpty, reason: '未注入即空，由用户手填');
      expect(c.isConfigured, isFalse, reason: '空 key ⇒ 未配置');
    });

    test('v2.15 存量迁移：旧 opencode 字面值映射到 DeepSeek 预设', () {
      expect(AiConfig.presetOf('opencode'), AiConfig.presetDeepSeek,
          reason: 'OpenCode 网关已下线，旧配置整体迁到 DeepSeek');
      expect(AiConfig.presetOf('opencode')!.model, 'deepseek-flash');
    });

    test('presetOf 映射；custom/未知返回 null', () {
      expect(AiConfig.presetOf(AiConfig.providerMinimax)!.model,
          'MiniMax-M3.1-Flash');
      expect(AiConfig.presetOf(AiConfig.providerDeepSeek)!.model,
          'deepseek-flash');
      expect(AiConfig.presetOf(AiConfig.providerCustom), isNull);
      expect(AiConfig.presetOf('unknown'), isNull);
    });

    test('copyWith 保留/覆盖 provider', () {
      const c = AiConfig.presetDeepSeek;
      final c2 = c.copyWith(provider: AiConfig.providerMinimax);
      expect(c2.provider, AiConfig.providerMinimax);
      expect(c2.baseUrl, c.baseUrl); // 未覆盖字段保留
      expect(c.copyWith().provider, AiConfig.providerDeepSeek);
    });
  });

  group('AiClient.splitThink（推理模型内联思维链剥离）', () {
    test('无 think 标签：原文返回，思维链 null', () {
      final (body, think) = AiClient.splitThink('答案是 1/4。');
      expect(body, '答案是 1/4。');
      expect(think, isNull);
    });

    test('标准形态：think 在前正文在后', () {
      const raw = '<think>先算配子比例</think>\n\n正常';
      final (body, think) = AiClient.splitThink(raw);
      expect(body, '正常');
      expect(think, '先算配子比例');
    });

    test('多段 think 合并，正文拼接', () {
      const raw = '<think>第一段</think>甲<think>第二段</think>乙';
      final (body, think) = AiClient.splitThink(raw);
      expect(body, '甲乙');
      expect(think, '第一段第二段');
    });

    test('未闭合 think（流式截断）：其余全算思维链', () {
      const raw = '前文<think>推理到一半';
      final (body, think) = AiClient.splitThink(raw);
      expect(body, '前文');
      expect(think, '推理到一半');
    });

    test('空 think 段不产生思维链', () {
      final (body, think) = AiClient.splitThink('<think></think>正文');
      expect(body, '正文');
      expect(think, isNull);
    });
  });
}
