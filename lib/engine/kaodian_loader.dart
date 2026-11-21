// kaodian_loader.dart —— 考点库加载与模型
//
// 数据来源：data/kaodian_compilation.json（rootBundle 加载）。
// JSON 结构：{ name, version, items: [ { id, name, content,
//   typical_ratio, source } ] }
// 用途：知识图谱页「考点速查」——图谱给结构，考点给应试口径。

import 'dart:convert';

/// 一条考点记录。
class KaodianItem {
  final String id;
  final String name;
  final String content;
  final String typicalRatio;
  final String source;

  const KaodianItem({
    required this.id,
    required this.name,
    required this.content,
    required this.typicalRatio,
    required this.source,
  });

  factory KaodianItem.fromJson(Map<String, dynamic> json) {
    String s(String key) => (json[key] ?? '').toString();
    return KaodianItem(
      id: s('id'),
      name: s('name'),
      content: s('content'),
      typicalRatio: s('typical_ratio'),
      source: s('source'),
    );
  }
}

/// 考点库。
class KaodianBank {
  final String name;
  final List<KaodianItem> items;

  const KaodianBank({required this.name, required this.items});

  /// 关键词过滤（名称 / 内容 / 比例）。
  List<KaodianItem> search(String query) {
    // 返回副本：items 是 final 但可变，直接把内部列表交给调用方，一旦对方
    // 排序/删除就会污染题库本体（审查发现的潜在共享可变状态）。
    if (query.isEmpty) return List<KaodianItem>.of(items);
    final q = query.toLowerCase();
    return items
        .where((e) =>
            e.name.toLowerCase().contains(q) ||
            e.content.toLowerCase().contains(q) ||
            e.typicalRatio.toLowerCase().contains(q))
        .toList();
  }
}

/// 解析 data/kaodian_compilation.json 的原始文本。容错：异常返回空库。
KaodianBank parseKaodianJson(String raw) {
  try {
    final decoded = json.decode(raw);
    if (decoded is! Map<String, dynamic>) {
      return const KaodianBank(name: '', items: []);
    }
    final name = (decoded['name'] ?? '').toString();
    final rawItems = decoded['items'];
    if (rawItems is! List) return KaodianBank(name: name, items: const []);
    return KaodianBank(
      name: name,
      items: [
        for (final e in rawItems)
          if (e is Map<String, dynamic>) KaodianItem.fromJson(e),
      ],
    );
  } on FormatException {
    return const KaodianBank(name: '', items: []);
  }
}
