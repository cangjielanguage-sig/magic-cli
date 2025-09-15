package cli

import magic.config.Config
import magic.log.LogUtils

import cli.core.config.CliConfig
import cli.io.{InputUtils, PrintUtils}
import cli.core.tools.fs_utils.writeFileBasic

import std.fs.{exists, File, Path, Directory}
import std.regex.Regex

import magic.utils.readFile

import cli.core.tools.FSToolset

private func setConfig(): Unit {
    Config.logFile = CliConfig.logFile.toString()
    Config.logLevel = "DEBUG"
    Config.modelRequestDir = CliConfig.dotDir.join("model-requests").toString()
    Config.enableModelToolCall = true
    // Tokenizer needs the tiktoken file in the Magic directory
    let magicPath = Path(Config.env['MAGIC_PATH'].getOrThrow({=> Exception("MAGIC_PATH not set")}))
    Config.resourceDir = magicPath.join("resource").toString()
    // Set your API key in the .env file
    let envInfo = Config.env.load(Path("./.env"))
    LogUtils.info(envInfo)
}

main(args: Array<String>): Int64 {
    if (!parseArgs(args)) {
        printHelp()
        return 0
    }
    setConfig()

    // Enter the raw input mode, the exiting will be called in atExit
    InputUtils.enterRawMode()

    // Initialize the global context
    let context = CliContext()
    if (CliConfig.noninteractive)
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
