/// 生物知识库的统一记录模型。
///
/// UniProt、RCSB PDB 与 PubMed 的原始字段不直接漏到界面层；内置精选与
/// 实时查询都先规范成同一结构，避免不同来源各自演一套卡片。
library;

enum BioSource { uniprot, pdb, pubmed }

extension BioSourceLabel on BioSource {
  String get label => switch (this) {
    BioSource.uniprot => 'UniProt',
    BioSource.pdb => 'RCSB PDB',
    BioSource.pubmed => 'PubMed',
  };

  String get kind => switch (this) {
    BioSource.uniprot => '蛋白质序列与功能',
    BioSource.pdb => '三维结构',
    BioSource.pubmed => '原始研究文献',
  };
}

class BioFact {
  const BioFact(this.label, this.value);

  final String label;
  final String value;
}

class BioKnowledgeRecord {
  const BioKnowledgeRecord({
    required this.source,
    required this.id,
    required this.title,
    required this.subtitle,
    required this.summary,
    required this.url,
    this.facts = const <BioFact>[],
    this.keywords = const <String>[],
    this.caution,
  });

  final BioSource source;
  final String id;
  final String title;
  final String subtitle;
  final String summary;
  final String url;
  final List<BioFact> facts;
  final List<String> keywords;

  /// 容易误读的结构或文献边界，必须在卡片上显式呈现。
  final String? caution;

  bool matches(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return true;
    final haystack = <String>[
      source.label,
      source.kind,
      id,
      title,
      subtitle,
      summary,
      ...keywords,
      ...facts.expand((f) => <String>[f.label, f.value]),
      // 教学边界常含“不能用于辨认 X”等否定说明，不应把条目误归为 X 主题。
    ].join('\n').toLowerCase();
    return q.split(RegExp(r'\s+')).every(haystack.contains);
  }
}

class BioSearchResponse {
  const BioSearchResponse({
    required this.records,
    required this.failures,
    required this.queriedAt,
  });

  final List<BioKnowledgeRecord> records;

  /// 单库失败不清空其它库的真实结果；每项都是可直接展示的中文说明。
  final List<String> failures;
  final DateTime queriedAt;
}
