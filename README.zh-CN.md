# Biology · 生物遗传计算平台

[English](README.md) | **简体中文**

把遗传计算的每一步摊开来看——错在哪一步，一眼可见。

一个面向高中生物的遗传计算与教学演示工具。它不满足于给出最终答案，而是把
配子、棋盘、概率、系谱的中间过程全部展开：同一道题目用分解法和配子法各算一遍，
两种结果并排呈现，让学生看到自己是从哪一步开始偏掉的。

当前版本：**0.1.0**（开源版首个发布）。

## 功能

| 模块 | 说明 |
|------|------|
| 遗传图谱 | 多对基因多代系谱树，逐代基因型与表型概率；支持连线配对、伴性、连锁互换、致死与多倍体 |
| 双基因 9331 | 9:3:3:1 及全部常见变式（9:7、9:3:4、15:1、1:4:6:4:1 等） |
| 三对基因 | 三对独立遗传的棋盘与比例推导 |
| 单基因杂交 | 分离定律、测交、回交、不完全显性、共显性、致死条件 |
| 伴性遗传 | 伴 X 遗传，按性别给出条件概率 |
| 方法对比 | 分解法与配子法并排，定位错误起点 |
| 连锁互换 | AB/ab 记法 + 交换值，亲本型与重组型配子 |
| 自由交配 | 配子库法与枚举法双解，逐代推演 |
| 基因工程 | 限制酶切（EcoRI / BamHI / HindIII）、虚拟 PCR 与电泳 |
| 种群增长 | J 型指数增长与连续 Logistic 对照 |
| 知识图谱 | 19 节点先修/关联图 + 考点速查 |
| 错题本 | 录入、错因归类、复习状态追踪 |
| 多账号档案 | 同一台电脑多个使用者，各自独立的错题本与设置，可设 4 位启动 PIN |
| 数据打包 | 整机数据导出为单个口令加密文件，可在本机原地恢复 |
| 问 AI | 携带当前页面与计算上下文的侧栏助手；可选联网搜索、抓网页、本机 Python 与命令行（逐次确认） |
| 新手引导 | 首次启动自动走一遍，可跳过；设置页可重看 |

## 版本与兼容性

**本项目不承诺向后兼容。**

在 1.0 之前，任何一次发布都可能包含破坏式、不可逆、不兼容的变更，包括但不限于：

- 本地数据文件的格式与目录结构；
- 配置项的名称、默认值与存放位置；
- 备份/导出包的格式（旧包可能无法被新版本导入）；
- 界面交互与快捷键。

升级前请自行导出备份，不要假定旧数据一定可被新版本读取。这是有意为之：
功能仍在快速演进，为每一版旧格式维护迁移层会拖慢每一次改动，也会让代码里
堆积大量只服务历史版本的死分支。

## 支持平台

| 平台 | 状态 |
|------|------|
| Windows | 主要目标平台，构建命令见下 |
| Web | 可构建并运行 |
| Android | 可构建 |
| macOS | 脚手架已就位，尚未做沙盒适配 |

## 快速开始

需要 Flutter **3.47.1** 或兼容版本（Dart SDK ^3.13.1）。

```bash
git clone https://github.com/hahahemmm/biology-genetics-calculation-platform.git
cd biology-genetics-calculation-platform
flutter pub get
flutter run -d windows     # 或 -d chrome / -d macos
```

## 构建

```bash
flutter build windows --release
flutter build web --release
flutter build apk --release
```

## AI 功能配置

仓库**不包含任何 API Key**。`dart_defines.example.json` 只是模板，字段全为空。

有两种配置方式：

1. 应用内「设置 → AI 接口」填写 BaseURL / Key / 模型名，密文本机加密保存；
2. 构建时注入：`--dart-define-from-file=dart_defines.local.json`（该文件已在
   `.gitignore` 中，切勿提交）。

支持任何 OpenAI 兼容的 `/chat/completions` 接口。不填 Key 时，除「问 AI」外的
全部计算功能可正常使用。

「AI 工具」中的本机 Python 与命令行默认关闭，开启后每次执行仍会弹确认框。

## 项目结构

```
lib/
  engine/     纯 Dart 领域引擎，零 Flutter 依赖
  services/   网络客户端、加密存储、备份与 AI 工具
  state/      全局状态与持久化
  pages/      页面与计算器组件
  ui/         通用 UI 组件与平台适配
  charts/     图表绘制
  data/       内置数据（课标、套路卡、预设基因型、知识条目）
  guide/      新手引导
  models/     知识数据模型
  storage/    平台存储抽象
data/         课标与考点 JSON（带来源标注）
docs/         架构说明
test/         单元 / Widget / golden 测试
```

架构细节与设计约定见 [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)。

分层约束：`lib → engine`，引擎不得反向依赖上层，也不得引入 Flutter。
这条约束由 `test/layer_purity_test.dart` 强制，改坏会直接红。

## 测试

```bash
flutter analyze
flutter test
flutter test --update-goldens    # 仅在确认视觉变更符合预期时使用
```

## 数据与来源

`data/` 下的考纲与考点条目均标注来源，依据教育部《普通高中生物学课程标准
（2017 年版 2020 年修订）》。生物数据库条目来自 UniProt / RCSB PDB / PubMed
的公开元数据。

本仓库不包含任何教科书正文或教材原文；课标条目的表述以课标文件本身为准。限制酶切、PCR、
种群增长等实验均为**教学简化模型**，用于讲清原理，不用于真实实验设计或
定量预测。

## 关于开发过程

本项目在 AI 辅助下完成：代码实现与重构、测试、审查与文档工作均有 AI 参与。
所有功能设计、内容取舍与最终验收由作者负责。

## 贡献

欢迎提 Issue 与 Pull Request，请先读 [CONTRIBUTING.md](CONTRIBUTING.md)。

- 更新记录见 [CHANGELOG.md](CHANGELOG.md)
- 安全问题的报告方式见 [SECURITY.md](SECURITY.md)（请勿开公开 issue）

## 持续集成

`.github/workflows/ci.yml` 在每次 push 与 PR 时执行 `flutter analyze` 与
`flutter test`。本地提 PR 前请先自行跑通这两条。

## 许可证

[MIT](LICENSE)。第三方依赖与字体的许可声明见
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。