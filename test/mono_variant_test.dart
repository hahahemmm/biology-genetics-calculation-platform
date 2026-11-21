// ════════════════════════════════════════════════════════════════════════
//  test/mono_variant_test.dart
//  v2.19.65：复习会话「练道变式」——mono 限定变式闭环（创新提案 #2 首刀）。
// ════════════════════════════════════════════════════════════════════════
//
//  ## 本文件钉住的两块
//  ① 纯函数内核 [monoVariantOf]（lib/state/mono_variant.dart）：
//     仅认 `cross_mono` + 2 字母基因型；变式确定性；答案**由引擎算**（手动
//     用同一引擎再算一遍逐字对齐，防函数内部算错）。
//  ② 复习会话揭示区那枚「练道变式」：mono 错题揭示后给按钮，点一下把变式
//     存进错题本并回执；再点不重复；非 mono 错题不给按钮。
//
//  ## 数据铁律
//  题干**必须唯一**：错题本按「题干+答案」去重，题干重复会让两条题互相顶替。
//  故 V5 的种子题一律用单调计数器拼题干，绝不用 `DateTime.now`（同毫秒会撞）。
//
//  ## ⚠️ 隔离：MistakeBook / AiChatStore / ScanBankStore 各落独立临时目录，
//  AI 通道用空配置（绝不碰真实网络），绝不碰真实用户目录。
//
//  ## 视口 / finder 作用域
//  800×1200 @1.0；复习会话盖在错题本列表**之上**，列表卡片仍在树里（非
//  offstage）⇒ 对话框内 finder 收在 `find.byType(Dialog)` 作用域内。

import 'dart:io';

import 'package:biology/services/ai_client.dart';
import 'package:biology/engine/cross_engine.dart';
import 'package:biology/state/mono_variant.dart';
import 'package:biology/state/scan_bank_store.dart';
import 'package:biology/pages/mistake_book_page.dart';
import 'package:biology/pages/settings_page.dart' show AiChatStore, AiSettingsStore;
import 'package:biology/pages/widgets/mono_cross_widget.dart'
    show kMonoCrossSubjectArea;
import 'package:biology/state/mistake_book.dart';
import 'package:biology/ui/ai_chat_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 揭示区那枚按钮的文案（禁方向词、禁 markdown 星号）。
const _kRevealVariantLabel = '练道变式';

/// 题干计数器：保证每条种子题干唯一。
int _stemSeq = 0;

void main() {
  // ────────────────────────────────────────────────────────────────
  //  A. 纯函数内核：monoVariantOf
  // ────────────────────────────────────────────────────────────────

  /// 造一条 mono 存题形态的错题（直接构造，不落库）。
  MistakeEntry monoEntry(
    String id, {
    String p1 = 'Aa',
    String p2 = 'Aa',
    String? srcModule = kMonoVariantSrcModule,
    Map<String, String>? srcParams,
  }) {
    return MistakeEntry(
      id: id,
      stem: '原题 $p1 × $p2',
      userAnswer: '我答',
      correctAnswer: '正答',
      errorType: MistakeErrorType.calculation,
      subjectArea: kMonoCrossSubjectArea,
      createdAt: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      srcModule: srcModule,
      srcParams: srcParams ?? {'p1': p1, 'p2': p2},
    );
  }

  /// 独立复算：用**同一个** CrossEngine 算变式两亲本的 F₂ 表型比文本。
  /// 与 `mono_variant.dart` 的 `_build` 是同一份算法（同仓唯一口径），
  /// 用它把「函数内部算错」抓出来。
  String expectedRatio(String vp1, String vp2) {
    var dom = '';
    for (final s in [vp1, vp2]) {
      for (final c in s.split('')) {
        if (c == c.toUpperCase() && c != c.toLowerCase()) {
          dom = c;
          break;
        }
      }
      if (dom.isNotEmpty) break;
    }
    if (dom.isEmpty) dom = vp1[0].toUpperCase();
    final r = CrossEngine()
        .singleGeneCross(vp1, vp2, dominant: dom, recessive: dom.toLowerCase());
    final counts = r.phenotypeRatios.map((e) => e.count).toList();
    var g = 0;
    for (final c in counts) {
      g = g == 0 ? c : _gcd(g, c);
    }
    return g > 1 ? counts.map((c) => c ~/ g).join(':') : counts.join(':');
  }

  test('V1：合法 cross_mono 杂交条目 ⇒ 出变式，亲本变、答案非空', () {
    final e = monoEntry('V1-id', p1: 'Aa', p2: 'Aa');
    final v = monoVariantOf(e);

    expect(v, isNotNull, reason: 'V1：合法 mono 杂交题必须推得出变式');
    expect(v!.answer.isNotEmpty, isTrue, reason: 'V1：答案由引擎算，非空');
    // 变式亲本与原题（字符串级）不同——这正是「练一道新的」的意义。
    expect('${v.parent1}×${v.parent2}', isNot('Aa×Aa'),
        reason: 'V1：变式亲本必须与原题不同');
    // 'Aa'×'Aa' 的两个候选（把某一亲本首字母 A→a ⇒ 该亲本变 'aa'）都是
    // 'aa×Aa' / 'Aa×aa'，F₂ 就是 1:1（与 hash 无关的已知答案）。
    expect('${v.parent1}×${v.parent2}', anyOf('aa×Aa', 'Aa×aa'),
        reason: 'V1：变式只能是首字母大小写翻转出的那一组亲本');
    expect(v.answer, '1:1', reason: 'V1：aa×Aa 族变式的 F₂ 表型比就是 1:1');
    expect(v.stem, contains(v.parent1), reason: '题干点名变式亲本');
    expect(v.stem, contains(v.parent2), reason: '题干点名变式亲本');
  });

  test('V2：确定性——同一 entry 调两次结果逐字相同', () {
    final e = monoEntry('V2-id', p1: 'Aa', p2: 'Aa');
    final a = monoVariantOf(e);
    final b = monoVariantOf(e);

    expect(a, isNotNull);
    expect(b, isNotNull);
    expect(a!.parent1, b!.parent1, reason: 'V2：同一错题每次得到同一亲本1');
    expect(a.parent2, b.parent2, reason: 'V2：同一错题每次得到同一亲本2');
    expect(a.stem, b.stem, reason: 'V2：题干逐字相同');
    expect(a.answer, b.answer, reason: 'V2：答案逐字相同');
  });

  test('V3：答案与「手动用引擎算变式亲本」一致（防内部算错）', () {
    for (final id in ['V3-a', 'V3-b', 'V3-c']) {
      final v = monoVariantOf(monoEntry(id, p1: 'AA', p2: 'aa'))!;
      expect(v.answer, expectedRatio(v.parent1, v.parent2),
          reason: 'V3：$id 的变式答案必须等于引擎对变式亲本的复算值');
    }
    for (final id in ['V3-d', 'V3-e']) {
      final v = monoVariantOf(monoEntry(id, p1: 'aa', p2: 'aA'))!;
      expect(v.answer, expectedRatio(v.parent1, v.parent2),
          reason: 'V3：$id 的变式答案必须等于引擎对变式亲本的复算值');
    }
  });

  test('V4：测交形态条目也出变式且引擎答案正确；非 mono / 非法参数 ⇒ null', () {
    // 测交存题口径：srcParams.p2 记的是 `'${rec}${rec}'`（如 'aa'），普通两字母
    // 基因型 ⇒ 通用规则覆盖（⛔ 不为测交单开一条路径）。
    final tc = monoEntry('V4-tc', p1: 'Aa', p2: 'aa');
    final v = monoVariantOf(tc);
    expect(v, isNotNull, reason: 'V4：测交形态（p2=aa）也推得出变式');
    expect(v!.answer, expectedRatio(v.parent1, v.parent2),
        reason: 'V4：测交形态变式的答案必须与引擎复算一致');

    // srcModule 不是 cross_mono ⇒ null。
    expect(monoVariantOf(monoEntry('V4-m', srcModule: null)), isNull,
        reason: 'V4：手加条目（无来源）⇒ null');
    expect(monoVariantOf(monoEntry('V4-m2', srcModule: 'cross_9331')), isNull,
        reason: 'V4：别的来源模块 ⇒ null');

    // p1/p2 非法（非 2 字母）⇒ null（同 `_monoSrcParams` 的 `^[A-Za-z]{2}$`）。
    expect(monoVariantOf(monoEntry('V4-i1', p1: '1a', p2: 'Aa')), isNull,
        reason: 'V4：p1 含非字母 ⇒ null');
    expect(monoVariantOf(monoEntry('V4-i2', p1: 'A', p2: 'Aa')), isNull,
        reason: 'V4：p1 单字母 ⇒ null');
    expect(monoVariantOf(monoEntry('V4-i3', p1: 'Aa', p2: 'AaBb')), isNull,
        reason: 'V4：p2 多基因 ⇒ null');

    // srcParams 整个缺失 ⇒ null。
    final noParams = MistakeEntry(
      id: 'V4-np',
      stem: '无参数题',
      userAnswer: '',
      correctAnswer: '',
      errorType: MistakeErrorType.calculation,
      subjectArea: kMonoCrossSubjectArea,
      createdAt: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      srcModule: kMonoVariantSrcModule,
    );
    expect(monoVariantOf(noParams), isNull, reason: 'V4：无 srcParams ⇒ null');
  });

  // ────────────────────────────────────────────────────────────────
  //  B. 复习会话揭示区「练道变式」（UI）
  // ────────────────────────────────────────────────────────────────

  group('B. 复习会话「练道变式」', () {
    late Directory tmp;

    setUp(() {
      tmp = Directory.systemTemp.createTempSync('mono_variant');
      MistakeBook.debugFilePath = '${tmp.path}/mistakes.json';
      MistakeBook.debugTrashFilePath = '${tmp.path}/mistakes.trash.json';
      MistakeBook.instance.debugReset();
      // AI 通道隔离：空配置 ⇒ 绝不碰真实网络。
      AiChatStore.debugFilePath = '${tmp.path}/ai_chat_history.json';
      AiSettingsStore.debugConfig =
          const AiConfig(baseUrl: '', apiKey: '', model: '');
      AiChatController.instance.reset();
      ScanBankStore.debugFilePath = '${tmp.path}/scan_bank.json';
    });

    tearDown(() {
      MistakeBook.instance.debugFlushSave();
      MistakeBook.instance.debugResetAiOrganize();
      MistakeBook.instance.debugReset();
      MistakeBook.debugFilePath = null;
      MistakeBook.debugTrashFilePath = null;
      AiChatStore.debugFilePath = null;
      AiSettingsStore.debugConfig = null;
      AiChatController.instance.reset();
      ScanBankStore.debugFilePath = null;
      if (tmp.existsSync()) tmp.deleteSync(recursive: true);
    });

    /// 存一条 mono 错题（题干唯一），返回条目本体。
    MistakeEntry seedMono({String p1 = 'Aa', String p2 = 'Aa'}) {
      final n = ++_stemSeq;
      return MistakeBook.instance.add(
        stem: '变式种子题$n',
        userAnswer: '我答$n',
        correctAnswer: '正答$n',
        errorType: MistakeErrorType.calculation,
        subjectArea: kMonoCrossSubjectArea,
        srcModule: kMonoVariantSrcModule,
        srcParams: {'p1': p1, 'p2': p2},
      );
    }

    /// 存一条非 mono 错题（手加形态）。
    MistakeEntry seedPlain() {
      final n = ++_stemSeq;
      return MistakeBook.instance.add(
        stem: '普通错题$n',
        userAnswer: '我答$n',
        correctAnswer: '正答$n',
        errorType: MistakeErrorType.concept,
        subjectArea: '',
      );
    }

    Future<void> pumpPage(WidgetTester tester) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(const MaterialApp(home: MistakeBookPage()));
      await tester.pumpAndSettle();
    }

    Future<void> enterReview(WidgetTester tester) async {
      await tester.ensureVisible(find.text('开始复习'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('开始复习'));
      await tester.pumpAndSettle();
    }

    Future<void> revealOnly(WidgetTester tester) async {
      await tester.tap(find.textContaining('显示答案（1）'));
      await tester.pumpAndSettle();
    }

    Finder inDialog(Finder matching) =>
        find.descendant(of: find.byType(Dialog), matching: matching);

    /// 收尾：泵过 SnackBar 计时器 + 写盘 debounce，别留 pending timer。
    Future<void> settle(WidgetTester tester) async {
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
    }

    testWidgets('V5a：mono 错题揭示 ⇒ 「练道变式」在屏；点 ⇒ 入库 + 回执；再点不重复',
        (tester) async {
      final mono = seedMono(p1: 'Aa', p2: 'Aa');
      final expected = monoVariantOf(mono);
      expect(expected, isNotNull, reason: '前提：种子题能推出变式');

      await pumpPage(tester);
      await enterReview(tester);
      await revealOnly(tester);

      expect(inDialog(find.text(_kRevealVariantLabel)), findsOneWidget,
          reason: 'V5a：mono 错题揭示后必须有「练道变式」');

      final before = MistakeBook.instance.entries.length;
      final btn = inDialog(find.text(_kRevealVariantLabel));
      await tester.ensureVisible(btn);
      await tester.pumpAndSettle();
      await tester.tap(btn);
      await tester.pumpAndSettle();

      expect(find.text('变式已加入错题本，今晚复习见'), findsOneWidget,
          reason: 'V5a：点击必须有回执（⛔ 不许静默）');
      expect(MistakeBook.instance.entries.length, before + 1,
          reason: 'V5a：错题本恰好多一条变式');
      final stored =
          MistakeBook.instance.findSame(expected!.stem, expected.answer);
      expect(stored, isNotNull, reason: 'V5a：变式题干+答案真的进库了');
      expect(stored!.srcModule, kMonoVariantSrcModule,
          reason: 'V5a：变式记下来源，复习时可一键回计算器重算');
      expect(stored.srcParams, {'p1': expected.parent1, 'p2': expected.parent2},
          reason: 'V5a：来源参数照 mono 存题口径只记 p1/p2');

      // 第二次：先让上一条回执烧完，再点。
      await settle(tester);
      final again = inDialog(find.text(_kRevealVariantLabel));
      await tester.ensureVisible(again);
      await tester.pumpAndSettle();
      await tester.tap(again);
      await tester.pumpAndSettle();

      expect(find.text('这道变式已在错题本里'), findsOneWidget,
          reason: 'V5a：再点必须回执「已在」，⛔ 不重复入库');
      expect(MistakeBook.instance.entries.length, before + 1,
          reason: 'V5a：再点不得多出第二条');

      await settle(tester);
    });

    testWidgets('V5b：非 mono 错题揭示 ⇒ 不给「练道变式」', (tester) async {
      seedPlain();
      await pumpPage(tester);
      await enterReview(tester);
      await revealOnly(tester);

      expect(inDialog(find.text(_kRevealVariantLabel)), findsNothing,
          reason: 'V5b：非 mono 错题 ⇒ 按钮不渲染（一个像素都不加）');

      await settle(tester);
    });
  });
}

/// 最大公约数（与 `mono_variant.dart` 同款，仅测试侧复算用）。
int _gcd(int a, int b) {
  var x = a.abs();
  var y = b.abs();
  while (y != 0) {
    final t = y;
    y = x % y;
    x = t;
  }
  return x;
}
