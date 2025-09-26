package cli

import magic.config.Config
import magic.log.LogUtils

import cli.core.config.{CliConfig, CliSettingManager}
import cli.io.{InputUtils, PrintUtils}
import cli.core.tools.fs_utils.writeFileBasic

import std.fs.{exists, File, Path, Directory}
import std.regex.Regex

func initSettingGuideline(): Unit {
    // Load the settings
    let setting = CliSettingManager.setting
    if (setting.language == "unknown" && CliConfig.language == "unknown") {
        let index = InputUtils.getOptions(
            ["Cangjie", "Others"],
            prompt: "Which programming language will be used (for this project). Default: Cangjie."
        ) ?? 0
        match (index) {
            case 0 =>
                setting.language = "cangjie"
                CliSettingManager.save()
            case 1 =>
                setting.language = "general"
                CliSettingManager.save()
            case _ => throw UnsupportedException("Unreachable")
        }
    }
}