// cross_pedigree_link.dart —— 9331 与遗传图谱之间的应用层链接
//
// 两个页面只依赖本服务和 ModuleFillBus，不互相 import。正向携带
// 当前题；反向只切回保活着的 9331 页面，不回填、不覆盖学生原输入。

import 'module_fill.dart';

/// 将当前杂交题送入遗传图谱。优先走「追加/空态计算」专用目标，
/// 未注册时回退到旧的 pedigree 填参契约。
bool openCrossInPedigree({
  required String p1,
  required String p2,
  String ratio = '',
  String sourceLabel = '9331 杂交计算',
}) {
  final params = <String, String>{
    'p1': p1,
    'p2': p2,
    'ratio': ratio,
    'sourceLabel': sourceLabel,
  };
  if (ModuleFillBus.fill(
    'pedigree_from_cross',
    params,
    sourceLabel: sourceLabel,
  )) {
    return true;
  }
  return ModuleFillBus.fill('pedigree', {
    'father': p1,
    'mother': p2,
  }, sourceLabel: sourceLabel);
}

/// 返回 9331 原页面，保留它已有的输入与结果。
///
/// 这里故意不调用 fill：页面已在 IndexedStack 中保活，直接导航即可；
/// HomeShell 的 navigator 会记录来源并提供反向返回横幅，左右导航不消失。
bool returnToCrossCalculator() {
  final target = ModuleFillBus.targetOf('cross_dihybrid');
  final navigator = ModuleFillBus.navigator;
  if (target == null || target.pageIndex < 0 || navigator == null) {
    return false;
  }
  navigator(target.pageIndex);
  return true;
}
