package cli.core.config

import std.fs.{canonicalize, exists, Path, Directory}

protected class CliConfig {
    private static const DOT_DIR_NAME = ".magic-cli"

    private static var _dotDir: Option<Path> = None

    /**
     * All generated files are stored under a hidden directory
     */
    private static prop dotDir: Path {
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
}