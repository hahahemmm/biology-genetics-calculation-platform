// image_pick_io.dart —— 桌面/安卓图片选择（dart:io 平台）。
//
// Windows：PowerShell WinForms OpenFileDialog（powershell.exe 5.1 默认 STA，
// 仍显式 -STA 保底；输出走 UTF8 防中文路径乱码）。
// Android：MethodChannel biology/image_pick → MainActivity 系统文档选择器。
// 其余 IO 平台（Linux/macOS）返回 null。

import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

import 'image_pick_stub.dart';

export 'image_pick_stub.dart' show PickedImage;

const _channel = MethodChannel('biology/image_pick');

Future<PickedImage?> pickImageFile() async {
  if (Platform.isWindows) return _pickWindows();
  if (Platform.isAndroid) return _pickAndroid();
  return null;
}

/// Windows：PowerShell 打开系统文件对话框，返回选中的图片路径。
Future<PickedImage?> _pickWindows() async {
  const script = 'Add-Type -AssemblyName System.Windows.Forms;'
      '[Console]::OutputEncoding=[Text.Encoding]::UTF8;'
      r'$d = New-Object System.Windows.Forms.OpenFileDialog;'
      r"$d.Filter = '图片文件|*.png;*.jpg;*.jpeg;*.webp;*.bmp;*.gif';"
      r"$d.Title = '选择题目图片';"
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
    final bytes = await f.readAsBytes();
    final name = path.split(RegExp(r'[\\/]')).last;
    final dot = name.lastIndexOf('.');
    return PickedImage(
        bytes, name, dot >= 0 ? name.substring(dot + 1).toLowerCase() : 'png');
  } catch (_) {
    return null;
  }
}

/// Android：系统文档选择器（SAF，无需存储权限）。
Future<PickedImage?> _pickAndroid() async {
  try {
    final r = await _channel
        .invokeMapMethod<String, dynamic>('pickImage');
    if (r == null) return null;
    final bytes = r['bytes'];
    if (bytes is! Uint8List) return null;
    final name = r['name']?.toString() ?? 'image.jpg';
    final dot = name.lastIndexOf('.');
    return PickedImage(
        bytes, name, dot >= 0 ? name.substring(dot + 1).toLowerCase() : 'jpg');
  } catch (_) {
    return null;
  }
}
