package cli.core.config

import magic.core.model.ChatModel
import magic.model.ModelManager
import magic.log.LogUtils

import std.fs.*
import std.io.readToEnd
import std.collection.{map, collectArray, ArrayList}
import std.time.DateTime
import std.sort.*

protected class CliConfig {
    /**
     * The version of Magic Cli
     */
    public static const version = "0.1.3"

    private static const DOT_DIR_NAME = ".magic-cli"

    private static var _dotDir: Option<Path> = None

    /**
     * All generated files are stored under a hidden directory
     */
    public static prop dotDir: Path {
        get() {
            if (let Some(d) <- _dotDir) {
                return d
            }
            let path = CliConfig.cwd.join(DOT_DIR_NAME)
            if (!exists(path)) {
                Directory.create(path, recursive: true)
            }
            return path
        }
    }

    /**
     * The current working directory
     */
    public static prop cwd: Path {
        get() {
            return canonicalize(".")
        }
    }

    /**
     * The logs directory
     */
    public static prop logsDir: Path {
        get() {
            let path = CliConfig.dotDir.join("logs")
            if (!exists(path)) {
                Directory.create(path, recursive: true)
            }
            return path
        }
    }

    /**
     * The log file of Cangjie Magic
     */
    public static prop logFile: Path {
        get() {
            let time = DateTime.now().format("yyyy_MM_dd-HH_mm_ss_SSS")
            CliConfig.logsDir.join("${time}.log")
        }
    }

    /**
     * The plan todo.md file
     * Used by the plan tool
     */
    public static prop todoFile: Path {
        get() {
            CliConfig.dotDir.join("todo.md")
        }
    }

    /**
     * The history file of user inputs
     */
    public static prop readlineFile: Path {
        get() {
            CliConfig.dotDir.join("readline.history")
        }
    }

    /**
     * The user-agent conversation history directory
     */
    public static prop conversationHistoryDir: Path {
        get() {
            CliConfig.dotDir.join("conversation-history")
        }
    }

    /**
     * User Rules Config
     */
    public static prop magicMarkdownPath: Path {
        get() {
            CliConfig.cwd.join("MAGIC.md")
        }
    }

    /**
     * Whether agent runs autonomously, i.e., tools will be be confirmed by users
     */
    public static var auto: Bool = false

    /**
     * Whether to enable data collection for telemetry and analytics
     */
    public static var collectData: Bool = CliSettingManager.setting.collectData

    /**
     * Temperature agents will use
     */
    public static var temperature: Float64 = CliSettingManager.setting.temperature

    /**
     * The chat model to use
     */
    public static var _model: Option<String> = None
    public static mut prop model: String {
        get() {
            return _model.getOrThrow()
        }
        set(v) {
            _model = Some(v)
        }
    }

    /**
     * Fast model for auxiliary tasks in hybrid mode
     */
    public static var _fastModel: Option<String> = None

    public static mut prop fastModel: Option<String> {
        get() {
            if (let Some(m) <- _fastModel) {
                return m
            }
            if (let Some(m) <- CliSettingManager.setting.fastModel) {
                _fastModel = m
            }
            return _fastModel
        }

        set(v) {
            _fastModel = v
        }
    }

    /**
     * Fallback models to use when primary model fails
     */
    private static var _fallbackModels: Array<String> = []

    public static mut prop fallbackModels: Array<String> {
        get() {
            if (_fallbackModels.isEmpty()) {
                _fallbackModels = CliSettingManager.setting.fallbackModels
            }
            return _fallbackModels
        }

        set(v) {
            _fallbackModels = v
        }
    }

    /**
     * The prompt when running magic-cli in non-interactive mode
     */
    public static var nonInteractive: Bool = false
    public static var nonInteractivePrompt: String = ""

    /**
    * language in [cangjie, general, unknown]
    */
    public static var language: String = "unknown" // will be set during the arguments parsing

    public static prop userRules: String {
        get() {
            let ruleFile = magicMarkdownPath
            if (exists(ruleFile)) {
                String.fromUtf8(readToEnd(File(ruleFile, OpenMode.Read)))
            } else {
                ""
            }
        }
    }

    /**
     * Code compression
     */
    // When the number of characters of the code exceeds this threshold * LLM's content window * 4, the code will be compressed.
    // The reason we multiple by 4 is because 1 token has about 4 characters on average.
    public static var readFileThreshold: Float64 = 0.05
    public static var batchReadFilesThreshold: Float64 = 0.1

    /**
     * Clean up old log files based on retention policy
     * - Removes files older than logRetentionDays
     * - Keeps only the most recent logMaxFiles files
     */
    public static func cleanupLogs(): Unit {
        try {
            if (!exists(logsDir)) {
                return
            }

            let retentionDays = CliSettingManager.setting.logRetentionDays
            let maxFiles = CliSettingManager.setting.logMaxFiles

            var logFiles = ArrayList<Path>()
            for (entry in Directory.readFrom(logsDir)) {
                if (entry.isRegular() && entry.name.endsWith(".log")) {
                    logFiles.add(entry.path)
                }
            }

            if (logFiles.isEmpty()) {
                return
            }

            // Sort by file name (oldest first)
            sort(logFiles, by: { a, b => a.fileName.compare(b.fileName) })

            // Step 1: Delete files older than retention days
            let now = DateTime.now()
            var filesToKeep = ArrayList<Path>()

            for (filePath in logFiles) {
                try {
                    // Extract date from filename
                    let fileName = filePath.fileName
                    let parts = fileName.split("-")
                    if (parts.size >= 2) {
                        let datePart = parts[0].replace("_", "-")
                        let fileDate = DateTime.parse(datePart, "yyyy-MM-dd")
                        let age = now - fileDate
                        let ageDays = age.toDays()

                        if (ageDays > retentionDays) {
                            remove(filePath)
                            LogUtils.info("Deleted old log file: ${filePath}")
                            continue
                        }
                    }
                    filesToKeep.add(filePath)
                } catch (e: Exception) {
                    LogUtils.error("Failed to parse date for ${filePath}: ${e}")
                    filesToKeep.add(filePath) // Keep files we can't parse
                }
            }

            // Step 2: If still too many files, delete oldest ones
            if (filesToKeep.size > maxFiles) {
                let toDelete = filesToKeep.size - maxFiles
                for (i in 0..toDelete) {
                    let filePath = filesToKeep[i]
                    try {
                        remove(filePath)
                        LogUtils.info("Deleted excess log file: ${filePath}")
                    } catch (e: Exception) {
                        LogUtils.error("Failed to delete log file ${filePath}: ${e}")
                    }
                }
            }
        } catch (e: Exception) {
            LogUtils.error("Failed to cleanup logs: ${e}")
        }
    }
}