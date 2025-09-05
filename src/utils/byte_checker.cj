package cli.utils

import magic.log.LogUtils
import std.collection.{ArrayList, LinkedList}
import std.regex.Regex
import std.deriving.*
import std.fs.{File, Path, exists}
import cli.core.config.CliConfig

public class ByteChecker {
    private static let VK_BACK: Byte = 0x08
    private static let VK_TAB: Byte = 0x09
    private static let VK_ENTER: Byte = 0x0A
    private static let VK_RETURN: Byte = 0x0D
    private static let VK_ESCAPE: Byte = 0x1B
    private static let VK_DELETE: Byte = 0x2E
    private static let VK_UP: Byte = 0x26
    private static let VK_DOWN: Byte = 0x28
    private static let VK_LEFT: Byte = 0x25
    private static let VK_RIGHT: Byte = 0x27

    public static func checkEsc(infinite!: Bool = false): ?String {
        try {
            RawInputUtils.rawEnter()
            if (RawInputUtils.checkReadByte([VK_ESCAPE], infinite: infinite)) {
                '\u{1B}'
            } else {
                None
            }
        } finally {
            RawInputUtils.rawExit()
        }
    }

    public static func checkEnter(infinite!: Bool = false): ?String {
        try {
            RawInputUtils.rawEnter()
            if (RawInputUtils.checkReadByte([VK_ENTER, VK_RETURN], infinite: infinite)) {
                '\n'
            } else {
                None
            }
        } finally {
            RawInputUtils.rawExit()
        }
    }
}
