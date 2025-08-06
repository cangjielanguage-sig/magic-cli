package cli.core.prompts

import std.fs.*
import std.collection.HashMap
import cli.core.tools.*

public class Prompt {
    public static func get(path: String): String {
        return FSTool.load(path)
    }
}