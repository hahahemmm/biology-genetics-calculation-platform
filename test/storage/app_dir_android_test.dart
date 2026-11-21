// app_dir_android_test.dart —— v2.13 R3 W1（P0：Android 全盘持久化失效）
//
// 验证 getFilesDir 链路：
//   1. channel 未注册（无 mock handler）→ ensureAppDirReady 不抛，缓存 null
//   2. getFilesDir 返回空 → 缓存保持 null，userAppDir() 返 null（不 fallback '.'）
//   3. mock 返回 /data/user/0/io.github.hahahemmm.biology/files → ensureAppDirReady
//      后 userAppDir() 返回 <filesDir>/.biology_app，且幂等（channel 只调一次）
//
// flutter_test 跑在 VM 上 Platform.isAndroid 恒 false，故用
// platform_storage_io.debugForceIsAndroid 注入强制走 Android 分支。

import 'dart:io';

import 'package:biology/storage/app_dir_android.dart';
import 'package:biology/storage/platform_storage_io.dart' as storage_io;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _channel = MethodChannel('biology/app_dir');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    storage_io.debugForceIsAndroid = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, null);
  });

  test('channel 未注册 → ensureAppDirReady 不抛，缓存保持 null',
      () async {
    storage_io.debugForceIsAndroid = true;

    await storage_io.ensureAppDirReady();

    expect(cachedAndroidFilesDir(), isNull);
    // 注意：此时不调 userAppDir()——缓存未就绪时它会触发
    // fire-and-forget 预取，迟到 future 会污染后续 mock 计数。
  });

  test('getFilesDir 返回空 → 缓存保持 null',
      () async {
    storage_io.debugForceIsAndroid = true;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, (call) async {
      expect(call.method, 'getFilesDir');
      return null;
    });

    await storage_io.ensureAppDirReady();

    expect(cachedAndroidFilesDir(), isNull);
  });

  test('mock getFilesDir → userAppDir 用它，且 channel 只调一次（幂等缓存）',
      () async {
    storage_io.debugForceIsAndroid = true;
    var calls = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, (call) async {
      expect(call.method, 'getFilesDir');
      calls++;
      return '/data/user/0/io.github.hahahemmm.biology/files';
    });

    await storage_io.ensureAppDirReady();
    expect(cachedAndroidFilesDir(), '/data/user/0/io.github.hahahemmm.biology/files');
    // 生产（Android）pathSeparator = '/';测试跑在 VM 上可能为 '\'，
    // 用 Platform.pathSeparator 拼期望值适配。
    final sep = Platform.pathSeparator;
    expect(storage_io.userAppDir(),
        '/data/user/0/io.github.hahahemmm.biology/files$sep.biology_app');

    // 二次 ensure + 三次 userAppDir：全部走缓存，channel 不再被调。
    await storage_io.ensureAppDirReady();
    expect(storage_io.userAppDir(),
        '/data/user/0/io.github.hahahemmm.biology/files$sep.biology_app');
    expect(storage_io.userAppDir(),
        '/data/user/0/io.github.hahahemmm.biology/files$sep.biology_app');
    expect(calls, 1);
  });
}