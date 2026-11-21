# 安全策略

## 报告漏洞

请**不要**通过公开 issue 报告安全问题。

推荐渠道：GitHub 仓库的 **Security → Report a vulnerability**（私密 Advisory），
或直接联系仓库维护者。

请在报告中包含：

- 受影响的版本与平台
- 复现步骤或概念验证
- 影响评估（能读到什么、能改什么）

## 范围

本项目的威胁模型上限已知且明确：

- **AI 密钥**：仓库不含任何密钥。密钥由用户在应用内填写，桌面与移动端用
  AES-256-GCM + PBKDF2-HMAC-SHA256（10 万次迭代）加密后存于本机用户目录。
- **Web 端不加密**：浏览器里拿不到稳定的本机特征（hostname、`USERNAME`、
  `.machine.key` 均不可用），密钥与配置以明文存于浏览器的 localStorage。
  Web 端请只在可信设备上使用，并依靠操作系统账户隔离来划分使用者。
- **同机可解密**：加密用于防止明文落盘被随手读取，不防御同机同用户的攻击者。
  这一点在 `lib/services/local_secure_store.dart` 的注释里有明确说明。
- **错题本与本机数据**：默认存于 `%USERPROFILE%\.biology_app\`，未上传任何服务器。
- **网络请求**：仅 AI 接口与生物数据库（UniProt / RCSB PDB / PubMed）的只读查询。

## 不受理的报告

- 需要物理接触已解锁设备的攻击
- 用户自行把密钥写进 `dart_defines.local.json` 并提交到公开仓库
- 依赖包本身的漏洞（请报给上游，但欢迎在此告知以便升级）
