package cli.replay

import magic.core.agent.Agent
import magic.core.message.{ChatRound, Message, MessageRole}
import magic.tool.AgentAsTool
import magic.log.LogUtils

import std.collection.ArrayList
import std.time.DateTime
import stdx.encoding.json.JsonValue

// Extracts an AgentTrace from a completed ChatRound.
//
// With enableModelToolCall=true (the default), step messages carry no XML tags:
//   - Action:      MessageRole.Assistant, content = raw JSON {"name":..., "arguments":...}
//   - Observation: MessageRole.User,      content = raw tool result string
//
// With enableModelToolCall=false (text mode), the observation is wrapped in
// <observation>...</observation> and the action is a ```json...``` markdown block.
// Both formats are handled by trying tag extraction first and falling back to raw content.
//
// subCaptures: (ChatRound, Agent) pairs collected by SubAgentEndEvent handlers, in the
// same order as the sub-agent calls appear in chatRound. Each sub-agent step consumes
// one entry and embeds a recursively extracted AgentTrace (Stage 2).
public class Recorder {
    public static func extract(
        chatRound: ChatRound,
        taskPrompt: String,
        agent: Agent,
        subCaptures!: ArrayList<(ChatRound, Agent)> = ArrayList<(ChatRound, Agent)>()
    ): AgentTrace {
        let systemPromptHash = computeHash(agent.systemPrompt)
        let records = ArrayList<ToolStepRecord>()
        var stepIndex: Int64 = 0
        var subCaptureIdx: Int64 = 0

        var pendingAction: Option<String> = None
        var pendingModelOutput: Option<String> = None

        for (msg in chatRound.steps) {
            let content = msg.content

            if (msg.role == MessageRole.Assistant) {
                // Action step: try XML tag first (text mode), then use raw content (tool-call mode).
                // Store raw msg.content as modelOutput for go-live history reconstruction.
                let actionContent = extractTagContent(content, "action") ?? content.trimAscii()
                if (!actionContent.isEmpty()) {
                    pendingAction = actionContent
                    pendingModelOutput = content  // raw message, including any tags
                }
            } else if (msg.role == MessageRole.User) {
                // Observation step: extract content for hashing/parsing; keep raw msg.content
                // as toolResultObserved for go-live history reconstruction.
                let obsContent = extractTagContent(content, "observation") ?? content.trimAscii()
                if (let Some(actionJson) <- pendingAction) {
                    let rawModelOutput = pendingModelOutput.getOrDefault { actionJson }
                    // Consume the next sub-capture if this action is a sub-agent call
                    let subCapOpt = peekSubCapture(actionJson, agent, subCaptures, subCaptureIdx)
                    if (subCapOpt.isSome()) {
                        subCaptureIdx++
                    }
                    if (let Some(record) <- buildRecord(stepIndex, actionJson, obsContent, content, rawModelOutput, agent, subCapOpt)) {
                        records.add(record)
                        stepIndex++
                    }
                    pendingAction = None
                    pendingModelOutput = None
                }
            }
            // System messages and other roles are skipped
        }

        // Warn about orphaned action (action with no following observation)
        if (let Some(_) <- pendingAction) {
            LogUtils.error("[record] Orphaned action at end of chatRound -- step dropped")
        }

        let recordedAt = DateTime.now().format("yyyy-MM-dd'T'HH:mm:ss")
        return AgentTrace(
            agentName: agent.name,
            systemPromptHash: systemPromptHash,
            taskPrompt: taskPrompt,
            steps: records.toArray(),
            recordedAt: recordedAt
        )
    }

    // Returns the next sub-capture entry if the action targets a sub-agent tool,
    // without advancing the index (caller increments after confirming isSome).
    private static func peekSubCapture(
        actionJson: String,
        agent: Agent,
        subCaptures: ArrayList<(ChatRound, Agent)>,
        idx: Int64
    ): Option<(ChatRound, Agent)> {
        try {
            let cleanJson = stripCodeFences(actionJson)
            let parsed = JsonValue.fromStr(cleanJson)
            let toolName = jsonGetString(parsed, "name").getOrDefault { "" }
            if (toolName.isEmpty()) { return None }
            if (let Some(t) <- agent.toolManager.findTool(toolName)) {
                if (t is AgentAsTool && idx < subCaptures.size) {
                    return subCaptures[idx]
                }
            }
        } catch (_: Exception) { }
        return None
    }

    // Parse one action+observation pair into a ToolStepRecord.
    // Strips ```json...``` code fences before JSON parsing (text mode wraps JSON in fences).
    // obsContent:    extracted text between <observation> tags (or raw), used for re-invoke fallback.
    // rawObsContent: the raw msg.content of the User message, stored as toolResultObserved.
    // rawModelOutput: the raw msg.content of the Assistant message, stored as modelOutput.
    // subCapture: if this is a sub-agent step, contains the sub-agent's ChatRound and Agent
    // for recursive sub-trace extraction (Stage 2).
    private static func buildRecord(
        index: Int64,
        actionJson: String,
        obsContent: String,
        rawObsContent: String,
        rawModelOutput: String,
        agent: Agent,
        subCapture: Option<(ChatRound, Agent)>
    ): Option<ToolStepRecord> {
        try {
            let cleanJson = stripCodeFences(actionJson)
            let parsed = JsonValue.fromStr(cleanJson)
            let toolName = jsonGetString(parsed, "name").getOrDefault { "" }
            if (toolName.isEmpty()) {
                LogUtils.error("[record] step ${index}: action JSON has no 'name' field")
                return None
            }

            let argsJson = if (let Some(argsVal) <- jsonGetValue(parsed, "arguments")) {
                argsVal.toJsonString()
            } else {
                "{}"
            }

            var isSubAgent = false
            let toolOpt = agent.toolManager.findTool(toolName)
            if (let Some(t) <- toolOpt) {
                if (t is AgentAsTool) {
                    isSubAgent = true
                }
            }

            // Re-invoke the tool to get the pre-compaction raw result. The observation stored
            // in chatRound.steps may be an LLM-compacted summary (e.g. "...") when the raw
            // result exceeded Config.toolResultCompactThreshold. Re-invoking makes the recorder
            // symmetric with the replayer, which also calls tool.invoke() directly.
            //
            // Falls back to obsContent for tools that cannot be idempotently re-invoked (e.g.
            // write tools whose effect has already been applied) or if invocation fails.
            var rawResult = obsContent
            if (!isSubAgent) {
                if (let Some(t) <- toolOpt) {
                    try {
                        let toolArgs = JsonValue.fromStr(argsJson).asObject().getFields()
                        rawResult = t.invoke(toolArgs).content
                    } catch (ex: Exception) {
                        LogUtils.debug("[record] step ${index}: re-invoke '${toolName}' failed, using observed result: ${ex.message}")
                    }
                }
            }

            // For sub-agent steps, recursively extract the nested trace (Stage 2).
            var subTrace: Option<AgentTrace> = None
            if (isSubAgent) {
                if (let Some((subRound, subAgent)) <- subCapture) {
                    subTrace = Some(Recorder.extract(subRound, "", subAgent))
                } else {
                    LogUtils.debug("[record] step ${index}: sub-agent '${toolName}' -- no capture, Stage 1 fallback")
                }
            }

            let hash = computeHash(ToolResultNormalizer.normalize(toolName, rawResult))
            return ToolStepRecord(
                index: index,
                toolName: toolName,
                toolArgsJson: argsJson,
                toolResult: rawResult,
                toolResultHash: hash,
                toolResultObserved: rawObsContent,
                modelOutput: rawModelOutput,
                isSubAgentCall: isSubAgent,
                subTrace: subTrace
            )
        } catch (ex: Exception) {
            LogUtils.error("[record] step ${index}: failed to parse action '${actionJson}': ${ex.message}")
            return None
        }
    }

    // Strip ```lang ... ``` code fences -- text mode wraps the action JSON in markdown fences.
    private static func stripCodeFences(s: String): String {
        let trimmed = s.trimAscii()
        if (trimmed.startsWith("```")) {
            if (let Some(newline) <- trimmed.indexOf("\n", 0)) {
                let afterFence = trimmed[(newline + 1)..]
                if (let Some(closing) <- afterFence.lastIndexOf("```")) {
                    return afterFence[0..closing].trimAscii()
                }
                return afterFence.trimAscii()
            }
        }
        return trimmed
    }
}
