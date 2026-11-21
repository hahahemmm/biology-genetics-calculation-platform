// big_question_cards_test.dart —— v2.19.24 建立 / v2.19.25 甄别扩充
//                            / v2.20.0 单栏导航改造
//
// ① 数据完整性：14 张卡信号/步骤/易错/口诀齐全、id 唯一、
//   深链（linkModuleId/linkNavIndex）合法（纯数据测试，不泵 UI）。
// ② 交互：选择条点选切章切卡、章内翻卡（含环绕）、搜索反查与点击直达、
//   已背标记 + 「只看未背」过滤、错题本回链初始定位、关联工具回调
//   （深链未注册时回退 onOpenTool）。
// ③ 布局：宽屏 6 章逐章点选零溢出 + **单栏导航守卫**（无 ToolWorkbench
//   第二列、无章节 TabBar、只有一套 SideNavWorkbench）、390 窄屏零溢出、
//   课堂模式 ×1.3 逐章逐卡零溢出。
//
// v2.20.0（用户裁定：全局导航永远单栏可滚动）：页面结构从「AppBar 章节
// TabBar + 宽屏 280px 左目录」换成「一套 SideNavWorkbench 顶部横向选择条
// + 右区正文」。⇒ 原「点章节页签 / 点左栏目录项」的旧断言全部改为点 pill；
// ⛔ 功能覆盖一条没删（换章、章内翻卡、跨章直达、已背 ✓、只看未背、
// 搜索、回链、Alt+L 都不动）。

import 'package:biology/data/big_question_cards.dart';
import 'package:biology/pages/big_question_cards_page.dart';
import 'package:biology/pages/widgets/side_nav_workbench.dart';
import 'package:biology/pages/widgets/tool_workbench.dart';
import 'package:biology/state/big_question_cards_store.dart';
import 'package:biology/theme.dart';
import 'package:biology/ui/module_fill.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 顶部选择条里那枚 pill。
///
/// 用 [find.textContaining] 而不是 `find.text`：已背卡片的 pill 文案带
/// `✓ ` 前缀（骨架没有 subtitle 位，已背标记走文本前缀）。`.first` 取到
/// 的必然是 pill 而不是正文标题 —— 横条在正文**之前**构建。
Finder _pill(String cardTitle) => find.textContaining(cardTitle).first;

/// 点一枚 pill（横滚条：视口外的条目先滚进来再点）。
Future<void> _tapPill(WidgetTester tester, String cardTitle) async {
  final f = _pill(cardTitle);
  await tester.ensureVisible(f);
  await tester.pump();
  await tester.tap(f);
  await tester.pumpAndSettle();
}

void main() {
  group('数据完整性', () {
    test('6 章 14 张卡，id 唯一，字段齐全', () {
      expect(bigQuestionChapters.length, 6);
      final ids = <String>{};
      var total = 0;
      for (final ch in bigQuestionChapters) {
        expect(ch.cards, isNotEmpty, reason: '${ch.title} 至少一张卡');
        for (final card in ch.cards) {
          total++;
          expect(ids.add(card.id), isTrue, reason: 'id 重复: ${card.id}');
          expect(card.title, isNotEmpty);
          expect(card.tag, isNotEmpty);
          expect(card.signals, isNotEmpty,
              reason: '${card.id} 应有识别信号');
          expect(card.steps.length, greaterThanOrEqualTo(2),
              reason: '${card.id} 至少两步套路');
          expect(card.pitfalls, isNotEmpty, reason: '${card.id} 应有易错');
          expect(card.takeaway, isNotEmpty, reason: '${card.id} 应有口诀');
          // linkLabel / linkNavIndex 同设或同空。
          expect(card.linkLabel != null, card.linkNavIndex != null,
              reason: '${card.id} 关联工具两项需同设或同空');
          if (card.linkNavIndex != null) {
            expect(card.linkNavIndex!, inInclusiveRange(0, 10),
                reason: '${card.id} 跳转索引须在主导航范围内');
          }
          // v2.19.25：深链 moduleId 若设，回退索引必须也在（失败兜底）。
          if (card.linkModuleId != null) {
            expect(card.linkNavIndex, isNotNull,
                reason: '${card.id} 深链需带回退导航索引');
          }
        }
      }
      expect(total, 14);
    });

    test('P0 回归：15N 标记例题口径 = 1/4（教材选择题正确项 C）', () {
      final card = bigQuestionChapters
          .expand((c) => c.cards)
          .firstWhere((c) => c.id == 'biaoji-shidai');
      final all = card.steps.join('\n');
      expect(all, contains('占 1/4（正确答案 C）'));
      expect(all, isNot(contains('（p65）')),
          reason: '旧版把选择题干扰项 1/8 当结论抄写，必须清除');
      // pitfall 里允许引用 1/8 作为陷阱说明（措辞为「2/2ⁿ⁺¹」口径）。
      expect(card.pitfalls.join('\n'), contains('2ⁿ⁺¹'));
    });

    test('反推卡存在且深链为双测交例题（v2.19.25 新增卡）', () {
      final pos = findCardIndexById('fan-tui-qinben');
      expect(pos, isNotNull);
      final card = bigQuestionChapters[pos!.$1].cards[pos.$2];
      expect(card.linkModuleId, 'cross_dihybrid');
      expect(card.linkParams?['p2'], 'aabb');
    });

    test('错题回链关键词映射：手输风格 + 应用自产常量 + 全角归一 + 无命中',
        () {
      // 手输风格。
      expect(findCardIdForTopic('系谱图推断'), 'xipu-koujue');
      expect(findCardIdForTopic('9331 变式'), 'b9331-bianshi');
      // v2.19.26（学生 P1-1 / 老师 P1-3 / 老用户 ③ 交叉）：App 自产
      // 考点常量（各计算器「存入错题本」写入的 subjectArea 全集）。
      expect(findCardIdForTopic('分离定律'), 'fan-tui-qinben');
      expect(findCardIdForTopic('自由组合定律'), 'b9331-bianshi');
      expect(findCardIdForTopic('伴性遗传'), 'banxing-buzhou');
      expect(findCardIdForTopic('人类遗传病'), 'xipu-koujue');
      // 全角冒号归一（「9：3：3：1」旧版 0 命中）。
      expect(findCardIdForTopic('后代比为 9：3：3：1'), 'b9331-bianshi');
      // 误命中修正（老用户 ③）：「碱基对替换」先命中变异卡而非碱基卡。
      expect(findCardIdForTopic('碱基对替换导致基因突变'), 'bianyi-sanfen');
      // 「标记基因」不再误命中同位素卡（裸「标记」已收紧）。
      expect(findCardIdForTopic('标记基因'), isNull);
      expect(findCardIdForTopic('完全无关的话题'), isNull);
      // 关键词表里的卡 id 全部真实存在（防改 id 静默断链）。
      for (final id in kCardTopicKeywords.keys) {
        expect(findCardIndexById(id), isNotNull, reason: '$id 应对应真实卡');
      }
    });
  });

  group('页面交互（窄屏回渲染）', () {
    testWidgets('选择条点选切章切卡 + 章内翻卡（含环绕）+ 已背过滤', (tester) async {
      BigQuestionCardsStore.mastered.value = <String>{};
      addTearDown(() => BigQuestionCardsStore.mastered.value = <String>{});

      await tester.pumpWidget(const MaterialApp(
        home: BigQuestionCardsPage(),
      ));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: '首帧无溢出');
      // v2.19.25：口诀已置顶，首屏即见。
      expect(find.textContaining('无中生有为隐性，有中生无为显性'),
          findsOneWidget);

      // 跨章直达：点「自由组合」章里的 pill（章与卡一起改写）。
      await _tapPill(tester, '9331 变式拆分');
      expect(find.textContaining('变式 = 9331 的格子重新合并，先画棋盘再归类'),
          findsOneWidget);
      // 章内换卡：点同章另一枚 pill。
      await _tapPill(tester, '连锁还是自由组合');
      expect(
          find.textContaining('测交四种均等 = 自由组合；两多两少 = 互换重组'),
          findsOneWidget);
      // 正文标题里的「第 N/M 张」跟着走（证明章索引也切了）。
      expect(find.text('自由组合 · 第 3/3 张'), findsOneWidget);

      // 章内翻卡：下一张环绕回第 1 张，上一张再绕回第 3 张。
      // ⛔ 这一对同时钉住「每章 _selected 记忆」与「翻卡不跨章」。
      final next = find.text('下一张');
      await tester.ensureVisible(next);
      await tester.pumpAndSettle();
      await tester.tap(next);
      await tester.pumpAndSettle();
      expect(find.text('自由组合 · 第 1/3 张'), findsOneWidget,
          reason: '章内末张「下一张」应环绕到首张');
      final prev = find.text('上一张');
      await tester.ensureVisible(prev);
      await tester.pumpAndSettle();
      await tester.tap(prev);
      await tester.pumpAndSettle();
      expect(find.text('自由组合 · 第 3/3 张'), findsOneWidget,
          reason: '章内首张「上一张」应环绕到末张（章记忆没丢）');

      // 切到别的章再回来：该章此前选中的卡仍在（_selected 记忆）。
      await _tapPill(tester, '显隐性判断三步');
      expect(find.text('分离定律 · 第 1/2 张'), findsOneWidget);
      await _tapPill(tester, '连锁还是自由组合');
      expect(find.text('自由组合 · 第 3/3 张'), findsOneWidget,
          reason: '跨章来回后该章仍停在之前选的那张卡');
    });

    testWidgets('搜索反查：输入关键词 → 命中跨章卡 → 点选直达（学生 P1-2）',
        (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: BigQuestionCardsPage(),
      ));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).first, '色盲');
      await tester.pumpAndSettle();
      // 「伴性遗传大题步骤」卡的信号含红绿色盲 → 命中（横条 pill + 命中项）。
      expect(find.text('伴性遗传大题步骤'), findsWidgets);
      expect(find.byKey(const ValueKey('cardHit:banxing-buzhou')),
          findsOneWidget,
          reason: '搜索命中项应能按卡 id 精确定位');

      // v2.20.0：命中项挂稳定 key（pill 与正文同名，靠 key 点选不靠次序）。
      await tester.tap(find.byKey(const ValueKey('cardHit:banxing-buzhou')));
      await tester.pumpAndSettle();
      // 直达伴性章：口诀置顶 + 搜索词清空（命中列表随之消失）。
      expect(
          find.textContaining('男性 X 只给女儿、Y 只给儿子'), findsOneWidget);
      expect(find.text('伴性遗传 · 第 2/2 张'), findsOneWidget,
          reason: '应切到伴性章并停在命中的那张卡');
      expect(find.byKey(const ValueKey('cardHit:banxing-buzhou')),
          findsNothing, reason: '点选后搜索词应清空');
    });

    testWidgets('只看未背：当前卡被滤掉时正文保持当前卡（与旧右区语义一致）',
        (tester) async {
      BigQuestionCardsStore.mastered.value = <String>{};
      addTearDown(() => BigQuestionCardsStore.mastered.value = <String>{});

      await tester.pumpWidget(const MaterialApp(
        home: BigQuestionCardsPage(),
      ));
      await tester.pumpAndSettle();

      // 标当前卡（首章首卡）已背 ⇒ 横条 pill 变「✓ 卡名」。
      final btn = find.text('标为已背熟');
      await tester.ensureVisible(btn);
      await tester.pumpAndSettle();
      await tester.tap(btn);
      await tester.pumpAndSettle();
      expect(find.textContaining('✓ 显隐性判断三步'), findsOneWidget,
          reason: '已背标记走 pill 文本前缀（骨架无 subtitle 位）');

      // 只看未背：该 pill 被滤掉，正文不许跟着抽空。
      final filter = find.text('只看未背');
      await tester.ensureVisible(filter);
      await tester.pumpAndSettle();
      await tester.tap(filter);
      await tester.pumpAndSettle();
      expect(find.textContaining('✓ 显隐性判断三步'), findsNothing,
          reason: '已背卡应从选择条里滤掉');
      expect(find.textContaining('无中生有为隐性，有中生无为显性'),
          findsOneWidget, reason: '正文保持当前卡');

      // 显示全部：pill 回来（过滤只是视图，不动记忆）。
      final back = find.text('显示全部');
      await tester.ensureVisible(back);
      await tester.pumpAndSettle();
      await tester.tap(back);
      await tester.pumpAndSettle();
      expect(find.textContaining('✓ 显隐性判断三步'), findsOneWidget);
      expect(find.text('分离定律 · 第 1/2 张'), findsOneWidget);
    });

    testWidgets('已背标记：切换 + 选择条 ✓（学生 P1-1）', (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: BigQuestionCardsPage(),
      ));
      await tester.pumpAndSettle();

      // 按钮在长内容底部，先滚入视口再点（窄屏回渲染）。
      final btn = find.text('标为已背熟');
      await tester.ensureVisible(btn);
      await tester.pumpAndSettle();
      await tester.tap(btn);
      await tester.pumpAndSettle();
      expect(find.text('已背熟'), findsOneWidget);
      expect(BigQuestionCardsStore.isMastered('xyx-panduan'), isTrue);

      final undo = find.text('已背熟');
      await tester.ensureVisible(undo);
      await tester.pumpAndSettle();
      await tester.tap(undo);
      await tester.pumpAndSettle();
      expect(find.text('标为已背熟'), findsOneWidget);
      expect(BigQuestionCardsStore.isMastered('xyx-panduan'), isFalse);
    });

    testWidgets('错题本回链：initialCardId 直达系谱卡（学生 P1-1）',
        (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: BigQuestionCardsPage(initialCardId: 'xipu-koujue'),
      ));
      await tester.pumpAndSettle();
      expect(find.textContaining('女患查父与子，男患查母与女'), findsOneWidget,
          reason: '应直接定位到系谱口诀卡');
    });

    testWidgets('关联工具回调（深链未注册时回退 onOpenTool）', (tester) async {
      final got = <int>[];
      await tester.pumpWidget(MaterialApp(
        home: BigQuestionCardsPage(onOpenTool: got.add),
      ));
      await tester.pumpAndSettle();
      final linkBtn = find.text('去 9331 练比例');
      await tester.ensureVisible(linkBtn);
      await tester.pumpAndSettle();
      await tester.tap(linkBtn);
      await tester.pumpAndSettle();
      expect(got, [2], reason: '测试无 fill target → 回退主导航索引 2');
    });

    // v2.19.26 三找茬代理交叉 P1：错题本 push 的卡页（onOpenTool==null）
    // 点深链——旧版 fill 只切被盖住的底层页、按钮零反应。修复后应
    // 执行 apply 且 pop 回根路由让目标页露出。
    testWidgets('深链从 push 路由触发：apply 执行 + pop 回壳页', (tester) async {
      ModuleFillBus.resetForTest();
      addTearDown(ModuleFillBus.resetForTest);
      var applied = false;
      ModuleFillBus.register(ModuleFillTarget(
        moduleId: 'cross_mono',
        pageIndex: 2,
        label: '测试目标',
        apply: (params) {
          applied = true;
          return true;
        },
      ));

      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (ctx) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.of(ctx).push(MaterialPageRoute<void>(
                builder: (_) =>
                    const BigQuestionCardsPage(initialCardId: 'xyx-panduan'),
              )),
              child: const Text('open-cards'),
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      await tester.tap(find.text('open-cards'));
      await tester.pumpAndSettle();

      final linkBtn = find.text('去 9331 练比例');
      await tester.ensureVisible(linkBtn);
      await tester.pumpAndSettle();
      await tester.tap(linkBtn);
      await tester.pumpAndSettle();

      expect(applied, isTrue, reason: 'fill target 的 apply 应执行');
      expect(find.text('open-cards'), findsOneWidget,
          reason: '卡页路由应被 pop 回壳页（死按钮修复）');
    });

    testWidgets('390 窄屏零溢出 + 单栏导航（无 TabBar / 只有一套选择条）',
        (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(const MaterialApp(
        home: BigQuestionCardsPage(),
      ));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: '390 窄屏首帧无溢出');
      // 窄屏同样是单栏：一条横滚选择条 + 正文，没有第二层导航。
      expect(find.byType(SideNavWorkbench), findsOneWidget);
      expect(find.byType(TabBar), findsNothing);
      expect(find.byType(ToolWorkbench), findsNothing);
    });
  });

  group('布局巡检', () {
    testWidgets('宽屏单栏导航守卫：无 ToolWorkbench 第二列 / 无章节 TabBar / '
        '只有一套选择条 / 6 章逐章切换零溢出', (tester) async {
      tester.view.physicalSize = const Size(1600, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(const MaterialApp(
        home: BigQuestionCardsPage(),
      ));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: '首帧无溢出');

      // ① 用户点名的双层导航：全局 Rail 之外的那一层。本页不是计算页，
      //    ToolWorkbench 的 280px 左栏（旧「本章卡片」目录）必须消失。
      expect(find.byType(ToolWorkbench), findsNothing,
          reason: 'v2.20.0：宽屏不得再有 ToolWorkbench 左目录列');
      // ② AppBar 不再叠章节 TabBar（旧 bottom 就是第二层导航）。
      expect(find.byType(TabBar), findsNothing, reason: '章节页签行已收掉');
      expect(find.byType(Tab), findsNothing);
      // ③ 全页只有一套选择条。
      expect(find.byType(SideNavWorkbench), findsOneWidget,
          reason: '整页只允许一条导航（骨架实例应恰好 1 个）');

      // ④ 宽屏用组名 + 全称：6 个章节组名都在横条上（窄屏不显示组名）。
      for (final chapter in bigQuestionChapters) {
        expect(find.text(chapter.title), findsOneWidget,
            reason: '宽屏应显示章节组名「${chapter.title}」');
      }

      // ⑤ 逐章点该章首卡的 pill：正文跟着换、无溢出。
      for (final chapter in bigQuestionChapters) {
        final first = chapter.cards.first;
        await _tapPill(tester, first.title);
        expect(tester.takeException(), isNull,
            reason: '章「${chapter.title}」激活帧无溢出');
        expect(find.textContaining(first.takeaway.substring(0, 6)),
            findsWidgets,
            reason: '章「${chapter.title}」正文应换成「${first.title}」');
      }
    });

    // 老师 P1-2 残留缺口：课堂模式 ×1.3 下逐章逐卡全遍历（present scan
    // 只泵默认卡，本用例把 14 张卡全部点一遍收溢出错误）。
    // v2.20.0：导航从「章节页签 + 左栏目录」改为「选择条 pill」。
    testWidgets('课堂模式 ×1.3 逐章逐卡零溢出', (tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final errors = <FlutterErrorDetails>[];
      final prev = FlutterError.onError;
      FlutterError.onError = (d) {
        if (d.exceptionAsString().contains('overflowed')) {
          errors.add(d);
        } else {
          prev?.call(d);
        }
      };
      addTearDown(() => FlutterError.onError = prev);

      await tester.pumpWidget(MediaQuery(
        data: const MediaQueryData(textScaler: TextScaler.linear(1.3)),
        child: MaterialApp(theme: AppTheme.light(), home: const BigQuestionCardsPage()),
      ));
      await tester.pumpAndSettle();

      for (var c = 0; c < bigQuestionChapters.length; c++) {
        final n = bigQuestionChapters[c].cards.length;
        for (var i = 0; i < n; i++) {
          // v2.20.0：换章换卡都走选择条 pill（章由 pill 所属分组带出）。
          await _tapPill(tester, bigQuestionChapters[c].cards[i].title);
        }
      }
      FlutterError.onError = prev;
      expect(errors, isEmpty,
          reason: '×1.3 课堂模式下逐章逐卡渲染零溢出：\n'
              '${errors.map((e) => e.exceptionAsString()).join('\n')}');
    });
  });
}
