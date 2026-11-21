// guide_controller.dart —— 新手引导状态机（v2.2）
//
// 设计来源：调研 Flutter 社区主流引导方案（showcaseview / tutorial_coach_mark
// / Material feature_discovery）后的自绘实现，遵循社区共识：
//   · 步骤化一次一步，带步骤计数与「上一步/下一步/跳过」；
//   · GlobalKey 定位目标，半透明罩 + 挖孔高亮（evenOdd）；
//   · 图标按钮圆形挖孔、卡片/区域圆角矩形挖孔；
//   · 首启自动开启一次：HomeShell 在角色选完后按 FirstRunStore.guideDone
//     判断，同一会话只自动开一次；完成/跳过即落盘 guide_done=true，
//     之后启动不再自动弹——仍可在「设置 → 新手引导」手动重看，
//     手动重看不重置该标记。
//   · 文案精炼（每步 ≤3 行），只教关键路径。
//
// 职责边界：本控制器只管步骤状态机；页面切换由 HomeShell 监听驱动
// （HomeShell 是唯一导航事实源）。

import 'dart:async';

import 'package:flutter/material.dart';

import '../state/first_run_store.dart';
import 'guide_keys.dart';

/// 单步引导定义。
class GuideStep {
  /// 本步要切到的导航索引；-1 = 不切页（居中卡片步）。
  final int pageIndex;

  /// 高亮目标；null = 无目标（居中说明卡，如欢迎/完成步）。
  final GlobalKey? target;

  /// 圆形挖孔（图标按钮类目标）；false = 圆角矩形。
  final bool circle;

  final String title;
  final String body;

  const GuideStep({
    required this.pageIndex,
    this.target,
    this.circle = false,
    required this.title,
    required this.body,
  });
}

class GuideController extends ChangeNotifier {
  GuideController._();
  static final GuideController instance = GuideController._();

  bool active = false;
  int stepIndex = 0;

  /// 步骤表（按屏幕宽度动态）：宽屏高亮左侧 Rail，窄屏高亮底部导航栏。
  /// 导航索引事实源：lib/ui/app_navigation.dart（顺序即页面索引）。
  List<GuideStep> stepsFor({required bool wide}) => [
        const GuideStep(
          pageIndex: 0,
          title: '欢迎使用生物遗传计算平台',
          body: '接下来用 1 分钟带你认识每个板块和按键。\n'
              '任何一步都可以点「跳过」结束引导。',
        ),
        GuideStep(
          pageIndex: 0,
          target: wide ? GuideKeys.navRail : GuideKeys.navBar,
          title: '导航栏',
          body: wide
              // v2.19.60：13 页只映射 10 个数字键（1~9 → 前 9 页；0 → 第 10
              // 页 = 变异）——设置已移到导航末位，0 不再落设置页。
              // v2.19.25：文案不写"1~0 快速切换"这种全量承诺（老用户 P2-1）。
              // v2.19.34：指路点名对象（导航栏/「全部」按钮名），删方向词
              // （左侧/底部/最左侧）——排版一改方向词就会变成假话。
              ? '点导航栏任意一项切换页面；数字键 1~9 直达前 9 页、'
                  '0 到第 10 页（变异）。'
              : '点导航栏任意一项切换页面；左右滑动可见更多，'
                  '点「全部」可打开完整功能列表（含每项用途说明）。',
        ),
        GuideStep(
          pageIndex: 0,
          target: GuideKeys.dashboardGrid,
          title: '首页 · 功能地图',
          body: '每张卡片是一个功能入口：图标 + 名称 + 一句话用途，'
              '点卡片直达对应工具页。',
        ),
        // v3.8 遗传图谱扩到 5 步：它是老师最常用的入口，也是按钮最多、
        // 最容易被卡住的一页——原文案一步带过，老师看完仍不会「连线配对」
        // 与「多代推演」。顺序即老师真实动线：填亲本 → 读结果 → 指定配对
        // → 手势 → 多代。
        //
        // ⚠ 正文长度受引导气泡高度预算约束（guide_overlay.dart 把气泡顶边
        //   clamp 在 `屏高 - 200`，约 4 行 @320 宽）：单步正文不得超 110 汉字，
        //   多一行「下一步」就被顶出屏外、引导卡死。改文案前先数字数。
        GuideStep(
          pageIndex: 1,
          target: GuideKeys.pedigreeParents,
          title: '遗传图谱 · 填亲本',
          body: '这一页算两亲本杂交的子代。左栏填两个亲本的基因型，'
              '如 AaBb × AaBb：同一对基因用同一个字母，'
              '大写显性、小写隐性，多对基因连写。',
        ),
        GuideStep(
          pageIndex: 1,
          target: GuideKeys.pedigreeCalc,
          title: '遗传图谱 · 读结果',
          body: '点「计算」后，画布按代出节点：每个节点标基因型和比例，'
              '比例是理论概率（Aa × Aa 出 aa 为 1/4）。'
              '点任意节点可查看它的信息。',
        ),
        GuideStep(
          pageIndex: 1,
          target: GuideKeys.pedigreeWireBtn,
          title: '遗传图谱 · 指定配对',
          body: '不连线时，上一代全部雌雄按各自占比两两组合。要指定谁跟谁生：点「连线」进入连线模式，'
              '依次点父方节点、母方节点，最后点「计算」出子代；'
              '再点一次「连线」退出。',
        ),
        GuideStep(
          pageIndex: 1,
          // v3.11：提示条只在未出子代时渲染，首启引导时内容不保证 → 不挖孔，走居中说明卡。
          title: '遗传图谱 · 手势',
          body: '画布上：拖动或滚轮=平移，Ctrl+滚轮或双指=缩放，'
              '长按节点或右键=收线，右键或长按空白=加样本，'
              '缩放条 ⛶=适应视图。算完之后这串手势提示会收起。',
        ),
        GuideStep(
          pageIndex: 1,
          target: GuideKeys.pedigreeCalc,
          title: '遗传图谱 · 多代推演',
          body: '出子代后：底栏「计算下一代」往下推一代，「删除整代」整代清掉，'
              '「全部连线」恢复全部自动连线，「只看所选」只看选中的一支；'
              '左栏还能开伴性遗传、连锁互换、致死、多倍体。',
        ),
        GuideStep(
          pageIndex: 2,
          target: GuideKeys.crossSteps,
          title: '遗传计算器',
          // v2.22.0：套路卡撤下主导航独立入口 ⇒ 在这里交代它的真实
          // 可达路径（结果页按 K / 错题本按需打开），不再单列一步。
          //
          // ⚠ 文案长度受引导气泡高度预算约束（guide_overlay.dart 把气泡
          //   顶边 clamp 在 `屏高 - 200`，即正文最多约 4 行 @320 宽）：
          //   多一行 ⇒ 「下一步」被顶出屏外、引导卡死。故本段压成连续
          //   一段（不硬换行浪费行尾），原文一字未删，只在末尾追加
          //   套路卡的新入口说明——信息一条没丢，版面不越界。
          body: '顶部 7 个标签切换题型（9331/三对/单基因/伴性/方法对比/连锁/自由交配）。'
              '填好亲本点「计算」，结果平铺呈现；变式速查与易错提醒同页对照。'
              '结果页按 K 可看配套套路卡，错题本按需打开。',
        ),
        GuideStep(
          pageIndex: 3,
          target: GuideKeys.graphCanvas,
          title: '知识图谱',
          body: '19 个遗传学知识点的关系网。点任意节点看详情，'
              '详情里可一键跳转到该知识点对应的计算功能（顶部横幅可返回）。',
        ),
        GuideStep(
          pageIndex: 4,
          target: GuideKeys.curriculumChip,
          title: '课标体系',
          body: '22 条课标内容要求对照。条目下的绿色小方块是工具直达键，'
              '点它跳到对应功能页，点顶部「返回课标」横幅跳回。',
        ),
        GuideStep(
          pageIndex: 5,
          target: GuideKeys.molecularFirst,
          title: '分子遗传',
          body: '碱基互补、DNA 复制、转录翻译、配子种类——'
              '填数字点按钮，结果带推导过程。',
        ),
        GuideStep(
          pageIndex: 6,
          target: GuideKeys.evolutionFirst,
          title: '进化 · 基因频率',
          body: 'Hardy-Weinberg 平衡判定与逐代选择模拟，'
              '适合种群基因频率类题目。',
        ),
        GuideStep(
          pageIndex: 7,
          target: GuideKeys.ploidyFirst,
          title: '染色体倍性',
          body: '染色体组数判断（形态法/基因型法）、倍性判定、'
              '单倍体育种、四倍体配子比例。',
        ),
        // v2.19.25：补引导步——v2.19.24 插入主导航 index 8 后漏介绍，
        // 首启引导走完的学生不知道这个主打新页（三份找茬报告交叉命中）。
        // v2.22.0：套路卡从主导航撤下独立入口 ⇒ 本步（pageIndex 8）撤销，
        // 改为在 9331 步交代真实可达路径（结果页按 K / 错题本按需打开）。
        // 引导不再把套路卡作为独立目的地介绍，其余步骤一律不动。
        // v2.19.31 导航扩项：补变异/遗传病引导步（同 v2.19.25
        // 套路卡步的补法——进导航后漏介绍 = 首启学生不知道这两页）。
        const GuideStep(
          pageIndex: 9,
          title: '变异',
          body: '基因突变模拟（替换/插入/缺失 → 密码子影响）、染色体组数'
              '判断、结构变异速览、诱变因素与育种方法对照。',
        ),
        const GuideStep(
          pageIndex: 10,
          title: '人类遗传病',
          body: '遗传咨询风险计算（常染色体/伴 X 显隐）、系谱推断器'
              '（给系谱图判遗传方式，4 个经典金标准）、分类速查。',
        ),
        GuideStep(
          // v2.19.60：设置移到导航末位（原名次 9，本次落到 index 11）。
          pageIndex: 11,
          target: GuideKeys.settingsAi,
          title: '设置',
          body: '这里可以切换浅色/深色模式、配置 AI 接口通道，'
              '以及再次开启本引导。',
        ),
        GuideStep(
          pageIndex: -1, // 停在设置页；所有页面的壳层 FAB 均可见。
          target: GuideKeys.aiFab,
          circle: true,
          title: '问 AI',
          body: '任何页面都可以点右下角「问 AI」——'
              '助手会自动读取当前页面截图、输入和刚算出的结果，不用复述题目。',
        ),
        const GuideStep(
          // v2.19.60：关于移到导航末位（原名次 10，本次落到 index 12）。
          pageIndex: 12,
          title: '引导完成',
          body: '你已经认识了全部板块！\n'
              '想再看一遍：到「设置 → 新手引导」随时再次开启。',
        ),
      ];

  int stepCount({required bool wide}) => stepsFor(wide: wide).length;

  /// 开启引导：回到第一步从头开始（设置页手动重看 / 首启自动开启
  /// 都走这里；每次开启走完整一遍，完成/跳过后自动关闭）。
  void start() {
    stepIndex = 0;
    active = true;
    notifyListeners();
  }

  void next({required bool wide}) {
    final total = stepCount(wide: wide);
    if (stepIndex >= total - 1) {
      _finish();
      return;
    }
    stepIndex++;
    notifyListeners();
  }

  void back() {
    if (stepIndex > 0) {
      stepIndex--;
      notifyListeners();
    }
  }

  void skip() => _finish();

  void _finish() {
    active = false;
    stepIndex = 0;
    // 关闭即算看过：完成与跳过两条路都走这里，落盘后下次启动不再自动弹。
    // fire-and-forget——写盘失败只该让「下次不再自动弹」失效，绝不能把
    // 引导本身崩掉（markGuideDone 内部已 catch，这里再兜一层防未处理的
    // 异步异常在测试 / 桌面壳里冒出来）。
    unawaited(FirstRunStore.instance.markGuideDone().catchError((Object e) {
      debugPrint('[biology] markGuideDone failed: $e');
    }));
    notifyListeners();
  }

  /// 测试/调试钩子：直接跳到某步。
  void debugJumpTo(int i) {
    stepIndex = i;
    notifyListeners();
  }
}
