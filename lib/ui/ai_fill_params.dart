// ai_fill_params.dart —— AI 读题填参（v2.4 功能 1）
//
// 场景：老师课件里的题，课堂上粘贴题干 → AI 提取遗传参数 → 一键填入
// 计算器开算。打通「老师讲真题课件」与「App 现场演算」之间的输入断点
//（白板软键盘敲基因型是最痛的环节）。
//
// 实现：对话框收题干 → AiClient（AiSettingsStore 持久化配置）→
// 让模型只回 JSON → 宽松解析（首个 {...} 块）→ onApply 回灌页面。

import 'dart:convert';

import 'package:flutter/material.dart';

import '../services/ai_client.dart';
import '../pages/settings_page.dart' show AiSettingsStore;
import '../theme.dart';

/// 读题填参对话框。[moduleHint] 告知 AI 目标模块（如「9331 双基因
/// 自由组合计算器，参数 p1/p2 为亲本基因型」）。
/// [onApply] 收到解析出的参数表（键值均为字符串）后回灌页面。
/// [extractor] 测试注入用：替换真实网络调用。
Future<void> showAiFillParams(
  BuildContext context, {
  required String moduleHint,
  required void Function(Map<String, String> params) onApply,
  Future<Map<String, String>?> Function(String text)? extractor,
}) {
  return showDialog<void>(
    context: context,
    builder: (ctx) => _AiFillDialog(
      moduleHint: moduleHint,
      onApply: onApply,
      extractor: extractor,
    ),
  );
}

/// 从模型回复中宽松提取首个 JSON 对象的参数表；失败返回 null。
Map<String, String>? parseParamsFromReply(String reply) {
  final start = reply.indexOf('{');
  final end = reply.lastIndexOf('}');
  if (start < 0 || end <= start) return null;
  try {
    final obj = jsonDecode(reply.substring(start, end + 1));
    if (obj is! Map) return null;
    return obj.map((k, v) => MapEntry('$k', '$v'));
  } catch (_) {
    return null;
  }
}

/// 真实提取：调 AI（只回 JSON）。
Future<Map<String, String>?> extractParamsWithAi(
    String text, String moduleHint) async {
  final config = await AiSettingsStore.load();
  final client = AiClient(config);
  final r = await client.ask('从下面的高中生物遗传题题干中提取计算参数。\n'
      '目标模块：$moduleHint\n'
      '要求：只输出一个 JSON 对象，键是参数名、值是参数值字符串，'
      '不要输出任何其他文字。无法确定时对应值填空字符串。\n'
      '题干：$text');
  if (!r.ok) return null;
  return parseParamsFromReply(r.content);
}

class _AiFillDialog extends StatefulWidget {
  final String moduleHint;
  final void Function(Map<String, String>) onApply;
  final Future<Map<String, String>?> Function(String text)? extractor;

  const _AiFillDialog({
    required this.moduleHint,
    required this.onApply,
    this.extractor,
  });

  @override
  State<_AiFillDialog> createState() => _AiFillDialogState();
}

class _AiFillDialogState extends State<_AiFillDialog> {
  final _ctrl = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _run() async {
    final text = _ctrl.text.trim();
    if (text.isEmpty) {
      setState(() => _error = '请先粘贴题干');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final extract =
        widget.extractor ?? ((t) => extractParamsWithAi(t, widget.moduleHint));
    final params = await extract(text);
    if (!mounted) return;
    if (params == null || params.values.every((v) => v.trim().isEmpty)) {
      setState(() {
        _busy = false;
        _error = '未能从题干提取参数（检查网络/题干是否含基因型信息）';
      });
      return;
    }
    widget.onApply(params);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('AI 读题填参'),
      content: SizedBox(
        width: 480,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('粘贴题目原文（从课件/PDF 复制），AI 提取参数并填入本页。',
                style: AppText.caption.copyWith(color: AppColors.graphite)),
            const SizedBox(height: 10),
            TextField(
              controller: _ctrl,
              maxLines: 6,
              decoration: const InputDecoration(
                hintText: '如：豌豆的高茎(D)对矮茎(d)为显性……亲本基因型为 Dd 和 dd……',
                border: OutlineInputBorder(),
              ),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(_error!,
                    style: AppText.caption.copyWith(color: AppColors.lethal)),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton.icon(
          onPressed: _busy ? null : _run,
          icon: _busy
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.auto_fix_high, size: 18),
          label: Text(_busy ? '提取中…' : '提取并填入'),
        ),
      ],
    );
  }
}
