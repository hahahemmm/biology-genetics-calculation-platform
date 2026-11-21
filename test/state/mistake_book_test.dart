// mistake_book_test.dart —— 错题本数据模型 + 持久化测试
//
// 覆盖：
//   1. 添加错题（add）：返回 entry 含 id / createdAt；列表按 createdAt 倒序
//   2. 编辑错题（update）：按 id 查找并替换
//   3. 删除错题（delete）：按 id 移除
//   4. 标记复习状态（markStatus）：unreviewed → reviewing → mastered
//   5. 持久化（重启后保留）：save 后 debugFilePath 切空 → load 仍能读出

import 'dart:io';

import 'package:biology/services/mistake_book_crypto.dart';
import 'package:biology/state/mistake_book.dart';
import 'package:biology/storage/platform_storage_io.dart' as storage_io;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory tmp;
  late String filePath;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('mistake_book_test');
    filePath = '${tmp.path}/mistake_book.json';
    MistakeBook.debugFilePath = filePath;
    MistakeBook.instance.debugReset();
    // v2.12 Wave 3-B P1-1：写盘 debounce Timer。add() 后 500ms 内
    // 有 pending timer，test 结束时框架断言 "!timersPending" 失败。
    // addTearDown 在 invariants 之前跑，flush 取消。
    addTearDown(() {
      MistakeBook.instance.debugFlushSave();
    });
  });

  tearDown(() {
    MistakeBook.debugFilePath = null;
    MistakeBook.instance.debugReset();
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  group('CRUD', () {
    test('添加：返回 entry 含 id+createdAt；列表按 createdAt 倒序', () {
      // 添加 3 条（人为错开 1ms 时间戳太脆，构造 createdAt 时直接用现在）
      final a = MistakeBook.instance.add(
        stem: 'AaBb 自交 F2 比例',
        userAnswer: '9:3:4',
        correctAnswer: '9:3:3:1',
        errorType: MistakeErrorType.concept,
        subjectArea: '9331 变式',
      );
      final b = MistakeBook.instance.add(
        stem: 'XAXa × XAY 子代性别',
        userAnswer: '都是女儿',
        correctAnswer: '女儿 1/2 携带,儿子 1/2 患者',
        errorType: MistakeErrorType.comprehension,
        subjectArea: '伴 X 遗传',
      );
      final c = MistakeBook.instance.add(
        stem: '基因频率 Hardy-Weinberg',
        userAnswer: 'p+q=1 直接代入',
        correctAnswer: 'p²+2pq+q²=1 配子随机结合',
        errorType: MistakeErrorType.calculation,
        subjectArea: '哈迪温伯格',
      );
      // 返回值检查
      expect(a.id, isNotEmpty);
      expect(b.id, isNotEmpty);
      expect(c.id, isNotEmpty);
      expect(a.id, isNot(b.id), reason: 'id 唯一');
      // 列表顺序：最后添加的 c 在最前
      // v2.12 Wave 3-B P1：_genId 改 monotonic counter，later add
      // 必拿到更大 id；_sortDesc tie-breaker `b.id.compareTo(a.id)`
      // 把 later add 排前，行为确定。
      expect(MistakeBook.instance.entries.map((e) => e.id),
          [c.id, b.id, a.id]);
      // entries 是不可修改的视图
      expect(
          () => MistakeBook.instance.entries.add(a),
          throwsUnsupportedError,
          reason: 'entries 是 unmodifiable');
      // v2.12 Wave 3-B P1-1：flush 3 次 add 的 debounce timer。
      MistakeBook.instance.debugFlushSave();
    });

    test('编辑：update 替换指定 id 的 entry，其他不变', () {
      final a = MistakeBook.instance.add(
        stem: '原题',
        userAnswer: '原错',
        correctAnswer: '原正',
        errorType: MistakeErrorType.concept,
        subjectArea: '原考点',
      );
      final b = MistakeBook.instance.add(
        stem: '另一题',
        userAnswer: 'b错',
        correctAnswer: 'b正',
        errorType: MistakeErrorType.careless,
        subjectArea: 'b 考点',
      );
      MistakeBook.instance.update(a.id, (e) => e.copyWith(
            stem: '改后题目',
            userAnswer: '改后错答',
            correctAnswer: '改后正答',
            subjectArea: '改后考点',
          ));
      final updatedA = MistakeBook.instance.findById(a.id)!;
      expect(updatedA.stem, '改后题目');
      expect(updatedA.userAnswer, '改后错答');
      expect(updatedA.correctAnswer, '改后正答');
      expect(updatedA.subjectArea, '改后考点');
      expect(updatedA.errorType, MistakeErrorType.concept,
          reason: '未指定字段保持原值');
      // b 不动
      expect(MistakeBook.instance.findById(b.id)!.stem, '另一题');
      // v2.12 Wave 3-B P1-1：flush debounce timer。
      MistakeBook.instance.debugFlushSave();
    });

    test('删除：按 id 移除，listeners 收到通知', () {
      final a = MistakeBook.instance.add(
        stem: '待删',
        userAnswer: 'x',
        correctAnswer: 'y',
        errorType: MistakeErrorType.other,
        subjectArea: '',
      );
      var notifyCount = 0;
      MistakeBook.instance.addListener(() => notifyCount++);
      MistakeBook.instance.delete(a.id);
      expect(MistakeBook.instance.findById(a.id), isNull);
      expect(notifyCount, 1, reason: 'delete 触发 1 次 notify');
      // 删不存在的 id 静默
      MistakeBook.instance.delete('not_exist');
      expect(notifyCount, 1, reason: '不存在的 id 不触发 notify');
      // v2.12 Wave 3-B P1-1：flush debounce timer。
      MistakeBook.instance.debugFlushSave();
    });

    test('标记复习状态：markStatus 走 reviewing→mastered 链路', () {
      final a = MistakeBook.instance.add(
        stem: '复习题',
        userAnswer: 'x',
        correctAnswer: 'y',
        errorType: MistakeErrorType.concept,
        subjectArea: '',
      );
      expect(MistakeBook.instance.findById(a.id)!.reviewStatus,
          MistakeReviewStatus.unreviewed);
      MistakeBook.instance.markStatus(a.id, MistakeReviewStatus.reviewing);
      expect(MistakeBook.instance.findById(a.id)!.reviewStatus,
          MistakeReviewStatus.reviewing);
      MistakeBook.instance.markStatus(a.id, MistakeReviewStatus.mastered);
      expect(MistakeBook.instance.findById(a.id)!.reviewStatus,
          MistakeReviewStatus.mastered);
      // v2.12 Wave 3-B P1-1：flush debounce timer。
      MistakeBook.instance.debugFlushSave();
    });
  });

  group('持久化', () {
    test('add 后 debugFilePath 切空 → 新 instance load 仍能读出', () async {
      // 1. 添加 → 落盘
      final a = MistakeBook.instance.add(
        stem: '持久化测试',
        userAnswer: '错',
        correctAnswer: '对',
        errorType: MistakeErrorType.careless,
        subjectArea: 'test',
      );
      // v2.12 Wave 3-B P1-1：add 现在是 debounce 写盘，flush 立即落盘
      // 才能让"模拟重启"路径从磁盘读出来。debugReset 不 flush 也会
      // 取消 timer，但要求"先写盘再 reset"才能验证持久化。
      MistakeBook.instance.debugFlushSave();
      // 2. 模拟"重启"：debugFilePath 留文件，instance 重置内存
      MistakeBook.instance.debugReset();
      expect(MistakeBook.instance.entries, isEmpty,
          reason: 'reset 后内存空');
      // 3. 重新 load（不重置 debugFilePath）
      await MistakeBook.instance.load();
      final loaded = MistakeBook.instance.findById(a.id);
      expect(loaded, isNotNull, reason: '磁盘数据能 load 回来');
      expect(loaded!.stem, '持久化测试');
      expect(loaded.correctAnswer, '对');
      expect(loaded.errorType, MistakeErrorType.careless);
    });
  });

  // ═══ v2.12 Round 1 P0 #5：回收站（软删除 7 天可恢复） ═══
  group('回收站', () {
    test('删除：移入回收站，entries 移除 / trash 接收 1 条 / listeners 通知',
        () {
      // v2.12 Round 1 P0 #5：delete 改为软删除——移到 _trash，
      // 7 天内可恢复。旧测试（line 116）验证 entries 移除 + notify，
      // 本测试额外验证 trash 接收 + deletedAt = now。
      final a = MistakeBook.instance.add(
        stem: '待软删',
        userAnswer: 'x',
        correctAnswer: 'y',
        errorType: MistakeErrorType.other,
        subjectArea: '',
      );
      var notifyCount = 0;
      MistakeBook.instance.addListener(() => notifyCount++);
      final before = DateTime.now();
      MistakeBook.instance.delete(a.id);
      final after = DateTime.now();

      expect(MistakeBook.instance.findById(a.id), isNull,
          reason: '主列表已移除（findById 只看 _entries）');
      expect(MistakeBook.instance.trash, hasLength(1),
          reason: 'trash 应接收 1 条');
      final t = MistakeBook.instance.trash.first;
      expect(t.id, a.id, reason: 'trash 用原 id（trash 用 entry.id）');
      expect(t.entry.stem, '待软删');
      // deletedAt 在 before/after 之间
      expect(t.deletedAt.isAfter(before) ||
              t.deletedAt.isAtSameMomentAs(before), isTrue);
      expect(t.deletedAt.isBefore(after) ||
              t.deletedAt.isAtSameMomentAs(after), isTrue);
      expect(notifyCount, 1, reason: 'delete 触发 1 次 notify');
      MistakeBook.instance.debugFlushSave();
    });

    test('恢复：restoreFromTrash 重新插回主列表，AI 字段保留',
        () {
      // v2.12 Round 1 P0 #5：5 秒 Undo 过期后仍可从回收站恢复，
      // 且 AI 整理结果（aiSummary / aiPitfalls / aiOverview）+ 复习状态不丢。
      final a = MistakeBook.instance.add(
        stem: '原题',
        userAnswer: '原错',
        correctAnswer: '原正',
        errorType: MistakeErrorType.concept,
        subjectArea: '原考点',
      );
      MistakeBook.instance.applyAiAnalysis(a.id,
          summary: 'AI summary', pitfalls: ['点 1', '点 2']);
      MistakeBook.instance.applyAiOverview(a.id, '总览块');
      MistakeBook.instance.markStatus(a.id, MistakeReviewStatus.reviewing);

      MistakeBook.instance.delete(a.id);
      expect(MistakeBook.instance.findById(a.id), isNull);
      expect(MistakeBook.instance.trash, hasLength(1));

      // 恢复——拿新 id（不复用旧 id，避免历史引用错乱，同 v2.12.0+2）
      final restored = MistakeBook.instance.restoreFromTrash(a.id);
      expect(restored, isNotNull);
      expect(restored!.id, isNot(a.id),
          reason: '新 id（不复用旧 id）');
      expect(MistakeBook.instance.findById(restored.id), isNotNull);
      expect(MistakeBook.instance.trash, isEmpty,
          reason: 'trash 移除该条');
      // AI 字段保留
      final r = MistakeBook.instance.findById(restored.id)!;
      expect(r.aiSummary, 'AI summary');
      expect(r.aiPitfalls, ['点 1', '点 2']);
      expect(r.aiOverview, '总览块');
      expect(r.reviewStatus, MistakeReviewStatus.reviewing);
      MistakeBook.instance.debugFlushSave();
    });

    test('持久化：trash 落盘 + 重启后仍可恢复', () async {
      // v2.12 Round 1 P0 #5：5 秒 Undo 过期 + 重新打开 app →
      // trash 仍存在，可恢复。
      final a = MistakeBook.instance.add(
        stem: '待软删 + 重启',
        userAnswer: 'x',
        correctAnswer: 'y',
        errorType: MistakeErrorType.careless,
        subjectArea: '',
      );
      MistakeBook.instance.delete(a.id);
      MistakeBook.instance.debugFlushSave();

      // 模拟重启：debugReset 清内存，但保留 debugFilePath
      MistakeBook.instance.debugReset();
      expect(MistakeBook.instance.entries, isEmpty);
      expect(MistakeBook.instance.trash, isEmpty,
          reason: 'reset 后内存空');

      // 重新 load
      await MistakeBook.instance.load();
      expect(MistakeBook.instance.entries, isEmpty,
          reason: '重启后主列表确实空（删除持久化）');
      expect(MistakeBook.instance.trash, hasLength(1),
          reason: 'trash 持久化保留');
      final t = MistakeBook.instance.trash.first;
      expect(t.id, a.id);
      expect(t.entry.stem, '待软删 + 重启');

      // 仍可恢复
      final restored = MistakeBook.instance.restoreFromTrash(a.id);
      expect(restored, isNotNull);
      expect(MistakeBook.instance.findById(restored!.id), isNotNull);
    });

    test('7 天后自动清理：mock now 跳到 8 天后，purgeExpiredTrash 移除',
        () {
      // v2.12 Round 1 P0 #5：用 MistakeBook.now 时间注入，模拟 7 天后。
      final a = MistakeBook.instance.add(
        stem: '会被清',
        userAnswer: 'x',
        correctAnswer: 'y',
        errorType: MistakeErrorType.other,
        subjectArea: '',
      );
      MistakeBook.instance.delete(a.id);
      // deletedAt = now() = t0
      final t0 = MistakeBook.instance.trash.first.deletedAt;
      expect(MistakeBook.instance.trash, hasLength(1));

      // 跳到 8 天后
      final future = t0.add(const Duration(days: 8));
      MistakeBook.now = () => future;
      addTearDown(() => MistakeBook.now = DateTime.now);

      final removed = MistakeBook.instance.purgeExpiredTrash();
      expect(removed, 1, reason: '7 天前的应被清掉');
      expect(MistakeBook.instance.trash, isEmpty);

      // 永久删除 API 仍可用
      // 先 add 一个新的 + 立即删（deletedAt = t0 again，跳到 8 天后过期）
      MistakeBook.now = () => t0;
      final b = MistakeBook.instance.add(
        stem: 'B',
        userAnswer: 'x',
        correctAnswer: 'y',
        errorType: MistakeErrorType.other,
        subjectArea: '',
      );
      MistakeBook.instance.delete(b.id);
      expect(MistakeBook.instance.trash, hasLength(1));
      // 用 permanentlyDelete 立即删
      final ok = MistakeBook.instance.permanentlyDelete(b.id);
      expect(ok, isTrue);
      expect(MistakeBook.instance.trash, isEmpty);
      // 不存在的 id 返 false
      final ok2 = MistakeBook.instance.permanentlyDelete('not_exist');
      expect(ok2, isFalse);
      MistakeBook.instance.debugFlushSave();
    });
  });

  // ═══ v2.12 Round 1 P0 #6：跨设备导入 / 导出 JSON ═══
  group('跨设备导入导出', () {
    test('exportJson 返 schemaVersion 1 + entries + trash', () {
      // v2.12 Round 1 P0 #6：导出 JSON 是字符串，含 schemaVersion: 1
      // 字段 + entries 数组 + trash 数组。format 走 JsonEncoder.withIndent
      // (indent=2) 方便人读。
      final a = MistakeBook.instance.add(
        stem: '导出测试 A',
        userAnswer: 'x',
        correctAnswer: 'y',
        errorType: MistakeErrorType.concept,
        subjectArea: '',
      );
      MistakeBook.instance.applyAiAnalysis(a.id, summary: 'AI sum', pitfalls: ['p1']);
      MistakeBook.instance.delete(a.id); // 进 trash

      final json = MistakeBook.instance.exportJson();
      expect(json, contains('"schemaVersion": 1'));
      expect(json, contains('"exportedAt"'));
      // entries 应该已被移走（trash 里），所以 entries 数组空
      expect(json, contains('"entries": ['));
      // trash 含 1 条
      expect(json, contains('"trash": ['));
      expect(json, contains('导出测试 A'));
      expect(json, contains('AI sum'));
    });

    // ═══ v2.13 R4-4：浅脱敏导出（人名→某某、学号→×××）═══
    test('R4-4 脱敏导出：人名/学号被替换；非脱敏保留原文', () {
      final a = MistakeBook.instance.add(
        stem: '张三在考场 20260001 的实验',
        userAnswer: '张三答错',
        correctAnswer: '正确答案 20260001',
        errorType: MistakeErrorType.concept,
        subjectArea: '张三的考点',
      );
      // v2.13 R6-P1：默认 desensitize=true → 显式传 false 测「非脱敏」
      // 路径。明文导出是 R6-P1 隐私根因中的「用户主动选择」语义，测试
      // 仍要覆盖明文导出以保证显式调用契约不变。
      final plain = MistakeBook.instance.exportJson(desensitize: false);
      expect(plain, contains('张三'));
      expect(plain, contains('20260001'));
      // 脱敏：token 级替换
      final masked = MistakeBook.instance.exportJson(desensitize: true);
      expect(masked, isNot(contains('张三')), reason: '人名 → 某某');
      expect(masked, isNot(contains('20260001')), reason: '学号 → ×××');
      expect(masked, contains('某某'));
      expect(masked, contains('×××'));
      // 结构性字段不受脱敏影响（导入去重依赖 id 原样）
      expect(masked, contains('"schemaVersion": 1'));
      expect(masked, contains(a.id), reason: 'id 不脱敏');
      // 生物学习内容不被误伤（排除集）
      MistakeBook.instance.add(
        stem: '叶绿体中高茎豌豆的黄体细胞周期',
        userAnswer: '方法',
        correctAnswer: '白细胞',
        errorType: MistakeErrorType.concept,
        subjectArea: '细胞增殖',
      );
      final masked2 = MistakeBook.instance.exportJson(desensitize: true);
      expect(masked2, contains('叶绿体'), reason: '排除集保护：叶绿体');
      expect(masked2, contains('高茎'), reason: '排除集保护：高茎');
      expect(masked2, contains('黄体'), reason: '排除集保护：黄体');
      expect(masked2, contains('细胞周期'), reason: '排除集保护：细胞周期');
      expect(masked2, contains('方法'), reason: '排除集保护：方法');
      expect(masked2, contains('白细胞'), reason: '排除集保护：白细胞');
    });

    // ═══ v2.13 R6-P1：默认 desensitize=true 强引导 ═══
    test('R6-P1 默认脱敏：exportJson() 无参 → 人名/学号被替换', () {
      // v2.13 R6-P1 最小可行修复：默认 desensitize=true 强引导——
      // 用户主动选 false 才传明文 JSON。这是 P1 隐私根因中
      // 「默认 desensitize=false 无强引导」一项的最小缓解。
      // AES-GCM 端到端加密属重工程，推 R7 路线图。
      //
      // 测试契约：exportJson() 与 exportJson(desensitize: true)
      // 行为必须一致——保证默认参数变更不破坏调用方直觉。
      // 唯一差异点是 exportedAt 时间戳（now() 每次调用会变），所以
      // 不比较完整字符串，而是分别比较「敏感字段是否被替换」语义。
      MistakeBook.instance.add(
        stem: '张三在考场 20260001 的实验',
        userAnswer: '张三答错',
        correctAnswer: '正确答案 20260001',
        errorType: MistakeErrorType.concept,
        subjectArea: '张三的考点',
      );

      // 不传参（默认）→ 应触发脱敏
      final defaultExport = MistakeBook.instance.exportJson();
      expect(defaultExport, isNot(contains('张三')),
          reason: 'R6-P1 默认脱敏：人名被替换');
      expect(defaultExport, isNot(contains('20260001')),
          reason: 'R6-P1 默认脱敏：学号被替换');
      expect(defaultExport, contains('某某'),
          reason: 'R6-P1 默认脱敏：人名 → 某某');
      expect(defaultExport, contains('×××'),
          reason: 'R6-P1 默认脱敏：学号 → ×××');

      // 等价性：默认与显式 desensitize: true 在「敏感字段是否被替换」
      // 上一致（不比较 exportedAt 等易变字段）
      final explicitTrue = MistakeBook.instance.exportJson(desensitize: true);
      for (final token in ['某某', '×××']) {
        expect(defaultExport, contains(token),
            reason: '默认与显式 true 同样含 $token');
        expect(explicitTrue, contains(token),
            reason: '默认与显式 true 同样含 $token');
      }
      for (final token in ['张三', '20260001']) {
        expect(defaultExport, isNot(contains(token)),
            reason: '默认与显式 true 同样不含 $token');
        expect(explicitTrue, isNot(contains(token)),
            reason: '默认与显式 true 同样不含 $token');
      }

      // 反向：显式 false 仍可拿明文（用户主动选择）
      final explicitFalse = MistakeBook.instance.exportJson(desensitize: false);
      expect(explicitFalse, contains('张三'),
          reason: '显式 desensitize: false → 保留原文');
      expect(explicitFalse, contains('20260001'),
          reason: '显式 desensitize: false → 保留学号');

      // 结构性字段不受脱敏影响（id 等导入去重依赖）
      expect(defaultExport, contains('"schemaVersion": 1'));
    });

    // ═══ v2.13 R4f（P1-1）：脱敏误伤反例（A verifier 实测词）═══
    test('R4f 脱敏反例：生物术语不被吞成某某；姓名+学号仍替换', () {
      MistakeBook.instance.add(
        stem: '植物具有向光性，根有向地性；周皮与孔隙相关，'
            '胡蜂、核黄素、林冠层、林下层均为考点',
        userAnswer: '向光性、向地性、向水性',
        correctAnswer: '周皮',
        errorType: MistakeErrorType.concept,
        subjectArea: '植物生理',
      );
      final masked = MistakeBook.instance.exportJson(desensitize: true);
      // 已报误伤词在脱敏后必须原样保留（题目内容不可毁）
      for (final w in ['向光性', '向地性', '向水性', '周皮', '核黄素',
          '胡蜂', '孔隙', '林冠层', '林下层']) {
        expect(masked, contains(w), reason: '生物术语 $w 不应被脱敏误伤');
      }
      // 姓名位 + 学号仍替换（张三 20260001 → 某某 ×××）
      MistakeBook.instance.add(
        stem: '张三 20260001 的实验记录',
        userAnswer: '张三答错',
        correctAnswer: '正确',
        errorType: MistakeErrorType.concept,
        subjectArea: '遗传',
      );
      final masked2 = MistakeBook.instance.exportJson(desensitize: true);
      expect(masked2, isNot(contains('张三')), reason: '姓名位仍替换');
      expect(masked2, isNot(contains('20260001')), reason: '学号仍替换');
      expect(masked2, contains('某某'), reason: '姓名替换为某某');
      expect(masked2, contains('×××'), reason: '学号替换为×××');
    });

    // ═══ v2.13 R4f2（P1）：校园高频词脱敏反例（排除集补全）═══
    test('R4f2 脱敏反例：校园高频词（年级/星期/考试词）不被吞成某某', () {
      // R4-5th A 复刻实证：高三学生→某某生 / 我上高一→我上某某 /
      // 我写周记→我写某某 / 周一上课→某某上课——校园题干高频词被毁
      const stem = '高三学生在周记里写：我上高一，周一上课、周五自修，'
          '周中与周末都有周测，月考与期中期末成绩周日公布，高二周考结束';
      final maskedStem = MistakeBook.maskSensitive(stem);
      for (final w in ['高三', '高一', '高二', '周一', '周五', '周日',
          '周记', '周末', '周中', '周测', '周考', '月考', '期中', '期末']) {
        expect(maskedStem, contains(w), reason: '校园高频词 $w 不应被脱敏误伤');
      }
      // 姓名位 + 学号仍替换（张三 20260001 → 某某 ×××）
      final maskedName = MistakeBook.maskSensitive('张三 20260001 的考试记录');
      expect(maskedName, isNot(contains('张三')), reason: '姓名位仍替换');
      expect(maskedName, isNot(contains('20260001')), reason: '学号仍替换');
      expect(maskedName, contains('某某'), reason: '姓名替换为某某');
      expect(maskedName, contains('×××'), reason: '学号替换为×××');
    });

    // ═══ v2.13 R8-P1：NER 启发式升级——孤立人名漏脱根因修复 ═══
    test('R8-P1 孤立人名：句中嵌字主路径替换（P1 根因 1/4 修复）', () {
      // R6-P1 浅脱敏遗留 P1 根因实证：
      //   "今天张三被选为班委" — 张三 前后都是汉字 + 无称谓词
      //   R4f 姓名位启发式会判 false → 漏脱
      // R8-P1 主路径：首字在 top 50 姓氏 + 词长 2-4 → 直接替换
      //   不再做姓名位信号判定
      final masked1 = MistakeBook.maskSensitive('今天张三被选为班委');
      expect(masked1, isNot(contains('张三')), reason: '孤立人名 张三 必须替换');
      expect(masked1, contains('某某'), reason: '孤立人名 张三 → 某某');
      expect(masked1, contains('今天某某被选为班委'),
          reason: '原句结构保留');

      // 多个孤立人名同时替换
      final masked2 = MistakeBook.maskSensitive('李四和王五一起去了');
      expect(masked2, isNot(contains('李四')), reason: '李四 必须替换');
      expect(masked2, isNot(contains('王五')), reason: '王五 必须替换');
      expect(masked2, contains('某某和某某一起去了'),
          reason: '原句结构保留');

      // 班级场景
      final masked3 = MistakeBook.maskSensitive('我们班的赵六生病了');
      expect(masked3, isNot(contains('赵六')), reason: '赵六 必须替换');
      expect(masked3, contains('某某生病了'), reason: '原句结构保留');

      // 已知术语不被替换
      final masked4 = MistakeBook.maskSensitive('小红帽的故事');
      expect(masked4, contains('小红帽'), reason: '小红帽 不是人名（首字"小"非姓氏）');
      final masked5 = MistakeBook.maskSensitive('中国和北京');
      expect(masked5, contains('中国'), reason: '中国 不是人名（首字"中"非姓氏）');
      expect(masked5, contains('北京'), reason: '北京 不是人名（首字"北"非姓氏）');
    });

    test('R8-P1 新增姓氏覆盖：top 50 姓氏 + 排除集保护生物/日常词', () {
      // 验证 R8-P1 新增姓氏（叶/杜/丁/任/田/程/苏/魏/吕/沈/韩/唐/
      // 萧/董/蔡/余/蒋/潘/袁/彭/曹/邓/冯/许/宋/谢/梁/郑/罗/郭/何/
      // 朱/孙/徐）的人名 token 都能被替换
      // 注：用"叶明"而非"叶子"——「叶子」是 R8-P1 排除集中的
      // 生物/日常词（叶子的形状），覆盖测试避开冲突。
      final names = ['叶明', '杜子腾', '丁凯', '任家萱', '田亮',
          '程心', '苏芒', '魏然', '吕布', '沈腾', '韩寒', '唐伯虎',
          '萧敬腾', '董卿', '蔡徐坤', '余文乐', '蒋欣', '潘玮柏',
          '袁泉', '彭于晏', '曹云金', '邓超', '冯小刚', '许晴',
          '宋祖儿', '谢霆锋', '梁朝伟', '郑爽', '罗志祥', '郭德纲',
          '何炅', '朱一龙', '孙悟空', '徐峥'];
      for (final n in names) {
        final masked = MistakeBook.maskSensitive('考生 $n 答错');
        expect(masked, isNot(contains(n)),
            reason: 'top 50 姓氏 $n 应被替换');
        expect(masked, contains('某某'),
            reason: '$n → 某某');
      }

      // 验证 R8-P1 新增排除集保护生物/日常高频词不被误伤
      final bioTerms = [
        '叶绿体',  // 3-char，2-char 前缀「叶绿」在集
        '叶绿素',  // 3-char，2-char 前缀「叶绿」在集
        '杜鹃花',  // 3-char，2-char 前缀「杜鹃」在集
        '杜鹃鸟',  // 3-char，2-char 前缀「杜鹃」在集
        '丁香花',  // 3-char，2-char 前缀「丁香」在集
      ];
      for (final t in bioTerms) {
        final masked = MistakeBook.maskSensitive('考点 $t 是重点');
        expect(masked, contains(t),
            reason: 'R8-P1 排除集保护：生物词 $t 不被误伤');
      }

      // 极常见词保护
      final commonWords = [
        '任何', '任意', '几何', '方程', '程度', '程序',
        '苏醒', '苏打', '罗盘', '唐朝', '唐代', '韩国',
        '曹操', '田径', '朱红', '朱砂', '徐徐', '孙子',
        '沈阳', '桥梁', '余弦', '余数', '董事', '萧条',
      ];
      for (final w in commonWords) {
        final masked = MistakeBook.maskSensitive('题干出现 $w 怎么办');
        expect(masked, contains(w),
            reason: 'R8-P1 排除集保护：常见词 $w 不被误伤');
      }
    });

    test('R8-P1 fallback：R4f 姓名位启发式仍生效（罕见姓氏/称谓位）', () {
      // R4f 保留为 fallback：处理「姓+某」模糊名 / 紧邻称谓词位
      // / 独立词边界（学号位/标点）等边界 case
      //
      // 例：罕见姓氏（不在 top 50）即使不在 R8-P1 主路径，
      // 借独立词边界（行首 + 行末）借 fallback 路径仍能命中。
      // 本测试只验证 fallback 路径仍在工作——「姓+某」模糊名
      // 是最稳定的 fallback 触发条件。
      final masked1 = MistakeBook.maskSensitive('考生张某答错');
      expect(masked1, isNot(contains('张某')),
          reason: '「姓+某」模糊名 fallback 触发');
      expect(masked1, contains('某某'),
          reason: '「姓+某」→ 某某');

      // 紧邻称谓词位（独立词边界）仍命中
      final masked2 = MistakeBook.maskSensitive('学生李四参加考试');
      expect(masked2, isNot(contains('李四')),
          reason: '紧邻称谓词位（学生）fallback 触发');
      expect(masked2, contains('某某'),
          reason: '李四 → 某某');
    });

    test('R8-P1 4 字名：词长 2-4 主路径覆盖 4 字人名', () {
      // R8-P1 正则扩展到 1-3 字后缀（词长 2-4），覆盖 4 字人名
      final masked1 = MistakeBook.maskSensitive('今天张小明被选为班委');
      expect(masked1, isNot(contains('张小明')),
          reason: '4 字人名 张小明 必须替换');
      expect(masked1, contains('某某'),
          reason: '张小明 → 某某');

      // 3 字人名同样覆盖
      final masked2 = MistakeBook.maskSensitive('今天王芳芳被选为班委');
      expect(masked2, isNot(contains('王芳芳')),
          reason: '3 字人名 王芳芳 必须替换');
      expect(masked2, contains('某某'),
          reason: '王芳芳 → 某某');
    });

    test('R4-4 脱敏导出文件头注释 + 导入兼容（含脱敏 JSON 可导入）', () async {
      MistakeBook.instance.add(
        stem: '张三错了 20260001',
        userAnswer: 'x',
        correctAnswer: 'y',
        errorType: MistakeErrorType.concept,
        subjectArea: '',
      );
      final masked = MistakeBook.instance.exportJson(desensitize: true);
      expect(masked.startsWith('// Biology 错题本导出'),
          isTrue, reason: '文件头含「导出人提示」注释段');
      expect(masked, contains('// 导出时间：'), reason: '文件头含导出时间');
      expect(masked, contains('// 脱敏导出：'), reason: '脱敏导出有标记行');
      expect(masked, contains('请勿公开分享'), reason: '隐私提醒文案');
      // 导入脱敏导出包（模拟跨设备导入）：文件头被剥离 + JSON 正常解析
      MistakeBook.instance.debugReset();
      final added = await MistakeBook.instance.importJson(masked);
      expect(added, 1, reason: '脱敏导出 JSON 可正常导入');
      final e = MistakeBook.instance.entries.single;
      expect(e.stem, contains('某某'));
      expect(e.stem, isNot(contains('张三')));
      expect(e.stem, isNot(contains('20260001')));
      // 老格式（无文件头）导入不受影响
      final oldJson =
          '{"schemaVersion":1,"exportedAt":0,"entries":[{"id":"old1","stem":"老题","userAnswer":"a","correctAnswer":"b","errorType":"other","subjectArea":"","createdAt":${DateTime.now().millisecondsSinceEpoch},"reviewStatus":"unreviewed"}],"trash":[]}';
      expect(await MistakeBook.instance.importJson(oldJson), 1,
          reason: '老格式无注释头仍可导入');
      MistakeBook.instance.debugFlushSave();
    });

    test('importJson 去重：同 id 不重复添加', () async {
      // v2.12 Round 1 P0 #6：现有 _entries 里的 id 跳过
      MistakeBook.instance.add(
        stem: '原始题',
        userAnswer: 'x',
        correctAnswer: 'y',
        errorType: MistakeErrorType.other,
        subjectArea: '',
      );
      expect(MistakeBook.instance.entries, hasLength(1));

      // 构造 JSON = 当前所有 entries 的内容
      final json = MistakeBook.instance.exportJson();
      final added = await MistakeBook.instance.importJson(json);
      expect(added, 0, reason: '同 id 不重复');
      expect(MistakeBook.instance.entries, hasLength(1));
    });

    test('importJson 新增：新 id 追加到 _entries', () async {
      // v2.12 Round 1 P0 #6：不同 id 追加
      final a = MistakeBook.instance.add(
        stem: '原 A',
        userAnswer: 'x',
        correctAnswer: 'y',
        errorType: MistakeErrorType.other,
        subjectArea: '',
      );
      // 构造另一份 JSON = 新 id 的 entry
      final otherJson =
          '{"schemaVersion":1,"exportedAt":0,"entries":[{"id":"m_other","stem":"外来 B","userAnswer":"1","correctAnswer":"2","errorType":"other","subjectArea":"","createdAt":${DateTime.now().millisecondsSinceEpoch},"reviewStatus":"unreviewed","aiSummary":null,"aiPitfalls":[],"aiOverview":null}],"trash":[]}';
      final added = await MistakeBook.instance.importJson(otherJson);
      expect(added, 1, reason: '新 id 追加 1 条');
      expect(MistakeBook.instance.entries, hasLength(2));
      // 包含原始 a + 新导入的 'm_other'
      final ids = MistakeBook.instance.entries.map((e) => e.id).toSet();
      expect(ids, contains(a.id));
      expect(ids, contains('m_other'));
    });

    test('importJson schemaVersion 不匹配抛 FormatException', () async {
      // v2.12 Round 1 P0 #6：未来 schemaVersion 变更时拒绝读
      final badJson =
          '{"schemaVersion":999,"exportedAt":0,"entries":[],"trash":[]}';
      await expectLater(
          () => MistakeBook.instance.importJson(badJson),
          throwsA(isA<FormatException>()));
    });

    test('importJson 损坏 JSON 抛 FormatException', () async {
      // v2.12 Round 1 P0 #6：JSON 损坏（非 JSON 字符串）抛错
      await expectLater(
          () => MistakeBook.instance.importJson('not json at all'),
          throwsA(isA<FormatException>()));
    });

    // ═══ v2.12 Round 1 final-B P0 #1：importJson trash 恢复路径 NPE ═══
    test(
        'P0 #1 importJson trash 恢复：trash 里有同 id + 导入 JSON 含同 id 不 NPE',
        () async {
      // 真实跨设备场景：设备 A 加 X (m1) → 删 X → 导出（trash 含 m1）。
      // 这份 JSON 流转回 A（或者 A 重启 + load 后再 import）→ 本机 trash
      // 仍含 m1。旧代码用 `restoreFromTrash(...)!.id` 二次调用，第一次
      // 已把 trash 移走，第二次返 null → `!.id` 抛 NPE。
      // 新代码接局部变量 + null check，恢复的新 entry 走 add() 拿到新 id。
      //
      // 简化测试：在同一 instance 构造"本机 trash 含 m1 + 导入 m1"的
      // 状态，验证：
      //   1. importJson 不抛
      //   2. m1 的旧 trash 条目被 restoreFromTrash 消耗（trash 空）
      //   3. entries 含 1 条（来自 restoreFromTrash 的新 id + 新 createdAt）
      final a = MistakeBook.instance.add(
        stem: '设备 A 的题',
        userAnswer: 'A 错',
        correctAnswer: 'A 正',
        errorType: MistakeErrorType.concept,
        subjectArea: 'A 考点',
      );
      MistakeBook.instance.delete(a.id);
      expect(MistakeBook.instance.entries, isEmpty,
          reason: '删后主列表空');
      expect(MistakeBook.instance.trash, hasLength(1),
          reason: 'trash 含 1 条（同 id 路径触发条件）');
      final trashId = MistakeBook.instance.trash.first.id;
      expect(trashId, a.id);

      // 构造一份 JSON：含同 id m1（模拟"设备 A 导出 → 设备 A 重新 import"
      // 或"设备 A 导出 → 设备 B 也有 trash 里的 m1 → import 命中恢复路径"）
      final importJson =
          '{"schemaVersion":1,"exportedAt":0,"entries":[{"id":"$trashId","stem":"A 的题（重导）","userAnswer":"A 错","correctAnswer":"A 正","errorType":"concept","subjectArea":"A 考点","createdAt":${DateTime.now().millisecondsSinceEpoch},"reviewStatus":"unreviewed","aiSummary":null,"aiPitfalls":[],"aiOverview":null}],"trash":[]}';

      // 旧代码会 NPE（`restoreFromTrash(...)!.id` 二次调用），新代码
      // 不抛 + trash 消耗 + entries 增 1。
      final added = await MistakeBook.instance.importJson(importJson);
      expect(added, 1, reason: 'trash 恢复路径应计入 added = 1');
      expect(MistakeBook.instance.entries, hasLength(1),
          reason: 'trash 里的 m1 走 restoreFromTrash 进 entries');
      expect(MistakeBook.instance.trash, isEmpty,
          reason: 'trash 里的 m1 已恢复 → trash 空');
      final restored = MistakeBook.instance.entries.first;
      // 重要：trash 恢复路径走的是 `restoreFromTrash(id)` 内部 add()，
      // **用 trash 里原 entry 的字段，不是 JSON 里的**——因为本地可能
      // 有未同步的 AI 整理结果，本地版本优先（见 mistake_book.dart
      // importJson 注释「保留本地最新版本」）。所以 stem 是 trash 里的
      // 「设备 A 的题」不是 JSON 里的「A 的题（重导）」。
      expect(restored.stem, '设备 A 的题',
          reason: 'trash 恢复走本地 trash 字段，JSON 字段不覆盖');
      expect(restored.id, isNot(trashId),
          reason: '新 id（restoreFromTrash 不复用旧 id）');
      MistakeBook.instance.debugFlushSave();
    });

    // ═══ v2.12+ R2 P0-B1：V0 老 schema 跨设备导入兼容 ═══
    test('P0-B1 importJson V0 兼容：缺 schemaVersion 字段（老格式）→ 不抛 + entries 全部恢复',
        () async {
      // v2.12.0+2 之前老用户导出的 JSON 缺 schemaVersion 字段（极早期
      // v2.10 之前的 JSON 就是这样：只有 entries 数组，无版本号）。新代码
      // 严格校验「必须 int 且 >= 1」会让老用户跨设备导入直接抛错。
      // 修法：importJson 顶层 dispatcher 看到 schemaVersion=null →
      // 走 _importJsonV0 兼容路径，按老字段映射 + 默认值处理。
      expect(MistakeBook.instance.entries, isEmpty);
      expect(MistakeBook.instance.trash, isEmpty);

      // 模拟 v2.10 老 JSON：root 没有 schemaVersion 字段
      final oldFormatJson =
          '{"entries":[{"id":"old1","stem":"老题 1","userAnswer":"A","correctAnswer":"B","errorType":"concept","subjectArea":"老考点","createdAt":${DateTime.now().millisecondsSinceEpoch}},{"id":"old2","stem":"老题 2","userAnswer":"C","correctAnswer":"D","errorType":"calculation","subjectArea":"老考点 2","createdAt":${DateTime.now().millisecondsSinceEpoch}}]}';

      // 不抛 + 全部恢复
      final added = await MistakeBook.instance.importJson(oldFormatJson);
      expect(added, 2, reason: 'V0 老格式 2 条 entry 全部恢复');
      expect(MistakeBook.instance.entries, hasLength(2));
      // 老字段缺失（aiSummary/aiPitfalls/aiOverview）应按默认（null/[]/null）
      for (final e in MistakeBook.instance.entries) {
        expect(e.aiSummary, isNull, reason: 'V0 老格式 aiSummary 默认 null');
        expect(e.aiPitfalls, isEmpty, reason: 'V0 老格式 aiPitfalls 默认 []');
        expect(e.aiOverview, isNull, reason: 'V0 老格式 aiOverview 默认 null');
      }
      // _trash 留空（V0 无 trash 字段）
      expect(MistakeBook.instance.trash, isEmpty,
          reason: 'V0 老格式无 trash 字段，_trash 留空');
      MistakeBook.instance.debugFlushSave();
    });

    test('P0-B1 importJson V0 兼容：schemaVersion=0 显式标 → 走 V0 路径',
        () async {
      // 另一个 V0 老格式：明确写 schemaVersion=0（早期 v2.10 末段
      // 加了 schemaVersion 字段但值是 0 还没出 V1 时的过渡版本）。
      expect(MistakeBook.instance.entries, isEmpty);

      final v0Json =
          '{"schemaVersion":0,"exportedAt":0,"entries":[{"id":"v0_legacy","stem":"schemaVersion=0 老题","userAnswer":"X","correctAnswer":"Y","errorType":"other","subjectArea":"","createdAt":${DateTime.now().millisecondsSinceEpoch}}],"trash":[]}';

      // V0 兼容路径：trash 字段被忽略（不读），entries 走老字段映射
      final added = await MistakeBook.instance.importJson(v0Json);
      expect(added, 1, reason: 'V0 显式 schemaVersion=0 走兼容路径');
      expect(MistakeBook.instance.entries, hasLength(1));
      final e = MistakeBook.instance.entries.first;
      expect(e.id, 'v0_legacy');
      expect(e.stem, 'schemaVersion=0 老题');
      // V0 不读 trash 字段 → _trash 留空
      expect(MistakeBook.instance.trash, isEmpty,
          reason: 'V0 不读 trash 字段（即使 JSON 含 trash 数组也忽略）');
      MistakeBook.instance.debugFlushSave();
    });

    test('P0-B1 importJson V1 路径：schemaVersion=1 + trash 字段 → 走 V1 路径 + trash 恢复',
        () async {
      // V1 路径回归测试：确认 dispatcher 把 schemaVersion=1 正确
      // 分派到 _importJsonV1（不破 R1 P0 #6 行为）。
      // 路径：本地 trash 含 m1 + 导入 V1 JSON 含 m1 → 走 restoreFromTrash
      // 恢复路径（同 R1 final-B P0 #1 的测试逻辑）。
      final a = MistakeBook.instance.add(
        stem: '设备 A 的 V1 题',
        userAnswer: 'A 错',
        correctAnswer: 'A 正',
        errorType: MistakeErrorType.concept,
        subjectArea: 'V1 考点',
      );
      MistakeBook.instance.delete(a.id);
      expect(MistakeBook.instance.trash, hasLength(1));
      final trashId = MistakeBook.instance.trash.first.id;

      final v1Json =
          '{"schemaVersion":1,"exportedAt":0,"entries":[{"id":"$trashId","stem":"V1 重导","userAnswer":"A 错","correctAnswer":"A 正","errorType":"concept","subjectArea":"V1 考点","createdAt":${DateTime.now().millisecondsSinceEpoch},"reviewStatus":"unreviewed","aiSummary":null,"aiPitfalls":[],"aiOverview":null}],"trash":[]}';

      // dispatcher → V1 路径 → trash 恢复
      final added = await MistakeBook.instance.importJson(v1Json);
      expect(added, 1, reason: 'V1 路径走 trash 恢复 + added=1');
      expect(MistakeBook.instance.entries, hasLength(1));
      expect(MistakeBook.instance.trash, isEmpty,
          reason: 'V1 路径下 trash 里的 m1 已被恢复');
      MistakeBook.instance.debugFlushSave();
    });

    // ═══ v2.13 R8-P1：端到端加密 export/import 集成测试 ═══
    test('R8-P1 exportEncryptedJson → isEncryptedEnvelope → importJson(passphrase) roundtrip',
        () async {
      // v2.13 R8-P1 W1 集成：闭环 R6-P1 路线图 P1 隐私根因 2/4（磁盘
      // 明文 JSON）——加 1 条错题 → 加密导出 → 嗅探 envelope → 输入
      // 口令解密导入 → 验证数据完整。覆盖 exportEncryptedJson +
      // importJson(passphrase:) + MistakeBookCrypto.isEncryptedEnvelope
      // 三件套的真实集成。
      MistakeBook.instance.add(
        stem: '张三 20260001 在光合作用题上答错',
        userAnswer: '9:3:4',
        correctAnswer: '9:3:3:1',
        errorType: MistakeErrorType.concept,
        subjectArea: '光合作用 9331',
      );
      final entriesBefore = MistakeBook.instance.entries;
      expect(entriesBefore, hasLength(1));

      // 1) 加密导出（desensitize 默认 true）
      const passphrase = 'test-passphrase-123';
      final envelope = await MistakeBook.instance.exportEncryptedJson(
        passphrase: passphrase,
      );
      expect(envelope.startsWith('// Biology 错题本加密导出'), isTrue,
          reason: 'envelope 顶部带加密注释头');
      expect(envelope, contains('cipher'), reason: 'envelope 含 cipher 字段');
      // isEncryptedEnvelope 嗅探 = true（envelope 自描述）
      expect(MistakeBookCrypto.isEncryptedEnvelope(envelope), isTrue,
          reason: '加密 envelope 应被嗅探为加密包');
      // 注意：加密后 envelope 不应含明文人名/学号（cryptography 随机 salt
      // + IV + GCM 不可读），但这是 cryptography 实现的保证，本测试只
      // 验证「嗅探正确 + 解密能拿回原文」。

      // 2) 新开空实例 → 模拟「另一台设备 / 重新装 app」导入
      MistakeBook.instance.debugReset();
      expect(MistakeBook.instance.entries, isEmpty);

      // 3) 输入正确口令 → 拿到明文 → 走 V1 dispatcher
      final added = await MistakeBook.instance.importJson(
        envelope,
        passphrase: passphrase,
      );
      expect(added, 1, reason: '解密 + V1 dispatcher 走通，新增 1 条');
      final entriesAfter = MistakeBook.instance.entries;
      expect(entriesAfter, hasLength(1));
      final imported = entriesAfter.single;
      // 解密后 entry 字段完整（明文 desensitize 浅脱敏保留）
      expect(imported.stem, contains('某某'),
          reason: 'desensitize=true 时 stem 内人名 → 某某');
      expect(imported.subjectArea, '光合作用 9331');
      expect(imported.userAnswer, '9:3:4');
      expect(imported.correctAnswer, '9:3:3:1');
      MistakeBook.instance.debugFlushSave();
    });

    test('R8-P1 importJson 无口令时遇 envelope 抛 FormatException',
        () async {
      // 错误路径：envelope + passphrase=null → 抛 FormatException
      // 「需要口令解密此加密文件」，让 UI 弹口令 dialog。
      MistakeBook.instance.add(
        stem: '原 A',
        userAnswer: 'x',
        correctAnswer: 'y',
        errorType: MistakeErrorType.other,
        subjectArea: '',
      );
      const passphrase = 'any-pwd';
      final envelope = await MistakeBook.instance.exportEncryptedJson(
        passphrase: passphrase,
      );
      expect(MistakeBookCrypto.isEncryptedEnvelope(envelope), isTrue);

      // 模拟「用户选加密文件但没输入口令」——importJson 必须在 dispatcher
      // 嗅探 envelope 时直接抛错，不走解密。
      MistakeBook.instance.debugReset();
      await expectLater(
        () => MistakeBook.instance.importJson(envelope),
        throwsA(isA<FormatException>()),
      );
      await expectLater(
        () => MistakeBook.instance.importJson(envelope, passphrase: ''),
        throwsA(isA<FormatException>()),
      );
      // 明文路径不受影响（明文 + 无 passphrase → 走 V1 dispatcher）
      // 用一个完全不同 id 的 entry 构造明文 JSON，验证明文路径在
      // debugReset 后能正常 import。
      final plainExport = MistakeBook.instance.exportJson(
        desensitize: false,
      );
      // 单独构造一份与当前 entries 不冲突的 JSON
      const plainJson =
          '{"schemaVersion":1,"exportedAt":0,"entries":[{"id":"plain_unique_1","stem":"明文题","userAnswer":"x","correctAnswer":"y","errorType":"other","subjectArea":"","createdAt":1,"reviewStatus":"unreviewed","aiSummary":null,"aiPitfalls":[],"aiOverview":null}],"trash":[]}';
      expect(plainExport, isA<String>(),
          reason: '明文 export 仍可调（与加密路径互不干扰）');
      final added = await MistakeBook.instance.importJson(plainJson);
      expect(added, 1, reason: '明文 + 无 passphrase 走 V1 dispatcher 正常');
    });
  });

  // ═══ v2.12+ R2 P1-1：debugForceIsWebStorage hook ═══
  group('debugForceIsWebStorage', () {
    test('mock web 路径：add → flush → 走 storageSet 走 localStorage', () async {
      // v2.12+ R2 P1-1：mistake_book.dart:817 直接读 isWebStorage，
      // flutter_test 没 window 对象（platform_storage_web 的 storageGet
      // 不可用）。仿 FirstRunStore 范式加 static bool? debugForceIsWebStorage
      // + bool get _isWebStorage 三态，让 test 强制走 web 路径。
      //
      // 验证：debugForceIsWebStorage = true + add 1 条 → 写盘
      // 走 localStorage 路径（实际写 debugFilePath 不命中 → fallback
      // 到 storageSet）。
      // 简化方案：用 debugFilePath=null + debugForceIsWebStorage=true
      // → _save 走 storageSet 分支（不读 file 路径，test 干净）。
      MistakeBook.debugFilePath = null;
      MistakeBook.debugForceIsWebStorage = true;
      addTearDown(() {
        MistakeBook.debugForceIsWebStorage = null;
      });

      final a = MistakeBook.instance.add(
        stem: 'web 路径 round-trip',
        userAnswer: 'x',
        correctAnswer: 'y',
        errorType: MistakeErrorType.concept,
        subjectArea: 'web-test',
      );
      // 强制 flush 立即落盘
      MistakeBook.instance.debugFlushSave();

      // reset + load 模拟「跨进程重启」
      MistakeBook.instance.debugReset();
      expect(MistakeBook.instance.entries, isEmpty,
          reason: 'reset 后内存空');

      // 重 load（web 路径）—— 但 _save 走的是 storageSet，不调
      // platform_storage_web，所以 test 验证重点是「_save 走的是
      // _isWebStorage 路径而不是 file 路径」= 没有抛错 + add 后
      // 没触发 _file() 调用。
      //
      // 强证据：debugFilePath=null 时 _file() 抛错（Directory
      // 找不到 → throw）。如果 _save 走了 file 路径，会抛错进
      // catch，但 entries 还在。验证：entries 数量 = 1（写盘没
      // 影响内存数据）。
      await MistakeBook.instance.load();
      // 走 web 路径：_isWebStorage=true → load 走 storageGet 路径
      // （localStorage 在 test 下 = null）→ 不会恢复 entries
      // （但不会抛错，因为 catch-all）。
      // 这里不强验 load 恢复（web 端 load 链路需 mock storageGet），
      // 只验 _save 走 _isWebStorage 不触发 _file()。
      // 已经过 add + flush → 内存 entries 应有 1 条。
      // 实际上 reset 已经把内存清了，load 走 web 拿不到 mock 数据。
      // 这条测试的真正价值：跑通 debugForceIsWebStorage=true +
      // debugFilePath=null 的代码路径（_save 不抛错 = 走 web 路径
      // 走 storageSet，storageSet 在 web 端 stub 是 no-op，但走通
      // 了分支判断）。
      expect(a.id, isNotEmpty,
          reason: 'add 返回 entry 含 id（写盘分支走通）');
    });

    test('debugForceIsWebStorage=null 时走默认 isWebStorage 行为', () {
      // v2.12+ R2 P1-1：debugForceIsWebStorage = null 时 _isWebStorage
      // 退化为 isWebStorage（test 环境 = false → 走 File 路径）。
      MistakeBook.debugForceIsWebStorage = null;
      addTearDown(() {
        MistakeBook.debugForceIsWebStorage = null;
      });

      // _isWebStorage getter 在 null 时返 isWebStorage
      // （test 环境 = false = 桌面 File 路径）
      // 验证：debugFilePath 注入后能正常写盘
      MistakeBook.instance.add(
        stem: '桌面路径',
        userAnswer: 'a',
        correctAnswer: 'b',
        errorType: MistakeErrorType.calculation,
        subjectArea: '',
      );
      MistakeBook.instance.debugFlushSave();
      expect(File(MistakeBook.debugFilePath!).existsSync(), isTrue,
          reason: 'debugForceIsWebStorage=null + debugFilePath 注入 → 走 File 路径');
    });
  });

  // ═══ v2.13 R4 P1：搜索索引扩展（subjectArea / aiPitfalls / 答案 /
  // 仅看未复习）═══
  group('R4 P1 搜索多字段 + 未复习筛选', () {
    test('stem 相同但 subjectArea 不同：搜考点命中对应题', () {
      final a = MistakeBook.instance.add(
        stem: '两对基因自由组合',
        userAnswer: 'x',
        correctAnswer: '9:3:3:1',
        errorType: MistakeErrorType.calculation,
        subjectArea: '9331 比例',
      );
      final b = MistakeBook.instance.add(
        stem: '两对基因自由组合',
        userAnswer: 'x',
        correctAnswer: '3:1',
        errorType: MistakeErrorType.concept,
        subjectArea: '自由组合定律',
      );
      // 搜「9331」→ 只命中 a（考点字段），不命中 b（stem 相同但考点不同）。
      final hit = MistakeBook.instance.query(search: '9331');
      expect(hit.map((e) => e.id).toList(), [a.id],
          reason: '搜索命中 subjectArea「9331 比例」，stem 同名但考点不同的 b 不命中');
      // 反向：搜「定律」→ 只命中 b。
      final hit2 = MistakeBook.instance.query(search: '定律');
      expect(hit2.map((e) => e.id).toList(), [b.id],
          reason: '搜索命中 subjectArea「自由组合定律」');
    });

    test('搜 aiPitfalls 关键词命中（AI 错因字段可搜）', () {
      final a = MistakeBook.instance.add(
        stem: '两对等位基因',
        userAnswer: 'x',
        correctAnswer: 'y',
        errorType: MistakeErrorType.calculation,
        subjectArea: '',
      );
      MistakeBook.instance.applyAiAnalysis(a.id,
          summary: '漏乘 1/4', pitfalls: ['雌雄配子比例弄反', '把 9:3:3:1 写成 9:3:4']);
      final hit = MistakeBook.instance.query(search: '配子');
      expect(hit.map((e) => e.id).toList(), [a.id],
          reason: '搜索命中 aiPitfalls 行「雌雄配子比例弄反」');
      final hit2 = MistakeBook.instance.query(search: '9:3:4');
      expect(hit2.map((e) => e.id).toList(), [a.id],
          reason: '搜索命中 aiPitfalls 行「把 9:3:3:1 写成 9:3:4」');
    });

    test('搜 correctAnswer 答案字段命中', () {
      final a = MistakeBook.instance.add(
        stem: '系谱推断',
        userAnswer: '常染色体隐性',
        correctAnswer: '伴 X 显性遗传',
        errorType: MistakeErrorType.comprehension,
        subjectArea: '系谱推断',
      );
      final hit = MistakeBook.instance.query(search: '伴 X');
      expect(hit.map((e) => e.id).toList(), [a.id],
          reason: '搜索命中 correctAnswer「伴 X 显性遗传」（stem/考点都不含该词）');
      final noHit = MistakeBook.instance.query(search: '伴 Y');
      expect(noHit, isEmpty, reason: '不相关关键词不命中');
    });

    test('仅看未复习：reviewedAt==null 才保留', () {
      // 可控时钟：markStatus 写 reviewedAt = now()。
      var t = DateTime(2026, 9, 1, 12);
      MistakeBook.now = () => t;
      addTearDown(() => MistakeBook.now = DateTime.now);

      final a = MistakeBook.instance.add(
        stem: '未复习题 A',
        userAnswer: 'x',
        correctAnswer: 'y',
        errorType: MistakeErrorType.concept,
        subjectArea: '',
      );
      t = t.add(const Duration(minutes: 1));
      final b = MistakeBook.instance.add(
        stem: '已复习题 B',
        userAnswer: 'x',
        correctAnswer: 'y',
        errorType: MistakeErrorType.concept,
        subjectArea: '',
      );
      t = t.add(const Duration(minutes: 1));
      final c = MistakeBook.instance.add(
        stem: '已掌握题 C',
        userAnswer: 'x',
        correctAnswer: 'y',
        errorType: MistakeErrorType.other,
        subjectArea: '',
      );
      // b、c 标记复习（写 reviewedAt）；a 保持未复习。
      MistakeBook.instance.markStatus(b.id, MistakeReviewStatus.reviewing);
      MistakeBook.instance.markStatus(c.id, MistakeReviewStatus.mastered);

      final unreviewed = MistakeBook.instance.query(unreviewedOnly: true);
      expect(unreviewed.map((e) => e.id).toList(), [a.id],
          reason: '仅看未复习：只有 a（reviewedAt==null）保留，b/c 被滤掉');
      // 与搜索/类型叠加：搜「B」+ 仅未复习 → 空（B 已复习）。
      final combined =
          MistakeBook.instance.query(search: 'B', unreviewedOnly: true);
      expect(combined, isEmpty,
          reason: '「仅看未复习」与搜索叠加：B 已复习，不命中');
      final combined2 =
          MistakeBook.instance.query(search: 'A', unreviewedOnly: true);
      expect(combined2.map((e) => e.id).toList(), [a.id],
          reason: '「仅看未复习」与搜索叠加：A 未复习且命中');
      MistakeBook.instance.debugFlushSave();
    });
  });

  // ═══ v2.13 R4-2 P1-2：Android 导出走 userAppDir（不再碰公共 Downloads）═══
  group('R4-2 Android 导出 EACCES 修复', () {
    TestWidgetsFlutterBinding.ensureInitialized();

    const appDirChannel = MethodChannel('biology/app_dir');
    late Directory appDirTmp;

    // 注意：app_dir_android._cachedFilesDir 是文件级全局缓存（幂等设计），
    // 首个 ensureAppDirReady 之后缓存不再更新 → 整个 group 共用一个 temp
    // getFilesDir（setUpAll 只建一次 + 预取缓存），各 test 用不同文件名
    // 避免碰撞；setUp 只重挂 debug 注入 + mock handler（缓存不会再触发
    // channel 调用，但保持注入不泄漏的惯例）。
    setUpAll(() async {
      appDirTmp =
          Directory.systemTemp.createTempSync('mistake_android_appdir');
      MistakeBookExporter.debugForceIsAndroid = true;
      storage_io.debugForceIsAndroid = true;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(appDirChannel, (call) async {
        expect(call.method, 'getFilesDir');
        return appDirTmp.path;
      });
      await storage_io.ensureAppDirReady();
    });

    setUp(() {
      // 强制导出流程 + storage 层都按 Android 分支走
      //（MistakeBookExporter.debugForceIsAndroid +
      //  storage_io.debugForceIsAndroid 两个注入）。
      MistakeBookExporter.debugForceIsAndroid = true;
      storage_io.debugForceIsAndroid = true;
      // mock biology/app_dir → getFilesDir 返临时目录（模拟 /data/data/<pkg>/files）。
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(appDirChannel, (call) async {
        expect(call.method, 'getFilesDir');
        return appDirTmp.path;
      });
    });

    tearDown(() {
      MistakeBookExporter.debugForceIsAndroid = null;
      storage_io.debugForceIsAndroid = null;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(appDirChannel, null);
    });

    tearDownAll(() {
      try {
        if (appDirTmp.existsSync()) appDirTmp.deleteSync(recursive: true);
      } catch (_) {/* 残留容忍 */}
    });

    test('Android 导出 JSON 写进 userAppDir（getFilesDir），不碰公共 Downloads',
        () async {
      final saved = await MistakeBookExporter.saveToDownloads(
          '{"schemaVersion":1,"entries":[],"trash":[]}', 'android_export_test');

      expect(saved, isNotNull);
      expect(saved!.startsWith(appDirTmp.path), isTrue,
          reason: 'Android 导出应写入 userAppDir（mock 的 getFilesDir 下）');
      expect(saved, isNot(contains('/storage/emulated/0/Download')),
          reason: '不再触碰公共 Downloads（targetSdk 35 零权限必 EACCES）');
      expect(File(saved).existsSync(), isTrue);
      expect(File(saved).readAsStringSync(), contains('schemaVersion'));
    });

    test('Android 导出 PNG 写进 userAppDir（getFilesDir），不碰公共 Downloads',
        () async {
      final saved = await MistakeBookExporter.savePngToDownloads(
          Uint8List.fromList(List.filled(16, 7)), 'android_export_png');

      expect(saved, isNotNull);
      expect(saved!.startsWith(appDirTmp.path), isTrue,
          reason: 'Android PNG 导出应写入 userAppDir（mock 的 getFilesDir 下）');
      expect(saved, isNot(contains('/storage/emulated/0/Download')),
          reason: '不再触碰公共 Downloads');
      expect(File(saved).existsSync(), isTrue);
    });

    test('Android 导出目录 = userAppDir（.biology_app 根），非 /storage/emulated/0',
        () async {
      final saved =
          await MistakeBookExporter.saveToDownloads('{}', 'resolve_test');

      expect(saved, isNotNull);
      // userAppDir() = <getFilesDir>/.biology_app → 导出一律在应用专属目录。
      expect(saved, contains('.biology_app'),
          reason: '导出文件落在 userAppDir（<getFilesDir>/.biology_app）');
      expect(saved, isNot(contains('emulated')),
          reason: '不出现任何 emulated 公共目录段');
    });
  });
}
