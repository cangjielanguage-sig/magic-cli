package cli

import magic.config.Config

import cli.core.config.CliConfig
import cli.io.{InputUtils, PrintUtils}
import cli.app.CliApp

main(args: Array<String>): Int64 {
   // Enter the raw input mode, the exiting will be called in atExit
    InputUtils.enterRawMode()

    // Parse the command line arguments and set the config
    if (!parseArgsAndSetConfig(args)) {
        printHelp()
        return 0
    }

    // Start the setting guideline when first time to run
    initSettingGuideline()

    // Initialize the app context
    let app = CliApp()
    if (CliConfig.nonInteractive) {
        app.startNonInteractive(CliConfig.nonInteractivePrompt)
        return 0
    } else {
        app.startInteractive()
    }
    return 0
}
