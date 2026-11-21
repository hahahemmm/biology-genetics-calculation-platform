# 参与贡献

## 提交前

```bash
flutter analyze     # 必须 0 error
flutter test        # 全量测试必须全绿
```

改动视觉相关内容时，只有在确认差异符合预期后才可
`flutter test --update-goldens`，并在 PR 中说明变化原因。

## 代码约定

- `lib/engine/` 必须是纯 Dart：不得 `import 'package:flutter/...'`，
  也不得反向依赖 `state/`、`storage/`、`pages/`、`ui/`。
  `test/layer_purity_test.dart` 会检查这一点。
- 概率计算一律走 `Fraction` 精确分数，不要引入浮点近似。
- 新增数据条目需标注来源。
- 不提交任何密钥、令牌或本机绝对路径。

## 提交信息

使用 `type: 摘要` 格式，type 取 `feat` / `fix` / `refactor` / `test` /
`docs` / `chore`。
