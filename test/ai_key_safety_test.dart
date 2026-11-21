// ai_key_safety_test.dart —— 凭据安全回归（v2.20.0）
//
// 本轮把 API key 从源码里彻底移除（只剩旧共享 key 的 SHA-256 指纹），
// 顺手补上「错误文本脱敏」。本文件钉住三件事：
//
//   1. redactSensitive：Bearer / sk- 长 token / URL query 里的
//      api_key·key·token 等值必须被抹掉，而**排障信息不许一起消失**
//      （状态码、原因文案、模型名都要留）。
//   2. AiClient 的错误出口也走脱敏——用 package:http 的 MockClient 注入
//      假响应，全程离线，绝不联网。
//   3. 源码扫描：lib/ 下不允许出现任何长形态的裸 key 字面量
//      （扫描正则自身也不得构成假阳性——它只在 test/ 出现，扫的是 lib/）。
//
// ⚠️ 本文件里的 key 全是虚构串（fake / 0000 形态），绝不写真实 key。

import 'dart:convert';
import 'dart:io';

import 'package:biology/services/ai_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// 虚构 token：够长（触发 sk- 长 token 规则），但与任何真实 key 无关。
const String kFakeLongToken = 'sk-fake-0123456789abcdefghijklmnop';

void main() {
  group('redactSensitive（统一脱敏）', () {
    test('Authorization: Bearer <token> → Bearer ***', () {
      const raw =
          'ClientException: Bad header '
          'Authorization: Bearer abcdefgh1234567890 (host example.com)';
      final out = redactSensitive(raw);
      expect(out, contains('Bearer ***'));
      expect(out, isNot(contains('abcdefgh1234567890')));
      // 排障信息保留
      expect(out, contains('ClientException'));
      expect(out, contains('host example.com'));
    });

    test('sk- 长 token → sk-***', () {
      final out = redactSensitive(
        'Incorrect API key provided: $kFakeLongToken',
      );
      expect(out, contains('sk-***'));
      expect(out, isNot(contains('0123456789abcdefghijklmnop')));
      expect(
        out,
        contains('Incorrect API key provided'),
        reason: '原因文案不许被一起抹掉',
      );
    });

    test('URL query 里的 api_key / key / token / access_token 值被抹', () {
      const raw =
          'GET https://api.example.com/v1/chat?api_key=AAAA1111'
          '&key=BBBB2222&token=CCCC3333&access_token=DDDD4444&model=x';
      final out = redactSensitive(raw);
      expect(out, contains('api_key=***'));
      expect(out, contains('key=***'));
      expect(out, contains('token=***'));
      expect(out, contains('access_token=***'));
      for (final leaked in ['AAAA1111', 'BBBB2222', 'CCCC3333', 'DDDD4444']) {
        expect(out, isNot(contains(leaked)), reason: 'query 值不得残留');
      }
      expect(out, contains('&model=x'), reason: '非敏感 query 参数原样保留（排障需要）');
      expect(
        out,
        contains('https://api.example.com/v1/chat'),
        reason: 'URL 主体保留',
      );
    });

    test('不误伤：模型名 / 短片段 / 普通错误文案原样保留', () {
      for (final keep in [
        '401: API Key 无效或已过期。',
        '模型 MiniMax-M3.1-Flash-Preview 不存在',
        'deepseek-flash',
        'sk-短', // 不足 8 字符，不按长 token 脱敏
      ]) {
        expect(redactSensitive(keep), keep, reason: '正常文本不得被脱敏改写：$keep');
      }
    });

    test('超长文本截断且截断后不残留被抹后的尾部凭据', () {
      final tail = 'x' * 2000;
      final raw = '$kFakeLongToken ${'a' * 900}$tail';
      final out = redactSensitive(raw, maxLength: 200);
      expect(out.length, lessThan(260), reason: '截断生效');
      expect(out, contains('已截断'));
      expect(out, isNot(contains('0123456789abcdefghijklmnop')));
    });

    test('空串直接返回', () {
      expect(redactSensitive(''), '');
    });
  });

  group('AiClient 错误出口脱敏（MockClient，离线）', () {
    AiClient client(String key) => AiClient(
      AiConfig(
        provider: AiConfig.providerMinimax,
        baseUrl: 'https://api.minimaxi.com/v1',
        apiKey: key,
        model: 'MiniMax-M3.1-Flash-Preview',
      ),
    );

    tearDown(() => AiClient.debugHttpClientFactory = null);

    test('401 回显 key：错误文本脱敏，但保留 401 + 原因', () async {
      AiClient.debugHttpClientFactory = () => MockClient(
        (req) async => http.Response(
          jsonEncode({
            'error': {'message': 'Incorrect API key provided: $kFakeLongToken'},
          }),
          401,
          headers: {'content-type': 'application/json'},
        ),
      );

      final res = await client(kFakeLongToken)
          .chat([const AiMessage('user', 'hi')]);

      expect(res.ok, isFalse);
      expect(res.error, contains('401'));
      expect(
        res.error,
        contains('Incorrect API key provided'),
        reason: '有效错误原因必须保留，否则用户无从下手',
      );
      expect(
        res.error,
        isNot(contains('0123456789abcdefghijklmnop')),
        reason: '错误文本不得回显 key 片段',
      );
      expect(res.error, contains('sk-***'));
      // toString 走的是同一个 error 字段，同样干净。
      expect(res.toString(), isNot(contains('0123456789abcdefghijklmnop')));
    });

    test('非 JSON 错误体里的 query 凭据也被抹掉', () async {
      AiClient.debugHttpClientFactory = () => MockClient(
        (req) async => http.Response(
          'upstream rejected POST https://relay.example.com/v1/chat'
          '?api_key=LEAKME9999&model=y',
          502,
          headers: {'content-type': 'text/plain'},
        ),
      );

      final res = await client(kFakeLongToken)
          .chat([const AiMessage('user', 'hi')]);

      expect(res.ok, isFalse);
      expect(res.error, contains('502'));
      expect(res.error, isNot(contains('LEAKME9999')));
      expect(res.error, contains('api_key=***'));
      expect(res.error, contains('model=y'), reason: '非敏感参数保留');
    });

    test('抛异常（非网络类）路径同样脱敏', () async {
      AiClient.debugHttpClientFactory = () => MockClient(
        (req) async => throw Exception(
          'bad request to https://x.example.com/v1?key=THROWLEAK1',
        ),
      );

      final res = await client(kFakeLongToken)
          .chat([const AiMessage('user', 'hi')]);

      expect(res.ok, isFalse);
      expect(res.error, contains('请求失败'));
      expect(res.error, isNot(contains('THROWLEAK1')));
      expect(res.error, contains('key=***'));
    });

    test('网络类异常仍映射成人话（不因脱敏改动丢原有分支）', () async {
      AiClient.debugHttpClientFactory = () => MockClient(
        (req) async =>
            throw http.ClientException('Failed host lookup: api.minimaxi.com'),
      );

      final res = await client(kFakeLongToken)
          .chat([const AiMessage('user', 'hi')]);

      expect(res.ok, isFalse);
      expect(res.error, '网络连接失败，请检查网络后重试');
    });
  });

  group('源码不含 key 字面量（只扫 lib/）', () {
    /// 扫「sk- 后跟 20+ 个 base64url/字母数字字符」——真实 key 的长形态。
    /// 注意：本正则只在 test/ 里出现，扫的是 lib/，因此不会自我命中；
    /// lib 里的脱敏正则写成 `sk-[…]{8,}`，`[` 不在字符类里，也不会命中。
    final longToken = RegExp('sk-[A-Za-z0-9_+/=-]{20,}');

    /// 连旧 key 的「前缀 + 省略号」形态也不许留（v2.10 那把已撤销）。
    final retiredPrefix = RegExp('sk-cp-[A-Za-z0-9_-]{4,}');

    List<String> scan(RegExp pattern) {
      final offenders = <String>[];
      final dir = Directory('lib');
      expect(dir.existsSync(), isTrue, reason: '扫描根 lib/ 必须存在');
      for (final e in dir.listSync(recursive: true)) {
        if (e is! File || !e.path.endsWith('.dart')) continue;
        final text = e.readAsStringSync();
        for (final m in pattern.allMatches(text)) {
          // 只报路径与长度——绝不把疑似凭据本身写进失败信息/日志。
          offenders.add('${e.path} (len=${m.group(0)!.length})');
        }
      }
      return offenders;
    }

    test('lib/ 里没有长形态的裸 key 字面量', () {
      expect(
        scan(longToken),
        isEmpty,
        reason: '源码不得携带 API key 字面量',
      );
    });

    test('lib/ 里没有旧共享 key 的前缀片段', () {
      expect(
        scan(retiredPrefix),
        isEmpty,
        reason: '旧共享 key 只允许以 SHA-256 指纹形式存在',
      );
    });
  });
}
