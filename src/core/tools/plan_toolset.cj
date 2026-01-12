package cli.core.tools

import magic.dsl.*
import magic.prelude.*
import magic.log.LogUtils

import cli.core.plan.{ Plan, Task }
import cli.core.config.CliConfig
import cli.io.{InputUtils, PrintUtils, Confirmation, WithColor, AnsiColor, Theme}
import cli.utils.*

import std.collection.*
import std.fs.*


@toolset
public class PlanToolset {
    private var plan = Plan.load()

    @tool[
        description: "Creates a new task plan or overwrites an existing plan with a new one. This is the first step to start complex tasks.",
        parameters: { tasks: "An array of strings, each item is a clear subtask description" }
    ]
    public func todoCreate(tasks: Array<String>): String {
        this.plan = Plan(tasks)
        // TODO: why confirm here does not show the task ID?
        if (InputUtils.confirm(this.plan) == Confirmation.Deny) {
            return "User denied the plan"
        }
        this.plan.save()
        return "Plan has been approved by user, ready to start execution. The following tasks are created:\n${plan.toString()}"
    }

    @tool[
        description: "Breaks down a parent task into clear and actionable subtasks.",
        parameters: {
            todoId: "Id of the parent task that needs to be broken down into subtasks",
            subtasks: "An array of strings, each item is a clear description of the subtask broken down from the parent task" 
        }
    ]
    public func todoBreakDown(todoId: String, subtasks: Array<String>): String {
        let parentTask: ?Task = this.plan.getTask(todoId)
        if (parentTask.isNone()) {
            return "Error: task with the task id ${todoId} is not found. Please check whether the todoId is correct."
        }
        for (subtask in subtasks) {
            this.plan.addSubtask(subtask, todoId)
        }
        if (InputUtils.confirm(parentTask.getOrThrow()) == Confirmation.Deny) {
            parentTask.getOrThrow().clearSubtasks()
            return "User denied the subtasks"
        }
        this.plan.save()
        return "Subtasks has been approved by user, ready to start execution. The current plan is in the following:\n${plan.toString()}"
    }

    @tool[
        description: "Review the current plan, the completion status (TODO/DONE), and the task id of each task."
    ]
    public func todoReview(): String {
        if (this.plan.isEmpty()) {
            return "No current plan."
        }
        return "Current Plan:\n${this.plan}"
    }

    @tool[
        description: "Marks the task with the specific task id as completed (DONE) and returns the current TODO List. If the task is the last subtask of the parent task, the parent task will also be marked as completed.",
        parameters: { taskId: "Id of the task to mark as complete" }
    ]
    public func taskMarkComplete(taskId: String): String {
        let tasks = plan.getPathFromRootToTask(taskId)
        if (tasks.isNone()) {
            return "Error: cannot find the task with task id ${taskId}. Please check whether this task id exists in the plan."
        }
        for (i in 0..tasks.getOrThrow().size) {
            let task = tasks.getOrThrow()[tasks.getOrThrow().size - 1 - i]
            if (!task.completed) {
                task.markAsComplete()
                if (i != tasks.getOrThrow().size - 1) {
                    let parentTask = tasks.getOrThrow()[tasks.getOrThrow().size - 2 - i]
                    let lastSubtask = parentTask.subtasks.last
                    if (lastSubtask.isSome() && task.taskId != lastSubtask.getOrThrow().taskId) {
                        break
                    }

                }
            }
        }
        plan.save()
        PrintUtils.printPlan(this.plan)
        PrintUtils.printLine("")
        return "Task ${taskId} has been completed. Current task list:\n${this.plan}"
    }
}