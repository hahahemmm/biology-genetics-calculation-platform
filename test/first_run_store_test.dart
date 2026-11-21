// first_run_store_test.dart —— 首启标记 + 角色分流测试
//
// 覆盖：
//   1. isFirstRun 初值：磁盘无 first_run.json 时 isFirstRun()=true
//   2. setRole 持久化：调 setRole 后磁盘有 json，currentRole()=指定值
//      且 isFirstRun()=false
//   3. 二次启动不弹 dialog：debugFilePath 切回 instance 模拟"重启"，
//      load() 后 isFirstRun()=false、currentRole()=上次选的角色
//   4. JSON 损坏降级：文件存在但内容坏 → 降级到首启，**不**抛
//   5. Web 端存储（用 isWebStorage=true mock + debugWebStorage）→ 角色
//      能正确读出（v2.12 Wave 3-B P0：修 Platform.environment web 端
//      UnimplementedError 后的回归测试）

import 'dart:io';

import 'package:biology/state/first_run_store.dart';
import 'package:biology/storage/platform_storage_io.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory tmp;
  late String filePath;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('first_run_store_test');
    filePath = '${tmp.path}/first_run.json';
    FirstRunStore.debugFilePath = filePath;
    FirstRunStore.debugWebStorage = null;
    FirstRunStore.debugForceIsWebStorage = null;
    FirstRunStore.instance.debugReset();
  });

  tearDown(() {
    FirstRunStore.debugFilePath = null;
    FirstRunStore.debugWebStorage = null;
    FirstRunStore.debugForceIsWebStorage = null;
    FirstRunStore.instance.debugReset();
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  test('isFirstRun 初值：磁盘无 first_run.json 时 isFirstRun()=true', () async {
    // 首次启动：debugFilePath 指向不存在的文件 → load() 不抛错，
    // _role 保持 null → isFirstRun()=true。
    expect(File(filePath).existsSync(), isFalse,
        reason: 'setUp 后磁盘应无 first_run.json');
    await FirstRunStore.instance.load();
    expect(FirstRunStore.instance.isFirstRun(), isTrue,
        reason: '首次启动 isFirstRun()=true');
    expect(FirstRunStore.instance.currentRole(), isNull,
        reason: '首次启动 currentRole()=null');
  });

  test('setRole 持久化：写盘后 currentRole()=指定值且 isFirstRun()=false',
      () async {
    await FirstRunStore.instance.load();
    expect(FirstRunStore.instance.isFirstRun(), isTrue);

    // 选老师
    await FirstRunStore.instance.setRole(UserRole.teacher);
    expect(FirstRunStore.instance.currentRole(), UserRole.teacher);
    expect(FirstRunStore.instance.isFirstRun(), isFalse,
        reason: '选完角色后 isFirstRun()=false');
    // 磁盘有 json
    expect(File(filePath).existsSync(), isTrue,
        reason: 'setRole 后磁盘应有 first_run.json');
    final j =
        await File(filePath).readAsString().then((s) => s); // synchronous path
    expect(j, contains('"role":"teacher"'),
        reason: '磁盘 JSON 应含 role=teacher');
  });

  test('v2.19.54 回归：nudge 在 store 未加载时⛔ 不写盘（防抹掉用户角色）',
      () async {
    // 事故实录：未隔离 FirstRunStore 的测试触发键宿主成功路径 → nudge
    // 写盘 {'role': null} → 真实用户角色被覆盖 + 泵真 app 的测试被首启
    // dialog 盖住全红。此守卫钉住修复：未 load() 时 mark 只更内存、
    // 磁盘文件必须保持不存在（setup 时即断言过无文件）。
    expect(File(filePath).existsSync(), isFalse,
        reason: '前提：未加载 store 时磁盘无文件');
    await FirstRunStore.instance.markShortcutNudgeShown();
    expect(FirstRunStore.instance.shortcutNudgeShown, isTrue,
        reason: '内存标记生效（当次会话不再弹）');
    expect(File(filePath).existsSync(), isFalse,
        reason: '⛔ 未加载写盘会把 role:null 落出去抹掉用户角色——不许写');
  });

  test('v2.19.54：nudge 已加载时正常落盘且与 role 共存（不互相覆盖）',
      () async {
    await FirstRunStore.instance.load();
    await FirstRunStore.instance.setRole(UserRole.student);
    await FirstRunStore.instance.markShortcutNudgeShown();
    final j = File(filePath).readAsStringSync();
    expect(j, contains('"role":"student"'),
        reason: '⛔ 合并写盘：nudge 不许把已存 role 抹掉');
    expect(j, contains('"nudge":true'));
    // 二次启动：role 与 nudge 都读回。
    FirstRunStore.instance.debugReset();
    await FirstRunStore.instance.load();
    expect(FirstRunStore.instance.currentRole(), UserRole.student);
    expect(FirstRunStore.instance.shortcutNudgeShown, isTrue);
  });

  test('二次启动不弹 dialog：reset 后 load 仍能读出上次角色', () async {
    // 1. 首次启动 → 选学生 → 落盘
    await FirstRunStore.instance.load();
    await FirstRunStore.instance.setRole(UserRole.student);
    expect(FirstRunStore.instance.currentRole(), UserRole.student);

    // 2. 模拟"重启"：debugReset 清内存（不删磁盘），再 load
    FirstRunStore.instance.debugReset();
    expect(FirstRunStore.instance.isFirstRun(), isTrue,
        reason: 'debugReset 后 _role=null → isFirstRun()=true');
    await FirstRunStore.instance.load();

    // 3. 二次启动：读到上次选的角色，isFirstRun=false（不再弹 dialog）
    expect(FirstRunStore.instance.currentRole(), UserRole.student,
        reason: '二次启动能读出上次选的学生角色');
    expect(FirstRunStore.instance.isFirstRun(), isFalse,
        reason: '二次启动 isFirstRun()=false → HomeShell 不会弹 dialog');

    // 4. v2.13 R5 P0：老磁盘 'parent' 数据应兜底为 student。
    //    v2.12 / v2.13 早期版本写入 {"role":"parent"} 的用户，升级
    //    后 fromName 兜底为 student——不被重弹首启 dialog、也不丢用户。
    File(filePath).writeAsStringSync('{"role":"parent"}');
    FirstRunStore.instance.debugReset();
    await FirstRunStore.instance.load();
    expect(FirstRunStore.instance.currentRole(), UserRole.student,
        reason: '老磁盘 role=parent 兜底为 student（R5 移除 parent 枚举的向后兼容）');
    expect(FirstRunStore.instance.isFirstRun(), isFalse,
        reason: 'role 字段非空 → isFirstRun=false（兜底仍视作已选）');
  });

  // ===== v2.12 Wave 3-B P0 新增：JSON 损坏降级 + Web 端 storage =====

  test('JSON 损坏降级：文件存在但内容坏 → 降级到首启，不抛', () async {
    // 预置一个损坏的 JSON（不是合法 JSON 字符串）
    File(filePath).writeAsStringSync('not-valid-json{{{');
    // debugFilePath 指向的"磁盘"已有内容，但内容坏
    // load() 必须不抛错，_role 保持 null → isFirstRun()=true
    await FirstRunStore.instance.load();
    expect(FirstRunStore.instance.isFirstRun(), isTrue,
        reason: 'JSON 损坏 → _role=null → isFirstRun=true（降级到首启）');
    expect(FirstRunStore.instance.currentRole(), isNull,
        reason: '损坏文件不解析出 role');
    // 不抛错 = 关键（不依赖 tester.takeException，因为异步已 await）
  });

  test('JSON 内容合法但 role 字段缺失：保持首启', () async {
    // role 字段缺失 → _role 保持 null
    File(filePath).writeAsStringSync('{"version":1}');
    await FirstRunStore.instance.load();
    expect(FirstRunStore.instance.isFirstRun(), isTrue,
        reason: 'role 字段缺失 → _role=null → isFirstRun=true');
    expect(FirstRunStore.instance.currentRole(), isNull);
  });

  test('JSON 顶层不是 Map（List / 字符串）：保持首启', () async {
    // 顶层是 List
    File(filePath).writeAsStringSync('[]');
    await FirstRunStore.instance.load();
    expect(FirstRunStore.instance.isFirstRun(), isTrue,
        reason: '顶层不是 Map → 保持首启');
    // 顶层是 String
    File(filePath).writeAsStringSync('"role"');
    FirstRunStore.instance.debugReset();
    await FirstRunStore.instance.load();
    expect(FirstRunStore.instance.isFirstRun(), isTrue,
        reason: '顶层 String → 保持首启');
  });

  test('Web 端存储（isWebStorage=true mock）→ 角色能正确读出', () async {
    // flutter_test 无 window 对象，platform_storage_web 的 storageGet 不可用。
    // 用 debugWebStorage + debugForceIsWebStorage 模拟"用户在浏览器中"。
    final webStore = <String, String>{};
    FirstRunStore.debugWebStorage = webStore;
    FirstRunStore.debugForceIsWebStorage = true;
    // 同时把 debugFilePath 设为 null 确保不走桌面 File 路径
    FirstRunStore.debugFilePath = null;
    FirstRunStore.instance.debugReset();

    // 1. 首启：web 端 localStorage 空
    await FirstRunStore.instance.load();
    expect(FirstRunStore.instance.isFirstRun(), isTrue,
        reason: 'web 端 localStorage 空 → 首启');
    expect(FirstRunStore.instance.currentRole(), isNull);

    // 2. setRole → 写 localStorage（mock）
    //    v2.13 R5 P0：枚举只有 teacher / student，web 端 round-trip
    //    改为验证 student（与磁盘版互证：首启 dialog 选学生 → 写
    //    localStorage → 刷新 → 仍为学生）。
    await FirstRunStore.instance.setRole(UserRole.student);
    expect(FirstRunStore.instance.currentRole(), UserRole.student);
    expect(webStore['first_run_json'], isNotNull,
        reason: 'setRole 应写到 web storage（mock）');
    expect(webStore['first_run_json'], contains('"role":"student"'),
        reason: 'web storage 内容含 role=student');

    // 3. 关键：isWebStorage=true 时**不**应该写桌面 File
    //    userAppDir() 在 test 返真实 ~/.biology_app 路径（虽然环境
    //    USERPROFILE 不一定有写权限），但因为走 web 分支不会到 File。
    //    这里不强断言文件不存在（userAppDir 可能因权限问题抛错），
    //    关键是 _isWebStorage 分支返回 true → 走 storageSet。

    // 4. 模拟"刷新页面"：reset 内存 + load → 从 web storage 读回
    FirstRunStore.instance.debugReset();
    expect(FirstRunStore.instance.isFirstRun(), isTrue,
        reason: 'debugReset 后 _role=null → 首启');
    await FirstRunStore.instance.load();
    expect(FirstRunStore.instance.currentRole(), UserRole.student,
        reason: 'web 端 storage round-trip：setRole → reset → load 读回 student');
    expect(FirstRunStore.instance.isFirstRun(), isFalse,
        reason: 'web 端二次启动不再弹首启 dialog');
  });

  // ===== 2026-10-29 偏好泄漏事故回归：FLUTTER_TEST + 默认真实路径闸门 =====
  //
  // 事故实录：全量回归窗口内 ~/.biology_app/first_run.json 被改写
  // （SHA256 DCA963CA… → D4BD2881…）。根因：未隔离 FirstRunStore 的
  // widget 测试（系谱页键宿主）真实 load → _loaded=true →
  // ui/shortcut_nudge.dart markShortcutNudgeShown 把 {'role':...,'nudge':true}
  // 写回真盘。修复：store 层 FLUTTER_TEST 闸（同 HistoryStore /
  // MistakeBook / PresentModeController），load 与 _save 双侧生效。

  group('v2.20.x FLUTTER_TEST 闸门：默认真实路径不读写真实用户文件', () {
    test('shouldSkipRealUserFile 真值表：web / 显式路径放行，flutter test + 默认路径跳过', () {
      expect(
        FirstRunStore.shouldSkipRealUserFile(
            isWebStorage: true, hasDebugFilePath: false, isFlutterTest: true),
        isFalse,
        reason: 'Web localStorage 路径：无磁盘文件可跳过，放行',
      );
      expect(
        FirstRunStore.shouldSkipRealUserFile(
            isWebStorage: false, hasDebugFilePath: true, isFlutterTest: true),
        isFalse,
        reason: '显式注入 debugFilePath（隔离临时文件）：round-trip 必须可测，放行',
      );
      expect(
        FirstRunStore.shouldSkipRealUserFile(
            isWebStorage: false, hasDebugFilePath: false, isFlutterTest: false),
        isFalse,
        reason: '生产环境（非 flutter test）：正常读写真实配置',
      );
      expect(
        FirstRunStore.shouldSkipRealUserFile(
            isWebStorage: false, hasDebugFilePath: false, isFlutterTest: true),
        isTrue,
        reason: 'flutter test + 默认真实路径：⛔ 必须跳过（本次事故根因）',
      );
    });

    test('load + setRole + markNudge 全链路：真实 first_run.json 字节零变化', () async {
      // 模拟事故链路：不注入 debugFilePath（默认真实路径），跑
      // load → setRole → markShortcutNudgeShown → 重启（reset+load）→
      // markShortcutNudgeShown。断言真实 ~/.biology_app/first_run.json
      // 逐字节不变（存在性 + 内容），同时内存语义照常生效（闸门只挡 IO）。
      FirstRunStore.debugFilePath = null;
      FirstRunStore.debugWebStorage = null;
      FirstRunStore.debugForceIsWebStorage = null;
      FirstRunStore.instance.debugReset();

      final realDir = userAppDir();
      expect(realDir, isNotNull, reason: '桌面测试环境应能解析 userAppDir');
      final real = File('$realDir/first_run.json');
      final existedBefore = real.existsSync();
      // 只做字节比对，不读取/打印内容语义（该文件仅 role/nudge，非凭据）。
      final bytesBefore =
          existedBefore ? real.readAsBytesSync() : const <int>[];

      // —— 事故全链路 ——
      await FirstRunStore.instance.load();
      await FirstRunStore.instance.setRole(UserRole.student);
      await FirstRunStore.instance.markShortcutNudgeShown();
      // 模拟「重启」后键宿主再次触发
      FirstRunStore.instance.debugReset();
      await FirstRunStore.instance.load();
      await FirstRunStore.instance.markShortcutNudgeShown();

      expect(real.existsSync(), existedBefore,
          reason: '⛔ 闸门失效时 setRole/markNudge 会在真实用户目录建文件——不许发生');
      if (existedBefore) {
        expect(real.readAsBytesSync(), orderedEquals(bytesBefore),
            reason: '真实 first_run.json 必须逐字节不变（本次事故即此文件被改写）');
      }

      // 内存语义不回退：闸门只挡 IO，调用方（dashboard / 键宿主）行为不变。
      // 注意第二次 reset+load 后角色回到 null（load 被闸、不读真盘）——
      // 这正是期望：真实用户角色不泄入测试内存。
      expect(FirstRunStore.instance.currentRole(), isNull,
          reason: '默认路径下 load 被闸：真实角色不泄入测试内存（防断言随真机数据漂移）');
      expect(FirstRunStore.instance.shortcutNudgeShown, isTrue,
          reason: 'markNudge 内存标记照常生效（当次会话不再弹）');
    });

    test('显式临时 debugFilePath：save / load round-trip 不受闸门影响', () async {
      // 与上一测试互证：闸门只针对「默认真实路径」，显式隔离路径必须照常
      // 可写可读（既有 setRole/二次启动测试语义，此处钉住闸门不误伤）。
      expect(
        FirstRunStore.shouldSkipRealUserFile(
            isWebStorage: false, hasDebugFilePath: true, isFlutterTest: true),
        isFalse,
      );
      await FirstRunStore.instance.load();
      await FirstRunStore.instance.setRole(UserRole.teacher);
      expect(File(filePath).existsSync(), isTrue,
          reason: '显式 debugFilePath 下 setRole 应正常落盘');
      FirstRunStore.instance.debugReset();
      await FirstRunStore.instance.load();
      expect(FirstRunStore.instance.currentRole(), UserRole.teacher,
          reason: '显式 debugFilePath 下 load 应读回（round-trip 完整）');
    });
  });

  // ===== 新手引导「看过一次就不再自动弹」（guide_done）=====

  test('guideDone 默认 false；markGuideDone 落盘且与 role / nudge 共存', () async {
    await FirstRunStore.instance.load();
    expect(FirstRunStore.instance.guideDone, isFalse,
        reason: '磁盘无 guide_done 字段 → 按 false（下次启动仍自动开引导）');

    await FirstRunStore.instance.setRole(UserRole.teacher);
    await FirstRunStore.instance.markShortcutNudgeShown();
    await FirstRunStore.instance.markGuideDone();
    expect(FirstRunStore.instance.guideDone, isTrue);

    final j = File(filePath).readAsStringSync();
    expect(j, contains('"guide_done":true'), reason: '合并写盘应带 guide_done');
    expect(j, contains('"role":"teacher"'), reason: '⛔ 不许把已存 role 抹掉');
    expect(j, contains('"nudge":true'), reason: '⛔ 不许把已存 nudge 抹掉');

    // 二次启动：读回 true（HomeShell 据此不再自动弹引导）
    FirstRunStore.instance.debugReset();
    expect(FirstRunStore.instance.guideDone, isFalse,
        reason: 'debugReset 应一并重置 guideDone');
    await FirstRunStore.instance.load();
    expect(FirstRunStore.instance.guideDone, isTrue, reason: 'round-trip');
    expect(FirstRunStore.instance.currentRole(), UserRole.teacher);
  });

  test('guide_done 非 true 视为没看过；未 load 时 markGuideDone 不写盘', () async {
    // 老数据 / 脏数据：只有字面量 true 才算看过。
    File(filePath).writeAsStringSync('{"role":"student","guide_done":"yes"}');
    await FirstRunStore.instance.load();
    expect(FirstRunStore.instance.guideDone, isFalse,
        reason: '字符串 yes 不是 true → 仍要自动开引导');

    // 未 load() 时写盘会把 role:null 落出去抹掉角色（同 nudge 的事故闸）
    FirstRunStore.instance.debugReset();
    await FirstRunStore.instance.markGuideDone();
    expect(FirstRunStore.instance.guideDone, isTrue,
        reason: '当次会话内存标记生效');
    expect(File(filePath).readAsStringSync(), contains('"role":"student"'),
        reason: '⛔ 未加载写盘会抹掉 role——不许写');
  });
}
