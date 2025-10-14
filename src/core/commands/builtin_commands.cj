package cli.core.commands

import cli.io.CompletionListUtils

import std.collection.ArrayList

/**
    * Command definitions: (command_name, description:  [subcommands])
    * Commands without subcommands have empty array
    */
protected let BUILTIN_COMMANDS: ArrayList<(String, String, Array<String>)> = ArrayList([
    ("help", "Show this help message", []),
    ("clear", "Clear conversation history", []),
    ("compact", "Compact the conversation history", []),
    ("memory", "Show MAGIC.md content", []),
    ("init", "Initialize MAGIC.md for project", []),
    ("exit", "Exit the program", []),
    ("status", "Show token status", []),
    ("mcp", "Manage MCP tools", ["add", "add-sse", "remove", "list"]),
    ("conversation", "Manage conversations", ["list", "save", "resume", "remove", "help"]),
    ("cmd", "Manage customized commands", ["list", "reload", "help"])
])

func registerBuiltinCommands(): Unit {
    for ((commandName, _commandDescription, subcommands) in BUILTIN_COMMANDS) {
        // Add the base command if it matches
        CompletionListUtils.registerCompletionItem("/${commandName}")

        // Add subcommands if they match
        for (subcommand in subcommands) {
            let fullSubcommand = "/${commandName} ${subcommand}"
            CompletionListUtils.registerCompletionItem(fullSubcommand)
        }
    }
}
