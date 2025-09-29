import std.process.*
import std.fs.*

@When[os == "Linux"]
const OS = "linux"

@When[os == "Windows"]
const OS = "windows"

@When[os == "macOS"]
const OS = "macos"

@When[os != "Linux" && os != "Windows" && os != "macOS"]
const OS = "unknown"

@When[arch == "aarch64"]
const ARCH = "aarch64"

@When[arch == "x86_64"]
const ARCH = "x64"

@When[arch != "x86_64" && arch != "aarch64"]
const ARCH = "unknown"

func checkStaticLinking(): Bool {
    try {
        let toml = String.fromUtf8(File.readFrom("./cjpm.toml"))
        return toml.contains("--static-libs")
    } catch (e: FSException) {
        println("Failed to read cjpm.toml: ${e.message}")
        return false
    }
}

func compileStaticLib(sourceFile: String, libFile: String): Bool {
    let objectFile = sourceFile.replace(".c", ".o")
    if (launch("gcc", ["-c", "-Wall", "-Werror", sourceFile, "-o", objectFile]).wait() != 0) {
        println("Building object file failed")
        return false
    }

    let buildProc = launch("ar", ["rcs", libFile, objectFile])
    if (buildProc.wait() != 0) {
        println("Building shared lib failed")
        return false
    }
    remove(objectFile)
    return true
}

func compileDynamicLib(sourceFile: String, libFile: String): Bool {
    let objectFile = sourceFile.replace(".c", ".o")
    if (launch("gcc", ["-c", "-Wall", "-Werror", "-fPIC", sourceFile, "-o", objectFile]).wait() != 0) {
        println("Building object file failed")
        return false
    }

    let buildProc = match (OS) {
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

func buildFFI(staticLib: Bool): Int64 {
    let ffiDir = "./ffi"
    let sourceFile = match(OS) {
        case "linux"|"macos" => "${ffiDir}/raw_input_linux.c"
        case "windows" => "${ffiDir}/raw_input_win.c"
        case _ => throw UnsupportedException("Unreachable")
    }
    let libFile = if (staticLib) {
        match(OS) {
            case "linux" | "macos" => "${ffiDir}/librawinput.a"
            case "windows" => "${ffiDir}/librawinput.lib"
            case _ => throw UnsupportedException("Unreachable")
        }
    } else {
         match(OS) {
            case "linux" => "${ffiDir}/librawinput.so"
            case "windows" => "${ffiDir}/librawinput.dll"
            case "macos" => "${ffiDir}/librawinput.dylib"
            case _ => throw UnsupportedException("Unreachable")
        }
    }

    if (!exists(libFile)) {
        let status = if (staticLib) {
            compileStaticLib(sourceFile, libFile)
        } else {
            compileDynamicLib(sourceFile, libFile)
        }
        return if (status) { 0 } else { 1 }
    }
    return 0
}

func stagePreBuild(): Int64 {
    if (OS == "unknown" || ARCH == "unknown") {
        println("Unsupported os or Arch")
        return 1
    }
    let staticLib = checkStaticLinking()
    println("OS: ${OS}, ARCH: ${ARCH}, Static Link: ${staticLib}")
    return buildFFI(staticLib)
}

main(): Int64 {
    match (Process.current.arguments[0]) {
        case "pre-build" => stagePreBuild()
        case _ => 0
    }
}
