package cli.replay

import magic.core.agent.Agent
import magic.core.message.{Message, MessageList}
import magic.core.model.ChatRequest
import magic.core.tool.ToolRequest
import magic.tool.AgentAsTool
import magic.config.Config
import magic.log.LogUtils

import cli.io.PrintUtils

import std.collection.{ArrayList, HashMap}
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

// Replay engine: validates recorded tool call results and resumes live model
// execution from the first divergence point (Stage 3).
// Sub-agent steps are validated recursively (Stage 2).
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

    // Go-live replay: walk the trace, cache-hit steps feed history; at first divergence
    // call the model live and continue until the agent produces a final answer.
    // Falls back to dry-run for pre-Stage-3 traces that lack modelOutput.
    public static func replayLive(trace: AgentTrace, agent: Agent): Unit {
        let currentHash = computeHash(agent.systemPrompt)
        let systemPromptChanged = currentHash != trace.systemPromptHash
        if (systemPromptChanged) {
            PrintUtils.printLine("[replay] System prompt changed -- going live from step 0")
        } else {
            PrintUtils.printLine("[replay] System prompt: unchanged")
        }

        // Pre-Stage-3 traces have empty modelOutput → dry-run only
        let isOldTrace = trace.steps.size > 0 && trace.steps[0].modelOutput.isEmpty()
        if (isOldTrace) {
            PrintUtils.printLine("[replay] Trace missing modelOutput (pre-Stage-3) -- dry-run only (re-record to enable go-live)")
            let result = validate(trace, agent)
            PrintUtils.printLine("")
            if (result.allCached) {
                PrintUtils.printLine("[replay] Result: all ${trace.steps.size} step(s) cache-hit -- no divergence")
            } else if (result.systemPromptChanged) {
                PrintUtils.printLine("[replay] Result: system prompt changed -- full re-run needed")
            } else if (let Some(idx) <- result.firstDivergenceIndex) {
                PrintUtils.printLine("[replay] Result: diverged at step ${idx} -- re-record to enable go-live")
            }
            return
        }

        // Build initial conversation history from system prompt + task
        let history = MessageList()
        history.add(Message.system(agent.systemPrompt))
        history.add(Message.user(trace.taskPrompt))

        if (systemPromptChanged) {
            PrintUtils.printLine("[replay] Going live from step 0")
            PrintUtils.printLine("")
            goLive(agent, history, startStep: 0)
            return
        }

        // Walk steps: cache-hit → add to history; diverged → go live
        for (step in trace.steps) {
            match (validateStep(step, agent)) {
                case StepResult.CacheHit =>
                    PrintUtils.printLine("[replay] step ${step.index}: cache hit  (${step.toolName})")
                    history.add(Message.assistant(step.modelOutput))
                    history.add(Message.user(step.toolResultObserved))
                case StepResult.Diverged(_) =>
                    PrintUtils.printLine("[replay] step ${step.index}: DIVERGED   (${step.toolName})")
                    PrintUtils.printLine("[replay] Going live from step ${step.index}")
                    PrintUtils.printLine("")
                    goLive(agent, history, startStep: step.index)
                    return
                case StepResult.Error(msg) =>
                    PrintUtils.printLine("[replay] step ${step.index}: error      (${step.toolName}) -- ${msg}")
                    PrintUtils.printLine("[replay] Going live from step ${step.index}")
                    PrintUtils.printLine("")
                    goLive(agent, history, startStep: step.index)
                    return
                case StepResult.Skipped(_) =>
                    PrintUtils.printLine("[replay] step ${step.index}: skipped    (${step.toolName})")
                    PrintUtils.printLine("[replay] Going live from step ${step.index} (old sub-trace, re-record to skip)")
                    PrintUtils.printLine("")
                    goLive(agent, history, startStep: step.index)
                    return
            }
        }

        PrintUtils.printLine("")
        PrintUtils.printLine("[replay] Result: all ${trace.steps.size} step(s) cache-hit -- no divergence detected")
    }

    // Manual tool loop: call the model live with the given history, invoke each tool it
    // selects, and repeat until the model produces a final answer (no tool call).
    private static func goLive(agent: Agent, history: MessageList, startStep!: Int64): Unit {
        let tools = agent.toolManager.tools
        let maxSteps = 500
        var liveStep: Int64 = 0

        while (liveStep < maxSteps) {
            let chatResp = try {
                agent.model.create(ChatRequest(history, tools: tools))
            } catch (ex: Exception) {
                PrintUtils.printLine("[replay] go-live: model call failed: ${ex.message}")
                return
            }

            let content = chatResp.message.content

            if (let Some((toolName, toolArgs)) <- parseToolCall(content, chatResp.toolRequests)) {
                let globalStep = startStep + liveStep
                PrintUtils.printLine("[replay] go-live step ${globalStep}: ${toolName}")

                // Invoke the tool (or inject an error observation so the model can recover)
                var toolResult = ""
                if (let Some(tool) <- agent.toolManager.findTool(toolName)) {
                    try {
                        toolResult = tool.invoke(toolArgs).content
                    } catch (ex: Exception) {
                        PrintUtils.printLine("[replay] go-live: '${toolName}' threw: ${ex.message}")
                        toolResult = "[tool error] ${ex.message}"
                    }
                } else {
                    toolResult = "[tool error] tool '${toolName}' not found in agent"
                    PrintUtils.printLine("[replay] go-live: ${toolResult}")
                }

                // Append to history in the same format the framework uses internally
                if (Config.enableModelToolCall) {
                    let callJson = ToolRequest(name: toolName, args: toolArgs).toJsonValue().toJsonString()
                    history.add(Message.assistant(callJson))
                    history.add(Message.user(toolResult))
                } else {
                    history.add(Message.assistant(content))
                    history.add(Message.user("<observation>${toolResult}</observation>"))
                }

                liveStep++
            } else if (!content.isEmpty()) {
                PrintUtils.printLine("[replay] go-live: agent finished")
                PrintUtils.printLine("")
                PrintUtils.printLine(content)
                return
            } else {
                PrintUtils.printLine("[replay] go-live: model returned empty response -- stopping")
                return
            }
        }

        PrintUtils.printLine("[replay] go-live: exceeded step limit (${maxSteps})")
    }

    // Returns (toolName, toolArgs) from a model response.
    // Checks structured toolRequests first (tool-call mode), then parses content (text mode).
    private static func parseToolCall(
        content: String,
        toolRequests: Array<ToolRequest>
    ): Option<(String, HashMap<String, JsonValue>)> {
        if (!toolRequests.isEmpty()) {
            let req = toolRequests[0]
            return Some((req.name, req.args))
        }
        let actionContent = extractTagContent(content, "action") ?? content.trimAscii()
        let cleanJson = stripCodeFences(actionContent)
        if (cleanJson.isEmpty()) {
            return None
        }
        try {
            let parsed = JsonValue.fromStr(cleanJson)
            let toolName = jsonGetString(parsed, "name").getOrDefault { "" }
            if (toolName.isEmpty()) {
                return None
            }
            let argsMap = if (let Some(argsVal) <- jsonGetValue(parsed, "arguments")) {
                argsVal.asObject().getFields()
            } else {
                HashMap<String, JsonValue>()
            }
            return Some((toolName, argsMap))
        } catch (_: Exception) {
            return None
        }
    }
}
