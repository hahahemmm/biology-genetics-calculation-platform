import 'dart:convert';
import 'dart:io';

import 'package:biology/data/bio_knowledge_data.dart';
import 'package:biology/models/bio_knowledge.dart';
import 'package:biology/services/bio_database_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  group('内置精选', () {
    test('18 条真实 ID、来源链接与教学边界完整', () {
      expect(kBioKnowledgeRecords, hasLength(18));
      expect(kBioKnowledgeRecords.map((r) => r.id).toSet(), <String>{
        '15823023',
        '17417022',
        '23399825',
        '8013946',
        'P00642',
        'P19821',
        'P42212',
        '2OXV',
        '1GFL',
        '3LWM',
        '4OO8',
        '4UN3',
        '2448875',
        '8303295',
        '4594039',
        '23287722',
        '25079318',
        '4377758',
      });
      for (final record in kBioKnowledgeRecords) {
        final expectedHost = switch (record.source) {
          BioSource.uniprot => 'www.uniprot.org',
          BioSource.pdb => 'www.rcsb.org',
          BioSource.pubmed => 'pubmed.ncbi.nlm.nih.gov',
        };
        expect(Uri.parse(record.url).host, expectedHost);
        expect(Uri.parse(record.url).scheme, 'https');
      }
      expect(
        kBioKnowledgeRecords.singleWhere((r) => r.id == '2OXV').caution,
        contains('A138T 突变体'),
      );
      expect(
        kBioKnowledgeRecords.singleWhere((r) => r.id == '3LWM').caution,
        contains('不是完整的 832 aa 蛋白'),
      );
      expect(
        kBioKnowledgeRecords.singleWhere((r) => r.id == '23287722').caution,
        contains('不属于高中基础 PCR'),
      );
    });

    test('关键词和来源筛选可组合', () {
      expect(filterBioKnowledge(query: 'EcoRI').map((r) => r.id), <String>[
        'P00642',
        '2OXV',
      ]);
      expect(filterBioKnowledge(query: 'GFP').map((r) => r.id), <String>[
        'P42212',
        '1GFL',
        '8303295',
      ]);
      expect(
        filterBioKnowledge(
          query: 'Taq',
          source: BioSource.pubmed,
        ).map((r) => r.id),
        <String>['2448875'],
      );
      expect(filterBioKnowledge(query: 'CRISPR').map((r) => r.id), <String>[
        '4OO8',
        '4UN3',
        '23287722',
        '25079318',
      ]);
      expect(filterBioKnowledge(query: 'PAM').map((r) => r.id), <String>[
        '4UN3',
        '25079318',
      ]);
      expect(filterBioKnowledge(query: '不存在的词'), isEmpty);
    });

    test('DNA 连接酶精选区分骨架共价连接与碱基配对', () {
      final record = kBioKnowledgeRecords.singleWhere((r) => r.id == '4377758');
      expect(record.source, BioSource.pubmed);
      expect(record.title, 'DNA ligase: structure, mechanism, and function.');
      expect(record.subtitle, 'Lehman · Science · 1974-11-29 · 综述');
      expect(record.summary, contains('3′-OH'));
      expect(record.summary, contains('5′-磷酸'));
      expect(record.summary, contains('磷酸二酯键'));
      expect(record.caution, contains('氢键负责碱基互补配对'));
      expect(record.url, 'https://pubmed.ncbi.nlm.nih.gov/4377758/');
      expect(
        record.facts.map((fact) => fact.value),
        containsAll(<String>['4377758', '10.1126/science.186.4166.790']),
      );
      expect(filterBioKnowledge(query: 'DNA 连接酶').map((r) => r.id), <String>[
        '4377758',
      ]);
    });

    test('Taq 精选明确耐热边界，不把大片段结构当作完整蛋白', () {
      final taq = kBioKnowledgeRecords.singleWhere((r) => r.id == 'P19821');
      expect(taq.summary, contains('较高温度'));
      expect(taq.caution, contains('不等于温度越高越好'));
      expect(taq.caution, contains('永不失活'));

      final paper = kBioKnowledgeRecords.singleWhere((r) => r.id == '2448875');
      expect(paper.source, BioSource.pubmed);
      expect(paper.url, 'https://pubmed.ncbi.nlm.nih.gov/2448875/');

      final structure = kBioKnowledgeRecords.singleWhere((r) => r.id == '3LWM');
      expect(structure.caution, contains('不是完整的 832 aa 蛋白'));
    });

    test('PCR 温度循环精选支持三步顺序并保留规程边界', () {
      final record = kBioKnowledgeRecords.singleWhere(
        (r) => r.id == '23399825',
      );
      expect(record.source, BioSource.pubmed);
      expect(record.title, 'Polymerase chain reaction.');
      expect(record.summary, contains('变性→退火→延伸'));
      expect(record.url, 'https://pubmed.ncbi.nlm.nih.gov/23399825/');
      expect(
        record.facts.map((fact) => fact.value),
        containsAll(<String>['PMC4102308', '10.1038/jid.2013.1']),
      );
      expect(record.caution, contains('具体温度和时间'));
      expect(record.caution, contains('不是所有 PCR 通用'));
      expect(filterBioKnowledge(query: 'PCR 温度循环').map((r) => r.id), <String>[
        '23399825',
      ]);
    });

    test('PCR 理论扩增精选区分每轮加倍、理想公式与真实平台期', () {
      final doubling = kBioKnowledgeRecords.singleWhere(
        (r) => r.id == '23399825',
      );
      expect(doubling.summary, contains('每重复一次'));
      expect(doubling.summary, contains('分子数加倍'));
      expect(doubling.caution, contains('理想'));

      final plateau = kBioKnowledgeRecords.singleWhere(
        (r) => r.id == '17417022',
      );
      expect(plateau.source, BioSource.pubmed);
      expect(plateau.title, 'Quantitative polymerase chain reaction.');
      expect(plateau.subtitle, contains('2007'));
      expect(plateau.summary, contains('平台期前'));
      expect(plateau.caution, contains('不能按理想 2ⁿ 外推真实终点产量'));
      expect(plateau.url, 'https://pubmed.ncbi.nlm.nih.gov/17417022/');
      expect(
        plateau.facts.map((fact) => fact.value),
        containsAll(<String>['17417022', '10.1007/978-1-59745-257-1_25']),
      );
      expect(filterBioKnowledge(query: 'PCR 理论扩增').map((r) => r.id), <String>[
        '23399825',
        '17417022',
      ]);
    });

    test('Cas9 结构精选保留 PDB 元数据与教学边界', () {
      final record = kBioKnowledgeRecords.singleWhere((r) => r.id == '4OO8');
      expect(record.source, BioSource.pdb);
      expect(record.title, contains('Streptococcus pyogenes Cas9'));
      expect(record.subtitle, 'X-ray diffraction · 2.50 Å · 2014-02-26');
      expect(record.url, 'https://www.rcsb.org/structure/4OO8');
      expect(
        record.facts.map((fact) => fact.value),
        containsAll(<String>['PMID 24529477', '10.1016/j.cell.2014.02.001']),
      );
      expect(record.caution, contains('含 4 个突变'));
      expect(record.caution, contains('不单独用于辨认完整 PAM 双链'));
      expect(record.keywords, isNot(contains('PAM')));
    });

    test('4UN3 与原始论文共同支撑 PAM 教学，不泛化到其他 Cas 蛋白', () {
      final structure = kBioKnowledgeRecords.singleWhere((r) => r.id == '4UN3');
      expect(structure.source, BioSource.pdb);
      expect(structure.title, contains('PAM-containing DNA target'));
      expect(structure.subtitle, 'X-ray diffraction · 2.59 Å · 2014-07-23');
      expect(structure.url, 'https://www.rcsb.org/structure/4UN3');
      expect(
        structure.facts.map((fact) => fact.value),
        containsAll(<String>['PMID 25079318', '10.1038/nature13579']),
      );
      expect(structure.caution, contains('含 1 个工程突变'));

      final paper = kBioKnowledgeRecords.singleWhere((r) => r.id == '25079318');
      expect(paper.source, BioSource.pubmed);
      expect(paper.summary, contains("5′-NGG-3′"));
      expect(paper.summary, contains('并非所有 Cas 蛋白通用'));
      expect(paper.url, 'https://pubmed.ncbi.nlm.nih.gov/25079318/');
      expect(
        paper.facts.map((fact) => fact.value),
        containsAll(<String>['PMC4176945', '10.1038/nature13579']),
      );
    });
  });

  group('数据库响应解析', () {
    test('UniProt JSON 规范化为蛋白质记录', () {
      final records = parseUniProtResults(<String, dynamic>{
        'results': <Map<String, dynamic>>[
          <String, dynamic>{
            'primaryAccession': 'P00642',
            'uniProtkbId': 'ECOR_ECOLI',
            'proteinDescription': <String, dynamic>{
              'recommendedName': <String, dynamic>{
                'fullName': <String, dynamic>{
                  'value': 'Type II restriction enzyme EcoRI',
                },
              },
            },
            'genes': <Map<String, dynamic>>[
              <String, dynamic>{
                'geneName': <String, dynamic>{'value': 'ecoRIR'},
              },
            ],
            'organism': <String, dynamic>{'scientificName': 'Escherichia coli'},
            'sequence': <String, dynamic>{'length': 277},
          },
        ],
      });
      expect(records, hasLength(1));
      expect(records.single.id, 'P00642');
      expect(records.single.title, contains('EcoRI'));
      expect(records.single.subtitle, 'ecoRIR · Escherichia coli');
      expect(records.single.facts.single.value, '277 aa');
      expect(records.single.url, contains('/P00642/entry'));
    });

    test('PDB 搜索 ID 与条目详情分别解析', () {
      expect(
        parsePdbSearchIds(<String, dynamic>{
          'result_set': <Map<String, dynamic>>[
            <String, dynamic>{'identifier': '2oxv'},
            <String, dynamic>{'identifier': '1gfl'},
          ],
        }),
        <String>['2oxv', '1gfl'],
      );
      final record = parsePdbEntry('2oxv', <String, dynamic>{
        'struct': <String, dynamic>{'title': 'EcoRI A138T mutant'},
        'exptl': <Map<String, dynamic>>[
          <String, dynamic>{'method': 'X-RAY DIFFRACTION'},
        ],
        'rcsb_entry_info': <String, dynamic>{
          'resolution_combined': <double>[1.95],
        },
        'rcsb_accession_info': <String, dynamic>{
          'initial_release_date': '2007-10-23T00:00:00Z',
        },
        'rcsb_primary_citation': <String, dynamic>{
          'pdbx_database_id_PubMed': 17997963,
          'pdbx_database_id_DOI': '10.example/test',
        },
      });
      expect(record, isNotNull);
      expect(record!.id, '2OXV');
      expect(record.subtitle, contains('1.95 Å'));
      expect(record.subtitle, contains('2007-10-23'));
      expect(record.url, 'https://www.rcsb.org/structure/2OXV');
      expect(record.facts.map((f) => f.value), contains('PMID 17997963'));
    });

    test('PubMed ESearch 与 ESummary 解析 PMID、PMCID、DOI', () {
      final ids = parsePubMedSearchIds(<String, dynamic>{
        'esearchresult': <String, dynamic>{
          'idlist': <String>['23287722'],
        },
      });
      expect(ids, <String>['23287722']);
      final records = parsePubMedSummaries(ids, <String, dynamic>{
        'result': <String, dynamic>{
          '23287722': <String, dynamic>{
            'title': 'RNA-guided human genome engineering via Cas9.',
            'authors': <Map<String, dynamic>>[
              <String, dynamic>{'name': 'Mali P'},
            ],
            'fulljournalname': 'Science',
            'pubdate': '2013 Feb 15',
            'articleids': <Map<String, dynamic>>[
              <String, dynamic>{'idtype': 'pubmed', 'value': '23287722'},
              <String, dynamic>{'idtype': 'pmc', 'value': 'PMC3712628'},
              <String, dynamic>{
                'idtype': 'doi',
                'value': '10.1126/science.1232033',
              },
            ],
          },
        },
      });
      expect(records, hasLength(1));
      expect(records.single.id, '23287722');
      expect(records.single.subtitle, contains('Mali P 等'));
      expect(
        records.single.facts.map((f) => f.value),
        containsAll(<String>['PMC3712628', '10.1126/science.1232033']),
      );
    });

    test('空结果与缺失可选字段不会伪造记录', () {
      expect(
        parseUniProtResults(const <String, dynamic>{'results': <dynamic>[]}),
        isEmpty,
      );
      expect(parsePdbSearchIds(const <String, dynamic>{}), isEmpty);
      expect(parsePdbEntry('0000', const <String, dynamic>{}), isNull);
      expect(parsePubMedSearchIds(const <String, dynamic>{}), isEmpty);
      expect(
        parsePubMedSummaries(const <String>['1'], const <String, dynamic>{}),
        isEmpty,
      );
    });
  });

  group('只读服务', () {
    test('UniProt 成功响应经服务返回真实解析结果', () async {
      final client = MockClient((request) async {
        expect(request.url.host, 'rest.uniprot.org');
        expect(request.url.queryParameters['query'], 'P00642');
        return http.Response('''
          {"results":[{"primaryAccession":"P00642","uniProtkbId":"ECOR_ECOLI",
          "proteinDescription":{"recommendedName":{"fullName":{"value":"EcoRI"}}},
          "organism":{"scientificName":"Escherichia coli"},"sequence":{"length":277}}]}
        ''', 200);
      });
      final service = BioDatabaseService(
        httpClient: client,
        now: () => DateTime(2026, 10, 29, 8, 30),
      );
      final response = await service.search(
        'P00642',
        source: BioSource.uniprot,
      );
      expect(response.records.single.id, 'P00642');
      expect(response.failures, isEmpty);
      expect(response.queriedAt, DateTime(2026, 10, 29, 8, 30));
      service.dispose();
    });

    test('UniProt gzip 响应先解压再解析', () async {
      final payload = jsonEncode({
        'results': [
          {
            'primaryAccession': 'P00642',
            'proteinDescription': {
              'recommendedName': {
                'fullName': {'value': 'EcoRI'},
              },
            },
          },
        ],
      });
      final service = BioDatabaseService(
        httpClient: MockClient(
          (_) async => http.Response.bytes(
            gzip.encode(utf8.encode(payload)),
            200,
            headers: const {'content-encoding': 'gzip'},
          ),
        ),
      );
      final response = await service.search('EcoRI', source: BioSource.uniprot);
      expect(response.records.single.id, 'P00642');
      expect(response.failures, isEmpty);
      service.dispose();
    });

    test('HTTP 错误转成可见失败，不生成替代条目', () async {
      final service = BioDatabaseService(
        httpClient: MockClient((_) async => http.Response('unavailable', 503)),
      );
      final response = await service.search('EcoRI', source: BioSource.uniprot);
      expect(response.records, isEmpty);
      expect(response.failures.single, contains('HTTP 503'));
      service.dispose();
    });

    test('PDB 详情全部失败时报告错误，不伪装成空结果', () async {
      final service = BioDatabaseService(
        httpClient: MockClient((request) async {
          if (request.url.host == 'search.rcsb.org') {
            return http.Response(
              jsonEncode({
                'result_set': [
                  {'identifier': '2OXV'},
                ],
              }),
              200,
            );
          }
          return http.Response('unavailable', 503);
        }),
      );
      final response = await service.search('EcoRI', source: BioSource.pdb);
      expect(response.records, isEmpty);
      expect(response.failures.single, contains('条目详情读取失败'));
      service.dispose();
    });
  });
}
