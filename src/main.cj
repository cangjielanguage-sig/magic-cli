package cli

import magic.config.Config
import magic.log.LogUtils

import cli.core.config.CliConfig
import cli.io.{InputUtils, PrintUtils}
import cli.app.CliApp
import cli.sandbox.startSandbox

import std.collection.{filter, collectArray}
import std.env.getVariable

@When[os == "Windows"]
import magic.utils.winGetArgs

@When[os == "Windows"]
main(): Int64 {
    // On Windows, we cannot use main(args: Array<String>) because
    // the standard library has a bug when parsing Unicode command line arguments.
    let args = winGetArgs()
    return cliMain(args)
}

@When[os != "Windows"]
main(args: Array<String>): Int64 {
    return cliMain(args)
}

func cliMain(args: Array<String>): Int64 {
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
    LogUtils.debug(CliConfig.toString())

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
