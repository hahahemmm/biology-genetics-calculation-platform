// syllabus_loader.dart —— 考纲数据加载（纯 Dart）
//
// 解析 data/syllabus_gaokao.json（v2.0）：
//   - 条目以课程标准官方编号（code）为骨架
//   - 覆盖关系优先读数据内显式声明的 covered_by（可信、可控）；
//     未声明 covered_by 字段时回退到能力关键词匹配（向后兼容旧数据）
//   - partial: true 表示「部分覆盖」（如 3.3.5 只覆盖合子致死情形）
//   - exam 段解析辽宁新高考考情速览
//
// 覆盖结果仅表示「本软件功能可支撑该条目的练习与推导」，
// 不构成教研意义上的完整覆盖，UI 中须如实标注。

import 'dart:convert';

/// 单条考纲条目。
class SyllabusItem {
  final String id;
  final String code; // 课程标准官方编号，如 3.2.3（概念级条目可为「概念4」）
  final String module;
  final String kaodian;
  final String level;
  final String note;
  final String source;

  /// 数据内显式声明的覆盖能力；null = 未声明（回退关键词匹配）。
  final List<String>? coveredByList;

  /// 部分覆盖标记（如只覆盖该条目的部分情形）。
  final bool partial;

  const SyllabusItem({
    required this.id,
    this.code = '',
    required this.module,
    required this.kaodian,
    required this.level,
    this.note = '',
    this.source = '',
    this.coveredByList,
    this.partial = false,
  });
}

/// 考情速览（exam 段）。
class ExamInfo {
  final String title;
  final String duration;
  final String totalScore;
  final String paperType;
  final String structure;
  final String geneticsWeight;
  final String note;
  final String source;

  const ExamInfo({
    this.title = '',
    this.duration = '',
    this.totalScore = '',
    this.paperType = '',
    this.structure = '',
    this.geneticsWeight = '',
    this.note = '',
    this.source = '',
  });

  bool get isEmpty => title.isEmpty && structure.isEmpty;
}

/// 考纲覆盖结果：条目 + 每条被哪些能力覆盖。
class SyllabusCoverage {
  final String name;
  final List<SyllabusItem> items;

  /// itemId → 覆盖能力描述（如「伴性遗传、系谱推断」）；不含部分覆盖条目。
  final Map<String, String> coveredBy;

  /// 部分覆盖的条目 id 集合。
  final Set<String> partialIds;

  /// 考情速览（无 exam 段时为 isEmpty）。
  final ExamInfo exam;

  const SyllabusCoverage({
    required this.name,
    required this.items,
    required this.coveredBy,
    this.partialIds = const {},
    this.exam = const ExamInfo(),
  });

  int get coveredCount => coveredBy.length;
  int get partialCount => partialIds.length;

  /// 按模块分组（保持首次出现顺序）。
  Map<String, List<SyllabusItem>> get byModule {
    final out = <String, List<SyllabusItem>>{};
    for (final item in items) {
      out.putIfAbsent(item.module, () => []).add(item);
    }
    return out;
  }
}

/// 本软件已实现能力 → 用于覆盖匹配的关键词（未显式声明 covered_by 时的回退）。
const _capabilities = <String, List<String>>{
  '双基因 9331 计算器': ['自由组合', '9:3:3:1', '9331', '两对', '多对'],
  '单基因杂交': ['分离定律', '测交', '回交', '一对相对性状'],
  '伴性遗传': ['伴性', '伴X', '性染色体', '性别相关联'],
  '致死条件': ['致死'],
  '9331 变式推导': ['变式', '9:7', '15:1', '修饰'],
  '数量性状（累加效应）': ['数量性状', '累加'],
  '系谱推断': ['系谱', '遗传病', '系谱图'],
  '自由交配': ['自由交配', '随机交配', '哈代', '基因频率'],
  '配子枚举': ['配子'],
  '连锁互换': ['连锁', '交叉互换', '交换值', '基因重组'],
};

/// 解析考纲 JSON 并计算覆盖度。任何解析失败都返回空结果，不抛异常。
SyllabusCoverage parseSyllabusCoverage(String jsonText) {
  try {
    return _parse(jsonText);
  } catch (_) {
    return const SyllabusCoverage(name: '', items: [], coveredBy: {});
  }
}

SyllabusCoverage _parse(String jsonText) {
  final map = jsonDecode(jsonText);
  if (map is! Map<String, dynamic>) {
    throw const FormatException('考纲 JSON 顶层必须是对象');
  }
  final items = <SyllabusItem>[];
  final rawItems = map['items'];
  if (rawItems is! List) {
    throw const FormatException('考纲 JSON 缺少 items 数组');
  }
  for (final e in rawItems) {
    if (e is! Map<String, dynamic>) continue;
    List<String>? coveredByList;
    final rawCov = e['covered_by'];
    if (rawCov is List) {
      coveredByList = rawCov.map((x) => x.toString()).toList();
    }
    items.add(SyllabusItem(
      id: (e['id'] ?? '').toString(),
      code: (e['code'] ?? '').toString(),
      module: (e['module'] ?? '').toString(),
      kaodian: (e['kaodian'] ?? '').toString(),
      level: (e['level'] ?? '').toString(),
      note: (e['note'] ?? '').toString(),
      source: (e['source'] ?? '').toString(),
      coveredByList: coveredByList,
      partial: e['partial'] == true,
    ));
  }

  // 覆盖关系：显式声明优先；未声明回退关键词匹配
  final coveredBy = <String, String>{};
  final partialIds = <String>{};
  for (final item in items) {
    if (item.coveredByList != null) {
      if (item.coveredByList!.isNotEmpty) {
        if (item.partial) {
          partialIds.add(item.id);
        } else {
          coveredBy[item.id] = item.coveredByList!.join('、');
        }
      }
      continue; // 显式声明（含空数组=明确未覆盖），不做关键词匹配
    }
    final haystack = '${item.kaodian} ${item.note}';
    final hits = <String>[
      for (final entry in _capabilities.entries)
        if (entry.value.any(haystack.contains)) entry.key,
    ];
    if (hits.isNotEmpty) coveredBy[item.id] = hits.join('、');
  }

  // 考情速览
  var exam = const ExamInfo();
  final rawExam = map['exam'];
  if (rawExam is Map<String, dynamic>) {
    exam = ExamInfo(
      title: (rawExam['title'] ?? '').toString(),
      duration: (rawExam['duration'] ?? '').toString(),
      totalScore: (rawExam['total_score'] ?? '').toString(),
      paperType: (rawExam['paper_type'] ?? '').toString(),
      structure: (rawExam['structure'] ?? '').toString(),
      geneticsWeight: (rawExam['genetics_weight'] ?? '').toString(),
      note: (rawExam['note'] ?? '').toString(),
      source: (rawExam['source'] ?? '').toString(),
    );
  }

  return SyllabusCoverage(
    name: (map['name'] ?? '').toString(),
    items: items,
    coveredBy: coveredBy,
    partialIds: partialIds,
    exam: exam,
  );
}
