package cli.utils

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
    var c_cc = VArray<UInt8, $32>({ i => 0 })

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
    static const ECHO: UIntNative  = 1 << 3
    static const ICANON: UIntNative  = 1 << 8
    static const INLCR: UIntNative  = 1 << 6
    static const ICRNL: UIntNative  = 1 << 8
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
        old.c_cc[VMIN]  = 1
        old.c_cc[VTIME] = 0

        unsafe{ tcsetattr(STDIN_FILENO, TCSANOW, inout old) }
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
        if (byte == 0x04) {  // Ctrl-D
            return None
        } else if (byte == b'\r'){
            return r'\n'
        } else if (byte == b'\n') { // enter
            return r'\n'
        } else if (byte == 0x7F) {
            return r'\u{7F}'
        } else if (byte == b'\b') {  // backspace
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

