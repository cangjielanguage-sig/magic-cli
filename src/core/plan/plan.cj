package cli.core.plan

import magic.log.LogUtils
import cli.core.config.CliConfig

import std.collection.ArrayList
import std.fs.{File, OpenMode, FSException, exists}

/**
 * A plan represents a list of tasks to be completed.
 */
protected class Plan <: ToString {
    protected let tasks: ArrayList<Task>

    protected init() {
        this.tasks = ArrayList<Task>()
    }

    protected init(tasks: Array<String>) {
        this.tasks = ArrayList<Task>(tasks.size, { i => Task(tasks[i]) })
    }

    public func isEmpty(): Bool {
        return this.tasks.isEmpty()
    }

    override public func toString(): String {
        let strBuilder = StringBuilder()
        for (task in this.tasks) {
            if (task.completed) {
                strBuilder.append("- [x] ${task.description}\n")
            } else {
                strBuilder.append("- [ ] ${task.description}\n")
            }
        }
        return strBuilder.toString()
    }

    public func save(): Unit {
        let path = CliConfig.todoFile
        try {
            let file = File(path, OpenMode.Write)
            file.write(this.toString().toArray())
            file.close()
        } catch(e: Exception) {
            LogUtils.error("Error: Unable to save plan file to ${path}. Details: ${e}")
        }
    }

    public static func load(): Plan {
        let plan = Plan()
        if (!exists(CliConfig.todoFile)) {
            return plan
        }
        let content = try {
            String.fromUtf8(File.readFrom(CliConfig.todoFile))
        } catch (e: FSException) {
            LogUtils.debug("File or directory does not exist or is not accessible")
            return plan
        }
        for (line in content.split("\n")) {
            if (!line.trimAscii().isEmpty()) {
                // Line must start with "- [ ] " or "- [x] "
                let task = Task(line[5..].trimAscii())
                if (line.startsWith("- [x]")) {
                    task.markAsComplete()
                }
                plan.tasks.add(task)
            }
        }
        return plan
    }
}

// protected class Task {
//     protected let description: String
//     protected var completed: Bool

//     public init(description: String) {
//         this.description = description
//         this.completed = false
//     }

//     public func markAsComplete(): Unit {
//         this.completed = true
//     }
// }

protected class Task <: ToString {
    protected let description: String
    protected let taskId: String
    protected let subtasks: ArrayList<Task>
    protected var completed: Bool
    protected let level: Int64
    protected let indent: Int64

    public init(description: String, taskId: String, level: Int64, indent!: Int64 = INDENT) {
        this.description = description
        this.taskId = taskId
        this.subtasks = ArrayList<Task>()
        this.completed = false
        this.level = level
        this.indent = indent
    }

    public init(description: String, taskId: String, subtasks: ArrayList<Task>, level: Int64, indent!: Int64 = INDENT) {
        this.description = description
        this.taskId = taskId
        this.subtasks = subtasks
        this.completed = false
        this.level = level
        this.indent = indent
    }

    public func addSubtask(subtask: Task): Unit {
        this.subtasks.add(subtask)
    }

    public func markAsComplete(): Unit {
        this.completed = true
    }

    public func clearSubtasks(): Unit {
        subtasks.clear()
    }

    public static func fromMarkdown(line: String, level: Int64): Task {
        // Line must start with "- [ ] " or "- [x] "
        let trimmedLine = line.trimAscii()
        let rawDescription = trimmedLine[5..].trimAscii().split(" :: ")
        let taskId = rawDescription[0]
        let description = String.join(rawDescription[1..], delimiter: " :: ")
        let task = Task(description, taskId, level)
        if (trimmedLine.startsWith("- [x]")) {
            task.markAsComplete()
        }
        return task
    }

    public static func fromMarkdownRecursively(line: String, subtaskLines: ArrayList<String>, level!: Int64 = 0, indent!: Int64 = INDENT): Task {
        let rootTask = Task.fromMarkdown(line, level)
        var co = 0
        while (co < subtaskLines.size) {
            let subtaskLine = subtaskLines[co]
            co += 1
            let subsubtaskLines = ArrayList<String>()
            while (co < subtaskLines.size) {
                if (subtaskLines[co].startsWith(" " * (level + 1) * indent + "-")) {
                    break
                }
                subsubtaskLines.add(subtaskLines[co])
                co += 1
            }
            let subtask = Task.fromMarkdownRecursively(subtaskLine, subsubtaskLines, level: level + 1, indent: indent)
            rootTask.addSubtask(subtask)
        }
        return rootTask
    }
}
