// error_diagnosis.dart —— 错因诊断引擎（v2.4 功能 3，纯 Dart）
//
// 场景（烟台二中「面批面改纠固定错误」教研实证）：学生答错比例题时，
// 输入亲本基因型 + 正确答案比 + 学生答案比，反推学生最可能犯了哪类错。
//
// 方法论：先引擎正推标准答案校验题面，再把学生答案与若干
// 「典型错误模式」比对（漏算一对基因/基因型比当表型比/误套变式/
// 未约分/份数体系错）。诊断是启发式的——输出「可能的错因」列表，
// 供老师面批时参考，不宣称唯一真相。

import 'kaoji_calc.dart';
import 'reverse_engine.dart';

/// 错因诊断结果。
class DiagnosisResult {
  /// 引擎正推的标准答案（供核对题目条件）。
  final String computedRatio;

  /// 教师给的「正确答案」与引擎计算是否一致（不一致说明题面可能有
  /// 致死/连锁等特殊条件超出引擎范围）。
  final bool correctMatchesEngine;

  /// 学生答案是否其实正确（含未约分情形）。
  final bool studentCorrect;

  /// 可能的错因列表（启发式，按可能性排序）。
  final List<String> causes;

  const DiagnosisResult({
    required this.computedRatio,
    required this.correctMatchesEngine,
    required this.studentCorrect,
    required this.causes,
  });
}

class ErrorDiagnosis {
  final KaojiCalc _calc = KaojiCalc();

  /// 诊断入口。[p1]/[p2] 亲本基因型（1~2 对基因），[correctText]
  /// 题目标准答案比例，[studentText] 学生答案比例。
  DiagnosisResult diagnose({
    required String p1,
    required String p2,
    required String correctText,
    required String studentText,
  }) {
    final correct = ReverseEngine.parseRatio(correctText);
    final student = ReverseEngine.parseRatio(studentText);
    final correctStr = correct.toString();
    final studentStr = student.toString();

    // 正推标准答案（按亲本位点数自动）
    final auto = _calc.crossAuto(p1: p1, p2: p2);
    final computed = auto.result?.phenotypeRatio.reduced().toString() ?? '';
    final computedOk = computed.isNotEmpty && computed == correctStr;

    // 学生其实答对（含未约分）
    final studentCorrect = studentStr == correctStr;

    final causes = <String>[];
    if (studentCorrect) {
      if (studentText.trim().replaceAll('：', ':') != correctStr) {
        causes.add('答案其实正确，只是未约分（规范书写要求约到最简整数比）');
      }
    } else {
      causes.addAll(_matchPatterns(studentStr, computed, correctStr, p1));
    }

    return DiagnosisResult(
      computedRatio: computed.isEmpty ? '（无法计算）' : computed,
      correctMatchesEngine: computedOk,
      studentCorrect: studentCorrect,
      causes: causes,
    );
  }

  /// 典型错误模式匹配。[computed] 为引擎正推比（空 = 算不出），
  /// [correct] 为题面正解（份数体系比对基准）。
  List<String> _matchPatterns(
      String student, String computed, String correct, String p1) {
    final out = <String>[];
    final loci = p1.trim().length ~/ 2;

    // 基因型比当表型比
    if (loci == 1 && student == '1:2:1') {
      out.add('把基因型比当成表型比：Aa 自交基因型 1:2:1，'
          '完全显性下表型应为 3:1（显:隐合并）');
    }
    if (loci == 2 && student == '1:2:1:2:4:2:1:2:1') {
      out.add('把基因型比当成表型比：两对基因的基因型 9 类须按表型合并');
    }

    // 漏算一对基因（两对题答成一对的常见比）
    if (loci == 2 && (student == '3:1' || student == '1:1')) {
      out.add('只按一对基因算（漏掉第二对）：两对杂合先数配子种类'
          '（2²=4 种），棋盘 16 格再合并表型');
    }

    // 误套变式 / 变式当标准
    const variants = ['9:7', '9:3:4', '9:6:1', '12:3:1', '15:1'];
    if (variants.contains(student) && computed == '9:3:3:1') {
      out.add('误套 9331 变式（$student）：本题无基因互作条件，'
          '标准 9:3:3:1；变式须有互补/上位/叠加等题干依据');
    }
    if (student == '9:3:3:1' && variants.contains(computed)) {
      out.add('本题是变式 $computed（基因互作），学生套用了标准 9331');
    }

    // 份数体系错误（学生总份数 ≠ 正解总份数）
    final studentTotal = student
        .split(':')
        .map(int.parse)
        .fold<int>(0, (a, b) => a + b);
    final correctTotal = correct
        .split(':')
        .map(int.parse)
        .fold<int>(0, (a, b) => a + b);
    if (studentTotal != correctTotal && studentTotal != 0) {
      out.add('份数体系与正解不符：正解总份数 $correctTotal，'
          '学生 $studentTotal；致死题先扣致死份数再换算，'
          '测交题总份数是 4 不是 16');
    }

    // 测交/自交混淆
    if (loci == 1 && student == '1:1' && computed == '3:1') {
      out.add('测交与自交混淆：杂合自交是 3:1，1:1 是测交（×隐性纯合）的结果');
    }

    if (out.isEmpty) {
      out.add('非典型错误——建议分步重算：① 数配子种类 ② 棋盘/分支法展开 '
          '③ 同表型合并 ④ 约分；也可把题目发「问 AI」看完整推导');
    }
    return out;
  }
}
