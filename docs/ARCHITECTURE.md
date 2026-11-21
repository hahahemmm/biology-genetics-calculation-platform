# 生物遗传计算平台 — 架构说明

> 本文档说明项目的目录分层与各层职责，以及 UI 的设计约定。

## 1. 总体分层（三层）

```
┌───────────────────────────────────┐
│  lib/        Flutter UI 层          │  ← 界面、交互、主题、AI 侧栏
├───────────────────────────────────┤
│  lib/engine/ Dart 领域引擎（纯 Dart）│  ← 核心，与平台无关
├───────────────────────────────────┤
│  data/       结构化 JSON 题库/知识   │  ← 纯数据，随包打包（rootBundle）
└───────────────────────────────────┘
```

依赖方向：`lib` → `lib/engine` → `data`。UI 只调用引擎公开 API，引擎不反向依赖 UI。
第三方 UI 依赖（如 `flutter_math_fork`）只允许出现在 `lib/` 与 `test/`，
⛔ 不得被 `lib/engine/` 引入——引擎必须保持可用纯 Dart 单独编译与测试。

**这条约束由测试强制**：`test/layer_purity_test.dart` 扫描 `lib/engine/` 的每一条
import，一旦出现 `package:flutter/` 或 `../state|storage|pages|ui|services|charts|guide`
即红。新增引擎文件不需要额外登记，守卫会自动覆盖。

## 2. 引擎层（lib/engine/，纯 Dart）

数学底座：`fraction.dart`（精确分数，全程不浮点近似）。
规则中枢：`genetics_env.dart`（注册位点/致死规则/表型规则，变式真实推导）。

| 文件 | 职责 |
|------|------|
| `models.dart` | 领域模型：Gene / Trait / Genotype / Individual / Ratio |
| `cross_engine.dart` | 单/双基因杂交、测交回交、修饰模型（不完全显性/共显性/致死） |
| `kaoji_calc.dart` | 9331 计算器封装 + 变式比例 |
| `pedigree_engine.dart` | 多对基因多代衍射（概率卷积防 4ⁿ 爆炸）+ Punnett 方阵 |
| `pedigree.dart` | 系谱风险推断（AD/AR/XD/XR） |
| `sex_linked_engine.dart` | 伴 X 遗传：配子、按性别条件概率、4 个经典预设 |
| `linkage_engine.dart` | 连锁互换：AB/ab 记法 + 交换值 r（0–1/2），2–3 位点 |
| `method_compare.dart` | 分解法 vs 配子法并排（效率量化 4ⁿ vs n） |
| `random_mating_engine.dart` | 自由交配：配子库法 + 枚举法，逐代推演；致死「统一淘汰」（用 `crossUnnormalized`，逐组合归一化是经典错误） |
| `mistake_book.dart`（位于 `lib/state/`） | 错题本单例，`~/.biology_app/mistake_book.json` 持久化（此处仅为职责索引，实体不在引擎层） |
| `knowledge_graph.dart` | 19 节点知识图谱（先修/关联边） |
| `restriction_engine.dart` | 限制酶切：EcoRI / BamHI / HindIII 的识别位点、双链切点、线性片段与黏性末端；纯 Dart、一次一酶、教学简化模型 |
| `pcr_engine.dart` | 虚拟 PCR 与电泳：正反向引物唯一结合、扩增子、理想 2ⁿ、对数迁移位置；不评估真实引物设计、扩增效率或精确定量 |
| `population_growth_engine.dart` | 种群 J 型指数增长与连续 Logistic：逐代数量、K／K/2、绝对增长速率与相对增长率；不模拟随机波动、迁移或年龄结构 |
| `syllabus_loader.dart` / `kaodian_loader.dart` | data/ 两份 JSON 的容错解析；syllabus 含覆盖度关键词匹配 |
| `engine.dart` | 聚合导出（`ai_client` / `scan_bank_store` 已迁出，见下） |

**不在引擎层但历史曾挂在这里的三个文件**（2026-11 架构盘点后迁出，因为它们
需要 Flutter 或要反向依赖上层，与「引擎纯 Dart」冲突）：

| 文件 | 现位置 | 为什么不属于引擎 |
|------|--------|------------------|
| `ai_client.dart` | `lib/services/` | 网络客户端，用 `package:flutter/foundation`（kReleaseMode / visibleForTesting） |
| `scan_bank_store.dart` | `lib/state/` | 持久化，用 `package:flutter/foundation` + `storage/` |
| `mono_variant.dart` | `lib/state/` | 错题本变式内核，依赖 `state/mistake_book.dart` |

## 3. UI 层（lib/）

- `main.dart`：导航壳（桌面 NavigationRail / 移动 NavigationBar，数字键 1–9/0、Ctrl+A）
- `theme.dart`：设计 token 的 Flutter 实现（颜色/字号/间距的唯一来源）
- `state/app_state.dart`：全局上下文单例——各页计算时写入快照，AI 侧栏注入 system prompt
- `ui/assistant_panel.dart`：右侧 380px 滑入 AI 助手
- `ui/tex_formula.dart`：教学公式的真排版组件（`Math.tex`），见 3.1
- `services/bio_database_service.dart`：UniProt / RCSB PDB / PubMed 实时只读检索；离线精选与实时结果在知识库 UI 分区，网络错误不清空已展示内容
- `ui/module_surface.dart`：模块薄壳（Surface + 1px Border + 14px 圆角；有标题时为 19px Sage 图标 + 16px 分区标题 + 同色系 1px 发丝线）
- `pages/`：遗传图谱衍射 / 遗传计算器（7 Tab）/ 分子遗传（5 Tab，含基因工程）/ 知识图谱 / 设置 / 关于
- `pages/widgets/`：计算器各 Tab 组件
- `charts/`、`data/`、`guide/`、`models/`、`storage/`：图表绘制组件、内置数据（课标/套路卡/预设基因型/知识条目）、新手引导、知识数据模型、平台存储抽象

约定：业务逻辑一律下沉引擎层，pages 只做展示与交互。

### 3.1 TeX 公式排版（TexFormula）

教学页此前把公式写成「源码式」纯文本（如 `N_t = K/(1+(K/N0−1)e^(−r·t))`），
学生读到的是程序员视角。`ui/tex_formula.dart` 用 `Math.tex` 把它们渲染成
真正的人类可读排版（分式上下结构、上下标、希腊字母）。

**依赖**：`flutter_math_fork: ^0.7.4`（`pubspec.yaml`）。实际入口是
`package:flutter_math_fork/flutter_math.dart`——库名是 `flutter_math_fork`，
但**没有** `flutter_math_fork.dart` 这个文件，照抄常见写法会直接编译失败。
依赖版本只在 `pubspec.yaml` 维护，组件文件不得自行调整。

**边界（四条，改动前先读）**：

| 约束 | 原因 |
|------|------|
| 解析/构建失败必须回落普通人类可读文本（`onErrorFallback`） | 公式排版失败不许让教学页崩 |
| 默认用 `Math.tex`（非 `SelectableMath`） | SelectableMath 的光标/工具条在 `pumpAndSettle` 期间反复调度，测试会挂起 |
| 390 窄屏长分式只做**本行内**横向滚动 | 不整页溢出，也不用 FittedBox 缩到看不清 |
| 中文说明留在外层 `Text`，⛔ 不写进 TeX | 数学字体无 CJK 字形，`\text{中文}` 会渲染成方框 |

另两点：颜色默认取 `AppColors.ink`（token 实时派生，深浅/高对比主题自动正确）；
每个公式带中文 `semanticsLabel`（缺省回落 `fallback`），屏幕阅读器读到的是
「N 下标 t 等于 N 下标 0 乘 λ 的 t 次方」这类描述，不是源码。

**作用范围**：本轮只接入进化页第 6 页签「种群增长」的 J／S 通项、绝对/相对
增长速率与 J 型增量公式。TeX 排版**不改变任何科学公式的语义或取值**——
数量、速率、K／K/2 仍由 `engine/population_growth_engine.dart` 以纯数值算出，
组件只负责把符号画对。引擎侧不感知、也不依赖渲染层。

## 4. 数据层（data/）

两份 JSON（考纲 14 条 / 考点 36 条），全部联网核实并标注 source URL，
通过 `pubspec.yaml` 的 `assets: - data/` 随包打包。字段约定与来源清单见 `data/README.md`。

## 5. 本地持久化（用户目录）

| 文件 | 内容 |
|------|------|
| `~/.biology_app/ai_config.json` | AI BaseURL / Key / 模型名（设置页维护） |
| `~/.biology_app/mistake_book.json` | 错题本 |

## 6. 测试与构建

- `test/`：引擎数学、伴性、连锁、自由交配、方法对比、错题本、loader、widget、UI golden 截图等全量回归
- `integration_test/knowledge_experience_test.dart`：知识库实时检索的 Windows 实窗口巡检，
  **14 个场景 / 43 张截图**——加载骨架与上次结果归属、部分来源失败、全部失败与无匹配空态、
  CRISPR / PAM 精选卡、SpCas9 正反向切割、连接酶 / Taq / PCR 引物·循环·扩增辨析；
  桌面与 390 窄屏、深浅主题成对覆盖，全程用内存假数据，不访问网络。
  截图与全部偏好、历史写入被 Git 忽略的 `.experience/`，不得污染真实用户目录；
  场景数量与截图名以该文件为准，改场景需同步本节。
- 改导航/页面结构后 golden 需重生成：`flutter test --update-goldens`
- Windows 发布构建：`flutter build windows --release`（无独立构建脚本）

### 6.1 Windows 产物结构

`build\windows\x64\runner\<Config>\biology.exe` 只是原生启动壳（窗口、插件注册、
版本资源），Dart 代码不在 exe 里：

| 构建 | Dart 载荷路径 | 形态 |
|------|---------------|------|
| Debug | `build\windows\x64\runner\Debug\data\flutter_assets\kernel_blob.bin` | Kernel 快照（JIT） |
| Release | `build\windows\x64\runner\Release\data\app.so` | AOT 机器码 |

exe 属性里的「文件版本」在构建时由 `pubspec.yaml` 的 `version` 生成
`windows/flutter/ephemeral/generated_config.cmake` 的 `FLUTTER_VERSION*`，
经 `windows/flutter/CMakeLists.txt` 引入、`windows/runner/CMakeLists.txt` 以编译
定义传给 `windows/runner/Runner.rc`，最后写进 exe 资源。

`pubspec.yaml` 的 `version` 是构建版本单源（当前 `0.1.0+1`）；应用内标签由
`lib/app_version.dart` 的 `appVersionNumber` 维护，升版需一并同步。

## 7. 跨平台共用

引擎层纯 Dart（无 dart:io 特定逻辑、无 Flutter 依赖），同一份源码编译进
Windows（AOT）/ Android（AOT）/ Web（dart2js），两端题库与逻辑完全一致。

## 8. 扩展边界与后续候选

- **已实现虚拟 PCR / 电泳判读**：采用“纯 Dart 引擎 + 独立教学组件 + 定向测试”，第 5 页签内与限制酶切并列切换；明确完全互补、唯一结合和理想 2ⁿ，不把指数模型或条带位置伪装成真实实验保证。
- **已实现种群生态动力学对照**：进化页第 6 页签以纯 Dart 引擎比较 J 型与连续 Logistic，明确模型假设、K／K/2 和两类增长指标；不用于预测真实种群。该页签的公式由 UI 层 `TexFormula`（`flutter_math_fork`）排版，引擎只出数值、不引入任何渲染依赖。
- **公式排版不等于通用 LaTeX**：`TexFormula` 只渲染本仓库写死的教学公式字符串，不接收用户输入的任意 TeX，也不做公式求解或符号推导；排版失败一律回落普通文本。
- **不把完整生信或生态预测平台搬进应用**：序列比对、基因组浏览器、VCF、蛋白结构预测、真实实验设计与复杂生态模型均不在当前产品边界内。
- 调研依据：[教育部课程标准](http://www.moe.gov.cn/srcsite/A26/s8001/202006/t20200603_462199.html)、[Flutter 教学项目结构参考](https://github.com/Aristotheles/gen-code-v1)、[PCR Learning Lab](https://github.com/nour0810/pcr-learning-lab)。外部项目只用于理解教学拆解，不复制代码。
