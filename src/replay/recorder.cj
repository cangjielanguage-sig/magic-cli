package cli.replay

import magic.core.agent.Agent
import magic.core.message.{ChatRound, Message}
import magic.tool.AgentAsTool
import magic.log.LogUtils

import std.collection.ArrayList
import std.time.DateTime
import stdx.encoding.json.JsonValue

// Extracts an AgentTrace from a completed ChatRound.
//
// Steps in chatRound.steps follow the ReAct pattern: each action message
// (<action>JSON</action>) is immediately followed by an observation message
// (<observation>result</observation>). We pair them up to build ToolStepRecords.
public class Recorder {
    public static func extract(
        chatRound: ChatRound,
        taskPrompt: String,
        agent: Agent
    ): AgentTrace {
        let systemPromptHash = computeHash(agent.systemPrompt)
        let records = ArrayList<ToolStepRecord>()
        var stepIndex: Int64 = 0

        // Walk the step messages and pair action+observation
        var pendingAction: Option<String> = None  // raw action JSON content

        for (msg in chatRound.steps) {
            let content = msg.content

            if (let Some(actionContent) <- extractTagContent(content, "action")) {
                // Found an action — remember it for the next observation
                pendingAction = actionContent
            } else if (let Some(obsContent) <- extractTagContent(content, "observation")) {
                // Found an observation — pair with the pending action
                if (let Some(actionJson) <- pendingAction) {
                    if (let Some(record) <- buildRecord(stepIndex, actionJson, obsContent, agent)) {
                        records.add(record)
                        stepIndex++
                    }
                    pendingAction = None
                }
            }
            // Thought / Answer / other tags are skipped — they don't need replay
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
    private static func buildRecord(
        index: Int64,
        actionJson: String,
        obsContent: String,
        agent: Agent
    ): Option<ToolStepRecord> {
        try {
            let parsed = JsonValue.fromStr(actionJson)
            let toolName = jsonGetString(parsed, "name").getOrDefault { "" }
            if (toolName.isEmpty()) {
                LogUtils.error("[record] step ${index}: action JSON has no 'name' field")
                return None
            }

            // Serialize the arguments object for storage
            let argsJson = if (let Some(argsVal) <- jsonGetValue(parsed, "arguments")) {
                argsVal.toJsonString()
            } else {
                "{}"
            }

            // Detect whether this tool is a sub-agent call
            var isSubAgent = false
            if (let Some(t) <- agent.toolManager.findTool(toolName)) {
                if (t is AgentAsTool) {
                    isSubAgent = true
                }
            }

            let hash = computeHash(obsContent)
            return ToolStepRecord(
                index: index,
                toolName: toolName,
                toolArgsJson: argsJson,
                toolResult: obsContent,
                toolResultHash: hash,
                isSubAgentCall: isSubAgent
            )
        } catch (ex: Exception) {
            LogUtils.error("[record] step ${index}: failed to parse action JSON '${actionJson}': ${ex.message}")
            return None
        }
    }
}
