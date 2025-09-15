package cli.core.config

import std.fs.*
import std.io.readToEnd
import magic.log.LogUtils

protected class CliConfig {
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
            CliConfig.dotDir.join("abc.log")
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
    public static prop uerRuleFile: Path {
        get() {
            CliConfig.dotDir.join("MAGIC.md")
        }
    }

    /**
     * Whether agent runs autonomously, i.e., tools will be be confirmed by users
     */
    public static var auto: Bool = false

    /**
     * The chat model to use
     */
    public static var model: String = "ark:kimi-k2-250711"

    /**
     * Fallback models to use when primary model fails
     */
    public static var fallbackModels: Array<String> = ["moonshot:kimi-k2-0905-preview", "zhipuai:glm-4.5"]
    
    /**
     * Enable model fallback functionality
     */
    public static var enableFallback: Bool = true

    /**
     * Maximum number of models to try
     */
    public static var maxFallbackAttempts: Int64 = 3

    /**
     * Fast model for auxiliary tasks in hybrid mode
     */
    public static var hybridFastModel: String = "ark:doubao-1-5-pro-32k-250115"

    /**
     * Enable hybrid mode (use fast model for auxiliary tasks)
     */
    public static var hybridMode: Bool = false

    /**
     * The prompt when running magic-cli in detach mode
     */
    public static var detach: Bool = false
    public static var detachPrompt: String = ""
    public static var printInfoSavingDir: Path = Path("")

    /**
    * language in [Cangjie, General]
    */
    public static var language: String = 'General'

    public static prop userRules: String {
        get() {
            let ruleFile = uerRuleFile
            if (exists(ruleFile)) {
                String.fromUtf8(readToEnd(File(ruleFile, OpenMode.Read)))    
            } else {
                ""
            }
        }
    }
}