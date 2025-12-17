package cli.core.tools

import magic.dsl.*
import magic.prelude.*
import magic.log.LogUtils

import cli.core.plan.Plan
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
        if (InputUtils.confirm(this.plan) == Confirmation.Deny) {
            return "User denied the plan"
        }
        this.plan.save()
        return "Plan has been approved by user, ready to start execution."
    }

    @tool[
        description: "Review the current plan and the completion status of each task (TODO/DONE)."
    ]
    public func todoReview(): String {
        if (this.plan.isEmpty()) {
            return "No current plan."
        }
        return "Current Plan:\n${this.plan}"
    }

    @tool[
        description: "Marks the task at the specified index as completed (DONE) and returns the current TODO List",
        parameters: { taskIndex: "Index of the task to mark as complete (starting from 1)" }
    ]
    public func todoMarkComplete(taskIndex: Int64): String {
        if (taskIndex < 1 || taskIndex > this.plan.tasks.size) {
            return "Error: Invalid task index ${taskIndex}."
        } else if (this.plan.tasks[taskIndex-1].completed) {
            return "Task ${taskIndex} is already completed."
        }
        this.plan.tasks[taskIndex-1].markAsComplete()
        this.plan.save()
        PrintUtils.printPlan(this.plan)
        PrintUtils.printLine("")
        return "Task ${taskIndex} has been completed. Current task list:\n${this.plan}"
    }
}