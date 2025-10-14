package cli.core.token_status

import magic.core.model.ChatUsage

import cli.io.{PrintUtils, Theme, wrapBox, WithColor}

/**
 * Manage token status
 */
protected class TokenStatusManager {
    private var promptTokens: Int64 = 0
    private var completionTokens: Int64 = 0
    private var totalTokens: Int64 = 0

    protected func addUsage(usage: ChatUsage): Unit {
        this.promptTokens += usage.promptTokens
        this.completionTokens += usage.completionTokens
        this.totalTokens += usage.totalTokens
    }

    protected func printStatus(): Unit {
        let message = wrapBox(
            " 📊 Token Status".withColor(Theme.PRIMARY),
            lines: [
                " ∙ Input:  ${promptTokens}",
                " ∙ Output: ${completionTokens}",
                " ∙ Total:  ${totalTokens}"
            ]
        )
        PrintUtils.printLine(message)
    }
}