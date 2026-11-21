// mistake_book_ai_test.dart —— 错题本 AI 整理 prompt 模板 + 解析测试
//
// 覆盖：
//   1. 单条 prompt 拼装正确（拼入题目/答案/自评类型/考点）
//   2. 单条 AI 返回 → 解析为 MistakeAiAnalysis（容错：代码块包裹 / 夹带文字）
//   3. 批量 prompt 拼装正确（按顺序排所有 entry，含 id 锚定）
//   4. 批量解析：返回数组 → 映射到 id → 与 entries 对齐
//   5. 总览 prompt 拼装 + 解析
//   6. 注入 debugSender 时 analyzeSingle 走注入（不发真实网络）

import 'package:biology/services/ai_client.dart';
import 'package:biology/state/mistake_book.dart';
import 'package:biology/ui/mistake_book_ai.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  tearDown(() {
    MistakeBookAi.debugSender = null;
  });

  final e1 = MistakeEntry(
    id: 'm_aaa_1',
    stem: 'AaBb 自交 F2 比例',
    userAnswer: '9:3:4',
    correctAnswer: '9:3:3:1',
    errorType: MistakeErrorType.concept,
    subjectArea: '9331 变式',
    createdAt: DateTime.fromMillisecondsSinceEpoch(1700000000000),
  );
  final e2 = MistakeEntry(
    id: 'm_bbb_2',
    stem: 'XAXa × XAY 儿子患病概率',
    userAnswer: '1/2',
    correctAnswer: '1/4',
    errorType: MistakeErrorType.calculation,
    subjectArea: '伴 X 隐性',
    createdAt: DateTime.fromMillisecondsSinceEpoch(1700000001000),
  );

  group('prompt 拼装', () {
    test('单条：含 id/题目/答案/自评/考点 4 段', () {
      final p = MistakeBookAi.buildSinglePrompt(e1);
      expect(p, contains('AaBb 自交 F2 比例'));
      expect(p, contains('9:3:4'));
      expect(p, contains('9:3:3:1'));
      expect(p, contains('概念错'));
      expect(p, contains('9331 变式'));
      expect(p, contains('summary'),
          reason: '要求输出 summary 字段');
      expect(p, contains('pitfalls'),
          reason: '要求输出 pitfalls 字段');
    });

    test('批量：按顺序排所有 entry，每条带 id 锚定', () {
      final p = MistakeBookAi.buildBatchPrompt([e1, e2]);
      expect(p, contains('m_aaa_1'));
      expect(p, contains('m_bbb_2'));
      final i1 = p.indexOf('m_aaa_1');
      final i2 = p.indexOf('m_bbb_2');
      expect(i1, lessThan(i2),
          reason: 'e1 在 e2 之前（拼装顺序）');
      expect(p, contains('第 1 条'));
      expect(p, contains('第 2 条'));
    });

    test('总览：拼入所有错题摘要 + 错误类型 + 考点', () {
      final p = MistakeBookAi.buildOverviewPrompt([e1, e2]);
      expect(p, contains('AaBb 自交 F2 比例'));
      expect(p, contains('XAXa × XAY'));
      expect(p, contains('概念错'));
      expect(p, contains('计算错'));
      expect(p, contains('text'),
          reason: '要求输出 text 字段');
    });
  });

  group('解析', () {
    test('单条：干净 JSON → MistakeAiAnalysis', () {
      final a = MistakeBookAi.parseMistakeAnalysis(
          '{"summary":"把 9331 当成 9431 记混了","pitfalls":["画表确认每列比例","先按一对拆再组合"]}');
      expect(a, isNotNull);
      expect(a!.summary, contains('9331'));
      expect(a.pitfalls, hasLength(2));
    });

    test('单条：代码块包裹 / 夹带解释文字 → 仍能解析', () {
      final a1 = MistakeBookAi.parseMistakeAnalysis('''
```json
{"summary":"粗心","pitfalls":["抄错数字"]}
```''');
      expect(a1, isNotNull);
      expect(a1!.summary, '粗心');

      final a2 = MistakeBookAi.parseMistakeAnalysis(
          '好的，分析如下：{"summary":"概念不清","pitfalls":["复习有丝分裂"]} 希望有帮助');
      expect(a2, isNotNull);
      expect(a2!.summary, '概念不清');
    });

    test('单条：垃圾输入 / 字段缺失 → null 或空', () {
      expect(MistakeBookAi.parseMistakeAnalysis('完全没有 JSON'), isNull);
      expect(
          MistakeBookAi.parseMistakeAnalysis('{"other": "field"}'), isNull,
          reason: '缺 summary+pitfalls 视为空');
      expect(MistakeBookAi.parseMistakeAnalysis('{"summary":"", "pitfalls":[]}'),
          isNull);
    });

    test('批量：JSON 数组 → 按 id 对齐到 entries（不在 entries 里的 id 丢弃）',
        () {
      final m = MistakeBookAi.parseMistakeBatch('''
[
  {"id":"m_aaa_1","summary":"A","pitfalls":["a1"]},
  {"id":"m_bbb_2","summary":"B","pitfalls":["b1","b2"]},
  {"id":"m_ghost","summary":"G","pitfalls":["g1"]}
]''', [e1, e2]);
      expect(m.keys, containsAll(['m_aaa_1', 'm_bbb_2']));
      expect(m.keys, isNot(contains('m_ghost')),
          reason: 'AI 幻觉的 id 不在 entries 中 → 丢弃');
      expect(m['m_aaa_1']!.summary, 'A');
      expect(m['m_bbb_2']!.pitfalls, ['b1', 'b2']);
    });

    test('总览：text 字段', () {
      final o = MistakeBookAi.parseMistakeOverview(
          '{"text":"最常错：9331 变式识别\\n建议：每周画 3 张表"}');
      expect(o, isNotNull);
      expect(o!.text, contains('9331'));
      expect(o.text.split('\n'), hasLength(2));
    });
  });

  group('AI 客户端集成（注入 debugSender）', () {
    test('analyzeSingle 走 debugSender，发出的 prompt 包含题目', () async {
      List<AiMessage>? captured;
      MistakeBookAi.debugSender = (msgs) {
        captured = msgs;
        return Future.value(const AiResult.ok(
            '{"summary":"粗心","pitfalls":["仔细读题"]}'));
      };
      final r = await MistakeBookAi.analyzeSingle(e1);
      expect(r, isNotNull);
      expect(r!.summary, '粗心');
      expect(captured, isNotNull);
      expect(captured!.last.content, contains('AaBb 自交 F2 比例'),
          reason: '发出的 user 消息含题目');
    });

    test('analyzeAll 走 debugSender，调用 1 次（批量合并发）', () async {
      var callCount = 0;
      List<AiMessage>? captured;
      MistakeBookAi.debugSender = (msgs) {
        callCount++;
        captured = msgs;
        return Future.value(const AiResult.ok('''
[
  {"id":"m_aaa_1","summary":"S1","pitfalls":["p1"]},
  {"id":"m_bbb_2","summary":"S2","pitfalls":["p2"]}
]'''));
      };
      final r = await MistakeBookAi.analyzeAll([e1, e2]);
      expect(callCount, 1, reason: '批量只发 1 次请求');
      expect(r, isNotNull);
      expect(r.keys, containsAll(['m_aaa_1', 'm_bbb_2']));
      expect(captured!.last.content, contains('m_aaa_1'));
      expect(captured!.last.content, contains('m_bbb_2'));
    });
  });
}
