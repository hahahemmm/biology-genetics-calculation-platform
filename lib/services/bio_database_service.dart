import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../app_version.dart';
import '../models/bio_knowledge.dart';

/// 应用内实时检索接口。组件测试用 fake 实现，避免任何真实网络请求。
abstract class BioDatabaseClient {
  Future<BioSearchResponse> search(String query, {BioSource? source});

  void dispose() {}
}

class BioDatabaseException implements Exception {
  const BioDatabaseException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// UniProt、RCSB PDB 与 PubMed 的轻量只读客户端。
///
/// 所有记录均来自本次 HTTP 响应；网络或解析失败只报告失败，不生成替代条目。
class BioDatabaseService implements BioDatabaseClient {
  BioDatabaseService({http.Client? httpClient, DateTime Function()? now})
    : _http = httpClient ?? http.Client(),
      _now = now ?? DateTime.now;

  final http.Client _http;
  final DateTime Function() _now;
  static const _timeout = Duration(seconds: 12);
  static const _limit = 6;

  @override
  Future<BioSearchResponse> search(String query, {BioSource? source}) async {
    final q = query.trim();
    if (q.isEmpty) {
      throw const BioDatabaseException('请输入要检索的蛋白质、结构或文献关键词。');
    }
    final sources = source == null ? BioSource.values : <BioSource>[source];
    final records = <BioKnowledgeRecord>[];
    final failures = <String>[];
    await Future.wait(
      sources.map((s) async {
        try {
          final result = await switch (s) {
            BioSource.uniprot => _searchUniProt(q),
            BioSource.pdb => _searchPdb(q),
            BioSource.pubmed => _searchPubMed(q),
          };
          records.addAll(result);
        } on BioDatabaseException catch (e) {
          failures.add('${s.label}：${e.message}');
        } on TimeoutException {
          failures.add('${s.label}：请求超时，请稍后重试。');
        } on http.ClientException catch (e) {
          failures.add('${s.label}：网络连接失败（${e.message}）。');
        } on FormatException {
          failures.add('${s.label}：返回格式无法解析，请稍后重试。');
        } catch (e) {
          failures.add('${s.label}：查询失败（$e）。');
        }
      }),
    );
    records.sort((a, b) {
      final bySource = a.source.index.compareTo(b.source.index);
      return bySource != 0 ? bySource : a.id.compareTo(b.id);
    });
    return BioSearchResponse(
      records: List.unmodifiable(records),
      failures: List.unmodifiable(failures),
      queriedAt: _now(),
    );
  }

  Future<List<BioKnowledgeRecord>> _searchUniProt(String query) async {
    final uri = Uri.https('rest.uniprot.org', '/uniprotkb/search', {
      'query': query,
      'format': 'json',
      'size': '$_limit',
      'fields': 'accession,id,protein_name,gene_names,organism_name,length',
    });
    final body = await _getJson(uri);
    return parseUniProtResults(body);
  }

  Future<List<BioKnowledgeRecord>> _searchPdb(String query) async {
    final searchUri = Uri.https('search.rcsb.org', '/rcsbsearch/v2/query');
    final searchResponse = await _http
        .post(
          searchUri,
          headers: const {
            'Content-Type': 'application/json',
            'Accept': 'application/json',
          },
          body: jsonEncode({
            'query': {
              'type': 'terminal',
              'service': 'full_text',
              'parameters': {'value': query},
            },
            'return_type': 'entry',
            'request_options': {
              'paginate': {'start': 0, 'rows': _limit},
            },
          }),
        )
        .timeout(_timeout);
    _checkStatus(searchResponse, 'RCSB PDB');
    final decoded = _decode(searchResponse);
    final ids = parsePdbSearchIds(decoded);
    if (ids.isEmpty) return const <BioKnowledgeRecord>[];

    // 每条详情独立容错：一个条目损坏不应抹掉同批其它真实记录。
    final details = await Future.wait(
      ids.map((id) async {
        try {
          final uri = Uri.https('data.rcsb.org', '/rest/v1/core/entry/$id');
          return parsePdbEntry(id, await _getJson(uri));
        } catch (_) {
          return null;
        }
      }),
    );
    final records = details.whereType<BioKnowledgeRecord>().toList(
      growable: false,
    );
    if (records.isEmpty) {
      throw const BioDatabaseException('条目详情读取失败，请稍后重试。');
    }
    return records;
  }

  Future<List<BioKnowledgeRecord>> _searchPubMed(String query) async {
    final searchUri = Uri.https(
      'eutils.ncbi.nlm.nih.gov',
      '/entrez/eutils/esearch.fcgi',
      {
        'db': 'pubmed',
        'term': query,
        'retmode': 'json',
        'retmax': '$_limit',
        'sort': 'relevance',
      },
    );
    final ids = parsePubMedSearchIds(await _getJson(searchUri));
    if (ids.isEmpty) return const <BioKnowledgeRecord>[];
    final summaryUri = Uri.https(
      'eutils.ncbi.nlm.nih.gov',
      '/entrez/eutils/esummary.fcgi',
      {'db': 'pubmed', 'id': ids.join(','), 'retmode': 'json'},
    );
    return parsePubMedSummaries(ids, await _getJson(summaryUri));
  }

  Future<Map<String, dynamic>> _getJson(Uri uri) async {
    final response = await _http
        .get(
          uri,
          // 非 const：UA 里的版本号来自 app_version 的运行时取值（三线各不同号）。
          headers: {
            'Accept': 'application/json',
            'User-Agent': 'BiologyGeneticsApp/$appVersionNumber',
          },
        )
        .timeout(_timeout);
    _checkStatus(response, uri.host);
    return _decode(response);
  }

  static void _checkStatus(http.Response response, String source) {
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw BioDatabaseException('服务返回 HTTP ${response.statusCode}。');
    }
  }

  static Map<String, dynamic> _decode(Object input) {
    late final String body;
    if (input is http.Response) {
      final bytes = input.bodyBytes;
      final isGzip = bytes.length >= 2 && bytes[0] == 0x1f && bytes[1] == 0x8b;
      body = isGzip ? utf8.decode(gzip.decode(bytes)) : input.body;
    } else {
      body = input as String;
    }
    final value = jsonDecode(body);
    if (value is! Map<String, dynamic>) {
      throw const FormatException('JSON 顶层不是对象');
    }
    return value;
  }

  @override
  void dispose() => _http.close();
}

List<BioKnowledgeRecord> parseUniProtResults(Map<String, dynamic> json) {
  final results = json['results'];
  if (results is! List) return const <BioKnowledgeRecord>[];
  final records = <BioKnowledgeRecord>[];
  for (final item in results.whereType<Map<String, dynamic>>()) {
    final id = item['primaryAccession']?.toString() ?? '';
    if (id.isEmpty) continue;
    final description = _map(item['proteinDescription']);
    final recommended = _map(description['recommendedName']);
    final fullName = _map(recommended['fullName']);
    final title =
        fullName['value']?.toString() ?? item['uniProtkbId']?.toString() ?? id;
    final genes = item['genes'];
    String? gene;
    if (genes is List && genes.isNotEmpty) {
      gene = _map(_map(genes.first)['geneName'])['value']?.toString();
    }
    final organism = _map(item['organism'])['scientificName']?.toString();
    final length = _map(item['sequence'])['length'];
    records.add(
      BioKnowledgeRecord(
        source: BioSource.uniprot,
        id: id,
        title: title,
        subtitle: <String>[
          if (gene != null && gene.isNotEmpty) gene,
          if (organism != null && organism.isNotEmpty) organism,
        ].join(' · '),
        summary: 'UniProt 蛋白质条目：查看序列、功能、基因与物种注释。',
        url: 'https://www.uniprot.org/uniprotkb/$id/entry',
        facts: <BioFact>[if (length != null) BioFact('序列长度', '$length aa')],
        keywords: <String>[?gene, ?organism],
      ),
    );
  }
  return records;
}

List<String> parsePdbSearchIds(Map<String, dynamic> json) {
  final resultSet = json['result_set'];
  if (resultSet is! List) return const <String>[];
  return resultSet
      .whereType<Map<String, dynamic>>()
      .map((item) => item['identifier']?.toString() ?? '')
      .where((id) => id.isNotEmpty)
      .toList(growable: false);
}

BioKnowledgeRecord? parsePdbEntry(String id, Map<String, dynamic> json) {
  final title = _map(json['struct'])['title']?.toString();
  if (title == null || title.isEmpty) return null;
  final methods = json['exptl'];
  final method = methods is List && methods.isNotEmpty
      ? _map(methods.first)['method']?.toString()
      : null;
  final resolutionValue = _map(json['rcsb_entry_info'])['resolution_combined'];
  double? resolution;
  if (resolutionValue is List && resolutionValue.isNotEmpty) {
    resolution = double.tryParse(resolutionValue.first.toString());
  } else {
    resolution = double.tryParse(resolutionValue?.toString() ?? '');
  }
  final release = _map(
    json['rcsb_accession_info'],
  )['initial_release_date']?.toString();
  final citation = _map(json['rcsb_primary_citation']);
  final pmid = citation['pdbx_database_id_PubMed']?.toString();
  final doi = citation['pdbx_database_id_DOI']?.toString();
  return BioKnowledgeRecord(
    source: BioSource.pdb,
    id: id.toUpperCase(),
    title: title,
    subtitle: <String>[
      ?method,
      if (resolution != null) '${resolution.toStringAsFixed(2)} Å',
      if (release != null && release.length >= 10) release.substring(0, 10),
    ].join(' · '),
    summary: 'RCSB PDB 三维结构条目：可继续查看实验方法、分子组成与结构模型。',
    url: 'https://www.rcsb.org/structure/${id.toUpperCase()}',
    facts: <BioFact>[
      if (method != null) BioFact('实验方法', method),
      if (resolution != null)
        BioFact('分辨率', '${resolution.toStringAsFixed(2)} Å'),
      if (pmid != null && pmid.isNotEmpty) BioFact('关联文献', 'PMID $pmid'),
      if (doi != null && doi.isNotEmpty) BioFact('DOI', doi),
    ],
    keywords: <String>[?method],
  );
}

List<String> parsePubMedSearchIds(Map<String, dynamic> json) {
  final result = _map(json['esearchresult']);
  final ids = result['idlist'];
  if (ids is! List) return const <String>[];
  return ids.map((id) => id.toString()).where((id) => id.isNotEmpty).toList();
}

List<BioKnowledgeRecord> parsePubMedSummaries(
  List<String> requestedIds,
  Map<String, dynamic> json,
) {
  final result = _map(json['result']);
  final records = <BioKnowledgeRecord>[];
  for (final id in requestedIds) {
    final item = _map(result[id]);
    if (item.isEmpty) continue;
    final title = item['title']?.toString() ?? '';
    if (title.isEmpty) continue;
    final authors = item['authors'];
    final firstAuthor = authors is List && authors.isNotEmpty
        ? _map(authors.first)['name']?.toString()
        : null;
    final journal =
        item['fulljournalname']?.toString() ?? item['source']?.toString();
    final date = item['pubdate']?.toString();
    final ids = item['articleids'];
    String? doi;
    String? pmcid;
    if (ids is List) {
      for (final raw in ids.whereType<Map<String, dynamic>>()) {
        final type = raw['idtype']?.toString();
        if (type == 'doi') doi = raw['value']?.toString();
        if (type == 'pmc') pmcid = raw['value']?.toString();
      }
    }
    records.add(
      BioKnowledgeRecord(
        source: BioSource.pubmed,
        id: id,
        title: title,
        subtitle: <String>[
          if (firstAuthor != null && firstAuthor.isNotEmpty) '$firstAuthor 等',
          if (journal != null && journal.isNotEmpty) journal,
          if (date != null && date.isNotEmpty) date,
        ].join(' · '),
        summary: 'PubMed 文献条目：阅读结论前请核对摘要、原文与后续研究。',
        url: 'https://pubmed.ncbi.nlm.nih.gov/$id/',
        facts: <BioFact>[
          BioFact('PMID', id),
          if (pmcid != null && pmcid.isNotEmpty) BioFact('PMCID', pmcid),
          if (doi != null && doi.isNotEmpty) BioFact('DOI', doi),
        ],
        keywords: <String>[?journal],
      ),
    );
  }
  return records;
}

Map<String, dynamic> _map(Object? value) =>
    value is Map<String, dynamic> ? value : const <String, dynamic>{};
