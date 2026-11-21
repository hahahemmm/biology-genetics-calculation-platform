// ai_tools_test.dart —— AI 工具层的开关闸与本地引擎输出（v2.24）。
//
// 只测不需要联网/进程的部分：schema 门槛与 punnett_cross 的比例文本。
// Python / 命令行涉及子进程，走人工确认 + 超时，不在单测里跑。

import 'package:biology/services/ai_client.dart' show AiConfig;
import 'package:biology/services/ai_tools.dart';
import 'package:biology/state/ai_tool_settings.dart';
import 'package:biology/ui/ai_chat_controller.dart' show withToolFooter;
import 'package:flutter_test/flutter_test.dart';

AiConfig cfg({String key = 'sk-test'}) => AiConfig(
      provider: AiConfig.providerDeepSeek,
      baseUrl: 'https://api.deepseek.com',
      apiKey: key,
      model: 'deepseek-flash',
    );

List<String> names(List<Map<String, dynamic>> tools) => [
      for (final t in tools) (t['function'] as Map)['name'] as String,
    ];

void main() {
  test('全部开关关闭时只剩本地遗传引擎', () async {
    final host = AiToolHost(
      config: cfg(key: ''),
      settings: const AiToolSettings(python: false, shell: false, web: false),
    );
    final s = await host.schemas();
    expect(names(s), ['punnett_cross']);
  });

  test('开启联网且已配 Key 时出现搜索与抓取', () async {
    final host = AiToolHost(
      config: cfg(),
      settings: const AiToolSettings(python: false, shell: false, web: true),
    );
    expect(
      names(await host.schemas()),
      containsAll(['punnett_cross', 'web_search', 'fetch_url']),
    );
  });

  test('未配 Key 时联网工具不出现', () async {
    final host = AiToolHost(
      config: cfg(key: ''),
      settings: const AiToolSettings(web: true),
    );
    expect(names(await host.schemas()), ['punnett_cross']);
  });

  test('punnett_cross 走确定性引擎：Aa × Aa = 1:2:1 / 3:1', () async {
    final host = AiToolHost(
      config: cfg(key: ''),
      settings: const AiToolSettings(web: false),
    );
    final out = await host.call('punnett_cross', {'p1': 'Aa', 'p2': 'Aa'});
    expect(out, contains('1/4'));
    expect(out, contains('1/2'));
    expect(out, contains('3/4'));
    expect(out, isNot(contains('参数错误')));
  });

  test('参数缺失与未知工具都转成中文提示，不抛异常', () async {
    final host = AiToolHost(
      config: cfg(key: ''),
      settings: const AiToolSettings(web: false),
    );
    expect(await host.call('punnett_cross', const {}), contains('参数错误'));
    expect(await host.call('no_such_tool', const {}), contains('参数错误'));
  });

  // 回归：显性字母曾写死成 A/a，Bb × Bb 四种组合都不含 'a'，
  // 于是四份全被判成显性，输出「显性 4/4」。正确答案是 3:1。
  test('字母从输入推导：Bb × Bb = 3:1，不是 4/4', () async {
    final host = AiToolHost(
      config: cfg(key: ''),
      settings: const AiToolSettings(web: false),
    );
    final out = await host.call('punnett_cross', {'p1': 'Bb', 'p2': 'Bb'});
    expect(out, contains('3/4'));
    expect(out, contains('1/4'));
    expect(out, isNot(contains('显性 4/4')));
  });

  // 同一根因的双基因版本：D/E 位点曾全按 A/B 判定，四个表型全错。
  test('双基因 DdEe × DdEe = 9:3:3:1', () async {
    final host = AiToolHost(
      config: cfg(key: ''),
      settings: const AiToolSettings(web: false),
    );
    final out = await host.call(
      'punnett_cross',
      {'p1': 'DdEe', 'p2': 'DdEe', 'kind': 'dihybrid'},
    );
    expect(out, contains('显性显性 9/16'));
    expect(out, contains('显性隐性 3/16'));
    expect(out, contains('隐性显性 3/16'));
    expect(out, contains('隐性隐性 1/16'));
  });

  // 回归：改成从输入推导字母后，A/a 这类常规题的比例必须原样不变。
  test('Aa × Aa 回归：基因型 1:2:1，表型 3:1', () async {
    final host = AiToolHost(
      config: cfg(key: ''),
      settings: const AiToolSettings(web: false),
    );
    final out = await host.call('punnett_cross', {'p1': 'Aa', 'p2': 'Aa'});
    expect(out, contains('AA 1/4'));
    expect(out, contains('Aa 1/2'));
    expect(out, contains('aa 1/4'));
    expect(out, contains('显性 3/4'));
    expect(out, contains('隐性 1/4'));
  });

  // 全隐性纯合：推出来的显性字母是 B，不能因为「没有大写字母」就崩或判成显性。
  test('bb × bb 表型全隐性', () async {
    final host = AiToolHost(
      config: cfg(key: ''),
      settings: const AiToolSettings(web: false),
    );
    final out = await host.call('punnett_cross', {'p1': 'bb', 'p2': 'bb'});
    expect(out, contains('隐性 1/1'));
    expect(out, isNot(contains('显性 1/1')));
  });
  test('基因型格式不对时给出可纠正的提示，不崩也不瞎算', () async {
    final host = AiToolHost(
      config: cfg(key: ''),
      settings: const AiToolSettings(web: false),
    );
    // 双基因只给两位：原先会在 _dihybridGametes 里 RangeError。
    expect(
      await host.call('punnett_cross',
          {'p1': 'Dd', 'p2': 'Dd', 'kind': 'dihybrid'}),
      contains('参数错误'),
    );
    // 不同字母凑一对（引擎会当成两个不同等位基因）。
    expect(await host.call('punnett_cross', {'p1': 'AB', 'p2': 'AB'}),
        contains('参数错误'));
    // 单基因给了四位。
    expect(
      await host.call('punnett_cross', {'p1': 'AaBb', 'p2': 'AaBb'}),
      contains('参数错误'),
    );
  });

  // P2-1：Aa x Bb 每一对都合法，但两个亲本不是同一位点。旧校验只看
  // 配对，引擎照算出 3:1——学生拿到的是一份「看着像答案」的废结果。
  test('两个亲本不是同一位点时拒绝计算', () async {
    final host = AiToolHost(
      config: cfg(key: ''),
      settings: const AiToolSettings(web: false),
    );
    final out = await host.call('punnett_cross', {'p1': 'Aa', 'p2': 'Bb'});
    expect(out, contains('参数错误'));
    expect(out, contains('不是同一个基因'));
    // 双基因同样要整对比：AaBb x AaCc 的第二对位点对不上。
    expect(
      await host.call(
          'punnett_cross', {'p1': 'AaBb', 'p2': 'AaCc', 'kind': 'dihybrid'}),
      contains('参数错误'),
    );
    // 换个书写顺序不算错：BbAa 与 AaBb 是同一组位点。
    expect(
      await host.call(
          'punnett_cross', {'p1': 'AaBb', 'p2': 'BbAa', 'kind': 'dihybrid'}),
      isNot(contains('参数错误')),
    );
  });

  // P2-2：工具足迹在思维链里，折叠后学生看不出「3:1 是算的还是猜的」。
  test('工具脚注：有足迹才追加，且去重保序', () {
    // 没有足迹时正文必须逐字不变（既有 golden 依赖这一点）。
    expect(withToolFooter('3:1', null), '3:1');
    expect(withToolFooter('3:1', '普通思维链，没有工具段'), '3:1');
    final reasoning = '推导\n\n【工具调用】\n'
        'punnett_cross({"p1":"Aa"})\n'
        'punnett_cross({"p1":"Bb"})\n'
        'web_search({"query":"x"})';
    final out = withToolFooter('3:1', reasoning);
    expect(out, startsWith('3:1\n\n（本条回答使用了工具：'));
    expect(out, contains('punnett_cross、web_search'));
    expect('punnett_cross'.allMatches(out).length, 1);
  });
}
