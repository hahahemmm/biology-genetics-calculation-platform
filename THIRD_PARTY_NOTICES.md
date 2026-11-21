# 第三方许可声明

本项目以 MIT 许可证发布。以下第三方组件随源码或构建产物分发，其许可条款同样适用。

> 完整聚合声明以 `flutter build` 生成的 `NOTICES.Z`（打包在产物内）为准，
> 本文件只列直接依赖与本项目特别需要说明的部分。

## 直接依赖

| 组件 | 版本 | 许可 |
|------|------|------|
| Flutter SDK | 3.x | BSD-3-Clause |
| cupertino_icons | ^1.0.8 | MIT |
| image | ^4.9.2 | MIT（另含 jpgjs 等移植片段的版权行，见包内 `LICENSE-other.md`） |
| http | ^1.6.0 | BSD-3-Clause |
| web | ^1.0.0 | BSD-3-Clause |
| cryptography | ^2.7.0 | Apache-2.0 |
| flutter_math_fork | ^0.7.4 | Apache-2.0（代码）+ SIL OFL 1.1（随包字体） |
| url_launcher | ^6.3.3 | BSD-3-Clause |

`pubspec.lock` 锁定 67 个包：上表 8 个直接依赖、3 个开发/测试依赖、56 个传递依赖；
许可均为 MIT / BSD / Apache-2.0 等宽松许可，无 GPL 系。

## KaTeX 字体

`flutter_math_fork` 的 `pubspec.yaml` 在 `flutter: fonts:` 中声明了 20 个
`KaTeX_*.ttf`，因此**每次构建都会打进产物**，OFL 义务成立。

实测各 TTF 的 name 表（非推断）：

- name ID 13：`... with Reserved Font Name KaTeX_XXX. This Font Software is
  licensed under the SIL Open Font License, Version 1.1`
- name ID 0：`Copyright (c) 2009-2010 Design Science, Inc.
  Copyright (c) 2014-2018 Khan Academy`

**许可**：SIL Open Font License 1.1，全文见 [licenses/OFL-1.1.txt](licenses/OFL-1.1.txt)。

**关于保留字体名（RFN）**：原条款含义是——**修改后的字体版本不得继续使用
保留名 `KaTeX_*`**。本项目原样分发未修改的字体，因此照常使用该名称，
无需改名。若要分发修改版，必须改用不与 `KaTeX_*` 冲突的新名称。

**关于包内两个 LICENSE 文件**：`flutter_math_fork` 顶层 `LICENSE` 为
**Apache-2.0**（代码部分）；其子目录 `lib/katex_fonts/LICENSE` 标注为
**MIT**（Khan Academy 2018）。字体的实际许可以 TTF name 表中的 OFL 1.1 为准。

## Apache-2.0 组件

`cryptography` 与 `flutter_math_fork` 以 Apache License 2.0 授权，
全文见 [licenses/Apache-2.0.txt](licenses/Apache-2.0.txt)。两者均未随附
NOTICE 文件，因此无需传递额外声明。

## BSD-3-Clause 组件

Flutter SDK、`http`、`web`、`url_launcher` 均为 BSD-3-Clause。分发二进制时
须保留其版权行与免责声明，相关文本由构建产物中的 `NOTICES.Z` 汇总提供。

## 内容来源

考纲与考点条目依据教育部《普通高中生物学课程标准（2017 年版 2020 年修订）》
自行整理，不属于官方文本。生物数据库条目来自 UniProt、RCSB PDB、PubMed
的公开元数据。

## 致谢

本项目的遗传计算引擎在数据结构设计上参考了公开的
GeneticsCalculator 类项目的思路（`GeneticsEnv` 规则
注册模型、统一分母转整数比等），代码为本项目自行编写，未复制其源码。
