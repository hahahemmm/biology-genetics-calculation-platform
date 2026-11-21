// curriculum_2020_test.dart —— 必修2课标内容要求数据完整性测试
//
// 覆盖：
//   - 22 条全量录入、code 唯一、格式合法
//   - 原文非空且长度足够（逐字录入的课标句子）
//   - 大概念 / 重要概念非空
//   - 关键条目关键词断言（3.2.3 / 3.1.2 / 4.2.2）
//   - heat 范围 0..3

import 'package:biology/data/curriculum_2020.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('curriculum2020 · 结构完整性', () {
    test('共 22 条内容要求（3.1.1~3.1.5、3.2.1~3.2.4、3.3.1~3.3.6、4.1.1~4.1.2、4.2.1~4.2.5）', () {
      expect(curriculum2020.length, 22);
    });

    test('code 唯一', () {
      final codes = curriculum2020.map((e) => e.code).toList();
      expect(codes.toSet().length, codes.length);
    });

    test('code 匹配 3.x.x / 4.x.x 次位概念编号格式', () {
      final re = RegExp(r'^[34]\.\d\.\d$');
      for (final item in curriculum2020) {
        expect(re.hasMatch(item.code), isTrue, reason: '非法 code: ${item.code}');
      }
    });

    test('每条的 code 均落在 PLAN_2.0 规定的 22 个编号内', () {
      const expected = {
        '3.1.1', '3.1.2', '3.1.3', '3.1.4', '3.1.5',
        '3.2.1', '3.2.2', '3.2.3', '3.2.4',
        '3.3.1', '3.3.2', '3.3.3', '3.3.4', '3.3.5', '3.3.6',
        '4.1.1', '4.1.2',
        '4.2.1', '4.2.2', '4.2.3', '4.2.4', '4.2.5',
      };
      expect(curriculum2020.map((e) => e.code).toSet(), expected);
    });

    test('顺序与 PLAN_2.0 表格一致', () {
      final codes = curriculum2020.map((e) => e.code).toList();
      expect(codes, [
        '3.1.1', '3.1.2', '3.1.3', '3.1.4', '3.1.5',
        '3.2.1', '3.2.2', '3.2.3', '3.2.4',
        '3.3.1', '3.3.2', '3.3.3', '3.3.4', '3.3.5', '3.3.6',
        '4.1.1', '4.1.2',
        '4.2.1', '4.2.2', '4.2.3', '4.2.4', '4.2.5',
      ]);
    });
  });

  group('curriculum2020 · 字段校验', () {
    test('text 非空且长度 > 10（课标原文为完整句子）', () {
      for (final item in curriculum2020) {
        expect(item.text.trim().length, greaterThan(10),
            reason: '${item.code} 原文过短: ${item.text}');
        expect(item.text.contains('……'), isFalse,
            reason: '${item.code} 含省略号，应为完整官方原文');
      }
    });

    test('bigIdea / keyConcept 非空', () {
      for (final item in curriculum2020) {
        expect(item.bigIdea, isNotEmpty, reason: item.code);
        expect(item.keyConcept, isNotEmpty, reason: item.code);
      }
    });

    test('bigIdea 与 code 首位一致（3 -> 概念3，4 -> 概念4）', () {
      for (final item in curriculum2020) {
        final expected = item.code.startsWith('3') ? '概念3' : '概念4';
        expect(item.bigIdea, expected, reason: item.code);
      }
    });

    test('keyConcept 为 code 的前两段（如 3.2.3 -> 3.2）', () {
      for (final item in curriculum2020) {
        final expected = item.code.substring(0, 3);
        expect(item.keyConcept, expected, reason: item.code);
      }
    });

    test('heat 在 0..3 范围内', () {
      for (final item in curriculum2020) {
        expect(item.heat, inInclusiveRange(0, 3),
            reason: '${item.code} heat=${item.heat}');
      }
    });

    test('含 ★ 标注的热门条目 heat > 0，未标注为 0', () {
      const hot = {'3.1.2', '3.1.3', '3.1.4', '3.2.1', '3.2.3', '3.2.4', '3.3.1', '3.3.4', '3.3.5', '3.3.6', '4.2.1', '4.2.2', '4.2.3', '4.2.4', '4.2.5'};
      for (final item in curriculum2020) {
        if (hot.contains(item.code)) {
          expect(item.heat, greaterThan(0), reason: '${item.code} 应为热门条目');
        } else {
          expect(item.heat, 0, reason: '${item.code} 应无热度标注');
        }
      }
    });
  });

  group('curriculum2020 · 关键原文断言', () {
    test('3.2.3 原文包含「分离」与「自由组合」', () {
      final item = curriculum2020.firstWhere((e) => e.code == '3.2.3');
      expect(item.text, contains('分离'));
      expect(item.text, contains('自由组合'));
    });

    test('3.1.2 原文包含「双螺旋」', () {
      final item = curriculum2020.firstWhere((e) => e.code == '3.1.2');
      expect(item.text, contains('双螺旋'));
    });

    test('4.2.2 原文包含「优势性状」', () {
      final item = curriculum2020.firstWhere((e) => e.code == '4.2.2');
      expect(item.text, contains('优势性状'));
    });

    test('loadCurriculum2020() 与常量一致（兼容接口契约）', () {
      expect(loadCurriculum2020(), curriculum2020);
    });
  });
}