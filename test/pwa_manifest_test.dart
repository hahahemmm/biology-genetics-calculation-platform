// pwa_manifest_test.dart —— PWA manifest 字段验证
//
// v2.12 Wave 3-B P2-2：web/manifest.json 加 `lang: "zh-CN"`，让 PWA 安装
// 提示 / 启动画面 / 名称按中文 locale 渲染（之前默认 en，与 App 中
// 文文案错位）。本测试断言 manifest 解析后含 lang 字段 = zh-CN。
//
// v2.12 Wave 3-B P1 补：web/index.html 含 `prefers-color-scheme: dark`
// 的 theme-color meta（`#212420` 深色版 brand bg），避免深色浏览器
// chrome 把 PWA 标签染浅。
//
// 覆盖：
//   1. web/manifest.json 解析后含 `lang == "zh-CN"`
//   2. web/index.html 含 `prefers-color-scheme: dark` 的 theme-color

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('web/manifest.json 含 lang: zh-CN', () {
    final manifestFile = File('web/manifest.json');
    expect(manifestFile.existsSync(), isTrue,
        reason: 'web/manifest.json 应存在（项目根相对路径）');
    final raw = manifestFile.readAsStringSync();
    final j = jsonDecode(raw) as Map<String, dynamic>;
    expect(j['lang'], 'zh-CN',
        reason: 'v2.12 Wave 3-B P2-2 加的 lang 字段应为 zh-CN');
    // 主题色与 brand 一致（回归保护）
    expect(j['theme_color'], '#5C7265',
        reason: 'theme_color 应保持 brand 色 #5C7265');
  });

  test('web/index.html 含 prefers-color-scheme: dark 的 theme-color meta', () {
    final indexFile = File('web/index.html');
    expect(indexFile.existsSync(), isTrue,
        reason: 'web/index.html 应存在（项目根相对路径）');
    final raw = indexFile.readAsStringSync();
    // v2.12 Wave 3-B P1：深色模式主题色（与浅色 #5C7265 共存）——深色
    // 浏览器 chrome 优先匹配 media query，避免标签底色变浅。
    expect(raw, contains('media="(prefers-color-scheme: dark)"'),
        reason: '应含 prefers-color-scheme: dark 媒体查询');
    // 深色版 theme-color 必须等于 AppColors.canvasD（lib/theme.dart:95）：
    // 原值是 #232523（旧版 canvasD），v2.22 中性族改色后 web 侧没跟上，
    // 两边不一致会让深色浏览器 chrome 与页面底色差一档。
    expect(raw, contains('content="#212420"'),
        reason: '深色 theme-color 应为 #212420（= AppColors.canvasD）');
    // 浅色版 theme-color 仍保留：#5C7265（brand 色）
    expect(raw, contains('content="#5C7265"'),
        reason: '浅色 theme-color 仍保留 #5C7265（brand 色）');
  });
}
