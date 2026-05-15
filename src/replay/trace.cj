package cli.replay

import std.collection.{ArrayList, map, collectArray}
import stdx.encoding.json.*

// Polynomial hash over UTF-8 bytes for change detection.
// Uses two independent bases to reduce collision probability.
public func computeHash(s: String): String {
    let MOD1: Int64 = 1_000_000_007
    let MOD2: Int64 = 998_244_353
    var h1: Int64 = 0
    var h2: Int64 = 0
    for (b in s.toArray()) {
        let v = Int64(b)
        h1 = (h1 * 31 + v) % MOD1
        h2 = (h2 * 37 + v) % MOD2
    }
    return "${h1}:${h2}"
}

// Extract the text between <tagName>...</tagName>.
// Returns None if the open tag is not found.
// Uses the LAST occurrence of the close tag so that tool results containing
// the close tag string (e.g., from reading HTML/XML files) are not truncated.
public func extractTagContent(content: String, tagName: String): Option<String> {
    let open = "<${tagName}>"
    let close = "</${tagName}>"
    if (let Some(start) <- content.indexOf(open, 0)) {
        let contentStart = start + open.size
        // Find the last occurrence of the close tag
        var lastEnd: Option<Int64> = None
        var searchFrom = contentStart
        while (true) {
            if (let Some(pos) <- content.indexOf(close, searchFrom)) {
                lastEnd = Some(pos)
                searchFrom = pos + 1
            } else {
                break
            }
        }
        if (let Some(end) <- lastEnd) {
            return content[contentStart..end].trimAscii()
        }
        // No close tag — take everything after the open tag
        return content[contentStart..].trimAscii()
    }
    return None
}

// One recorded tool call and its result.
// For sub-agent calls, subTrace holds the nested trace (Stage 2); None means old Stage-1 trace.
public struct ToolStepRecord {
    public let index: Int64
    public let toolName: String
    public let toolArgsJson: String   // JSON string of the arguments object
    public let toolResult: String     // full text returned by the tool
    public let toolResultHash: String // hash of toolResult for fast comparison
    public let isSubAgentCall: Bool
    public let subTrace: Option<AgentTrace>  // nested sub-agent trace (Stage 2)

    public init(
        index!: Int64,
        toolName!: String,
        toolArgsJson!: String,
        toolResult!: String,
        toolResultHash!: String,
        isSubAgentCall!: Bool,
        subTrace!: Option<AgentTrace> = None
    ) {
        this.index = index
        this.toolName = toolName
        this.toolArgsJson = toolArgsJson
        this.toolResult = toolResult
        this.toolResultHash = toolResultHash
        this.isSubAgentCall = isSubAgentCall
        this.subTrace = subTrace
    }

    public func toJsonValue(): JsonValue {
        let jo = JsonObject()
        jo.put("index", JsonInt(index))
        jo.put("toolName", JsonString(toolName))
        jo.put("toolArgsJson", JsonString(toolArgsJson))
        jo.put("toolResult", JsonString(toolResult))
        jo.put("toolResultHash", JsonString(toolResultHash))
        jo.put("isSubAgentCall", JsonBool(isSubAgentCall))
        if (let Some(t) <- subTrace) {
            jo.put("subTrace", t.toJsonValue())
        }
        return jo
    }

    public static func fromJsonValue(json: JsonValue): ToolStepRecord {
        let index = jsonGetInt(json, "index").getOrDefault { 0 }
        let toolName = jsonGetString(json, "toolName").getOrDefault { "" }
        let toolArgsJson = jsonGetString(json, "toolArgsJson").getOrDefault { "{}" }
        let toolResult = jsonGetString(json, "toolResult").getOrDefault { "" }
        let toolResultHash = jsonGetString(json, "toolResultHash").getOrDefault { "" }
        let isSubAgentCall = jsonGetBool(json, "isSubAgentCall").getOrDefault { false }
        let subTrace: Option<AgentTrace> = if (let Some(v) <- jsonGetValue(json, "subTrace")) {
            match (v.kind()) {
                case JsonKind.JsObject => Some(AgentTrace.fromJsonValue(v))
                case _ => None
            }
        } else {
            None
        }
        return ToolStepRecord(
            index: index,
            toolName: toolName,
            toolArgsJson: toolArgsJson,
            toolResult: toolResult,
            toolResultHash: toolResultHash,
            isSubAgentCall: isSubAgentCall,
            subTrace: subTrace
        )
    }
}

// Complete trace of a single agent task run.
public class AgentTrace {
    public let version: String
    public let agentName: String
    public let systemPromptHash: String
    public let taskPrompt: String
    public let steps: Array<ToolStepRecord>
    public let recordedAt: String

    public init(
        agentName!: String,
        systemPromptHash!: String,
        taskPrompt!: String,
        steps!: Array<ToolStepRecord>,
        recordedAt!: String
    ) {
        this.version = "1"
        this.agentName = agentName
        this.systemPromptHash = systemPromptHash
        this.taskPrompt = taskPrompt
        this.steps = steps
        this.recordedAt = recordedAt
    }

    public func toJsonValue(): JsonValue {
        let jo = JsonObject()
        jo.put("version", JsonString(version))
        jo.put("agentName", JsonString(agentName))
        jo.put("systemPromptHash", JsonString(systemPromptHash))
        jo.put("taskPrompt", JsonString(taskPrompt))
        jo.put("recordedAt", JsonString(recordedAt))
        let stepValues = steps |> map { s: ToolStepRecord => s.toJsonValue() } |> collectArray
        jo.put("steps", buildJsonArray(stepValues))
        return jo
    }

    public static func fromJsonValue(json: JsonValue): AgentTrace {
        let agentName = jsonGetString(json, "agentName").getOrDefault { "unknown" }
        let systemPromptHash = jsonGetString(json, "systemPromptHash").getOrDefault { "" }
        let taskPrompt = jsonGetString(json, "taskPrompt").getOrDefault { "" }
        let recordedAt = jsonGetString(json, "recordedAt").getOrDefault { "" }

        let steps = if (let Some(arr) <- jsonGetArray(json, "steps")) {
            arr.getItems() |>
                map { jv: JsonValue => ToolStepRecord.fromJsonValue(jv) } |>
                collectArray
        } else {
            Array<ToolStepRecord>()
        }

        return AgentTrace(
            agentName: agentName,
            systemPromptHash: systemPromptHash,
            taskPrompt: taskPrompt,
            steps: steps,
            recordedAt: recordedAt
        )
    }
}
