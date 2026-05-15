package cli.replay

import magic.core.agent.Agent
import magic.tool.AgentAsTool
import magic.log.LogUtils

import cli.io.PrintUtils

import std.collection.ArrayList
import stdx.encoding.json.JsonValue

// Result of replaying a single step.
public enum StepResult {
    | CacheHit
    | Diverged(String)  // carries the actual result or divergence description
    | Skipped(String)   // reason (e.g. "no sub-trace -- re-record to enable Stage 2")
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

// Dry-run validator: re-executes each recorded tool call and compares result hashes.
// Sub-agent steps with embedded sub-traces are validated recursively (Stage 2).
// Reports where the trajectory diverges from the recording.
//
// NOTE: Stage 2 validates sub-agent internal steps but does NOT resume live model
// calls from the divergence point. That is the full incremental replay described
// in design.md and is HIGH priority future work -- see todo.md "Go Live from Divergence".
public class Replayer {
    public static func validate(trace: AgentTrace, agent: Agent): ReplayResult {
        // Check system prompt
        let currentHash = computeHash(agent.systemPrompt)
        if (currentHash != trace.systemPromptHash) {
            PrintUtils.printLine("[replay] System prompt changed -- all steps would diverge from step 0")
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
                    PrintUtils.printLine("[replay] step ${step.index}: skipped    (${step.toolName}) -- ${reason}")
                case StepResult.Error(msg) =>
                    PrintUtils.printLine("[replay] step ${step.index}: error      (${step.toolName}) -- ${msg}")
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
        if (step.isSubAgentCall) {
            // Stage 2: recursively validate the nested sub-agent trace.
            if (let Some(subTrace) <- step.subTrace) {
                if (let Some(t) <- agent.toolManager.findTool(step.toolName)) {
                    if (let Some(aat) <- (t as AgentAsTool)) {
                        let subResult = Replayer.validate(subTrace, aat.innerAgent)
                        if (subResult.allCached) {
                            return StepResult.CacheHit
                        } else if (subResult.systemPromptChanged) {
                            return StepResult.Diverged("sub-agent system prompt changed")
                        } else {
                            let idx = subResult.firstDivergenceIndex.getOrDefault { 0 }
                            return StepResult.Diverged("sub-agent diverged at step ${idx}")
                        }
                    } else {
                        return StepResult.Error("'${step.toolName}' is not an AgentAsTool")
                    }
                } else {
                    return StepResult.Error("sub-agent tool '${step.toolName}' not found")
                }
            } else {
                // No sub-trace: recorded with Stage 1 (pre-Stage 2) -- fall back to skip.
                return StepResult.Skipped("no sub-trace -- re-record to enable Stage 2 validation")
            }
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
        let actualHash = computeHash(ToolResultNormalizer.normalize(step.toolName, actualResult))
        if (actualHash == step.toolResultHash) {
            return StepResult.CacheHit
        } else {
            return StepResult.Diverged(actualResult)
        }
    }
}
