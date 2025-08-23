package cli.utils

func buildBanner(): String {
    let c1 = AnsiColor.color256(66)
    let c2 = AnsiColor.color256(103)
    let c3 = AnsiColor.color256(109)
    let c4 = AnsiColor.color256(146)
    let c5 = AnsiColor.color256(152)
    let c6 = AnsiColor.color256(242)
    let c7 = AnsiColor.color256(110)
    let c8 = AnsiColor.color256(145)
    let c9 = AnsiColor.color256(139)
    
    let shadow = AnsiColor.color256(236)
    let highlight = AnsiColor.color256(253)
    let reset = RESET

    let taglineColor = AnsiColor.color256(144)
    let tagline = padString("Powered By Cangjie Magic Framework", width: 100, center: true)

    let lines = [
        "\n",
        "${c1}████${highlight}██${c1}████  ${c2}  ██████    ${c3}  ██████    ${c4}${highlight}█${c4}████████${highlight}█  ${c5}  ██████    ${c6}  ${c7}  ██████    ${c8}██${highlight}██${shadow}        ${c9}${highlight}█${c9}████████${highlight}█  ${reset}",
        "${c1}████${highlight}██${c1}████  ${c2} ██${highlight}████${c2}██   ${c3} ██${highlight}████${c3}██   ${c4}${highlight}██${shadow}██${c4}██${highlight}██${shadow}██  ${c5} ██${highlight}████${c5}██   ${c6}  ${c7} ██${highlight}████${c7}██   ${c8}██${highlight}██${shadow}        ${c9}${highlight}██${shadow}██${c9}██${highlight}██${shadow}██  ${reset}",
        "${c1}██${highlight}█${c1}████${highlight}█${c1}██  ${c2}██${highlight}██████${c2}██  ${c3}██${highlight}██${shadow}        ${c4}${highlight}██${shadow}██${c4}██${highlight}██${shadow}██  ${c5}██${highlight}██${shadow}        ${c6}  ${c7}██${highlight}██${shadow}        ${c8}██${highlight}██${shadow}        ${c9}${highlight}██${shadow}██${c9}██${highlight}██${shadow}██  ${reset}",
        "${c1}██${highlight}██${c1}██${highlight}██${c1}██  ${c2}██████████  ${c3}██${highlight}██${c3}  ████  ${c4}${highlight}██${shadow}██${c4}██${highlight}██${shadow}██  ${c5}██${highlight}██${shadow}        ${c6}  ${c7}██${highlight}██${shadow}        ${c8}██${highlight}██${shadow}        ${c9}${highlight}██${shadow}██${c9}██${highlight}██${shadow}██  ${reset}",
        "${c1}██${highlight}██████${c1}██  ${c2}██${highlight}██████${c2}██  ${c3}██${highlight}██${c3}   ███  ${c4}${highlight}██${shadow}██${c4}██${highlight}██${shadow}██  ${c5}██${highlight}██${shadow}        ${c6}  ${c7}██${highlight}██${shadow}        ${c8}██${highlight}██${shadow}        ${c9}${highlight}██${shadow}██${c9}██${highlight}██${shadow}██  ${reset}",
        "${c1}██${highlight}██████${c1}██  ${c2}██${highlight}██████${c2}██  ${c3} ██${highlight}████${c3}██   ${c4}${highlight}██${shadow}██${c4}██${highlight}██${shadow}██  ${c5} ██${highlight}████${c5}██   ${c6}  ${c7} ██${highlight}████${c7}██   ${c8}██${highlight}██${shadow}        ${c9}${highlight}██${shadow}██${c9}██${highlight}██${shadow}██  ${reset}",
        "${c1}██${highlight}██████${c1}██  ${c2}██${highlight}██████${c2}██  ${c3}  ██████    ${c4}${highlight}█${c4}████████${highlight}█  ${c5}  ██████    ${c6}  ${c7}  ██████    ${c8}██████████  ${c9}${highlight}█${c9}████████${highlight}█  ${reset}",
        "\n",
        tagline.withColor(taglineColor)
    ]
    return String.join(lines, delimiter: "\n")
}