// ready_app.dart —— 全 App widget 测试的已选角色启动夹具
//
// 只用于不关心首启流程的测试：用临时文件提供确定角色，避免首启模态框
// 遮挡 NavigationRail，也避免读写真实用户配置。首启与角色专项测试应
// 自行准备存储状态，不要使用本夹具。

import 'dart:convert';
import 'dart:io';

import 'package:biology/main.dart';
import 'package:biology/state/first_run_store.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> pumpReadyBiologyApp(
  WidgetTester tester, {
  UserRole role = UserRole.student,
}) async {
  final tmp = Directory.systemTemp.createTempSync('biology_ready_app_test');
  final file = File('${tmp.path}/first_run.json');
  // guide_done：本夹具只服务「不关心首启流程」的测试。缺这个键时
  // HomeShell 会在启动后自动开新手引导，罩层吸收点击 → 全量用例的打点
  // 全打空。需要验首启/自动引导的用例自己准备存储状态。
  file.writeAsStringSync(
      jsonEncode({'role': role.name, 'nudge': true, 'guide_done': true}));

  FirstRunStore.debugFilePath = file.path;
  FirstRunStore.debugWebStorage = null;
  FirstRunStore.debugForceIsWebStorage = false;
  FirstRunStore.instance.debugReset();

  addTearDown(() {
    FirstRunStore.debugFilePath = null;
    FirstRunStore.debugWebStorage = null;
    FirstRunStore.debugForceIsWebStorage = null;
    FirstRunStore.instance.debugReset();
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  await tester.pumpWidget(const BiologyApp());
  await tester.pumpAndSettle();
  expect(find.text('欢迎使用 Biology'), findsNothing);
}
