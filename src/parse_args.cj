package cli

import cli.core.config.CliConfig
import cli.io.PrintUtils

import std.collection.ArrayList
import std.argopt.{parseArguments, ArgumentSpec, ArgumentMode, ArgumentParseException}

func printHelp(): Unit {
    PrintUtils.printLine("Magic Cli")
    PrintUtils.printLine("  --auto            The agent runs autonomously")
    PrintUtils.printLine("  --language, -l    Specify languages in [Cangjie, General(Default)]")
    PrintUtils.printLine("  --model <model>   Set the chat model")
    PrintUtils.printLine("  --help, -h        Print this help message")
}

/**
 * Parse the command line arguments
 */
func parseArgs(args: Array<String>): Bool {
    let argSpecs = [
        Long("auto", NoValue),
        Long("model", RequiredValue),
        Full("language", r"l", RequiredValue),
        Full("help", r"h", NoValue)
    ]
    let result = try {
        parseArguments(args, argSpecs)
    } catch (ex: ArgumentParseException) {
        PrintUtils.printLine(ex.message)
        return false
    }
    if (result.options.contains("help") || result.options.contains("h")) {
        return false
    }
    if (result.options.contains("auto")) {
        CliConfig.auto = true
    }
    if (let Some(model) <- result.options.get("model")) {
        CliConfig.model = model
    }
    if (let Some(language) <- result.options.get("language") && language.toAsciiUpper() == 'CANGJIE') {
        CliConfig.language = 'Cangjie'
    } else if (let Some(language) <- result.options.get("l") && language.toAsciiUpper() == 'CANGJIE') {
        CliConfig.language = 'Cangjie'
    } else {
        CliConfig.language = 'General'
    }
    return true
}
