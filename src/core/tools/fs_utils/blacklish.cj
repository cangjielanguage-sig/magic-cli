package cli.core.tools.fs_utils

import std.fs.Path

// Predefined black-list of directories
let IGNORED_DIR = [".git", ".cache", "node_modules", "bower_components", "build", "target"]

protected func ignored(path: Path): Bool {
    return path.fileName.startsWith(".") || IGNORED_DIR.contains(path.fileName)
}