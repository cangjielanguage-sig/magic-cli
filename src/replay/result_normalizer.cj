package cli.replay

import std.collection.{ArrayList, filter, collectArray}

// Strips self-induced noise from tool results before hashing.
//
// "Self-induced" means the change is caused by the replay mechanism's own file writes
// (trace file, log file), not by a real environment change. Only patterns that meet this
// bar receive a normalization rule — everything else is reported as DIVERGED and left to
// the user or a future semantic-equivalence mechanism.
//
// Current rules:
//   listDirectory — strip the Windows `dir` disk-summary line ("N Dir(s)  X bytes free")
//   because the trace and log files written by the replay mechanism change disk free space
//   on every run, regardless of whether anything in the project changed.
//
// See design-docs/agent-implemental-test/result-normalizer-design.md for full rationale.
public class ToolResultNormalizer {
    public static func normalize(toolName: String, result: String): String {
        if (toolName == "listDirectory") {
            return normalizeListDirectory(result)
        }
        return result
    }

    // Strip the Windows `dir` summary line that reports total directory count and disk
    // free space.  Example line: "   2 Dir(s)  696,857,165,824 bytes free"
    // This line changes on every disk write, including the trace/log writes done by the
    // replay mechanism itself, so it is always a self-induced false divergence.
    private static func normalizeListDirectory(result: String): String {
        let lines = result.split("\n")
        let filtered = lines
            |> filter { line: String => !line.contains("bytes free") }
            |> collectArray
        return String.join(filtered, delimiter: "\n")
    }
}
