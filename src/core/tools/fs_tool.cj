package cli.core.tools

import std.fs.*
import std.process.*
import std.io.*
import std.env.*
import std.posix.*
import std.collection.*

class FSTool {
    public static func createDirectory(path: String): String {
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

    public static func createFile(content: String, filePath: String): String {
        let message = "你正在尝试创建文件 ${filePath}，内容为：\n${content}\n"
        if (!confirm(message)) {
            return "操作已取消"
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

    public static func deleteFileOrDirectory(path: String): String {
        let message = "你正在尝试删除文件或目录 ${path}，请确认是否继续？\n"
        if (!confirm(message)) {
            return "操作已取消"
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
    
    public static func listDirectory(path: String): String {
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

    public static func readFile(filePath: String): String {
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

    public static func writeFile(filePath: String, content: String): String {
        let message = "你正在尝试写入文件 ${filePath}，内容为：\n${content}\n"
        if (!confirm(message)) {
            return "操作已取消"
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

    public static func grep(pattern: String, fileType: String): String {
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

    public static func glob(path: String, extension: String): String {
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

    public static func getPermissions(path: String): String {
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

    public static func setPermissions(path: String, permissions: String): String {
        let message = "你正在尝试修改文件或目录 ${path} 的权限为：${permissions}\n"
        if (!confirm(message)) {
            return "操作已取消"
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
        description: "修改文件内容，返回修改结果",
        parameters: { filePath: "文件路径", oldContent: "原本文件的内容，必须是文件里出现的部分", newContent: "即将覆盖的内容" }
    ]
    public static func editFileContent(filePath: String, oldContent: String, newContent: String): String {
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

    public func confirm(message: String): Bool {
        println(message)
        print("用户是否同意执行？(yes/no): ")
        var response = readln()
        if (response.isEmpty()) {
            response = "yes"
        }
        if (response.toAsciiLower().contains("yes")) {
            return true
        } else {
            return false
        }
    }
}