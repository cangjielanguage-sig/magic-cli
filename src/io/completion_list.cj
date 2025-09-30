package cli.io

import std.collection.{ArrayList, filter, enumerate, collectArray}

protected class CompletionListUtils {
    /**
     * Command definitions: (command_name, description:  [subcommands])
     * Commands without subcommands have empty array
     */
    protected static let COMMANDS: Array<(String, String, Array<String>)> = [
        ("/help", "Show this help message", []),
        ("/clear", "Clear conversation history", []),
        ("/compact", "Compact the conversation history", []),
        ("/memory", "Show MAGIC.md content", []),
        ("/init", "Initialize MAGIC.md for project", []),
        ("/exit", "Exit the program", []),
        ("/mcp", "Manage MCP tools", ["add", "add-sse", "remove", "list"]),
        ("/conversation", "Manage conversations", ["list", "save", "resume", "remove", "help"]),
        ("/cmd", "Manage customized commands", ["list", "reload", "help"])
    ]

    static let COMPLETION_LIST = ArrayList<String>()

    protected static func registerCompletionItem(item: String) {
        COMPLETION_LIST.add(item)
    }

    protected static func unregisterCompletionItem(item: String) {
        for ((idx, value) in enumerate(COMPLETION_LIST)) {
            if (value == item) {
                COMPLETION_LIST.remove(at: idx)
                break
            }
        }
    }
}

/**
 * Build completion list based on current input and cursor position
 * Supports both /commands and @paths (but @paths are disabled in shell mode)
*/
func buildCompletionList(input: String, cursor: Int64, isShellMode!: Bool = false): Option<Array<String>> {
    let text = input
    if (text.isEmpty()) {
        return None
    }
    // Completion list is disable for shell mode
    if (isShellMode) {
        return None
    }

    // Check for @path completion based on cursor position
    if (let Some((atIndex, pathStart, pathEnd, pathPrefix)) <- extractPathContext(text, cursor)) {
        let pathCompletions = getPathCompletionList(prefix: pathPrefix)
        if (pathCompletions.size > 0) {
            // For empty prefix (just "@"), show all files
            // For non-empty prefix, show paths that start with prefix but are different
            if (pathPrefix.isEmpty()) {
                return pathCompletions
            } else {
                return pathCompletions |>
                    filter { path => path.startsWith(pathPrefix) && path != pathPrefix } |>
                    collectArray
            }
        }
    }
    return buildCompletionListForCommand(text, cursor)
}

func buildCompletionListForCommand(text: String, cursor: Int64): Option<Array<String>> {
    // Check for /command completion (only at beginning and cursor at end)
    if (!text.startsWith("/") || cursor != text.size) {
        return None
    }

    let allCompletions = ArrayList<String>()

    let addCommandIfMatches = { command: String =>
        if (command.startsWith(text) && command != text) {
            allCompletions.add(command)
        }
    }

    // Generate all possible completions from command definitions
    for ((commandName, _commandDescription, subcommands) in CompletionListUtils.COMMANDS) {
        // Add the base command if it matches
        addCommandIfMatches(commandName)

        // Add subcommands if they match
        for (subcommand in subcommands) {
            let fullSubcommand = commandName + " " + subcommand
            addCommandIfMatches(fullSubcommand)
        }
    }
    // Last, add all registered items
    for (command in CompletionListUtils.COMPLETION_LIST) {
        addCommandIfMatches(command)
    }

    if (allCompletions.isEmpty()) {
        return None
    } else {
        return allCompletions.toArray()
    }
}