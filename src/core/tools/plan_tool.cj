package cli.core.tools

import std.collection.*
import std.fs.*

public class PlanTool {
    public static func createPlan(tasks: Array<String>): String {
        var content = ""
        for (task in tasks) {
            content += "- [ ] ${task}\n"
        }
        return content
    }

    public static func completeTask(content: String, task_index: Int64): (String, String) {
        let lines = content.split("\n")
        let updatedLines = ArrayList<String>()
        var taskFound = false
        var currentTaskNum = 0

        for (line in lines) {
            if (line.trimAscii().startsWith("- [")) {
                currentTaskNum += 1
                if (currentTaskNum == task_index) {
                    if (line.contains("- [ ]")) {
                        updatedLines.add(line.replace("- [ ]", "- [x]"))
                        taskFound = true
                    } else {
                        updatedLines.add(line)
                        return (content, "任务 ${task_index} 已经是完成状态。")
                    }
                } else {
                    updatedLines.add(line)
                }
            } else {
                updatedLines.add(line)
            }
        }

        if (!taskFound) {
            return (content, "错误: 无效的任务索引 ${task_index}。")
        }

        var updatedContent = ""
        for (i in 0..updatedLines.size) {
            updatedContent += updatedLines[i]
            if (i < updatedLines.size - 1) {
                updatedContent += "\n"
            }
        }
        return (updatedContent, "任务 ${task_index} 已完成。")
    }

    public static func save(content: String, filePath: String): Unit {
        try {
            let file = File(filePath, Write)
            file.write(content.toArray())
            file.close()
            println("todo.md保存成功！")
        } catch(e: Exception) {
            println("错误：无法保存计划文件到 ${filePath}。 详情: ${e}")
        }
    }
}