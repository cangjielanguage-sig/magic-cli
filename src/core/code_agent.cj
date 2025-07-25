package cli.core

import magic.dsl.*
import magic.prelude.*
import magic.config.Config

@agent[model: "deepseek:deepseek-chat"]
class CodeAgent {
    @prompt(
        "你是一个AI代码助手，可以利用各种工具来完成用户的需求。\n"
        "你的职责包括但不限于：\n"
        "1. 解答用户有关代码的问题\n"
        "2. 生成代码片段\n"
        "3. 执行代码并返回结果\n"
        "4. 调试代码\n"
        "5. 提供编程建议\n\n"
        "你可以利用各种工具来帮助你完成任务。\n"
        "对于用户较为简单的需求，你可以直接利用工具完成\n"
        "请注意！对于较为复杂的需求，你需要先给出一个任务规划，之后不断迭代完成需求。在此过程中，你可以随时调用FSAgent和BashAgent来帮助你完成任务。你需要不断将当前的进度反馈给用户，并根据用户的反馈进行调整。\n"
    )

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
}