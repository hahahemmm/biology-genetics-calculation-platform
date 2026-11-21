// mistake_book.dart —— 错题本（v2.12 Wave 2 / Worker B）
//
// 设计哲学（用户口述 2026-09-05 沉淀）：
//   软件是「用户输入数据 → 软件计算/处理 → 呈现完整流程/逻辑」的运行框架，
//   不是内置题库 / 刷题库 / 错题库的内容库。
//   错题本 = 用户的**私人数据空间**，由用户主动录入；软件本身不预设
//   任何真题/题库内容到错题本里。
//
// 数据来源：
//   - 用户手动添加：错题摘要 + 错误答案 + 正确答案 + 错误类型 + 关联考点
//   - AI 主动整理：用户点按钮后调 MiniMax AI 归类错因、提炼易错点
//   - AI 主动总结：基于所有错题生成总览
//
// 持久化：与 HistoryStore 同样的模式（静态类 + debugFilePath 注入 +
// 桌面/安卓 File + Web localStorage 条件导入）。
//
// 跨页同步：单例 ChangeNotifier，DashboardPage 推入错题本页 → 修改
// → pop 回首页 → 再进错题本页 = 看到最新数据（因为 MistakeBook 是
// 同一实例，instance.entries 一直在）。测试覆盖这条链路。
//
// ─────────────────────────────────────────────────────────
// TODO v2.13：错题本未来工作（7 项软性建议，待后续迭代）
// ─────────────────────────────────────────────────────────
//   1. schemaVersion 字段：当前 JSON 缺版本号，未来字段加减时
//      无法做迁移。给 MistakeEntry.toJson 加 'schemaVersion: 1'。
//   2. 复习状态徽标：列表里每条 entry 加小圆点（未复习灰 / 复习中橙
//      / 已掌握绿），无需打开详情即可一眼掌握复习进度。当前要打开
//      popup menu 才能切状态，UX 偏重。
//   3. _showMenu 回调拆出：错题本底部 sheet 里「编辑 / 删除 / AI
//      整理 / 复制题目」目前是 inline widget（_buildActions）。拆成
//      可复用的 ActionMenu widget，dashboard / 错题本都能用。
//   4. aiOverview 拆出独立 widget：analyzeAll 返回的 overview 现在
//      写到每条 entry 的 aiOverview 字段再在卡片底部展示。等数据量
//      上来（>50 条）后整页会有大量重复 overview → 拆为顶部总览
//      section（与底部每条 per-entry overview 解耦）。
//   5. 错题导入：从拍题识别（ScanBankStore）一键把已识别的题目
//      导入错题本——现在需要手动重填 4 个字段，路径太重。
//   6. 错题导出 JSON：用户主动备份/迁移数据。当前仅 File 持久化，
//      没法跨设备同步。
//   7. 复习间隔算法：艾宾浩斯间隔重复。复习状态目前仅 manual
//      三态（未复习/复习中/已掌握），v2.13 引入时间戳 + 间隔算法
//      自动提示"该复习了"。
// ─────────────────────────────────────────────────────────

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../services/mistake_book_crypto.dart';
import '../storage/platform_storage_io.dart'
    if (dart.library.html) '../storage/platform_storage_web.dart';
import '../ui/mistake_book_ai.dart';

// v2.12 Round 1 P0 #6：条件导入 Web 端下载触发器（package:web + dart:js_interop）。
// 桌面 / 安卓：走 stub（直接返回，不触发下载）；Web：走 _webTriggerDownload 真实实现。
import 'mistake_book_exporter_stub.dart'
    if (dart.library.html) 'mistake_book_exporter_web.dart';

/// 错误类型枚举（用户在添加对话框里选）。
///
/// 字符串表示 `name` 写入 JSON，避免 Dart 枚举 ordinal 重排破坏历史数据。
/// 与 AI 整理 prompt 里「错因」维度对齐：用户选的类型是「自评」，AI 整理
/// 给出的 aiSummary 是「客观判定」，两者可能不同。
enum MistakeErrorType {
  concept, // 概念错（不理解知识点）
  calculation, // 计算错（9331 比例算错等）
  comprehension, // 理解错（读题偏题）
  careless, // 粗心错（看错/写错）
  other; // 其他

  String get displayName {
    switch (this) {
      case MistakeErrorType.concept:
        return '概念错';
      case MistakeErrorType.calculation:
        return '计算错';
      case MistakeErrorType.comprehension:
        return '理解错';
      case MistakeErrorType.careless:
        return '粗心错';
      case MistakeErrorType.other:
        return '其他';
    }
  }

  static MistakeErrorType fromName(String? n) {
    for (final t in MistakeErrorType.values) {
      if (t.name == n) return t;
    }
    return MistakeErrorType.other;
  }
}

/// v2.19.62：AI 判定的**结构化错因词表**（闭集，单一真相）。
///
/// 词表来源对齐 lib/engine/error_diagnosis.dart 的五类典型错误模式
/// （漏算一对基因 / 基因型比当表型比 / 误套变式 / 份数体系错 /
/// 测交自交混淆）+ 未归类兜底——`ErrorDiagnosis._matchPatterns` 里
/// 逐一命名的正是这五类（外加「非典型错误」退化为 [unclassified]）。
///
/// 用途：错题本 AI 整理（lib/ui/mistake_book_ai.dart）时，让模型**只能**
/// 从这六个 key 里选一个，从而把「AI 客观判定的错因」落成一个可聚合
/// 的结构化字段（[MistakeEntry.causeKey]）；错因雷达的「AI 判」视图按
/// 这六轴计数。
///
/// 字符串表示 `name` 写入 JSON（与 [MistakeErrorType] 同款口径——
/// ⛔ 不写 ordinal，避免枚举重排破坏历史数据）。
enum MistakeCauseKey {
  missedGenePair, // 漏算一对基因
  genotypeAsPhenotype, // 基因型当表型（基因型比当表型比）
  misappliedVariant, // 误套 9331 变式
  fractionSystem, // 份数体系错
  testcrossSelfingConfusion, // 测交自交混淆
  unclassified; // 未归类（AI 拿不准 / 老数据未判 / 非法值兜底）

  String get displayName {
    switch (this) {
      case MistakeCauseKey.missedGenePair:
        return '漏算一对基因';
      case MistakeCauseKey.genotypeAsPhenotype:
        return '基因型当表型';
      case MistakeCauseKey.misappliedVariant:
        return '误套 9331 变式';
      case MistakeCauseKey.fractionSystem:
        return '份数体系错';
      case MistakeCauseKey.testcrossSelfingConfusion:
        return '测交自交混淆';
      case MistakeCauseKey.unclassified:
        return '未归类';
    }
  }

  /// 白名单解析：**只**认词表内的 name；null / 空 / 词表外的自由文本
  /// 一律返 null（⛔ 不兜底成 [unclassified]——「非法值」与「AI 明确判为
  /// 未归类」是两回事：[unclassified] 只能由模型显式输出或被计数口径
  /// 归并，不能由解析器私自代填）。
  static MistakeCauseKey? fromName(String? n) {
    for (final k in MistakeCauseKey.values) {
      if (k.name == n) return k;
    }
    return null;
  }
}

/// 复习状态：用户手动标记。
enum MistakeReviewStatus {
  unreviewed, // 未复习（默认）
  reviewing, // 复习中
  mastered; // 已掌握

  String get displayName {
    switch (this) {
      case MistakeReviewStatus.unreviewed:
        return '未复习';
      case MistakeReviewStatus.reviewing:
        return '复习中';
      case MistakeReviewStatus.mastered:
        return '已掌握';
    }
  }

  static MistakeReviewStatus fromName(String? n) {
    for (final s in MistakeReviewStatus.values) {
      if (s.name == n) return s;
    }
    return MistakeReviewStatus.unreviewed;
  }
}

/// v2.13 R3 P1-B4：错题本列表排序方式（页面下拉框选项）。
enum MistakeSortMode {
  createdAt, // 最近添加（默认：现有 createdAt 倒序）
  errorType, // 错因类型（概念→计算→理解→粗心→其他，组内最近添加在前）
  recentReview, // 最近复习（reviewedAt 倒序，未复习过的排最后）
  mostErrorProne; // 最易错（全量各错因出现次数降序，同类内最近添加在前）

  String get displayName {
    switch (this) {
      case MistakeSortMode.createdAt:
        return '最近添加';
      case MistakeSortMode.errorType:
        return '错因类型';
      case MistakeSortMode.recentReview:
        return '最近复习';
      case MistakeSortMode.mostErrorProne:
        return '最易错';
    }
  }
}

/// 一条错题。
///
/// 字段均为可变（immutable + 副本式 update），但 list 持有的是不可变
/// 快照；CRUD 都会 notifyListeners。
class MistakeEntry {
  final String id; // UUID（时间戳+随机后缀）
  final String stem; // 题目摘要
  final String userAnswer; // 用户的错误答案
  final String correctAnswer; // 正确答案
  final MistakeErrorType errorType; // 用户自评的错误类型
  final String subjectArea; // 关联考点（自由文本，如 "9331 变式 / 系谱推断"）
  final DateTime createdAt; // 创建时间
  final MistakeReviewStatus reviewStatus; // 复习状态
  /// v2.13 R3 P1-B4：最近一次标记复习状态的时间（「最近复习」排序依据）。
  /// null = 从未标记过复习状态；老 JSON 数据缺该字段 → null，在
  /// 「最近复习」排序里排在已复习的后面。
  final DateTime? reviewedAt;
  final String? aiSummary; // AI 整理：错因归类（一句话）
  final List<String> aiPitfalls; // AI 提炼：易错点（多行，每行一条）
  final String? aiOverview; // AI 整理全部后写入的与本条相关的总览块
  /// v2.13+ R5：连续「已掌握」次数——间隔退避（3→7→14→30→60→120 天）的依据。
  /// 标「还需复习」清零；老 JSON 数据缺该字段 → 0（按 1 次 = 3 天计）。
  final int masteredStreak;
  /// 这道题**是从哪个工具存进来的**（`ModuleFillBus` 的 moduleId，
  /// 如 'cross_mono'）。null = 不是从工具存进来的（手加表单 / 导入 /
  /// 老数据）⇒ 错题本里**不渲染**「回来源工具重算」按钮。
  ///
  /// 为什么值得加：退避阶梯（3→7→14→30→60→120 天）最想服务的就是「防遗忘」
  /// 那一刻，可复习会话原先**只有一行题干**——学生必须自己切回 9331、
  /// 凭记忆把亲本重敲一遍才能重做。记下来源 + 来源参数，到期时点一下即可
  /// 回到那道题本身。
  final String? srcModule;
  /// 存进来那一刻的**参数**（单基因页是 `{'p1':…, 'p2':…}`，连锁互换页
  /// 另有 `{'r':…}`）。null = 没记下参数 ⇒ 同样不渲染按钮（宁可没有，
  /// 不要一个点不动的）。
  final Map<String, String>? srcParams;
  /// v2.19.62：AI 客观判定的结构化错因 = [MistakeCauseKey] 的 `name`
  /// 字符串（与 [errorType] 的 JSON 口径一致——⛔ 不存 ordinal）。
  ///
  /// null = 这条还没被 AI 判过（老数据 / 手改文件 / AI 未判）。错因雷达
  /// 的「AI 判」视图把 null 计入 [MistakeCauseKey.unclassified] 桶。
  final String? causeKey;
  /// v2.19.66：这条错题**归谁的**——null = 本人原创（本人录入 / 老数据）。
  /// 非空 = 合并导入（[classIncomingToAdd]）打上的来源标记，当前只有
  /// 「来自同学」一种值。
  ///
  /// 与 [srcModule] 不同：[srcModule] 记的是「回来源工具重算」的入口，
  /// 本字段记的是**所有权**——错题本「仅看本人」筛选与卡片来源标都用它。
  ///
  /// ⛔ 合并导入**永不覆盖**本人已有条目——[classIncomingToAdd] 只返回
  /// 「待追加的新条目」，本字段只是给新条目打标。
  ///
  /// v2 方向（本版不做）：按来源分层标签（多来源）、dashboard 班级聚合、
  /// 按来源统计——见 [classIncomingToAdd] 顶部注释。
  final String? sourceTag;

  const MistakeEntry({
    required this.id,
    required this.stem,
    required this.userAnswer,
    required this.correctAnswer,
    required this.errorType,
    required this.subjectArea,
    required this.createdAt,
    this.reviewStatus = MistakeReviewStatus.unreviewed,
    this.reviewedAt,
    this.aiSummary,
    this.aiPitfalls = const [],
    this.aiOverview,
    this.masteredStreak = 0,
    this.srcModule,
    this.srcParams,
    this.causeKey,
    this.sourceTag,
  });

  /// 不可变 update：返回新对象（与 AppState / ThemeController 一致的风格）。
  MistakeEntry copyWith({
    /// v2.19.66：换一个 id 的副本。合并导入时慎用——源包的 id 是在**别人的
    /// 机器**上生成的，可能与本地撞 id；撞了错题本页 `_cardKeys` 的
    /// GlobalKey 会重复 ⇒ 抛「Multiple widgets used the same GlobalKey」。
    String? id,
    String? stem,
    String? userAnswer,
    String? correctAnswer,
    MistakeErrorType? errorType,
    String? subjectArea,
    MistakeReviewStatus? reviewStatus,
    DateTime? reviewedAt,
    String? aiSummary,
    List<String>? aiPitfalls,
    String? aiOverview,
    int? masteredStreak,
    // 来源信息随副本一起带走（复习时仍要能回那道题）。
    String? srcModule,
    Map<String, String>? srcParams,
    /// v2.19.62：AI 判定错因（[MistakeCauseKey] 的 name）。
    String? causeKey,
    /// v2.19.66：来源标记（null = 本人原创）。
    String? sourceTag,
    // R5 学生走查：「还需复习 = 今晚立即到期」此前是死代码——
    // copyWith(reviewedAt: null) 被 `?? this.reviewedAt` 吞掉。
    // 显式开关才能真正清空。
    bool clearReviewedAt = false,
    /// v2.19.62：同 clearReviewedAt 的显式开关——`causeKey ?? this.causeKey`
    /// 会吞掉显式 null，要**清空** causeKey 必须走本开关。
    bool clearCauseKey = false,
    /// v2.19.66：同 clearCauseKey 的显式开关——`sourceTag ?? this.sourceTag`
    /// 会吞掉显式 null；要**清空** sourceTag（把同学题「转正」成本人题）必须
    /// 走本开关。
    bool clearSourceTag = false,
  }) {
    return MistakeEntry(
      id: id ?? this.id,
      stem: stem ?? this.stem,
      userAnswer: userAnswer ?? this.userAnswer,
      correctAnswer: correctAnswer ?? this.correctAnswer,
      errorType: errorType ?? this.errorType,
      subjectArea: subjectArea ?? this.subjectArea,
      createdAt: createdAt,
      reviewStatus: reviewStatus ?? this.reviewStatus,
      reviewedAt:
          clearReviewedAt ? null : (reviewedAt ?? this.reviewedAt),
      aiSummary: aiSummary ?? this.aiSummary,
      aiPitfalls: aiPitfalls ?? this.aiPitfalls,
      aiOverview: aiOverview ?? this.aiOverview,
      masteredStreak: masteredStreak ?? this.masteredStreak,
      srcModule: srcModule ?? this.srcModule,
      srcParams: srcParams ?? this.srcParams,
      // v2.19.62：显式开关优先（否则 `?? this.causeKey` 吞掉显式 null）。
      causeKey: clearCauseKey ? null : (causeKey ?? this.causeKey),
      // v2.19.66：同 causeKey 的显式开关口径。
      sourceTag: clearSourceTag ? null : (sourceTag ?? this.sourceTag),
    );
  }

  /// v2.13 R4-4：浅脱敏副本（人名→某某、学号→×××），用于「脱敏导出」。
  ///
  /// 只替换题干 / 答案 / 考点 / AI 文本字段；id / createdAt / reviewedAt
  /// 等结构性字段不动（脱敏后导入仍能去重、恢复回收站）。
  MistakeEntry desensitized() {
    String m(String s) => MistakeBook.maskSensitive(s);
    return MistakeEntry(
      id: id,
      stem: m(stem),
      userAnswer: m(userAnswer),
      correctAnswer: m(correctAnswer),
      errorType: errorType,
      subjectArea: m(subjectArea),
      createdAt: createdAt,
      reviewStatus: reviewStatus,
      reviewedAt: reviewedAt,
      aiSummary: aiSummary == null ? null : m(aiSummary!),
      aiPitfalls: [for (final p in aiPitfalls) m(p)],
      aiOverview: aiOverview == null ? null : m(aiOverview!),
      masteredStreak: masteredStreak,
      // 来源**原样带走**。它不是个人信息（p1/p2 是基因型），
      // 脱敏的意义是别把「人名/学号」带出机器；把来源丢了，学生导出的
      // 错题本重新导入后就再也回不到那道题，等于白脱敏一次。
      srcModule: srcModule,
      srcParams: srcParams,
      // v2.19.62：AI 判定错因不是个人信息（是枚举 name），原样带走。
      causeKey: causeKey,
      // v2.19.66：来源标（「来自同学」）不是个人信息，原样带走——否则
      // 同学导出的包脱敏后合进来，「仅看本人」就再也筛不干净。
      sourceTag: sourceTag,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'stem': stem,
        'userAnswer': userAnswer,
        'correctAnswer': correctAnswer,
        'errorType': errorType.name,
        'subjectArea': subjectArea,
        'createdAt': createdAt.millisecondsSinceEpoch,
        'reviewStatus': reviewStatus.name,
        'reviewedAt': reviewedAt?.millisecondsSinceEpoch,
        'aiSummary': aiSummary,
        'aiPitfalls': aiPitfalls,
        'aiOverview': aiOverview,
        'masteredStreak': masteredStreak,
        // 可空新增，老条目写出 null（与 aiSummary/aiOverview 同款）。
        'srcModule': srcModule,
        'srcParams':
            srcParams == null ? null : Map<String, String>.from(srcParams!),
        // v2.19.62：AI 判定错因（[MistakeCauseKey] 的 name）；老条目 / 未判 ⇒ null。
        'causeKey': causeKey,
        // v2.19.66：来源标；老条目 / 本人原创 ⇒ null（与 causeKey 同款）。
        'sourceTag': sourceTag,
      };

  static MistakeEntry? fromJson(dynamic j) {
    if (j is! Map) return null;
    final id = j['id']?.toString();
    if (id == null || id.isEmpty) return null;
    final stem = j['stem']?.toString() ?? '';
    if (stem.isEmpty) return null; // 题目摘要是必填，空条目丢弃
    final rawPits = j['aiPitfalls'];
    final pits = <String>[];
    if (rawPits is List) {
      for (final p in rawPits) {
        final s = p?.toString() ?? '';
        if (s.isNotEmpty) pits.add(s);
      }
    }
    final ts = j['createdAt'];
    final createdAt = ts is int
        ? DateTime.fromMillisecondsSinceEpoch(ts)
        : DateTime.now();
    // ⛔ **老数据没有 srcModule / srcParams 这两个 key**——缺省一律按
    // null 处理，**不**升 schemaVersion、**不**写迁移脚本。
    // ⚠️ 这一段是最不能写错的地方：fromJson 一旦对老格式返回 null，
    // `_entries` 就整批空掉 ⇒ 学生的错题本**静默消失**。
    final rawModule = j['srcModule'];
    final srcModule =
        (rawModule is String && rawModule.isNotEmpty) ? rawModule : null;
    Map<String, String>? srcParams;
    final rawParams = j['srcParams'];
    if (rawParams is Map) {
      final m = <String, String>{};
      rawParams.forEach((k, v) {
        if (k == null) return;
        m[k.toString()] = v?.toString() ?? '';
      });
      // 空 map = 没记下可回填的东西 ⇒ 归一成 null（复习时不渲染按钮）。
      if (m.isNotEmpty) srcParams = m;
    }
    // v2.19.62：causeKey 容忍缺键 / 非法值——老数据、手改文件、词表外的
    // 自由文本一律落 null（**不抛**，也不代填 unclassified）。⚠️ 同 srcModule
    // 的口径：fromJson 一旦对老格式返回 null，`_entries` 会整批空掉 ⇒
    // 学生的错题本静默消失。
    final causeKey = MistakeCauseKey.fromName(j['causeKey']?.toString())?.name;
    // v2.19.66：sourceTag 容忍缺键 / 非法值——老数据、手改文件、空串一律
    // 落 null（**不抛**）。与 causeKey 同款：fromJson 一旦对老格式返回
    // null，`_entries` 会整批空掉 ⇒ 学生的错题本静默消失。
    final sourceTagRaw = j['sourceTag']?.toString();
    final sourceTag = (sourceTagRaw == null || sourceTagRaw.trim().isEmpty)
        ? null
        : sourceTagRaw;
    return MistakeEntry(
      id: id,
      stem: stem,
      userAnswer: j['userAnswer']?.toString() ?? '',
      correctAnswer: j['correctAnswer']?.toString() ?? '',
      errorType: MistakeErrorType.fromName(j['errorType']?.toString()),
      subjectArea: j['subjectArea']?.toString() ?? '',
      createdAt: createdAt,
      reviewStatus:
          MistakeReviewStatus.fromName(j['reviewStatus']?.toString()),
      // v2.13 R3 P1-B4：老数据无 reviewedAt 字段 → null（排序末尾）。
      reviewedAt: (j['reviewedAt'] is int)
          ? DateTime.fromMillisecondsSinceEpoch(j['reviewedAt'] as int)
          : null,
      aiSummary: j['aiSummary']?.toString(),
      aiPitfalls: pits,
      aiOverview: j['aiOverview']?.toString(),
      // 老数据无该字段 → 0（按首次掌握 = 3 天间隔计）。
      masteredStreak:
          (j['masteredStreak'] as num?)?.toInt() ?? 0,
      srcModule: srcModule,
      srcParams: srcParams,
      causeKey: causeKey,
      sourceTag: sourceTag,
    );
  }
}

/// v2.19.61：错因雷达（错题本页「错因分布」卡）的聚合口径。
///
/// ⛔ 只聚合**已有**字段 [MistakeEntry.errorType]，不调 AI、不读 aiSummary。
/// （AI causeKey 词表回填属 v2.19.62，与本函数无关。）
///
/// 口径（写死在这里，以免将来被改松）：
///   ① 输入 = 一份错题列表。生产环境传 `MistakeBook.instance.entries`，
///      该列表**不含回收站**——[MistakeBook.delete] 把条目移出 `_entries`
///      进 `_trash` ⇒ 已删的题不参与统计。
///   ② 每条按自己的 errorType 记 1 次。[MistakeBook.add] 强制要求 errorType
///      ⇒ **不存在 null 桶**，无需兜底归并。
///   ③ 五个键**全部出现**，零值也保留（图要画零轴）。
///
/// 纯函数：输入列表即可，不读任何全局状态 ⇒ 单元测试友好。
Map<MistakeErrorType, int> mistakeCauseCounts(List<MistakeEntry> entries) {
  final counts = <MistakeErrorType, int>{
    for (final t in MistakeErrorType.values) t: 0,
  };
  for (final e in entries) {
    counts[e.errorType] = (counts[e.errorType] ?? 0) + 1;
  }
  return counts;
}

/// v2.19.62：错因雷达「AI 判」视图的聚合口径。
///
/// ⛔ 与 [mistakeCauseCounts] 是**两个独立口径**：本函数聚合的是 AI 判定的
/// [MistakeEntry.causeKey]（不是用户自评的 errorType），供雷达卡「AI 判」
/// 视图使用。
///
/// 口径（写死在这里，以免将来被改松）：
///   ① 输入 = 一份错题列表（生产环境传 `MistakeBook.instance.entries`，
///      **不含回收站**，同 [mistakeCauseCounts]）。
///   ② 每条按自己的 [MistakeEntry.causeKey] 记 1 次；**null / 词表外的
///      值一律归入 [MistakeCauseKey.unclassified] 桶**（老数据未判、AI 拿不
///      准都落这一桶——这是**计数兜底**，不是解析器代填）。
///   ③ 六个键**全部出现**，零值也保留（图要画零轴）。
///
/// 纯函数：输入列表即可，不读任何全局状态 ⇒ 单元测试友好。
Map<MistakeCauseKey, int> mistakeCauseKeyCounts(List<MistakeEntry> entries) {
  final counts = <MistakeCauseKey, int>{
    for (final k in MistakeCauseKey.values) k: 0,
  };
  for (final e in entries) {
    final k =
        MistakeCauseKey.fromName(e.causeKey) ?? MistakeCauseKey.unclassified;
    counts[k] = (counts[k] ?? 0) + 1;
  }
  return counts;
}

/// v2.19.62：全库是否**至少有一条**被 AI 判过（causeKey 非空且合法）。
///
/// 雷达卡「AI 判」视图据此决定画图还是渲染诚实空态——
/// `entries.any((e) => MistakeCauseKey.fromName(e.causeKey) != null)`。
bool hasAnyAiCauseKey(List<MistakeEntry> entries) => entries
    .any((e) => MistakeCauseKey.fromName(e.causeKey) != null);

/// v2.19.66：班级错题「合并导入」的核心口径——算出 [incoming] 里**该追加**
/// 的新条目（其余为重复，跳过）。
///
/// 去重键：`(stem.trim(), correctAnswer.trim())`——与 [MistakeBook.findSame]
/// 同一口径（同一道题的一字不差重复）。同时与 **local** 及 **incoming 自身**
/// 去重（同一个包里同一道题出现两次也只进一条）。
///
/// 返回：每条 `copyWith(sourceTag: sourceTag)` 打过来源标的新条目列表。
///
/// ⛔ 铁律：**local 一条都不改**——函数是纯的，只读 local、只返回新增列表；
/// 「老师/本人自己的题永不被覆盖」就靠这一点（合并只追加，不替换、不合并
/// 同题干的两条题）。
///
/// v2 方向（本版**不做**）：dashboard 班级聚合视图、按来源统计、同学分层
/// 标签（多来源）——届时本函数可能改为返回 `(adds, conflicts)` 结构。
List<MistakeEntry> classIncomingToAdd(
  List<MistakeEntry> local,
  List<MistakeEntry> incoming, {
  required String sourceTag,
}) {
  // 记录类型 (stem, answer) 做键：record 自带值相等，无需拼接分隔符
  // （拼字符串会被题干里恰好含分隔符的题骗过去）。
  final seen = <(String, String)>{};
  for (final e in local) {
    seen.add((e.stem.trim(), e.correctAnswer.trim()));
  }
  final out = <MistakeEntry>[];
  for (final e in incoming) {
    // seen.add 返回 false = 已在集合里（与 local 重复 或 与 incoming 自身
    // 重复）⇒ 跳过。
    if (!seen.add((e.stem.trim(), e.correctAnswer.trim()))) continue;
    out.add(e.copyWith(sourceTag: sourceTag));
  }
  return out;
}

/// v2.12 Round 1 P0 #5：错题本回收站条目（原 MistakeEntry 快照 + 删除时间）。
///
/// 设计：不改动 MistakeEntry，外包一层包含 deletedAt。这样 MistakeEntry
/// 仍可以被 add() 重插使用（同 v2.12.0+2 hotfix 的 add 返回新 id 思路），
/// 且 JSON 格式与原有 entries 列表兼容（只是包了一层）。
class MistakeTrashEntry {
  final MistakeEntry entry;
  final DateTime deletedAt;

  const MistakeTrashEntry({required this.entry, required this.deletedAt});

  /// 外部查找用：跟 MistakeEntry 同一个 id，跨主列表 + 回收站唯一。
  String get id => entry.id;

  Map<String, dynamic> toJson() => {
        'entry': entry.toJson(),
        'deletedAt': deletedAt.millisecondsSinceEpoch,
      };

  static MistakeTrashEntry? fromJson(dynamic j) {
    if (j is! Map) return null;
    final entry = MistakeEntry.fromJson(j['entry']);
    if (entry == null) return null;
    final ts = j['deletedAt'];
    final deletedAt = ts is int
        ? DateTime.fromMillisecondsSinceEpoch(ts)
        : DateTime.now();
    return MistakeTrashEntry(entry: entry, deletedAt: deletedAt);
  }
}

/// v2.13 R3 P1-B3：批量 AI 整理结果（页面据此决定 SnackBar 文案，
/// 不再把全失败显示成「批量整理完成：0 / N」假成功）。
class BatchOrganizeOutcome {
  /// 本次参与整理的条目总数（调用方传入）。
  final int total;

  /// 成功解析出 AI 结果的条目映射（id → analysis）。
  final Map<String, MistakeAiAnalysis> successes;

  /// 网络 / AI 层失败原因（未配置 AI、HTTP 错误等）；纯解析失败
  /// 时可能为 null（没有具体原因可报）。
  final String? failureReason;

  const BatchOrganizeOutcome(
      {required this.total, required this.successes, this.failureReason});

  /// 成功条数。
  int get successCount => successes.length;

  /// 全失败（0 成功）。
  bool get allFailed => successes.isEmpty;

  /// 部分成功（>0 且 < 总数）。
  bool get partialSuccess => successes.isNotEmpty && successes.length < total;
}

/// 错题本存储（单例，ChangeNotifier）。
///
/// - `add()` / `update()` / `delete()` / `markStatus()` / `applyAiAnalysis()`
///   全部同步修改内存 + 异步落盘（写盘失败不抛错，避免主流程崩溃）。
/// - 列表按 `createdAt` 倒序展示（UI 层用 `entries` 直接渲染即可）。
/// - 测试用 `debugFilePath` 注入临时文件（同 HistoryStore / ScanBankStore）。
class MistakeBook extends ChangeNotifier {
  MistakeBook._();
  static final MistakeBook instance = MistakeBook._();

  /// 测试注入：非空时 load/save 走该文件而非用户目录。
  static String? debugFilePath;

  /// v2.12+ R2 P1-1：测试注入——mock `isWebStorage` 标志。
  ///
  /// 非空时 `_isWebStorage` getter 返该值（true=强制走 web/localStorage
  /// 路径；false=强制走桌面 File 路径），与 FirstRunStore.debugForceIsWebStorage
  /// 同款三态模式。flutter_test 无 window 对象（`package:web` 的
  /// `localStorage` 不可用），此 hook 让 test/state/mistake_book_test.dart
  /// 能验证 web 端 round-trip 链路（add 写 localStorage → load 读回 →
  /// entries 一致）。
  @visibleForTesting
  static bool? debugForceIsWebStorage;

  /// v2.12+ R2 P1-1：实际 web 存储标志。test hook 优先于真实 isWebStorage。
  bool get _isWebStorage => debugForceIsWebStorage ?? isWebStorage;

  /// v2.12 Round 1 P0 #5：时间注入（默认 DateTime.now）。
  /// 测试可改写验证 7 天后自动清理、过期判定等场景。
  /// 为静态；多个测试不互相干扰。生产环境不要改。
  static DateTime Function() now = DateTime.now;

  static const int maxEntries = 500;
  static const String _key = 'mistake_book_json';

  /// v2.12 Round 1 P0 #5：回收站 localStorage key + 桌面/安卓文件名。
  static const String _trashKey = 'mistake_book_trash_json';
  static const String _trashFileName = 'mistake_book_trash.json';
  static const Duration defaultTrashRetention = Duration(days: 7);

  /// 内存中的错题列表（按 createdAt 倒序）。
  final List<MistakeEntry> _entries = [];

  /// 公开只读视图（避免外部修改列表结构）。
  List<MistakeEntry> get entries => List.unmodifiable(_entries);

  /// v2.12 Round 1 P0 #5：回收站列表。按 deletedAt 倒序（最近删除的在前）。
  final List<MistakeTrashEntry> _trash = [];

  /// 回收站只读视图。
  List<MistakeTrashEntry> get trash => List.unmodifiable(_trash);

  /// 索引查找（O(n)；n ≤ 500 可接受）。
  MistakeEntry? findById(String id) {
    for (final e in _entries) {
      if (e.id == id) return e;
    }
    return null;
  }

  /// 已加载标记（避免重复 load 覆盖内存中已修改的数据）。
  bool _loaded = false;

  /// v2.12 Wave 3-B P1-1：写盘 debounce 计时器。多次 add/update/delete
  /// 短时连击时（例如 AI 批量整理 8 条）只落盘 1 次，避免每次都同步
  /// writeAsStringSync（实测桌面 500 条错题连续写盘 = 数十次磁盘 I/O）。
  /// 500ms 是经验值：长于常见手抖连点（<200ms），短于用户感知"卡顿"
  /// 阈值。落盘失败仍按原策略不抛错。
  Timer? _saveDebounce;
  static const Duration _saveDebounceWindow = Duration(milliseconds: 500);

  /// v2.12 Wave 3-B P1-1：标记"有未落盘修改"。debounce 触发时才真正
  /// 调 _save()。避免某些路径 _saveDebounce 被 cancel（dispose）时丢
  /// 数据。dispose 时若 dirty=true → 立即同步落盘一次。
  bool _dirty = false;

  /// 加载磁盘数据。重复调用幂等。
  ///
  /// ⚠️ FLUTTER_TEST 守卫：dashboard / 老师页等入口（v2.15 R6 起）也会
  /// 触发 load——测试环境若无 guard 会读用户真实 ~/.biology_app 错题，
  /// 让断言随真机数据漂移。注入 debugFilePath（隔离临时文件）时放行。
  Future<void> load() async {
    if (_loaded) return;
    if (!kIsWeb && Platform.environment['FLUTTER_TEST'] == 'true' &&
        MistakeBook.debugFilePath == null) {
      _loaded = true; // 视为已加载（空），后续 debugReset 会复位
      return;
    }
    _loaded = true;
    // v2.13 R3 W1（P0）：Android 先等 getFilesDir() 缓存就绪，避免
    // _file() fallback 到 '/'（EACCES 静默丢数据）。桌面/Web no-op。
    await ensureAppDirReady();
    try {
      final raw = storageGet(_key);
      List<dynamic> json;
      if (raw != null) {
        final decoded = jsonDecode(raw);
        json = decoded is List ? decoded : const [];
      } else {
        // Web 上 raw == null 只表示 localStorage 空，不是「该读文件」。
        if (kIsWeb) return;
        final f = File(_file());
        if (!f.existsSync()) return;
        final decoded = jsonDecode(f.readAsStringSync());
        json = decoded is List ? decoded : const [];
      }
      _entries.clear();
      for (final e in json) {
        final m = MistakeEntry.fromJson(e);
        if (m != null) _entries.add(m);
      }
      _sortDesc();
      // v2.12 Round 1 P0 #5：加载回收站。过期条目不在这里过滤，
      // 由页面层在 initState 调 purgeExpiredTrash。
      await _loadTrash();
    } catch (e) {
      // v2.19.6 polish（性能 🟡#4）：原本 catch(_) 静默 → 损坏文件
      // / 写盘满 / Web Storage 异常时用户零提示。debugPrint 暴露根因，
      // 不阻塞主流程（保持空列表）。UI 提示由调用方在 _loadFromFile
      // 包装层做（避免 state 类耦合 UI context）。
      debugPrint('[biology] MistakeBook.load 失败：$e');
    }
  }

  /// 从独立的 trash JSON 文件加载。文件不存在 / 损坏不抛错，
  /// 仅记入空。路径与 _file() 同源（默认 ~/.biology_app/mistake_book_trash.json）。
  Future<void> _loadTrash() async {
    _trash.clear();
    try {
      final raw = storageGet(_trashKey);
      List<dynamic> json;
      if (raw != null) {
        final decoded = jsonDecode(raw);
        json = decoded is List ? decoded : const [];
      } else {
        if (kIsWeb) return;
        final f = File(_trashFile());
        if (!f.existsSync()) return;
        final decoded = jsonDecode(f.readAsStringSync());
        json = decoded is List ? decoded : const [];
      }
      for (final e in json) {
        final t = MistakeTrashEntry.fromJson(e);
        if (t != null) _trash.add(t);
      }
      _sortTrashDesc();
    } catch (e) {
      // v2.19.6 polish（性能 🟡#4）：同 load()——debugPrint 暴露根因，
      // 不抛错不阻塞。trash 损坏比主条目轻，但仍需留痕便于排查。
      debugPrint('[biology] MistakeBook._loadTrash 失败：$e');
    }
  }

  /// 测试用：重置内存状态 + 重置 loaded 标记 + 重置 _idCounter。
  /// **不**触碰磁盘文件。
  ///
  /// v2.12 Wave 3-B P1 补：reset 时把 _idCounter 一起清零，让每个
  /// 测试独立从 0 开始。否则测试间 counter 累积，A 测试的 id 可能
  /// 比 B 测试的小（因为 A 先跑 + counter 不重置），但 B 测试重新
  /// 排序时基于 counter 的 tie-breaker 会让顺序更乱。
  @visibleForTesting
  void debugReset() {
    _entries.clear();
    _trash.clear();
    _loaded = false;
    _dirty = false;
    _saveDebounce?.cancel();
    _saveDebounce = null;
    _idCounter = 0; // 静态 counter 跨 add 持久，测试间必须清零
    debugForceIsWebStorage = null; // v2.12+ R2 P1-1：清 test hook
    notifyListeners();
  }

  /// 添加错题。返回新分配的 entry（含 id + createdAt）。
  MistakeEntry add({
    required String stem,
    required String userAnswer,
    required String correctAnswer,
    required MistakeErrorType errorType,
    required String subjectArea,
    // 来源工具（moduleId）与来源参数；不传 = 不是从工具存进来的。
    String? srcModule,
    Map<String, String>? srcParams,
  }) {
    final entry = MistakeEntry(
      id: _genId(),
      stem: stem,
      userAnswer: userAnswer,
      correctAnswer: correctAnswer,
      errorType: errorType,
      subjectArea: subjectArea,
      createdAt: DateTime.now(),
      srcModule: srcModule,
      srcParams: srcParams,
    );
    _entries.add(entry);
    _sortDesc();
    _trim();
    notifyListeners();
    _scheduleSave();
    return entry;
  }

  /// v2.13+ R5：按 题干+正确答案 查重（存入类入口共用）——同一道题连点
  /// 两下、或在练习/拍题/计算器多个入口各存一次，会产生一字不差的
  /// 重复条目（AI 整理也各跑一遍耗额度，复习会话里同一题连出两遍）。
  MistakeEntry? findSame(String stem, String correctAnswer) {
    final s = stem.trim();
    final c = correctAnswer.trim();
    if (s.isEmpty) return null;
    for (final e in _entries) {
      if (e.stem.trim() == s && e.correctAnswer.trim() == c) return e;
    }
    return null;
  }

  /// 存入类入口的统一去重添加：已有同题干+同答案 → 复用旧条目返回
  /// isNew=false（调用方据此跳过 AI 整理入队、且不给「撤销」语义——
  /// 旧条目不是这次加的）；否则正常 add。
  ///
  /// 命中重复时**不是**整包返回旧条目：本次带来的**来源**要按
  /// [_backfillSource] 的三条口径补写上去（老数据第一次重存即拿回
  /// 程按钮），而错答 / 错因 / 考点不动——它们是「最近一次观测」，
  /// 本仓的重复存入语义至今是「只提示已在库」。
  ({MistakeEntry entry, bool isNew}) addOrFind({
    required String stem,
    required String userAnswer,
    required String correctAnswer,
    required MistakeErrorType errorType,
    required String subjectArea,
    // 同上，转发给 add。
    String? srcModule,
    Map<String, String>? srcParams,
  }) {
    final dup = findSame(stem, correctAnswer);
    if (dup != null) {
      return (entry: _backfillSource(dup, srcModule, srcParams), isNew: false);
    }
    return (
      entry: add(
        stem: stem,
        userAnswer: userAnswer,
        correctAnswer: correctAnswer,
        errorType: errorType,
        subjectArea: subjectArea,
        srcModule: srcModule,
        srcParams: srcParams,
      ),
      isNew: true
    );
  }

  /// 一条错题**记不记得**可用的来源（复习时能不能一键回那页重算）。
  ///
  /// 判据与错题本的按钮判据（`mistakeEntryHasSource`）**逐条对齐**：
  /// srcModule 非空 **且** srcParams 非空，两个条件缺一不可 —— 少任何
  /// 一个，那枚「去…重算这道题」按钮就不渲染（宁可没有，不要一个点
  /// 不动的）。
  static bool _hasUsableSource(MistakeEntry e) =>
      (e.srcModule?.isNotEmpty ?? false) && (e.srcParams?.isNotEmpty ?? false);

  /// 把本次调用带来的来源回填进一条**命中重复**的旧条目，返回它在
  /// `_entries` 里的当前实例（没回填时原样返回入参那一条）。
  ///
  /// ## 为什么要它
  ///
  /// 「存题来源」上线**之前**存的错题，两个字段都是 null ⇒ 复习按钮根本
  /// 不渲染。而这类条目学生**再存一次**（他当时就是存进去的，这是最自
  /// 然的动作）仍然拿不回程按钮 ⇒ 该功能对最需要它的人群（历史错题）
  /// **只对第一次**有效。本函数补的就是这条路径。
  ///
  /// ## 口径（三条，写死在这里以免将来被改松）
  ///
  /// ① 旧条目**已有**可用来源 ⇒ **不覆盖**。那是这道题第一次真实存取时
  ///    的来源，也是当初那道题真实的亲本；本次只是又一次相同的存入，
  ///    改掉等于拿后来的观测篡改历史来源。
  /// ② 旧条目**没有**可用来源（老数据）+ 本次带来可用来源 ⇒ 回填。
  /// ③ 旧条目没有、本次也没有 ⇒ 什么都不做（不写空串、不写空 map）。
  ///
  /// ⚠️ ①② 只认「可用来源」这一个判据，**不做逐字段回填**：若先写一个
  ///   孤零零的 srcModule 上去，①就会挡住后面那次「字段齐了」的回填，
  ///   把老条目永久卡在「有 module 没参数 = 还是不出按钮」的状态。宁可
  ///   什么都不写，也不能写出一个更接近可用、实则仍不可用的半截状态。
  ///
  /// ⚠️ `copyWith` 的语义是 `srcModule ?? this.srcModule`（见 MistakeEntry）
  ///   ⇒ **拿它清空字段会被静默吞掉**。本函数只设不清，且只在两个字段
  ///   都非空时才调 ⇒ 踩不到那个语义坑。
  MistakeEntry _backfillSource(
      MistakeEntry dup, String? srcModule, Map<String, String>? srcParams) {
    if (_hasUsableSource(dup)) return dup; // ①：已有来源，原样返回
    if (!(srcModule?.isNotEmpty ?? false) ||
        !(srcParams?.isNotEmpty ?? false)) {
      return dup; // ③：本次也没带来可用来源，什么都不写
    }
    update(dup.id, (e) => e.copyWith(srcModule: srcModule, srcParams: srcParams)); // ②
    final i = _indexOf(dup.id); // update() 返 void ⇒ 回读拿回回填后的新实例
    return i < 0 ? dup : _entries[i];
  }

  /// 更新错题（按 id 查找）。id 不存在时静默忽略。
  void update(String id, MistakeEntry Function(MistakeEntry current) edit) {
    final i = _indexOf(id);
    if (i < 0) return;
    _entries[i] = edit(_entries[i]);
    notifyListeners();
    _scheduleSave();
  }

  /// v2.12 Round 1 P0 #5：删除改为软删除——移入回收站。
  ///
  /// 原行为（v2.12.0+2 hotfix 也是 hard delete）：从 _entries 直接 removeAt，
  /// 5 秒 Undo 过期后不可恢复——学生误删后无任何救济手段。
  ///
  /// 新行为：移到 _trash，deletedAt = now()。在回收站里 7 天内可恢复，
  /// 7 天后被 purgeExpiredTrash() 自动清理。调用方可以走 _handleDelete 的
  /// 5 秒 Undo（调 restoreFromTrash）。
  void delete(String id) {
    final i = _indexOf(id);
    if (i < 0) return;
    final entry = _entries.removeAt(i);
    _trash.add(MistakeTrashEntry(entry: entry, deletedAt: now()));
    notifyListeners();
    _scheduleSave();
  }

  /// 从回收站恢复一条到主列表。调用 add() 会重新分配 id，
  /// 避免历史引用错乱（同 v2.12.0+2 Undo 修复思路）。
  ///
  /// trashId：回收站条目的 id（原 MistakeEntry.id）。
  /// 返回新分配的 entry，或 null（trashId 不存在）。
  MistakeEntry? restoreFromTrash(String trashId) {
    final i = _trashIndexOf(trashId);
    if (i < 0) return null;
    final snapshot = _trash[i].entry;
    _trash.removeAt(i);
    // 重插：用 add() 重新生成 id + createdAt，保留原全部字段
    // （包括 aiSummary / aiPitfalls / aiOverview / reviewStatus）。
    final restored = add(
      stem: snapshot.stem,
      userAnswer: snapshot.userAnswer,
      correctAnswer: snapshot.correctAnswer,
      errorType: snapshot.errorType,
      subjectArea: snapshot.subjectArea,
    );
    if (snapshot.aiSummary != null || snapshot.aiPitfalls.isNotEmpty) {
      applyAiAnalysis(restored.id,
          summary: snapshot.aiSummary,
          pitfalls:
              snapshot.aiPitfalls.isEmpty ? null : snapshot.aiPitfalls,
          // v2.19.62：恢复时保留 AI 判定错因（快照里有就带回来）。
          causeKey: snapshot.causeKey);
    }
    if (snapshot.aiOverview != null) {
      applyAiOverview(restored.id, snapshot.aiOverview!);
    }
    if (snapshot.reviewStatus != MistakeReviewStatus.unreviewed ||
        snapshot.reviewedAt != null) {
      // v2.13 R3 P1-B4：恢复时保留原复习状态 + 原 reviewedAt——
      // 不走 markStatus（它会写 now()，让「最近复习」排序漂移到恢复
      // 时刻）；直接 update 用快照时间。老数据无 reviewedAt 时保持
      // null（copyWith 无法清空，null ?? 保留原值 = 本就 null）。
      update(restored.id, (e) => e.copyWith(
            reviewStatus: snapshot.reviewStatus,
            reviewedAt: snapshot.reviewedAt,
          ));
    }
    return restored;
  }

  /// 从回收站永久删除（不可恢复）。
  /// 返回删除是否成功（trashId 不存在返 false）。
  bool permanentlyDelete(String trashId) {
    final i = _trashIndexOf(trashId);
    if (i < 0) return false;
    _trash.removeAt(i);
    notifyListeners();
    _scheduleSave();
    return true;
  }

  /// 清理超过 retention 时间的回收站条目。默认 7 天。
  /// 返回被清理的条数（用于测试断言）。
  int purgeExpiredTrash(
      {Duration retention = const Duration(days: 7)}) {
    final cutoff = now().subtract(retention);
    final keep = <MistakeTrashEntry>[];
    var removed = 0;
    for (final t in _trash) {
      if (t.deletedAt.isBefore(cutoff)) {
        removed++;
      } else {
        keep.add(t);
      }
    }
    if (removed == 0) return 0;
    _trash
      ..clear()
      ..addAll(keep);
    _sortTrashDesc();
    notifyListeners();
    _scheduleSave();
    return removed;
  }

  // ─── v2.12 Round 1 P0 #6：跨设备导入 / 导出 JSON ────────────
  //
  // 学生场景：家里 Windows + 学校 iPad，Web vs 桌面数据完全不通。
  // 用户隐私 + 工程复杂度考虑，**不做云端同步**——做主动导出 / 导入。
  //
  // JSON 格式（schemaVersion 1）：
  //   {
  //     'schemaVersion': 1,
  //     'exportedAt': <millisEpoch>,
  //     'entries': [ <MistakeEntry json>, ... ],
  //     'trash':    [ <MistakeTrashEntry json>, ... ]
  //   }
  //
  // v2.12+ R2 P0-B1：兼容老 schemaVersion 0 / 缺失字段的 JSON。
  // 老格式无 trash 字段、无 aiOverview 字段，importJson 会自动
  // 走 _importJsonV0 兼容路径，按老字段映射 + 默认值处理。
  //
  // 解析容错：缺 schemaVersion/entries/trash 字段时按空处理；
  // entries 数组里逐项 fromJson，损坏项丢弃（不抛错）。

  static const int _exportSchemaVersion = 1;

  // ─── v2.13 R8-P1：NER 启发式升级（高频姓氏 + 2-4 字识别）─────
  //
  // R6-P1 浅脱敏遗留 P1 隐私根因 1/4：孤立人名漏脱。R4f 姓名位
  // 启发式（前后都是汉字且无称谓时**不换**）兜底太严——
  // 「今天张三被选为班委」这种典型句中嵌字场景，张三不会被替换。
  // verifier 三方一致锁定的 P1 根因：浅脱敏孤立人名漏脱敏。
  //
  // R8-P1 升级：两步走——
  //   1. 扩姓氏字符集到 top 50 百家姓（覆盖更广人名）
  //   2. 主路径判定改为「首字姓氏 + 词长 2-4」——**不再**要求姓名位
  //      信号。句中嵌字（"今天张三被选为班委"）也直接替换。
  //   3. 排除集仍保护已知生物 / 校园 / 日常高频词（叶绿体 / 高三 /
  //      周记 / 杜鹃 / 任何 / 几何 等）
  //   4. R4f 姓名位启发式保留为 fallback——处理「姓+某」模糊名、
  //      紧邻称谓词位、独立词边界（学号位 / 标点）等边界 case
  //      （罕见姓氏未进入 top 50 集合时仍可借 fallback 路径替换）。
  //
  // 限制：纯字符串启发式无 NLP / 词典，是**有损**脱敏——可能漏网
  // （罕见姓氏 / 复姓 / 非常见写法），也可能过度（top 50 中与生物
  // 术语冲突的姓氏已通过 _nameExclusion 保护，见下方「R8-P1 补
  // 充排除集」段）。

  /// v2.13 R8-P1：高频中文姓氏集合（百家姓前 50）。比 R4-4
  /// 避冲突精选集扩展——原集合为避生物术语冲突刻意剔除
  /// 「叶 / 杜 / 丁 / 任 / 田 / 程 / 苏 / 魏 / 吕 / 沈 / 韩 / 唐 /
  /// 萧 / 董 / 蔡 / 余 / 蒋 / 潘 / 袁 / 彭 / 曹 / 邓 / 冯 / 许 /
  /// 宋 / 谢 / 梁 / 郑 / 罗 / 郭 / 何 / 朱 / 孙 / 徐」等易冲突
  /// 字符。R8-P1 保留这些以覆盖更广人名，但通过扩充 _nameExclusion
  /// 抵消新增姓氏的误伤风险（见下方「R8-P1 补充排除集」段）。
  static const Set<String> _surnamesTop50 = {
    '王', '李', '张', '刘', '陈', '杨', '黄', '赵', '吴', '周',
    '徐', '孙', '马', '朱', '胡', '郭', '何', '高', '林', '罗',
    '郑', '梁', '谢', '宋', '唐', '许', '韩', '冯', '邓', '曹',
    '彭', '曾', '萧', '田', '董', '袁', '潘', '于', '蒋', '蔡',
    '余', '杜', '叶', '程', '苏', '魏', '吕', '丁', '任', '沈',
  };

  /// v2.13 R8-P1：扩展姓氏字符集（合并原 R4-4 避冲突精选集 +
  /// R8-P1 新增 top 50 姓氏）——R8-P1 主路径正则使用。已剔除
  /// 「白/方/石/金/熊/梅/姜/兰/龙/甘/毛/范/雷/陆/夏/万」等
  /// 与生物/化学高频词冲突的字符（原 R4-4 同样剔除这些）。
  /// v2.13 R8-P1：主路径人名判定——首字在 top 50 姓氏集合 + 词长
  /// 2-4。**不再**要求姓名位信号（句中嵌字也换）——P1 根因实证
  /// 「今天张三被选为班委」必须替换。误伤风险由 _nameExclusion
  /// 兜底。
  static bool _isLikelyPersonName(String token) {
    if (token.length < 2 || token.length > 4) return false;
    return _surnamesTop50.contains(token[0]);
  }

  /// v2.13 R8-P1：是否被 _nameExclusion 排除（保护已知生物 /
  /// 校园 / 日常高频词）。覆盖：
  ///   - token 整体在排除集（如「向光性」「林冠层」）
  ///   - 3+ char token 的 2-char 前缀在排除集（如「高茎豌豆」
  ///     2-char 前缀「高茎」）
  /// R8-P1 起抽出独立函数供主路径 + fallback 共用，避免漏写。
  static bool _isExcluded(String token) {
    if (_nameExclusion.contains(token)) return true;
    if (token.length >= 3 &&
        _nameExclusion.contains(token.substring(0, 2))) {
      return true;
    }
    return false;
  }

  /// v2.13 R8-P1：常见单字功能词集合（用于词长试探中间字符判定）——
  /// 这些字符几乎不可能是名字的一部分（"王选"是名字但"被""的"
  /// "是""在"等是功能词/介词/代词/数词/量词）。R8-P1 主路径
  /// 试探 2/3/4 字符时，若中间字符是这些功能词则停——P1 根因
  /// 「今天张三被选为班委」贪心匹配会得 4 字符「张三被选」，
  /// 中间字符「被」是功能词，试探停在 2 字符「张三」，保留
  /// 「被选为班委」上下文。
  ///
  /// 设计原则：包含「几乎肯定不是名字」的字符——
  ///   - 助词/结构助词（的/了/着/过/们）
  ///   - 介词（在/于/对/向/被/为/给/把）
  ///   - 连词（和/与/或/但/而/则）
  ///   - 副词（是/有/没/不/也/都/很/就/才/已/将/会/能/可/要/得）
  ///   - 代词（我/你/他/她/它/这/那/哪/谁）
  ///   - 方位（上/下/里/外/前/后/中/内/间/东/南/西/北/左/右）
  ///   - 常见动词（看/听/说/想/做/走/出/进/打/写/读/买/卖/选/开/关）
  ///   - 数词（一/二/三/四/五/六/七/八/九/十/百/千/万/两/几）
  ///   - 量词（个/些/次/回/种/样/本/位/名/群/块/张/条/只/双/对）
  /// 故意不包含：军/华/强/丽/芳/伟/杰/鹏/龙/凤/明/国/建/文/武
  /// ——这些是常见名字用字（"张军""王华""李明"等）。
  static const Set<String> _nameBoundaryChars = {
    // 助词/结构助词/语气词
    '的', '地', '得', '了', '着', '过', '们', '吧', '呢', '啊', '吗',
    '嘛', '呀', '哦', '嗯', '哈', '耶', '咯', '啰', '哇', '哎', '嚯',
    // 介词
    '在', '于', '对', '向', '从', '到', '给', '让', '把', '被', '为',
    '自', '往', '跟', '比', '当', '按', '据', '由', '至', '随', '凭',
    // 连词
    '和', '与', '或', '但', '而', '则', '虽', '因', '所', '故', '且',
    '若', '以', '便', '并', '乃', '即', '然',
    // 副词
    '是', '有', '没', '不', '也', '都', '很', '还', '就', '才', '已',
    '将', '会', '能', '可', '要', '应', '必', '许', '曾',
    // 代词
    '我', '你', '他', '她', '它', '这', '那', '哪', '谁', '某', '各',
    '何', '彼', '此', '吾', '汝', '尔',
    // 方位
    '上', '下', '里', '外', '前', '后', '中', '内', '间', '东', '南',
    '西', '北', '左', '右',
    // 时间
    '今', '明', '昨', '去', '来',
    // 常用动词
    '看', '听', '说', '想', '做', '走', '回', '出', '进', '打', '写',
    '读', '买', '卖', '吃', '喝', '选', '开', '关', '放', '拿', '送',
    '接', '教', '用', '找', '记', '算', '画', '唱', '跳', '跑',
    '坐', '站', '死', '活', '生', '加', '参', '考', '试', '复', '习',
    '工', '作', '休', '息', '睡', '醒', '笑', '哭', '叫', '喊', '问',
    '答', '告', '诉', '请', '求', '帮', '完', '成', '始', '终',
    // 数字
    '一', '二', '三', '四', '五', '六', '七', '八', '九', '十', '百',
    '千', '万', '两', '几', '零', '半',
    // 量词
    '个', '些', '次', '种', '样', '本', '位', '名', '群', '块',
    '片', '条', '只', '双', '颗', '粒', '滴', '堆', '层',
  };

  /// v2.13 R8-P1：罕见姓氏字符集合（R4-4 兼容 fallback）——R4-4
  /// 的 _surnameChars 含 44 个精选姓氏字符（含孔/向/汤/武/覃等
  /// 与生物术语冲突少的「避冲突精选集」成员，这些未进 R8-P1
  /// top 50）。R4f 姓名位启发式作为 fallback 仍要能命中这些罕见
  /// 姓氏字符开头的人名——所以保留这份避冲突精选集作为 fallback
  /// 触发集。转 Set 是因为 main path 已用 _surnamesTop50 集合判
  /// 定，fallback 路径需要 char-by-char 查找。
  static const Set<String> _surnameCharsFallbackSet = {
    '张', '王', '李', '赵', '刘', '陈', '杨', '黄', '周', '吴',
    '徐', '孙', '马', '朱', '胡', '郭', '何', '高', '林', '罗',
    '郑', '梁', '谢', '宋', '唐', '许', '韩', '冯', '邓', '曹',
    '彭', '曾', '邹', '廖', '贾', '韦', '付', '戴', '莫', '孔',
    '向', '汤', '武', '覃',
  };

  // ─── v2.13 R4-4：浅脱敏（token 级，不做全文理解）─────────
  //
  // 错题本含用户私人数据（错题文本 + 答案明码），明文导出 JSON 若落到
  // 公共目录，其他 app 可读全文。轻量缓解（不等 AES-GCM 大工程）：
  // 导出前对文本字段做 token 级替换：
  //   - 学号：5 位及以上连续数字 → ×××（4 位及以下保留，如比例 "9331"）
  //   - 人名：以常见姓氏开头的 2-4 字连续中文 → 某某
  //
  // 限制（用户勾选「脱敏导出」即接受）：无 NLP / 词典，是**有损**脱敏
  // ——可能漏网（罕见姓氏 / 非常见写法），也可能过度（罕见以姓氏开头的
  // 词）。已通过「排除集」保护高频生物/日常词的误伤（见 _nameExclusion）。

  /// 学号：5 位及以上连续数字（20260001 等）→ ×××。
  static final RegExp _studentIdRe = RegExp(r'\d{5,}');

  /// 姓氏开头的常见词排除集（2 字词；3 字 token 若其 2 字前缀在此集合
  /// 同样跳过——覆盖「高茎豌豆→高茎」「黄体酮→黄体」「周长公式→周长」
  /// 这类生物/数学高频组合，避免「叶绿体→某某」式内容损毁）。
  ///
  /// v2.13 R4f（P1-1 · 四轮重审 Fix）：扩生物学术语保护——
  /// A verifier 实测「向光性/向地性/向水性/周皮/核黄素/胡蜂/孔隙/
  /// 林冠层/林下层」被吞成某某。补充：
  ///   - 向字头：向光/向地/向水/向性（向光性运动）/向心（向心加速度）
  ///   - 黄字头：黄素（核黄素——"核"非姓氏，正则从"黄"起匹配成「黄素」）
  ///   - 周字头：周皮（周皮细胞）
  ///   - 孔字头：孔隙/孔道
  ///   - 胡字头：胡蜂
  ///   - 林字头：林冠/林下/林缘（林冠层/林下层/林缘效应）
  ///
  /// v2.13 R4f2（P1 · 校园高频词）：错题本是校园场景，题干高频出现
  /// 年级/星期/考试词——「高三学生→某某生」「我上高一→我上某某」
  /// 「我写周记→我写某某」「周一上课→某某上课」等被正则当成人名
  /// 吞成某某，脱敏反而毁题。年级（高一/高二/高三/高中）、星期
  /// （周一~周日）、周系（周记/周末/周中/周测/周考）及考试词
  /// （月考/期中/期末/中考/高考）全量入集，任何位置都不换。
  static const Set<String> _nameExclusion = {
    // 生物/化学高频词（以姓氏字符开头）
    '黄体', '黄酮', '黄嘌呤', '黄豆', '黄瓜', '黄色', '黄金', '黄河', '黄叶',
    '黄绿', '黄曲', '黄斑', '黄白', '黄素', '黄化',
    '杨树', '杨柳', '杨梅',
    '周期', '周围', '周边', '周长', '周皮',
    // v2.13 R4f2（P1）：校园星期/周系高频词
    '周一', '周二', '周三', '周四', '周五', '周六', '周日',
    '周记', '周末', '周中', '周测', '周考',
    '马尾', '马路', '马上', '马力', '马蜂', '马蹄',
    '马铃薯', '马兜铃', '胡萝卜', '胡椒', '胡杨', '胡蜂',
    '高温', '高度', '高原', '高压', '高山', '高茎', '高粱', '高倍', '高血',
    // v2.13 R4f2（P1）：校园年级/考试高频词（高中生物是错题本主力场景）
    '高一', '高二', '高三', '高中', '高考',
    '孔雀', '向日葵',
    '张力', '李子', '李树', '林带', '林地', '林冠', '林下', '林缘',
    '向光', '向地', '向水', '向性', '向心',
    '孔隙', '孔道',
    // v2.13 R4f（P1-1）：A verifier 实测被误伤的完整 3 字词（双保险，
    // 位置启发式已挡，但整词入集保证任何边界情形都不换）
    '向光性', '向地性', '向水性', '核黄素', '林冠层', '林下层',
    // 日常高频词
    '许多', '曾经', '唐氏',
    // v2.13 R4f2（P1）：考试词兜底（月/期/中当前不在姓氏集内，
    // 双保险防止未来姓氏集扩充时误伤校园考试词）
    '月考', '期中', '期末', '中考',
    // v2.13 R8-P1：top 50 姓氏扩充的代价——需要补回生物/日常
    // 高频词。原则：「姓氏字符+1 字」形成非人名高频组合即入集。
    // 生物核心术语（叶绿体/杜鹃/丁香）+ 极常见词（任何/任意/几何/
    // 方程/程序/苏醒/苏打/罗盘/唐朝/唐代/田径/朱红/朱砂/徐徐/
    // 孙子/沈阳/桥梁/余弦/余数/董事/萧条/韩国/曹操/程度）
    // ——这些是高中生物题干里最可能被误伤的 2-char 词，必须
    // 入集保护。3-char 词通过 2-char 前缀规则兜底（叶绿体→叶绿
    // 在集 → 3-char 整体被 _isExcluded 拦下）。
    '叶绿', '叶脉', '叶片', '叶柄', '叶子',
    '杜鹃', '丁香',
    '任何', '任意',
    '几何', '方程', '程度', '程序',
    '苏醒', '苏打',
    '罗盘',
    '唐朝', '唐代', '韩国', '曹操',
    '田径', '朱红', '朱砂', '徐徐', '孙子', '沈阳',
    '桥梁', '余弦', '余数', '董事', '萧条',
  };

  /// v2.13 R4f（P1-1 · 四轮重审 Fix）：明确姓名位称谓词——
  /// 「学生张三」「李四同学」「王老师」等紧邻称谓的姓名为姓名位，
  /// 即使前后是汉字（无标点边界）也替换。
  static const Set<String> _nameContextWords = {
    '学生', '同学', '老师', '家长', '姓名', '名字', '考生', '监考', '阅卷',
  };

  /// v2.13 R4f（P1-1）：是否为 CJK 统一表意文字（单 code unit 判断，
  /// 汉字均在 BMP 内，s[idx] 取单 code unit 安全）。
  static bool _isHan(String ch) {
    if (ch.isEmpty) return false;
    final c = ch.codeUnitAt(0);
    return c >= 0x4e00 && c <= 0x9fff;
  }

  /// v2.13 R4f（P1-1）：保守姓名位判定——正则 token 级无 NLP，纯
  /// 「姓氏+1-2 字」会把「向光性/周皮/孔隙/胡蜂」等生物词误伤成某某，
  /// 且排除集挡不完（词表无限）。因此对 token 额外要求**姓名位信号**
  /// （宁可漏脱敏，不可毁题目）：
  ///   - 「姓+某」模糊名（张某 / 王某某）：作者已模糊化 → 无条件替换
  ///   - 紧邻称谓词位（学生张三 / 王小明同学 / 监考李四）：替换
  ///   - 独立词边界：前后任一侧为非汉字（行首/行尾/标点/空白/数字，
  ///     含已替换的 ××× 学号位）→ 替换（「张三 20260001」「张三在考场」
  ///     都命中）；**句中嵌字**（前后都是汉字且无称谓）→ 不换——
  ///     「植物具有向光性」「筛管孔隙」这类生物术语几乎总嵌在短语里，
  ///     天然被挡；已报误伤词全部进排除集兜底（含句首/句末边界情形）。
  ///     2 字与 3 字 token 同一规则（3 字名「张小明」行首同样替换，
  ///     不会误伤已入集词）。
  /// v2.13 R4f（保留为 fallback）：姓名位判定。R8-P1 主路径不
  /// 再用此函数（改为「姓氏首位 + 词长」直接判定，无姓名位信号
  /// 要求），但罕见姓氏（未进 _surnamesTop50）仍需姓名位启发式
  /// 兜底（如「孔明」「向明」紧邻称谓词位才替换）。
  static bool _isNamePositionAt(String s, int start, int end) {
    // 「姓+某」：已模糊化，无条件替换。
    if (s[end - 1] == '某') return true;
    final before = start == 0 ? '' : s[start - 1];
    final after = end >= s.length ? '' : s[end];
    // 称谓词位：紧邻 2 字是称谓词（学生张三 / 王小明同学）。
    if (start >= 2 &&
        _nameContextWords.contains(s.substring(start - 2, start))) {
      return true;
    }
    if (s.length - end >= 2 &&
        _nameContextWords.contains(s.substring(end, end + 2))) {
      return true;
    }
    // 独立词边界（前后任一侧非汉字）。
    return !_isHan(before) || !_isHan(after);
  }

  /// v2.13 R4-4：浅脱敏 token 级替换（学号 → ×××，人名 → 某某）。
  /// 只做正则 token 替换，不做全文理解；非脱敏导出不经过本方法。
  ///
  /// v2.13 R4f（P1-1 · 四轮重审 Fix）：加 _isNamePosition 位置启发式——
  /// 排除集只管「已知词」，未知的「姓氏+术语」组合（如「周质」「孔道」）
  /// 由姓名位信号兜底：句中嵌字（前后汉字且无称谓）不换，独立词
  /// 边界 / 称谓位 / 「姓+某」才换。已报误伤词（向光性/周皮/核黄素/
  /// 胡蜂/孔隙/林冠层等）全量入排除集，任何位置都不换。
  ///
  /// v2.13 R8-P1（NER 启发式升级）：主路径改为「首字在 top 50 姓氏
  /// + 词长 2-4」——**不再**要求姓名位信号。句中嵌字
  /// （"今天张三被选为班委"）也直接替换，解决 R6-P1 浅脱敏遗留
  /// P1 根因（孤立人名漏脱敏）。R4f 姓名位启发式保留为 fallback：
  /// 「姓+某」模糊名、紧邻称谓词位、独立词边界仍可命中罕见姓氏
  /// （未进 top 50 集合的字符）。排除集始终优先（见 _isExcluded）。
  ///
  /// v2.13 R8-P1（手动 token 化算法）：不用 RegExp.allMatches 的
  /// 贪心迭代（其 `m.end` 是最长匹配末尾，无法回头处理「匹配
  /// 内的子名字」如「李四和王」只取「李四」），改成 char-by-char
  /// 扫描 + 词长试探：
  ///   - 命中姓氏首字后试 2 字符、3 字符、4 字符
  ///   - 3+ 字符要求中间字符不能是功能词（被/的/是/在/和/与/或/
  ///     但/而/介词/代词/数词/量词）
  ///   - 第一个合法长度即采用（短名字优先）
  ///   - 找不到合法长度时回退 R4f 姓名位启发式
  /// 这样既保留 R4f 的位置启发式优势（保护「叶绿体」「向光性」等
  /// 嵌在句中的生物术语），又解决 P1 根因（孤立人名直接替换）。
  static String maskSensitive(String text) {
    if (text.isEmpty) return text;
    final s = text.replaceAll(_studentIdRe, '×××');
    final sb = StringBuffer();
    var last = 0;
    var i = 0;
    while (i < s.length) {
      // v2.13 R8-P1 主路径：姓氏首字 + 词长试探
      if (_surnamesTop50.contains(s[i])) {
        var foundLen = 0;
        // 试 2/3/4 字符（短名字优先——「李四」优先于「李四和」）
        for (var len = 2; len <= 4 && i + len <= s.length; len++) {
          // 中间字符必须是汉字（R4-4 正则 `[_surnameChars][\u4e00-\u9fa5]{1,2}`
          // 自然只匹配 Han 字符；手动循环需显式检查——避免
          // "何 怎么" 跨空格匹配 4 字符误伤"何"为名字）
          var allMiddleHan = true;
          for (var k = 1; k < len; k++) {
            if (!_isHan(s[i + k])) {
              allMiddleHan = false;
              break;
            }
          }
          if (!allMiddleHan) break;
          final subToken = s.substring(i, i + len);
          // 排除集优先：保护已知生物/校园/日常高频词
          if (_isExcluded(subToken)) break;
          // 必须是 top 50 姓氏开头的合法名字 token
          if (!_isLikelyPersonName(subToken)) break;
          // 3+ 字符：中间字符不能是功能词（"李四和王" 中 "和" 是
          // 功能词，不应被吞进名字）
          if (len >= 3) {
            var hasBoundaryInMiddle = false;
            for (var k = 1; k < len; k++) {
              if (_nameBoundaryChars.contains(subToken[k])) {
                hasBoundaryInMiddle = true;
                break;
              }
            }
            if (hasBoundaryInMiddle) break;
          }
          foundLen = len;
        }
        if (foundLen >= 2) {
          sb.write(s.substring(last, i));
          sb.write('某某');
          last = i + foundLen;
          i = last;
          continue;
        }
        // 主路径未命中：尝试 R4f fallback（针对罕见姓氏——
        // _surnameCharsFallbackSet 内的字符，未进 _surnamesTop50）
        if (_surnameCharsFallbackSet.contains(s[i])) {
          // 罕见姓氏 2-3 字符 + 姓名位启发式
          for (var len = (i + 3 <= s.length ? 3 : 2); len >= 2; len--) {
            if (i + len > s.length) continue;
            final subToken = s.substring(i, i + len);
            if (_isExcluded(subToken)) continue;
            if (_isNamePositionAt(s, i, i + len)) {
              sb.write(s.substring(last, i));
              sb.write('某某');
              last = i + len;
              i = last;
              foundLen = len; // 标记已处理
              break;
            }
          }
          if (foundLen >= 2) continue;
        }
        i++;
        continue;
      }
      i++;
    }
    sb.write(s.substring(last));
    return sb.toString();
  }

  /// 导出全部错题 + 回收站到 JSON 字符串。
  /// 返回的字符串可保存到 .json 文件，跨设备跨平台。
  ///
  /// v2.13 R4-4：文件头加「导出人提示」注释段（含导出时间 + 隐私提醒 +
  /// 导出范围），提醒该文件含个人数据、请勿公开分享。`desensitize=true`
  /// 时对题干 / 答案 / 考点 / AI 字段做浅脱敏（人名→某某、学号→×××）。
  /// 注释行以 `//` 开头，importJson 导入时会自动剥离（老格式无注释头，
  /// 同样兼容）。
  ///
  /// v2.13 R6-P1：默认 `desensitize=true` 强引导——用户主动选 `false`
  /// 才传明文。理由：导出 JSON 是明文包，落到下载 / 公共目录后其他 app
  /// 可读；浅脱敏可显著降低隐私暴露面。AES-GCM 端到端加密属重工程，
  /// 推到 R7 路线图（pubspec 未引入 cryptography / flutter_secure_storage
  /// 时不具备改造条件）；本轮先用「默认脱敏 + 显式明文二选一」覆盖 P1
  /// 隐私根因的「默认 desensitize=false 无强引导」一项。调用方（导出
  /// 对话框 / 单元测试）已相应调整。
  String exportJson({bool desensitize = true}) {
    final exportedAt = now();
    final m = <String, dynamic>{
      'schemaVersion': _exportSchemaVersion,
      'exportedAt': exportedAt.millisecondsSinceEpoch,
      'entries': [
        for (final e in _entries)
          (desensitize ? e.desensitized() : e).toJson(),
      ],
      'trash': [
        for (final t in _trash)
          desensitize
              ? {
                  'entry': t.entry.desensitized().toJson(),
                  'deletedAt': t.deletedAt.millisecondsSinceEpoch,
                }
              : t.toJson(),
      ],
    };
    // v2.13 R4-4：「导出人提示」段——文件头注释（导出时间 + 隐私提示）。
    final header = StringBuffer()
      ..writeln('// Biology 错题本导出 — 包含个人数据，请勿公开分享')
      ..writeln('// 导出时间：${_formatExportTime(exportedAt)}')
      ..writeln('// 导出范围：${_entries.length} 条错题 + ${_trash.length} 条回收站');
    if (desensitize) {
      header.writeln('// 脱敏导出：人名已替换为「某某」，学号已替换为「×××」');
    }
    // 格式化的 JSON（indent 2）方便人读 + diff；学生打开文件
    // 看到可读结构时不再觉得"黑箱"。
    // v2.13 R5 P0：移除"家长"——产品决策 Biology 不面向家长。
    return '$header${const JsonEncoder.withIndent('  ').convert(m)}';
  }

  /// v2.13 R4-4：导出文件头时间戳的本地格式化（yyyy-MM-dd HH:mm:ss）。
  static String _formatExportTime(DateTime t) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${t.year}-${two(t.month)}-${two(t.day)} '
        '${two(t.hour)}:${two(t.minute)}:${two(t.second)}';
  }

  /// v2.13 R8-P1：加密导出 envelope（用于 UI「加密导出（推荐）」菜单）。
  ///
  /// 流程：先用 `exportJson(desensitize: desensitize)` 拿到明文 JSON
  /// （保留现有注释头 / 脱敏标注 / 导出时间），再走
  /// `MistakeBookCrypto.encryptJson` 加密。返回 envelope 文本（自带
  /// `// Biology 错题本加密导出` 注释头 + JSON 主体）。
  ///
  /// 参数：
  ///   - [passphrase]：用户口令，**必须** ≥1 字符（弱口令由 dialog
  ///     层校验 ≥6 位后再传入；本方法不做格式校验只做非空）
  ///   - [desensitize]：默认 true——加密 + 浅脱敏双重保护。理由：用户
  ///     主动选加密导出场景下，多数仍会分发分享（家人 / 老师），浅脱敏
  ///     进一步降低风险。设为 false 走「加密 + 全文明文」但仍密文形式。
  ///
  /// 抛错：passphrase 为空 → ArgumentError；cryptography 内部错误 →
  /// FormatException（理论上不发生）。
  Future<String> exportEncryptedJson({
    required String passphrase,
    bool desensitize = true,
  }) async {
    // v2.13 R8-P1：先走明文导出（保留现有 exportJson 的注释头 / 脱敏标注
    // / 导出时间等 metadata），再走加密层包 envelope。
    final plain = exportJson(desensitize: desensitize);
    return MistakeBookCrypto.encryptJson(plain, passphrase);
  }

  /// 从 JSON 字符串导入错题。
  ///
  /// 顶层 dispatcher：
  ///   1. v2.13 R8-P1：先用 `MistakeBookCrypto.isEncryptedEnvelope` 嗅探
  ///      是否为加密 envelope（cipher=aes-256-gcm 的 JSON 包）。
  ///      - 是 envelope + [passphrase] 非空 → 走 `decryptJson` 拿到明文
  ///        → 递归调 `importJson(plain)` 走 V0/V1 dispatcher。
  ///      - 是 envelope + [passphrase] 为空/null → 抛 `FormatException`
  ///        「需要口令解密此加密文件」，让 UI 弹口令 dialog。
  ///      - 不是 envelope（明文 / 损坏 / 老 schema）→ 走原 V0/V1 路径
  ///        （[passphrase] 不传不强制；明文 + 有 passphrase 也走明文）
  ///   2. 读 schemaVersion 后分派到 V0（老格式兼容）或 V1（当前格式）。
  ///      返回新增到 _entries 的条数。
  ///
  /// 解析失败（JSON 根非 object / JSON 损坏 / 不支持的 schemaVersion）
  /// 抛 FormatException——调用方负责捕获并提示用户"文件格式不对"。
  ///（与 R1 final-B P0 #4 的 try/catch 链路对齐，_handleImport 会
  ///  catch 住不让 app crash。）
  ///
  /// v2.12+ R2 P0-B1：老用户跨设备导入兼容。
  ///   - 现状：v2.12.0+2 之前导出的 JSON 缺 schemaVersion 字段或
  ///     schemaVersion=0，importJson 严格校验「必须是 int 且 1≤v≤1」
  ///     → 老数据永远进不来。
  ///   - 修法：分派到 _importJsonV0（schemaVersion 0 / 缺失 / null）
  ///     走老路径：只读 entries，无 trash 恢复，老字段缺失按默认值
  ///     （aiSummary=null / aiPitfalls=[] / aiOverview=null）处理。
  ///
  /// v2.13 R6-P1：导入的是明文 JSON（非加密）——文件中可能含明文人名 /
  /// 学号 / 答案。调用方（`_handleImport` in `mistake_book_page.dart`）
  /// 在导入成功后必须弹 SnackBar 提示用户「导入文件未加密，请确认来源
  /// 可信」，避免陌生来源 JSON 被静默合并进个人错题本。R8-P1 起
  /// 加密 envelope 走 `decryptJson` 后再到本 dispatcher，明文路径
  /// 行为保留。
  Future<int> importJson(String raw, {String? passphrase}) async {
    // v2.13 R8-P1：先用 crypto 层嗅探 envelope。envelope = 含
    // cipher=aes-256-gcm 字段的 JSON（剥前导 // 注释后）。
    if (MistakeBookCrypto.isEncryptedEnvelope(raw)) {
      if (passphrase == null || passphrase.isEmpty) {
        throw const FormatException('需要口令解密此加密文件');
      }
      final plain = await MistakeBookCrypto.decryptJson(raw, passphrase);
      // 解密出来的明文走原 dispatcher（V0/V1 自动嗅探）。
      return importJson(plain);
    }
    // v2.13 R4-4：新版本 exportJson 在 JSON 前加「导出人提示」注释段
    // （`//` 开头）；导入前先剥离。老版本导出 / 用户手贴纯 JSON 无
    // 这些行 → 原样解析（兼容）。
    final cleaned = _stripExportHeader(raw);
    final decoded = jsonDecode(cleaned);
    if (decoded is! Map) {
      throw const FormatException('JSON 根必须是 object');
    }
    final v = decoded['schemaVersion'];
    if (v == null || (v is int && v == 0)) {
      // v2.12+ R2 P0-B1：老格式（V0 / 缺 schemaVersion）兼容。
      return _importJsonV0(decoded);
    }
    if (v is! int || v < 1 || v > _exportSchemaVersion) {
      throw FormatException('schemaVersion 不支持：$v');
    }
    // 当前格式：V1（schemaVersion=1）。
    return _importJsonV1(decoded);
  }

  /// v2.19.66：班级错题「合并导入」——与 [importJson]（覆盖式备份恢复）
  /// **并列**的另一条路径。
  ///
  /// 语义差异（写死在两条路径的入口文案里，防误点覆盖）：
  ///   - [importJson] = 「恢复备份（覆盖）」：按 id 去重追加 / 复用 trash 恢复
  ///   - 本方法 = 「合并同学错题包」：按 **题干+答案** 去重，只把新题追加进来、
  ///     每条打上 [sourceTag] 来源标，**本人 / 老师自己的题一条都不动**
  ///
  /// 返回 `(added, skipped)`：added = 实际追加条数；skipped = incoming 里
  /// 被去重跳过的条数（与现有条目重复 + 包里自身重复）。
  ///
  /// 加密包（[MistakeBookCrypto.isEncryptedEnvelope]）必须先给 [passphrase]，
  /// 否则抛 [FormatException]「需要口令解密此加密文件」——与 importJson 同款。
  ///
  /// ⛔ 不改 [importJson] 的语义：备份恢复照旧走它。本方法是**只增**路径。
  ///
  /// 追加时**重新分配 id**：源包的 id 是在同学机器上生成的，直接沿用有两条
  /// 隐患——① 与本地已有 id 撞（错题本页按 id 建 GlobalKey ⇒ 重复 key 崩）；
  /// ② 日后老师用覆盖式导入恢复自己的备份时，撞 id 会让**老师自己的题被
  /// 静默跳过**。分配新 id 后这两条都不可能发生（去重仍按 题干+答案）。
  Future<({int added, int skipped})> classMergeImport(
    String raw, {
    String? passphrase,
    String sourceTag = '来自同学',
  }) async {
    final incoming = await _parseIncomingEntries(raw, passphrase: passphrase);
    final toAdd = classIncomingToAdd(_entries, incoming, sourceTag: sourceTag);
    if (toAdd.isNotEmpty) {
      // 换新 id（见方法头注释），再追加。
      _entries.addAll([for (final e in toAdd) e.copyWith(id: _genId())]);
      _sortDesc();
      _trim();
      notifyListeners();
      _scheduleSave();
    }
    return (added: toAdd.length, skipped: incoming.length - toAdd.length);
  }

  /// v2.19.66：把一份导出包（明文 / 加密）解析成 [MistakeEntry] 列表。
  ///
  /// 只做「读」——不写库、不去重、不改 [importJson] 的任何行为。加密嗅探 +
  /// 注释头剥离 + schemaVersion 分派与 [importJson] 同口径（独立实现，避免
  /// 触碰覆盖式导入的既有代码）。
  ///
  /// 抛错：加密无口令 / JSON 根非 object / schemaVersion 不支持 / entries
  /// 非 array → [FormatException]（调用方 catch 弹 SnackBar）。单条损坏
  /// （fromJson 返 null）静默丢弃，不抛。
  Future<List<MistakeEntry>> _parseIncomingEntries(
    String raw, {
    String? passphrase,
  }) async {
    var source = raw;
    if (MistakeBookCrypto.isEncryptedEnvelope(source)) {
      if (passphrase == null || passphrase.isEmpty) {
        throw const FormatException('需要口令解密此加密文件');
      }
      source = await MistakeBookCrypto.decryptJson(source, passphrase);
    }
    final decoded = jsonDecode(_stripExportHeader(source));
    if (decoded is! Map) {
      throw const FormatException('JSON 根必须是 object');
    }
    final v = decoded['schemaVersion'];
    // 老格式（V0 / 缺 schemaVersion）与当前格式（V1）都从 entries 读；
    // 差异只在 entries 缺失的容忍度——这里合并导入**必须**有 entries。
    if (v != null && (v is! int || v < 1 || v > _exportSchemaVersion)) {
      throw FormatException('schemaVersion 不支持：$v');
    }
    final entriesJson = decoded['entries'];
    if (entriesJson is! List) {
      throw const FormatException('entries 字段必须是 array');
    }
    final out = <MistakeEntry>[];
    for (final j in entriesJson) {
      final e = MistakeEntry.fromJson(j);
      if (e != null) out.add(e);
    }
    return out;
  }

  /// v2.13 R4-4：剥离导出文件头注释段。
  ///
  /// 新版本 `exportJson()` 在 JSON 前写多行 `//` 注释（导出人提示 +
  /// 导出时间 + 脱敏标记）；标准 jsonDecode 不认 `//`，导入前把开头的
  /// 空行 / 注释行全部剥掉。V0 / V1 老格式（无注释头）原样返回。
  /// 解析容错：整段全是注释（异常文件）→ 返回空串，jsonDecode 抛
  /// FormatException，由调用方按"文件格式不对"处理。
  static String _stripExportHeader(String raw) {
    var s = raw;
    // Windows 记事本保存易带 UTF-8 BOM。
    if (s.startsWith('\uFEFF')) s = s.substring(1);
    final lines = s.split('\n');
    var i = 0;
    while (i < lines.length) {
      final line = lines[i].trim();
      if (line.isEmpty) {
        i++;
        continue;
      }
      if (line.startsWith('//')) {
        i++;
        continue;
      }
      break;
    }
    return lines.sublist(i).join('\n');
  }

  /// v2.12+ R2 P0-B1：V1 格式导入（R1 P0 #6 行为，含 trash 恢复）。
  ///
  /// 去重规则：
  ///   - 现有 _entries 里已存在的 id 跳过（保留本地最新版本——
  ///     假设本地版本可能有未同步的 AI 整理结果）
  ///   - 现有 _trash 里已存在的 id 跳过
  ///   - 其他按 createdAt 倒序追加到 _entries 末尾
  ///
  /// 返回新增到 _entries 的条数（不包含 trash 恢复）。
  /// V0 老 schema 不走这条路径（用 _importJsonV0）。
  int _importJsonV1(Map<dynamic, dynamic> decoded) {
    final entriesJson = decoded['entries'];
    if (entriesJson is! List) {
      throw const FormatException('entries 字段必须是 array');
    }
    final existingIds = {for (final e in _entries) e.id};
    final existingTrashIds = {for (final t in _trash) t.id};
    var added = 0;
    for (final j in entriesJson) {
      final e = MistakeEntry.fromJson(j);
      if (e == null) continue;
      if (existingIds.contains(e.id)) continue;
      // 如果 trash 里有同 id（之前从这台设备删过，又从别处导入），
      // 视为恢复（移到 entries，不重复）。
      if (existingTrashIds.contains(e.id)) {
        final restored = restoreFromTrash(e.id);
        if (restored != null) {
          existingIds.add(restored.id);
          added++;
        }
        continue;
      }
      _entries.add(e);
      existingIds.add(e.id);
      added++;
    }
    if (added > 0) {
      _sortDesc();
      _trim();
      notifyListeners();
      _scheduleSave();
    }
    return added;
  }

  /// v2.12+ R2 P0-B1：V0 老格式兼容导入。
  ///
  /// 场景：v2.12.0+2 之前导出的 JSON（缺 schemaVersion 字段，或
  /// schemaVersion=0）。老字段语义：
  ///   - `entries`：每项 = MistakeEntry 老格式（id / stem / userAnswer /
  ///     correctAnswer / errorType / subjectArea / createdAt /
  ///     reviewStatus / aiSummary? / aiPitfalls? / aiOverview?）
  ///   - 老格式**没有** `trash` 字段——V0 时错题本是 hard delete，
  ///     不存在软删除/回收站概念
  ///   - 老格式**没有** `aiOverview` 字段——V0 时 AI 整理只写
  ///     aiSummary + aiPitfalls，不写 per-entry overview
  ///   - aiSummary / aiPitfalls 字段可能缺失或为 null——按默认值
  ///     （null / []）处理，MistakeEntry.fromJson 已天然支持
  ///
  /// 行为：
  ///   - 现有 _entries 同 id 跳过（保留本地最新版本）
  ///   - 现有 _trash 跳过 V0 没有 trash 字段的检查（_trash 保留为
  ///     本地现有状态，不被 V0 导入影响）
  ///   - 顺序：按 JSON 内 entries 数组顺序追加
  ///
  /// 返回新增到 _entries 的条数。
  int _importJsonV0(Map<dynamic, dynamic> decoded) {
    // V0 老数据：entries 字段可能在 JSON 根也可能在 list 形式（极
    // 早期 v2.10 之前 exportJson 直接 dump entries 数组）。两都
    // 支持：root['entries'] 为空时尝试把 decoded 自身当 entries。
    dynamic entriesJson = decoded['entries'];
    if (entriesJson == null && decoded.isNotEmpty) {
      // 极早期 v2.10 之前 exportJson 可能直接输出 List<Entry>
      // （即 decoded 本身是 list 的展开）——但这里是 Map，不走
      // 这分支。保留占位避免日后误判。
      entriesJson = <dynamic>[];
    }
    if (entriesJson is! List) {
      // V0 没有 entries 字段是正常（极早期无错题时导出的空文件），
      // 不抛错，返回 0。
      return 0;
    }
    final existingIds = {for (final e in _entries) e.id};
    var added = 0;
    for (final j in entriesJson) {
      final e = MistakeEntry.fromJson(j);
      if (e == null) continue;
      if (existingIds.contains(e.id)) continue;
      _entries.add(e);
      existingIds.add(e.id);
      added++;
    }
    if (added > 0) {
      _sortDesc();
      _trim();
      notifyListeners();
      _scheduleSave();
    }
    return added;
  }

  /// 标记复习状态（便捷方法，比 update 更轻量）。
  ///
  /// v2.13 R3 P1-B4：每次标记都写 reviewedAt = now()——「最近复习」
  /// 排序的时间依据（用户主动复习操作 = 状态切换）。
  /// R5：标「已掌握」累计 masteredStreak（间隔退避依据）；标「还需复习」
  /// 清零——错题回来意味着上次的掌握判定作废。
  void markStatus(String id, MistakeReviewStatus status) {
    update(
        id,
        (e) => e.copyWith(
              reviewStatus: status,
              reviewedAt: now(),
              masteredStreak:
                  status == MistakeReviewStatus.mastered ? e.masteredStreak + 1 : 0,
            ));
  }

  /// 写入 AI 整理结果（单条）。
  ///
  /// v2.19.62：新增可选 [causeKey]（[MistakeCauseKey] 的 name）——整理成功
  /// 时把 AI 判定的结构化错因一并入库（错因雷达「AI 判」视图的数据源）。
  /// 传 null = 本次结果没带错因（旧模型输出 / 解析未命中白名单）⇒ 不动库。
  void applyAiAnalysis(String id,
      {String? summary, List<String>? pitfalls, String? causeKey}) {
    update(id, (e) {
      var next = e;
      if (summary != null) next = next.copyWith(aiSummary: summary);
      if (pitfalls != null) next = next.copyWith(aiPitfalls: pitfalls);
      if (causeKey != null) next = next.copyWith(causeKey: causeKey);
      return next;
    });
  }

  /// 写入 AI 整理「总览」块（每条相关的部分，由 `analyzeAll` 调用方分配）。
  void applyAiOverview(String id, String overview) {
    update(id, (e) => e.copyWith(aiOverview: overview));
  }

  // ─── v2.13 R3 P1-B4：搜索 / 错因筛选 / 排序（数据侧） ─────────
  //
  // 100+ 条错题时页面需要「找得到」入口。把筛选逻辑放在数据层
  // （而非页面临时 where/sort），页面只持有 3 个状态（搜索词 / 错因
  // 类型 / 排序方式）每次 build 调一次 query()。
  //
  // 排序定义：
  //   - createdAt：_entries 本身就是该序（_sortDesc），保持原序。
  //   - errorType：枚举顺序分组（概念→计算→理解→粗心→其他），
  //     组内最近添加在前——把同类错题聚在一起，复习时按类过。
  //   - recentReview：reviewedAt 倒序（最近复习过的最先），从未
  //     复习过的排在已复习的后面（组内按最近添加）。
  //   - mostErrorProne：全量统计各错因出现次数（不随筛选变化，
  //     结果稳定），出现最多的错因类型排最前——「错得最多的先看」。

  /// v2.13 R3 P1-B4 + R4 P1：搜索 + 错因筛选 + 复习状态筛选 + 排序。
  ///
  /// [search]：多字段子串匹配，不区分大小写；空/空白视为不过滤。
  /// 匹配字段：题目摘要（stem）、关联考点（subjectArea）、AI 错因
  /// （aiPitfalls 每行）、正确答案（correctAnswer）——错题 stem 可能
  /// 只写「两对基因」，考点 / 错因在 subjectArea / aiPitfalls，单字段
  /// 搜索会漏（「搜索 9331」场景落空）。匹配的是用户录入时的原始
  /// 文本（不做分词）。
  /// [type]：错误类型筛选；null = 全部。
  /// [unreviewedOnly]：仅看未复习（reviewedAt == null）；false = 全部。
  /// v2.13+ 零插件间隔复习（艾宾浩斯的本地实现，不依赖通知插件——
  /// 提醒入口 = 页顶「今日待复习」横幅 + dashboard 未复习徽标）：
  ///   未复习   —— 随时到期（新错题即欠账）
  ///   复习中   —— reviewedAt ≥1 天前到期（再认一遍）
  ///   已掌握   —— 按 masteredStreak 退避：1 次=3 天、2 次=7 天、
  ///                3 次=14 天、4 次=30 天、5 次=60 天、≥6 次=120 天
  ///                （R5：原固定 3 天会让「已掌握」题永久轮回，错题本越攒
  ///                复习债越多；v2.19.63：由 4 级延到 6 级，让真正稳固的
  ///                题不再频繁回炉）
  /// reviewedAt 为空一律视为到期。数据字段 v2.12 已落盘，本查询纯函数。
  List<MistakeEntry> dueEntries({DateTime? now}) {
    final t = now ?? DateTime.now();
    bool due(MistakeEntry e) {
      final r = e.reviewedAt;
      if (r == null) return true;
      final days = t.difference(r).inDays;
      switch (e.reviewStatus) {
        case MistakeReviewStatus.unreviewed:
          return true;
        case MistakeReviewStatus.reviewing:
          return days >= 1;
        case MistakeReviewStatus.mastered:
          final s = e.masteredStreak;
          // v2.19.63：退避阶梯由 4 级延到 6 级——3 / 7 / 14 / 30 / 60 / 120
          // 天（原 ≥4 次封顶 30 天）。仍然同形分桶：streak 超出现有最大档
          // 一律按 120 顶。纯规则改动，落盘字段与 schema 不变。
          final interval = s >= 6
              ? 120
              : (s >= 5
                  ? 60
                  : (s >= 4
                      ? 30
                      : (s >= 3 ? 14 : (s >= 2 ? 7 : 3))));
          return days >= interval;
      }
    }

    return _entries.where(due).toList()
      ..sort((a, b) {
        // 未复习优先，其次最早复习的（欠账最久的在前）。
        final ra = a.reviewedAt, rb = b.reviewedAt;
        if (ra == null && rb == null) return 0;
        if (ra == null) return -1;
        if (rb == null) return 1;
        return ra.compareTo(rb);
      });
  }

  /// [sort]：排序方式，默认最近添加（现有 createdAt 倒序行为）。
  List<MistakeEntry> query({
    String search = '',
    MistakeErrorType? type,
    MistakeSortMode sort = MistakeSortMode.createdAt,
    bool unreviewedOnly = false,
    /// v2.19.66：仅看本人——只留 [MistakeEntry.sourceTag] 为空的条目
    /// （合并进来的同学题被筛掉）。
    bool ownOnly = false,
  }) {
    final q = search.trim().toLowerCase();
    final visible = <MistakeEntry>[];
    for (final e in _entries) {
      if (type != null && e.errorType != type) continue;
      if (unreviewedOnly && e.reviewedAt != null) continue;
      if (ownOnly && (e.sourceTag != null && e.sourceTag!.trim().isNotEmpty)) {
        continue;
      }
      if (q.isNotEmpty && !_matchesSearch(e, q)) continue;
      visible.add(e);
    }
    switch (sort) {
      case MistakeSortMode.createdAt:
        break; // _entries 已按 createdAt 倒序，保持原序
      case MistakeSortMode.errorType:
        visible.sort((a, b) {
          final c = a.errorType.index.compareTo(b.errorType.index);
          return c != 0 ? c : b.createdAt.compareTo(a.createdAt);
        });
      case MistakeSortMode.recentReview:
        visible.sort((a, b) {
          final ar = a.reviewedAt;
          final br = b.reviewedAt;
          if (ar != null && br != null) {
            final c = br.compareTo(ar);
            return c != 0 ? c : b.createdAt.compareTo(a.createdAt);
          }
          if (ar != null) return -1; // a 复习过 → 前
          if (br != null) return 1; // b 复习过 → 前
          return b.createdAt.compareTo(a.createdAt);
        });
      case MistakeSortMode.mostErrorProne:
        final freq = <MistakeErrorType, int>{};
        for (final e in _entries) {
          freq[e.errorType] = (freq[e.errorType] ?? 0) + 1;
        }
        visible.sort((a, b) {
          final c = (freq[b.errorType] ?? 0).compareTo(freq[a.errorType] ?? 0);
          return c != 0 ? c : b.createdAt.compareTo(a.createdAt);
        });
    }
    return List.unmodifiable(visible);
  }

  /// v2.13 R4 P1：搜索命中判定——stem / subjectArea / aiPitfalls /
  /// correctAnswer 任一字段含关键词即命中。
  bool _matchesSearch(MistakeEntry e, String q) {
    if (e.stem.toLowerCase().contains(q)) return true;
    if (e.subjectArea.toLowerCase().contains(q)) return true;
    if (e.correctAnswer.toLowerCase().contains(q)) return true;
    for (final p in e.aiPitfalls) {
      if (p.toLowerCase().contains(q)) return true;
    }
    return false;
  }

  // ─── v2.12+ R1 P0 #3：AI 主动整理后台队列 ─────────────
  //
  // 产品宣传"AI 主动整理"——v2.12 之前是「错题本 + 卡片底部 AI 整理按钮」
  // 手动触发（_handleAiSingle），与「主动」语义不符。本节把 AI 整理
  // 变成「加错题后自动入队 + 500ms debounce 后台批量跑」：
  //
  //   - `debugEnqueueAiOrganize(entryId)`：页面 add 完调一下入队
  //   - `_aiOrganizeDebounce`：500ms debounce 计时器
  //   - `_pendingAiOrganize`：待跑 id 集合（防重复入队）
  //   - `_runAiOrganize()`：跑 MistakeBookAi.analyzeSingle + 写回
  //
  // 设计权衡：
  //   - 500ms 经验值：长于手抖连点（<200ms），短于用户感知"卡顿"阈值
  //   - 调用方不需要 await —— 后台 fire-and-forget，主流程（SnackBar
  //     提示、错题本列表立即可见）不被网络抖动阻塞
  //   - 不阻塞首屏：错题本实例是 ChangeNotifier，notifyListeners 在
  //     AI 完成时才触发，避免每条 entry 都触发 rebuild

  /// 测试注入：mock AI 发送器（同 MistakeBookAi.debugSender）。
  /// 非 null 时 `_runAiOrganize` 走注入而非真实网络。
  static Future<MistakeAiAnalysis?> Function(MistakeEntry e)?
      debugOrganizeSender;

  /// 待跑的 entry id 集合。
  final Set<String> _pendingAiOrganize = <String>{};

  /// 500ms debounce 计时器。
  Timer? _aiOrganizeDebounce;
  static const Duration _aiOrganizeDebounceWindow =
      Duration(milliseconds: 500);

  /// 当前正在跑的 `_runAiOrganize` Future 列表。测试用 await
  /// `debugWaitAiOrganizeDone` 等所有 in-flight 调用完成。
  final List<Future<void>> _aiOrganizeFutures = [];

  /// 入队一条待 AI 整理的 entry。500ms 内多次入队会合并成一次批跑
  /// （debounce）。已存在 aiSummary 的 entry 会被跳过（避免重写
  /// 用户已手动整理过的结果）。
  void debugEnqueueAiOrganize(String entryId) {
    final entry = findById(entryId);
    if (entry == null) return;
    if (entry.aiSummary != null && entry.aiSummary!.isNotEmpty) return;
    _pendingAiOrganize.add(entryId);
    _aiOrganizeDebounce?.cancel();
    _aiOrganizeDebounce = Timer(_aiOrganizeDebounceWindow, () {
      _aiOrganizeDebounce = null;
      _runAiOrganize();
    });
  }

  /// 内部执行：批量跑 pending 集合里所有 entry 的 organizeSingle。
  /// fire-and-forget；调用方不需要 await。
  /// 测试用 `debugWaitAiOrganizeDone()` 同步等待本 Future 完成。
  Future<void> _runAiOrganize() {
    final future = _doRunAiOrganize();
    _aiOrganizeFutures.add(future);
    future.then((_) => _aiOrganizeFutures.remove(future));
    return future;
  }

  Future<void> _doRunAiOrganize() async {
    if (_pendingAiOrganize.isEmpty) return;
    final pending = List<String>.from(_pendingAiOrganize);
    _pendingAiOrganize.clear();
    for (final id in pending) {
      final entry = findById(id);
      if (entry == null) continue;
      if (entry.aiSummary != null && entry.aiSummary!.isNotEmpty) continue;
      MistakeAiAnalysis? analysis;
      try {
        // 优先用 debugOrganizeSender 注入（测试用）；否则走真实
        // MistakeBookAi.analyzeSingle 链路（会调 AiClient）。
        final sender = debugOrganizeSender;
        if (sender != null) {
          analysis = await sender(entry);
        } else {
          analysis = await MistakeBookAi.analyzeSingle(entry);
        }
      } catch (_) {
        // AI 整理失败不抛错（与「主流程不被网络抖动阻塞」承诺对齐）。
        continue;
      }
      if (analysis == null) continue;
      // applyAiAnalysis 内部走 update + notifyListeners，UI 端监听者
      // （mistake_book_page）可以借此刷掉「AI 整理中…」hint。
      applyAiAnalysis(id,
          summary: analysis.summary,
          pitfalls: analysis.pitfalls,
          causeKey: analysis.causeKey);
    }
  }

  /// 测试用：等待所有 in-flight `_runAiOrganize` Future 完成。
  /// widget tester 场景下，`_runAiOrganize` 是 timer 触发的
  /// fire-and-forget Future，测试 body 退出后这个 Future 仍可能
  /// pending——`_verifyInvariants` 会报"pending timer"红（虽然
  /// 不是真 timer，但 FakeAsync 把 Future 也算作 pending）。
  ///
  /// 修法：测试 body 末尾调 `debugWaitAiOrganizeDone()` + 再
  /// `pumpAndSettle`，等所有 Future 跑完。
  @visibleForTesting
  Future<void> debugWaitAiOrganizeDone() async {
    while (_aiOrganizeFutures.isNotEmpty) {
      final futures = List<Future<void>>.from(_aiOrganizeFutures);
      try {
        await Future.wait(futures);
      } catch (_) {
        // _runAiOrganize 内部已经 catch 所有异常，这里再 catch 兜底
      }
    }
  }

  /// 测试用：清空 pending 集合 + cancel debounce timer。
  /// **不**碰磁盘；**不**撤回已跑的 AI 整理结果。
  @visibleForTesting
  void debugResetAiOrganize() {
    _pendingAiOrganize.clear();
    _aiOrganizeDebounce?.cancel();
    _aiOrganizeDebounce = null;
    debugOrganizeSender = null;
    // 不清 _aiOrganizeFutures——in-flight Future 由调用方 await
    // debugWaitAiOrganizeDone() 主动等。
  }

  /// v2.13 R3 P1-B3：批量 AI 整理（AppBar「AI 整理全部」按钮触发）。
  ///
  /// 与后台自动队列（`_runAiOrganize`）不同：这是用户点按钮的显式
  /// 批量整理，一次请求跑全部未整理条目。成功条目直接写回
  /// （applyAiAnalysis），并返回带失败原因的结果——页面按成功数
  /// 分支显示：全失败弹「批量整理失败（0/N）」+ 原因，不再出现
  /// 「批量整理完成：0 / N」假成功。
  ///
  /// 失败原因透传自 `MistakeBookAi.analyzeAllDetailed`（`res.error`：
  /// 未配置 AI / 网络错误 / HTTP 错误）；AI 返回了内容但解析不出
  /// 结果时 `failureReason` 为 null。
  Future<BatchOrganizeOutcome> organizeBatch(List<MistakeEntry> entries) async {
    if (entries.isEmpty) {
      return BatchOrganizeOutcome(total: 0, successes: const {});
    }
    final outcome = await MistakeBookAi.analyzeAllDetailed(entries);
    for (final e in outcome.successes.entries) {
      applyAiAnalysis(e.key,
          summary: e.value.summary,
          pitfalls: e.value.pitfalls,
          causeKey: e.value.causeKey);
    }
    return outcome;
  }

  /// 按 createdAt 倒序。
  ///
  /// v2.12 P0-3 修复：实测 `flutter test test/state/mistake_book_test.dart`
  /// 出现 1/5 失败——同毫秒连 add 3 条时，compareTo 返 0 → `List.sort` 顺序
  /// 随机。Dart `List.sort` 实现是 merge sort 但 **ISO spec 不保证 stable**，
  /// 所以同 createdAt 时 compareTo 返 0 → 顺序随机。加 id 倒序 tie-breaker
  /// 保证「同毫秒 → 后生成（id 含 24-bit 随机）排在前面」是确定的。
  void _sortDesc() {
    _entries.sort((a, b) {
      final c = b.createdAt.compareTo(a.createdAt);
      return c != 0 ? c : b.id.compareTo(a.id);
    });
  }

  /// 超过 maxEntries 时丢弃最旧。
  void _trim() {
    if (_entries.length > maxEntries) {
      _entries.removeRange(maxEntries, _entries.length);
    }
  }

  int _indexOf(String id) {
    for (var i = 0; i < _entries.length; i++) {
      if (_entries[i].id == id) return i;
    }
    return -1;
  }

  int _trashIndexOf(String id) {
    for (var i = 0; i < _trash.length; i++) {
      if (_trash[i].id == id) return i;
    }
    return -1;
  }

  void _sortTrashDesc() {
    _trash.sort((a, b) => b.deletedAt.compareTo(a.deletedAt));
  }

  // ---- 持久化（桌面/安卓 File；Web localStorage） ----

  static String _file() {
    if (debugFilePath != null) return debugFilePath!;
    final appDir = userAppDir();
    if (appDir == null) return 'mistake_book.json'; // Web 兜底占位
    final dir = Directory(appDir);
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return '${dir.path}/mistake_book.json';
  }

  /// v2.12 Round 1 P0 #5：回收站文件路径（与 _file() 同目录）。
  /// 默认走 debugFilePath 同路径 + 不同文件名；测试可单独注入。
  static String? debugTrashFilePath;

  static String _trashFile() {
    if (debugTrashFilePath != null) return debugTrashFilePath!;
    if (debugFilePath != null) {
      return debugFilePath!.replaceAll(RegExp(r'\.json$'), '.trash.json');
    }
    final appDir = userAppDir();
    if (appDir == null) return 'mistake_book_trash.json';
    final dir = Directory(appDir);
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return '${dir.path}/$_trashFileName';
  }

  void _save() {
    final trimmed = _entries.length > maxEntries
        ? _entries.sublist(0, maxEntries)
        : _entries;
    final s = jsonEncode([for (final e in trimmed) e.toJson()]);
    final sTrash = jsonEncode([for (final t in _trash) t.toJson()]);
    try {
      // v2.12+ R2 P1-1：用 _isWebStorage 替代 isWebStorage，让 test
      // 可强制走 web 路径。
      if (_isWebStorage) {
        storageSet(_key, s);
        storageSet(_trashKey, sTrash);
        return;
      }
      File(_file()).writeAsStringSync(s);
      File(_trashFile()).writeAsStringSync(sTrash);
    } catch (e) {
      // 写盘失败不抛错；v2.13 R3 W1 P0：debugPrint 暴露失败原因——
      // 之前 catch(_) 静默吞 → Android 目录异常时错题本/回收站全丢，
      // 用户零提示。
      debugPrint('[biology] MistakeBook save failed: $e');
    }
  }

  /// v2.12 Wave 3-B P1-1：写盘 debounce。500ms 内的多次 add/update/delete
  /// 只触发 1 次实际磁盘写入。AI 批量整理 8 条时实测：原来 8 次 writeAsStringSync
  /// 约 80ms → debounce 后 1 次 < 10ms，且不会因每条都 disk I/O 抖动 UI 帧。
  ///
  /// 边界：
  /// - dispose 时若有未落盘修改（_dirty=true 且 timer 未触发），flush 一次。
  /// - 首次写入时 _dirty=true 但 timer 仍 null → 走 timer，正常 debounce。
  void _scheduleSave() {
    _dirty = true;
    _saveDebounce?.cancel();
    _saveDebounce = Timer(_saveDebounceWindow, () {
      _saveDebounce = null;
      if (_dirty) {
        _dirty = false;
        _save();
      }
    });
  }

  /// v2.12 Wave 3-B P1-1：测试 + dispose 共用——立即落盘（取消 pending timer）。
  /// 用于测试断言"我刚 add 的内容应该已经写盘"。
  @visibleForTesting
  void debugFlushSave() {
    _saveDebounce?.cancel();
    _saveDebounce = null;
    if (_dirty) {
      _dirty = false;
      _save();
    }
  }

  /// v2.12 Wave 3-B P1-1：单例 dispose 兜底——测试间不调，但理论上 app
  /// 关闭时若有 pending 写盘需要 flush。当前 app 关闭 = OS kill，不会
  /// 走 dispose；保留以备后续 hot-restart 流程用到。
  @override
  void dispose() {
    debugFlushSave();
    super.dispose();
  }

  /// 生成唯一 id：时间戳 + 6 位单调递增后缀（保证 later add 拿到更大 id）。
  /// 不引入 uuid 依赖（v2.11 plan 约束「无新增依赖」）。
  ///
  /// v2.12 Wave 3-B P1-1：`Random()` 改 `Random.secure()`——安全随机源，
  /// 同毫秒内多次 add 也不会拿到相同 id 序列（之前同毫秒随机碰撞概率
  /// 24 bit = 1/16777216，10k 条样本里至少出现 1 次重复，_sortDesc
  /// tie-breaker 掩盖了 bug 表面但底层不健壮）。
  ///
  /// v2.12 Wave 3-B P1 补：再改 monotonic counter——Random.secure() 24 bit
  /// 在 1/6 概率下随机顺序 ≠ add 顺序（a/b/c 3 条同毫秒 add，c 不一定
  /// 拿到最大 random），导致 `state/mistake_book_test.dart` 的
  /// 「[c.id, b.id, a.id]」断言 flaky。counter 模式：
  ///   - later add 永远拿到更大 id（_idCounter 单调递增）
  ///   - _sortDesc tie-breaker `b.id.compareTo(a.id)`（bigger id first）
  ///     把 later add 排到前面，行为确定
  ///   - 单例 dispose 不重置 counter（counter 跨 add 持久化保证
  ///     monotonic；测试间通过 debugReset 清内存但不重置 counter，
  ///     因为 counter 是 static 状态，进程内只增不减）
  static int _idCounter = 0;
  static String _genId() {
    final ts = DateTime.now().millisecondsSinceEpoch;
    final r = _idCounter++; // 24 bit monotonic（同进程内）
    return 'm_${ts.toRadixString(16)}_${r.toRadixString(16).padLeft(6, '0')}';
  }
}

// ============================================================================
// v2.12 Round 1 P0 #6：跨设备导出助手
// ============================================================================

/// 错题本导出 / 导入跨设备桥。
///
// 桌面 / 安卓：直接写文件到 ~/Downloads/（或应用目录兜底）。
// Web：条件导入到 web_exporter_web.dart（package:web 触发 <a> download）。
///
// 错误处理：写盘失败 / Web 触发失败返 null，调用方显示「导出失败」
// SnackBar；不抛异常破坏主流程（同 _save() 的 catch-all 哲学）。
class MistakeBookExporter {
  MistakeBookExporter._();

  /// 测试注入：覆盖下载目录（用于临时文件测试）。
  /// 非空时 saveToDownloads 走该目录而非 ~/Downloads。
  static String? debugDownloadsDir;

  /// v2.13 R4-2（P1-2 EACCES 修复）：测试注入——强制模拟 Android 导出分支。
  ///
  /// flutter_test 跑在 VM 上 `Platform.isAndroid` 恒为 false，无法直接
  /// 测 Android 导出路径 / SnackBar 文案 / 分享按钮；置 true 后
  /// [isAndroidExport] 走 Android 分支（配合 [debugDownloadsDir] 或
  /// storage_io.debugForceIsAndroid + appDirChannel mock 注入）。
  @visibleForTesting
  static bool? debugForceIsAndroid;

  /// 导出流程当前是否按 Android 处理。
  ///
  /// Android 上导出文件只落应用专属目录（getFilesDir，见
  /// [_resolveDownloadsDir] / png_export_io.writePng），用户看不到公共
  /// Downloads → SnackBar 文案诚实告知「已保存到应用目录」+ 提供 [分享]。
  static bool get isAndroidExport =>
      debugForceIsAndroid ?? (!kIsWeb && Platform.isAndroid);

  /// 保存 JSON 字符串到下载目录，返回用户可见的文件路径或错误说明。
  /// [baseName] 不含扩展名（自动加 .json）。
  static Future<String?> saveToDownloads(
      String json, String baseName) async {
    // v2.13 R4-2（P1-2 EACCES 修复）：Android 导出前先等 getFilesDir()
    // 缓存就绪，保证 _resolveDownloadsDir 拿到真实应用专属目录（否则
    // 回退 '/' 抛 EACCES）。桌面 / Web no-op。
    await ensureAppDirReady();
    // v2.12+ R2 P1-1：走 debugForceIsWebStorage ?? isWebStorage 三态，
    // 兼容 test 注入。
    if (MistakeBook.debugForceIsWebStorage ?? isWebStorage) {
      return _saveWeb(json, baseName);
    }
    return _saveDesktop(json, baseName);
  }

  /// v2.12+ R2 P0-B2：保存 PNG 字节到下载目录 / 触发浏览器下载。
  ///
  /// 与 saveToDownloads 同样的 web / desktop 分流：
  ///   - 桌面：File 写到 ~/Downloads/（_resolveDownloadsDir 路径）
  ///   - Android（v2.13 R4-2）：写应用专属目录（userAppDir / getFilesDir）
  ///   - Web：触发 <a download> Blob 浏览器下载
  ///
  /// 返回用户可见的文件路径（桌面 / 安卓）或「已触发浏览器下载」标记
  /// （Web）。失败返错误说明。**不**抛异常。
  static Future<String?> savePngToDownloads(
      Uint8List bytes, String baseName) async {
    // v2.13 R4-2（P1-2 EACCES 修复）：Android 导出前先等 getFilesDir()
    // 缓存就绪（同 saveToDownloads）。桌面 / Web no-op。
    await ensureAppDirReady();
    // v2.12+ R2 P1-1：走 debugForceIsWebStorage ?? isWebStorage 三态。
    if (MistakeBook.debugForceIsWebStorage ?? isWebStorage) {
      try {
        webTriggerPngDownload(bytes, '$baseName.png');
        return '已触发浏览器下载';
      } catch (e) {
        return '导出失败：$e';
      }
    }
    try {
      final dir = _resolveDownloadsDir();
      if (dir == null) return '未找到可写目录';
      final f = File('${dir.path}${Platform.pathSeparator}$baseName.png');
      await f.writeAsBytes(bytes, flush: true);
      return f.path;
    } catch (e) {
      return '导出失败：$e';
    }
  }

  /// v2.12+ R2 P0-B2 + P1：在系统文件管理器中显示该文件。
  ///
  /// 跨端：
  ///   - Windows：`explorer.exe /select,<path>` 高亮选中单文件
  ///   - macOS：`open -R <path>` 在 Finder 中显示
  ///   - Linux：`xdg-open <dirname>` 打开父目录（xdg-open 本身不支持
  ///     选中单文件，但打开父目录是 99% 老师能接受的兜底）
  ///   - Web / Android：无文件管理器概念，返错误原因，调用方按需
  ///     隐藏 SnackBar [打开下载目录] action
  ///
  /// v2.12+ R2 A2 P1-5：返回值从 bool 改为 `String?`——null = 成功，
  /// 非 null = 失败原因（可直接显示给用户）。Process.start 是 GUI
  /// launcher，理论上不产 stdout/stderr，但防御性 await + 5 秒
  /// timeout 兜底（极端挂起不阻塞 UI），异常按失败处理返回原因。
  /// **不**抛错（维持既有"调用方不需要 try/catch"契约）。
  ///
  /// v2.12+ R2 A2 P1-6：web 端调用方（dashboard _showBoardInExplorer）
  /// 应在调用前拦截；本方法内部 Platform 分支在 web 会抛
  /// UnsupportedError（dart:io stub），由 catch 兜底为失败原因。
  ///
  /// 设计：把 dashboard_page 的 _showBoardInExplorer 私有方法抽成
  /// 公开静态 API，供错题本导出 / 板书导出共用。
  static Future<String?> openInExplorer(String path) async {
    // 公开 API，调用方不一定在 Web 上拦截（cross_calculator / 系谱页多处
    // 直接调）。这里先判别，避免把「程序包 xxx 不存在」这类技术错误弹给用户。
    if (kIsWeb) return '网页版无法打开文件管理器，请改用页面上的下载入口。';
    try {
      if (Platform.isWindows) {
        // /select, 后面紧跟路径；逗号无空格。Process.start args 用 list，
        // 避免整段命令字符串解析。
        await _launchProcess('explorer.exe', ['/select,', path]);
        return null;
      } else if (Platform.isMacOS) {
        await _launchProcess('open', ['-R', path]);
        return null;
      } else if (Platform.isLinux) {
        // xdg-open 不支持 select；打开父目录。
        final dir = File(path).parent.path;
        await _launchProcess('xdg-open', [dir]);
        return null;
      }
      return '当前平台不支持在文件管理器中显示';
    } catch (e) {
      return '在文件管理器中显示失败：$e';
    }
  }

  /// v2.12+ R2 A2 P1-5：测试注入——非 null 时 `openInExplorer` 用它
  /// 替代 `Process.start`（flutter_test 无法 mock dart:io 进程启动，
  /// 注入后测试可模拟"启动抛异常 / 启动挂起"两条失败路径）。
  @visibleForTesting
  static Future<Process> Function(String executable, List<String> arguments)?
      debugProcessLauncher;

  /// v2.12+ R2 A2 P1-5：启动 GUI 文件管理器 launcher。
  ///
  /// dart:io GUI launcher（explorer.exe / open / xdg-open）不产
  /// stdout/stderr，但防御性 await + 5 秒 timeout：极端情况（启动
  /// 挂起）不阻塞 UI；超时 / 抛错统一由调用方按「失败」处理。
  static Future<void> _launchProcess(
      String executable, List<String> args) async {
    final custom = debugProcessLauncher;
    if (custom != null) {
      await custom(executable, args).timeout(const Duration(seconds: 5));
      return;
    }
    await Process.start(executable, args).timeout(const Duration(seconds: 5));
  }

  /// 桌面：File 写到 ~/Downloads（_resolveDownloadsDir 解析）。
  /// Android（v2.13 R4-2 P1-2 EACCES 修复）：写应用专属目录
  /// （userAppDir = `getFilesDir`/.biology_app，无需任何存储权限）。
  static Future<String?> _saveDesktop(
      String json, String baseName) async {
    try {
      final dir = _resolveDownloadsDir();
      if (dir == null) return '未找到可写目录';
      final f = File('${dir.path}${Platform.pathSeparator}$baseName.json');
      await f.writeAsString(json, flush: true);
      return f.path;
    } catch (e) {
      return '导出失败：$e';
    }
  }

  /// Web：触发 <a download> 锚点击让浏览器下载。
  static String? _saveWeb(String json, String baseName) {
    try {
      webTriggerDownload(json, '$baseName.json');
      return '已触发浏览器下载';
    } catch (e) {
      return '导出失败：$e';
    }
  }

  /// 解析导出目录。
  ///   - 桌面：优先 ~/Downloads，失败用 '.'（cwd）兜底（v2.10 行为）。
  ///   - Android（v2.13 R4-2 P1-2 EACCES 修复）：**不再碰公共 Downloads**
  ///     ——targetSdk 35 scoped storage + 零存储权限下写
  ///     /storage/emulated/0/Download 必抛 EACCES。改走 userAppDir()
  ///     （= `getFilesDir`/.biology_app，R3 W1 已修好且 7 store 接入），
  ///     应用专属目录无需任何权限。
  static Directory? _resolveDownloadsDir() {
    if (debugDownloadsDir != null) {
      return Directory(debugDownloadsDir!)..createSync(recursive: true);
    }
    if (isAndroidExport) {
      final appDir = userAppDir();
      if (appDir == null) return null;
      return Directory(appDir)..createSync(recursive: true);
    }
    final candidates = <String>[];
    final home = kIsWeb
        ? null
        : (Platform.environment['USERPROFILE'] ?? Platform.environment['HOME']);
    if (home != null) {
      candidates.add('$home${Platform.pathSeparator}Downloads');
    }
    candidates.add('.'); // cwd 兜底
    for (final p in candidates) {
      try {
        final d = Directory(p);
        if (!d.existsSync()) d.createSync(recursive: true);
        return d;
      } catch (_) {
        continue;
      }
    }
    return null;
  }
}

/// Web 端下载触发（条件编译入口）。
// 桌面 / 安卓：stub 返 false（不会被调到，因 saveToDownloads 分流到
// _saveDesktop）。
// Web：实际走 package:web + dart:js_interop。
