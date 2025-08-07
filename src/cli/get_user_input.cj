package cli.cli

import std.io.*
import std.fs.*
import std.collection.*

import cli.cli.utils.*

// func parsePathAndPrefix(input: String): (String, String) {
//     let parts = input.split("/")
//     let fileName = parts.last.getOrDefault({=> ""})
//     var path = if (parts.size > 1) {
//         String.join(parts[0..parts.size - 1], delimiter: "/")
//     } else {
//         ""
//     }
//     if (path.isEmpty()) {
//         path = "./"
//     } else {
//         path = "./" + path + "/"
//     }
//     return (path, fileName)
// }

// let chatHistory: ArrayList<String> = ArrayList()

public func getUserInput(): String {
    while (true) {
        printPrompt("User")

        // var cursorPos: Int64 = 0
        // var atMode: Bool = false
        // var historyIndex: Int64 = chatHistory.size
        // var atPos: Int64 = -1

        // var input: String = ""

        // while (true) {
        //     var c = getchar()

        //     if (c == 10 || c == 13) { // Enter key
        //         chatHistory.add(input)
        //         println("")
        //         break
        //     } else if (c == 0) { // 扩展键前缀
        //         c = getchar()
        //         if (c == 72) { // Up arrow
        //             if (historyIndex > 0) {
        //                 historyIndex -= 1
        //                 print(" " * (input.size - cursorPos) + "\b \b" * input.size)
        //                 input = chatHistory[historyIndex]
        //                 print(input)
        //                 cursorPos = input.size
        //                 atMode = false
        //             }
        //         } else if (c == 80) {
        //             if (historyIndex < chatHistory.size - 1) {
        //                 historyIndex += 1
        //                 print(" " * (input.size - cursorPos) + "\b \b" * input.size)
        //                 input = chatHistory[historyIndex]
        //                 print(input)
        //                 cursorPos = input.size
        //                 atMode = false
        //             } else if (historyIndex == chatHistory.size - 1) {
        //                 historyIndex += 1
        //                 print(" " * (input.size - cursorPos) + "\b \b" * input.size)
        //                 input = ""
        //                 cursorPos = 0
        //                 atMode = false
        //             }
        //         } else if (c == 75) { // Left arrow
        //             if (cursorPos > 0) {
        //                 cursorPos -= 1
        //                 print("\b")
        //             }
        //         } else if (c == 77) { // Right arrow
        //             if (cursorPos < input.size) {
        //                 cursorPos += 1
        //                 print(input[cursorPos - 1..cursorPos])
        //             }
        //         }
        //     } else if (c == 8 || c == 127) { // Backspace
        //         if (cursorPos > 0) {
        //             print(" " * (input.size - cursorPos) + "\b \b" * input.size)
        //             cursorPos -= 1
        //             input = input[0..cursorPos] + input[cursorPos + 1..input.size]
        //             print(input + "\b" * (input.size - cursorPos))
        //             if (atMode && cursorPos <= atPos) {
        //                 atMode = false
        //             }
        //         }
        //     } else if (c == 9 && atMode) {
        //         if (cursorPos > atPos) {
        //             let atString = input[atPos + 1..cursorPos]
        //             let (path, filePrefix) = parsePathAndPrefix(atString)
        //             let fileInfos = Directory.readFrom(path)
        //             let filesMatched = ArrayList<String>()
        //             for (fileInfo in fileInfos) {
        //                 var name = fileInfo.name
        //                 if (fileInfo.isDirectory()) {
        //                     name += "/"
        //                 }
        //                 if (name.startsWith(filePrefix)) {
        //                     filesMatched.add(name)
        //                 }
        //             }
                    
        //             if (filesMatched.size == 1) {
        //                 print(" " * (input.size - cursorPos) + "\b \b" * input.size)
        //                 input = input[0..atPos + 1] + path[2..] + filesMatched[0]
        //                 if (input[input.size - 1..input.size] != "/") {
        //                     input += " "
        //                     atMode = false
        //                 }
        //                 cursorPos = input.size
        //                 print(input)
        //             } else if (filesMatched.size > 1) {
        //                 printFilesInfo(filesMatched, path)
        //                 printPrompt("User")
        //                 input = input[0..atPos + path.size - 2 + filePrefix.size + 1]
        //                 cursorPos = input.size
        //                 print(input)
        //             }
        //         }
        //     } else if (32 <= c && c <= 126) {
        //         print(" " * (input.size - cursorPos) + "\b \b" * input.size)
        //         input = input[0..cursorPos] + String.fromUtf8([UInt8(c)]) + input[cursorPos..input.size]
        //         cursorPos += 1
        //         print(input + "\b" * (input.size - cursorPos))
        //         if (c == 64) {
        //             atMode = true
        //             atPos = cursorPos - 1
        //         }
        //         historyIndex = chatHistory.size
        //     } else if (c == 3) {
        //         println("")
        //         input = "exit"
        //         break
        //     } else {
        //         // Ignore other keys
        //     }
        // }

        let input = readln()

        if (processCommand(input)) {
            return input
        }

    }
    return ""
}