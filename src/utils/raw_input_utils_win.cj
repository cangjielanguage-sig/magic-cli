package cli.utils

import std.collection.{ArrayList, HashMap}
import magic.log.LogUtils

@When[os == "Windows"]
foreign {
    func enterRaw(): IntNative

    func getRawUtf8(bytes: CPointer<Byte>): IntNative

    func exitRaw(): Unit

    func getByte(timeout: UInt32, keyCode:CPointer<UInt16>): IntNative
}

@When[os == "Windows"]
class RawInputUtils {
    static func rawEnter(): Unit {
        unsafe { enterRaw() }
    }

    static func rawExit(): Unit {
        unsafe { exitRaw() }
    }

    static func rawGetRune(): Option<Rune> {
        var buffer: VArray<Byte, $4> = [0, 0, 0, 0]
        let len = unsafe { getRawUtf8(inout buffer) }
        if (len == 0) { // WHEN UNKNOWN ASCII
            return rawGetRune()
        }
        let bytes = [buffer[0], buffer[1], buffer[2], buffer[3]]
        // Convert to a rune
        let (r, size) = Rune.fromUtf8(bytes, 0)
        // Assert
        if (size != Int64(len)) {
            throw Exception("Read bytes(${len}) != Expected bytes(${size})")
        }
        return r
    }

    static func checkReadByte(bytes: Array<Byte>, infinite!: Bool = false): Bool {
        var keyCode: UInt16 = 0
        let waitTimeMs: UInt32
        if (infinite) {
            waitTimeMs = 0
        } else {
            waitTimeMs = 50
        }
        let len = unsafe { getByte(waitTimeMs, inout keyCode) }
        if (len == 1 && bytes.contains(UInt8(keyCode))) { // ASCII
            return true
        }
        return false
    }
}