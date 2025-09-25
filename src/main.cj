package cli

import magic.config.Config
import magic.log.LogUtils

import cli.core.config.CliConfig
import cli.io.{InputUtils, PrintUtils}
import cli.core.tools.fs_utils.writeFileBasic

import std.fs.{exists, File, Path, Directory}

private func setConfig(): Unit {
    Config.logFile = CliConfig.logFile.toString()
    Config.modelRequestDir = CliConfig.dotDir.join("model-requests").toString()
    Config.enableModelToolCall = true
    Config.enableParallelToolCall = false
    Config.enableJsonRetry = false
    Config.httpReadWriteTimeout = 600000 // ms
    // Set your API key in the .env file
    let envInfo = Config.env.load(Path("./.env"))
    LogUtils.info(envInfo)
}

main(args: Array<String>): Int64 {
    // Enter the raw input mode, the exiting will be called in atExit
    InputUtils.enterRawMode()

    // Start the setting guideline when first time to run
    // Note that the complete settings of CliConfig are distributed across the following processes
    // Process 1:
    initSettingGuideline()
    // Process 2:
    if (!parseArgs(args)) {
        printHelp()
        return 0
    }
    // Process 3:
    setConfig()

    // Initialize the global context
    let context = CliContext()
    if (CliConfig.nonInteractive) {
        if (!exists(CliConfig.printInfoSavingDir)) {
            Directory.create(CliConfig.printInfoSavingDir, recursive: true)
        }
        let commandSavingPath = CliConfig.printInfoSavingDir.join("command_args.txt")
        writeFileBasic(commandSavingPath, String.join(args, delimiter: " "))
        let input = CliConfig.nonInteractivePrompt
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
