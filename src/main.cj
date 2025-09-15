package cli

import magic.config.Config
import magic.log.LogUtils

import cli.core.config.CliConfig
import cli.core.context.CliContext
import cli.io.{InputUtils, PrintUtils}
import cli.core.tools.fs_utils.writeFileBasic

import std.fs.{exists, File, Path, Directory}
import std.regex.Regex

private func loadEnvFile(): Unit {
    let path = Path("./.env")
    if (!exists(path)) {
        return
    }
    try {
        let content = String.fromUtf8(File.readFrom(path))
        let regex = Regex("^\\s*([\\w.]+)\\s*=\\s*(\"[^\"]*\"|'[^']*'|[^#]*)\\s*(?:#.*)?$")
        for (line in content.split("\n")) {
            if (let Some(md) <- regex.find(line, group: true)) {
                let key = md.matchString(1).trimAscii()
                var value = md.matchString(2).trimAscii()
                // strip quote marks if necessary
                if (value.startsWith('"')) {
                    value = value.replace('"', "")
                } else if (value.startsWith("'")) {
                    value = value.replace("'", "")
                }
                LogUtils.info("[ENV Set] ${key}=${value}")
                Config.env[key] = value
            }
        }
    } catch (e: Exception) {
        LogUtils.error("Failed to read .env file")
    }
}

private func setConfig(): Unit {
    Config.logFile = CliConfig.logFile.toString()
    Config.logLevel = "DEBUG"
    Config.modelRequestDir = CliConfig.dotDir.join("model-requests").toString()
    Config.enableModelToolCall = true
    let magicPath = Path(Config.env['MAGIC_PATH'].getOrThrow({=> Exception("MAGIC_PATH not set")}))
    Config.resourceDir = magicPath.join("resource").toString()
    // Set your API key in the .env file
    loadEnvFile()
}

main(args: Array<String>): Int64 {
    if (!parseArgs(args)) {
        printHelp()
        return 0
    }
    setConfig()

    // register global context
    let context = CliContext()
    context.registerHooks()
    if (CliConfig.noninteractive) {
        if (!exists(CliConfig.printInfoSavingDir)) {
            Directory.create(CliConfig.printInfoSavingDir, recursive: true)
        }
        let commandSavingPath = CliConfig.printInfoSavingDir.join("command_args.txt")
        writeFileBasic(commandSavingPath, String.join(args, delimiter: " "))
        let input = CliConfig.noninteractivePrompt
        processInput(input, context)
        return 0
    }

    PrintUtils.printWelcome()
    // Simplified event loop
    while (true) {
        let input = InputUtils.getUserInput()
        if (input.isEmpty()) {
            continue
        }

        // Process input and check if we should continue
        if (!processInput(input, context)) {
            break  // Exit requested
        }
    }
    return 0
}
