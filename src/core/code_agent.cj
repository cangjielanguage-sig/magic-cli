package cli.core

import magic.dsl.*
import magic.prelude.*
import magic.config.Config

import cli.core.tools.*

@agent[
    model: "ark:ep-20250801112849-w4jk5",
    description: "你是一个专门处理软件工程任务的交互式命令行AI助手。你的主要目标是安全、高效地帮助用户完成各种需求。",
    executor: "tool-loop:1000"
]
public class CodeAgent {
    @prompt(
        """
        你是一个专门处理Cangjie语言开发任务的交互式命令行AI助手。你的主要目标是安全、高效地帮助用户完成各种需求。

        # 重要Cangjie相关工具

        - **retrieveCangjieDocuments**: 用于检索Cangjie文档的工具。
        - [VERY IMPORTANT] **repairCangjieCode**: 用于修复或优化Cangjie代码的工具。
        - **cjpmInitModule**: 用于初始化Cangjie模块的工具。
        - **cjpmBuildModule**: 用于编译Cangjie模块的工具
        - **cjpmRun**: 用于运行Cangjie模块的工具。
        - **cjpmCleanTarget**: 用于清理Cangjie模块的工具。

        这些工具是你处理Cangjie语言开发任务的核心，时刻牢记它们的功能和使用方法。

        # 工作流程

        ## Cangjie语言代码生成任务：
        1. 理解需求：分析用户需求，将需求拆解为具体的Cangjie代码生成任务。多利用retrieveCangjieDocuments工具获取相关文档，确保对Cangjie语言的理解。
        2. 规划方案：制定清晰的代码生成计划，确保代码结构、函数和类设计符合Cangjie语言规范。必要时，向用户确认计划。
        3. 创建框架：利用cjpmInitModule工具初始化Cangjie模块，创建必要的文件和目录结构。通过listDirectory、glob等工具了解代码结构，通过查阅文档retrieveCangjieDocuments了解Cangjie项目的开发规则。
        4. 编写代码：使用Cangjie语言生成代码，确保代码符合用户需求和Cangjie语言规范。利用cjpmInitModule工具初始化Cangjie模块。在写代码时一定要遵循Cangjie语言的语法和风格，如有疑问需要利用retrieveCangjieDocuments工具进行查阅。
        5. 验证代码：使用cjpmBuildModule工具编译代码，确保无语法错误和逻辑问题。使用cjpmRun工具运行代码，检查代码运行时的状态。如遇到编译或运行时问题，必须使用repairCangjieCode工具对代码进行不断修复，直至通过验证。

        ## Cangjie语言代码修复任务：
        1. 理解问题：分析用户提供的Cangjie代码和需求，明确需要修复或优化的部分。
        2. 使用repairCangjieCode工具：将用户提供的代码和修复需求传递给repairCangjieCode工具，获取修复后的代码，并将修复后的代码写入文件。
        3. 验证修复：使用cjpmBuildModule工具编译修复后的代码，确保无语法错误和逻辑问题。使用cjpmRun工具运行代码，检查代码运行时的状态。如遇到编译或运行时问题，必须使用repairCangjieCode工具对代码进行不断修复，直至通过验证。
        4. 提交修复：将修复后的代码提交给用户，确保满足其需求。

        ## Cangjie语言代码理解任务：
        1. 理解代码：分析用户提供的Cangjie代码，确保对代码逻辑和结构有清晰的理解。
        2. 使用retrieveCangjieDocuments工具：如果对Cangjie代码有疑问，使用retrieveCangjieDocuments工具获取相关文档，确保对Cangjie语言的理解。
        3. 提供解释：根据用户需求，提供对Cangjie代码的详细解释，确保用户理解代码逻辑和实现方式。
        4. 确认理解：在提供解释后，主动询问用户是否有进一步的疑问或需要更深入的解释。

        # 注意事项

        1. 请注意！！你并不会Cangjie语言，对于Cangjie的代码相关问题，一定需要优先查阅Cangjie的开发文档，使用retrieveCangjieDocuments工具，避免语法错误。
        2. 请注意！！请牢记！！对于编译或运行错误的Cangjie代码，必须使用repairCangjieCode工具进行修复。
        3. 你需要在Cangjie项目里的src文件夹下实现代码生成和修复任务，项目的main函数在init后已经创建好，在src/main.cj中。
        4. 始终谨记你的工作目录是${workingDirectory}。在执行文件操作时，始终使用绝对路径。禁止使用相对路径或当前工作目录。
        5. 请牢记！！你需要持续完成项目，直至项目完全达到用户的需求。

        """
    )

    let workingDirectory = FSTool.getWorkingDirectory()

    @tool[
        description: "创建目录，可递归创建，返回创建结果",
        parameters: { path: "目录路径，必须是绝对路径" }
    ]
    public func createDirectory(path: String): String {
        return FSTool.createDirectory(path)
    }

    @tool[
        description: "创建文件并写入内容，返回创建结果",
        parameters: { content: "文件内容", filePath: "文件路径，必须是绝对路径" }
    ]
    public func createFile(content: String, filePath: String): String {
        return FSTool.createFile(content, filePath)
    }

    @tool[
        description: "删除文件或目录，删除目录为递归删除，返回删除结果",
        parameters: { path: "文件或目录路径，必须是绝对路径" }
    ]
    public func deleteFileOrDirectory(path: String): String {
        return FSTool.deleteFileOrDirectory(path)
    }

    @tool[
        description: "列出目录下的所有文件和子目录，返回列表",
        parameters: { path: "目录路径，必须是绝对路径" }
    ]
    public func listDirectory(path: String): String {
        return FSTool.listDirectory(path)
    }

    @tool[
        description: "读取单个文件的内容，返回文件内容",
        parameters: { filePath: "文件路径，必须是绝对路径" }
    ]
    public func readFile(filePath: String): String {
        return FSTool.readFile(filePath)
    }

    @tool[
        description: "写入内容到单个文件，返回写入结果",
        parameters: { filePath: "文件路径，必须是绝对路径", content: "要写入的内容" }
    ]
    public func writeFile(filePath: String, content: String): String {
        return FSTool.writeFile(filePath, content)
    }

    @tool[
        description: "在指定目录及子目录的特定种类文件中搜索特定内容，返回包含内容的所有文件",
        parameters: { path: "目录路径，必须是绝对路径", pattern: "要搜索的内容", fileType: "文件类型，形如：*.cs, *.txt" }
    ]
    public func grep(path: String, pattern: String, fileType: String): String {
        return FSTool.grep(path, pattern, fileType)
    }

    @tool[
        description: "在指定目录下基于模式匹配查找特定后缀名的文件",
        parameters: { path: "目录路径，必须是绝对路径", extension: "文件后缀名，形如：.cs, .txt" }
    ]
    public func glob(path: String, extension: String): String {
        return FSTool.glob(path, extension)
    }

    @tool[
        description: "查询文件或目录的权限，返回权限信息",
        parameters: { path: "文件或目录路径，必须是绝对路径" }
    ]
    public func getPermissions(path: String): String {
        return FSTool.getPermissions(path)
    }

    @tool[
        description: "修改文件或目录的权限，返回修改结果",
        parameters: { path: "文件或目录路径，必须是绝对路径", permissions: "设置当前用户的权限，形如：rwx, rw-, --x" }
    ]
    public func setPermissions(path: String, permissions: String): String {
        return FSTool.setPermissions(path, permissions)
    }

    // @tool[
    //     description: "修改文件内容，返回修改结果",
    //     parameters: { filePath: "文件路径，必须是绝对路径", oldContent: "原本文件的内容，必须是文件里出现的部分", newContent: "即将覆盖的内容" }
    // ]
    // public func editFileContent(filePath: String, oldContent: String, newContent: String): String {
    //     return FSTool.editFileContent(filePath, oldContent, newContent)
    // }

    @tool[
        description: "在指定目录下执行Shell命令，返回运行结果",
        parameters: { path: "执行命令的目录路径，必须是绝对路径", command: "要执行的shell命令" }
    ]
    public func executeShellCommand(path:String, command: String): String {
        return ShellTool.execute(path, command)
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
        description: "在指定目录下编译单个Cangjie文件，生成可执行文件main",
        parameters: { path: "Cangjie文件对应目录路径，必须是绝对路径", name: "要编译的Cangjie文件名，例如test.cj" }
    ]
    public func cjCompiler(path: String, name: String): String {
        return CJTool.cj_compiler(path, name)
    }

    @tool[
        description: "在指定目录下初始化一个新的仓颉模块。",
        parameters: { path: "仓颉模块的路径，必须是绝对路径" }
    ]
    public func cjpmInitModule(path: String): String {
        return CJTool.cjpm_init_module(path)
    }

     @tool[
        description: "编译指定路径的Cangjie模块。可选择是否进行增量编译以加快速度。",
        parameters: { incremental: "如果为 true，则进行增量编译，否则进行常规全量编译。", path: "仓颉模块的路径，必须是绝对路径" }
    ]
    public func cjpmBuildModule(incremental: Bool, path: String): String {
        return CJTool.cjpm_build_module(incremental, path)
    }

    @tool[
        description: "编译并运行一个指定名称的可执行产物。",
        parameters: { name: "要运行的可执行产物的名称。", path: "仓颉模块的路径，必须是绝对路径" }
    ]
    public func cjpmRun(name: String, path: String): String {
        return CJTool.cjpm_run(name, path)
    }

    @tool[
        description: "清理目标目录，删除所有之前构建生成的产物。",
        parameters: {  path: "仓颉模块的路径，必须是绝对路径" }
    ]
    public func cjpmCleanTarget(path: String): String {
        return CJTool.cjpm_clean_target(path)
    }
}