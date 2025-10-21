import std.process.*
import std.fs.*
import std.env.exit

@When[os == "Linux"]
const OS = "linux"

@When[os == "Windows"]
const OS = "windows"

@When[os == "macOS"]
const OS = "mac"

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
        case "mac" =>
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
        case "linux"|"mac" => "${ffiDir}/raw_input_linux.c"
        case "windows" => "${ffiDir}/raw_input_win.c"
        case _ => throw UnsupportedException("Unreachable")
    }
    let libFile = if (staticLib) {
        match(OS) {
            case "linux" | "mac" => "${ffiDir}/librawinput.a"
            case "windows" => "${ffiDir}/librawinput.lib"
            case _ => throw UnsupportedException("Unreachable")
        }
    } else {
         match(OS) {
            case "linux" => "${ffiDir}/librawinput.so"
            case "windows" => "${ffiDir}/librawinput.dll"
            case "mac" => "${ffiDir}/librawinput.dylib"
            case _ => throw UnsupportedException("Unreachable")
        }
    }

    if (!exists(libFile) ||
        FileInfo(libFile).lastModificationTime < FileInfo(sourceFile).lastModificationTime) {
        let status = if (staticLib) {
            compileStaticLib(sourceFile, libFile)
        } else {
            compileDynamicLib(sourceFile, libFile)
        }
        return if (status) { 0 } else { 1 }
    }
    return 0
}

func getEnvOrExit(key: String): String {
    match (Process.current.getEnv(key)) {
        case Some(value) => value
        case None =>
            eprintln("${key} not set")
            exit(1)
    }
}

func checkStdx(): Bool {
    let version = "1.0.0.1"
    let magicDir = getEnvOrExit("MAGIC_PATH")
    let stdxDir = "${magicDir}/libs/cangjie-stdx-${OS}-${ARCH}-${version}"
    println("stdxDir: ${stdxDir}")
    return exists(stdxDir)
}

func downloadStdx(): Int64 {
    // Build CangjieMagic to download stdx
    let magicDir = getEnvOrExit("MAGIC_PATH")
    let proc = launch("cjpm", ["build"], workingDirectory: Path(magicDir))
    return proc.wait()
}

func stagePreBuild(): Int64 {
    if (OS == "unknown" || ARCH == "unknown") {
        println("Unsupported os or Arch")
        return 1
    }
    if (!checkStdx()) {
        println("stdx not found, try to download")
        let status = downloadStdx()
        if (status != 0) {
            println("Download stdx failed")
            return status
        }
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
