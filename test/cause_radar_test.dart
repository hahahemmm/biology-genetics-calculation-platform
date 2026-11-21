// ════════════════════════════════════════════════════════════════════════
//  test/cause_radar_test.dart
//  v2.19.61：错题「错因雷达」——聚合口径 + 雷达图 + 页面挂载。
// ════════════════════════════════════════════════════════════════════════
//
//  ## 本文件钉住的五块
//  A1 聚合单元：`mistakeCauseCounts` 按 errorType 计数，五键全出现
//     （零值键也保留）。
//  A2 页面挂载：错题本页五轴标签（概念错/计算错/理解错/粗心错/其他）
//     全部在屏，且雷达图 CustomPaint 在树。
//  A3 最高频文案：往某一型堆 3 道 ⇒ 文案点名该型且报数正确。
//  A4 空错题本：雷达卡一个像素都不渲染。
//  A5 回收站隔离：删一道题 ⇒ 计数减一（走回收站软删机制）。
//
//  ## 数据铁律
//  题干**必须唯一**：MistakeBook 的存入类入口按「题干+答案」去重，
//  题干重复会让两条题在库/屏上互相顶替。故一律用单调计数器拼题干，
//  绝不用 `DateTime.now`（同毫秒会撞）。
//
//  ## ⚠️ 隔离：MistakeBook 落到独立临时目录，绝不碰真实库。
//  setUp/tearDown 照抄 review_session_card_link_test.dart。

import 'dart:io';

import 'package:biology/pages/mistake_book_page.dart';
import 'package:biology/pages/widgets/cause_radar.dart';
import 'package:biology/state/mistake_book.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 题干计数器：保证每条题干唯一。
int _stemSeq = 0;

void main() {
  late Directory tmp;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('cause_radar');
    MistakeBook.debugFilePath = '${tmp.path}/mistakes.json';
    MistakeBook.debugTrashFilePath = '${tmp.path}/mistakes.trash.json';
    MistakeBook.instance.debugReset();
  });

  tearDown(() {
    MistakeBook.instance.debugFlushSave();
    MistakeBook.instance.debugResetAiOrganize();
    MistakeBook.instance.debugReset();
    MistakeBook.debugFilePath = null;
    MistakeBook.debugTrashFilePath = null;
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  /// 存一条错题（题干唯一，单调计数器拼）；返回条目本体。
  MistakeEntry seed(MistakeErrorType type) {
    final n = ++_stemSeq;
    return MistakeBook.instance.add(
      stem: '错因题$n',
      userAnswer: '我答$n',
      correctAnswer: '正答$n',
      errorType: type,
      subjectArea: '',
    );
  }

  Future<void> pumpPage(WidgetTester tester) async {
    tester.view.physicalSize = const Size(900, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const MaterialApp(home: MistakeBookPage()));
    await tester.pumpAndSettle();
  }

  /// 收尾：泵过写盘 debounce，别留 pending timer。
  Future<void> settle(WidgetTester tester) async {
    await tester.pump(const Duration(milliseconds: 600));
  }

  // ══════════════════════════════════════════════════════════════════
  //  A1. 聚合单元
  // ══════════════════════════════════════════════════════════════════

  test('A1：mistakeCauseCounts 逐键精确相等，零值键也保留', () {
    // concept 3 / calculation 2 / comprehension 1 / careless 1 / other 0。
    for (var i = 0; i < 3; i++) {
      seed(MistakeErrorType.concept);
    }
    for (var i = 0; i < 2; i++) {
      seed(MistakeErrorType.calculation);
    }
    seed(MistakeErrorType.comprehension);
    seed(MistakeErrorType.careless);

    final counts = mistakeCauseCounts(MistakeBook.instance.entries);

    expect(counts.length, MistakeErrorType.values.length,
        reason: 'A1：五键全出现');
    expect(counts[MistakeErrorType.concept], 3);
    expect(counts[MistakeErrorType.calculation], 2);
    expect(counts[MistakeErrorType.comprehension], 1);
    expect(counts[MistakeErrorType.careless], 1);
    expect(counts[MistakeErrorType.other], 0,
        reason: 'A1：零值键必须保留（图要画零轴）');
  });

  // ══════════════════════════════════════════════════════════════════
  //  A2. 页面挂载：五轴标签 + CustomPaint
  // ══════════════════════════════════════════════════════════════════

  testWidgets('A2：五轴标签全部在屏，雷达 CustomPaint 在树', (tester) async {
    seed(MistakeErrorType.concept);
    seed(MistakeErrorType.calculation);
    seed(MistakeErrorType.comprehension);
    seed(MistakeErrorType.careless);
    seed(MistakeErrorType.other);

    await pumpPage(tester);

    expect(find.byType(CauseRadarChart), findsOneWidget,
        reason: 'A2：非空错题本 ⇒ 雷达卡在屏');
    expect(
      find.descendant(
        of: find.byType(CauseRadarChart),
        matching: find.byType(CustomPaint),
      ),
      findsOneWidget,
      reason: 'A2：图本体由 CustomPainter 自绘',
    );
    for (final t in MistakeErrorType.values) {
      expect(
          find.descendant(
            of: find.byType(CauseRadarChart),
            matching: find.text(t.displayName),
          ),
          findsOneWidget,
          reason: 'A2：轴标签「${t.displayName}」必须在屏');
    }

    await settle(tester);
  });

  // ══════════════════════════════════════════════════════════════════
  //  A3. 最高频文案
  // ══════════════════════════════════════════════════════════════════

  testWidgets('A3：某型堆 3 道 ⇒ 文案点名该型且报数正确', (tester) async {
    seed(MistakeErrorType.calculation);
    seed(MistakeErrorType.calculation);
    seed(MistakeErrorType.calculation);
    seed(MistakeErrorType.concept);

    await pumpPage(tester);

    expect(find.text('计算错最多（3 道）——点下方筛选看这类题'), findsOneWidget,
        reason: 'A3：文案须点名「计算错」且报数 3');

    await settle(tester);
  });

  // ══════════════════════════════════════════════════════════════════
  //  A4. 空错题本零像素
  // ══════════════════════════════════════════════════════════════════

  testWidgets('A4：空错题本 ⇒ 雷达卡一个像素都不渲染', (tester) async {
    await pumpPage(tester);

    expect(find.byType(CauseRadarChart), findsNothing,
        reason: 'A4：空错题本不挂雷达图');
    expect(find.text('错因分布'), findsNothing,
        reason: 'A4：空错题本不挂卡标题');

    await settle(tester);
  });

  // ══════════════════════════════════════════════════════════════════
  //  A5. 回收站隔离
  // ══════════════════════════════════════════════════════════════════

  test('A5：删一道题（进回收站）⇒ 该型计数减一；回收站不计入', () {
    seed(MistakeErrorType.careless);
    seed(MistakeErrorType.careless);
    seed(MistakeErrorType.concept);

    final before = mistakeCauseCounts(MistakeBook.instance.entries);
    expect(before[MistakeErrorType.careless], 2, reason: '前提：粗心错 2 道');

    final target = MistakeBook.instance.entries
        .firstWhere((e) => e.errorType == MistakeErrorType.careless);
    MistakeBook.instance.delete(target.id);

    final after = mistakeCauseCounts(MistakeBook.instance.entries);
    expect(after[MistakeErrorType.careless], 1,
        reason: 'A5：已删（进回收站）的题不再计入');
    expect(after[MistakeErrorType.concept], 1, reason: 'A5：其它型不受影响');
    expect(MistakeBook.instance.trash.length, 1,
        reason: 'A5：走的是软删（回收站）机制');
  });
}
