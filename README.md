# Cortex OS · DingTalk AI Persona

> Part of **Cortex OS** — Enterprise AI Operating System
> *The thinking center of your enterprise.*

这是 Cortex OS 的钉钉入口模块：每个员工在钉钉中拥有自己的 AI 分身，以本人身份和权限操作企业系统。

## 功能

- 📄 读取/搜索/创建钉钉文档
- 💬 以用户身份发消息给同事或群
- 📊 读取分析团队周报
- ✅ 查看和管理待办
- 📅 查询日程安排
- 📚 管理知识库

## 架构

```
用户 PC 本地运行
  ├── dws auth login（用户自己的钉钉身份）
  ├── HAI Gateway Token（用户自己的 AI 额度）
  └── python main.py（AI 分身 bot，Stream 模式）
```

每人独立运行，互不干扰，权限完全继承钉钉账号本身的权限。

## 安装

**Windows（PowerShell）：**
```powershell
irm https://raw.githubusercontent.com/YumingMa/dingtalk-ai-persona/main/install.ps1 -OutFile $env:TEMP\ai-setup.ps1; & $env:TEMP\ai-setup.ps1
```

**macOS / Linux：**
```bash
curl -fsSL https://raw.githubusercontent.com/YumingMa/dingtalk-ai-persona/main/install.sh | bash
```

安装脚本自动完成：Python → dws → 钉钉登录 → 创建机器人 → 配置 HAI Gateway → 启动。

## 手动安装

```bash
git clone https://git.appexnetworks.com.cn/maym/dingai.git
cd dingai
pip install -r requirements.txt
cp .env.example .env   # 填写配置
python main.py
```

## 配置

复制 `.env.example` 为 `.env` 并填写：

```
DINGTALK_APP_KEY=your_app_key
DINGTALK_APP_SECRET=your_app_secret
ANTHROPIC_API_KEY=your_hai_gateway_token
ANTHROPIC_BASE_URL=https://api.hai.network/unified-preview/openai
```

详细说明见 [USER_GUIDE.md](USER_GUIDE.md)。

## 安全

- 所有凭证存本地 `.env`，不上传
- 详见 [SECURITY.md](SECURITY.md)

## 开发

```bash
pip install -r requirements.txt
# 修改代码后直接 python main.py 测试
```

项目结构：

```
main.py        # 启动入口
bot.py         # 钉钉 Stream 消息处理
agent.py       # AI 编排主循环
dws_tools.py   # dws 工具定义（11个）
dws_runner.py  # 执行 dws 命令
lightchat.py   # HAI Gateway 调用
session.py     # 消息去重、会话队列、对话历史
config.py      # 配置加载
install.sh     # macOS/Linux 一键安装
install.ps1    # Windows 一键安装
```
