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

protected class Task {
    protected let description: String
    protected var completed: Bool

    public init(description: String) {
        this.description = description
        this.completed = false
    }

    public func markAsComplete(): Unit {
        this.completed = true
    }
}