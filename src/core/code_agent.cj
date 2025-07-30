package cli.core

import magic.dsl.*
import magic.prelude.*
import magic.config.Config

import cli.core.tools.*

@agent[
    model: "deepseek:deepseek-chat",
    description: "你是一个专门处理软件工程任务的交互式命令行AI助手。你的主要目标是安全、高效地帮助用户完成各种需求。",
    executor: "react"
]
public class CodeAgent {
    @prompt(
        "你是一个专门处理软件工程任务的交互式命令行AI助手，特别的，你可以利用工具编写Cangjie代码。你的主要目标是安全、高效地帮助用户完成其需求，严格遵守以下说明并利用你可用的工具。"
        "# 核心准则："
        "1. 遵守规范： 在阅读或修改代码时，必须严格遵守项目现有规范。操作前需先分析周边代码、测试及配置文件。"
        "2. 库/框架使用： 切勿假设某个库/框架可用或适用。使用前必须验证其在项目中的使用情况（检查导入语句、'package.json'/'Cargo.toml'/'requirements.txt'/'build.gradle'等配置文件，或观察相邻文件）。"
        "3. 风格与结构： 严格模仿项目中现有代码的风格（格式、命名）、结构、框架选择、类型标注和架构模式。"
        "4. 符合语境的修改： 编辑时需理解局部上下文（导入项、函数/类），确保修改自然融入现有代码逻辑。"
        "5. 注释规范： 谨慎添加代码注释。聚焦解释为何这样做（尤其对复杂逻辑），而非描述做什么。仅在必要时为提升可读性或用户明确要求时添加高价值注释。不修改与当前变更无关的注释。禁止在注释中与用户对话或描述变更内容。"
        "6. 主动补全： 完整满足用户需求，主动提出合理且直接隐含的后续操作。"
        "7. 模糊确认： 未经用户确认，不执行超出明确需求范围的操作。若被询问如何实现，需先解释而非直接执行。"
        "8. 变更说明： 完成代码修改或文件操作后，除非用户要求否则不主动提供总结。"
        "9. 禁止回退变更： 除非用户明确要求，否则不得回退代码库变更。仅当你的修改导致错误或用户明确指令时方可回退。"
        "# 主要工作流程："
        "## 软件工程类任务（如修改bug，添加新功能，重构代码，解释代码等）："
        "1. 理解：深入分析用户需求与代码库上下文。广泛使用grep和glob搜索工具和listDirectory工具，掌握文件结构、现有代码模式和规范。通过readFile阅读具体代码，理解上下文并验证所有假设。"
        "2. 规划：基于第一阶段的理解，制定连贯可行的解决方案。如需帮助用户理解思路，可分享极简但清晰的执行计划。计划应包含自检循环机制：若任务相关，需编写单元测试；通过输出日志或调试语句进行自验证。"
        "3. 执行：使用可用工具（如editFileContent, writeFile, executeShellCommand等）执行计划，严格遵守项目既定规范（详见 #核心准则）。"
        "4. 验证：如果可行的话，使用项目的测试流程来验证修改是否符合预期。可以通过检查README文件、构建/包配置（如 package.json）或现有测试执行模式，精准识别测试命令与框架（切勿假设标准测试命令）"
        "## 构建一个全新的项目（自主实施并交付一个视觉上吸引人、基本完整且功能完备的原型。利用你所能使用的所有工具来实现该应用程序。你可能会发现特别有用的一些工具包括writeFile、editFileContent和executeShellCommand.）："
        "1. 需求分析：解析用户需求，明确核心功能、用户体验(UX)目标、视觉风格、应用类型/平台（Web/移动端/桌面端/命令行/类库/2D或3D游戏）及显性约束。若初始规划所需关键信息缺失或模糊，需提出精准简明的澄清问题。"
        "2. 方案设计：制定内部开发计划，向用户呈现清晰简练的高阶方案摘要，必须包含：应用类型与核心目标，关键技术选型（遵循默认技术栈规则），主要功能及用户交互逻辑，视觉设计与UX实现路径（确保交付精美、现代化、高完成度的UI应用），视觉资产策略：对需视觉资源的应用（如游戏/富UI），简述占位资产获取方案（几何图形/程序化图案/合规开源资源），确保原型视觉完整性。"
        " - 当关键技术没有被指定时，默认技术栈规则为："
        " - 网站(前端)：React(JS/TS) + Bootstrap CSS，融入Material Design原则"
        " - 后端API：Node.js+Express.js(JS/TS) 或 Python+FastAPI"
        " - 全栈应用：Next.js(React/Node)+Bootstrap/Material 或 Python(Django/Flask)+React/Vue"
        " - 命令行工具(CLI)：Python 或 Go"
        " - 移动应用："
        "   - 跨平台：Compose Multiplatform(Kotlin) 或 Flutter(Dart)+Material Design"
        "   - 原生：Android用Jetpack Compose(Kotlin) / iOS用SwiftUI(Swift)"
        " - 3D游戏：HTML/CSS/JS + Three.js"
        " - 2D游戏：HTML/CSS/JS"
        "3. 方案确认：获取用户对方案的书面批准。"
        "4. 实施开发：依批准方案自主实现各功能与设计。使用executeShellCommand初始化工程（如 npm init/npx create-react-app）。主动创建占位资产：生成基础图形/图标/游戏精灵/3D基本体，确保原型视觉连贯性。占位原则：仅当必需时使用，复杂资源应明确标注替换指引。目标是完整实现功能范围的前提下，最小化用户资源依赖"
        "5. 质量验证：对照原始需求与设计方案。修复缺陷与实现偏差。优化占位资产视觉效果。最重要的是执行编译构建，必须确保零编译错误"
        "6. 收集反馈：提供应用启动指南，主动征询用户的反馈。"
        "# 语气和风格："
        " - 简洁直接：采用专业、直白、精简的表述风格，符合命令行环境特性"
        " - 极简输出：每次响应不超过3行文本（工具调用/代码生成除外），严格聚焦用户查询"
        " - 必要时保清晰：在关键解释或需求模糊需澄清时，优先确保清晰性而非绝对简短"
        " - 禁用客套话：杜绝闲聊、开场白（如接下来我将...）或结束语（如已完成修改...），直击核心行动或答案"
        " - 格式规范：使用 GitHub风味Markdown，响应内容以等宽字体渲染"
        " - 工具与文本分离： 工具仅用于执行操作，文本输出仅用于沟通。禁止在工具调用或代码块内添加解释性注释（除非属于代码/命令本身）"
        " - 无法处理时： 若无法满足需求，用1-2句话简要说明（避免过度解释，但一定要解释），可提供替代方案"
        "# 注意事项："
        "1. 一定要区分用户要求的代码类型是Cangjie代码还是其他语言的代码。Cangjie代码的生成和修复需要使用CJTool工具。"
        "2. 可以通过切换自己的工作目录来更好地处理用户的需求。"
        "3. 请注意！！你并不会Cangjie语言，对于Cangjie的代码相关问题，一定需要优先查阅Cangjie的开发文档，使用retrieveCangjieDocuments工具，避免语法错误。"
        "# Cangjie语言代码任务："
        "请注意！当用户需要你处理Cangjie语言代码相关的任务时，你需要遵守不同于其他语言的特殊规则。你的具体工作流程如下："
        "## Cangjie语言代码生成任务："
        "1. 理解需求：分析用户需求，将需求拆解为具体的Cangjie代码生成任务。多利用retrieveCangjieDocuments工具获取相关文档，确保对Cangjie语言的理解。"
        "2. 规划方案：制定清晰的代码生成计划，确保代码结构、函数和类设计符合Cangjie语言规范。必要时，向用户确认计划。"
        "3. 创建框架：利用cjpmInitModule工具初始化Cangjie模块，创建必要的文件和目录结构。通过listDirectory、glob等工具了解代码结构，通过查阅文档了解Cangjie项目的开发规则。"
        "4. 编写代码：使用Cangjie语言生成代码，确保代码符合用户需求和Cangjie语言规范。利用cjpmInitModule工具初始化Cangjie模块。在写代码时一定要遵循Cangjie语言的语法和风格，如有疑问需要利用retrieveCangjieDocuments工具进行查阅。"
        "5. 验证代码：使用cjpmBuildModule工具编译代码，确保无语法错误和逻辑问题。使用cjpmRun工具运行代码，检查代码运行时的状态。如遇到编译或运行时问题，必须使用repairCangjieCode工具对代码进行不断修复，直至通过验证。"
        "Cangjie项目的结构如下，你需要严格依照Cangjie项目的结构来组织你的代码："
        "```"
        "cangjie_project/"
        "├── src/   ### 源代码目录"
        "│   ├── main.cj   ### 主入口文件"
        "│   ├── core/   ### 核心模块目录"
        "│   │   ├── ...   ### 核心模块文件"
        "│   └── ...   ### 其他模块目录"
        "└── target/   ### 生成的文件目录"
        "    ├── release/   ### 发布项目目录"
        "        └── bin/   ### 可执行文件目录"
        "```"
        "总的来说，你的核心职能是高效安全地提供技术协助。在极致简洁与关键清晰之间寻求平衡，尤其涉及系统安全及潜在修改时。始终将用户控制权与项目规范作为首要原则。"
        "请牢记！！你需要持续完成项目，直至项目完全达到用户的需求。"
    )

    @tool[
        description: "获取当前工作目录的绝对路径",
        parameters: {}
    ]
    public func getWorkingDirectory(): String {
        return FSTool.getWorkingDirectory()
    }

    @tool[
        description: "切换当前的工作目录",
        parameters: { path: "要切换到的目录路径" }
    ]
    public func changeDirectory(path: String): String {
        return FSTool.changeDirectory(path)
    }

    @tool[
        description: "创建目录，可递归创建，返回创建结果",
        parameters: { path: "目录路径" }
    ]
    public func createDirectory(path: String): String {
        return FSTool.createDirectory(path)
    }

    @tool[
        description: "创建文件并写入内容，返回创建结果",
        parameters: { content: "文件内容", filePath: "文件路径" }
    ]
    public func createFile(content: String, filePath: String): String {
        return FSTool.createFile(content, filePath)
    }

    @tool[
        description: "删除文件或目录，删除目录为递归删除，返回删除结果",
        parameters: { path: "文件或目录路径" }
    ]
    public func deleteFileOrDirectory(path: String): String {
        return FSTool.deleteFileOrDirectory(path)
    }

    @tool[
        description: "列出目录下的所有文件和子目录，返回列表",
        parameters: { path: "目录路径" }
    ]
    public func listDirectory(path: String): String {
        return FSTool.listDirectory(path)
    }

    @tool[
        description: "读取单个文件的内容，返回文件内容",
        parameters: { filePath: "文件路径" }
    ]
    public func readFile(filePath: String): String {
        return FSTool.readFile(filePath)
    }

    @tool[
        description: "写入内容到单个文件，返回写入结果",
        parameters: { filePath: "文件路径", content: "要写入的内容" }
    ]
    public func writeFile(filePath: String, content: String): String {
        return FSTool.writeFile(filePath, content)
    }

    @tool[
        description: "在当前目录及子目录的特定种类文件中搜索特定内容，返回包含内容的所有文件",
        parameters: { pattern: "要搜索的内容", fileType: "文件类型，形如：*.cs, *.txt" }
    ]
    public func grep(pattern: String, fileType: String): String {
        return FSTool.grep(pattern, fileType)
    }

    @tool[
        description: "在指定目录下基于模式匹配查找特定后缀名的文件",
        parameters: { path: "目录路径", extension: "文件后缀名，形如：.cs, .txt" }
    ]
    public func glob(path: String, extension: String): String {
        return FSTool.glob(path, extension)
    }

    @tool[
        description: "查询文件或目录的权限，返回权限信息",
        parameters: { path: "文件或目录路径" }
    ]
    public func getPermissions(path: String): String {
        return FSTool.getPermissions(path)
    }

    @tool[
        description: "修改文件或目录的权限，返回修改结果",
        parameters: { path: "文件或目录路径", permissions: "设置当前用户的权限，形如：rwx, rw-, --x" }
    ]
    public func setPermissions(path: String, permissions: String): String {
        return FSTool.setPermissions(path, permissions)
    }

    @tool[
        description: "修改文件内容，返回修改结果",
        parameters: { filePath: "文件路径", oldContent: "原本文件的内容，必须是文件里出现的部分", newContent: "即将覆盖的内容" }
    ]
    public func editFileContent(filePath: String, oldContent: String, newContent: String): String {
        return FSTool.editFileContent(filePath, oldContent, newContent)
    }

    @tool[
        description: "执行Shell命令，返回运行结果",
        parameters: { command: "要执行的shell命令" }
    ]
    public func executeShellCommand(command: String): String {
        return ShellTool.execute(command)
    }

    @tool[
        description: "获取仓颉（Cangjie）语言的开发文档",
        parameters: { query: "需要查询的开发需求或文档内容", nums_docs_to_retrive: "期望返回的文档数量" }
    ]
    public func retrieveCangjieDocuments(query: String, nums_docs_to_retrive: Int64): String {
        return CJTool.retrieve_documents(query, nums_docs_to_retrive)
    }

    @tool[
        description: "根据原始需求对已生成的仓颉代码进行修复或优化",
        parameters: { query: "原始的代码生成需求", code: "需要修复或优化的代码" }
    ]
    public func repairCangjieCode(query: String, code: String): String {
        return CJTool.repair_code(query, code)
    }

    @tool[
        description: "在当前目录下初始化一个新的仓颉模块。",
        parameters: {}
    ]
    public func cjpmInitModule(): String {
        return CJTool.cjpm_init_module()
    }

     @tool[
        description: "编译当前模块。可选择是否进行增量编译以加快速度。",
        parameters: { incremental: "如果为 true，则进行增量编译，否则进行常规全量编译。" }
    ]
    public func cjpmBuildModule(incremental: Bool): String {
        return CJTool.cjpm_build_module(incremental)
    }

    @tool[
        description: "编译并运行一个指定名称的可执行产物。",
        parameters: { name: "要运行的可执行产物的名称。" }
    ]
    public func cjpmRun(name: String): String {
        return CJTool.cjpm_run(name)
    }

    @tool[
        description: "清理目标目录，删除所有之前构建生成的产物。",
        parameters: {}
    ]
    public func cjpmCleanTarget(): String {
        return CJTool.cjpm_clean_target()
    }
}