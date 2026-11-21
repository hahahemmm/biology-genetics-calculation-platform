// ai_config_validate_test.dart —— v2.11 H3 BaseURL 校验测试
//
// 修复前：isConfigured 仅校验 `startsWith('http')`——同时接受明文
// http://（API key 裸奔）、内网 IP（SSRF）、localhost（127.0.0.1）
//
// 修复后：
//   1. isConfigured 强校验 scheme == 'https'
//   2. AiConfig.validateBaseUrl 静态方法拦截：
//      - 明文 http
//      - 内网 IP（10.* / 172.16-31.* / 192.168.* / 127.*）
//      - 本机地址（localhost / 0.0.0.0）
//      - 空字符串 / 格式错
//   3. 合法 HTTPS 公网域名通过

import 'package:biology/services/ai_client.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('v2.11 H3：AiConfig.validateBaseUrl SSRF 校验', () {
    test('合法 HTTPS 公网域名 → 通过', () {
      expect(AiConfig.validateBaseUrl('https://api.minimaxi.com/v1'),
          isNull);
      expect(AiConfig.validateBaseUrl('https://api.openai.com/v1'), isNull);
      expect(AiConfig.validateBaseUrl('https://api.deepseek.com'), isNull);
    });

    test('合法 HTTPS 带端口 + 路径 → 通过', () {
      expect(AiConfig.validateBaseUrl('https://example.com:8443/v1/api'),
          isNull);
    });

    test('明文 http → 拒绝', () {
      expect(AiConfig.validateBaseUrl('http://api.example.com/v1'),
          isNotNull,
          reason: '明文 HTTP 拒绝——会泄露 API key');
    });

    test('非 http(s) scheme → 拒绝', () {
      expect(AiConfig.validateBaseUrl('ftp://api.example.com/v1'),
          isNotNull);
      expect(AiConfig.validateBaseUrl('file:///etc/passwd'), isNotNull);
    });

    test('localhost / 0.0.0.0 → 拒绝', () {
      expect(AiConfig.validateBaseUrl('https://localhost/v1'), isNotNull);
      expect(AiConfig.validateBaseUrl('https://0.0.0.0/v1'), isNotNull);
    });

    test('loopback 127.0.0.1 → 拒绝', () {
      expect(AiConfig.validateBaseUrl('https://127.0.0.1/v1'), isNotNull);
      expect(AiConfig.validateBaseUrl('https://127.0.0.1:8080/v1'),
          isNotNull);
    });

    test('RFC1918 私有 IP 段 → 拒绝', () {
      // 10.0.0.0/8
      expect(AiConfig.validateBaseUrl('https://10.0.0.1/v1'), isNotNull);
      expect(AiConfig.validateBaseUrl('https://10.255.255.254/v1'),
          isNotNull);
      // 172.16.0.0/12
      expect(AiConfig.validateBaseUrl('https://172.16.0.1/v1'), isNotNull);
      expect(AiConfig.validateBaseUrl('https://172.20.5.5/v1'), isNotNull);
      expect(AiConfig.validateBaseUrl('https://172.31.255.254/v1'),
          isNotNull);
      // 192.168.0.0/16
      expect(AiConfig.validateBaseUrl('https://192.168.1.1/v1'),
          isNotNull);
      expect(AiConfig.validateBaseUrl('https://192.168.0.100/v1'),
          isNotNull);
    });

    test('172.15.x 与 172.32.x（不在 RFC1918 范围内）→ 通过', () {
      // 这两个 IP 段不在私有范围内，应允许通过
      // 注：实际有效性依赖网络环境，校验只检查 scheme + 内网段
      expect(AiConfig.validateBaseUrl('https://172.15.0.1/v1'), isNull,
          reason: '172.15.* 不在 172.16-31 私有段内');
      expect(AiConfig.validateBaseUrl('https://172.32.0.1/v1'), isNull,
          reason: '172.32.* 不在 172.16-31 私有段内');
    });

    test('公网 IP → 通过', () {
      expect(AiConfig.validateBaseUrl('https://8.8.8.8/v1'), isNull);
      expect(AiConfig.validateBaseUrl('https://1.1.1.1/v1'), isNull);
    });

    test('空字符串 / 乱码 → 拒绝', () {
      expect(AiConfig.validateBaseUrl(''), isNotNull);
      expect(AiConfig.validateBaseUrl('   '), isNotNull);
      expect(AiConfig.validateBaseUrl('not-a-url'), isNotNull);
      expect(AiConfig.validateBaseUrl('https://'), isNotNull,
          reason: 'https:// 后无 host');
    });

    test('前后空格容忍', () {
      expect(
          AiConfig.validateBaseUrl('  https://api.minimaxi.com/v1  '),
          isNull,
          reason: 'URL 前后空格应被 trim 后校验');
    });

    test('大写 host 不影响校验', () {
      expect(AiConfig.validateBaseUrl('https://LOCALHOST/v1'),
          isNotNull,
          reason: 'host 大小写归一化后查白名单');
    });
  });

  group('v2.11 H3：AiConfig.isConfigured 强校验 https', () {
    test('空 baseUrl / 空 key → false', () {
      const c = AiConfig(baseUrl: '', apiKey: 'xxx');
      expect(c.isConfigured, isFalse);
    });

    test('明文 http → false', () {
      const c = AiConfig(
        baseUrl: 'http://api.example.com/v1',
        apiKey: 'xxx',
      );
      expect(c.isConfigured, isFalse,
          reason: '明文 HTTP 不通过 isConfigured');
    });

    test('合法 https + 非空 key → true', () {
      const c = AiConfig(
        baseUrl: 'https://api.minimaxi.com/v1',
        apiKey: 'sk-xxx',
      );
      expect(c.isConfigured, isTrue);
    });

    test('乱码 baseUrl → false', () {
      const c = AiConfig(baseUrl: 'not-a-url', apiKey: 'sk-xxx');
      expect(c.isConfigured, isFalse,
          reason: '乱码不是合法 URL，Uri.tryParse 返回 null');
    });
  });
}
