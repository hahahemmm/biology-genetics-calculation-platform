// ════════════════════════════════════════════════════════════════════════
//  test/pages/mistake_book_curriculum_badge_test.dart
//  「这道题考哪条课标」+「回来源工具重算」——错题本侧的闭环守卫。
// ════════════════════════════════════════════════════════════════════════
//
//  ## 本文件补的是哪一跳
//
//  移植前本仓三处全为零：
//  · 数据层没有 srcModule / srcParams ⇒ 复习时「回不到那道题」；
//  · 复习会话与列表卡片都没有「去那一页重算」按钮；
//  · `curriculum_page.dart` 连反向锚点表都没有 ⇒ 错题本与课标零连接。
//
//  ## ⛔ 本文件最重的一条是第 4 条（多义 moduleId 不给徽章）
//
//  那是**口径命脉**：「宁可不给，也不给错」。`molecular` 一枚 moduleId 对
//  本仓 **五条** code（3.1.1 / 3.1.2 / 3.1.3 / 3.1.4 / 3.2.1），而错题本
//  **不记页签** ⇒ 替学生挑一条 = 凭空编造对应关系，且编出来的东西**屏上完全
//  看不出来**（徽章照样可点、照样跳得过去，只是落到了另一条正文上）。
//  ⇒ `findsNothing` 写成 `findsAtLeastNWidgets` 就等于把这轮的口径拆了。
//
//  ## 第 3 条为什么要「真点」而不是只断「有徽章」
//
//  「看得见却点不动」是本仓反复出现的症状（`findsOneWidget` 全绿、手感却
//  是死的）。所以断两层：`hitTestable()` 命中（被 `AbsorbPointer` 吞掉或被
//  别的层盖住都会红），点下去**真的** push 出课标页并高亮那一条（断
//  「正在查看」+ 条目 key，⛔ 不只断「有 SnackBar」）。
//
//  ## ⛔ 已知副作用：多条错题的徽章文案会重复
//
//  列表里**多条**错题各自显示各自的徽章时，文本会重复（例如两条都来自
//  9331 ⇒ 两条都是「课标 3.2.3」）⇒ 既有测试里任何 `findsOneWidget` 断言
//  可能因此变红。第 8 条把这个副作用**如实钉住**，而不是去改既有断言。
//
//  ## 视口 / 隔离
//
//  · 800×1200 @1.0；第 7 条在 **360×800** 下量一次。
//  · `MistakeBook.debugFilePath` / `FirstRunStore.debugFilePath` 隔离到
//    `Directory.systemTemp` 下的独立临时目录。
//  · 定长 pump，不用 pumpAndSettle：错题本有 500ms 写盘 debounce 与常驻
//    动画，`pumpAndSettle` 会超时。路由 push 是 300ms 过渡，泵到 400ms 足够。

import 'dart:io';

import 'package:biology/data/curriculum_2020.dart';
import 'package:biology/pages/curriculum_page.dart';
import 'package:biology/pages/genetic_disease_page.dart';
import 'package:biology/pages/mistake_book_page.dart';
import 'package:biology/state/first_run_store.dart';
import 'package:biology/state/mistake_book.dart';
import 'package:biology/ui/module_fill.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 唯一命中的 moduleId：锚点表里 `cross_mono` → `3.2.3` **只出现一次**
/// （3.2.3 那三枚锚点各是不同 moduleId）⇒ 反查必然有唯一 code。
const _kUniqueModule = 'cross_mono';

/// **多义**的 moduleId：`molecular` 对应本仓 3.1.1 / 3.1.2 / 3.1.3 /
/// 3.1.4 / 3.2.1 **五条** code ⇒ 依「宁可不给，也不给错」口径**不登记**
/// ⇒ `curriculumReverseCodeOf` 返回 null ⇒ 一个徽章都不给。
const _kAmbiguousModule = 'molecular';

/// 期望的徽章文案（= 锚点表里 3.2.3 那三枚的 `badgeLabel`，逐字相同）。
const _kBadgeText = '课标 3.2.3';

/// 课标页里被高亮那一条的 key（`curriculum_page.dart` 的
/// `ValueKey('curriculum-item-<code>')`，只在 focused 时挂）。
const _kItemTileKey = ValueKey('curriculum-item-3.2.3');

/// 课标页给焦点条目的语言线索。
const _kFocusMarker = '正在查看';

/// 列表卡片那枚重算按钮的 key，与 lib 侧 `kListRefillButtonKey` 同一字面量。
const _kListBtn = Key('mistake_list_refill_btn');

/// 复习会话那枚按钮的 key，与 lib 侧 `kReviewRefillButtonKey` 同一字面量。
const _kReviewBtn = Key('mistake_review_refill_btn');

void main() {
  late Directory tmp;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('mistake_curr_badge');
    MistakeBook.debugFilePath = '${tmp.path}/mistakes.json';
    MistakeBook.debugTrashFilePath = '${tmp.path}/mistakes.trash.json';
    MistakeBook.instance.debugReset();
    FirstRunStore.debugFilePath = '${tmp.path}/first_run.json';
    FirstRunStore.debugWebStorage = null;
    FirstRunStore.debugForceIsWebStorage = false;
    FirstRunStore.instance.debugReset();
    ModuleFillBus.resetForTest();
  });

  tearDown(() {
    MistakeBook.instance.debugFlushSave();
    MistakeBook.instance.debugResetAiOrganize();
    MistakeBook.instance.debugReset();
    MistakeBook.debugFilePath = null;
    MistakeBook.debugTrashFilePath = null;
    FirstRunStore.debugFilePath = null;
    FirstRunStore.debugWebStorage = null;
    FirstRunStore.debugForceIsWebStorage = false;
    FirstRunStore.instance.debugReset();
    ModuleFillBus.resetForTest();
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  /// 造一条错题。`srcModule` 传 null 即「老条目」（不写 srcParams）。
  ///
  /// ⚠️ `srcParams` 一律给非空值：`mistakeEntryHasSource` 要求
  /// `srcModule != null && srcParams` 非空，那一行才渲染。徽章住在**那一行
  /// 里**⇒ srcParams 空的话徽章根本轮不到渲染，第 4/5 条就会退化成
  /// 「整行不存在」而不是「行在、徽章不给」。
  void seed({
    required String? srcModule,
    String stem = '9331 单基因：Aa × Aa 的子代比例',
    Map<String, String>? srcParams,
  }) {
    MistakeBook.instance.addOrFind(
      stem: stem,
      userAnswer: '1:2:1',
      correctAnswer: '3:1',
      errorType: MistakeErrorType.other,
      subjectArea: '遗传 · 9331',
      srcModule: srcModule,
      srcParams: srcParams ?? const {'p1': 'Aa', 'p2': 'Aa'},
    );
    MistakeBook.instance.debugFlushSave();
  }

  /// 注册一个可写的假 target（列表那枚按钮与复习会话那枚都要它）。
  void registerTarget({
    required void Function(Map<String, String> params) onApply,
    required void Function(int pageIndex) onNavigate,
    String moduleId = _kUniqueModule,
  }) {
    ModuleFillBus.navigator = onNavigate;
    ModuleFillBus.register(ModuleFillTarget(
      moduleId: moduleId,
      pageIndex: 1,
      label: '单基因遗传（9331）',
      apply: (params) {
        onApply(params);
        return true;
      },
      canOverwrite: () => true,
    ));
  }

  /// 起错题本（只起页面，不进复习会话）。
  Future<void> pumpList(WidgetTester tester,
      {Size size = const Size(800, 1200)}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const MaterialApp(home: MistakeBookPage()));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  /// 点一枚徽章后把路由过渡泵完（MaterialPageRoute = 300ms）。
  Future<void> pumpRoute(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));
  }

  /// 收尾：泵过写盘 debounce，不留 pending timer。
  Future<void> settle(WidgetTester tester) async {
    await tester.pump(const Duration(milliseconds: 600));
  }

  // ══════════════════════════════════════════════════════════════════
  //  A. 锚点表自身的数据守卫（纯函数，先于一切 UI）
  // ══════════════════════════════════════════════════════════════════

  test('A1 表里每枚锚点的 code 都真实存在于 curriculum2020', () {
    for (final a in curriculumReverseAnchors) {
      expect(curriculum2020.any((i) => i.code == a.code), isTrue,
          reason: '锚点指向不存在的课标条目 ${a.code}（moduleId '
              '${a.moduleId}）⇒ 徽章会跳到一个空分区');
      expect(a.badgeLabel, '课标 ${a.code}',
          reason: '徽章文案口径固定为「课标 X」，实测：${a.badgeLabel}');
    }
  });

  test('A2 ⛔ 表里没有任何多义 moduleId（唯一命中口径的表侧保证）', () {
    final seen = <String, int>{};
    for (final a in curriculumReverseAnchors) {
      seen[a.moduleId] = (seen[a.moduleId] ?? 0) + 1;
    }
    final dup = seen.entries.where((e) => e.value > 1).map((e) => e.key);
    expect(dup, isEmpty,
        reason: '⛔ 同一 moduleId 登记了多条 code ⇒ 反查必然多义。'
            '要么把多义的那些**整条删掉**（本仓口径：多义不登记，'
            'curriculumReverseCodeOf 自然返 null），不许留着一行当'
            '"反查返 null"的道具。实测多义：$dup');
  });

  test('A3 唯一命中的 moduleId ⇒ 反查得到那条 code', () {
    expect(curriculumReverseCodeOf('cross_mono'), '3.2.3');
    expect(curriculumReverseCodeOf('cross_dihybrid'), '3.2.3');
    expect(curriculumReverseCodeOf('cross_trihybrid'), '3.2.3');
    expect(curriculumReverseCodeOf('cross_sex_linked'), '3.2.4');
    expect(curriculumReverseCodeOf('cross_linkage'), '3.3.4');
    expect(curriculumReverseCodeOf('disease_risk'), '3.3.6');
  });

  test('A4 ⛔ 多义 / 未被任何课标点名的 moduleId ⇒ 返 null', () {
    // 分子页：五条课标都点名它（3.1.1/3.1.2/3.1.3/3.1.4/3.2.1）⇒ 不登记。
    expect(curriculumReverseCodeOf(_kAmbiguousModule), isNull);
    // 进化页：七条（4.1.1/4.1.2/4.2.1~4.2.5）。
    expect(curriculumReverseCodeOf('evolution'), isNull);
    // 变异页：四条（3.3.1/3.3.2/3.3.3/3.3.5）。
    expect(curriculumReverseCodeOf('cross_chromosomal_struct'), isNull);
    // 遗传图谱页：3.2.2 与 3.2.3 都点名它。
    expect(curriculumReverseCodeOf('pedigree'), isNull);
    // 本仓没有任何一条课标点名它们。
    expect(curriculumReverseCodeOf('ploidy'), isNull);
    expect(curriculumReverseCodeOf('cross_method_compare'), isNull);
    expect(curriculumReverseCodeOf('cross_random_mating'), isNull);
    expect(curriculumReverseCodeOf('pd_inference'), isNull);
    expect(curriculumReverseCodeOf('压根没注册过的'), isNull);
  });

  test('A5 reverseAnchorOf：同一 code 多枚锚点取第一枚（取哪枚都一样）', () {
    final a = reverseAnchorOf('3.2.3');
    expect(a, isNotNull);
    expect(a!.code, '3.2.3');
    expect(a.badgeLabel, '课标 3.2.3');
    expect(reverseAnchorOf('不存在的 code'), isNull);
  });

  // ══════════════════════════════════════════════════════════════════
  //  1. 唯一命中的条目：列表卡片上出现可点的「课标 3.2.3」徽章
  // ══════════════════════════════════════════════════════════════════

  testWidgets('1：srcModule 唯一命中（cross_mono）⇒ 显示可点的「课标 3.2.3」徽章',
      (tester) async {
    registerTarget(onApply: (_) {}, onNavigate: (_) {});
    seed(srcModule: _kUniqueModule);
    await pumpList(tester);

    // ── 前提（硬断言，⛔ 不许「找不到就跳过」）──
    // 先把「那一行确实在树上」钉住：徽章住在重算按钮**那一行**里，
    // 行没渲染的话下面任何 findsNothing 都可能是「行没了」而非「不给徽章」。
    final listBtn = find.byKey(_kListBtn);
    expect(listBtn, findsOneWidget,
        reason: '前提：带来源的条目，列表卡片上必须渲染重算按钮那一行');

    // 徽章**存在**。⛔ 不用 findsOneWidget：多张卡片时文案会重复（第 8 条）。
    final badge = find.text(_kBadgeText);
    expect(badge, findsWidgets,
        reason: '唯一命中的条目必须显示「$_kBadgeText」徽章');

    // 徽章与重算按钮在**同一行**（同一个 Wrap），不是另起一行/另一个区块。
    // ⛔ 必须取**最内层**那个 Wrap 祖先（`.first`）：屏上别的层（卡片自己的
    // 结构）也可能是 Wrap，只断「有某个 Wrap 祖先」的话，徽章被塞进
    // `_buildActions` 或另起一个 Align 都会照样变绿。
    final rowWrap = find
        .ancestor(of: badge.first, matching: find.byType(Wrap))
        .first;
    expect(
      find.descendant(of: rowWrap, matching: find.byKey(_kListBtn)),
      findsOneWidget,
      reason: '徽章与重算按钮必须在**同一个** Wrap 里（同一行 = 两件'
          '「接下来做什么」并排）',
    );

    // 徽章本体是可点实现（InkWell），不是自造的静态 chip。
    // ⛔ 取**最内层**那个 InkWell 祖先：整张卡片自己就裹在一个大 InkWell 里，
    // 断「有 InkWell 祖先」对静态 chip 也会变绿。这里断的是「徽章**自己**
    // 那层 InkWell 就住在这一行里」。
    final badgeInk = find
        .ancestor(of: badge.first, matching: find.byType(InkWell))
        .first;
    expect(
      find.descendant(of: rowWrap, matching: badgeInk),
      findsOneWidget,
      reason: '徽章必须裹在**它自己那层** InkWell 里才有 onTap'
          '（复用 curriculumReverseBadge，不是静态 chip）',
    );

    // 「看得见却点不动」的典型症状：被 AbsorbPointer 吞掉 / 被别的层盖住。
    expect(badge.first.hitTestable(), findsOneWidget,
        reason: '徽章必须真的点得动');

    await settle(tester);
  });

  // ══════════════════════════════════════════════════════════════════
  //  2. 真点得动：点下去真的跳到课标页并高亮那一条
  // ══════════════════════════════════════════════════════════════════

  testWidgets('2：点徽章**真的**跳到课标页并高亮那一条（不只断「有 SnackBar」）',
      (tester) async {
    registerTarget(onApply: (_) {}, onNavigate: (_) {});
    seed(srcModule: _kUniqueModule);
    await pumpList(tester);

    final badge = find.text(_kBadgeText);
    // ⛔ 前提排在牙齿**后面**：先把「它可点」钉住，再点。
    expect(badge, findsWidgets, reason: '前提：徽章在');
    expect(badge.first.hitTestable(), findsOneWidget,
        reason: '前提：徽章点得动（否则后面 tap 会假红）');

    await tester.tap(badge.first);
    await pumpRoute(tester);

    // ① 真的 push 出了一份**带 focusCode 的**课标页。
    final pages = find.byType(CurriculumPage);
    expect(pages, findsOneWidget, reason: '点徽章必须 push 出课标页');
    final page = tester.widget<CurriculumPage>(pages);
    expect(page.focusCode, '3.2.3',
        reason: '高亮哪一条由 focusCode 决定；徽章拿的是锚点的 code');

    // ② ⛔ 真的**高亮**了：不是「有个页面」，是那一条被标了出来。
    expect(find.text(_kFocusMarker), findsOneWidget,
        reason: '课标页必须给焦点条目语言线索「$_kFocusMarker」'
            '（全页只应有一个焦点标记）');
    expect(find.byKey(_kItemTileKey), findsOneWidget,
        reason: '被高亮的必须正是 3.2.3 **那一条**条目，'
            '不是落在同一分区里的另一条正文上');

    await settle(tester);
  });

  // ══════════════════════════════════════════════════════════════════
  //  2b. ⛔ 不带 focusCode 打开课标页 ⇒ 零高亮（既有入口全都不许被影响）
  // ══════════════════════════════════════════════════════════════════

  testWidgets('2b：focusCode 为 null 的课标页 ⇒ 不描边、不标「正在查看」',
      (tester) async {
    // 主导航里那一份就是这个形状（`CurriculumPage(onOpenTool: …)`）。
    await tester.pumpWidget(const MaterialApp(home: CurriculumPage()));
    await tester.pump();

    expect(find.text(_kFocusMarker), findsNothing,
        reason: '⛔ focusCode=null 时不许出现任何焦点标记（既有屏零像素变化）');
    expect(find.byKey(_kItemTileKey), findsNothing,
        reason: '⛔ focusCode=null 时不许给任何条目挂高亮 key');
  });

  // ══════════════════════════════════════════════════════════════════
  //  3. ⛔ 多义命中 ⇒ 不给徽章（本能力的口径命脉）
  // ══════════════════════════════════════════════════════════════════

  testWidgets('3：⛔ srcModule 多义（molecular 对五条 code）⇒ 一个徽章都不给',
      (tester) async {
    registerTarget(
        onApply: (_) {}, onNavigate: (_) {}, moduleId: _kAmbiguousModule);
    seed(srcModule: _kAmbiguousModule);
    await pumpList(tester);

    // ── 前提（硬断言，排在牙齿后面）：那**一行确实在树上** ──
    // ⛔ 这条前提是本用例的全部意义所在：若行都不在，「没有徽章」就
    // 证明不了「多义不给」——它可能只是「整行没渲染」。
    expect(find.byKey(_kListBtn), findsOneWidget,
        reason: '前提：molecular 是带来源的条目，那一行必须在；'
            '否则下面的 findsNothing 证明不了「多义不给」');

    // ── 牙齿 ──
    expect(find.text(_kBadgeText), findsNothing,
        reason: '⛔ 多义命中必须**一个徽章都不给**（宁可不给，也不给错）：'
            'molecular 一枚 moduleId 对 3.1.1/3.1.2/3.1.3/3.1.4/3.2.1 五条 '
            'code，错题本不记页签，替学生挑一条 = 编造对应关系');
    // 任何一张课标徽章都不许出现（不只是「课标 3.2.3」这一种文案）。
    expect(find.textContaining('课标'), findsNothing,
        reason: '⛔ 多义命中时**任何**课标徽章都不许给，'
            '不许换个文案绕开「宁可不给」的口径');

    await settle(tester);
  });

  // ══════════════════════════════════════════════════════════════════
  //  4. 老条目（srcModule == null）⇒ 不给徽章
  // ══════════════════════════════════════════════════════════════════

  testWidgets('4：老条目（srcModule == null）⇒ 不给徽章', (tester) async {
    registerTarget(onApply: (_) {}, onNavigate: (_) {});
    seed(srcModule: null, stem: '9331 单基因（老条目，无来源）');
    await pumpList(tester);

    // 前提：老条目连重算按钮那一行都不该有。
    expect(find.byKey(_kListBtn), findsNothing,
        reason: '前提：老条目没有来源，那一行不该渲染');
    expect(find.textContaining('课标'), findsNothing,
        reason: '老条目不知道考哪条课标（srcModule 都没有）⇒ 不给徽章');

    await settle(tester);
  });

  // ══════════════════════════════════════════════════════════════════
  //  5. 复习会话里那枚「去「X」重算这道题」仍然在、仍然能用
  // ══════════════════════════════════════════════════════════════════

  testWidgets('5：复习会话里那枚「去「X」重算这道题」仍然在、仍然能用',
      (tester) async {
    final applied = <Map<String, String>>[];
    registerTarget(onApply: applied.add, onNavigate: (_) {});
    seed(srcModule: _kUniqueModule);
    await pumpList(tester);

    // 进复习会话（列表仍留在树里，非 offstage）。
    await tester.ensureVisible(find.text('开始复习'));
    await tester.pump();
    await tester.tap(find.text('开始复习'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    // 前提先钉住：会话那枚按钮存在且可点。
    final reviewBtn = find.byKey(_kReviewBtn);
    expect(reviewBtn, findsOneWidget, reason: '前提：复习会话那枚按钮在');
    expect(reviewBtn.hitTestable(), findsOneWidget,
        reason: '前提：复习会话那枚按钮点得动');

    // ⛔ 与列表那枚**不同 key** 是硬要求：对话框盖在列表之上而列表卡片
    // 仍在树里，共用一个 key 会让两处互相命中。
    expect(find.byKey(_kListBtn), findsOneWidget,
        reason: '列表那枚仍在树里（对话框是盖上来的）⇒ 两个 key 必须分开');

    await tester.tap(reviewBtn);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    // 「仍然能用」= 真的把参数送进了目标页的 apply。
    expect(applied.length, 1,
        reason: '复习会话那枚必须真的生效（实测 apply 次数：${applied.length}）');
    expect(applied.single, {'p1': 'Aa', 'p2': 'Aa'},
        reason: '送进去的必须是这道题当初的 srcParams');

    await settle(tester);
  });

  // ══════════════════════════════════════════════════════════════════
  //  6. 三结局：填不进去必须自己说话（⛔ 禁止静默）
  // ══════════════════════════════════════════════════════════════════

  testWidgets('6：fill 返 false（模块没注册）⇒ 本条必须自己说一句话',
      (tester) async {
    // 前提：这一条 srcModule 是 '压根没注册过的'，targetOf 返 null ⇒
    // fill 返 false（结局 ③）。
    seed(srcModule: '压根没注册过的');
    await pumpList(tester);
    expect(find.byKey(_kListBtn), findsOneWidget, reason: '前提：按钮在');

    await tester.tap(find.byKey(_kListBtn));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.textContaining('过不去'), findsOneWidget,
        reason: '⛔ 结局 ③ 必须自己说一句（静默 = 学生对着不动的一页发呆）；'
            '文案要点名那一页，并说明题目不会丢');

    await settle(tester);
  });

  // ══════════════════════════════════════════════════════════════════
  //  6b. 三结局的另外两结局（② 挡下 ⇒ 本条一字不说 / ① 真写入 ⇒ 退栈+回执）
  // ══════════════════════════════════════════════════════════════════

  /// 起一份**带路由栈**的宿主：首页 → push 错题本。
  ///
  /// ⚠️ 结局 ① 要断 `popUntil((r) => r.isFirst)`，那要求错题本是**被 push
  /// 出来的一层**（本仓真实形态：首页卡片 push 打开，不在主导航
  /// IndexedStack 里）。直接 `home: MistakeBookPage()` 的话它是**唯一**
  /// 一层路由，`popUntil` 只会把栈退空——断言就变成假的。
  Future<void> pumpStacked(WidgetTester tester) async {
    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
      home: Builder(builder: (ctx) => Scaffold(
        body: Center(
          child: TextButton(
            onPressed: () => Navigator.of(ctx).push(
              MaterialPageRoute<void>(builder: (_) => const MistakeBookPage()),
            ),
            child: const Text('去错题本'),
          ),
        ),
      )),
    ));
    await tester.pump();
    await tester.tap(find.text('去错题本'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  testWidgets('6b-①：真写进去 ⇒ 退栈回首页 + 给成功回执', (tester) async {
    registerTarget(onApply: (_) {}, onNavigate: (_) {});
    seed(srcModule: _kUniqueModule);
    await pumpStacked(tester);
    expect(find.byKey(_kListBtn), findsOneWidget, reason: '前提：按钮在');

    await tester.tap(find.byKey(_kListBtn));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));

    // ① 路由真的退到首页了：否则学生点了仍盯在错题本上，看起来就是
    //    「点了没反应」（`fill` 只切主导航索引，不会自己 pop 掉错题本）。
    expect(find.byType(MistakeBookPage), findsNothing,
        reason: '⛔ 结局 ① 必须退栈（popUntil isFirst）');
    expect(find.text('去错题本'), findsOneWidget,
        reason: '退栈后应落在首页那一层');

    // ② 回执挂在 MaterialApp 根 messenger 上 ⇒ 退栈之后仍然有人接。
    expect(find.textContaining('已退出本轮复习'), findsOneWidget,
        reason: '结局 ① 必须给成功回执（说明进度已保存 + 切到了哪一页）');
    expect(find.textContaining('单基因遗传（9331）'), findsWidgets,
        reason: '回执要点名来源页（禁方向词、禁 markdown 星号）');

    await settle(tester);
  });

  testWidgets('6b-②：被 canOverwrite 挡下 ⇒ 本条一个字都不说', (tester) async {
    // 目标页「现在不空」（学生自己敲过题）——此时总线的 onApplyFailed 会
    // 由**目标页**负责提示，本条重复说就是双重提示。
    ModuleFillBus.navigator = (_) {};
    ModuleFillBus.register(ModuleFillTarget(
      moduleId: _kUniqueModule,
      pageIndex: 1,
      label: '单基因遗传（9331）',
      apply: (_) => true,
      canOverwrite: () => false,
    ));
    seed(srcModule: _kUniqueModule);
    await pumpStacked(tester);
    expect(find.byKey(_kListBtn), findsOneWidget, reason: '前提：按钮在');

    await tester.tap(find.byKey(_kListBtn));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.textContaining('已退出本轮复习'), findsNothing,
        reason: '⛔ 结局 ② 本条必须**静默**（目标页自己会说，两处都说是双重提示）');
    expect(find.textContaining('过不去'), findsNothing,
        reason: '⛔ 结局 ② 不是「过不去」，不许混用结局 ③ 的文案');

    await settle(tester);
  });

  // ══════════════════════════════════════════════════════════════════
  //  7. 360 宽：零 RenderFlex 溢流，且徽章与重算按钮**都还在屏内**
  // ══════════════════════════════════════════════════════════════════

  testWidgets('7：360 宽下零溢流，徽章与重算按钮都还在屏内', (tester) async {
    registerTarget(onApply: (_) {}, onNavigate: (_) {});
    seed(srcModule: _kUniqueModule);
    await pumpList(tester, size: const Size(360, 800));

    // 前提：两者都在树上。
    final listBtn = find.byKey(_kListBtn);
    final badge = find.text(_kBadgeText);
    expect(listBtn, findsOneWidget, reason: '前提：重算按钮在');
    expect(badge, findsWidgets, reason: '前提：徽章在');

    // 实测宽度（报告用）。卡片可用宽 = 360 − 左右各 14 内边距 = 332。
    final btnW = tester.getSize(listBtn).width;
    final badgeW = tester.getSize(badge.first).width;
    // ignore: avoid_print
    print('[360 实测] 重算按钮宽 $btnW · 徽章宽 $badgeW · 合计 ${btnW + badgeW}'
        ' · 可用 332 · Wrap 间距 8 ⇒ 需 ${btnW + badgeW + 8}');

    // 判据①：**零溢流**。⛔ 不退化成「别新增溢流」——本仓 `_buildActions`
    // 已按窄屏折行收口，360 下两个分支都该是零溢流。
    expect(tester.takeException(), isNull,
        reason: '360 宽下整个错题本列表**零 RenderFlex 溢流**'
            '（徽章行已换 Wrap，重算按钮 + 徽章会折行而不是挤爆）');

    // 判据②：两者**都还在屏内**（徽章被折到第二行也算在屏内）。
    for (final (label, finder) in <(String, Finder)>[
      ('重算按钮', listBtn),
      ('课标徽章', badge.first),
    ]) {
      final r = tester.getRect(finder);
      expect(r.left, greaterThanOrEqualTo(-0.5),
          reason: '$label 左缘不得在屏外（实测 ${r.left}）');
      expect(r.right, lessThanOrEqualTo(360.5),
          reason: '$label 右缘不得越屏（实测 ${r.right}）');
    }

    await settle(tester);
  });

  // ══════════════════════════════════════════════════════════════════
  //  8. 多条错题各自显示各自的徽章（⚠️ 文案会重复，故此处只用 findsWidgets）
  // ══════════════════════════════════════════════════════════════════

  testWidgets('8：多条都来自 9331 的错题 ⇒ 各自都显示徽章（文案因此重复）',
      (tester) async {
    registerTarget(onApply: (_) {}, onNavigate: (_) {});
    seed(srcModule: _kUniqueModule, stem: '第 1 条：9331 单基因');
    seed(srcModule: _kUniqueModule, stem: '第 2 条：9331 单基因');
    await pumpList(tester);

    expect(find.byKey(_kListBtn), findsNWidgets(2),
        reason: '前提：两条错题 ⇒ 两行重算按钮');
    // ⛔ 这里**故意**用 findsNWidgets(2) 而不是 findsOneWidget：那正是本轮
    // 已知的副作用（两条都来自 9331 ⇒ 两条都是「课标 3.2.3」），必须显式
    // 钉住它存在，而不是让既有测试的红掩盖掉它。
    expect(find.text(_kBadgeText), findsNWidgets(2),
        reason: '两条各自显示各自的徽章 ⇒ 文案重复是**预期**结果');

    await settle(tester);
  });

  // ══════════════════════════════════════════════════════════════════
  //  9. 回得去 · push 型目标（v2.19.37 独立验证者 P0 回归）：
  //     先退错题本层再 push —— 目标页留栈顶 + pending/标签零幽灵。
  //     （旧顺序「fill 后 popUntil」会把刚 push 的页一起弹掉：
  //     深链失效 + 下次拍题横幅误说「来自课标」。）
  // ══════════════════════════════════════════════════════════════════

  testWidgets('9：disease_risk（push 型）回得去 ⇒ 错题本退栈、遗传病页留栈顶、'
      '示范题真写入、pending 已消费', (tester) async {
    seed(
      srcModule: 'disease_risk',
      stem: '伴X隐：XaY × XAXa 的子女患病风险',
      srcParams: const {'father': 'XaY', 'mother': 'XAXa', 'mode': 'rec'},
    );
    // 复刻 main.dart 的 App 级注册（push 型 + sourceLabel 从总线取）。
    ModuleFillBus.register(ModuleFillTarget(
      moduleId: 'disease_risk',
      pageIndex: -1,
      label: '遗传病页·风险计算',
      apply: (_) => false,
      pushFactory: (_) => GeneticDiseasePage(
          sourceLabel: ModuleFillBus.consumePushSourceLabel('disease_risk') ??
              '拍题识别'),
    ));
    // 生产形态：错题本是从首页卡片 push 的一层路由（popUntil(isFirst) 退的
    // 就是它）；若直接当 home 泵，popUntil 无栈可退，测不到真路径。
    // 视口同 pumpList（800×1200）：默认 600 高下条目懒构建，finder 找不到。
    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester
        .pumpWidget(const MaterialApp(home: Scaffold(body: SizedBox())));
    final ctx = tester.element(find.byType(Scaffold));
    await tester.pump(const Duration(milliseconds: 400));
    Navigator.of(ctx)
        .push(MaterialPageRoute(builder: (_) => MistakeBookPage()));
    // push 过渡 300ms + 页内 500ms 加载/debounce：单泵 400ms 不够（探针实测），
    // 三档 400ms 与 pumpRoute 同款节奏。
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));

    // pusher：fill 的 push 路由在测试里显式接管（生产走 HomeShell 注入；
    // 不设则 appCanvasKey 兜底失败、清掉入队——测不到真路径）。
    ModuleFillBus.pusher = (WidgetBuilder b) {
      Navigator.of(ctx).push(MaterialPageRoute(builder: b));
    };
    // 直接驱动 onPressed：跳过命中测试（mono 流的 hitTestable 由第 3 条
    // 钉住；本例只验 push 型回程的路由顺序与消费链路）。
    tester.widget<OutlinedButton>(find.byKey(_kListBtn)).onPressed!();
    // 退栈 300ms + push 过渡 300ms + initState 消费 postFrame：泵足三档。
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byType(MistakeBookPage), findsNothing,
        reason: '错题本层必须先退掉（留在栈上即红）');
    expect(find.textContaining('XaY'), findsWidgets,
        reason: 'push 出的遗传病页留在栈顶且 initState 真消费了 pending');
    expect(ModuleFillBus.consumePending('disease_risk'), isNull,
        reason: '⛔ 幽灵 params：被弹页面从未构建才会留下——回归即红');
    expect(ModuleFillBus.consumePushSourceLabel('disease_risk'), isNull,
        reason: '⛔ 幽灵来源标签：下次拍题横幅误说「来自课标」的源头');
  });
}
