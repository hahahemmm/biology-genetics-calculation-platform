// disease_projection_overflow_test.dart —— 遗传病页投影溢出专项（R13 定位版）
//
// 【为什么单独一个文件】v213_r13_projection_test.dart 的「零溢出」
// 量测网把 13 页压在一个用例里，只记 `exceptionAsString().split('\n').first`
// ⇒ 报「[遗传病] A RenderFlex overflowed by 26 pixels on the right.」
// 却不给**哪一条 Row**。本文件把遗传病页单独拎出来、两档分辨率各跑一遍，
// 失败时把 FlutterErrorDetails 的完整诊断（含 RenderFlex 的 creator 链、
// 尺寸、父子约束）原样打出来，并断言零溢出——定位与回归同一张网。
//
// 【取样方式：泵真实 BiologyApp】与 v213 同源：课堂 ×1.75 是
// MaterialApp.builder 注入的 MediaQuery.textScaler，复刻 builder 只对
// 副本负责。
import 'dart:io';

import 'package:biology/services/ai_client.dart';
import 'package:biology/main.dart';
import 'package:biology/pages/settings_page.dart' show AiSettingsStore;
import 'package:biology/state/first_run_store.dart';
import 'package:biology/state/mistake_book.dart';
import 'package:biology/state/present_mode_controller.dart';
import 'package:biology/state/theme_controller.dart';
import 'package:biology/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'golden_fonts.dart';

/// 投影两档：1920×1080（教室主流）/ 1280×720（老投影）。
const Map<String, Size> kSizes = <String, Size>{
  '1920': Size(1920, 1080),
  '1280': Size(1280, 720),
};

void main() {
  late Directory tmp;
  late String firstRunFile;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('disease_projection');
    firstRunFile = '${tmp.path}${Platform.pathSeparator}first_run.json';
    File(firstRunFile).writeAsStringSync('{"role":"teacher"}');
    FirstRunStore.debugFilePath = firstRunFile;
    FirstRunStore.debugWebStorage = null;
    FirstRunStore.debugForceIsWebStorage = false;
    FirstRunStore.instance.debugReset();
    MistakeBook.debugFilePath = '${tmp.path}${Platform.pathSeparator}m.json';
    MistakeBook.debugTrashFilePath =
        '${tmp.path}${Platform.pathSeparator}m.trash.json';
    MistakeBook.instance.debugReset();
  });

  tearDown(() {
    PresentModeController.instance.debugSetEnabled(false);
    PresentModeController.instance.debugSetHighContrast(false);
    ThemeController.instance.debugSetMode(ThemeMode.system);
    ThemeController.instance.debugReset();
    FirstRunStore.debugFilePath = null;
    FirstRunStore.debugWebStorage = null;
    FirstRunStore.debugForceIsWebStorage = null;
    FirstRunStore.instance.debugReset();
    MistakeBook.debugFilePath = null;
    MistakeBook.debugTrashFilePath = null;
    MistakeBook.instance.debugReset();
    AiSettingsStore.debugConfig = null;
    AppColors.sync(Brightness.light);
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  for (final entry in kSizes.entries) {
    testWidgets('遗传病页 投影 ${entry.key} 课堂 ×1.75 零溢出', (tester) async {
      tester.view.physicalSize = entry.value;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await loadGoldenFonts();
      assertMaterialIconsLoaded();
      assertMonoLoaded();

      await tester.runAsync(() async {
        await ThemeController.instance.debugEnsureLoaded();
        await PresentModeController.instance.debugEnsureLoaded();
      });
      ThemeController.instance.debugSetMode(ThemeMode.light);
      AiSettingsStore.debugConfig = AiConfig.presetMinimax;
      PresentModeController.instance.debugSetHighContrast(false);
      PresentModeController.instance.debugSetEnabled(true);

      final failures = <String>[];
      final prevOnError = FlutterError.onError;
      FlutterError.onError = (d) {
        final s = d.exceptionAsString();
        if (s.contains('overflowed') || s.contains('OVERFLOW')) {
          // 完整诊断：首行摘要 + RenderFlex 的 creator 链 + 尺寸/约束，
          // 这才是「哪一条 Row」的答案（v213 只留首行，定位全靠猜）。
          failures.add('--- ${s.split('\n').first}\n'
              '${d.toString(minLevel: DiagnosticLevel.info)}');
        } else {
          prevOnError?.call(d);
        }
      };
      addTearDown(() => FlutterError.onError = prevOnError);

      await tester.pumpWidget(const BiologyApp());
      await tester.pumpAndSettle();

      // 走导航进遗传病页（pageIndex 11）：Rail 标签点击，与 v213 同路径。
      final railLabel = find
          .descendant(
            of: find.byType(NavigationRail),
            matching: find.text('遗传病'),
          )
          .first;
      await tester.ensureVisible(railLabel);
      await tester.pumpAndSettle();
      await tester.tap(railLabel);
      await tester.pumpAndSettle();
      // rootBundle 异步数据放行
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 200));
      });
      await tester.pumpAndSettle();

      FlutterError.onError = prevOnError;

      expect(
        find.text('人类遗传病'),
        findsWidgets,
        reason: '投影 ${entry.key}：必须真的停在遗传病页（否则零溢出是假绿）',
      );
      expect(failures, isEmpty,
          reason: '投影 ${entry.key} 遗传病页溢出：\n${failures.join('\n')}');
    });
  }
}
