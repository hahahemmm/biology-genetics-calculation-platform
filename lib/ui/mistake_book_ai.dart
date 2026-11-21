// mistake_book_ai.dart —— 错题本 AI 主动整理（v2.12 Wave 2 / Worker B）
//
// 复用 Wave 1 既有 `AiClient`（lib/services/ai_client.dart），不新建客户端。
// 复用 `AiSettingsStore.load()` 读当前用户的 ApiConfig（用户在设置页填的）。
//
// 三套 prompt 模板：
//   1. `buildSinglePrompt` —— 单条错题归类错因 + 提炼易错点
//   2. `buildBatchPrompt` —— 批量整理（循环套单条 prompt，集中一次发）
//   3. `buildOverviewPrompt` —— 全部错题生成总览（错误模式聚类）
//
// 输出格式：要求 AI 严格返回 JSON（用 `parseMistakeAnalysis` 解析，容错：
// 兼容代码块包裹、夹带解释文字、字段缺失）。

import 'dart:convert';

import '../services/ai_client.dart';
import '../pages/settings_page.dart' show AiSettingsStore;
import '../state/mistake_book.dart';
import 'image_pick.dart';

/// 单条 AI 整理结果。
class MistakeAiAnalysis {
  /// 错因归类（一句话，AI 客观判定，可能与用户自评不同）。
  final String summary;

  /// 易错点（多条，每行一条；解析时按换行 / 列表项拆分）。
  final List<String> pitfalls;

  /// v2.19.62：AI 判定的**结构化错因** = [MistakeCauseKey] 的 `name`
  /// （词表内的合法值），或 null（旧模型输出没带 / 解析未命中白名单）。
  /// ⛔ 这里只允许词表内取值——解析时走 [MistakeCauseKey.fromName] 白名单，
  /// 绝不把模型自由文本写进这个结构化字段。
  final String? causeKey;

  const MistakeAiAnalysis({
    required this.summary,
    required this.pitfalls,
    this.causeKey,
  });

  bool get isEmpty => summary.isEmpty && pitfalls.isEmpty && causeKey == null;

  /// 序列化为 MistakeEntry 字段。
  /// - summary → aiSummary
  /// - pitfalls → aiPitfalls
  /// - causeKey → causeKey（v2.19.62）
  Map<String, dynamic> toMap() => {
        'aiSummary': summary,
        'aiPitfalls': pitfalls,
        'causeKey': causeKey,
      };
}

/// AI 整理总览结果。
class MistakeAiOverview {
  /// 总览文本（多段：模式聚类 + 重点提示 + 复习建议）。
  final String text;

  const MistakeAiOverview({required this.text});
}

/// 拍照识别结果：对齐「添加错题」表单的四个字段（stem / userAnswer /
/// correctAnswer / subjectArea）。
///
/// 与 [MistakeAiAnalysis]（错因归类）互补：本类只做「图片 → 表单回填」。
class MistakePhotoAnalysis {
  /// 题目摘要。
  final String stem;

  /// 错误答案（照片上「我的答案 / 作答」等标注）。
  final String userAnswer;

  /// 正确答案（照片上「答案 / 参考答案」等标注）。
  final String correctAnswer;

  /// 关联考点。
  final String subjectArea;

  const MistakePhotoAnalysis({
    required this.stem,
    required this.userAnswer,
    required this.correctAnswer,
    required this.subjectArea,
  });

  /// 四字段全空 = 什么都没识别出来（视为解析失败，不回填）。
  bool get isEmpty =>
      stem.isEmpty &&
      userAnswer.isEmpty &&
      correctAnswer.isEmpty &&
      subjectArea.isEmpty;
}

/// v2.19.62：AI 整理 prompt 里的**错因闭集词表**——六个 key 的 name +
/// 中文释义，逐字由 [MistakeCauseKey.values] 生成。
///
/// ⛔ 单一真相：枚举改了 prompt 口径随之改，不会出现「枚举加了新类、
/// prompt 忘了同步」的漂移。模型只能从这六个 name 里选一个填 `causeKey`。
String get causeKeyVocabularyText => [
      for (final k in MistakeCauseKey.values) '${k.name}（${k.displayName}）',
    ].join(' / ');

/// prompt 模板集合。
///
/// 1. 单条：拼出 1 道题 + 答案对照，让 AI 输出 JSON
///    `{summary, pitfalls, causeKey}`（v2.19.62 起含结构化错因）。
/// 2. 批量：把多条错题拼成列表，让 AI 对每条各出一段，输出 JSON 数组。
/// 3. 总览：所有错题摘要列表 + 自评错误类型，让 AI 总结「你最常错的
///    模式 / 重点提示 / 复习建议」。
class MistakeBookAi {
  /// 测试用：注入发送器（与 AiChatController.debugSender 同款套路）。
  /// 非 null 时 `analyzeSingle` / `analyzeAll` / `buildOverview` 走它而非
  /// 真实网络。让测试可以断言 prompt 拼装 / 解析逻辑而不依赖外部 HTTP。
  static Future<AiResult> Function(List<AiMessage> messages)? debugSender;

  /// 单条 prompt：归类错因 + 提炼易错点。
  ///
  /// 输出：要求 AI 返回严格 JSON
  /// `{"summary": "...", "pitfalls": [...], "causeKey": "..."}`。
  static String buildSinglePrompt(MistakeEntry e) {
    return '你是一名高中生物错题分析助手。\n'
        '用户提交了一道错题，请：\n'
        '  1. 客观判定错因（不是用户自评的，是基于答案对照给出的最可能的根因）。\n'
        '  2. 提炼 1~3 条易错点（每条一句话，给出下次避坑的具体动作）。\n'
        '  3. 从下面的错因词表里选**一个** key 填进 causeKey（拿不准就给 unclassified）。\n'
        '只输出一个 JSON 对象，不要输出任何其他文字、不要加代码块标记：\n'
        '{"summary":"错因一句话（≤60字）","pitfalls":["易错点1","易错点2","易错点3"],'
        '"causeKey":"misappliedVariant"}\n'
        '【错因词表 causeKey】只能选以下之一（拿不准就给 unclassified）：'
        '$causeKeyVocabularyText\n\n'
        '【题目】\n${e.stem}\n\n'
        '【用户答案】\n${e.userAnswer}\n\n'
        '【正确答案】\n${e.correctAnswer}\n\n'
        '【用户自评错误类型】\n${e.errorType.displayName}\n\n'
        '【关联考点】\n${e.subjectArea.isEmpty ? "（未填）" : e.subjectArea}\n\n'
        // v2.13+ 教材对齐：考点词表锚定人教版必修2 章名——AI 归一
        // subjectArea 用统一词表，错题本「考点」筛选才不会碎片化
        // （否则同一内容会出现「孟德尔」「分离定律」「遗传因子」多种写法）。
        '【考点词表】请把关联考点归一到以下课本章节名之一'
        '（高中生物必修2，无对应项时选最接近的）：\n'
        '分离定律 / 自由组合定律 / 减数分裂与受精作用 / 基因在染色体上 / '
        '伴性遗传 / DNA的结构与复制 / 基因的表达 / 基因突变与重组 / '
        '染色体变异 / 人类遗传病 / 种群基因频率与进化 / 其他';
  }

  /// 批量 prompt：对每条错题独立做"单条整理"。
  ///
  /// 输出：JSON 数组 `[{"id": "m_...", "summary": "...", "pitfalls": [...]}, ...]`
  /// 顺序与输入的 entries 严格对应。
  static String buildBatchPrompt(List<MistakeEntry> entries) {
    final sb = StringBuffer()
      ..writeln('你是一名高中生物错题分析助手。下面有 ${entries.length} 道错题，'
          '请按顺序对每道题独立做错因归类 + 易错点提炼。')
      ..writeln('只输出一个 JSON 数组，不要输出任何其他文字、不要加代码块标记：')
      ..writeln(
          '[{"id":"m_...","summary":"错因一句话（≤60字）","pitfalls":["易错点1","易错点2"],'
          '"causeKey":"misappliedVariant"}, ...]')
      ..writeln('每条都要从下面的错因词表里选**一个** key 填进 causeKey'
          '（拿不准就给 unclassified）：$causeKeyVocabularyText')
      ..writeln('关联考点请归一到课本章节名（高中生物必修2 词表：分离定律 / '
          '自由组合定律 / 减数分裂与受精作用 / 基因在染色体上 / 伴性遗传 / '
          'DNA的结构与复制 / 基因的表达 / 基因突变与重组 / 染色体变异 / '
          '人类遗传病 / 种群基因频率与进化 / 其他），与单条 prompt 词表一致。')
      ..writeln()
      ..writeln('【错题列表】');
    for (var i = 0; i < entries.length; i++) {
      final e = entries[i];
      sb
        ..writeln('--- 第 ${i + 1} 条 ---')
        ..writeln('id=${e.id}')
        ..writeln('题目：${e.stem}')
        ..writeln('用户答案：${e.userAnswer}')
        ..writeln('正确答案：${e.correctAnswer}')
        ..writeln('自评错误类型：${e.errorType.displayName}')
        ..writeln('关联考点：${e.subjectArea.isEmpty ? "（未填）" : e.subjectArea}')
        ..writeln();
    }
    return sb.toString();
  }

  /// 总览 prompt：基于所有错题生成模式聚类。
  ///
  /// 输出：JSON `{"text": "总览文本（3~5 段，每段一行）"}`。
  static String buildOverviewPrompt(List<MistakeEntry> entries) {
    // v2.13+：复习状态分布进总览——AI 的建议可结合「还有多少欠账」
    // （如「已掌握占比高但未复习 N 道积压」）。
    final mastered = entries
        .where((e) => e.reviewStatus == MistakeReviewStatus.mastered)
        .length;
    final reviewing = entries
        .where((e) => e.reviewStatus == MistakeReviewStatus.reviewing)
        .length;
    final unreviewed = entries
        .where((e) => e.reviewStatus == MistakeReviewStatus.unreviewed)
        .length;
    // R5 老师走查 #10：总览补「今日到期」——三态计数是存量，到期是
    // 行动信号（AI 建议可明确「今天先清这 N 道」）。
    final dueToday = MistakeBook.instance.dueEntries().length;
    final sb = StringBuffer()
      ..writeln('你是一名高中生物错题复盘助手。下面是用户的 ${entries.length} 道错题'
          '摘要（含自评错误类型）。请基于这些错题做模式聚类，输出 3~5 段总览：')
      ..writeln('  1. 最常错的 1~2 个模式（如「9331 变式识别」「伴 X 隐性判断」）')
      ..writeln('  2. 错误类型分布观察（如「概念错占比最高，提示对 X 章节基础不牢」）')
      ..writeln('  3. 关联考点重复出现的薄弱点')
      ..writeln('  4. 给用户的具体复习建议（1~2 条）——可结合复习进度'
          '（已掌握 $mastered / 复习中 $reviewing / 未复习 $unreviewed；'
          '今日到期 $dueToday 道，建议优先安排）')
      ..writeln(
          '只输出一个 JSON 对象，不要输出任何其他文字、不要加代码块标记：')
      ..writeln('{"text":"第1段\\n第2段\\n第3段\\n第4段"}')
      ..writeln()
      ..writeln('【错题摘要列表】');
    for (var i = 0; i < entries.length; i++) {
      final e = entries[i];
      sb
        ..writeln(
            '${i + 1}. [${e.errorType.displayName}] ${e.subjectArea.isEmpty ? "（无考点）" : e.subjectArea}：${e.stem}')
        ..writeln(
            '   错答 ${e.userAnswer} → 正答 ${e.correctAnswer}');
    }
    return sb.toString();
  }

  /// 单条错题 AI 整理。
  ///
  /// 返回 `null` 表示 AI 未配置 / 网络失败 / 解析失败。调用方应已有
  /// "未配置提示" 兜底（页面层做 SnackBar）。
  static Future<MistakeAiAnalysis?> analyzeSingle(MistakeEntry e) async {
    final res = await _send([
      const AiMessage('system',
          '你是高中生物错题分析助手，输出严格 JSON。'),
      AiMessage('user', buildSinglePrompt(e)),
    ]);
    if (!res.ok) return null;
    return parseMistakeAnalysis(res.content);
  }

  /// 拍照识别 prompt：从题目图片提取表单四字段。
  ///
  /// 输出 JSON `{"stem","userAnswer","correctAnswer","subjectArea"}`，
  /// 识别不出的字段填空字符串（⛔ 不编造）。
  static String buildPhotoPrompt() {
    return '你是一名高中生物错题录入助手。用户拍了一道题的照片（可能含题干、'
        '学生的错误作答、正确答案、考点标注），请提取以下四个字段回填录入表单：\n'
        '  1. stem 题目摘要：一句话概括这道题考什么（≤80 字）。\n'
        '  2. userAnswer 错误答案：照片上「我的答案 / 作答 / 错答」等标注的内容。\n'
        '  3. correctAnswer 正确答案：照片上「答案 / 正确答案 / 参考答案」等标注的内容。\n'
        '  4. subjectArea 关联考点：归一到人教版必修2 章节名之一（分离定律 / '
        '自由组合定律 / 减数分裂与受精作用 / 基因在染色体上 / 伴性遗传 / '
        'DNA的结构与复制 / 基因的表达 / 基因突变与重组 / 染色体变异 / '
        '人类遗传病 / 种群基因频率与进化 / 其他）。\n'
        '识别不出的字段一律填空字符串 ""，绝对不要编造内容。\n'
        '只输出一个 JSON 对象，不要输出任何其他文字、不要加代码块标记：\n'
        '{"stem":"...","userAnswer":"...","correctAnswer":"...","subjectArea":"..."}';
  }

  /// 拍照识别：题目图片 → 表单四字段（[MistakePhotoAnalysis]）。
  ///
  /// 返回 (结果, 失败原因)：成功时失败原因为 null；失败（未配置 AI /
  /// 请求失败 / 返回非法 JSON）时结果为 null、失败原因是可读中文提示，
  /// 调用方直接展示，不要求用户看懂英文技术细节。
  static Future<(MistakePhotoAnalysis?, String?)> analyzePhoto(
      PickedImage image) async {
    final res = await _send([
      const AiMessage('system',
          '你是高中生物错题录入助手，输出严格 JSON。'),
      AiMessage('user', buildPhotoPrompt(),
          imagePngBase64: base64Encode(image.bytes),
          imageMimeType: _imageMime(image.extension)),
    ]);
    if (!res.ok) return (null, res.error ?? 'AI 请求失败，请稍后重试。');
    final a = parsePhotoAnalysis(res.content);
    if (a == null) return (null, 'AI 返回的内容不是有效 JSON，请重试。');
    return (a, null);
  }

  /// 按扩展名猜 MIME（认不出按 png 兜底）。
  static String _imageMime(String ext) {
    switch (ext.toLowerCase()) {
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'webp':
        return 'image/webp';
      case 'gif':
        return 'image/gif';
      case 'bmp':
        return 'image/bmp';
      default:
        return 'image/png';
    }
  }

  /// 批量整理（透传失败原因版）：返回带失败原因的完整结果。
  ///
  /// v2.13 R3 P1-B3：旧 `analyzeAll` 把 `res.error`（未配置 AI /
  /// 网络失败 / HTTP 错误）丢掉，页面只能凭成功数猜结果——全失败
  /// 时错误地显示「批量整理完成：0 / N」假成功。本方法保留失败原因，
  /// 页面据此弹「批量整理失败（0/N）」+ 失败原因。
  static Future<BatchOrganizeOutcome> analyzeAllDetailed(
      List<MistakeEntry> entries) async {
    if (entries.isEmpty) {
      return BatchOrganizeOutcome(total: 0, successes: const {});
    }
    final res = await _send([
      const AiMessage('system',
          '你是高中生物错题分析助手，输出严格 JSON 数组。'),
      AiMessage('user', buildBatchPrompt(entries)),
    ]);
    if (!res.ok) {
      return BatchOrganizeOutcome(
        total: entries.length,
        successes: const {},
        failureReason: res.error ?? 'AI 请求失败',
      );
    }
    return BatchOrganizeOutcome(
      total: entries.length,
      successes: parseMistakeBatch(res.content, entries),
    );
  }

  /// 批量整理：返回 id → analysis 的映射（解析失败的 id 不在结果中）。
  ///
  /// 调用方拿到结果后遍历 entries，用 `applyAiAnalysis(id, ...)` 写入。
  /// 同时把 totalOverview 写回每条 entry 的 aiOverview 字段（如果调用方
  /// 传了 `overviewText`）。
  ///
  /// 保留旧签名（兼容既有调用方 / 测试）；需要失败原因时改用
  /// `analyzeAllDetailed`（v2.13 R3 P1-B3）。
  static Future<Map<String, MistakeAiAnalysis>> analyzeAll(
      List<MistakeEntry> entries) async {
    return (await analyzeAllDetailed(entries)).successes;
  }

  /// 整理总览。
  static Future<MistakeAiOverview?> buildOverview(
      List<MistakeEntry> entries) async {
    if (entries.isEmpty) return null;
    final res = await _send([
      const AiMessage('system',
          '你是高中生物错题复盘助手，输出严格 JSON。'),
      AiMessage('user', buildOverviewPrompt(entries)),
    ]);
    if (!res.ok) return null;
    return parseMistakeOverview(res.content);
  }

  /// 内部发送：优先 debugSender 注入；否则走 AiSettingsStore + AiClient。
  static Future<AiResult> _send(List<AiMessage> msgs) async {
    final sender = debugSender;
    if (sender != null) return sender(msgs);
    final config = await AiSettingsStore.load();
    if (!config.isConfigured) {
      return const AiResult.fail('未配置 AI：请先在「设置」页填入 BaseURL 和 API Key。');
    }
    final client = AiClient(config);
    return client.chat(msgs);
  }

  // ---- 解析器（公开，便于测试 + 其他模块复用） ----

  /// 解析单条分析结果。容错：代码块包裹 / 夹带文字 / 字段缺失。
  static MistakeAiAnalysis? parseMistakeAnalysis(String content) {
    final j = _extractJsonObject(content);
    if (j == null) return null;
    final summary = (j['summary']?.toString() ?? '').trim();
    final rawPits = j['pitfalls'];
    final pits = <String>[];
    if (rawPits is List) {
      for (final p in rawPits) {
        final s = p?.toString().trim() ?? '';
        if (s.isNotEmpty) pits.add(s);
      }
    } else if (rawPits is String) {
      // 兜底：AI 把数组写成多行字符串
      for (final line in rawPits.split(RegExp(r'[\n;；]'))) {
        final s = line.trim().replaceFirst(RegExp(r'^[-•·\d.\s]+'), '');
        if (s.isNotEmpty) pits.add(s);
      }
    }
    // v2.19.62：causeKey 白名单过滤——只认词表内的 name；缺键（旧模型输出）
    // / 空 / 词表外的自由文本一律 null（⛔ 绝不把模型自由文本写进这个
    // 结构化字段）。null 会在雷达「AI 判」视图里计入 unclassified 桶，
    // 但**不**由解析器代填成 unclassified。
    final causeKey =
        MistakeCauseKey.fromName(j['causeKey']?.toString())?.name;
    if (summary.isEmpty && pits.isEmpty && causeKey == null) return null;
    return MistakeAiAnalysis(
        summary: summary, pitfalls: pits, causeKey: causeKey);
  }

  /// 解析拍照识别结果。容错：代码块包裹 / 夹带文字 / 字段缺失（缺失按
  /// 空字符串）。四字段全空视为解析失败（返回 null，调用方提示重试）。
  static MistakePhotoAnalysis? parsePhotoAnalysis(String content) {
    final j = _extractJsonObject(content);
    if (j == null) return null;
    String field(String k) => (j[k]?.toString() ?? '').trim();
    final a = MistakePhotoAnalysis(
      stem: field('stem'),
      userAnswer: field('userAnswer'),
      correctAnswer: field('correctAnswer'),
      subjectArea: field('subjectArea'),
    );
    return a.isEmpty ? null : a;
  }

  /// 解析批量分析结果。返回 id → analysis；解析失败的 id 不在结果中。
  static Map<String, MistakeAiAnalysis> parseMistakeBatch(
      String content, List<MistakeEntry> entries) {
    final j = _extractJsonArray(content);
    if (j == null) return const {};
    final result = <String, MistakeAiAnalysis>{};
    for (final item in j) {
      if (item is! Map) continue;
      final id = item['id']?.toString();
      if (id == null || id.isEmpty) continue;
      final a = parseMistakeAnalysis(_mapToJsonString(item));
      if (a == null || a.isEmpty) continue;
      // 仅保留 entries 里实际存在的 id（防止 AI 幻觉）
      if (entries.any((e) => e.id == id)) {
        result[id] = a;
      }
    }
    return result;
  }

  /// 解析总览。
  static MistakeAiOverview? parseMistakeOverview(String content) {
    final j = _extractJsonObject(content);
    if (j == null) return null;
    final text = (j['text']?.toString() ?? '').trim();
    if (text.isEmpty) return null;
    return MistakeAiOverview(text: text);
  }

  // ---- 内部：从 AI 输出中抠出 JSON 对象 / 数组 ----

  /// 从字符串中抠出第一个完整的 JSON 对象 {...}（容忍代码块包裹 / 夹带文字）。
  /// 简单手写括号匹配——不引入额外依赖。
  static Map<String, dynamic>? _extractJsonObject(String content) {
    final start = content.indexOf('{');
    if (start < 0) return null;
    var depth = 0;
    var inStr = false;
    var escape = false;
    for (var i = start; i < content.length; i++) {
      final c = content[i];
      if (escape) {
        escape = false;
        continue;
      }
      if (c == r'\') {
        escape = true;
        continue;
      }
      if (c == '"') {
        inStr = !inStr;
        continue;
      }
      if (inStr) continue;
      if (c == '{') depth++;
      if (c == '}') {
        depth--;
        if (depth == 0) {
          final sub = content.substring(start, i + 1);
          try {
            final v = jsonDecode(sub);
            return v is Map ? v.cast<String, dynamic>() : null;
          } catch (_) {
            return null;
          }
        }
      }
    }
    return null;
  }

  /// 抠出第一个完整的 JSON 数组 [...]。
  static List<dynamic>? _extractJsonArray(String content) {
    final start = content.indexOf('[');
    if (start < 0) return null;
    var depth = 0;
    var inStr = false;
    var escape = false;
    for (var i = start; i < content.length; i++) {
      final c = content[i];
      if (escape) {
        escape = false;
        continue;
      }
      if (c == r'\') {
        escape = true;
        continue;
      }
      if (c == '"') {
        inStr = !inStr;
        continue;
      }
      if (inStr) continue;
      if (c == '[') depth++;
      if (c == ']') {
        depth--;
        if (depth == 0) {
          final sub = content.substring(start, i + 1);
          try {
            final v = jsonDecode(sub);
            return v is List ? v : null;
          } catch (_) {
            return null;
          }
        }
      }
    }
    return null;
  }

  /// 把 Map 重新序列化回 JSON 字符串（parseMistakeBatch 用）。
  /// v2.19.62：带上 causeKey——否则批量解析时该键会在这一步被丢掉。
  static String _mapToJsonString(Map item) =>
      '{"summary":${jsonEncode(item['summary'])}'
      ',"pitfalls":${jsonEncode(item['pitfalls'])}'
      ',"causeKey":${jsonEncode(item['causeKey'])}}';
}
