package cli

import magic.config.Config

import cli.core.config.{CliConfig, CliSettingManager}
import cli.io.PrintUtils

import std.collection.{ArrayList, map, collectArray}
import std.argopt.{parseArguments, ArgumentSpec, ArgumentMode, ArgumentParseException}
import std.time.*
import std.fs.*
import std.convert.Parsable

func printHelp(): Unit {
    PrintUtils.printLine("Magic Cli")
    PrintUtils.printLine("  --auto            The agent runs autonomously")
    PrintUtils.printLine("  --language, -l    Specify languages in [Cangjie, General(Default)]")
    PrintUtils.printLine("  --model <model>   Set the chat model")
    PrintUtils.printLine("  --fast-model      Set the fast model, which also enables hybrid mode (use fast model for auxiliary tasks)")
    PrintUtils.printLine("  --fallback-models <models>  Set fallback models (comma-separated)")
    PrintUtils.printLine("  --temperature, -t Set the temperature for the model (default: 1.0)")
    PrintUtils.printLine("  --prompt <prompt>, -p <prompt>  Set the prompt and run magic-cli in the noninteractive mode")
    PrintUtils.printLine("  --log-level <level>  Set the log level (default: DEBUG)")
    PrintUtils.printLine("  --help, -h           Print this help message")
}

/**
 * Parse the command line arguments
 */
func parseArgs(args: Array<String>): Bool {
    let argSpecs = [
        Long("auto", NoValue),
        Long("model", RequiredValue),
        Long("fast-model", RequiredValue),
        Long("fallback-models", RequiredValue),
        Full("language", r"l", RequiredValue),
        Full("help", r"h", NoValue),
        Full("prompt", r"p", RequiredValue),
        Full("temperature", r"t", RequiredValue),
        Long("log-level", RequiredValue)
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

    // Log level must be set first
    if (let Some(level) <- result.options.get("log-level")) {
        Config.logLevel = level
    } else {
        Config.logLevel = "DEBUG"
    }
    // Log file must be set together with the log level
    Config.logFile = CliConfig.logFile.toString()

    if (result.options.contains("auto")) {
        CliConfig.auto = true
    }
    if (let Some(model) <- result.options.get("model")) {
        CliConfig.setModel(model)
    }
    if (let Some(model) <- result.options.get("fast-model")) {
        CliConfig.setFastModel(model)
    }
    if (let Some(modelsStr) <- result.options.get("fallback-models")) {
        let models = modelsStr.split(",") |>
            map { model => model.trimAscii() } |>
            collectArray
        CliConfig.setFallbackModels(models)
    }
    if (let Some(temperature) <- result.options.get("temperature")) {
        try {
            CliConfig.temperature = Float64.parse(temperature)
        } catch (ex: IllegalArgumentException) {
            PrintUtils.printLine("Failed to parse temperature: ${ex.message}")
            return false
        }
    }
    if (result.options.contains("prompt") || result.options.contains("p")) {
        let prompt = result.options.get("prompt").getOrDefault { result.options.get("p").getOrThrow() }
        CliConfig.nonInteractive = true
        CliConfig.auto = true
        CliConfig.nonInteractivePrompt = prompt
        CliConfig.printInfoSavingDir = Path("test").join(DateTime.now().toUnixTimeStamp().toMilliseconds().toString())
    }

    var changeSetting = false

    if (let Some(language) <- result.options.get("language")) {
        CliConfig.language = language.toAsciiLower()
        CliSettingManager.setting.language = CliConfig.language
        changeSetting = true
    } else if (let Some(language) <- result.options.get("l")) {
        CliConfig.language = language.toAsciiLower()
        CliSettingManager.setting.language = CliConfig.language
        changeSetting = true
    } else {
        CliConfig.language = CliSettingManager.setting.language
    }

    if (let Some(model) <- result.options.get("model")) {
        CliSettingManager.setting.model = model
        changeSetting = true
    }
    if (let Some(model) <- result.options.get("fast-model")) {
        CliSettingManager.setting.fastModel = model
        changeSetting = true
    }
    if (let Some(models) <- result.options.get("fallback-models")) {
        CliSettingManager.setting.fallbackModels = CliConfig.fallbackModels |>
            map { model => model.fullName } |>
            collectArray
        changeSetting = true
    }
    if (let Some(temp) <- result.options.get("temperature")) {
        CliSettingManager.setting.temperature = CliConfig.temperature
        changeSetting = true
    }
    if (changeSetting) {
        CliSettingManager.save()
    }
    return true
}
