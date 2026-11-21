// pedigree_inference_view.dart —— 系谱推断器 UI（v2.13+）
//
// 宿主：人类遗传病页（genetic_disease_page）「系谱推断」分区——
// 课标 3.2.6「系谱分析」教学场景：给一张家族遗传病系谱图，判断遗传方式。
// 引擎见 lib/engine/pedigree_inference.dart（纯规则打分 + 人话依据条文）。
//
// 交互模型（v1，运行框架哲学：录入 → 引擎 → 呈现）：
// - 逐成员录入：性别 / 表型 / 父亲 / 母亲（下拉选已录成员，代际自动推导）
// - 4 个经典金标准一键载入（课堂演示与学生自学各取所需）
// - 运行 → 最可能结论卡 + 候选列表（未排除按分数降序，evidence 逐条呈现）
// - v2.13+ 学生走查 P0：录入草稿持久化——录 5 分钟的真实家族切页/重启
//   不丢（draft 自动落盘，300ms 防抖）。

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../../charts/pedigree_chart.dart';
import '../../engine/pedigree_genotype.dart';
import '../../engine/pedigree_inference.dart';
import '../../storage/platform_storage_io.dart'
    if (dart.library.html) '../../storage/platform_storage_web.dart';
import '../../theme.dart';
import '../../ui/ai_chat_controller.dart';
import '../../ui/assistant_panel.dart';
import '../../ui/png_export.dart';
import 'save_mistake_key_host.dart';
import 'save_to_mistake_book.dart';

/// 一名成员的录入行（id 自动生成 M1/M2…）。
class _MemberRow {
  String id;
  PdSex sex;
  PdStatus status;
  String? fatherId; // 录入后通过下拉赋值（构造时不带，避免 unused 参数告警）
  String? motherId;
  _MemberRow(this.id, this.sex, this.status);
}

/// 经典示例（教材金标准，与引擎测试同源——改数据要双边同步）。
class _Example {
  final String name;
  final String hint;
  final List<({String id, PdSex sex, PdStatus st})> members;
  final List<({String p, String c})> relations;
  const _Example(this.name, this.hint, this.members, this.relations);
}

const _examples = <_Example>[
  _Example(
    '常隐·无中生有',
    '正常父母生出患病女儿',
    [
      (id: 'I1', sex: PdSex.male, st: PdStatus.normal),
      (id: 'I2', sex: PdSex.female, st: PdStatus.normal),
      (id: 'II1', sex: PdSex.female, st: PdStatus.affected),
    ],
    [(p: 'I1', c: 'II1'), (p: 'I2', c: 'II1')],
  ),
  _Example(
    '伴X隐·交叉遗传',
    '男患者母亲携带，隔代传男',
    [
      (id: 'I1', sex: PdSex.male, st: PdStatus.normal),
      (id: 'I2', sex: PdSex.female, st: PdStatus.normal),
      (id: 'II1', sex: PdSex.male, st: PdStatus.affected),
      (id: 'II2', sex: PdSex.female, st: PdStatus.normal),
      (id: 'III1', sex: PdSex.male, st: PdStatus.affected),
    ],
    [
      (p: 'I1', c: 'II1'),
      (p: 'I2', c: 'II1'),
      (p: 'II1', c: 'III1'),
      (p: 'II2', c: 'III1'),
    ],
  ),
  _Example(
    '常显·有中生无',
    '患病父母生出正常孩子',
    [
      (id: 'I1', sex: PdSex.male, st: PdStatus.affected),
      (id: 'I2', sex: PdSex.female, st: PdStatus.affected),
      (id: 'II1', sex: PdSex.female, st: PdStatus.normal),
      (id: 'II2', sex: PdSex.male, st: PdStatus.affected),
      (id: 'III1', sex: PdSex.female, st: PdStatus.affected),
    ],
    [
      (p: 'I1', c: 'II1'),
      (p: 'I2', c: 'II1'),
      (p: 'I1', c: 'II2'),
      (p: 'I2', c: 'II2'),
      (p: 'II2', c: 'III1'),
    ],
  ),
  _Example(
    '伴Y·三代男传男',
    '仅男性患病，父病子必病',
    [
      (id: 'I1', sex: PdSex.male, st: PdStatus.affected),
      (id: 'I2', sex: PdSex.female, st: PdStatus.normal),
      (id: 'II1', sex: PdSex.male, st: PdStatus.affected),
      (id: 'II2', sex: PdSex.female, st: PdStatus.normal),
      (id: 'III1', sex: PdSex.male, st: PdStatus.affected),
    ],
    [
      (p: 'I1', c: 'II1'),
      (p: 'I2', c: 'II1'),
      (p: 'II1', c: 'III1'),
      (p: 'II2', c: 'III1'),
    ],
  ),
];

/// 系谱推断器（可独立嵌入任何 ListView 的分区组件）。
class PedigreeInferenceView extends StatefulWidget {
  const PedigreeInferenceView({super.key});

  @override
  State<PedigreeInferenceView> createState() =>
      PedigreeInferenceViewState();
}

/// State 公开：宿主页（GeneticDiseasePage）持 GlobalKey 供拍题识别
/// actions 录入（loadFromActions）。
class PedigreeInferenceViewState extends State<PedigreeInferenceView> {
  final List<_MemberRow> _rows = [];
  InferenceOutcome? _outcome;
  List<String> _errors = const [];
  // v2.19.56（找茬 D）：推断**算出那一刻**的成员行快照。Ctrl+S 组装
  // payload 时比对现文——成员任何字段变动且未重跑推断 ⇒ 题面（_rows
  // 现文）与答案（best）不同源：stale ⇒ 题干/答案空串（⛔ 不存「题干新
  // 成员 + 答案旧结论」的矛盾题，矛盾数据会喂给错题本 AI 错因归类）。
  // best/患者数由 _rows 推导不必单列；_quizAnswer 是学生作答（不是
  // 题面），换作答不算题目过期 ⇒ ⛔ 不进快照。
  String? _pdSnap;
  int _seq = 0;
  // v2.13+ 基因型反推的选定方式（默认 = 推断最可能；可下拉切换）。
  InheritancePattern? _analysisPattern;
  // v2.13+ 系谱图渲染/导出：图表挂在独立 RepaintBoundary 上截图。
  final _chartKey = GlobalKey();
  bool _exportingChart = false;
  // v2.13+ 练习模式：随机载入经典系谱、结论遮罩，学生先判后验。
  bool _quizMode = false;
  InheritancePattern? _quizAnswer;
  bool _quizRevealed = false;

  /// R5：进入练习前的用户系谱快照——退出练习时恢复（练习载入示例会
  /// 整个替换 _rows 并覆盖磁盘草稿；老师走查 P0：误触的代价必须是零）。
  List<_MemberRow>? _preQuizRows;

  /// R5 练习本轮战绩（进入练习清零；揭示答案时累计）。
  int _quizRight = 0;
  int _quizWrong = 0;

  /// R5 上一道练习示例名（抽题避开立刻重复）。
  String? _lastExampleName;

  /// R5 老师走查：草稿从磁盘恢复后给显式提示（课堂上不知道系谱被
  /// 换成上次留下的，讲错题隐患真实存在）。
  bool _draftRestored = false;

  static final _rng = math.Random();

  /// 练习模式：随机抽一道经典系谱（结论遮罩）。
  /// R5 学生走查：池子只有 4 道，shuffle().first 有 25% 概率立刻
  /// 重复上一题——能避则避。
  void _quizNext() {
    final pool = [..._examples]..shuffle(_rng);
    var pick = pool.first;
    if (pool.length > 1 && pick.name == _lastExampleName) {
      pick = pool.last;
    }
    _lastExampleName = pick.name;
    _loadExample(pick);
    setState(() {
      _quizAnswer = null;
      _quizRevealed = false;
    });
  }

  /// 深拷贝成员行（快照/恢复用——fatherId/motherId 是可变引用，
  /// 浅拷贝会共享状态）。
  List<_MemberRow> _cloneRows(List<_MemberRow> src) => [
        for (final r in src)
          _MemberRow(r.id, r.sex, r.status)
            ..fatherId = r.fatherId
            ..motherId = r.motherId,
      ];

  /// R5 老师走查 P0：练习模式开关。进入：_rows 非空先弹确认（示例会
  /// 整个替换录入），确认前快照原系谱；退出：恢复快快照并写回草稿，
  /// 误触的代价归零。
  Future<void> _toggleQuiz() async {
    if (!_quizMode) {
      if (_rows.isNotEmpty) {
        final enter = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('进入练习模式？'),
            content: Text(
                '练习会用一道经典系谱替换当前录入的 ${_rows.length} 名成员'
                '（退出练习模式可恢复）。'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                child: const Text('进入练习'),
              ),
            ],
          ),
        );
        if (enter != true || !mounted) return;
        _preQuizRows = _cloneRows(_rows);
      }
      setState(() {
        _quizMode = true;
        _quizRight = 0;
        _quizWrong = 0;
      });
      _quizNext();
      return;
    }
    final restored = _preQuizRows;
    setState(() {
      _quizMode = false;
      _quizAnswer = null;
      _quizRevealed = false;
      if (restored != null) {
        _rows
          ..clear()
          ..addAll(restored);
        _seq = restored.length;
        _outcome = null;
        _errors = const [];
      }
    });
    if (restored != null) _scheduleSaveDraft();
    _preQuizRows = null;
  }

  /// 系谱图导出 PNG（教师出题插图：近白底打印友好，含世代标注）。
  Future<void> _exportChart() async {
    setState(() => _exportingChart = true);
    final r = await captureBoundaryPng(_chartKey, '系谱图');
    if (!mounted) return;
    setState(() => _exportingChart = false);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(r.path != null ? '已保存：${r.path}' : r.error ?? '导出失败'),
      duration: const Duration(seconds: 4),
    ));
  }
  // v2.13+ 草稿持久化：300ms 防抖写盘（切页/重启不丢录入）。
  Timer? _draftDebounce;

  static const _draftKey = 'pd_inference_draft';

  @override
  void initState() {
    super.initState();
    _loadDraft();
  }

  @override
  void dispose() {
    _draftDebounce?.cancel();
    super.dispose();
  }

  // ── 草稿持久化（学生走查 P0：录入的系谱切页/退出不丢） ──

  String? _draftPath() {
    final appDir = userAppDir();
    if (appDir == null) return null;
    final d = Directory(appDir);
    if (!d.existsSync()) d.createSync(recursive: true);
    return '$appDir${Platform.pathSeparator}$_draftKey.json';
  }

  Map<String, dynamic> _draftJson() => {
        'seq': _seq,
        'members': [
          for (final r in _rows)
            {
              'id': r.id,
              'sex': r.sex.name,
              'status': r.status.name,
              'fatherId': r.fatherId,
              'motherId': r.motherId,
            },
        ],
      };

  void _scheduleSaveDraft() {
    _draftDebounce?.cancel();
    _draftDebounce = Timer(const Duration(milliseconds: 300), _saveDraft);
  }

  Future<void> _saveDraft() async {
    // FLUTTER_TEST 守卫：同 HistoryStore.append——测试期写真实目录会
    // 污染用户草稿（且 widget 测试间互相串数据）。
    if (!kIsWeb && Platform.environment['FLUTTER_TEST'] == 'true') return;
    try {
      final json = jsonEncode(_draftJson());
      if (isWebStorage) {
        await storageSet(_draftKey, json);
        return;
      }
      final p = _draftPath();
      if (p == null) return;
      await File(p).writeAsString(json, flush: true);
    } catch (_) {/* 草稿写失败静默——推断不依赖它 */}
  }

  Future<void> _loadDraft() async {
    if (!kIsWeb && Platform.environment['FLUTTER_TEST'] == 'true') return;
    try {
      String? raw;
      if (isWebStorage) {
        raw = storageGet(_draftKey);
      } else {
        final p = _draftPath();
        final f = p == null ? null : File(p);
        if (f != null && f.existsSync()) raw = f.readAsStringSync();
      }
      if (raw == null || raw.isEmpty) return;
      final j = jsonDecode(raw);
      if (j is! Map) return;
      final members = j['members'];
      if (members is! List) return;
      final loaded = <_MemberRow>[];
      for (final m in members) {
        if (m is! Map) continue;
        loaded.add(_MemberRow(
          m['id']?.toString() ?? 'M${loaded.length + 1}',
          m['sex'] == 'female' ? PdSex.female : PdSex.male,
          m['status'] == 'affected' ? PdStatus.affected : PdStatus.normal,
        ));
        loaded.last
          ..fatherId = m['fatherId']?.toString()
          ..motherId = m['motherId']?.toString();
      }
      if (!mounted || loaded.isEmpty) return;
      setState(() {
        _rows
          ..clear()
          ..addAll(loaded);
        _seq = (j['seq'] as num?)?.toInt() ?? loaded.length;
        // R5 老师走查：恢复草稿后给显式提示（课堂上不知道系谱被换成
        // 上次留下的，讲错题隐患真实存在）。
        _draftRestored = true;
      });
    } catch (_) {/* 草稿损坏 = 从空开始 */}
  }

  String _nextId() => 'M${++_seq}';

  /// v2.13+：拍题识别录入——把 AI 解析的 add_member 动作序列载入为
  /// 成员行（供 ModuleFillBus 的 applyActions 调用；返回是否成功）。
  /// 宽容解析：缺失字段给默认、悬空父母引用置空（引擎校验兜底）。
  /// R7 学生走查 P0：已录入的系谱会被识别结果静默整体替换——现与
  /// 练习模式同款确认（取消 = 原样保留，绝不丢手画草稿）。
  Future<bool> loadFromActions(List<Map<String, String>> actions) async {
    final loaded = <_MemberRow>[];
    for (final a in actions) {
      if (a['type'] != 'add_member') continue;
      final id = (a['id'] ?? '').trim();
      if (id.isEmpty) continue;
      loaded.add(_MemberRow(
        id,
        a['sex'] == 'female' ? PdSex.female : PdSex.male,
        a['status'] == 'affected' ? PdStatus.affected : PdStatus.normal,
      ));
    }
    if (loaded.isEmpty) return false;
    // 覆盖确认：手头已有录入时不许静默清掉（学生手画作业系谱的
    // 血泪教训——取消即保留原状）。
    if (_rows.isNotEmpty && mounted) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('按识别结果替换当前系谱？'),
          content: Text('识别出 ${loaded.length} 名成员，将替换当前录入的'
              ' ${_rows.length} 名成员（取消则保留原样）。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('替换'),
            ),
          ],
        ),
      );
      if (ok != true || !mounted) return false;
    }
    final ids = loaded.map((r) => r.id).toSet();
    // 二次遍历挂父母（须引用已载入成员，悬空置空）。
    for (final a in actions) {
      if (a['type'] != 'add_member') continue;
      final id = (a['id'] ?? '').trim();
      _MemberRow? row;
      for (final x in loaded) {
        if (x.id == id) {
          row = x;
          break;
        }
      }
      if (row == null) continue;
      final f = (a['father'] ?? '').trim();
      final m = (a['mother'] ?? '').trim();
      row.fatherId = f.isNotEmpty && ids.contains(f) ? f : null;
      row.motherId = m.isNotEmpty && ids.contains(m) ? m : null;
    }
    setState(() {
      _rows
        ..clear()
        ..addAll(loaded);
      _seq = loaded.length;
      _outcome = null;
      _errors = const [];
    });
    _scheduleSaveDraft();
    // R5 学生走查：识别必须对照原图核对——AI 漏/错一个成员学生无从
    // 发现（pd_capture_chart 底图随题展示留待后续，先给显式提示）。
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('已按识别填入成员，请对照原图核对有无遗漏'),
        duration: Duration(seconds: 5),
      ));
    }
    return true;
  }

  void _addRow() => setState(() {
        _rows.add(_MemberRow(_nextId(), PdSex.male, PdStatus.normal));
        _outcome = null;
        _scheduleSaveDraft();
      });

  void _removeRow(String id) => setState(() {
        _rows.removeWhere((r) => r.id == id);
        for (final r in _rows) {
          if (r.fatherId == id) r.fatherId = null;
          if (r.motherId == id) r.motherId = null;
        }
        _outcome = null;
        _scheduleSaveDraft();
      });

  void _loadExample(_Example ex) => setState(() {
        _rows
          ..clear()
          ..addAll(ex.members.map((m) =>
              _MemberRow(m.id, m.sex, m.st)));
        for (final r in _rows) {
          for (final rel in ex.relations) {
            if (rel.c != r.id) continue;
            final parent = _rows.firstWhere((p) => p.id == rel.p);
            if (parent.sex == PdSex.male) {
              r.fatherId = rel.p;
            } else {
              r.motherId = rel.p;
            }
          }
        }
        // id 序列对齐示例（继续添加不撞名）。
        _seq = _rows.length;
        _outcome = null;
        _errors = const [];
        _scheduleSaveDraft();
      });

  /// 代际推导：无父=0，否则 = max(父代 generation)+1。
  int _genOf(_MemberRow row) {
    final ps = [row.fatherId, row.motherId]
        .whereType<String>()
        .map((id) => _rows.firstWhere((r) => r.id == id))
        .toList();
    if (ps.isEmpty) return 0;
    var g = 0;
    for (final p in ps) {
      final v = _genOf(p) + 1;
      if (v > g) g = v;
    }
    return g;
  }

  void _run() {
    // v2.13+ 练习模式闸门：先选判断再运行，否则提示不揭示结论。
    if (_quizMode && !_quizRevealed) {
      if (_quizAnswer == null) {
        setState(() => _errors = const ['先选出你的判断，再点「运行推断」对答案']);
        return;
      }
    }
    final members = <PdMember>[
      for (final r in _rows)
        PdMember(
          id: r.id,
          sex: r.sex,
          status: r.status,
          generation: _genOf(r),
        ),
    ];
    final relations = <PdRelation>[
      for (final r in _rows) ...[
        if (r.fatherId != null)
          PdRelation(parentId: r.fatherId!, childId: r.id),
        if (r.motherId != null)
          PdRelation(parentId: r.motherId!, childId: r.id),
      ],
    ];
    final engine = PedigreeInferenceEngine();
    final out = engine.infer(members, relations);
    setState(() {
      _outcome = out.candidates.isEmpty ? null : out;
      // v2.19.56（找茬 D）：快照与结果同生——重算成功（_outcome 非空）
      // 才落，此刻的 _rows 与 best 严格同源（同一次 _run 的输入/输出）；
      // 重算失败（引擎 errors、candidates 空）不落：旧快照随 _outcome
      // 作废，门的第一腿（_outcome != null）照样拦。
      if (_outcome != null) _pdSnap = _pdSnapOf(_rows);
      _errors = engine.errors;
      // R5：揭示瞬间累计本轮战绩（防重跑重复计数——只在首次揭示）。
      // R7 学生走查：信息不足（best==null）不算学生错——题本身出坏了，
      // 不计对也不计错、不给存题入口，换一题即可。
      if (_quizMode && _quizAnswer != null && !_quizRevealed) {
        _quizRevealed = true;
        if (out.best == null) {
          // 信息不足：战绩不动。
        } else if (out.best == _quizAnswer) {
          _quizRight++;
        } else {
          _quizWrong++;
        }
      }
    });
  }

  /// v2.19.56（找茬 D）：成员行序列化——id/性别/表型/父/母任何字段变动
  /// （含增删成员带来的行序变动）都会改变序列化结果 ⇒ 快照 != 现文 ⇒
  /// stale。
  String _pdSnapOf(List<_MemberRow> rows) => rows
      .map((r) => '${r.id}|${r.sex}|${r.status}|${r.fatherId}|${r.motherId}')
      .join(';');

  // v2.19.56（找茬 D）：stale 快照门（照分子/变异页 v2.19.53 同款）——
  // 结果存在**且算出那一刻的行快照与现文一致**才算新鲜。成员变动未
  // 重跑时题干/答案一并剔除，⛔ 不存题面与答案不同源的矛盾题；不新鲜
  // ⇒ 答案空串 ⇒ saveToMistakeBook 既有「先算出结果」守卫应答。
  bool get _pdFresh => _outcome != null && _pdSnap == _pdSnapOf(_rows);

  // ── v2.19.56（找茬 D）测试缝 ──

  /// **故意**改一名成员的表型且**不清** _outcome——模拟「未来某个编辑
  /// 入口漏写 `_outcome = null`」的回归态：现网所有编辑入口（性别/表型/
  /// 父母 chip、增删成员、载入示例/识别、练习切换、清空）都随手清
  /// `_outcome`，生产 UI 走不到「结果还在、题面已改」的 stale 态——
  /// 正因如此才把底线判定交给显式快照门（分子/变异页同款防御深度：
  /// 门兜的是「未来漏写」，不是「今天能走到的路径」）。守卫网
  /// （test/pd_inference_stale_gate_test.dart）靠它把「摘快照比对」的
  /// 变异验证做成可红可绿：门被摘 ⇒ 矛盾题（题干新成员 + 答案旧结论）
  /// 直写入库。
  @visibleForTesting
  void debugEditMemberKeepingOutcome(String id, PdStatus status) {
    for (final r in _rows) {
      if (r.id == id) r.status = status;
    }
  }

  @override
  Widget build(BuildContext context) {
    // v2.19.15：页面级 Ctrl+S 宿主——与 9331/单基因/伴性同模式。
    // 数据与练习态「存入错题本」按钮严格同链（_quizSaveToMistakeBook）。
    // v2.19.55：CallbackShortcuts 旧宿主换新宿主——payload 按下现取
    // （消灭「输入改了没重建 ⇒ 存旧题干」的潜伏病）+ 激活闸 + 焦点让路。
    // v2.19.56：块体闭包——门与屏上数字一律按下那一刻现读 State 现文
    // （不再从 build 局部变量捕获，消灭「build 后改过状态 ⇒ 存旧数」
    // 的残余潜伏窗）。
    return SaveMistakeKeyHost(
      payload: () {
        // v2.19.56（找茬 D）：stale 快照门（见 _pdFresh 头注）——成员
        // 变动未重跑 ⇒ 题干/答案空串，由 saveToMistakeBook 既有「先算出
        // 结果」守卫应答、零写入；userAnswer 照常：学生作答不是题面，
        // stale 也带出（复习会话「你当时写」与 AI 错因归类依赖它）。
        final fresh = _pdFresh;
        final best = _outcome?.best;
        final affected =
            _rows.where((r) => r.status == PdStatus.affected).length;
        final members = _rows
            .map((r) =>
                '${r.id} ${r.sex == PdSex.male ? "男" : "女"}·'
                '${r.status == PdStatus.affected ? "患病" : "正常"}'
                '${r.fatherId != null || r.motherId != null ? "（父 ${r.fatherId ?? "—"}·母 ${r.motherId ?? "—"}）" : ""}')
            .join('；');
        return SavePayload(
          stem: fresh
              ? '系谱判断练习：${_rows.length} 名成员（$affected 名患者）。'
                  '成员与关系：$members。请判断最可能的遗传方式。'
              : '',
          correctAnswer:
              fresh && best != null ? '最可能：${best.displayName}' : '',
          subjectArea: '人类遗传病',
          userAnswer: _quizAnswer?.displayName ?? '',
        );
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('录入家族成员（性别 / 表型 / 父母），或载入经典系谱一键演示。',
              style: AppText.caption),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              // v2.13+ 练习模式：随机经典系谱 + 结论遮罩，先判后验。
              // R5 老师走查 P0：录入到一半手滑点开，原系谱被随机示例
              // 整个替换且草稿被覆盖（无确认无撤销）——现规则见 _toggleQuiz。
              ActionChip(
                avatar: Icon(
                    _quizMode
                        ? Icons.school
                        : Icons.school_outlined,
                    size: 14),
                label: Text(_quizMode ? '练习中' : '练习模式',
                    style: AppText.caption.copyWith(
                        color: _quizMode ? AppColors.teal : null)),
                onPressed: _toggleQuiz,
              ),
              if (_quizMode) ...[
                ActionChip(
                  avatar: const Icon(Icons.skip_next, size: 14),
                  label: Text('换一题', style: AppText.caption),
                  onPressed: _quizNext,
                ),
                // R5 学生走查：本轮战绩——先判后验的积累感（不然刷 10 轮
                // 只有单条横幅，没有任何积累）。
                AppChip('本轮 $_quizRight 对 $_quizWrong'),
              ] else
                for (final ex in _examples)
                  ActionChip(
                    avatar:
                        const Icon(Icons.library_books_outlined, size: 14),
                    label: Text(ex.name, style: AppText.caption),
                    onPressed: () => _loadExample(ex),
                  ),
            ],
          ),
          const SizedBox(height: 8),
          // R5 老师走查：磁盘草稿恢复提示——「已载入上次草稿 · 清空重录」，
          // 别破坏学生 P0 的草稿功能，只把「静默恢复」变成「显式告知」。
          if (_draftRestored && _rows.isNotEmpty) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.tealWash,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.teal.withValues(alpha: 0.4)),
              ),
              child: Row(
                children: [
                  Icon(Icons.history_outlined, size: 14, color: AppColors.teal),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text('已载入上次未完成的系谱（${_rows.length} 名成员）',
                        style: AppText.caption.copyWith(color: AppColors.teal)),
                  ),
                  TextButton(
                    onPressed: () => setState(() {
                      _rows.clear();
                      _outcome = null;
                      _errors = const [];
                      _draftRestored = false;
                      _scheduleSaveDraft();
                    }),
                    child: const Text('清空重录'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
          ],
          for (final r in _rows) _memberRow(r),
          Align(
            alignment: Alignment.centerLeft,
            child: Wrap(
              spacing: 8,
              children: [
                TextButton.icon(
                  onPressed: _addRow,
                  icon: const Icon(Icons.person_add_outlined, size: 16),
                  label: const Text('添加成员'),
                ),
                // v2.13+ 学生走查：清空入口（逐个 × 删要 N 次点击）；
                // 确认 dialog 防误点。
                TextButton.icon(
                  onPressed: _rows.isEmpty
                      ? null
                      : () async {
                          final ok = await showDialog<bool>(
                            context: context,
                            builder: (ctx) => AlertDialog(
                              title: const Text('清空全部成员？'),
                              content: const Text('已录入的系谱将删除，不可撤销。'),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(ctx, false),
                                  child: const Text('取消'),
                                ),
                                FilledButton(
                                  onPressed: () => Navigator.pop(ctx, true),
                                  child: const Text('清空'),
                                ),
                              ],
                            ),
                          );
                          if (ok == true) {
                            setState(() {
                              _rows.clear();
                              _outcome = null;
                            });
                            _scheduleSaveDraft();
                          }
                        },
                  icon: const Icon(Icons.delete_sweep_outlined, size: 16),
                  label: const Text('清空'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.icon(
              onPressed: _rows.isEmpty ? null : _run,
              icon: const Icon(Icons.troubleshoot_outlined, size: 18),
              label: const Text('运行推断',
                  style: TextStyle(fontWeight: FontWeight.w600)),
            ),
          ),
          // v2.13+：标准系谱图实时呈现（男=方 女=圆 患者=实心）——
          // 教师一眼核对录入，且可导出 PNG 当作业插图（出题神器）。
          if (_rows.isNotEmpty) ...[
            const SizedBox(height: 10),
            RepaintBoundary(
              key: _chartKey,
              child: Container(
                decoration: BoxDecoration(
                  border: Border.all(color: AppColors.border),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: PedigreeChart(
                    members: [
                      for (final r in _rows)
                        PdMember(
                          id: r.id,
                          sex: r.sex,
                          status: r.status,
                          generation: _genOf(r),
                        ),
                    ],
                    relations: [
                      for (final r in _rows) ...[
                        if (r.fatherId != null)
                          PdRelation(
                              parentId: r.fatherId!, childId: r.id),
                        if (r.motherId != null)
                          PdRelation(
                              parentId: r.motherId!, childId: r.id),
                      ],
                    ],
                    genOf: (m) => _genOf(_rows.firstWhere((x) => x.id == m.id)),
                  ),
                ),
              ),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: _exportingChart ? null : _exportChart,
                icon: const Icon(Icons.image_outlined, size: 16),
                label: Text(_exportingChart ? '导出中…' : '系谱图存为图片'),
              ),
            ),
          ],
          if (_errors.isNotEmpty) ...[
            const SizedBox(height: 8),
            for (final e in _errors)
              Text('⚠ $e',
                  style: AppText.caption.copyWith(color: AppColors.lethal)),
          ],
          // v2.13+ 练习模式·先判后验：成员可见、结论遮罩——选判断后
          // 「运行推断」才揭示并对答案。
          if (_quizMode && !_quizRevealed && _rows.isNotEmpty) ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.tealWash,
                borderRadius: BorderRadius.circular(8),
                border:
                    Border.all(color: AppColors.teal.withValues(alpha: 0.4)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('你的判断：这张系谱图最可能是哪种遗传方式？',
                      style: AppText.label.copyWith(color: AppColors.teal)),
                  const SizedBox(height: 6),
                  Wrap(spacing: 6, runSpacing: 4, children: [
                    for (final p in InheritancePattern.values)
                      ChoiceChip(
                        label: Text(p.displayName, style: AppText.caption),
                        selected: _quizAnswer == p,
                        onSelected: (_) =>
                            setState(() => _quizAnswer = p),
                      ),
                  ]),
                  const SizedBox(height: 4),
                  Text('选好点「运行推断」对答案——依据条文会逐条展示',
                      style: AppText.caption
                          .copyWith(color: AppColors.graphite)),
                ],
              ),
            ),
          ],
          if (_outcome != null) ...[
            const SizedBox(height: 12),
            if (_quizMode && _quizRevealed) _quizVerdictBanner(),
            if (_quizMode &&
                _quizRevealed &&
                _outcome!.best != null && // R7：信息不足不怪学生，不给存题入口
                _quizAnswer != _outcome!.best) ...[
              const SizedBox(height: 4),
              _quizSaveToMistakeBook(),
              const SizedBox(height: 8),
            ],
            _resultCard(),
          ],
        ],
      ),
      );
    }

    /// 练习模式判定横幅：✓ 判对了 / ✗ + 正确答案。
  Widget _quizVerdictBanner() {
    final best = _outcome!.best;
    final correct = best != null && _quizAnswer == best;
    final color = correct ? AppColors.teal : AppColors.lethal;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Text(
        best == null
            // R5 学生走查：与结果卡「信息不足，无法给出结论」口径一致
            //（原「正确答案是『信息不足』」读起来像一种遗传方式）。
            ? '这张系谱信息不足，无法给出结论——读下方依据，'
                '想想还缺什么信息'
            : (correct
                ? '✓ 判对了！这正是「${best.displayName}」——看下方依据条文巩固思路'
                : '✗ 你判的是「${_quizAnswer?.displayName ?? "（未选）"}」，'
                    '正确答案是「${best.displayName}」——'
                    '读下方排除依据，想想差在哪'),
        style: AppText.label.copyWith(color: color),
      ),
    );
  }

  /// 练习判错 → 一键存入错题本（AI 自动整理后回到复习闭环）。
  ///
  /// R5 双走查修订：①题干把成员清单序列化进文本——原「系谱图见推断器
  /// 练习记录」是悬空引用（练习一换题系谱本体就没了，复习/AI 整理无从
  /// 重判）；②userAnswer 把学生判错的选项带进错题本（复习会话「你当时
  /// 写」+ AI 错因归类的关键信号）。
  Widget _quizSaveToMistakeBook() {
    final best = _outcome!.best;
    final affected = _rows.where((r) => r.status == PdStatus.affected).length;
    final members = _rows
        .map((r) =>
            '${r.id} ${r.sex == PdSex.male ? "男" : "女"}·'
            '${r.status == PdStatus.affected ? "患病" : "正常"}'
            '${r.fatherId != null || r.motherId != null ? "（父 ${r.fatherId ?? "—"}·母 ${r.motherId ?? "—"}）" : ""}')
        .join('；');
    return Align(
      alignment: Alignment.centerLeft,
      child: SaveToMistakeBookButton(
        stem: '系谱判断练习：${_rows.length} 名成员（$affected 名患者）。'
            '成员与关系：$members。请判断最可能的遗传方式。',
        correctAnswer: '最可能：${best?.displayName ?? "信息不足"}',
        subjectArea: '人类遗传病',
        // ⛔ 屏上占位串不许进库：`?? '（未选择）'` 传下去的是「这一项没有
        // 值」的占位符，不是学生写下的东西。它非空 ⇒ 错题本把它当成一次
        // 真实错答观测，复习会话「你当时写：…」印出来的就是那个占位符。
        // 没作答就传空串（错题本渲染为「（未作答）」）。
        //
        // ⛔ 刻意**不**记 srcModule/srcParams：本题的「答案」是一次判断
        // 结论，回程没有任何可回填的参数——记下来只会得到一枚点下去必然
        // 弹「那一页现在过不去」的死按钮。宁可没有。
        userAnswer: _quizAnswer?.displayName ?? '',
      ),
    );
  }

  Widget _memberRow(_MemberRow r) {
    // 父亲候选：除自己外的男性；母亲候选：除自己外的女性。
    final fathers =
        _rows.where((o) => o.id != r.id && o.sex == PdSex.male).toList();
    final mothers =
        _rows.where((o) => o.id != r.id && o.sex == PdSex.female).toList();
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(10, 8, 6, 8),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(r.id, style: AppText.label),
              // v2.13+ 学生走查：代际可视化（_genOf 推导，不依赖命名）。
              Padding(
                padding: const EdgeInsets.only(left: 6),
                child: AppChip('第 ${_genOf(r) + 1} 代'),
              ),
              const Spacer(),
              IconButton(
                tooltip: '删除该成员',
                icon: const Icon(Icons.close, size: 16),
                onPressed: () => _removeRow(r.id),
              ),
            ],
          ),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              ChoiceChip(
                label: Text('男', style: AppText.caption),
                selected: r.sex == PdSex.male,
                onSelected: (_) => setState(() {
                  r.sex = PdSex.male;
                  r.fatherId = null; // 性别变了，父母引用清掉防矛盾
                  _outcome = null;
                  _scheduleSaveDraft();
                }),
              ),
              ChoiceChip(
                label: Text('女', style: AppText.caption),
                selected: r.sex == PdSex.female,
                onSelected: (_) => setState(() {
                  r.sex = PdSex.female;
                  r.motherId = null;
                  _outcome = null;
                  _scheduleSaveDraft();
                }),
              ),
              const SizedBox(width: 4),
              ChoiceChip(
                label: Text('正常', style: AppText.caption),
                selected: r.status == PdStatus.normal,
                onSelected: (_) => setState(() {
                  r.status = PdStatus.normal;
                  _outcome = null;
                  _scheduleSaveDraft();
                }),
              ),
              ChoiceChip(
                label: Text('患病', style: AppText.caption),
                selected: r.status == PdStatus.affected,
                onSelected: (_) => setState(() {
                  r.status = PdStatus.affected;
                  _outcome = null;
                  _scheduleSaveDraft();
                }),
              ),
              _parentMenu('父亲', r.fatherId, fathers, (v) => setState(() {
                    r.fatherId = v;
                    _outcome = null;
                    _scheduleSaveDraft();
                  })),
              _parentMenu('母亲', r.motherId, mothers, (v) => setState(() {
                    r.motherId = v;
                    _outcome = null;
                    _scheduleSaveDraft();
                  })),
            ],
          ),
        ],
      ),
    );
  }

  Widget _parentMenu(String label, String? value, List<_MemberRow> cands,
      ValueChanged<String?> onChanged) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('$label：', style: AppText.caption),
        DropdownButton<String?>(
          value: cands.any((c) => c.id == value) ? value : null,
          hint: Text('无', style: AppText.caption),
          underline: const SizedBox.shrink(),
          isDense: true,
          items: [
            for (final c in cands)
              DropdownMenuItem(value: c.id, child: Text(c.id)),
          ],
          onChanged: (v) => onChanged(v),
        ),
      ],
    );
  }

  Widget _resultCard() {
    // 首个未排除候选（排序保证即得分最高者）；best 枚举 getter 不带
    // score，需要候选对象判 0 分信息不足。
    PatternCandidate? bestCand;
    for (final c in _outcome!.candidates) {
      if (!c.excluded) {
        bestCand = c;
        break;
      }
    }
    final best = bestCand?.pattern;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.tealWash,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.teal.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('推断结论（${_outcome!.summary}）',
              style: AppText.caption.copyWith(color: AppColors.graphite)),
          const SizedBox(height: 4),
          if (best != null)
            // v2.13+ 学生走查 P0：全部候选 0 分（如只录 1 人无家族结构）
            // 时不得显示具体结论——学生会把「0 分的猜测」抄成答案。
            (bestCand?.score ?? 0) > 0
                ? Text('最可能：${best.displayName}',
                    style:
                        AppText.sectionTitle.copyWith(color: AppColors.teal))
                : Text('信息不足，无法给出结论——请补充家族成员与关系',
                    style: AppText.sectionTitle
                        .copyWith(color: AppColors.graphite))
          else
            Text('输入的系谱有矛盾，所有遗传方式均被排除——请核对成员关系',
                style: AppText.body.copyWith(color: AppColors.lethal)),
          // v2.13+ 老师走查 P1：两个候选得分接近时明示「备选」——
          // 「常显 vs 常隐 都可能」不是结论，「最可能 X，备选 Y」才是。
          if (bestCand != null) ...[
            for (final c in _outcome!.candidates)
              if (!c.excluded &&
                  c.pattern != bestCand.pattern &&
                  bestCand.score - c.score <= 2 &&
                  c.score > 0)
                Text('备选：${c.pattern.displayName}（得分 ${c.score}）',
                    style:
                        AppText.caption.copyWith(color: AppColors.graphite)),
          ],
          const SizedBox(height: 8),
          // v2.13+：结论一键深讲——系谱事实 + 推断结论 + 全部依据条文
          // 自动进 AI 上下文，学生追问「为什么不是 X 显」不用重述题目。
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: () => _askDeepDive(),
              icon: const Icon(Icons.psychology_outlined, size: 16),
              label: const Text('问 AI 深讲这道系谱'),
            ),
          ),
          const SizedBox(height: 4),
          for (final c in _outcome!.candidates)
            if (!c.excluded || c.evidence.isNotEmpty)
              _candidateTile(c),
          // v2.13+ 半开放反推：判完方式再求基因型（高考 staple）。
          if (bestCand != null && (bestCand.score) > 0) ...[
            const SizedBox(height: 8),
            _genotypePanel(bestCand.pattern),
          ],
        ],
      ),
    );
  }

  /// 结论档位小胶囊（AppChip 不支持自定义色，本地面板专用）。
  Widget _confChip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.45)),
      ),
      child: Text(label,
          style: AppText.caption
              .copyWith(color: color, fontWeight: FontWeight.w700)),
    );
  }

  /// 基因型反推面板：选定遗传方式（默认最可能），逐成员给基因型结论。
  Widget _genotypePanel(InheritancePattern bestPattern) {
    _analysisPattern ??= bestPattern;
    // 选项 = 未排除的候选（得分 >0）。
    final options = [
      for (final c in _outcome!.candidates)
        if (!c.excluded && c.score > 0) c.pattern,
    ];
    if (options.isEmpty) return const SizedBox.shrink();
    if (!options.contains(_analysisPattern)) {
      _analysisPattern = options.first;
    }
    final analysis = PedigreeGenotypeAnalysis.analyze(
      [
        for (final r in _rows)
          PdMember(
            id: r.id,
            sex: r.sex,
            status: r.status,
            generation: _genOf(r),
          ),
      ],
      [
        for (final r in _rows) ...[
          if (r.fatherId != null)
            PdRelation(parentId: r.fatherId!, childId: r.id),
          if (r.motherId != null)
            PdRelation(parentId: r.motherId!, childId: r.id),
        ],
      ],
      _analysisPattern!,
    );
    final confidenceLabel = {
      GenotypeConfidence.deduced: '确定',
      GenotypeConfidence.probabilistic: '概率',
      GenotypeConfidence.unknown: '未定',
    };
    final confidenceColor = {
      GenotypeConfidence.deduced: AppColors.teal,
      GenotypeConfidence.probabilistic: AppColors.sand,
      GenotypeConfidence.unknown: AppColors.steel,
    };
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.surfaceLow,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('基因型反推', style: AppText.label),
              const SizedBox(width: 8),
              DropdownButton<InheritancePattern>(
                value: _analysisPattern,
                underline: const SizedBox.shrink(),
                isDense: true,
                items: [
                  for (final p in options)
                    DropdownMenuItem(
                        value: p, child: Text(p.displayName)),
                ],
                onChanged: (v) => setState(() => _analysisPattern = v),
              ),
            ],
          ),
          Text(analysis.summary,
              style: AppText.caption.copyWith(color: AppColors.steel)),
          const SizedBox(height: 6),
          for (final c in analysis.calls)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _confChip(confidenceLabel[c.confidence]!,
                      confidenceColor[c.confidence]!),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('${c.memberId}：${c.genotype}',
                            style: AppText.caption.copyWith(
                                color: AppColors.ink,
                                fontWeight: FontWeight.w600)),
                        Text('· ${c.evidence}',
                            style: AppText.caption
                                .copyWith(color: AppColors.graphite)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  /// v2.13+：结论卡「问 AI 深讲」——上下文 = 系谱事实 + 推断结论 +
  /// 每条依据，AI 可针对性解释排除逻辑（「为什么不是伴 X 显性」）。
  void _askDeepDive() {
    final out = _outcome;
    if (out == null) return;
    final sb = StringBuffer()
      ..writeln('【系谱推断·请给我讲解这张系谱】')
      ..writeln('成员与表型：${_rows.map((r) => '${r.id}(${r.sex == PdSex.male ? "男" : "女"}·${r.status == PdStatus.affected ? "患病" : "正常"})').join('，')}')
      ..writeln('推断结论：${out.best?.displayName ?? "各方式均有矛盾"}')
      ..writeln('各候选与依据：');
    for (final c in out.candidates) {
      sb.writeln(
          '- ${c.pattern.displayName}${c.excluded ? "（已排除）" : "（得分 ${c.score}）"}');
      for (final e in c.evidence) {
        sb.writeln('  $e');
      }
    }
    sb.writeln('请解释推断思路，并回答我可能的疑问（如「为什么不是其他方式」）。');
    // R5 老师走查：同错题卡「问 AI」——清掉一次性画布截图，否则 AI
    // 会带着上一张拍题截图回答这道系谱。
    AiChatController.instance.pendingCanvasImage = null;
    AiChatController.instance.queueSend(sb.toString());
    showAiAssistant(context);
  }

  Widget _candidateTile(PatternCandidate c) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(c.pattern.displayName, style: AppText.label),
                const SizedBox(width: 8),
                if (c.excluded)
                  Text('已排除',
                      style: AppText.caption
                          .copyWith(color: AppColors.lethal))
                else
                  Text('得分 ${c.score}',
                      style: AppText.caption
                          .copyWith(color: AppColors.steel)),
              ],
            ),
            for (final e in c.evidence)
              Padding(
                padding: const EdgeInsets.only(top: 3, left: 6),
                child: Text('· $e',
                    style: AppText.caption
                        .copyWith(color: AppColors.graphite)),
              ),
          ],
        ),
      ),
    );
  }
}
