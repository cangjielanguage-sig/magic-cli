package cli

import cli.core.config.CliConfig
import cli.io.PrintUtils

import std.collection.ArrayList
import std.argopt.{parseArguments, ArgumentSpec, ArgumentMode, ArgumentParseException}
import std.time.*
import std.fs.*

func printHelp(): Unit {
    PrintUtils.printLine("Magic Cli")
    PrintUtils.printLine("  --auto            The agent runs autonomously")
    PrintUtils.printLine("  --language, -l    Specify languages in [Cangjie, General(Default)]")
    PrintUtils.printLine("  --model <model>   Set the chat model")
    PrintUtils.printLine("  --hybrid          Enable hybrid mode (use fast model for auxiliary tasks)")
    PrintUtils.printLine("  --prompt <prompt>, -p <prompt>  Set the prompt and run magic-cli in the noninteractive mode")
    PrintUtils.printLine("  --help, -h        Print this help message")
}

/**
 * Parse the command line arguments
 */
func parseArgs(args: Array<String>): Bool {
    let argSpecs = [
        Long("auto", NoValue),
        Long("model", RequiredValue),
        Long("hybrid", NoValue),
        Full("language", r"l", RequiredValue),
        Full("help", r"h", NoValue),
        Full("prompt", r"p", RequiredValue)
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
    if (result.options.contains("hybrid")) {
        CliConfig.hybridMode = true
    }
    if (let Some(model) <- result.options.get("model")) {
        CliConfig.model = model
    }
    if (result.options.contains("prompt") || result.options.contains("p")) {
        let prompt = result.options.get("prompt").getOrDefault { result.options.get("p").getOrThrow() }
        CliConfig.noninteractive = true
        CliConfig.auto = true
        CliConfig.noninteractivePrompt = prompt
        CliConfig.printInfoSavingDir = Path("test").join(DateTime.now().toUnixTimeStamp().toMilliseconds().toString())
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
