package cli.core.tools

import std.fs.*
import std.process.*
import std.io.*
import std.env.*
import std.posix.*
import std.collection.*

import magic.dsl.*
import magic.prelude.*

import cli.utils.*

@toolset
public class FSTool {
    public static func getWorkingDirectory(): String {
        return canonicalize(".").toString()
    }

    public static func changeDirectory(path: String): String {
        if (!Path(path).isAbsolute()) {
            return "目录路径必须是绝对路径"
        }

        try {
            let exitCode = chdir(path)
            if (exitCode == 0) {
                return "已切换到目录：${path}"
            } else {
                return "切换目录失败，错误代码：${exitCode}"
            }
        } catch (e: IllegalArgumentException) {
            return "路径为空或包含非法字符"
        } catch (e: Exception) {
            return "切换目录失败：${e}"
        }
    }

    @tool[
        description: "创建目录，可递归创建，返回创建结果",
        parameters: { path: "目录路径，必须是绝对路径" }
    ]
    public func createDirectory(path: String): String {
        if (!Path(path).isAbsolute()) {
            return "目录路径必须是绝对路径"
        }

        let message = path
        let (confirmation, userInput) = ConfirmTool.confirm("Create Directory", message)
        if (!confirmation) {
            return "用户取消执行该操作，用户意见反馈：${userInput}"
        }

        try {
            Directory.create(path, recursive: true)
            return "目录 ${path} 创建成功！"
        } catch (e: FSException) {
            return "目录已存在"
        } catch (e: IllegalArgumentException) {
            return "目录为空、目录为当前目录、目录为根目录或目录中存在空字符"
        } catch (e: Exception) {
            return "创建目录失败：${e}"
        }
    }

    @tool[
        description: "创建文件并写入内容，返回创建结果",
        parameters: { content: "文件内容", filePath: "文件路径，必须是绝对路径" }
    ]
    public func createFile(content: String, filePath: String): String {
        if (!Path(filePath).isAbsolute()) {
            return "文件路径必须是绝对路径"
        }

        let message = filePath + "\n" + content
        let (confirmation, userInput) = ConfirmTool.confirm("Create File", message)
        if (!confirmation) {
            return "用户取消执行该操作，用户意见反馈：${userInput}"
        }

        try {
            let file = File(filePath, Write)
            file.write(content.toArray())
            file.close()
            return "文件 ${filePath} 创建成功！"
        } catch (e: Exception) {
            return "创建文件失败：${e}"
        }
    }

    @tool[
        description: "删除文件或目录，删除目录为递归删除，返回删除结果",
        parameters: { path: "文件或目录路径，必须是绝对路径" }
    ]
    public func deleteFileOrDirectory(path: String): String {
        if (!Path(path).isAbsolute()) {
            return "文件或目录路径必须是绝对路径"
        }

        let message = path
        let (confirmation, userInput) = ConfirmTool.confirm("Delete File or Directory", message)
        if (!confirmation) {
            return "用户取消执行该操作，用户意见反馈：${userInput}"
        }

        try {
            remove(path, recursive: true)
            return "文件或目录 ${path} 删除成功！"
        } catch (e: FSException) {
            return "指定目录不存在或删除失败"
        } catch (e: IllegalArgumentException) {
            return "路径为空或包含字符串结束符"
        } catch (e: Exception) {
            return "删除文件或目录失败：${e}"
        }
    }

    @tool[
        description: "列出目录下的所有文件和子目录，返回列表",
        parameters: { path: "目录路径，必须是绝对路径" }
    ]
    public func listDirectory(path: String): String {
        if (!Path(path).isAbsolute()) {
            return "目录路径必须是绝对路径"
        }

        let message = path
        PrintUtils.printTool("List Directory", message)

        try {
            let osName = getVariable("OS") ?? "Unknown"
            let isWindows = osName.toAsciiLower().contains("windows")

            let (exitCode, stdOutData, stdErrData) = if (isWindows) {
                executeWithOutput("powershell", ["-Command", "dir"], workingDirectory: Path(path))
            } else {
                executeWithOutput("/bin/bash", ["-c", "ls -la"], workingDirectory: Path(path))
            }

            if (exitCode == 0) {
                let outString = String.fromUtf8(stdOutData).trimAscii()
                return "目录内容如下：\n${outString}"
            } else {
                let errString = String.fromUtf8(stdErrData).trimAscii()
                return "获取目录内容失败，错误输出:\n${errString}"
            }
        } catch (e: Exception) {
            return "列出目录失败：${e}"
        }
    }

    @tool[
        description: "读取单个文件的内容，返回文件内容",
        parameters: { filePath: "文件路径，必须是绝对路径" }
    ]
    public func readFile(filePath: String): String {
        let message = filePath
        PrintUtils.printTool("Read File", message)

        return load(filePath)
    }

    @tool[
        description: "写入内容到单个文件，返回写入结果",
        parameters: { filePath: "文件路径，必须是绝对路径", content: "要写入的内容" }
    ]
    public func writeFile(filePath: String, content: String): String {
        if (!Path(filePath).isAbsolute()) {
            return "文件路径必须是绝对路径"
        }

        let message = filePath + "\n" + content
        let (confirmation, userInput) = ConfirmTool.confirm("Write File", message)
        if (!confirmation) {
            return "用户取消执行该操作，用户意见反馈：${userInput}"
        }

        try {
            let file = File(filePath, Write)
            file.write(content.toArray())
            file.close()
            return "文件 ${filePath} 写入成功！"
        } catch (e: FSException) {
            return "文件的父目录不存在、其他原因导致无法打开文件、写入失败、只写入了部分数据或文件不可写"
        } catch (e: IllegalArgumentException) {
            return "文件路径为空或文件路径包含空字符"
        } catch (e: Exception) {
            return "写入文件失败：${e}"
        }
    }

    @tool[
        description: "在指定目录及子目录的特定种类文件中搜索特定内容，返回包含内容的所有文件",
        parameters: { path: "目录路径，必须是绝对路径", pattern: "要搜索的内容", fileType: "文件类型，形如：*.cj, *.toml" }
    ]
    public func grep(path: String, pattern: String, fileType: String): String {
        let message = path + ", pattern: " + pattern + ", fileType: " + fileType
        PrintUtils.printTool("Grep", message)

        try {
            let osName = getVariable("OS") ?? "Unknown"
            let isWindows = osName.toAsciiLower().contains("windows")

            let command = if (isWindows) {
                "Get-ChildItem -Recurse -Include \"${fileType}\" | Select-String -Pattern \"${pattern}\" | Select-Object Path, LineNumber, Line"
            } else {
                "grep -rl --include=\"${fileType}\" \"${pattern}\" ."
            }

            let (exitCode, stdOutData, stdErrData) = if (isWindows) {
                executeWithOutput("powershell", ["-Command", command], workingDirectory: Path(path))
            } else {
                executeWithOutput("/bin/bash", ["-c", command], workingDirectory: Path(path))
            }

            if (exitCode == 0) {
                let outString = String.fromUtf8(stdOutData).trimAscii()
                return "搜索结果：\n${outString}\n状态： 搜索成功"
            } else {
                let errString = String.fromUtf8(stdErrData).trimAscii()
                return "搜索失败：${errString}"
            }
        } catch (e: Exception) {
            return "搜索文件失败：${e}"
        }
    }

    @tool[
        description: "在指定目录下基于模式匹配查找特定后缀名的文件",
        parameters: { path: "目录路径，必须是绝对路径", extension: "文件后缀名，形如：.cs, .txt" }
    ]
    public func glob(path: String, extension: String): String {
        if (!Path(path).isAbsolute()) {
            return "目录路径必须是绝对路径"
        }

        let message = path + ", extension: " + extension
        PrintUtils.printTool("Glob", message)

        try {
            if (!exists(path)) {
                return "目录 ${path} 不存在"
            }

            let matchedFiles = ArrayList<String>()

            func searchDirectory(currentPath: String): Unit {
                try {
                    for (item in Directory.readFrom(currentPath)) {
                        let fullPath = "${currentPath}/${item.name}"
                        if (item.isDirectory()) {
                            searchDirectory(fullPath)
                        } else if (item.name.endsWith(extension)) {
                            matchedFiles.add(fullPath)
                        }
                    }
                } catch (e: Exception) {
                    return
                }
            }

            searchDirectory(path)

            if (matchedFiles.size == 0) {
                return "在目录 ${path} 中未找到匹配 ${extension} 的文件"
            }

            var result = "在目录 ${path} 中找到 ${matchedFiles.size} 个匹配 ${extension} 的文件：\n"
            for (file in matchedFiles) {
                result += "- ${file}\n"
            }

            return result
        } catch (e: FSException) {
            return "目录访问失败：指定路径不是目录或权限不足"
        } catch (e: IllegalArgumentException) {
            return "参数错误：路径为空或包含非法字符"
        } catch (e: Exception) {
            return "搜索文件失败：${e}"
        }
    }

    // @tool[
    //     description: "查询文件或目录的权限，返回权限信息",
    //     parameters: { path: "文件或目录路径，必须是绝对路径" }
    // ]
    public func getPermissions(path: String): String {
        if (!Path(path).isAbsolute()) {
            return "文件或目录路径必须是绝对路径"
        }

        try {
            let fileInfo = FileInfo(path)
            var result = "路径: ${path}\n"
            result += "权限: "
            if (fileInfo.canRead()) {
                result += "可读 "
            } else {
                result += "不可读 "
            }
            if (fileInfo.canWrite()) {
                result += "可写 "
            } else {
                result += "不可写 "
            }
            if (fileInfo.canExecute()) {
                result += "可执行"
            } else {
                result += "不可执行"
            }
            return result
        } catch (e: FSException) {
            return "文件或目录不存在或无法访问"
        } catch (e: IllegalArgumentException) {
            return "路径为空或包含非法字符"
        } catch (e: Exception) {
            return "查询权限失败：${e}"
        }
    }

    // @tool[
    //     description: "修改文件或目录的权限，返回修改结果",
    //     parameters: { path: "文件或目录路径，必须是绝对路径", permissions: "设置当前用户的权限，形如：rwx, rw-, --x" }
    // ]
    public func setPermissions(path: String, permissions: String): String {
        if (!Path(path).isAbsolute()) {
            return "文件或目录路径必须是绝对路径"
        }

        let message = "${path}  ${permissions}\n"
        let (confirmation, userInput) = ConfirmTool.confirm("Set Permissions", message)
        if (!confirmation) {
            return "用户取消执行该操作，用户意见反馈：${userInput}"
        }

        try {
            let fileInfo = FileInfo(path)
            if (permissions.size != 3) {
                return "权限格式错误，必须为三字符格式，如：rwx, rw-, --x"
            }
            if (permissions.contains("r")) {
                fileInfo.setReadable(true)
            } else {
                fileInfo.setReadable(false)
            }
            if (permissions.contains("w")) {
                fileInfo.setWritable(true)
            } else {
                fileInfo.setWritable(false)
            }
            if (permissions.contains("x")) {
                fileInfo.setExecutable(true)
            } else {
                fileInfo.setExecutable(false)
            }
            return "文件或目录 ${path} 的权限已修改为：${permissions}"
        } catch (e: FSException) {
            return "文件或目录不存在或无法访问"
        } catch (e: IllegalArgumentException) {
            return "路径为空或包含非法字符"
        } catch (e: Exception) {
            return "修改权限失败：${e}"
        }
    }

    @tool[
        description: "修改文件内容，必须一次至少修改一个函数的内容，返回修改结果",
        parameters: { filePath: "文件路径，必须是绝对路径", oldContent: "原本文件的内容，必须是文件里出现的部分，必须至少包含原文件中的一个函数", newContent: "即将覆盖的内容" }
    ]
    public func editFileContent(filePath: String, oldContent: String, newContent: String): String {
        if (!Path(filePath).isAbsolute()) {
            return "文件路径必须是绝对路径"
        }

        let message = filePath + "\nold content:\n" + oldContent + "\nnew content:\n" + newContent
        let (confirmation, userInput) = ConfirmTool.confirm("Edit File Content", message)
        if (!confirmation) {
            return "用户取消执行该操作，用户意见反馈：${userInput}"
        }

        try {
            let content = String.fromUtf8(File.readFrom(filePath))
            if (!content.contains(oldContent)) {
                return "文件 ${filePath} 中不包含指定的内容 '${oldContent}'，无法进行修改"
            }
            let updatedContent = content.replace(oldContent, newContent)
            let file = File(filePath, Write)
            file.write(updatedContent.toArray())
            file.close()
            return "文件 ${filePath} 内容已成功修改"
        } catch (e: FSException) {
            return "文件路径错误或文件不可读写"
        } catch (e: IllegalArgumentException) {
            return "文件路径为空或包含非法字符"
        } catch (e: Exception) {
            return "修改文件内容失败：${e}"
        }
    }

    public static func load(filePath: String): String {
        if (!Path(filePath).isAbsolute()) {
            return "文件路径必须是绝对路径"
        }

        try {
            let fileContent = File.readFrom(filePath)
            return "文件内容:\n${String.fromUtf8(fileContent)}"
        } catch (e: FSException) {
            return "文件路径为空、文件不可读或文件读取失败"
        } catch (e: IllegalArgumentException) {
            return "文件路径包含空字符"
        } catch (e: Exception) {
            return "读取文件失败：${e}"
        }
    }
}