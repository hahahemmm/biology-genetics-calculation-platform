// tex_formula.dart —— TeX 教学公式共享组件（flutter_math_fork 0.7.4）
//
// 为什么单独一个组件：教学页里的公式原是「源码式」纯文本
//（N_t = K/(1+(K/N0−1)e^(−r·t))），学生看到的是程序员视角。本组件把
// 它们渲染为真正的人类可读排版（分式上下结构、上下标、希腊字母），并
// 守住四条底线：
//   ① 解析/构建失败 → 回落到普通人类可读公式文本，⛔ 不许崩；
//   ② 默认走 Math.tex（非 Selectable）：SelectableMath 的选中光标/
//      工具条会在 pumpAndSettle 期间反复调度，测试会挂起；
//   ③ 390 窄屏长分式 → 只做**本行内**横向滚动，不整页溢出、不缩到看不清；
//   ④ 中文解释一律留在外层 Text，⛔ 不进 TeX（数学字体无 CJK 字形，
//      \text{中文} 会渲染成方框）。
//
// 颜色：默认 AppColors.ink（token 实时派生，深/浅/高对比主题自动正确）；
// 需要贴合上下文（如 caption 灰字）时传显式 color。
// 依赖由主线程统一管理（pubspec.yaml/flutter_math_fork ^0.7.4），⛔ 本文件
// 不得改依赖。实际 import 路径是 package:flutter_math_fork/flutter_math.dart
//（库名 flutter_math_fork，入口文件 flutter_math.dart，没有
// flutter_math_fork.dart 这个文件）。

import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart';

import '../theme.dart';

/// 一条 TeX 公式：真排版 + 失败回落 + 窄屏局部滚动 + 可读语义。
class TexFormula extends StatelessWidget {
  const TexFormula({
    super.key,
    required this.tex,
    required this.fallback,
    this.color,
    this.fontSize,
    this.mathStyle,
    this.semanticsLabel,
  });

  /// TeX 源码——只放数学符号（拉丁/希腊字母、数字、运算符、分式、上下标）。
  /// ⛔ 中文说明不要写进来：用外层 Text 排在公式前后。
  final String tex;

  /// 解析失败时展示的人类可读普通公式（同时充当默认语义标签）。
  /// 必填——「不崩」的另一半是「还能看懂」。
  final String fallback;

  /// 公式颜色；null = 跟随 AppColors.ink（深浅主题自动正确）。
  final Color? color;

  /// 公式字号（逻辑像素）；null = 14（与 AppText.body 一致，窄屏可读下限）。
  final double? fontSize;

  /// display（默认，公式独立成行、分式舒展）或 text（行内紧凑）。
  final MathStyle? mathStyle;

  /// 屏幕阅读器朗读的完整描述；null = 朗读 [fallback]。
  final String? semanticsLabel;

  @override
  Widget build(BuildContext context) {
    // AppColors.ink 由全局主题控制器派生，不是 InheritedWidget。此处显式
    // 订阅 Theme，确保 const TexFormula 在深浅切换时也会重建实际字形。
    Theme.of(context);
    final style = TextStyle(
      fontSize: fontSize ?? 14,
      height: 1.3,
      color: color ?? AppColors.ink,
    );

    // 人读回落：解析失败时直接把 fallback 当普通文本画出来。
    final Widget plainFallback = Text(fallback, style: style);

    final Widget math = Math.tex(
      tex,
      mathStyle: mathStyle ?? MathStyle.display,
      textStyle: style,
      onErrorFallback: (_) => plainFallback,
    );

    // 窄屏守卫：公式只在自己的行内横向滚动，绝不撑破页面；无 FittedBox
    // 之类的缩放保命——原生字号优先，宁可滚动也不缩到看不清。
    final Widget body = LayoutBuilder(
      builder: (context, constraints) {
        if (!constraints.hasBoundedWidth) return math; // 无界宽度（Row 内）裸渲染
        return SizedBox(
          width: constraints.maxWidth,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            physics: const ClampingScrollPhysics(),
            child: math,
          ),
        );
      },
    );

    return Semantics(
      label: semanticsLabel ?? fallback,
      child: ExcludeSemantics(child: body),
    );
  }
}
