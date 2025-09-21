# Magic CLI 使用指南

Magic CLI 是一个基于仓颉语言开发的智能代码助手工具，支持多种编程语言的代码分析、生成和优化功能。

本指南以 Windows 操作系统环境为例进行介绍。

## 第一步：安装仓颉 SDK 环境

### 1.1 下载和安装

访问仓颉官方网站下载最新版本的 Cangjie SDK：
https://cangjie-lang.cn/docs?url=%2F1.0.0%2Fuser_manual%2Fsource_zh_cn%2Ffirst_understanding%2Finstall_Community.html

### 1.2 设置环境变量

**方法一：永久设置 CANGJIE_HOME（推荐）**

将仓颉安装目录添加到系统环境变量：
1. 右键"此电脑" → "属性" → "高级系统设置" → "环境变量"
2. 在"系统变量"中点击"新建"
3. 变量名：`CANGJIE_HOME`
4. 变量值：仓颉SDK安装路径（如：`C:\Program Files\Cangjie`）

**方法二：临时设置（单次会话有效）**

在 PowerShell 中执行：
```powershell
"path\to\cangjie\envsetup.ps1"
```

### 1.3 验证安装

打开命令提示符或PowerShell，输入：
```cmd
cjc --version
```
如果显示版本信息，说明安装成功。

## 第二步：下载和配置 Magic CLI

### 2.1 下载 Magic CLI

将 Magic CLI 项目放置到您希望安装的目录，例如：
```
C:\Tools\magic-cli
```

### 2.2 设置执行权限，将 magic-cli 添加到 PATH 环境变量

由于 Windows 安全策略，可能需要临时允许 PowerShell 脚本执行。

```powershell
Set-ExecutionPolicy Bypass -Scope CurrentUser
.\add-to-path.ps1
```

脚本会自动将当前目录添加到用户的 PATH 环境变量中。

## 第三步：安装依赖环境

### 3.1 安装 Node.js

由于 Cangjie Agent 功能需要 Node.js 运行环境，请从官网下载安装：
https://nodejs.org/

推荐安装 LTS 版本。安装完成后验证：
```cmd
node --version
npm --version
```
如果访问nodejs官方源失败，请设置npm镜像源：
```
 npm config set registry https://registry.npmmirror.com
```


## 第四步：设置 API 密钥

本例子中设置的 API KEY 以火山为例子，我们主要推荐的模型为火山部署的 Kimi-K2 模型，具体为`ark:kimi-k2-250711`。
此处可以根据[Cangjie Magic的文档](https://gitcode.com/Cangjie-TPC/CangjieMagic/blob/dev/docs/tutorial.md#%E6%A8%A1%E5%9E%8B%E9%85%8D%E7%BD%AE)自行配置模型和对应的 API KEY。

### 4.1 临时设置（当前会话有效）

**命令提示符：**
```cmd
set ARK_API_KEY=your_api_key_here
```

**PowerShell：**
```powershell
$env:ARK_API_KEY="your_api_key_here"
```

### 4.2 永久设置（推荐）

**命令提示符：**
```cmd
setx ARK_API_KEY your_api_key_here
```

**PowerShell：**
```powershell
[Environment]::SetEnvironmentVariable("ARK_API_KEY", "your_api_key_here", "User")
```

### 4.3 通过配置文件设置

您也可以在项目根目录创建 `.env` 文件，并配置多个API KEY,利用 magic-cli 的 model fallback 特性在一个模型访问出错的时候快速切换到另外一个模型，并继续您的任务（默认的后备模型提供商为月之暗面及智谱）：
```
ARK_API_KEY=your_api_key_here

MOONSHOT_API_KEY=your_api_key_here

ZHIPU_API_KEY=your_api_key_here
```

## 第五步：启动和使用

### 5.1 基本启动

重新打开命令提示符或PowerShell（以加载新的PATH），然后运行：
```cmd
magic-cli
```

### 5.2 命令行参数说明

Magic CLI 支持多种启动参数：

- `--auto`：启用自主模式，代理将自动处理任务
- `--language, -l`：指定编程语言模式
  - `cangjie`：仓颉语言专用模式（默认）
  - `general`：通用模式
- `--model <model>`：指定使用的AI模型
- `--fast-model <model>`：设置快速模型，启用混合模式
- `--temperature, -t <value>`：设置AI模型温度参数（默认：1.0）
- `--prompt, -p <prompt>`：非交互模式，直接执行指定提示
- `--log-level <level>`：设置日志级别（默认：DEBUG）
- `--help, -h`：显示帮助信息

### 5.3 使用示例

**启动仓颉专用模式：**
```cmd
magic-cli --language cangjie
```

**自主模式运行：**
```cmd
magic-cli --auto
```

**非交互模式执行任务：**
```cmd
magic-cli -p "帮我分析这个代码的性能问题" --auto
```

**设置特定模型和温度：**
```cmd
magic-cli --model openai:gpt-4 --temperature 0.7
```

## 故障排除

### 常见问题

1. **配置后执行magic-cli 无反应直接结束**：
    - 检查 是否设置好 cangjie 环境，如是否已执行 envsetup.ps1，当前启动窗口是否可以正确执行 cjc 命令。

2. **"无法识别 magic-cli 命令"**
   - 确认已正确运行 `add-to-path.ps1`
   - 重新打开命令提示符/PowerShell
   - 检查 PATH 环境变量是否包含 Magic CLI 目录

3. **"无法加载文件，因为在此系统上禁止运行脚本"**
   - 以管理员身份运行PowerShell
   - 执行：`Set-ExecutionPolicy Bypass -Scope CurrentUser`

4. **API 调用失败**
   - 检查 ARK_API_KEY 是否正确设置
   - 确认API密钥有效且有足够配额
   - 检查网络连接

### 获取帮助

如果遇到其他问题，可以：
1. 运行 `magic-cli --help` 查看完整参数说明
2. 查看`.magic-cli/`下的日志文件 `abc.log` 了解详细错误信息
3. 确保所有依赖环境正确安装

---

🎉 **安装完成！** Enjoy :(