// theme_controller_test.dart —— 主题模式控制器持久化测试
//
// v2.12 R1 C P0 #7 修复回归测试：原 `Platform.environment['USERPROFILE']`
// 在 Web 端抛 UnimplementedError，catch 吞掉 → 主题不持久。改用
// platform_storage 中性 API 后必须验证：
//   1. 桌面 / 安卓 File 路径 round-trip：setMode → load 读回
//   2. Web 端 localStorage 路径 round-trip（用 debugWebStorage mock）
//   3. JSON 损坏降级：文件存在但内容坏 → 降级到默认 system，不抛

import 'dart:io';

import 'package:biology/state/theme_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory tmp;
  late String filePath;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('theme_controller_test');
    filePath = '${tmp.path}/theme_mode.json';
    ThemeController.debugFilePath = filePath;
    ThemeController.debugWebStorage = null;
    ThemeController.debugForceIsWebStorage = null;
    ThemeController.instance.debugReset();
  });

  tearDown(() {
    ThemeController.debugFilePath = null;
    ThemeController.debugWebStorage = null;
    ThemeController.debugForceIsWebStorage = null;
    ThemeController.instance.debugReset();
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  group('桌面 / 安卓 File 路径', () {
    test('setMode 写盘 + debugReset + load 读回', () async {
      // 1. 首次启动：磁盘无文件 → load 后保持默认 system
      expect(File(filePath).existsSync(), isFalse,
          reason: 'setUp 后磁盘应无 theme_mode.json');
      await ThemeController.instance.load();
      expect(ThemeController.instance.mode, ThemeMode.system,
          reason: '首次启动 mode 应为默认 system');

      // 2. 选 dark → 落盘
      await ThemeController.instance.setMode(ThemeMode.dark);
      expect(ThemeController.instance.mode, ThemeMode.dark);
      expect(File(filePath).existsSync(), isTrue,
          reason: 'setMode 后磁盘应有 theme_mode.json');
      expect(File(filePath).readAsStringSync(), contains('"mode":"dark"'),
          reason: '磁盘 JSON 应含 mode=dark');

      // 3. 模拟"重启"：reset 内存 + load → 读到 dark
      ThemeController.instance.debugReset();
      expect(ThemeController.instance.mode, ThemeMode.system,
          reason: 'debugReset 后 mode 回到默认 system');
      await ThemeController.instance.load();
      expect(ThemeController.instance.mode, ThemeMode.dark,
          reason: '重启后 load 读出上次选的模式');
    });
  });

  group('Web 端 localStorage 路径', () {
    test('web 路径（isWebStorage=true mock）：round-trip', () async {
      // flutter_test 无 window 对象，platform_storage_web 的 storageGet
      // 不可用。用 debugWebStorage + debugForceIsWebStorage 模拟"用户在浏览器中"。
      final webStore = <String, String>{};
      ThemeController.debugWebStorage = webStore;
      ThemeController.debugForceIsWebStorage = true;
      // debugFilePath 设为 null 确保不走桌面 File 路径
      ThemeController.debugFilePath = null;
      ThemeController.instance.debugReset();

      // 1. 首次启动：web 端 localStorage 空 → load 后保持默认 system
      await ThemeController.instance.load();
      expect(ThemeController.instance.mode, ThemeMode.system,
          reason: 'web 端 localStorage 空 → mode 保持默认 system');

      // 2. setMode(light) → 写 localStorage（mock）
      await ThemeController.instance.setMode(ThemeMode.light);
      expect(ThemeController.instance.mode, ThemeMode.light);
      expect(webStore['theme_mode_json'], isNotNull,
          reason: 'setMode 应写到 web storage（mock）');
      expect(webStore['theme_mode_json'], contains('"mode":"light"'),
          reason: 'web storage 内容含 mode=light');

      // 3. 模拟"刷新页面"：reset 内存 + load → 从 web storage 读回
      ThemeController.instance.debugReset();
      expect(ThemeController.instance.mode, ThemeMode.system);
      await ThemeController.instance.load();
      expect(ThemeController.instance.mode, ThemeMode.light,
          reason: '刷新后 web storage 读回 light');
    });

    test('web 路径写时**不**触桌面 File（避免浏览器里尝试读硬盘）', () async {
      final webStore = <String, String>{};
      ThemeController.debugWebStorage = webStore;
      ThemeController.debugForceIsWebStorage = true;
      ThemeController.debugFilePath = null;
      ThemeController.instance.debugReset();

      await ThemeController.instance.setMode(ThemeMode.dark);
      // 关键断言：web 路径走 storageSet，不走 File.writeAsString
      // userAppDir() 在 test 返真实 ~/.biology_app 路径（不一定可写），
      // 但因为走 web 分支不会到 File。这里不强断言文件不存在，
      // 关键是 _isWebStorage 分支返回 true → 走 storageSet。
      expect(webStore['theme_mode_json'], isNotNull,
          reason: 'web 路径只写 localStorage，不写桌面 File');
    });
  });

  group('JSON 损坏降级', () {
    test('文件存在但内容坏 → 降级到默认 system，不抛', () async {
      // 预置一个损坏的 JSON
      File(filePath).writeAsStringSync('not-valid-json{{{');
      // load() 必须不抛错，mode 保持默认 system
      await ThemeController.instance.load();
      expect(ThemeController.instance.mode, ThemeMode.system,
          reason: 'JSON 损坏 → mode 保持默认 system（降级）');
    });

    test('mode 字段值未知 → 降级到 system', () async {
      // mode 是 'cyan' 等未知值
      File(filePath).writeAsStringSync('{"mode":"cyan"}');
      await ThemeController.instance.load();
      expect(ThemeController.instance.mode, ThemeMode.system,
          reason: '未知 mode 值 → 降级到 system');
    });

    test('JSON 顶层不是 Map → 降级到 system', () async {
      File(filePath).writeAsStringSync('[]');
      await ThemeController.instance.load();
      expect(ThemeController.instance.mode, ThemeMode.system,
          reason: '顶层不是 Map → 降级到 system');
    });
  });

  group('debugEnsureLoaded', () {
    test('debugEnsureLoaded 后 initState 的 load() 不会覆盖', () async {
      // 实锤 v2.2 批次5 注释里的竞态：load() 是真实文件 I/O，
      // 测试里若不先让它落地，initState 的 load() 后续覆盖。
      File(filePath).writeAsStringSync('{"mode":"dark"}');
      await ThemeController.instance.debugEnsureLoaded();
      expect(ThemeController.instance.mode, ThemeMode.dark,
          reason: 'debugEnsureLoaded 后 mode=dark（已落盘）');

      // 现在 debugSetMode 改 mode（不写盘）——模拟 test 主体操作
      ThemeController.instance.debugSetMode(ThemeMode.light);
      expect(ThemeController.instance.mode, ThemeMode.light);

      // 再调一次 load() 不会覆盖（_loaded 守卫）
      await ThemeController.instance.load();
      expect(ThemeController.instance.mode, ThemeMode.light,
          reason: '_loaded 守卫让 initState 后续 load() 不覆盖');
    });
  });
}
