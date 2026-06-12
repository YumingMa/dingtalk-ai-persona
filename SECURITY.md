# AI 分身 · Security Policy

## 敏感信息处理规范

### 绝不提交到代码库的内容

| 文件 / 内容 | 原因 |
|------------|------|
| `.env` | 包含真实 Token 和密钥 |
| `*.db` | 可能含用户数据 |
| `*_token*`, `*_secret*` | 凭证文件 |
| `__pycache__/` | 编译缓存 |

### Token 安全规范

1. **HAI Gateway Token**：每人独立，不共享，不发群，不写代码
2. **DingTalk AppKey/AppSecret**：存 `.env`，不硬编码
3. **dws auth token**：存用户本机，不上传服务器

### 如发现 Token 泄露

1. 立即在对应平台吊销该 Token
2. 在 `.env` 中生成新 Token
3. 通知管理员

### 报告安全问题

请通过内部渠道联系管理员，不要在 GitHub Issues 中公开。
