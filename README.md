# 🤖 Magic-CLI

基于 **CangjieMagic** 框架的 AI 命令行助手，专为 **Cangjie 语言** 开发设计！

## ✨ 核心特性

- 🎯 **智能对话** - 交互式 CLI 界面，支持自然语言处理 Cangjie 编程任务
- 🔧 **代码工具链** - 集成 Cangjie 开发全套工具（初始化、编译、运行、调试）
- 📚 **文档检索** - 内置 RAG 系统，可查询 Cangjie 官方文档和代码示例
- 🗂️ **上下文管理** - 智能对话压缩，保持长期会话效率
- 💾 **对话持久化** - 支持保存和恢复对话会话，项目切换无缝衔接
- 📝 **用户记忆** - 通过 MAGIC.md 文件自定义项目规则和上下文
- ⚡ **自定义命令** - 支持用户定义 prompt 模板，固化常用工作流程
- 🚀 **一键构建** - 自动化项目构建和依赖管理
- 🔌 **MCP 集成** - 支持 Model Context Protocol，扩展外部工具和服务能力

## 🛠️ 技术栈

| 组件 | 技术 |
|------|------|
| 语言 | **Cangjie** (仓颉语言) |
| 框架 | **CangjieMagic** (AI Agent 框架) |
| 依赖 | Cangjie stdx 标准库 + Magic 框架 |
| 模型 | 支持配置 LLM (默认远程 API) |
| 集成 | **MCP** (Model Context Protocol) 支持用户自定义配置 |

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
   git clone <repository-url>
   cd magic-cli
   ```

2. **配置环境变量**
   创建 `.env` 文件设置必需的环境变量：
   ```env
   MAGIC_PATH=/path/to/CangjieMagic
   # 其他 API 密钥配置...
   ```

3. **启动应用**
   ```bash
   cjpm run --name cli
   ```

4. **首次使用提示**
   - 程序启动后会自动创建 `.magic-cli/` 目录存储配置和历史
   - 输入 `/help` 查看所有可用命令
   - 可创建`.magic-cli/`目录下的 `MAGIC.md` 文件来自定义 AI 行为规则
   
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

## 🎯 使用示例

### 基本对话
```
🤖 Magic-CLI > 帮我创建一个 Cangjie 项目，实现一个贪吃蛇游戏
✨ 正在为您创建项目...
📁 已创建新项目：cj_snake_game
```

### 代码生成
```
🤖 Magic-CLI > 生成一个快速排序算法
✨ 生成代码：
```cangjie
func quickSort(arr: Array<Int64>): Array<Int64> {
    // 快速排序实现...
}
```

### 文档查询
```
🤖 Magic-CLI > 如何定义泛型函数？
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

## 📋 命令参考

Magic-CLI 提供了丰富的内置命令来管理对话、配置和系统功能：

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

### 用户记忆管理
- **`/memory`** - 查看当前目录下 MAGIC.md 文件的内容

MAGIC.md 是用户自定义规则文件，可以包含项目相关的上下文、编码规范或特殊指令。AI 会在处理请求时参考这些规则。

**使用示例：**
```bash
🔮 Agent > /memory
📝 Current MAGIC.md content:
## 项目规范
- 使用 4 空格缩进
- 函数命名使用 camelCase
- 注释使用中文
```

### 自定义命令
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

### MCP 工具管理
- **`/mcp`** - 显示当前加载的所有 MCP 服务器和工具
- **`/mcp add <name> <command> [args...]`** - 添加新的 stdio MCP 服务器
- **`/mcp add-sse <name> <url>`** - 添加新的 SSE MCP 服务器  
- **`/mcp remove <name>`** - 移除指定的 MCP 服务器

**环境变量配置：**
```bash
/mcp add myserver uvx server-name --env API_KEY=your_key ENV_VAR=value
```

## 🔧 开发命令

| 命令 | 说明 |
|------|------|
| `cjpm build` | 构建项目 |
| `cjpm run --name cli` | 运行应用 |
| `cjpm test` | 运行测试 |
| `cjpm clean` | 清理构建产物 |

## 📦 依赖管理

项目使用 `cjpm.toml` 管理依赖，支持多平台构建：
- 🐧 Linux (x86_64, aarch64)
- 🪟 Windows (x86_64)
- 🍎 macOS (aarch64)

## 🤝 贡献指南

欢迎贡献！请遵循以下步骤：

1. 🍴 Fork 项目
2. 🌿 创建功能分支 (`git checkout -b feature/AmazingFeature`)
3. 💾 提交更改 (`git commit -m 'Add some AmazingFeature'`)
4. 📤 推送分支 (`git push origin feature/AmazingFeature`)
5. 🔍 创建 Pull Request

## 📄 许可证

本项目采用 [MIT 许可证](LICENSE) 开源。

## 🙋‍♂️ 支持

- 📖 [项目文档](docs/)
- 🔌 [MCP 配置文档](docs/mcp.md)
- 🐛 [问题反馈](https://github.com/your-repo/issues)
- 💬 [讨论区](https://github.com/your-repo/discussions)

### 配置文件说明

| 文件 | 位置 | 说明 |
|------|------|------|
| `.env` | 项目根目录 | 环境变量配置（API 密钥等）|
| `MAGIC.md` | 项目根目录 | 用户自定义规则和上下文 |
| `settings.json` | `.magic-cli/` | MCP 服务器配置 |
| `*.history` | `.magic-cli/conversation-history/` | 保存的对话记录 |

### 常见问题

**Q: MCP 服务器加载失败怎么办？**
A: 程序会显示警告但继续运行。检查 `.magic-cli/settings.json` 配置和网络连接。

**Q: 对话历史丢失了？**
A: 程序会在退出时自动保存为 `last-conversation`，可通过 `/conversation resume last-conversation` 恢复。

**Q: 如何自定义 AI 行为？**
A: 在项目`.magic-cli/`目录创建 `MAGIC.md` 文件，写入项目相关的规则和上下文。

---

<div align="center">
  <p>Made with ❤️ by Cangjie 开发者社区</p>
  <p><i>让 Cangjie 开发更简单！</i></p>
</div>