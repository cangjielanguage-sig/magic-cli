package cli.core.config

import magic.dsl.jsonable
import magic.jsonable.*
import magic.log.LogUtils

import std.collection.{HashMap, ArrayList, filter, collectArray, map}
import std.fs.{File, Path, exists}

import stdx.encoding.json.*

@jsonable
protected class CliSetting {
    /**
     * The programming language setting for the CLI.
     */
    protected var language: String = "unknown"

    /**
     * The MCP server configurations.
     */
    protected var mcpServers: Option<JsonObject> = None

    /**
     * The chat model to use
     */
    protected var model: String = "ark:kimi-k2-250905"

    /**
     * Fast model for auxiliary tasks in hybrid mode
     */
    protected var fastModel: Option<String> = Some("ark:doubao-1-5-pro-32k-250115")

    /**
     * Fallback models to use when primary model fails
     */
    protected var fallbackModels: Array<String> = [] // Disable fallback models by default
    // ["moonshot:kimi-k2-0905-preview", "zhipuai:glm-4.5"]

    /**
     * Temperature agents will use
     */
    protected var temperature: Float64 = 1.0

    /**
     * Whether to enable data collection for telemetry and analytics
     */
    protected var collectData: Bool = false

    /**
     * Number of days to retain log files (default: 7 days)
     */
    protected var logRetentionDays: Int64 = 7

    /**
     * Maximum number of log files to keep (default: 100 files)
     */
    protected var logMaxFiles: Int64 = 100
}

protected class CliSettingManager {
    private static prop settingFilePath: Path {
        get() {
            return CliConfig.dotDir.join("settings.json")
        }
    }

    /**
     * Standard Json does not support comments,
     * we add // as Json comment.
     */
    private static func loadJsonFile(path: Path): String {
        return String.join(
            String.fromUtf8(File.readFrom(path)).split("\n") |>
                filter { line => !line.trimAscii().startsWith("//") } |>
                collectArray,
            delimiter: "\n"
        )
    }

    private static var _setting: Option<CliSetting> = None

    protected static mut prop setting: CliSetting {
        get() {
            if (let Some(value) <- _setting) {
                return value
            }
            let setting = CliSettingManager.load()
            _setting = Some(setting)
            return setting
        }
        set(v) {
            _setting = v
            CliSettingManager.save()
        }
    }

    private static func load(): CliSetting {
        if (!exists(settingFilePath)) {
            LogUtils.info("Setting file not found at ${settingFilePath}")
            return CliSetting()
        }

        try {
            let content = loadJsonFile(settingFilePath)
            let jsonValue = JsonValue.fromStr(content)
            return CliSetting.fromJsonValue(jsonValue)
        } catch (ex: JsonableException) {
            LogUtils.info("Setting file is not a valid JSON object")
        } catch (ex: JsonException) {
            LogUtils.info("Setting file is not a valid JSON object")
        } catch (ex: Exception) {
            LogUtils.error("Failed to load setting file: ${ex}")
        }
        return CliSetting()
    }

    /**
     * Save setting to file
     */
    protected static func save(): Bool {
        try {
            let jsonStr = CliSettingManager.setting.toJsonValue().toJsonString()
            File.writeTo(settingFilePath, jsonStr.toArray())
            return true
        } catch (ex: Exception) {
            LogUtils.error("Failed to save setting file: ${ex}")
            return false
        }
    }
}