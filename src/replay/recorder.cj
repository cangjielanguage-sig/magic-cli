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
public class Recorder {
    public static func extract(
        chatRound: ChatRound,
        taskPrompt: String,
        agent: Agent
    ): AgentTrace {
        let systemPromptHash = computeHash(agent.systemPrompt)
        let records = ArrayList<ToolStepRecord>()
        var stepIndex: Int64 = 0

        var pendingAction: Option<String> = None

        for (msg in chatRound.steps) {
            let content = msg.content

            if (msg.role == MessageRole.Assistant) {
                // Action step: try XML tag first (text mode), then use raw content (tool-call mode)
                let actionContent = extractTagContent(content, "action") ?? content.trimAscii()
                if (!actionContent.isEmpty()) {
                    pendingAction = actionContent
                }
            } else if (msg.role == MessageRole.User) {
                // Observation step: try XML tag first (text mode), then use raw content (tool-call mode)
                let obsContent = extractTagContent(content, "observation") ?? content.trimAscii()
                if (let Some(actionJson) <- pendingAction) {
                    if (let Some(record) <- buildRecord(stepIndex, actionJson, obsContent, agent)) {
                        records.add(record)
                        stepIndex++
                    }
                    pendingAction = None
                }
            }
            // System messages and other roles are skipped
        }

        // Warn about orphaned action (action with no following observation)
        if (let Some(_) <- pendingAction) {
            LogUtils.error("[record] Orphaned action at end of chatRound — step dropped")
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

    // Parse one action+observation pair into a ToolStepRecord.
    // Strips ```json...``` code fences before JSON parsing (text mode wraps JSON in fences).
    private static func buildRecord(
        index: Int64,
        actionJson: String,
        obsContent: String,
        agent: Agent
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

            let hash = computeHash(ToolResultNormalizer.normalize(toolName, rawResult))
            return ToolStepRecord(
                index: index,
                toolName: toolName,
                toolArgsJson: argsJson,
                toolResult: rawResult,
                toolResultHash: hash,
                isSubAgentCall: isSubAgent
            )
        } catch (ex: Exception) {
            LogUtils.error("[record] step ${index}: failed to parse action '${actionJson}': ${ex.message}")
            return None
        }
    }

    // Strip ```lang ... ``` code fences — text mode wraps the action JSON in markdown fences.
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
