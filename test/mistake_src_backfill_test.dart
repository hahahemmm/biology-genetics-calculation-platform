// ════════════════════════════════════════════════════════════════════════
//  test/mistake_src_backfill_test.dart
//  错题本「存题来源」闭环的数据层守卫：srcModule / srcParams 的落库、
//  重复存入时的**来源补写**、JSON 新老兼容。
// ════════════════════════════════════════════════════════════════════════
//
//  ## 病灶（移植前本仓的状态）
//
//  本仓 `MistakeEntry` 只有 13 个字段，**没有** srcModule / srcParams：
//  · 复习退避（3→7→14→30 天）到期那一刻，学生手里**只有题干**——必须
//    自己切回 9331、凭记忆把亲本重敲一遍才能重做；
//  · 错题本与课标**零连接**（本仓 `curriculum_page.dart` 连反向锚点表
//    都还没有），学生不知道一条错题考的是哪条课标。
//
//  ## 口径（与 `MistakeBook._backfillSource` 注释同款，此处钉住行为）
//
//  · SRC-1 老条目（来源字段皆 null）**再存一次** ⇒ 来源回填。这是老
//        数据第一次拿到回程按钮的唯一路径（否则该功能对历史错题只对
//        「第一次」有效）。
//  · SRC-2 旧条目**已有**可用来源 ⇒ 本次**不覆盖**（那是第一次真实存取
//        时的来源；改掉等于拿后来的观测篡改历史）。
//  · SRC-3 本次**也没**带来可用来源 ⇒ 什么都不写。不写空串、不写空 map、
//        也不写「有 module 没参数」那种半截状态——半截会让后来的完整
//        回填被「不覆盖」口径挡回去，把老条目永久卡在不出按钮的状态。
//  · SRC-4 回填**只动来源**：id / createdAt / 复习状态 / 退避 / AI 字段
//        全部原样。
//  · SRC-5 落盘往返：写得出、读得回。
//  · SRC-6 老 JSON（无那两个 key）整批不丢。⛔ 这是本文件最不能写错的
//        一条：`fromJson` 一旦对老格式返 null，`_entries` 整批空掉 ⇒
//        学生的错题本**静默消失**且无任何报错。
//
//  ## 视口
//
//  纯数据层，不需要 widget 树；800×1200 @1.0（同批 UI 守卫）。

import 'dart:convert';
import 'dart:io';

import 'package:biology/state/first_run_store.dart';
import 'package:biology/state/mistake_book.dart';
import 'package:flutter_test/flutter_test.dart';

/// 一条「存题来源上线**之前**」的错题：两个来源字段皆 null。
/// 走真实的 `addOrFind` 且**不传**来源 —— 那就是老数据落盘后的样子。
MistakeEntry seedLegacy({
  String stem = '9331 单基因：Aa × aa 的子代比例',
  String correct = '1:1',
}) =>
    MistakeBook.instance.addOrFind(
      stem: stem,
      userAnswer: '3:1',
      correctAnswer: correct,
      errorType: MistakeErrorType.other,
      subjectArea: '遗传 · 9331',
    ).entry;

/// 本次「从工具存进来」带来的来源（单基因页 `cross_mono` 的 p1/p2）。
Map<String, String> monoParams([String p1 = 'Aa', String p2 = 'aa']) =>
    {'p1': p1, 'p2': p2};

void main() {
  late Directory tmp;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('mistake_src_backfill');
    MistakeBook.debugFilePath = '${tmp.path}/mistakes.json';
    MistakeBook.debugTrashFilePath = '${tmp.path}/mistakes.trash.json';
    MistakeBook.instance.debugReset();
    FirstRunStore.debugFilePath = '${tmp.path}/first_run.json';
    FirstRunStore.debugWebStorage = null;
    FirstRunStore.debugForceIsWebStorage = false;
    FirstRunStore.instance.debugReset();
  });

  tearDown(() {
    MistakeBook.instance.debugFlushSave();
    MistakeBook.instance.debugResetAiOrganize();
    MistakeBook.instance.debugReset();
    MistakeBook.debugFilePath = null;
    MistakeBook.debugTrashFilePath = null;
    FirstRunStore.debugFilePath = null;
    FirstRunStore.debugWebStorage = null;
    FirstRunStore.debugForceIsWebStorage = null;
    FirstRunStore.instance.debugReset();
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  // ── SRC-0 新条目：来源随 add 落库（正向最基本的一条）──────────────────

  test('SRC-0 从工具存进来的新条目 ⇒ srcModule / srcParams 随 add 落库', () {
    final r = MistakeBook.instance.addOrFind(
      stem: '9331 单基因：Aa × Aa 的子代比例',
      userAnswer: '1:2:1',
      correctAnswer: '3:1',
      errorType: MistakeErrorType.other,
      subjectArea: '分离定律',
      srcModule: 'cross_mono',
      srcParams: monoParams('Aa', 'Aa'),
    );
    final e = r.entry;

    expect(r.isNew, isTrue);
    expect(e.srcModule, 'cross_mono');
    expect(e.srcParams!['p1'], 'Aa');
    expect(e.srcParams!['p2'], 'Aa');
  });

  // ── SRC-1 核心：老条目再存一次 ⇒ 来源回填 ─────────────────────────────

  test('SRC-1 老条目再存一次 ⇒ 来源回填（去重语义不变）', () {
    final legacy = seedLegacy();
    expect(legacy.srcModule, isNull, reason: '前提：老条目没有来源');
    expect(legacy.srcParams, isNull);

    // 学生再存一次——这一次是从 9331 单基因页存进来的。
    final r = MistakeBook.instance.addOrFind(
      stem: legacy.stem,
      userAnswer: '3:1',
      correctAnswer: legacy.correctAnswer,
      errorType: MistakeErrorType.other,
      subjectArea: '遗传 · 9331',
      srcModule: 'cross_mono',
      srcParams: monoParams(),
    );

    // ① 仍是**同一条**旧条目（去重语义没被破坏：不许凭空多一条）。
    expect(r.isNew, isFalse,
        reason: '命中重复 ⇒ 仍报 isNew=false（调用方据此跳过 AI 整理入队）');
    expect(r.entry.id, legacy.id, reason: 'id 不变：改的是旧条目，不是新条目');
    expect(MistakeBook.instance.entries.length, 1,
        reason: '去重路径不许产生第二条');

    // ② 来源被回填，且是**具体值**（不许只断非空）。
    expect(r.entry.srcModule, 'cross_mono');
    expect(r.entry.srcParams, isNotNull);
    expect(r.entry.srcParams!['p1'], 'Aa');
    expect(r.entry.srcParams!['p2'], 'aa');

    // ③ 库里那一条也拿到了（返回实例不能是孤儿副本）。
    expect(MistakeBook.instance.entries.single.srcModule, 'cross_mono',
        reason: '回填必须落进 _entries，不许只改一个临时对象');
  });

  // ── SRC-2 旧来源不被覆盖 ────────────────────────────────────────────

  test('SRC-2 旧条目已有来源 ⇒ 本次再存**不覆盖**（不篡改历史来源）', () {
    final first = MistakeBook.instance.addOrFind(
      stem: '9331 单基因：Aa × aa 的子代比例',
      userAnswer: '3:1',
      correctAnswer: '1:1',
      errorType: MistakeErrorType.other,
      subjectArea: '遗传 · 9331',
      srcModule: 'cross_mono',
      srcParams: monoParams('Aa', 'aa'),
    ).entry;

    // 同一道题，改从伴性遗传页再存一次（参数是另一组）。
    final r = MistakeBook.instance.addOrFind(
      stem: first.stem,
      userAnswer: '3:1',
      correctAnswer: first.correctAnswer,
      errorType: MistakeErrorType.other,
      subjectArea: '遗传 · 9331',
      srcModule: 'cross_sex_linked',
      srcParams: monoParams('XAXa', 'XAY'),
    );

    expect(r.isNew, isFalse);
    expect(r.entry.srcModule, 'cross_mono',
        reason: '第一次真实存取时的来源不能被后来的观测改掉');
    expect(r.entry.srcParams!['p1'], 'Aa');
    expect(r.entry.srcParams!['p2'], 'aa',
        reason: '旧来源的参数才是当初那道题真实的亲本');
    expect(MistakeBook.instance.entries.length, 1);
  });

  // ── SRC-3 没有可用来源 ⇒ 什么都不写 ──────────────────────────────────

  test('SRC-3 本次也没带来可用来源 ⇒ 不写空串/空 map/半截状态', () {
    final legacy = seedLegacy();

    // ① 这次仍然是从手加表单存的（无来源）⇒ 保持 null。
    MistakeBook.instance.addOrFind(
      stem: legacy.stem,
      userAnswer: '3:1',
      correctAnswer: legacy.correctAnswer,
      errorType: MistakeErrorType.other,
      subjectArea: '遗传 · 9331',
    );
    var e = MistakeBook.instance.entries.single;
    expect(e.srcModule, isNull, reason: '不许把空值写上去');
    expect(e.srcParams, isNull);

    // ② 只带 moduleId、不带参数 ⇒ **不写**。写了就是「有 module 没参数」，
    //    按钮照样不渲染，而这一行会把后来那次字段齐了的回填挡回去
    //    （不覆盖口径），老条目就永久卡在不出按钮的状态。
    MistakeBook.instance.addOrFind(
      stem: legacy.stem,
      userAnswer: '3:1',
      correctAnswer: legacy.correctAnswer,
      errorType: MistakeErrorType.other,
      subjectArea: '遗传 · 9331',
      srcModule: 'cross_mono',
    );
    e = MistakeBook.instance.entries.single;
    expect(e.srcModule, isNull,
        reason: '半截来源（无参数）不产生任何学生可见收益 ⇒ 不落盘');
    expect(e.srcParams, isNull);

    // ③ 反证：半截状态一旦写上，后面那次完整来源就填不进去了——这正是
    //    口径 ③ 不能退让的原因。
    final r = MistakeBook.instance.addOrFind(
      stem: legacy.stem,
      userAnswer: '3:1',
      correctAnswer: legacy.correctAnswer,
      errorType: MistakeErrorType.other,
      subjectArea: '遗传 · 9331',
      srcModule: 'cross_mono',
      srcParams: monoParams(),
    );
    expect(r.entry.srcModule, 'cross_mono');
    expect(r.entry.srcParams!['p1'], 'Aa');
  });

  // ── SRC-4 回填不得动其它字段 ────────────────────────────────────────

  test('SRC-4 回填只动来源：id/时间/复习状态/退避/AI 字段全部原样', () {
    final legacy = seedLegacy();
    // 给这条挂上复习进度与 AI 整理——它们比来源更早写盘。
    MistakeBook.instance.applyAiAnalysis(legacy.id,
        summary: '把显性纯合当隐性看了', pitfalls: ['先判显隐再写基因型']);
    MistakeBook.instance.markStatus(legacy.id, MistakeReviewStatus.reviewing);
    final before = MistakeBook.instance.entries.single;
    expect(before.aiSummary, isNotNull, reason: '前提：AI 字段已挂上');

    final r = MistakeBook.instance.addOrFind(
      stem: legacy.stem,
      userAnswer: '',
      correctAnswer: legacy.correctAnswer,
      errorType: MistakeErrorType.other,
      subjectArea: '遗传 · 9331',
      srcModule: 'cross_mono',
      srcParams: monoParams(),
    );
    final after = MistakeBook.instance.entries.single;

    expect(after.id, before.id);
    expect(after.createdAt, before.createdAt,
        reason: 'createdAt 是排序键，回填不得改动它');
    expect(after.reviewStatus, before.reviewStatus);
    expect(after.reviewedAt, before.reviewedAt,
        reason: 'reviewedAt 空/非空决定到期判定，回填不得碰');
    expect(after.masteredStreak, before.masteredStreak);
    expect(after.aiSummary, before.aiSummary);
    expect(after.aiPitfalls, before.aiPitfalls);
    expect(after.userAnswer, before.userAnswer);
    expect(after.srcModule, 'cross_mono');
    expect(r.entry.id, before.id);
  });

  // ── SRC-5 落盘往返：回填必须写得出去、读得回来 ─────────────────────────

  test('SRC-5 回填后写盘 + 清内存 + 重载 ⇒ 来源仍在', () async {
    final legacy = seedLegacy();
    MistakeBook.instance.addOrFind(
      stem: legacy.stem,
      userAnswer: '3:1',
      correctAnswer: legacy.correctAnswer,
      errorType: MistakeErrorType.other,
      subjectArea: '遗传 · 9331',
      srcModule: 'cross_mono',
      srcParams: monoParams(),
    );
    MistakeBook.instance.debugFlushSave();

    // 磁盘上必须真的有这两个 key（toJson 没跟上 ⇒ 回填只在内存里活一轮）。
    final raw = File(MistakeBook.debugFilePath!).readAsStringSync();
    expect(raw.contains('"srcModule":"cross_mono"'), isTrue,
        reason: '写盘 JSON 必须含 srcModule；实际：$raw');
    expect(raw.contains('"p1":"Aa"'), isTrue,
        reason: '写盘 JSON 必须含 srcParams 的具体参数');

    MistakeBook.instance.debugReset();
    expect(MistakeBook.instance.entries.length, 0, reason: '前提：内存已清空');
    await MistakeBook.instance.load();

    final back = MistakeBook.instance.entries.single;
    expect(back.id, legacy.id);
    expect(back.srcModule, 'cross_mono', reason: '重载后来源仍可用');
    expect(back.srcParams!['p1'], 'Aa');
    expect(back.srcParams!['p2'], 'aa');
  });

  // ── SRC-6 老数据整批不许丢（fromJson 的老格式分支）────────────────────

  test('SRC-6 老 JSON（无 srcModule/srcParams 两个 key）整批不丢', () async {
    // 手工写一份「存题来源上线之前」的盘面格式：压根没有那两个 key。
    final legacy = <Map<String, dynamic>>[
      {
        'id': 'legacy-1',
        'stem': '老题一',
        'userAnswer': 'a',
        'correctAnswer': 'A',
        'errorType': 'other',
        'subjectArea': '遗传',
        'createdAt': 1700000000000,
        'reviewStatus': 'unreviewed',
        'aiPitfalls': <String>[],
      },
      {
        'id': 'legacy-2',
        'stem': '老题二',
        'userAnswer': 'b',
        'correctAnswer': 'B',
        'errorType': 'other',
        'subjectArea': '遗传',
        'createdAt': 1700000001000,
        'reviewStatus': 'reviewing',
        'aiPitfalls': <String>[],
      },
      {
        'id': 'legacy-3',
        'stem': '老题三',
        'userAnswer': 'c',
        'correctAnswer': 'C',
        'errorType': 'other',
        'subjectArea': '遗传',
        'createdAt': 1700000002000,
        'reviewStatus': 'mastered',
        'aiPitfalls': <String>[],
      },
    ];
    File(MistakeBook.debugFilePath!)
        .writeAsStringSync(jsonEncode(legacy), encoding: utf8);

    await MistakeBook.instance.load();

    expect(MistakeBook.instance.entries.length, 3,
        reason: '⛔ fromJson 一旦对老格式返 null，这三条会整批消失——'
            '学生的错题本静默清空，且没有任何报错');
    for (final e in MistakeBook.instance.entries) {
      expect(e.srcModule, isNull, reason: '老数据本就没有来源，只是 null');
      expect(e.srcParams, isNull);
    }
    final ids = MistakeBook.instance.entries.map((e) => e.id).toSet();
    expect(ids, {'legacy-1', 'legacy-2', 'legacy-3'});

    // 老条目**再存一次**仍能被认成同一条（查重按题干+答案，与来源无关）。
    final r = MistakeBook.instance.addOrFind(
      stem: '老题一',
      userAnswer: 'a',
      correctAnswer: 'A',
      errorType: MistakeErrorType.other,
      subjectArea: '遗传',
    );
    expect(r.isNew, isFalse);
    expect(MistakeBook.instance.entries.length, 3);
  });

  // ── SRC-7 脏参数不许进库（非 Map / 空 map / 非字符串 moduleId）──────────

  test('SRC-7 脏 srcParams 归一成 null，空 map 不算可用来源', () async {
    // srcParams 写成非 Map（人工改盘 / 跨版本导出的典型脏数据）。
    File(MistakeBook.debugFilePath!).writeAsStringSync(
      jsonEncode([
        {
          'id': 'dirty-1',
          'stem': '脏题',
          'userAnswer': 'a',
          'correctAnswer': 'A',
          'errorType': 'other',
          'subjectArea': '遗传',
          'createdAt': 1700000000000,
          'reviewStatus': 'unreviewed',
          'aiPitfalls': <String>[],
          'srcModule': 'cross_mono',
          'srcParams': '不是 map',
        },
        {
          'id': 'dirty-2',
          'stem': '空参数题',
          'userAnswer': 'a',
          'correctAnswer': 'A',
          'errorType': 'other',
          'subjectArea': '遗传',
          'createdAt': 1700000001000,
          'reviewStatus': 'unreviewed',
          'aiPitfalls': <String>[],
          'srcModule': 'cross_mono',
          'srcParams': <String, dynamic>{},
        },
      ]),
      encoding: utf8,
    );
    await MistakeBook.instance.load();

    final byId = {for (final e in MistakeBook.instance.entries) e.id: e};
    expect(byId.keys, containsAll(['dirty-1', 'dirty-2']),
        reason: '脏参数不许让条目整条丢失（其余字段仍是好的）');
    expect(byId['dirty-1']!.srcModule, 'cross_mono',
        reason: 'moduleId 本身是好的，保留');
    expect(byId['dirty-1']!.srcParams, isNull,
        reason: '脏参数不许进库（否则回程按钮点下去必然无效）');
    expect(byId['dirty-2']!.srcParams, isNull,
        reason: '空 map = 没有可回填的东西 ⇒ 归一成 null');

    // 反证：这两条都判为「无可用来源」，再存一次**能**拿到完整来源
    // （半截状态没被写上，所以没把「不覆盖」口径的闸门关上）。
    for (final id in ['dirty-1', 'dirty-2']) {
      final e = byId[id]!;
      final r = MistakeBook.instance.addOrFind(
        stem: e.stem,
        userAnswer: e.userAnswer,
        correctAnswer: e.correctAnswer,
        errorType: e.errorType,
        subjectArea: e.subjectArea,
        srcModule: 'cross_mono',
        srcParams: monoParams(),
      );
      expect(r.entry.srcModule, 'cross_mono',
          reason: '$id 重存后必须拿到可用来源');
      expect(r.entry.srcParams!['p1'], 'Aa');
    }
  });
}
