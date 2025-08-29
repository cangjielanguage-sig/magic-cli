package cli.utils

import std.collection.*
import std.fs.*
import cli.core.config.CliConfig
import std.sort.sort

protected func toUnixStyle(pathStr: String, appendSuffix!: Bool = false) {
    if (appendSuffix) {
        var res = pathStr.replace("\\", "/")
        if (!res.endsWith("/")) {
            res = res + "/"
        }
        res
    } else {
        pathStr.replace("\\", "/")
    }
}

protected func listFiles(workDir!: Path = CliConfig.cwd, prefix!: String = ""): Array<String> {
    var workSpace = try {
        workDir.join(prefix)
    } catch (e: FSException) { // Illegal path
        return []
    }
    let basePath = toUnixStyle(workDir.normalize().toString(), appendSuffix: true)
    let fi = if(exists(workSpace)) {
        FileInfo(workSpace)
    } else if (exists(workSpace.parent)) { // Incomplete path input 
        FileInfo(workSpace.parent)
    } else {
        return []
    }
    if (!fi.isDirectory()) {
        return []
    }
    let fileLst = ArrayList<String>()
    Directory.walk(fi.path) {
        fileInfo: FileInfo =>
        var path = fileInfo.path.normalize().toString()
        path = toUnixStyle(path).replace(basePath, "")
        if (!path.startsWith(prefix) || path.startsWith('.')) {
            return true
        }
        if (fileInfo.isDirectory()) {
            fileLst.add(path + "/")
        } else {
            fileLst.add(path)
        }
        true
    }
    let arr = fileLst.toArray()
    sort(
        arr,
        by: {
            path1: String, path2: String =>
            var p1 = path1
            var p2 = path2
            if (p1.endsWith('/')) {
                p1 = '\0' + p1
            }
            if (p2.endsWith('/')) {
                p2 = '\0' + p2
            }
            if (p1 > p2) {
                return Ordering.GT
            } else if (p1 == p2) {
                return Ordering.EQ
            } else {
                return Ordering.LT
            }
        },
        stable: true
    )
    arr
}
