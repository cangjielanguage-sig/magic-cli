package cli.core.tools

import std.collection.*
import std.fs.*

import magic.dsl.*
import magic.prelude.*

@toolset
public class PlanTool {
    let planFilePath = FSTool.getWorkingDirectory() + "/todo.md"
    var planMarkdown = FSTool.load(planFilePath)

    @tool[
        description: "创建一个新的任务计划，或用新计划覆盖现有计划。这是开始复杂任务的第一步。",
        parameters: { tasks: "一个字符串数组，每项都是一个清晰的子任务描述" }
    ]
    public func createOrUpdatePlan(tasks: Array<String>): String {
        var content = ""
        for (task in tasks) {
            content += "- [ ] ${task}\n"
        }
        this.planMarkdown = content
        let message = "\n" + this.planMarkdown + "\n计划已创建，请确认是否需要修改计划，确认执行则保存该计划，并开始执行。"
        let (confirmation, userInput) = ConfirmTool.confirm("Plan", message)
        if (!confirmation) {
            return "用户取消执行该操作，用户意见反馈：${userInput}"
        }
        save(this.planMarkdown, this.planFilePath)
        return "目前的计划:\n" + this.planMarkdown + "\n计划已获得用户批准，准备开始执行。"
    }

    @tool[
        description: "查看当前的计划和每个任务的完成状态 (TODO/DONE)。"
    ]
    public func viewPlan(): String {
        if (this.planMarkdown.trimAscii().isEmpty()) {
            return "当前没有计划。"
        }
        return "当前计划:\n${this.planMarkdown}"
    }

    @tool[
        description: "将指定索引的任务标记为已完成 (DONE)。",
        parameters: { task_index: "要标记为完成的任务的索引 (从1开始)" }
    ]
    public func markTaskAsComplete(task_index: Int64): String {
        let (updatedMarkdown, message) = completeTask(this.planMarkdown, task_index)
        this.planMarkdown = updatedMarkdown
        save(this.planMarkdown, this.planFilePath)
        return message
    }

    public func completeTask(content: String, task_index: Int64): (String, String) {
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