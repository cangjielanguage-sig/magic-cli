package cli.utils

func buildBanner(): String {
    let c1 = AnsiColor.color256(98)
    let c2 = AnsiColor.color256(133)
    let c3 = AnsiColor.color256(168)
    let c4 = AnsiColor.color256(169)
    let c5 = AnsiColor.color256(203)
    let c6 = AnsiColor.color256(241) // separator color
    let c7 = AnsiColor.color256(215)
    let c8 = AnsiColor.color256(216)
    let c9 = AnsiColor.color256(222)
    let reset = RESET

    let taglineColor = AnsiColor.color256(179)
    let tagline = padString("Powered By Cangjie Magic Framework", width: 100, center: true)

    let lines = [
        "\n",
        "${c1}████▒▒████  ${c2}  ██████    ${c3}  ██████    ${c4}▒████████▒  ${c5}  ██████    ${c6}  ${c7}  ██████    ${c8}██▒▒        ${c9}▒████████▒  ${reset}",
        "${c1}████▒▒████  ${c2} ██▒▒▒▒██   ${c3} ██▒▒▒▒██   ${c4}▒▒▒▒██▒▒▒▒  ${c5} ██▒▒▒▒██   ${c6}  ${c7} ██▒▒▒▒██   ${c8}██▒▒        ${c9}▒▒▒▒██▒▒▒▒  ${reset}",
        "${c1}██▒████▒██  ${c2}██▒▒▒▒▒▒██  ${c3}██▒▒        ${c4}▒▒▒▒██▒▒▒▒  ${c5}██▒▒        ${c6}  ${c7}██▒▒        ${c8}██▒▒        ${c9}▒▒▒▒██▒▒▒▒  ${reset}",
        "${c1}██▒▒██▒▒██  ${c2}██████████  ${c3}██▒▒  ████  ${c4}▒▒▒▒██▒▒▒▒  ${c5}██▒▒        ${c6}  ${c7}██▒▒        ${c8}██▒▒        ${c9}▒▒▒▒██▒▒▒▒  ${reset}",
        "${c1}██▒▒▒▒▒▒██  ${c2}██▒▒▒▒▒▒██  ${c3}██▒▒   ███  ${c4}▒▒▒▒██▒▒▒▒  ${c5}██▒▒        ${c6}  ${c7}██▒▒        ${c8}██▒▒        ${c9}▒▒▒▒██▒▒▒▒  ${reset}",
        "${c1}██▒▒▒▒▒▒██  ${c2}██▒▒▒▒▒▒██  ${c3} ██▒▒▒▒██   ${c4}▒▒▒▒██▒▒▒▒  ${c5} ██▒▒▒▒██   ${c6}  ${c7} ██▒▒▒▒██   ${c8}██▒▒        ${c9}▒▒▒▒██▒▒▒▒  ${reset}",
        "${c1}██▒▒▒▒▒▒██  ${c2}██▒▒▒▒▒▒██  ${c3}  ██████    ${c4}▒████████▒  ${c5}  ██████    ${c6}  ${c7}  ██████    ${c8}██████████  ${c9}▒████████▒  ${reset}",
        "\n",
        tagline.withColor(taglineColor)
    ]
    return String.join(lines, delimiter: "\n")
}