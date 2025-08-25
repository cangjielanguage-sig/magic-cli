package cli.utils

import std.collection.*

public func listFiles(workDir: String, prefix!: String = ""): Array<String> {
    let arr = ['workdir', 'workdir/a', 'workdir/a/main.cj', 'workdir/a/test.cj', 'workdir/a/dest.cj', 'workdir/b',
        'workdir/b/main.cj', 'workdir/b/test.cj', 'workdir/b/dest.cj', 'workdir/c', 'workdir/c/main.cj',
        'workdir/c/test.cj', 'workdir/c/dest.cj', 'workdir/d', 'workdir/d/main.cj', 'workdir/d/test.cj',
        'workdir/d/dest.cj']
    if (prefix == String.empty) {
        return arr
    }
    return arr |> filter {str => str.startsWith(prefix) && str != prefix} |>  collectArray
}
