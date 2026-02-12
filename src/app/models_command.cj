package cli.app

import magic.config.Config
import magic.log.LogUtils

import cli.core.config.{CliConfig, CliSettingManager}
import cli.core.model.CliModelManager
import cli.io.{InputUtils, PrintUtils, WithColor, Theme, AnsiColor}

import std.collection.{ArrayList, map, filter, collectArray}
import std.fs.{Path, File, exists}

private struct ModelProviderPreset {
    ModelProviderPreset(
        let provider: String,
        let name: String,
        let apiKeyEnv: String,
        let baseURLEnv: String,
        let defaultBaseURL: String,
        let suggestedModels: Array<String>,
        let runtimeApiKeyEnv: String,
        let runtimeBaseURLEnv: String
    ) { }
}

private let PROVIDER_PRESETS = [
    ModelProviderPreset(
        "ark",
        "ARK Coding Plan",
        "ARK_API_KEY",
        "ARK_BASE_URL",
        "https://ark.cn-beijing.volces.com/api/coding/v3",
        ["ark-code-latest", "kimi-k2-250905"],
        "ARK_API_KEY",
        "ARK_BASE_URL"
    ),
    ModelProviderPreset(
        "moonshot",
        "Kimi Code",
        "MOONSHOT_API_KEY",
        "MOONSHOT_BASE_URL",
        "https://api.kimi.com/coding/v1",
        ["kimi-for-coding", "kimi-k2-0711-preview"],
        "MOONSHOT_API_KEY",
        "MOONSHOT_BASE_URL"
    ),
    ModelProviderPreset(
        "zhipuai",
        "GLM Coding Plan",
        "ZHIPU_API_KEY",
        "ZHIPU_BASE_URL",
        "https://open.bigmodel.cn/api/coding/paas/v4",
        ["glm-4.7", "glm-4.5"],
        "ZHIPU_API_KEY",
        "ZHIPU_BASE_URL"
    ),
    // ModelProviderPreset(
    //     "openai",
    //     "NVIDIA NIM",
    //     "NVIDIA_NIM_API_KEY",
    //     "NVIDIA_NIM_BASE_URL",
    //     "https://integrate.api.nvidia.com/v1/",
    //     ["minimaxai/minimax-m2.1", "z-ai/glm4.7"],
    //     "OPENAI_API_KEY",
    //     "OPENAI_BASE_URL"
    // ),
    ModelProviderPreset(
        "openai",
        "OpenAI Compatible",
        "OPENAI_API_KEY",
        "OPENAI_BASE_URL",
        "https://api.openai.com/v1",
        ["gpt-5", "gpt-5-mini", "gpt-4.1"],
        "OPENAI_API_KEY",
        "OPENAI_BASE_URL"
    ),
    ModelProviderPreset(
        "anthropic",
        "Anthropic Compatible",
        "ANTHROPIC_API_KEY",
        "ANTHROPIC_BASE_URL",
        "https://api.anthropic.com/v1",
        ["claude-sonnet-4-5", "claude-3-7-sonnet-latest"],
        "ANTHROPIC_API_KEY",
        "ANTHROPIC_BASE_URL"
    )
]

protected func handleModelsCommand(app: CliApp): Unit {
    PrintUtils.printProcedure("Models", "Configure provider credentials and main model")
    PrintUtils.printLine("${"Current model:".withColor(Theme.MUTED)} ${CliConfig.model.withColor(Theme.ACCENT).withColor(AnsiColor.BOLD)}")
    let tipsLine = "${"Tips:".withColor(Theme.MUTED)} Enter keeps default. Press ${"ESC".withColor(Theme.HIGHLIGHT)} to cancel and return to chat."
    PrintUtils.printLine(tipsLine)
    PrintUtils.printLine("")

    let providerOptions = PROVIDER_PRESETS |>
        map { preset =>
            let key = Config.env[preset.apiKeyEnv] ?? ""
            let apiKeyStatus = if (key.trimAscii().isEmpty()) {
                "API KEY: not set"
            } else {
                "API KEY: configured"
            }
            "${preset.name} | ${apiKeyStatus}"
        } |>
        collectArray

    let providerIndex = InputUtils.getOptions(providerOptions, prompt: "Select provider (Enter to confirm, ESC to cancel)")
    let preset = match (providerIndex) {
        case Some(index) => PROVIDER_PRESETS[index]
        case None =>
            PrintUtils.printLine("Cancelled /models.")
            return
    }

    let defaultModelId = getDefaultModelId(preset, CliConfig.model)
    let modelPrompt = if (defaultModelId.isEmpty()) {
        "Model ID (${preset.name}) [required, e.g. ${String.join(preset.suggestedModels, delimiter: ", ")}]:"
    } else {
        "Model ID (${preset.name}) [default: ${defaultModelId}]:"
    }
    var modelInput = match (InputUtils.getUserInputOrCancel(prompt: modelPrompt)) {
        case Some(text) => text.trimAscii()
        case None =>
            PrintUtils.printLine("Cancelled /models.")
            return
    }
    if (modelInput.isEmpty()) {
        modelInput = defaultModelId
    }
    modelInput = normalizeModelId(modelInput)
    if (modelInput.isEmpty()) {
        PrintUtils.printLine("Model is empty, cancelled.")
        return
    }
    let mainModel = "${preset.provider}:${modelInput}"

    let oldApiKey = (Config.env[preset.apiKeyEnv] ?? "").trimAscii()
    let apiKeyPrompt = if (oldApiKey.isEmpty()) {
        "${preset.apiKeyEnv} [required]:"
    } else {
        "${preset.apiKeyEnv} [default: keep current]:"
    }
    var apiKey = match (InputUtils.getUserInputOrCancel(prompt: apiKeyPrompt)) {
        case Some(text) => text.trimAscii()
        case None =>
            PrintUtils.printLine("Cancelled /models.")
            return
    }
    if (apiKey.isEmpty()) {
        apiKey = oldApiKey
    }
    if (apiKey.isEmpty()) {
        PrintUtils.printLine("API key is empty, cancelled.")
        return
    }

    let oldBaseURL = (Config.env[preset.baseURLEnv] ?? preset.defaultBaseURL).trimAscii()
    let baseURLPrompt = "${preset.baseURLEnv} [default: ${oldBaseURL}]:"
    let baseURLInput = match (InputUtils.getUserInputOrCancel(prompt: baseURLPrompt)) {
        case Some(text) => text.trimAscii()
        case None =>
            PrintUtils.printLine("Cancelled /models.")
            return
    }
    let baseURL = if (baseURLInput.isEmpty()) { oldBaseURL } else { baseURLInput }

    PrintUtils.printLine("")
    PrintUtils.printLine("Will apply:".withColor(Theme.PRIMARY).withColor(AnsiColor.BOLD))
    PrintUtils.printLine("  ${"provider:".withColor(Theme.MUTED)} ${preset.provider.withColor(Theme.INFO)}")
    PrintUtils.printLine("  ${"model:".withColor(Theme.MUTED)} ${mainModel.withColor(Theme.ACCENT)}")
    PrintUtils.printLine("  ${"API KEY:".withColor(Theme.MUTED)} ${maskSecret(apiKey).withColor(Theme.INFO)}")
    PrintUtils.printLine("  ${"Base URL:".withColor(Theme.MUTED)} ${baseURL.withColor(Theme.INFO)}")
    PrintUtils.printLine("")

    let apply = InputUtils.getOptions(["Save and apply now", "Cancel"], prompt: "Confirm /models")
    match (apply) {
        case Some(0) => ()
        case _ =>
            PrintUtils.printLine("Cancelled /models.")
            return
    }

    // Persist model selection
    CliConfig.model = mainModel
    CliSettingManager.setting.model = mainModel
    let savedSettings = CliSettingManager.save()

    // Apply credentials immediately to this process
    Config.env[preset.apiKeyEnv] = apiKey
    Config.env[preset.baseURLEnv] = baseURL
    if (preset.runtimeApiKeyEnv != preset.apiKeyEnv) {
        Config.env[preset.runtimeApiKeyEnv] = apiKey
    }
    if (preset.runtimeBaseURLEnv != preset.baseURLEnv) {
        Config.env[preset.runtimeBaseURLEnv] = baseURL
    }

    // Persist credentials to .env for next startup
    let envEntries = ArrayList<(String, String)>()
    envEntries.add((preset.apiKeyEnv, apiKey))
    envEntries.add((preset.baseURLEnv, baseURL))
    if (preset.runtimeApiKeyEnv != preset.apiKeyEnv) {
        envEntries.add((preset.runtimeApiKeyEnv, apiKey))
    }
    if (preset.runtimeBaseURLEnv != preset.baseURLEnv) {
        envEntries.add((preset.runtimeBaseURLEnv, baseURL))
    }
    let savedEnv = upsertDotEnv(envEntries.toArray())

    // Reset model caches and apply the new main model immediately
    CliModelManager.resetRuntimeState()
    app.agent.model = CliModelManager.model

    if (savedSettings && savedEnv) {
        PrintUtils.printLine("Model configuration updated. Current model: ${CliConfig.model}")
    } else if (savedSettings) {
        PrintUtils.printLine("Model updated, but failed to persist .env.")
    } else {
        PrintUtils.printLine("Model switched for current session, but failed to save settings.")
    }
}

private func getDefaultModelId(preset: ModelProviderPreset, currentModel: String): String {
    let prefix = "${preset.provider}:"
    if (currentModel.startsWith(prefix) && currentModel.size > prefix.size) {
        return currentModel[prefix.size..].trimAscii()
    }
    if (!preset.suggestedModels.isEmpty()) {
        return preset.suggestedModels[0]
    }
    return ""
}

private func normalizeModelId(modelInput: String): String {
    let content = modelInput.trimAscii()
    if (content.isEmpty()) {
        return ""
    }
    if (let Some(index) <- content.indexOf(b':')) {
        return content[index + 1..].trimAscii()
    }
    return content
}

private func maskSecret(secret: String): String {
    if (secret.size <= 8) {
        return "********"
    }
    return "${secret[0..4]}****${secret[secret.size - 4..]}"
}

private func parseEnvKey(line: String): Option<String> {
    let trimmed = line.trimAscii()
    if (trimmed.isEmpty() || trimmed.startsWith("#")) {
        return None
    }
    if (let Some(eq) <- trimmed.indexOf(b'=')) {
        let key = trimmed[0..eq].trimAscii()
        if (!key.isEmpty()) {
            return key
        }
    }
    return None
}

private func upsertDotEnv(entries: Array<(String, String)>): Bool {
    try {
        let envPath = Path("./.env")
        let oldLines = if (exists(envPath)) {
            String.fromUtf8(File.readFrom(envPath)).split("\n")
        } else {
            Array<String>()
        }

        let keys = entries |> map { item => item[0] } |> collectArray
        let keptLines = oldLines |> filter { line =>
            if (let Some(key) <- parseEnvKey(line)) {
                return !keys.contains(key)
            }
            return true
        } |> collectArray

        let newLines = ArrayList<String>(keptLines)
        if (!newLines.isEmpty() && !newLines[newLines.size - 1].trimAscii().isEmpty()) {
            newLines.add("")
        }
        for ((key, value) in entries) {
            newLines.add("${key}=${value}")
        }

        File.writeTo(envPath, String.join(newLines.toArray(), delimiter: "\n").toArray())
        return true
    } catch (ex: Exception) {
        LogUtils.error("Failed to update .env: ${ex.message}")
        return false
    }
}
