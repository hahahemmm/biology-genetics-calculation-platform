// present_mode_controller_test.dart —— 课堂模式控制器持久化测试
//
// v2.12 R1 C P0 #7 修复回归测试：原 `Platform.environment['USERPROFILE']`
// 在 Web 端抛 UnimplementedError，catch 吞掉 → 课堂模式 / 激光笔 / 高对比
// 全部不持久。改用 platform_storage 中性 API 后必须验证：
//   1. 桌面 / 安卓 File 路径 round-trip：enabled / laser / hc 写盘 → load 读回
//   2. Web 端 localStorage 路径 round-trip（用 debugWebStorage mock）
//   3. JSON 损坏降级：文件存在但内容坏 → 降级到默认关，不抛
//
// v2.20.1 → 2026-10-30 修订（用户裁定，本文件的核心不变式）：
//   **课堂模式 enabled 是持久化的模式记忆**——首次启动（无配置文件 /
//   字段缺失）一律「标准」小字号；之后每次冷启动恢复上次退出时的模式
//   （上次是课堂大屏就仍进课堂大屏）。
//   ⇒ setEnabled(true) 当次为 true，**且落盘** `"enabled":true`；
//     debugReset + load 后 enabled 恢复为 true，laser / hc 偏好按磁盘值
//     恢复；存量 JSON 里的 `enabled:true` 照常恢复；`_save` 三字段同写
//     （enabled / laser / hc）。真实 App（非测试）的持久化语义一致。
//
// ⚠️ 本文件所有持久化用例都**必须**注入 `debugFilePath`（隔离临时文件）：
// v2.20.0 起 `PresentModeController` 在 `FLUTTER_TEST` 环境下对**默认**
// 真实路径（`~/.biology_app/present_mode.json`）加了读写闸门——不注入时
// load 直接保持标准默认（enabled/laser/hc 全 false）、save 不落盘。所以
// 忘了注入不会「读到真机配置」，而是用例静默变成测默认值（setUp 已统一
// 注入，末尾小组专门钉住这条闸门语义）。

import 'dart:io';

import 'package:biology/state/present_mode_controller.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory tmp;
  late String filePath;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('present_mode_test');
    filePath = '${tmp.path}/present_mode.json';
    // 显式隔离路径：走真实 File 分支但不碰用户配置（FLUTTER_TEST 闸门
    // 只拦「默认路径」，注入 debugFilePath 时读写照常）。
    PresentModeController.debugFilePath = filePath;
    PresentModeController.debugWebStorage = null;
    PresentModeController.debugForceIsWebStorage = null;
    PresentModeController.instance.debugReset();
  });

  tearDown(() {
    PresentModeController.debugFilePath = null;
    PresentModeController.debugWebStorage = null;
    PresentModeController.debugForceIsWebStorage = null;
    PresentModeController.instance.debugReset();
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  group('桌面 / 安卓 File 路径', () {
    test('setEnabled 落盘模式记忆；laser / hc 落盘 + 读回', () async {
      // 1. 首次启动：磁盘无文件 → load 后保持默认
      expect(File(filePath).existsSync(), isFalse,
          reason: 'setUp 后磁盘应无 present_mode.json');
      await PresentModeController.instance.load();
      expect(PresentModeController.instance.enabled, isFalse);
      expect(PresentModeController.instance.laserEnabled, isFalse);
      expect(PresentModeController.instance.highContrast, isFalse);

      // 2. 开课堂模式 → 当次生效，**且落盘**（模式记忆，2026-10-30）
      await PresentModeController.instance.setEnabled(true);
      expect(PresentModeController.instance.enabled, isTrue,
          reason: 'setEnabled(true) 当次会话必须立即为 true（课堂大屏可用）');
      expect(File(filePath).existsSync(), isTrue,
          reason: 'enabled 持久化：setEnabled 必须写盘');
      expect(File(filePath).readAsStringSync(), contains('"enabled":true'),
          reason: '磁盘 JSON 必须含 "enabled":true（冷启动恢复用）');

      // 3. 激光笔 + 高对比（偏好）→ 落盘（与 enabled 同一 JSON）
      await PresentModeController.instance.setLaserEnabled(true);
      await PresentModeController.instance.setHighContrast(true);
      expect(PresentModeController.instance.laserEnabled, isTrue);
      expect(PresentModeController.instance.highContrast, isTrue);
      expect(File(filePath).existsSync(), isTrue);
      final content = File(filePath).readAsStringSync();
      expect(content, contains('"laser":true'));
      expect(content, contains('"hc":true'));
      expect(content, contains('"enabled":true'),
          reason: 'JSON 三字段同写：enabled / laser / hc');

      // 4. 模拟"重启"：reset + load → 模式记忆恢复上次模式
      PresentModeController.instance.debugReset();
      await PresentModeController.instance.load();
      expect(PresentModeController.instance.enabled, isTrue,
          reason: '冷启动恢复上次退出时的模式（enabled 持久化记忆）');
      expect(PresentModeController.instance.laserEnabled, isTrue,
          reason: '激光笔是偏好，照常恢复');
      expect(PresentModeController.instance.highContrast, isTrue,
          reason: '高对比是偏好，照常恢复');

      // 5. 聚光灯 spotlightOn **不**落盘（v2.3 会话级）——debugReset 已清
      expect(PresentModeController.instance.spotlightOn, isFalse,
          reason: '聚光灯不持久化，重启后回到默认关');
    });

    test('首次启动无配置文件 → 标准模式', () async {
      expect(File(filePath).existsSync(), isFalse,
          reason: '首次安装：磁盘无 present_mode.json');
      await PresentModeController.instance.load();
      expect(PresentModeController.instance.enabled, isFalse,
          reason: '首次启动（无文件）= 标准模式');
      expect(PresentModeController.instance.laserEnabled, isFalse);
      expect(PresentModeController.instance.highContrast, isFalse);
    });

    test('上次退出是课堂大屏 → 冷启动恢复课堂大屏', () async {
      // 上次会话：开激光笔 + 高对比 + 课堂大屏，退出
      await PresentModeController.instance.setLaserEnabled(true);
      await PresentModeController.instance.setHighContrast(true);
      await PresentModeController.instance.setEnabled(true);

      // 冷启动：内存清空 → load 从磁盘恢复整套模式记忆
      PresentModeController.instance.debugReset();
      await PresentModeController.instance.load();
      expect(PresentModeController.instance.enabled, isTrue,
          reason: '上次是课堂大屏 → 冷启动仍进课堂大屏');
      expect(PresentModeController.instance.laserEnabled, isTrue,
          reason: 'laser 偏好按磁盘恢复');
      expect(PresentModeController.instance.highContrast, isTrue,
          reason: 'hc 偏好按磁盘恢复');
    });
  });

  group('Web 端 localStorage 路径', () {
    test('web 路径（isWebStorage=true mock）：三字段 round-trip，enabled 照常恢复',
        () async {
      final webStore = <String, String>{};
      PresentModeController.debugWebStorage = webStore;
      PresentModeController.debugForceIsWebStorage = true;
      PresentModeController.debugFilePath = null;
      PresentModeController.instance.debugReset();

      // 1. 首启：web 端 localStorage 空
      await PresentModeController.instance.load();
      expect(PresentModeController.instance.enabled, isFalse,
          reason: 'web 端 localStorage 空 → 首次启动标准模式');

      // 2. setEnabled(true) → 当次生效，**且写 localStorage**（模式记忆）
      await PresentModeController.instance.setEnabled(true);
      expect(PresentModeController.instance.enabled, isTrue,
          reason: 'setEnabled(true) 当次必须为 true');
      expect(webStore['present_mode_json'], contains('"enabled":true'),
          reason: 'enabled 持久化：必须写 localStorage');

      // 3. 激光笔 + 高对比（偏好）走 localStorage
      await PresentModeController.instance.setLaserEnabled(true);
      await PresentModeController.instance.setHighContrast(true);
      expect(webStore['present_mode_json'], isNotNull);
      expect(webStore['present_mode_json'], contains('"laser":true'));
      expect(webStore['present_mode_json'], contains('"hc":true'));
      expect(webStore['present_mode_json'], contains('"enabled":true'),
          reason: 'JSON 三字段同写：enabled / laser / hc');

      // 4. 模拟"刷新页面"：reset + load → 模式记忆恢复 enabled=true
      PresentModeController.instance.debugReset();
      await PresentModeController.instance.load();
      expect(PresentModeController.instance.enabled, isTrue,
          reason: '刷新后恢复上次模式（enabled 持久化记忆）');
      expect(PresentModeController.instance.laserEnabled, isTrue);
      expect(PresentModeController.instance.highContrast, isTrue);
    });
  });

  group('JSON 损坏降级', () {
    test('文件存在但内容坏 → 降级到默认关，不抛', () async {
      File(filePath).writeAsStringSync('not-valid-json{{{');
      await PresentModeController.instance.load();
      expect(PresentModeController.instance.enabled, isFalse,
          reason: 'JSON 损坏 → enabled 默认关（降级）');
      expect(PresentModeController.instance.laserEnabled, isFalse);
      expect(PresentModeController.instance.highContrast, isFalse);
    });

    test('JSON 顶层不是 Map → 降级到默认关', () async {
      File(filePath).writeAsStringSync('"some string"');
      await PresentModeController.instance.load();
      expect(PresentModeController.instance.enabled, isFalse,
          reason: '顶层不是 Map → 降级到默认关');
    });
  });

  // ── 存量配置（含 enabled:true）冷启动语义 ──────────────────────────
  group('存量配置冷启动', () {
    test('enabled:true + hc:true → 冷启动恢复课堂大屏，hc 偏好保留', () async {
      // 真实存量形态：用户上次停在课堂大屏（且开了高对比）。
      File(filePath).writeAsStringSync(
          '{"enabled":true,"laser":true,"hc":true}');
      await PresentModeController.instance.load();
      expect(PresentModeController.instance.enabled, isTrue,
          reason: '存量 enabled:true 照常恢复：冷启动仍进课堂大屏');
      expect(PresentModeController.instance.laserEnabled, isTrue,
          reason: 'laser 是偏好，照常恢复');
      expect(PresentModeController.instance.highContrast, isTrue,
          reason: 'hc 是配色偏好，照常恢复（≠ 课堂大屏已开启）');
    });

    test('存量配置无 laser / hc 字段时默认关（2026-08-31 裁定兼容）', () async {
      // v2.3.4 之前的配置没有 laser / hc 字段，加载时应默认关
      File(filePath).writeAsStringSync('{"enabled":true}');
      await PresentModeController.instance.load();
      expect(PresentModeController.instance.enabled, isTrue,
          reason: 'enabled 照常从存量配置恢复（模式记忆）');
      expect(PresentModeController.instance.laserEnabled, isFalse,
          reason: '存量配置无 laser → 默认关');
      expect(PresentModeController.instance.highContrast, isFalse);
    });
  });

  group('debugEnsureLoaded', () {
    test('debugEnsureLoaded 后 initState 的 load() 不会覆盖', () async {
      File(filePath).writeAsStringSync(
          '{"enabled":true,"laser":true,"hc":true}');
      await PresentModeController.instance.debugEnsureLoaded();
      expect(PresentModeController.instance.laserEnabled, isTrue,
          reason: 'load 真的读了磁盘（偏好恢复）');
      expect(PresentModeController.instance.enabled, isTrue,
          reason: '模式记忆照常恢复（enabled:true）');

      // debugSetEnabled 改 enabled（不写盘）——模拟 test 主体切回标准模式
      PresentModeController.instance.debugSetEnabled(false);
      expect(PresentModeController.instance.enabled, isFalse);

      // 再调一次 load() 不会覆盖（_loaded 守卫）
      await PresentModeController.instance.load();
      expect(PresentModeController.instance.enabled, isFalse,
          reason: '_loaded 守卫让 initState 后续 load() 不覆盖当次会话状态');
    });
  });

  // ── v2.20.0：FLUTTER_TEST 默认真实路径闸门 ──────────────────────────
  // 背景：真实配置带 hc=true（激光/高对比偏好），而大量 widget 测试直接泵
  // BiologyApp 且不注入 debugFilePath → load 读到真机偏好（高对比配色），
  // UI / 色彩断言随真机使用漂移；ClassroomQuickBar / 设置页的真实 setter
  // 还会把测试值写回真实配置。
  //
  // 验收方式（不读真实文件）：语义用纯判定 helper 钉住；集成侧断言
  // 「未注入路径时 load 得到标准默认」。写盘侧不在这里读真实文件验证——
  // 由外部验收（跑完本套用例后真实 present_mode.json 仍是偏好值、字节未变）
  // 覆盖。
  group('FLUTTER_TEST 默认真实路径闸门', () {
    test('纯判定：仅「测试进程 + 默认路径」跳过，Web / 显式路径不跳过', () {
      expect(
          PresentModeController.shouldSkipRealUserConfig(
              isWebStorage: false,
              hasDebugFilePath: false,
              isFlutterTest: true),
          isTrue,
          reason: 'flutter test + 默认真实路径 → 不得读写 ~/.biology_app');
      expect(
          PresentModeController.shouldSkipRealUserConfig(
              isWebStorage: false,
              hasDebugFilePath: false,
              isFlutterTest: false),
          isFalse,
          reason: '真实 App（非测试）行为完全不变');
      expect(
          PresentModeController.shouldSkipRealUserConfig(
              isWebStorage: false,
              hasDebugFilePath: true,
              isFlutterTest: true),
          isFalse,
          reason: '显式 debugFilePath 的临时文件 round-trip 照常');
      expect(
          PresentModeController.shouldSkipRealUserConfig(
              isWebStorage: true,
              hasDebugFilePath: false,
              isFlutterTest: true),
          isFalse,
          reason: 'Web（localStorage）路径不受闸门影响');
    });

    test('未注入 debugFilePath：load 保持标准默认，setter 只改内存', () async {
      PresentModeController.debugFilePath = null;
      PresentModeController.debugWebStorage = null;
      PresentModeController.debugForceIsWebStorage = null;
      PresentModeController.instance.debugReset();

      // 若闸门失效，这一步会读到真机配置（可能 hc=true）。
      await PresentModeController.instance.load();
      expect(PresentModeController.instance.enabled, isFalse,
          reason: '测试进程里默认路径必须保持标准默认');
      expect(PresentModeController.instance.laserEnabled, isFalse);
      expect(PresentModeController.instance.highContrast, isFalse,
          reason: 'hc 也不得从真机配置渗进来（lightwhite 类色彩断言的前提）');

      // setter 更新内存态（UI 断言仍需可切换），但 save 被同一闸门拦下。
      await PresentModeController.instance.setEnabled(true);
      await PresentModeController.instance.setHighContrast(true);
      expect(PresentModeController.instance.enabled, isTrue);
      expect(PresentModeController.instance.highContrast, isTrue,
          reason: '内存态照常切换（ModeSwitcher / 快捷条行为不变）');
    });
  });
}
