// utils_math_test.dart —— lib/engine/utils.dart 单测守护（v2.11 M11a）
//
// 守护抽公共后的 gcd() / lcm() 行为契约：
// - gcd 基本 + 负数 abs 兜底 + 0 守卫 + gcd(0,0) = 1
// - lcm 基本 + 0 守卫
//
// 之前 v2.10 的 5 处本地 _gcd 实现行为不一致：
// - fraction / genetics_env / linkage_engine 无 abs（负数返负数 gcd）
// - models / mono_cross_widget 有 abs 但无 0 守卫（gcd(0,0) 返 0）
// 抽公共后统一到 utils.dart 的 gcd()，本测试守护不变量。
//
// v2.13 引擎优化追加：hasUpperAscii 契约 + Ratio.equalsValues 值比较
// （替代易碎的 ratio.toString() == '9:3:3:1' 字符串比对）。
import 'package:biology/engine/models.dart';
import 'package:biology/engine/utils.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('gcd', () {
    test('基本互质', () {
      expect(gcd(12, 8), 4);
      expect(gcd(8, 12), 4);
      expect(gcd(15, 10), 5);
      expect(gcd(7, 13), 1); // 互质
    });

    test('负数入参走 abs 兜底（与 v2.10 之前 models 行为一致）', () {
      expect(gcd(-12, 8), 4);
      expect(gcd(12, -8), 4);
      expect(gcd(-12, -8), 4);
    });

    test('0 守卫：gcd(0, 0) = 1（不返 0，避免下游 ratio ~/0 抛 NaN）', () {
      expect(gcd(0, 0), 1);
    });

    test('0 与正数：gcd(0, x>0) = x', () {
      expect(gcd(0, 5), 5);
      expect(gcd(5, 0), 5);
    });

    test('大数（验证欧几里得算法效率）', () {
      expect(gcd(1024, 768), 256);
      expect(gcd(1000000, 500000), 500000);
    });
  });

  group('lcm', () {
    test('基本最小公倍数', () {
      expect(lcm(4, 6), 12);
      expect(lcm(3, 5), 15);
      expect(lcm(7, 7), 7);
    });

    test('0 守卫：lcm(0, x) = 0 与 lcm(x, 0) = 0', () {
      expect(lcm(0, 5), 0);
      expect(lcm(5, 0), 0);
      expect(lcm(0, 0), 0);
    });
  });

  group('hasUpperAscii', () {
    test('含大写字母返回 true', () {
      expect(hasUpperAscii('Aa'), isTrue);
      expect(hasUpperAscii('AB'), isTrue);
      expect(hasUpperAscii('aB'), isTrue);
      expect(hasUpperAscii('Z'), isTrue);
    });

    test('纯小写/空串返回 false', () {
      expect(hasUpperAscii('aa'), isFalse);
      expect(hasUpperAscii('ab'), isFalse);
      expect(hasUpperAscii(''), isFalse);
    });

    test('与 RegExp 语义一致（对照样例）', () {
      // 守护等价性：hasUpperAscii(s) == s.contains(RegExp('[A-Z]'))
      for (final s in ['AaBb', 'aabb', 'AABB', 'abc', 'ABC', '', 'xY']) {
        expect(hasUpperAscii(s), s.contains(RegExp('[A-Z]')));
      }
    });
  });

  group('Ratio.equalsValues', () {
    test('相等：同长度同份数逐项相等', () {
      expect(const Ratio([9, 3, 3, 1]).equalsValues(const [9, 3, 3, 1]),
          isTrue);
      expect(const Ratio([3, 1]).equalsValues(const [3, 1]), isTrue);
    });

    test('不等：长度不同或任一份数不同', () {
      expect(const Ratio([9, 3, 3, 1]).equalsValues(const [9, 3, 1]), isFalse);
      expect(const Ratio([9, 3, 3, 1]).equalsValues(const [9, 3, 3, 2]),
          isFalse);
      expect(const Ratio([3, 1]).equalsValues(const [1, 3]), isFalse);
    });

    test('空比与空列表相等；与非空不等', () {
      expect(const Ratio([]).equalsValues(const []), isTrue);
      expect(const Ratio([]).equalsValues(const [1]), isFalse);
    });

    test('语义等价于 toString 比对（守护重构不变式）', () {
      // 重构前：ratio.toString() == '9:3:3:1'
      // 重构后：ratio.equalsValues([9,3,3,1])
      // 两者对任意整数列表判定必须一致。
      const cases = [
        [9, 3, 3, 1],
        [27, 9, 9, 9, 3, 3, 3, 1],
        [3, 1],
        [1, 2, 1],
      ];
      for (final c in cases) {
        final r = Ratio(c);
        expect(r.equalsValues(c), r.toString() == c.join(':'));
      }
    });
  });
}
