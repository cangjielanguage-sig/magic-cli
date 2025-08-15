package cli.utils

import std.env.*

private struct AnsiColor {
    public let code: String

    public AnsiColor(code: String) {
        this.code = code
    }

    public static func color256(index: Int64): AnsiColor {
        return AnsiColor("\u{1b}[38;5;${index}m")
    }

    public static prop reset: String {
        get() {
            "\u{1b}[0m"
        }
    }
}

public class Banner {
    public func printBanner() {
        let c1 = AnsiColor.color256(98).code
        let c2 = AnsiColor.color256(133).code
        let c3 = AnsiColor.color256(168).code
        let c4 = AnsiColor.color256(169).code
        let c5 = AnsiColor.color256(203).code
        let c6 = AnsiColor.color256(241).code   // separator color
        let c7 = AnsiColor.color256(215).code
        let c8 = AnsiColor.color256(216).code
        let c9 = AnsiColor.color256(222).code
        let reset = AnsiColor.reset

        println("${c1}████▒▒████  ${c2}  ██████    ${c3}  ██████    ${c4}▒████████▒  ${c5}  ██████    ${c6}  ${c7}  ██████    ${c8}██▒▒        ${c9}▒████████▒  ${reset}")
        println("${c1}████▒▒████  ${c2} ██▒▒▒▒██   ${c3} ██▒▒▒▒██   ${c4}▒▒▒▒██▒▒▒▒  ${c5} ██▒▒▒▒██   ${c6}  ${c7} ██▒▒▒▒██   ${c8}██▒▒        ${c9}▒▒▒▒██▒▒▒▒  ${reset}")
        println("${c1}██▒████▒██  ${c2}██▒▒▒▒▒▒██  ${c3}██▒▒        ${c4}▒▒▒▒██▒▒▒▒  ${c5}██▒▒        ${c6}  ${c7}██▒▒        ${c8}██▒▒        ${c9}▒▒▒▒██▒▒▒▒  ${reset}")
        println("${c1}██▒▒██▒▒██  ${c2}██████████  ${c3}██▒▒  ████  ${c4}▒▒▒▒██▒▒▒▒  ${c5}██▒▒        ${c6}  ${c7}██▒▒        ${c8}██▒▒        ${c9}▒▒▒▒██▒▒▒▒  ${reset}")
        println("${c1}██▒▒▒▒▒▒██  ${c2}██▒▒▒▒▒▒██  ${c3}██▒▒   ███  ${c4}▒▒▒▒██▒▒▒▒  ${c5}██▒▒        ${c6}  ${c7}██▒▒        ${c8}██▒▒        ${c9}▒▒▒▒██▒▒▒▒  ${reset}")
        println("${c1}██▒▒▒▒▒▒██  ${c2}██▒▒▒▒▒▒██  ${c3} ██▒▒▒▒██   ${c4}▒▒▒▒██▒▒▒▒  ${c5} ██▒▒▒▒██   ${c6}  ${c7} ██▒▒▒▒██   ${c8}██▒▒        ${c9}▒▒▒▒██▒▒▒▒  ${reset}")
        println("${c1}██▒▒▒▒▒▒██  ${c2}██▒▒▒▒▒▒██  ${c3}  ██████    ${c4}▒████████▒  ${c5}  ██████    ${c6}  ${c7}  ██████    ${c8}██████████  ${c9}▒████████▒  ${reset}")

        let taglineColor = AnsiColor.color256(179)
        let tagline = "Powered By CangjieMagic Framework"
        let totalWidth = 100
        let taglinePadding = (totalWidth - tagline.size) / 2

        var paddingString = ""
        var paddingCounter: Int64 = 0
        while (paddingCounter < taglinePadding) {
            paddingString += " "
            paddingCounter += 1
        }

        println("\n${taglineColor.code}${paddingString}${tagline}${AnsiColor.reset}")
    }
}