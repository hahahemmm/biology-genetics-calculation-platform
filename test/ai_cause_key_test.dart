// ════════════════════════════════════════════════════════════════════════
//  test/ai_cause_key_test.dart
//  v2.19.62：错因雷达下半幅——AI 结构化错因（MistakeCauseKey）+ 双视图。
// ════════════════════════════════════════════════════════════════════════
//
//  ## 本文件钉住的八块
//  B1 prompt 闭集词表：单条 / 批量 prompt 文本含六个 key 的 name。
//  B2 解析兼容：无 causeKey 的旧输出 → null；合法 key → 对应 enum；
//     词表外垃圾 → null（白名单过滤）。
//  B3 schema round-trip：toJson → fromJson 保留 causeKey；旧 JSON（无该
//     键）不抛且为 null；非法值 → null。
//  B4 copyWith 显式清 causeKey（clearCauseKey 开关，置 null 真的 null）。
//  B5 整理写回链路：注入假 AI（带 causeKey）⇒ 条目 causeKey 落库。
//  B6 mistakeCauseKeyCounts 六键计数精确（含 null → unclassified 归并）。
//  B7 雷达卡 AI 视图：无 AI 数据 → 诚实空态在屏、图不渲染；有数据 → 六轴
//     标签在屏。
//  B8 视图切换 chip 可点且切得动（自评 ⇄ AI 判）。
//
//  ## 数据铁律
//  题干**必须唯一**：MistakeBook 的存入类入口按「题干+答案」去重，题干
//  重复会让两条题互相顶替。故一律用单调计数器拼题干，绝不用
//  `DateTime.now`（同毫秒会撞）。
//
//  ## ⚠️ 隔离：MistakeBook 落到独立临时目录，绝不碰真实库。
//  setUp/tearDown 照抄 cause_radar_test.dart。

import 'dart:io';

import 'package:biology/pages/mistake_book_page.dart';
import 'package:biology/pages/widgets/cause_radar.dart';
import 'package:biology/state/mistake_book.dart';
import 'package:biology/ui/mistake_book_ai.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 题干计数器：保证每条题干唯一。
int _stemSeq = 0;

void main() {
  late Directory tmp;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('ai_cause_key');
    MistakeBook.debugFilePath = '${tmp.path}/mistakes.json';
    MistakeBook.debugTrashFilePath = '${tmp.path}/mistakes.trash.json';
    MistakeBook.instance.debugReset();
  });

  tearDown(() {
    MistakeBook.instance.debugFlushSave();
    MistakeBook.instance.debugResetAiOrganize();
    MistakeBook.instance.debugReset();
    MistakeBook.debugOrganizeSender = null;
    MistakeBookAi.debugSender = null;
    MistakeBook.debugFilePath = null;
    MistakeBook.debugTrashFilePath = null;
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  /// 存一条错题（题干唯一）；返回条目本体。
  MistakeEntry seed(MistakeErrorType type, {String? causeKey}) {
    final n = ++_stemSeq;
    final e = MistakeBook.instance.add(
      stem: 'AI判错因题$n',
      userAnswer: '我答$n',
      correctAnswer: '正答$n',
      errorType: type,
      subjectArea: '',
    );
    if (causeKey != null) {
      MistakeBook.instance.update(e.id, (x) => x.copyWith(causeKey: causeKey));
      return MistakeBook.instance.findById(e.id)!;
    }
    return e;
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
  //  B1. prompt 闭集词表
  // ══════════════════════════════════════════════════════════════════

  test('B1：单条 / 批量 prompt 均含六个 key 的 name + 兜底口径', () {
    final e = MistakeEntry(
      id: 'm_b1',
      stem: 'AaBb 自交',
      userAnswer: '9:3:4',
      correctAnswer: '9:3:3:1',
      errorType: MistakeErrorType.concept,
      subjectArea: '',
      createdAt: DateTime.fromMillisecondsSinceEpoch(1),
    );
    final single = MistakeBookAi.buildSinglePrompt(e);
    final batch = MistakeBookAi.buildBatchPrompt([e]);

    for (final k in MistakeCauseKey.values) {
      expect(single, contains(k.name),
          reason: 'B1：单条 prompt 应含词表 key「${k.name}」');
      expect(batch, contains(k.name),
          reason: 'B1：批量 prompt 应含词表 key「${k.name}」');
    }
    expect(single, contains('causeKey'), reason: 'B1：单条 prompt 要求输出 causeKey');
    expect(batch, contains('causeKey'), reason: 'B1：批量 prompt 要求输出 causeKey');
    // 「拿不准就给 unclassified」这句兜底口径必须在。
    expect(single, contains('unclassified'));
  });

  // ══════════════════════════════════════════════════════════════════
  //  B2. 解析兼容
  // ══════════════════════════════════════════════════════════════════

  test('B2：解析——无 causeKey ⇒ null；合法 ⇒ enum；垃圾 ⇒ null', () {
    // 旧模型输出（没有 causeKey 键）⇒ causeKey 为 null。
    final old = MistakeBookAi.parseMistakeAnalysis(
        '{"summary":"错因一句话","pitfalls":["点 1"]}');
    expect(old, isNotNull);
    expect(old!.causeKey, isNull, reason: 'B2：旧输出缺 causeKey ⇒ null');

    // 合法 key ⇒ 对应 enum 的 name。
    final ok = MistakeBookAi.parseMistakeAnalysis(
        '{"summary":"S","pitfalls":[],"causeKey":"missedGenePair"}');
    expect(ok!.causeKey, MistakeCauseKey.missedGenePair.name,
        reason: 'B2：合法 key 应保留');

    // 词表外垃圾字符串 ⇒ null（白名单过滤，不写进结构化字段）。
    final bad = MistakeBookAi.parseMistakeAnalysis(
        '{"summary":"S","pitfalls":[],"causeKey":"我猜是算错了叭"}');
    expect(bad!.causeKey, isNull, reason: 'B2：词表外自由文本 ⇒ null');

    // 批量路径同样保留 causeKey（_mapToJsonString 不能丢键）。
    final m = MistakeBookAi.parseMistakeBatch(
        '[{"id":"m_x","summary":"S","pitfalls":[],"causeKey":"fractionSystem"}]',
        [
          MistakeEntry(
            id: 'm_x',
            stem: 'stem',
            userAnswer: 'u',
            correctAnswer: 'c',
            errorType: MistakeErrorType.concept,
            subjectArea: '',
            createdAt: DateTime.fromMillisecondsSinceEpoch(1),
          )
        ]);
    expect(m['m_x']!.causeKey, MistakeCauseKey.fractionSystem.name,
        reason: 'B2：批量解析须保留 causeKey');
  });

  // ══════════════════════════════════════════════════════════════════
  //  B3. schema round-trip
  // ══════════════════════════════════════════════════════════════════

  test('B3：toJson → fromJson 保留 causeKey；旧 JSON 无键 ⇒ null 不抛', () {
    final e = MistakeEntry(
      id: 'm_b3',
      stem: '题干',
      userAnswer: 'u',
      correctAnswer: 'c',
      errorType: MistakeErrorType.concept,
      subjectArea: '',
      createdAt: DateTime.fromMillisecondsSinceEpoch(1),
      causeKey: MistakeCauseKey.testcrossSelfingConfusion.name,
    );
    final json = e.toJson();
    expect(json['causeKey'], MistakeCauseKey.testcrossSelfingConfusion.name,
        reason: 'B3：toJson 写 enum name（非 ordinal）');

    final back = MistakeEntry.fromJson(json);
    expect(back!.causeKey, MistakeCauseKey.testcrossSelfingConfusion.name,
        reason: 'B3：round-trip 保留 causeKey');

    // 旧 JSON（无 causeKey 键）⇒ 不抛且为 null。
    final legacy = Map<String, dynamic>.from(json)..remove('causeKey');
    final legacyBack = MistakeEntry.fromJson(legacy);
    expect(legacyBack, isNotNull, reason: 'B3：缺键不得导致整条丢弃');
    expect(legacyBack!.causeKey, isNull, reason: 'B3：缺键 ⇒ null');

    // 手改文件塞了词表外的值 ⇒ null（不抛）。
    final corrupt = Map<String, dynamic>.from(json)..['causeKey'] = '不存在的key';
    expect(MistakeEntry.fromJson(corrupt)!.causeKey, isNull,
        reason: 'B3：非法值 ⇒ null');
  });

  // ══════════════════════════════════════════════════════════════════
  //  B4. copyWith 显式清 causeKey
  // ══════════════════════════════════════════════════════════════════

  test('B4：copyWith(clearCauseKey: true) 真的清空（不被 ?? 吞）', () {
    final e = MistakeEntry(
      id: 'm_b4',
      stem: '题干',
      userAnswer: 'u',
      correctAnswer: 'c',
      errorType: MistakeErrorType.concept,
      subjectArea: '',
      createdAt: DateTime.fromMillisecondsSinceEpoch(1),
      causeKey: MistakeCauseKey.misappliedVariant.name,
    );
    // 普通 copyWith 保留原值。
    expect(e.copyWith().causeKey, MistakeCauseKey.misappliedVariant.name);
    // 显式清空开关 ⇒ null。
    expect(e.copyWith(clearCauseKey: true).causeKey, isNull,
        reason: 'B4：clearCauseKey 开关必须能真正清空');
  });

  // ══════════════════════════════════════════════════════════════════
  //  B5. 整理写回链路
  // ══════════════════════════════════════════════════════════════════

  test('B5：整理写回链路（假 AI 带 causeKey）⇒ 条目 causeKey 落库', () async {
    MistakeBook.debugOrganizeSender = (entry) async => MistakeAiAnalysis(
          summary: 'AI 归类',
          pitfalls: const ['避坑 1'],
          causeKey: MistakeCauseKey.misappliedVariant.name,
        );

    final added = MistakeBook.instance.add(
      stem: 'B5 写回题',
      userAnswer: 'u',
      correctAnswer: 'c',
      errorType: MistakeErrorType.calculation,
      subjectArea: '',
    );
    MistakeBook.instance.debugEnqueueAiOrganize(added.id);

    // 过 500ms debounce（真实 timer）→ 跑 _runAiOrganize → 写回。
    await Future<void>.delayed(const Duration(milliseconds: 700));
    await MistakeBook.instance.debugWaitAiOrganizeDone();

    final refreshed = MistakeBook.instance.findById(added.id);
    expect(refreshed?.aiSummary, 'AI 归类', reason: 'B5：summary 照旧写回');
    expect(refreshed?.causeKey, MistakeCauseKey.misappliedVariant.name,
        reason: 'B5：causeKey 必须一并入库');
  });

  // ══════════════════════════════════════════════════════════════════
  //  B6. mistakeCauseKeyCounts 六键计数
  // ══════════════════════════════════════════════════════════════════

  test('B6：mistakeCauseKeyCounts 六键精确（null → unclassified 归并）', () {
    seed(MistakeErrorType.calculation, causeKey: 'missedGenePair');
    seed(MistakeErrorType.calculation, causeKey: 'missedGenePair');
    seed(MistakeErrorType.concept, causeKey: 'misappliedVariant');
    seed(MistakeErrorType.concept, causeKey: 'fractionSystem');
    // 两条未判（causeKey null）→ unclassified 桶。
    seed(MistakeErrorType.careless);
    seed(MistakeErrorType.other);

    final counts = mistakeCauseKeyCounts(MistakeBook.instance.entries);

    expect(counts.length, MistakeCauseKey.values.length, reason: 'B6：六键全出现');
    expect(counts[MistakeCauseKey.missedGenePair], 2);
    expect(counts[MistakeCauseKey.misappliedVariant], 1);
    expect(counts[MistakeCauseKey.fractionSystem], 1);
    expect(counts[MistakeCauseKey.genotypeAsPhenotype], 0,
        reason: 'B6：零值键也保留');
    expect(counts[MistakeCauseKey.testcrossSelfingConfusion], 0);
    expect(counts[MistakeCauseKey.unclassified], 2,
        reason: 'B6：null 的条目归入 unclassified 桶');

    // 全库无一条 AI 判过 ⇒ hasAnyAiCauseKey 为 false。
    final allNull = [
      MistakeEntry(
        id: 'm_b6_a',
        stem: 'a',
        userAnswer: 'u',
        correctAnswer: 'c',
        errorType: MistakeErrorType.concept,
        subjectArea: '',
        createdAt: DateTime.fromMillisecondsSinceEpoch(1),
      )
    ];
    expect(hasAnyAiCauseKey(allNull), isFalse);
    expect(hasAnyAiCauseKey(MistakeBook.instance.entries), isTrue);
  });

  // ══════════════════════════════════════════════════════════════════
  //  B7. 雷达卡 AI 视图
  // ══════════════════════════════════════════════════════════════════

  testWidgets('B7a：无 AI 数据 → AI 视图诚实空态在屏、图不渲染', (tester) async {
    seed(MistakeErrorType.concept); // 没有 causeKey
    seed(MistakeErrorType.calculation);

    await pumpPage(tester);

    // 默认自评视图：雷达图在，AI 空态不在。
    expect(find.byType(CauseRadarChart), findsOneWidget);
    expect(find.text('还没有 AI 判过的错因'), findsNothing);

    // 切到 AI 判视图 → 诚实空态 + 不画图。
    await tester.tap(find.text('AI 判'));
    await tester.pumpAndSettle();

    expect(find.text('还没有 AI 判过的错因'),
        findsOneWidget, reason: 'B7a：无 AI 数据 ⇒ 诚实空态在屏');
    expect(find.byType(CauseRadarChart), findsNothing,
        reason: 'B7a：AI 视图无数据 ⇒ 自评图不渲染');
    expect(find.byType(CauseKeyRadarChart), findsNothing,
        reason: 'B7a：AI 视图无数据 ⇒ AI 图不渲染');

    await settle(tester);
  });

  testWidgets('B7b：有 AI 数据 → AI 视图六轴标签在屏', (tester) async {
    seed(MistakeErrorType.calculation, causeKey: 'missedGenePair');
    seed(MistakeErrorType.concept, causeKey: 'misappliedVariant');

    await pumpPage(tester);

    await tester.tap(find.text('AI 判'));
    await tester.pumpAndSettle();

    expect(find.byType(CauseKeyRadarChart), findsOneWidget,
        reason: 'B7b：有 AI 数据 ⇒ AI 图在屏');
    for (final k in MistakeCauseKey.values) {
      expect(
        find.descendant(
          of: find.byType(CauseKeyRadarChart),
          matching: find.text(k.displayName),
        ),
        findsOneWidget,
        reason: 'B7b：六轴标签「${k.displayName}」必须在屏',
      );
    }
    expect(find.text('还没有 AI 判过的错因'), findsNothing);

    await settle(tester);
  });

  // ══════════════════════════════════════════════════════════════════
  //  B8. 视图切换 chip 可点 / 切得动
  // ══════════════════════════════════════════════════════════════════

  testWidgets('B8：自评 ⇄ AI 判 chip 可点且切得动（默认自评）', (tester) async {
    seed(MistakeErrorType.calculation, causeKey: 'missedGenePair');

    await pumpPage(tester);

    // 默认自评视图。
    expect(find.byType(CauseRadarChart), findsOneWidget,
        reason: 'B8：默认自评视图（零变化）');
    expect(find.byType(CauseKeyRadarChart), findsNothing);

    // 点「AI 判」→ 切到 AI 视图。
    await tester.tap(find.text('AI 判'));
    await tester.pumpAndSettle();
    expect(find.byType(CauseKeyRadarChart), findsOneWidget,
        reason: 'B8：点 AI 判 ⇒ 切到 AI 视图');
    expect(find.byType(CauseRadarChart), findsNothing);

    // 点「自评」→ 切回自评视图。
    await tester.tap(find.text('自评'));
    await tester.pumpAndSettle();
    expect(find.byType(CauseRadarChart), findsOneWidget,
        reason: 'B8：点自评 ⇒ 切回自评视图');
    expect(find.byType(CauseKeyRadarChart), findsNothing);

    await settle(tester);
  });
}
