package cli.core.commands

import magic.dsl.*
import magic.prelude.*
import magic.jsonable.*
import magic.agent.ConversationAgent
import magic.log.LogUtils
import cli.core.config.CliConfig
import cli.utils.PrintUtils
import std.fs.{exists, Directory, Path, File}
import std.collection.{HashMap, ArrayList}
import stdx.encoding.json.*

@jsonable
protected class CustomCommand {
    let description: String
    let prompt: String
}

protected class CustomCommandManager {
    private var commands: HashMap<String, CustomCommand> = HashMap<String, CustomCommand>()
    private let commandsDir: Path

    public init() {
        this.commandsDir = CliConfig.dotDir.join("commands")
        loadCommands()
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
                if (entry.isRegular() && entry.name.endsWith(".json")) {
                    let commandName = entry.name.replace(".json", "")
                    if (let Some(command) <- loadCommand(entry.path)) {
                        commands[commandName] = command
                        LogUtils.info("Loaded custom command: ${commandName}")
                    }
                }
            }
        } catch (e: Exception) {
            LogUtils.error("Failed to load commands: ${e.message}")
        }
    }

    /**
     * Load a single command from JSON file
     */
    private func loadCommand(filePath: Path): Option<CustomCommand> {
        try {
            let content = String.fromUtf8(File.readFrom(filePath))
            let jsonValue = JsonValue.fromStr(content)
            let command = CustomCommand.fromJsonValue(jsonValue)

            if (command.description.isEmpty() || command.prompt.isEmpty()) {
                LogUtils.error("Command ${filePath}: description and prompt cannot be empty")
                return None
            }

            return Some(command)
        } catch (e: Exception) {
            LogUtils.error("Failed to load command from ${filePath}: ${e.message}")
            return None
        }
    }

    /**
     * Execute a custom command
     */
    private func executeCommand(name: String, args: String, agent: ConversationAgent): ?AgentResponse {
        if (let Some(command) <- commands.get(name)) {
            let finalPrompt = command.prompt.replace("$ARGS", args)
            let response = agent.chat(AgentRequest(finalPrompt))
            return response
        } else {
            return AgentResponse("❌ Custom command '${name}' not found. Use '/cmd list' to see available commands.")
        }
    }

    /**
     * List all available commands
     */
    private func listCommands(): Unit {
        if (commands.isEmpty()) {
            println("No custom commands found. Create JSON files in ${commandsDir} to add commands.")
            return
        }

        PrintUtils.printTool("Custom Commands", "📋 Available custom commands:")
        for ((name, command) in commands) {
            println("  • ${name} - ${command.description}")
        }
        println("")
        println("Usage: /cmd:<name> [arguments]")
    }

    /**
     * Show help for a specific command
     */
    private func showHelp(name: String): Unit {
        if (let Some(command) <- commands.get(name)) {
            PrintUtils.printTool("Command Help", "📖 ${name}")
            println("Description: ${command.description}")
            println("Usage: /cmd:${name} [your arguments]")
            println("Prompt template:")
            println("  ${command.prompt}")
        } else {
            println("❌ Command '${name}' not found.")
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
    public func handleCommand(input: String, agent: ConversationAgent): ?AgentResponse {
        // Check for /cmd:command format
        if (input.contains(":")) {
            // /cmd:name args...
            if (let Some(colonIndex) <- input.indexOf(":")) {
                let remaining = input[colonIndex + 1..]
                let cmdParts = remaining.split(" ")
                if (!cmdParts.isEmpty()) {
                    let cmdName = cmdParts[0]
                    let args = if (cmdParts.size > 1) {
                        remaining[cmdName.size..].trimAscii()
                    } else {
                        ""
                    }
                    return executeCommand(cmdName, args, agent)
                }
            }
        }

        let parts = input.split(" ")

        if (parts.size == 1 || (parts.size == 2 && parts[1] == "list")) {
            // /cmd or /cmd list
            listCommands()
        } else if (parts.size >= 2 && parts[1] == "help") {
            // /cmd help <name>
            if (parts.size >= 3) {
                showHelp(parts[2])
            } else {
                println("Usage: /cmd help <command-name>")
            }
        } else if (parts.size >= 2 && parts[1] == "reload") {
            // /cmd reload
            reloadCommands()
        } else {
            println("Unknown command. Available options:")
            println("  /cmd list          - List all commands")
            println("  /cmd help <name>   - Show command help")
            println("  /cmd reload        - Reload commands")
            println("  /cmd:<name> [args] - Execute command")
        }
        return None
    }
}
