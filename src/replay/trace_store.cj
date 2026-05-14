package cli.replay

import magic.log.LogUtils

import cli.core.config.CliConfig

import std.fs.{Path, File, exists, Directory}
import stdx.encoding.json.JsonValue

public class TraceStore {
    // Save a trace to .magic-cli/traces/<name>.json (overwrites any existing file).
    public static func save(trace: AgentTrace, name: String): Unit {
        ensureTracesDir()
        let path = tracePath(name)

        try {
            let json = trace.toJsonValue().toJsonString()
            File.writeTo(path, json.toArray())
        } catch (ex: Exception) {
            LogUtils.error("[replay] Failed to save trace: ${ex.message}")
            throw ex
        }
    }

    // Load a trace by name. Returns None if not found.
    public static func load(name: String): Option<AgentTrace> {
        let path = tracePath(name)
        if (!exists(path)) {
            return None
        }
        try {
            let json = File.readFrom(path) |> String.fromUtf8 |> JsonValue.fromStr
            return AgentTrace.fromJsonValue(json)
        } catch (ex: Exception) {
            LogUtils.error("[replay] Failed to load trace '${name}': ${ex.message}")
            return None
        }
    }

    public static func tracePath(name: String): Path {
        return CliConfig.traceDir.join("${name}.json")
    }

    private static func ensureTracesDir(): Unit {
        let dir = CliConfig.traceDir
        if (!exists(dir)) {
            Directory.create(dir, recursive: true)
        }
    }
}
