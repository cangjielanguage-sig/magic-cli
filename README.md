# Magic-CLI

基于 **Cangjie Agent DSL** 和 **Cangjie Magic** 构建的 AI 命令行助手

## ✨ 核心特性

- 🎯 **智能对话** - 交互式 CLI 界面，支持自然语言处理 Cangjie 编程任务
- 🔧 **代码工具链** - 集成 Cangjie 开发全套工具（初始化、编译、运行、调试）
- 📚 **文档检索** - 内置 RAG 系统，可查询 Cangjie 官方文档和代码示例
- 🗂️ **上下文管理** - 智能对话压缩，保持长期会话效率
- 💾 **对话持久化** - 支持保存和恢复对话会话，项目切换无缝衔接
- 📝 **用户记忆** - 通过 AGENTS.md 文件自定义项目规则和上下文
- ⚡ **自定义命令** - 支持用户定义 prompt 模板，固化常用工作流程
- 🔄 **模型容错** - 智能模型切换，主模型失败时自动使用备用模型，确保服务连续性
- 🚀 **一键构建** - 自动化项目构建和依赖管理
- 🔌 **MCP 集成** - 支持 Model Context Protocol，扩展外部工具和服务能力

## 🛠️ 技术栈

| 组件 | 技术 |
|------|------|
| 语言 | Cangjie (仓颉语言) |
| 依赖 | Cangjie stdx + Cangjie Magic |
| 模型 | 支持配置 LLM (默认远程 API) |
| 集成 | MCP (Model Context Protocol) 支持用户自定义配置 |

## 🏗️ 项目结构

```
magic-cli/
├── 📁 src/                 # 核心源码
│   ├── agent/             # AI 代理实现
│   ├── tools/             # 工具集
│   └── main.cj           # 程序入口
├── 📁 docs/               # 文档
├── 📁 benchmark/         # 性能测试
├── 📁 ffi/               # 外部接口
├── 📁 scripts/           # 构建脚本
├── 📄 cjpm.toml         # 项目配置
└── 📄 README.md         # 项目说明
```

## 🚀 快速开始

### 前置要求

1. **CangjieMagic 环境** - 参考 [CangjieMagic 安装指南](https://gitcode.com/Cangjie-TPC/CangjieMagic/blob/dev/docs/install.md#%E6%8E%A8%E8%8D%90recommended)
2. **Cangjie 编译器** - 确保已安装 Cangjie 1.0.0+

### 安装配置

1. **克隆项目**
   ```bash
   git clone https://gitcode.com/Cangjie-SIG/magic-cli
   cd magic-cli
   ```

2. **配置环境变量**

- 需要先手动设置`MAGIC_PATH`的环境变量，指向 Cangjie Magic 项目根目录：

   **Windows (PowerShell):**
   ```powershell
   # 临时设置（仅当前会话）
   $env:MAGIC_PATH = "C:\path\to\CangjieMagic"

   # 永久设置（推荐）
   [Environment]::SetEnvironmentVariable("MAGIC_PATH", "C:\path\to\CangjieMagic", "User")
   ```

   **Windows (CMD):**
   ```cmd
   # 临时设置（仅当前会话）
   set MAGIC_PATH=C:\path\to\CangjieMagic

   # 永久设置（需要管理员权限）
   setx MAGIC_PATH "C:\path\to\CangjieMagic"
   ```

   **macOS/Linux:**
   ```bash
   # 临时设置（仅当前会话）
   export MAGIC_PATH="/path/to/CangjieMagic"

   # 永久设置 - 添加到 ~/.bashrc 或 ~/.zshrc
   echo 'export MAGIC_PATH="/path/to/CangjieMagic"' >> ~/.bashrc
   source ~/.bashrc
   ```

- 参考项目根目录下 `.env.example` 创建 `.env` 文件设置必需的环境变量：
   ```env
   # LLM API 密钥配置...
   # Web Search API 密钥配置...
   ```

3. **启动应用**
- 直接在`magic-cli`目录下运行程序：
   ```bash
   cjpm run --name cli
   ```
- 使用`magic-cli`辅助开发其他项目工程：
  - macOS / Linux 使用下面脚本启动`magic-cli`:
   ```bash
   <path/to/magic-cli>/scripts/magic-cli.sh
   ```
  - Windows 启动`magic-cli`:
   ```bash
   cjpm run --target-dir <path/to/magic-cli>/target
   ```

4. **运行参数配置**
   Magic-CLI 支持通过 `--run-args` 传递运行参数来定制 Agent 行为：

   - **自动执行模式** - 无需用户授权即可执行工具命令：
     ```bash
     cjpm run --name cli --run-args "--auto"
     ```

   - **指定生成 Cangjie 代码** - 默认 Agent 生成通用语言代码，如需生成 Cangjie 代码需特别指定：
     ```bash
     cjpm run --name cli --run-args "--language cangjie"
     ```

   - **组合使用参数**：
     ```bash
     cjpm run --name cli --run-args "--auto --language cangjie"
     ```

5. **首次使用提示**
   - 程序启动后会自动创建 `.magic-cli/` 目录存储配置和历史
   - 输入 `/help` 查看所有可用命令
   - 可在项目根目录创建 `AGENTS.md` 文件来自定义 AI 行为规则

### 性能加速（可选推荐）

Magic-CLI 自动使用 [ripgrep](https://github.com/BurntSushi/ripgrep) 来显著提升代码搜索性能，支持自动回退到系统默认工具。

**快速安装 ripgrep：**

**Windows:**
```bash
# 使用 Chocolatey
choco install ripgrep

# 使用 Scoop
scoop install ripgrep

# 使用包含的安装脚本（推荐）
scripts/install-ripgrep.ps1
```

**macOS:**
```bash
# 使用 Homebrew
brew install ripgrep

# 使用包含的安装脚本
chmod +x scripts/install-ripgrep.sh && ./scripts/install-ripgrep.sh
```

**Linux:**
```bash
# Ubuntu/Debian
sudo apt install ripgrep

# Arch Linux
sudo pacman -S ripgrep

# Fedora/RHEL
sudo dnf install ripgrep

# 使用包含的安装脚本
chmod +x scripts/install-ripgrep.sh && ./scripts/install-ripgrep.sh
```

> 即使不安装 ripgrep，Magic-CLI 也能正常工作 - 会自动回退到系统的 grep 工具。

## 📋 命令系统

Magic-CLI 提供了丰富的内置命令来管理对话、配置和系统功能：
目前支持三种命令模式：
- `@` 命令，可以通过 `@` 单个或者多个文件，将该文件加入对话上下文，进行对话
- `!` 命令，可以通过输入`！` 命令将当前模式变为终端模式，可以直接在终端执行`shell`命令
- `/` 命令，具体功能介绍见下方

### 基础命令
- **`/help`** - 显示帮助信息和所有可用命令
- **`/exit`** - 退出程序
- **`/clear`** - 清除当前对话历史
- **`/compact`** - 压缩对话上下文，优化长期会话性能

### 对话管理
Magic-CLI 支持保存和恢复对话会话：

- **`/conversation`** - 列出所有保存的对话
- **`/conversation list`** - 同上，列出所有对话
- **`/conversation save <name>`** - 保存当前对话为指定名称
- **`/conversation resume <name>`** - 恢复指定名称的对话
- **`/conversation remove <name>`** - 删除指定的对话

**使用示例：**
```bash
🔮 Agent > /conversation save my-project-work
✅ Conversation saved as 'my-project-work'

🔮 Agent > /conversation resume my-project-work
✅ Conversation 'my-project-work' resumed successfully!

🔮 Agent > /conversation list
📚 Available Conversations:
  • my-project-work
  • last-conversation (auto-saved conversation)
```
### MCP 工具管理
- **`/mcp`** - 显示当前加载的所有 MCP 服务器和工具
- **`/mcp add <name> <command> [args...]`** - 添加新的 stdio MCP 服务器
- **`/mcp add-sse <name> <url>`** - 添加新的 SSE MCP 服务器
- **`/mcp remove <name>`** - 移除指定的 MCP 服务器
- **支持环境变量配置：**
  ```bash
  /mcp add myserver uvx server-name --env API_KEY=your_key ENV_VAR=value
  ```
- 支持手动编辑`.magic-cli\settings.json`来直接添加MCP Servers，例如：
  ```json
  {
    "mcpServers": {
      "zhipu-web-search-sse": {
          "url": "https://open.bigmodel.cn/api/mcp/web_search/sse?Authorization=<API KEY>"
      },
      "MiniMax": {
          "command": "uvx",
          "args": [
              "minimax-mcp"
          ],
          "env": {
              "MINIMAX_API_KEY": "<MINIMAX_API_KEY>",
              "MINIMAX_MCP_BASE_PATH": "<MINIMAX_MCP_BASE_PATH>",
              "MINIMAX_API_HOST": "https://api.minimaxi.com",
              "MINIMAX_API_RESOURCE_MODE": "local"
          }
      }
    }
  }
  ```

### 记忆管理
- **`/memory`** - 查看当前目录下 AGENTS.md 文件的内容

AGENTS.md 是用户自定义规则文件，可以包含项目相关的上下文、编码规范或特殊指令。AI 会在处理请求时参考这些规则。
该文件建议遵循 [agents.md 标准](https://agents.md/) 组织内容。

**使用示例：**
```bash
🔮 Agent > /memory
📝 Current AGENTS.md content:
## 项目规范
- 使用 4 空格缩进
- 函数命名使用 camelCase
- 注释使用中文
```

### 自定义 /cmd 命令
Magic-CLI 支持用户自定义 prompt 模板命令，实现常用工作流程的快速执行：

- **`/cmd`** 或 **`/cmd list`** - 列出所有可用的自定义命令
- **`/cmd help <name>`** - 显示指定命令的详细信息和用法
- **`/cmd reload`** - 重新加载命令配置（编辑配置文件后使用）
- **`/cmd:<name> [参数]`** - 执行指定的自定义命令

**配置方法：**
在 `.magic-cli/commands/` 目录下创建 JSON 文件：
```json
{
  "description": "生成规范的 git commit message",
  "prompt": "请基于当前的代码改动生成一个规范的 commit message。要求：$ARGS"
}
```

**使用示例：**
```bash
🔮 Agent > /cmd list
📋 Available custom commands:
  • commit - 生成规范的 git commit message
  • explain - 解释代码的功能和实现原理
  • refactor - 提供代码重构建议

🔮 Agent > /cmd:commit 修复用户登录bug
[AI 会基于 git diff 和用户要求生成 commit message]

🔮 Agent > /cmd help commit
📖 commit
Description: 生成规范的 git commit message
Usage: /cmd:commit [your arguments]
Prompt template: 请基于当前的代码改动生成一个规范的 commit message。要求：$ARGS
```

### 自定义 SubAgent
Magic-CLI 支持创建自定义的专用 AI 助手（SubAgent），每个 SubAgent 都有自己的系统提示、可用工具和参数说明。

#### 创建自定义 SubAgent

**目录结构：**
```
.magic-cli/
└── agents/
    └── my-agent/
        └── AGENT.md          # Agent 定义文件（必需）
        └── *.py, *.cj, etc.  # 辅助脚本（可选）
```

**AGENT.md 文件格式：**
```markdown
---
name: MyAgent
description: 我的专用助手描述
tools: fileRead,fileWrite,grepSearch,shellExecute
---

你是一个专业的代码分析助手。你的任务是...

# 工作流程

1. 首先读取输入文件（用户会提供文件路径）
2. 分析代码结构
3. 将结果写入输出文件（用户会提供输出路径）

# 注意事项

- 保持代码风格一致
- 添加必要的注释
```

**元数据字段说明：**
- `name`（必需）：Agent 名称，用于调用（如 `@MyAgent`）
- `description`（必需）：Agent 简短描述，显示在帮助信息中
- `tools`（可选）：逗号分隔的工具列表

**可用工具列表：**
| 工具名 | 功能 |
|--------|------|
| `listDirectory` | 列出目录内容 |
| `fileRead` | 读取文件内容 |
| `fileCreate` | 创建新文件 |
| `fileWrite` | 写入文件内容 |
| `fileEdit` | 编辑文件 |
| `shellExecute` | 执行 shell 命令 |
| `grepSearch` | 搜索文本内容 |
| `globSearch` | 通配符搜索文件 |

#### 使用 SubAgent

1. **指定 Agent 目录启动**
```bash
cjpm run --name cli --run-args "--subagent-dir .magic-cli/agents"
```

2. **交互式调用 Agent**
```bash
# 启动后，直接与 Agent 对话即可
@MyAgent 请分析 /path/to/input.txt 文件，将结果保存到 /path/to/output.md
```

3. **查看可用 Agent**
```bash
# 输入 @ 后按 Tab 键自动补全
@<Tab>
```

#### 高级特性

**递归文档引用**：Agent 可以引用其他文档文件：
```markdown
参考 `./advanced_guide.md` 获取更多细节
```
Agent 会自动使用 `loadReferenceFile` 工具读取引用的文件。

**多 Agent 目录**：
```bash
# 指定多个 Agent 目录
cjpm run --name cli --run-args "--subagent-dir .magic-cli/agents,/path/to/other/agents"
```

## 配置文件说明

| 文件 | 位置 | 说明 |
|------|------|------|
| `.env` | 项目根目录 | 环境变量配置（API 密钥等）|
| `AGENTS.md` | 项目根目录 | 用户自定义规则和上下文|
| `settings.json` | `.magic-cli/` | MCP 服务器配置 |
| `*.history` | `.magic-cli/conversation-history/` | 保存的对话记录 |

### 模型配置

Magic-CLI 支持配置主模型和备用模型来确保服务稳定性：

```cangjie
// src/core/config/cli_config.cj
public static var model: String = "ark:kimi-k2-250711"  // 主模型
public static var fallbackModels: Array<String> = [     // 备用模型列表
    "moonshot:kimi-k2-0905-preview",
    "zhipuai:glm-4.5"
]
public static var enableFallback: Bool = true           // 启用模型切换
public static var maxFallbackAttempts: Int64 = 3        // 最大重试次数
```

> ⚠️ **重要提醒**：请确保在 `.env` 文件中配置了所有使用模型对应的 API 密钥，否则模型切换可能无法正常工作。

## 🎯 使用示例

### 基本对话
```
🤖 > 帮我创建一个 Cangjie 项目，实现一个贪吃蛇游戏
✨ 正在为您创建项目...
📁 已创建新项目：cj_snake_game
```

### 代码生成
```
🤖 > 生成一个快速排序算法
✨ 生成代码：
```cangjie
func quickSort(arr: Array<Int64>): Array<Int64> {
    // 快速排序实现...
}
```

### 文档查询
```
🤖 > 如何定义泛型函数？
📚 查询文档：
泛型函数使用 `func<T>` 语法，例如：
```cangjie
func identity<T>(x: T): T {
    return x
}
```

### MCP 集成
```bash
🔮 Agent > /mcp add filesystem npx -y @modelcontextprotocol/server-filesystem ~/Documents
✅ Added stdio MCP server: filesystem

🔮 Agent > /mcp
📡 filesystem (Stdio) - 3 tools:
  • read_file
  • write_file
  • list_directory
```

## 🤝 贡献指南

欢迎贡献！请遵循以下步骤：

1. 🍴 Fork 项目
2. 🌿 创建功能分支 (`git checkout -b feature/AmazingFeature`)
3. 💾 提交更改 (`git commit -m 'Add some AmazingFeature'`)
4. 📤 推送分支 (`git push origin feature/AmazingFeature`)
5. 🔍 创建 Pull Request

## 📄 许可证

本项目采用 [MIT 许可证](LICENSE) 开源。

## 🔐 隐私与协议

- **隐私声明**：[PRIVACY.md](./PRIVACY.md)
- **用户协议**：[TERMS.md](./TERMS.md)

## 🙋‍♂️ 支持

- 📖 [项目文档](docs/)
- 🔌 [MCP 配置文档](docs/mcp.md)
- 🐛 [问题反馈](https://gitcode.com/ice_chester/magic-cli/issues)
- 💬 [讨论区](https://gitcode.com/ice_chester/magic-cli/discussions)
---

<div align="center">
  <p>Made with ❤️ by Cangjie 开发者社区</p>
  <p><i>让 Cangjie 开发更简单！</i></p>
</div>
