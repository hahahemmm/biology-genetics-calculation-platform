// syllabus_loader_test.dart —— 考纲加载与覆盖度匹配单元测试

import 'package:biology/engine/syllabus_loader.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const sample = '''
{
  "name": "测试考纲",
  "items": [
    {"id": "SYL-01", "module": "必修2 · 遗传因子的发现",
     "kaodian": "阐明分离定律，并用于解释或预测遗传现象",
     "level": "理解", "note": "F2 性状分离比 3:1。", "source": "https://a"},
    {"id": "SYL-02", "module": "必修2 · 遗传因子的发现",
     "kaodian": "分析孟德尔两对相对性状的杂交实验",
     "level": "应用", "note": "自由组合，9:3:3:1。", "source": "https://b"},
    {"id": "SYL-03", "module": "必修2 · 伴性遗传",
     "kaodian": "概述伴性遗传的特点",
     "level": "理解", "note": "性染色体上的基因传递。", "source": "https://c"},
    {"id": "SYL-04", "module": "选择性必修 · 基因工程",
     "kaodian": "概述基因工程的基本操作程序",
     "level": "应用", "note": "限制酶、载体。", "source": "https://d"}
  ]
}
''';

  group('解析', () {
    final cov = parseSyllabusCoverage(sample);

    test('读取名称与条目数', () {
      expect(cov.name, '测试考纲');
      expect(cov.items.length, 4);
    });

    test('字段完整', () {
      final first = cov.items.first;
      expect(first.id, 'SYL-01');
      expect(first.level, '理解');
      expect(first.source, 'https://a');
    });

    test('按模块分组保持顺序', () {
      final modules = cov.byModule.keys.toList();
      expect(modules, [
        '必修2 · 遗传因子的发现',
        '必修2 · 伴性遗传',
        '选择性必修 · 基因工程',
      ]);
      expect(cov.byModule['必修2 · 遗传因子的发现']!.length, 2);
    });
  });

  group('覆盖度匹配', () {
    final cov = parseSyllabusCoverage(sample);

    test('分离/自由组合/伴性被覆盖', () {
      expect(cov.coveredBy.containsKey('SYL-01'), isTrue);
      expect(cov.coveredBy.containsKey('SYL-02'), isTrue);
      expect(cov.coveredBy.containsKey('SYL-03'), isTrue);
    });

    test('基因工程未覆盖', () {
      expect(cov.coveredBy.containsKey('SYL-04'), isFalse);
    });

    test('coveredCount 正确', () {
      expect(cov.coveredCount, 3);
    });

    test('覆盖理由非空', () {
      expect(cov.coveredBy['SYL-01']!, isNotEmpty);
    });
  });

  group('容错', () {
    test('非法 JSON 返回空', () {
      final cov = parseSyllabusCoverage('not json');
      expect(cov.items, isEmpty);
      expect(cov.coveredCount, 0);
    });

    test('缺 items 返回空', () {
      final cov = parseSyllabusCoverage('{"name":"x"}');
      expect(cov.items, isEmpty);
    });

    test('缺字段填空字符串', () {
      final cov = parseSyllabusCoverage(
          '{"items":[{"id":"X"}]}');
      expect(cov.items.single.kaodian, '');
      expect(cov.items.single.module, '');
    });
  });

  group('v2.0：课标编号与显式覆盖声明', () {
    const v2 = '''
{
  "name": "课标覆盖表",
  "exam": {
    "title": "辽宁新高考生物 · 考情速览",
    "duration": "75 分钟",
    "total_score": "100 分",
    "paper_type": "辽宁省自主命题",
    "structure": "单选 15×2 + 多选 5×3 + 非选择题约 55 分",
    "genetics_weight": "遗传与进化约占 25–30%",
    "note": "典型结构",
    "source": "可信资料库"
  },
  "items": [
    {"id": "A", "code": "3.2.3", "module": "概念3", "kaodian": "分离与自由组合",
     "level": "应用", "covered_by": ["9331", "自由交配"]},
    {"id": "B", "code": "3.3.5", "module": "概念3", "kaodian": "染色体变异可能致死",
     "level": "理解", "covered_by": ["致死条件"], "partial": true},
    {"id": "C", "code": "3.1.1", "module": "概念3", "kaodian": "DNA是遗传物质",
     "level": "理解", "covered_by": []},
    {"id": "D", "module": "旧格式", "kaodian": "阐明分离定律",
     "level": "理解"}
  ]
}
''';

    test('解析 code 与 exam 段', () {
      final cov = parseSyllabusCoverage(v2);
      expect(cov.items.first.code, '3.2.3');
      expect(cov.exam.isEmpty, isFalse);
      expect(cov.exam.duration, '75 分钟');
      expect(cov.exam.geneticsWeight, contains('25'));
    });

    test('显式 covered_by 优先于关键词匹配', () {
      final cov = parseSyllabusCoverage(v2);
      expect(cov.coveredBy['A'], '9331、自由交配');
    });

    test('显式空数组 = 明确未覆盖，不回退关键词', () {
      final cov = parseSyllabusCoverage(v2);
      expect(cov.coveredBy.containsKey('C'), isFalse);
      expect(cov.partialIds.contains('C'), isFalse);
    });

    test('partial 计入 partialIds 而非 coveredBy', () {
      final cov = parseSyllabusCoverage(v2);
      expect(cov.partialIds, {'B'});
      expect(cov.coveredBy.containsKey('B'), isFalse);
      expect(cov.coveredCount, 2); // A + D（D 走关键词回退）
      expect(cov.partialCount, 1);
    });

    test('无 covered_by 字段时回退关键词匹配', () {
      final cov = parseSyllabusCoverage(v2);
      expect(cov.coveredBy.containsKey('D'), isTrue);
      expect(cov.coveredBy['D'], contains('单基因杂交'));
    });
  });
}
