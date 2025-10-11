package cli.io

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
foreign {
    func enterRaw(): IntNative

    func getRawByte(): Byte

    func getRawUtf8(bytes: CPointer<Byte>): IntNative

    func getByte(timeout: UInt32, keyCode:CPointer<UInt16>): Int64

    func exitRaw(): Unit
}

@When[os != "Windows"]
class RawInputUtils {
    static func rawEnter(): Unit {
        unsafe { enterRaw() }
    }

    static func rawExit(): Unit {
        unsafe { exitRaw() }
    }

    static func rawGetRune(): Option<Rune> {
        var buffer: VArray<Byte, $4> = [0, 0, 0, 0]
        let len: IntNative = unsafe { getRawUtf8(inout buffer) }

        let bytes = [buffer[0], buffer[1], buffer[2], buffer[3]]
        // Convert to a rune
        let (r, size) = Rune.fromUtf8(bytes, 0)
        // Assert
        if (size != Int64(len)) {
            throw Exception("Read bytes ${len} != Expected bytes ${size}")
        }
        return r
    }

    static func checkReadByte(bytes: Array<Byte>, infinite!: Bool = false): Bool {
        var keyCode: UInt16 = 0
        let waitTimeMs: UInt32
        if (infinite) {
            waitTimeMs = 0
        } else {
            waitTimeMs = 20
        }
        let len = unsafe { getByte(waitTimeMs, inout keyCode) }
        if (len == 1 && bytes.contains(UInt8(keyCode))) { // ASCII
            return true
        }
        return false
    }
}
