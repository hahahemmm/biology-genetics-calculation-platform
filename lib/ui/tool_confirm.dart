// tool_confirm.dart —— AI 要求执行本机代码时的人工确认（v2.24）。
//
// 为什么必须有：run_python / run_shell 会以当前用户权限执行**模型生成的
// 代码**。题的截图里可能藏着诱导性文字（提示注入），模型自己分不清
// 那是题干还是指令。所以每一次执行都停下来，把完整代码摊给用户看，
// 由人来点「继续」。
//
// 主操作是「拒绝执行」：课堂里多数人其实看不清那段代码，把放行做成实心
// 按钮等于鼓励盲点。拒绝只让模型拿到一条工具结果并自己绕路，代价很小。
//
// 拿不到 Navigator（例如启动早期、或 MaterialApp 尚未挂载）时一律
// 返回 false —— 拒绝执行永远比误执行安全。

import 'package:flutter/material.dart';

import '../theme.dart';
import 'app_navigator_key.dart';

/// 弹一次执行确认。返回 true = 用户同意执行。
Future<bool> confirmToolExecution(String title, String detail) async {
  final ctx = appNavigatorKey.currentContext;
  if (ctx == null) return false;
  final ok = await showDialog<bool>(
    context: ctx,
    // 点外面 / 按返回键都等于拒绝：看不清代码时，退出对话框必须比留在
    // 对话框里更容易，否则用户只能盲点一个按钮才能继续。
    barrierDismissible: true,
    builder: (dctx) => AlertDialog(
      title: Row(
        children: [
          Icon(Icons.warning_amber_rounded, size: 20, color: AppColors.lethal),
          const SizedBox(width: 8),
          Expanded(child: Text(title)),
        ],
      ),
      content: SizedBox(
        width: 560,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'AI 要求在你的电脑上执行下面这段代码。它会以你当前账号的权限运行，'
              '可以读写文件、访问网络。确认代码内容后再继续。',
              style: TextStyle(fontSize: 12),
            ),
            const SizedBox(height: 6),
            const Text(
              '看不清或拿不准就点拒绝——拒绝不会影响 AI 继续回答。',
              style: TextStyle(fontSize: 11),
            ),
            const SizedBox(height: 12),
            Container(
              constraints: const BoxConstraints(maxHeight: 320),
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.surfaceLow,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.border),
              ),
              child: SingleChildScrollView(
                child: SelectableText(
                  detail,
                  style: const TextStyle(
                    fontFamily: 'Consolas',
                    fontSize: 12,
                    height: 1.45,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
      // 拒绝做成实心主操作，放行降为文字按钮：视觉上先劝退，再谈执行。
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dctx).pop(true),
          child: const Text('我已看清，继续执行'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(dctx).pop(false),
          child: const Text('拒绝执行'),
        ),
      ],
    ),
  );
  return ok == true;
}
