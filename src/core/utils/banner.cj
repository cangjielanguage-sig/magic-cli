package cli.core.utils

import std.env.*

struct AnsiColor {
    public let code: String
    
    public AnsiColor(code: String) {
        this.code = code
    }

    public static func rgb(r: Int64, g: Int64, b: Int64): AnsiColor {
        return AnsiColor("\u{1b}[38;2;${r};${g};${b}m")
    }

    public static prop reset: String {
        get() {
            "\u{1b}[0m"
        }
    }
}

public class Banner {
    public func printBanner() {
        let c1 = AnsiColor.rgb(110, 80, 200).code
        let c2 = AnsiColor.rgb(145, 82, 185).code
        let c3 = AnsiColor.rgb(180, 85, 165).code
        let c4 = AnsiColor.rgb(215, 90, 140).code
        let c5 = AnsiColor.rgb(255, 110, 110).code
        let c6 = AnsiColor.rgb(100, 100, 100).code // Separator color
        let c7 = AnsiColor.rgb(255, 150, 80).code
        let c8 = AnsiColor.rgb(255, 170, 80).code
        let c9 = AnsiColor.rgb(255, 190, 80).code
        let reset = AnsiColor.reset

        println("${c1}████▒▒████  ${c2}  ██████    ${c3}  ██████    ${c4}▒████████▒  ${c5}  ██████    ${c6}  ${c7}  ██████    ${c8}██▒▒        ${c9}▒████████▒  ${reset}")
        println("${c1}████▒▒████  ${c2} ██▒▒▒▒██   ${c3} ██▒▒▒▒██   ${c4}▒▒▒▒██▒▒▒▒  ${c5} ██▒▒▒▒██   ${c6}  ${c7} ██▒▒▒▒██   ${c8}██▒▒        ${c9}▒▒▒▒██▒▒▒▒  ${reset}")
        println("${c1}██▒████▒██  ${c2}██▒▒▒▒▒▒██  ${c3}██▒▒        ${c4}▒▒▒▒██▒▒▒▒  ${c5}██▒▒        ${c6}  ${c7}██▒▒        ${c8}██▒▒        ${c9}▒▒▒▒██▒▒▒▒  ${reset}")
        println("${c1}██▒▒██▒▒██  ${c2}██████████  ${c3}██▒▒  ████  ${c4}▒▒▒▒██▒▒▒▒  ${c5}██▒▒        ${c6}  ${c7}██▒▒        ${c8}██▒▒        ${c9}▒▒▒▒██▒▒▒▒  ${reset}")
        println("${c1}██▒▒▒▒▒▒██  ${c2}██▒▒▒▒▒▒██  ${c3}██▒▒   ███  ${c4}▒▒▒▒██▒▒▒▒  ${c5}██▒▒        ${c6}  ${c7}██▒▒        ${c8}██▒▒        ${c9}▒▒▒▒██▒▒▒▒  ${reset}")
        println("${c1}██▒▒▒▒▒▒██  ${c2}██▒▒▒▒▒▒██  ${c3} ██▒▒▒▒██   ${c4}▒▒▒▒██▒▒▒▒  ${c5} ██▒▒▒▒██   ${c6}  ${c7} ██▒▒▒▒██   ${c8}██▒▒        ${c9}▒▒▒▒██▒▒▒▒  ${reset}")
        println("${c1}██▒▒▒▒▒▒██  ${c2}██▒▒▒▒▒▒██  ${c3}  ██████    ${c4}▒████████▒  ${c5}  ██████    ${c6}  ${c7}  ██████    ${c8}██████████  ${c9}▒████████▒  ${reset}")

        let taglineColor = AnsiColor.rgb(220, 180, 80)
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