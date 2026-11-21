// ai_tools_section.dart —— 设置页「AI 工具」分区（v2.24）。
//
// 三个开关决定 AI 在解题时能调用哪些工具。默认只开「联网搜索」——
// 本地遗传引擎（punnett_cross）是零风险工具，恒开、不设开关。
//
// Python / 命令行默认关闭：它们以当前用户权限执行模型生成的代码，
// 属于本软件里风险最高的一条路径，必须由用户显式打开，且每次执行
// 前还有一道人工确认（见 AiToolHost.confirm）。

import 'package:flutter/material.dart';

import '../../services/ai_tools.dart';
import '../../state/ai_tool_settings.dart';
import '../../theme.dart';

class AiToolsSection extends StatefulWidget {
  const AiToolsSection({super.key});

  @override
  State<AiToolsSection> createState() => _AiToolsSectionState();
}

class _AiToolsSectionState extends State<AiToolsSection> {
  AiToolSettings? _settings;
  String? _python;
  String? _shell;
  bool _probing = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final s = await AiToolSettingsStore.load();
    final py = await AiToolHost.detectPython();
    final sh = await AiToolHost.detectShell();
    if (!mounted) return;
    setState(() {
      _settings = s;
      _python = py;
      _shell = sh;
      _probing = false;
    });
  }

  Future<void> _set(AiToolSettings next) async {
    setState(() => _settings = next);
    await AiToolSettingsStore.save(next);
  }

  Widget _header(BuildContext context, String title, String? desc) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: AppText.sectionTitle),
        if (desc != null) ...[
          const SizedBox(height: 6),
          Text(desc, style: Theme.of(context).textTheme.bodySmall),
        ],
        const SizedBox(height: 14),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = _settings;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _header(
          context,
          'AI 工具',
          '开启后，AI 会在解题过程中自行决定调用哪个工具，而不是凭记忆心算。'
              '本地遗传引擎恒开：涉及基因型与比例的计算一律走它，避免模型算错。',
        ),
        if (_probing)
          // 不用 LinearProgressIndicator：无限动画会让 pumpAndSettle 永不收敛，
          // 设置页的既有 widget 测试会被拖到超时。
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text('正在检测本机解释器…',
                style: Theme.of(context).textTheme.bodySmall),
          )
        else if (s != null) ...[
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: s.web,
            onChanged: (v) => _set(s.copyWith(web: v)),
            title: const Text('联网搜索与网页抓取'),
            subtitle: const Text(
              '走 DeepSeek 官方 Search / Fetch 接口，用你已填的同一个 API Key。'
              '按成功请求计费（5 元 / 1000 次），搜索无结果不计费。',
            ),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: s.python,
            onChanged: _python == null ? null : (v) => _set(s.copyWith(python: v)),
            title: const Text('本机 Python'),
            subtitle: Text(
              _python == null
                  ? '未检测到 Python 解释器。装好 Python 并加入 PATH 后重启软件即可开启。'
                  : '解释器：$_python。每次执行前弹确认框展示完整代码，超时 10 秒强制终止。',
            ),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: s.shell,
            onChanged: _shell == null ? null : (v) => _set(s.copyWith(shell: v)),
            title: const Text('本机命令行'),
            subtitle: Text(
              _shell == null
                  ? '未检测到可用命令行。'
                  : '解释器：$_shell。以当前用户权限执行，工作目录为系统临时目录，超时 15 秒强制终止。',
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Python 与命令行能读写你账下的全部文件。只在你信任当前对话内容时开启；'
            '执行前请看清确认框里的代码再点继续。',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.lethal),
          ),
        ],
      ],
    );
  }
}
