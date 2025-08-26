package cli.utils

import std.collection.*
import std.fs.*
import cli.core.config.CliConfig
import std.sort.sort


protected func listCmds(prefix!: String = ""): Array<String> {
    let cmdArray = CMDS
    sort(cmdArray, stable: true)
    return cmdArray |> filter {str => str.startsWith(prefix) && str != prefix} |> collectArray
}

protected func listFiles(workDir!: Path = CliConfig.cwd, prefix!: String = ""): Array<String> {
    let fileLst = ArrayList<String>()
    doListFiles(workDir, fileLst)
    let arr = fileLst.toArray()
    sort(arr, stable: true)
    return arr |> filter {str => str.startsWith(prefix) && str != prefix} |> collectArray
}

private func doListFiles(workDir: Path, lst: ArrayList<String>): Bool {
    Directory.walk(workDir) {
        fileInfo: FileInfo => if (fileInfo.isDirectory()) {
            lst.add(fileInfo.path.normalize().toString())
            return doListFiles(fileInfo.path, lst)
        } else {
            lst.add(fileInfo.path.normalize().toString())
            return true
        }
    }
    return true
}
