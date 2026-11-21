// ════════════════════════════════════════════════════════════════════════
//  test/card_keyword_coverage_test.dart
//  v2.19.64：kCardTopicKeywords 覆盖率守卫（六考点决定表 + 12 签回归网）
// ════════════════════════════════════════════════════════════════════════
//
//  ## 本文件钉住什么
//  1. `findCardIdForTopic`（lib/data/big_question_cards.dart:487）按
//     `kCardTopicKeywords` 的**插入顺序**返回首个子串命中的卡 id；本文件
//     不复制实现，只钉「六考点 → 卡 id / null」这张决定表。
//  2. 加词是**语义判决**，不是覆盖率刷分：卡库没有语义正确的卡就明确不铺
//     （没有合适的卡宁可 null，硬凑一张会让错题本「看套路卡」回链跳到
//     与考点无关的卡）。表里只新增了一个词：`配子种类`。
//
//  ## 六考点决定表（v2.19.64 逐张通读 14 张卡的
//     title/signals/steps/pitfalls 后判定）
//
//  | 考点（App 自产 subjectArea 字面量）            | 决定              | 理由 |
//  |-----------------------------------------------|-------------------|------|
//  | 配子种类（减数分裂）                           | peizi-ziyoujiaopei| 卡「配子法与自由交配速算」是卡库里**唯一**配子层的卡：其 step1 就按「每种基因型产生的配子」拆开并枚举 AaBb → AB:Ab:aB:ab（= 2² 种配子），与减数分裂「n 对同源染色体 → 2ⁿ 种配子」是同一计数口径 ⇒ 加窄词「配子种类」。⚠️ 不铺宽词「配子」：它会让「育种应用（单倍体育种·杂交育种·**四倍体配子**）」从 danbei-liucheng 漂到本卡（见 K2）。 |
//  | 进化树（共同祖先·先导图）                      | null              | 本页签是纯展示先导图（共同祖先证据）；卡库里没有任何一张讲系统树/共同祖先的卡 ⇒ 不铺。 |
//  | 选择模拟（自然选择逐代递推）                    | null              | 最近的是 pingheng-panduan（遗传平衡判断），但它是「判断是否平衡 + p²·2pq·q² 验算」套路，只把「有选择」列为 5 条件之一被破坏的例子（'基因频率**会**改变'），并不给「给定选择系数 s 逐代递推」的套路 ⇒ 相邻不同源，不铺。 |
//  | 进化理论（现代生物进化理论）                    | null              | 本页签是纯知识区（共同祖先证据/现代生物进化理论/物种形成）；卡库里无对应卡 ⇒ 不铺。 |
//  | 染色体组数判断（形态法与基因型法）              | null              | 卡库里没有「数染色体组数」的套路卡；danbei-liucheng 只覆盖育种流程，bianyi-sanfen 的易错里只有「单倍体 ≠ 只有一个染色体组」一句提醒，不构成组数判断套路 ⇒ 判不适用，不铺。 |
//  | 倍性判定与育性（三倍体无子西瓜）                | null              | 同上：danbei-liucheng 是育种流程（花药离培 + 秋水仙素），其「组不成对→联会紊乱→不育」只针对单倍体育种；无「判倍性/判育性」套路卡 ⇒ 判不适用，不铺。 |
//
//  ## K3 说明（drift 红在 K2 已经全覆盖）
//  新词「配子种类」只可能造成「某考点从原卡漂到别处」这一种回归；K2 把
//  v2.19.61/62 的 12 个签 + 其它页自产考点 + 14 张卡的 subjectArea 自反查
//  全部逐条再断言一遍 ⇒ 任何漂移都会在 K2 变红，故不另设 K3 用例（只留此
//  注释）。⚠️ 加词前已逐一核对：含「配子种类」的 subjectArea 全 App 只有
//  分子页 tab3 这一处（`molecular_page.dart:488`），且它在旧表里是 null。
//
//  ## 已知的既有断言红（本文件管不到，如实记账）
//  加词后分子页 tab3 不再是「命不中卡」：
//  · `test/card_link_key_concept_test.dart` A0b（:142）断言其 isNull；
//  · 同文件 A2b（:194）断言该页签零提示 + 按 K 不导航。
//  ⇒ 这两条同源于 v2.19.61/62 的**旧事实**（当时代码确实命中 null），
//    本任务的「新事实」正是要它们改变。它们不在本 worker 的文件所有权内
//    （只许动数据表 + 本文件 + pubspec），故不做静默改写，仅在交付里上报。

import 'package:biology/data/big_question_cards.dart';
import 'package:flutter_test/flutter_test.dart';

/// 分子页 tab3 考点（配子种类）——本版唯一由「不命中」变「命中」的签。
const _kGameteTopic = '配子种类（减数分裂）';
const _kGameteCardId = 'peizi-ziyoujiaopei';

void main() {
  // ══════════════════════════════════════════════════════════════════
  //  K1. 六考点决定表（命中 → 卡 id；不铺 → null）
  // ══════════════════════════════════════════════════════════════════

  group('K1·六考点决定表（逐条与文件头判决一致）', () {
    test('K1a·配子种类（减数分裂）→ 配子法与自由交配速算卡', () {
      // 理由：卡库唯一配子层卡（step1 枚举 AaBb → AB:Ab:aB:ab）。
      expect(findCardIdForTopic(_kGameteTopic), _kGameteCardId,
          reason: '命中窄词「配子种类」（⛔ 不是宽词「配子」——那会引来 K2 的漂移）');
    });

    test('K1b·进化页三签（进化树/选择模拟/进化理论）→ 判不适用，不铺', () {
      // 进化树：纯展示先导图，无系统树/共同祖先卡。
      expect(findCardIdForTopic('进化树（共同祖先·先导图）'), isNull,
          reason: '卡库无系统树/共同祖先卡 ⇒ 不铺');
      // 选择模拟：遗传平衡卡只讲「有选择 ⇒ 频率会变」，不是逐代递推套路。
      expect(findCardIdForTopic('选择模拟（自然选择逐代递推）'), isNull,
          reason: '相邻（遗传平衡卡）不同源 ⇒ 不铺');
      // 进化理论：纯知识区，无卡。
      expect(findCardIdForTopic('进化理论（现代生物进化理论）'), isNull,
          reason: '卡库无现代生物进化理论卡 ⇒ 不铺');
    });

    test('K1c·倍性页两签（组数判断/倍性与育性）→ 判不适用，不铺', () {
      // 组数判断：卡库无「数染色体组数」套路卡。
      expect(findCardIdForTopic('染色体组数判断（形态法与基因型法）'), isNull,
          reason: '卡库无组数判断卡 ⇒ 判不适用，不铺');
      // 倍性与育性：danbei-liucheng 只覆盖育种流程。
      expect(findCardIdForTopic('倍性判定与育性（三倍体无子西瓜）'), isNull,
          reason: '卡库无「判倍性/判育性」套路卡 ⇒ 判不适用，不铺');
    });

    test('K1d·「配子种类」是窄词：不含它的考点一律不受影响（反例）', () {
      // 反例一：含「配子」但不含「配子种类」的育种签，必须仍归 danbei-liucheng
      // （这是宽词「配子」会踩的坑——本版用窄词专为躲开它）。
      expect(findCardIdForTopic('育种应用（单倍体育种·杂交育种·四倍体配子）'),
          'danbei-liucheng',
          reason: '含「四倍体配子」但不含「配子种类」⇒ 不许漂到 peizi 卡');
      // 反例二：卡自身的领起词不受影响（错题本回链自反查）。
      expect(findCardIdForTopic('自由交配'), _kGameteCardId);
    });
  });

  // ══════════════════════════════════════════════════════════════════
  //  K2. 回归网：v2.19.61/62 的 12 个签 + 其它页自产考点 + 14 卡自反查
  //      —— 一个都不许漂移（唯一有意改动 = 配子种类，见 K1a）
  // ══════════════════════════════════════════════════════════════════

  group('K2·回归网（12 签 6 中：命中不许漂移）', () {
    test('K2a·分子页 4 签（旧命中 3 + 本版新增 1）', () {
      expect(findCardIdForTopic('碱基组成（DNA 碱基互补）'), 'jianji-hubu',
          reason: '旧命中词「碱基互补」不许漂');
      expect(findCardIdForTopic('复制与标记（半保留复制与密度梯度）'),
          'biaoji-shidai',
          reason: '旧命中词「半保留」不许漂');
      expect(findCardIdForTopic('基因表达（6:3:1 与中心法则）'), 'fanyi-huansuan',
          reason: '旧命中词「中心法则」不许漂');
      // ⚠️ 本版唯一有意改动：旧表里此签是 null，加窄词「配子种类」后命中
      //    peizi-ziyoujiaopei（决定表 K1a）。除它以外，12 签零漂移。
      expect(findCardIdForTopic(_kGameteTopic), _kGameteCardId);
    });

    test('K2b·进化页 5 签（旧命中 2 不许漂，其余仍 null）', () {
      expect(findCardIdForTopic('基因频率（按个体数计算）'), 'pinlv-susuan',
          reason: '旧命中词「基因频率」不许漂');
      expect(findCardIdForTopic('遗传平衡（哈迪-温伯格预测）'), 'pingheng-panduan',
          reason: '旧命中词「遗传平衡」不许漂');
      expect(findCardIdForTopic('进化树（共同祖先·先导图）'), isNull);
      expect(findCardIdForTopic('选择模拟（自然选择逐代递推）'), isNull);
      expect(findCardIdForTopic('进化理论（现代生物进化理论）'), isNull);
    });

    test('K2c·倍性页 3 签（旧命中 1 不许漂）', () {
      expect(findCardIdForTopic('育种应用（单倍体育种·杂交育种·四倍体配子）'),
          'danbei-liucheng',
          reason: '旧命中词「单倍体」不许漂——⛔ 若改为宽词「配子」这条必红');
      expect(findCardIdForTopic('染色体组数判断（形态法与基因型法）'), isNull);
      expect(findCardIdForTopic('倍性判定与育性（三倍体无子西瓜）'), isNull);
    });

    test('K2d·其它页 App 自产考点（v2.19.26 词表 + 变异页/遗传咨询页）', () {
      // 计算器页考点常量。
      expect(findCardIdForTopic('自由组合定律'), 'b9331-bianshi');
      expect(findCardIdForTopic('分离定律'), 'fan-tui-qinben');
      expect(findCardIdForTopic('伴性遗传'), 'banxing-buzhou');
      // 系谱推断页。
      expect(findCardIdForTopic('人类遗传病'), 'xipu-koujue');
      // 遗传咨询页：本就不该命中任何卡（无对应套路卡）。
      expect(findCardIdForTopic('遗传咨询（单基因遗传病风险）'), isNull);
      // 变异页 4 签。
      expect(findCardIdForTopic('基因突变模拟（碱基替换/插入/缺失）'),
          'bianyi-sanfen',
          reason: '命中词「基因突变」');
      expect(findCardIdForTopic('染色体组数判断（基因型法）'), isNull);
      expect(findCardIdForTopic('染色体结构变异（缺失/重复/倒位/易位）'), isNull,
          reason: '「染色体结构变异」不含表里的「染色体变异」子串 ⇒ null（现状，不许漂）');
      expect(findCardIdForTopic('诱变因素与育种方法'), 'danbei-liucheng',
          reason: '命中词「育种」');
    });

    test('K2e·14 张卡的领起词自反查（= subjectAreaForBigQuestionCard 回链）', () {
      // subjectAreaForBigQuestionCard 取 keywords.first 当考点；它必须经
      // findCardIdForTopic 恰好回到本卡（cards_step_selftest D1 的同一事实，
      // 本文件再钉一遍，防加词把某张卡的领起词漂走）。
      for (final ch in bigQuestionChapters) {
        for (final card in ch.cards) {
          final kws = kCardTopicKeywords[card.id]!;
          expect(kws, isNotEmpty, reason: '${card.id} 应有领起词');
          expect(findCardIdForTopic(kws.first), card.id,
              reason: '${card.id} 的领起词「${kws.first}」反查漂到了别的卡（或 null）');
        }
      }
    });
  });
}
