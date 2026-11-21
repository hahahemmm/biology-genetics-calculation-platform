// MiniMax 通道配置回归测试（纯 Dart，离线）。
// 钉住模型名 / baseUrl / 退役名单 / reasoning_effort，防止回退成 Preview
// 或退役名单自迁移死循环。请求体断言走 debugHttpClientFactory 注入
// MockClient 截获 body，绝不联网。
import 'dart:convert';

import 'package:biology/services/ai_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// 明显的虚构 key：只用来满足 isConfigured 的非空校验，非任何真实凭据形状。
const String kFakeApiKey = 'sk-fake-for-test';

void main() {
  group('AiConfig MiniMax 通道预设', () {
    test('presetMinimax.model 钉住 MiniMax-M3.1-Flash，不得回退成 Preview', () {
      expect(AiConfig.presetMinimax.model, 'MiniMax-M3.1-Flash');
    });

    test('presetMinimax.baseUrl 保持官方 https 端点', () {
      expect(AiConfig.presetMinimax.baseUrl, 'https://api.minimaxi.com/v1');
    });

    test('退役名单含旧名 Preview、不含新名（防自迁移死循环）', () {
      expect(
        AiConfig.retiredMinimaxModels,
        contains('MiniMax-M3.1-Flash-Preview'),
      );
      expect(
        AiConfig.retiredMinimaxModels,
        isNot(contains('MiniMax-M3.1-Flash')),
        reason: '新名若进退役名单，读回时会无限迁移到自己',
      );
    });

    test('minimaxReasoningEffort 锁死 max', () {
      expect(AiConfig.minimaxReasoningEffort, 'max');
    });

    test('presetMinimax.apiKey 源码无 key：未注入即空', () {
      // 开源版口径：源码不含任何 key；本测试进程没带 --dart-define ⇒ 空串。
      expect(AiConfig.presetMinimax.apiKey, AiConfig.minimaxApiKeyFromEnv);
      expect(AiConfig.presetMinimax.apiKey, isEmpty);
      expect(AiConfig.presetMinimax.isConfigured, isFalse);
    });
  });

  group('AiClient.chat 请求体 reasoning_effort（MockClient，离线）', () {
    late List<String> capturedBodies;

    setUp(() {
      capturedBodies = <String>[];
      AiClient.debugHttpClientFactory = () => MockClient((req) async {
            capturedBodies.add(req.body);
            return http.Response(
              jsonEncode({
                'choices': [
                  {
                    'message': {'content': 'ok'}
                  }
                ],
              }),
              200,
              headers: {'content-type': 'application/json'},
            );
          });
    });

    tearDown(() => AiClient.debugHttpClientFactory = null);

    test('MiniMax 通道请求体含 reasoning_effort=max，chat 正常返回', () async {
      final client = AiClient(const AiConfig(
        provider: AiConfig.providerMinimax,
        baseUrl: 'https://api.minimaxi.com/v1',
        apiKey: kFakeApiKey,
        model: 'MiniMax-M3.1-Flash',
      ));

      final res = await client.chat([const AiMessage('user', 'hi')]);

      expect(res.ok, isTrue, reason: '200 合法响应不得进错误分支');
      expect(res.content, 'ok');
      expect(capturedBodies, hasLength(1));
      final body = jsonDecode(capturedBodies.single) as Map<String, dynamic>;
      expect(body['reasoning_effort'], 'max');
    });

    test('DeepSeek 通道请求体不含 reasoning_effort 键', () async {
      final client = AiClient(const AiConfig(
        provider: AiConfig.providerDeepSeek,
        baseUrl: 'https://api.deepseek.com',
        apiKey: kFakeApiKey,
        model: 'deepseek-flash',
      ));

      final res = await client.chat([const AiMessage('user', 'hi')]);

      expect(res.ok, isTrue, reason: '200 合法响应不得进错误分支');
      expect(res.content, 'ok');
      expect(capturedBodies, hasLength(1));
      final body = jsonDecode(capturedBodies.single) as Map<String, dynamic>;
      expect(
        body.containsKey('reasoning_effort'),
        isFalse,
        reason: '其它通道不得带 MiniMax 专属字段',
      );
    });
  });
}
