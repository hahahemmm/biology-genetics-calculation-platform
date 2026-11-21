// flutter_test_config.dart —— 全仓测试基线：默认不自动弹新手引导
//
// 为什么需要：HomeShell 现在是「角色已选 + guideDone=false 就自动开新手
// 引导」（首启体验）。整壳测试（main_test / nav_* / mobile_smoke / 各
// v2.x 回归套件）都在模拟「用过一阵的老用户」：它们 setUp 里写一份
// first_run.json 或 setRole，然后 debugReset() —— guideDone 因此是 false，
// 引导罩层会把 App 盖住并吸收点击，tap 打空后报的是一堆跑偏的 hit-test
// 警告，看着像布局回归，实际是引导在挡路。
//
// 为什么不用 setUp 置位：各文件自己的 setUp（debugReset）会把标记清回
// false，顺序不可靠。这里用 FirstRunStore.debugSuppressAutoGuide 静态
// 开关，不受 debugReset 影响。要验「首启自动弹引导」的用例
// （main_first_run_test）在 setUp 里把它置 false 即可。
import 'dart:async';

import 'package:biology/state/first_run_store.dart';

Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  FirstRunStore.debugSuppressAutoGuide = true;
  await testMain();
}
