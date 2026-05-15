package cli.replay

import magic.core.agent.Agent
import magic.core.message.ChatRound
import magic.interaction.*
import magic.log.LogUtils

import cli.app.CliApp
import cli.core.config.CliConfig
import cli.io.PrintUtils

import std.collection.ArrayList

// Entry point for --mode record and --mode replay.
public class ReplayRunner {
    // Record a task run: run the agent live and save the resulting trace.
    // The taskPrompt must be non-empty (supplied via --prompt / -p).
    public static func record(app: CliApp, taskPrompt: String): Unit {
        if (taskPrompt.trimAscii().isEmpty()) {
            PrintUtils.printLine("[record] Error: supply a task prompt with --prompt or -p")
            return
        }

        let traceName = CliConfig.traceName
        PrintUtils.printLine("[record] Task: \"${taskPrompt}\"")
        PrintUtils.printLine("[record] Trace name: ${traceName}")

        // Collect sub-agent (ChatRound, Agent) pairs in call order via SubAgentEndEvent.
        // These are used by Recorder to embed nested sub-traces (Stage 2).
        let subCaptures = ArrayList<(ChatRound, Agent)>()
        EventHandlerManager.global.addHandler { evt: SubAgentEndEvent =>
            let subRound = evt.agentResponse.execution.chatRound
            subCaptures.add((subRound, evt.agent))
        }

        // Run the agent and get the response
        let response = app.runRecordableTask(taskPrompt)

        // Wait for completion and print the final answer
        let content = response.content
        if (!content.trimAscii().isEmpty()) {
            PrintUtils.printAgentResponse(response)
        }

        // Extract the trace from the completed chat round
        let chatRound = response.execution.chatRound
        let trace = Recorder.extract(chatRound, taskPrompt, app.mainAgent, subCaptures: subCaptures)

        var subAgentCount: Int64 = 0
        for (step in trace.steps) {
            if (step.subTrace.isSome()) { subAgentCount++ }
        }
        PrintUtils.printLine("[record] Captured ${trace.steps.size} tool step(s) (${subAgentCount} sub-agent with nested trace)")

        // Save to disk
        TraceStore.save(trace, traceName)
        let path = TraceStore.tracePath(traceName)
        PrintUtils.printLine("[record] Trace saved -> ${path}")
    }

    // Dry-run replay: re-execute each recorded tool call and report where results diverge.
    // Sub-agent steps with embedded sub-traces are validated recursively (Stage 2).
    // Sub-agent steps without sub-traces (Stage 1 traces) are skipped with a warning.
    // NOTE: Tool calls with side effects (file writes, shell commands) ARE re-executed.
    // Start from a clean environment to avoid state pollution between runs.
    public static func replay(app: CliApp, traceName: String): Unit {
        // Load trace
        let traceOpt = TraceStore.load(traceName)
        if (traceOpt.isNone()) {
            PrintUtils.printLine("[replay] Error: trace '${traceName}' not found in ${CliConfig.traceDir}")
            return
        }
        let trace = traceOpt.getOrThrow()

        PrintUtils.printLine("[replay] Trace: ${traceName}  (recorded ${trace.recordedAt})")
        PrintUtils.printLine("[replay] Agent: ${trace.agentName}")
        PrintUtils.printLine("[replay] Task:  \"${trace.taskPrompt}\"")
        PrintUtils.printLine("[replay] Steps: ${trace.steps.size}")
        PrintUtils.printLine("")

        // Validate each tool step
        let result = Replayer.validate(trace, app.mainAgent)

        // Count skipped steps (Stage 1 sub-agent steps without sub-trace)
        var skippedCount: Int64 = 0
        for ((_, _, r) in result.stepResults) {
            match (r) {
                case StepResult.Skipped(_) => skippedCount++
                case _ => ()
            }
        }

        // Print summary
        PrintUtils.printLine("")
        if (result.allCached) {
            if (skippedCount > 0) {
                PrintUtils.printLine("[replay] Result: all checked step(s) cache-hit -- ${skippedCount} sub-agent step(s) skipped (re-record to enable Stage 2 validation)")
            } else {
                PrintUtils.printLine("[replay] Result: all ${trace.steps.size} step(s) cache-hit -- no divergence detected")
            }
        } else if (result.systemPromptChanged) {
            PrintUtils.printLine("[replay] Result: system prompt changed -- full re-run needed")
        } else if (let Some(idx) <- result.firstDivergenceIndex) {
            PrintUtils.printLine("[replay] Result: first divergence at step ${idx} -- re-run from that step onward")
        }
    }
}
