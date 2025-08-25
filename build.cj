import std.process.*
import std.fs.*

func getOsInfo() {
    @When[os == "Linux"]
    let os = "linux"

    @When[os == "Windows"]
    let os = "windows"

    @When[os == "macOS"]
    let os = "macos"

    @When[os != "Linux" && os != "Windows" && os != "macOS"]
    let os = "unknown"

    @When[arch == "aarch64"]
    let arch = "aarch64"

    @When[arch == "x86_64"]
    let arch = "x64"

    @When[arch != "x86_64" && arch != "aarch64"]
    let arch = "unknown"

    return (os, arch)
}

func compile(os: String, sourceFile: String, libFile: String): Bool {
    let objectFile = sourceFile.replace(".c", ".o")
    if (launch("gcc", ["-c", "-fPIC", sourceFile, "-o", objectFile]).wait() != 0) {
        println("Building object file failed")
        return false
    }

    let buildProc = match (os) {
        case "linux" | "windows"=>
            launch("gcc", ["-shared", "-o", libFile, objectFile])
        case "macos" =>
            launch("gcc", ["-dynamiclib", "-o", libFile, objectFile])
        case _ =>
            throw UnsupportedException("Unreachable")
    }
    if (buildProc.wait() != 0) {
        println("Building shared lib failed")
        return false
    }
    remove(objectFile)
    return true
}

func buildFFI(os: String, arch: String): Int64 {
    let ffiDir = "./ffi"
    let sourceFile = match(os) {
        case "linux"|"macos" => "${ffiDir}/raw_input_linux.c"
        case "windows" => "${ffiDir}/raw_input_win.c"
        case _ => throw UnsupportedException("Unreachable")
    }
    let libFile = match(os) {
        case "linux" => "${ffiDir}/librawinput.so"
        case "windows" => "${ffiDir}/librawinput.dll"
        case "macos" => "${ffiDir}/librawinput.dylib"
        case _ => throw UnsupportedException("Unreachable")
    }

    if (!exists(libFile)) {
        let status = compile(os, sourceFile, libFile)
        if (!status) {
            return 1
        } else {
            return 0
        }
    }
    return 0
}

func stagePreBuild(): Int64 {
    let (os, arch) = getOsInfo()

    if (os == "unknown" || arch == "unknown") {
        println("Unsupported os or Arch")
        return 1
    }

    println("OS: ${os}, ARCH: ${arch}")
    return buildFFI(os, arch)
}

main(): Int64 {
    match (Process.current.arguments[0]) {
        case "pre-build" => stagePreBuild()
        case _ => 0
    }
}