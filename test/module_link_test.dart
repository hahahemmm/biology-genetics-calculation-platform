// module_link_test.dart —— v2.21.0 图谱节点 → 功能页链接（AppModuleLink）验收
//
// 守卫（A 项）：
//   M1：代表性映射不变——9331 → cross(2)、pedigree-analysis → pedigree(1)、
//       dna-genes-alleles → molecular(5)，label 仍是「遗传计算器 / 遗传图谱 /
//       分子遗传」（按钮文案「打开对应功能：<label>」）。
//   M2：旧 _nodeTools 的 19 个节点 id 一个不丢（且与图谱数据节点集完全一致）。
//   M3：导航索引**由 appNavDestinations 顺序派生**，不是写死数字——
//       与 appNavById/下标逐条对齐；主导航重排时这里跟着走。
//   M4：未知节点 id / 空串 ⇒ null；未知 destinationId ⇒ 不可跳转。
//   M5：纯导览——解析链路不碰 ModuleFillBus（不注册、不挂待填参数）。

import 'package:biology/engine/knowledge_graph.dart';
import 'package:biology/ui/app_navigation.dart';
import 'package:biology/ui/module_fill.dart';
import 'package:biology/ui/module_link.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(ModuleFillBus.resetForTest);
  tearDown(ModuleFillBus.resetForTest);

  group('M1 代表映射（v2.2 行为不变）', () {
    test('9331 → 遗传计算器（cross，导航索引 2）', () {
      final link = knowledgeGraphLinkForNode('9331');
      expect(link, isNotNull);
      expect(link!.destinationId, 'cross');
      expect(link.label, '遗传计算器');
      expect(link.navIndex, 2, reason: 'cross 在主导航第 3 位 ⇒ 索引 2');
      expect(link.isNavigable, isTrue);
    });

    test('pedigree-analysis → 遗传图谱（pedigree，导航索引 1）', () {
      final link = knowledgeGraphLinkForNode('pedigree-analysis');
      expect(link, isNotNull);
      expect(link!.destinationId, 'pedigree');
      expect(link.label, '遗传图谱');
      expect(link.navIndex, 1);
    });

    test('dna-genes-alleles → 分子遗传（molecular，导航索引 5）', () {
      final link = knowledgeGraphLinkForNode('dna-genes-alleles');
      expect(link, isNotNull);
      expect(link!.destinationId, 'molecular');
      expect(link.label, '分子遗传', reason: '按钮文案是「分子遗传」，不是导航短名「分子」');
      expect(link.navIndex, 5);
    });
  });

  group('M2 覆盖面：19 个节点一个不丢', () {
    test('图谱数据里的每个节点都有链接（19 个）', () {
      final ids = defaultKnowledgeGraph.nodes.map((n) => n.id).toList();
      expect(ids.length, 19, reason: '图谱当前节点数');
      for (final id in ids) {
        expect(
          knowledgeGraphLinkForNode(id),
          isNotNull,
          reason: '$id 缺功能映射（旧 _nodeTools 迁移丢了）',
        );
      }
      expect(
        knowledgeGraphLinkedNodeIds,
        ids.toSet(),
        reason: '链接表与图谱数据节点集完全一致（不多不少）',
      );
    });

    test('旧表 19 条逐条点名（防「表在但键名漂移」）', () {
      const legacyIds = <String>[
        'dna-genes-alleles',
        'genotype-phenotype',
        'dominant-recessive',
        'law-of-segregation',
        'law-of-independent-assortment',
        'punnett-square',
        'gamete-formation',
        'testcross',
        'backcross',
        '9331',
        '9331-variant-97',
        '9331-variant-934',
        '9331-variant-151',
        '9331-variant-14641',
        'lethal-gene',
        'incomplete-dominance',
        'codominance',
        'sex-linked',
        'pedigree-analysis',
      ];
      expect(legacyIds.length, 19);
      for (final id in legacyIds) {
        expect(knowledgeGraphLinkForNode(id), isNotNull, reason: '缺 $id');
      }
    });
  });

  group('M3 索引派生', () {
    test('每条链接的 navIndex == 目的地 id 在 appNavDestinations 的下标', () {
      for (final nodeId in knowledgeGraphLinkedNodeIds) {
        final link = knowledgeGraphLinkForNode(nodeId)!;
        final idx = appNavDestinations.indexWhere(
          (d) => d.id == link.destinationId,
        );
        expect(idx, isNot(-1), reason: '${link.destinationId} 不在主导航目录里');
        expect(link.navIndex, idx, reason: '$nodeId 的索引必须来自目录顺序，不是手写常量');
        expect(link.destination?.id, link.destinationId);
      }
    });

    test('目的地 id 是稳定 id（改文案不动跳转）', () {
      // 分子页文案叫「分子遗传」，目的地 id 仍是 molecular。
      final link = knowledgeGraphLinkForNode('dna-genes-alleles')!;
      expect(link.destinationId, 'molecular');
      expect(link.destination!.name, '分子', reason: '导航全名与按钮 label 是两套文案，各自独立');
    });
  });

  group('M4 未知即 null', () {
    test('未知节点 id / 空串 ⇒ null', () {
      expect(knowledgeGraphLinkForNode('no-such-node'), isNull);
      expect(knowledgeGraphLinkForNode(''), isNull);
      expect(
        knowledgeGraphLinkForNode('9331 '),
        isNull,
        reason: '不做模糊匹配，id 必须逐字命中',
      );
    });

    test('未知 destinationId ⇒ 不可跳转（导航索引 null）', () {
      const link = AppModuleLink(destinationId: 'no-such-page', label: '幽灵页');
      expect(link.navIndex, isNull);
      expect(link.isNavigable, isFalse);
      expect(link.destination, isNull);
      // 展示名仍可回退，不至于渲染空按钮（但页面因 navIndex==null 不渲染）
      expect(link.displayLabel, '幽灵页');
      const bare = AppModuleLink(destinationId: 'no-such-page', label: '');
      expect(bare.displayLabel, 'no-such-page');
    });

    test('label 为空时回退目的地名', () {
      const link = AppModuleLink(destinationId: 'cross', label: '  ');
      expect(link.displayLabel, '遗传计算器');
      expect(link.isNavigable, isTrue);
    });
  });

  group('M5 纯导览：不经 ModuleFillBus', () {
    test('解析全部链接后不注册目标、不留待填参数', () {
      for (final nodeId in knowledgeGraphLinkedNodeIds) {
        final link = knowledgeGraphLinkForNode(nodeId)!;
        // 只读解析导航与页内导览元数据；点击行为由页面决定。
        expect(link.navIndex, isNotNull);
        expect(
          ModuleFillBus.targetOf(link.destinationId),
          isNull,
          reason: '${link.destinationId} 不应被图谱链接注册成填充目标',
        );
        expect(
          ModuleFillBus.consumePending(link.destinationId),
          isNull,
          reason: '${link.destinationId} 不应留下待填参数',
        );
        expect(
          ModuleFillBus.consumePendingActions(link.destinationId),
          isEmpty,
          reason: '${link.destinationId} 不应留下待执行动作',
        );
      }
    });
  });

  group('M6 页内只读导览', () {
    test('DNA 走无脏页闸的 molecular_tab', () {
      final link = knowledgeGraphLinkForNode('dna-genes-alleles')!;
      expect(link.moduleId, 'molecular_tab');
      expect(link.linkParams, {'tab': '0'});
    });

    test('链接参数不同插入序仍相等且同哈希', () {
      const a = AppModuleLink(
        destinationId: 'cross',
        label: 'x',
        linkParams: {'a': '1', 'b': '2'},
      );
      const b = AppModuleLink(
        destinationId: 'cross',
        label: 'x',
        linkParams: {'b': '2', 'a': '1'},
      );
      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });

    test('伴性 / 分离 / 9331 各到正确页签，且不携带填题参数', () {
      const expected = <String, String>{
        'sex-linked': '3',
        'law-of-segregation': '2',
        'law-of-independent-assortment': '0',
        'codominance': '2',
      };
      for (final entry in expected.entries) {
        final link = knowledgeGraphLinkForNode(entry.key)!;
        expect(link.moduleId, 'cross_tab', reason: entry.key);
        expect(link.linkParams, {'tab': entry.value}, reason: entry.key);
        expect(link.linkParams.keys, ['tab'], reason: '只允许页签，不允许 p1/p2');
      }
    });
  });
}
