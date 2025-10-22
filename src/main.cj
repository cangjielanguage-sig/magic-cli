package cli

import magic.config.Config

import cli.core.config.CliConfig
import cli.io.{InputUtils, PrintUtils}
import cli.app.CliApp
import cli.sandbox.startSandbox

import std.collection.{filter, collectArray}
import std.env.getVariable

main(args: Array<String>): Int64 {
   // Enter the raw input mode, the exiting will be called in atExit
    InputUtils.enterRawMode()

    // Parse the command line arguments and set the config
    match (parseArgsAndSetConfig(args)) {
        case ParseArgsResult.Exit => return 0
        case ParseArgsResult.Continue => ()
        case ParseArgsResult.Sandbox =>
            // Avoid running the sandbox inside a sandbox
            if (getVariable("MAGIC_CLI_IN_SANDBOX").isNone()) {
                // Remove the "--sandbox" argument from the cliArgs
                let cliArgs = args |> filter { arg => arg != "--sandbox" } |> collectArray
                return startSandbox(cliArgs)
            }
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
