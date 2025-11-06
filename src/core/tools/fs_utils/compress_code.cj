package cli.core.tools.fs_utils

import memory_management.user_end.code.*

import cli.core.config.CliConfig
import cli.core.model.ModelTokenLimits
import cli.core.model.CliModelManager

protected func compressCode(filePath: String, startLine!: Int = 1, endLine!: Int = Int.Max): String {
    let cmm = CodeMemoryManagement("", "")
    var content = cmm.analyzeFile(filePath, startLine: startLine, endLine: endLine)
    content = """
The returned code is too large to return in full. Instead, you will receive a compressed index of code entities (functions, classes, structs, enums, etc.). The index contains: the signature of each entity, its hierarchical structure (e.g., a method inside a class), and its location (start and end line numbers). The following are the compressed index of code entities:

```
${content}
```

To get the full code for an entity, you can read the source file from the provided start line to end line, and expand the range slightly to include surrounding context, such as comments, annotations, or preprocessor directives, which may be crucial.
"""
    return content
}

protected func getCompressionThreshold(batchRead: Bool): Int {
    let modelTokenLimit = ModelTokenLimits.getContextLimit(
        (CliModelManager.lastAvailableModel ?? CliModelManager.model).fullName
    )
    let compressionThreshold = if (batchRead) {
        CliConfig.batchReadFilesThreshold
    } else {
        CliConfig.readFileThreshold
    }
    Int64(compressionThreshold * Float64(modelTokenLimit) * 4.0) // each token has about 4 characters on average
}
