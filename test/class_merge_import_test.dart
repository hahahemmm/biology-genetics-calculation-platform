// ════════════════════════════════════════════════════════════════════════
//  test/class_merge_import_test.dart
//  v2.19.66：班级错题「合并导入 + 来源标记」的第一部分守卫。
// ════════════════════════════════════════════════════════════════════════
//
//  ## 本文件钉住的五块
//  C1：合并纯函数 classIncomingToAdd——按 题干+答案 与 local 及 incoming
//      自身去重；返回的新条目全带 sourceTag；**local 一字不改**。
//  C2：sourceTag schema round-trip；旧 JSON 无键 / 空串不抛且落 null。
//  C3：加密包全链路——甲机器导出 → 乙机器（独立临时目录）合并入库带标；
//      再合一次 ⇒ 0 新增、跳过数正确。
//  C4：UI——合并后卡片见「来自同学」caption；点「仅看本人」⇒ 该条消失、
//      本人条仍在；取消筛选恢复。
//  C5：覆盖式导入（恢复备份）与「合并同学错题包」两个入口并存、文案可区分。
//
//  ## 数据铁律
//  题干**唯一**：MistakeBook 存入类入口按 题干+答案 去重，题干重复会互相
//  顶替。一律用单调计数器拼题干，绝不用 DateTime.now（同毫秒撞）。
//
//  ## ⚠️ 隔离：MistakeBook 落到独立临时目录，绝不碰真实库。
//  setUp/tearDown 照抄 ai_cause_key_test.dart。

import 'dart:io';

import 'package:biology/pages/mistake_book_page.dart';
import 'package:biology/state/mistake_book.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 题干 / 来源标计数器：保证各行题干唯一。
int _seq = 0;

/// 直接造一条 [MistakeEntry]（纯函数 / schema 测试用，不进库）。
MistakeEntry _mk(String id, String stem, String answer, {String? tag}) =>
    MistakeEntry(
      id: id,
      stem: stem,
      userAnswer: '我答$id',
      correctAnswer: answer,
      errorType: MistakeErrorType.concept,
      subjectArea: '',
      createdAt: DateTime.fromMillisecondsSinceEpoch(1),
      sourceTag: tag,
    );

void main() {
  late Directory tmp;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('class_merge_import');
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

  /// 存一条本人错题（题干唯一）；返回条目本体。
  MistakeEntry seedOwn() {
    final n = ++_seq;
    return MistakeBook.instance.add(
      stem: '本人题$n',
      userAnswer: '我答$n',
      correctAnswer: '正答$n',
      errorType: MistakeErrorType.concept,
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
  //  C1. 合并纯函数
  // ══════════════════════════════════════════════════════════════════

  test('C1：去重（与 local + 自身）+ 打标 + local 原列表逐字未动', () {
    final local = [
      _mk('l1', '题A', 'A'),
      _mk('l2', '题B', 'B'),
      _mk('l3', '题C', 'C'),
    ];
    // 快照：函数跑完逐字对比 local 没被动过。
    final before = [for (final e in local) e.toJson().toString()];

    final incoming = [
      _mk('i1', '题A', 'A'), // 与 local 重复
      _mk('i2', ' 题B ', 'B'), // trim 后与 local 重复
      _mk('i3', '新题D', 'D'),
      _mk('i4', '新题E', 'E'),
      _mk('i5', '新题D', 'D'), // 与 incoming 自身重复
    ];

    final add = classIncomingToAdd(local, incoming, sourceTag: '来自同学');

    expect(add.length, 2, reason: 'C1：5 条里 3 条重复 ⇒ 只追加 2 条');
    expect(add.map((e) => e.stem).toSet(), {'新题D', '新题E'},
        reason: 'C1：追加的正是两条新题');
    expect(add.every((e) => e.sourceTag == '来自同学'), isTrue,
        reason: 'C1：追加的每条都要打上传入的 sourceTag');

    // local 逐字未动（同长度 + 每条的 JSON 一字不差）。
    expect(local.length, 3, reason: 'C1：local 条数不变');
    for (var i = 0; i < local.length; i++) {
      expect(local[i].toJson().toString(), before[i],
          reason: 'C1：local[$i] 必须逐字未动');
      expect(local[i].sourceTag, isNull,
          reason: 'C1：local 条目的 sourceTag 不得被函数改写');
    }
  });

  // ══════════════════════════════════════════════════════════════════
  //  C2. schema round-trip
  // ══════════════════════════════════════════════════════════════════

  test('C2：sourceTag round-trip；旧 JSON 无键 / 空串 ⇒ null 不抛', () {
    final e = _mk('m_c2', '题干', '答案', tag: '来自同学');
    final json = e.toJson();
    expect(json['sourceTag'], '来自同学', reason: 'C2：toJson 写 sourceTag');

    final back = MistakeEntry.fromJson(json);
    expect(back!.sourceTag, '来自同学', reason: 'C2：round-trip 保留 sourceTag');

    // 旧 JSON（无 sourceTag 键）⇒ 不抛且为 null（绝不整条丢弃）。
    final legacy = Map<String, dynamic>.from(json)..remove('sourceTag');
    final legacyBack = MistakeEntry.fromJson(legacy);
    expect(legacyBack, isNotNull, reason: 'C2：缺键不得导致整条丢弃');
    expect(legacyBack!.sourceTag, isNull, reason: 'C2：缺键 ⇒ null');

    // 空串（手改文件塞的「非法」值）⇒ 归一成 null。
    final empty = Map<String, dynamic>.from(json)..['sourceTag'] = '';
    expect(MistakeEntry.fromJson(empty)!.sourceTag, isNull,
        reason: 'C2：空串 ⇒ null');

    // 本人原创（sourceTag null）也 round-trip。
    final own = _mk('m_c2b', '本人题', '答案');
    expect(own.toJson()['sourceTag'], isNull, reason: 'C2：本人题写 null');
    expect(MistakeEntry.fromJson(own.toJson())!.sourceTag, isNull,
        reason: 'C2：null round-trip');
  });

  // ══════════════════════════════════════════════════════════════════
  //  C3. 加密包全链路
  // ══════════════════════════════════════════════════════════════════

  test('C3：加密包导出 → 另一实例合并入库带标；再合 ⇒ 0 新增', () async {
    // 甲机器（同学）：3 条本人原创（无标）。
    final sourceIds = <String>{};
    for (var i = 1; i <= 3; i++) {
      final e = MistakeBook.instance.add(
        stem: '同学题$i',
        userAnswer: 'u$i',
        correctAnswer: 'c$i',
        errorType: MistakeErrorType.concept,
        subjectArea: '',
      );
      sourceIds.add(e.id);
    }
    final env = await MistakeBook.instance.exportEncryptedJson(
      passphrase: 'pwd123',
      desensitize: false,
    );

    // 乙机器（老师）：独立临时目录 + 空库。
    final teacherTmp = Directory.systemTemp.createTempSync('teacher_machine');
    MistakeBook.instance.debugFlushSave();
    MistakeBook.debugFilePath = '${teacherTmp.path}/mistakes.json';
    MistakeBook.debugTrashFilePath = '${teacherTmp.path}/mistakes.trash.json';
    MistakeBook.instance.debugReset();
    expect(MistakeBook.instance.entries, isEmpty, reason: 'C3：乙机器起始空库');

    // 第一次合并 ⇒ 3 条入库、全带标。
    final r1 = await MistakeBook.instance.classMergeImport(
      env,
      passphrase: 'pwd123',
    );
    expect(r1.added, 3, reason: 'C3：3 条全新 ⇒ 全并入');
    expect(r1.skipped, 0, reason: 'C3：空库里没有可跳过的重复');
    expect(MistakeBook.instance.entries.length, 3, reason: 'C3：3 条落库');
    expect(
      MistakeBook.instance.entries.every((e) => e.sourceTag == '来自同学'),
      isTrue,
      reason: 'C3：并进来的每条都带「来自同学」标',
    );
    // 合并条目必须换新 id（源包 id 在同学机器上生成，沿用会撞 id ⇒
    // 错题本页按 id 建 GlobalKey，重复 key 直接崩）。
    final mergedIds = MistakeBook.instance.entries.map((e) => e.id).toSet();
    expect(mergedIds.length, 3, reason: 'C3：入库 id 唯一');
    for (final e in MistakeBook.instance.entries) {
      expect(sourceIds.contains(e.id), isFalse,
          reason: 'C3：合并条目不得沿用源包 id');
    }

    // 同一个包再合一次 ⇒ 0 新增、3 道重复跳过。
    final r2 = await MistakeBook.instance.classMergeImport(
      env,
      passphrase: 'pwd123',
    );
    expect(r2.added, 0, reason: 'C3：重复包 ⇒ 0 新增');
    expect(r2.skipped, 3, reason: 'C3：回执跳过数正确');
    expect(MistakeBook.instance.entries.length, 3, reason: 'C3：库不变');

    // 收尾：把 store 落盘到乙机器目录（验证可写 + 别留 pending timer），
    // 再把指针还原到本测试的目录——否则 tearDown 的 flush 会写到已删除的
    // 乙机器目录，吐一行被吞掉的 save failed 噪音。
    MistakeBook.instance.debugFlushSave();
    expect(File('${teacherTmp.path}/mistakes.json').existsSync(), isTrue,
        reason: 'C3：合并结果确实写盘');
    MistakeBook.instance.debugReset();
    MistakeBook.debugFilePath = '${tmp.path}/mistakes.json';
    MistakeBook.debugTrashFilePath = '${tmp.path}/mistakes.trash.json';
    if (teacherTmp.existsSync()) teacherTmp.deleteSync(recursive: true);
  });

  // ══════════════════════════════════════════════════════════════════
  //  C4. UI：来源标 + 仅看本人筛选
  // ══════════════════════════════════════════════════════════════════

  testWidgets('C4：合并后卡片见「来自同学」；仅看本人筛掉它、取消恢复', (tester) async {
    // 用明文包模拟同学包：先造一条同学题 → 导出 → 清空 → 只留本人题 → 合并。
    MistakeBook.instance.add(
      stem: '同学错题XYZ',
      userAnswer: 'u',
      correctAnswer: 'c',
      errorType: MistakeErrorType.concept,
      subjectArea: '',
    );
    final pack = MistakeBook.instance.exportJson(desensitize: false);
    MistakeBook.instance.debugReset();

    seedOwn(); // 本人一条（sourceTag 为空）
    final r = await MistakeBook.instance.classMergeImport(pack);
    expect(r.added, 1, reason: 'C4：同学那条并入');
    expect(MistakeBook.instance.entries.length, 2);

    await pumpPage(tester);

    // 合并后的卡片：题干在 + 「来自同学」来源标在。
    expect(find.text('同学错题XYZ'), findsOneWidget);
    expect(find.text('来自同学'), findsOneWidget,
        reason: 'C4：同学题卡片显示来源标');

    // 点「仅看本人」⇒ 同学条消失、本人条仍在、来源标消失。
    expect(find.byKey(const Key('mistake_own_only_filter')), findsOneWidget,
        reason: 'C4：筛选 chip 在屏');
    await tester.tap(find.byKey(const Key('mistake_own_only_filter')));
    await tester.pumpAndSettle();

    expect(find.text('同学错题XYZ'), findsNothing,
        reason: 'C4：仅看本人 ⇒ 同学题被筛掉');
    expect(find.text('来自同学'), findsNothing, reason: 'C4：来源标随之消失');
    expect(find.textContaining('本人题'), findsOneWidget,
        reason: 'C4：本人自己的题仍在');

    // 再点一次取消筛选 ⇒ 同学条回来。
    await tester.tap(find.byKey(const Key('mistake_own_only_filter')));
    await tester.pumpAndSettle();
    expect(find.text('同学错题XYZ'), findsOneWidget,
        reason: 'C4：取消筛选后同学题恢复可见');
    expect(find.text('来自同学'), findsOneWidget);

    await settle(tester);
  });

  // ══════════════════════════════════════════════════════════════════
  //  C5. 两个入口并存
  // ══════════════════════════════════════════════════════════════════

  testWidgets('C5：覆盖式导入与「合并同学错题包」两入口并存、文案可区分', (tester) async {
    seedOwn();
    await pumpPage(tester);

    await tester.tap(find.byTooltip('更多'));
    await tester.pumpAndSettle();

    // 覆盖式（恢复备份）入口仍在——防误删回归。
    expect(find.text('导入 JSON'), findsOneWidget,
        reason: 'C5：覆盖式导入入口不得消失');
    expect(find.textContaining('恢复备份（覆盖）'), findsOneWidget,
        reason: 'C5：覆盖式入口文案点明「恢复备份（覆盖）」');

    // 合并入口并列在屏。
    expect(find.text('合并同学错题包'), findsOneWidget,
        reason: 'C5：合并同学错题包入口在屏');

    await settle(tester);
  });
}
