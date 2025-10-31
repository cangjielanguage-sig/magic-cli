package cli.core.commands

import magic.dsl.*
import magic.prelude.*
import magic.jsonable.*
import magic.agent.ConversationAgent
import magic.log.LogUtils
import magic.utils.readFile

import cli.core.config.CliConfig
import cli.io.{PrintUtils, CompletionListUtils, wrapBox, WithColor, Theme, AnsiColor, Align}

import std.fs.{exists, Directory, Path, File}
import std.collection.{HashMap, ArrayList, enumerate, filter, map, collectArray}
import stdx.encoding.json.*

@jsonable
protected class CustomCommand {
    let description: String
    let prompt: String
}

protected class CustomCommandManager {
    private var commands = HashMap<String, CustomCommand>()
    private let commandsDir = CliConfig.dotDir.join("commands")

    public init() {
        registerBuiltinCommands()
        this.loadCommands()
    }

    /**
     * Load all command configurations from the commands directory
     */
    private func loadCommands(): Unit {
        this.commands.clear()

        if (!exists(commandsDir)) {
            LogUtils.info("Commands directory does not exist: ${commandsDir}")
            return
        }

        try {
            for (entry in Directory.readFrom(commandsDir)) {
                if (!entry.isRegular()) {
                    continue
                }
                // Support two approaches to define custom commands:
                // 1. As a JSON file
                // 2. As a markdown file
                if (entry.path.extensionName == "json") {
                    let commandName = entry.path.fileNameWithoutExtension
                    if (let Some(command) <- loadCommandFromJson(entry.path)) {
                        this.addCommand(commandName, command)
                    }
                } else if (entry.path.extensionName == "md") {
                    let commandName = entry.path.fileNameWithoutExtension
                    if (let Some(command) <- loadCommandFromMd(entry.path)) {
                        this.addCommand(commandName, command)
                    }
                }
            }
        } catch (ex: Exception) {
            LogUtils.error("Failed to load commands: ${ex.message}")
            LogUtils.error(ex)
        }
    }

    private func addCommand(name: String, command: CustomCommand): Unit {
        // Check for conflicts with built-in commands
        if (isBuiltinCommand(name)) {
            LogUtils.info("Custom command '${name}' conflicts with built-in commands', skipping")
            return
        }
        if (this.commands.contains(name)) {
            LogUtils.info("Custom command '${name}' conflicts with existing commands', skipping")
            return
        }

        commands[name] = command
        CompletionListUtils.registerCompletionItem("/${name}")
        LogUtils.info("Loaded custom command: ${name}")
    }

    /**
     * Load a single command from JSON file
     */
    private func loadCommandFromJson(filePath: Path): Option<CustomCommand> {
        try {
            let content = readFile(filePath)
            let jsonValue = JsonValue.fromStr(content)
            let command = CustomCommand.fromJsonValue(jsonValue)

            if (command.description.isEmpty() || command.prompt.isEmpty()) {
                LogUtils.error("Command ${filePath}: description and prompt cannot be empty")
                return None
            }

            return Some(command)
        } catch (ex: Exception) {
            LogUtils.error("Failed to load command from ${filePath}: ${ex.message}")
            LogUtils.error(ex)
            return None
        }
    }

    /**
     * Load a single command from Markdown file
     */
    private func loadCommandFromMd(filePath: Path): Option<CustomCommand> {
        let content = readFile(filePath)
        let lines = content.split("\n")
        var pivot = -1
        for ((idx, line) in enumerate(lines)) {
            if (line.startsWith("---")) {
                pivot = idx
                break
            }
        }
        if (pivot == -1) {
            return CustomCommand(description: "", prompt: content)
        }
        let prompt = String.join(lines[pivot+1..], delimiter: "\n")
        for (line in lines[0..pivot]) {
            let items = line.split(":")
            if (items.size == 2 && items[0].trimAscii() == "description") {
                return CustomCommand(description: items[1].trimAscii(), prompt: prompt)
            }
        }
        return CustomCommand(description: "", prompt: prompt)
    }

    /**
     * Build the full user query by replacing $ARGS in the command prompt template
     */
    private func buildUserRequest(name: String, args: String): Option<String> {
        if (let Some(command) <- commands.get(name)) {
            return command.prompt.replace("$ARGS", args)
        } else {
            PrintUtils.printLine("❌ Custom command '${name}' not found. Use '/cmd list' to see available commands.")
            return None
        }
    }

    /**
     * List all available commands
     */
    private func listCommands(): Unit {
        if (commands.isEmpty()) {
            PrintUtils.printLine("No custom commands found. Create JSON files in ${commandsDir} to add commands.")
            return
        }

        PrintUtils.printTool("Custom Commands", "📋 Available custom commands:")
        for ((name, command) in commands) {
            PrintUtils.printLine("  • ${name} - ${command.description}")
        }
        PrintUtils.printLine("")
        PrintUtils.printLine("Usage: /<name> [arguments]")
    }

    /**
     * Show help for a specific command
     */
    private func showHelp(name: String): Unit {
        if (let Some(command) <- commands.get(name)) {
            PrintUtils.printTool("Command Help", "📖 ${name}")
            PrintUtils.printLine("Description: ${command.description}")
            PrintUtils.printLine("Usage: /${name} [your arguments]")
            PrintUtils.printLine("Prompt template:")
            PrintUtils.printLine("  ${command.prompt}")
        } else {
            PrintUtils.printLine("❌ Command '${name}' not found.")
        }
    }

    /**
     * Reload all commands
     */
    private func reloadCommands(): Unit {
        let oldSize = commands.size
        loadCommands()
        let newSize = commands.size
        PrintUtils.printTool("Command Reload", "✅ Reloaded ${newSize} custom commands (was ${oldSize})")
    }

    /**
     * Handle custom command input parsing and execution
     */
    public func handleCommand(input: String): Option<String> {
        // Check for direct /<command> format
        // /<command> args...
        let parts = input.split(" ") |>
            filter { x => !x.isEmpty() } |>
            map { x => x.trimAscii() } |>
            collectArray
        let cmdName = parts[0][1..] // Remove the leading '/'
        let args = String.join(parts[1..], delimiter: " ")

        // /cmd xxx
        if (cmdName == "cmd") {
            if (args.isEmpty() || args == "list") {
                // /cmd or /cmd list
                listCommands()
            } else if (parts.size >= 2 && parts[1] == "help") {
                // /cmd help <name>
                if (parts.size >= 3) {
                    showHelp(parts[2])
                } else {
                    PrintUtils.printLine("Usage: /cmd help <command-name>")
                }
            } else if (args == "reload") {
                // /cmd reload
                reloadCommands()
            } else {
                PrintUtils.printLine("Unknown command. Available options:")
                PrintUtils.printLine("  /cmd list          - List all commands")
                PrintUtils.printLine("  /cmd help <name>   - Show command help")
                PrintUtils.printLine("  /cmd reload        - Reload commands")
                PrintUtils.printLine("  /<name> [args]     - Execute command (new)")
            }
            return None
        } else {
            // Custom command
            return buildUserRequest(cmdName, args)
        }
    }

    static public func printBuiltinCommands() {
        let message = wrapBox(
            "Available Builtin Commands".withColor(Theme.PRIMARY),
            lines: BUILTIN_COMMANDS |>
                map { commandInfo: (String, String, Array<String>) =>
                    let cmd = "/${commandInfo[0]}".padEnd(15).withColor(AnsiColor.YELLOW)
                    let separator = " ║ ".withColor(Theme.MUTED)
                    let message = "- ${commandInfo[1]}".withColor(Theme.MUTED)
                    return " ${cmd}${separator}${message}"
                } |>
                collectArray,
            width: 60,
            align: Align.Center
        )
        PrintUtils.printLine(message)
    }

    /**
     * Check if input is a built-in command
     */
    protected static func isBuiltinCommand(name: String): Bool {
        for (builtin in BUILTIN_COMMANDS |> map { info => info[0] }) {
            if (name == builtin) {
                return true
            }
        }
        return false
    }
}
