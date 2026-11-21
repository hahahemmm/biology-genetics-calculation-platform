// guide_keys.dart —— 新手引导高亮目标的 GlobalKey 注册表（v2.2）
//
// 各页面在代表性 widget 上挂载对应 key；GuideOverlay 经 key 取屏幕坐标
// 挖孔高亮。静态持有：IndexedStack 重建时 GlobalKey 可 reparent 到新
// widget 实例（同帧唯一即可），页面状态不丢。
import 'package:flutter/material.dart';

/// 引导高亮目标 key 表。挂 key 的 widget 必须真实存在于树中
 /// （offstage 页无 RenderObject——引导步骤会先切页再取坐标）。
class GuideKeys {
  GuideKeys._();

  static final navRail = GlobalKey(); // 桌面左侧导航 Rail
  static final navBar = GlobalKey(); // 移动端底部导航栏
  static final aiFab = GlobalKey(); // 「问 AI」悬浮按钮
  static final dashboardGrid = GlobalKey(); // 首页功能网格
  static final pedigreeCalc = GlobalKey(); // 遗传图谱底部条「计算」
  static final crossSteps = GlobalKey(); // 9331 步骤流程卡区
  static final graphCanvas = GlobalKey(); // 知识图谱画布
  static final curriculumChip = GlobalKey(); // 课标大概念区（chip 所在卡）
  static final molecularFirst = GlobalKey(); // 分子页首卡
  static final evolutionFirst = GlobalKey(); // 进化页首卡
  static final ploidyFirst = GlobalKey(); // 倍性页首卡
  static final settingsAi = GlobalKey(); // 设置页 AI 接口卡

  // ── v3.7 遗传图谱新手引导扩写（老师首用视角）──
  static final pedigreeParents = GlobalKey(); // 图谱左栏亲本输入区
  static final pedigreeHintBar = GlobalKey(); // 图谱画布底部提示条
  static final pedigreeWireBtn = GlobalKey(); // 图谱底栏「连线」按钮
}
