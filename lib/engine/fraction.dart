// fraction.dart —— 精确分数（纯 Dart，零依赖）
//
// 借鉴 GitHub 开源高中遗传计算项目的共识做法：
// 概率全程用分数表示（如 9/16），不做浮点近似，
// 多代传递零误差，输出直接显示学生熟悉的分数形式。
//
// 特性：
//  - 构造即约分（gcd），符号统一放分子
//  - 支持 + - * /、比较、与 int 互转
//  - toString() 输出 '3/4'、整数输出 '2'、负数输出 '-1/8'

import 'utils.dart';

/// 精确分数（不可变）。
class Fraction implements Comparable<Fraction> {
  final int numerator; // 分子（携带符号）
  final int denominator; // 分母（恒为正）

  Fraction(int n, int d)
      : numerator = _norm(n, d).$1,
        denominator = _norm(n, d).$2;

  static (int, int) _norm(int n, int d) {
    if (d == 0) throw ArgumentError('分母不能为 0');
    if (d < 0) {
      n = -n;
      d = -d;
    }
    final g = gcd(n.abs(), d);
    return (n ~/ g, d ~/ g);
  }

  static final zero = Fraction(0, 1);
  static final one = Fraction(1, 1);
  static final half = Fraction(1, 2);

  factory Fraction.of(int n) => Fraction(n, 1);

  /// 从浮点近似构造（最大分母 10^6），供兼容旧 double 数据。
  factory Fraction.approx(double v, {int maxDen = 1000000}) {
    if (v == v.roundToDouble() && v.abs() < maxDen) {
      return Fraction(v.round(), 1);
    }
    int bestN = v.round(), bestD = 1;
    double bestErr = (v - bestN).abs();
    // 有限连分式逼近
    double x = v;
    int p0 = 0, p1 = 1, q0 = 1, q1 = 0;
    while (true) {
      final a = x.floor();
      final p2 = a * p1 + p0, q2 = a * q1 + q0;
      if (q2 > maxDen) break;
      p0 = p1; p1 = p2; q0 = q1; q1 = q2;
      final err = (v - p2 / q2).abs();
      if (err < bestErr) {
        bestErr = err;
        bestN = p2;
        bestD = q2;
      }
      if (err < 1e-12) break;
      x = 1 / (x - a);
      if (!x.isFinite) break;
    }
    return Fraction(bestN, bestD);
  }

  bool get isZero => numerator == 0;
  bool get isInteger => denominator == 1;

  double toDouble() => numerator / denominator;

  Fraction operator +(Fraction o) =>
      Fraction(numerator * o.denominator + o.numerator * denominator,
          denominator * o.denominator);
  Fraction operator -(Fraction o) =>
      Fraction(numerator * o.denominator - o.numerator * denominator,
          denominator * o.denominator);
  Fraction operator *(Fraction o) =>
      Fraction(numerator * o.numerator, denominator * o.denominator);
  Fraction operator /(Fraction o) =>
      Fraction(numerator * o.denominator, denominator * o.numerator);
  Fraction operator -() => Fraction(-numerator, denominator);

  @override
  int compareTo(Fraction o) =>
      (numerator * o.denominator).compareTo(o.numerator * denominator);

  @override
  bool operator ==(Object other) =>
      other is Fraction &&
      other.numerator == numerator &&
      other.denominator == denominator;

  @override
  int get hashCode => Object.hash(numerator, denominator);

  @override
  String toString() =>
      isInteger ? '$numerator' : '$numerator/$denominator';

  /// 百分比文本（保留 2 位小数），供 UI 显示。
  String toPercent() => '${(toDouble() * 100).toStringAsFixed(2)}%';

  /// 混合数显示：'1又1/4'（可选，教学用）。
  String toMixedString() {
    if (isInteger) return '$numerator';
    final whole = numerator ~/ denominator;
    final rem = numerator % denominator;
    if (whole == 0) return toString();
    if (rem == 0) return '$whole';
    return '$whole+$rem/$denominator';
  }
}
