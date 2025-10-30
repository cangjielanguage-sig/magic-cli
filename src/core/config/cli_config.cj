package cli.core.config

import magic.core.model.ChatModel
import magic.model.ModelManager
import magic.log.LogUtils

import std.fs.*
import std.io.readToEnd
import std.collection.{map, collectArray}
import std.time.DateTime

protected class CliConfig {
    /**
     * The version of Cangjie Magic
     */
    public static const version = "0.1.1"

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
     * The log file of Cangjie Magic
     */
    public static prop logFile: Path {
        get() {
            let time = DateTime.now().format("yyyy_MM_dd-HH_mm_ss_SSS")
            CliConfig.dotDir.join("${time}.log")
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
    public static var _model: Option<ChatModel> = None
    public static prop model: ChatModel {
        get() {
            if (let Some(m) <- _model) {
                return m
            }
            setModel(CliSettingManager.setting.model)
            return _model.getOrThrow()
        }
    }

    public static func setModel(model: String): Unit {
        let m = ModelManager.createChatModel(model)
        m.maxTokens = ModelTokenLimits.getMaxTokensLimit(model)
        _model = m
    }

    /**
     * Fast model for auxiliary tasks in hybrid mode
     */
    public static var _fastModel: Option<ChatModel> = None

    public static prop fastModel: Option<ChatModel> {
        get() {
            if (let Some(m) <- _fastModel) {
                return m
            }
            if (let Some(m) <- CliSettingManager.setting.fastModel) {
                _fastModel = ModelManager.createChatModel(m)
            }
            return _fastModel
        }
    }

    public static func setFastModel(model: String): Unit {
        _fastModel = ModelManager.createChatModel(model)
    }

    /**
     * Fallback models to use when primary model fails
     */
    private static var _fallbackModels: Array<ChatModel> = []
    public static prop fallbackModels: Array<ChatModel> {
        get() {
            if (_fallbackModels.isEmpty()) {
                _fallbackModels = CliSettingManager.setting.fallbackModels |>
                    map { model => ModelManager.createChatModel(model) } |>
                    collectArray
            }
            return _fallbackModels
        }
    }

    public static func setFallbackModels(models: Array<String>): Unit {
        _fallbackModels = models |>
            map { model => ModelManager.createChatModel(model) } |>
            collectArray
    }

    /**
     * The prompt when running magic-cli in noninteractive mode
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
}