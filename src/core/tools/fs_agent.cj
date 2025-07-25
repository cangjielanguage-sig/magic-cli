package cli.core.tools

import magic.dsl.*
import magic.prelude.*
import magic.config.Config
import std.fs.*
import std.process.*
import std.io.*
import std.env.*
import std.posix.*
import std.collection.*

@agent[model: "deepseek:deepseek-chat"]
class FSAgent {
    @prompt(
        "你是一个能够执行文件系统操作的AI助手，你的能力包括但不限于：\n"
        "1. 创建、删除文件和目录\n"
        "2. 读取和写入文件内容\n"
        "3. 对文件的特定内容进行修改\n"
        "4. 列出目录内容\n"
        "5. 基于模式匹配查找文件\n"
        "6. 搜索文件内容\n"
        "7. 查询或修改文件权限\n\n"
        "请注意，你需要根据用户的输入提炼出需要执行的文件系统操作。\n\n"
        "请注意，请注意！你需要向用户请求确认当且仅当：\n"
        "1. 执行的操作可能会导致数据丢失，如删除文件或目录\n"
        "2. 执行的操作可能会覆盖现有文件，如写入文件内容或修改文件内容或创建并写入文件\n"
        "3. 执行的操作需要修改文件权限\n"
        "请注意，当用户同意执行操作后，你需要执行该操作并返回结果；如果用户不同意，则直接退出Agent，返回'用户取消执行操作'。\n\n"
        "注意你需要尽力完成用户的任务，如果你在执行操作时遇到错误，包括但不限于语法错误、权限问题等，你需要将错误信息简洁易懂地反馈给用户，并提供解决方案，寻求用户的确认。\n"
        "如果你实在无法对遇到的问题提供解决方案，那么返回问题详情，退出Agent\n"
    )

    @tool[
        description: "获取当前工作目录"
    ]
    public func getCurrentDirectory(): String {
        return canonicalize(".").toString()
    }

    @tool[
        description: "创建目录，可递归创建，返回创建结果",
        parameters: { path: "目录路径" }
    ]
    public func createDirectory(path: String): String {
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
        parameters: { content: "文件内容", filePath: "文件路径" }
    ]
    public func createFile(content: String, filePath: String): String {
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
        parameters: { path: "文件或目录路径" }
    ]
    public func deleteFileOrDirectory(path: String): String {
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
        description: "列出目录下的所有文件和子目录，返回目录内容",
        parameters: { path: "目录路径" }
    ]
    public func listDirectory(path: String): String {
        try {
            if (Directory.isEmpty(path)) {
                return "目录 ${path} 为空"
            }
            var result = "目录 ${path} 的内容：\n"
            for (item in Directory.readFrom(path)) {
                result += "- ${item.name}"
                if (item.isDirectory()) {
                    result += " (目录)"
                } else {
                    result += " (文件)"
                }
                result += "\n"
            }
            return result
        } catch (e: FSException) {
            return "目录不存在或该路径不是一个目录"
        } catch (e: IllegalArgumentException) {
            return "指定路径为空或包含空字符"
        } catch (e: Exception) {
            return "列出目录失败：${e}"
        }
    }

    @tool[
        description: "读取单个文件的内容，返回文件内容",
        parameters: { filePath: "文件路径" }
    ]
    public func readFile(filePath: String): String {
        try {
            let fileContent = File.readFrom(filePath)
            return "文件内容:\n${fileContent.toString()}"
        } catch (e: FSException) {
            return "文件路径为空、文件不可读或文件读取失败"
        } catch (e: IllegalArgumentException) {
            return "文件路径包含空字符"
        } catch (e: Exception) {
            return "读取文件失败：${e}"
        }
    }

    @tool[
        description: "写入内容到单个文件，返回写入结果",
        parameters: { filePath: "文件路径", content: "要写入的内容" }
    ]
    public func writeFile(filePath: String, content: String): String {
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
        description: "在当前目录及子目录的特定种类文件中搜索特定内容，返回包含内容的所有文件",
        parameters: { pattern: "要搜索的内容", fileType: "文件类型，形如：*.cs, *.txt" }
    ]
    public func grep(pattern: String, fileType: String): String {
        try {
            let osName = getVariable("OS") ?? "Unknown"
            let isWindows = osName.toAsciiLower().contains("windows")

            let command = if (isWindows) {
                "Get-ChildItem -Recurse -Include \"${fileType}\" | Select-String -Pattern \"${pattern}\" | Select-Object Path, LineNumber, Line"
            } else {
                "grep -rl --include=\"${fileType}\" \"${pattern}\" ."
            }

            let process = if (isWindows) {
                launch("powershell", ["-Command", command], stdOut: ProcessRedirect.Pipe)
            } else {
                launch("/bin/bash", ["-c", command], stdOut: ProcessRedirect.Pipe)
            }

            let outReader = StringReader<InputStream>(process.stdOutPipe)
            let output = outReader.readToEnd()
            let exitCode = process.wait()

            var result = "搜索结果：\n${output}\n"
            if (exitCode == 0) {
                result += "状态: 搜索成功"
            } else {
                result += "状态: 搜索失败"
            }

            return result
        } catch (e: Exception) {
            return "搜索文件失败：${e}"
        }
    }

    @tool[
        description: "在指定目录下基于模式匹配查找特定后缀名的文件",
        parameters: { path: "目录路径", extension: "文件后缀名，形如：.cs, .txt" }
    ]
    public func glob(path: String, extension: String): String {
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

    @tool[
        description: "查询文件或目录的权限，返回权限信息",
        parameters: { path: "文件或目录路径" }
    ]
    public func getPermissions(path: String): String {
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

    @tool[
        description: "修改文件或目录的权限，返回修改结果",
        parameters: { path: "文件或目录路径", permissions: "设置当前用户的权限，形如：rwx, rw-, --x" }
    ]
    public func setPermissions(path: String, permissions: String): String {
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
        description: "修改文件内容，返回修改结果",
        parameters: { filePath: "文件路径", oldContent: "原本文件的内容，必须是文件里出现的部分", newContent: "即将覆盖的内容" }
    ]
    public func editFileContent(filePath: String, oldContent: String, newContent: String): String {
        try {
            let file = File(filePath, ReadWrite)
            let content = File.readFrom(filePath).toString()
            if (!content.contains(oldContent)) {
                return "文件 ${filePath} 中不包含指定的内容 '${oldContent}'，无法进行修改"
            }
            let updatedContent = content.replace(oldContent, newContent)
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

    @tool[
        description: "请求用户确认，返回用户意见",
        parameters: { message: "需要用户确认的消息，具体要求：1. 如果需要向用户确认删除文件或目录，必须明确指出要删除的文件或目录的路径。2. 如果需要向用户确认覆盖文件或修改文件内容，必须明确指出要覆盖的文件的路径、原本文件的内容（可只显示部分）、即将覆盖的内容（必须全部显示）。3. 如果需要向用户确认修改文件权限，必须明确指出要修改的文件路径、即将修改的权限设置。" }
    ]
    public func requestUserConfirmation(message: String): String {
        println(message)
        print("用户是否同意执行？(yes/no): ")
        var response = readln()
        if (response.isEmpty()) {
            response = "yes"
        }
        return response
    }

}