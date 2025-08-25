package cli.utils

import std.collection.{ArrayList, HashMap}
/**
 * According to the first byte, compute the total bytes of the current UTF8 code point
 */
private func nextUtf8ByteSize(byte: Byte): Int64 {
    if (byte < 0x80) {
        return 1
    } else if (byte < 0xE0) {
        return 2
    } else if (byte < 0xF0) {
        return 3
    } else {
        return 4
    }
}

@When[os != "Windows"]
@C
struct Termios {
    var c_iflag: UIntNative = 0
    let c_oflag: UIntNative = 0
    let c_cflag: UIntNative = 0
    var c_lflag: UIntNative = 0
    var c_cc = VArray<UInt8, $32>({i => 0})

    func dump(): Unit {
        println("c_iflag: ${c_iflag}")
        println("c_oflag: ${c_oflag}")
        println("c_cflag: ${c_cflag}")
        println("c_lflag: ${c_lflag}")
        print("c_cc: ")
        for (i in 0..32) {
            print("${c_cc[i]}, ")
        }
        println()
    }
}

@When[os != "Windows"]
foreign {
    func tcgetattr(fd: IntNative, termios_p: CPointer<Termios>): IntNative

    func tcsetattr(fd: IntNative, optional_actions: IntNative, termios_p: CPointer<Termios>): IntNative

    func read(fd: IntNative, buf: CPointer<UInt8>, count: UIntNative): IntNative
}

@When[os != "Windows"]
class RawInputUtils {
    static const STDIN_FILENO: IntNative = 0
    static const ECHO: UIntNative = 1 << 3
    static const ICANON: UIntNative = 1 << 8
    static const INLCR: UIntNative = 1 << 6
    static const ICRNL: UIntNative = 1 << 8
    static const VMIN: Int64 = 16
    static const VTIME: Int64 = 17
    static const TCSANOW: IntNative = 0

    static var GLOBAL_OLD = Termios()

    static func rawEnter(): Unit {
        var old = Termios()
        // If we pass `inout GLOBAL_OLD` directly, cangjie runtime will crash. BUG?
        unsafe { tcgetattr(STDIN_FILENO, inout old) }
        GLOBAL_OLD = old

        // old.c_iflag &= !(ICRNL | INLCR)
        old.c_lflag &= !(ECHO | ICANON)
        old.c_cc[VMIN] = 1
        old.c_cc[VTIME] = 0

        unsafe { tcsetattr(STDIN_FILENO, TCSANOW, inout old) }
    }

    static func rawExit(): Unit {
        var old = GLOBAL_OLD
        unsafe { tcsetattr(STDIN_FILENO, TCSANOW, inout old) }
    }

    /**
     * Read a byte
     */
    static func rawGetByte(): Option<Byte> {
        var ch: UInt8 = 0
        if (unsafe { read(STDIN_FILENO, inout ch, 1) } == 1) {
            return ch
        } else {
            return None
        }
    }

    static func rawGetRune(): Option<Rune> {
        let byte = if (let Some(b) <- rawGetByte()) {
            b
        } else {
            return None // EOF
        }
        if (byte == 0x04) { // Ctrl-D
            return None
        } else if (byte == b'\r') {
            return r'\n'
        } else if (byte == b'\n') { // enter
            return r'\n'
        } else if (byte == 0x7F) {
            return r'\u{7F}'
        } else if (byte == b'\b') { // backspace
            return r'\b'
        }
        // Escape arrows
        if (byte == 0x1B) { // ESC byte
            let byte2 = rawGetByte().getOrThrow()
            let byte3 = rawGetByte().getOrThrow()
            if (byte2 != b'[') {
                eprintln("Unknown escaped ascii")
                return None
            }
            return match (byte3) {
                case b'A' => r'\u{2191}' // Up
                case b'B' => r'\u{2193}' // Down
                case b'C' => r'\u{2192}' // Right
                case b'D' => r'\u{2190}' // Left
                case _ =>
                    eprintln("Unknown escaped ascii")
                    None
            }
        }

        let utf8ByteSize = nextUtf8ByteSize(byte)
        let bytes = Array<Byte>(utf8ByteSize, repeat: 0)
        bytes[0] = byte
        // Read the rest bytes of the current rune
        for (i in 1..utf8ByteSize) {
            bytes[i] = rawGetByte().getOrThrow()
        }
        // Convert to a rune
        let (r, size) = Rune.fromUtf8(bytes, 0)
        // Assert
        if (size != utf8ByteSize) {
            throw Exception("Read bytes != Expected bytes")
        }
        return r
    }
}

/**
 * 映射关系
 * BOOL => Int32
 * WORD => UInt16
 * DWORD => UInt32
 * CHAR => UInt8
 * WCHAR => UInt16
 * HANDLE => UIntNative
 * INT => Int32
 * UINT => UInt32
 */
/**
typedef struct _KEY_EVENT_RECORD {
    BOOL  bKeyDown;          // 指示键是按下还是释放
    WORD  wRepeatCount;      // 按键重复次数（按住键时递增）
    WORD  wVirtualKeyCode;   // 虚拟键码（如 VK_ESCAPE、VK_RETURN 等）
    WORD  wVirtualScanCode;  // 虚拟扫描码（与硬件相关的扫描码）
    union {
        WCHAR UnicodeChar;   // Unicode 字符（适用于 Unicode 模式）
        CHAR  AsciiChar;     // ASCII 字符（适用于 ASCII 模式）
    } uChar;                 // 按键对应的字符
    DWORD dwControlKeyState; // 控制键状态（如 Shift、Ctrl、Alt 等是否按下）
} KEY_EVENT_RECORD;
 */
@When[os == "Windows"]
@C
struct KEY_EVENT_RECORD {
    var bKeyDown: Int32 = 0i32
    var wRepeatCount: UInt16 = 0u16
    var wVirtualKeyCode: UInt16 = 0u16
    var wVirtualScanCode: UInt16 = 0u16
    var wChar: UInt16 = 0u16
    var dwControlKeyState: UInt32 = 0u32
}

@When[os == "Windows"]
@C
struct INPUT_RECORD {
    var EventType: UInt16 = 0u16
    var Event: KEY_EVENT_RECORD = KEY_EVENT_RECORD()
}

@When[os == "Windows"]
foreign {
    /**
     *  HANDLE GetStdHandle(
     *  DWORD nStdHandle
     *  );
     *  HANDLE是void*指针
     *  DWORD是uint32_t
     *  STD_INPUT_HANDLE=-10
     *  STD_OUTPUT_HANDLE=-11
     *  STD_ERROR_HANDLE=-12
     */
    func GetStdHandle(nStdHandle: UIntNative): UIntNative

    /**
     * BOOL GetConsoleMode(
     *  HANDLE  hConsoleHandle,
     *  LPDWORD lpMode
     * );
     * HANDLE是void* → CPointer<UInt8>
     * LPDWORD是uint32_t* → CPointer<UInt32>
     * 返回值BOOL是int → Int32
     */
    func GetConsoleMode(hConsoleHandle: UIntNative, lpMode: CPointer<UInt32>): Int32

    /**
     * BOOL SetConsoleMode(
     *  HANDLE  hConsoleHandle,
     *  DWORD   dwMode
     * );
     * HANDLE是void* → CPointer<UInt8>
     * DWORD是uint32_t → UInt32
     * 返回值BOOL是int → Int32
     */
    func SetConsoleMode(hConsoleHandle: UIntNative, dwMode: UInt32): Int32

    /**
     * BOOL ReadConsoleInput(
     *  HANDLE        hConsoleInput,
     *  PINPUT_RECORD lpBuffer,
     *  DWORD         nLength,
     *  LPDWORD       lpNumberOfEventsRead
     * );
     * HANDLE是void* → CPointer<Unit>
     * PINPUT_RECORD是INPUT_RECORD* → CPointer<INPUT_RECORD>
     * DWORD是uint32_t → UInt32
     * LPDWORD是uint32_t* → CPointer<UInt32>
     * 返回值BOOL是int → Int32
     */
    func ReadConsoleInputW(hConsoleInput: UIntNative, lpBuffer: CPointer<INPUT_RECORD>, nLength: UInt32,
        lpNumberOfEventsRead: CPointer<UInt32>): Int32

    /**
     * BOOL WINAPI SetConsoleOutputCP(
     * _In_ UINT wCodePageID
     * );
     */
    func SetConsoleOutputCP(wCodePageID: UInt32): Int32

    /**
     * BOOL WINAPI SetConsoleCP(
     * _In_ UINT wCodePageID
     * );
     */
    func SetConsoleCP(wCodePageID: UInt32): Int32
}

@When[os == "Windows"]
class RawInputUtils {
    static let STD_INPUT_HANDLE: UIntNative = 0xFFFFFFF6 // DWORD(-10)
    static let INVALID_HANDLE_VALUE: UIntNative = 0xFFFFFFFF
    static var H_CONSOLE: UIntNative = 0
    static var OLD_MODE: UInt32 = 0

    // 控制台模式标志
    static const ENABLE_ECHO_INPUT: UInt32 = 0x0004
    static const ENABLE_INSERT_MODE: UInt32 = 0x0020
    static const ENABLE_LINE_INPUT: UInt32 = 0x0002
    static const ENABLE_MOUSE_INPUT: UInt32 = 0x0010
    static const ENABLE_PROCESSED_INPUT: UInt32 = 0x0001
    static const ENABLE_QUICK_EDIT_MODE: UInt32 = 0x0040
    static const ENABLE_WINDOW_INPUT: UInt32 = 0x0008
    static const ENABLE_VIRTUAL_TERMINAL_INPUT: UInt32 = 0x0200

    // 虚拟键码 - 用于识别特殊键
    static let VK_UP: UInt16 = 0x26
    static let VK_DOWN: UInt16 = 0x28 
    static let VK_LEFT: UInt16 = 0x25
    static let VK_RIGHT: UInt16 = 0x27
    static let VK_ESCAPE: UInt16 = 0x1B
    static let VK_BACK: UInt16 = 0x08
    static let VK_DELETE: UInt16 = 0x2E
    static let VK_TAB: UInt16 = 0x09
    static let VK_ENTER: UInt16 = 0x0D
    //static let ALL_VKS: Array<UInt16> = [VK_UP, VK_DOWN, VK_LEFT, VK_RIGHT, VK_ESCAPE, VK_BACK, VK_DELETE, VK_TAB, VK_ENTER]
    static let ALL_VKS: Array<UInt16> = [VK_UP, VK_DOWN, VK_LEFT, VK_RIGHT, VK_BACK, VK_TAB]
    static let VKS_VALUE_DICT:HashMap<UInt16, Array<Byte>> = HashMap()
    static init() {
        VKS_VALUE_DICT.add(VK_UP, [0x1B, 0x5B, 0x41])
        VKS_VALUE_DICT.add(VK_DOWN, [0x1B, 0x5B, 0x42])
        VKS_VALUE_DICT.add(VK_LEFT, [0x1B, 0x5B, 0x44])
        VKS_VALUE_DICT.add(VK_RIGHT, [0x1B, 0x5B, 0x43])
        VKS_VALUE_DICT.add(VK_ESCAPE, [0x1B])
        VKS_VALUE_DICT.add(VK_BACK, [0x08])
        VKS_VALUE_DICT.add(VK_DELETE, [0x1B, 0x5B, 0x33, 0x7E])
        VKS_VALUE_DICT.add(VK_TAB, [0x09])
        VKS_VALUE_DICT.add(VK_ENTER, [0x0A])
    }
    // EVENT
    static const KEY_EVENT: UInt16 = 0x0001
    static var HIGH_SURROGATE: Option<UInt16> = None
    static func rawEnter(): Unit {
        unsafe {
            SetConsoleCP(65001)
            SetConsoleOutputCP(65001)
        }
        let hConsole = unsafe { GetStdHandle(STD_INPUT_HANDLE) }
        if (hConsole == INVALID_HANDLE_VALUE) {
            throw Exception("Failed to get console handler")
        }
        H_CONSOLE = hConsole
        var old: UInt32 = 0
        let getProcess = unsafe { GetConsoleMode(H_CONSOLE, inout old) }
        if (getProcess != 1) {
            throw Exception("Failed to get console mode")
        }
        OLD_MODE = old

        var rawMode = old
        rawMode &= !ENABLE_ECHO_INPUT
        rawMode &= !ENABLE_LINE_INPUT
        rawMode &= !ENABLE_MOUSE_INPUT
        rawMode &= !ENABLE_WINDOW_INPUT
        unsafe { SetConsoleMode(H_CONSOLE, rawMode) }
    }

    static func rawExit(): Unit {
        var old = OLD_MODE
        unsafe { SetConsoleMode(H_CONSOLE, old) }
    }

    /**
     * 读取一个UTF-8字节数组
     */
    static func rawGetBytes(): Option<Array<Byte>> {
        while (true) {
            let (wcOp, virtual) = rawGetWChar()
            if (let Some(wChar) <- wcOp) {
                if (virtual) {
                    return VKS_VALUE_DICT.get(wChar).getOrThrow()
                } else {
                    let checkpoint: ?UInt32 = getCheckPoint(wChar)
                    if (let Some(cp) <- checkpoint) {
                        return codepointToUtf8(cp)
                    }
                }
            }
        }
        None
    }

    static func rawGetRune(): Option<Rune> {
        let bytes = if (let Some(bs) <- rawGetBytes()) {
            bs
        } else {
            return None // EOF
        }
        let byte = bytes[0]
        if (byte == 0x04) { // Ctrl-D
            return None
        } else if (byte == 0x0D) { // '\r'
            return r'\n'
        } else if (byte == 0x0A) { // enter
            return r'\n'
        } else if (byte == 0x7F) {
            return r'\u{7F}'
        } else if (byte == 0x08) { // backspace
            return r'\b'
        } else if (byte == 0x09) { // tab
            return r'\t'
        }
        
        // Escape arrows
        if (byte == 0x1B) { 
            if (bytes.size == 1) { // ESC byte
                return None
            } 
            if (bytes == VKS_VALUE_DICT.get(VK_DELETE).getOrThrow()) {
                return r'\u{7F}'
            }
            let byte2 = bytes[1]
            let byte3 = bytes[2]
            if (byte2 != 0x5B) {
                eprintln("Unknown escaped ascii")
                return None
            }
            return match (byte3) {
                case 0x41 => r'\u{2191}' // Up
                case 0x42 => r'\u{2193}' // Down
                case 0x43 => r'\u{2192}' // Right
                case 0x44 => r'\u{2190}' // Left
                case _ =>
                    eprintln("Unknown escaped ascii")
                    None
            }
        }
        // Convert to a rune
        let (r, size) = Rune.fromUtf8(bytes, 0)
        return r
    }

    private static func rawGetWChar(): (Option<UInt16>, Bool) {
        var lpBuffer = INPUT_RECORD()
        var eventsRead: UInt32 = 0
        let res = unsafe { ReadConsoleInputW(H_CONSOLE, inout lpBuffer, 1u32, inout eventsRead) }
        if (res != 1 || eventsRead != 1) {
            throw Exception("Failed to read console input")
        }

        let ir = lpBuffer
        if (ir.EventType != KEY_EVENT) {
            return (None, false)
        }
        let keyEvent = ir.Event
        // Only Press Event useful
        if (keyEvent.bKeyDown == 0) {
            return (None, false)
        }

        let virtualKeyCode = keyEvent.wVirtualKeyCode
        // Check if it's a function key or other non-printable character
        if (ALL_VKS.contains(virtualKeyCode)) {
            return (virtualKeyCode, true)
        }
        // For special characters, ensure that only valid character values are returned.
        if (keyEvent.wChar != 0) {
            return (keyEvent.wChar, false)
        }
        (None, false)
    }

    private static func codepointToUtf8(codepoint: UInt32): Array<Byte> {
        let lst = ArrayList<Byte>()
        if (codepoint <= 0x7F) {
            lst.add(UInt8(codepoint))
        } else if (codepoint <= 0x7FF) {
            // 2字节：110xxxxx 10xxxxxx
            lst.add(UInt8(0xC0 | (codepoint >> 6)))
            lst.add(UInt8(0x80 | (codepoint & 0x3F)))
        } else if (codepoint <= 0xFFFF) {
            // 3字节：1110xxxx 10xxxxxx 10xxxxxx
            lst.add(UInt8(0xE0 | (codepoint >> 12)))
            lst.add(UInt8(0x80 | ((codepoint >> 6) & 0x3F)))
            lst.add(UInt8(0x80 | (codepoint & 0x3F)))
        } else if (codepoint <= 0x10FFFF) {
            // 4字节：11110xxx 10xxxxxx 10xxxxxx 10xxxxxx
            lst.add(UInt8(0xF0 | (codepoint >> 18)))
            lst.add(UInt8(0x80 | ((codepoint >> 12) & 0x3F)))
            lst.add(UInt8(0x80 | ((codepoint >> 6) & 0x3F)))
            lst.add(UInt8(0x80 | (codepoint & 0x3F)))
        } else {
            // 无效码点，使用替换字符 (U+FFFD)
            lst.add(0xEF)
            lst.add(0xBF)
            lst.add(0xBD)
        }
        return lst.toArray();
    }

    private static func isHighSurrogate(wChar: UInt16): Bool {
        return wChar >= 0xD800 && wChar <= 0xDBFF
    }

    private static func isLowSurrogate(wChar: UInt16): Bool {
        return wChar >= 0xDC00 && wChar <= 0xDFFF
    }

    private static func isSingleSurrogate(wChar: UInt16): Bool {
        return wChar < 0xD800 || wChar > 0xDFFF
    }

    private static func getCheckPoint(fWChar: UInt16): Option<UInt32> {
        var wChar = fWChar
        if (isSingleSurrogate(wChar)) {
            return UInt32(wChar)
        }
        if (isLowSurrogate(wChar)) {
            // ILLEGAL SKIP
            return None
        }
        if (isHighSurrogate(wChar)) {
            let highSurrogate: UInt16 = wChar
            let (wcOp, _) = rawGetWChar()
            if (let Some(wc) <- wcOp) {
                wChar = wc
            } else {
                // ILLEGAL SKIP
                return None
            }
            if (isLowSurrogate(wChar)) {
                let lowSurrogate = wChar
                return mergeWCharPair(highSurrogate, lowSurrogate)
            }
            // ILLEGAL SKIP
            return None
        }
        // Never Happened
        return None
    }

    private static func mergeWCharPair(high: UInt16, low: UInt16): UInt32 {
        return UInt32(0x10000u32 + UInt32((high - 0xD800) << 10) + UInt32(low - 0xDC00));
    }
}
