package cli.core.tools

import magic.dsl.*
import magic.prelude.*
import magic.log.LogUtils

import cli.core.config.CliConfig
import cli.io.{InputUtils, PrintUtils}
import cli.utils.*

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
            LogUtils.error("Error: Unable to save plan file to ${path}. Details: ${e}")
        }
    }

    public static func fromFile(): Plan {
        let plan = Plan()
        let content = try {
            String.fromUtf8(File.readFrom(CliConfig.todoFile))
        } catch (e: FSException) {
            LogUtils.debug("File or directory does not exist or is not accessible")
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
public class PlanToolset {
    private var plan = Plan.fromFile()

    @tool[
        description: "Creates a new task plan or overwrites an existing plan with a new one. This is the first step to start complex tasks.",
        parameters: { tasks: "An array of strings, each item is a clear subtask description" }
    ]
    public func createOrUpdatePlan(tasks: Array<String>): String {
        this.plan = Plan(tasks)
        let message = "\n${this.plan}\nPlan has been created. Please confirm if you need to modify the plan. Confirm execution to save this plan and start execution."
        if (let Deny(userInput) <- InputUtils.confirm("Plan", message)) {
            return "User cancelled the operation, feedback: ${userInput}"
        }
        this.plan.save()
        return "\nPlan has been approved by user, ready to start execution."
    }

    @tool[
        description: "View the current plan and the completion status of each task (TODO/DONE)."
    ]
    public func viewPlan(): String {
        if (this.plan.isEmpty()) {
            return "No current plan."
        }
        return "Current plan:\n${this.plan}"
    }

    @tool[
        description: "Marks the task at the specified index as completed (DONE) and returns the current TODO List",
        parameters: { taskIndex: "Index of the task to mark as complete (starting from 1)" }
    ]
    public func markTaskAsComplete(taskIndex: Int64): String {
        if (taskIndex < 1 || taskIndex > this.plan.tasks.size) {
            return "Error: Invalid task index ${taskIndex}."
        } else if (this.plan.tasks[taskIndex-1].completed) {
            return "Task ${taskIndex} is already completed."
        }
        this.plan.tasks[taskIndex-1].markAsComplete()
        this.plan.save()
        PrintUtils.printTool("📝 Current Plan", this.plan.toString())
        return "Task ${taskIndex} has been completed. Current task list:\n${this.plan}"
    }
}