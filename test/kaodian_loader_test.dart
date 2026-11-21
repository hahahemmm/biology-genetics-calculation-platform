// kaodian_loader_test.dart —— 考点库加载与搜索单元测试

import 'package:biology/engine/kaodian_loader.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const sample = '''
{
  "name": "2026 考点速查",
  "version": "1.0",
  "items": [
    {"id": "KD-01", "name": "分离定律（3∶1）",
     "content": "F2 性状分离比 3∶1 —— 显性:隐性",
     "typical_ratio": "3∶1", "source": "必修2"},
    {"id": "KD-02", "name": "自由组合定律",
     "content": "F2 表型比 9∶3∶3∶1",
     "typical_ratio": "9∶3∶3∶1", "source": "必修2"},
    {"id": "KD-03", "name": "DNA 复制",
     "content": "半保留复制 ×2 次循环",
     "typical_ratio": "—", "source": "必修2"}
  ]
}
''';

  group('正常解析', () {
    final bank = parseKaodianJson(sample);

    test('读取名称与条目数', () {
      expect(bank.name, '2026 考点速查');
      expect(bank.items.length, 3);
    });

    test('字段完整且顺序保持', () {
      expect(bank.items[0].id, 'KD-01');
      expect(bank.items[0].name, '分离定律（3∶1）');
      expect(bank.items[0].typicalRatio, '3∶1');
      expect(bank.items[0].source, '必修2');
      expect(bank.items[2].id, 'KD-03');
    });

    test('中文与特殊字符不被改写', () {
      expect(bank.items[0].name, contains('（3∶1）'));
      expect(bank.items[0].content, contains('∶'));
      expect(bank.items[0].content, contains('——'));
      expect(bank.items[2].content, contains('×'));
    });

    test('未知字段被忽略', () {
      final b = parseKaodianJson(
          '{"name":"n","items":[{"id":"a","extra_field":"x","rank":1}]}');
      expect(b.items.length, 1);
      expect(b.items[0].id, 'a');
      expect(b.items[0].name, '');
    });
  });

  group('空输入与空数据', () {
    test('空字符串 → 空库', () {
      final b = parseKaodianJson('');
      expect(b.name, '');
      expect(b.items, isEmpty);
    });

    test('纯空白 → 空库', () {
      final b = parseKaodianJson('   \n\t ');
      expect(b.name, '');
      expect(b.items, isEmpty);
    });

    test('顶层空数组 → 空库', () {
      final b = parseKaodianJson('[]');
      expect(b.name, '');
      expect(b.items, isEmpty);
    });

    test('空对象 → 空库', () {
      final b = parseKaodianJson('{}');
      expect(b.name, '');
      expect(b.items, isEmpty);
    });

    test('items 为空数组 → 保留 name', () {
      final b = parseKaodianJson('{"name":"空库","items":[]}');
      expect(b.name, '空库');
      expect(b.items, isEmpty);
    });
  });

  group('非法 JSON', () {
    test('截断的 JSON → 空库不抛', () {
      final b = parseKaodianJson('{"name":"x","items":[{"id":"a"');
      expect(b.name, '');
      expect(b.items, isEmpty);
    });

    test('少右括号 → 空库不抛', () {
      final b = parseKaodianJson('{"name":"x","items":[');
      expect(b.name, '');
      expect(b.items, isEmpty);
    });

    test('非 JSON 文本 → 空库不抛', () {
      final b = parseKaodianJson('not json at all');
      expect(b.name, '');
      expect(b.items, isEmpty);
    });
  });

  group('结构与类型容错', () {
    test('顶层是数组而非对象 → 空库', () {
      final b = parseKaodianJson('[{"id":"a"}]');
      expect(b.name, '');
      expect(b.items, isEmpty);
    });

    test('items 不是数组 → 保留 name、空条目', () {
      final b = parseKaodianJson('{"name":"n","items":{"id":"a"}}');
      expect(b.name, 'n');
      expect(b.items, isEmpty);
    });

    test('items 元素非对象被跳过', () {
      final b = parseKaodianJson(
          '{"name":"n","items":[1,"x",null,{"id":"a"},true]}');
      expect(b.items.length, 1);
      expect(b.items[0].id, 'a');
    });

    test('字段为数字 → 转成字符串', () {
      final b = parseKaodianJson('{"name":"n","items":[{"id":42,"name":3.5}]}');
      expect(b.items[0].id, '42');
      expect(b.items[0].name, '3.5');
    });

    test('字段为 null → 空串', () {
      final b = parseKaodianJson('{"name":"n","items":[{"id":null,"name":"a"}]}');
      expect(b.items[0].id, '');
      expect(b.items[0].name, 'a');
    });

    test('缺字段 → 空串', () {
      final b = parseKaodianJson('{"name":"n","items":[{"id":"a"}]}');
      final it = b.items[0];
      expect(it.name, '');
      expect(it.content, '');
      expect(it.typicalRatio, '');
      expect(it.source, '');
    });

    test('name 缺失 → 空串', () {
      final b = parseKaodianJson('{"items":[]}');
      expect(b.name, '');
    });
  });

  group('搜索', () {
    final bank = parseKaodianJson(sample);

    test('空查询返回全部', () {
      expect(bank.search(''), bank.items);
    });

    test('按名称匹配', () {
      expect(bank.search('分离').map((e) => e.id), ['KD-01']);
    });

    test('按内容匹配', () {
      expect(bank.search('半保留').map((e) => e.id), ['KD-03']);
    });

    test('按典型比例匹配', () {
      expect(bank.search('9∶3∶3∶1').map((e) => e.id), ['KD-02']);
    });

    test('大小写不敏感', () {
      expect(bank.search('dna').map((e) => e.id), ['KD-03']);
    });

    test('id 与 source 不参与匹配', () {
      expect(bank.search('KD-01'), isEmpty);
      expect(bank.search('必修2'), isEmpty);
    });

    test('无命中返回空', () {
      expect(bank.search('量子力学'), isEmpty);
    });
  });

  group('重复调用独立性', () {
    test('多次解析互不串数据', () {
      final a = parseKaodianJson(sample);
      final b = parseKaodianJson('{"name":"B","items":[{"id":"z"}]}');
      expect(a.items.length, 3);
      expect(a.name, '2026 考点速查');
      expect(b.items.length, 1);
      expect(b.items[0].id, 'z');
      expect(b.name, 'B');
    });

    test('搜索结果不影响库内容', () {
      final bank = parseKaodianJson(sample);
      final hits = bank.search('复制');
      expect(hits.length, 1);
      expect(bank.search('').length, 3);
      expect(bank.items.length, 3);
    });

    test('search("") 返回副本：外部改动不污染题库', () {
      final bank = parseKaodianJson(sample);
      bank.search('').clear();
      expect(bank.items.length, 3, reason: '空查询不得把内部列表暴露出去');
    });
  });
}
