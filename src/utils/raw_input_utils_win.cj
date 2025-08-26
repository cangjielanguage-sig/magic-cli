package cli.utils

import std.collection.{ArrayList, HashMap}

@When[os == "Windows"]
foreign {
    func enterRaw(): IntNative

    func getRawUtf8(bytes: CPointer<Byte>): IntNative

    func exitRaw(): Unit
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
}