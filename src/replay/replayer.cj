package cli.replay

import magic.core.agent.Agent
import magic.log.LogUtils

import cli.io.PrintUtils

import std.collection.ArrayList
import stdx.encoding.json.JsonValue

// Result of replaying a single step.
public enum StepResult {
    | CacheHit
    | Diverged(String)  // carries the actual result
    | Skipped(String)   // reason (e.g. "sub-agent", "tool not found")
    | Error(String)
}

// Summary of a full replay validation run.
public struct ReplayResult {
    public let systemPromptChanged: Bool
    public let firstDivergenceIndex: Option<Int64>  // None if all steps cached
    public let stepResults: Array<(Int64, String, StepResult)>  // (index, toolName, result)

    public init(
        systemPromptChanged!: Bool,
        firstDivergenceIndex!: Option<Int64>,
        stepResults!: Array<(Int64, String, StepResult)>
    ) {
        this.systemPromptChanged = systemPromptChanged
        this.firstDivergenceIndex = firstDivergenceIndex
        this.stepResults = stepResults
    }

    public prop allCached: Bool {
        get() {
            return !systemPromptChanged && firstDivergenceIndex.isNone()
        }
    }
}

// Replays a recorded trace by re-executing each tool call and comparing result hashes.
// Does NOT make model calls. Reports where the trajectory diverges.
public class Replayer {
    public static func validate(trace: AgentTrace, agent: Agent): ReplayResult {
        // Check system prompt
        let currentHash = computeHash(agent.systemPrompt)
        if (currentHash != trace.systemPromptHash) {
            PrintUtils.printLine("[replay] System prompt changed — all steps would diverge from step 0")
            return ReplayResult(
                systemPromptChanged: true,
                firstDivergenceIndex: Some(0),
                stepResults: []
            )
        }
        PrintUtils.printLine("[replay] System prompt: unchanged")

        let results = ArrayList<(Int64, String, StepResult)>()
        var firstDivergence: Option<Int64> = None

        for (step in trace.steps) {
            let result = validateStep(step, agent)
            results.add((step.index, step.toolName, result))

            match (result) {
                case StepResult.CacheHit =>
                    PrintUtils.printLine("[replay] step ${step.index}: cache hit  (${step.toolName})")
                case StepResult.Diverged(_) =>
                    PrintUtils.printLine("[replay] step ${step.index}: DIVERGED   (${step.toolName})")
                    if (firstDivergence.isNone()) {
                        firstDivergence = Some(step.index)
                    }
                case StepResult.Skipped(reason) =>
                    PrintUtils.printLine("[replay] step ${step.index}: skipped    (${step.toolName}) — ${reason}")
                case StepResult.Error(msg) =>
                    PrintUtils.printLine("[replay] step ${step.index}: error      (${step.toolName}) — ${msg}")
                    if (firstDivergence.isNone()) {
                        firstDivergence = Some(step.index)
                    }
            }
        }

        return ReplayResult(
            systemPromptChanged: false,
            firstDivergenceIndex: firstDivergence,
            stepResults: results.toArray()
        )
    }

    private static func validateStep(step: ToolStepRecord, agent: Agent): StepResult {
        // Skip sub-agent re-execution to avoid expensive model calls
        if (step.isSubAgentCall) {
            return StepResult.Skipped("sub-agent — skipped to avoid model calls")
        }

        // Look up tool
        let toolOpt = agent.toolManager.findTool(step.toolName)
        if (toolOpt.isNone()) {
            return StepResult.Error("tool '${step.toolName}' not found in agent")
        }
        let tool = toolOpt.getOrThrow()

        // Parse args
        let args = try {
            JsonValue.fromStr(step.toolArgsJson).asObject().getFields()
        } catch (ex: Exception) {
            return StepResult.Error("failed to parse args: ${ex.message}")
        }

        // Re-execute
        let actualResult = try {
            tool.invoke(args).content
        } catch (ex: Exception) {
            return StepResult.Error("tool threw: ${ex.message}")
        }

        // Compare
        let actualHash = computeHash(actualResult)
        if (actualHash == step.toolResultHash) {
            return StepResult.CacheHit
        } else {
            return StepResult.Diverged(actualResult)
        }
    }
}
