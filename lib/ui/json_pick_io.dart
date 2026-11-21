// json_pick_io.dart —— 桌面 / 安卓 .json 文件选择（dart:io 平台）。
//
// Windows：PowerShell WinForms OpenFileDialog（与 image_pick_io 同款
// PowerShell 进程 + OpenFileDialog 范式，仅 Filter 改为 *.json）。
// Android：MethodChannel biology/json_pick → MainActivity 系统文档选择器。
// 其余 IO 平台（Linux/macOS）返回 null。
//
// 为什么不复用 image_pick_io 的 PowerShell 段：image_pick 走 PickedImage
// 数据契约（bytes + name + extension），导入 JSON 只需要 text content
// 不用 bytes；硬塞 PickedImage 会让"读 .json 文件"语义变得奇怪（要
// PickedImage.bytes 然后 utf8.decode，多此一举）。新写 json_pick_io
// 保持数据契约最小（content + name），上层 _MistakeImportDialog 用
// 起来更直接。

import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

import 'json_pick_stub.dart';

export 'json_pick_stub.dart' show PickedJson;

const _channel = MethodChannel('biology/json_pick');

Future<PickedJson?> pickJsonFile() async {
  if (Platform.isWindows) return _pickWindows();
  if (Platform.isAndroid) return _pickAndroid();
  return null;
}

/// Windows：PowerShell 打开系统文件对话框，返回选中的 .json 路径，
/// 读文件全文返回。OpenFileDialog Filter 限 .json（防止用户选到
/// 别的格式导致 importJson 解析失败）。
Future<PickedJson?> _pickWindows() async {
  const script = 'Add-Type -AssemblyName System.Windows.Forms;'
      '[Console]::OutputEncoding=[Text.Encoding]::UTF8;'
      r'$d = New-Object System.Windows.Forms.OpenFileDialog;'
      r"$d.Filter = 'JSON 文件|*.json';"
      r"$d.Title = '选择错题导入 JSON';"
      r'if ($d.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK)'
      r'{ Write-Output $d.FileName }';
  try {
    final r = await Process.run(
      'powershell',
      ['-NoProfile', '-NonInteractive', '-STA', '-Command', script],
      stdoutEncoding: utf8,
    );
    final path = (r.stdout as String).trim();
    if (r.exitCode != 0 || path.isEmpty) return null;
    final f = File(path);
    if (!f.existsSync()) return null;
    final content = await f.readAsString();
    final name = path.split(RegExp(r'[\\/]')).last;
    return PickedJson(content, name);
  } catch (_) {
    return null;
  }
}

/// Android：系统文档选择器（SAF，无需存储权限）。
/// 读 .json 全文返回；其他类型文件由用户主动选时**仍可读取**
/// （系统文档选择器不限后缀），但错题本页 UI 上加扩展名过滤
/// 见 _MistakeImportDialog。
Future<PickedJson?> _pickAndroid() async {
  try {
    final r = await _channel
        .invokeMapMethod<String, dynamic>('pickJson');
    if (r == null) return null;
    final content = r['content']?.toString();
    final name = r['name']?.toString() ?? 'import.json';
    if (content == null) return null;
    return PickedJson(content, name);
  } catch (_) {
    return null;
  }
}
