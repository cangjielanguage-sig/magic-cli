package cli

import magic.config.Config
import magic.log.LogUtils
import magic.utils.readFile
import magic.model.ModelManager

import cli.core.config.{CliConfig, CliSettingManager}
import cli.io.PrintUtils
import cli.core.model.ModelTokenLimits

import std.collection.{ArrayList, map, collectArray}
import std.argopt.{parseArguments, ArgumentSpec, ArgumentMode, ArgumentParseException}
import std.time.*
import std.fs.*
import std.convert.Parsable

enum ParseArgsResult {
    | Continue
    | Exit
    | Sandbox
}

func printHelp(): Unit {
    PrintUtils.printLine("Magic Cli")
    PrintUtils.printLine("  --auto            The agent runs autonomously")
    PrintUtils.printLine("  --language, -l    Specify languages in [Cangjie, General(Default)]")
    PrintUtils.printLine("  --model <model>   Set the chat model")
    PrintUtils.printLine("  --fast-model      Set the fast model, which also enables hybrid mode (use fast model for auxiliary tasks)")
    PrintUtils.printLine("  --fallback-models <models>  Set fallback models (comma-separated)")
    PrintUtils.printLine("  --collect-data    Enable data collection for telemetry and analytics")
    PrintUtils.printLine("  --sandbox         Enable sandbox mode (default: false)")
    PrintUtils.printLine("  --temperature, -t Set the temperature for the model (default: 1.0)")
    PrintUtils.printLine("  --prompt <prompt>, -p <prompt>  Set the prompt and run magic-cli in the non-interactive mode")
    PrintUtils.printLine("  --prompt-file <file>            Set the prompt from a file and run magic-cli in the non-interactive mode")
    PrintUtils.printLine("  --output-format <format>        Set the output format for non-interactive mode: plain | colorful (default: colorful)")
    PrintUtils.printLine("  --log-level <level>  Set the log level (default: DEBUG)")
    PrintUtils.printLine("  --subagent-dir <dir>  Add the subagent search directories (comma-separated)")
    PrintUtils.printLine("  --command-dir <dir>   Add the command search directories (comma-separated)")
    PrintUtils.printLine("  --default-model-input-limit <limit>  Set the default input token limit for the model (default: 128 * 1024)")
    PrintUtils.printLine("  --default-model-output-limit <limit>  Set the default output token limit for the model (default: 32 * 1024)")
    PrintUtils.printLine("  --disable-model-tool-call   Disable the model tool call (default: false)")
    PrintUtils.printLine("  --enable-lsp-tool    Enable LSP tools (default: false)")
    PrintUtils.printLine("  --version, -v        Print the version of magic-cli")
    PrintUtils.printLine("  --help, -h           Print this help message")
}

/**
 * Parse the command line arguments
 */
func parseArgsAndSetConfig(args: Array<String>): ParseArgsResult {
    let argSpecs = [
        Long("auto", NoValue),
        Long("model", RequiredValue),
        Long("fast-model", RequiredValue),
        Long("fallback-models", RequiredValue),
        Long("collect-data", NoValue),
        Long("sandbox", NoValue),
        Full("language", r"l", RequiredValue),
        Long("subagent-dir", RequiredValue),
        Long("command-dir",  RequiredValue),
        Full("help", r"h", NoValue),
        Full("version", r"v", NoValue),
        Full("prompt", r"p", RequiredValue),
        Long("prompt-file", RequiredValue),
        Long("output-format", RequiredValue),
        Full("temperature", r"t", RequiredValue),
        Long("log-level", RequiredValue),
        Long("default-model-input-limit", RequiredValue),
        Long("default-model-output-limit", RequiredValue),
        Long("disable-model-tool-call", NoValue),
        Long("enable-lsp-tool", NoValue)
    ]
    let result = try {
        parseArguments(args, argSpecs)
    } catch (ex: ArgumentParseException) {
        PrintUtils.printLine(ex.message)
        return ParseArgsResult.Exit
    }
    if (result.options.contains("help") || result.options.contains("h")) {
        printHelp()
        return ParseArgsResult.Exit
    }
    if (result.options.contains("version") || result.options.contains("v")) {
        PrintUtils.printLine(CliConfig.version)
        return ParseArgsResult.Exit
    }

    // Log level must be set first
    if (let Some(level) <- result.options.get("log-level")) {
        Config.logLevel = level
    } else {
        Config.logLevel = "INFO"
    }
    // Log file must be set together with the log level
    Config.logFile = CliConfig.logFile.toString()

    // Clean up old log files based on retention policy
    CliConfig.cleanupLogs()

    // Set your API key in the .env file
    let envInfo = Config.env.load(Path("./.env"))
    LogUtils.info(envInfo)

    // Now, we can start the sandbox because it will inherits environment variables
    if (result.options.contains("sandbox")) {
        return ParseArgsResult.Sandbox
    }

    // Set Magic settings
    Config.modelRequestDir = CliConfig.dotDir.join("model-requests").toString()
    Config.enableModelToolCall = !result.options.contains("disable-model-tool-call")
    Config.enableParallelToolCall = false
    Config.httpReadWriteTimeout = 600000 // ms

    if (result.options.contains("subagent-dir")) {
        let option = result.options.get("subagent-dir").getOrThrow()
        for (dir in option.trimAscii().split(",")) {
            if (exists(dir)) {
                CliConfig.subagentDirs.add(Path(dir))
            }
        }
    }

    if (result.options.contains("command-dir")) {
        let option = result.options.get("command-dir").getOrThrow()
        for (dir in option.trimAscii().split(",")) {
            if (exists(dir)) {
                CliConfig.commandDirs.add(Path(dir))
            }
        }
    }

    // Set Magic-Cli settings
    if (result.options.contains("auto")) {
        CliConfig.auto = true
    }

    if (result.options.contains("collect-data")) {
        CliConfig.collectData = true
    }

    // Mark that we need to update the setting file
    var changeSetting = false

    // Initialize the main model
    if (let Some(model) <- result.options.get("model")) {
        CliConfig.model = model
        CliSettingManager.setting.model = model
        changeSetting = true
    } else {
        CliConfig.model = CliSettingManager.setting.model
    }

    if (let Some(model) <- result.options.get("fast-model")) {
        CliConfig.fastModel = model
        CliSettingManager.setting.fastModel = model
        changeSetting = true
    }

    // Set fallback models if provided
    if (let Some(modelsStr) <- result.options.get("fallback-models")) {
        let models = modelsStr.split(",") |>
            map { model => model.trimAscii() } |>
            collectArray
        CliConfig.fallbackModels = models
        CliSettingManager.setting.fallbackModels = models
        changeSetting = true
    }

    if (let Some(inputLimit) <- result.options.get("default-model-input-limit")) {
        try {
            let inputLimit = Int64.parse(inputLimit)
            CliConfig.defaultModelInputLimit = inputLimit
            CliSettingManager.setting.defaultModelInputLimit = inputLimit
            changeSetting = true
        } catch (ex: IllegalArgumentException) {
            PrintUtils.printLine("Failed to parse default-model-input-limit: ${ex.message}")
            return ParseArgsResult.Exit
        }
    } else {
        CliConfig.defaultModelInputLimit = CliSettingManager.setting.defaultModelInputLimit
    }

    if (let Some(outputLimit) <- result.options.get("default-model-output-limit")) {
        try {
            let outputLimit = Int64.parse(outputLimit)
            CliConfig.defaultModelOutputLimit = outputLimit
            CliSettingManager.setting.defaultModelOutputLimit = outputLimit
            changeSetting = true
        } catch (ex: IllegalArgumentException) {
            PrintUtils.printLine("Failed to parse default-model-output-limit: ${ex.message}")
            return ParseArgsResult.Exit
        }
    } else {
        CliConfig.defaultModelOutputLimit = CliSettingManager.setting.defaultModelOutputLimit
    }

    if (let Some(temperature) <- result.options.get("temperature")) {
        try {
            let temperature = Float64.parse(temperature)
            CliConfig.temperature = temperature
            CliSettingManager.setting.temperature = temperature
            changeSetting = true
        } catch (ex: IllegalArgumentException) {
            PrintUtils.printLine("Failed to parse temperature: ${ex.message}")
            return ParseArgsResult.Exit
        }
    } else {
        CliConfig.temperature = CliSettingManager.setting.temperature
    }

    if (result.options.contains("prompt-file")) {
        let promptFile = result.options.get("prompt-file").getOrThrow()
        if (exists(promptFile)) {
            let content = readFile(Path(promptFile))
            CliConfig.nonInteractive = true
            CliConfig.auto = true
            CliConfig.nonInteractivePrompt = content
        } else {
            LogUtils.error("Failed to read prompt file: ${promptFile}")
            return ParseArgsResult.Exit
        }
    }

    // It can override the prompt file
    if (result.options.contains("prompt") || result.options.contains("p")) {
        let prompt = result.options.get("prompt").getOrDefault { result.options.get("p").getOrThrow() }
        CliConfig.nonInteractive = true
        CliConfig.auto = true
        CliConfig.nonInteractivePrompt = prompt
    }

    if (let Some(format) <- result.options.get("output-format")) {
        if (format == "colorful") {
            CliConfig.nonInteractiveOutputFormat = "colorful"
        } else {
            CliConfig.nonInteractiveOutputFormat = "plain"
        }
    }

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

    if (result.options.contains("collect-data")) {
        CliConfig.collectData = true
        CliSettingManager.setting.collectData = true
        changeSetting = true
    } else {
        CliConfig.collectData = CliSettingManager.setting.collectData
    }

    if (result.options.contains("enable-lsp-tool")) {
        CliConfig.enableLSPTool = true
    }

    // Save the settings if any change
    if (changeSetting) {
        CliSettingManager.save()
    }
    return ParseArgsResult.Continue
}
