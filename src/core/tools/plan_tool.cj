package cli.core.tools

import cli.utils.*
import cli.core.config.CliConfig

import magic.dsl.*
import magic.prelude.*
import magic.log.LogUtils

import std.collection.*
import std.fs.*

private class Task {
    let description: String
    var completed: Bool

    public init(description: String) {
        this.description = description
        this.completed = false
    }

    public func markAsComplete(): Unit {
        this.completed = true
    }

    public func toMarkdown(): String {
        if (this.completed) {
            return "- [x] ${this.description}"
        } else {
            return "- [ ] ${this.description}"
        }
    }

    public static func fromMarkdown(line: String): Task {
        // Line must start with "- [ ] " or "- [x] "
        let task = Task(line[5..].trimAscii())
        if (line.startsWith("- [x]")) {
            task.markAsComplete()
        }
        return task
    }
}

private class Plan <: ToString {
    let tasks: ArrayList<Task>

    init() {
        this.tasks = ArrayList<Task>()
    }

    init(tasks: Array<String>) {
        this.tasks = ArrayList<Task>(tasks.size, { i => Task(tasks[i]) })
    }

    public func isEmpty(): Bool {
        return this.tasks.isEmpty()
    }

    override public func toString(): String {
        return String.join(
            this.tasks |> map { task => task.toMarkdown() } |> collectArray,
            delimiter: "\n"
        )
    }

    public func save(): Unit {
        let path = CliConfig.todoFile
        try {
            let file = File(path, Write)
            let content = this.toString()
            file.write(content.toArray())
            file.close()
        } catch(e: Exception) {
            LogUtils.error("错误：无法保存计划文件到 ${path}。 详情: ${e}")
        }
    }

    public static func fromFile(): Plan {
        let plan = Plan()
        let content = try {
            String.fromUtf8(File.readFrom(CliConfig.todoFile))
        } catch (e: FSException) {
            LogUtils.debug("文件或目录不存在或无法访问")
            return plan
        }
        for (line in content.split("\n")) {
            if (!line.trimAscii().isEmpty()) {
                plan.tasks.add(Task.fromMarkdown(line))
            }
        }
        return plan
    }
}

@toolset
public class PlanTool {
    private var plan = Plan.fromFile()

    @tool[
        description: "创建一个新的任务计划，或用新计划覆盖现有计划。这是开始复杂任务的第一步。",
        parameters: { tasks: "一个字符串数组，每项都是一个清晰的子任务描述" }
    ]
    public func createOrUpdatePlan(tasks: Array<String>): String {
        this.plan = Plan(tasks)
        let message = "\n${this.plan}\n计划已创建，请确认是否需要修改计划，确认执行则保存该计划，并开始执行。"
        if (let Deny(userInput) <- InputUtils.confirm("Plan", message)) {
            return "用户取消执行该操作，用户意见反馈：${userInput}"
        }
        this.plan.save()
        return "\n计划已获得用户批准，准备开始执行。"
    }

    @tool[
        description: "查看当前的计划和每个任务的完成状态 (TODO/DONE)。"
    ]
    public func viewPlan(): String {
        if (this.plan.isEmpty()) {
            return "当前没有计划。"
        }
        return "当前计划:\n${this.plan}"
    }

    @tool[
        description: "将指定索引的任务标记为已完成 (DONE)，并返回当前的 TODO List",
        parameters: { taskIndex: "要标记为完成的任务的索引 (从1开始)" }
    ]
    public func markTaskAsComplete(taskIndex: Int64): String {
        if (taskIndex < 1 || taskIndex > this.plan.tasks.size) {
            return "错误: 无效的任务索引 ${taskIndex}。"
        } else if (this.plan.tasks[taskIndex].completed) {
            return "任务 ${taskIndex} 已经是完成状态。"
        }
        this.plan.tasks[taskIndex-1].markAsComplete()
        this.plan.save()
        PrintUtils.printTool("📝 Current Plan", this.plan.toString())
        return "任务 ${taskIndex} 已被完成，当前任务列表：\n${this.plan}"
    }
}