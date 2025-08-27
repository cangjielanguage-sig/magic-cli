package cli.core.config

import std.fs.{canonicalize, exists, Path, Directory}

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
     * The history file of user-agent conversation
     */
    public static prop conversationFile: Path {
        get() {
            CliConfig.dotDir.join("conversation.history")
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
    * language in [Cangjie, General]
    */
    public static var language: String = 'General'
}